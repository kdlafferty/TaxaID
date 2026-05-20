#' Interactive Workflow Chat (CLI Mode)
#'
#' @description
#' `r lifecycle::badge("deprecated")`
#'
#' \code{workflow_chat()} has been renamed to \code{\link{workflow_create}}.
#' This wrapper calls \code{workflow_create(mode = "console")} and will be
#' removed in a future version.
#'
#' @inheritParams workflow_create
#'
#' @return See \code{\link{workflow_create}}.
#'
#' @seealso \code{\link{workflow_create}}, \code{\link{workflow_fix}}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Use workflow_create() instead:
#' workflow_create(mode = "console")
#' }
workflow_chat <- function(model      = "claude-sonnet-4-6",
                          api_key    = NULL,
                          output_dir = ".",
                          trial      = FALSE) {

  message("Note: workflow_chat() is deprecated. Use workflow_create() instead.")
  workflow_create(
    mode       = "console",
    output_dir = output_dir,
    model      = model,
    api_key    = api_key,
    trial      = trial
  )
}


#' Fix a Generated Workflow After an Error
#'
#' Resumes the conversation from \code{\link{workflow_create}} by sending
#' the error message to the workflow engine. The engine diagnoses the
#' problem and generates a corrected script.
#'
#' When called with no arguments, opens an interactive prompt where you
#' can paste the error message directly (avoids quoting issues). You can
#' also pass the error as a string argument.
#'
#' @param error_text Character or missing. The error message from running
#'   the generated script. When missing, opens a \code{readline()} prompt
#'   for interactive paste. Can include the function call and stack trace.
#' @param context Character or NULL. Optional additional context
#'   (e.g. "this happened at step 3" or "the column is actually
#'   called 'ESV_ID' not 'ESVID'").
#' @param auto Logical. When \code{TRUE}, skips confirmation prompts
#'   and returns the regenerated script path (for programmatic use
#'   by generated scripts). Default \code{FALSE}.
#'
#' @return When \code{auto = FALSE}, invisibly returns the engine
#'   response. When \code{auto = TRUE}, invisibly returns the path
#'   to the regenerated script (or NULL if fix failed).
#'
#' @seealso \code{\link{workflow_create}} to start a new session
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Interactive mode (recommended) -- paste error at the prompt:
#' workflow_fix()
#'
#' # Direct mode (use single quotes to avoid nesting issues):
#' workflow_fix('Error in build_context: date must be NULL')
#'
#' # With additional context:
#' workflow_fix(context = "the column is called ESV_ID not ESVID")
#' }
workflow_fix <- function(error_text, context = NULL, auto = FALSE) {

  session <- .load_session()
  if (is.null(session)) {
    stop(
      "No saved workflow session found.\n",
      "Run workflow_create() first to create a workflow.",
      call. = FALSE
    )
  }

  # Interactive prompt when error_text is not provided
  if (missing(error_text)) {
    if (!interactive()) {
      stop("error_text is required in non-interactive mode.", call. = FALSE)
    }
    cat("Paste the error message below (press Enter twice when done):\n")
    lines <- character()
    repeat {
      line <- readline()
      if (!nzchar(trimws(line)) && length(lines) > 0L) break
      lines <- c(lines, line)
    }
    error_text <- paste(lines, collapse = "\n")
    if (!nzchar(trimws(error_text))) {
      cat("No error text provided. Cancelled.\n")
      return(invisible(NULL))
    }
  }

  # Build the error message for the engine
  user_msg <- paste0(
    "I ran the generated script and got this error:\n\n",
    error_text
  )
  if (!is.null(context)) {
    user_msg <- paste0(user_msg, "\n\nAdditional context: ", context)
  }

  history <- session$history
  history <- c(history, list(list(role = "user", content = user_msg)))

  if (!auto) cat("Diagnosing error...\n")

  # --- Build error-fix prompt with full parameter docs ---
  # Parse step number and edge from error text + session DAG
  error_context <- .parse_error_context(error_text, session)

  # Build the error_fix phase prompt with targeted documentation
  error_prompt <- tryCatch(
    .build_phase_prompt(
      phase    = "error_fix",
      context  = error_context,
      metadata = session$metadata
    ),
    error = function(e) NULL
  )

  # Add auto-mode instruction if applicable
  if (auto && !is.null(error_prompt)) {
    error_prompt <- paste0(
      error_prompt, "\n\n",
      "## AUTO MODE\n",
      "This is an automated fix attempt. Be CONSERVATIVE: only fix errors ",
      "you are confident about (wrong parameter name, missing package prefix). ",
      "For anything else, set status to 'incomplete' and describe what ",
      "diagnostics the user should run."
    )
  }

  result <- tryCatch(
    workflow_engine(
      history       = history,
      metadata      = session$metadata,
      model         = session$model,
      api_key       = session$api_key,
      system_prompt = error_prompt
    ),
    error = function(e) {
      list(status = "error", message = paste("Engine error:", conditionMessage(e)))
    }
  )

  if (!auto) cat(sprintf("\nAssistant: %s\n\n", result$message))

  # Add full structured response to history (enables phase detection)
  history <- c(history, list(list(
    role    = "assistant",
    content = jsonlite::toJSON(result, auto_unbox = TRUE)
  )))

  # Track generated script path for auto mode
  script_path <- NULL

  # If corrected, regenerate files
  if (identical(result$status, "complete") && !is.null(result$dag)) {

    do_regen <- auto
    if (!auto) {
      confirm <- readline(prompt = "Regenerate workflow? (yes/no): ")
      do_regen <- tolower(trimws(confirm)) %in% c("yes", "y")
    }

    if (do_regen) {
      # Clear stale checkpoints so the corrected script runs fresh
      checkpoint_dir <- file.path(session$output_dir, ".workflow_checkpoints")
      if (dir.exists(checkpoint_dir)) {
        unlink(checkpoint_dir, recursive = TRUE)
        if (!auto) cat("Cleared stale checkpoints.\n")
      }

      generated <- .generate_outputs(
        dag        = result$dag,
        outputs    = result$outputs %||% "script",
        output_dir = session$output_dir,
        trial      = session$trial
      )

      # Find the .R script in generated files
      r_files <- grep("\\.R$", generated, value = TRUE)
      if (length(r_files) > 0L) script_path <- r_files[1L]

      if (!auto) {
        cat("Updated files:\n")
        for (f in generated) cat(sprintf("  %s\n", f))
        cat("\nRun again. If more errors, call workflow_fix() again.\n\n")
      } else {
        message(sprintf("Auto-fix: regenerated %s", script_path %||% "script"))
      }

      # Save the correction for future sessions
      .save_correction(
        error_text      = error_text,
        fix_description = substr(result$message, 1, 200)
      )
    }
  }

  # Save updated state
  .save_session(history, session$metadata, session$model,
                session$api_key, session$output_dir, session$trial)

  # Return script path in auto mode for re-sourcing
  if (auto) return(invisible(script_path))
  invisible(result)
}


