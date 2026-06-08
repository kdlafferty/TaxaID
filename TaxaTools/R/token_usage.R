# ==============================================================================
# token_usage.R
# TaxaTools — session-level LLM token ledger
#
# Exported:
#   token_usage()        return accumulated token records as a data frame
#   reset_token_usage()  clear the ledger
# Internal:
#   .token_ledger        environment that holds the records list
#   .append_token_record() called by call_api() after every successful response
#   .get_llm_caller()    walks sys.calls() to find the nearest named caller
# ==============================================================================

# Internal environment — persists for the R session
.token_ledger <- new.env(parent = emptyenv())
.token_ledger$records <- list()

# Functions to skip when attributing a token record to a caller
.skip_fns <- c(
  "call_api", "do.call", "lapply", "sapply", "vapply", "Map", "mapply",
  "tryCatch", "withCallingHandlers", "try", "force", "local",
  "eval", "evalq", "match.arg", "switch"
)

#' @noRd
.get_llm_caller <- function() {
  calls <- sys.calls()
  # Walk from the outermost frame inward; return the first user-visible name
  for (i in seq_along(calls)) {
    fn <- tryCatch(deparse(calls[[i]][[1L]]), error = function(e) "")
    fn <- trimws(fn)
    if (nzchar(fn) && !startsWith(fn, ".") && !fn %in% .skip_fns &&
        !grepl("^\\$|^::|\\[", fn)) {
      return(fn)
    }
  }
  "unknown"
}

#' @noRd
.append_token_record <- function(caller, provider, model, input, output) {
  rec <- list(
    timestamp = Sys.time(),
    caller    = caller,
    provider  = provider,
    model     = model,
    input     = as.integer(input),
    output    = as.integer(output),
    total     = as.integer(input) + as.integer(output)
  )
  .token_ledger$records <- c(.token_ledger$records, list(rec))
  invisible(NULL)
}


# ==============================================================================
# token_usage()
# ==============================================================================

