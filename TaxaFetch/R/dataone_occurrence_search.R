# ==============================================================================
# dataone_occurrence_search.R
# TaxaExpect -- EDI / PASTA dataset discovery
#
# Exported:  search_dataone(), fetch_dataone_eml()
# Internal:  .parse_pasta_response(), .parse_coordinates_field(),
#            .bbox_overlaps(), .score_occurrence_relevance(), .pasta_eml_url()
#
# -- Endpoint ------------------------------------------------------------------
# EDI PASTA+ Solr at pasta.lternet.edu.
# DataONE CN (cn.dataone.org) is sunset -- do not use.
#
# -- PASTA Solr confirmed field list (from PASTA+ API docs) -------------------
# Single-value: abstract, begindate, doi, enddate, funding,
#   geographicdescription, id, methods, packageid, pubdate,
#   responsibleParties, scope, singledate, site, taxonomic, title
# Multi-value:  author, coordinates, keyword, organization,
#   projectTitle, relatedProjectTitle, timescale
# CopyField:    subject (aggregates title+abstract+keyword+author+organization;
#   valid for q= searches with defType=edismax but NOT a stored return field)
#
# -- PASTA Solr confirmed-working query patterns -------------------------------
# q=*:*                       -- match all (safest baseline)
# q=keyword:fish              -- field term search
# q=subject:"Santa Barbara"   -- copyField search (edismax only)
# fq=-scope:ecotrends         -- ONE fq per noise scope (must be separate params)
# sort=pubdate,desc           -- ONE sort per param (comma-separated field,dir)
#
# -- Root causes of previous HTTP 500 -----------------------------------------
# 1. fq="-scope:(ecotrends lter-landsat*)" as one param -> needs two fq params
# 2. sort="score desc, pubdate desc" as one param -> needs two sort params
# 3. subject:() syntax with parenthesised OR inside edismax can choke on
#    special characters encoded by httr2 req_url_query
# All three fixed: q=*:* + multiple fq via .multi="append" + two sort params.
#
# -- Bbox filtering ------------------------------------------------------------
# PASTA's 'coordinates' is a plain multi-value TEXT field -- not a Solr spatial
# type. Solr geofilt/bbox queries cannot be used against it. All results are
# retrieved and bbox-filtered in R by parsing the 'coordinates' text.
# Format is unknown until first run; verbose=TRUE prints a sample for inspection.
# ==============================================================================


.PASTA_SOLR <- "https://pasta.lternet.edu/package/search/eml"
.PASTA_META <- "https://pasta.lternet.edu/package/metadata/eml"

.DEFAULT_BIO_KEYWORDS <- c(
  "species", "occurrence", "abundance", "population", "biodiversity",
  "community", "survey", "specimen", "observation", "monitoring",
  "fish", "invertebrate", "algae", "kelp", "bird", "marine", "benthic",
  "intertidal", "subtidal", "reef", "transect", "quadrat", "taxa", "taxon"
)


# ==============================================================================
# Exported: search_dataone
# ==============================================================================

