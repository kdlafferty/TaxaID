#' Encode a Value as a Literal R String for Generated Code
#'
#' Both generators in this package (\code{.generate_script()} for workflow
#' scripts, \code{.build_app_code()} for Shiny apps) embed free-form text --
#' file paths, step descriptions, parameter defaults, whole step code blocks
#' -- inside R string literals in the file they emit. Escaping only the double
#' quotes leaves any backslash in that text as a lone backslash in the emitted
#' literal, which is an invalid R escape: the generated file then fails to
#' parse in its entirety. \code{encodeString()} escapes backslashes, quotes
#' and control characters together, so the emitted literal always parses back
#' to exactly the original text.
#'
#' @param x Value to embed. Coerced with \code{as.character()}; \code{NULL}
#'   and \code{NA} become an empty string so a widget or step is never
#'   silently dropped from the generated file.
#' @return Character scalar, including the surrounding double quotes.
#' @noRd
.r_string <- function(x) {
  x <- as.character(x)
  if (length(x) == 0L) {
    return("\"\"")
  }
  x <- x[1L]
  if (is.na(x)) x <- ""
  encodeString(x, quote = "\"")
}


#' Generate Workflow Outputs
#'
#' Dispatches to the appropriate output generator(s) based on the
#' requested output types. This is the fan-out point: a single DAG
#' can produce multiple output files.
#'
#' @param dag List. The complete workflow DAG from the engine.
#' @param outputs Character vector. Output types: \code{"script"},
#'   \code{"methods"}, \code{"app"}.
#' @param output_dir Character. Directory to write files.
#' @param trial Logical. Include trial-mode subsetting.
#' @param known_script_path Character or NULL. Path to a script this SAME
#'   \code{workflow_create()} session already generated (i.e. what
#'   \code{attr(result, "script_path")} returned from an earlier call in
#'   this session). When supplied and it still exists, new steps are
#'   appended to it directly -- no need to guess via
#'   \code{\link{.find_existing_script}}'s same-day filename scan, and
#'   \code{attr(result, "cross_session_append")} is always \code{FALSE}.
#'   When \code{NULL} (the first generation of a session), a same-day file
#'   found by \code{.find_existing_script()} may belong to an earlier,
#'   unrelated session in the same \code{output_dir} -- callers should
#'   check \code{attr(result, "cross_session_append")} and warn the user.
#'
#' @return Character vector of generated file paths, with attributes
#'   \code{appended} (logical), \code{script_path} (character or NULL --
#'   pass this back in as \code{known_script_path} on the next call in the
#'   same session), and \code{cross_session_append} (logical -- TRUE when
#'   the appended-to file was discovered by same-day filename match rather
#'   than known to belong to this session).
#' @noRd
.generate_outputs <- function(dag, outputs, output_dir, trial = FALSE,
                              known_script_path = NULL) {
  generated <- character()
  appended <- FALSE
  cross_session_append <- FALSE
  script_path <- NULL

  if ("script" %in% outputs) {
    known_valid <- !is.null(known_script_path) && file.exists(known_script_path)
    existing <- if (known_valid) known_script_path else .find_existing_script(output_dir)
    appended <- !is.null(existing)
    cross_session_append <- appended && !known_valid
    script_path <- .generate_script(dag, output_dir, trial,
      known_script_path = known_script_path
    )
    generated <- c(generated, script_path)
  }

  if ("methods" %in% outputs) {
    path <- .generate_markdown(dag, output_dir)
    generated <- c(generated, path)
  }

  if ("app" %in% outputs) {
    path <- .generate_app(dag, output_dir, script_path = script_path)
    generated <- c(generated, path)
  }

  # Save context file for future sessions
  .save_context(dag, output_dir)

  attr(generated, "appended") <- appended
  attr(generated, "cross_session_append") <- cross_session_append
  attr(generated, "script_path") <- script_path
  generated
}


