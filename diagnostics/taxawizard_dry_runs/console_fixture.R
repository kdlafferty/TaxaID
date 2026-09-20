# P7(a): console dry run. Drives the REAL engine -- workflow_engine() through
# classify -> path_select -> parameterize -> a complete DAG -- with a scripted
# user, generates the script the console mode would generate, and for the cheap
# path RUNS it against a fast fixture.
#
# This is the only end-to-end exercise of P6: the unit tests check that each
# placeholder is filled, but only this checks that a real model, given a real
# setup report and a real sniff result, reaches a correct plan and writes a
# script that executes.
#
# Usage:  P7_OUT=/tmp Rscript diagnostics/taxawizard_dry_runs/console_fixture.R [tier]
.libPaths(c(path.expand("~/Library/R/4.0/library"), .libPaths()))
suppressMessages(devtools::load_all(
  file.path(normalizePath("."), "TaxaWizard"), quiet = TRUE
))

`%||%` <- function(a, b) if (is.null(a)) b else a

args <- commandArgs(trailingOnly = TRUE)
tier <- if (length(args)) args[1] else "mid"
out_dir <- Sys.getenv("P7_OUT", tempdir())
root <- normalizePath(".")
# The .rds fixtures are gitignored (they are data, not code), so they exist only
# in a working tree someone has built them in -- never in a fresh checkout, and
# not in a git worktree. Resolve explicitly and say so rather than failing on a
# bare stopifnot().
fixtures <- Sys.getenv("TAXAID_FIXTURES", file.path(root, "diagnostics", "fast_workflows"))
match_fixture <- file.path(fixtures, "ptcon12s_fast_match_obj.rds")
if (!file.exists(match_fixture)) {
  stop(sprintf(paste0(
    "fast fixture not found: %s\n",
    "  The *.rds fixtures are gitignored, so they are absent from fresh checkouts\n",
    "  and from git worktrees. Point TAXAID_FIXTURES at a tree that has them,\n",
    "  or build them with diagnostics/fast_workflows/build_fast_fixture.R."),
    match_fixture), call. = FALSE)
}

# The engine's contract (see R/api.R): llm_fn(messages, system_prompt, model,
# max_tokens) returning ONE character string of raw response text. Flatten the
# conversation into a single prompt, since TaxaTools::call_api() takes a string.
llm <- function(messages, system_prompt, model = NULL, max_tokens = 8000L, ...) {
  convo <- paste(vapply(messages, function(m) {
    sprintf("%s: %s", toupper(m$role), m$content)
  }, ""), collapse = "\n\n")
  prompt <- paste0(system_prompt, "\n\n", convo, "\n\nASSISTANT:")
  as.character(TaxaTools::call_api(
    prompt, provider = "anthropic", tier = tier,
    max_tokens = as.integer(max_tokens %||% 8000L)
  ))
}

# --- drive the engine with a scripted user -----------------------------------
run_interview <- function(label, user_turns, max_turns = 8L) {
  cat("\n================ ", label, " ================\n", sep = "")
  history <- list()
  transcript <- character()
  result <- NULL
  for (i in seq_len(max_turns)) {
    msg <- if (i <= length(user_turns)) user_turns[i] else
      "Yes, that is right. Please proceed with that plan."
    history <- c(history, list(list(role = "user", content = msg)))
    result <- tryCatch(
      workflow_engine(history = history, llm_fn = llm),
      error = function(e) list(status = "error", message = conditionMessage(e))
    )
    transcript <- c(transcript, sprintf(
      "---- USER %d ----\n%s\n\n---- ASSISTANT %d (%s) ----\n%s\n",
      i, msg, i, result$status %||% "?", result$message %||% ""))
    cat(sprintf("  turn %d: status=%-10s phase=%-12s dag_steps=%s\n", i,
                result$status %||% "?", result$phase %||% "?",
                if (is.null(result$dag)) "-" else length(result$dag$steps)))
    history <- c(history, list(list(
      role = "assistant",
      content = jsonlite::toJSON(result, auto_unbox = TRUE)
    )))
    if (identical(result$status, "complete") && !is.null(result$dag)) break
    if (identical(result$status, "error")) break
  }
  list(result = result, transcript = transcript)
}

