utils::globalVariables(c(
  "organismQuantity", "biotime_biomass"
))

# -- read_biotime_study ---------------------------------------------------------

#' Read and DwC-map a downloaded BioTime study CSV
#'
#' Reads a single-study occurrence CSV downloaded from the BioTime database
#' and returns a Darwin Core-mapped tibble compatible with
#' [stack_occurrences()].
#'
#' @section Obtaining BioTime data:
#' BioTime (<https://biotime.st-andrews.ac.uk>) is a global database of
#' biodiversity time-series assembled from published studies.  Data are
#' provided as per-study CSVs -- one file per study -- and are **not** available
#' via a query API.  To download a study:
#'
#' 1. Go to <https://biotime.st-andrews.ac.uk/home.php> and register for a
#'    free account.
#' 2. Browse or search the study list to find studies relevant to your taxon
#'    and region.  Each study has a numeric STUDY_ID (e.g. 595).
#' 3. On the study page, click **Download data** to save the CSV
#'    (typically named `raw_data_<STUDY_ID>.csv`).
#' 4. Note the STUDY_ID -- pass it to the `study_id` argument so that
#'    `datasetID` is populated correctly in the output.
#'
#' **Citation:** BioTime requires that you cite both the database and the
#' original study.  The DOI for the BioTime database is
#' 10.1111/geb.12729 (Dornelas et al. 2018, *Global Ecology and Biogeography*).
#' Per-study citations are shown on each study's BioTime page.
#'
#' @section Column mapping:
#' BioTime per-study CSVs use the following columns, which are mapped to
#' Darwin Core:
#'
#' \describe{
#'   \item{`valid_name`}{-> `scientificName`}
#'   \item{`LATITUDE`}{-> `decimalLatitude`}
#'   \item{`LONGITUDE`}{-> `decimalLongitude`}
#'   \item{`ABUNDANCE`}{-> `organismQuantity`; `organismQuantityType` set to
#'     `"abundance"`}
#'   \item{`BIOMAS`}{-> `biotime_biomass` (non-DwC passthrough; note the
#'     one-s spelling in BioTime source files)}
#'   \item{`DAY`, `MONTH`, `YEAR`}{-> `day`, `month`, `year`}
#'   \item{`SAMPLE_DESC`}{-> `eventID` (BioTime sample identifier)}
#' }
#'
#' `occurrenceStatus` is set to `"present"` when `ABUNDANCE > 0` or
#' `BIOMAS > 0`, and `"absent"` otherwise.  Explicit zero records are
#' retained; filter with
#' `dplyr::filter(occurrenceStatus == "present")` if absences are not needed.
#'
#' @param local_path Character scalar or `NULL`.  Path to the downloaded
#'   BioTime study CSV.  If `NULL` (the default), a system file-chooser
#'   dialog is opened so you can navigate to the file interactively.
#'   Passing a path directly is recommended for reproducible scripts.
#' @param study_id Character or integer scalar or `NULL`.  The BioTime
#'   STUDY_ID for this file (e.g. `595L` or `"595"`).  Used to populate
#'   the `datasetID` column as `"biotime:<study_id>"`.  If `NULL`, the
#'   numeric portion of the filename is used when the filename matches the
#'   pattern `raw_data_<id>.csv`; otherwise `datasetID` is set to
#'   `"biotime:unknown"` with a warning.
#' @param verbose Logical.  Print progress messages.  Default `TRUE`.
#'
#' @return A tibble with Darwin Core columns plus BioTime-specific
#'   passthroughs, compatible with [stack_occurrences()]:
#' \describe{
#'   \item{`scientificName`}{Character.  From `valid_name`.}
#'   \item{`decimalLatitude`}{Numeric.}
#'   \item{`decimalLongitude`}{Numeric.}
#'   \item{`year`}{Integer.}
#'   \item{`month`}{Integer or NA.}
#'   \item{`day`}{Integer or NA.}
#'   \item{`occurrenceStatus`}{Character.  `"present"` or `"absent"`.}
#'   \item{`organismQuantity`}{Numeric.  ABUNDANCE value.}
#'   \item{`organismQuantityType`}{Character.  `"abundance"`.}
#'   \item{`eventID`}{Character.  BioTime SAMPLE_DESC value.}
#'   \item{`datasetID`}{Character.  `"biotime:<study_id>"`.}
#'   \item{`basisOfRecord`}{Character.  `"HumanObservation"`.}
#'   \item{`biotime_biomass`}{Numeric.  BIOMAS value (passthrough).}
#' }
#'
#' @seealso [stack_occurrences()], [fetch_gbif_occurrences()],
#'   [fetch_dataone_occurrences()]
#'
#' @examples
#' \dontrun{
#' # Interactive file chooser -- useful in RStudio
#' occ <- read_biotime_study()
#'
#' # Explicit path with study ID
#' occ <- read_biotime_study("~/Downloads/raw_data_595.csv", study_id = 595L)
#'
#' # Stack with other sources
#' all_occ <- stack_occurrences(list(occ, dataone_occ, gbif_occ))
#' }
#'
#' @export
read_biotime_study <- function(local_path = NULL,
                               study_id   = NULL,
                               verbose    = TRUE) {

  # -- input validation --------------------------------------------------------
  if (!is.null(local_path) &&
      (!is.character(local_path) || length(local_path) != 1L)) {
    stop("`local_path` must be a single character string or NULL.", call. = FALSE)
  }
  if (!is.logical(verbose) || length(verbose) != 1L || is.na(verbose)) {
    stop("`verbose` must be TRUE or FALSE.", call. = FALSE)
  }

  # -- file chooser -------------------------------------------------------------
  if (is.null(local_path)) {
    if (!interactive()) {
      stop(
        "`local_path` is NULL and R is not running interactively.\n",
        "Provide the path to your downloaded BioTime CSV explicitly:\n",
        "  read_biotime_study(local_path = \"path/to/raw_data_595.csv\",\n",
        "                     study_id   = 595L)",
        call. = FALSE
      )
    }
    if (verbose) message(
      "No path supplied -- opening file chooser.\n",
      "Navigate to your downloaded BioTime CSV (e.g. raw_data_595.csv).\n",
      "Download studies from https://biotime.st-andrews.ac.uk/home.php"
    )
    local_path <- file.choose()
    if (!nzchar(local_path)) stop("No file selected.", call. = FALSE)
  }

  if (!file.exists(local_path)) {
    stop(
      "File not found: ", local_path, "\n\n",
      "To obtain BioTime data:\n",
      "  1. Register at https://biotime.st-andrews.ac.uk/home.php (free)\n",
      "  2. Browse studies and find one relevant to your taxon and region\n",
      "  3. Click 'Download data' on the study page\n",
      "  4. Save the CSV (e.g. raw_data_595.csv) to your computer\n",
      "  5. Pass the saved path to local_path, e.g.:\n",
      "       read_biotime_study(\"~/Downloads/raw_data_595.csv\",\n",
      "                          study_id = 595L)",
      call. = FALSE
    )
  }

  # -- resolve study_id ---------------------------------------------------------
  if (is.null(study_id)) {
    # Try to extract from filename pattern raw_data_<id>.csv
    fname    <- basename(local_path)
    id_match <- regmatches(fname, regexpr("(?<=raw_data_)\\d+", fname, perl = TRUE))
    if (length(id_match) == 1L && nzchar(id_match)) {
      study_id <- id_match
      if (verbose) message(sprintf(
        "study_id inferred from filename: %s (datasetID = \"biotime:%s\")",
        study_id, study_id
      ))
    } else {
      warning(
        "Could not infer study_id from filename '", fname, "'.\n",
        "datasetID will be set to \"biotime:unknown\".\n",
        "Pass study_id explicitly to fix:\n",
        "  read_biotime_study(local_path, study_id = 595L)",
        call. = FALSE
      )
      study_id <- "unknown"
    }
  }
  dataset_id <- paste0("biotime:", study_id)

  # -- read CSV ------------------------------------------------------------------
  if (verbose) message("Reading: ", local_path)

  raw <- tryCatch(
    utils::read.csv(local_path, stringsAsFactors = FALSE, check.names = FALSE),
    error = function(e) stop("Failed to read CSV: ", conditionMessage(e),
                             call. = FALSE)
  )

  if (verbose) message(sprintf("  %d rows x %d columns", nrow(raw), ncol(raw)))

  # -- check for required columns ------------------------------------------------
  required <- c("valid_name", "LATITUDE", "LONGITUDE", "YEAR", "ABUNDANCE")
  missing  <- setdiff(required, names(raw))
  if (length(missing) > 0L) {
    stop(
      "BioTime CSV is missing expected columns: ",
      paste(missing, collapse = ", "), "\n",
      "Columns found: ", paste(names(raw), collapse = ", "), "\n",
      "Ensure you downloaded a per-study data file from BioTime\n",
      "(not a metadata or summary file).",
      call. = FALSE
    )
  }

  # -- rename to DwC -------------------------------------------------------------
  col_map <- c(
    valid_name  = "scientificName",
    LATITUDE    = "decimalLatitude",
    LONGITUDE   = "decimalLongitude",
    ABUNDANCE   = "organismQuantity",
    YEAR        = "year",
    MONTH       = "month",
    DAY         = "day",
    SAMPLE_DESC = "eventID",
    BIOMAS      = "biotime_biomass"   # note: BioTime source spells it BIOMAS
  )

  # Only rename columns that are actually present in this file
  present_map <- col_map[names(col_map) %in% names(raw)]
  names(raw)[match(names(present_map), names(raw))] <- present_map

  # -- coerce types --------------------------------------------------------------
  raw$decimalLatitude  <- suppressWarnings(as.numeric(raw$decimalLatitude))
  raw$decimalLongitude <- suppressWarnings(as.numeric(raw$decimalLongitude))
  raw$organismQuantity <- suppressWarnings(as.numeric(raw$organismQuantity))
  raw$year             <- suppressWarnings(as.integer(raw$year))
  if ("month"          %in% names(raw))
    raw$month          <- suppressWarnings(as.integer(raw$month))
  if ("day"            %in% names(raw))
    raw$day            <- suppressWarnings(as.integer(raw$day))
  if ("biotime_biomass" %in% names(raw))
    raw$biotime_biomass <- suppressWarnings(as.numeric(raw$biotime_biomass))

  # -- derived DwC columns -------------------------------------------------------
  biomass_vals <- if ("biotime_biomass" %in% names(raw)) raw$biotime_biomass else NA_real_

  raw$occurrenceStatus     <- ifelse(
    (!is.na(raw$organismQuantity) & raw$organismQuantity > 0) |
      (!is.na(biomass_vals) & biomass_vals > 0),
    "present", "absent"
  )
  raw$organismQuantityType <- "abundance"
  raw$basisOfRecord        <- "HumanObservation"
  raw$datasetID            <- dataset_id

  # Ensure biotime_biomass column exists even when BIOMAS was absent in source
  if (!"biotime_biomass" %in% names(raw)) raw$biotime_biomass <- NA_real_

  # -- drop rows missing coordinates ---------------------------------------------
  has_coords  <- !is.na(raw$decimalLatitude) & !is.na(raw$decimalLongitude)
  n_no_coords <- sum(!has_coords)
  if (n_no_coords > 0L) {
    if (verbose) message(sprintf(
      "  Dropping %d row(s) with missing coordinates.", n_no_coords
    ))
    raw <- raw[has_coords, , drop = FALSE]
  }

  # -- report --------------------------------------------------------------------
  if (verbose) {
    n_present <- sum(raw$occurrenceStatus == "present")
    n_absent  <- sum(raw$occurrenceStatus == "absent")
    n_taxa    <- length(unique(raw$scientificName))
    message(sprintf(
      "  %d records: %d present, %d absent | %d taxa | datasetID = \"%s\"",
      nrow(raw), n_present, n_absent, n_taxa, dataset_id
    ))
  }

  # --- Add bibliographic citation ----------------------------------------------
  raw$bibliographicCitation <- sprintf(
    "BioTime: Study %s. https://biotime.st-andrews.ac.uk",
    as.character(study_id)
  )

  tibble::as_tibble(raw)
}
