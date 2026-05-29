#' Create a TaxaID Workflow
#'
#' Interactive workflow designer that interviews you about your data and goals,
#' then generates an executable .R script (and optionally a methods .md file).
#' The conversation is powered by \code{\link{workflow_engine}} and can run
#' either in the R console or in the RStudio Viewer pane.
#'
#' @param mode Character. Where to run the chat interface:
#'   \describe{
#'     \item{\code{"auto"}}{(Default) Uses the browser if shiny is
#'       available, otherwise falls back to the console.}
#'     \item{\code{"browser"}}{Chat in a standalone browser window
#'       (requires shiny). Can be moved and resized freely.}
#'     \item{\code{"viewer"}}{Chat in the RStudio Viewer pane (requires
#'       shiny). Compact but may be hidden behind other tabs.}
#'     \item{\code{"console"}}{Chat via \code{readline()} in the R console.
#'       Works in any interactive R environment.}
#'   }
#' @param output_dir Character. Directory to write generated files.
#'   Default \code{"."} (current working directory).
#' @param model Character. LLM model ID. Default \code{"claude-sonnet-4-6"}.
#' @param api_key Character or NULL. Anthropic API key. When \code{NULL},
#'   uses the \code{ANTHROPIC_API_KEY} environment variable. Ignored when
#'   \code{llm_fn} is supplied.
#' @param llm_fn Function or NULL. Custom LLM caller for non-Anthropic
#'   providers (Azure, OpenAI, Gemini, …). When non-NULL, \code{api_key} and
#'   the built-in Anthropic HTTP logic are bypassed entirely. The function
#'   must accept four named arguments and return a single character string:
#'   \itemize{
#'     \item \code{messages} — list of \code{list(role, content)} objects
#'       (the conversation history + current user turn).
#'     \item \code{system_prompt} — character string (the phase prompt).
#'     \item \code{model} — character string (passed from the \code{model}
#'       argument; ignore if your provider uses a fixed model).
#'     \item \code{max_tokens} — integer (default 16384).
#'   }
#'   The return value should be the raw LLM response text (plain or JSON).
#'   For Azure OpenAI the caller must assemble the chat-completion request
#'   using \code{messages} + \code{system_prompt} — see the example below.
#' @param trial Logical. When \code{TRUE}, generated scripts include
#'   trial-mode subsetting for performance estimation. Default \code{FALSE}.
#'
#' @return Invisibly returns the final engine response (console mode) or
#'   \code{NULL} (viewer mode). Generated files are written to
#'   \code{output_dir}.
#'
#' @seealso \code{\link{workflow_fix}} to resume after a script error,
#'   \code{\link{workflow_app}} to convert a generated script into a Shiny app
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Auto-detect mode (viewer in RStudio, console otherwise)
#' workflow_create()
#'
#' # Force console mode
#' workflow_create(mode = "console")
#'
#' # Generate to a specific directory
#' workflow_create(output_dir = "~/my_project")
#' }
workflow_create <- function(mode       = c("auto", "viewer", "browser", "console"),
                            output_dir = ".",
                            model      = "claude-sonnet-4-6",
                            api_key    = NULL,
                            llm_fn     = NULL,
                            trial      = FALSE) {

  mode <- match.arg(mode)

  if (!interactive()) {
    stop("workflow_create() requires an interactive R session.", call. = FALSE)
  }

  # Auto-detect: use viewer if RStudio is available, else console

  if (mode == "auto") {
    mode <- if (requireNamespace("shiny", quietly = TRUE)) "browser" else "console"
  }

  if (mode %in% c("viewer", "browser")) {
    if (!requireNamespace("shiny", quietly = TRUE)) {
      message("shiny package not installed. Falling back to console mode.")
      message("Install shiny for the GUI interface: install.packages('shiny')")
      mode <- "console"
    }
  }

  if (mode %in% c("viewer", "browser")) {
    if (identical(mode, "viewer")) {
      message("Opening chat in the RStudio Viewer pane (bottom-right).")
      message("Tip: click the 'pop out' arrow to move it to a separate window.")
    } else {
      message("Opening chat in your web browser...")
    }
    message("When finished, press the Stop button in the R console to exit the chat.")
    message("Then source the generated script to run your workflow.")
    .create_viewer(model = model, api_key = api_key, llm_fn = llm_fn,
                   output_dir = output_dir, trial = trial,
                   use_browser = identical(mode, "browser"))
  } else {
    .create_console(model = model, api_key = api_key, llm_fn = llm_fn,
                    output_dir = output_dir, trial = trial)
  }
}


