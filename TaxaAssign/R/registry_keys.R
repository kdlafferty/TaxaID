# registry_keys.R
# TaxaAssign package
#
# Shared internals for the `registry =` arguments: tables keyed by taxon_id, lineage from the registry's own tree.

# Refuse a registry that is not frozen, and a table that carries no taxon_id or another registry's stamp.
.registry_check_tables <- function(registry, tables) {
  if (!inherits(registry, "taxon_registry")) cli::cli_abort("{.arg registry} must be a {.cls taxon_registry} (TaxaTools::build_taxon_registry()).")
  if (!isTRUE(registry$meta$frozen)) cli::cli_abort("{.arg registry} must be frozen (TaxaTools::freeze_taxon_registry()).")
  for (a in names(tables)) {
    x <- tables[[a]]
    s <- attr(x, "taxon_registry", exact = TRUE)
    if (!"taxon_id" %in% names(x) || is.null(s)) {
      cli::cli_abort("{.arg {a}} has no {.field taxon_id} column or no registry stamp: attach ids with TaxaTools::attach_taxon_ids() before the call.")
    }
    if (!identical(s$digest, registry$meta$digest)) cli::cli_abort("{.arg {a}} was stamped by a different registry than {.arg registry}.")
  }
  invisible(TRUE)
}

# Ancestor ids of `ids` at each of `ranks` (a taxon AT a rank returns itself), as a named list of named vectors.
.registry_ancestors <- function(ids, ranks, registry) {
  ids <- unique(stats::na.omit(as.character(ids)))
  lapply(stats::setNames(ranks, ranks), function(r) stats::setNames(TaxaTools::parent_at(ids, r, registry), ids))
}

# Member clades of tied-anchor rings, listed by NAME, to one registry id each: through the registry's names table, else
# its accepted names. A name with no id, or with two, maps to NA (never guessed). Named by the input names.
.registry_member_ids <- function(member_names, registry) {
  mn <- unique(stats::na.omit(as.character(member_names)))
  out <- stats::setNames(rep(NA_character_, length(mn)), mn)
  if (!length(mn)) return(out)
  nt <- registry$names[!is.na(registry$names$verbatim_name) & !is.na(registry$names$taxon_id), c("verbatim_name", "taxon_id")]
  nt <- unique(rbind(nt, data.frame(verbatim_name = registry$taxa$name, taxon_id = registry$taxa$taxon_id, stringsAsFactors = FALSE)))
  nt <- nt[nt$verbatim_name %in% mn, , drop = FALSE]
  n_ids <- tapply(nt$taxon_id, nt$verbatim_name, function(x) length(unique(x)))
  one <- names(n_ids)[n_ids == 1L]
  out[one] <- nt$taxon_id[match(one, nt$verbatim_name)]
  out
}