#' Generate R Script from DAG
#'
#' Converts the workflow DAG into a self-contained .R script with
#' checkpoint/resume, auto-error-catch, and optional debug subsetting.
#'
#' When an existing script is found in \code{output_dir} (from a prior
#' workflow in the same session), new steps are appended to it rather
#' than overwriting. This keeps the full pipeline in a single file.
#'
#' @param dag List. Workflow DAG.
#' @param output_dir Character. Output directory.
#' @param trial Logical. Include trial-mode subsetting.
#' @param known_script_path Character or NULL. A script this same session
#'   already generated (see \code{\link{.generate_outputs}}). Preferred
#'   over \code{.find_existing_script()}'s same-day filename scan when
#'   present and still on disk.
#'
#' @return Character: path to generated file.
#' @noRd
.generate_script <- function(dag, output_dir, trial = FALSE,
                             known_script_path = NULL) {
  n_steps <- length(dag$steps)

  # --- Check for existing script to append to ---
  existing <- if (!is.null(known_script_path) && file.exists(known_script_path)) {
    known_script_path
  } else {
    .find_existing_script(output_dir)
  }

  if (!is.null(existing)) {
    return(.append_to_script(existing, dag, output_dir))
  }

  # --- Fresh script (no prior workflow) ---
  lines <- character()

  # --- Header ---
  lines <- c(
    lines,
    "# =============================================================================",
    sprintf("# TaxaID Workflow -- Generated %s by TaxaWizard", Sys.Date()),
    "# =============================================================================",
    "#",
    "# Features:",
    "#   - Checkpoint/resume: completed steps are cached and skipped on re-run",
    "#   - Auto-error-catch: errors are sent to workflow_fix() automatically",
    "#   - Debug mode: set debug_mode <- TRUE to run on a small subset first",
    "# =============================================================================",
    ""
  )

  # --- Library calls ---
  packages <- unique(vapply(dag$steps, `[[`, "", "package"))
  packages <- c("TaxaWizard", packages)
  for (pkg in packages) {
    lines <- c(lines, sprintf("library(%s)", pkg))
  }
  lines <- c(
    lines, "",
    "# --- Console output ---",
    "# cli's progress bars redraw with a carriage return, which a logged or",
    "# non-interactive run records as thousands of separate lines rather than",
    "# one bar redrawing in place: 45,991 carriage returns and 223 progress",
    "# lines per audit in one log. A progress bar is worthless",
    "# in a batch run anyway. Set to 2 (cli's default) to get them back.",
    "options(cli.progress_show_after = Inf)",
    ""
  )

  # --- Debug mode ---
  lines <- c(
    lines,
    "# --- Debug / Trial Mode ---",
    "# Set TRUE for first run (fast, catches errors); FALSE for full dataset",
    "debug_mode <- TRUE",
    "debug_n    <- 20L  # rows to subset in debug mode",
    ""
  )

  # --- Checkpoint directory ---
  lines <- c(
    lines,
    "# --- Checkpoint directory (for resume on re-run) ---",
    sprintf(
      'checkpoint_dir <- file.path(%s, ".workflow_checkpoints")',
      .r_string(output_dir)
    ),
    "if (!dir.exists(checkpoint_dir)) dir.create(checkpoint_dir, recursive = TRUE)",
    sprintf(
      "total_steps <- %dL  # updated automatically when workflow is extended",
      n_steps
    ),
    "",
    "# Checkpoint signatures.",
    "#",
    "# A checkpoint keyed on the step NUMBER alone answers \"has step N run?\",",
    "# never \"has step N run with THESE inputs?\". That matters here because the",
    "# parameters above are meant to be edited: change one, re-run, and a",
    "# number-keyed cache replays every step and prints the OLD answer under the",
    "# NEW parameters, silently. It also defeats content-addressed caches further",
    "# down -- TaxaFetch keys its GBIF checkpoints on the query itself, and an",
    "# outer existence check short-circuits before that can notice the query",
    "# changed, downgrading a good cache to a worse one.",
    "#",
    "# So each step stores a signature beside its result: a digest of the step's",
    "# own code plus the values of the parameters that step actually reads. A",
    "# checkpoint is reused only when that signature still matches.",
    ".taxaid_digest <- function(x) {",
    "  tf <- tempfile()",
    "  on.exit(unlink(tf), add = TRUE)",
    "  writeLines(as.character(x), tf)",
    "  unname(tools::md5sum(tf))",
    "}",
    ".taxaid_step_signature <- function(code_expr, env) {",
    "  code_txt <- paste(deparse(code_expr), collapse = \"\\n\")",
    "  # Only the parameters this step REFERENCES, so editing an unrelated",
    "  # parameter does not needlessly invalidate it.",
    "  used <- sort(intersect(all.vars(code_expr), .workflow_params))",
    "  vals <- vapply(used, function(nm) {",
    "    v <- tryCatch(get(nm, envir = env), error = function(e) NULL)",
    "    paste0(nm, \" = \", paste(deparse(v), collapse = \" \"))",
    "  }, character(1))",
    "  .taxaid_digest(c(code_txt, vals))",
    "}",
    "# A step whose inputs changed invalidates every LATER step too: their own",
    "# signatures may be unchanged, but they were computed from this step's old",
    "# output, which they reference by variable name rather than by parameter.",
    ".taxaid_clear_steps_after <- function(step_id) {",
    '  f <- list.files(checkpoint_dir, pattern = "^step_[0-9]+\\\\.(rds|sig)$", full.names = TRUE)',
    '  n <- suppressWarnings(as.integer(sub("^step_0*([0-9]+)\\\\..*$", "\\\\1", basename(f))))',
    "  stale <- f[!is.na(n) & n > step_id]",
    "  if (length(stale) > 0L) {",
    "    unlink(stale)",
    '    message(sprintf("  (cleared %d later checkpoint(s), which were built on the old result)", length(stale) / 2L))',
    "  }",
    "}",
    "",
    "# Helper: run a step with checkpoint and auto-fix on error.",
    "# Code is evaluated in the CALLING environment so all variables created",
    "# by prior steps (e.g. consensus_df, context_df) remain visible.",
    ".run_step <- function(step_id, description, code_expr, env = parent.frame()) {",
    '  cache_file <- file.path(checkpoint_dir, sprintf("step_%02d.rds", step_id))',
    '  sig_file   <- file.path(checkpoint_dir, sprintf("step_%02d.sig", step_id))',
    "  sig <- .taxaid_step_signature(code_expr, env)",
    "  if (file.exists(cache_file)) {",
    "    prev <- if (file.exists(sig_file)) readLines(sig_file, warn = FALSE)[1L] else NA_character_",
    "    if (identical(prev, sig)) {",
    '      message(sprintf("Step %d: %s [cached, skipping]", step_id, description))',
    "      return(readRDS(cache_file))",
    "    }",
    '    message(sprintf("Step %d: %s [inputs changed since the cached run -- recomputing]", step_id, description))',
    "    .taxaid_clear_steps_after(step_id)",
    "  }",
    '  message(sprintf("Step %d/%d: %s", step_id, total_steps, description))',
    "  result <- tryCatch(",
    "    eval(code_expr, envir = env),",
    "    error = function(e) {",
    '      msg <- sprintf("Step %d (%s) failed:\\n%s", step_id, description, conditionMessage(e))',
    "      message(msg)",
    "      message(\"\")",
    '      message("Attempting auto-fix...")',
    "      script_path <- tryCatch(",
    "        TaxaWizard::workflow_fix(error_text = msg, auto = TRUE),",
    "        error = function(e2) {",
    '          message("Auto-fix engine error: ", conditionMessage(e2))',
    "          NULL",
    "        }",
    "      )",
    "      if (!is.null(script_path) && file.exists(script_path)) {",
    '        message("")',
    '        message("=== Script corrected and regenerated. ===")',
    '        message("Press Ctrl+Shift+S (or click Source) to re-run.")',
    '        message("Cached steps will be skipped automatically.")',
    '        message("")',
    "      } else {",
    '        message("Auto-fix could not generate a corrected script.")',
    '        message("To fix manually, run:  workflow_fix()")',
    '        message("Then re-source this script.")',
    "      }",
    '      stop("Workflow halted at step ", step_id, ". See above.", call. = FALSE)',
    "    }",
    "  )",
    "  saveRDS(result, cache_file)",
    "  writeLines(sig, sig_file)",
    "  result",
    "}",
    ""
  )

  # --- User parameters ---
  if (length(dag$parameters) > 0L) {
    lines <- c(lines, "# --- User Parameters ---")
    for (param in dag$parameters) {
      lines <- c(lines, sprintf("%s <- %s", param$name, param$value))
    }
    lines <- c(lines, "")
  }

  # The names .taxaid_step_signature() digests. Emitted unconditionally, so a
  # DAG with no parameters still defines it rather than erroring at step 1.
  param_names <- vapply(dag$parameters %||% list(), function(p) as.character(p$name %||% ""), "")
  param_names <- param_names[nzchar(param_names)]
  lines <- c(
    lines,
    "# Parameters whose values are part of each step's checkpoint signature.",
    if (length(param_names) > 0L) {
      sprintf(".workflow_params <- c(%s)", paste(vapply(param_names, .r_string, ""), collapse = ", "))
    } else {
      ".workflow_params <- character(0)"
    },
    ""
  )

  # --- Step 0: setup check ---
  # Only when the dag's steps carry edge_id (the shape documented in
  # create.R's "status: complete" prompt: step_id, edge_id, package,
  # function_name, description, code, inputs, output_var). A dag whose steps
  # don't all set edge_id falls back to edges = NULL (checks the whole
  # ecosystem) rather than silently omitting the check.
  step_edge_ids <- unique(vapply(dag$steps, function(s) as.character(s$edge_id %||% ""), ""))
  step_edge_ids <- step_edge_ids[nzchar(step_edge_ids)]
  step_edge_ids <- .keep_known_edges(step_edge_ids, context = "generated script Step 0")
  edges_arg <- if (length(step_edge_ids) > 0L) {
    sprintf(
      "c(%s)",
      paste(vapply(step_edge_ids, .r_string, ""), collapse = ", ")
    )
  } else {
    "NULL"
  }
  lines <- c(
    lines,
    "# --- Step 0: setup check (generated by TaxaWizard) ---",
    sprintf(".setup <- TaxaWizard::workflow_check(edges = %s, verbose = TRUE)", edges_arg),
    'if (any(.setup$status == "missing")) stop("Setup incomplete -- see the fix column above.")',
    ""
  )

  # --- Pipeline steps ---
  for (i in seq_along(dag$steps)) {
    step <- dag$steps[[i]]
    desc <- step$description %||% step$function_name
    output_var <- step$output_var %||% sprintf("step_%d_result", i)

    # Wrap the LLM-generated code in the checkpoint/error-catch helper.
    # Uses quote({...}) so code is evaluated in the calling environment,
    # giving access to all variables from prior steps.
    step_header <- sprintf("# --- Step %d: %s ---", i, desc)
    if (isFALSE(step$validated)) {
      # Tier-B fallback (.get_path_context()): no validated snippet existed
      # for this step, so the LLM wrote it from registry documentation
      # alone. Flag it above the step so it is impossible to miss before
      # running the generated script.
      step_header <- c(
        "# WARNING: this step was generated without a validated snippet; review before running",
        step_header
      )
    }
    lines <- c(
      lines,
      step_header,
      sprintf(
        "%s <- .run_step(%d, %s, quote({",
        output_var, i, .r_string(desc)
      ),
      paste0("  ", strsplit(step$code, "\n")[[1]]), # indent code inside quote
      "}))",
      ""
    )

    # Add debug subsetting after the first data-loading step
    if (i == 1L) {
      lines <- c(
        lines,
        "# Apply debug subsetting after initial data load",
        "# Subsets by observation_id (not raw rows) so each sample keeps all its matches",
        sprintf(
          "if (debug_mode && is.data.frame(%s) && \"observation_id\" %%in%% names(%s)) {",
          output_var, output_var
        ),
        sprintf("  .debug_n_total <- nrow(%s)", output_var),
        sprintf(
          "  .debug_ids <- unique(%s$observation_id)[seq_len(min(debug_n, length(unique(%s$observation_id))))]",
          output_var, output_var
        ),
        sprintf(
          "  %s <- %s[%s$observation_id %%in%% .debug_ids, , drop = FALSE]",
          output_var, output_var, output_var
        ),
        sprintf(
          paste0(
            '  message(sprintf("DEBUG MODE: subsetting to %%d observation_ids ',
            '(%%d rows of %%d)", length(.debug_ids), nrow(%s), .debug_n_total))'
          ),
          output_var
        ),
        sprintf(
          "} else if (debug_mode && is.data.frame(%s) && nrow(%s) > debug_n) {",
          output_var, output_var
        ),
        sprintf("  .debug_n_total <- nrow(%s)", output_var),
        sprintf("  %s <- head(%s, debug_n)", output_var, output_var),
        sprintf(
          '  message(sprintf("DEBUG MODE: subsetting to %%d rows (of %%d)", nrow(%s), .debug_n_total))',
          output_var
        ),
        "}",
        ""
      )
    }
  }

  # --- Clear checkpoints message ---
  lines <- c(
    lines,
    "# --- Workflow complete ---",
    'message("Workflow complete.")',
    "if (debug_mode) {",
    '  message("\\nThis was a DEBUG run (", debug_n, " rows).")',
    '  message("If everything looks good, set debug_mode <- FALSE and re-run.")',
    '  message("Checkpoints from debug will be cleared automatically.")',
    "}",
    "",
    "# To clear all checkpoints and re-run from scratch:",
    sprintf(
      '# unlink("%s/.workflow_checkpoints", recursive = TRUE)',
      gsub('"', '\\\\"', output_dir)
    ),
    ""
  )

  # --- Write file ---
  filename <- sprintf("taxaid_workflow_%s.R", format(Sys.Date(), "%Y%m%d"))
  filepath <- file.path(output_dir, filename)
  writeLines(lines, filepath)
  filepath
}