#' Check if Running Inside RStudio
#' @return Logical.
#' @noRd
.is_rstudio <- function() {
  Sys.getenv("RSTUDIO") == "1" || !is.null(tryCatch(
    get(".rs.api.versionInfo", envir = as.environment("tools:rstudio")),
    error = function(e) NULL
  ))
}


# =========================================================================
# Console Mode
# =========================================================================

#' @noRd
.create_console <- function(model, api_key, llm_fn, output_dir, trial) {

  metadata <- .load_metadata()
  history  <- list()

  # Check for saved context from a previous session
  saved_ctx <- .load_context(output_dir)

  cat("=== TaxaWizard Designer ===\n")
  if (!is.null(saved_ctx)) {
    cat("Previous session context found.\n")
    use_ctx <- readline(prompt = "Use previous session defaults? (yes/no): ")
    if (!tolower(trimws(use_ctx)) %in% c("yes", "y")) {
      saved_ctx <- NULL
      ctx_path <- file.path(output_dir, "workflow_context.json")
      if (file.exists(ctx_path)) file.remove(ctx_path)
      cat("Previous context cleared. Starting fresh.\n")
    } else {
      cat("Using previous defaults.\n")
    }
  }
  cat("Describe your data and what you want to accomplish.\n")
  cat("Type 'quit' to exit.\n\n")

  auto_message <- NULL   # set non-NULL to skip readline on next iteration

  repeat {
    # --- Get user input (or use auto-message from phase transition) ---
    if (!is.null(auto_message)) {
      user_input <- auto_message
      auto_message <- NULL
    } else {
      user_input <- readline(prompt = "You: ")
      if (tolower(trimws(user_input)) %in% c("quit", "exit", "q")) {
        cat("Session ended.\n")
        return(invisible(NULL))
      }
      if (!nzchar(trimws(user_input))) next
    }

    history <- c(history, list(list(role = "user", content = user_input)))

    cat("Processing...\n")

    # --- Call engine ---
    result <- tryCatch(
      workflow_engine(
        history  = history,
        metadata = metadata,
        model    = model,
        api_key  = api_key,
        llm_fn   = llm_fn
      ),
      error = function(e) {
        list(status = "error", message = paste("Error:", conditionMessage(e)))
      }
    )

    # Add full structured response to history (enables phase detection)
    history <- c(history, list(list(
      role    = "assistant",
      content = jsonlite::toJSON(result, auto_unbox = TRUE)
    )))

    # --- Check for phase transition before displaying ---
    # Suppress the LLM message when it's just a phase transition (e.g.
    # path_select -> parameterize). The next phase will immediately ask
    # the user a concrete question, so the transitional text is noise.
    # Detect based on: status complete + selected_path exists + no DAG.
    # Don't rely on the 'phase' field — the LLM sometimes mislabels it.
    has_path_no_dag <- !is.null(result$selected_path) &&
      length(result$selected_path) > 0L &&
      (is.null(result$dag) || length(result$dag$steps) == 0L)
    is_phase_transition <- identical(result$status, "complete") && has_path_no_dag

    if (!is_phase_transition) {
      cat(sprintf("\nAssistant: %s\n\n", result$message))
    }

    # --- Handle complete workflow ---
    if (identical(result$status, "complete")) {

      # Validate DAG has actual steps
      dag <- result$dag
      if (is.null(dag) || length(dag$steps) == 0L) {
        if (has_path_no_dag) {
          auto_message <- "Path confirmed. Please ask the user for any parameter values you still need (file paths, coordinates, etc.), or generate the DAG if you already have everything."
          next
        }

        # Classify phase completion: input_type + output_type set, no path, no dag.
        # This is expected — the user just confirmed their input/output types.
        # Wait for their confirmation reply; .detect_phase() will then move to path_select.
        has_classify_complete <- !is.null(result$input_type) &&
          nzchar(result$input_type %||% "") &&
          !is.null(result$output_type) &&
          nzchar(result$output_type %||% "") &&
          (is.null(result$selected_path) || length(result$selected_path) == 0L)
        if (has_classify_complete) next

        # Parameterize phase returned empty DAG
        cat("Warning: The workflow DAG is empty (no steps).\n")
        cat("DAG structure received: ", paste(names(dag), collapse = ", "), "\n")
        if (!is.null(dag)) {
          cat("DAG contents:\n")
          cat(jsonlite::toJSON(dag, auto_unbox = TRUE, pretty = TRUE), "\n")
        }
        cat("Let me ask the LLM to try again.\n\n")

        retry_path <- result$selected_path
        auto_message <- paste0(
          "ERROR: Your response had status 'complete' but the dag.steps array was empty or missing. ",
          "This is not allowed. You MUST include a fully populated dag.steps array when status is 'complete'. ",
          "Each step needs: step_id, edge_id, package, function_name, description, code, inputs, output_var. ",
          "The code field must contain actual R code from the snippets with placeholders filled in. ",
          if (!is.null(retry_path)) {
            paste0(
              "The selected_path is: ", jsonlite::toJSON(retry_path, auto_unbox = TRUE), ". ",
              "Generate one step per edge in this path. "
            )
          } else "",
          "Return the complete JSON response now with dag.steps populated."
        )
        next
      }

      confirm <- readline(prompt = "Generate workflow? (yes/no): ")
      if (tolower(trimws(confirm)) %in% c("yes", "y")) {
        generated <- .generate_outputs(
          dag        = dag,
          outputs    = result$outputs %||% "script",
          output_dir = output_dir,
          trial      = trial
        )
        is_extension <- isTRUE(attr(generated, "appended"))
        cat(if (is_extension) "Updated files:\n" else "Generated files:\n")
        for (f in generated) cat(sprintf("  %s\n", f))

        # Save conversation state for workflow_fix()
        .save_session(history, metadata, model, api_key, llm_fn, output_dir, trial)
        if (is_extension) {
          cat("\nNew steps appended to the existing script.\n")
          cat("Re-source it to run the full pipeline (earlier steps load from cache).\n")
        } else {
          cat("\nRun the script. If you hit errors, call:\n")
          cat("  workflow_fix()   # opens a prompt to paste the error\n")
        }
        cat("\nYou can keep typing to extend the workflow (e.g. add flagging or review).\n")
        cat("Type 'quit' to exit.\n\n")
      } else {
        cat("OK, let's keep refining. What would you like to change?\n\n")
        history <- c(history, list(list(
          role    = "user",
          content = "User declined generation. They want to refine the workflow."
        )))
      }
    }
  }
}


