utils::globalVariables(c(
  "taxon_name", "taxon_name_rank", "grid_id", "main_habitat",
  "undetected_type", "alpha", "beta", "prior_mean", "prior_alpha", "prior_beta",
  "genus", "family", "family.fill", "dark_alpha", "dark_beta",
  "singleton_alpha", "singleton_beta",
  "source_taxon_name", "theta_s",
  "group_prior_alpha", "group_prior_beta",
  "dark_diversity_group", "n_singletons_group", "n_undetected_group",
  ".ha_theta_mean"
))

# ==============================================================================
# Internal helper: coarse-rank expansion
# ==============================================================================

# .expand_coarse_rank_rows()
#
# For each row in `result` where the primary taxon_name join failed (alpha = NA)
# AND the row's taxon_name_rank is a rank coarser than the finest rank in
# rank_system (e.g. a family-rank or genus-rank hypothesis), find all species
# in taxaexpect_priors that:
#   (a) belong to that coarser taxon (via expansion_taxonomy),
#   (b) have a modelled prior (non-NA alpha) at the same grid_id x main_habitat.
#
# The candidate species are filtered using the same logic as posterior_consensus():
#   1. Normalize prior_mean within the candidate set.
#   2. Drop species with normalized_prior < expansion_min_prior.
#   3. Keep the fewest top species whose cumulative normalized_prior >=
#      expansion_cumulative_prior.
#
# Each retained species replaces the original coarse-rank row. All likelihood
# columns (observation_id, score_likelihood, etc.) are inherited from the
# template row. Score normalization inside compute_posterior() makes the
# inherited score_likelihood magnitude irrelevant -- only relative values matter,
# so uniform inheritance is correct.
#
# Returns `result` unchanged when:
#   - expansion_taxonomy is NULL or lacks coarser-rank columns
#   - no coarse-rank rows are present
#   - no matching species are found in taxaexpect_priors for a given constraint
#     (those rows remain for the dark diversity fallback downstream)
#' @noRd
.expand_coarse_rank_rows <- function(result,
                                     taxaexpect_priors,
                                     expansion_taxonomy,
                                     rank_system,
                                     expansion_min_prior,
                                     expansion_cumulative_prior) {
  if (is.null(expansion_taxonomy) || !is.data.frame(expansion_taxonomy)) {
    return(result)
  }
  if (!"taxon_name" %in% names(expansion_taxonomy)) {
    return(result)
  }

  finest_rank <- rank_system[length(rank_system)]

  # Ranks coarser than finest that exist as columns in expansion_taxonomy.
  # Only these can be used to match species to a coarse constraint.
  coarser_ranks <- intersect(rank_system[-length(rank_system)], names(expansion_taxonomy))
  if (length(coarser_ranks) == 0L) {
    cli::cli_inform(
      "join_priors: expansion_taxonomy lacks coarser-rank columns ({paste(rank_system[-length(rank_system)], collapse=', ')}); coarse-rank expansion skipped."
    )
    return(result)
  }

  # Rows eligible for expansion: failed primary join + coarser rank + named taxon.
  # Exclude H2/H3 unreferenced-hypothesis rows -- their coarse taxon_name_rank reflects
  # the best-available match level, not a coarse identification. Expanding them would
  # replace one generic placeholder with all modelled species in that family/genus,
  # flooding compute_posterior() with spurious competitors and diluting H1 posteriors
  # for legitimate species (e.g. common intertidal fish resolving to family instead of
  # species because all Cottidae species are added as new rows).
  is_coarse <- is.na(result$alpha) &
    !is.na(result$taxon_name_rank) &
    result$taxon_name_rank %in% coarser_ranks &
    !is.na(result$taxon_name) &
    (!("hypothesis_type" %in% names(result)) |
      !.is_complement_type(result$hypothesis_type))

  if (!any(is_coarse)) {
    return(result)
  }

  # Species-level rows from taxaexpect_priors: modelled (non-NA alpha), site-resolved.
  sp_bare <- taxaexpect_priors[
    !is.na(taxaexpect_priors$taxon_name) &
      !is.na(taxaexpect_priors$alpha) &
      !is.na(taxaexpect_priors$grid_id) &
      !is.na(taxaexpect_priors$main_habitat), ,
    drop = FALSE
  ]
  if (nrow(sp_bare) == 0L) {
    return(result)
  }

  # Join coarser-rank columns from expansion_taxonomy onto sp_bare.
  # We merge only the taxonomy columns to avoid importing redundant priors columns.
  tax_extra <- setdiff(names(expansion_taxonomy), "taxon_name")
  sp_priors <- merge(
    sp_bare,
    expansion_taxonomy[, c("taxon_name", tax_extra), drop = FALSE],
    by = "taxon_name", all.x = TRUE
  )

  # Columns to override in template rows with species-level values.
  # Likelihood-side columns are always inherited from the template (this is
  # implicit in how override_cols below is used, not a separate keep-list --
  # a `template_keep_cols` variable enumerating them was found unused, dead
  # code from an earlier draft, and removed during code review).
  override_cols <- intersect(
    names(sp_priors),
    # model_tier/observed_in_habitat carried so the modelled-species floor
    # promotion downstream sees each expanded row's own provenance (an
    # evidence_blend/tier_domestic_food row must never be promoted; a
    # modelled row is promotable only on a real habitat mismatch) instead of
    # the template coarse row's NA values.
    c(
      "taxon_name", "taxon_name_rank", "alpha", "beta", "undetected_type",
      "model_tier", "observed_in_habitat",
      # branch label + effective evidence travel with expanded rows;
      # prior_branch also gates the promotion below.
      "prior_branch", "effective_records",
      # presence-mixture columns: expanded evidence rows keep their own
      # mixture so compute_posterior()'s presence-draw sampler sees it
      "prior_mix_w", "prior_mix_theta_present", "prior_mix_theta_absent",
      "prior_mix_p_conc", tax_extra
    )
  )

  # Build expansion map: unique (crank | cvalue | grid | hab) -> filtered species df
  .sep <- "|||"
  coarse_rows <- result[is_coarse, , drop = FALSE]
  combo_keys <- paste(coarse_rows$taxon_name_rank, coarse_rows$taxon_name,
    coarse_rows$grid_id, coarse_rows$main_habitat,
    sep = .sep
  )
  unique_keys <- unique(combo_keys)

  expansion_map <- vector("list", length(unique_keys))
  names(expansion_map) <- unique_keys
  n_expanded_combos <- 0L
  n_fallback_combos <- 0L

  for (key in unique_keys) {
    parts <- strsplit(key, .sep, fixed = TRUE)[[1L]]
    crank <- parts[1L]
    cvalue <- parts[2L]
    cgrid <- parts[3L]
    chab <- parts[4L]

    if (!crank %in% names(sp_priors)) {
      n_fallback_combos <- n_fallback_combos + 1L
      next
    }

    cands <- sp_priors[
      !is.na(sp_priors[[crank]]) &
        sp_priors[[crank]] == cvalue &
        sp_priors$grid_id == cgrid &
        sp_priors$main_habitat == chab, ,
      drop = FALSE
    ]

    if (nrow(cands) == 0L) {
      n_fallback_combos <- n_fallback_combos + 1L
      next
    }

    # Compute normalized prior within candidate set
    sp_pm <- cands$alpha / (cands$alpha + cands$beta)
    total <- sum(sp_pm, na.rm = TRUE)
    if (!is.finite(total) || total == 0) {
      n_fallback_combos <- n_fallback_combos + 1L
      next
    }
    norm_pm <- sp_pm / total

    # Floor filter (expansion_min_prior)
    keep <- !is.na(norm_pm) & norm_pm >= expansion_min_prior
    if (!any(keep)) {
      n_fallback_combos <- n_fallback_combos + 1L
      next
    }
    cands <- cands[keep, , drop = FALSE]
    norm_pm <- norm_pm[keep]

    # Cumulative threshold (expansion_cumulative_prior): fewest top species
    ord <- order(norm_pm, decreasing = TRUE)
    cands <- cands[ord, , drop = FALSE]
    norm_pm <- norm_pm[ord]
    keep_n <- which(cumsum(norm_pm) >= expansion_cumulative_prior)[1L]
    if (is.na(keep_n)) keep_n <- nrow(cands)
    cands <- cands[seq_len(keep_n), , drop = FALSE]

    expansion_map[[key]] <- cands
    n_expanded_combos <- n_expanded_combos + 1L
  }

  if (n_expanded_combos == 0L) {
    return(result)
  }

  # Replace coarse-rank rows with species-level rows
  coarse_idx <- which(is_coarse)
  drop_idx <- integer(0)
  new_rows_l <- vector("list", length(coarse_idx) * 15L)
  nr_k <- 0L

  for (ii in seq_along(coarse_idx)) {
    i <- coarse_idx[ii]
    key <- combo_keys[ii]

    cands_sp <- expansion_map[[key]]
    # No expansion found for this coarse-rank taxon -- leave it as-is; the
    # dark-diversity fallback (main function body, below) assigns it a floor
    # prior downstream, same as any other unmodelled candidate.
    if (is.null(cands_sp)) next

    template <- result[i, , drop = FALSE]

    for (j in seq_len(nrow(cands_sp))) {
      nr <- template
      for (col in override_cols) {
        if (col %in% names(nr)) {
          nr[[col]] <- cands_sp[[col]][j]
        } else {
          nr[[col]] <- cands_sp[[col]][j]
        }
      }
      # Ensure finest rank regardless of whether taxon_name_rank was in override_cols
      nr$taxon_name_rank <- finest_rank
      nr$hypothesis_type <- "rank_expanded"
      nr_k <- nr_k + 1L
      new_rows_l[[nr_k]] <- nr
    }
    drop_idx <- c(drop_idx, i)
  }

  if (length(drop_idx) == 0L || nr_k == 0L) {
    return(result)
  }

  new_rows <- dplyr::bind_rows(new_rows_l[seq_len(nr_k)])
  result <- dplyr::bind_rows(result[-drop_idx, , drop = FALSE], new_rows)

  cli::cli_inform(c(
    "join_priors: expanded {length(unique(drop_idx))} coarse-rank row(s) into {nrow(new_rows)} species-level hypothesis row(s).",
    if (n_fallback_combos > 0L) {
      "i" <- "{n_fallback_combos} coarse-rank constraint(s) had no matching species in taxaexpect_priors; dark diversity floor applied."
    }
  ))

  result
}

# ==============================================================================
# Internal helper: hierarchical dark diversity group priors
# ==============================================================================

