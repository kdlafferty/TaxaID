utils::globalVariables(c(
  ".classify_entity", ".attempt_dwc_join", ".do_entity_join", ".finalize_entity",
  ".extract_eml_sites", ".find_site_code_column"
))

# ==============================================================================
# dataone_standardize.R
# TaxaExpect -- DataONE / EDI dataset download and standardization
#
# Exported functions:
#   fetch_dataone_occurrences()     Full pipeline: EML -> download -> DWC -> bbox
#
# Internal helpers (all @noRd):
#   .default_dwc_map                Default regex -> DWC column map (data.frame)
#   .parse_eml_metadata()           Fetch and parse EML; return entity list
#   .map_columns_to_dwc()           Fuzzy-match raw column names to DWC terms
#   .report_dwc_mapping()           Print mapping summary (debug aid)
#   .download_data_table()          HTTP fetch + delim detection + read
#   .standardize_to_dwc()           Rename, type-coerce, construct eventDate
#   .filter_to_bbox_df()            Keep records within bounding box
#   .load_gbif_hashes()             Build hash set from GBIF snapshot for dedup
#   .deduplicate_against_gbif()     Remove records matching a GBIF hash set
#   .attempt_odm_join()             Join ODM observation+location+taxon tables
#   .process_one_dataset()          Single-dataset pipeline (EML -> tidy tibble)
#
# Dependencies (all in TaxaExpect Imports unless noted):
#   httr2, xml2 (*add to DESCRIPTION Imports*), dplyr, tibble, stringr, readr
#
# Pipeline position:
#   candidates <- search_dataone(bbox)              # discover datasets
#   occ        <- fetch_dataone_occurrences(        # download + standardize
#                   candidates$id, bbox)
#   all_occ    <- combine_occurrence_sources(       # merge with GBIF
#                   gbif_occ, supplemental = occ)
# ==============================================================================


# -- Default Darwin Core column mapping ----------------------------------------
#
# Regex patterns matched case-insensitively against raw column names.
# First match wins. Extend at call time via the `extra_dwc_map` argument.

.default_dwc_map <- data.frame(
  stringsAsFactors = FALSE,
  pattern  = c(
    "decimal.?lat|^lat$|^lat_dd|^latitude$",
    "decimal.?lon|^lon$|^lon_dd|^long$|^longitude$",
    "coord.*uncert|location.*acc",
    "^scientific.?name$|scientific.?name[^i]|^taxon.?name$",
    "^species$|species[_.]name|sp\\.?$|spec.?epithet",
    "^genus$|genus[_.]name",
    "family$",
    "common.?name",
    "date$|event.?date|obs.*date|sample.*date|collect.*date",
    "^year$",
    "^month$",
    "^day$",
    "count$|abundance|n_ind|num.*ind|total.*count",
    "observer|recorder|collector",
    "site$|station$|location.?name|plot$|transect$",
    "habitat|veg.*type|substrate",
    "depth$|depth.*m$",
    "elevation|elev.*m",
    "basis|record.?type|obs.?type",
    "institution|org$",
    "dataset$|source$",
    "occurrence.*id|^occid$"
  ),
  dwc_term = c(
    "decimalLatitude",
    "decimalLongitude",
    "coordinateUncertaintyInMeters",
    "scientificName",
    "specificEpithet",
    "genus",
    "family",
    "vernacularName",
    "eventDate",
    "year",
    "month",
    "day",
    "individualCount",
    "recordedBy",
    "locality",
    "habitat",
    "minimumDepthInMeters",
    "minimumElevationInMeters",
    "basisOfRecord",
    "institutionCode",
    "datasetName",
    "occurrenceID"
  )
)


# ==============================================================================
# Exported: fetch_dataone_occurrences
# ==============================================================================