# A prior table keyed by id: `taxon_name` holds the taxon_id, `.verbatim` the table's own name. A row whose name has no
# id (a placeholder or floor row the registry does not hold) keeps its own name, which can never equal an id, so it
# joins nothing by taxon and its other roles (dark-diversity rows, floors) are unchanged. Rows of one taxon at one
# (site, habitat, rank) are reduced to one: the row under the registry's accepted name, else the strongest
# (`theta_col`, or alpha / (alpha + beta) where that column is absent). Returns the table, the rows set aside, and the
# count of names with no id.
.registry_key_priors <- function(priors, registry, theta_col = "theta_mean") {
  reg_name <- stats::setNames(registry$taxa$name, registry$taxa$taxon_id)
  pw <- as.data.frame(priors)
  pw$.verbatim <- as.character(pw$taxon_name)
  pw$.ord <- seq_len(nrow(pw))
  no_id <- is.na(pw$taxon_id) & !is.na(pw$.verbatim)
  n_no_id <- length(unique(pw$.verbatim[no_id]))
  pw$taxon_name <- ifelse(no_id, pw$.verbatim, as.character(pw$taxon_id))
  keyed <- !is.na(pw$taxon_id)
  site_cols <- intersect(c("grid_id", "main_habitat"), names(pw))
  acc <- keyed & pw$.verbatim == unname(reg_name[pw$taxon_name])
  acc[is.na(acc)] <- FALSE
  th <- if (theta_col %in% names(pw)) pw[[theta_col]] else if (all(c("alpha", "beta") %in% names(pw))) pw$alpha / (pw$alpha + pw$beta) else rep(0, nrow(pw))
  th[!is.finite(th)] <- -Inf
  ord <- order(!acc, -th)
  pw <- pw[ord, , drop = FALSE]; keyed <- keyed[ord]
  key <- do.call(paste, c(pw[c(site_cols, "taxon_name", intersect("taxon_name_rank", names(pw)))], sep = "\r"))
  dup <- keyed & (duplicated(key) | duplicated(key, fromLast = TRUE))
  merged <- pw[dup, c(site_cols, "taxon_name", ".verbatim", intersect(theta_col, names(pw))), drop = FALSE]
  names(merged)[names(merged) == "taxon_name"] <- "taxon_id"
  names(merged)[names(merged) == ".verbatim"] <- "taxon_name"
  n_merged <- sum(dup) - length(unique(key[dup]))
  pw <- pw[!(keyed & duplicated(key)), , drop = FALSE]
  # original row order for the rows kept (callers that care about order see the input's)
  pw <- pw[order(pw$.ord), , drop = FALSE]
  pw$.ord <- NULL
  list(priors = pw, merged = merged, n_no_id = n_no_id, n_merged = n_merged)
}

