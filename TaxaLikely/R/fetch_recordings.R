# ==============================================================================
# fetch_recordings.R
# TaxaLikely -- Fetch reference recordings from Xeno-canto
#
# Exported functions:
#   fetch_reference_recordings()   Query Xeno-canto for species recordings
#
# Internal helpers (@noRd):
#   .xc_query_all()          Paginate through Xeno-canto API results
#   .xc_standardize_cols()   Rename raw API fields to clean R names
#   .parse_xc_duration()     Parse "m:ss" duration string to seconds
# ==============================================================================

#' @importFrom TaxaTools %||%
NULL


# ==============================================================================
# fetch_reference_recordings()
# ==============================================================================

#' Fetch Reference Recordings from Xeno-canto
#'
#' Queries the Xeno-canto API v3 for bird sound recordings matching a list
#' of species. Returns a metadata table suitable for building a reference set
#' to train a TaxaLikely acoustic likelihood model. Optionally downloads audio
#' files for local BirdNET-Analyzer processing.
#'
#' @param species Character vector. Scientific names to query
#'   (e.g. `c("Turdus migratorius", "Setophaga petechia")`). Each name is
#'   queried separately. Genus-only queries are supported.
#' @param quality Character vector. Xeno-canto quality grades to include:
#'   `"A"` (best) through `"E"` (worst). Default `c("A", "B")`.
#' @param type Character. Recording type filter, e.g. `"song"`, `"call"`,
#'   `"alarm call"`. Default `NULL` (no filter). Xeno-canto type tags are
#'   free-text; common values are `"song"` and `"call"`.
#' @param max_per_species Integer. Maximum recordings to return per species
#'   after quality-sorting (A before B, etc.). Default `50L`.
#' @param api_key Character. Xeno-canto API v3 key. Required. Defaults to the
#'   `XC_API_KEY` environment variable. Every registered XC member with a
#'   verified email address has one; look yours up at
#'   `https://xeno-canto.org/account`.
#' @param download Logical. If `TRUE`, download audio files to `download_dir`.
#'   Default `FALSE` (metadata only).
#' @param download_dir Character. Directory for downloaded audio. Default
#'   `NULL` creates `xeno-canto-recordings/` inside `tempdir()`. Ignored when
#'   `download = FALSE`.
#' @param verbose Logical. Print per-species progress messages. Default `TRUE`.
#'
#' @return A data frame with one row per recording, containing:
#'   \describe{
#'     \item{`recording_id`}{Xeno-canto identifier, e.g. `"XC123456"`.}
#'     \item{`species`}{Scientific binomial (`genus` + species epithet).}
#'     \item{`genus`}{Genus name.}
#'     \item{`common_name`}{English common name.}
#'     \item{`quality`}{Quality grade (`A`–`E`).}
#'     \item{`type`}{Recording type tag (e.g. `"song"`).}
#'     \item{`country`}{Country where recording was made.}
#'     \item{`location`}{Locality description.}
#'     \item{`lat`, `lng`}{Coordinates (numeric; `NA` if absent).}
#'     \item{`duration_s`}{Duration in seconds (parsed from `"m:ss"`).}
#'     \item{`date`}{Recording date (`"YYYY-MM-DD"`).}
#'     \item{`license`}{Creative Commons license URL.}
#'     \item{`file_url`}{Direct download URL for the audio file.}
#'     \item{`also_species`}{Background species in the recording (comma-separated).}
#'     \item{`local_path`}{Local file path if `download = TRUE`; `NA` otherwise.}
#'   }
#'   The `"xc_query"` attribute stores the original `species` argument.
#'
#' @details
#' **Xeno-canto API v3:** Queries the Xeno-canto API v3
#' (<https://xeno-canto.org/api/3/recordings>). An API key is required —
#' register at <https://xeno-canto.org/account> and store your key in the
#' `XC_API_KEY` environment variable (e.g., in `~/.Renviron`). The API
#' returns up to 500 recordings per page; pagination is handled automatically.
#'
#' **Reference training workflow:**
#' 1. Call `fetch_reference_recordings()` to get metadata + download URLs.
#' 2. Download audio files (`download = TRUE`) or use the `file_url` column.
#' 3. Run BirdNET-Analyzer on the downloaded recordings.
#' 4. Read BirdNET output with [TaxaMatch::read_birdnet_output()].
#' 5. Label each detection as H1/H2/H3 by joining BirdNET's identified species
#'    back to the Xeno-canto ground-truth label (via `source_file` /
#'    `local_path`): H1 = correct species, H2 = wrong species (same genus or
#'    close relative in your species list), H3 = wrong genus.
#' 6. Train with [train_likelihood_model()].
#'
#' **Background species:** The `also_species` column lists other species
#' audible in the recording. Consider filtering these out from your training
#' set — a BirdNET detection of a background species is not a false positive
#' in the way you want H2 to represent.
#'
#' **Polite API use:** A 0.5-second delay is inserted between paginated
#' requests. Xeno-canto asks that automated clients not overwhelm the API.
#' For large species lists, run during off-peak hours.
#'
#' @seealso [train_likelihood_model()],
#'   [TaxaMatch::read_birdnet_output()][TaxaMatch::read_birdnet_output]
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Fetch high-quality song recordings for two species (metadata only)
#' recs <- fetch_reference_recordings(
#'   species         = c("Turdus migratorius", "Setophaga petechia"),
#'   quality         = c("A", "B"),
#'   type            = "song",
#'   max_per_species = 30L
#' )
#' head(recs[, c("recording_id", "species", "quality", "duration_s", "file_url")])
#'
#' # Download audio for model training
#' recs <- fetch_reference_recordings(
#'   species      = "Turdus migratorius",
#'   quality      = "A",
#'   download     = TRUE,
#'   download_dir = "reference_audio/"
#' )
#' # Run BirdNET-Analyzer on reference_audio/, then:
#' # TaxaMatch::read_birdnet_output("birdnet_results/")
#' }
fetch_reference_recordings <- function(species,
                                       quality         = c("A", "B"),
                                       type            = NULL,
                                       max_per_species = 50L,
                                       api_key         = Sys.getenv("XC_API_KEY"),
                                       download        = FALSE,
                                       download_dir    = NULL,
                                       verbose         = TRUE) {

  # ---- input validation ------------------------------------------------------
  if (!is.character(species) || length(species) == 0L) {
    stop("fetch_reference_recordings: 'species' must be a non-empty character vector.")
  }
  valid_grades <- c("A", "B", "C", "D", "E")
  quality      <- toupper(trimws(quality))
  bad_q        <- setdiff(quality, valid_grades)
  if (length(bad_q) > 0L) {
    stop(sprintf(
      "fetch_reference_recordings: invalid quality grade(s): %s. Must be A-E.",
      paste(bad_q, collapse = ", ")
    ))
  }
  max_per_species <- as.integer(max_per_species)
  if (is.na(max_per_species) || max_per_species < 1L) {
    stop("fetch_reference_recordings: 'max_per_species' must be a positive integer.")
  }

  if (!requireNamespace("httr2", quietly = TRUE)) {
    stop(
      "fetch_reference_recordings: the 'httr2' package is required.\n",
      "Install with: install.packages('httr2')"
    )
  }

  if (!nzchar(api_key)) {
    stop(
      "fetch_reference_recordings: Xeno-canto API v3 requires an API key.\n",
      "Register at https://xeno-canto.org/account and set:\n",
      "  Sys.setenv(XC_API_KEY = 'your_key')  # or add to ~/.Renviron"
    )
  }

  if (isTRUE(download)) {
    if (is.null(download_dir)) {
      download_dir <- file.path(tempdir(), "xeno-canto-recordings")
    }
    if (!dir.exists(download_dir)) {
      dir.create(download_dir, recursive = TRUE, showWarnings = FALSE)
    }
  }

  # ---- per-species query -----------------------------------------------------
  all_rows <- vector("list", length(species))

  for (i in seq_along(species)) {
    sp <- species[[i]]
    if (verbose) message(sprintf(
      "fetch_reference_recordings [%d/%d]: querying '%s'...",
      i, length(species), sp
    ))

    # Build Xeno-canto v3 query string using structured search tags.
    # v3 requires tags (gen:/sp:) rather than free-text species names.
    words <- strsplit(trimws(sp), "\\s+")[[1L]]
    sp_tags <- if (length(words) >= 2L) {
      paste0("gen:", words[1L], " sp:", words[2L])
    } else {
      paste0("gen:", words[1L])   # genus-only query
    }
    q_clause <- paste(paste0("q:", quality), collapse = " OR ")
    query_str <- paste0(
      sp_tags,
      if (!is.null(type)) paste0(' type:"', type, '"') else "",
      " ", q_clause
    )

    recs <- tryCatch(
      .xc_query_all(query_str, api_key = api_key),
      error = function(e) {
        warning(sprintf(
          "fetch_reference_recordings: query for '%s' failed: %s",
          sp, conditionMessage(e)
        ), call. = FALSE)
        NULL
      }
    )

    if (is.null(recs) || nrow(recs) == 0L) {
      if (verbose) message(sprintf(
        "fetch_reference_recordings: no recordings found for '%s'.", sp
      ))
      next
    }

    # Filter to exact quality grades requested (API OR may over-fetch)
    recs <- recs[recs$quality %in% quality, , drop = FALSE]

    # Sort by quality grade (A best) then apply cap
    grade_rank    <- match(recs$quality, c("A", "B", "C", "D", "E"))
    recs          <- recs[order(grade_rank), , drop = FALSE]
    if (nrow(recs) > max_per_species) {
      recs <- recs[seq_len(max_per_species), , drop = FALSE]
    }

    if (verbose) message(sprintf(
      "fetch_reference_recordings: %d recording(s) selected for '%s'.",
      nrow(recs), sp
    ))

    all_rows[[i]] <- recs
  }

  out <- do.call(rbind, Filter(Negate(is.null), all_rows))

  if (is.null(out) || nrow(out) == 0L) {
    if (verbose) message("fetch_reference_recordings: no recordings found.")
    result <- data.frame()
    attr(result, "xc_query") <- species
    return(invisible(result))
  }

  rownames(out) <- NULL
  out$local_path <- NA_character_

  # ---- download audio if requested -------------------------------------------
  if (isTRUE(download)) {
    n <- nrow(out)
    for (j in seq_len(n)) {
      url  <- out$file_url[j]
      fname <- paste0(
        out$recording_id[j], "_",
        gsub("[^A-Za-z0-9_-]", "_", out$species[j]),
        ".mp3"
      )
      dest <- file.path(download_dir, fname)
      ok   <- tryCatch({
        utils::download.file(url, destfile = dest, quiet = !verbose, mode = "wb")
        TRUE
      }, error = function(e) {
        warning(sprintf(
          "fetch_reference_recordings: failed to download %s: %s",
          out$recording_id[j], conditionMessage(e)
        ), call. = FALSE)
        FALSE
      })
      if (ok) out$local_path[j] <- dest
    }
  }

  attr(out, "xc_query") <- species
  out
}


