utils::globalVariables(c("id_x", "id_y"))

# Reference-consistency table for train_likelihood_model(): the existing TaxaMatch reference screen's own
# functions, run on the training matrix (library-internal pairs only, no BLAST, no network), plus one
# stated rule for species with exactly two references. Documented in train_likelihood_model()'s
# "Reference-consistency table" section, which is the place to read the rule.
#
# Reused unchanged from TaxaMatch:
#   corroborate_references_locally()   local_tier (exported)
#   .compute_hierarchy_congruence()    the congruence vote (internal; called with `:::`, and a test pins
#                                      that it exists with the arguments passed here)
#   score_reference_labels()           label_confidence, reference_action, the local-corroboration veto
#   evaluate_reference_accessions()    its formals supply top_n, min_congruent_rank, submission_window and
#                                      the hierarchy_flag thresholds, so the defaults are the screen's own
.rc_columns <- c(
  "accession", "species", "n_references", "local_tier", "n_independent_conspecific",
  "best_independent_pident", "hierarchy_flag", "n_independent_top_matches",
  "frac_independent_below_min_congruent_rank", "best_disagreeing_pident", "best_disagreeing_taxon",
  "label_confidence", "reference_action", "best_disagreeing_pident_species",
  "best_disagreeing_taxon_species", "pair_rule_support", "pair_rule_suspect", "suspect", "excluded"
)

.rc_empty <- function(status) {
  out <- as.data.frame(stats::setNames(replicate(length(.rc_columns), logical(0), simplify = FALSE), .rc_columns))
  attr(out, "status") <- status
  out
}