# join_priors(registry =): working copies keyed by taxon_id. `taxon_name` of every table holds the taxon_id; every
# lineage column a table already carries holds the ancestor id from the registry's tree (so families come from the
# registry, never from a table's own column); the taxonomy tables keep the rank columns the caller supplied, rebuilt
# from the registry over the same taxa. Returns the copies and what .jp_registry_finish() needs to restore names.
.jp_registry_inputs <- function(likelihoods, priors, taxonomy_lookup, expansion_taxonomy, singleton_taxonomy, registry) {
  .registry_check_tables(registry, list(likelihoods = likelihoods, taxaexpect_priors = priors))
  all_ranks <- c("kingdom", "phylum", "class", "order", "family", "genus", "species")
  reg_name <- stats::setNames(registry$taxa$name, registry$taxa$taxon_id)
  kp <- .registry_key_priors(priors, registry)
  pw <- kp$priors
  # source_taxon_name (a singleton mirror's source species) is a name in the same prior table: key it the same way
  name_to_id <- unique(data.frame(n = as.character(priors$taxon_name), id = as.character(priors$taxon_id), stringsAsFactors = FALSE))
  name_to_id <- name_to_id[!is.na(name_to_id$id) & !duplicated(name_to_id$n), , drop = FALSE]
  # a source species that is not itself a prior row: the registry's own name table (names registered to one id only)
  rn <- unique(registry$names[!is.na(registry$names$taxon_id), c("verbatim_name", "taxon_id")])
  rn <- rn[!rn$verbatim_name %in% rn$verbatim_name[duplicated(rn$verbatim_name)], , drop = FALSE]
  rn <- rn[!rn$verbatim_name %in% name_to_id$n, , drop = FALSE]
  name_to_id <- rbind(name_to_id, data.frame(n = rn$verbatim_name, id = rn$taxon_id, stringsAsFactors = FALSE))
  if ("source_taxon_name" %in% names(pw)) {
    pw$source_taxon_name <- name_to_id$id[match(as.character(pw$source_taxon_name), name_to_id$n)]
  }
  pw$.verbatim <- NULL
  pw$taxon_id <- NULL

  lw <- as.data.frame(likelihoods)
  lik_names <- unique(data.frame(id = as.character(lw$taxon_id), n = as.character(lw$taxon_name), stringsAsFactors = FALSE))
  lik_names <- lik_names[!is.na(lik_names$id), , drop = FALSE]
  n_lik_no_id <- sum(is.na(lw$taxon_id) & !is.na(lw$taxon_name))
  lw$taxon_name <- as.character(lw$taxon_id)
  lw$taxon_id <- NULL

  ids <- unique(c(lw$taxon_name, pw$taxon_name, pw$source_taxon_name %||% character(0)))
  anc <- .registry_ancestors(ids, all_ranks, registry)
  # A ring row (an unreferenced hypothesis above species) stands for the clade of the candidates it was built from: the
  # candidates in its observation whose OWN lineage column at the ring's rank names the ring. Its id is their registry
  # ancestor at that rank when they agree on one, so the ring and its candidates sit in one clade of the registry's
  # tree (an NCBI family ring "Leuciscidae" over genera the registry places in Cyprinidae becomes the Cyprinidae ring).
  # Where those candidates map to 2+ registry taxa, or there are none, the ring keeps the id of its own name; listed.
  ring_rekeyed <- NULL
  if ("hypothesis_type" %in% names(lw)) {
    orig <- as.data.frame(likelihoods)
    is_ring <- !lw$hypothesis_type %in% "specific_candidate" & !is.na(lw$taxon_name) &
      lw$taxon_name_rank %in% setdiff(all_ranks, "species")
    cand <- lw$hypothesis_type %in% "specific_candidate" & !is.na(lw$taxon_name)
    # a candidate's own-source lineage: the likelihoods' column where present, else the caller's taxonomy_lookup (the
    # name path fills lineage from it), matched by the candidate's own name
    tl <- if (is.data.frame(taxonomy_lookup) && "taxon_name" %in% names(taxonomy_lookup)) {
      as.data.frame(taxonomy_lookup)[!duplicated(taxonomy_lookup$taxon_name), , drop = FALSE]
    } else NULL
    own_lin <- function(r, idx) {
      v <- if (r %in% names(orig)) as.character(orig[[r]][idx]) else rep(NA_character_, length(idx))
      if (!is.null(tl) && r %in% names(tl)) {
        f <- is.na(v)
        v[f] <- as.character(tl[[r]][match(as.character(orig$taxon_name[idx[f]]), tl$taxon_name)])
      }
      v
    }
    rr <- setdiff(all_ranks, "species")
    rr <- rr[vapply(rr, function(r) r %in% names(orig) || (!is.null(tl) && r %in% names(tl)), TRUE)]
    ci <- which(cand)
    cl <- do.call(rbind, lapply(rr, function(r) data.frame(obs = as.character(lw$observation_id[ci]), rank = rep(r, length(ci)),
      ring = own_lin(r, ci), anc = unname(anc[[r]][lw$taxon_name[ci]]), stringsAsFactors = FALSE)))
    if (is.null(cl)) cl <- data.frame(obs = character(0), rank = character(0), ring = character(0), anc = character(0), stringsAsFactors = FALSE)
    cl <- unique(cl[!is.na(cl$ring) & !is.na(cl$anc), , drop = FALSE])
    key_c <- paste(cl$obs, cl$rank, cl$ring, sep = "\r")
    per <- split(cl$anc, key_c)
    # a tied-anchor ring (ring_member_clades set) is keyed below, at the registry LCA of its member clades
    is_lca <- if ("ring_member_clades" %in% names(orig)) !is.na(orig$ring_member_clades) & !lw$hypothesis_type %in% "specific_candidate" else rep(FALSE, nrow(lw))
    ri <- which(is_ring & lw$taxon_name_rank %in% rr & !is_lca)
    key_r <- paste(lw$observation_id[ri], lw$taxon_name_rank[ri], as.character(orig$taxon_name[ri]), sep = "\r")
    got <- per[key_r]
    n_a <- lengths(got)
    one <- n_a == 1L & !vapply(got, is.null, TRUE)
    to1 <- vapply(got, function(v) if (length(v) == 1L) v else NA_character_, "")
    chg <- one & !is.na(to1) & to1 != lw$taxon_name[ri]
    spl <- n_a > 1L
    rk_rows <- list()
    if (any(chg)) rk_rows[[1L]] <- data.frame(observation_id = lw$observation_id[ri[chg]], ring = as.character(orig$taxon_name[ri[chg]]),
      rank = as.character(lw$taxon_name_rank[ri[chg]]), from_id = lw$taxon_name[ri[chg]], to_id = to1[chg], outcome = "rekeyed", stringsAsFactors = FALSE)
    if (any(spl)) rk_rows[[2L]] <- data.frame(observation_id = lw$observation_id[ri[spl]], ring = as.character(orig$taxon_name[ri[spl]]),
      rank = as.character(lw$taxon_name_rank[ri[spl]]), from_id = lw$taxon_name[ri[spl]],
      to_id = vapply(got[spl], paste, "", collapse = "|"), outcome = "candidates_split_kept", stringsAsFactors = FALSE)
    lw$taxon_name[ri[chg]] <- to1[chg]
    # A tied-anchor ring: TaxaLikely named it at the lowest common rank of its tied candidates in the likelihoods' own
    # lineage (ring_lca_status "lca"), or kept the anchor's label where none was common ("anchor_fallback"), and listed
    # their clades at the ring's own rank. Here it takes the registry's (GBIF's) lowest common
    # ancestor of the observation's candidates in those clades: the finest rank, from the ring's own rank upwards, at
    # which they share ONE registry ancestor. Its id and taxon_name_rank follow the registry, finer or coarser than the
    # likelihoods' label; with no common ancestor the row keeps the id of its own name. Listed, outcome "lca_registry".
    # The registry's lineage stands in where a candidate's is missing. A candidate with no registry id, or with a
    # run-local id the registry could not place (no ancestor at the ring's rank or above), says nothing about where its
    # clade sits: it is missing data, not a second lineage, and is left out of the search. A member clade whose
    # candidates are all left out is then represented by the registry's own taxon of that name, under the rule
    # add_unreferenced_prior_mass() uses for member clades (exactly one id, at the ring's own rank). A member clade
    # that has neither is not guessed: the ring keeps its own id ("lca_registry_none"). A member clade with no
    # candidate in the observation at all is not read. The rows rekeyed list how many
    # candidates were left out (n_unplaced_candidates) and which member clades took the registry's own taxon
    # (member_clades_from_registry).
    li <- which(is_lca)
    if (length(li)) {
      own_rank <- .unreferenced_ring_rank(lw$hypothesis_type[li])
      member_id <- .registry_member_ids(unlist(strsplit(stats::na.omit(as.character(orig$ring_member_clades[li])), "|", fixed = TRUE)),
                                        registry)
      new_m <- setdiff(stats::na.omit(unname(member_id)), names(anc[[1L]]))
      if (length(new_m)) {
        anc_m <- .registry_ancestors(new_m, all_ranks, registry)
        for (r in all_ranks) anc[[r]] <- c(anc[[r]], anc_m[[r]])
      }
      reg_rank <- stats::setNames(registry$taxa$rank, registry$taxa$taxon_id)
      ca <- which(lw$hypothesis_type %in% "specific_candidate")
      lca_rows <- lapply(seq_along(li), function(k) {
        i <- li[k]; mr <- own_rank[k]
        if (is.na(mr) || !mr %in% all_ranks) return(NULL)
        mem <- strsplit(as.character(orig$ring_member_clades[i]), "|", fixed = TRUE)[[1L]]
        # every candidate of the observation, with or without an id: one with no id is unplaced like a run-local id
        # with no ancestor, so its member clade is never silently dropped (which made the LCA finer than the ring)
        co <- ca[as.character(lw$observation_id[ca]) == as.character(lw$observation_id[i])]
        own <- own_lin(mr, co)
        sel <- co[own %in% mem]
        own <- own[own %in% mem]
        up <- rev(all_ranks[seq_len(match(mr, all_ranks))])   # the ring's own rank, then coarser
        cid_sel <- lw$taxon_name[sel]
        placed <- !is.na(cid_sel) & vapply(cid_sel, function(x) !is.na(x) && any(!is.na(vapply(up, function(r) unname(anc[[r]][x]), ""))), TRUE)
        cid <- unique(cid_sel[placed])
        n_unplaced <- length(unique(stats::na.omit(cid_sel[!placed]))) + sum(is.na(cid_sel))
        bare <- setdiff(intersect(mem, own), own[placed])   # member clades whose candidates are all unplaced
        bare_id <- unname(member_id[bare])
        bare_ok <- vapply(bare_id, function(x) !is.na(x) && identical(unname(reg_rank[x]), mr), TRUE)
        to <- NA_character_; to_rank <- NA_character_
        if (all(bare_ok)) {
          ids <- unique(c(cid, bare_id))
          if (length(ids)) for (r in up) {
            a <- unique(unname(anc[[r]][ids]))
            if (length(a) == 1L && !is.na(a)) { to <- a; to_rank <- r; break }
          }
        }
        data.frame(row = i, observation_id = lw$observation_id[i], ring = as.character(orig$taxon_name[i]),
                   rank = as.character(lw$taxon_name_rank[i]), from_id = lw$taxon_name[i], to_id = to, to_rank = to_rank,
                   n_member_candidates = length(cid), n_unplaced_candidates = as.integer(n_unplaced),
                   member_clades_from_registry = if (length(bare)) paste(bare, collapse = "|") else NA_character_,
                   outcome = if (is.na(to)) "lca_registry_none" else "lca_registry", stringsAsFactors = FALSE)
      })
      lr <- do.call(rbind, lca_rows[!vapply(lca_rows, is.null, TRUE)])
      if (!is.null(lr) && nrow(lr)) {
        ok <- !is.na(lr$to_id)
        lw$taxon_name[lr$row[ok]] <- lr$to_id[ok]
        lw$taxon_name_rank[lr$row[ok]] <- lr$to_rank[ok]
        # an "lca" or "anchor_fallback" ring the registry names at its common ancestor: recorded in the status
        if ("ring_lca_status" %in% names(lw)) lw$ring_lca_status[lr$row[ok]] <- "lca_registry"
        rk_rows[[3L]] <- lr[, setdiff(names(lr), "row")]
      }
    }
    if (length(rk_rows)) ring_rekeyed <- do.call(rbind, lapply(rk_rows[!vapply(rk_rows, is.null, TRUE)], function(d) {
      for (cc in setdiff(c("to_rank", "n_member_candidates", "n_unplaced_candidates", "member_clades_from_registry"), names(d))) d[[cc]] <- NA
      d
    }))
    new_ids <- setdiff(unique(stats::na.omit(lw$taxon_name)), names(anc[[1L]]))
    if (length(new_ids)) {
      anc2 <- .registry_ancestors(new_ids, all_ranks, registry)
      for (r in all_ranks) anc[[r]] <- c(anc[[r]], anc2[[r]])
    }
  }
  for (r in intersect(all_ranks, names(lw))) lw[[r]] <- unname(anc[[r]][lw$taxon_name])
  # prior rows: a row with an id takes its own ancestors; a singleton mirror (no taxon of its own) takes its source
  # species' ancestors; any other row keeps the lineage it came with
  pr_key <- ifelse(pw$taxon_name %in% registry$taxa$taxon_id, pw$taxon_name,
                   if ("source_taxon_name" %in% names(pw)) as.character(pw$source_taxon_name) else NA_character_)
  has_key <- !is.na(pr_key) & pr_key %in% registry$taxa$taxon_id
  for (r in intersect(all_ranks, names(pw))) pw[[r]][has_key] <- unname(anc[[r]][pr_key[has_key]])
  tax_of <- function(tab, taxa) {
    if (is.null(tab)) return(NULL)
    cols <- intersect(all_ranks, names(tab))
    out <- data.frame(taxon_name = taxa, stringsAsFactors = FALSE)
    for (r in cols) out[[r]] <- unname(anc[[r]][taxa])
    out
  }
  pr_ids <- unique(stats::na.omit(pw$taxon_name))
  all_ids <- unique(stats::na.omit(c(lw$taxon_name, pr_ids)))

  # Output names are the registry's accepted names (GBIF by default), derived from taxon_id: the name is a display
  # column, never the key. Each likelihood row's own name(s) are kept as taxon_name_verbatim, per observation and id:
  # the id the row ends up under (lw holds the likelihoods' rows in order), so a rekeyed ring keeps its own name.
  nn <- table(lik_names$id)
  multi <- names(nn)[nn > 1L]
  disp <- reg_name
  vb <- unique(data.frame(k = paste(as.character(likelihoods$observation_id), as.character(lw$taxon_name), sep = "\r"),
                          n = as.character(likelihoods$taxon_name), stringsAsFactors = FALSE))
  vb <- vb[!is.na(vb$n), , drop = FALSE]
  verbatim <- vapply(split(vb$n, vb$k), function(v) paste(sort(unique(v)), collapse = " | "), "")

  list(
    likelihoods = lw, priors = pw,
    taxonomy_lookup = tax_of(taxonomy_lookup, all_ids),
    expansion_taxonomy = tax_of(expansion_taxonomy, pr_ids),
    singleton_taxonomy = tax_of(singleton_taxonomy, pr_ids),
    display = disp, reg_name = reg_name, verbatim = verbatim, merged_prior_rows = kp$merged, ring_rekeyed = ring_rekeyed,
    counts = list(n_likelihood_rows_no_id = n_lik_no_id, n_prior_names_no_id = kp$n_no_id, n_prior_rows_merged = kp$n_merged,
                  n_likelihood_taxa_under_2plus_names = length(multi),
                  n_ring_rows_rekeyed = sum(ring_rekeyed$outcome %in% "rekeyed"),
                  n_ring_rows_candidates_split = sum(ring_rekeyed$outcome %in% "candidates_split_kept"),
                  n_lca_rings_registry = sum(ring_rekeyed$outcome %in% "lca_registry"),
                  n_lca_rings_registry_none = sum(ring_rekeyed$outcome %in% "lca_registry_none"))
  )
}