#' Find Existing TaxaWizard Script from the Current Session
#'
#' Looks for a \code{taxaid_workflow_*.R} file generated TODAY.
#' Only returns scripts created in the current session to avoid
#' accidentally appending to old unrelated workflows.
#'
#' @param output_dir Character. Directory to search.
#' @return Character path to existing script, or NULL if none found.
#' @noRd
.find_existing_script <- function(output_dir) {
  # Only match today's date to avoid appending to old scripts

  today_pattern <- sprintf(
    "^taxaid_workflow_%s\\.R$",
    format(Sys.Date(), "%Y%m%d")
  )
  candidates <- list.files(output_dir,
    pattern = today_pattern,
    full.names = TRUE
  )
  if (length(candidates) == 0L) {
    return(NULL)
  }
  # Return the most recently modified
  info <- file.info(candidates)
  candidates[which.max(info$mtime)]
}


#' Append New DAG Steps to an Existing Script
#'
#' Reads the existing script, finds the highest step number, adds any new
#' library() calls, inserts the new steps before the "Workflow complete"
#' footer, and updates the total step count in the .run_step progress
#' messages.
#'
#' @param script_path Character. Path to existing script.
#' @param dag List. The new workflow DAG.
#' @param output_dir Character. Output directory.
#' @return Character: path to the updated script file.
#' @noRd
.append_to_script <- function(script_path, dag, output_dir) {
  existing_lines <- readLines(script_path, warn = FALSE)

  # --- Find highest existing step number ---
  step_pattern <- "^# --- Step (\\d+):"
  step_matches <- regmatches(existing_lines, regexpr(step_pattern, existing_lines))
  step_nums <- as.integer(gsub(
    "^# --- Step (\\d+):.*", "\\1",
    step_matches[nzchar(step_matches)]
  ))
  last_step <- if (length(step_nums) > 0L) max(step_nums) else 0L

  # --- Find insertion point (just before "# --- Workflow complete ---") ---
  complete_idx <- grep("^# --- Workflow complete ---$", existing_lines)
  if (length(complete_idx) == 0L) {
    # No footer found; append at end
    insert_at <- length(existing_lines)
    footer_lines <- character(0)
  } else {
    insert_at <- complete_idx[1L] - 1L
    footer_lines <- existing_lines[complete_idx[1L]:length(existing_lines)]
    existing_lines <- existing_lines[seq_len(insert_at)]
  }

  # --- Add new library() calls if needed ---
  new_packages <- unique(vapply(dag$steps, `[[`, "", "package"))
  existing_libs <- regmatches(
    existing_lines,
    regexpr("(?<=^library\\()\\w+(?=\\))", existing_lines, perl = TRUE)
  )
  existing_libs <- existing_libs[nzchar(existing_libs)]
  missing_libs <- setdiff(new_packages, existing_libs)

  if (length(missing_libs) > 0L) {
    # Insert after last existing library() line
    lib_lines <- grep("^library\\(", existing_lines)
    if (length(lib_lines) > 0L) {
      lib_insert <- max(lib_lines)
      new_lib_lines <- vapply(missing_libs, function(pkg) {
        sprintf("library(%s)", pkg)
      }, character(1))
      after_libs <- if (lib_insert < length(existing_lines)) {
        existing_lines[(lib_insert + 1L):length(existing_lines)]
      } else {
        character(0)
      }
      existing_lines <- c(
        existing_lines[seq_len(lib_insert)],
        new_lib_lines,
        after_libs
      )
      # Adjust insert_at for the added lines
      insert_at <- insert_at + length(new_lib_lines)
    }
  }

  # --- Add new user parameters ---
  new_param_lines <- character(0)
  if (length(dag$parameters) > 0L) {
    new_param_lines <- c(
      "",
      sprintf("# --- Extension Parameters (added %s) ---", Sys.Date())
    )
    for (param in dag$parameters) {
      # Only add if not already defined in existing script
      param_pattern <- sprintf("^%s\\s*<-", gsub("\\.", "\\\\.", param$name))
      if (!any(grepl(param_pattern, existing_lines))) {
        new_param_lines <- c(
          new_param_lines,
          sprintf("%s <- %s", param$name, param$value)
        )
      }
    }
    new_param_lines <- c(new_param_lines, "")
  }

  # --- Step 0: widen the EXISTING check, never write a second one ---
  # P6. An appended stage can need things the original path did not (a BLAST
  # binary, an NCBI key). The script's Step 0 is at the top and has already
  # run by the time those steps execute, so leaving it alone would let the
  # script sail past a requirement it is about to need and fail deep in a
  # stage instead of before step 1. Re-deriving Step 0 is equally wrong: a
  # second check block would either duplicate the first or silently narrow it
  # to the extension's edges, dropping the original path's requirements. So
  # the existing line is widened in place, to the union.
  existing_lines <- .widen_step0_edges(existing_lines, dag)
  existing_lines <- .widen_workflow_params(existing_lines, dag)

  # --- Build new step lines ---
  new_step_lines <- c(
    "",
    "# =============================================================================",
    sprintf("# Extension -- Added %s by TaxaWizard", Sys.Date()),
    "# ============================================================================="
  )

  if (length(new_param_lines) > 0L) {
    new_step_lines <- c(new_step_lines, new_param_lines)
  }

  for (i in seq_along(dag$steps)) {
    step <- dag$steps[[i]]
    step_num <- last_step + i
    desc <- step$description %||% step$function_name
    output_var <- step$output_var %||% sprintf("step_%d_result", step_num)

    step_header <- sprintf("# --- Step %d: %s ---", step_num, desc)
    if (isFALSE(step$validated)) {
      step_header <- c(
        "# WARNING: this step was generated without a validated snippet; review before running",
        step_header
      )
    }

    new_step_lines <- c(
      new_step_lines,
      "",
      step_header,
      sprintf(
        "%s <- .run_step(%d, %s, quote({",
        output_var, step_num, .r_string(desc)
      ),
      paste0("  ", strsplit(step$code, "\n")[[1]]),
      "}))",
      ""
    )
  }

  # --- Update total step count in the script ---
  total_steps <- last_step + length(dag$steps)
  combined <- c(existing_lines, new_step_lines, "", footer_lines)

  # New-style scripts use a total_steps variable; update it
  combined <- sub(
    "^total_steps <- \\d+L.*$",
    sprintf(
      "total_steps <- %dL  # updated automatically when workflow is extended",
      total_steps
    ),
    combined
  )

  # Old-style scripts hardcode the count in sprintf; update that too
  # Pattern: step_id, <number>, description  →  step_id, <new_total>, description
  combined <- sub(
    "(step_id, )\\d+(, description)",
    sprintf("\\1%d\\2", total_steps),
    combined
  )

  writeLines(combined, script_path)
  script_path
}


