
#' Flag Detections Near Start or End of a Sampling Period
#'
#' Identifies detections that occur within a user-specified time interval
#' of the earliest or latest timestamp in each group (e.g., camera station,
#' sampling event). Detections near these edges are likely handler artifacts
#' (researcher setting up or retrieving equipment).
#'
#' This is a placeholder implementation for camera trap and similar
#' time-stamped detection data. The datetime column is auto-parsed using
#' \code{\link[base]{as.POSIXct}} with common format guessing.
#'
#' @param df Data frame with at minimum a datetime column, a taxon column,
#'   and optionally a grouping column (e.g., station or site).
#' @param datetime_col Character. Column name containing timestamps. The
#'   function attempts to parse with several common formats. Default
#'   \code{"datetime"}.
#' @param taxon_col Character. Column name identifying taxa. Default
#'   \code{"taxon_name"}.
#' @param group_col Character or \code{NULL}. Column name for grouping
#'   (e.g., camera station). Min/max times are computed within each group.
#'   If \code{NULL}, all rows are treated as one group. Default \code{NULL}.
#' @param interval_minutes Numeric. Minutes from the earliest or latest
#'   timestamp within each group to flag. Default \code{30}.
#' @param handler_taxa Character vector or \code{NULL}. If supplied, only
#'   these taxa are flagged (e.g., \code{"Homo sapiens"}). Other taxa
#'   within the interval receive a score but are flagged \code{"likely"}.
#'   If \code{NULL}, all taxa within the interval are flagged. Default
#'   \code{NULL}.
#' @param verbose Logical. Print summary messages. Default \code{TRUE}.
#'
#' @return The input data frame with three columns appended:
#' \describe{
#'   \item{\code{flag_handler}}{Character. \code{"likely"} (valid detection),
#'     \code{"possible"}, or \code{"unlikely"} (probable handler artifact).}
#'   \item{\code{flag_handler_score}}{Numeric 0--1. 1.0 for detections
#'     outside the interval; decreasing toward 0 as the detection approaches
#'     the min/max timestamp.}
#'   \item{\code{flag_handler_reason}}{Character. Plain-English explanation.}
#' }
#'
#' @seealso \code{\link{flag_contaminant}} for data-driven contaminant detection,
#'   \code{\link{review_assignments}} for LLM-based expert review
#'
#' @examples
#' \dontrun{
#' # Flag detections within 30 minutes of camera setup/retrieval
#' flagged <- flag_handler(
#'   df               = camera_detections,
#'   datetime_col     = "datetime",
#'   group_col        = "station",
#'   interval_minutes = 30,
#'   handler_taxa     = "Homo sapiens"
#' )
#' }
#'
#' @export
flag_handler <- function(df,
                         datetime_col     = "datetime",
                         taxon_col        = "taxon_name",
                         group_col        = NULL,
                         interval_minutes = 30,
                         handler_taxa     = NULL,
                         verbose          = TRUE) {

  # --- Input validation ---
  if (!is.data.frame(df)) stop("'df' must be a data frame.", call. = FALSE)

  for (col in c(datetime_col, taxon_col)) {
    if (!col %in% names(df))
      stop(sprintf("Column '%s' not found in df.", col), call. = FALSE)
  }

  if (!is.null(group_col) && !group_col %in% names(df))
    stop(sprintf("Column '%s' not found in df.", group_col), call. = FALSE)

  if (!is.numeric(interval_minutes) || length(interval_minutes) != 1L ||
      interval_minutes <= 0)
    stop("'interval_minutes' must be a single positive number.", call. = FALSE)

  # --- Parse datetimes ---
  parsed <- .parse_datetimes(df[[datetime_col]])
  if (all(is.na(parsed)))
    stop(sprintf("Could not parse any values in column '%s' as datetimes.",
                 datetime_col), call. = FALSE)

  n_failed <- sum(is.na(parsed) & !is.na(df[[datetime_col]]))
  if (n_failed > 0L && verbose)
    message(sprintf("flag_handler: %d of %d datetime values could not be parsed.",
                    n_failed, nrow(df)))

  df$datetime_parsed <- parsed

  # --- Compute min/max per group ---
  if (is.null(group_col)) {
    df$.tmp_group <- "all"
  } else {
    df$.tmp_group <- df[[group_col]]
  }

  group_edges <- stats::aggregate(
    datetime_parsed ~ .tmp_group,
    data = df[!is.na(df$datetime_parsed), , drop = FALSE],
    FUN = function(x) c(min = min(x), max = max(x))
  )
  # aggregate with FUN returning multiple values creates a matrix column
  edge_mat <- group_edges$datetime_parsed
  group_edges$group_min <- as.POSIXct(edge_mat[, "min"], origin = "1970-01-01")
  group_edges$group_max <- as.POSIXct(edge_mat[, "max"], origin = "1970-01-01")
  group_edges$datetime_parsed <- NULL

  df <- merge(df, group_edges, by = ".tmp_group", all.x = TRUE)

  # --- Compute scores ---
  interval_secs <- interval_minutes * 60

  mins_to_start <- as.numeric(difftime(df$datetime_parsed, df$group_min,
                                       units = "secs"))
  mins_to_end   <- as.numeric(difftime(df$group_max, df$datetime_parsed,
                                       units = "secs"))
  df$minutes_to_edge <- pmin(mins_to_start, mins_to_end) / 60

  # Score: 1.0 if outside interval, decreasing linearly to 0 at the edge

  df$handler_score <- ifelse(
    is.na(df$minutes_to_edge), NA_real_,
    pmin(1, pmax(0, df$minutes_to_edge / interval_minutes))
  )

  # --- Apply handler_taxa filter ---
  if (!is.null(handler_taxa)) {
    is_handler_taxon <- df[[taxon_col]] %in% handler_taxa
    # Non-handler taxa in the interval get score = 1 (not flagged)
    df$handler_score <- ifelse(!is_handler_taxon, 1.0, df$handler_score)
  }

  # --- Assign flags ---
  df$flag_handler <- dplyr::case_when(
    is.na(df$handler_score)  ~ NA_character_,
    df$handler_score >= 1.0  ~ "likely",
    df$handler_score >= 0.5  ~ "possible",
    TRUE                     ~ "unlikely"
  )

  df$flag_handler_score <- df$handler_score

  # --- Build reason strings ---
  df$flag_handler_reason <- ifelse(
    is.na(df$handler_score), NA_character_,
    ifelse(df$handler_score >= 1.0,
           sprintf("%.1f min from nearest edge; outside %d-min interval",
                   df$minutes_to_edge, as.integer(interval_minutes)),
           sprintf("%.1f min from nearest edge; within %d-min interval, score %.3f",
                   df$minutes_to_edge, as.integer(interval_minutes),
                   df$handler_score))
  )

  # --- Clean up temporary columns ---
  df$datetime_parsed  <- NULL
  df$.tmp_group       <- NULL
  df$group_min        <- NULL
  df$group_max        <- NULL
  df$minutes_to_edge  <- NULL
  df$handler_score    <- NULL

  if (verbose) {
    n_unlikely <- sum(df$flag_handler == "unlikely", na.rm = TRUE)
    n_possible <- sum(df$flag_handler == "possible", na.rm = TRUE)
    n_likely   <- sum(df$flag_handler == "likely",   na.rm = TRUE)
    n_na       <- sum(is.na(df$flag_handler))
    message(sprintf("flag_handler: %d rows flagged: %d unlikely, %d possible, %d likely, %d NA.",
                    nrow(df), n_unlikely, n_possible, n_likely, n_na))
  }

  df
}