# ==============================================================================
# Internal helpers
# ==============================================================================

#' Paginate through all Xeno-canto results for a query string
#' @noRd
.xc_query_all <- function(query_str, api_key) {
  base_url <- "https://xeno-canto.org/api/3/recordings"
  all_recs <- list()
  page     <- 1L

  repeat {
    resp <- httr2::request(base_url) |>
      httr2::req_url_query(query = query_str, key = api_key,
                           page = page, per_page = 500L) |>
      httr2::req_error(is_error = function(r) FALSE) |>
      httr2::req_timeout(30L) |>
      httr2::req_perform()

    status <- httr2::resp_status(resp)
    if (status == 401L) {
      stop("Xeno-canto API: invalid or missing API key. ",
           "Check your XC_API_KEY environment variable.")
    }
    if (status != 200L) {
      stop(sprintf(
        "Xeno-canto API returned HTTP %d for query: %s", status, query_str
      ))
    }

    parsed    <- httr2::resp_body_json(resp, simplifyVector = TRUE)
    num_pages <- as.integer(parsed$numPages %||% 1L)
    recs      <- parsed$recordings

    if (!is.null(recs) && length(recs) > 0L) {
      if (!is.data.frame(recs)) {
        recs <- do.call(rbind, lapply(recs, function(r) {
          as.data.frame(lapply(r, function(v) {
            if (length(v) == 0L) NA_character_
            else if (length(v) > 1L) paste(v, collapse = ", ")
            else as.character(v)
          }), stringsAsFactors = FALSE)
        }))
      }
      all_recs[[page]] <- recs
    }

    if (page >= num_pages) break
    page <- page + 1L
    Sys.sleep(0.5)  # polite delay between pages
  }

  if (length(all_recs) == 0L) return(data.frame())

  .xc_standardize_cols(do.call(rbind, all_recs))
}