#' Generate Methods Markdown from DAG
#'
#' Converts the workflow DAG into a .md file containing Methods text
#' describing the analytical steps taken.
#'
#' @param dag List. Workflow DAG.
#' @param output_dir Character. Output directory.
#'
#' @return Character: path to generated file.
#' @noRd
.generate_markdown <- function(dag, output_dir) {
  lines <- character()
  lines <- c(
    lines,
    sprintf("# Methods -- Generated %s by TaxaWizard", Sys.Date()),
    "",
    dag$methods_text %||% "Methods text will be generated after the workflow runs.",
    ""
  )

  filename <- sprintf("taxaid_methods_%s.md", format(Sys.Date(), "%Y%m%d"))
  filepath <- file.path(output_dir, filename)
  writeLines(lines, filepath)
  filepath
}


#' Generate Shiny App from DAG
#'
#' Converts the workflow DAG into a single-file Shiny app (app.R). Delegates
#' to \code{\link{workflow_app}} -- the real script-to-app converter -- when
#' a generated \code{.R} script is available. \code{workflow_app()} parses
#' the script's \verb{# --- User Parameters ---}/\verb{# --- Step N ---}
#' markers automatically, so no separate DAG-to-app translation is needed.
#'
#' @param dag List. Workflow DAG.
#' @param output_dir Character. Output directory.
#' @param script_path Character or NULL. Path to the sibling generated
#'   \code{.R} script (from \code{.generate_script()}), when the same
#'   \code{workflow_engine()} response also requested \code{"script"}.
#'   When \code{NULL} or when \code{shiny} is unavailable, a minimal
#'   placeholder app is written instead.
#'
#' @return Character: path to generated file.
#' @noRd
.generate_app <- function(dag, output_dir, script_path = NULL) {
  if (!is.null(script_path) && file.exists(script_path) &&
    requireNamespace("shiny", quietly = TRUE)) {
    return(workflow_app(
      script_path = script_path, output_dir = output_dir,
      launch = FALSE
    ))
  }

  # Fallback: no sibling script was generated in this response (the user
  # requested "app" without "script"), or shiny is unavailable. Write a
  # minimal placeholder that points the user at workflow_app() directly.
  lines <- c(
    "# Shiny app placeholder -- generated by TaxaWizard",
    "#",
    "# No workflow script was available to convert automatically. Generate",
    "# a script first (outputs including \"script\"), then run:",
    "#   TaxaWizard::workflow_app(\"path/to/taxaid_workflow_YYYYMMDD.R\")",
    "library(shiny)",
    "",
    "ui <- fluidPage(",
    "  titlePanel(\"TaxaID Workflow\"),",
    "  mainPanel(\"Run TaxaWizard::workflow_app() on a generated script to build this app.\")",
    ")",
    "",
    "server <- function(input, output, session) { }",
    "",
    "shinyApp(ui, server)"
  )

  filepath <- file.path(output_dir, "app.R")
  writeLines(lines, filepath)
  filepath
}