#' Discover Occurrence-Bearing Datasets from EDI / PASTA
#'
#' Queries the EDI PASTA+ Solr index for all datasets (\code{q=*:*}), then
#' filters results in R by bounding-box overlap on the returned
#' \code{coordinates} field. An optional \code{keywords} argument adds Solr
#' \code{fq} constraints on \code{title}, \code{geographicdescription}, and
#' \code{taxonomic} fields before the R-side bbox filter.
#'
#' @param bbox Named list with numeric elements \code{west}, \code{east},
#'   \code{south}, \code{north} (decimal degrees, WGS84). Datasets whose
#'   geographic coverage does not overlap this box are removed. Records with
#'   unparseable \code{coordinates} are \strong{retained} (fail open).
#'   Pass \code{NULL} to skip spatial filtering and return all results.
#' @param keywords Optional character vector. Simple search terms added as
#'   Solr \code{fq} filters (one OR-joined \code{fq} param, searching
#'   \code{title}, \code{geographicdescription}, and \code{taxonomic}).
#'   E.g. \code{c("kelp", "fish", "invertebrate")}. \code{NULL} (default)
#'   applies no keyword filter.
#' @param max_rows Integer. Rows to fetch from Solr before R-side filtering.
#'   Default \code{500L}. Increase for large bboxes.
#' @param exclude_noise Logical. Exclude the \code{ecotrends} and
#'   \code{lter-landsat*} scopes (~25 000 non-occurrence packages).
#'   Default \code{TRUE}.
#' @param min_bio_score Integer. Minimum biological relevance score to flag
#'   \code{is_candidate = TRUE}. Default \code{1L}. Set \code{0L} for all.
#' @param verbose Logical. Print progress. On first run, set \code{TRUE} to
#'   see the raw \code{coordinates} value format returned by PASTA, which is
#'   needed to verify the bbox parser is working. Default \code{TRUE}.
#'
#' @return A tibble sorted by \code{bio_score} descending, with columns:
#'   \code{id}, \code{title}, \code{scope}, \code{pubdate},
#'   \code{geographicdescription}, \code{taxonomic}, \code{keywords_str},
#'   \code{authors}, \code{begindate}, \code{enddate}, \code{abstract},
#'   \code{coordinates_raw}, \code{bbox_status} (one of \code{"overlap"},
#'   \code{"no_overlap"}, \code{"unparseable"}, \code{"no_filter"}),
#'   \code{bio_score}, \code{has_taxonomic}, \code{is_candidate}.
#'
#' @importFrom httr2 request req_url_query req_perform resp_body_string
#' @importFrom xml2 read_xml xml_ns_strip xml_find_all xml_find_first xml_text
#' @examples
#' \dontrun{
#' results <- search_dataone(
#'   bbox = c(-120, 34, -119, 35),
#'   keywords = c("fish", "occurrence")
#' )
#' }
#'
#' @importFrom dplyr arrange desc select all_of
#' @importFrom tibble tibble as_tibble
#' @export
search_dataone <- function(bbox,
                           keywords      = NULL,
                           max_rows      = 500L,
                           exclude_noise = TRUE,
                           min_bio_score = 1L,
                           verbose       = TRUE) {

  # -- Input validation -------------------------------------------------------
  if (!is.null(bbox)) {
    req_nms <- c("west", "east", "south", "north")
    if (!is.list(bbox) || !all(req_nms %in% names(bbox))) {
      stop("search_dataone: 'bbox' must be NULL or a named list with ",
           "elements west, east, south, north (decimal degrees).")
    }
    bbox_vals <- bbox[req_nms]
    non_numeric <- vapply(bbox_vals, function(x) {
      !is.numeric(x) || length(x) != 1L || is.na(x) || !is.finite(x)
    }, logical(1L))
    if (any(non_numeric)) {
      stop("search_dataone: all bbox elements (west, east, south, north) must be ",
           "single finite numeric values.")
    }
  }
  max_rows      <- as.integer(max_rows)
  min_bio_score <- as.integer(min_bio_score)
  if (is.na(max_rows) || max_rows < 1L)
    stop("search_dataone: 'max_rows' must be a positive integer.")

  if (verbose) {
    message("search_dataone: querying EDI PASTA Solr...")
    if (!is.null(bbox)) {
      message(sprintf("  bbox: W=%.4f  E=%.4f  S=%.4f  N=%.4f",
                      bbox$west, bbox$east, bbox$south, bbox$north))
    }
    if (!is.null(keywords)) {
      message("  keywords: ", paste(keywords, collapse = " | "))
    }
  }

  # -- Build base request ----------------------------------------------------
  # q=*:* -- guaranteed not to 500; all filtering via fq or post-hoc in R.
  req <- httr2::request(.PASTA_SOLR) |>
    httr2::req_url_query(
      defType = "edismax",
      q       = "*:*",
      fl      = paste(c("packageid", "title", "authors", "scope", "site",
                        "pubdate", "begindate", "enddate",
                        "geographicdescription", "abstract", "taxonomic",
                        "keyword", "coordinates"),
                      collapse = ","),
      rows    = max_rows,
      start   = 0L
    ) |>
    # Two sort params as a vector -- .multi = "explode" sends each as a
    # separate ?sort= param, which is what PASTA requires.
    httr2::req_url_query(
      sort = c("pubdate,desc", "packageid,asc"),
      .multi = "explode"
    )

  # Noise exclusion -- two separate fq params (must use "explode")
  if (exclude_noise) {
    req <- httr2::req_url_query(
      req,
      fq = c("-scope:ecotrends", "-scope:lter-landsat*"),
      .multi = "explode"
    )
  }

  # Optional keyword fq: title OR geographicdescription OR taxonomic
  if (!is.null(keywords) && length(keywords) > 0L) {
    kw_parts <- vapply(trimws(keywords), function(kw) {
      kw_safe <- gsub(":", "\\:", kw, fixed = TRUE)
      kw_safe <- gsub("/", "\\/", kw_safe, fixed = TRUE)
      if (grepl(" ", kw_safe)) kw_safe <- paste0('"', kw_safe, '"')
      sprintf("title:%s OR geographicdescription:%s OR taxonomic:%s",
              kw_safe, kw_safe, kw_safe)
    }, character(1L))
    req <- httr2::req_url_query(
      req,
      fq = paste(kw_parts, collapse = " OR "),
      .multi = "explode"
    )
  }

  # -- HTTP request ----------------------------------------------------------
  resp <- tryCatch(
    httr2::req_perform(req),
    error = function(e) {
      stop("search_dataone: PASTA Solr request failed -- ", conditionMessage(e))
    }
  )

  raw_xml <- httr2::resp_body_string(resp)

  # -- Parse response --------------------------------------------------------
  docs <- tryCatch(
    .parse_pasta_response(raw_xml),
    error = function(e) {
      stop("search_dataone: XML parse failed -- ", conditionMessage(e))
    }
  )

  if (is.null(docs) || nrow(docs) == 0L) {
    if (verbose) message("  No datasets returned from Solr.")
    return(tibble::tibble())
  }

  if (verbose) {
    message(sprintf("  %d dataset(s) returned from Solr.", nrow(docs)))
    # Print raw coordinates sample -- essential for verifying the bbox parser.
    if ("coordinates_raw" %in% names(docs)) {
      sample_raw <- docs$coordinates_raw[!is.na(docs$coordinates_raw)]
      if (length(sample_raw) > 0L) {
        message("  Sample raw 'coordinates' value (first non-NA):")
        message("    '", sample_raw[[1L]], "'")
        message("  (Inspect this to verify bbox parser is extracting ",
                "N/S/E/W correctly.)")
      } else {
        message("  WARNING: all 'coordinates' values are NA. ",
                "Bbox filter will retain all results (fail open).")
      }
    }
  }

  # -- Biological relevance scoring ------------------------------------------
  docs <- .score_occurrence_relevance(docs, .DEFAULT_BIO_KEYWORDS,
                                      min_bio_score)

  # -- Bbox post-filter (R-side) ---------------------------------------------
  if (!is.null(bbox) && "coordinates_raw" %in% names(docs)) {
    n_before <- nrow(docs)

    docs$bbox_status <- vapply(docs$coordinates_raw, function(raw) {
      pb <- .parse_coordinates_field(raw)
      if (is.null(pb)) return("unparseable")
      if (.bbox_overlaps(pb, bbox)) "overlap" else "no_overlap"
    }, character(1L))

    n_unparse <- sum(docs$bbox_status == "unparseable")
    docs <- docs[docs$bbox_status != "no_overlap", ]

    if (verbose) {
      message(sprintf(
        "  Bbox filter: %d -> %d dataset(s) kept. %d unparseable (retained).",
        n_before, nrow(docs), n_unparse))
      if (n_unparse > 0L) {
        message("  Inspect coordinates_raw on 'unparseable' rows to report ",
                "the unhandled format.")
      }
    }
  } else {
    docs$bbox_status <- "no_filter"
  }

  if (nrow(docs) == 0L) {
    if (verbose) {
      message("  No datasets remain after bbox filter.")
      message("  Possible causes:")
      message("    1. coordinates_raw is NA for all results ",
              "(no bbox in EML metadata)")
      message("    2. Coordinates format not handled by parser")
      message("    3. Genuine spatial mismatch with bbox")
      message("  Tip: run with bbox = NULL to see all results and inspect ",
              "the coordinates_raw column.")
    }
    return(tibble::tibble())
  }

  # -- Column order ----------------------------------------------------------
  priority <- c("id", "title", "scope", "site", "pubdate",
                "bio_score", "has_taxonomic", "is_candidate", "bbox_status",
                "geographicdescription", "taxonomic", "keywords_str",
                "authors", "begindate", "enddate", "abstract",
                "coordinates_raw")
  present   <- intersect(priority, names(docs))
  remaining <- setdiff(names(docs), priority)
  docs      <- dplyr::select(docs,
                              dplyr::all_of(present),
                              dplyr::all_of(remaining))

  if (verbose) {
    n_cand <- sum(docs$is_candidate, na.rm = TRUE)
    message(sprintf("  %d candidate(s) with bio_score >= %d.",
                    n_cand, min_bio_score))
  }
  docs
}


