# ==============================================================================
# dataone_catalog.R
# TaxaExpect -- DataONE / PASTA Solr catalog harvest
#
# Exported functions:
#   harvest_dataone_catalog()   Pull full PASTA Solr catalog; cache to disk
#
# Internal helpers (@noRd):
#   .pasta_solr_page()          Fetch one page of Solr results
# ==============================================================================


# ==============================================================================
# harvest_dataone_catalog()
# ==============================================================================

#' Harvest the Full PASTA / EDI Dataset Catalog
#'
#' Downloads metadata for all non-noise packages from the PASTA Solr endpoint
#' and returns them as a tibble. Results are cached to disk; subsequent calls
#' within \code{max_age_days} return the cache without hitting the network.
#'
#' This is the first step in the DataONE supplemental occurrence pipeline:
#' \preformatted{
#' catalog    <- harvest_dataone_catalog(cache_file = "pasta_catalog.rds")
#' geo_prompt <- build_geo_prompt(catalog, bbox)
#' llm_output <- prompt_api(geo_prompt)
#' candidates <- parse_geo_screening_response(llm_output, geo_prompt)
#' }
#'
#' @param cache_file Character. Path to an \code{.rds} cache file. If the file
#'   exists and is younger than \code{max_age_days}, the cache is returned
#'   without any network requests. Set to \code{NULL} to disable caching.
#'   Default \code{"pasta_catalog.rds"}.
#' @param max_age_days Numeric. Maximum age of a valid cache in days.
#'   Default \code{7}.
#' @param max_rows Integer. Maximum total records to retrieve. Set to
#'   \code{Inf} to retrieve all available records (may take 2-5 minutes on
#'   first run). Default \code{Inf}.
#' @param page_size Integer. Records per Solr request. Default \code{500}.
#'   Reduce if you encounter timeouts.
#' @param exclude_noise Logical. Exclude known non-biological scopes
#'   (\code{ecotrends}, \code{lter-landsat*}). Default \code{TRUE}.
#' @param pause_seconds Numeric. Pause between paginated requests. Default
#'   \code{0.5}.
#' @param verbose Logical. Print progress. Default \code{TRUE}.
#'
#' @return A tibble with one row per PASTA package and columns:
#'   \code{id}, \code{scope}, \code{title}, \code{site},
#'   \code{pubdate}, \code{geographicdescription}, \code{taxonomic},
#'   \code{abstract}, \code{keywords_str}, \code{authors}, \code{begindate},
#'   \code{enddate}, \code{has_taxonomic}, \code{is_candidate}.
#'   \code{is_candidate} is \code{TRUE} for packages that have a non-empty
#'   \code{taxonomic} field and are therefore worth geographic screening.
#'
#' @details
#' \strong{Cache invalidation:} Delete or rename the cache file to force a
#' full re-download. The cache stores the raw tibble -- no further processing
#' is done at cache-read time.
#'
#' \strong{PASTA coordinates field:} The Solr \code{coordinates} field is
#' indexed but unreliably populated for most packages. Spatial filtering is
#' handled downstream via \code{\link{screen_eml_columns}} (EML
#' \code{<boundingCoordinates>}) and record-level bbox filtering in
#' \code{\link{fetch_dataone_occurrences}}.
#'
#' @seealso \code{\link{build_geo_prompt}}, \code{\link{screen_eml_columns}},
#'   \code{\link{fetch_dataone_occurrences}}
#'
#' @importFrom httr2 request req_url_query req_perform resp_body_string
#' @importFrom xml2 read_xml xml_find_first xml_find_all xml_attr xml_text
#' @importFrom dplyr tibble bind_rows mutate if_else
#' @export
#'
#' @examples
#' \dontrun{
#' catalog <- harvest_dataone_catalog(cache_file = "pasta_catalog.rds",
#'                                    max_age_days = 7)
#' nrow(catalog)
#' table(catalog$is_candidate)
#' }

