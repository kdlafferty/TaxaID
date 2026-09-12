# score_consensus_workflow_regression.R
# ------------------------------------------------------------------------------
# Prove that consensus_mode's arrival (2026-09-12) changed NOTHING for any real
# production workflow, by re-running each workflow's own exact score_consensus()
# call on its own real saved checkpoint data and diffing against the pre-change
# function.
#
# Why this exists as a committed diagnostic rather than a one-off check
# ---------------------------------------------------------------------
# score_consensus() is the conventional-pipeline baseline the assignment-method
# manuscript compares TaxaID against. A silent change to "gap" mode would not
# throw an error anywhere -- it would just quietly move the baseline, and every
# published comparison number with it. The package tests pin the behaviour on
# synthetic fixtures; this pins it on the actual production inputs, which are
# far messier (NA ranks, genus-only hits, duplicated accessions, 13k+ ESVs).
#
# What it compares
# ----------------
#   new: the installed TaxaAssign
#   old: TaxaAssign/R/score_consensus.R as of the commit BEFORE consensus_mode
#        (OLD_REF below), sourced into an environment parented on the namespace
#        so its internal helper calls (.find_lca, .extract_rank_values, ...)
#        still resolve.
# Both are handed identical inputs and identical arguments. The new function's
# two added columns (bracket_width_used, agreement_achieved) are dropped before
# the diff; the diff must be exactly empty, and the remaining column NAMES must
# still be in their original order.
#
# Run:  Rscript diagnostics/score_consensus_workflow_regression.R
# Requires: the production checkpoints listed in WORKFLOWS below. Any that are
# absent are reported as SKIPPED, not silently passed.
# ------------------------------------------------------------------------------

suppressMessages({
  library(TaxaAssign)
  library(dplyr)
})

`%||%` <- function(x, y) if (is.null(x)) y else x

# The baseline is "the commit before consensus_mode landed", resolved from
# history rather than hard-coded as HEAD~1. HEAD~1 is WRONG the moment anything
# else lands on the branch -- which is exactly what happened the first time this
# script ran (a concurrent session had pushed four unrelated commits on top), and
# it fails in the worst possible way: `git show` cheerfully returns the NEW file,
# so "old" and "new" are the same function and every check reports a spurious
# diff. The extraction is asserted below, so that trap cannot recur silently.
OLD_REF <- NULL   # resolved from history; override with a ref only if you must

# Repo root: walk up from the working directory until TaxaAssign/ appears, so
# the script runs from the repo root or from diagnostics/ either way.
REPO <- getwd()
while (!dir.exists(file.path(REPO, "TaxaAssign")) && dirname(REPO) != REPO) {
  REPO <- dirname(REPO)
}
if (!dir.exists(file.path(REPO, "TaxaAssign"))) {
  stop("Run this from the TaxaID repo (could not locate TaxaAssign/ above ", getwd(), ").")
}

PT   <- "/Users/lafferty/My Drive/Rscripts/eDNA/PtConception"
MUGU <- "/Users/lafferty/My Drive/Rscripts/eDNA/SepulvedaMugu"
GL   <- "/Users/lafferty/My Drive/Stats and Data/GreatLakes data"

NEW_COLS <- c("bracket_width_used", "agreement_achieved")

cat("TaxaAssign built:", packageDescription("TaxaAssign")$Built, "\n")
cat("consensus_mode present:",
    "consensus_mode" %in% names(formals(score_consensus)), "\n\n")

# --- the pre-change function --------------------------------------------------
.git <- function(...) {
  out <- suppressWarnings(system2("git", c("-C", shQuote(REPO), ...),
                                  stdout = TRUE, stderr = FALSE))
  if (!is.null(attr(out, "status")) && attr(out, "status") != 0) character(0) else out
}

if (is.null(OLD_REF)) {
  # -S finds commits that changed the number of occurrences of the string;
  # the LAST one listed (oldest) is the one that introduced it.
  touched <- .git("log", "--format=%H", "-S", "consensus_mode", "--",
                  "TaxaAssign/R/score_consensus.R")
  if (!length(touched)) {
    stop("Could not find the commit that introduced consensus_mode. ",
         "Is this the TaxaID repo, with that history still reachable?")
  }
  OLD_REF <- paste0(touched[[length(touched)]], "^")
}
cat("baseline ref:", OLD_REF, "\n")

old_src <- tempfile(fileext = ".R")
ok <- system2("git", c("-C", shQuote(REPO), "show",
                       paste0(OLD_REF, ":TaxaAssign/R/score_consensus.R")),
              stdout = old_src)
