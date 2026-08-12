# ==============================================================================
# utils_shared.R
# TaxaMatch -- internal helpers shared across the read_*()/blast/score_image_inat
# ingest functions. Added during the code-review response pass (see
# inst/taxamatch_review_response.md) to consolidate patterns the review found
# duplicated across blast.R, read_acoustic.R, read_image.R, and
# score_image_inat.R.
#
# Internal helpers (@noRd):
#   .check_pkg              -- requireNamespace() guard with an informative stop()
#   .stop_missing_files     -- consistent "file(s) not found" error across ingest fns
#   .extract_genus          -- genus token from a binomial species name (vectorized)
#   .validate_min_conf_top_n -- shared min_confidence/top_n input validation
#   .apply_top_n            -- keep top N rows per group_col, ordered by score_col desc
# ==============================================================================

#' Guard a Suggests-only namespace, stopping with an informative message
#' @noRd
.check_pkg <- function(pkg, install_cmd = NULL) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    stop(sprintf(
      "Package '%s' is required for this function. Install with %s.",
      pkg,
      if (is.null(install_cmd)) sprintf('install.packages("%s")', pkg) else install_cmd
    ), call. = FALSE)
  }
  invisible(TRUE)
}

#' Stop with a consistently formatted "file(s) not found" message
#' @noRd
.stop_missing_files <- function(missing_files, fn_name) {
  stop(sprintf(
    "%s: file(s) not found:\n  %s",
    fn_name, paste(missing_files, collapse = "\n  ")
  ), call. = FALSE)
}

#' Extract genus from a binomial species name (vectorized)
#'
#' Returns the first whitespace-delimited token when \code{x} looks like a
#' standard binomial (\code{"Genus species"}); \code{NA_character_} otherwise
#' (single-word labels, hybrid notations, placeholder strings such as
#' \code{"empty"}/\code{"blank"}/\code{"human"}).
#' @noRd
.extract_genus <- function(x) {
  out <- rep(NA_character_, length(x))
  is_binomial <- !is.na(x) & grepl("^[A-Z][a-z]+ [a-z]", x)
  out[is_binomial] <- sub("^(\\S+).*", "\\1", x[is_binomial])
  out
}

#' Validate min_confidence/top_n shared by the classifier-output readers
#'
#' Checks type before coercion (rather than coercing `top_n` with
#' \code{as.integer()} first) so a non-numeric input produces this function's
#' clear error rather than a cryptic coercion warning followed by a generic
#' NA-check failure. Returns the validated, integer-coerced \code{top_n}.
#' @noRd
.validate_min_conf_top_n <- function(min_confidence, top_n, fn_name) {
  if (!is.numeric(min_confidence) || length(min_confidence) != 1L ||
      is.na(min_confidence)) {
    stop(sprintf("%s: `min_confidence` must be a single numeric value.", fn_name),
         call. = FALSE)
  }
  if (!is.null(top_n)) {
    if (!is.numeric(top_n) || length(top_n) != 1L || is.na(top_n) || top_n < 1) {
      stop(sprintf("%s: `top_n` must be a single positive integer, or NULL.", fn_name),
           call. = FALSE)
    }
    top_n <- as.integer(top_n)
  }
  top_n
}

#' Keep the top N rows per group, ordered by score descending
#'
#' \code{NULL} \code{top_n} is a no-op (returns \code{input_df} unchanged).
#' @noRd
.apply_top_n <- function(input_df, group_col, score_col, top_n) {
  if (is.null(top_n) || nrow(input_df) == 0L) return(input_df)
  groups <- split(input_df, input_df[[group_col]])
  out <- lapply(groups, function(g) {
    g[order(-g[[score_col]]), , drop = FALSE][seq_len(min(top_n, nrow(g))), , drop = FALSE]
  })
  do.call(rbind, out)
}

#' Warn when as.numeric() coercion introduced new NAs
#'
#' Compares an already-non-NA raw value against its coerced counterpart;
#' a raw value that was not itself NA but coerced to NA indicates malformed
#' (non-numeric) source data, not a genuine missing value.
#' @noRd
.warn_na_coercion <- function(raw, coerced, col_name, source_label) {
  bad <- is.na(coerced) & !is.na(raw) & nzchar(as.character(raw))
  if (any(bad)) {
    warning(sprintf(
      "%s: %d value(s) in column '%s' could not be coerced to numeric.",
      source_label, sum(bad), col_name
    ), call. = FALSE)
  }
  invisible(NULL)
}

#' Warn when a "File" column's basenames collide across different directories
#'
#' A duplicate basename (e.g. \code{"recording.wav"} from two different
#' directories) would otherwise produce indistinguishable observation_id
#' stems for genuinely different recordings/images. \code{paths} legitimately
#' repeats the same full path across multiple rows in long-format data
#' (e.g. one row per candidate species for the same image) -- that is not a
#' collision, so uniqueness is checked on (basename, full path) pairs first;
#' only a basename mapping to more than one distinct full path is flagged.
#' @noRd
.warn_duplicate_basenames <- function(paths, fn_name) {
  paths     <- trimws(as.character(paths))
  base      <- basename(paths)
  unique_pairs <- unique(data.frame(base = base, path = paths, stringsAsFactors = FALSE))
  dup  <- unique(unique_pairs$base[duplicated(unique_pairs$base)])
  if (length(dup) > 0L) {
    warning(sprintf(
      paste0(
        "%s: %d duplicate basename(s) found across different source paths ",
        "(e.g. %s); their observation_id stems will collide."
      ),
      fn_name, length(dup), paste(utils::head(dup, 3L), collapse = ", ")
    ), call. = FALSE)
  }
  invisible(NULL)
}

#' Format a numeric time value with a fixed decimal count for stable IDs
#'
#' Guards against the same window producing different \code{observation_id}
#' strings on different platforms/R versions due to default numeric-to-
#' character formatting (e.g. \code{3} vs \code{3.0}).
#' @noRd
.fmt_time <- function(x, digits = 1L) {
  ifelse(is.na(x), NA_character_, sprintf(paste0("%.", digits, "f"), x))
}