harvest_dataone_catalog <- function(cache_file    = "pasta_catalog.rds",
                                    max_age_days  = 7,
                                    max_rows      = Inf,
                                    page_size     = 500L,
                                    exclude_noise = TRUE,
                                    pause_seconds = 0.5,
                                    verbose       = TRUE) {

  # ---- cache check -----------------------------------------------------------
  if (!is.null(cache_file) && file.exists(cache_file)) {
    age_days <- as.numeric(difftime(Sys.time(),
                                    file.info(cache_file)$mtime,
                                    units = "days"))
    if (age_days <= max_age_days) {
      if (verbose) {
        message(sprintf(
          "harvest_dataone_catalog: loading cache (%s, %.1f days old)",
          cache_file, age_days
        ))
      }
      return(readRDS(cache_file))
    }
    if (verbose) {
      message(sprintf(
        "harvest_dataone_catalog: cache expired (%.1f days old) -- re-downloading",
        age_days
      ))
    }
  }

  if (!requireNamespace("httr2", quietly = TRUE)) {
    stop("harvest_dataone_catalog: package 'httr2' is required. ",
         "Install with: install.packages('httr2')")
  }

  # ---- build fixed fq params -------------------------------------------------
  fq_params <- character(0)
  if (exclude_noise) {
    fq_params <- c("-scope:ecotrends", "-scope:lter-landsat*")
  }

  # ---- paginate --------------------------------------------------------------
  page_size  <- as.integer(page_size)
  start      <- 0L
  total_rows <- NA_integer_
  all_pages  <- list()
  page_num   <- 0L

  repeat {
    page_num <- page_num + 1L
    rows_this_page <- if (is.finite(max_rows)) {
      min(page_size, as.integer(max_rows) - start)
    } else {
      page_size
    }
    if (rows_this_page <= 0L) break

    if (verbose) {
      if (is.na(total_rows)) {
        message(sprintf("  Page %d (rows %d-%d) ...",
                        page_num, start + 1L, start + rows_this_page))
      } else {
        message(sprintf("  Page %d (rows %d-%d of %d) ...",
                        page_num, start + 1L,
                        min(start + rows_this_page, total_rows),
                        total_rows))
      }
    }

    result <- tryCatch(
      .pasta_solr_page(start         = start,
                       rows          = rows_this_page,
                       fq_params     = fq_params),
      error = function(e) {
        warning(sprintf(
          "harvest_dataone_catalog: page %d failed -- %s",
          page_num, conditionMessage(e)
        ), call. = FALSE)
        NULL
      }
    )

    if (is.null(result)) break

    if (is.na(total_rows)) total_rows <- result$n_found
    if (nrow(result$data) == 0L) break

    all_pages[[page_num]] <- result$data
    start <- start + nrow(result$data)

    # Stop if we have everything
    if (!is.na(total_rows) && start >= total_rows) break
    if (!is.infinite(max_rows) && start >= as.integer(max_rows)) break

    Sys.sleep(pause_seconds)
  }

  if (length(all_pages) == 0L) {
    stop("harvest_dataone_catalog: no data retrieved. Check network and PASTA endpoint.")
  }

  catalog <- dplyr::bind_rows(all_pages)

  if (verbose) {
    message(sprintf(
      "harvest_dataone_catalog: %d packages retrieved", nrow(catalog)
    ))
  }

  # ---- derived columns -------------------------------------------------------
  catalog$has_taxonomic <- !is.na(catalog$taxonomic) &
    nzchar(trimws(catalog$taxonomic))
  catalog$is_candidate  <- catalog$has_taxonomic

  # ---- cache -----------------------------------------------------------------
  if (!is.null(cache_file)) {
    saveRDS(catalog, cache_file)
    if (verbose) {
      message(sprintf("harvest_dataone_catalog: cached to '%s'", cache_file))
    }
  }

  catalog
}


# ==============================================================================
# Internal: fetch one page from PASTA Solr
# ==============================================================================

#' Fetch one page of results from the PASTA Solr endpoint
#'
#' Returns a list with \code{$n_found} (total matching records) and
#' \code{$data} (a tibble of this page's records).
#'
#' @noRd
.pasta_solr_page <- function(start, rows, fq_params) {

  # PASTA returns its own XML format (<resultset>) regardless of wt= parameter.
  # Parse with xml2 directly.

  fl_fields <- paste(c(
    "id", "scope", "title", "site", "pubdate",
    "geographicdescription", "taxonomic", "abstract",
    "keyword", "author", "begindate", "enddate"
  ), collapse = ",")

  req <- httr2::request("https://pasta.lternet.edu/package/search/eml") |>
    httr2::req_url_query(
      q     = "*:*",
      fl    = fl_fields,
      rows  = rows,
      start = start,
      sort  = c("pubdate,desc", "packageid,asc"),
      .multi = "explode"
    )

  if (length(fq_params) > 0L) {
    req <- httr2::req_url_query(req, fq = fq_params, .multi = "explode")
  }

  resp    <- req |> httr2::req_perform()
  xml_doc <- xml2::read_xml(httr2::resp_body_string(resp))

  # <resultset numFound='N' ...>
  resultset <- xml2::xml_find_first(xml_doc, "//resultset")
  n_found   <- as.integer(xml2::xml_attr(resultset, "numFound") %||% "0")

  docs <- xml2::xml_find_all(xml_doc, "//document")

  if (length(docs) == 0L) {
    return(list(n_found = n_found, data = dplyr::tibble()))
  }

  # Helpers for xml2 node extraction
  # Each <document> is an xml2 node; fields are child elements.
  # Multi-value fields (keyword, author) may appear more than once.

  .xml_scalar <- function(doc, field) {
    node <- xml2::xml_find_first(doc, field)
    if (inherits(node, "xml_missing")) return(NA_character_)
    val <- trimws(xml2::xml_text(node))
    if (!nzchar(val)) NA_character_ else val
  }

  .xml_collapse <- function(doc, field) {
    nodes <- xml2::xml_find_all(doc, field)
    if (length(nodes) == 0L) return(NA_character_)
    vals <- trimws(xml2::xml_text(nodes))
    vals <- vals[nzchar(vals)]
    if (length(vals) == 0L) NA_character_ else paste(vals, collapse = " | ")
  }

  rows_list <- lapply(docs, function(doc) {
    dplyr::tibble(
      id                    = .xml_scalar(doc, "id"),
      scope                 = .xml_scalar(doc, "scope"),
      title                 = .xml_scalar(doc, "title"),
      site                  = .xml_scalar(doc, "site"),
      pubdate               = .xml_scalar(doc, "pubdate"),
      geographicdescription = .xml_scalar(doc, "geographicdescription"),
      taxonomic             = .xml_scalar(doc, "taxonomic"),
      abstract              = .xml_scalar(doc, "abstract"),
      keywords_str          = .xml_collapse(doc, "keyword"),
      authors               = .xml_collapse(doc, "author"),
      begindate             = .xml_scalar(doc, "begindate"),
      enddate               = .xml_scalar(doc, "enddate")
    )
  })

  list(
    n_found = n_found,
    data    = dplyr::bind_rows(rows_list)
  )
}