# ==============================================================================
# Exported: fetch_dataone_eml
# ==============================================================================

#' Fetch Raw EML XML for an EDI / PASTA Dataset
#'
#' @param dataset_id Character. PASTA package ID, e.g.
#'   \code{"knb-lter-sbc.17.18"}.
#' @return Length-1 character string of raw EML XML.
#'
#' @examples
#' \dontrun{
#' eml_xml <- fetch_dataone_eml("knb-lter-sbc.17.18")
#' }
#'
#' @importFrom httr2 request req_perform resp_body_string
#' @export
fetch_dataone_eml <- function(dataset_id) {
  if (!is.character(dataset_id) || length(dataset_id) != 1L ||
      !nzchar(dataset_id)) {
    stop("fetch_dataone_eml: 'dataset_id' must be a single non-empty string.")
  }
  url <- .pasta_eml_url(dataset_id)
  message("fetch_dataone_eml: fetching ", url)
  resp <- tryCatch(
    httr2::request(url) |> httr2::req_perform(),
    error = function(e) {
      stop("fetch_dataone_eml: request failed -- ", conditionMessage(e))
    }
  )
  httr2::resp_body_string(resp)
}


# ==============================================================================
# Internal helpers
# ==============================================================================

#' Parse PASTA Solr XML resultset into a tibble
#' @noRd
.parse_pasta_response <- function(raw_xml) {
  doc <- xml2::read_xml(raw_xml)
  xml2::xml_ns_strip(doc)

  doc_nodes <- xml2::xml_find_all(doc, ".//document")
  if (length(doc_nodes) == 0L) return(NULL)

  single_flds <- c("packageid", "title", "authors", "scope", "site",
                   "pubdate", "begindate", "enddate",
                   "geographicdescription", "abstract", "taxonomic")

  rows <- lapply(doc_nodes, function(node) {
    row <- list()

    for (fld in single_flds) {
      n <- xml2::xml_find_first(node, fld)
      row[[fld]] <- if (inherits(n, "xml_missing") || length(n) == 0L) {
        NA_character_
      } else {
        txt <- xml2::xml_text(n, trim = TRUE)
        if (nzchar(txt)) txt else NA_character_
      }
    }

    # keywords -- two possible XML layouts
    kw_nodes <- xml2::xml_find_all(node, "keywords/keyword")
    if (length(kw_nodes) == 0L)
      kw_nodes <- xml2::xml_find_all(node, "keyword")
    if (length(kw_nodes) > 0L) {
      vals <- xml2::xml_text(kw_nodes, trim = TRUE)
      vals <- vals[nzchar(vals)]
      row[["keywords_str"]] <- if (length(vals) > 0L)
        paste(vals, collapse = "|") else NA_character_
    } else {
      row[["keywords_str"]] <- NA_character_
    }

    # coordinates -- multi-value; collect all child text nodes
    # Try nested <coordinate> elements first, then flat text node
    coord_nodes <- xml2::xml_find_all(node, "coordinates/coordinate")
    if (length(coord_nodes) == 0L)
      coord_nodes <- xml2::xml_find_all(node, "coordinate")
    if (length(coord_nodes) > 0L) {
      vals <- xml2::xml_text(coord_nodes, trim = TRUE)
      vals <- vals[nzchar(vals)]
      row[["coordinates_raw"]] <- if (length(vals) > 0L)
        paste(vals, collapse = "|") else NA_character_
    } else {
      cn <- xml2::xml_find_first(node, "coordinates")
      if (!inherits(cn, "xml_missing") && length(cn) > 0L) {
        txt <- xml2::xml_text(cn, trim = TRUE)
        row[["coordinates_raw"]] <- if (nzchar(txt)) txt else NA_character_
      } else {
        row[["coordinates_raw"]] <- NA_character_
      }
    }

    row
  })

  df <- do.call(rbind, lapply(rows, as.data.frame, stringsAsFactors = FALSE))

  if ("packageid" %in% names(df))
    names(df)[names(df) == "packageid"] <- "id"

  tibble::as_tibble(df)
}


