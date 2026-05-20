# ==============================================================================
# report_fetch.R
# TaxaFetch -- Summarize data acquisition for Methods/Results reporting
#
# Exported functions:
#   report_fetch()   -- generate report_section from stacked occurrence data
#
# Session 65: initial implementation
# ==============================================================================


#' Generate a Report Section for Data Acquisition
#'
#' Summarizes the occurrence data fetched by TaxaFetch into a structured
#' \code{report_section} object (from TaxaTools). Works standalone or feeds
#' into \code{TaxaTools::assemble_report()} for a unified pipeline report.
#'
#' @param occurrences Data frame. Stacked occurrence records, typically the
#'   output of \code{\link{stack_occurrences}}. Must contain at least
#'   \code{scientificName}. Optionally contains \code{bibliographicCitation},
#'   \code{decimalLatitude}, \code{decimalLongitude}, \code{year},
#'   \code{datasetID}.
#' @param study_area Character or \code{NULL}. Plain-language description of
#'   the study area (e.g. \code{"Southern California coast"}). If \code{NULL},
#'   the geographic extent is described from coordinate ranges.
#' @param verbose Logical. Print summary messages. Default \code{FALSE}.
#'
#' @return A \code{report_section} object (S3 class from TaxaTools) with:
#' \describe{
#'   \item{methods}{Template text describing data sources and scope.}
#'   \item{results}{Template text summarizing record counts.}
#'   \item{citations}{Unique values from \code{bibliographicCitation} column.}
#'   \item{params}{Named list of acquisition parameters (bbox, year_range).}
#'   \item{statistics}{Named list of summary counts.}
#' }
#'
#' @seealso \code{\link{stack_occurrences}}
#'
#' @examples
#' \dontrun{
#' occ <- stack_occurrences(list(gbif_occ, dataone_occ, pdf_occ))
#' sec <- report_fetch(occ, study_area = "Santa Barbara Channel")
#' print(sec)
#' }
#'
#' @export
report_fetch <- function(occurrences,
                         study_area = NULL,
                         verbose    = FALSE) {


  if (!is.data.frame(occurrences) || nrow(occurrences) == 0L)
    stop("report_fetch: 'occurrences' must be a non-empty data frame.",
         call. = FALSE)

  # --- Read report_params if available ----------------------------------------
  rp <- attr(occurrences, "report_params")


  # --- Extract citations ------------------------------------------------------
  citations <- NULL
  if ("bibliographicCitation" %in% names(occurrences)) {
    citations <- unique(occurrences$bibliographicCitation)
    citations <- citations[!is.na(citations) & nzchar(citations)]
    if (length(citations) == 0L) citations <- NULL
  }

  # --- Detect sources from datasetID prefix -----------------------------------
  sources <- list()
  if ("datasetID" %in% names(occurrences)) {
    ds <- occurrences$datasetID
    sources$gbif    <- sum(grepl("^gbif:", ds, ignore.case = TRUE), na.rm = TRUE)
    sources$biotime <- sum(grepl("^biotime:", ds, ignore.case = TRUE), na.rm = TRUE)
    sources$dataone <- sum(grepl("^dataone:|^doi:", ds, ignore.case = TRUE), na.rm = TRUE)
    sources$pdf     <- sum(grepl("\\.pdf", ds, ignore.case = TRUE), na.rm = TRUE)
    # Anything else
    known <- sources$gbif + sources$biotime + sources$dataone + sources$pdf
    sources$other   <- nrow(occurrences) - known
    # Remove zero-count sources
    sources <- sources[vapply(sources, function(x) x > 0L, logical(1L))]
  }

  # --- Geographic extent ------------------------------------------------------
  bbox_text <- NULL
  if (all(c("decimalLatitude", "decimalLongitude") %in% names(occurrences))) {
    lat <- occurrences$decimalLatitude
    lon <- occurrences$decimalLongitude
    lat <- lat[!is.na(lat)]
    lon <- lon[!is.na(lon)]
    if (length(lat) > 0L && length(lon) > 0L) {
      bbox_text <- sprintf("lat [%.2f, %.2f], lon [%.2f, %.2f]",
                           min(lat), max(lat), min(lon), max(lon))
    }
  }

  # --- Temporal extent --------------------------------------------------------
  year_text <- NULL
  if ("year" %in% names(occurrences)) {
    yrs <- occurrences$year[!is.na(occurrences$year)]
    if (length(yrs) > 0L) {
      year_text <- sprintf("%d-%d", min(yrs), max(yrs))
    }
  }

  # --- Statistics -------------------------------------------------------------
  n_records   <- nrow(occurrences)
  n_taxa      <- length(unique(occurrences$scientificName[
    !is.na(occurrences$scientificName)]))
  n_sources   <- max(1L, length(sources))

  statistics <- list(
    n_records = n_records,
    n_taxa    = n_taxa,
    n_sources = n_sources
  )

  # --- Build source description -----------------------------------------------
  source_parts <- character(0L)
  if (length(sources) > 0L) {
    source_names <- c(
      gbif = "GBIF", biotime = "BioTime", dataone = "DataONE",
      pdf = "published literature", other = "other sources"
    )
    for (nm in names(sources)) {
      label <- if (nm %in% names(source_names)) source_names[[nm]] else nm
      source_parts <- c(source_parts,
                        sprintf("%s (n = %d)", label, sources[[nm]]))
    }
  }

  # --- Methods text -----------------------------------------------------------
  methods_parts <- "Occurrence records were obtained from"
  if (length(source_parts) > 0L) {
    methods_parts <- paste0(methods_parts, " ",
                            paste(source_parts, collapse = ", "), ".")
  } else {
    methods_parts <- paste0(methods_parts, " biodiversity databases.")
  }

  if (!is.null(study_area)) {
    methods_parts <- paste0(methods_parts,
                            sprintf(" The study area encompassed %s.", study_area))
  } else if (!is.null(bbox_text)) {
    methods_parts <- paste0(methods_parts,
                            sprintf(" Geographic extent: %s.", bbox_text))
  }

  if (!is.null(year_text)) {
    methods_parts <- paste0(methods_parts,
                            sprintf(" Records spanned %s.", year_text))
  }

  # --- Results text -----------------------------------------------------------
  results_text <- sprintf(
    "A total of %s occurrence records were compiled across %d unique taxa",
    format(n_records, big.mark = ","), n_taxa
  )
  if (n_sources > 1L) {
    results_text <- paste0(results_text,
                           sprintf(" from %d data sources", n_sources))
  }
  results_text <- paste0(results_text, ".")

  if (!is.null(bbox_text) && is.null(study_area)) {
    results_text <- paste0(results_text,
                           sprintf(" Coordinates spanned %s.", bbox_text))
  }

  # --- Params -----------------------------------------------------------------
  params <- list()
  if (!is.null(bbox_text)) params$bbox <- bbox_text
  if (!is.null(year_text)) params$year_range <- year_text
  if (!is.null(study_area)) params$study_area <- study_area
  # Merge any existing report_params

  if (!is.null(rp)) params <- c(params, rp[!names(rp) %in% names(params)])

  # --- Construct report_section -----------------------------------------------
  TaxaTools::new_report_section(
    package    = "TaxaFetch",
    section    = "fetch",
    methods    = methods_parts,
    results    = results_text,
    citations  = citations,
    params     = params,
    statistics = statistics
  )
}
