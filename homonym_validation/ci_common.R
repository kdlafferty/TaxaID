# Shared by ci_stage1_round1.R and ci_stage2_final.R.  Usage of either script:
#   Rscript ci_stageN_*.R <posterior_extract.rds> <new_lineage_table.rds> [out_prefix]
# Optional environment variables:
#   CI_DIR            CalIntertidal dir (default: the Drive dir)
#   CI_CONSENSUS      saved consensus file (default <CI_DIR>/CalIntertidal_consensus_final_esv_site.rds); its
#                     attr "consensus_settings" supplies species_reference and the other settings; its
#                     consensus_taxon / consensus_rank / consensus_limit (Round 2) and consensus_taxon_v1 /
#                     consensus_rank_v1 (Round 1) are the saved calls
#   CI_TOUCHED        touched-unit csv (observation_id column); default the m26_homonym_units.csv path
#   CI_OLD_LINEAGE    optional OLD lineage table to overlay before the reproduction run. Default: none, because
#                     the saved posteriors already carry the OLD phylum/class/order (the workflow's .apply_lineage()
#                     joined them on taxon_name before compute_posterior()).
#   CI_LOOKUP         "TRUE" to use lookup_missing_taxonomy = TRUE (needs CI_TAXONOMY_CACHE). Default FALSE.
#   CI_TAXONOMY_CACHE taxonomy cache dir for CI_LOOKUP=TRUE
#   CI_NCTRL          control count (default 200)
# The lineage table does NOT enter posterior_consensus(): the workflow joins phylum/class/order/lineage_backbone
# onto the likelihood rows by taxon_name (.apply_lineage, multi_marker.R ~l.3777) BEFORE compute_posterior().
# So "re-run under the new lineage table" = overlay the new table on the posterior rows, then posterior_consensus().
.libPaths(c(path.expand(Sys.getenv("R_LIBS_USER")), .libPaths()))
suppressMessages({ devtools::load_all("TaxaTools", quiet = TRUE); devtools::load_all("TaxaAssign", quiet = TRUE) })

ci_env <- function(k, d) { v <- Sys.getenv(k, ""); if (nzchar(v)) v else d }

overlay_lineage <- function(df, L) {
  L <- as.data.frame(L)
  if (anyDuplicated(L$taxon_name)) stop("lineage table has duplicated taxon_name; this overlay joins on taxon_name exactly as the workflow does")
  keep <- intersect(c("phylum", "class", "order", "lineage_backbone"), names(L))
  nm <- unique(df$taxon_name[!is.na(df$taxon_name) & !grepl("^unk_", df$taxon_name)])
  miss <- setdiff(nm, L$taxon_name)
  if (length(miss)) message(sprintf("  lineage overlay: %d taxon name(s) absent from the table (ranks go NA): %s", length(miss), paste(head(miss, 5), collapse = ", ")))
  df <- df[, setdiff(names(df), c("phylum", "class", "order", "lineage_backbone")), drop = FALSE]
  i <- match(df$taxon_name, L$taxon_name)
  for (k in keep) df[[k]] <- L[[k]][i]
  df
}