#' Parse Datetimes with Format Auto-detection
#'
#' Tries several common datetime formats and returns the first successful
#' parse. Already-POSIXct input is returned as-is.
#'
#' @param x Vector of datetime values (character, POSIXct, or Date).
#' @return POSIXct vector (NA for unparseable values).
#' @noRd
.parse_datetimes <- function(x) {
  if (inherits(x, "POSIXct")) return(x)
  if (inherits(x, "Date")) return(as.POSIXct(x))

  x <- as.character(x)

  formats <- c(
    "%Y-%m-%d %H:%M:%S",
    "%Y-%m-%dT%H:%M:%S",
    "%Y/%m/%d %H:%M:%S",
    "%m/%d/%Y %H:%M:%S",
    "%d/%m/%Y %H:%M:%S",
    "%Y-%m-%d %H:%M",
    "%Y-%m-%d",
    "%m/%d/%Y",
    "%d/%m/%Y"
  )

  for (fmt in formats) {
    parsed <- as.POSIXct(x, format = fmt)
    if (sum(!is.na(parsed)) > sum(!is.na(x)) * 0.5) return(parsed)
  }

  # Last resort: let R guess
  tryCatch(suppressWarnings(as.POSIXct(x)),
           error = function(e) rep(as.POSIXct(NA), length(x)))
}
