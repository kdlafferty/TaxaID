# GBIF Backbone keys. TaxaID's GBIF identifiers are GBIF Backbone Taxonomy keys, which are integers.
# rgbif 3.9.0 and later match names against the Catalogue of Life Extended Release by default and
# return its alphanumeric keys (e.g. "Q2M4"), so every name-matching call names the Backbone
# checklist explicitly, and a key that is not an integer stops with an error rather than
# becoming NA.

#' The GBIF Backbone Taxonomy's checklist key, passed as `checklistKey` to rgbif name matching
#' @noRd
.GBIF_BACKBONE_CHECKLIST <- "d7dddbf4-2cf0-4f39-9b2a-bb099caae36c"

#' GBIF taxon keys as integers; any non-NA value that is not an integer is an error
#' (class `taxaid_gbif_key_not_backbone`), never a silent NA
#' @noRd
.gbif_backbone_key <- function(x, what) {
  x <- unlist(x, use.names = FALSE)
  if (!length(x)) return(integer(0))
  if (is.numeric(x)) return(as.integer(x))
  s <- trimws(as.character(x))
  bad <- !is.na(s) & nzchar(s) & !grepl("^[0-9]+$", s)
  if (any(bad)) {
    shown <- unique(s[bad])
    stop(structure(class = c("taxaid_gbif_key_not_backbone", "error", "condition"), list(
      message = sprintf(paste0(
        "%s: %d GBIF taxon key(s) are not GBIF Backbone keys (%s). TaxaID's GBIF keys are Backbone ",
        "integers; rgbif 3.9.0 and later return Catalogue of Life keys unless checklistKey names the ",
        "GBIF Backbone (\"%s\")."
      ), what, sum(bad), paste0("\"", utils::head(shown, 5L), "\"", collapse = ", "), .GBIF_BACKBONE_CHECKLIST),
      call = NULL
    )))
  }
  s[!nzchar(s)] <- NA_character_
  as.integer(s)
}

#' Evaluate `expr`, silencing only rgbif's notice that a function "works by default with the
#' out-of-date GBIF Backbone Taxonomy": TaxaID uses the Backbone deliberately
#' @noRd
.gbif_quiet_backbone_notice <- function(expr) {
  withCallingHandlers(expr, warning = function(w) {
    if (grepl("works by default with the out-of-date GBIF Backbone Taxonomy", conditionMessage(w), fixed = TRUE)) {
      invokeRestart("muffleWarning")
    }
  })
}

#' Stop unless the installed rgbif can name a checklist: `checklistKey` reached
#' name_backbone() and name_backbone_checklist() in rgbif 3.8.4
#' @noRd
.gbif_require_checklist_rgbif <- function(what, v = utils::packageVersion("rgbif")) {
  if (v < "3.8.4") {
    stop(structure(class = c("taxaid_rgbif_too_old", "error", "condition"), list(
      message = sprintf(paste0(
        "%s: rgbif %s cannot ask GBIF for the Backbone checklist (checklistKey reached name matching in rgbif 3.8.4). ",
        "Install rgbif 3.8.4 or later."
      ), what, v),
      call = NULL
    )))
  }
  invisible(TRUE)
}