#' Widen an Existing Generated Script's Step 0 Edge List
#'
#' Finds the \code{workflow_check(edges = ...)} line a previous
#' \code{.generate_script()} wrote and rewrites it to the union of the edges
#' already listed and the edges of \code{dag}'s steps. Used when APPENDING to
#' a script, where writing a fresh Step 0 would either duplicate the existing
#' one or narrow it to only the new steps' requirements.
#'
#' Leaves the script untouched when there is nothing to do: no Step 0 line (a
#' hand-written script -- inserting a check into someone else's script is
#' not this function's business), an \code{edges = NULL} check
#' (already the widest possible), or no new edge ids.
#'
#' @param lines Character vector. The existing script's lines.
#' @param dag The DAG being appended.
#' @return \code{lines}, with at most one line changed.
#' @noRd
.widen_step0_edges <- function(lines, dag) {
  new_edges <- unique(vapply(dag$steps, function(s) as.character(s$edge_id %||% ""), ""))
  new_edges <- new_edges[nzchar(new_edges)]
  new_edges <- .keep_known_edges(new_edges, context = "appended Step 0")
  if (length(new_edges) == 0L) {
    return(lines)
  }

  idx <- grep("^\\.setup <- TaxaWizard::workflow_check\\(edges = ", lines)
  if (length(idx) == 0L) {
    return(lines)
  }
  idx <- idx[1L]
  line <- lines[idx]

  # edges = NULL already checks the whole ecosystem: nothing to widen.
  if (grepl("edges = NULL", line, fixed = TRUE)) {
    return(lines)
  }

  existing_edges <- unlist(regmatches(line, gregexpr('"[^"]*"', line)))
  existing_edges <- gsub('"', "", existing_edges, fixed = TRUE)

  merged <- unique(c(existing_edges, new_edges))
  if (setequal(merged, existing_edges)) {
    return(lines)
  }

  lines[idx] <- sprintf(
    ".setup <- TaxaWizard::workflow_check(edges = c(%s), verbose = TRUE)",
    paste(vapply(merged, .r_string, ""), collapse = ", ")
  )
  lines
}