#' Rename raw Xeno-canto API fields to clean R column names
#' @noRd
.xc_standardize_cols <- function(df) {
  # Map JSON field names (with . from simplifyVector) to clean names
  renames <- c(
    "id"            = "recording_id",
    "gen"           = "genus",
    "ssp"           = "subspecies",
    "en"            = "common_name",
    "rec"           = "recordist",
    "cnt"           = "country",
    "loc"           = "location",
    "type"          = "type",
    "sex"           = "sex",
    "stage"         = "stage",
    "url"           = "xc_url",
    "file"          = "file_url",
    "file.name"     = "file_name",
    "lic"           = "license",
    "q"             = "quality",
    "length"        = "length_raw",
    "date"          = "date",
    "rmk"           = "remarks",
    "bird.seen"     = "bird_seen",
    "playback.used" = "playback_used",
    "also"          = "also_species"
  )

  for (old in names(renames)) {
    new <- renames[[old]]
    if (old %in% names(df) && !new %in% names(df)) {
      names(df)[names(df) == old] <- new
    }
  }

  # species = genus + sp epithet
  if ("genus" %in% names(df) && "sp" %in% names(df)) {
    df$species <- trimws(paste(df$genus, df$sp))
    df$sp      <- NULL
  }

  # Prefix recording_id with "XC"
  if ("recording_id" %in% names(df)) {
    df$recording_id <- paste0("XC", df$recording_id)
  }

  # Parse "m:ss" duration to seconds
  if ("length_raw" %in% names(df)) {
    df$duration_s <- vapply(df$length_raw, .parse_xc_duration, numeric(1L),
                            USE.NAMES = FALSE)
    df$length_raw <- NULL
  }

  # Coerce coordinates to numeric
  for (coord in c("lat", "lng")) {
    if (coord %in% names(df)) {
      df[[coord]] <- suppressWarnings(as.numeric(df[[coord]]))
    }
  }

  # Flatten also_species list-column if present
  if ("also_species" %in% names(df) && is.list(df$also_species)) {
    df$also_species <- vapply(
      df$also_species,
      function(x) if (length(x) == 0L) "" else paste(unlist(x), collapse = ", "),
      character(1L)
    )
  }

  # Canonical column order (extra cols appended)
  core <- c("recording_id", "species", "genus", "common_name", "quality",
            "type", "country", "location", "lat", "lng", "duration_s",
            "date", "license", "file_url", "also_species")
  df[, intersect(c(core, setdiff(names(df), core)), names(df)), drop = FALSE]
}


#' Parse Xeno-canto duration string "m:ss" or "mm:ss" to seconds
#' @noRd
.parse_xc_duration <- function(x) {
  if (is.na(x) || !nzchar(trimws(x))) return(NA_real_)
  parts <- strsplit(trimws(x), ":", fixed = TRUE)[[1L]]
  if (length(parts) == 2L) {
    as.numeric(parts[1L]) * 60 + as.numeric(parts[2L])
  } else {
    suppressWarnings(as.numeric(parts[1L]))
  }
}