#' Parse Error Context from Error Text and Session State
#'
#' Extracts step number, edge ID, step code, and description from the
#' error text and the saved session's DAG. Used to build a targeted
#' error_fix phase prompt with full parameter docs.
#'
#' @param error_text Character. The error message from the user.
#' @param session List. The saved session from \code{.load_session()}.
#' @return Named list suitable for \code{.build_phase_prompt("error_fix", ...)}.
#' @noRd
.parse_error_context <- function(error_text, session) {
  ctx <- list(
    step_number      = "?",
    edge_id          = "unknown",
    step_description = "",
    error_message    = error_text,
    step_code        = ""
  )

  # Try to extract step number from error text
  # Common patterns: "Step 3 (...) failed:" or "step_3" or "Step 3:"
  step_match <- regmatches(error_text, regexpr("Step\\s+(\\d+)", error_text,
                                                ignore.case = TRUE))
  if (length(step_match) > 0L && nzchar(step_match)) {
    step_num <- as.integer(sub("\\D+", "", step_match))
    ctx$step_number <- step_num

    # Look up step in the saved DAG
    last_asst <- .last_assistant_state(session$history)
    if (!is.null(last_asst$dag) && !is.null(last_asst$dag$steps)) {
      steps <- last_asst$dag$steps
      if (step_num <= length(steps)) {
        step <- steps[[step_num]]
        ctx$edge_id <- step$edge_id %||% "unknown"
        ctx$step_description <- step$description %||% ""
        ctx$step_code <- step$code %||% ""
      }
    }

    # Also try to look up edge from selected_path
    if (identical(ctx$edge_id, "unknown") && !is.null(last_asst$selected_path)) {
      path <- unlist(last_asst$selected_path)
      if (step_num <= length(path)) {
        ctx$edge_id <- path[step_num]
      }
    }
  }

  ctx
}


#' Save Conversation State
#' @noRd
.save_session <- function(history, metadata, model, api_key,
                          output_dir, trial) {
  session <- list(
    history    = history,
    metadata   = metadata,
    model      = model,
    api_key    = api_key,
    output_dir = output_dir,
    trial      = trial,
    timestamp  = Sys.time()
  )
  session_path <- file.path(tempdir(), "taxawizard_session.rds")
  saveRDS(session, session_path)
}


#' Load Saved Conversation State
#' @noRd
.load_session <- function() {
  session_path <- file.path(tempdir(), "taxawizard_session.rds")
  if (!file.exists(session_path)) return(NULL)
  readRDS(session_path)
}
