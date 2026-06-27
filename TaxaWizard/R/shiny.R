utils::globalVariables(c("log_lines", "final_result"))

#' Convert a Workflow Script into a Shiny App
#'
#' Takes a workflow script (from \code{\link{workflow_create}} or any R script)
#' and produces a standalone Shiny app with user-facing controls for file paths,
#' parameters, and other inputs. The resulting app can be shared with
#' collaborators who only need to upload data and press "Run".
#'
#' For TaxaWizard-generated scripts (with \code{# --- User Parameters ---}
#' markers), parsing is automatic. For generic R scripts, the \code{annotate}
#' parameter controls how parameters and steps are identified.
#'
#' @param script_path Character. Path to an R script.
#' @param output_dir Character. Directory to write the app files (app.R
#'   and any supporting files). Default: same directory as \code{script_path}.
#' @param api_key_mode Character. How API keys are handled for LLM steps:
#'   \describe{
#'     \item{\code{"server"}}{No key widget. Uses the server's environment
#'       variable (e.g. \code{ANTHROPIC_API_KEY} set on the hosting machine).}
#'     \item{\code{"user"}}{Shows a password input. The user must paste their
#'       own API key before running LLM steps.}
#'     \item{\code{"both"}}{Shows a password input, but falls back to the
#'       server's environment variable if the user leaves it blank.}
#'   }
#' @param annotate Character. How to handle scripts without TaxaWizard markers:
#'   \describe{
#'     \item{\code{"auto"}}{(Default) Try TaxaWizard parsing first; if no steps
#'       found, ask the user to choose self-guided or LLM annotation.}
#'     \item{\code{"self"}}{Force console-based guided annotation (3 questions).}
#'     \item{\code{"llm"}}{Force LLM-assisted annotation (1 confirmation).}
#'     \item{\code{"none"}}{Error if no TaxaWizard markers found (backward
#'       compatible).}
#'   }
#' @param llm_fn Function. LLM provider for \code{annotate = "llm"} or when
#'   chosen interactively in \code{annotate = "auto"}. Default \code{NULL}.
#' @param launch Logical. When \code{TRUE} (default), immediately launch the
#'   generated app with \code{shiny::runApp()}.
#'
#' @return Invisibly returns the path to the generated app.R file.
#'
#' @seealso \code{\link{workflow_create}} to design the workflow first,
#'   \code{\link{annotate_script}} for standalone annotation
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # TaxaWizard script -- automatic
#' workflow_app("taxaid_workflow_20260506.R")
#'
#' # Any R script -- guided annotation
#' workflow_app("my_analysis.R", annotate = "self")
#'
#' # Any R script -- LLM annotation
#' workflow_app("my_analysis.R", annotate = "llm",
#'              llm_fn = TaxaTools::call_anthropic_api)
#'
#' # App where users supply their own API key
#' workflow_app("taxaid_workflow_20260506.R", api_key_mode = "user")
#' }
workflow_app <- function(script_path,
                         output_dir   = dirname(script_path),
                         api_key_mode = "server",
                         annotate     = c("auto", "self", "llm", "none"),
                         llm_fn       = NULL,
                         launch       = TRUE) {

  api_key_mode <- match.arg(api_key_mode, c("server", "user", "both"))
  annotate <- match.arg(annotate)

  if (!requireNamespace("shiny", quietly = TRUE)) {
    stop(
      "workflow_app() requires the shiny package.\n",
      "Install with: install.packages('shiny')",
      call. = FALSE
    )
  }

  if (missing(script_path) || !file.exists(script_path)) {
    stop(
      "Please provide the path to a workflow script.\n",
      "Example: workflow_app('my_script.R')",
      call. = FALSE
    )
  }

  lines <- readLines(script_path, warn = FALSE)
  parsed <- .parse_workflow_script(lines)

  if (length(parsed$steps) == 0L) {
    # No TaxaWizard markers -- handle based on annotate mode
    if (annotate == "none") {
      stop("No TaxaWizard step markers found in script.\n",
           "Use annotate = 'self' or 'llm' for generic R scripts.",
           call. = FALSE)
    }

    if (annotate == "auto") {
      message("No TaxaWizard markers found in script.")
      resp <- readline("Annotate interactively? (self/llm/cancel): ")
      resp <- trimws(tolower(resp))
      if (resp %in% c("cancel", "c", "n", "no", "")) {
        message("Cancelled.")
        return(invisible(NULL))
      }
      annotate <- if (resp %in% c("llm", "l")) "llm" else "self"
    }

    parsed <- annotate_script(script_path, mode = annotate, llm_fn = llm_fn)
    if (is.null(parsed)) {
      message("Annotation cancelled.")
      return(invisible(NULL))
    }
  }

  app_code <- .build_app_code(parsed, api_key_mode = api_key_mode)
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)
  app_path <- file.path(output_dir, "app.R")
  writeLines(app_code, app_path)

  # Copy USGS logo to app's www/ directory
  www_dir <- file.path(output_dir, "www")
  if (!dir.exists(www_dir)) dir.create(www_dir)
  logo_src <- system.file("www/usgs_logo.png", package = "TaxaWizard")
  if (nzchar(logo_src) && file.exists(logo_src)) {
    file.copy(logo_src, file.path(www_dir, "usgs_logo.png"), overwrite = TRUE)
  }
  message("Shiny app written to: ", app_path)
  message("  ", length(parsed$params), " parameters, ",
          length(parsed$steps), " steps")

  if (launch) {
    message("Launching app...")
    shiny::runApp(output_dir)
  }

  invisible(app_path)
}


# =============================================================================
# Script Parsing
# =============================================================================

#' Parse a TaxaWizard-generated workflow script
#' @param lines Character vector of script lines.
#' @return List with `$libraries`, `$params`, `$steps`.
#' @noRd
.parse_workflow_script <- function(lines) {
  list(
    libraries = .extract_libraries(lines),
    params    = .extract_params(lines),
    steps     = .extract_steps(lines)
  )
}


#' Extract library names from script
#' @noRd
.extract_libraries <- function(lines) {
  m <- regmatches(lines, regexpr("^library\\(([^)]+)\\)", lines))
  libs <- sub("^library\\(([^)]+)\\)", "\\1", m)
  libs <- libs[!libs %in% c("TaxaWizard", "TaxaWorkflow", "base")]
  unique(libs)
}


#' Extract and classify user parameters
#' @noRd
.extract_params <- function(lines) {
  # Find parameter section headers
  param_headers <- grep("^# --- (User|Extension) Parameters", lines)
  if (length(param_headers) == 0L) return(list())

  # Infrastructure params to skip
  skip_names <- c("debug_mode", "debug_n", "checkpoint_dir", "total_steps")

  params <- list()
  for (hdr in param_headers) {
    # Scan forward from header until next section marker or step
    i <- hdr + 1L
    while (i <= length(lines)) {
      ln <- lines[i]
      # Stop at next section marker
      if (grepl("^# ---", ln) && !grepl("^# --- (User|Extension) Parameters", ln)) break
      # Stop at extension/step/footer markers
      if (grepl("^# ={3,}", ln)) break

      # Try to match assignment
      m <- regmatches(ln, regexec("^(\\w+)\\s*<-\\s*(.+)$", ln))[[1]]
      if (length(m) == 3L) {
        name <- m[2]
        value_expr <- m[3]
        if (!name %in% skip_names) {
          params[[length(params) + 1L]] <- .classify_param(name, value_expr)
        }
      }
      i <- i + 1L
    }
  }

  # Deduplicate by name (extensions may re-declare)
  seen <- character()
  unique_params <- list()
  for (p in params) {
    if (!p$name %in% seen) {
      unique_params[[length(unique_params) + 1L]] <- p
      seen <- c(seen, p$name)
    }
  }
  unique_params
}