#' Keep Only Edge Ids That Exist in the Workflow Graph
#'
#' A DAG's \code{edge_id} values come from the LLM, and an LLM will happily
#' invent one for a step the graph has no edge for -- P7(a)'s console dry run
#' produced \code{"load_match_df"} for its data-loading step, which is not an
#' edge at all. \code{workflow_check()} ignores an unknown id with a message,
#' so the generated script still RAN, but it shipped a fabricated identifier in
#' a line the user reads and may copy. Filter at the point of writing.
#'
#' Unknown ids are dropped with a warning rather than silently, because a
#' fabricated edge id usually means the LLM invented a STEP the graph does not
#' model -- worth seeing, even though it is not fatal.
#'
#' @param ids Character vector of candidate edge ids.
#' @param context Character. Where this is happening, for the warning text.
#' @return \code{ids} with unknown entries removed (possibly empty).
#' @noRd
.keep_known_edges <- function(ids, context = "Step 0") {
  if (length(ids) == 0L) {
    return(ids)
  }
  graph <- tryCatch(.load_graph(), error = function(e) NULL)
  if (is.null(graph) || is.null(graph$edges)) {
    return(ids)
  }
  known <- vapply(graph$edges, function(e) as.character(e$id %||% ""), "")
  unknown <- setdiff(ids, known)
  if (length(unknown) > 0L) {
    warning(sprintf(
      "TaxaWizard (%s): dropping %d edge id(s) not in the workflow graph: %s",
      context, length(unknown), paste(unknown, collapse = ", ")
    ), call. = FALSE)
  }
  ids[ids %in% known]
}


