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
  prior_disp <- stats::setNames(pw$.verbatim, pw$taxon_name)
  prior_disp <- prior_disp[!duplicated(names(prior_disp))]
  # source_taxon_name (a singleton mirror's source species) is a name in the same prior table: key it the same way
  name_to_id <- unique(data.frame(n = as.character(priors$taxon_name), id = as.character(priors$taxon_id), stringsAsFactors = FALSE))
  name_to_id <- name_to_id[!is.na(name_to_id$id) & !duplicated(name_to_id$n), , drop = FALSE]
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
    ri <- which(is_ring & lw$taxon_name_rank %in% rr)
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
    if (length(rk_rows)) ring_rekeyed <- do.call(rbind, rk_rows[!vapply(rk_rows, is.null, TRUE)])
    new_ids <- setdiff(unique(stats::na.omit(lw$taxon_name)), names(anc[[1L]]))
    if (length(new_ids)) {
      anc2 <- .registry_ancestors(new_ids, all_ranks, registry)
      for (r in all_ranks) anc[[r]] <- c(anc[[r]], anc2[[r]])
    }
  }
  for (r in intersect(all_ranks, names(lw))) lw[[r]] <- unname(anc[[r]][lw$taxon_name])
  for (r in intersect(all_ranks, names(pw))) pw[[r]] <- unname(anc[[r]][pw$taxon_name])
  tax_of <- function(tab, taxa) {
    if (is.null(tab)) return(NULL)
    cols <- intersect(all_ranks, names(tab))
    out <- data.frame(taxon_name = taxa, stringsAsFactors = FALSE)
    for (r in cols) out[[r]] <- unname(anc[[r]][taxa])
    out
  }
  pr_ids <- unique(stats::na.omit(pw$taxon_name))
  all_ids <- unique(stats::na.omit(c(lw$taxon_name, pr_ids)))

  # display name per id: the likelihoods' own name where it has exactly one; the registry's accepted name where the
  # likelihoods hold the taxon under 2+ names (those rows are one hypothesis now); else the prior table's kept name
  nn <- table(lik_names$id)
  disp <- stats::setNames(lik_names$n, lik_names$id)[!duplicated(lik_names$id)]
  multi <- names(nn)[nn > 1L]
  disp[multi] <- reg_name[multi]
  extra <- setdiff(names(prior_disp), names(disp))
  disp <- c(disp, prior_disp[extra])

  list(
    likelihoods = lw, priors = pw,
    taxonomy_lookup = tax_of(taxonomy_lookup, all_ids),
    expansion_taxonomy = tax_of(expansion_taxonomy, pr_ids),
    singleton_taxonomy = tax_of(singleton_taxonomy, pr_ids),
    display = disp, reg_name = reg_name, merged_prior_rows = kp$merged, ring_rekeyed = ring_rekeyed,
    counts = list(n_likelihood_rows_no_id = n_lik_no_id, n_prior_names_no_id = kp$n_no_id, n_prior_rows_merged = kp$n_merged,
                  n_likelihood_taxa_under_2plus_names = length(multi),
                  n_ring_rows_rekeyed = sum(ring_rekeyed$outcome %in% "rekeyed"),
                  n_ring_rows_candidates_split = sum(ring_rekeyed$outcome %in% "candidates_split_kept"))
  )
}

# Put names back on join_priors(registry =) output: taxon_id from the working key; taxon_name the display name; every
# lineage column (and the dark-diversity group, a clade) the registry's name for its ancestor id.
.jp_registry_finish <- function(result, rg, stamp) {
  nm <- function(v, pref = rg$reg_name) { v <- as.character(v); o <- unname(pref[v]); keep <- is.na(o); o[keep] <- v[keep]; o }
  result$taxon_id <- as.character(result$taxon_name)
  result$taxon_name <- nm(result$taxon_id, c(rg$display, rg$reg_name[setdiff(names(rg$reg_name), names(rg$display))]))
  for (r in intersect(c("kingdom", "phylum", "class", "order", "family", "genus", "species", "dark_diversity_group", "source_taxon_name"), names(result))) {
    result[[r]] <- nm(result[[r]])
  }
  ft <- attr(result, "prior_floor_fallthrough")
  if (!is.null(ft)) {
    ft$taxon_id <- as.character(ft$taxon_name)
    ft$taxon_name <- nm(ft$taxon_id, c(rg$display, rg$reg_name[setdiff(names(rg$reg_name), names(rg$display))]))
    attr(result, "prior_floor_fallthrough") <- ft
  }
  attr(result, "registry_join_counts") <- rg$counts
  attr(result, "merged_prior_rows") <- rg$merged_prior_rows
  attr(result, "ring_rows_rekeyed") <- rg$ring_rekeyed
  attr(result, "taxon_registry") <- stamp
  result
}