# Put names back on join_priors(registry =) output: taxon_id from the working key; taxon_name the display name; every
# lineage column (and the dark-diversity group, a clade) the registry's name for its ancestor id.
.jp_registry_finish <- function(result, rg, stamp) {
  nm <- function(v, pref = rg$reg_name) { v <- as.character(v); o <- unname(pref[v]); keep <- is.na(o); o[keep] <- v[keep]; o }
  result$taxon_id <- as.character(result$taxon_name)
  result$taxon_name <- nm(result$taxon_id, rg$display)
  result$taxon_name_verbatim <- unname(rg$verbatim[paste(as.character(result$observation_id), result$taxon_id, sep = "\r")])
  for (r in intersect(c("kingdom", "phylum", "class", "order", "family", "genus", "species", "dark_diversity_group", "source_taxon_name"), names(result))) {
    result[[r]] <- nm(result[[r]])
  }
  ft <- attr(result, "prior_floor_fallthrough")
  if (!is.null(ft)) {
    ft$taxon_id <- as.character(ft$taxon_name)
    ft$taxon_name <- nm(ft$taxon_id, rg$display)
    attr(result, "prior_floor_fallthrough") <- ft
  }
  attr(result, "registry_join_counts") <- rg$counts
  attr(result, "merged_prior_rows") <- rg$merged_prior_rows
  attr(result, "ring_rows_rekeyed") <- rg$ring_rekeyed
  attr(result, "taxon_registry") <- stamp
  result
}

