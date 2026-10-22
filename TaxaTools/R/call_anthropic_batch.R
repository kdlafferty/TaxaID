# ==============================================================================
# call_anthropic_batch.R
# TaxaTools -- Anthropic Message Batches API: many prompts, one asynchronous
# submission, half the per-token price of call_api()
#
# Exported:
#   call_anthropic_batch()   submit, poll, collect; texts in input order
# Internal:
#   .anthropic_batch_request()  one HTTP request, the API key scrubbed from errors
#   .anthropic_batch_check()    stop on a non-200 response
#   .anthropic_batch_result()   one JSONL result line -> text, status, tokens
#   .batch_redact()             remove the API key from a message
#   .batch_sleep()              Sys.sleep(), separate so tests can skip the wait
# ==============================================================================

#' @noRd
.batch_redact <- function(msg, api_key) {
  if (!is.null(api_key) && nzchar(api_key)) {
    msg <- gsub(api_key, "***REDACTED***", msg, fixed = TRUE)
  }
  msg
}

#' @noRd
.batch_sleep <- function(seconds) Sys.sleep(seconds)

#' One Message Batches HTTP request
#'
#' Every transport error leaves here with the API key removed: httr2 can echo
#' request details into a connection error, and this message reaches the
#' caller, its warnings and its logs.
#' @noRd
.anthropic_batch_request <- function(url, api_key, version, body = NULL,
                                     timeout = 120) {
  req <- httr2::request(url) |>
    httr2::req_headers(
      "x-api-key"         = api_key,
      "anthropic-version" = version,
      "content-type"      = "application/json"
    ) |>
    httr2::req_timeout(timeout) |>
    httr2::req_error(is_error = function(resp) FALSE)
  if (!is.null(body)) req <- httr2::req_body_json(req, body)
  tryCatch(
    httr2::req_perform(req),
    error = function(e) {
      stop(sprintf(
        "call_anthropic_batch: HTTP request failed: %s",
        .batch_redact(conditionMessage(e), api_key)
      ), call. = FALSE)
    }
  )
}

#' @noRd
.anthropic_batch_check <- function(resp, what, api_key) {
  status <- httr2::resp_status(resp)
  if (status != 200L) {
    body <- tryCatch(httr2::resp_body_json(resp), error = function(e) list())
    stop(sprintf(
      "call_anthropic_batch: %s failed, HTTP %d: %s", what, status,
      .batch_redact(body$error$message %||% "(no message)", api_key)
    ), call. = FALSE)
  }
  invisible(resp)
}

#' Read one result line of a batch
#'
#' `status` is the batch's own result type (`succeeded`, `errored`,
#' `canceled`, `expired`), except that a succeeded message holding no text
#' block -- the model thought until `max_tokens` -- is `no_text`, since it
#' carries no answer.
#' @noRd
.anthropic_batch_result <- function(line, api_key) {
  res <- line$result %||% list()
  type <- res$type %||% "unknown"
  out <- list(
    text = NA_character_, status = type, detail = NA_character_,
    input = NA_integer_, output = NA_integer_, truncated = FALSE
  )
  if (identical(type, "succeeded")) {
    msg <- res$message %||% list()
    out$input <- as.integer(msg$usage$input_tokens %||% NA_integer_)
    out$output <- as.integer(msg$usage$output_tokens %||% NA_integer_)
    blocks <- Filter(function(b) identical(b$type, "text"), msg$content %||% list())
    out$truncated <- identical(msg$stop_reason, "max_tokens")
    if (length(blocks) == 0L) {
      out$status <- "no_text"
      out$detail <- sprintf("stop_reason = %s", msg$stop_reason %||% "NA")
    } else {
      out$text <- blocks[[1L]]$text
    }
  } else if (identical(type, "errored")) {
    err <- res$error$error %||% res$error %||% list()
    out$detail <- .batch_redact(err$message %||% err$type %||% "(no message)", api_key)
  }
  out
}