#' Download and Standardize Occurrence Records from DataONE / EDI
#'
#' Given a vector of EDI PASTA dataset identifiers (from
#' \code{\link{search_dataone}}), fetches and parses the EML metadata for each
#' dataset, downloads data tables that contain coordinate and taxon columns,
#' standardizes column names to Darwin Core, filters to the supplied bounding
#' box, and optionally deduplicates against a GBIF occurrence snapshot. Returns
#' a single tibble compatible with \code{\link{stack_occurrences}}.
#'
#' @param dataset_ids Character vector. One or more PASTA package identifiers,
#'   as returned in the \code{id} column of \code{\link{search_dataone}},
#'   e.g. \code{c("knb-lter-sbc.17.18", "knb-lter-sbc.50.9")}.
#' @param bbox A named list with elements \code{west}, \code{east},
#'   \code{south}, \code{north} (decimal degrees). Records outside this box
#'   are removed. Example:
#'   \code{list(west = -121.0, east = -118.5, south = 33.5, north = 35.0)}.
#' @param gbif_snapshot_path Character or \code{NULL}. Path to a GBIF
#'   occurrence download in tab-separated format. When provided, records whose
#'   combination of \code{scientificName}, \code{eventDate}, and rounded
#'   coordinates (3 d.p.) match a GBIF record are removed. \code{NULL}
#'   (default) skips deduplication.
#' @param extra_dwc_map A \code{data.frame} with columns \code{pattern} and
#'   \code{dwc_term}, prepended before the default map so dataset-specific
#'   patterns take priority. \code{NULL} (default) uses the built-in map only.
#' @param timeout Integer. HTTP download timeout in seconds for individual data
#'   table downloads. Default \code{120L}. Increase to \code{600L} or more for
#'   datasets with very large entity files (e.g. multi-hundred-MB event tables).
#' @param site_lookup A \code{data.frame} with columns \code{site_code},
#'   \code{decimalLatitude}, and \code{decimalLongitude}, or \code{NULL}
#'   (default). When supplied, overrides EML \code{geographicCoverage} point
#'   sites for multi-site coordinate injection. Use this when EML site codes do
#'   not match the site labels in the data (e.g. \code{"BC"} in EML vs
#'   \code{"BC I"}, \code{"BC II"} in data). Applies to all datasets in the
#'   current call; for per-dataset overrides call \code{fetch_dataone_occurrences}
#'   separately for each dataset.
#' @param odm_variable Character. The \code{variable_name} value to filter on
#'   when joining LTER Observation Data Model (ODM) tables. Default
#'   \code{"DENSITY"}. Other common values: \code{"PERCENT_COVER"},
#'   \code{"DRY_GM2"}, \code{"AFDM"}. Set to \code{NULL} to keep all variable
#'   rows (produces long-format output with one row per taxon x location x
#'   date x variable).
#' @param verbose Logical. Print per-dataset and per-entity progress messages.
#'   Default \code{TRUE}.
#'
#' @return A tibble with standardized Darwin Core columns, or \code{NULL}
#'   invisibly if no records survive all filters. Column order:
#'   \code{occurrenceID}, \code{datasetID}, \code{datasetName},
#'   \code{institutionCode}, \code{basisOfRecord}, \code{eventDate},
#'   \code{year}, \code{month}, \code{day}, \code{decimalLatitude},
#'   \code{decimalLongitude}, \code{coordinateUncertaintyInMeters},
#'   \code{scientificName}, \code{genus}, \code{family},
#'   \code{specificEpithet}, \code{vernacularName}, \code{individualCount},
#'   \code{recordedBy}, \code{locality}, \code{habitat};
#'   followed by any unmapped source columns.
#'
#' @details
#' \strong{EML parsing:} EML is fetched from the PASTA metadata endpoint.
#' Entity data URLs are extracted from \code{<dataTable>} and
#' \code{<otherEntity>} nodes. Only entities whose EML attribute names map to
#' both a latitude and longitude column are downloaded. Namespaces are stripped
#' before XPath queries to handle both EML 2.1 and 2.2.
#'
#' \strong{Column mapping:} Raw column names are matched case-insensitively
#' against the \code{pattern} column using first-match-wins regex. Unmapped
#' columns are retained at the end of the tibble. Use \code{extra_dwc_map}
#' to handle non-standard names without modifying package internals.
#'
#' \strong{Date standardization:} Existing \code{eventDate} columns are
#' normalized to ISO 8601 (\code{YYYY-MM-DD}). If absent but
#' \code{year}/\code{month}/\code{day} are present, \code{eventDate} is
#' constructed from them.
#'
#' \strong{Deduplication hash key:}
#' \code{tolower(scientificName)|eventDate|round(lat,3)|round(lon,3)}.
#'
#' @seealso \code{\link{search_dataone}}, \code{\link{fetch_dataone_eml}},
#'   \code{\link{stack_occurrences}}
#'
#' @importFrom httr2 request req_timeout req_perform resp_body_string
#' @importFrom xml2 read_xml xml_ns_strip xml_find_all xml_find_first xml_text
#' @importFrom dplyr mutate rename select filter bind_rows any_of all_of
#'   coalesce n_distinct left_join
#' @importFrom stats setNames
#' @importFrom tibble as_tibble
#' @importFrom cli cli_progress_bar cli_progress_update cli_progress_done
#' @importFrom stringr str_to_lower str_trim str_pad str_count
#' @importFrom readr read_delim read_tsv
#' @export
#'
#' @examples
#' \dontrun{
#' bbox <- list(west = -121.0, east = -118.5, south = 33.5, north = 35.0)
#' candidates <- search_dataone(bbox, scope = "knb-lter-sbc")
#'
#' # Single dataset smoke test
#' occ <- fetch_dataone_occurrences(candidates$id[1], bbox)
#'
#' # Full run without GBIF dedup
#' occ <- fetch_dataone_occurrences(candidates$id, bbox)
#'
#' # With GBIF deduplication
#' occ <- fetch_dataone_occurrences(
#'   candidates$id, bbox,
#'   gbif_snapshot_path = "~/data/gbif_sbchannel.csv"
#' )
#'
#' # Fix a non-standard column name
#' extra <- data.frame(
#'   pattern  = "spp_name",
#'   dwc_term = "scientificName",
#'   stringsAsFactors = FALSE
#' )
#' occ <- fetch_dataone_occurrences(candidates$id[1], bbox,
#'                                  extra_dwc_map = extra)
#' }
fetch_dataone_occurrences <- function(dataset_ids,
                                      bbox,
                                      gbif_snapshot_path = NULL,
                                      extra_dwc_map      = NULL,
                                      timeout            = 120L,
                                      site_lookup        = NULL,
                                      odm_variable       = "DENSITY",
                                      verbose            = TRUE) {

  # -- Input validation -------------------------------------------------------
  if (!is.character(dataset_ids) || length(dataset_ids) == 0L) {
    stop("fetch_dataone_occurrences: 'dataset_ids' must be a non-empty ",
         "character vector.")
  }
  # Coerce c(west, east, south, north) vector to named list
  if (is.numeric(bbox) && length(bbox) == 4L && is.null(names(bbox))) {
    bbox <- list(west = bbox[1], east = bbox[2],
                 south = bbox[3], north = bbox[4])
  }
  if (!is.list(bbox) ||
      !all(c("west", "east", "south", "north") %in% names(bbox))) {
    stop("fetch_dataone_occurrences: 'bbox' must be a named list with ",
         "elements west, east, south, and north (decimal degrees).")
  }
  if (!is.null(extra_dwc_map)) {
    if (!is.data.frame(extra_dwc_map) ||
        !all(c("pattern", "dwc_term") %in% names(extra_dwc_map))) {
      stop("fetch_dataone_occurrences: 'extra_dwc_map' must be a data.frame ",
           "with columns 'pattern' and 'dwc_term'.")
    }
  }
  if (!is.null(site_lookup)) {
    if (!is.data.frame(site_lookup) ||
        !all(c("site_code", "decimalLatitude", "decimalLongitude") %in%
             names(site_lookup))) {
      stop("fetch_dataone_occurrences: 'site_lookup' must be a data.frame ",
           "with columns 'site_code', 'decimalLatitude', and 'decimalLongitude'.")
    }
  }

  dwc_map <- if (!is.null(extra_dwc_map)) {
    rbind(extra_dwc_map, .default_dwc_map)
  } else {
    .default_dwc_map
  }

  gbif_hashes <- .load_gbif_hashes(gbif_snapshot_path, verbose = verbose)

  pb <- cli::cli_progress_bar("Fetching DataONE datasets",
                               total = length(dataset_ids))
  results <- lapply(dataset_ids, function(id) {
    cli::cli_progress_update(id = pb)
    tryCatch(
      .process_one_dataset(id, bbox, dwc_map, gbif_hashes, verbose,
                            timeout = timeout, site_lookup = site_lookup,
                            odm_variable = odm_variable),
      error = function(e) {
        message(sprintf("fetch_dataone_occurrences: ERROR on %s -- %s",
                        id, conditionMessage(e)))
        NULL
      }
    )
  })
  cli::cli_progress_done(id = pb)

  results <- Filter(Negate(is.null), results)

  if (length(results) == 0L) {
    if (verbose) message("fetch_dataone_occurrences: no records returned.")
    return(invisible(NULL))
  }

  all_results <- dplyr::bind_rows(results)

  # -- Canonical DWC column order ---------------------------------------------
  dwc_cols <- c(
    "occurrenceID", "datasetID", "datasetName", "institutionCode",
    "basisOfRecord", "eventDate", "year", "month", "day",
    "decimalLatitude", "decimalLongitude", "coordinateUncertaintyInMeters",
    "scientificName", "genus", "family", "specificEpithet", "vernacularName",
    "individualCount", "recordedBy", "locality", "habitat"
  )
  present_dwc <- intersect(dwc_cols, names(all_results))
  extra_cols  <- setdiff(names(all_results), dwc_cols)
  all_results <- dplyr::select(all_results,
                               dplyr::all_of(present_dwc),
                               dplyr::all_of(extra_cols))

  if (verbose) {
    message("\nfetch_dataone_occurrences: summary --------------------------")
    message(sprintf("  Total records      : %d", nrow(all_results)))
    message(sprintf("  Datasets processed : %d",
                    dplyr::n_distinct(all_results$datasetID, na.rm = TRUE)))
    if ("scientificName" %in% names(all_results)) {
      message(sprintf("  Unique taxa        : %d",
                      dplyr::n_distinct(all_results$scientificName,
                                        na.rm = TRUE)))
    }
  }

  all_results
}


# ==============================================================================
# Internal helpers
# ==============================================================================