.reference_consistency <- function(raw_df, rank_system, min_overlap = 0.8, chunk_rows = 1e6) {
  rank_system <- tolower(rank_system)
  need <- c("id_x", "id_y", "p_match", "coverage", "species.x", "species.y")
  miss <- setdiff(need, names(raw_df))
  if (length(miss)) {
    return(.rc_empty(sprintf("not computed: raw_df lacks %s", paste(miss, collapse = ", "))))
  }
  ranks <- rank_system[paste0(rank_system, ".x") %in% names(raw_df) & paste0(rank_system, ".y") %in% names(raw_df)]
  if (!all(c("family", "species") %in% ranks)) {
    return(.rc_empty("not computed: rank_system needs family and species, with .x/.y columns in raw_df"))
  }
  fe <- formals(TaxaMatch::evaluate_reference_accessions)
  top_n <- eval(fe$top_n)
  fam_rank <- eval(fe$min_congruent_rank)
  window <- eval(fe$submission_window)
  min_partners <- eval(fe$min_independent_partners)
  incongruent_at <- eval(fe$hierarchy_incongruent_threshold)

  # one row per reference, with its label
  idx <- as.character(raw_df$id_x)
  idy <- as.character(raw_df$id_y)
  refs <- data.frame(id = c(idx, idy), species = c(as.character(raw_df$species.x), as.character(raw_df$species.y)),
                     stringsAsFactors = FALSE)
  refs <- refs[!duplicated(refs$id), , drop = FALSE]
  n_ref <- table(refs$species)

  # Every quantity here is per reference and depends only on that reference's own pairs, so references are
  # processed in chunks (exact, and memory bounded by the chunk rather than the library). A chunk holds the
  # pairs touching its references, both directions, one row per directed pair (its best).
  rows_x <- split(seq_along(idx), idx)
  rows_y <- split(seq_along(idy), idy)
  deg <- as.numeric(lengths(rows_x[refs$id])) + as.numeric(lengths(rows_y[refs$id]))
  chunk <- cumsum(deg) %/% chunk_rows
  keep <- c("id_x", "id_y", "p_match", "coverage", paste0(ranks, ".x"), paste0(ranks, ".y"))
  parts <- lapply(split(refs$id, chunk), function(ids) {
    rx <- unlist(rows_x[ids], use.names = FALSE)
    ry <- unlist(rows_y[ids], use.names = FALSE)
    touch <- as.data.frame(raw_df[unique(c(rx, ry)), keep, drop = FALSE])
    d1 <- as.data.frame(raw_df[rx, keep, drop = FALSE])
    d2 <- as.data.frame(raw_df[ry, keep, drop = FALSE])
    d2[, c("id_x", "id_y")] <- d2[, c("id_y", "id_x")]
    for (r in ranks) d2[, paste0(r, c(".x", ".y"))] <- d2[, paste0(r, c(".y", ".x"))]
    dd <- rbind(d1, d2)
    rm(d1, d2)
    dd <- dd[dd$id_x != dd$id_y, , drop = FALSE]
    dd <- dd[order(dd$id_x, dd$id_y, -dd$p_match), , drop = FALSE]
    dd <- dd[!duplicated(dd[, c("id_x", "id_y")]), , drop = FALSE]
    meta <- data.frame(composite_id = unique(c(dd$id_x, dd$id_y, ids)), stringsAsFactors = FALSE)
    lc <- TaxaMatch::corroborate_references_locally(touch, meta, min_overlap = min_overlap, submission_window = window)
    lc <- lc[lc$accession %in% sub("\\.[0-9]+$", "", ids), , drop = FALSE]
    congruence <- function(rank) {
      TaxaMatch:::.compute_hierarchy_congruence(
        dd, meta,
        rank_system = ranks, top_n = top_n, min_congruent_rank = rank,
        submission_window = window, min_coverage = min_overlap, require_species_resolved_partner = TRUE
      )
    }
    fam <- congruence(fam_rank)
    fam <- fam[fam$id_x %in% ids, , drop = FALSE]
    attr(fam, "pair_table") <- NULL
    spc <- congruence("species")
    pt <- attr(spc, "pair_table")
    spc <- spc[spc$id_x %in% ids, c("id_x", "best_disagreeing_pident", "best_disagreeing_taxon"), drop = FALSE]
    # support: the species-rank vote's own valid partners (independent, at coverage, species-resolved)
    # carrying the best disagreeing taxon's label
    hit <- !is.na(pt$species_y) & pt$species_y == spc$best_disagreeing_taxon[match(pt$id_x, spc$id_x)]
    hit[is.na(hit)] <- FALSE
    su <- unique(pt[hit, c("id_x", "id_y"), drop = FALSE])
    spc$support <- as.integer(table(factor(su$id_x, levels = spc$id_x))[spc$id_x])
    list(lc = lc, fam = fam, spc = spc)
  })
  lc <- do.call(rbind, lapply(parts, `[[`, "lc"))
  fam <- do.call(rbind, lapply(parts, `[[`, "fam"))
  spc <- do.call(rbind, lapply(parts, `[[`, "spc"))
  rm(parts)
  # the screen's hierarchy_flag rule, at the screen's own thresholds
  fam$hierarchy_flag <- ifelse(
    fam$n_independent_top_matches < min_partners, "insufficient_independent_evidence",
    ifelse(fam$frac_independent_below_min_congruent_rank >= incongruent_at, "incongruent", "congruent")
  )
  ev <- fam
  names(ev)[names(ev) == "id_x"] <- "accession"
  sc <- TaxaMatch::score_reference_labels(ev, local_corroboration = lc)

  out <- data.frame(accession = refs$id, species = refs$species, stringsAsFactors = FALSE)
  out$n_references <- as.integer(n_ref[out$species])
  lk <- match(sub("\\.[0-9]+$", "", out$accession), lc$accession)
  out$local_tier <- lc$local_tier[lk]
  out$n_independent_conspecific <- lc$n_independent_conspecific[lk]
  out$best_independent_pident <- lc$best_independent_pident[lk]
  k <- match(out$accession, sc$accession)
  for (col in c("hierarchy_flag", "n_independent_top_matches", "frac_independent_below_min_congruent_rank",
                "best_disagreeing_pident", "best_disagreeing_taxon", "label_confidence", "reference_action")) {
    out[[col]] <- sc[[col]][k]
  }
  ks <- match(out$accession, spc$id_x)
  out$best_disagreeing_pident_species <- spc$best_disagreeing_pident[ks]
  out$best_disagreeing_taxon_species <- spc$best_disagreeing_taxon[ks]
  out$pair_rule_support <- spc$support[ks]
  out$pair_rule_support[is.na(out$pair_rule_support)] <- 0L

  # The pair rule (two-reference species, both "disagree"): the suspect is the member whose best
  # disagreeing species is matched at a strictly higher identity than its partner's, and supported by at
  # least two references of that species. Anything else stays unresolved.
  out$pair_rule_suspect <- FALSE
  two <- which(out$n_references == 2L)
  for (i in split(two, out$species[two])) {
    if (length(i) != 2L || !all(out$local_tier[i] %in% "disagree")) next
    p <- out$best_disagreeing_pident_species[i]
    p[is.na(p)] <- -Inf
    if (p[1L] == p[2L]) next
    w <- i[which.max(p)]
    if (out$pair_rule_support[w] >= 2L) out$pair_rule_suspect[w] <- TRUE
  }
  out$suspect <- out$reference_action %in% "remove" | out$pair_rule_suspect
  out$excluded <- FALSE
  out <- out[order(out$accession), .rc_columns, drop = FALSE]
  rownames(out) <- NULL
  attr(out, "status") <- "computed"
  out
}