# .compute_dark_diversity_groups()
#
# Per-clade dark-diversity budget for unmodelled candidates (no occurrence
# record). For each clade X (phylum .. genus): f1 = its singletons, D = their
# mean share (the share one missing species would hold if present), K = its
# unrecorded candidates, W = evidence weight already priced by other
# generators. The expected number of missing species is shrunk toward the
# parent's: N* = (f1 + kappa * Nhat) / (1 + kappa), Nhat = parent N* times the
# clade's share of the parent's candidates. Each candidate gets
# min(1, (N* - W) / K) * D at its finest known clade: the clade's unseen mass
# shared among its candidates, never more than one species' share. The
# remainder (missing species no candidate accounts for) is returned in
# attr(, "dark_budget") for the unsequenced-relative ring rows: at genus
# N* - K - W, at a coarser rank N* minus its child clades' N*.
#
# Returns: unref_df with group_prior_alpha, group_prior_beta,
#   dark_diversity_group, n_singletons_group, n_undetected_group, and
#   attr "dark_budget" (rank, clade, f1, N, K, W, D, remainder).
#' @noRd
.compute_dark_diversity_groups <- function(unref_df,
                                           singleton_df,
                                           global_singleton_mean,
                                           singleton_ess = 2L,
                                           evidence_df = NULL,
                                           kappa = 1) {
  tax_ranks <- c("phylum", "class", "order", "family", "genus")
  n <- nrow(unref_df)
  for (col in tax_ranks) {
    if (col %in% names(unref_df)) unref_df[[col]] <- dplyr::na_if(as.character(unref_df[[col]]), "")
    if (col %in% names(singleton_df)) singleton_df[[col]] <- dplyr::na_if(as.character(singleton_df[[col]]), "")
    if (!is.null(evidence_df) && col %in% names(evidence_df)) evidence_df[[col]] <- dplyr::na_if(as.character(evidence_df[[col]]), "")
  }
  ranks <- tax_ranks[tax_ranks %in% names(unref_df) & tax_ranks %in% names(singleton_df)]
  gsm <- global_singleton_mean
  if (!is.finite(gsm) || gsm <= 0) gsm <- 1 / (n + 1)
  singleton_df$theta_s <- singleton_df$alpha / (singleton_df$alpha + singleton_df$beta)

  # ---- per-clade budget, top-down --------------------------------------------
  # f1 = singletons in the clade, D = their mean share (one missing species'
  # share if present), K = unrecorded candidates, W = evidence weight already
  # priced elsewhere. N* = (f1 + kappa * Nhat) / (1 + kappa), Nhat = the
  # parent's N* apportioned by the clade's share of the parent's candidates.
  key <- function(r, v) paste(r, v, sep = "\r")
  root <- list(N = nrow(singleton_df), D = gsm, K = n)
  bud <- data.frame(rank = "ROOT", clade = "ROOT", key = "ROOT", f1 = root$N, D = root$D,
    K = root$K, W = 0, N = root$N, stringsAsFactors = FALSE)
  for (ri in seq_along(ranks)) {
    r <- ranks[ri]
    cl <- unique(c(unref_df[[r]], singleton_df[[r]]))
    cl <- cl[!is.na(cl)]
    if (!length(cl)) next
    rows <- lapply(cl, function(v) {
      s_in <- !is.na(singleton_df[[r]]) & singleton_df[[r]] == v
      c_in <- !is.na(unref_df[[r]]) & unref_df[[r]] == v
      par <- if (ri == 1L) "ROOT" else {
        pv <- unique(c(unref_df[[ranks[ri - 1L]]][c_in], singleton_df[[ranks[ri - 1L]]][s_in]))
        pv <- pv[!is.na(pv)]
        if (length(pv)) key(ranks[ri - 1L], pv[1]) else "ROOT"
      }
      w_in <- if (!is.null(evidence_df) && r %in% names(evidence_df)) {
        sum(evidence_df$w[!is.na(evidence_df[[r]]) & evidence_df[[r]] == v], na.rm = TRUE)
      } else 0
      data.frame(rank = r, clade = v, key = key(r, v), parent = par, f1 = sum(s_in),
        Dself = if (any(s_in)) mean(singleton_df$theta_s[s_in], na.rm = TRUE) else NA_real_,
        K = sum(c_in), W = w_in, stringsAsFactors = FALSE)
    })
    rr <- do.call(rbind, rows)
    pidx <- match(rr$parent, bud$key)
    pN <- bud$N[pidx]; pK <- bud$K[pidx]; pD <- bud$D[pidx]
    pN[is.na(pN)] <- root$N; pK[is.na(pK)] <- root$K; pD[is.na(pD)] <- root$D
    Nhat <- ifelse(pK > 0, pN * rr$K / pK, 0)
    rr$N <- (rr$f1 + kappa * Nhat) / (1 + kappa)
    rr$D <- ifelse(is.na(rr$Dself) | !is.finite(rr$Dself), pD, rr$Dself)
    bud <- rbind(bud, rr[, c("rank", "clade", "key", "f1", "D", "K", "W", "N")])
  }

  # ---- candidate priors: min(1, (N* - W) / K) * D at the finest known clade --
  g_alpha <- rep(NA_real_, n); g_beta <- rep(NA_real_, n)
  g_label <- rep(NA_character_, n); g_ns <- rep(0L, n); g_nu <- rep(0L, n)
  for (i in seq_len(n)) {
    fin <- NA_character_
    for (r in rev(ranks)) {
      v <- unref_df[[r]][i]
      if (!is.na(v)) { fin <- key(r, v); break }
    }
    if (is.na(fin)) { g_label[i] <- "no_phylum"; next }
    b <- bud[bud$key == fin, , drop = FALSE][1, ]
    w <- if (b$K > 0) min(1, max(b$N - b$W, 0) / b$K) else 0
    pm <- min(max(w * b$D, 1e-12), 1 - 1e-9)
    phi <- max(1, b$N) * singleton_ess
    g_alpha[i] <- pm * phi; g_beta[i] <- (1 - pm) * phi
    g_label[i] <- sub("\r", ":", fin); g_ns[i] <- as.integer(b$f1); g_nu[i] <- as.integer(b$K)
  }
  unref_df$group_prior_alpha <- g_alpha
  unref_df$group_prior_beta <- g_beta
  unref_df$dark_diversity_group <- g_label
  unref_df$n_singletons_group <- g_ns
  unref_df$n_undetected_group <- g_nu

  # ---- remainder for ring rows -------------------------------------------------
  # Missing species no named candidate accounts for. At genus: N* - K - W. At a
  # coarser rank: the clade's N* not carried by its child clades (unsequenced
  # lower clades), so nothing is counted twice.
  bud$child_N <- vapply(bud$key, function(k) {
    r <- bud$rank[bud$key == k][1]
    ri <- match(r, ranks)
    if (is.na(ri) || ri == length(ranks)) return(0)
    v <- bud$clade[bud$key == k][1]
    ch <- unique(c(unref_df[[ranks[ri + 1L]]][!is.na(unref_df[[r]]) & unref_df[[r]] == v],
      singleton_df[[ranks[ri + 1L]]][!is.na(singleton_df[[r]]) & singleton_df[[r]] == v]))
    ch <- ch[!is.na(ch)]
    sum(bud$N[bud$key %in% key(ranks[ri + 1L], ch)])
  }, numeric(1))
  bud$remainder <- ifelse(bud$rank == "genus",
    pmax(bud$N - bud$K - bud$W, 0),
    pmax(bud$N - bud$child_N, 0)) * bud$D
  attr(unref_df, "dark_budget") <- bud[bud$rank != "ROOT", c("rank", "clade", "f1", "N", "K", "W", "D", "remainder")]
  unref_df
}