#' Parse PASTA coordinates text -> bbox list(north, south, east, west)
#'
#' Tries multiple formats in order. Returns NULL on failure (caller retains
#' the dataset). All known PASTA coordinate formats:
#'
#' Format B  "N:35.0 S:33.5 E:-118.5 W:-121.0"  (key:value tokens)
#' Format A  "35.0|33.5|-118.5|-121.0"           (4 nums, NSEW order)
#' Format C  "+35.0 +33.5 -118.5 -121.0"         (4 space-sep nums)
#' Format D  "35.0,-121.0|35.0,-118.5|..."        (lat,lon corner pairs)
#'
#' @noRd
.parse_coordinates_field <- function(raw) {
  if (is.na(raw) || !nzchar(trimws(raw))) return(NULL)

  # Format B: N:, S:, E:, W: tokens
  .xkey <- function(k) {
    m <- regmatches(raw, regexpr(
      paste0("(?i)\\b", k, ":([+-]?[0-9]+\\.?[0-9]*)"), raw, perl = TRUE))
    if (length(m) == 0L) return(NA_real_)
    as.numeric(sub(paste0("(?i)\\b", k, ":"), "", m, perl = TRUE))
  }
  n <- .xkey("N"); s <- .xkey("S"); e <- .xkey("E"); w <- .xkey("W")
  if (!any(is.na(c(n, s, e, w))))
    return(list(north = n, south = s, east = e, west = w))

  # Extract all numeric tokens
  nums <- suppressWarnings(as.numeric(
    regmatches(raw, gregexpr("[+-]?[0-9]+\\.?[0-9]*", raw))[[1L]]))
  nums <- nums[!is.na(nums)]

  # Format A/C: exactly 4 numbers, assumed NSEW
  if (length(nums) == 4L) {
    n2 <- nums[1L]; s2 <- nums[2L]; e2 <- nums[3L]; w2 <- nums[4L]
    if (abs(n2) <= 90 && abs(s2) <= 90 && abs(e2) <= 180 && abs(w2) <= 180
        && n2 >= s2)
      return(list(north = n2, south = s2, east = e2, west = w2))
    # Try WESN order
    w3 <- nums[1L]; e3 <- nums[2L]; s3 <- nums[3L]; n3 <- nums[4L]
    if (abs(n3) <= 90 && abs(s3) <= 90 && abs(e3) <= 180 && abs(w3) <= 180
        && n3 >= s3)
      return(list(north = n3, south = s3, east = e3, west = w3))
  }

  # Format D: 8 numbers as 4 lat,lon corner pairs
  if (length(nums) == 8L) {
    lats <- nums[c(1L, 3L, 5L, 7L)]; lons <- nums[c(2L, 4L, 6L, 8L)]
    if (all(abs(lats) <= 90) && all(abs(lons) <= 180))
      return(list(north = max(lats), south = min(lats),
                  east  = max(lons), west  = min(lons)))
  }

  # Fallback: even count >= 4, treat as lat/lon pairs
  if (length(nums) >= 4L && length(nums) %% 2L == 0L) {
    lats <- nums[seq(1L, length(nums), 2L)]
    lons <- nums[seq(2L, length(nums), 2L)]
    if (all(abs(lats) <= 90) && all(abs(lons) <= 180))
      return(list(north = max(lats), south = min(lats),
                  east  = max(lons), west  = min(lons)))
  }

  NULL
}