# A table that has passed through functions outside the registry's reach (compute_posterior()) may have lost its stamp;
# what it must still hold is a taxon_id column whose ids all belong to `registry`.
.registry_check_ids <- function(x, registry, arg) {
  if (!inherits(registry, "taxon_registry")) cli::cli_abort("{.arg registry} must be a {.cls taxon_registry} (TaxaTools::build_taxon_registry()).")
  if (!isTRUE(registry$meta$frozen)) cli::cli_abort("{.arg registry} must be frozen (TaxaTools::freeze_taxon_registry()).")
  if (!"taxon_id" %in% names(x)) cli::cli_abort("{.arg {arg}} has no {.field taxon_id} column: run join_priors() with the same {.arg registry}.")
  s <- attr(x, "taxon_registry", exact = TRUE)
  if (!is.null(s) && !identical(s$digest, registry$meta$digest)) cli::cli_abort("{.arg {arg}} was stamped by a different registry than {.arg registry}.")
  bad <- setdiff(stats::na.omit(as.character(x$taxon_id)), registry$taxa$taxon_id)
  if (length(bad)) cli::cli_abort("{.arg {arg}} holds {length(bad)} taxon id(s) that {.arg registry} does not (e.g. {.val {utils::head(bad, 3)}}): another registry's ids?")
  invisible(TRUE)
}