#' Classify a parameter by inspecting its value expression
#' @noRd
.classify_param <- function(name, value_expr) {
  ve <- trimws(value_expr)

  # Logical
  if (ve %in% c("TRUE", "FALSE")) {
    return(list(name = name, type = "logical", default = as.logical(ve), raw = ve))
  }

  # NULL
  if (ve == "NULL") {
    return(list(name = name, type = "null_param", default = NULL, raw = ve))
  }

  # Function reference (pkg::fn pattern)
  if (grepl("^\\w+::\\w+", ve)) {
    return(list(name = name, type = "function_ref", default = ve, raw = ve))
  }

  # Bare numeric (integer or double)
  if (grepl("^-?\\d+\\.?\\d*(L)?$", ve)) {
    val <- suppressWarnings(as.numeric(sub("L$", "", ve)))
    return(list(name = name, type = "numeric", default = val, raw = ve))
  }

  # Named numeric vector: c(name = N, ...)
  if (grepl("^c\\(\\s*\\w+\\s*=", ve)) {
    val <- tryCatch(eval(parse(text = ve)), error = function(e) NULL)
    return(list(name = name, type = "named_numeric", default = val, raw = ve))
  }

  # Numeric range: c(N, N) with exactly 2 unnamed numbers
  if (grepl("^c\\(\\s*-?\\d", ve)) {
    val <- tryCatch(eval(parse(text = ve)), error = function(e) NULL)
    if (!is.null(val) && is.numeric(val) && length(val) == 2L && is.null(names(val))) {
      return(list(name = name, type = "numeric_range", default = val, raw = ve))
    }
  }

  # data.frame(...)
  if (grepl("^data\\.frame\\(", ve)) {
    return(list(name = name, type = "data_frame", default = ve, raw = ve))
  }

  # String -- file path (input)
  if (grepl('^".*\\.(csv|tsv|txt|rds|xlsx|fasta|fa)"', ve, ignore.case = TRUE) &&
      !grepl("output|save|write", name, ignore.case = TRUE)) {
    val <- gsub('^"|"$', "", ve)
    return(list(name = name, type = "file_input", default = val, raw = ve))
  }

  # String -- file path (output)
  if (grepl('^".*\\.(csv|tsv|rds)"', ve, ignore.case = TRUE) &&
      grepl("output|save|write", name, ignore.case = TRUE)) {
    val <- gsub('^"|"$', "", ve)
    return(list(name = name, type = "file_output", default = val, raw = ve))
  }

  # Generic string
  if (grepl('^"', ve)) {
    val <- tryCatch(eval(parse(text = ve)), error = function(e) ve)
    return(list(name = name, type = "character", default = val, raw = ve))
  }

  # Fallback
  list(name = name, type = "character", default = ve, raw = ve)
}


#' Extract steps from script using brace counting
#' @noRd
.extract_steps <- function(lines) {
  steps <- list()

  # Find lines that start step assignments
  step_starts <- grep("^\\w+\\s*<-\\s*\\.run_step\\(", lines)

  for (si in step_starts) {
    ln <- lines[si]

    # Parse output_var, step_id, description
    m <- regmatches(ln, regexec(
      '^(\\w+)\\s*<-\\s*\\.run_step\\(\\s*(\\d+)\\s*,\\s*"([^"]*)"',
      ln
    ))[[1]]
    if (length(m) < 4L) next

    output_var <- m[2]
    step_id <- as.integer(m[3])
    description <- m[4]

    # Collect lines from step start to closing })) or }) using brace counting
    brace_count <- 0L
    started <- FALSE
    step_lines <- character()

    for (j in si:length(lines)) {
      line <- lines[j]
      step_lines <- c(step_lines, line)

      # Count braces (simple -- doesn't handle braces inside strings,
      # but generated scripts don't have that)
      for (ch in strsplit(line, "")[[1]]) {
        if (ch == "{") { brace_count <- brace_count + 1L; started <- TRUE }
        if (ch == "}") brace_count <- brace_count - 1L
      }
      if (started && brace_count <= 0L) break
    }

    steps[[length(steps) + 1L]] <- list(
      step_id     = step_id,
      description = description,
      output_var  = output_var,
      code_text   = paste(step_lines, collapse = "\n")
    )
  }

  steps
}


# =============================================================================
# Generic Script Segmentation
# =============================================================================

#' Segment a generic R script into libraries, parameters, and steps
#'
#' Pure R parsing -- no LLM, no user interaction. Identifies:
#' \itemize{
#'   \item Libraries: \code{library()} calls
#'   \item Parameter candidates: top-level \code{name <- literal} assignments
#'     before the first non-assignment expression
#'   \item Step candidates: remaining code, grouped by comment headers or
#'     blank-line-separated blocks
#' }
#'
#' @param lines Character vector of script lines.
#' @return List with \code{$libraries} (character), \code{$param_candidates}
#'   (list of lists with name/type/default/raw/line), and
#'   \code{$step_candidates} (list of lists with description/code_text/
#'   output_var/start_line/end_line).
#' @noRd
.segment_script <- function(lines) {
  libraries <- .extract_libraries(lines)


  # Use parse() with keep.source to get expression boundaries
  src <- tryCatch(
    parse(text = paste(lines, collapse = "\n"), keep.source = TRUE),
    error = function(e) {
      warning("Script has parse errors: ", conditionMessage(e), call. = FALSE)
      return(NULL)
    }
  )
  if (is.null(src)) {
    return(list(libraries = libraries,
                param_candidates = list(),
                step_candidates = list()))
  }

  srcref <- utils::getSrcref(src)
  n_expr <- length(src)

  # --- Phase 1: identify parameter candidates ---
  # Top-level `name <- literal` before the first non-assignment, non-library,

  # non-source expression.
  param_candidates <- list()
  first_step_expr <- n_expr + 1L  # index of first non-param expression

  for (k in seq_len(n_expr)) {
    expr_k <- src[[k]]
    ref_k <- srcref[[k]]
    line_start <- ref_k[1L]
    line_end   <- ref_k[3L]
    expr_text <- paste(lines[line_start:line_end], collapse = "\n")

    # Skip library() / require() calls
    if (.is_library_call(expr_k)) next

    # Skip source() calls
    if (.is_source_call(expr_k)) next

    # Check if this is a simple assignment: name <- literal
    if (.is_simple_assignment(expr_k)) {
      name <- as.character(expr_k[[2]])
      value_expr <- trimws(deparse(expr_k[[3]], width.cutoff = 500L))
      # Reconstruct the raw value from the source line for .classify_param
      raw_line <- trimws(lines[line_start])
      raw_value <- sub("^\\w+\\s*(<-|=)\\s*", "", raw_line)
      p <- .classify_param(name, raw_value)
      p$line <- line_start
      param_candidates[[length(param_candidates) + 1L]] <- p
    } else {
      # First non-assignment expression -- everything from here on is steps
      first_step_expr <- k
      break
    }
  }

  # --- Phase 2: identify step candidates ---
  # Collect remaining expressions and group by comment headers or proximity
  if (first_step_expr > n_expr) {
    # No step expressions found
    return(list(libraries = libraries,
                param_candidates = param_candidates,
                step_candidates = list()))
  }

  # Get source line ranges for remaining expressions
  expr_ranges <- list()
  for (k in first_step_expr:n_expr) {
    ref_k <- srcref[[k]]
    if (.is_library_call(src[[k]])) next
    if (.is_source_call(src[[k]])) next
    expr_ranges[[length(expr_ranges) + 1L]] <- list(
      start = ref_k[1L],
      end   = ref_k[3L],
      expr  = src[[k]]
    )
  }

  # Group expressions into steps using comment headers as boundaries
  step_candidates <- .group_into_steps(lines, expr_ranges)

  list(
    libraries        = libraries,
    param_candidates = param_candidates,
    step_candidates  = step_candidates
  )
}