#' Add an Extension's Parameters to an Existing Script's Signature List
#'
#' Appended steps bring their own parameters, and a parameter absent from
#' \code{.workflow_params} is invisible to \code{.taxaid_step_signature()} --
#' so editing it would not invalidate the step that reads it, which is the
#' exact defect signatures exist to prevent. Widen the list in place, the same
#' way \code{.widen_step0_edges()} widens the setup check.
#'
#' A script with no \code{.workflow_params} line is left alone: it predates
#' signatures entirely, and injecting the name list without the helpers that
#' consume it would achieve nothing.
#'
#' @param lines Character vector. The existing script's lines.
#' @param dag The DAG being appended.
#' @return \code{lines}, with at most one line changed.
#' @noRd
.widen_workflow_params <- function(lines, dag) {
  new_params <- vapply(dag$parameters %||% list(), function(p) as.character(p$name %||% ""), "")
  new_params <- new_params[nzchar(new_params)]
  if (length(new_params) == 0L) {
    return(lines)
  }

  idx <- grep("^\\.workflow_params <- ", lines)
  if (length(idx) == 0L) {
    return(lines)
  }
  idx <- idx[1L]

  existing <- gsub('"', "", unlist(regmatches(lines[idx], gregexpr('"[^"]*"', lines[idx]))), fixed = TRUE)
  merged <- unique(c(existing, new_params))
  if (setequal(merged, existing)) {
    return(lines)
  }

  lines[idx] <- sprintf(
    ".workflow_params <- c(%s)",
    paste(vapply(merged, .r_string, ""), collapse = ", ")
  )
  lines
}