#' Fetch and parse EML for a single PASTA dataset ID
#'
#' Fetches EML from the PASTA metadata endpoint (pasta.lternet.edu), then
#' parses entity names, data URLs, and attribute names. Returns a metadata
#' list, or NULL with a message on HTTP or parse failure.
#'
#' @noRd
.parse_eml_metadata <- function(dataset_id) {

  eml_url <- .pasta_eml_url(dataset_id)
  message("  Fetching EML: ", str_trunc_safe(dataset_id, 80))

  resp <- tryCatch(
    httr2::request(eml_url) |>
      httr2::req_timeout(30) |>
      httr2::req_perform(),
    error = function(e) {
      message("    HTTP error: ", conditionMessage(e))
      NULL
    }
  )
  if (is.null(resp)) return(NULL)

  eml <- tryCatch(
    xml2::read_xml(httr2::resp_body_string(resp)),
    error = function(e) {
      message("    XML parse error: ", conditionMessage(e))
      NULL
    }
  )
  if (is.null(eml)) return(NULL)

  # Strip namespaces so XPath works across EML 2.1.x and 2.2.x
  xml2::xml_ns_strip(eml)

  # -- Package-level metadata -----------------------------------------------
  title    <- xml_text_safe(xml2::xml_find_first(eml, ".//dataset/title"))
  creator  <- xml_text_safe(xml2::xml_find_first(
    eml, ".//creator/individualName/surName"))
  pub_date <- xml_text_safe(xml2::xml_find_first(eml, ".//pubDate"))
  abstract <- xml_text_safe(xml2::xml_find_first(eml, ".//abstract//para[1]"))
  if (!is.na(abstract)) abstract <- str_trunc_safe(abstract, 200)

  # -- Data entities --------------------------------------------------------
  entity_nodes <- xml2::xml_find_all(eml, ".//dataTable | .//otherEntity")

  entities <- lapply(entity_nodes, function(node) {
    entity_name <- xml_text_safe(xml2::xml_find_first(node, ".//entityName"))
    obj_name    <- xml_text_safe(xml2::xml_find_first(node, ".//objectName"))
    url_node    <- xml2::xml_find_first(node, ".//online/url")
    data_url    <- if (!inherits(url_node, "xml_missing") &&
                       length(url_node) > 0L) {
      xml_text_safe(url_node)
    } else {
      NA_character_
    }

    # Iterate individual <attribute> nodes to get one row per attribute
    attr_nodes <- xml2::xml_find_all(node, ".//attribute")
    if (length(attr_nodes) > 0L) {
      attrs <- do.call(rbind, lapply(attr_nodes, function(a) {
        data.frame(
          stringsAsFactors    = FALSE,
          attributeName       = xml_text_safe(
            xml2::xml_find_first(a, ".//attributeName")),
          attributeDefinition = xml_text_safe(
            xml2::xml_find_first(a, ".//attributeDefinition")),
          storageType         = xml_text_safe(
            xml2::xml_find_first(a, ".//storageType"))
        )
      }))
    } else {
      attrs <- data.frame(
        stringsAsFactors    = FALSE,
        attributeName       = character(0),
        attributeDefinition = character(0),
        storageType         = character(0)
      )
    }

    list(
      entity_name = entity_name,
      obj_name    = obj_name,
      data_url    = data_url,
      attributes  = attrs
    )
  })

  # -- Geographic coverage -> fixed-site lookup ------------------------------
  # Extracts named point sites for datasets where coordinates are in EML
  # metadata rather than in data columns (e.g. single-site or multi-site
  # LTER datasets with a site_code column in the data).
  sites <- .extract_eml_sites(eml)

  list(
    id       = dataset_id,
    title    = title,
    creator  = creator,
    pub_date = pub_date,
    abstract = abstract,
    entities = entities,
    sites    = sites
  )
}


#' Map raw column names to Darwin Core terms
#'
#' Returns a named character vector: names = raw column names,
#' values = DWC term or NA_character_. First pattern match wins.
#'
#' @noRd
.map_columns_to_dwc <- function(col_names, dwc_map) {
  col_lower <- stringr::str_to_lower(col_names)
  mapping   <- stats::setNames(rep(NA_character_, length(col_names)), col_names)

  for (i in seq_len(nrow(dwc_map))) {
    unmatched <- is.na(mapping)
    if (!any(unmatched)) break
    hits <- grepl(dwc_map$pattern[i], col_lower[unmatched],
                  ignore.case = TRUE, perl = TRUE)
    mapping[unmatched][hits] <- dwc_map$dwc_term[i]
  }

  mapping
}


#' Print column mapping summary (debug aid)
#'
#' @noRd
.report_dwc_mapping <- function(col_names, mapping, entity_name = "") {
  message("  Column mapping",
          if (nzchar(entity_name)) paste0(" [", entity_name, "]"))
  df       <- data.frame(raw = col_names, dwc = mapping,
                         stringsAsFactors = FALSE)
  mapped   <- df[!is.na(df$dwc), ]
  unmapped <- df[is.na(df$dwc), ]
  if (nrow(mapped) > 0L) {
    message(sprintf("    Mapped (%d): %s", nrow(mapped),
                    paste(paste0(mapped$raw, "->", mapped$dwc), collapse = ", ")))
  }
  if (nrow(unmapped) > 0L) {
    message(sprintf("    Unmapped (%d): %s", nrow(unmapped),
                    paste(unmapped$raw, collapse = ", ")))
  }
}


#' Download a data table from an entity URL
#'
#' Detects CSV vs TSV from first-line delimiter counts.
#' Returns NULL with a message on HTTP or parse failure.
#'
#' @noRd
.download_data_table <- function(data_url, timeout = 120L) {
  if (is.na(data_url) || !nzchar(data_url)) return(NULL)

  message("    Downloading: ", str_trunc_safe(data_url, 80))

  resp <- tryCatch(
    httr2::request(data_url) |>
      httr2::req_timeout(timeout) |>
      httr2::req_perform(),
    error = function(e) {
      message("    Download error: ", conditionMessage(e))
      NULL
    }
  )
  if (is.null(resp)) return(NULL)

  raw_text   <- httr2::resp_body_string(resp)
  first_line <- strsplit(raw_text, "\n")[[1L]][1L]
  if (is.na(first_line) || !nzchar(stringr::str_trim(first_line))) {
    message("    Could not read first line -- file may be binary. Skipping.")
    return(NULL)
  }
  n_tab      <- stringr::str_count(first_line, "\t")
  n_comma    <- stringr::str_count(first_line, ",")
  delim      <- if (isTRUE(n_tab > n_comma)) "\t" else ","

  tryCatch(
    readr::read_delim(raw_text, delim = delim,
                      show_col_types = FALSE, name_repair = "minimal"),
    error = function(e) {
      message("    Parse error: ", conditionMessage(e))
      NULL
    }
  )
}


#' Rename and type-coerce a raw data table to Darwin Core
#'
#' col_mapping: names = raw column names, values = DWC terms (or NA).
#' tapply gives dwc_to_raw (names = DWC terms, values = raw names).
#' dplyr::rename(any_of(dwc_to_raw)) renames old_name -> new_name correctly.
#'
#' @noRd
.standardize_to_dwc <- function(raw_df, col_mapping, dataset_meta) {

  mapped_cols <- col_mapping[!is.na(col_mapping)]
  dwc_to_raw  <- tapply(names(mapped_cols), mapped_cols, function(x) x[1L])

  std_df <- raw_df |>
    dplyr::rename(dplyr::any_of(dwc_to_raw))

  # Construct scientificName from genus + specificEpithet when absent.
  # Handles datasets (e.g. SONGS UCSB) that split the name into two columns
  # rather than providing a single scientificName field.
  if (!"scientificName" %in% names(std_df)) {
    has_genus   <- "genus"           %in% names(std_df)
    has_epithet <- "specificEpithet" %in% names(std_df)
    if (has_genus && has_epithet) {
      g <- ifelse(is.na(std_df$genus),           "", std_df$genus)
      e <- ifelse(is.na(std_df$specificEpithet), "", std_df$specificEpithet)
      sn <- trimws(paste(g, e))
      std_df$scientificName <- ifelse(nzchar(sn), sn, NA_character_)
    } else if (has_genus) {
      std_df$scientificName <- std_df$genus
    }
  }

  # Coordinate coercion
  if ("decimalLatitude" %in% names(std_df)) {
    std_df$decimalLatitude <- suppressWarnings(as.numeric(std_df$decimalLatitude))
  }
  if ("decimalLongitude" %in% names(std_df)) {
    std_df$decimalLongitude <- suppressWarnings(as.numeric(std_df$decimalLongitude))
  }

  # Date standardization (no lubridate)
  if (!"eventDate" %in% names(std_df)) {
    has_ymd <- all(c("year", "month", "day") %in% names(std_df))
    has_ym  <- all(c("year", "month") %in% names(std_df))
    if (has_ymd) {
      std_df$eventDate <- as.character(suppressWarnings(
        as.Date(paste(as.integer(std_df$year),
                      as.integer(std_df$month),
                      as.integer(std_df$day), sep = "-"))
      ))
    } else if (has_ym) {
      std_df$eventDate <- paste0(
        std_df$year, "-",
        stringr::str_pad(as.character(std_df$month), 2, pad = "0")
      )
    }
  } else {
    std_df$eventDate <- .try_parse_date(std_df$eventDate)
  }

  # Required DWC fields
  if (!"basisOfRecord" %in% names(std_df)) {
    std_df$basisOfRecord <- "HumanObservation"
  }
  std_df$datasetName     <- dataset_meta$title
  std_df$datasetID       <- dataset_meta$id
  std_df$institutionCode <- dataset_meta$creator

  # Construct bibliographic citation from EML metadata
  cite_parts <- c(dataset_meta$creator, dataset_meta$pub_date, dataset_meta$title)
  cite_parts <- cite_parts[!is.na(cite_parts) & nzchar(cite_parts)]
  std_df$bibliographicCitation <- if (length(cite_parts) > 0L) {
    paste(cite_parts, collapse = ". ")
  } else {
    NA_character_
  }

  if (!"occurrenceID" %in% names(std_df)) {
    std_df$occurrenceID <- paste0(dataset_meta$id, "_row",
                                  seq_len(nrow(std_df)))
  }

  # Coerce unmapped extra columns to character to prevent type-conflict errors
  # in dplyr::bind_rows() when the same raw column name appears in multiple
  # datasets with different storage types (e.g. id <character> vs id <double>).
  dwc_canonical <- c(
    "occurrenceID", "datasetID", "datasetName", "institutionCode",
    "basisOfRecord", "eventDate", "year", "month", "day",
    "decimalLatitude", "decimalLongitude", "coordinateUncertaintyInMeters",
    "scientificName", "genus", "family", "specificEpithet", "vernacularName",
    "individualCount", "recordedBy", "locality", "habitat"
  )
  extra_cols <- setdiff(names(std_df), dwc_canonical)
  for (col in extra_cols) {
    std_df[[col]] <- as.character(std_df[[col]])
  }

  std_df
}