#' Join Likelihoods to TaxaExpect Priors
#'
#' Bridges the gap between TaxaLikely likelihoods and
#' [compute_posterior()]: maps each `observation_id` to a site, joins
#' occurrence-based priors from TaxaExpect, applies a dark diversity
#' fallback for species with no modelled prior, deduplicates, fills
#' missing taxonomy columns, and removes redundant higher-rank
#' hypotheses.
#'
#' ## Site specification
#' The `site` argument accepts two forms:
#' \describe{
#'   \item{Named list (single-site)}{All observations are assigned the same
#'     `grid_id` and `main_habitat`. This is the most common case.
#'     Example: `list(grid_id = "Grid_34p1_m119p1",
#'     main_habitat = "Estuarine Bay")`.}
#'   \item{Data frame (multi-site)}{One row per `observation_id` with
#'     columns `observation_id`, `grid_id`, `main_habitat`. Use when
#'     observations come from different locations.}
#' }
#'
#' ## Dark diversity fallback
#' Dark diversity is the set of species that belong to the regional species
#' pool and could inhabit a site, but have not been observed there. Species
#' with no TaxaExpect prior (e.g., referenced species not expected at the
#' site) receive a dark diversity prior: the mean `alpha` and `beta` from Tier
#' 3 (undetected) rows in `taxaexpect_priors` for the same `grid_id` x
#' `main_habitat`, or, if no site-level Tier 3 rows exist, a global average
#' across all Tier 3 rows. Every hypothesis therefore has a non-zero prior.
#'
#' ## Habitat-agnostic named-species prior fallback
#' A named prior row can legitimately have no habitat concept at all --
#' `TaxaExpect::generate_domestic_food_priors()`'s output is the example (a
#' food/domestic species' plausibility is governed by human food supply, not
#' local habitat suitability, so `main_habitat = NA` there is intentional, not
#' a missing value to fill in). The primary composite-key join requires an
#' exact `main_habitat` match, so such a row could never match on its own.
#' This function therefore re-matches any row whose primary join failed on
#' `(taxon_name, taxon_name_rank, grid_id)` alone against habitat-agnostic
#' (`main_habitat = NA`) `taxaexpect_priors` rows, ranked below a real
#' per-habitat match but above the dark-diversity/global-floor fallback.
#' Without it, a domestic-food prior row would silently fall back to the
#' generic floor instead of the tailored prior.
#'
#' **Domestic/synanthropic species caveat:** the floor assumes unmodelled
#' species are exchangeable draws from one detection process. Domestic and
#' synanthropic species (pets, livestock) violate this systematically, since
#' GBIF/iNaturalist under-index captive organisms; see
#' `TaxaExpect::generate_undetected_diversity()`'s Domestic/synanthropic
#' species section for the recommended fix (augment your occurrence data
#' before training, rather than relying on this floor).
#' `TaxaFlag::add_posthoc_assessment(domestic_taxa = ...)` can flag the
#' resulting low-prior-vs-strong-likelihood contrast downstream for review.
#'
#' ## Deduplication and redundancy filtering
#' After the join, rows are deduplicated on `observation_id` x
#' `taxon_name` x `taxon_name_rank` x `grid_id` x `main_habitat`
#' (keeping the highest `prior_mean` among same-site duplicates --
#' e.g. artifacts of coarse-rank expansion). The `grid_id`/`main_habitat`
#' keys mean a genuine multi-site observation (the same
#' `observation_id` detected at more than one site) keeps one row per site
#' per candidate rather than collapsing to a single site. Pass the result
#' through [combine_multisite_priors()] before [compute_posterior()] to
#' combine each candidate's per-site rows into one. Genus-rank rows with
#' missing taxonomy are filled from `taxon_name` and propagated from other
#' rows sharing the same genus. Finally,
#' [TaxaMatch::filter_redundant_hypotheses()] removes coarser-rank rows
#' superseded by finer-rank rows in the same lineage. Unreferenced hypotheses
#' (`hypothesis_type` `unreferenced_*` or `unresolved_species`) are never
#' removed by that step: an unsequenced species of a candidate's genus
#' competes with the candidate rather than being a coarser label for it.
#'
#' @param likelihoods Data frame of likelihoods, typically from
#'   [TaxaLikely::apply_coverage_constraints()] or
#'   [TaxaLikely::expand_unreferenced_hypotheses()]. Must contain
#'   `observation_id`, `taxon_name`, `taxon_name_rank`.
#' @param taxaexpect_priors Data frame of TaxaExpect priors. One row
#'   per `taxon_name` x `grid_id` x `main_habitat`, with columns
#'   `alpha`, `beta`, `undetected_type`, and taxonomy columns
#'   (`genus`, `family`, etc.).
#' @param site Site specification including habitat. \code{main_habitat}
#'   is always required -- the function does not guess which habitat your
#'   observations came from. Accepted formats:
#'   \describe{
#'     \item{Named list with lat/lon}{\code{list(lat = 34.1, lon = -119.1,
#'       main_habitat = "Marine")} -- auto-resolves to nearest grid_id.}
#'     \item{Named list with grid_id}{\code{list(grid_id = "...",
#'       main_habitat = "Marine")}}
#'     \item{Data frame (multi-site)}{Columns \code{observation_id},
#'       \code{grid_id}, \code{main_habitat}. Or \code{observation_id},
#'       \code{lat}, \code{lon}, \code{main_habitat}.}
#'   }
#'   If \code{main_habitat} is omitted, the error message lists available
#'   habitats and row counts at the resolved grid cell.
#'   \code{list(main_habitat = "Marine")} alone (no \code{lat}/\code{lon}/
#'   \code{grid_id}) auto-fills coordinates from
#'   \code{attr(taxaexpect_priors, "search_center")} when present
#'   (\code{estimate_kernel_priors()}'s own output does not set this
#'   attribute) -- \code{main_habitat} itself is never auto-filled or
#'   guessed.
#'   See Details.
#' @param taxonomy_lookup Optional data frame mapping `taxon_name` to
#'   taxonomy columns (e.g. `genus`, `family`). Used to fill taxonomy
#'   for species that have likelihoods but are absent from
#'   `taxaexpect_priors`. Typically built from `match_df` columns.
#'   Default `NULL` (no external taxonomy fill).
#' @param rank_system Character vector of taxonomic ranks from
#'   coarsest to finest. Passed to
#'   [TaxaMatch::filter_redundant_hypotheses()]. Default `NULL`
#'   auto-detects from columns in `likelihoods`.
#' @param expansion_taxonomy Optional data frame mapping species names in
#'   `taxaexpect_priors` to their higher-rank taxonomy. Must contain
#'   `taxon_name` plus one or more coarser-rank columns (e.g. `genus`,
#'   `family`). Typically produced from the priors' distinct
#'   (`taxon_name`, `taxon_name_rank`) pairs, passing each name's own rank:
#'   `TaxaTools::fill_higher_ranks(tx$taxon_name, input_rank = tx$taxon_name_rank,
#'   local_sources = list(match_df))`. When `NULL` (default) and coarse-rank
#'   likelihood rows are present, a warning is emitted and those rows fall
#'   back to the dark diversity floor prior. See Details.
#' @param expansion_min_prior Numeric in \[0, 1). Minimum normalized prior
#'   (within the coarse-rank candidate set) for a species to be included in
#'   the expansion. Mirrors `min_posterior` in [posterior_consensus()].
#'   Default `0.05`.
#' @param expansion_cumulative_prior Numeric in (0, 1]. Cumulative prior
#'   threshold for the expansion candidate set. Species are added in
#'   descending prior order until this fraction of the within-constraint
#'   prior mass is reached. Mirrors `cumulative_threshold` in
#'   [posterior_consensus()]. Default `0.90`.
#' @param backbone_id Taxonomic backbone ID used for the taxonomy fallback
#'   fill (see Details). Required, no default -- the correct value depends on
#'   which backbone your input taxonomy was verified against, which varies by
#'   project. Passed straight through to
#'   [TaxaTools::verify_taxon_names()]/`TaxaTools::change_backbone()`'s
#'   `dataSources` ID (see <https://verifier.globalnames.org/> for the full
#'   list). Common values: `1` Catalogue of Life, `3` ITIS, `4` NCBI, `9`
#'   WoRMS, `11` GBIF. Both sides of the join must be on one backbone, and
#'   the direction matters: harmonise the sequence-derived side (the
#'   likelihoods) onto the occurrence backbone (usually GBIF, `11`), not the
#'   reverse. The occurrence backbone holds taxa that have never been
#'   sequenced and so have no node in a sequence taxonomy; moving the priors
#'   onto NCBI drops those taxa silently (roughly 20 to 30 percent of a
#'   marine prior table on two independent 120-taxon draws, with a further
#'   fifth coarsened to genus or family).
#'   A prior taxon that fails to map does not raise; it falls to the dark
#'   diversity floor, which is indistinguishable in the output from genuine
#'   dark diversity. The join rate per rank is reported at the end of every
#'   call so a wrong direction is visible immediately.
#' @param singleton_taxonomy Optional data frame mapping `taxon_name` to
#'   taxonomy columns (`genus`, `family`, `order`, `class`, `phylum`). When
#'   supplied, unmodelled candidates (those with no TaxaExpect prior) receive
#'   mass-conserving hierarchical group priors instead of the flat global-floor
#'   prior. Groups are formed by descending phylum -> class -> order -> family
#'   -> genus: sub-clades with zero singleton mirrors form a single combined
#'   group (budget = 1 x parent-clade singleton mean / n_candidates);
#'   sub-clades with >= 1 singleton mirrors subdivide further; genus is
#'   terminal. Concentration phi = effective_singletons * singleton_ess (2).
#'   Adds three diagnostic columns to output: `dark_diversity_group`,
#'   `n_singletons_group`, `n_undetected_group`. Typically the same data frame
#'   passed as `taxonomy` to `generate_undetected_diversity()` (built from
#'   `occurrences_std`). Default `NULL` (flat global-floor for all unmodelled
#'   candidates).
#'
#' @section Modelled-species floor (scoped by cause):
#' A modelled species whose prior at the focal habitat falls below the
#' singleton-mirror mean is promoted up to that mean -- but only when the low
#' value is habitat EXTRAPOLATION (`observed_in_habitat` is `FALSE`: the
#' species was never recorded in this habitat during training, so the
#' habitat-conditional estimate is model extrapolation rather than data).
#' A genuinely low in-habitat estimate is real rarity signal and is left
#' alone. Named evidence-derived rows (`undetected_type == "evidence_blend"`,
#' `model_tier` `"tier_undetected_evidence"`/`"tier_domestic_food"`) are
#' never promoted under any condition: their sub-singleton theta is the
#' deliberate output of a graded evidence blend
#' (\code{TaxaExpect::apply_undetected_evidence()}) or ESS-based domestic
#' scale, and promotion would silently erase that gradation.
#' When `taxaexpect_priors` carries no `observed_in_habitat` column, every
#' modelled row below the singleton-mirror mean is promoted -- the
#' extrapolation check requires that column.
#'
#' @section Ring rows share one global floor per unit:
#' A ring row (`unreferenced_*` above species: an unsequenced relative named
#' by its genus or family) has no occurrence prior of its own. Where its
#' clade has a dark-diversity budget it carries that clade's remaining
#' missing-species mass; otherwise it falls back to the global floor, the
#' prior that the detected taxon is one arbitrary unrecorded taxon. A unit
#' detects one taxon, so the floor-priced rings of one observation (at one
#' site) share a single floor: each of the `k` such rings gets floor / `k`,
#' with the floor's concentration kept. Without this the unreferenced
#' prior mass of a unit would grow with the number of candidate genera, with
#' no regional evidence behind it. A unit with one floor-priced ring, and a
#' ring priced by a clade budget, are unchanged.
#'
#' This holds whatever ranks `taxaexpect_priors` carries. A ring row never
#' takes its clade's own occurrence prior, even when the table holds a row for
#' that exact genus or family: the clade's record counts the referenced
#' congeners, and each of those already competes as its own
#' `specific_candidate` row, so pricing the ring with it would both contradict
#' what the ring means and count those relatives twice in one unit. The rule
#' applies to a ring row -- a complement hypothesis ABOVE the finest rank in
#' `rank_system`. A `unreferenced_species` row AT the finest rank is a named
#' unsequenced species, not a ring, and keeps its own occurrence prior.
#'
#' @section Coarse-rank expansion:
#' When a likelihood row has `taxon_name_rank` coarser than species (e.g.
#' `"family"` or `"genus"`), the primary join finds no match -- it requires
#' the row's rank to equal the prior row's, and a coarse-rank prior row is
#' reserved for named hypotheses -- and the row would otherwise fall back to
#' the global floor prior, ignoring all species-level prior information
#' within that taxon.
#'
#' When `expansion_taxonomy` is supplied, `join_priors()` instead expands each
#' coarse-rank row into one species-level hypothesis row per retained candidate:
#' \enumerate{
#'   \item Find all modelled species in `taxaexpect_priors` at the focal site x
#'     habitat that belong to the coarse-rank constraint.
#'   \item Normalize their `prior_mean` values within the candidate set.
#'   \item Drop species below `expansion_min_prior`.
#'   \item Keep the fewest top species whose cumulative normalized prior
#'     reaches `expansion_cumulative_prior`.
#'   \item Replace the coarse-rank row with one row per retained species,
#'     inheriting all likelihood columns unchanged and receiving the
#'     species-level `alpha`/`beta` priors.
#' }
#'
#' Because `compute_posterior()` normalizes likelihoods within each
#' `observation_id` group before the Bayesian update, the inherited
#' `score_likelihood` values are equivalent to uniform -- posteriors are
#' proportional to the prior alone, which is the correct behaviour when no
#' within-family score discrimination is available.
#'
#' Rows whose coarse-rank constraint finds no matching species in
#' `taxaexpect_priors` (e.g. a family absent from the study region) are left
#' unchanged and receive the dark diversity floor prior as before.
#'
#' @return A data frame ready for [compute_posterior()], with columns
#'   `prior_mean`, `prior_alpha`, and `prior_beta` added. All input columns are
#'   preserved. Additional columns from `taxaexpect_priors`
#'   (e.g. `alpha`, `beta`, `model_tier`) are included from the
#'   join. `prior_site_records`: the site x habitat's kernel prior
#'   concentration (median `alpha + beta` of its kernel-estimated rows), the
#'   record count [posterior_consensus()]'s `robust_prior_s` check uses; `NA`
#'   when `taxaexpect_priors` has no `prior_branch` or the site has no
#'   kernel-estimated rows.
#'
#' @section Taxa that matched no prior:
#'   A row whose prior lookup failed at every tier takes the global floor. That
#'   is right for a taxon genuinely absent from `taxaexpect_priors`, and it is
#'   also what a NAME MISMATCH looks like: a call under a currently accepted
#'   name cannot meet a prior row filed under a synonym, and the floored row is
#'   indistinguishable from an honest absence. Every such named taxon is
#'   counted in a message and listed in
#'   `attr(result, "prior_floor_fallthrough")` (`taxon_name`,
#'   `taxon_name_rank`), which is present, possibly with zero rows, on every
#'   return.
#'   It is REPORTED and never corrected here: this function cannot tell a
#'   synonym from a real absence, and the join is an exact string match on
#'   `(taxon_name, taxon_name_rank, grid_id, main_habitat)`. Resolving both the
#'   likelihood side and the prior side to one backbone is the caller's job --
#'   see [TaxaMatch::convert_taxonomy_backbone()] -- and this report is how a
#'   caller finds out that it has not been done.
#'
#' @seealso [compute_posterior()], [TaxaLikely::expand_unreferenced_hypotheses()],
#'   [TaxaLikely::apply_coverage_constraints()]
#'
#' @examples
#' likelihoods <- data.frame(
#'   observation_id = c("ASV_1", "ASV_1"),
#'   taxon_name = c("Gadus morhua", "Gadus chalcogrammus"),
#'   taxon_name_rank = "species",
#'   genus = "Gadus",
#'   family = "Gadidae",
#'   stringsAsFactors = FALSE
#' )
#' taxaexpect_priors <- data.frame(
#'   taxon_name      = c("Gadus morhua", "Gadus chalcogrammus"),
#'   taxon_name_rank = "species",
#'   grid_id         = "Grid_34p4_m119p8",
#'   main_habitat    = "Marine",
#'   alpha           = c(30, 5),
#'   beta            = c(20, 45),
#'   undetected_type = NA_character_
#' )
#' joined <- join_priors(
#'   likelihoods       = likelihoods,
#'   taxaexpect_priors = taxaexpect_priors,
#'   site              = list(grid_id = "Grid_34p4_m119p8", main_habitat = "Marine"),
#'   backbone_id       = 11L
#' )
#' joined[, c("observation_id", "taxon_name", "prior_mean")]
#'
#' # A non-DNA likelihoods table (e.g. from an image or acoustic classifier)
#' # joins the same way -- join_priors() reads taxon_name/taxon_name_rank,
#' # never the evidence column the likelihoods were scored from.
#' likelihoods_acoustic <- data.frame(
#'   observation_id = c("REC_1", "REC_1"),
#'   taxon_name = c("Turdus migratorius", "Turdus rufopalliatus"),
#'   taxon_name_rank = "species",
#'   genus = "Turdus",
#'   family = "Turdidae",
#'   stringsAsFactors = FALSE
#' )
#' taxaexpect_priors_acoustic <- data.frame(
#'   taxon_name      = c("Turdus migratorius", "Turdus rufopalliatus"),
#'   taxon_name_rank = "species",
#'   grid_id         = "Grid_34p4_m119p8",
#'   main_habitat    = "Terrestrial",
#'   alpha           = c(25, 4),
#'   beta            = c(15, 40),
#'   undetected_type = NA_character_
#' )
#' joined_acoustic <- join_priors(
#'   likelihoods       = likelihoods_acoustic,
#'   taxaexpect_priors = taxaexpect_priors_acoustic,
#'   site              = list(grid_id = "Grid_34p4_m119p8", main_habitat = "Terrestrial"),
#'   backbone_id       = 11L
#' )
#' joined_acoustic[, c("observation_id", "taxon_name", "prior_mean")]
#'
#' @importFrom dplyr left_join distinct filter mutate select arrange
#' @importFrom dplyr group_by summarise coalesce if_else desc na_if
#' @importFrom rlang .data
#' @export
join_priors <- function(likelihoods,
                        taxaexpect_priors,
                        site = NULL,
                        taxonomy_lookup = NULL,
                        rank_system = NULL,
                        expansion_taxonomy = NULL,
                        expansion_min_prior = 0.05,
                        expansion_cumulative_prior = 0.90,
                        singleton_taxonomy = NULL,
                        backbone_id) {
  # ---- Input validation -----------------------------------------------------
  if (!is.data.frame(likelihoods)) {
    cli::cli_abort("{.arg likelihoods} must be a data frame.")
  }

  if (missing(backbone_id)) {
    cli::cli_abort(c(
      "{.arg backbone_id} must be specified explicitly.",
      "i" = "There is no safe default: the correct backbone depends on which \\
      backbone your input taxonomy was verified against, and this varies by \\
      project. Common values: {.val 11} (GBIF), {.val 4} (NCBI). See \\
      TaxaTools::verify_taxon_names()'s {.arg backbone_id} docs, or \\
      https://verifier.globalnames.org/ for the full list."
    ))
  }

  needed_lik <- c("observation_id", "taxon_name", "taxon_name_rank")
  missing_lik <- setdiff(needed_lik, names(likelihoods))
  if (length(missing_lik) > 0L) {
    cli::cli_abort(
      "{.arg likelihoods} is missing required column(s): {.field {missing_lik}}"
    )
  }

  if (!is.data.frame(taxaexpect_priors)) {
    cli::cli_abort("{.arg taxaexpect_priors} must be a data frame.")
  }

  needed_priors <- c(
    "taxon_name", "taxon_name_rank",
    "grid_id", "main_habitat", "alpha", "beta"
  )
  missing_priors <- setdiff(needed_priors, names(taxaexpect_priors))
  if (length(missing_priors) > 0L) {
    cli::cli_abort(
      "{.arg taxaexpect_priors} is missing required column(s): {.field {missing_priors}}"
    )
  }

  # Blank rank values ("" for an absent genus/species in a reference
  # taxonomy) are missing values, not taxa; see .blank_ranks_to_na().
  likelihoods <- .blank_ranks_to_na(likelihoods)
  taxonomy_lookup <- .blank_ranks_to_na(taxonomy_lookup)
  expansion_taxonomy <- .blank_ranks_to_na(expansion_taxonomy)
  singleton_taxonomy <- .blank_ranks_to_na(singleton_taxonomy)

  # Auto-detect rank_system from likelihoods columns
  if (is.null(rank_system)) {
    rank_system <- TaxaTools::detect_ranks(likelihoods, warn = FALSE)
    if (length(rank_system) == 0L) {
      rank_system <- c("family", "genus", "species")
    }
    cli::cli_inform(
      "join_priors: auto-detected rank_system: {paste(rank_system, collapse = ', ')}"
    )
  }

  if (!is.character(rank_system) || length(rank_system) < 2L) {
    cli::cli_abort("{.arg rank_system} must be a character vector of length >= 2.")
  }
  # Coarsest/finest below are inferred from rank_system's POSITION -- warn if
  # a user-supplied vector disagrees in order with the standard Linnaean
  # ranking, since that would silently swap "coarsest" and "finest".
  .check_rank_system_order(rank_system, "join_priors")

  if (!is.numeric(expansion_min_prior) || length(expansion_min_prior) != 1L ||
    expansion_min_prior < 0 || expansion_min_prior >= 1) {
    cli::cli_abort("{.arg expansion_min_prior} must be a single number in [0, 1).")
  }
  if (!is.numeric(expansion_cumulative_prior) || length(expansion_cumulative_prior) != 1L ||
    expansion_cumulative_prior <= 0 || expansion_cumulative_prior > 1) {
    cli::cli_abort("{.arg expansion_cumulative_prior} must be a single number in (0, 1].")
  }
  if (!is.null(expansion_taxonomy) && !is.data.frame(expansion_taxonomy)) {
    cli::cli_abort("{.arg expansion_taxonomy} must be a data frame or NULL.")
  }
  if (!is.null(singleton_taxonomy)) {
    if (!is.data.frame(singleton_taxonomy) || !"taxon_name" %in% names(singleton_taxonomy)) {
      cli::cli_abort("{.arg singleton_taxonomy} must be a data frame with a 'taxon_name' column, or NULL.")
    }
    st_rank_cols <- intersect(
      c("genus", "family", "order", "class", "phylum"),
      names(singleton_taxonomy)
    )
    if (length(st_rank_cols) == 0L) {
      cli::cli_warn(
        "{.arg singleton_taxonomy} has none of genus/family/order/class/phylum -- ignored for group priors."
      )
      singleton_taxonomy <- NULL
    }
  }

  # ---- Build event_meta from `site` ----------------------------------------

  # NULL default: require site with main_habitat
  if (is.null(site)) {
    search_center <- attr(taxaexpect_priors, "search_center")
    if (!is.null(search_center) &&
      !is.null(search_center$lat) && !is.null(search_center$lon)) {
      cli::cli_abort(c(
        "{.arg site} is required, including {.arg main_habitat}.",
        "i" = "Coordinates from build_priors() are available: ({search_center$lat}, {search_center$lon}).",
        "i" = 'Use: site = list(lat = {search_center$lat}, lon = {search_center$lon}, main_habitat = "...")'
      ))
    } else {
      cli::cli_abort(c(
        "{.arg site} is required, including {.arg main_habitat}.",
        "i" = 'Use: site = list(lat = ..., lon = ..., main_habitat = "...")',
        "i" = 'Or:  site = list(grid_id = "...", main_habitat = "...")'
      ))
    }
  }

  # Character shortcut: bare grid_id string -- require main_habitat

  if (is.character(site) && length(site) == 1L) {
    grid_rows <- taxaexpect_priors[taxaexpect_priors$grid_id == site &
      !is.na(taxaexpect_priors$main_habitat), ]
    if (nrow(grid_rows) == 0L) {
      cli::cli_abort(
        "grid_id {.val {site}} not found in {.arg taxaexpect_priors}."
      )
    }
    hab_counts <- table(grid_rows$main_habitat)
    counts_str <- paste(
      sprintf(
        "  \"%s\" (%d prior rows)", names(hab_counts),
        as.integer(hab_counts)
      ),
      collapse = "\n"
    )
    cli::cli_abort(c(
      "{.arg main_habitat} is required when specifying a grid_id.",
      "i" = "Available habitats at {.val {site}}:",
      " " = counts_str,
      "i" = 'Use: site = list(grid_id = "{site}", main_habitat = "...")'
    ))
  }

  if (is.list(site) && !is.data.frame(site)) {
    # Auto-fill lat/lon from taxaexpect_priors' own search_center attribute
    # (set by build_priors()) when the caller supplied main_habitat but no
    # location at all -- the coordinates are already known, so there is no
    # reason to force the caller to retype them (main_habitat itself is
    # still never auto-filled -- this function does not guess habitat).
    if (!any(c("lat", "lon", "grid_id") %in% names(site))) {
      search_center <- attr(taxaexpect_priors, "search_center")
      if (!is.null(search_center) &&
        !is.null(search_center$lat) && !is.null(search_center$lon)) {
        site$lat <- search_center$lat
        site$lon <- search_center$lon
        cli::cli_inform(
          "join_priors: using coordinates from build_priors()'s search_center: ({site$lat}, {site$lon})."
        )
      }
    }

    # lat/lon path: resolve to nearest existing grid_id in priors
    if (all(c("lat", "lon") %in% names(site))) {
      resolved <- .latlon_to_grid(
        lat               = site$lat,
        lon               = site$lon,
        main_habitat      = site$main_habitat,
        taxaexpect_priors = taxaexpect_priors
      )
      site$grid_id <- resolved$grid_id
      site$main_habitat <- resolved$main_habitat
    }

    # Single-site shortcut
    needed_site <- c("grid_id", "main_habitat")
    missing_site <- setdiff(needed_site, names(site))
    if (length(missing_site) > 0L) {
      cli::cli_abort(
        "{.arg site} list is missing element(s): {.field {missing_site}}. Supply (grid_id + main_habitat) or (lat + lon)."
      )
    }
    event_meta <- data.frame(
      observation_id = unique(likelihoods$observation_id),
      grid_id = site$grid_id,
      main_habitat = site$main_habitat,
      stringsAsFactors = FALSE
    )
    cli::cli_inform(
      "Single-site mode: all {nrow(event_meta)} observation(s) mapped to {.val {site$grid_id}} / {.val {site$main_habitat}}."
    )
  } else if (is.data.frame(site)) {
    # Multi-site
    needed_site <- c("observation_id", "grid_id", "main_habitat")
    missing_site <- setdiff(needed_site, names(site))
    if (length(missing_site) > 0L) {
      cli::cli_abort(
        "{.arg site} data frame is missing column(s): {.field {missing_site}}"
      )
    }
    event_meta <- site

    # Warn about likelihood observation_ids not in site
    lik_ids <- unique(likelihoods$observation_id)
    site_ids <- unique(event_meta$observation_id)
    unmapped <- setdiff(lik_ids, site_ids)
    if (length(unmapped) > 0L) {
      cli::cli_warn(
        "{length(unmapped)} observation_id(s) in {.arg likelihoods} have no entry in {.arg site}. These will receive NA priors."
      )
    }
  } else {
    cli::cli_abort(
      "{.arg site} must be a named list (single-site) or a data frame (multi-site)."
    )
  }

  # ---- Validate site combos exist in taxaexpect_priors -----------------------
  # Every (grid_id, main_habitat) the observations map to must exist in the
  # priors. Without this, a site that matches nothing (a placeholder grid_id,
  # a habitat spelled differently) gives every candidate the floor prior and
  # the run completes with nothing to show that it went wrong.
  for (k in seq_len(nrow(dplyr::distinct(event_meta, grid_id, main_habitat)))) {
    combo_k <- dplyr::distinct(event_meta, grid_id, main_habitat)[k, ]
    .assert_site_has_priors(combo_k$grid_id, combo_k$main_habitat, taxaexpect_priors)
  }
  site_combos <- dplyr::distinct(event_meta, grid_id, main_habitat)
  missing_combos <- dplyr::anti_join(
    site_combos, taxaexpect_priors,
    by = c("grid_id", "main_habitat")
  )
  if (nrow(missing_combos) > 0L) {
    # Find nearest existing grid_id for each missing combo
    all_grids <- unique(taxaexpect_priors$grid_id[!is.na(taxaexpect_priors$grid_id)])
    grid_coords <- .parse_grid_ids(all_grids)

    combo_labels <- vapply(seq_len(nrow(missing_combos)), function(j) {
      gid <- missing_combos$grid_id[j]
      hab <- missing_combos$main_habitat[j]
      # Parse the missing grid_id to coordinates
      parsed <- tryCatch(.parse_grid_ids(gid), error = function(e) NULL)
      nearest_msg <- ""
      if (!is.null(parsed) && nrow(parsed) == 1L) {
        nearest <- .find_nearest_grid(
          parsed$grid_lat, parsed$grid_lon,
          grid_coords
        )
        nearest_msg <- sprintf(
          " Nearest grid with priors: '%s'. Consider passing site = list(lat, lon) instead of a hardcoded grid_id.",
          nearest$grid_id
        )
      }
      sprintf(
        "'%s' / '%s' has 0 prior rows -- ALL species will get fallback priors.%s",
        gid, hab, nearest_msg
      )
    }, character(1L))

    cli::cli_warn(c(
      "{nrow(missing_combos)} grid_id/main_habitat combo(s) not found in {.arg taxaexpect_priors}:",
      stats::setNames(combo_labels, rep("*", length(combo_labels)))
    ))
  }

  # ---- Join likelihoods -> event_meta -> taxaexpect_priors ------------------
  # relationship = "many-to-many" on the first join is expected and intentional
  # when an observation_id has multiple candidates AND multiple sites: every
  # candidate fans out against every site row, to be recombined downstream by
  # combine_multisite_priors(). Declaring this
  # explicitly silences dplyr's precautionary warning, which would otherwise
  # fire on every genuinely multi-site, multi-candidate observation.
  .jp_base <- likelihoods |>
    dplyr::left_join(event_meta,
      by = "observation_id",
      relationship = "many-to-many"
    )

  # ---- A ring row takes no clade occurrence prior ----------------------------
  # A ring row means "an UNREFERENCED member of this clade", so its prior is the
  # floor plus the clade's unrecorded mass, which is what the ring-floor section
  # of this function's documentation describes and what
  # add_unreferenced_prior_mass() computes. The clade's OWN occurrence row
  # counts the referenced congeners, and each of those is already present as its
  # own specific_candidate row -- taking it here would price the ring with the
  # evidence for the very relatives it is defined to exclude, and double-count
  # them in the same unit.
  #
  # The join below matches on taxon_name_rank, so while taxaexpect_priors held
  # species rows only, a genus- or family-rank ring could never match and this
  # was true for free. A prior table carrying coarse-rank rows makes the clade
  # row matchable, so the rule has to be enforced rather than assumed.
  #
  # The test is on RANK, not on hypothesis_type alone. `unreferenced_species`
  # occurs at two ranks with two meanings: at a coarser rank it is the ring, but
  # AT the finest rank it is a named unsequenced species, which legitimately has
  # an occurrence prior of its own. Excluding by type alone would strip the
  # prior from those named rows -- the opposite of the intent.
  #
  # Enforced by masking the rank key across the join, so a blocked row matches
  # nothing and reaches the floor path exactly as a failed join does, rather
  # than by clearing joined columns afterwards (which would have to guess which
  # columns the join contributed, and guess wrong whenever dplyr suffixes a
  # name that collides).
  finest_rank <- rank_system[length(rank_system)]
  blocked_ring <- if ("hypothesis_type" %in% names(.jp_base)) {
    .is_complement_type(.jp_base$hypothesis_type) &
      !is.na(.jp_base$taxon_name_rank) &
      .jp_base$taxon_name_rank != finest_rank
  } else {
    rep(FALSE, nrow(.jp_base))
  }

  .jp_rank_keep <- .jp_base$taxon_name_rank
  .jp_base$.jp_prior_row <- seq_len(nrow(.jp_base))
  if (any(blocked_ring)) {
    # A rank value no real taxonomy can carry, so no prior row can match it.
    .jp_base$taxon_name_rank[blocked_ring] <- "\r.ring_takes_no_clade_prior"
  }

  result <- .jp_base |>
    dplyr::left_join(
      taxaexpect_priors,
      by = c("taxon_name", "taxon_name_rank", "grid_id", "main_habitat")
    )

  result$taxon_name_rank <- .jp_rank_keep[result$.jp_prior_row]
  result$.jp_prior_row <- NULL

  if (any(blocked_ring)) {
    .br <- .jp_base[blocked_ring, , drop = FALSE]
    cli::cli_inform(
      "join_priors: {sum(blocked_ring)} ring row(s) at {paste(sort(unique(.jp_rank_keep[blocked_ring])), collapse = ', ')} rank kept the floor path rather than their clade's own occurrence prior ({length(unique(.br$taxon_name))} clade(s))."
    )
  }

  # ---- Habitat-agnostic named-species prior fallback --------------------------
  # A named prior row can legitimately have no habitat concept at all --
  # TaxaExpect::generate_domestic_food_priors()'s output is the real example: a
  # food/domestic species' plausibility is governed by human food supply, not
  # local habitat suitability, so it has no single correct main_habitat value
  # (a grid_id can span more than one real habitat). Such rows carry
  # main_habitat = NA by design. The primary composite-key join above requires
  # an EXACT main_habitat match, so a habitat-agnostic row can never match a
  # real observation's specific habitat there -- without this fallback it
  # would silently receive the same generic dark-diversity/global-floor
  # treatment as a species with no tailored prior at all, defeating the entire
  # point of a named per-species evidence source. Confirmed a real, not
  # hypothetical, gap: a real Gadus morhua domestic-food row on real
  # GreatLakes2023 data never matched, and the affected observation's theta
  # came out ~3.4x lower than the prior this function computed for it.
  #
  # This tier rescues any row whose primary join failed (alpha still NA) by
  # re-matching on (taxon_name, taxon_name_rank, grid_id) alone against
  # habitat-agnostic (main_habitat = NA) taxaexpect_priors rows -- ranked
  # below a real per-habitat match (which always wins when one exists, since
  # this only touches rows where alpha is still NA after the primary join)
  # and above the coarse-rank/dark-diversity fallbacks below. If more than one
  # habitat-agnostic row exists for the same (taxon_name, taxon_name_rank,
  # grid_id) -- e.g. two independent evidence sources both naming the same
  # species -- the strongest (highest theta_mean) is used, matching this
  # function's own final dedup convention further below, rather than an
  # ambiguous many-to-many join.
  habitat_agnostic_priors <- taxaexpect_priors |>
    dplyr::filter(is.na(main_habitat), !is.na(taxon_name), !is.na(alpha)) |>
    dplyr::mutate(.ha_theta_mean = alpha / (alpha + beta)) |>
    dplyr::arrange(dplyr::desc(.ha_theta_mean)) |>
    dplyr::distinct(taxon_name, taxon_name_rank, grid_id, .keep_all = TRUE) |>
    dplyr::select(taxon_name, taxon_name_rank, grid_id,
      .ha_alpha = alpha, .ha_beta = beta,
      # provenance carried so the modelled-species floor promotion
      # downstream can recognize a rescued row's origin (e.g. a
      # tier_domestic_food row must never be promoted to singleton
      # parity -- its tiny theta IS the design, not an artifact).
      dplyr::any_of(c(
        .ha_model_tier = "model_tier",
        .ha_prior_branch = "prior_branch",
        .ha_undetected_type = "undetected_type"
      ))
    )

  needs_ha_fallback <- is.na(result$alpha) & !is.na(result$taxon_name)
  if (any(needs_ha_fallback) && nrow(habitat_agnostic_priors) > 0L) {
    ha_match <- result[needs_ha_fallback, c("taxon_name", "taxon_name_rank", "grid_id")] |>
      dplyr::left_join(habitat_agnostic_priors,
        by = c("taxon_name", "taxon_name_rank", "grid_id")
      )
    n_ha_applied <- sum(!is.na(ha_match$.ha_alpha))
    result$alpha[needs_ha_fallback] <- dplyr::coalesce(
      result$alpha[needs_ha_fallback], ha_match$.ha_alpha
    )
    result$beta[needs_ha_fallback] <- dplyr::coalesce(
      result$beta[needs_ha_fallback], ha_match$.ha_beta
    )
    for (.prov in c("model_tier", "prior_branch", "undetected_type")) {
      .ha_col <- paste0(".ha_", .prov)
      if (.ha_col %in% names(ha_match) && .prov %in% names(result)) {
        result[[.prov]][needs_ha_fallback] <- dplyr::coalesce(
          result[[.prov]][needs_ha_fallback], ha_match[[.ha_col]]
        )
      }
    }
    if (n_ha_applied > 0L) {
      cli::cli_inform(
        "join_priors: applied {n_ha_applied} habitat-agnostic named-species prior row(s) (e.g. domestic/food priors with no habitat concept)."
      )
    }
  }

  # ---- Coarse-rank expansion -------------------------------------------------
  # Rows where the primary join failed because taxon_name_rank is coarser than
  # species (e.g. a family- or genus-level identification). Expand into
  # species-level hypothesis rows using taxaexpect_priors + expansion_taxonomy.
  # Must run before the dark diversity fallback so expanded rows receive their
  # species-level alpha/beta directly.

  # Warn if coarse-rank rows exist but expansion_taxonomy was not supplied.
  coarser_than_finest <- rank_system[-length(rank_system)]
  n_coarse_unmatched <- sum(
    is.na(result$alpha) &
      !is.na(result$taxon_name_rank) &
      result$taxon_name_rank %in% coarser_than_finest &
      !is.na(result$taxon_name),
    na.rm = TRUE
  )
  if (n_coarse_unmatched > 0L && is.null(expansion_taxonomy)) {
    cli::cli_warn(c(
      "{n_coarse_unmatched} likelihood row(s) have a coarse-rank taxon_name_rank ({paste(sort(unique(result$taxon_name_rank[is.na(result$alpha) & result$taxon_name_rank %in% coarser_than_finest & !is.na(result$taxon_name)])), collapse = ', ')}) that cannot join to species-level priors.",
      "i" = "These rows will receive the dark diversity floor prior.",
      "i" = "To expand them into species-level hypotheses, supply {.arg expansion_taxonomy}:",
      "i" = "  tx <- dplyr::distinct(taxaexpect_priors[!is.na(taxaexpect_priors$taxon_name), ], taxon_name, taxon_name_rank)",
      "i" = "  expansion_taxonomy = TaxaTools::fill_higher_ranks(",
      "i" = "    tx$taxon_name, input_rank = tx$taxon_name_rank,",
      "i" = "    local_sources = list(match_df, gbif_occurrences))"
    ))
  }

  if (n_coarse_unmatched > 0L && !is.null(expansion_taxonomy)) {
    result <- .expand_coarse_rank_rows(
      result = result,
      taxaexpect_priors = taxaexpect_priors,
      expansion_taxonomy = expansion_taxonomy,
      rank_system = rank_system,
      expansion_min_prior = expansion_min_prior,
      expansion_cumulative_prior = expansion_cumulative_prior
    )
  }

  # ---- Dark diversity fallback -----------------------------------------------
  # Site-level: mean alpha/beta from Tier 3 (undetected) rows per grid x habitat
  dark_by_site <- taxaexpect_priors |>
    dplyr::filter(!is.na(undetected_type)) |>
    dplyr::group_by(grid_id, main_habitat) |>
    dplyr::summarise(
      dark_alpha = mean(alpha, na.rm = TRUE),
      dark_beta = mean(beta, na.rm = TRUE),
      .groups = "drop"
    )

  # Global fallback: average across all Tier 3 rows (used to fill dark_alpha/beta
  # when a site has no Tier 3 rows, driving the modelled-species floor promotion).
  global_dark <- taxaexpect_priors |>
    dplyr::filter(!is.na(undetected_type)) |>
    dplyr::summarise(
      dark_alpha = mean(alpha, na.rm = TRUE),
      dark_beta  = mean(beta, na.rm = TRUE)
    )

  # Singleton-mirror mean: used as the floor threshold for modelled-species
  # prior promotion. Singleton mirrors represent the detection probability
  # of species observed exactly once in training data -- the correct floor
  # for a modelled species with genuine (but very low) theta. Using
  # dark_mean (= mean of singleton
  # mirrors + global floor) was too aggressive: a Tier 2 species with genuine
  # small theta could be promoted to dark_mean even though dark_mean is pulled
  # down by the global floor, erasing the signal that the species was actually
  # detected. With singleton_mean as the threshold, only species whose model
  # estimate falls below the rarest-known detection rate are promoted.
  singleton_by_site <- taxaexpect_priors |>
    dplyr::filter(undetected_type == "singleton_mirror") |>
    dplyr::group_by(grid_id, main_habitat) |>
    dplyr::summarise(
      singleton_alpha = mean(alpha, na.rm = TRUE),
      singleton_beta = mean(beta, na.rm = TRUE),
      .groups = "drop"
    )

  global_singleton <- taxaexpect_priors |>
    dplyr::filter(undetected_type == "singleton_mirror") |>
    dplyr::summarise(
      singleton_alpha = mean(alpha, na.rm = TRUE),
      singleton_beta  = mean(beta, na.rm = TRUE)
    )

  # Global floor prior: used specifically as the fallback for UNMODELLED species
  # (those with no row in taxaexpect_priors, e.g. species never detected anywhere).
  # Distinct from dark_alpha/dark_beta: the site-level dark mean is dominated by
  # singleton mirrors (observed species), so using it as an unmodelled-species
  # fallback conflates "detected once elsewhere" with "never detected", erasing
  # the prior distinction between rare observed species and true dark diversity.
  # The global floor Beta(1, N_total - 1) is specifically designed to represent
  # species from the regional pool that have zero detections -- appropriate here.
  gf_rows <- taxaexpect_priors |>
    dplyr::filter(undetected_type == "global_floor")
  if (nrow(gf_rows) > 0 && !is.na(mean(gf_rows$alpha, na.rm = TRUE))) {
    gf_alpha <- mean(gf_rows$alpha, na.rm = TRUE)
    gf_beta <- mean(gf_rows$beta, na.rm = TRUE)
  } else {
    # No global floor row present -- fall back to global dark mean.
    # This preserves prior behaviour when generate_undetected_diversity() output
    # was filtered to exclude the global floor (habitat = NA) row.
    gf_alpha <- global_dark$dark_alpha
    gf_beta <- global_dark$dark_beta
    cli::cli_warn(paste0(
      "join_priors: no global_floor row found in taxaexpect_priors. ",
      "Unmodelled species will use site-level dark diversity as fallback. ",
      "Make sure taxaexpect_priors includes the global_floor row ",
      "(undetected_type == 'global_floor') from ",
      "TaxaExpect::generate_undetected_diversity() to enable the principled ",
      "unmodelled-species prior."
    ))
  }

  result <- result |>
    dplyr::left_join(dark_by_site, by = c("grid_id", "main_habitat")) |>
    dplyr::left_join(singleton_by_site, by = c("grid_id", "main_habitat")) |>
    dplyr::mutate(
      dark_alpha = dplyr::coalesce(dark_alpha, global_dark$dark_alpha),
      dark_beta = dplyr::coalesce(dark_beta, global_dark$dark_beta),
      singleton_alpha = dplyr::coalesce(singleton_alpha, global_singleton$singleton_alpha),
      singleton_beta = dplyr::coalesce(singleton_beta, global_singleton$singleton_beta),
      # Unmodelled species (alpha = NA) fall back to global floor, NOT dark_alpha.
      # Modelled species retain their model-derived alpha/beta here; the floor
      # promotion below handles modelled species that fall below singleton_mean.
      prior_alpha = dplyr::coalesce(alpha, gf_alpha),
      prior_beta = dplyr::coalesce(beta, gf_beta),
      prior_mean = prior_alpha / (prior_alpha + prior_beta)
    )

  # ---- Modelled-species floor: never worse than singleton-mirror mean --------
  # A species the model has seen (non-NA alpha) at the WRONG habitat can get
  # theta ~= 0, producing prior_alpha well below the singleton-mirror level.
  # This inverts the intended ordering: unobserved species beat observed ones.
  # Fix: promote such rows to the singleton-mirror level. We use singleton_mean
  # (not dark_mean) because dark_mean is pulled down by the global floor.
  #
  # SCOPED BY CAUSE. A blanket `!is.na(alpha) & below-singleton` condition
  # would promote far more than its motivating case:
  # (a) Named evidence-derived rows (undetected_type == "evidence_blend",
  #     model_tier tier_undetected_evidence/tier_domestic_food) sit below the
  #     singleton mean BY CONSTRUCTION -- their graded theta IS the design
  #     (TaxaExpect::apply_undetected_evidence()'s weighted blend,
  #     generate_domestic_food_priors()'s ESS-based scale). Promoting them to
  #     exact singleton parity would silently erase every weight/distance/age
  #     gradation and convert the blend into a binary admission gate
  #     (verified by ablation on GreatLakes data: byte-identical consensus
  #     output across a 4x d_half sweep; 177 observations flipped
  #     species->coarser). Never promoted, under any condition.
  # (b) Modelled rows whose low theta is a genuine, in-habitat estimate
  #     (observed_in_habitat TRUE) are data, not artifact -- promoting them
  #     discards real rarity signal. Only rows whose low prior is habitat
  #     EXTRAPOLATION (observed_in_habitat explicitly FALSE -- the species was
  #     never recorded in this habitat in training, the rule's actual
  #     motivating case) are promoted. When taxaexpect_priors carries no
  #     observed_in_habitat column at all, blanket promotion is retained for
  #     modelled rows so such priors are not silently skipped.
  has_model <- !is.na(result$alpha)
  singleton_mean <- result$singleton_alpha / (result$singleton_alpha + result$singleton_beta)

  not_evidence_row <- rep(TRUE, nrow(result))
  if ("undetected_type" %in% names(result)) {
    not_evidence_row <- not_evidence_row &
      (is.na(result$undetected_type) | result$undetected_type != "evidence_blend")
  }
  if ("model_tier" %in% names(result)) {
    not_evidence_row <- not_evidence_row &
      (is.na(result$model_tier) |
        !result$model_tier %in% c("tier_undetected_evidence", "tier_domestic_food"))
  }
  # Kernel-priors schema: when prior_branch is present, only kernel-estimated
  # resident rows are promotion-eligible -- every other branch's magnitude
  # (evidence blends, transport/domestic, undetected floors) is its design,
  # not a habitat-extrapolation artifact. Subsumes the model_tier value
  # checks above once that column is retired.
  #
  # Reads .is_kernel_branch() rather than a bare string comparison (see
  # kernel_branch.R), so an unrecognised prior_branch value (e.g. a pre-1.0
  # label on a cached prior table) stops loudly instead of silently failing
  # this membership test. Deliberately NOT
  # gated on effective_records as well: promotion only ever lifts a row to singleton
  # parity, and a low-evidence row's theta is already ~13,000x below a
  # well-evidenced one's (real PtCon 12S medians, 1.5e-08 vs 1.9e-04), so
  # there is no case here of a thin row being promoted to prominence. The
  # evidence question binds on the PLAUSIBILITY claim instead -- see
  # posterior_consensus(min_effective_records=).
  if ("prior_branch" %in% names(result)) {
    not_evidence_row <- not_evidence_row &
      (is.na(result$prior_branch) | .is_kernel_branch(result$prior_branch))
  }

  habitat_mismatch <- if ("observed_in_habitat" %in% names(result)) {
    !is.na(result$observed_in_habitat) & !result$observed_in_habitat
  } else {
    rep(TRUE, nrow(result))
  }

  below_singleton <- has_model & not_evidence_row & habitat_mismatch &
    result$prior_mean < singleton_mean
  if (any(below_singleton, na.rm = TRUE)) {
    n_promoted <- sum(below_singleton, na.rm = TRUE)
    result$prior_alpha[below_singleton] <- result$singleton_alpha[below_singleton]
    result$prior_beta[below_singleton] <- result$singleton_beta[below_singleton]
    result$prior_mean[below_singleton] <- singleton_mean[below_singleton]
    cli::cli_inform(
      "join_priors: promoted {n_promoted} habitat-mismatch modelled row(s) with priors below the singleton-mirror floor."
    )
  }

  # ---- Group-based dark diversity priors -------------------------------------
  # When singleton_taxonomy is supplied, replace the flat global-floor prior
  # for unmodelled candidates with mass-conserving hierarchical group priors.
  # See .compute_dark_diversity_groups() for the algorithm.
  # Adds diagnostic columns: dark_diversity_group, n_singletons_group,
  # n_undetected_group (NA for modelled rows and when singleton_taxonomy = NULL).
  if (!is.null(singleton_taxonomy)) {
    tax_rank_cols <- c("genus", "family", "order", "class", "phylum")
    st_rank_cols <- intersect(tax_rank_cols, names(singleton_taxonomy))

    # Normalize empty strings to NA and deduplicate
    sing_tax_norm <- singleton_taxonomy
    for (.col in st_rank_cols) {
      sing_tax_norm[[.col]] <- dplyr::na_if(sing_tax_norm[[.col]], "")
    }
    sing_tax_norm <- sing_tax_norm[!duplicated(sing_tax_norm$taxon_name), ,
      drop = FALSE
    ]

    # Identify unmodelled rows (got gf_alpha as fallback above)
    is_unmod <- is.na(result$alpha)

    # Retrieve singleton mirror rows from taxaexpect_priors; join taxonomy via
    # source_taxon_name so we know which phylum/class/order/family/genus each
    # singleton proxy represents. (Taxonomy columns were stripped by
    # estimate_kernel_priors()'s own select() -- must re-join here.)
    if ("source_taxon_name" %in% names(taxaexpect_priors)) {
      sing_rows <- taxaexpect_priors[
        !is.na(taxaexpect_priors$undetected_type) &
          taxaexpect_priors$undetected_type == "singleton_mirror" &
          !is.na(taxaexpect_priors$source_taxon_name), ,
        drop = FALSE
      ]
      if (nrow(sing_rows) > 0L) {
        sing_rows <- merge(
          sing_rows,
          sing_tax_norm[, c("taxon_name", st_rank_cols), drop = FALSE],
          by.x = "source_taxon_name", by.y = "taxon_name",
          all.x = TRUE
        )
      }
    } else {
      sing_rows <- taxaexpect_priors[integer(0L), , drop = FALSE]
      cli::cli_warn(paste0(
        "join_priors: singleton_taxonomy supplied but taxaexpect_priors lacks ",
        "'source_taxon_name'. Group dark diversity priors require ",
        "source_taxon_name in your priors table (present in ",
        "TaxaExpect::generate_undetected_diversity() output ",
        "and in estimate_kernel_priors() output)."
      ))
    }

    if (any(is_unmod) && nrow(sing_rows) > 0L) {
      # Unique unmodelled taxon names -- group prior is per-taxon, not per-row
      unmod_taxa <- unique(result$taxon_name[is_unmod & !is.na(result$taxon_name)])

      if (length(unmod_taxa) > 0L) {
        unmod_df <- data.frame(taxon_name = unmod_taxa, stringsAsFactors = FALSE)
        unmod_df <- merge(
          unmod_df,
          sing_tax_norm[, c("taxon_name", st_rank_cols), drop = FALSE],
          by = "taxon_name", all.x = TRUE
        )
        # An unrecorded candidate is usually absent from the occurrence
        # taxonomy; take its ranks from its own rows where that left them empty.
        own <- result[is_unmod & !is.na(result$taxon_name), , drop = FALSE]
        own <- own[!duplicated(own$taxon_name), , drop = FALSE]
        oi <- match(unmod_df$taxon_name, own$taxon_name)
        for (rc in intersect(st_rank_cols, names(own))) {
          fill <- is.na(unmod_df[[rc]]) | !nzchar(unmod_df[[rc]])
          unmod_df[[rc]][fill] <- as.character(own[[rc]][oi[fill]])
        }

        # Compute global singleton mean for fallback
        gs_a <- global_singleton$singleton_alpha
        gs_b <- global_singleton$singleton_beta
        gs_mean <- if (is.finite(gs_a) && is.finite(gs_b) && (gs_a + gs_b) > 0) {
          gs_a / (gs_a + gs_b)
        } else {
          gf_alpha / (gf_alpha + gf_beta)
        }

        # Compute group priors
        # Evidence-priced taxa (regional, iNaturalist, watch list) use up part
        # of their clade's missing-species budget.
        ev_df <- NULL
        if (all(c("undetected_type", "prior_mix_w") %in% names(taxaexpect_priors))) {
          ev <- taxaexpect_priors[!is.na(taxaexpect_priors$prior_mix_w) &
            taxaexpect_priors$undetected_type %in% "evidence_blend", c("taxon_name", "prior_mix_w"), drop = FALSE]
          ev <- ev[!duplicated(ev$taxon_name), , drop = FALSE]
          if (nrow(ev)) {
            ev_df <- merge(data.frame(taxon_name = ev$taxon_name, w = ev$prior_mix_w),
              sing_tax_norm[, c("taxon_name", st_rank_cols), drop = FALSE], by = "taxon_name", all.x = TRUE)
          }
        }
        unmod_groups <- .compute_dark_diversity_groups(
          unref_df              = unmod_df[!is.na(match(unmod_df$taxon_name, result$taxon_name[is_unmod & result$taxon_name_rank %in% "species"])), , drop = FALSE],
          singleton_df          = sing_rows,
          global_singleton_mean = gs_mean,
          singleton_ess         = 2L,
          evidence_df           = ev_df
        )
        dark_budget <- attr(unmod_groups, "dark_budget")

        # Join group priors back to result rows by taxon_name (index-based,
        # preserves row order and avoids duplicates from merge)
        idx <- match(result$taxon_name, unmod_groups$taxon_name)
        result$dark_diversity_group <- unmod_groups$dark_diversity_group[idx]
        result$n_singletons_group <- unmod_groups$n_singletons_group[idx]
        result$n_undetected_group <- unmod_groups$n_undetected_group[idx]
        result$group_prior_alpha <- unmod_groups$group_prior_alpha[idx]
        result$group_prior_beta <- unmod_groups$group_prior_beta[idx]

        # Apply group priors to unmodelled rows (replace flat gf_alpha/gf_beta)
        apply_mask <- is_unmod & !is.na(result$group_prior_alpha)
        if (any(apply_mask)) {
          result$prior_alpha[apply_mask] <- result$group_prior_alpha[apply_mask]
          result$prior_beta[apply_mask] <- result$group_prior_beta[apply_mask]
          result$prior_mean[apply_mask] <- result$prior_alpha[apply_mask] /
            (result$prior_alpha[apply_mask] + result$prior_beta[apply_mask])
          n_groups_used <- length(unique(stats::na.omit(
            result$dark_diversity_group[apply_mask]
          )))
          cli::cli_inform(
            "join_priors: group dark diversity priors applied to {sum(apply_mask)} unmodelled row(s) across {n_groups_used} taxonomic group(s)."
          )
        }
        # Ring rows (an unsequenced relative named by its clade) carry the
        # clade's remaining missing-species mass, when larger than their floor.
        if (!is.null(dark_budget) && nrow(dark_budget) && "hypothesis_type" %in% names(result)) {
          rk <- paste(dark_budget$rank, dark_budget$clade, sep = "\r")
          ring <- which(.is_unreferenced_type(result$hypothesis_type) & !is.na(result$taxon_name))
          rm_i <- match(paste(result$taxon_name_rank[ring], result$taxon_name[ring], sep = "\r"), rk)
          has <- !is.na(rm_i) & dark_budget$remainder[rm_i] > result$prior_mean[ring]
          if (any(has)) {
            rows <- ring[has]
            pm <- pmin(dark_budget$remainder[rm_i[has]], 1 - 1e-9)
            phi <- pmax(1, dark_budget$N[rm_i[has]]) * 2
            result$prior_mean[rows] <- pm
            result$prior_alpha[rows] <- pm * phi
            result$prior_beta[rows] <- (1 - pm) * phi
            cli::cli_inform("join_priors: {length(rows)} unsequenced-relative row(s) carry their clade's remaining dark-diversity mass.")
          }
        }
      }
    }

    # Ensure diagnostic columns exist (NA for modelled rows and rows with no
    # taxonomy match) so the output schema is consistent for downstream use.
    if (!"dark_diversity_group" %in% names(result)) result$dark_diversity_group <- NA_character_
    if (!"n_singletons_group" %in% names(result)) result$n_singletons_group <- NA_integer_
    if (!"n_undetected_group" %in% names(result)) result$n_undetected_group <- NA_integer_
    # Clean up intermediate columns not needed downstream
    result$group_prior_alpha <- NULL
    result$group_prior_beta <- NULL
  }

  zero_ab <- which((result$prior_alpha + result$prior_beta) == 0)
  if (length(zero_ab) > 0L) {
    cli::cli_warn(
      "{length(zero_ab)} row(s) have alpha + beta = 0; setting prior_mean to \\
      0.5 (uninformative)."
    )
    result$prior_alpha[zero_ab] <- 0.5
    result$prior_beta[zero_ab] <- 0.5
    result$prior_mean[zero_ab] <- 0.5
  }

  n_no_prior <- sum(is.na(result$prior_mean))
  if (n_no_prior > 0L) {
    cli::cli_warn(
      "{n_no_prior} row(s) have no prior after dark diversity fallback. Check site coverage in TaxaExpect."
    )
  }

  # ---- Dedup + taxonomy fill + redundancy filter -----------------------------
  # grid_id/main_habitat included so a genuine multi-site observation (the same
  # observation_id detected at more than one site -- see combine_multisite_priors())
  # keeps one row PER SITE per candidate, instead of collapsing to a single
  # highest-prior_mean site per candidate. Without this, each candidate would be
  # matched only to its own most favorable site, discarding the site it was
  # actually detected at (see combine_multisite_priors() roxygen for the full
  # empirical repro). This still dedupes same-site duplicates from coarse-rank
  # expansion as well.
  result <- result |>
    dplyr::arrange(dplyr::desc(prior_mean)) |>
    dplyr::distinct(observation_id, taxon_name, taxon_name_rank, grid_id,
      main_habitat,
      .keep_all = TRUE
    )

  # Fill taxonomy from taxonomy_lookup (e.g. from match_df reference taxonomy)
  if (!is.null(taxonomy_lookup) && is.data.frame(taxonomy_lookup) &&
    "taxon_name" %in% names(taxonomy_lookup)) {
    tax_cols <- intersect(rank_system, names(taxonomy_lookup))
    if (length(tax_cols) > 0L) {
      lookup_slim <- taxonomy_lookup |>
        dplyr::select(dplyr::all_of(c("taxon_name", tax_cols))) |>
        dplyr::distinct(taxon_name, .keep_all = TRUE)
      for (col in tax_cols) {
        if (col %in% names(result)) {
          # Fill NAs from lookup
          idx <- match(result$taxon_name, lookup_slim$taxon_name)
          na_mask <- is.na(result[[col]]) & !is.na(idx)
          result[[col]][na_mask] <- lookup_slim[[col]][idx[na_mask]]
        } else {
          # Add the column from lookup
          idx <- match(result$taxon_name, lookup_slim$taxon_name)
          result[[col]] <- lookup_slim[[col]][idx]
        }
      }
    }
  }

  # Derive genus from species binomials when genus column is NA
  result <- result |>
    dplyr::mutate(genus = dplyr::coalesce(
      genus,
      dplyr::if_else(taxon_name_rank == "species",
        sub(" .*", "", taxon_name), NA_character_
      ),
      dplyr::if_else(taxon_name_rank == "genus", taxon_name, NA_character_)
    ))

  # Fill the rank column matching taxon_name_rank from taxon_name itself.
  # e.g. a family-rank row with taxon_name="Girellidae" should have
  # family="Girellidae", an order-rank row should fill the order column, etc.
  rank_cols_in_df <- intersect(rank_system, names(result))
  for (rc in rank_cols_in_df) {
    is_this_rank <- !is.na(result$taxon_name_rank) & result$taxon_name_rank == rc
    needs_val <- is_this_rank & is.na(result[[rc]]) & !is.na(result$taxon_name)
    if (any(needs_val)) {
      result[[rc]][needs_val] <- result$taxon_name[needs_val]
    }
  }

  # Propagate family from rows that share a genus. A genus name is not a
  # key: homonyms (Porella, Eisenia, ...) and reassigned genera carry more
  # than one family, and joining on the bare name gave every row of such a
  # genus one copy per family. Only genera with a single family fill.
  fam_lookup <- result |>
    dplyr::filter(!is.na(genus), !is.na(family)) |>
    dplyr::distinct(genus, family)
  ambiguous_genera <- unique(fam_lookup$genus[duplicated(fam_lookup$genus)])
  if (length(ambiguous_genera) > 0L) {
    fam_lookup <- fam_lookup[!fam_lookup$genus %in% ambiguous_genera, , drop = FALSE]
    cli::cli_inform(c(
      "i" = "join_priors: {length(ambiguous_genera)} genus name(s) map to more than one \\
      family ({.val {utils::head(ambiguous_genera, 5)}}{if (length(ambiguous_genera) > 5) ', ...' else ''}); \\
      family is not filled from genus for them."
    ))
  }

  result <- result |>
    dplyr::left_join(fam_lookup, by = "genus", suffix = c("", ".fill")) |>
    dplyr::mutate(family = dplyr::coalesce(family, family.fill)) |>
    dplyr::select(-family.fill)

  # Fill higher taxonomy for genus/family-level rows from other rows in
  # the same lineage. Without this, filter_redundant_hypotheses() cannot
  # detect that e.g. "Girella" (genus) shares a lineage with "Girella
  # nigricans" (species), because the genus row has NA in kingdom/phylum/
  # class/order -- and the filter conservatively retains rows with NA
  # ancestors. Process fine-to-coarse so genus rows filled by species rows
  # can then donate to family rows.
  if (length(rank_cols_in_df) >= 2L) {
    for (rc_idx in rev(seq_along(rank_cols_in_df))) {
      anchor_col <- rank_cols_in_df[rc_idx]
      if (rc_idx == 1L) next
      coarser_cols <- rank_cols_in_df[seq_len(rc_idx - 1L)]
      needs_fill <- which(
        !is.na(result[[anchor_col]]) &
          rowSums(is.na(result[, coarser_cols, drop = FALSE])) > 0L
      )
      if (length(needs_fill) == 0L) next
      donor_lookup <- result[!is.na(result[[anchor_col]]), , drop = FALSE] |>
        dplyr::select(dplyr::all_of(c(anchor_col, coarser_cols))) |>
        dplyr::distinct(.data[[anchor_col]], .keep_all = TRUE)
      # Vectorized match() lookup (one hash lookup per rank level) instead of
      # a per-row linear scan through donor_lookup -- same semantics (first
      # donor row sharing anchor_col's value; only fill cells that are NA).
      donor_idx <- match(result[[anchor_col]][needs_fill], donor_lookup[[anchor_col]])
      for (cc in coarser_cols) {
        donor_vals <- donor_lookup[[cc]][donor_idx]
        fillable <- is.na(result[[cc]][needs_fill]) & !is.na(donor_vals)
        result[[cc]][needs_fill[fillable]] <- donor_vals[fillable]
      }
    }
  }

  # Fallback: fill remaining taxonomy holes via TaxaTools backbone query.
  # Only fires when sibling propagation left gaps (e.g. no species-level
  # row existed for a genus). Queries are batched on unique taxon_names.
  if (length(rank_cols_in_df) >= 2L &&
    requireNamespace("TaxaTools", quietly = TRUE)) {
    still_missing <- which(
      rowSums(is.na(result[, rank_cols_in_df, drop = FALSE])) > 0L &
        !is.na(result$taxon_name)
    )
    if (length(still_missing) > 0L) {
      names_to_query <- unique(result$taxon_name[still_missing])
      backbone_fill <- tryCatch(
        {
          vargs <- list(names_to_query, backbone_id = backbone_id)
          # The row's own rank resolves an NCBI homonym without a decision
          # (see posterior_consensus()). The nine packages version-lock and
          # install as a set, so the argument is passed outright: a rename
          # must fail loudly here, not silently stop passing the rank.
          if ("taxon_name_rank" %in% names(result)) {
            vargs$input_rank <- as.character(result$taxon_name_rank)[match(names_to_query, result$taxon_name)]
          }
          verified <- do.call(TaxaTools::verify_taxon_names, vargs)
          TaxaTools::change_backbone(verified,
            input_col = "user_supplied_name"
          )
        },
        error = function(e) {
          cli::cli_warn(
            "Taxonomy fallback via TaxaTools failed: {conditionMessage(e)}"
          )
          NULL
        }
      )
      if (!is.null(backbone_fill) && nrow(backbone_fill) > 0L) {
        fill_cols <- intersect(rank_cols_in_df, names(backbone_fill))
        # change_backbone() returns user_supplied_name, not taxon_name
        join_col <- if ("user_supplied_name" %in% names(backbone_fill)) {
          "user_supplied_name"
        } else {
          NULL
        }
        if (length(fill_cols) > 0L && !is.null(join_col)) {
          bb_lookup <- backbone_fill |>
            dplyr::select(dplyr::all_of(c(join_col, fill_cols))) |>
            dplyr::distinct(.data[[join_col]], .keep_all = TRUE)
          idx <- match(
            result$taxon_name[still_missing],
            bb_lookup[[join_col]]
          )
          for (fc in fill_cols) {
            na_mask <- is.na(result[[fc]][still_missing]) & !is.na(idx)
            if (any(na_mask)) {
              result[[fc]][still_missing[na_mask]] <-
                bb_lookup[[fc]][idx[na_mask]]
            }
          }
          n_filled <- sum(!is.na(idx))
          if (n_filled > 0L) {
            cli::cli_inform(
              "Filled taxonomy for {n_filled} taxon name{?s} via backbone {backbone_id}."
            )
          }
        }
      }
    }
  }

  # Drop coarser-rank rows superseded by finer-rank rows in same lineage
  if (!requireNamespace("TaxaMatch", quietly = TRUE)) {
    cli::cli_warn(
      "{.pkg TaxaMatch} is not installed. Skipping redundant hypothesis filtering."
    )
  } else {
    # The generic unreferenced hypotheses (an unsequenced species of the
    # candidate's genus, an unsequenced genus of its family) sit at a coarser
    # rank than the candidates in the same lineage, but they are not coarser
    # labels for those candidates: they are their competitors. The redundancy
    # filter cannot tell the two apart, so it would delete them. Run it as
    # before, then restore any unreferenced row it removed.
    result$.jp_row <- seq_len(nrow(result))
    kept <- TaxaMatch::filter_redundant_hypotheses(
      result,
      rank_system = rank_system
    )
    if ("hypothesis_type" %in% names(result)) {
      lost <- result[.is_complement_type(result$hypothesis_type) &
        !result$.jp_row %in% kept$.jp_row, , drop = FALSE]
      if (nrow(lost) > 0L) {
        kept <- dplyr::bind_rows(kept, lost)
        kept <- kept[order(kept$.jp_row), , drop = FALSE]
      }
    }
    kept$.jp_row <- NULL
    result <- kept
  }

  # ---- one global floor per unit for floor-priced ring rows ----------------
  # A ring row (an unsequenced relative named by its clade) that no clade
  # budget priced still holds the flat global floor: the prior that the
  # detected taxon is one arbitrary unrecorded taxon. A unit detects one
  # taxon, and its rings are mutually exclusive versions of that one event,
  # so together they carry the floor ONCE: each of the k floor-priced rings
  # of a unit (per observation and site) gets floor / k, concentration kept.
  # Rings priced by a clade budget keep their own mass; a unit with one
  # floor-priced ring is unchanged. Runs after the dedup and the redundancy
  # filter, so k counts only the rings that survive into the output.
  result <- .split_ring_floor(result, gf_alpha, gf_beta)

  # Join rate per rank: how many distinct candidate taxa found a modelled
  # prior (alpha set by the join) against how many were offered. A wrong
  # harmonisation direction, or priors on a different backbone, shows here
  # as a low species-level rate, instead of surfacing later as a table with
  # too much apparent dark diversity.
  if (all(c("taxon_name", "taxon_name_rank", "alpha") %in% names(result))) {
    offered <- unique(data.frame(
      taxon_name_rank = result$taxon_name_rank,
      taxon_name = result$taxon_name,
      matched = !is.na(result$alpha),
      stringsAsFactors = FALSE
    ))
    offered <- offered[!is.na(offered$taxon_name) & !is.na(offered$taxon_name_rank), , drop = FALSE]
    if (nrow(offered) > 0L) {
      n_all <- table(offered$taxon_name_rank)
      n_hit <- tapply(offered$matched, offered$taxon_name_rank, sum)
      ranks <- names(n_all)[order(match(names(n_all), rank_system))]
      by_rank <- data.frame(
        taxon_name_rank = ranks,
        n = as.integer(n_all[ranks]),
        n_matched = as.integer(n_hit[ranks]),
        stringsAsFactors = FALSE
      )
      rate_lines <- sprintf(
        "%s: %d of %d candidate taxa matched a prior", by_rank$taxon_name_rank,
        by_rank$n_matched, by_rank$n
      )
      cli::cli_inform(c(
        "join_priors: join rate by rank (the rest receive the dark diversity floor):",
        stats::setNames(rate_lines, rep(" ", length(rate_lines)))
      ))
    }
  }

  # ---- Site record concentration (for posterior_consensus(robust_prior_s)) ---
  # The kernel prior's Dirichlet concentration for the site x habitat: the
  # median alpha + beta of its kernel-estimated rows. Stamped on every row so
  # the robust check can use the site's records for an observation whose own
  # candidates are all unrecorded (whose alpha + beta are floor or dark-
  # diversity pseudo-counts, not records).
  result$prior_site_records <- NA_real_
  if ("prior_branch" %in% names(taxaexpect_priors) &&
    all(c("grid_id", "main_habitat") %in% names(result))) {
    kp <- taxaexpect_priors[.is_kernel_branch(taxaexpect_priors$prior_branch) &
      is.finite(taxaexpect_priors$alpha + taxaexpect_priors$beta), , drop = FALSE]
    if (nrow(kp) > 0L) {
      site_n <- tapply(kp$alpha + kp$beta, paste(kp$grid_id, kp$main_habitat, sep = "\r"), stats::median)
      result$prior_site_records <- as.numeric(site_n[paste(result$grid_id, result$main_habitat, sep = "\r")])
    }
  }

  # ---- Rows that reached the global floor at their OWN rank -----------------
  # A row whose `alpha` is still NA after every tier matched no prior and took
  # the global floor. That is correct for a species with genuinely no prior, and
  # it is also what a NAME MISMATCH looks like: a call under the currently
  # accepted name cannot meet a prior row filed under a synonym, so it is
  # floored and nothing says so. The coarse-rank warning above covers only rows
  # coarser than the finest rank, and only when `expansion_taxonomy` is absent,
  # so a species-rank synonym miss had no report at all.
  # Reported, never corrected here: this function cannot tell a synonym from a
  # taxon that is truly absent from the prior, and guessing would be worse than
  # naming it. The caller resolves both sides to one backbone; this says when
  # that has not happened.
  floored <- !is.na(result$taxon_name) &
    (if ("alpha" %in% names(result)) is.na(result$alpha) else FALSE)
  fallthrough <- if (any(floored)) {
    d <- unique(data.frame(
      taxon_name = result$taxon_name[floored],
      taxon_name_rank = result$taxon_name_rank[floored],
      stringsAsFactors = FALSE
    ))
    d[order(d$taxon_name_rank, d$taxon_name), , drop = FALSE]
  } else {
    data.frame(
      taxon_name = character(0), taxon_name_rank = character(0),
      stringsAsFactors = FALSE
    )
  }
  attr(result, "prior_floor_fallthrough") <- fallthrough
  if (nrow(fallthrough) > 0L) {
    by_rank <- table(fallthrough$taxon_name_rank, useNA = "ifany")
    cli::cli_inform(c(
      "join_priors: {nrow(fallthrough)} named taxa matched no prior and took the global floor.",
      "i" = "By rank: {paste(sprintf('%s %d', names(by_rank), as.integer(by_rank)), collapse = ', ')}.",
      "i" = "First few: {paste(utils::head(fallthrough$taxon_name, 8L), collapse = ', ')}.",
      "i" = "A taxon here is either genuinely absent from the priors, or filed under a different name than the call uses. The full table is {.code attr(x, \'prior_floor_fallthrough\')}."
    ))
  }

  cli::cli_inform(
    "join_priors: {nrow(result)} row(s) ready for {.fn compute_posterior}."
  )
  result
}