#' Send Many Prompts to Anthropic as One Message Batch
#'
#' Submits every prompt as one request of a Message Batch, waits for the
#' batch to finish, and returns the response texts in the order the prompts
#' were given. A batch is billed at half the per-token price of a
#' synchronous call (\code{\link{call_api}}), in exchange for an answer that
#' arrives asynchronously: most batches finish within an hour, and a batch
#' that has not finished within 24 hours expires. Requests within a batch are
#' processed independently, so one failing prompt does not fail the others.
#'
#' Use it where many independent prompts are ready at once and nothing waits
#' on each answer, for example as the \code{llm_batch_fn} of
#' \code{TaxaFlag::review_assignments()}.
#'
#' @param prompts Character vector, one complete prompt per element, no
#'   \code{NA}. At most 100,000 prompts (the API's own limit; it also caps a
#'   batch at 256 MB).
#' @param model,tier,max_tokens,api_key,temperature As in
#'   \code{\link{call_anthropic_api}}. \code{temperature = NULL} (default)
#'   sends no temperature field; some current models reject the parameter
#'   with HTTP 400, which here fails every request in the batch.
#' @param poll_seconds Numeric. Seconds between status checks. Default 30.
#' @param max_wait_hours Numeric. How long to wait for the batch to finish
#'   before stopping with a "no results yet" error that names the batch.
#'   Default 24, the API's own expiry.
#' @param batch_id Character or \code{NULL}. The id of a batch already
#'   submitted -- from that "no results yet" error -- to resume waiting for
#'   and collect, instead of submitting again. Pass the same \code{prompts}
#'   in the same order: results are matched to them by position.
#' @param verbose Logical. Report submission and progress. Default \code{TRUE}.
#'
#' @return A character vector the length of \code{prompts}, \code{NA} where a
#'   prompt has no answer, with attributes:
#'   \describe{
#'     \item{\code{"status"}}{Per prompt: \code{"succeeded"}, \code{"no_text"}
#'       (the model stopped before writing any text), \code{"errored"},
#'       \code{"canceled"}, \code{"expired"}, or \code{"missing"} (no result
#'       line came back for it).}
#'     \item{\code{"outcome"}}{\code{"complete"} (every prompt answered),
#'       \code{"partial"} (some answered) or \code{"no_results"} (the batch
#'       finished with none answered). A batch that has not finished is
#'       never returned: it stops with a "no results yet" error instead, so
#'       the three cases stay distinct.}
#'     \item{\code{"detail"}}{Per prompt: the error message or stop reason
#'       behind a missing answer, \code{NA} otherwise.}
#'     \item{\code{"truncated"}}{Per prompt: \code{TRUE} when the answer
#'       stopped at \code{max_tokens} and may be incomplete.}
#'     \item{\code{"tokens"}}{Data frame of per-prompt \code{input} and
#'       \code{output} token counts.}
#'     \item{\code{"batch_id"}, \code{"model"}, \code{"provider"}}{The batch,
#'       the resolved model and \code{"anthropic"}.}
#'   }
#'   Token counts of answered prompts are added to \code{\link{token_usage}}.
#'   The API key never appears in an error, warning or attribute.
#'
#' @seealso \code{\link{call_anthropic_api}} and \code{\link{call_api}} for
#'   one synchronous call.
#'
#' @export
#'
#' @examples
#' \dontrun{
#' out <- call_anthropic_batch(
#'   c("What phylum do sea urchins belong to?", "What class are barnacles in?"),
#'   model = "claude-haiku-5-5", max_tokens = 2000L
#' )
#' attr(out, "outcome")
#' out[attr(out, "status") == "succeeded"]
#' }
call_anthropic_batch <- function(prompts,
                                 model = NULL,
                                 tier = c("mid", "fast", "top"),
                                 max_tokens = 16000L,
                                 api_key = Sys.getenv("ANTHROPIC_API_KEY"),
                                 temperature = NULL,
                                 poll_seconds = 30,
                                 max_wait_hours = 24,
                                 batch_id = NULL,
                                 verbose = TRUE) {
  tier <- match.arg(tier)
  if (!is.character(prompts) || length(prompts) == 0L || anyNA(prompts)) {
    stop("call_anthropic_batch: 'prompts' must be a non-empty character vector with no NA.",
      call. = FALSE
    )
  }
  if (length(prompts) > 100000L) {
    stop("call_anthropic_batch: a batch holds at most 100,000 prompts; split 'prompts'.",
      call. = FALSE
    )
  }
  if (!is.null(temperature) &&
    (!is.numeric(temperature) || length(temperature) != 1L || !is.finite(temperature) ||
      temperature < 0)) {
    stop("call_anthropic_batch: 'temperature' must be NULL or one non-negative number.",
      call. = FALSE
    )
  }
  if (!is.null(batch_id) && (!is.character(batch_id) || length(batch_id) != 1L ||
    is.na(batch_id) || !nzchar(batch_id))) {
    stop("call_anthropic_batch: 'batch_id' must be NULL or one non-empty string.",
      call. = FALSE
    )
  }

  registry <- .get_registry()
  prov_reg <- registry$providers[["anthropic"]]
  api_key <- .resolve_api_key("anthropic", if (nzchar(api_key)) api_key else NULL, registry)
  version <- prov_reg$api_version_header %||% "2023-06-01"
  base <- paste0(prov_reg$chat_endpoint %||% "https://api.anthropic.com/v1/messages", "/batches")
  model <- model %||% .resolve_model("anthropic", tier)
  ids <- sprintf("p%06d", seq_along(prompts))

  # --- Submit (unless resuming) ----------------------------------------------
  if (is.null(batch_id)) {
    requests <- lapply(seq_along(prompts), function(i) {
      list(
        custom_id = ids[i],
        params = c(
          list(
            model      = model,
            max_tokens = as.integer(max_tokens),
            messages   = list(list(role = "user", content = prompts[[i]]))
          ),
          # Sent only when set, as in call_api(), so NULL keeps the model's default.
          if (!is.null(temperature)) list(temperature = temperature)
        )
      )
    })
    resp <- .anthropic_batch_request(base, api_key, version, body = list(requests = requests))
    .anthropic_batch_check(resp, "batch submission", api_key)
    batch_id <- httr2::resp_body_json(resp)$id
    if (verbose) {
      message(sprintf(
        "call_anthropic_batch: submitted %d prompt(s) to %s as batch %s.",
        length(prompts), model, batch_id
      ))
    }
  }

  # --- Wait ------------------------------------------------------------------
  started <- Sys.time()
  repeat {
    resp <- .anthropic_batch_request(paste0(base, "/", batch_id), api_key, version)
    .anthropic_batch_check(resp, "batch status", api_key)
    batch <- httr2::resp_body_json(resp)
    if (identical(batch$processing_status, "ended")) break
    waited_h <- as.numeric(difftime(Sys.time(), started, units = "hours"))
    if (waited_h >= max_wait_hours) {
      stop(structure(
        class = c("taxatools_batch_pending", "error", "condition"),
        list(
          message = sprintf(paste0(
            "call_anthropic_batch: no results yet -- batch %s is still %s after %.1f h. ",
            "Call again with batch_id = \"%s\" and the same prompts to collect it."
          ), batch_id, batch$processing_status %||% "processing", waited_h, batch_id),
          call = NULL, batch_id = batch_id
        )
      ))
    }
    if (verbose) {
      counts <- batch$request_counts %||% list()
      message(sprintf(
        "call_anthropic_batch: batch %s %s (%s processing, %s succeeded, %s errored).",
        batch_id, batch$processing_status %||% "?", counts$processing %||% "?",
        counts$succeeded %||% "?", counts$errored %||% "?"
      ))
    }
    .batch_sleep(poll_seconds)
  }

  # --- Collect ---------------------------------------------------------------
  if (is.null(batch$results_url)) {
    stop(sprintf("call_anthropic_batch: batch %s ended without a results URL.", batch_id),
      call. = FALSE
    )
  }
  resp <- .anthropic_batch_request(batch$results_url, api_key, version)
  .anthropic_batch_check(resp, "batch results", api_key)
  lines <- strsplit(httr2::resp_body_string(resp), "\n", fixed = TRUE)[[1L]]
  lines <- lines[nzchar(trimws(lines))]

  n <- length(prompts)
  text <- rep(NA_character_, n)
  status <- rep("missing", n)
  detail <- rep(NA_character_, n)
  truncated <- rep(FALSE, n)
  tok_in <- rep(NA_integer_, n)
  tok_out <- rep(NA_integer_, n)
  for (ln in lines) {
    rec <- tryCatch(jsonlite::fromJSON(ln, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(rec)) next
    i <- match(rec$custom_id %||% "", ids)
    if (is.na(i)) next
    r <- .anthropic_batch_result(rec, api_key)
    text[i] <- r$text
    status[i] <- r$status
    detail[i] <- r$detail
    truncated[i] <- r$truncated
    tok_in[i] <- r$input
    tok_out[i] <- r$output
  }

  caller <- .get_llm_caller()
  for (i in which(!is.na(tok_in) | !is.na(tok_out))) {
    .append_token_record(
      caller = caller, provider = "anthropic", model = model,
      input = tok_in[i], output = tok_out[i]
    )
  }

  n_ok <- sum(status == "succeeded")
  outcome <- if (n_ok == n) "complete" else if (n_ok > 0L) "partial" else "no_results"
  if (verbose) {
    message(sprintf(
      "call_anthropic_batch: batch %s ended -- %d of %d answered (%s).",
      batch_id, n_ok, n, outcome
    ))
  }

  attr(text, "status") <- status
  attr(text, "outcome") <- outcome
  attr(text, "detail") <- detail
  attr(text, "truncated") <- truncated
  attr(text, "tokens") <- data.frame(input = tok_in, output = tok_out)
  attr(text, "batch_id") <- batch_id
  attr(text, "model") <- model
  attr(text, "provider") <- "anthropic"
  text
}