#' Parse dates from a character vector, trying common formats in order
#'
#' Falls back to the original string for any element that cannot be parsed.
#'
#' @noRd
.try_parse_date <- function(x) {
  formats <- c("%Y-%m-%d", "%Y/%m/%d", "%m/%d/%Y", "%d-%m-%Y",
               "%d/%m/%Y", "%Y%m%d", "%Y")
  result  <- rep(NA_character_, length(x))

  for (fmt in formats) {
    unparsed <- is.na(result)
    if (!any(unparsed)) break
    parsed <- suppressWarnings(as.Date(x[unparsed], format = fmt))
    filled <- !is.na(parsed)
    result[which(unparsed)[filled]] <- as.character(parsed[filled])
  }

  still_na          <- is.na(result)
  result[still_na]  <- as.character(x[still_na])
  result
}


#' Filter a data frame to records within the bounding box
#'
#' @noRd
.filter_to_bbox_df <- function(df, bbox) {
  if (!all(c("decimalLatitude", "decimalLongitude") %in% names(df))) {
    message("    WARNING: missing coordinate columns; cannot apply bbox filter.")
    return(df)
  }
  n_before <- nrow(df)
  out <- dplyr::filter(
    df,
    !is.na(.data$decimalLatitude),
    !is.na(.data$decimalLongitude),
    .data$decimalLatitude  >= bbox$south,
    .data$decimalLatitude  <= bbox$north,
    .data$decimalLongitude >= bbox$west,
    .data$decimalLongitude <= bbox$east
  )
  message(sprintf("    Bbox filter: %d \u2192 %d records", n_before, nrow(out)))
  out
}


#' Build deduplication hash set from a GBIF snapshot
#'
#' Hash key: tolower(scientificName) | eventDate | round(lat,3) | round(lon,3)
#' Returns NULL if no path provided or file not found.
#'
#' @noRd
.load_gbif_hashes <- function(gbif_path, verbose = TRUE) {
  if (is.null(gbif_path)) return(NULL)
  if (!file.exists(gbif_path)) {
    warning(sprintf(
      ".load_gbif_hashes: file not found: %s -- skipping deduplication.",
      gbif_path
    ), call. = FALSE)
    return(NULL)
  }
  if (verbose) message("Loading GBIF snapshot: ", gbif_path)

  gbif <- readr::read_tsv(gbif_path, show_col_types = FALSE, quote = "")

  name_col <- dplyr::coalesce(gbif$species, gbif$scientificName,
                               rep("", nrow(gbif)))
  date_col <- dplyr::coalesce(gbif$eventDate, rep("", nrow(gbif)))
  lat_col  <- dplyr::coalesce(gbif$decimalLatitude,  rep(0, nrow(gbif)))
  lon_col  <- dplyr::coalesce(gbif$decimalLongitude, rep(0, nrow(gbif)))

  hashes <- paste(tolower(stringr::str_trim(name_col)), date_col,
                  round(lat_col, 3), round(lon_col, 3), sep = "|")

  if (verbose) {
    message(sprintf("  %d unique hashes from %d GBIF records",
                    length(unique(hashes)), nrow(gbif)))
  }
  unique(hashes)
}


#' Remove records matching a GBIF hash set
#'
#' @noRd
.deduplicate_against_gbif <- function(df, gbif_hashes) {
  if (is.null(gbif_hashes)) return(df)

  name_col <- dplyr::coalesce(df$scientificName, rep("", nrow(df)))
  date_col <- dplyr::coalesce(df$eventDate,      rep("", nrow(df)))
  lat_col  <- dplyr::coalesce(df$decimalLatitude,  rep(0, nrow(df)))
  lon_col  <- dplyr::coalesce(df$decimalLongitude, rep(0, nrow(df)))

  record_hashes <- paste(tolower(stringr::str_trim(name_col)), date_col,
                         round(lat_col, 3), round(lon_col, 3), sep = "|")

  n_before <- nrow(df)
  out      <- df[!record_hashes %in% gbif_hashes, ]
  message(sprintf("    GBIF dedup: %d \u2192 %d records (%d removed)",
                  n_before, nrow(out), n_before - nrow(out)))
  out
}


# -- EML fixed-site coordinate helpers -----------------------------------------

#' Extract named point sites from EML geographicCoverage nodes
#'
#' Parses every <geographicCoverage> block. Extracts the site code from the
#' description as the substring before the first ':' or whitespace. Returns a
#' data frame with columns site_code, decimalLatitude, decimalLongitude. Rows
#' where coordinates are NA or where W != E (i.e. true bounding boxes rather
#' than points) are dropped -- only point sites are returned.
#'
#' @noRd
.extract_eml_sites <- function(eml) {
  gc_nodes <- xml2::xml_find_all(eml, ".//geographicCoverage")
  if (length(gc_nodes) == 0L) {
    return(data.frame(site_code        = character(0),
                      decimalLatitude  = numeric(0),
                      decimalLongitude = numeric(0),
                      stringsAsFactors = FALSE))
  }

  rows <- lapply(gc_nodes, function(g) {
    desc  <- xml_text_safe(xml2::xml_find_first(g, ".//geographicDescription"))
    west  <- suppressWarnings(as.numeric(xml_text_safe(
      xml2::xml_find_first(g, ".//westBoundingCoordinate"))))
    east  <- suppressWarnings(as.numeric(xml_text_safe(
      xml2::xml_find_first(g, ".//eastBoundingCoordinate"))))
    south <- suppressWarnings(as.numeric(xml_text_safe(
      xml2::xml_find_first(g, ".//southBoundingCoordinate"))))
    north <- suppressWarnings(as.numeric(xml_text_safe(
      xml2::xml_find_first(g, ".//northBoundingCoordinate"))))

    # Only keep point sites (W == E and S == N) with valid coordinates
    if (is.na(west) || is.na(east) || is.na(south) || is.na(north)) return(NULL)
    if (!isTRUE(all.equal(west, east)) || !isTRUE(all.equal(south, north))) return(NULL)

    # Extract site code: everything before the first ':' or whitespace
    code <- if (!is.na(desc) && nzchar(desc)) {
      trimws(sub("^([^:\\s]+)[:\\s].*$", "\\1", desc, perl = TRUE))
    } else {
      NA_character_
    }

    data.frame(site_code        = code,
               decimalLatitude  = south,
               decimalLongitude = west,
               stringsAsFactors = FALSE)
  })

  rows <- Filter(Negate(is.null), rows)
  if (length(rows) == 0L) {
    return(data.frame(site_code        = character(0),
                      decimalLatitude  = numeric(0),
                      decimalLongitude = numeric(0),
                      stringsAsFactors = FALSE))
  }
  result <- do.call(rbind, rows)
  result[!is.na(result$site_code) & nzchar(result$site_code), ]
}