#' Check if an expression is a library/require call
#' @noRd
.is_library_call <- function(expr) {
  if (is.call(expr)) {
    fn <- as.character(expr[[1L]])
    return(fn %in% c("library", "require"))
  }
  FALSE
}


#' Check if an expression is a source() call
#' @noRd
.is_source_call <- function(expr) {
  if (is.call(expr)) {
    fn <- as.character(expr[[1L]])
    return(fn == "source")
  }
  FALSE
}


#' Check if an expression is a simple assignment of a literal value
#' @noRd
.is_simple_assignment <- function(expr) {
  if (!is.call(expr)) return(FALSE)
  op <- as.character(expr[[1L]])
  if (!op %in% c("<-", "=")) return(FALSE)
  if (length(expr) != 3L) return(FALSE)

  # LHS must be a simple name (not subset, not $)
  lhs <- expr[[2]]
  if (!is.symbol(lhs)) return(FALSE)

  # RHS must be a literal, a c() of literals, or a simple string/number
  rhs <- expr[[3]]
  .is_literal_value(rhs)
}


#' Check if an expression is a literal value (or c() of literals)
#' @noRd
.is_literal_value <- function(expr) {
  # Atomic literal: number, string, logical, NULL
  if (is.numeric(expr) || is.character(expr) || is.logical(expr)) return(TRUE)
  if (is.null(expr)) return(TRUE)

  # Negative number: -N
  if (is.call(expr) && identical(expr[[1L]], as.symbol("-")) &&
      length(expr) == 2L && is.numeric(expr[[2L]])) return(TRUE)

  # c() of literals
  if (is.call(expr) && identical(expr[[1L]], as.symbol("c"))) {
    args <- as.list(expr)[-1L]
    return(all(vapply(args, .is_literal_value, logical(1L))))
  }

  # data.frame() call -- treat as parameter
  if (is.call(expr)) {
    fn_name <- tryCatch(as.character(expr[[1L]]), error = function(e) "")
    if (fn_name == "data.frame") return(TRUE)
  }

  FALSE
}


#' Group expression ranges into steps using comment headers as delimiters
#' @noRd
.group_into_steps <- function(lines, expr_ranges) {
  if (length(expr_ranges) == 0L) return(list())

  # Find comment-header lines: "# ---", "## Section", "# ===", "####",
  # or single-# comments that look like section headers (standalone, 3+ chars)
  header_pattern <- "^\\s*#{1,4}\\s*[-=]{3,}|^\\s*##?\\s+\\S.{2,}"
  header_lines <- grep(header_pattern, lines)

  # Also treat blank-line gaps (>1 blank line) between expressions as boundaries
  # Build groups: each group starts at a header or after a gap
  groups <- list()
  current_group <- list(exprs = list(), header = NULL)

  for (i in seq_along(expr_ranges)) {
    er <- expr_ranges[[i]]

    # Check if there is a comment header between previous expression and this one
    if (i > 1L) {
      prev_end <- expr_ranges[[i - 1L]]$end
      gap_start <- prev_end + 1L
      gap_end <- er$start - 1L

      if (gap_end >= gap_start) {
        # Look for headers in the gap
        gap_headers <- header_lines[header_lines >= gap_start &
                                    header_lines <= gap_end]
        # Look for blank-line gaps (2+ consecutive blank lines)
        gap_lines <- lines[gap_start:gap_end]
        has_blank_gap <- any(nchar(trimws(gap_lines)) == 0L) &&
                         (gap_end - gap_start + 1L) >= 1L

        if (length(gap_headers) > 0L || has_blank_gap) {
          # Save current group and start new one
          if (length(current_group$exprs) > 0L) {
            groups[[length(groups) + 1L]] <- current_group
          }
          # Use the last header in the gap as this group's header
          hdr_text <- NULL
          if (length(gap_headers) > 0L) {
            hdr_text <- .extract_header_text(lines[max(gap_headers)])
          }
          current_group <- list(exprs = list(), header = hdr_text)
        }
      }
    } else {
      # First expression -- check for headers above it
      if (er$start > 1L) {
        above_headers <- header_lines[header_lines < er$start]
        if (length(above_headers) > 0L) {
          current_group$header <- .extract_header_text(
            lines[max(above_headers)]
          )
        }
      }
    }

    current_group$exprs[[length(current_group$exprs) + 1L]] <- er
  }

  # Don't forget the last group
  if (length(current_group$exprs) > 0L) {
    groups[[length(groups) + 1L]] <- current_group
  }

  # Convert groups to step_candidates
  step_candidates <- list()
  for (gi in seq_along(groups)) {
    g <- groups[[gi]]
    exprs <- g$exprs

    start_line <- exprs[[1L]]$start
    end_line <- exprs[[length(exprs)]]$end
    code_text <- paste(lines[start_line:end_line], collapse = "\n")

    # Description: from header, or from first function call in the block
    description <- if (!is.null(g$header) && nzchar(g$header)) {
      g$header
    } else {
      .describe_code_block(exprs)
    }

    # Output var: last assignment's LHS
    output_var <- .last_assignment_var(exprs)

    step_candidates[[length(step_candidates) + 1L]] <- list(
      step_id     = gi,
      description = description,
      output_var  = output_var %||% paste0("step_", gi, "_result"),
      code_text   = code_text,
      start_line  = start_line,
      end_line    = end_line
    )
  }

  step_candidates
}


#' Extract descriptive text from a comment header line
#' @noRd
.extract_header_text <- function(line) {
  # Strip leading #, spaces, dashes, equals, underscores
  txt <- sub("^\\s*#{1,4}\\s*[-=_]*\\s*", "", line)
  txt <- sub("\\s*[-=_]*\\s*$", "", txt)
  trimws(txt)
}


#' Generate a description from the first expression in a code block
#' @noRd
.describe_code_block <- function(exprs) {
  for (er in exprs) {
    e <- er$expr
    if (is.call(e)) {
      fn <- tryCatch(deparse(e[[1L]], width.cutoff = 60L), error = function(e) "")
      fn <- paste(fn, collapse = "")
      # For assignments, use RHS function name
      if (fn %in% c("<-", "=") && length(e) >= 3L && is.call(e[[3L]])) {
        fn <- tryCatch(deparse(e[[3L]][[1L]], width.cutoff = 60L),
                       error = function(e) "")
        fn <- paste(fn, collapse = "")
      }
      if (nzchar(fn) && fn != "") {
        return(paste0("Run ", fn, "()"))
      }
    }
  }
  "Code block"
}


#' Find the last assignment variable name in a list of expression ranges
#' @noRd
.last_assignment_var <- function(exprs) {
  last_var <- NULL
  for (er in exprs) {
    e <- er$expr
    if (is.call(e)) {
      op <- tryCatch(as.character(e[[1L]]), error = function(e) "")
      if (op %in% c("<-", "=") && length(e) >= 2L && is.symbol(e[[2L]])) {
        last_var <- as.character(e[[2L]])
      }
    }
  }
  last_var
}


# =============================================================================
# Script Annotation (interactive + LLM)
# =============================================================================

