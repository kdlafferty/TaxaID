# Tests for call_anthropic_batch(). Offline: the one HTTP helper
# (.anthropic_batch_request) and the poll sleep are mocked, so every branch of
# the submit / poll / collect logic runs for real against canned responses.

.bt_key <- "sk-ant-test-SECRET-123"

.bt_json <- function(x, status = 200L) {
  httr2::response(
    status_code = status,
    headers = list("Content-Type" = "application/json"),
    body = charToRaw(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null"))
  )
}
.bt_text <- function(txt) {
  httr2::response(status_code = 200L, body = charToRaw(txt))
}
.bt_ok <- function(id, text, stop = "end_turn", input = 10L, output = 5L) {
  jsonlite::toJSON(list(custom_id = id, result = list(
    type = "succeeded",
    message = list(
      content = list(list(type = "text", text = text)),
      stop_reason = stop, usage = list(input_tokens = input, output_tokens = output)
    )
  )), auto_unbox = TRUE)
}

# A fake API: records every request; `statuses` is the sequence of
# processing_status values the status endpoint returns; `results` the JSONL.
.bt_fake <- function(statuses = c("in_progress", "ended"), results = character(0)) {
  st <- new.env()
  st$calls <- list()
  st$i <- 0L
  fn <- function(url, api_key, version, body = NULL, timeout = 120) {
    st$calls[[length(st$calls) + 1L]] <- list(url = url, body = body, key = api_key)
    if (!is.null(body)) return(.bt_json(list(id = "msgbatch_1", processing_status = "in_progress")))
    if (grepl("results$", url)) return(.bt_text(paste(results, collapse = "\n")))
    st$i <- min(st$i + 1L, length(statuses))
    .bt_json(list(
      id = "msgbatch_1", processing_status = statuses[st$i],
      results_url = "https://api.anthropic.com/v1/messages/batches/msgbatch_1/results",
      request_counts = list(processing = 0L, succeeded = 0L, errored = 0L)
    ))
  }
  list(fn = fn, state = st)
}

.bt_run <- function(fake, prompts = c("a", "b"), ...) {
  local_mocked_bindings(
    .anthropic_batch_request = fake$fn,
    .batch_sleep = function(seconds) invisible(NULL),
    .env = parent.frame()
  )
  call_anthropic_batch(prompts, model = "claude-test", api_key = .bt_key, verbose = FALSE, ...)
}

test_that("texts come back in input order, matched by custom_id, not result order", {
  fake <- .bt_fake(results = c(.bt_ok("p000002", "second"), .bt_ok("p000001", "first")))
  out <- .bt_run(fake)
  expect_identical(as.character(out), c("first", "second"))
  expect_identical(attr(out, "status"), c("succeeded", "succeeded"))
  expect_identical(attr(out, "outcome"), "complete")
  expect_identical(attr(out, "batch_id"), "msgbatch_1")
  expect_equal(attr(out, "tokens")$input, c(10L, 10L))
})

test_that("'partial' and 'no_results' are distinct outcomes, with per-prompt status", {
  errored <- jsonlite::toJSON(list(custom_id = "p000002", result = list(
    type = "errored", error = list(type = "error", error = list(
      type = "invalid_request_error", message = "bad request"
    ))
  )), auto_unbox = TRUE)
  out <- .bt_run(.bt_fake(results = c(.bt_ok("p000001", "ok"), errored)))
  expect_identical(attr(out, "outcome"), "partial")
  expect_identical(attr(out, "status"), c("succeeded", "errored"))
  expect_identical(attr(out, "detail")[2], "bad request")
  expect_true(is.na(out[2]))

  expired <- vapply(c("p000001", "p000002"), function(id) {
    as.character(jsonlite::toJSON(list(custom_id = id, result = list(type = "expired")),
      auto_unbox = TRUE
    ))
  }, "")
  none <- .bt_run(.bt_fake(results = expired))
  expect_identical(attr(none, "outcome"), "no_results")
  expect_true(all(is.na(none)))
  expect_identical(attr(none, "status"), c("expired", "expired"))
})

test_that("a prompt with no result line is 'missing', not silently answered", {
  out <- .bt_run(.bt_fake(results = .bt_ok("p000001", "only one")))
  expect_identical(attr(out, "status"), c("succeeded", "missing"))
  expect_identical(attr(out, "outcome"), "partial")
})

test_that("a message with no text block is 'no_text', and truncation is flagged", {
  thinking_only <- jsonlite::toJSON(list(custom_id = "p000001", result = list(
    type = "succeeded", message = list(
      content = list(list(type = "thinking", thinking = "...")),
      stop_reason = "max_tokens", usage = list(input_tokens = 5L, output_tokens = 100L)
    )
  )), auto_unbox = TRUE)
  out <- .bt_run(.bt_fake(results = c(thinking_only, .bt_ok("p000002", "cut", stop = "max_tokens"))))
  expect_identical(attr(out, "status"), c("no_text", "succeeded"))
  expect_identical(attr(out, "truncated"), c(TRUE, TRUE))
  expect_identical(out[2], "cut")
})

test_that("an unfinished batch stops with 'no results yet' and names the batch", {
  fake <- .bt_fake(statuses = "in_progress")
  err <- tryCatch(.bt_run(fake, max_wait_hours = 0), error = function(e) e)
  expect_s3_class(err, "taxatools_batch_pending")
  expect_match(conditionMessage(err), "no results yet", fixed = TRUE)
  expect_match(conditionMessage(err), "msgbatch_1", fixed = TRUE)
  expect_identical(err$batch_id, "msgbatch_1")
})

test_that("batch_id resumes an existing batch without submitting again", {
  fake <- .bt_fake(statuses = "ended", results = c(.bt_ok("p000001", "x"), .bt_ok("p000002", "y")))
  out <- .bt_run(fake, batch_id = "msgbatch_1")
  expect_identical(as.character(out), c("x", "y"))
  expect_false(any(vapply(fake$state$calls, function(cl) !is.null(cl$body), logical(1))))
})

test_that("no temperature is sent unless one is given", {
  fake <- .bt_fake(results = c(.bt_ok("p000001", "x"), .bt_ok("p000002", "y")))
  .bt_run(fake)
  params <- fake$state$calls[[1]]$body$requests[[1]]$params
  expect_false("temperature" %in% names(params))
  expect_identical(params$max_tokens, 16000L)

  fake2 <- .bt_fake(results = c(.bt_ok("p000001", "x"), .bt_ok("p000002", "y")))
  .bt_run(fake2, temperature = 0.2)
  expect_identical(fake2$state$calls[[1]]$body$requests[[2]]$params$temperature, 0.2)
})

test_that("the API key never appears in an HTTP error", {
  rejecting <- function(url, api_key, version, body = NULL, timeout = 120) {
    .bt_json(list(error = list(message = paste("invalid x-api-key", api_key))), status = 401L)
  }
  local_mocked_bindings(.anthropic_batch_request = rejecting)
  err <- tryCatch(
    call_anthropic_batch("a", model = "claude-test", api_key = .bt_key, verbose = FALSE),
    error = function(e) conditionMessage(e)
  )
  expect_false(grepl(.bt_key, err, fixed = TRUE))
  expect_match(err, "***REDACTED***", fixed = TRUE)
  expect_match(err, "HTTP 401", fixed = TRUE)
})

test_that("the real request helper scrubs the key from a transport error", {
  local_mocked_bindings(
    req_perform = function(req, ...) stop(paste("Could not resolve host; header", .bt_key)),
    .package = "httr2"
  )
  err2 <- tryCatch(
    .anthropic_batch_request("https://example.invalid", .bt_key, "2023-06-01"),
    error = function(e) conditionMessage(e)
  )
  expect_false(grepl(.bt_key, err2, fixed = TRUE))
  expect_match(err2, "***REDACTED***", fixed = TRUE)
})

test_that("answered prompts are added to the token ledger", {
  reset_token_usage()
  .bt_run(.bt_fake(results = c(.bt_ok("p000001", "x", input = 7L, output = 3L),
                               .bt_ok("p000002", "y", input = 8L, output = 4L))))
  u <- token_usage()
  expect_equal(sum(u$input), 15L)
  expect_equal(sum(u$output), 7L)
  reset_token_usage()
})

test_that("bad prompts are refused before any request", {
  expect_error(call_anthropic_batch(c("a", NA), api_key = .bt_key), "no NA")
  expect_error(call_anthropic_batch(character(0), api_key = .bt_key), "non-empty")
  expect_error(call_anthropic_batch("a", api_key = .bt_key, temperature = -1), "temperature")
})