#' Find the column in df whose values best overlap with a set of site codes
#'
#' Returns the name of the column with the highest overlap fraction, or
#' NULL if no column exceeds min_overlap_frac (default 0.5).
#'
#' @noRd
.find_site_code_column <- function(df, site_codes, min_overlap_frac = 0.5) {
  if (length(site_codes) == 0L || ncol(df) == 0L) return(NULL)
  site_codes_upper <- toupper(site_codes)

  best_col  <- NULL
  best_frac <- min_overlap_frac

  for (col in names(df)) {
    vals <- toupper(as.character(df[[col]]))
    frac <- length(intersect(unique(vals), site_codes_upper)) /
            length(site_codes_upper)
    if (frac > best_frac) {
      best_frac <- frac
      best_col  <- col
    }
  }
  best_col
}


# -- DwC Archive join helpers ---------------------------------------------------

#' Classify a DWC column mapping as complete / spatial_only / species_only / unknown
#'
#' Returns one of: "complete" (has coords + species), "spatial_only" (coords only),
#' "species_only" (species only), "no_coords_no_species", or "unknown" (empty mapping).
#'
#' @noRd
.classify_entity <- function(mapping) {
  if (length(mapping) == 0L) return("unknown")
  has_lat     <- any(mapping == "decimalLatitude",  na.rm = TRUE)
  has_lon     <- any(mapping == "decimalLongitude", na.rm = TRUE)
  has_species <- any(mapping %in% c("scientificName", "specificEpithet", "genus"),
                     na.rm = TRUE)
  if (isTRUE(has_lat && has_lon && has_species)) return("complete")
  if (isTRUE(has_lat && has_lon))               return("spatial_only")
  if (isTRUE(has_species))                      return("species_only")
  "no_coords_no_species"
}


#' Attempt to join a spatial-only and a species-only entity data frame
#'
#' Builds a set of candidate join key pairs, then selects the best by the
#' cardinality of the spatial-side key (unique values / nrow). A high-cardinality
#' spatial key (close to 1.0) is the true primary key and avoids many-to-many
#' explosions caused by low-cardinality identifier columns (e.g. a dataset-level
#' eventID repeated across all rows).
#'
#' Candidate strategies:
#'   1. shared "id" column in both tables (id <-> id)
#'   2. spatial$id <-> species$eventID  (DwC Archive asymmetric standard)
#'   3. shared eventID column in both tables (eventID <-> eventID)
#'   4. any other shared event.*id-pattern column across both tables
#'
#' Only candidates with at least one overlapping value are kept.
#' Returns NULL with a message if no candidate survives.
#'
#' @noRd
.attempt_dwc_join <- function(spatial_df, species_df, verbose) {
  s_lower <- tolower(names(spatial_df))
  o_lower <- tolower(names(species_df))

  n_overlap <- function(a, b) {
    length(intersect(as.character(a), as.character(b)))
  }
  cardinality <- function(col) {
    length(unique(col)) / max(length(col), 1L)
  }

  candidates <- list()

  # Strategy 1: shared "id" column (both tables have a column literally named "id")
  if ("id" %in% s_lower && "id" %in% o_lower) {
    s_key <- names(spatial_df)[s_lower == "id"][1L]
    o_key <- names(species_df)[o_lower == "id"][1L]
    n     <- n_overlap(spatial_df[[s_key]], species_df[[o_key]])
    if (n > 0L) candidates[["shared_id"]] <- list(
      s_key = s_key, o_key = o_key, n = n,
      card  = cardinality(spatial_df[[s_key]]),
      label = "shared id"
    )
  }

  # Strategy 2: DwC Archive asymmetric -- spatial$id <-> species$eventID
  if ("id" %in% s_lower && "eventid" %in% o_lower) {
    s_key <- names(spatial_df)[s_lower == "id"][1L]
    o_key <- names(species_df)[o_lower == "eventid"][1L]
    n     <- n_overlap(spatial_df[[s_key]], species_df[[o_key]])
    if (n > 0L) candidates[["asymmetric"]] <- list(
      s_key = s_key, o_key = o_key, n = n,
      card  = cardinality(spatial_df[[s_key]]),
      label = "event$id <-> occ$eventID"
    )
  }

  # Strategy 3: shared eventID column
  if ("eventid" %in% s_lower && "eventid" %in% o_lower) {
    s_key <- names(spatial_df)[s_lower == "eventid"][1L]
    o_key <- names(species_df)[o_lower == "eventid"][1L]
    n     <- n_overlap(spatial_df[[s_key]], species_df[[o_key]])
    if (n > 0L) candidates[["shared_eventid"]] <- list(
      s_key = s_key, o_key = o_key, n = n,
      card  = cardinality(spatial_df[[s_key]]),
      label = "shared eventID"
    )
  }

  # Strategy 4: any other shared event.*id-pattern column
  s_eid <- names(spatial_df)[grepl("event.?id", s_lower, perl = TRUE)]
  o_eid <- names(species_df)[grepl("event.?id", o_lower, perl = TRUE)]
  for (k in intersect(tolower(s_eid), tolower(o_eid))) {
    if (k %in% c("id", "eventid")) next
    s_key <- names(spatial_df)[s_lower == k][1L]
    o_key <- names(species_df)[o_lower == k][1L]
    n     <- n_overlap(spatial_df[[s_key]], species_df[[o_key]])
    if (n > 0L) candidates[[paste0("shared_", k)]] <- list(
      s_key = s_key, o_key = o_key, n = n,
      card  = cardinality(spatial_df[[s_key]]),
      label = paste0("shared ", k)
    )
  }

  if (length(candidates) == 0L) {
    if (verbose) message("    DwC join: no key with overlapping values found \u2014 skipping.")
    return(NULL)
  }

  # Select candidate whose spatial-side key has highest cardinality.
  # High cardinality (close to 1.0) = true primary key = avoids row explosion.
  best <- candidates[[which.max(vapply(candidates, `[[`, 0, "card"))]]

  if (verbose) {
    message(sprintf(
      "    DwC join (%s): %s <-> %s  [%d overlapping values, spatial cardinality %.2f]",
      best$label, best$s_key, best$o_key, best$n, best$card
    ))
  }
  .do_entity_join(spatial_df, species_df, best$s_key, best$o_key, verbose)
}


#' Execute the actual join, resolving column name conflicts
#'
#' Drops columns from species_df that already exist in spatial_df (except
#' the join key), then performs a left_join expanding events to occurrences.
#'
#' @noRd
.do_entity_join <- function(spatial_df, species_df, s_key, o_key, verbose) {
  # Drop columns from species_df that already exist in spatial_df,
  # except the join keys themselves (both s_key and o_key must be protected).
  overlap      <- setdiff(
    intersect(tolower(names(spatial_df)), tolower(names(species_df))),
    c(tolower(s_key), tolower(o_key))
  )
  species_df   <- species_df[, !tolower(names(species_df)) %in% overlap, drop = FALSE]

  merged <- tryCatch({
    spatial_df[[s_key]] <- as.character(spatial_df[[s_key]])
    species_df[[o_key]] <- as.character(species_df[[o_key]])
    dplyr::left_join(spatial_df, species_df,
                     by = stats::setNames(o_key, s_key))
  },
    error = function(e) {
      message("    Join error: ", conditionMessage(e))
      NULL
    }
  )
  if (!is.null(merged) && verbose) {
    message(sprintf("    Join result: %d rows \u00d7 %d cols",
                    nrow(merged), ncol(merged)))
  }
  merged
}