# The cross-phylum rule's lineage map (phylum name -> root-to-phylum path of names), read from the registry's tree.
.registry_phylum_lineage_map <- function(phyla, registry) {
  phyla <- unique(phyla[!is.na(phyla) & nzchar(phyla)])
  t <- registry$taxa
  par <- stats::setNames(t$parent_id, t$taxon_id); nm <- stats::setNames(t$name, t$taxon_id)
  out <- stats::setNames(vector("list", length(phyla)), phyla)
  for (p in phyla) {
    id <- t$taxon_id[t$name %in% p & t$rank %in% "phylum"][1]
    if (is.na(id)) next
    path <- character(0); k <- 0L
    while (!is.na(id) && k < 100L) { path <- c(unname(nm[id]), path); id <- unname(par[id]); k <- k + 1L }
    out[[p]] <- path
  }
  out[!vapply(out, is.null, logical(1))]
}

# Names of a caller's table resolved to registry ids: the registry's name table first (a name registered to one id), then
# its taxa by accepted name. A name held under 2+ ids is narrowed by `ranks` (the taxon's rank in the registry) where
# that leaves one. Returns the ids (NA where unresolved) with attribute "unresolved": the names with no single id.
.registry_resolve_names <- function(nm, ranks, registry) {
  nm <- as.character(nm); ranks <- if (is.null(ranks)) rep(NA_character_, length(nm)) else rep_len(as.character(ranks), length(nm))
  rn <- unique(registry$names[!is.na(registry$names$taxon_id), c("verbatim_name", "taxon_id")])
  by_name <- split(as.character(rn$taxon_id), rn$verbatim_name)
  by_acc <- split(as.character(registry$taxa$taxon_id), registry$taxa$name)
  rk_of <- stats::setNames(as.character(registry$taxa$rank), registry$taxa$taxon_id)
  key <- paste(nm, ranks, sep = "\r")
  u <- !duplicated(key) & !is.na(nm)
  one <- vapply(which(u), function(i) {
    ids <- by_name[[nm[i]]] %||% by_acc[[nm[i]]] %||% character(0)
    if (length(ids) > 1L && !is.na(ranks[i])) { r <- ids[rk_of[ids] %in% ranks[i]]; if (length(r)) ids <- r }
    if (length(ids) == 1L) ids else NA_character_
  }, "")
  out <- unname(stats::setNames(one, key[u])[key])
  out[is.na(nm)] <- NA_character_
  attr(out, "unresolved") <- unique(nm[!is.na(nm) & is.na(out)])
  out
}

