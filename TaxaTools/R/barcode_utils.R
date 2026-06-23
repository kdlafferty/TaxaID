#' Default NCBI Nucleotide Length Ranges by Barcode Type
#'
#' A named list mapping lowercase barcode marker names to integer vectors
#' `c(min_bp, max_bp)`.  Keys are matched by prefix or substring (case
#' insensitive) so `"MiFishU"` matches `"mifish"`.  Length ranges are
#' intentionally generous to accommodate primer variation and partial
#' sequences.
#'
#' @format A named list of length 12.  Each element is an integer vector of
#'   length 2 (`c(min, max)`).
#'
#' @references
#' Miya et al. (2015) for MiFish/12S; Ward et al. (2005) for COI;
#' CBOL Plant Working Group (2009) for rbcL/matK; Taberlet et al. (2007)
#' for trnL; Schoch et al. (2012) for ITS/ITS2.
#'
#' @examples
#' barcode_length_defaults[["coi"]]
#' # 300 900
#'
#' @export
barcode_length_defaults <- list(
  "mifish" = c(130L,  210L),   # MiFishU/E 12S amplicon 163-185 bp; bounds exclude non-target cross-amplicons
  "teleo"  = c( 50L,  300L),   # Teleo 12S amplicon ~60-100 bp
  "12s"    = c(100L,  600L),   # General 12S vertebrate
  "16s"    = c(100L,  700L),   # 16S vertebrate ~200-450 bp
  "coi"    = c(300L,  900L),   # COI Folmer ~650 bp; mini ~130-200 bp
  "cytb"   = c(200L,  900L),   # CytB partial ~300-700 bp
  "its2"   = c(100L,  600L),   # ITS2 ~200-350 bp
  "its"    = c(100L,  900L),   # ITS full ~500-750 bp
  "rbcl"   = c(400L,  800L),   # rbcL ~550-650 bp
  "matk"   = c(600L, 1100L),   # matK ~800-900 bp
  "18s"    = c(100L, 2000L),   # 18S varies by primer set
  "trnl"   = c( 10L,  300L)    # trnL P6 loop ~10-150 bp
)


#' Resolve Barcode Length Bounds from a Barcode Term
#'
#' Looks up `barcode_term` in [barcode_length_defaults] and returns
#' `c(min_bp, max_bp)`.
#'
#' For vector input (multiple marker names), collects all matched ranges and
#' returns `c(min(mins), max(maxes))` so the query covers all supplied terms.
#' User-supplied `min_len` / `max_len` override the resolved bounds.
#'
#' @param barcode_term Character vector of barcode marker names (e.g.
#'   `"MiFishU"`, `"COI"`, `c("12S", "16S")`).
#' @param min_len,max_len Optional integer overrides.  When non-`NULL`,
#'   replace the auto-detected bound.
#'
#' @return Integer vector of length 2: `c(min_bp, max_bp)`.
#'
#' @examples
#' resolve_barcode_lengths("MiFishU")
#' # 130 210
#' resolve_barcode_lengths(c("12S", "16S"))
#' # 100 700  (union of both ranges)
#' resolve_barcode_lengths("COI", min_len = 500)
#' # 500 900  (min_len overrides auto-detected)
#'
#' @export
resolve_barcode_lengths <- function(barcode_term, min_len = NULL,
                                    max_len = NULL) {
  if (!is.null(min_len) && !is.null(max_len))
    return(c(as.integer(min_len), as.integer(max_len)))

  if (is.null(barcode_term))
    stop("Specify barcode_term for auto-detection, or provide both min_len and max_len")

  all_ranges <- lapply(barcode_term, function(bt) {
    key <- tolower(trimws(bt))
    for (nm in names(barcode_length_defaults)) {
      if (startsWith(key, nm) || grepl(nm, key, fixed = TRUE))
        return(barcode_length_defaults[[nm]])
    }
    NULL
  })

  matched <- Filter(Negate(is.null), all_ranges)

  if (length(matched) == 0L) {
    resolved <- c(100L, 2000L)
    if (is.null(min_len) || is.null(max_len))
      message(sprintf(
        "No length defaults found for barcode_term '%s'. Using fallback 100-2000 bp. ",
        paste(barcode_term, collapse = "/")
      ), "Supply min_len/max_len to override.")
  } else {
    all_mins  <- vapply(matched, `[`, integer(1L), 1L)
    all_maxes <- vapply(matched, `[`, integer(1L), 2L)
    resolved  <- c(min(all_mins), max(all_maxes))
  }

  if (!is.null(min_len)) resolved[1L] <- as.integer(min_len)
  if (!is.null(max_len)) resolved[2L] <- as.integer(max_len)

  resolved
}