#' Standardize, bbox-filter, dedup, and return a tibble for one entity data frame
#'
#' Shared by both self-contained complete entities and DwC Archive join results.
#'
#' @noRd
.finalize_entity <- function(raw_df, mapping, meta, bbox, gbif_hashes, verbose) {
  std <- tryCatch(
    .standardize_to_dwc(raw_df, mapping, meta),
    error = function(e) {
      message("    Standardization error: ", conditionMessage(e))
      NULL
    }
  )
  if (is.null(std)) return(NULL)

  std <- .filter_to_bbox_df(std, bbox)
  if (nrow(std) == 0L) {
    if (verbose) message("    No records within bbox \u2014 skipping entity.")
    return(NULL)
  }

  std <- .deduplicate_against_gbif(std, gbif_hashes)
  if (nrow(std) == 0L) {
    if (verbose) message("    All records matched GBIF \u2014 skipping entity.")
    return(NULL)
  }

  tibble::as_tibble(std)
}


#' Full pipeline for a single PASTA dataset ID
#'
#' Returns a standardized tibble or NULL if no usable entities were found.
#' Automatically detects Darwin Core Archive structure (separate event and
#' occurrence tables joined on event$id <-> occurrence$eventID) and handles
#' it transparently alongside non-DwC datasets.
#'
#' @noRd
.process_one_dataset <- function(dataset_id, bbox, dwc_map,
                                 gbif_hashes, verbose, timeout = 120L,
                                 site_lookup = NULL, odm_variable = "DENSITY") {

  if (verbose) message(sprintf("\nProcessing: %s", str_trunc_safe(dataset_id, 70)))

  meta <- .parse_eml_metadata(dataset_id)
  if (is.null(meta)) return(NULL)

  if (verbose) {
    message(sprintf("  Title   : %s", str_trunc_safe(meta$title   %||% "(none)", 70)))
    message(sprintf("  Creator : %s", str_trunc_safe(meta$creator %||% "(none)", 50)))
    message(sprintf("  Entities: %d", length(meta$entities)))
  }

  # -- Pass 1: classify every entity from EML attribute names -----------------
  # No downloads yet -- just read the attribute list already in `meta`.
  entity_info <- lapply(meta$entities, function(entity) {
    ename     <- entity$entity_name %||% "(unnamed)"
    col_names <- entity$attributes$attributeName
    if (length(col_names) == 0L || all(is.na(col_names))) col_names <- character(0)
    mapping   <- if (length(col_names) > 0L) {
      .map_columns_to_dwc(col_names, dwc_map)
    } else {
      character(0)
    }
    list(
      entity   = entity,
      ename    = ename,
      mapping  = mapping,
      category = .classify_entity(mapping),
      raw      = NULL
    )
  })

  # -- Pass 2: download and (re)classify --------------------------------------
  # complete     -> self-contained; process normally in Pass 3
  # spatial_only -> coordinates but no species; hold for DwC join in Pass 4
  # species_only -> species but no coordinates; hold for DwC join in Pass 4
  # unknown      -> no EML attributes; download and classify from file headers
  # no_coords_no_species -> nothing useful; skip without downloading
  download_cats <- c("complete", "spatial_only", "species_only", "unknown")

  for (i in seq_along(entity_info)) {
    ei <- entity_info[[i]]

    if (!ei$category %in% download_cats) {
      if (verbose) {
        message(sprintf("\n  Entity: %s", str_trunc_safe(ei$ename, 60)))
        if (length(ei$mapping) > 0L) {
          .report_dwc_mapping(names(ei$mapping), ei$mapping, ei$ename)
        }
        message("    No lat/lon or species in EML \u2014 skipping.")
      }
      next
    }

    if (is.na(ei$entity$data_url)) {
      if (verbose) {
        message(sprintf("\n  Entity: %s\n    No data URL \u2014 skipping.",
                        str_trunc_safe(ei$ename, 60)))
      }
      entity_info[[i]]$category <- "skip"
      next
    }

    if (verbose) message(sprintf("\n  Entity: %s", str_trunc_safe(ei$ename, 60)))

    # Print EML-derived mapping before downloading (if we have one)
    if (length(ei$mapping) > 0L) {
      if (verbose) .report_dwc_mapping(names(ei$mapping), ei$mapping, ei$ename)
    } else {
      if (verbose) message("    No attribute names in EML \u2014 will map from file header.")
    }

    raw <- .download_data_table(ei$entity$data_url, timeout = timeout)
    if (is.null(raw) || nrow(raw) == 0L) {
      if (verbose) message("    Download returned no data \u2014 skipping.")
      entity_info[[i]]$category <- "skip"
      next
    }
    if (verbose) {
      message(sprintf("    Downloaded: %d rows \u00d7 %d cols", nrow(raw), ncol(raw)))
    }

    # Reclassify "unknown" entities once we have real column names
    if (ei$category == "unknown") {
      mapping  <- .map_columns_to_dwc(names(raw), dwc_map)
      if (verbose) .report_dwc_mapping(names(raw), mapping, ei$ename)
      entity_info[[i]]$mapping  <- mapping
      entity_info[[i]]$category <- .classify_entity(mapping)
    }

    entity_info[[i]]$raw <- raw
  }

  # -- Pass 3: process self-contained (complete) entities ---------------------
  entity_results <- list()

  for (ei in entity_info) {
    if (!isTRUE(ei$category == "complete") || is.null(ei$raw)) next
    result <- .finalize_entity(ei$raw, ei$mapping, meta, bbox, gbif_hashes, verbose)
    if (!is.null(result)) entity_results[[ei$ename]] <- result
  }

  # -- Pass 4: DwC Archive join ------------------------------------------------
  # Triggered only when the dataset has separate spatial-only and species-only
  # entities. All spatial x species pairs are tried; each successful join that
  # survives bbox filtering is kept.
  spatial_eis <- Filter(
    function(ei) isTRUE(ei$category == "spatial_only") && !is.null(ei$raw),
    entity_info
  )
  species_eis <- Filter(
    function(ei) isTRUE(ei$category == "species_only") && !is.null(ei$raw),
    entity_info
  )

  if (length(spatial_eis) > 0L && length(species_eis) > 0L) {
    if (verbose) {
      message(sprintf(
        "\n  DwC Archive detected: %d spatial + %d species entities \u2014 attempting join.",
        length(spatial_eis), length(species_eis)
      ))
    }
    for (sei in spatial_eis) {
      for (oei in species_eis) {
        merged <- .attempt_dwc_join(sei$raw, oei$raw, verbose)
        if (is.null(merged)) next
        merged_mapping <- .map_columns_to_dwc(names(merged), dwc_map)
        result <- .finalize_entity(merged, merged_mapping, meta,
                                   bbox, gbif_hashes, verbose)
        if (!is.null(result)) {
          jname <- paste0(sei$ename, " + ", oei$ename)
          entity_results[[jname]] <- result
        }
      }
    }
  }

  # -- Pass 5: EML coordinate injection ---------------------------------------
  # For species_only entities not already handled by Pass 4 (no spatial entity
  # to join with), try to inject coordinates from EML geographicCoverage or
  # from a user-supplied site_lookup table.
  # Handles two sub-cases:
  #   A. Single point site -> attach that lat/lon to every row.
  #   B. Multi-site with site code column -> join site lookup onto data.
  #
  # already_covered uses grepl so that join results stored as "event + occurrence"
  # correctly block the "occurrence" entity from re-running in Pass 5.
  # ODM table names (taxon, location, observation, taxon_ancillary, etc.) are
  # excluded -- they are handled by Pass 6 and should never receive site injection.
  odm_entity_patterns <- c("^observation$", "^location$", "^taxon$",
                            "observation_ancillary", "taxon_ancillary",
                            "dataset_summary", "variable_mapping")
  is_odm_entity <- function(ename) {
    any(grepl(paste(odm_entity_patterns, collapse = "|"),
              tolower(trimws(ename)), perl = TRUE))
  }

  already_covered <- names(entity_results) %||% character(0)
  unmatched_species <- Filter(
    function(ei) {
      isTRUE(ei$category == "species_only") &&
        !is.null(ei$raw) &&
        !is_odm_entity(ei$ename) &&
        !any(vapply(already_covered,
                    function(k) grepl(ei$ename, k, fixed = TRUE),
                    logical(1L)))
    },
    entity_info
  )

  # Resolve site table: user-supplied lookup takes priority over EML sites.
  # For EML sites, average coordinates for duplicate site codes (multiple depth
  # stations sharing a site name each become one centroid coordinate).
  sites_table <- if (!is.null(site_lookup)) {
    site_lookup
  } else if (nrow(meta$sites) > 0L) {
    if (anyDuplicated(meta$sites$site_code)) {
      dup_codes <- unique(meta$sites$site_code[duplicated(meta$sites$site_code)])
      if (verbose) {
        message(sprintf(
          "\n  EML site dedup: averaging coordinates for %d site code(s) with multiple entries: %s",
          length(dup_codes), paste(dup_codes, collapse = ", ")
        ))
      }
      # Average lat/lon per site_code using base R (no dplyr dependency here)
      codes  <- unique(meta$sites$site_code)
      avg_df <- do.call(rbind, lapply(codes, function(code) {
        rows <- meta$sites[meta$sites$site_code == code, ]
        data.frame(
          site_code        = code,
          decimalLatitude  = mean(rows$decimalLatitude,  na.rm = TRUE),
          decimalLongitude = mean(rows$decimalLongitude, na.rm = TRUE),
          stringsAsFactors = FALSE
        )
      }))
      avg_df
    } else {
      meta$sites
    }
  } else {
    NULL
  }

  if (length(unmatched_species) > 0L && !is.null(sites_table)) {
    if (verbose) {
      message(sprintf(
        "\n  EML site injection: %d site(s), %d unmatched species-only entity/entities.",
        nrow(sites_table), length(unmatched_species)
      ))
    }

    for (ei in unmatched_species) {
      if (verbose) message(sprintf("\n  Entity: %s", str_trunc_safe(ei$ename, 60)))

      injected <- if (nrow(sites_table) == 1L) {
        # Case A: single site -- attach coords to all rows
        if (verbose) {
          message(sprintf("    EML single-site injection: lat=%.4f lon=%.4f",
                          sites_table$decimalLatitude[1L],
                          sites_table$decimalLongitude[1L]))
        }
        ei$raw$decimalLatitude  <- sites_table$decimalLatitude[1L]
        ei$raw$decimalLongitude <- sites_table$decimalLongitude[1L]
        ei$raw

      } else {
        # Case B: multi-site -- find site code column and join
        site_col <- .find_site_code_column(ei$raw, sites_table$site_code)
        if (is.null(site_col)) {
          if (verbose) {
            # Identify the best candidate character column to show as an example
            char_cols <- names(ei$raw)[
              vapply(ei$raw, function(x) is.character(x) || is.factor(x), logical(1L))
            ]
            eml_codes_str <- paste(
              head(unique(sites_table$site_code), 6), collapse = ", "
            )
            data_example <- if (length(char_cols) > 0L) {
              sample_vals <- head(unique(as.character(ei$raw[[char_cols[1L]]])), 5)
              sprintf("column '%s' contains: %s",
                      char_cols[1L], paste(sample_vals, collapse = ", "))
            } else {
              "(no character columns found in data)"
            }
            message(sprintf(paste(
              "    WARNING: site code matching failed for entity '%s'.",
              "    Site table has %d site(s) with codes: %s",
              "    Best candidate %s",
              "    These do not overlap well enough for automatic joining (threshold 50%%).",
              "    To fix this, supply a site_lookup data.frame to fetch_dataone_occurrences():",
              "      site_lookup = data.frame(",
              "        site_code        = c(\"SiteA\", \"SiteB\", ...),",
              "        decimalLatitude  = c(...),",
              "        decimalLongitude = c(...)",
              "      )",
              "    Use the site labels as they appear in the DATA (not the EML).",
              "    Alternatively, download the data manually and join coordinates yourself.",
              sep = "\n    "
            ),
            str_trunc_safe(ei$ename, 40),
            nrow(sites_table),
            eml_codes_str,
            data_example
            ))
          }
          next
        }
        if (verbose) {
          message(sprintf("    EML multi-site injection: joining on '%s' (%d sites)",
                          site_col, nrow(sites_table)))
        }
        lookup <- sites_table
        lookup$site_code <- toupper(lookup$site_code)
        df_join <- ei$raw
        df_join[[site_col]] <- toupper(as.character(df_join[[site_col]]))
        dplyr::left_join(df_join, lookup,
                         by = stats::setNames("site_code", site_col))
      }

      if (is.null(injected)) next
      inj_mapping <- .map_columns_to_dwc(names(injected), dwc_map)
      result <- .finalize_entity(injected, inj_mapping, meta,
                                 bbox, gbif_hashes, verbose)
      if (!is.null(result)) entity_results[[ei$ename]] <- result
    }
  }

  # -- Pass 6: LTER Observation Data Model (ODM) join -------------------------
  # Triggered when the dataset has separate observation, location, and taxon
  # entities following the ecocomDP / ODM schema. Recognised by entity names
  # containing "observation", "location", and "taxon" (case-insensitive).
  # The observation table carries location_id and taxon_id foreign keys;
  # coordinates come from the location table and names from the taxon table.
  # Filtered to a single variable_name (default "DENSITY") to produce one row
  # per taxon x location x date.
  if (length(entity_results) == 0L) {
    odm_result <- .attempt_odm_join(entity_info, dwc_map, meta,
                                    bbox, gbif_hashes, verbose,
                                    odm_variable = odm_variable)
    if (!is.null(odm_result)) entity_results[["ODM"]] <- odm_result
  }

  if (length(entity_results) == 0L) return(NULL)
  dplyr::bind_rows(entity_results)
}


