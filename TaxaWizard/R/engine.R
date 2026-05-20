#' Run the Workflow Engine
#'
#' Stateless core function that takes the full conversation history and
#' determines the current phase, builds a phase-specific system prompt,
#' calls the LLM, and returns a structured JSON response.
#'
#' The engine operates in three phases:
#' \enumerate{
#'   \item \strong{Classify}: Identify what data the user has and what they want.
#'   \item \strong{Path Select}: Present valid workflow paths (computed in R)
#'     and let the user choose.
#'   \item \strong{Parameterize}: Fill in parameter values using pre-validated
#'     code snippets.
#' }
#'
#' Phase detection is stateless — determined entirely from conversation history.
#'
#' @param history List of message objects, each with \code{role}
#'   (\code{"user"} or \code{"assistant"}) and \code{content} (character).
#'   Assistant content should be the full JSON response string (not just
#'   the message text) so phase detection works correctly.
#' @param metadata Named list of package metadata from
#'   \code{.load_metadata()}. When \code{NULL} (default), loads all
#'   available TaxaID package metadata automatically.
#' @param model Character. LLM model ID. Default \code{"claude-opus-4-6"}.
#' @param api_key Character or NULL. Anthropic API key.
#' @param system_prompt Character or NULL. Custom system prompt override.
#'   When \code{NULL} (default), builds phase-specific prompt automatically.
#'
#' @return A list with components:
#' \describe{
#'   \item{\code{status}}{Character: \code{"incomplete"} (more info needed),
#'     \code{"complete"} (ready to generate), or \code{"error"}.}
#'   \item{\code{phase}}{Character: current phase (\code{"classify"},
#'     \code{"path_select"}, \code{"parameterize"}, \code{"error_fix"}).}
#'   \item{\code{message}}{Character: the assistant's response text.}
#'   \item{\code{input_type}}{Character or NULL: classified input node ID.}
#'   \item{\code{output_type}}{Character or NULL: classified output node ID.}
#'   \item{\code{selected_path}}{Character vector or NULL: edge IDs of
#'     the selected path.}
#'   \item{\code{dag}}{List or NULL: the workflow DAG when status is
#'     \code{"complete"}.}
#'   \item{\code{outputs}}{Character vector: requested output types.}
#' }
#'
#' @export
#'
#' @examples
#' \dontrun{
#' history <- list(
#'   list(role = "user", content = "I have 12S eDNA data and want to
#'     identify fish species from a coral reef in Hawaii.")
#' )
#' result <- workflow_engine(history)
#' cat(result$message)
#' }
workflow_engine <- function(history,
                            metadata      = NULL,
                            model         = "claude-opus-4-6",
                            api_key       = NULL,
                            system_prompt = NULL) {

  # Wrap the engine body in a tryCatch so that any unexpected

  # NULL/NA-in-if errors produce a recoverable response instead of crashing.
  tryCatch(
    .workflow_engine_impl(history, metadata, model, api_key, system_prompt),
    error = function(e) {
      msg <- conditionMessage(e)
      # Re-throw API and configuration errors as-is
      if (grepl("API|ANTHROPIC_API_KEY|Prompt template", msg)) stop(e)
      # Wrap unexpected errors (e.g. NA-in-if from LLM response parsing)
      warning("workflow_engine internal error: ", msg, call. = FALSE)
      list(
        status  = "incomplete",
        phase   = "classify",
        message = paste0(
          "I encountered an internal processing error. ",
          "Could you rephrase your last message? (Detail: ", msg, ")"
        )
      )
    }
  )
}


