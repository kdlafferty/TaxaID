# ==============================================================================
# infer_predicted.R
# TaxaLikely — Infer whether predicted sequences were excluded from BLAST ref
# ==============================================================================

#' Infer whether predicted sequences were excluded from the BLAST reference
#'
#' Examines accession numbers in a match object to determine whether the BLAST
#' reference database included computationally predicted sequences (NCBI
#' \code{XR_} and \code{XM_} RefSeq accessions).  Returns \code{TRUE} if
#' predicted sequences appear to have been excluded — the correct value for
#' \code{\link{audit_barcode_coverage}}'s \code{exclude_predicted} argument
#' when using curated databases (Jonah Ventures, SILVA, PR2, MIDORI).
#' Returns \code{FALSE} if predicted sequences are present, or \code{NA} when
#' the accession column contains only custom (non-NCBI) identifiers and the
#' inference cannot be made.
#'
#' @param match_obj Data frame.  A standardised match object as produced by
#'   \code{TaxaMatch::standardize_match_data()} or a compatible user-supplied
#'   table.  Must contain an accession column.
#' @param accession_col Character scalar or \code{NULL}.  Name of the accession
#'   column.  If \code{NULL} (default) the function auto-detects a column named
#'   \code{"accession"}, \code{"Accession"}, \code{"acc"}, or \code{"accno"}.
#' @param verbose Logical.  If \code{TRUE} (default), emits a message
#'   explaining the inference and its basis.
#'
#' @return A single logical: \code{TRUE} (exclude predicted — no
#'   \code{XR_}/\code{XM_} accessions found among NCBI-format accessions),
#'   \code{FALSE} (do not exclude — predicted accessions are present in the
#'   match object), or \code{NA} (cannot determine — no standard NCBI
#'   accessions found; set \code{exclude_predicted} explicitly).
#'
#' @details
#' ## What predicted sequences are
#' NCBI predicted sequences carry \code{XR_} (predicted ncRNA, including rRNA)
#' or \code{XM_} (predicted mRNA) RefSeq prefixes.  They are computationally
#' annotated from whole-genome assemblies and are absent from curated barcode
#' databases used by metabarcoding labs (SILVA, PR2, MIDORI, Jonah Ventures).
#' Counting them as "has sequences in NCBI" incorrectly suppresses unreferenced-
#' species hypotheses for taxa whose only NCBI entry is a predicted record.
#'
#' ## How inference works
#' Standard NCBI accessions match the pattern
#' \code{^([A-Z]\{1,2\}_[0-9]|[A-Z]\{2,4\}[0-9])}: a RefSeq two-letter prefix
#' followed by underscore + digit (e.g. \code{NR_}, \code{XR_}, \code{NM_}), or
#' a GenBank letter-block immediately followed by digits (e.g. \code{AB123456},
#' \code{KP891234}).  Custom accessions such as \code{JV_voucher_*} or internal
#' lab IDs do not match this pattern and are excluded from the check.  When the
#' column contains a mix of custom and NCBI accessions, only the NCBI subset is
#' examined.
#'
#' ## NA return and fallback
#' If all accessions are custom (e.g. a fully curated lab database with no NCBI
#' identifiers), or if the match object has no accession column at all (e.g.
#' WilderLab/Mugu workflows where the match object is built directly from ESV
#' taxonomy tables), the function returns \code{NA}.  Use \code{!isFALSE()} to
#' apply a safe default:
#' \preformatted{
#' ep <- infer_exclude_predicted(match_obj)
#' coverage <- audit_barcode_coverage(..., exclude_predicted = !isFALSE(ep))
#' }
#' \code{!isFALSE(ep)} is \code{TRUE} for both \code{TRUE} and \code{NA}, and
#' \code{FALSE} only when the function confirmed predicted sequences are present.
#' This is safer than \code{ep \%||\% TRUE} because \code{\%||\%} replaces
#' \code{NULL} but not \code{NA}.
#'
#' @seealso \code{\link{audit_barcode_coverage}}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Typical usage — result feeds directly into audit_barcode_coverage()
#' ep <- infer_exclude_predicted(match_obj)
#' coverage <- audit_barcode_coverage(
#'   genus_species_audit,
#'   barcode_term      = "18S",
#'   target_rank       = "genus",
#'   exclude_predicted = !isFALSE(ep)
#' )
#' }
infer_exclude_predicted <- function(match_obj,
                                    accession_col = NULL,
                                    verbose       = TRUE) {

  # ---- resolve accession column -----------------------------------------------
  if (!is.data.frame(match_obj))
    stop("match_obj must be a data frame.")

  if (is.null(accession_col)) {
    candidates <- c("accession", "Accession", "acc", "accno", "AccessionNumber")
    found      <- intersect(candidates, names(match_obj))
    if (length(found) == 0L) {
      if (verbose)
        message("infer_exclude_predicted: no accession column found ",
                "(tried: ", paste(candidates, collapse = ", "), "). ",
                "Returning NA -- set exclude_predicted explicitly.")
      return(NA)
    }
    accession_col <- found[1L]
  } else {
    if (!accession_col %in% names(match_obj))
      stop(sprintf("Column '%s' not found in match_obj.", accession_col))
  }

  acc <- as.character(match_obj[[accession_col]])
  acc <- acc[!is.na(acc) & nzchar(trimws(acc))]

  if (length(acc) == 0L) {
    if (verbose)
      message("infer_exclude_predicted: accession column is empty. ",
              "Returning NA.")
    return(NA)
  }

  # Strip version suffix (.1, .2, ...)
  acc_base <- sub("\\.[0-9]+$", "", acc)

  # Identify NCBI-style accessions:
  #   RefSeq:  ^[A-Z]{1,2}_[0-9]  (NR_, XR_, NM_, XM_, NC_, NW_, ...)
  #   GenBank: ^[A-Z]{2,4}[0-9]   (AB123456, KP891234, AAAA01000001, ...)
  ncbi_mask <- grepl("^([A-Z]{1,2}_[0-9]|[A-Z]{2,4}[0-9])", acc_base)
  n_ncbi    <- sum(ncbi_mask)
  n_total   <- length(acc_base)
  n_custom  <- n_total - n_ncbi

  if (n_ncbi == 0L) {
    if (verbose)
      message(sprintf(
        "infer_exclude_predicted: all %d accession(s) appear to be custom ",
        n_total),
        "(non-NCBI format, e.g. lab vouchers). ",
        "Cannot infer exclude_predicted. Returning NA -- set it explicitly.")
    return(NA)
  }

  ncbi_acc    <- acc_base[ncbi_mask]
  n_predicted <- sum(grepl("^X[RM]_", ncbi_acc))

  if (n_predicted > 0L) {
    if (verbose)
      message(sprintf(
        "infer_exclude_predicted: %d predicted (XR_/XM_) accession(s) found ",
        n_predicted),
        sprintf("among %d NCBI accession(s). Reference includes predicted ",
                n_ncbi),
        "sequences -- exclude_predicted = FALSE.")
    return(FALSE)
  }

  if (verbose) {
    custom_note <- if (n_custom > 0L)
      sprintf(" (%d custom/non-NCBI accession(s) not examined)", n_custom)
    else
      ""
    message(sprintf(
      "infer_exclude_predicted: no XR_/XM_ accessions found among %d NCBI ",
      n_ncbi),
      sprintf("accession(s)%s. Reference excludes predicted sequences -- ",
              custom_note),
      "exclude_predicted = TRUE.")
  }
  TRUE
}