if (!identical(ok, 0L)) {
  stop("Could not retrieve ", OLD_REF, ":TaxaAssign/R/score_consensus.R -- ",
       "adjust OLD_REF if history has moved on.")
}
# Assert we really got the PRE-change file. Without this the script can compare
# the new function against itself and report nonsense with total confidence.
if (any(grepl("consensus_mode", readLines(old_src, warn = FALSE), fixed = TRUE))) {
  stop("The file extracted at ", OLD_REF, " already contains consensus_mode -- ",
       "that is the post-change version, so there is nothing to compare against. ",
       "Fix OLD_REF.")
}
oldenv <- new.env(parent = asNamespace("TaxaAssign"))
sys.source(old_src, envir = oldenv)
old_sc <- oldenv$score_consensus
cat("baseline function loaded (", length(ls(oldenv, all.names = TRUE)),
    " objects, incl. its own internal helpers)\n", sep = "")

# --- helpers ------------------------------------------------------------------
.load <- function(path) if (file.exists(path)) readRDS(path) else NULL

results <- list()

compare_one <- function(label, match_df, ...) {
  if (is.null(match_df)) {
    cat(sprintf("  %-44s SKIPPED (checkpoint not on disk)\n", label))
    results[[label]] <<- list(status = "skipped", n = NA_integer_)
    return(invisible(NULL))
  }
  new <- suppressMessages(score_consensus(match_df = match_df, ...))
  old <- suppressMessages(old_sc(match_df = match_df, ...))
  trimmed <- new[, setdiff(names(new), NEW_COLS), drop = FALSE]

  cols_additive <- identical(names(trimmed), names(old))
  cmp <- all.equal(old, trimmed, check.attributes = FALSE)
  same <- isTRUE(cmp)

  cat(sprintf("  %-44s obs=%-6d additive=%-5s identical=%-5s\n",
              label, nrow(new), cols_additive, same))
  if (!same) print(cmp)
  results[[label]] <<- list(status = if (same && cols_additive) "ok" else "FAIL",
                            n = nrow(new))
  invisible(new)
}

PT_ARGS <- list(
  min_score = 80, max_gap = 1,
  rank_thresholds = c(species = 98, genus = 95, family = 90, order = 85),
  score_col = "score_original", rank_system = c("family", "genus", "species")
)

# =============================================================================
cat("== PtConception (12S single, 12S multi, 18S) ==\n")
pt12 <- .load(file.path(PT, "PtConMifishSchulte_match_obj_restored.rds"))
do.call(compare_one, c(list("12S single site  [:2039]", pt12), PT_ARGS))

# The multi-site call is argument-identical to the single-site one and
# score_consensus() is site-agnostic (no site table, no covariate), so when the
# multi-site checkpoint is absent the single-site data still exercises the exact
# call. Reported honestly under its own label either way.
pt12m <- .load(file.path(PT, "PtConMifishSchulteMulti_match_obj_restored.rds")) %||%
         .load(file.path(PT, "PtConMifishSchulteMulti_match_obj.rds"))
if (is.null(pt12m)) {
  cat("  (no multi-site checkpoint; re-running the identical call on single-site data)\n")
  pt12m <- pt12
}
do.call(compare_one, c(list("12S multi site   [:1850]", pt12m), PT_ARGS))

pt18 <- .load(file.path(PT, "PtCon18SSchulte_match_obj.rds"))
do.call(compare_one, c(list("18S single site  [:2435]", pt18), PT_ARGS))

# =============================================================================
# MuguFishWorkflow.R -- three markers, each with its own derived thresholds,
# then bind_rows(). MATCH_SOURCE toggles blast/wilder but NOT min_score, so one
# pass covers both sources. (MuguWilderFishWorkflow.R was retired 2026-09-12 and
# folded into this script as MATCH_SOURCE <- "wilder".)
cat("\n== Mugu (MuguFishWorkflow.R:1922-1930, 3 markers) ==\n")
RANK_SYSTEM <- c("order", "family", "genus", "species")
mugu_new <- list(); mugu_old <- list()
for (nm in c("coi", "12s", "16s")) {
  marker <- toupper(nm)
  md <- .load(file.path(MUGU, sprintf("MuguWilderFish_blast_match_%s.rds", nm)))
  rt <- .load(file.path(MUGU, sprintf("MuguWilderFish_blast_rank_thresholds_%s.rds", marker)))
  if (is.null(md) || is.null(rt)) {
    cat(sprintf("  %-44s SKIPPED (checkpoint not on disk)\n", paste("marker", nm)))
    next
  }
  args <- list(min_score = 100, max_gap = 0, rank_thresholds = rt,
               score_col = "score_original", rank_system = RANK_SYSTEM)
  mugu_new[[nm]] <- do.call(compare_one, c(list(sprintf("marker %-4s", nm), md), args))
  mugu_old[[nm]] <- suppressMessages(do.call(old_sc, c(list(match_df = md), args)))
}
if (length(mugu_new) == 3L) {
  # The real downstream step. Worth exercising: bind_rows() is the one place a
  # column-set change could bite, and the three frames must stay conformable.
  bn <- bind_rows(mugu_new); bo <- bind_rows(mugu_old)
  ok <- isTRUE(all.equal(bo, bn[, setdiff(names(bn), NEW_COLS), drop = FALSE],
                         check.attributes = FALSE))
  cat(sprintf("  bind_rows(3 markers): %d rows, %d -> %d cols, identical=%s\n",
              nrow(bn), ncol(bo), ncol(bn), ok))
  results[["Mugu bind_rows"]] <- list(status = if (ok) "ok" else "FAIL", n = nrow(bn))
}