#' Internal engine implementation
#' @noRd
.workflow_engine_impl <- function(history, metadata, model, api_key,
                                   system_prompt) {

  # --- Load metadata ---
  if (is.null(metadata)) {
    metadata <- .load_metadata()
  }

  # --- Detect phase and build prompt ---
  phase_info <- NULL
  if (is.null(system_prompt)) {
    phase_info <- .detect_phase(history)
    system_prompt <- .build_phase_prompt(
      phase   = phase_info$phase,
      context = phase_info$context,
      metadata = metadata
    )
  }

  # --- Trim history for continuation mode ---
  # When extending a completed workflow, the old conversation (with full DAG
  # code) is dead weight that bloats the API request and can cause timeouts.
  # The classify prompt already carries the prior_output_type context.
  api_history <- history
  if (!is.null(phase_info) && identical(phase_info$phase, "classify") &&
      !is.null(phase_info$context$prior_output_type)) {
    # Keep only the last user message (the extension request)
    user_msgs <- Filter(function(m) identical(m$role, "user"), history)
    if (length(user_msgs) > 0L) {
      api_history <- list(user_msgs[[length(user_msgs)]])
    }
  }

  # --- Call LLM ---
  response <- .call_llm(
    messages      = api_history,
    system_prompt = system_prompt,
    model         = model,
    api_key       = api_key
  )

  # --- Sanitize response ---
  # LLM may return NULL/NA for fields that should be strings.
  # Normalize before any if() checks to prevent missing-value errors.
  if (!is.list(response)) {
    response <- list(status = "incomplete", message = as.character(response))
  }
  response$status  <- as.character(response$status  %||% "incomplete")[1L]
  response$message <- as.character(response$message %||% "")[1L]
  if (is.na(response$status))  response$status  <- "incomplete"
  if (is.na(response$message)) response$message <- ""

  # Normalize invented status values
  valid_statuses <- c("incomplete", "complete", "error")
  if (!response$status %in% valid_statuses) {
    if (response$status %in% c("confirmed", "ready", "done", "success")) {
      response$status <- "complete"
    } else {
      response$status <- "incomplete"
    }
  }

  # Normalize selected_path from list to character vector
  if (is.list(response$selected_path)) {
    response$selected_path <- unlist(response$selected_path)
  }

  # Validate selected_path edge IDs against the graph
  if (!is.null(response$selected_path) && length(response$selected_path) > 0) {
    graph <- .load_graph()
    valid_ids <- vapply(graph$edges, `[[`, "", "id")
    bad_ids <- setdiff(unlist(response$selected_path), valid_ids)
    if (length(bad_ids) > 0) {
      # Try to repair: fuzzy match against real edge IDs
      repaired <- .repair_edge_ids(unlist(response$selected_path), valid_ids,
                                    response$input_type, response$output_type, graph)
      if (!is.null(repaired)) {
        response$selected_path <- repaired
      } else {
        warning(
          "LLM returned invalid edge IDs: ", paste(bad_ids, collapse = ", "),
          ". Clearing selected_path.", call. = FALSE
        )
        response$selected_path <- NULL
        response$status <- "incomplete"
      }
    }
  }

  response
}