# --- static checks on a generated script -------------------------------------
check_script <- function(path, expect_edges) {
  lines <- readLines(path, warn = FALSE)
  txt <- paste(lines, collapse = "\n")
  ok <- list()

  ok$parses <- !is.null(tryCatch(parse(path), error = function(e) NULL))

  step0 <- grep("^\\.setup <- TaxaWizard::workflow_check\\(edges = ", lines, value = TRUE)
  ok$step0_present <- length(step0) == 1L
  ok$step0_edges <- if (length(step0) == 1L) {
    found <- gsub('"', "", unlist(regmatches(step0, gregexpr('"[^"]*"', step0))))
    all(expect_edges %in% found)
  } else FALSE

  reg <- workflow_registry()
  exports <- unlist(lapply(reg, function(p) vapply(p$functions, `[[`, "", "name")))
  called <- unique(unlist(regmatches(txt, gregexpr("Taxa[A-Za-z]+::[A-Za-z_.]+", txt))))
  called <- called[!grepl("^TaxaWizard::", called)]
  bad <- called[!sub(".*::", "", called) %in% exports]
  ok$all_fns_real <- length(bad) == 0L
  attr(ok$all_fns_real, "bad") <- bad

  # every named argument must be a real formal
  stale <- character()
  exprs <- tryCatch(parse(path, keep.source = FALSE), error = function(e) NULL)
  walk <- function(x) {
    if (is.call(x)) {
      f <- x[[1]]
      if (is.call(f) && identical(f[[1]], as.name("::")) && as.character(f[[2]]) %in% names(reg)) {
        pkg <- as.character(f[[2]]); fn <- as.character(f[[3]])
        e <- Filter(function(z) z$name == fn, reg[[pkg]]$functions)
        if (length(e)) {
          formals_ok <- vapply(e[[1]]$params, `[[`, "", "name")
          given <- names(as.list(x))[-1]; given <- given[nzchar(given)]
          if (!"..." %in% formals_ok) {
            d <- setdiff(given, formals_ok)
            if (length(d)) stale <<- c(stale, sprintf("%s::%s(%s)", pkg, fn, paste(d, collapse = ", ")))
          }
        }
      }
      # Index into the list rather than `for (a in ...)`: binding a loop
      # variable to an EMPTY argument (as in df[, 1]) creates a missing-arg
      # binding, and merely testing it with identical() forces it and throws
      # "argument \"a\" is missing". List extraction is safe.
      rest <- as.list(x)[-1]
      for (.i in seq_along(rest)) {
        if (identical(rest[[.i]], quote(expr = ))) next
        walk(rest[[.i]])
      }
    }
  }
  if (!is.null(exprs)) for (e in exprs) walk(e)
  ok$no_stale_args <- length(stale) == 0L
  attr(ok$no_stale_args, "stale") <- stale
  ok
}

report <- function(label, ok) {
  cat("\n  --- checks:", label, "---\n")
  for (n in names(ok)) {
    v <- ok[[n]]
    extra <- c(attr(v, "bad"), attr(v, "stale"))
    cat(sprintf("    %-16s %s%s\n", n, if (isTRUE(v)) "PASS" else "FAIL",
                if (length(extra)) paste0("  [", paste(extra, collapse = "; "), "]") else ""))
  }
  all(vapply(ok, isTRUE, TRUE))
}

# Re-check an ALREADY generated script without re-running the interview (the
# interview costs API calls; the checks and the execution do not).
existing <- Sys.getenv("P7A_SCRIPT", "")
if (nzchar(existing)) {
  cat("\n=== checking existing script (no interview) ===\n  ", existing, "\n")
  ok <- check_script(existing, "match_to_consensus_score")
  report("existing script", ok)
  cat("\n  --- EXECUTING ---\n")
  res <- system2(file.path(R.home("bin"), "Rscript"), shQuote(existing), stdout = TRUE, stderr = TRUE)
  st <- attr(res, "status") %||% 0L
  writeLines(res, file.path(out_dir, "p7a_run_score_only.log"))
  cat(sprintf("    exit status: %s\n", st))
  cat(paste0("      ", utils::tail(res, 12), collapse = "\n"), "\n")
  quit(save = "no", status = if (isTRUE(all(vapply(ok, isTRUE, TRUE))) && st == 0L) 0L else 1L)
}

# =============================================================================
# ARM 1: score-only path -- generated AND executed
# =============================================================================
arm1 <- run_interview("ARM 1  score-only (match_df -> consensus)", c(
  sprintf(paste0(
    "I have a match data frame saved as an .rds file at %s. I want a consensus ",
    "taxonomic assignment for each observation. Use the score-based route only ",
    "-- no Bayesian priors, no reference fetching, no LLM calls. This is a quick ",
    "check on a small fixture."), match_fixture),
  "Yes, match_df in and consensus out. Use the single-step score route (match_to_consensus_score). Please pick that path.",
  sprintf("Use defaults for everything. The input file is %s. Write the script now.", match_fixture)
))

script1 <- NULL
if (identical(arm1$result$status, "complete") && !is.null(arm1$result$dag)) {
  d1 <- file.path(out_dir, "p7a_score_only"); dir.create(d1, showWarnings = FALSE, recursive = TRUE)
  # Save the DAG so a later run can regenerate the script without paying for
  # another interview (P7A_DAG), the way P7A_SCRIPT skips it for checks.
  saveRDS(arm1$result$dag, file.path(out_dir, "p7a_dag_score_only.rds"))
  gen <- .generate_outputs(dag = arm1$result$dag, outputs = "script", output_dir = d1, trial = FALSE)
  script1 <- grep("\\.R$", gen, value = TRUE)[1]
  cat("\n  generated:", script1, "\n")
}

writeLines(unlist(arm1$transcript), file.path(out_dir, "p7a_transcript_score_only.md"))
cat("\n  transcript:", file.path(out_dir, "p7a_transcript_score_only.md"), "\n")

if (!is.null(script1)) {
  ok1 <- check_script(script1, "match_to_consensus_score")
  pass1 <- report("ARM 1 script", ok1)

  cat("\n  --- EXECUTING the generated script ---\n")
  res <- system2(file.path(R.home("bin"), "Rscript"), shQuote(script1), stdout = TRUE, stderr = TRUE)
  status <- attr(res, "status") %||% 0L
  writeLines(res, file.path(out_dir, "p7a_run_score_only.log"))
  cat(sprintf("    exit status: %s  (log: %s)\n", status,
              file.path(out_dir, "p7a_run_score_only.log")))
  cat("    last lines:\n")
  cat(paste0("      ", utils::tail(res, 8), collapse = "\n"), "\n")
} else {
  cat("\n  ARM 1 did not reach a complete DAG -- nothing to check or run.\n")
}