#' Annotate a Generic R Script for Shiny Conversion
#'
#' Guides the user through identifying parameters and steps in any R script,
#' producing the same structure that \code{\link{workflow_app}} needs to
#' generate a Shiny app. Two modes are available:
#' \describe{
#'   \item{\code{"self"}}{Console-based guided annotation (3 questions):
#'     select parameters, confirm steps, confirm build.}
#'   \item{\code{"llm"}}{LLM analyzes the script and proposes parameters
#'     and steps; user confirms with one question.}
#' }
#'
#' @param script_path Character. Path to the R script to annotate.
#' @param mode Character. \code{"self"} for console readline or \code{"llm"}
#'   for LLM-assisted annotation.
#' @param llm_fn Function. LLM provider function (required when
#'   \code{mode = "llm"}). Should accept \code{prompt} and return a string.
#'   Default \code{NULL}.
#'
#' @return A list with \code{$libraries} (character vector),
#'   \code{$params} (list of param specs), and \code{$steps} (list of step
#'   specs) -- the same structure as \code{.parse_workflow_script()}.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Self-guided annotation
#' parsed <- annotate_script("my_analysis.R", mode = "self")
#'
#' # LLM-guided annotation
#' parsed <- annotate_script("my_analysis.R", mode = "llm",
#'                           llm_fn = TaxaTools::call_anthropic_api)
#' }
annotate_script <- function(script_path,
                            mode   = c("self", "llm"),
                            llm_fn = NULL) {
  mode <- match.arg(mode)

  if (!file.exists(script_path)) {
    stop("Script not found: ", script_path, call. = FALSE)
  }

  lines <- readLines(script_path, warn = FALSE)
  segmented <- .segment_script(lines)

  if (mode == "self") {
    .annotate_self(segmented, lines)
  } else {
    if (is.null(llm_fn)) {
      stop("llm_fn is required for mode = 'llm'.\n",
           "Example: annotate_script(path, mode = 'llm', ",
           "llm_fn = TaxaTools::call_anthropic_api)",
           call. = FALSE)
    }
    .annotate_llm(segmented, lines, script_path, llm_fn)
  }
}


#' Self-guided annotation via console readline
#' @noRd
.annotate_self <- function(segmented, lines) {
  libraries <- segmented$libraries
  param_cands <- segmented$param_candidates
  step_cands <- segmented$step_candidates

  # --- Question 1: Select parameters ---
  if (length(param_cands) > 0L) {
    message("\n--- Parameter Candidates ---")
    message("I found these potential parameters (top-level literal assignments):")
    for (i in seq_along(param_cands)) {
      p <- param_cands[[i]]
      message(sprintf("  [%d] %s = %s  (type: %s, line %d)",
                       i, p$name, p$raw, p$type, p$line))
    }
    message("")
    resp <- readline(
      "Which should be editable in the app? (numbers separated by commas, 'all', or 'none'): "
    )
    resp <- trimws(resp)

    if (tolower(resp) == "none" || resp == "") {
      selected_params <- list()
    } else if (tolower(resp) == "all") {
      selected_params <- param_cands
    } else {
      idx <- .parse_number_list(resp, length(param_cands))
      selected_params <- param_cands[idx]
    }
  } else {
    message("\nNo parameter candidates found (no top-level literal assignments).")
    selected_params <- list()
  }

  # --- Question 2: Confirm steps ---
  if (length(step_cands) > 0L) {
    message("\n--- Step Candidates ---")
    message("I found these code blocks:")
    for (i in seq_along(step_cands)) {
      s <- step_cands[[i]]
      n_lines <- s$end_line - s$start_line + 1L
      message(sprintf("  [%d] \"%s\" (lines %d-%d, %d lines, output: %s)",
                       i, s$description, s$start_line, s$end_line,
                       n_lines, s$output_var))
    }
    message("")
    resp <- readline("Does this grouping look right? (y/n, or enter numbers to keep): ")
    resp <- trimws(resp)

    if (tolower(resp) %in% c("y", "yes", "")) {
      selected_steps <- step_cands
    } else if (tolower(resp) %in% c("n", "no")) {
      message("You can merge steps by listing groups separated by semicolons.")
      message("Example: '1,2; 3; 4,5' merges steps 1-2, keeps 3, merges 4-5.")
      resp2 <- readline("Enter grouping (or press Enter to keep original): ")
      resp2 <- trimws(resp2)
      if (nzchar(resp2)) {
        selected_steps <- .merge_steps_by_groups(step_cands, resp2, lines)
      } else {
        selected_steps <- step_cands
      }
    } else {
      # Interpret as numbers to keep
      idx <- .parse_number_list(resp, length(step_cands))
      selected_steps <- step_cands[idx]
    }
  } else {
    message("\nNo step candidates found. The entire script will be one step.")
    # Treat entire non-param script as one step
    selected_steps <- list(list(
      step_id     = 1L,
      description = "Run script",
      output_var  = "result",
      code_text   = paste(lines, collapse = "\n")
    ))
  }

  # Renumber steps
  for (i in seq_along(selected_steps)) {
    selected_steps[[i]]$step_id <- i
  }

  # --- Question 3: Confirm ---
  message(sprintf(
    "\nReady to build app with %d parameter(s) and %d step(s). Proceed? (y/n): ",
    length(selected_params), length(selected_steps)
  ))
  resp <- readline("")
  if (!tolower(trimws(resp)) %in% c("y", "yes", "")) {
    message("Annotation cancelled.")
    return(invisible(NULL))
  }

  # Strip line metadata from params (not needed by .build_app_code)
  params <- lapply(selected_params, function(p) {
    p$line <- NULL
    p
  })

  list(
    libraries = libraries,
    params    = params,
    steps     = selected_steps
  )
}


#' Parse comma-separated numbers from user input
#' @noRd
.parse_number_list <- function(input, max_val) {
  nums <- suppressWarnings(as.integer(
    trimws(unlist(strsplit(input, "[,;\\s]+")))
  ))
  nums <- nums[!is.na(nums) & nums >= 1L & nums <= max_val]
  unique(nums)
}


#' Merge step candidates based on user-specified groups
#' @param step_cands List of step candidates.
#' @param grouping_str String like "1,2; 3; 4,5".
#' @param lines Original script lines.
#' @noRd
.merge_steps_by_groups <- function(step_cands, grouping_str, lines) {
  groups <- strsplit(grouping_str, ";")[[1]]
  merged <- list()

  for (gi in seq_along(groups)) {
    idx <- .parse_number_list(groups[gi], length(step_cands))
    if (length(idx) == 0L) next

    steps_in_group <- step_cands[idx]
    start_line <- min(vapply(steps_in_group, `[[`, integer(1), "start_line"))
    end_line <- max(vapply(steps_in_group, `[[`, integer(1), "end_line"))

    merged[[length(merged) + 1L]] <- list(
      step_id     = gi,
      description = steps_in_group[[1]]$description,
      output_var  = steps_in_group[[length(steps_in_group)]]$output_var,
      code_text   = paste(lines[start_line:end_line], collapse = "\n"),
      start_line  = start_line,
      end_line    = end_line
    )
  }

  merged
}


#' LLM-guided annotation
#' @noRd
.annotate_llm <- function(segmented, lines, script_path, llm_fn) {
  # Load prompt template
  prompt_path <- system.file("prompts", "annotate_script.md",
                             package = "TaxaWizard")
  if (!nzchar(prompt_path)) {
    stop("annotate_script.md prompt template not found.", call. = FALSE)
  }

  prompt_template <- paste(readLines(prompt_path, warn = FALSE), collapse = "\n")
  script_text <- paste(lines, collapse = "\n")

  # Build the prompt
  prompt <- gsub("{{SCRIPT_TEXT}}", script_text, prompt_template, fixed = TRUE)
  prompt <- gsub("{{SCRIPT_PATH}}", basename(script_path), prompt, fixed = TRUE)

  message("Sending script to LLM for analysis...")
  response <- llm_fn(prompt = prompt)

  # Parse the JSON response
  parsed <- .parse_annotation_response(response)
  if (is.null(parsed)) {
    message("LLM response could not be parsed. Falling back to self-guided mode.")
    return(.annotate_self(segmented, lines))
  }

  # Show summary and ask for confirmation
  message("\n--- LLM Annotation Summary ---")
  message(sprintf("Parameters (%d):", length(parsed$params)))
  for (p in parsed$params) {
    message(sprintf("  - %s (%s) = %s", p$name, p$type, p$raw))
  }
  message(sprintf("\nSteps (%d):", length(parsed$steps)))
  for (s in parsed$steps) {
    message(sprintf("  - [%d] %s", s$step_id, s$description))
  }

  message("")
  resp <- readline("Does this look right? (y/n/edit): ")
  resp <- trimws(tolower(resp))

  if (resp %in% c("n", "no")) {
    message("Falling back to self-guided mode...")
    return(.annotate_self(segmented, lines))
  }

  if (resp == "edit") {
    message("Switching to self-guided mode with LLM suggestions as starting point...")
    # Use LLM results as the segmented input for self-guided
    segmented$param_candidates <- parsed$params
    segmented$step_candidates <- parsed$steps
    return(.annotate_self(segmented, lines))
  }

  parsed
}