ci_run <- function(stage, argv) {
  stopifnot(length(argv) >= 2)
  ext_path <- argv[1]; lin_path <- argv[2]
  outp <- if (length(argv) >= 3) argv[3] else file.path("homonym_validation", paste0("ci_", stage))
  D <- ci_env("CI_DIR", "/Users/lafferty/My Drive/Rscripts/eDNA/CaliforniaIntertidal")
  cons_path <- ci_env("CI_CONSENSUS", file.path(D, "CalIntertidal_consensus_final_esv_site.rds"))
  touched_path <- ci_env("CI_TOUCHED", "/private/tmp/claude-501/-Users-lafferty/89188ade-2bbd-41c4-9a80-7cabae178c87/scratchpad/m26_homonym_units.csv")
  nctrl <- as.integer(ci_env("CI_NCTRL", "200"))
  lookup <- identical(toupper(ci_env("CI_LOOKUP", "FALSE")), "TRUE")
  out <- character(); say <- function(...) { l <- sprintf(...); cat(l, "\n"); out <<- c(out, l) }

  saved <- readRDS(cons_path)
  S <- attr(saved, "consensus_settings")
  tc <- if (stage == 1) c("consensus_taxon_v1", "consensus_rank_v1") else c("consensus_taxon", "consensus_rank")
  saved$s_taxon <- saved[[tc[1]]]; saved$s_rank <- saved[[tc[2]]]
  saved$s_limit <- if (stage == 2) saved$consensus_limit else NA_character_
  post <- readRDS(ext_path)
  stopifnot(is.data.frame(post), all(c("observation_id", "taxon_name", "posterior_point_est") %in% names(post)))
  touched <- unique(read.csv(touched_path, stringsAsFactors = FALSE)$observation_id)
  ids_in <- unique(post$observation_id)
  t_ids <- intersect(touched, ids_in)
  say("stage %d | extract %d rows, %d units | touched list %d, present in extract %d", stage, nrow(post), length(ids_in), length(touched), length(t_ids))
  set.seed(1)
  pool <- setdiff(ids_in, t_ids)
  c_ids <- if (length(pool) > nctrl) sample(pool, nctrl) else pool
  say("controls: %d (set.seed(1) sample of the other extract units; requested %d)", length(c_ids), nctrl)
  say("settings (saved attr): rank_system=%s; cumulative_threshold=%s; min_posterior=%s; posterior_col=%s; backbone_id=%s; consensus_method=%s; robust_prior_s=%s; cross_phylum_eps=%s; group_priors=%s; lookup_missing_taxonomy=%s",
      "phylum/class/order/family/genus/species (RANK_SYSTEM_CONSENSUS, workflow l.472)", S$cumulative_threshold, S$min_posterior, S$posterior_col, S$backbone_id,
      S$consensus_method, S$robust_prior_s, S$cross_phylum_eps, if (is.null(S$group_priors)) "NULL" else "set", lookup)

  run <- function(df) {
    args <- list(cumulative_threshold = S$cumulative_threshold, min_posterior = S$min_posterior,
      posterior_col = S$posterior_col, lookup_missing_taxonomy = lookup, backbone_id = S$backbone_id,
      rank_system = c("phylum", "class", "order", "family", "genus", "species"),
      species_reference = S$species_reference, taxonomy_cache_dir = if (lookup) ci_env("CI_TAXONOMY_CACHE", NULL) else NULL,
      consensus_method = S$consensus_method, robust_prior_s = S$robust_prior_s, cross_phylum_eps = S$cross_phylum_eps)
    run1 <- function(d) { set.seed(1); do.call(posterior_consensus, c(list(d), args)) }
    if (stage == 1) {   # Round 1 is per marker (the marker prefix of "<marker>_ESV_<n>@<site>")
      mk <- sub("_.*$", "", df$observation_id)
      do.call(rbind, lapply(split(df, mk), function(d) run1(d)[, c("observation_id", "consensus_taxon", "consensus_rank", "consensus_limit")]))
    } else run1(df)[, c("observation_id", "consensus_taxon", "consensus_rank", "consensus_limit")]
  }
  eq <- function(a, b) (is.na(a) & is.na(b)) | (!is.na(a) & !is.na(b) & a == b)

  sub_ids <- c(t_ids, c_ids)
  grp <- c(rep("touched", length(t_ids)), rep("control", length(c_ids)))
  base <- post[post$observation_id %in% sub_ids, , drop = FALSE]
  r_old <- run(if (nzchar(ci_env("CI_OLD_LINEAGE", ""))) overlay_lineage(base, readRDS(ci_env("CI_OLD_LINEAGE", ""))) else base)
  L <- readRDS(lin_path)
  r_new <- run(overlay_lineage(base, L))

  m <- data.frame(observation_id = sub_ids, group = grp, stringsAsFactors = FALSE)
  j <- function(r, p) { i <- match(m$observation_id, r$observation_id)
    m[[paste0(p, "_taxon")]] <<- r$consensus_taxon[i]; m[[paste0(p, "_rank")]] <<- r$consensus_rank[i]; m[[paste0(p, "_limit")]] <<- r$consensus_limit[i] }
  i <- match(m$observation_id, saved$observation_id)
  m$saved_taxon <- saved$s_taxon[i]; m$saved_rank <- saved$s_rank[i]; m$saved_limit <- saved$s_limit[i]
  j(r_old, "old"); j(r_new, "new")
  m$repro_ok <- eq(m$old_taxon, m$saved_taxon) & eq(m$old_rank, m$saved_rank)
  m$changed <- !(eq(m$old_taxon, m$new_taxon) & eq(m$old_rank, m$new_rank))
  m$limit_changed <- !eq(m$old_limit, m$new_limit)
  for (g in c("touched", "control")) {
    k <- m$group == g
    say("%s: n=%d | reproduce saved call (taxon+rank) under OLD: %d / %d | calls changed under NEW lineage: %d | consensus_limit changed: %d",
        g, sum(k), sum(m$repro_ok[k]), sum(k), sum(m$changed[k]), sum(m$limit_changed[k]))
  }
  say("  controls must be identical: %s", if (any(m$changed[m$group == "control"])) "FAIL (a control moved)" else "ok")
  for (r in which(!m$repro_ok)) say("  REPRO MISMATCH %s: old %s [%s] vs saved %s [%s]", m$observation_id[r], m$old_taxon[r], m$old_rank[r], m$saved_taxon[r], m$saved_rank[r])
  for (r in which(m$changed)) say("  CHANGED(%s) %s: %s [%s] -> %s [%s]", m$group[r], m$observation_id[r], m$old_taxon[r], m$old_rank[r], m$new_taxon[r], m$new_rank[r])
  write.csv(m, paste0(outp, "_units.csv"), row.names = FALSE)
  writeLines(out, paste0(outp, "_results.txt"))
  invisible(m)
}
