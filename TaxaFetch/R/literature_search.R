# ==============================================================================
# literature_search.R
# TaxaFetch -- OpenAlex literature catalog harvest and PDF download
#
# Exported functions:
#   search_literature()          -- query OpenAlex; return standard catalog tibble
#   download_literature_pdfs()   -- download PDFs for screened catalog rows
#
# Internal helpers:
#   .decode_openalex_abstract()  -- decode inverted-index abstract to plain text
#   .openalex_fetch_page()       -- single paginated OpenAlex request
#   .literature_cache_path()     -- build cache filename from query hash
#   .query_hash()                -- lightweight query fingerprint
#
# Design:
#   Output mirrors harvest_dataone_catalog() column structure so the entire
#   downstream pipeline (taxon screening -> geo screening -> structure
#   characterisation -> extraction) is reusable unchanged.
#
#   Geographic filtering:
#     geo_scope parameter: user-supplied comma-separated place names, OR-grouped
#     and AND-combined with taxon_scope as title_and_abstract.search filters.
#     bbox is stored as metadata only -- does not affect the OpenAlex query.
#     Cache key: taxon_scope + geo_scope + max_results + from_year + open_access.
#     Changing bbox alone loads from cache -- delete openalex_cache/ to force
#     a fresh query.
#
#   OpenAlex API key:
#     Required since February 2026. Free to obtain -- create an account at
#     openalex.org and copy the key from openalex.org/settings/api.
#     Add OPENALEX_API_KEY=your_key to ~/.Renviron.
#     $1 free usage per day covers all realistic TaxaFetch query volumes.
#
# See AI_CONTEXT.md for full design rationale and pipeline context.
# Session 25: initial implementation; Nominatim geocoding removed in favour
#   of user-supplied geo_scope parameter.
# ==============================================================================


# ==============================================================================
# Internal helpers
# ==============================================================================

#' Decode an OpenAlex inverted-index abstract to plain text
#'
#' OpenAlex stores abstracts as inverted indices for legal reasons.
#' Structure (with simplifyVector = FALSE): named list, word -> list of integers.
#' Positions are 0-indexed.
#'
#' @noRd
.decode_openalex_abstract <- function(inv_index) {
  if (is.null(inv_index) || length(inv_index) == 0L) return(NA_character_)

  # unlist() flattens the list-of-lists structure; as.integer() is defensive
  # against JSON integers arriving as numeric doubles or nested lists
  all_positions <- as.integer(unlist(inv_index, use.names = FALSE))
  if (length(all_positions) == 0L) return(NA_character_)

  n_pos  <- max(all_positions) + 1L
  tokens <- character(n_pos)

  for (word in names(inv_index)) {
    # Each word's positions may be a list of scalars -- flatten and coerce
    positions <- as.integer(unlist(inv_index[[word]], use.names = FALSE))
    tokens[positions + 1L] <- word
  }

  tokens <- tokens[nzchar(tokens)]
  if (length(tokens) == 0L) return(NA_character_)
  paste(tokens, collapse = " ")
}


#' Perform a single OpenAlex works page request
#' @noRd
.openalex_fetch_page <- function(url, api_key) {
  req <- httr2::request(url) |>
    httr2::req_headers(
      "User-Agent" = "TaxaFetch/0.1 (R package; biodiversity occurrence data)"
    ) |>
    httr2::req_url_query(api_key = api_key) |>
    httr2::req_retry(max_tries = 3L, backoff = ~ 2) |>
    httr2::req_throttle(rate = 9 / 1)    # stay under 10 req/s

  resp <- tryCatch(
    httr2::req_perform(req),
    error = function(e) {
      stop(sprintf("OpenAlex request failed: %s", conditionMessage(e)),
           call. = FALSE)
    }
  )
  httr2::resp_body_json(resp, simplifyVector = FALSE)
}


#' Build cache file path
#' @noRd
.literature_cache_path <- function(cache_dir, query_hash) {
  file.path(cache_dir, paste0("openalex_cache_", query_hash, ".rds"))
}


#' Lightweight query fingerprint (no digest dependency)
#' @noRd
.query_hash <- function(...) {
  args  <- paste(c(...), collapse = "|")
  chars <- utf8ToInt(substr(args, 1L, 800L))
  as.character(abs(sum(chars * seq_along(chars))))
}