#' Parse the JSON response from the LLM annotation prompt
#' @noRd
.parse_annotation_response <- function(response) {
  # Try to extract JSON from fenced block or raw
  json_str <- response

  # Strip markdown fences
  json_str <- sub("(?s)^.*?```(?:json)?\\s*", "", json_str, perl = TRUE)
  json_str <- sub("(?s)\\s*```.*$", "", json_str, perl = TRUE)

  # Try to find a JSON object
  result <- tryCatch({
    obj <- jsonlite::fromJSON(json_str, simplifyVector = FALSE)

    # Extract params
    params <- lapply(obj$parameters %||% list(), function(p) {
      list(
        name    = p$name,
        type    = p$type %||% "character",
        default = p$default,
        raw     = as.character(p$default %||% ""),
        line    = p$line %||% NA_integer_
      )
    })

    # Extract steps
    steps <- lapply(seq_along(obj$steps %||% list()), function(i) {
      s <- obj$steps[[i]]
      list(
        step_id     = i,
        description = s$description %||% paste("Step", i),
        output_var  = s$output_var %||% paste0("step_", i, "_result"),
        code_text   = s$code_text %||% "",
        start_line  = s$start_line %||% NA_integer_,
        end_line    = s$end_line %||% NA_integer_
      )
    })

    list(
      libraries = obj$libraries %||% character(0),
      params    = params,
      steps     = steps
    )
  }, error = function(e) {
    NULL
  })

  result
}


# =============================================================================
# App Code Generation
# =============================================================================

#' Build complete app.R code from parsed script
#' @noRd
.build_app_code <- function(parsed, api_key_mode = "server") {
  libs <- parsed$libraries
  params <- parsed$params
  steps <- parsed$steps
  n_steps <- length(steps)

  # Detect if workflow has LLM steps (function_ref params present)
  has_llm <- any(vapply(params, function(p) p$type == "function_ref", logical(1)))

  # Collect file_input params for path replacement in step code
  file_params <- Filter(function(p) p$type == "file_input", params)

  # Apply path replacement to step code
  step_code_blocks <- vapply(steps, function(s) {
    code <- s$code_text
    for (fp in file_params) {
      # Replace hardcoded path literal with variable reference
      code <- gsub(fp$default, paste0('", ', fp$name, ', "'),
                   code, fixed = TRUE)
      # Clean up empty string concatenation artifacts
      code <- gsub(', ""', "", code, fixed = TRUE)
      code <- gsub('"", ', "", code, fixed = TRUE)
    }
    code
  }, character(1))

  # --- Build the code ---
  c(
    .app_header(libs),
    "",
    .app_run_step_shim(n_steps),
    "",
    .app_ui(params, steps, api_key_mode = api_key_mode, has_llm = has_llm),
    "",
    .app_server(params, steps, step_code_blocks, n_steps,
                api_key_mode = api_key_mode, has_llm = has_llm),
    "",
    "shinyApp(ui, server)"
  )
}


#' Generate app header with library calls
#' @noRd
.app_header <- function(libs) {
  # Always include TaxaTools so .onAttach() runs and sets options(TaxaID.provider).
  # Workflow scripts use TaxaTools:: notation (not library calls), so TaxaTools
  # would otherwise be absent from libs and call_api() would default to Anthropic.
  all_libs <- unique(c("TaxaTools", libs))
  c(
    "# =============================================================================",
    sprintf("# TaxaID Workflow App -- Generated %s by TaxaWizard", Sys.Date()),
    "# =============================================================================",
    "",
    "library(shiny)",
    vapply(all_libs, function(l) sprintf("library(%s)", l), character(1))
  )
}


#' Generate the Shiny-compatible .run_step shim
#' @noRd
.app_run_step_shim <- function(n_steps) {
  c(
    sprintf("total_steps <- %dL", n_steps),
    "",
    "# Shiny-compatible step runner (no checkpoint/auto-fix)",
    ".run_step <- function(step_id, description, code_expr, env = parent.frame()) {",
    "  if (is.function(code_expr)) code_expr()",
    "  else eval(code_expr, envir = env)",
    "}"
  )
}