# =========================================================================
# Viewer Mode (RStudio Gadget)
# =========================================================================

#' @noRd
.create_viewer <- function(model, api_key, llm_fn, output_dir, trial,
                           use_browser = FALSE) {

  metadata <- .load_metadata()

  # --- UI ---
  # Layout: fixed title + scrollable chat log + fixed input row.
  # The chat log uses absolute positioning within a relative container
  # so it gets a real height and can scroll. uiOutput/htmlOutput are
  # avoided for the scroll container because their wrapper divs break
  # the height chain.
  ui <- shiny::fillPage(
    shiny::tags$head(
      shiny::tags$style(shiny::HTML("
        html, body { height: 100%; margin: 0; overflow: hidden;
          font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
        #chat-container {
          position: absolute; top: 0; bottom: 0; left: 0; right: 0;
          display: flex; flex-direction: column;
          padding: 8px; box-sizing: border-box;
        }
        #chat-title { flex-shrink: 0; }
        #chat-log-frame {
          flex: 1; position: relative; min-height: 0;
          margin-bottom: 8px;
        }
        #chat-log {
          position: absolute; top: 0; bottom: 0; left: 0; right: 0;
          overflow-y: auto; padding: 8px;
          border: 1px solid #ddd; border-radius: 4px;
          background: #fafafa; font-size: 13px; line-height: 1.5;
          display: flex; flex-direction: column;
        }
        #chat-log-inner { margin-top: auto; width: 100%; }
        .msg-user { color: #1a5276; margin: 6px 0; word-wrap: break-word; }
        .msg-user::before { content: 'You: '; font-weight: bold; }
        .msg-assistant { color: #1c2833; margin: 6px 0;
          white-space: pre-wrap; word-wrap: break-word; }
        .msg-assistant::before { content: 'Assistant: '; font-weight: bold; color: #6c3483; }
        .msg-system { color: #888; font-style: italic; margin: 4px 0; font-size: 12px; }
        @keyframes pulse { 0%,100% { opacity: 1; } 50% { opacity: 0.4; } }
        .msg-system:last-child { animation: pulse 1.5s ease-in-out infinite; }
        #input-row { flex-shrink: 0; display: flex; gap: 6px; }
        #input-row .form-group { flex: 1; margin-bottom: 0; }
        #send_btn { padding: 6px 16px; background: #6c3483; color: white; border: none;
                    border-radius: 4px; cursor: pointer; font-size: 13px; align-self: flex-end; }
        #send_btn:hover { background: #884ea0; }
      "))
    ),
    shiny::div(id = "chat-container",
      shiny::div(id = "chat-title",
        shiny::h4("TaxaWizard Designer", style = "margin: 4px 0 8px 0;")
      ),
      # The frame gets flex height; the chat-log inside is absolute-positioned
      # so it gets a real pixel height and can scroll.
      shiny::div(id = "chat-log-frame",
        shiny::div(id = "chat-log",
          shiny::div(id = "chat-log-inner")
        )
      ),
      # Custom JS handler to update chat log innerHTML and scroll
      shiny::tags$script(shiny::HTML("
        Shiny.addCustomMessageHandler('update_chat', function(html) {
          var log = document.getElementById('chat-log');
          var inner = document.getElementById('chat-log-inner');
          if (inner) { inner.innerHTML = html; }
          if (log) { log.scrollTop = log.scrollHeight; }
        });
        // Show 'Thinking...' immediately on Send click (client-side).
        $(document).on('click', '#send_btn', function() {
          var input = document.getElementById('user_input');
          var msg = (input && input.value) ? input.value.trim() : '';
          if (!msg) return;
          var inner = document.getElementById('chat-log-inner');
          var log = document.getElementById('chat-log');
          if (inner) {
            var safeMsg = msg.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
            inner.innerHTML += '<div class=\"msg-user\">' + safeMsg + '</div>' +
                               '<div class=\"msg-system\">Thinking...</div>';
          }
          if (log) { log.scrollTop = log.scrollHeight; }
        });
        // Send on Enter key (Shift+Enter for newline if we ever use textarea)
        $(document).on('keydown', '#user_input', function(e) {
          if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            $('#send_btn').click();
          }
        });
        // Keepalive: ping the server every 30s to prevent idle disconnect
        setInterval(function() {
          Shiny.setInputValue('keepalive', Date.now());
        }, 30000);
      ")),
      shiny::div(id = "input-row",
        shiny::textInput("user_input", label = NULL,
                         placeholder = "Describe your data and goals...",
                         width = "100%"),
        shiny::actionButton("send_btn", "Send")
      )
    )
  )

  # --- Server ---
  server <- function(input, output, session) {

    # Keep session alive while user thinks about what to type
    session$allowReconnect(TRUE)

    chat_history <- shiny::reactiveVal(list())
    display_msgs <- shiny::reactiveVal(list(
      list(type = "system", text = "Describe your data and what you want to accomplish.")
    ))

    # Send on button click
    shiny::observeEvent(input$send_btn, {
      msg <- trimws(input$user_input)
      if (!nzchar(msg)) return()

      # Update display
      msgs <- display_msgs()
      msgs <- c(msgs, list(list(type = "user", text = msg)))
      msgs <- c(msgs, list(list(type = "system", text = "Thinking...")))
      display_msgs(msgs)

      # Update history
      hist <- chat_history()
      hist <- c(hist, list(list(role = "user", content = msg)))

      # Clear input
      shiny::updateTextInput(session, "user_input", value = "")


      # Call engine
      result <- tryCatch(
        workflow_engine(
          history  = hist,
          metadata = metadata,
          model    = model,
          api_key  = api_key,
          llm_fn   = llm_fn
        ),
        error = function(e) {
          list(status = "error",
               message = paste("Error:", conditionMessage(e)))
        }
      )


      # Remove "Thinking..." and add response
      msgs <- msgs[!vapply(msgs, function(m) {
        identical(m$type, "system") && identical(m$text, "Thinking...")
      }, logical(1))]

      # Check for phase transition (e.g. path_select -> parameterize)
      # Detect based on: status complete + selected_path exists + no DAG.
      has_path_no_dag <- !is.null(result$selected_path) &&
        length(result$selected_path) > 0L &&
        (is.null(result$dag) || length(result$dag$steps) == 0L)
      is_phase_transition <- identical(result$status, "complete") && has_path_no_dag

      if (is_phase_transition) {
        # Don't show transitional message; auto-advance to next phase
        hist <- c(hist, list(list(
          role    = "assistant",
          content = jsonlite::toJSON(result, auto_unbox = TRUE)
        )))
        # Inject auto-advance message
        hist <- c(hist, list(list(
          role    = "user",
          content = "Path confirmed. Please ask the user for any parameter values you still need (file paths, coordinates, etc.), or generate the DAG if you already have everything."
        )))
        msgs <- c(msgs, list(list(type = "system", text = "Thinking...")))
        display_msgs(msgs)
        chat_history(hist)

        # Call engine again for next phase
        result <- tryCatch(
          workflow_engine(
            history  = hist,
            metadata = metadata,
            model    = model,
            api_key  = api_key,
            llm_fn   = llm_fn
          ),
          error = function(e) {
            list(status = "error",
                 message = paste("Error:", conditionMessage(e)))
          }
        )


        # Remove thinking indicator
        msgs <- msgs[!vapply(msgs, function(m) {
          identical(m$type, "system") && identical(m$text, "Thinking...")
        }, logical(1))]
      }

      msgs <- c(msgs, list(list(type = "assistant", text = result$message)))
      display_msgs(msgs)


      # Update history with full structured response
      hist <- c(hist, list(list(
        role    = "assistant",
        content = jsonlite::toJSON(result, auto_unbox = TRUE)
      )))
      chat_history(hist)

      # Handle complete workflow
      if (identical(result$status, "complete") && !is.null(result$dag) &&
          length(result$dag$steps) > 0L) {
        generated <- .generate_outputs(
          dag        = result$dag,
          outputs    = result$outputs %||% "script",
          output_dir = output_dir,
          trial      = trial
        )

        # Save session for workflow_fix()
        .save_session(hist, metadata, model, api_key, llm_fn, output_dir, trial)

        file_list <- paste(generated, collapse = "\n  ")
        is_extension <- isTRUE(attr(generated, "appended"))
        action_word <- if (is_extension) "Updated" else "Generated"
        rerun_note <- if (is_extension) {
          paste0("New steps were appended to the existing script. ",
                 "Re-source it to run the full pipeline ",
                 "(earlier steps will load from cache).")
        } else {
          "Run the script in the console. Use workflow_fix() if you hit errors."
        }
        msgs <- c(display_msgs(), list(list(
          type = "system",
          text = paste0(action_word, " files:\n  ", file_list,
                        "\n\n", rerun_note,
                        "\n\nYou can continue typing here to extend ",
                        "the workflow (e.g. add flagging or review). ",
                        "Or press Stop in the R console to exit.")
        )))
        display_msgs(msgs)
      }
    })

    # Render chat log: send HTML to client via custom message handler
    shiny::observe({
      msgs <- display_msgs()
      html_parts <- vapply(msgs, function(m) {
        # Escape HTML entities in message text
        safe_text <- gsub("&", "&amp;", m$text, fixed = TRUE)
        safe_text <- gsub("<", "&lt;", safe_text, fixed = TRUE)
        safe_text <- gsub(">", "&gt;", safe_text, fixed = TRUE)
        # Preserve newlines for pre-wrap display
        safe_text <- gsub("\n", "<br>", safe_text, fixed = TRUE)
        sprintf('<div class="msg-%s">%s</div>', m$type, safe_text)
      }, character(1))
      html <- paste(html_parts, collapse = "\n")

      session$sendCustomMessage("update_chat", html)
    })
  }


  # --- Launch ---
  if (use_browser) {
    # Opens in the default web browser as a separate window
    shiny::runGadget(ui, server,
                     viewer = shiny::browserViewer(),
                     stopOnCancel = TRUE)
  } else {
    # Opens in the RStudio Viewer tab (bottom-right pane).
    # Click the "pop out" arrow icon to move it to a separate window.
    shiny::runGadget(ui, server,
                     viewer = shiny::paneViewer(minHeight = 400),
                     stopOnCancel = TRUE)
  }
}