# ==============================================================================
# search_literature()
# ==============================================================================

#' Search the OpenAlex literature catalog for occurrence-relevant papers
#'
#' @description
#' Queries the OpenAlex API for papers matching a taxon scope and geographic
#' bounding box, and returns a catalog tibble with the same column structure as
#' \code{\link{harvest_dataone_catalog}}.  This makes the entire downstream PDF
#' pipeline (optional taxon screening -> optional geo screening -> structure
#' characterisation -> extraction) reusable unchanged.
#'
#' \strong{Geographic filtering:}
#' Pass a plain-language study area description as \code{geo_scope}, e.g.
#' \code{"California, Arizona"} or \code{"Santa Barbara Channel"}.
#' Comma-separated terms are split and OR-grouped so any term matches.
#' This is AND-combined with the taxon filter.  The \code{bbox} parameter is
#' stored as metadata on the result tibble but does NOT drive the search query.
#' Set \code{geo_scope = NULL} to search without any geographic pre-filtering.
#'
#' \strong{OpenAlex API key:}
#' Required since February 2026.  Free to obtain -- create an account at
#' \url{https://openalex.org} and copy your key from
#' \url{https://openalex.org/settings/api}.  Add
#' \code{OPENALEX_API_KEY=your_key} to \file{~/.Renviron} then restart R.
#' Your free key provides $1 of usage per day, which covers all typical
#' TaxaFetch query volumes.
#'
#' @param taxon_scope Character string.  Comma-separated taxon names or synonyms,
#'   e.g. \code{"timema"} or
#'   \code{"gobies, goby, Gobiidae, tidewater goby, Eucyclogobius"}.
#'   Terms are OR-grouped: any term matching in title or abstract is sufficient.
#' @param geo_scope Character string or \code{NULL} (default).  Comma-separated
#'   place names describing the study area, e.g. \code{"California, Arizona"} or
#'   \code{"Santa Barbara Channel, southern California"}.  Terms are OR-grouped
#'   and AND-combined with \code{taxon_scope}.  Set \code{NULL} to search without
#'   geographic pre-filtering.
#' @param bbox Numeric vector of length 4:
#'   \code{c(lon_min, lon_max, lat_min, lat_max)}.  Stored as metadata on the
#'   result tibble for downstream reference only -- does not affect the search
#'   query.  Pass \code{NULL} (default) if no bbox is relevant.
#' @param api_key Character.  OpenAlex API key.  Defaults to
#'   \code{Sys.getenv("OPENALEX_API_KEY")}.
#' @param max_results Integer.  Maximum papers to return.  Default \code{200L}.
#'   Results are returned in OpenAlex relevance order.
#' @param from_year Integer or \code{NULL}.  Filter to papers published from
#'   this year onward.  Default \code{NULL}.
#' @param open_access Logical.  Restrict to open-access papers with a direct
#'   PDF URL.  Default \code{TRUE}.
#' @param cache_dir Character or \code{NULL}.  Directory for \code{.rds} disk
#'   cache keyed by query hash.  \code{NULL} (default) disables caching.
#' @param verbose Logical.  Print progress messages.  Default \code{TRUE}.
#'
#' @return A tibble with columns:
#'   \code{id}, \code{title}, \code{abstract}, \code{keywords},
#'   \code{doi}, \code{pdf_url}, \code{year}, \code{authors}, \code{journal},
#'   \code{geo_match} (\code{NA}), \code{taxon_match} (\code{NA}).
#'
#'   Returns \code{invisible(NULL)} with a message if no results are found.
#'
#'   Attributes: \code{taxon_scope}, \code{geo_scope}, \code{bbox},
#'   \code{query_date}.
#'
#' @seealso \code{\link{download_literature_pdfs}},
#'   \code{\link{build_taxon_screen_prompt}}, \code{\link{build_geo_prompt}}
#'
#' @examples
#' \dontrun{
#' catalog <- search_literature(
#'   taxon_scope = "timema, Timema",
#'   geo_scope   = "California, Arizona",
#'   from_year   = 1992L
#' )
#' }
#'
#' @export
search_literature <- function(taxon_scope,
                               geo_scope   = NULL,
                               bbox        = NULL,
                               api_key     = Sys.getenv("OPENALEX_API_KEY"),
                               max_results = 200L,
                               from_year   = NULL,
                               open_access = TRUE,
                               cache_dir   = NULL,
                               verbose     = TRUE) {

  # --- Input validation ---
  if (!is.character(taxon_scope) || length(taxon_scope) != 1L ||
      is.na(taxon_scope) || !nzchar(trimws(taxon_scope))) {
    stop("'taxon_scope' must be a non-empty character string.", call. = FALSE)
  }
  if (!is.null(geo_scope)) {
    if (!is.character(geo_scope) || length(geo_scope) != 1L ||
        is.na(geo_scope) || !nzchar(trimws(geo_scope))) {
      stop("'geo_scope' must be a non-empty character string or NULL.", call. = FALSE)
    }
  }
  if (!is.null(bbox)) {
    if (!is.numeric(bbox) || length(bbox) != 4L) {
      stop(
        "'bbox' must be a numeric vector of length 4: c(lon_min, lon_max, lat_min, lat_max).",
        call. = FALSE
      )
    }
  }
  max_results <- as.integer(max_results)
  if (!is.null(from_year)) from_year <- as.integer(from_year)
  open_access <- isTRUE(open_access)

  # --- API key ---
  if (!nzchar(api_key)) {
    stop(
      "OpenAlex API key not found.\n",
      "  An API key is required since February 2026.\n",
      "  Getting one is free (30 seconds):\n",
      "    1. Create an account at openalex.org\n",
      "    2. Copy your key from openalex.org/settings/api\n",
      "    3. Add OPENALEX_API_KEY=your_key to ~/.Renviron\n",
      "    4. Restart R\n",
      "  Your free key provides $1 of usage per day -- enough for all typical queries.",
      call. = FALSE
    )
  }

  # --- Build geo_query from geo_scope ---
  # geo_scope is the user-supplied plain-language study area description.
  # It may be a comma-separated list of place names, e.g. "California, Arizona".
  # Split on commas and OR-group, exactly as taxon_scope is handled.
  # bbox is retained as metadata only and does NOT drive the search query --
  # Nominatim reverse-geocoding was removed because corner-based place names
  # are unreliable for broad or offshore bboxes and the user already knows
  # their study area.
  geo_query <- NULL
  if (!is.null(geo_scope)) {
    geo_terms <- trimws(strsplit(geo_scope, ",")[[1L]])
    geo_terms <- geo_terms[nzchar(geo_terms)]
    geo_query <- if (length(geo_terms) == 1L) {
      geo_terms
    } else {
      sprintf("(%s)", paste(geo_terms, collapse = " OR "))
    }
  }

  # --- Cache check ---
  cache_key <- .query_hash(
    taxon_scope, geo_scope %||% "none",
    max_results, from_year %||% "none", open_access
  )
  if (!is.null(cache_dir)) {
    if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)
    cache_file <- .literature_cache_path(cache_dir, cache_key)
    if (file.exists(cache_file)) {
      if (verbose) message("search_literature: loading from cache.")
      return(readRDS(cache_file))
    }
  }

  # --- Build OpenAlex filter string ---
  # Logic:
  #   - Within taxon_scope: OR  (any term matches)
  #   - Within geo_scope:   OR  (any place name matches)
  #   - Between taxon and geo: AND (must satisfy both)
  #
  # Both taxon_scope and geo_scope may be comma-separated synonym lists.
  # Each is split on commas, trimmed, and joined with OR inside a boolean group.
  # Single-term scopes are passed through unchanged.
  # OpenAlex boolean search syntax: (term1 OR term2 OR term3)

  # Split taxon_scope on commas into individual terms
  taxon_terms <- trimws(strsplit(taxon_scope, ",")[[1L]])
  taxon_terms <- taxon_terms[nzchar(taxon_terms)]

  taxon_query <- if (length(taxon_terms) == 1L) {
    taxon_terms
  } else {
    sprintf("(%s)", paste(taxon_terms, collapse = " OR "))
  }

  # geo_query already built above from geo_scope

  filter_parts <- character(0L)

  # Taxon filter -- OR within terms
  filter_parts <- c(
    filter_parts,
    sprintf("title_and_abstract.search:%s",
            utils::URLencode(taxon_query, reserved = TRUE))
  )

  # Geographic filter -- OR within place names, AND with taxon
  if (!is.null(geo_query)) {
    filter_parts <- c(
      filter_parts,
      sprintf("title_and_abstract.search:%s",
              utils::URLencode(geo_query, reserved = TRUE))
    )
  }

  if (open_access)    filter_parts <- c(filter_parts, "open_access.is_oa:true")
  if (!is.null(from_year)) {
    filter_parts <- c(filter_parts,
                      sprintf("publication_year:>%d", from_year - 1L))
  }
  filter_parts <- c(filter_parts, "type:article", "is_paratext:false")

  filter_str <- paste(filter_parts, collapse = ",")

  # Select only needed fields (reduces credits consumed per call)
  select_fields <- paste(c(
    "id", "title", "abstract_inverted_index",
    "topics", "keywords",
    "doi", "open_access",
    "publication_year", "authorships",
    "primary_location"
  ), collapse = ",")

  base_url <- sprintf(
    paste0(
      "https://api.openalex.org/works",
      "?filter=%s&select=%s&per-page=200&sort=relevance_score:desc"
    ),
    filter_str, select_fields
  )

  if (verbose) {
    message(sprintf(
      "search_literature: querying OpenAlex for '%s'", taxon_query
    ))
    if (!is.null(geo_query)) {
      message(sprintf("  AND geo           : %s", geo_query))
    } else {
      message("  No geo_scope supplied -- searching without geographic pre-filtering.")
    }
    if (!is.null(from_year)) message(sprintf("  from_year         : %d", from_year))
    if (open_access)          message("  open_access       : TRUE")
  }

  # --- Cursor-paginate ---
  all_works <- list()
  cursor    <- "*"
  n_fetched <- 0L

  repeat {
    page_url <- paste0(
      base_url, "&cursor=",
      utils::URLencode(cursor, reserved = TRUE)
    )

    if (verbose) {
      message(sprintf("  Fetching page (n_fetched = %d) ...", n_fetched))
    }

    body <- tryCatch(
      .openalex_fetch_page(page_url, api_key),
      error = function(e) {
        warning(sprintf(
          "search_literature: page fetch failed -- %s", conditionMessage(e)
        ), call. = FALSE)
        return(NULL)
      }
    )
    if (is.null(body)) break

    results <- body$results %||% list()
    if (length(results) == 0L) break

    all_works <- c(all_works, results)
    n_fetched <- n_fetched + length(results)

    if (verbose) {
      message(sprintf("  %d works retrieved so far.", n_fetched))
    }

    if (n_fetched >= max_results) break

    next_cursor <- body$meta$next_cursor %||% NULL
    if (is.null(next_cursor) || !nzchar(next_cursor)) break
    cursor <- next_cursor

    Sys.sleep(0.12)
  }

  if (length(all_works) > max_results) {
    all_works <- all_works[seq_len(max_results)]
  }

  if (length(all_works) == 0L) {
    message(sprintf(
      "search_literature: no results found for '%s'.", taxon_scope
    ))
    if (!is.null(geo_query)) {
      message(
        "  Tip: the AND geo filter may be too restrictive.\n",
        "  Try broadening geo_scope, or set geo_scope = NULL to search without geographic pre-filtering."
      )
    }
    return(invisible(NULL))
  }

  if (verbose) {
    message(sprintf("search_literature: parsing %d works.", length(all_works)))
  }

  # --- Parse works to catalog tibble ---
  rows <- lapply(all_works, function(w) {

    catalog_id <- w$id %||% NA_character_
    title      <- w$title %||% NA_character_
    abstract   <- .decode_openalex_abstract(w$abstract_inverted_index)

    topic_names <- vapply(
      w$topics %||% list(),
      function(t) t$display_name %||% "",
      character(1L)
    )
    kw_names <- vapply(
      w$keywords %||% list(),
      function(k) k$display_name %||% "",
      character(1L)
    )
    all_kw   <- unique(c(topic_names, kw_names))
    all_kw   <- all_kw[nzchar(all_kw)]
    keywords <- if (length(all_kw) > 0L) {
      paste(all_kw, collapse = "; ")
    } else NA_character_

    doi     <- w$doi %||% NA_character_
    oa      <- w$open_access %||% list()
    pdf_url <- oa$oa_url %||% NA_character_

    year <- w$publication_year %||% NA_integer_
    year <- if (!is.null(year) && !is.na(year)) as.integer(year) else NA_integer_

    author_names <- vapply(
      w$authorships %||% list(),
      function(a) (a$author %||% list())$display_name %||% "",
      character(1L)
    )
    author_names <- author_names[nzchar(author_names)]
    authors      <- if (length(author_names) > 0L) {
      paste(author_names, collapse = "; ")
    } else NA_character_

    pl      <- w$primary_location %||% list()
    src     <- pl$source %||% list()
    journal <- src$display_name %||% NA_character_

    data.frame(
      id          = catalog_id,
      title       = title,
      abstract    = abstract,
      keywords    = keywords,
      doi         = doi,
      pdf_url     = pdf_url,
      year        = year,
      authors     = authors,
      journal     = journal,
      geo_match   = NA_character_,
      taxon_match = NA_character_,
      stringsAsFactors = FALSE
    )
  })

  result <- tibble::as_tibble(do.call(rbind, rows))

  if (verbose) {
    n_with_pdf <- sum(!is.na(result$pdf_url))
    message(sprintf(
      "search_literature: %d papers returned (%d with PDF URL).",
      nrow(result), n_with_pdf
    ))
  }

  attr(result, "taxon_scope") <- taxon_scope
  attr(result, "geo_scope")   <- geo_scope
  attr(result, "bbox")        <- bbox
  attr(result, "query_date")  <- Sys.time()

  if (!is.null(cache_dir)) {
    saveRDS(result, cache_file)
    if (verbose) message(sprintf("  Cached to: %s", cache_file))
  }

  result
}