#' Generate the UI code
#' @noRd
.app_ui <- function(params, steps, api_key_mode = "server", has_llm = FALSE) {
  # Build widget lines -- each param gets its widget + an info button
  widget_lines <- unlist(lapply(params, .widget_with_info))

  # API key widget (for "user" or "both" modes when LLM steps exist)
  api_key_widget <- character()
  if (has_llm && api_key_mode %in% c("user", "both")) {
    hint <- if (api_key_mode == "both") {
      " (optional -- leave blank to use server default)"
    } else {
      " (required for AI-assisted steps)"
    }
    api_key_widget <- c(
      "      shiny::hr(),",
      sprintf('      shiny::passwordInput("api_key", "API key%s"),', hint)
    )
  }

  # Step code viewer -- collapsible details for each step
  step_details <- unlist(lapply(seq_along(steps), function(i) {
    s <- steps[[i]]
    c(
      sprintf('      shiny::tags$details('),
      sprintf('        shiny::tags$summary(shiny::tags$strong("Step %d: %s")),',
              s$step_id, gsub('"', "'", s$description)),
      sprintf('        shiny::tags$pre(style = "font-size: 11px; max-height: 200px; overflow-y: auto;",'),
      sprintf('          "%s"', gsub('"', '\\\\"', gsub("\n", "\\\\n", s$code_text))),
      "        )",
      "      ),"
    )
  }))

  c(
    "ui <- shiny::fluidPage(",
    # CSS for info buttons + USGS header/footer
    '  shiny::tags$head(shiny::tags$style("',
    '    .param-row { margin-bottom: 5px; }',
    '    .info-btn { background: none; border: 1px solid #ccc; border-radius: 50%;',
    '      width: 22px; height: 22px; padding: 0; font-size: 12px; color: #666;',
    '      cursor: pointer; margin-left: 4px; vertical-align: middle; }',
    '    .info-btn:hover { background: #e8e8e8; color: #333; }',
    '    body > .container-fluid { padding-top: 0; }',
    '    .usgs-header { background: white; padding: 10px 15px;',
    '      border-bottom: 2px solid #234a22; }',
    '    .usgs-header img { height: 50px; vertical-align: middle; }',
    '    .usgs-header .usgs-title { color: #234a22; font-size: 18px;',
    '      font-weight: bold; margin-left: 15px; vertical-align: middle; }',
    '    .usgs-footer { background: #234a22; color: white; padding: 10px 15px;',
    '      margin-top: 20px; font-size: 11px; }',
    '    .usgs-footer a { color: #b3d4b3; }',
    '  ")),',
    # USGS header with logo from www/ directory
    '  shiny::tags$div(class = "usgs-header",',
    '    shiny::tags$img(src = "usgs_logo.png", alt = "USGS"),',
    '    shiny::tags$span(class = "usgs-title", "TaxaID Workflow")',
    "  ),",
    "  shiny::sidebarLayout(",
    "    shiny::sidebarPanel(width = 4,",
    '      shiny::h4("Parameters"),',
    paste0("      ", widget_lines),
    api_key_widget,
    "      shiny::hr(),",
    '      shiny::actionButton("run_btn", "Run Workflow",',
    '                          class = "btn-primary", width = "100%")',
    "    ),",
    "    shiny::mainPanel(width = 8,",
    '      shiny::tabsetPanel(',
    '        shiny::tabPanel("Workflow",',
    '          shiny::h4("Progress"),',
    '          shiny::tags$div(',
    '            style = "max-height: 400px; overflow-y: auto; background: #f5f5f5; padding: 10px; font-size: 12px; font-family: monospace; white-space: pre-wrap;",',
    '            shiny::textOutput("log_display")',
    "          ),",
    '          shiny::h4("Results"),',
    '          shiny::tableOutput("result_table"),',
    "          shiny::fluidRow(",
    "            shiny::column(3,",
    '              shiny::downloadButton("download_csv", "Download CSV")',
    "            ),",
    "            shiny::column(3,",
    '              shiny::downloadButton("download_rds", "Download RDS")',
    "            )",
    "          ),",
    '          shiny::hr(),',
    '          shiny::h4("Workflow Steps"),',
    '          shiny::tags$p(style = "color: #666; font-size: 12px;",',
    '            "Click a step to see the underlying R code."',
    "          ),",
    step_details,
    "        ),",
    # Help / About tab
    '        shiny::tabPanel("Help & About",',
    '          shiny::h4("About This Application"),',
    '          shiny::tags$p(',
    '            "This application was generated by ",',
    '            shiny::tags$a(href = "https://github.com/DOI-USGS/TaxaID",',
    '                          "TaxaID"),',
    '            ", a modular R ecosystem for Bayesian taxonomic assignment."',
    "          ),",
    '          shiny::tags$p(',
    '            "TaxaID is developed by the U.S. Geological Survey,",',
    '            " Western Ecological Research Center."',
    "          ),",
    '          shiny::h4("Citation"),',
    '          shiny::tags$p(style = "font-style: italic;",',
    '            "Lafferty, K.D., 2026, TaxaID -- A modular R ecosystem for ",',
    '            "Bayesian taxonomic assignment: U.S. Geological Survey ",',
    '            "software release, https://doi.org/10.5066/xxxxxx."',
    "          ),",
    '          shiny::h4("Disclaimer"),',
    '          shiny::tags$p(style = "font-size: 12px; color: #666;",',
    '            "This software is preliminary or provisional and is subject to ",',
    '            "revision. It is being provided to meet the need for timely best ",',
    '            "science. The software has not received final approval by the ",',
    '            "U.S. Geological Survey (USGS). No warranty, expressed or implied, ",',
    '            "is made by the USGS or the U.S. Government as to the functionality ",',
    '            "of the software and related material nor shall the fact of release ",',
    '            "constitute any such warranty. The software is provided on the ",',
    '            "condition that neither the USGS nor the U.S. Government shall be ",',
    '            "held liable for any damages resulting from the authorized or ",',
    '            "unauthorized use of the software."',
    "          ),",
    '          shiny::tags$p(style = "font-size: 12px; color: #666; font-style: italic;",',
    '            "Any use of trade, firm, or product names is for descriptive ",',
    '            "purposes only and does not imply endorsement by the U.S. Government."',
    "          )",
    "        )",
    "      )",
    "    )",
    "  ),",
    # USGS footer
    '  shiny::tags$div(class = "usgs-footer",',
    '    shiny::tags$a(href = "https://www.usgs.gov/policies-and-notices",',
    '                  "Policies and Notices"), " | ",',
    '    shiny::tags$a(href = "https://www.usgs.gov/accessibility-and-us-geological-survey",',
    '                  "Accessibility"), " | ",',
    '    shiny::tags$a(href = "https://www.doi.gov/disclaimer",',
    '                  "DOI Disclaimer"), " | ",',
    '    shiny::tags$a(href = "https://www.doi.gov/privacy",',
    '                  "Privacy")',
    "  )",
    ")"
  )
}


#' Generate a UI widget for one parameter
#' @noRd
.widget_code <- function(param) {
  nm <- param$name
  input_id <- paste0("param_", nm)

  # Descriptive labels for common TaxaWizard parameter names
  known_labels <- c(
    input_file       = "Input file",
    input_path       = "Input file",
    output_path      = "Output file path",
    output_file      = "Output file path",
    min_score        = "Min score (percent identity threshold)",
    max_gap          = "Max gap (score gap to second-best match)",
    rank_thresholds  = "Rank thresholds (min % identity per rank)",
    geographic_hint  = "Geographic location (e.g. 'Santa Barbara, CA, USA')",
    geographic_context = "Geographic context for habitat/occurrence queries",
    date             = "Sample date or year range (e.g. '2023' or '2020-2024')",
    habitat_scheme   = "Habitat classification scheme",
    target_group     = "Target organism group (e.g. 'fish', 'invertebrates')",
    marker           = "Molecular marker or barcode (e.g. 'MiFish', 'COI')",
    llm_fn           = "LLM provider for AI-assisted steps",
    barcode_term     = "Barcode marker for NCBI search (e.g. 'MiFish', '12S')",
    lat              = "Latitude (decimal degrees)",
    lon              = "Longitude (decimal degrees)",
    search_radius_deg = "Search radius (degrees) for occurrence data",
    year_range       = "Year range for occurrence data",
    target_backbone_id = "Taxonomic backbone (11 = GBIF, 9 = WoRMS, 4 = NCBI)",
    taxon_col        = "Column name containing taxon names"
  )

  label <- if (nm %in% names(known_labels)) {
    known_labels[[nm]]
  } else {
    lbl <- gsub("_", " ", nm)
    paste0(toupper(substring(lbl, 1, 1)), substring(lbl, 2))
  }

  switch(param$type,
    file_input = sprintf(
      'shiny::fileInput("%s", "%s", accept = c(".csv", ".tsv", ".txt", ".rds", ".fasta")),',
      input_id, label
    ),
    file_output = sprintf(
      'shiny::textInput("%s", "%s", value = "%s"),',
      input_id, label, param$default
    ),
    logical = sprintf(
      'shiny::checkboxInput("%s", "%s", value = %s),',
      input_id, label, toupper(as.character(param$default))
    ),
    numeric = sprintf(
      'shiny::numericInput("%s", "%s", value = %s),',
      input_id, label, param$default
    ),
    named_numeric = {
      # Multiple numericInput rows in a div
      nms <- names(param$default)
      vals <- unname(param$default)
      inner <- vapply(seq_along(nms), function(i) {
        sprintf(
          '  shiny::numericInput("%s_%s", "%s", value = %s)',
          input_id, nms[i], nms[i], vals[i]
        )
      }, character(1))
      c(
        sprintf('shiny::tags$fieldset(shiny::tags$legend("%s"),', label),
        paste0(inner, ","),
        "),"
      )
    },
    numeric_range = c(
      sprintf('shiny::fluidRow(shiny::column(6, shiny::numericInput("%s_1", "%s (min)", value = %s)),',
              input_id, label, param$default[1]),
      sprintf('               shiny::column(6, shiny::numericInput("%s_2", "%s (max)", value = %s))),',
              input_id, label, param$default[2])
    ),
    data_frame = {
      # Convert data.frame expression to CSV-like text for textarea
      df_val <- tryCatch(eval(parse(text = param$raw)), error = function(e) NULL)
      if (!is.null(df_val) && is.data.frame(df_val)) {
        csv_text <- paste(
          c(paste(names(df_val), collapse = ","),
            apply(df_val, 1, function(r) paste(r, collapse = ","))),
          collapse = "\\n"
        )
      } else {
        csv_text <- param$raw
      }
      sprintf(
        'shiny::textAreaInput("%s", "%s (CSV: first line = column name, then one value per line)", value = "%s", rows = 4),',
        input_id, label, csv_text
      )
    },
    function_ref = sprintf(
      'shiny::selectInput("%s", "%s", choices = c("Auto-detect" = "TaxaTools::call_api", "Anthropic Claude" = "TaxaTools::call_anthropic_api", "Azure OpenAI (DOI)" = "TaxaTools::call_azure_openai_api", "OpenAI GPT" = "TaxaTools::call_openai_api", "Google Gemini" = "TaxaTools::call_gemini_api", "Ollama (local)" = "TaxaTools::call_ollama_api"), selected = "%s"),',
      input_id, label, param$default
    ),
    null_param = sprintf(
      'shiny::textInput("%s", "%s (leave empty for NULL)", value = ""),',
      input_id, label
    ),
    # Default: character
    sprintf(
      'shiny::textInput("%s", "%s", value = "%s"),',
      input_id, label, gsub('"', '\\\\"', as.character(param$default))
    )
  )
}