#' Summarise LLM Token Usage for the Current Session
#'
#' Returns a data frame of token usage records accumulated since the last call
#' to \code{\link{reset_token_usage}} (or since \code{library(TaxaTools)}).
#' Every call to \code{\link{call_api}} appends one record automatically; no
#' changes are needed in downstream package functions.
#'
#' @param by Character. How to aggregate:
#'   \describe{
#'     \item{\code{"call"}}{One row per individual API call (default). Includes
#'       timestamp, caller function, provider, model, and token counts.}
#'     \item{\code{"function"}}{Totals per caller function.}
#'     \item{\code{"provider"}}{Totals per provider.}
#'     \item{\code{"session"}}{Single-row grand total for the session.}
#'   }
#' @param cost_per_1k_input Numeric or \code{NULL}. If supplied, adds a
#'   \code{cost_usd} column estimated as
#'   \code{(input * cost_per_1k_input + output * cost_per_1k_output) / 1000}.
#'   Default \code{NULL} (no cost column).
#' @param cost_per_1k_output Numeric or \code{NULL}. Output cost rate.
#'   Used only when \code{cost_per_1k_input} is non-\code{NULL}.
#'   Default \code{NULL} (same rate as input).
#'
#' @return A data frame. Columns depend on \code{by}:
#'   \describe{
#'     \item{\code{"call"}}{
#'       \code{timestamp}, \code{caller}, \code{provider}, \code{model},
#'       \code{input}, \code{output}, \code{total}}
#'     \item{\code{"function"}}{
#'       \code{caller}, \code{n_calls}, \code{input}, \code{output},
#'       \code{total}}
#'     \item{\code{"provider"}}{
#'       \code{provider}, \code{n_calls}, \code{input}, \code{output},
#'       \code{total}}
#'     \item{\code{"session"}}{
#'       \code{n_calls}, \code{input}, \code{output}, \code{total}}
#'   }
#'   Returns an empty data frame with a message if no calls have been recorded.
#'
#' @seealso \code{\link{reset_token_usage}}, \code{\link{call_api}}
#'
#' @examples
#' \dontrun{
#' library(TaxaTools)
#'
#' # After running workflow steps that call LLMs:
#' token_usage()                       # per-call detail
#' token_usage(by = "function")        # totals per TaxaID function
#' token_usage(by = "session")         # grand total
#'
#' # With cost estimate (Anthropic claude-sonnet-4 pricing example)
#' token_usage(by = "function",
#'             cost_per_1k_input  = 0.003,
#'             cost_per_1k_output = 0.015)
#'
#' reset_token_usage()                 # clear before next workflow step
#' }
#'
#' @export
token_usage <- function(by                  = c("call", "function", "provider", "session"),
                        cost_per_1k_input   = NULL,
                        cost_per_1k_output  = NULL) {

  by <- match.arg(by)

  recs <- .token_ledger$records
  if (length(recs) == 0L) {
    message("token_usage: no LLM calls recorded this session.")
    return(invisible(data.frame(
      caller = character(0), input = integer(0),
      output = integer(0), total = integer(0)
    )))
  }

  df <- data.frame(
    timestamp = as.POSIXct(vapply(recs, function(r) as.numeric(r$timestamp),
                                  numeric(1L)),
                           origin = "1970-01-01", tz = "UTC"),
    caller    = vapply(recs, `[[`, character(1L), "caller"),
    provider  = vapply(recs, `[[`, character(1L), "provider"),
    model     = vapply(recs, `[[`, character(1L), "model"),
    input     = vapply(recs, function(r) r$input  %||% NA_integer_, integer(1L)),
    output    = vapply(recs, function(r) r$output %||% NA_integer_, integer(1L)),
    total     = vapply(recs, function(r) r$total  %||% NA_integer_, integer(1L)),
    stringsAsFactors = FALSE
  )

  out <- switch(by,
    "call" = df,
    "function" = {
      agg <- lapply(split(df, df$caller), function(g) {
        data.frame(caller   = g$caller[[1L]],
                   n_calls  = nrow(g),
                   input    = sum(g$input,  na.rm = TRUE),
                   output   = sum(g$output, na.rm = TRUE),
                   total    = sum(g$total,  na.rm = TRUE),
                   stringsAsFactors = FALSE)
      })
      do.call(rbind, unname(agg))
    },
    "provider" = {
      agg <- lapply(split(df, df$provider), function(g) {
        data.frame(provider = g$provider[[1L]],
                   n_calls  = nrow(g),
                   input    = sum(g$input,  na.rm = TRUE),
                   output   = sum(g$output, na.rm = TRUE),
                   total    = sum(g$total,  na.rm = TRUE),
                   stringsAsFactors = FALSE)
      })
      do.call(rbind, unname(agg))
    },
    "session" = {
      data.frame(n_calls = nrow(df),
                 input   = sum(df$input,  na.rm = TRUE),
                 output  = sum(df$output, na.rm = TRUE),
                 total   = sum(df$total,  na.rm = TRUE),
                 stringsAsFactors = FALSE)
    }
  )

  # Optional cost column
  if (!is.null(cost_per_1k_input)) {
    rate_out  <- cost_per_1k_output %||% cost_per_1k_input
    out$cost_usd <- round(
      (out$input * cost_per_1k_input + out$output * rate_out) / 1000, 4
    )
  }

  out
}


# ==============================================================================
# reset_token_usage()
# ==============================================================================

#' Reset the LLM Token Usage Ledger
#'
#' Clears all accumulated token records for the current session.  Call this
#' before starting a new workflow step when you want per-step accounting.
#'
#' @return \code{NULL} invisibly.
#'
#' @seealso \code{\link{token_usage}}
#'
#' @examples
#' \dontrun{
#' reset_token_usage()
#' # ... run a workflow step ...
#' token_usage(by = "session")   # tokens for that step only
#' }
#'
#' @export
reset_token_usage <- function() {
  .token_ledger$records <- list()
  message("token_usage: ledger cleared.")
  invisible(NULL)
}