# ==============================================================================
# download_literature_pdfs()
# ==============================================================================

#' Download PDFs for papers in a screened literature catalog
#'
#' @description
#' Downloads PDFs for rows in a \code{\link{search_literature}} catalog tibble
#' (or any downstream-filtered version of it) that have a non-\code{NA}
#' \code{pdf_url}.  Adds a \code{local_pdf_path} column so records feed
#' directly into \code{\link{extract_pdf_text}}.
#'
#' Per-paper failures are caught and warned rather than stopping the loop,
#' following the same error-handling pattern as
#' \code{\link{fetch_dataone_occurrences}}.
#'
#' @param catalog A tibble from \code{\link{search_literature}}, optionally
#'   filtered by \code{\link{parse_taxon_screening_response}} and/or
#'   \code{\link{parse_geo_screening_response}}.  Must contain columns
#'   \code{id} and \code{pdf_url}.
#' @param output_dir Character.  Directory where PDFs are saved.  Created if
#'   it does not exist.
#' @param overwrite Logical.  If \code{FALSE} (default), skip papers whose PDF
#'   already exists in \code{output_dir}.
#' @param max_papers Integer or \code{NULL}.  Cap the number of downloads.
#'   \code{NULL} (default) downloads all rows with a \code{pdf_url}.  Useful
#'   for testing before committing to a full run.
#' @param pause_s Numeric.  Seconds to pause between downloads.  Default
#'   \code{0.5}.  Publisher servers have rate limits; be polite.
#' @param verbose Logical.  Print progress.  Default \code{TRUE}.
#'
#' @return The input \code{catalog} with \code{local_pdf_path} added.  Rows
#'   where download failed or \code{pdf_url} was \code{NA} have
#'   \code{local_pdf_path = NA_character_}.
#'
#'   Pass the non-\code{NA} paths directly to \code{\link{extract_pdf_text}}:
#'   \code{na.omit(result$local_pdf_path)}.
#'
#' @seealso \code{\link{search_literature}}, \code{\link{extract_pdf_text}}
#'
#' @examples
#' \dontrun{
#' # Download up to 10 PDFs for initial inspection
#' catalog_dl <- download_literature_pdfs(
#'   catalog    = geo_screened,
#'   output_dir = "pdfs/sbc_fish",
#'   max_papers = 10L
#' )
#' pdf_paths <- na.omit(catalog_dl$local_pdf_path)
#' }
#'
#' @export
download_literature_pdfs <- function(catalog,
                                      output_dir,
                                      overwrite  = FALSE,
                                      max_papers = NULL,
                                      pause_s    = 0.5,
                                      verbose    = TRUE) {

  if (!is.data.frame(catalog)) {
    stop("'catalog' must be a data frame or tibble.", call. = FALSE)
  }
  missing_cols <- setdiff(c("id", "pdf_url"), names(catalog))
  if (length(missing_cols) > 0L) {
    stop(sprintf("'catalog' is missing required columns: %s",
                 paste(missing_cols, collapse = ", ")), call. = FALSE)
  }

  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
    if (verbose) message(sprintf("Created output directory: %s", output_dir))
  }

  has_url    <- !is.na(catalog$pdf_url) & nzchar(catalog$pdf_url)
  candidates <- which(has_url)
  if (!is.null(max_papers)) {
    candidates <- head(candidates, as.integer(max_papers))
  }

  if (verbose) {
    message(sprintf(
      "download_literature_pdfs: %d of %d rows have PDF URLs; downloading %d.",
      sum(has_url), nrow(catalog), length(candidates)
    ))
  }

  catalog$local_pdf_path <- NA_character_

  if (length(candidates) == 0L) {
    if (verbose) message("  No PDF URLs to download.")
    return(catalog)
  }

  n_success <- 0L
  n_skip    <- 0L
  n_fail    <- 0L

  for (i in candidates) {

    url        <- catalog$pdf_url[i]
    catalog_id <- catalog$id[i] %||% sprintf("row%d", i)

    # Build a safe filename from catalog_id
    safe_id   <- gsub("[^A-Za-z0-9_-]", "_", basename(catalog_id))
    safe_id   <- substr(safe_id, 1L, 80L)
    dest_file <- file.path(output_dir, paste0(safe_id, ".pdf"))

    if (!overwrite && file.exists(dest_file)) {
      catalog$local_pdf_path[i] <- dest_file
      n_skip <- n_skip + 1L
      if (verbose) {
        message(sprintf("  [%d/%d] skip (exists): %s",
                        which(candidates == i), length(candidates),
                        basename(dest_file)))
      }
      next
    }

    if (verbose) {
      message(sprintf("  [%d/%d] downloading: %s",
                      which(candidates == i), length(candidates),
                      basename(dest_file)))
    }

    success <- tryCatch({
      req  <- httr2::request(url) |>
        httr2::req_headers(
          "User-Agent" =
            "TaxaFetch/0.1 (R package; biodiversity occurrence data)"
        ) |>
        httr2::req_retry(max_tries = 3L, backoff = ~ 2) |>
        httr2::req_timeout(60L)
      httr2::req_perform(req, path = dest_file)
      TRUE
    }, error = function(e) {
      warning(sprintf(
        "download_literature_pdfs: failed to download '%s': %s",
        basename(dest_file), conditionMessage(e)
      ), call. = FALSE)
      if (file.exists(dest_file)) file.remove(dest_file)
      FALSE
    })

    if (success) {
      # Sanity check: must be > 1 KB and start with the PDF magic bytes
      file_size <- file.info(dest_file)$size
      is_pdf    <- tryCatch({
        con    <- file(dest_file, "rb")
        header <- rawToChar(readBin(con, "raw", n = 4L))
        close(con)
        header == "%PDF"
      }, error = function(e) FALSE)

      if (!is_pdf || file_size < 1024L) {
        warning(sprintf(
          "download_literature_pdfs: '%s' does not appear to be a valid PDF (size=%d bytes). Skipping.",
          basename(dest_file), file_size
        ), call. = FALSE)
        if (file.exists(dest_file)) file.remove(dest_file)
        n_fail <- n_fail + 1L
      } else {
        catalog$local_pdf_path[i] <- dest_file
        n_success <- n_success + 1L
      }
    } else {
      n_fail <- n_fail + 1L
    }

    Sys.sleep(pause_s)
  }

  if (verbose) {
    message(sprintf(
      "download_literature_pdfs: %d downloaded, %d skipped (already exist), %d failed.",
      n_success, n_skip, n_fail
    ))
    message(sprintf(
      "  %d rows ready for extract_pdf_text().",
      sum(!is.na(catalog$local_pdf_path))
    ))
  }

  catalog
}
