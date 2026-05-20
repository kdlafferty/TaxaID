#' Save Workflow Context to Disk
#'
#' Writes a \code{workflow_context.json} file alongside the generated script
#' so that future \code{workflow_create()} sessions can resume without
#' re-interviewing the user.
#'
#' @param dag List. The complete workflow DAG.
#' @param output_dir Character. Directory to write context file.
#' @noRd
.save_context <- function(dag, output_dir) {

  ctx <- list(
    parameters = dag$parameters,
    outputs    = dag$outputs %||% "script",
    timestamp  = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  )

  filepath <- file.path(output_dir, "workflow_context.json")
  writeLines(
    jsonlite::toJSON(ctx, auto_unbox = TRUE, pretty = TRUE),
    filepath
  )
  filepath
}


#' Load Saved Workflow Context
#'
#' Reads \code{workflow_context.json} from the output directory, if present.
#'
#' @param output_dir Character. Directory to check.
#' @return Named list of context, or NULL if no context file exists.
#' @noRd
.load_context <- function(output_dir) {

  filepath <- file.path(output_dir, "workflow_context.json")
  if (!file.exists(filepath)) return(NULL)

  tryCatch(
    jsonlite::fromJSON(filepath, simplifyVector = FALSE),
    error = function(e) NULL
  )
}


#' Format Saved Context for System Prompt Injection
#'
#' Converts loaded context into a brief text block for the system prompt
#' so the LLM knows what the user already specified.
#'
#' @param ctx List from \code{.load_context()}.
#' @return Character string for prompt injection, or empty string.
#' @noRd
.format_context_for_prompt <- function(ctx) {
  if (is.null(ctx) || length(ctx$parameters) == 0L) return("")

  lines <- "# PREVIOUS SESSION CONTEXT\nThe user has previously specified:"
  for (param in ctx$parameters) {
    lines <- c(lines, sprintf(
      "- %s = %s (%s)",
      param$name,
      param$value %||% "unset",
      param$description %||% ""
    ))
  }
  lines <- c(lines,
    "",
    "Use these values as defaults. Ask the user if they want to change any.",
    ""
  )
  paste(lines, collapse = "\n")
}


# =============================================================================
# Per-user corrections file
# =============================================================================

#' Get Corrections File Path
#' @noRd
.corrections_path <- function() {
  dir <- file.path(Sys.getenv("HOME"), ".taxawizard")
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  file.path(dir, "corrections.json")
}


#' Load User Corrections
#'
#' Reads the per-user corrections file that accumulates fixes from
#' \code{workflow_fix()} sessions. These corrections are injected into
#' the system prompt to prevent repeat mistakes.
#'
#' @return List of correction entries, or empty list.
#' @noRd
.load_corrections <- function() {
  path <- .corrections_path()
  if (!file.exists(path)) return(list())

  tryCatch(
    jsonlite::fromJSON(path, simplifyVector = FALSE),
    error = function(e) list()
  )
}


#' Save a Correction
#'
#' Appends a correction entry after a successful \code{workflow_fix()}.
#'
#' @param error_text Character. The original error message.
#' @param fix_description Character. What was wrong and how it was fixed.
#' @noRd
.save_correction <- function(error_text, fix_description) {
  corrections <- .load_corrections()

  entry <- list(
    error   = error_text,
    fix     = fix_description,
    date    = format(Sys.time(), "%Y-%m-%d"),
    applied = TRUE
  )

  corrections <- c(corrections, list(entry))

  # Keep last 50 corrections
  if (length(corrections) > 50L) {
    corrections <- corrections[(length(corrections) - 49L):length(corrections)]
  }

  writeLines(
    jsonlite::toJSON(corrections, auto_unbox = TRUE, pretty = TRUE),
    .corrections_path()
  )
}


#' Format Corrections for System Prompt Injection
#'
#' Converts corrections into a text block for the system prompt.
#'
#' @return Character string, or empty string if no corrections.
#' @noRd
.format_corrections_for_prompt <- function() {
  corrections <- .load_corrections()
  if (length(corrections) == 0L) return("")

  # Only inject the 5 most recent corrections to keep prompt size reasonable
  if (length(corrections) > 5L) {
    corrections <- corrections[(length(corrections) - 4L):length(corrections)]
  }

  lines <- c(
    "# KNOWN ISSUES (from previous sessions)",
    "Do NOT make these mistakes again:",
    ""
  )

  for (corr in corrections) {
    lines <- c(lines, sprintf("- ERROR: %s", substr(corr$error, 1, 100)))
    lines <- c(lines, sprintf("  FIX: %s", substr(corr$fix, 1, 100)))
    lines <- c(lines, "")
  }

  paste(lines, collapse = "\n")
}