#' Bbox intersection test
#' @noRd
.bbox_overlaps <- function(a, b) {
  !(a$south > b$north || a$north < b$south ||
    a$west  > b$east  || a$east  < b$west)
}


#' Score biological relevance
#' @noRd
.score_occurrence_relevance <- function(docs, bio_keywords, min_bio_score) {
  for (col in c("abstract", "taxonomic", "keywords_str", "title"))
    if (!col %in% names(docs)) docs[[col]] <- NA_character_

  scores <- mapply(function(ti, ab, kw, tax) {
    txt <- tolower(paste(c(
      if (!is.na(ti))  ti  else "",
      if (!is.na(ab))  ab  else "",
      if (!is.na(kw))  kw  else "",
      if (!is.na(tax)) tax else ""), collapse = " "))
    sum(vapply(bio_keywords, function(k) grepl(k, txt, fixed = TRUE),
               logical(1L)))
  }, docs$title, docs$abstract, docs$keywords_str, docs$taxonomic)

  docs$bio_score     <- as.integer(scores)
  docs$has_taxonomic <- !is.na(docs$taxonomic) & nzchar(docs$taxonomic)
  docs$is_candidate  <- docs$bio_score >= min_bio_score
  dplyr::arrange(docs, dplyr::desc(.data$bio_score))
}


#' Build PASTA EML metadata URL
#' @noRd
.pasta_eml_url <- function(dataset_id) {
  parts <- strsplit(dataset_id, "\\.")[[1L]]
  if (length(parts) < 3L)
    stop(sprintf(".pasta_eml_url: cannot parse ID '%s'. ", dataset_id),
         "Expected scope.identifier.revision (e.g. knb-lter-sbc.17.18).")
  rev   <- parts[length(parts)]
  ident <- parts[length(parts) - 1L]
  scope <- paste(parts[seq_len(length(parts) - 2L)], collapse = ".")
  paste(.PASTA_META, scope, ident, rev, sep = "/")
}