#' Wrap a widget with an info button that opens a help modal
#' @noRd
.widget_with_info <- function(param) {
  nm <- param$name
  btn_id <- paste0("info_", nm)
  widget_lines <- .widget_code(param)

  # Build help text for the modal
  help <- .param_help_text(param)

  # Wrap: info button on a line, then the widget
  c(
    sprintf('shiny::tags$div(class = "param-row",'),
    sprintf('  shiny::actionButton("%s", "i", class = "info-btn",', btn_id),
    sprintf('    title = "Click for help on this parameter"),'),
    paste0("  ", widget_lines),
    "),"
  )
}


#' Generate help text for a parameter (used in info modal)
#' @noRd
.param_help_text <- function(param) {
  nm <- param$name
  type_desc <- switch(param$type,
    file_input     = "Upload a data file. Accepted formats: CSV, TSV, TXT, RDS, FASTA.",
    file_output    = "File path where results will be saved.",
    logical        = "TRUE or FALSE toggle.",
    numeric        = "A single numeric value.",
    named_numeric  = "A set of numeric thresholds, one per taxonomic rank. Higher values are more stringent.",
    numeric_range  = "A pair of numbers defining a range (min and max).",
    data_frame     = "Tabular data in CSV format. First line is the column name, followed by one value per line.",
    function_ref   = "Choose which AI language model provider to use for LLM-assisted steps.",
    null_param     = "Optional text value. Leave blank for no value (NULL).",
    "A text value."
  )

  # Known detailed help for specific parameters
  known_help <- list(
    input_file = "The primary input data file for this workflow. Typically a CSV with one row per sample-by-reference match, including columns for sample ID, percent identity score, and taxonomy.",
    min_score = "Minimum percent identity score to accept a taxonomic match. Matches below this threshold are excluded from consensus. Typical values: 95-98 for eDNA barcoding.",
    max_gap = "Maximum allowed gap (in percent identity points) between the best match and the second-best match. A smaller gap means the assignment is more ambiguous. Typical values: 1-5.",
    rank_thresholds = "Minimum percent identity required to assign taxonomy at each rank. For example, 98% for species means a match must be at least 98% identical to assign a species name. Lower ranks (family, order) accept lower scores.",
    geographic_hint = "A text description of the sampling location and environment. Used by the AI to assess whether detected taxa are plausible for this area. Example: 'Point Conception, California, USA - coastal marine'.",
    date = "The year or year range when samples were collected. Used to establish ecological context. Can be a single year ('2023') or a range ('2020-2024').",
    habitat_scheme = "A list of habitat categories relevant to the study site. The AI uses this to classify detected taxa by habitat. Enter as CSV: column name on the first line, then one habitat per line.",
    target_group = "The broad organism group being studied (e.g., 'fish', 'invertebrates', 'plants'). Helps the AI focus its ecological assessment.",
    marker = "The molecular barcode marker used for sequencing (e.g., 'MiFish' for fish 12S, 'COI' for invertebrate cytochrome oxidase I). Helps assess taxonomic resolution expectations.",
    llm_fn = "The AI provider for LLM-assisted steps (context inference, expert review). Anthropic Claude is the default and best-tested option. All providers require an API key.",
    lat = "Latitude of the sampling site in decimal degrees (e.g., 34.45 for Santa Barbara, CA).",
    lon = "Longitude of the sampling site in decimal degrees (negative for Western hemisphere, e.g., -119.85).",
    search_radius_deg = "How far from the sampling coordinates to search for occurrence records (in degrees). Default 5 degrees. Smaller values give more local results but may have too few records for modeling.",
    year_range = "Year range for querying occurrence databases (GBIF). Only records from within this range are used to build priors.",
    barcode_term = "The barcode marker name for NCBI sequence searches. Use gene names (12S, COI, 16S) rather than primer names (MiFish, Leray).",
    target_backbone_id = "Which taxonomic backbone to use for name resolution. 11 = GBIF (best for occurrence data), 9 = WoRMS (marine taxa), 4 = NCBI (best for molecular data)."
  )

  detail <- if (nm %in% names(known_help)) known_help[[nm]] else type_desc

  default_str <- if (is.null(param$default) || identical(param$default, "")) {
    "None"
  } else if (is.numeric(param$default) && length(param$default) > 1) {
    paste(names(param$default), "=", param$default, collapse = ", ")
  } else {
    as.character(param$default)
  }

  list(
    detail = detail,
    type = param$type,
    default = default_str
  )
}