.registry_abort_unresolved <- function(bad, arg) {
  if (!length(bad)) return(invisible(TRUE))
  cli::cli_abort(c("{length(bad)} name(s) in {.arg {arg}} have no single id in {.arg registry} (e.g. {.val {utils::head(bad, 5)}}).",
    "i" = "Register the table's names before the freeze, as {.fn TaxaTools::attach_taxon_ids} requires; a name the registry does not hold would otherwise silently match nothing."))
}

# posterior_consensus(registry =): group_priors renamed to the registry's accepted name of each group's id, so a group
# filed under a synonym or a superseded name meets the consensus the registry names; groups that land on one (rank, id)
# are summed (theta_sum capped at 1, as compute_group_priors() caps it).
.registry_group_priors <- function(gp, registry) {
  reg_name <- stats::setNames(registry$taxa$name, registry$taxa$taxon_id)
  id <- if ("taxon_id" %in% names(gp)) {
    bad <- setdiff(stats::na.omit(as.character(gp$taxon_id)), registry$taxa$taxon_id)
    if (length(bad)) cli::cli_abort("{.arg group_priors} holds {length(bad)} taxon id(s) that {.arg registry} does not (e.g. {.val {utils::head(bad, 3)}}).")
    as.character(gp$taxon_id)
  } else {
    r <- .registry_resolve_names(gp$taxon, gp$rank, registry)
    .registry_abort_unresolved(attr(r, "unresolved"), "group_priors"); r
  }
  gp <- as.data.frame(gp)
  gp$taxon_id <- id
  gp$taxon <- ifelse(is.na(id), as.character(gp$taxon), unname(reg_name[id]))
  k <- paste(gp$rank, gp$taxon, sep = "\r")
  if (anyDuplicated(k)) {
    th <- vapply(split(gp$theta_sum, k), sum, 0)
    nmem <- if ("n_members" %in% names(gp)) vapply(split(gp$n_members, k), sum, 0) else NULL
    gp <- gp[!duplicated(k), , drop = FALSE]; k1 <- k[!duplicated(k)]
    gp$theta_sum <- pmin(unname(th[k1]), 1)
    if (!is.null(nmem)) gp$n_members <- as.integer(unname(nmem[k1]))
  }
  rownames(gp) <- NULL
  gp
}

# posterior_consensus(registry =): species_reference on the registry's names and tree. The finest column (taxon_name,
# else species) becomes the accepted name of its id, and every coarser rank column the reference carries becomes that
# id's ancestor in the registry's tree, so downranking walks the same tree the consensus was formed on.
.registry_species_reference <- function(sr, registry) {
  if (inherits(sr, "unreferenced_species_result")) sr <- .build_species_ref(sr, "species")
  if (is.null(sr)) return(NULL)
  sr <- as.data.frame(sr)
  fin <- if ("taxon_name" %in% names(sr)) "taxon_name" else if ("species" %in% names(sr)) "species" else return(sr)
  id <- .registry_resolve_names(sr[[fin]], "species", registry)
  .registry_abort_unresolved(attr(id, "unresolved"), "species_reference")
  reg_name <- stats::setNames(registry$taxa$name, registry$taxa$taxon_id)
  sr[[fin]] <- unname(reg_name[id])
  for (r in setdiff(intersect(c("kingdom", "phylum", "class", "order", "family", "genus", "species"), names(sr)), fin)) {
    sr[[r]] <- unname(reg_name[TaxaTools::parent_at(id, r, registry)])
  }
  unique(sr)
}