#' Detect Current Phase from Conversation History
#'
#' Analyzes the conversation history to determine which phase the engine
#' should be in. Phase is detected from the last assistant message's
#' structured JSON content.
#'
#' @param history List of message objects.
#' @return A list with \code{$phase} (character) and \code{$context} (list)
#'   containing any state needed to build the phase prompt.
#' @noRd
.detect_phase <- function(history) {
  # Default: start fresh with classify
  default <- list(phase = "classify", context = list())

  if (length(history) == 0L) return(default)

  # Check if the latest user message looks like an error report
  last_user <- .last_message_by_role(history, "user")
  if (!is.null(last_user) && .looks_like_error(last_user)) {
    # Error fix mode — try to find context from previous assistant state
    last_asst <- .last_assistant_state(history)
    return(list(
      phase   = "error_fix",
      context = list(
        error_message = last_user,
        selected_path = last_asst$selected_path
      )
    ))
  }

  # Parse the last assistant response for phase state
  last_asst <- .last_assistant_state(history)
  if (is.null(last_asst)) return(default)

  # Normalize selected_path: JSON round-trip with simplifyVector=FALSE

  # turns character arrays into lists. Flatten back to character vector.
  if (is.list(last_asst$selected_path)) {
    last_asst$selected_path <- unlist(last_asst$selected_path)
  }

  has_input    <- !is.null(last_asst$input_type) && nzchar(last_asst$input_type)
  has_output   <- !is.null(last_asst$output_type) && nzchar(last_asst$output_type)
  has_path     <- !is.null(last_asst$selected_path) && length(last_asst$selected_path) > 0
  has_dag      <- !is.null(last_asst$dag) && length(last_asst$dag) > 0

  if (has_dag) {
    # Workflow already complete -- the user wants to extend it.
    # Map the previous output type to the corresponding input type.
    # Output nodes (e.g. "consensus") are not valid inputs; the graph
    # has separate input nodes (e.g. "consensus_df") for chaining.
    output_to_input <- c(
      consensus = "consensus_df"
    )
    prior_out <- last_asst$output_type
    continuation_input <- output_to_input[prior_out] %||% prior_out
    return(list(
      phase   = "classify",
      context = list(
        prior_output_type = continuation_input
      )
    ))
  }

  if (has_path) {
    # Path selected, need parameterization.
    # Check if this is a continuation (a prior DAG exists in history).
    is_continuation <- .history_has_prior_dag(history, exclude_last = TRUE)
    return(list(
      phase   = "parameterize",
      context = list(
        input_type      = last_asst$input_type,
        output_type     = last_asst$output_type,
        selected_path   = last_asst$selected_path,
        is_continuation = is_continuation
      )
    ))
  }

  if (has_input && has_output) {
    # Classified but no path selected → path_select
    # Compute paths in R (the whole point: LLM doesn't invent these)
    graph <- .load_graph()
    paths <- .compute_paths(last_asst$input_type, last_asst$output_type, graph)
    return(list(
      phase   = "path_select",
      context = list(
        input_type  = last_asst$input_type,
        output_type = last_asst$output_type,
        paths       = paths
      )
    ))
  }

  # Partial classification or no progress → stay in classify
  default
}


#' Extract Last Assistant State from History
#'
#' Finds the last assistant message in history and attempts to parse it
#' as JSON to extract phase state fields.
#'
#' @param history List of message objects.
#' @return Parsed list with phase state fields, or NULL.
#' @noRd
.last_assistant_state <- function(history) {
  asst_msgs <- Filter(function(m) identical(m$role, "assistant"), history)
  if (length(asst_msgs) == 0L) return(NULL)

  last_content <- asst_msgs[[length(asst_msgs)]]$content
  if (is.null(last_content) || !nzchar(last_content)) return(NULL)

  # Try to parse as JSON
  parsed <- tryCatch(
    jsonlite::fromJSON(last_content, simplifyVector = FALSE),
    error = function(e) NULL
  )

  parsed
}


#' Get Last Message by Role
#' @noRd
.last_message_by_role <- function(history, role) {
  msgs <- Filter(function(m) identical(m$role, role), history)
  if (length(msgs) == 0L) return(NULL)
  msgs[[length(msgs)]]$content
}


#' Check if History Contains a Prior Completed DAG
#'
#' Scans assistant messages for any that contain a non-empty \code{dag}.
#' Used to detect continuation mode (extending a previously completed workflow).
#'
#' @param history List of message objects.
#' @param exclude_last Logical. If TRUE, skip the last assistant message
#'   (used when we only want to check prior messages, not the current one).
#' @return Logical.
#' @noRd
.history_has_prior_dag <- function(history, exclude_last = FALSE) {
  asst_msgs <- Filter(function(m) identical(m$role, "assistant"), history)
  if (exclude_last && length(asst_msgs) > 0L) {
    asst_msgs <- asst_msgs[-length(asst_msgs)]
  }
  for (m in asst_msgs) {
    parsed <- tryCatch(
      jsonlite::fromJSON(m$content, simplifyVector = FALSE),
      error = function(e) NULL
    )
    if (!is.null(parsed) && !is.null(parsed$dag) && length(parsed$dag) > 0L) {
      return(TRUE)
    }
  }
  FALSE
}