#' Generate the server function code
#' @noRd
.app_server <- function(params, steps, step_code_blocks, n_steps,
                        api_key_mode = "server", has_llm = FALSE) {
  # Build parameter assembly lines
  param_assembly <- unlist(lapply(params, .param_assembly_line))

  # Build step execution lines -- code is included literally and
  # executed in `env` via eval(quote({...}), envir = env).
  # setProgress() is called in the server context (outside eval) so
  # Shiny can flush the progress update to the browser.
  # On error, workflow halts (does not continue to next step).
  step_exec <- character()
  for (i in seq_along(steps)) {
    s <- steps[[i]]
    code <- step_code_blocks[i]
    code_lines <- strsplit(code, "\n")[[1]]
    short_desc <- if (nchar(s$description) > 60) {
      paste0(substr(s$description, 1, 57), "...")
    } else {
      s$description
    }

    step_exec <- c(step_exec,
      "",
      sprintf("      # Step %d: %s", s$step_id, s$description),
      sprintf('      if (!.failed) {'),
      sprintf('        shiny::setProgress(value = %d, detail = "Step %d/%d: %s")',
              i - 1L, s$step_id, n_steps, gsub('"', "'", short_desc)),
      sprintf('        .log(sprintf("Step %%d/%d: %%s ...", %d, "%s"))',
              n_steps, s$step_id, gsub('"', "'", short_desc)),
      "        tryCatch(eval(quote({",
      sprintf("          %s", code_lines),
      "        }), envir = env), error = function(e) {",
      sprintf('          .log(sprintf("STEP %d FAILED: %%s", conditionMessage(e)))', s$step_id),
      "          .failed <<- TRUE",
      "        })",
      sprintf('        if (!.failed) .log("  done.")'),
      "      }"
    )
  }

  # Last step's output var
  last_var <- steps[[length(steps)]]$output_var

  # Check which params are file_input for validation
  file_input_params <- Filter(function(p) p$type == "file_input", params)

  # Build file validation lines
  file_checks <- character()
  if (length(file_input_params) > 0L) {
    file_checks <- c(
      "    # Validate file uploads",
      unlist(lapply(file_input_params, function(p) {
        input_id <- paste0("param_", p$name)
        c(
          sprintf('    if (is.null(input$%s)) {', input_id),
          sprintf('      shiny::showModal(shiny::modalDialog('),
          sprintf('        title = "Missing input",'),
          sprintf('        "Please upload a file for: %s",', gsub("_", " ", p$name)),
          sprintf('        easyClose = TRUE'),
          sprintf('      ))'),
          sprintf('      return()'),
          sprintf('    }')
        )
      })),
      ""
    )
  }

  # Build info button modal observers
  info_observers <- unlist(lapply(params, function(p) {
    btn_id <- paste0("info_", p$name)
    help <- .param_help_text(p)
    label <- gsub("_", " ", p$name)
    label <- paste0(toupper(substring(label, 1, 1)), substring(label, 2))
    c(
      sprintf('  shiny::observeEvent(input$%s, {', btn_id),
      sprintf('    shiny::showModal(shiny::modalDialog('),
      sprintf('      title = "%s",', gsub('"', "'", label)),
      sprintf('      shiny::tags$p(shiny::tags$strong("Description: "),'),
      sprintf('        "%s"),', gsub('"', "'", help$detail)),
      sprintf('      shiny::tags$p(shiny::tags$strong("Type: "), "%s"),', help$type),
      sprintf('      shiny::tags$p(shiny::tags$strong("Default: "), "%s"),',
              gsub('"', "'", help$default)),
      "      easyClose = TRUE, size = \"s\"",
      "    ))",
      "  })",
      ""
    )
  }))

  # API key setup code
  # Find the function_ref param's input id (for provider detection)
  fn_ref_param <- Filter(function(p) p$type == "function_ref", params)
  fn_input_id <- if (length(fn_ref_param) > 0L) {
    paste0("param_", fn_ref_param[[1]]$name)
  } else {
    "param_llm_fn"  # fallback
  }

  api_key_setup <- character()
  if (has_llm && api_key_mode == "user") {
    api_key_setup <- c(
      '    # Set API key from user input',
      '    if (!nzchar(input$api_key)) {',
      '      shiny::showModal(shiny::modalDialog(',
      '        title = "API key required",',
      '        "Please enter your API key before running LLM-assisted steps.",',
      '        easyClose = TRUE',
      '      ))',
      '      return()',
      '    }',
      '    # Detect which provider is selected and set the appropriate env var',
      sprintf('    .key_var <- if (grepl("openai", input$%s, ignore.case = TRUE)) "OPENAI_API_KEY"', fn_input_id),
      sprintf('      else if (grepl("gemini", input$%s, ignore.case = TRUE)) "GEMINI_API_KEY"', fn_input_id),
      '      else "ANTHROPIC_API_KEY"',
      '    .old_key <- Sys.getenv(.key_var)',
      '    do.call(Sys.setenv, stats::setNames(list(input$api_key), .key_var))',
      '    on.exit(do.call(Sys.setenv, stats::setNames(list(.old_key), .key_var)), add = TRUE)',
      ""
    )
  } else if (has_llm && api_key_mode == "both") {
    api_key_setup <- c(
      '    # Set API key from user input (or fall back to server default)',
      '    if (nzchar(input$api_key)) {',
      '      .key_var <- if (grepl("openai", input$param_llm_fn, ignore.case = TRUE)) "OPENAI_API_KEY"',
      '        else if (grepl("gemini", input$param_llm_fn, ignore.case = TRUE)) "GEMINI_API_KEY"',
      '        else "ANTHROPIC_API_KEY"',
      '      .old_key <- Sys.getenv(.key_var)',
      '      do.call(Sys.setenv, stats::setNames(list(input$api_key), .key_var))',
      '      on.exit(do.call(Sys.setenv, stats::setNames(list(.old_key), .key_var)), add = TRUE)',
      '    }',
      ""
    )
  }

  c(
    "server <- function(input, output, session) {",
    "  log_lines <- shiny::reactiveVal(character())",
    "  final_result <- shiny::reactiveVal(NULL)",
    "",
    info_observers,
    "  shiny::observeEvent(input$run_btn, {",
    "    log_lines(character())",
    "    final_result(NULL)",
    "",
    file_checks,
    api_key_setup,
    "    # Helper to append to log and flush to UI",
    '    .log <- function(msg) {',
    '      log_lines(c(log_lines(), msg))',
    '    }',
    "",
    "    # Assemble parameters from widgets",
    "    env <- new.env(parent = globalenv())",
    "    assign(\".run_step\", .run_step, envir = env)",
    paste0("    ", param_assembly),
    "",
    "    .failed <- FALSE",
    sprintf("    shiny::withProgress(message = 'Running workflow', value = 0, max = %d, {", n_steps),
    step_exec,
    "    })",
    "",
    "    # Capture final result",
    "    if (.failed) {",
    '      .log("")',
    '      .log("Workflow halted due to error. See above.")',
    "    } else {",
    sprintf("      if (exists(\"%s\", envir = env) && is.data.frame(env$%s)) {",
            last_var, last_var),
    sprintf("        final_result(env$%s)", last_var),
    sprintf('        .log(sprintf("\\nWorkflow complete. Result: %%d rows, %%d columns.", nrow(env$%s), ncol(env$%s)))',
            last_var, last_var),
    "      } else {",
    '        .log("\\nWorkflow complete but no data frame result to display.")',
    "      }",
    "    }",
    "  })",
    "",
    '  output$log_display <- shiny::renderText({',
    '    paste(log_lines(), collapse = "\\n")',
    "  })",
    "",
    "  output$result_table <- shiny::renderTable({",
    "    req(final_result())",
    "    res <- final_result()",
    "    # Convert list columns to character for display",
    "    for (col in names(res)) {",
    "      if (is.list(res[[col]])) res[[col]] <- vapply(res[[col]], toString, character(1))",
    "    }",
    "    if (nrow(res) > 100) head(res, 100) else res",
    "  })",
    "",
    "  output$download_csv <- shiny::downloadHandler(",
    '    filename = function() paste0("taxaid_results_", Sys.Date(), ".csv"),',
    "    content = function(file) {",
    "      req(final_result())",
    "      utils::write.csv(final_result(), file, row.names = FALSE)",
    "    }",
    "  )",
    "",
    "  output$download_rds <- shiny::downloadHandler(",
    '    filename = function() paste0("taxaid_results_", Sys.Date(), ".rds"),',
    "    content = function(file) {",
    "      req(final_result())",
    "      saveRDS(final_result(), file)",
    "    }",
    "  )",
    "}"
  )
}


#' Generate one line of parameter assembly code for the server
#' @noRd
.param_assembly_line <- function(param) {
  nm <- param$name
  input_id <- paste0("param_", nm)

  switch(param$type,
    file_input = c(
      sprintf('if (!is.null(input$%s)) {', input_id),
      sprintf('  assign("%s", input$%s$datapath, envir = env)', nm, input_id),
      "} else {",
      sprintf('  assign("%s", NULL, envir = env)', nm),
      "}"
    ),
    file_output = sprintf('assign("%s", input$%s, envir = env)', nm, input_id),
    logical = sprintf('assign("%s", input$%s, envir = env)', nm, input_id),
    numeric = sprintf('assign("%s", input$%s, envir = env)', nm, input_id),
    named_numeric = {
      nms <- names(param$default)
      inner <- vapply(nms, function(n) {
        sprintf('"%s" = input$%s_%s', n, input_id, n)
      }, character(1))
      sprintf('assign("%s", c(%s), envir = env)', nm, paste(inner, collapse = ", "))
    },
    numeric_range = sprintf(
      'assign("%s", c(input$%s_1, input$%s_2), envir = env)',
      nm, input_id, input_id
    ),
    data_frame = c(
      paste0('.df_text <- input$', input_id),
      'if (nzchar(trimws(.df_text))) {',
      paste0('  assign("', nm, '", utils::read.csv(text = .df_text, stringsAsFactors = FALSE), envir = env)'),
      "} else {",
      paste0('  assign("', nm, '", NULL, envir = env)'),
      "}"
    ),
    function_ref = c(
      sprintf('.fn_str <- input$%s', input_id),
      sprintf('assign("%s", eval(parse(text = .fn_str)), envir = env)', nm)
    ),
    null_param = c(
      sprintf('if (nzchar(trimws(input$%s))) {', input_id),
      sprintf('  assign("%s", input$%s, envir = env)', nm, input_id),
      "} else {",
      sprintf('  assign("%s", NULL, envir = env)', nm),
      "}"
    ),
    # Default: character
    sprintf('assign("%s", input$%s, envir = env)', nm, input_id)
  )
}