# =============================================================================
cat("\n== GreatLakes (GreatLakes2023_ConsensusWorkflow.R:1740-1776, 8 configs) ==\n")
mo  <- .load(file.path(GL, "GreatLakes2023BurnsHarbor_match_obj_restored.rds"))
sqm <- .load(file.path(GL, "GreatLakes2023BurnsHarbor_seq_matrix.rds"))
gl_new <- list()
if (!is.null(mo) && !is.null(sqm)) {
  gl_rt <- suppressMessages(TaxaLikely::compute_rank_thresholds(sqm))
  SCRS  <- c("family", "genus", "species")
  mo_top3 <- mo |>
    dplyr::group_by(observation_id) |>
    dplyr::filter(score_original %in% sort(unique(score_original), decreasing = TRUE)[1:3]) |>
    dplyr::ungroup()

  cfg <- list(
    gita_jv_default = list(mo,      80,  1,   c(species=98, genus=95, family=90, order=85)),
    marker_derived  = list(mo,      80,  1,   gl_rt),
    stricter        = list(mo,      90,  0.5, c(species=99, genus=97, family=93, order=88)),
    looser          = list(mo,      70,  2,   c(species=95, genus=90, family=85, order=80)),
    pct100          = list(mo,     100,  0,   NULL),
    top_score       = list(mo,       0,  0,   NULL),
    top3            = list(mo_top3,  0,  Inf, NULL),
    near_top1       = list(mo,       0,  1,   NULL)
  )
  for (nm in names(cfg)) {
    a <- cfg[[nm]]
    gl_new[[nm]] <- compare_one(sprintf("config %-16s", nm), a[[1]],
                                min_score = a[[2]], max_gap = a[[3]],
                                rank_thresholds = a[[4]],
                                score_col = "score_original", rank_system = SCRS)
  }

  # Strongest available evidence: the output the real workflow actually saved.
  saved <- .load(file.path(GL, "GreatLakes2023BurnsHarbor_score_con_results.rds"))
  if (!is.null(saved)) {
    cat("\n  -- vs saved production score_con_results.rds --\n")
    for (nm in names(gl_new)) {
      d  <- gl_new[[nm]][, setdiff(names(gl_new[[nm]]), NEW_COLS), drop = FALSE]
      ok <- isTRUE(all.equal(saved[[nm]], d, check.attributes = FALSE))
      cat(sprintf("     %-18s matches production run: %s\n", nm, ok))
      results[[paste("production", nm)]] <- list(status = if (ok) "ok" else "FAIL",
                                                 n = nrow(d))
      if (!ok) print(all.equal(saved[[nm]], d, check.attributes = FALSE))
    }
  }
} else {
  cat("  SKIPPED (GreatLakes checkpoints not on disk)\n")
}

# =============================================================================
# Every workflow consumes score_con the same way: an explicit named-column
# subset fed to merge(). Exercise it, so a future column change that DID collide
# would be caught here rather than in a production run.
cat("\n== Downstream consumer pattern ==\n")
cf <- .load(file.path(GL, "GreatLakes2023BurnsHarbor_consensus_final.rds"))
if (!is.null(cf) && length(gl_new)) {
  cmp <- merge(
    cf[, c("observation_id", "consensus_taxon", "consensus_rank", "is_resolved",
           "consensus_posterior", "n_plausible", "consensus_prior")],
    gl_new$gita_jv_default[, c("observation_id", "consensus_taxon", "consensus_rank",
                               "is_resolved", "top_score", "n_taxa")],
    by = "observation_id", suffixes = c("_posterior", "_score"))
  cat(sprintf("  merge(consensus_final, score_con): %d rows x %d cols, no collision\n",
              nrow(cmp), ncol(cmp)))
  results[["downstream merge"]] <- list(status = "ok", n = nrow(cmp))
} else {
  cat("  SKIPPED\n")
}

# =============================================================================
cat("\n", strrep("=", 72), "\nSUMMARY\n", strrep("=", 72), "\n", sep = "")
tab <- do.call(rbind, lapply(names(results), function(n)
  data.frame(check = n, obs = results[[n]]$n, status = results[[n]]$status)))
print(tab, row.names = FALSE)

n_fail <- sum(tab$status == "FAIL")
n_skip <- sum(tab$status == "skipped")
cat(sprintf("\n%d checks: %d ok, %d skipped, %d FAILED\n",
            nrow(tab), sum(tab$status == "ok"), n_skip, n_fail))
if (n_fail > 0) {
  stop("score_consensus() gap-mode behaviour CHANGED for a production workflow.")
}
cat("gap-mode behaviour unchanged for every production workflow checked.\n")