# -- ODM join helper ------------------------------------------------------------

#' Attempt to join LTER Observation Data Model tables into a DwC-compatible frame
#'
#' Looks for entity names matching "observation", "location", and "taxon"
#' (case-insensitive substring match). Downloads each if not already in
#' entity_info$raw. Joins observation -> location on location_id and
#' observation -> taxon on taxon_id (both coerced to character). Filters to
#' odm_variable (default "DENSITY") for a single numeric measure per row.
#' Renames columns to DwC equivalents and passes through .finalize_entity().
#'
#' Returns NULL with a message if any required table is missing or the join
#' produces no rows within the bbox.
#'
#' @noRd
.attempt_odm_join <- function(entity_info, dwc_map, meta,
                               bbox, gbif_hashes, verbose,
                               odm_variable = "DENSITY") {

  enames_lower <- tolower(vapply(entity_info, `[[`, "", "ename"))

  find_entity <- function(pattern) {
    idx <- grep(pattern, enames_lower, fixed = TRUE)
    if (length(idx) == 0L) return(NULL)
    # Prefer exact match over partial (e.g. "observation" over "observation_ancillary")
    exact <- which(enames_lower[idx] == pattern)
    if (length(exact) > 0L) idx[exact[1L]] else idx[1L]
  }

  obs_idx <- find_entity("observation")
  loc_idx <- find_entity("location")
  tax_idx <- find_entity("taxon")

  if (is.null(obs_idx) || is.null(loc_idx) || is.null(tax_idx)) return(NULL)

  # ---- helper: get raw data, downloading if needed --------------------------
  get_raw <- function(idx) {
    ei <- entity_info[[idx]]
    if (!is.null(ei$raw)) return(ei$raw)
    if (is.na(ei$entity$data_url)) {
      if (verbose) message(sprintf("    ODM: no data URL for '%s' -- skipping.", ei$ename))
      return(NULL)
    }
    if (verbose) message(sprintf("\n  ODM entity: %s", str_trunc_safe(ei$ename, 60)))
    raw <- .download_data_table(ei$entity$data_url)
    if (is.null(raw) || nrow(raw) == 0L) {
      if (verbose) message("    Download returned no data -- skipping ODM join.")
      return(NULL)
    }
    if (verbose) message(sprintf("    Downloaded: %d rows x %d cols", nrow(raw), ncol(raw)))
    raw
  }

  obs_raw <- get_raw(obs_idx)
  loc_raw <- get_raw(loc_idx)
  tax_raw <- get_raw(tax_idx)

  if (is.null(obs_raw) || is.null(loc_raw) || is.null(tax_raw)) return(NULL)

  # ---- detect column names case-insensitively --------------------------------
  find_col <- function(df, pattern) {
    idx <- grep(pattern, tolower(names(df)), fixed = TRUE)
    if (length(idx) == 0L) NA_character_ else names(df)[idx[1L]]
  }

  obs_loc_col  <- find_col(obs_raw, "location_id")
  obs_tax_col  <- find_col(obs_raw, "taxon_id")
  obs_var_col  <- find_col(obs_raw, "variable_name")
  obs_val_col  <- find_col(obs_raw, "value")
  obs_date_col <- find_col(obs_raw, "datetime")
  loc_id_col   <- find_col(loc_raw, "location_id")
  loc_lat_col  <- find_col(loc_raw, "latitude")
  loc_lon_col  <- find_col(loc_raw, "longitude")
  loc_name_col <- find_col(loc_raw, "location_name")
  tax_id_col   <- find_col(tax_raw, "taxon_id")
  tax_name_col <- find_col(tax_raw, "taxon_name")

  required <- c(obs_loc_col, obs_tax_col, obs_var_col, obs_val_col,
                obs_date_col, loc_id_col, loc_lat_col, loc_lon_col,
                tax_id_col, tax_name_col)
  if (any(is.na(required))) {
    if (verbose) {
      message(sprintf(
        "    ODM join: required columns missing -- skipping.\n    Missing: %s",
        paste(c("obs.location_id", "obs.taxon_id", "obs.variable_name",
                "obs.value", "obs.datetime", "loc.location_id",
                "loc.latitude", "loc.longitude",
                "tax.taxon_id", "tax.taxon_name")[is.na(required)],
              collapse = ", ")
      ))
    }
    return(NULL)
  }

  # ---- filter location table to rows with coordinates -----------------------
  loc_coords <- loc_raw[
    !is.na(loc_raw[[loc_lat_col]]) & !is.na(loc_raw[[loc_lon_col]]), ]
  if (nrow(loc_coords) == 0L) {
    if (verbose) message("    ODM join: location table has no coordinate rows -- skipping.")
    return(NULL)
  }

  # ---- filter observation table to chosen variable --------------------------
  if (!is.null(obs_var_col) && !is.na(obs_var_col) &&
      odm_variable %in% obs_raw[[obs_var_col]]) {
    obs_filt <- obs_raw[obs_raw[[obs_var_col]] == odm_variable, ]
    if (verbose) {
      message(sprintf(
        "\n  ODM join: filtering to variable_name = '%s' (%d of %d rows)",
        odm_variable, nrow(obs_filt), nrow(obs_raw)
      ))
    }
  } else {
    # Requested variable absent -- use all rows and warn
    obs_filt <- obs_raw
    if (verbose) {
      avail <- if (!is.na(obs_var_col))
        paste(unique(obs_raw[[obs_var_col]]), collapse = ", ") else "(unknown)"
      message(sprintf(
        "    ODM join: variable '%s' not found; using all rows. Available: %s",
        odm_variable, avail
      ))
    }
  }

  # ---- join observation -> location ------------------------------------------
  obs_filt[[obs_loc_col]] <- as.character(obs_filt[[obs_loc_col]])
  loc_coords[[loc_id_col]] <- as.character(loc_coords[[loc_id_col]])

  merged <- tryCatch(
    dplyr::left_join(obs_filt, loc_coords,
                     by = stats::setNames(loc_id_col, obs_loc_col)),
    error = function(e) {
      if (verbose) message("    ODM obs->loc join error: ", conditionMessage(e))
      NULL
    }
  )
  if (is.null(merged) || nrow(merged) == 0L) {
    if (verbose) message("    ODM obs->loc join produced no rows -- skipping.")
    return(NULL)
  }
  if (verbose) {
    message(sprintf("    ODM obs->loc join: %d rows", nrow(merged)))
  }

  # ---- join merged -> taxon --------------------------------------------------
  merged[[obs_tax_col]] <- as.character(merged[[obs_tax_col]])
  tax_raw[[tax_id_col]] <- as.character(tax_raw[[tax_id_col]])

  # Keep only id + name from taxon table to avoid column conflicts
  tax_slim <- tax_raw[, c(tax_id_col, tax_name_col), drop = FALSE]

  merged <- tryCatch(
    dplyr::left_join(merged, tax_slim,
                     by = stats::setNames(tax_id_col, obs_tax_col)),
    error = function(e) {
      if (verbose) message("    ODM merged->taxon join error: ", conditionMessage(e))
      NULL
    }
  )
  if (is.null(merged) || nrow(merged) == 0L) {
    if (verbose) message("    ODM merged->taxon join produced no rows -- skipping.")
    return(NULL)
  }
  if (verbose) {
    message(sprintf("    ODM merged->taxon join: %d rows x %d cols",
                    nrow(merged), ncol(merged)))
  }

  # ---- rename to DwC --------------------------------------------------------
  rename_if_present <- function(df, old, new) {
    if (old %in% names(df) && !old == new) {
      names(df)[names(df) == old] <- new
    }
    df
  }

  merged <- rename_if_present(merged, tax_name_col,  "scientificName")
  merged <- rename_if_present(merged, obs_date_col,   "eventDate")
  merged <- rename_if_present(merged, obs_val_col,    "individualCount")
  merged <- rename_if_present(merged, loc_lat_col,    "decimalLatitude")
  merged <- rename_if_present(merged, loc_lon_col,    "decimalLongitude")
  merged <- rename_if_present(merged, loc_name_col,   "locality")

  # Coerce coordinate columns to numeric
  merged$decimalLatitude  <- suppressWarnings(as.numeric(merged$decimalLatitude))
  merged$decimalLongitude <- suppressWarnings(as.numeric(merged$decimalLongitude))

  # ---- finalize -------------------------------------------------------------
  final_mapping <- .map_columns_to_dwc(names(merged), dwc_map)
  .finalize_entity(merged, final_mapping, meta, bbox, gbif_hashes, verbose)
}


# -- Lightweight string helpers -------------------------------------------------

#' Safe xml_text that returns NA_character_ on missing node
#' @noRd
xml_text_safe <- function(node) {
  if (inherits(node, "xml_missing") || length(node) == 0L || is.na(node)) {
    return(NA_character_)
  }
  xml2::xml_text(node, trim = TRUE)
}

#' str_trunc fallback that works without stringr at load time
#' @noRd
str_trunc_safe <- function(x, width) {
  if (is.na(x) || !nzchar(x)) return(x)
  if (nchar(x) <= width) return(x)
  paste0(substr(x, 1L, width - 3L), "...")
}