#' Check if Text Looks Like an Error Report
#' @noRd
.looks_like_error <- function(text) {
  if (is.null(text) || length(text) == 0L || is.na(text[1L])) return(FALSE)
  error_patterns <- c(
    "Error in ", "Error:", "failed:", "error:",
    "could not find function", "unused argument",
    "object .+ not found", "missing required column",
    "Step \\d+.*failed"
  )
  any(vapply(error_patterns, grepl, FALSE, x = text[1L], ignore.case = TRUE))
}


#' Repair Invalid Edge IDs
#'
#' When the LLM invents edge IDs instead of using the graph's real ones,
#' attempt to recover by computing the valid path between input and output
#' and selecting the path that best matches the LLM's intent.
#'
#' @param bad_path Character vector of LLM-invented edge IDs.
#' @param valid_ids Character vector of all valid edge IDs in the graph.
#' @param input_type Character. The classified input node.
#' @param output_type Character. The classified output node.
#' @param graph The workflow graph object.
#' @return Character vector of valid edge IDs, or NULL if no match found.
#' @noRd
.repair_edge_ids <- function(bad_path, valid_ids, input_type, output_type, graph) {
  # If input/output types are available, compute the real paths and pick
  # the one with the same number of steps
  if (is.null(input_type) || is.null(output_type)) return(NULL)

  paths <- tryCatch(
    .compute_paths(input_type, output_type, graph),
    error = function(e) list()
  )
  if (length(paths) == 0L) return(NULL)

  # Prefer a path with the same number of edges
  n_bad <- length(bad_path)
  same_len <- Filter(function(p) length(p$edges) == n_bad, paths)
  if (length(same_len) == 1L) return(same_len[[1L]]$edges)

  # If multiple same-length paths, pick the first (simplest)
  if (length(same_len) > 1L) return(same_len[[1L]]$edges)

  # No same-length match; return the shortest path
  lengths <- vapply(paths, function(p) length(p$edges), 0L)
  paths[[which.min(lengths)]]$edges
}


#' Load and Assemble the Legacy System Prompt
#'
#' Reads the system prompt template from \code{inst/prompts/system_prompt.md}
#' and injects the compressed metadata registry. Kept for backward
#' compatibility; the phase-based engine uses \code{.build_phase_prompt()}.
#'
#' @param metadata Named list from \code{.load_metadata()}.
#' @return Character string: the full system prompt.
#' @noRd
.load_system_prompt <- function(metadata, output_dir = ".") {

  prompt_path <- system.file("prompts", "system_prompt.md",
                             package = "TaxaWizard")
  if (!nzchar(prompt_path)) {
    stop("System prompt file not found. Is TaxaWizard installed?",
         call. = FALSE)
  }

  template <- paste(readLines(prompt_path, warn = FALSE), collapse = "\n")
  registry_text <- .compress_metadata(metadata)

  # Replace placeholder with compressed metadata
  prompt <- sub("{{FUNCTION_REGISTRY}}", registry_text, template, fixed = TRUE)

  # Inject per-user corrections (learned from previous errors)
  corrections_text <- .format_corrections_for_prompt()
  if (nzchar(corrections_text)) {
    prompt <- paste0(prompt, "\n\n", corrections_text)
  }

  # Inject saved context from previous session
  ctx <- .load_context(output_dir)
  ctx_text <- .format_context_for_prompt(ctx)
  if (nzchar(ctx_text)) {
    prompt <- paste0(prompt, "\n\n", ctx_text)
  }

  prompt
}
