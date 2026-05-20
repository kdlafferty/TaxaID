utils::globalVariables(c(
  ".get_content_length", ".stream_n_rows", ".parse_streamed_lines",
  ".build_scientific_name", ".apply_dwc_mapping", ".count_in_bbox",
  ".preview_one_entity", ".preview_one_dataset",
  ".detect_preview_joins", ".print_preview_section", ".print_preview_dataset"
))

# ==============================================================================
# dataone_preview.R
# TaxaExpect — lightweight preview of DataONE/EDI datasets before full download
#
# Exported:
#   preview_dataone_occurrences()   Scout datasets: size, taxa, bbox, speed est.
#   print.dataone_preview()         S3 print method — three-section summary
#
# Internal helpers (@noRd):
#   .get_content_length()           HEAD request -> file size in MB (no download)
#   .stream_n_rows()                Stream first n rows without full download
#   .parse_streamed_lines()         Parse streamed lines to tibble
#   .build_scientific_name()        Construct scientificName from genus+epithet
#   .apply_dwc_mapping()            Rename cols to DWC, coerce coordinates
#   .count_in_bbox()                Count rows within bbox
#   .preview_one_entity()           One entity -> one-row summary tibble
#   .detect_preview_joins()         Detect spatial+species pairs; collapse to
#                                   join_ready / join_large rows
#   .preview_one_dataset()          All entities for one dataset ID
#   .print_preview_section()        Print one status section (READY/LARGE/SKIP)
#   .print_preview_dataset()        Print entity rows under one dataset header
#
# Shares helpers from dataone_standardize.R (available after load_all):
#   .parse_eml_metadata(), .map_columns_to_dwc(), .classify_entity(),
#   .attempt_dwc_join(), str_trunc_safe(), .default_dwc_map
#
# Internal operator dependency:
#   %||%  defined in get_keys_from_context.R (package-internal) -- do NOT redefine here
#
# Dependencies (all in TaxaExpect Imports):
#   httr2, dplyr, tibble, stringr, readr, stats
#
# Typical workflow:
#
#   bbox     <- c(-120.5, -119.3, 33.8, 34.5)
#   catalog  <- harvest_dataone_catalog(bbox)
#   prompt   <- build_geo_prompt(catalog, bbox)
#   screened <- parse_geo_screening_response(prompt_api(prompt), prompt)
#   accepted <- screened[screened$geo_match, ]
#   eml      <- screen_eml_columns(accepted$resolved_id, bbox)
#   to_eval  <- dplyr::inner_join(accepted, eml[eml$eml_pass, ], by = "id")
#
#   prev <- preview_dataone_occurrences(to_eval$resolved_id, bbox)
#   print(prev)
#   # Output: three sections (READY / LARGE / SKIPPED), each grouped by dataset
#   # with full dataset title as header and one line per entity/join-pair below.
#
#   # Review sample rows before committing to a large download:
#   prev$sample[[3]]
#
#   # Select datasets to fetch:
#   ready_ids <- prev |>
#     dplyr::filter(status %in% c("ready", "join_ready")) |>
#     dplyr::pull(dataset_id) |> unique()
#
#   large_ids <- prev |>
#     dplyr::filter(status %in% c("large", "join_large"),
#                   grepl("fish|invert", entity_name, ignore.case = TRUE)) |>
#     dplyr::pull(dataset_id) |> unique()
#
#   occ <- fetch_dataone_occurrences(unique(c(ready_ids, large_ids)), bbox)
# ==============================================================================


# ==============================================================================
# Exported: preview_dataone_occurrences
# ==============================================================================

#' Preview DataONE/EDI Datasets Before Full Download
#'
#' For each PASTA dataset ID, fetches EML metadata (fast), issues HEAD requests
#' to obtain file sizes without downloading, then streams only the first
#' \code{n_rows} lines per entity to extract a sample taxon name and check
#' bounding-box coverage. Automatically detects datasets with separate spatial
#' and species tables (DwC Archive star schema) and reports them as joinable
#' pairs rather than independent incomplete entities.
#'
#' Returns a tibble classed \code{"dataone_preview"} with one row per entity
#' or joinable pair. The S3 \code{print} method groups rows into three sections
#' -- READY, LARGE, SKIPPED -- and within each section groups by dataset,
#' printing the full dataset title as a sub-header.
#'
#' @param dataset_ids Character vector. PASTA package identifiers as returned
#'   in the \code{resolved_id} column of \code{\link{screen_eml_columns}}.
#' @param bbox Numeric vector \code{c(west, east, south, north)} or a named
#'   list with elements \code{west}, \code{east}, \code{south}, \code{north}
#'   (decimal degrees).
#' @param n_rows Integer. Number of data rows to stream per entity. Default
#'   \code{20L}.
#' @param large_mb Numeric. File-size threshold (MB) separating
#'   \code{"ready"} from \code{"large"} status. Default \code{50}.
#' @param assume_mbps Numeric. Assumed download speed in MB/s for estimating
#'   download time. PASTA connections are typically 3--10 MB/s. Default
#'   \code{5}.
#' @param extra_dwc_map A \code{data.frame} with columns \code{pattern} and
#'   \code{dwc_term}, prepended before the default map. \code{NULL} (default)
#'   uses the built-in map only.
#' @param verbose Logical. Print per-dataset progress messages. Default
#'   \code{TRUE}.
#'
#' @return A tibble of class \code{c("dataone_preview", "tbl_df", "tbl",
#'   "data.frame")} with one row per entity (or joinable pair) and columns:
#'   \describe{
#'     \item{dataset_id}{PASTA identifier, e.g. \code{"edi.653.8"}.}
#'     \item{dataset_title}{Full dataset title (not truncated).}
#'     \item{entity_name}{Entity (table) name; for joinable pairs formatted as
#'       \code{"entity_A + entity_B"}.}
#'     \item{status}{One of \code{"ready"}, \code{"large"}, \code{"skip"},
#'       \code{"join_ready"}, or \code{"join_large"}. The \code{join_*} values
#'       indicate that \code{\link{fetch_dataone_occurrences}} will join two
#'       tables automatically.}
#'     \item{skip_reason}{Reason string; \code{NA} unless
#'       \code{status == "skip"}.}
#'     \item{file_mb}{File size in MB from \code{Content-Length} header. For
#'       join pairs, the sum of both entity sizes. \code{NA} for chunked
#'       responses.}
#'     \item{est_min}{Estimated download time in minutes. \code{NA} when
#'       \code{file_mb} is \code{NA}.}
#'     \item{coord_source}{\code{"columns"}, \code{"eml_sites"}, or
#'       \code{NA}.}
#'     \item{n_bbox}{Preview rows within \code{bbox}. \code{NA} for
#'       \code{eml_sites} rows (bbox already confirmed by
#'       \code{\link{screen_eml_columns}}).}
#'     \item{join_key}{Join column description for \code{join_*} rows, e.g.
#'       \code{"shared id"} or \code{"event$id <-> occ$eventID"}. \code{NA}
#'       for single-entity rows.}
#'     \item{first_taxon}{Scientific name from the first non-NA sample row.
#'       \code{NA} when no usable rows were streamed.}
#'     \item{large_mb}{The \code{large_mb} threshold used (stored for the
#'       print method).}
#'     \item{sample}{List-column of small preview tibbles (up to
#'       \code{n_rows} rows, DWC-renamed). For join pairs, the joined sample.
#'       Inspect with \code{prev$sample[[i]]}.}
#'   }
#'
#' @details
#' \strong{No full download required:} sizes come from HTTP HEAD requests;
#' only \code{n_rows} lines are streamed per entity.
#'
#' \strong{Join detection:} when a dataset has both a spatial-only and a
#' species-only entity, the function attempts to identify a join key from the
#' sample rows using the same strategies as
#' \code{\link{fetch_dataone_occurrences}}. Detection may fail for sparse
#' samples; \code{fetch_dataone_occurrences} will still attempt the join on
#' the full data regardless.
#'
#' @seealso \code{\link{fetch_dataone_occurrences}},
#'   \code{\link{screen_eml_columns}}, \code{\link{harvest_dataone_catalog}}
#'
#' @importFrom httr2 request req_method req_timeout req_perform
#'   req_perform_stream resp_header
#' @importFrom dplyr bind_rows filter mutate select pull n_distinct rename
#'   any_of
#' @importFrom tibble tibble as_tibble
#' @importFrom stringr str_count str_to_lower str_trim
#' @importFrom readr read_delim
#' @examples
#' \dontrun{
#' preview <- preview_dataone_occurrences(
#'   dataset_ids = candidate_ids,
#'   bbox = c(-120, 34, -119, 35)
#' )
#' print(preview)
#' }
#'
#' @importFrom stats setNames
#' @export
preview_dataone_occurrences <- function(dataset_ids,
                                        bbox,
                                        n_rows        = 20L,
                                        large_mb      = 50,
                                        assume_mbps   = 5,
                                        extra_dwc_map = NULL,
                                        verbose       = TRUE) {

  # ── Input validation ────────────────────────────────────────────────────────
  if (!is.character(dataset_ids) || length(dataset_ids) == 0L) {
    stop("preview_dataone_occurrences: 'dataset_ids' must be a non-empty ",
         "character vector.")
  }
  if (is.numeric(bbox) && length(bbox) == 4L && is.null(names(bbox))) {
    bbox <- list(west  = bbox[1L], east  = bbox[2L],
                 south = bbox[3L], north = bbox[4L])
  }
  if (!is.list(bbox) ||
      !all(c("west", "east", "south", "north") %in% names(bbox))) {
    stop("preview_dataone_occurrences: 'bbox' must be c(west, east, south, ",
         "north) or a named list with those four elements.")
  }
  if (!is.null(extra_dwc_map)) {
    if (!is.data.frame(extra_dwc_map) ||
        !all(c("pattern", "dwc_term") %in% names(extra_dwc_map))) {
      stop("preview_dataone_occurrences: 'extra_dwc_map' must be a data.frame ",
           "with columns 'pattern' and 'dwc_term'.")
    }
  }

  dwc_map <- if (!is.null(extra_dwc_map)) {
    rbind(extra_dwc_map, .default_dwc_map)
  } else {
    .default_dwc_map
  }

  rows <- lapply(dataset_ids, function(id) {
    tryCatch(
      .preview_one_dataset(id, bbox, n_rows, large_mb,
                           assume_mbps, dwc_map, verbose),
      error = function(e) {
        if (verbose) {
          message(sprintf("  preview error on %s: %s", id,
                          conditionMessage(e)))
        }
        NULL
      }
    )
  })

  rows <- Filter(Negate(is.null), rows)

  if (length(rows) == 0L) {
    if (verbose) message("preview_dataone_occurrences: no entities found.")
    return(invisible(NULL))
  }

  out <- dplyr::bind_rows(rows)
  class(out) <- c("dataone_preview", class(out))
  out
}


# ==============================================================================
# S3 print method
# ==============================================================================

#' Print method for dataone_preview objects
#'
#' Renders three sections -- READY, LARGE, SKIPPED. Within each section,
#' datasets are grouped under their full title with entity rows indented below.
#'
#' @param x A \code{dataone_preview} tibble.
#' @param ... Ignored.
#' @return \code{x}, invisibly.
#' @export
print.dataone_preview <- function(x, ...) {
  threshold <- x$large_mb[1L] %||% 50
  n_ds      <- dplyr::n_distinct(x$dataset_id)
  n_ent     <- nrow(x)

  cat(sprintf(
    "\n-- dataone_preview: %d %s across %d %s --\n",
    n_ent, if (n_ent == 1L) "entity" else "entities",
    n_ds,  if (n_ds  == 1L) "dataset" else "datasets"
  ))

  .print_preview_section(
    x[x$status %in% c("ready", "join_ready"), ],
    sprintf("READY (<= %.0f MB)", threshold)
  )
  .print_preview_section(
    x[x$status %in% c("large", "join_large"), ],
    sprintf("LARGE (> %.0f MB or unknown size)", threshold)
  )
  .print_preview_section(
    x[x$status == "skip", ],
    "SKIPPED"
  )

  cat("  Inspect sample rows: prev$sample[[i]]\n\n")
  invisible(x)
}


# ── Print helpers ──────────────────────────────────────────────────────────────

#' Print one status section grouped by dataset
#' @noRd
.print_preview_section <- function(rows, header) {
  rule <- strrep("-", 68L)
  cat(sprintf("\n%s %s\n", header, rule))

  if (nrow(rows) == 0L) {
    cat("  (none)\n")
    return(invisible(NULL))
  }

  is_skip <- all(rows$status == "skip")

  for (did in unique(rows$dataset_id)) {
    ds_rows <- rows[rows$dataset_id == did, ]
    title   <- ds_rows$dataset_title[1L]
    # Full title on its own line — no truncation
    cat(sprintf("\n  [%s]  %s\n", did, title))
    .print_preview_dataset(ds_rows, is_skip)
  }
}


#' Print entity rows for one dataset (indented)
#' @noRd
.print_preview_dataset <- function(ds_rows, is_skip) {
  for (i in seq_len(nrow(ds_rows))) {
    r <- ds_rows[i, ]

    if (is_skip) {
      cat(sprintf("    %-40s  %s\n",
                  str_trunc_safe(r$entity_name, 40L),
                  r$skip_reason %||% ""))
      next
    }

    mb_str   <- if (is.na(r$file_mb))  "    ? MB" else
                  sprintf("%6.1f MB", r$file_mb)
    min_str  <- if (is.na(r$est_min))  "   ? min" else
                  sprintf("%5.1f min", r$est_min)
    csrc     <- r$coord_source %||% "?"
    taxon    <- r$first_taxon  %||% "(taxon unknown)"

    n_samp   <- if (!is.null(r$sample[[1L]])) nrow(r$sample[[1L]]) else 0L
    bbox_str <- if (!is.na(r$n_bbox)) {
      sprintf(" [%d/%d in bbox]", r$n_bbox, n_samp)
    } else ""

    join_str <- if (!is.na(r$join_key %||% NA_character_) &&
                    nzchar(r$join_key %||% "")) {
      sprintf(" [join: %s]", r$join_key)
    } else ""

    cat(sprintf("    %-36s  %s  %s  %-10s  %s%s%s\n",
                str_trunc_safe(r$entity_name, 36L),
                mb_str, min_str, csrc,
                taxon, bbox_str, join_str))
  }
}


# ==============================================================================
# Internal helpers
# ==============================================================================

#' Issue a HEAD request and return Content-Length in MB
#'
#' Returns NA_real_ if the server does not return a Content-Length header
#' (chunked transfer encoding) or the request times out.
#'
#' @noRd
.get_content_length <- function(url) {
  resp <- tryCatch(
    httr2::request(url) |>
      httr2::req_method("HEAD") |>
      httr2::req_timeout(10L) |>
      httr2::req_perform(),
    error = function(e) NULL
  )
  if (is.null(resp)) return(NA_real_)
  cl <- httr2::resp_header(resp, "content-length")
  if (is.null(cl) || is.na(cl) || !nzchar(cl)) return(NA_real_)
  suppressWarnings(as.numeric(cl)) / 1024^2
}


#' Stream the first n data rows from a URL without a full download
#'
#' Accumulates bytes into lines and returns FALSE from the callback once
#' header + n data rows have been received. The connection closes cleanly.
#'
#' @return Named list: lines (header + up to n rows), bytes, seconds.
#'
#' @noRd
.stream_n_rows <- function(url, n) {
  complete_lines <- character(0)
  partial        <- ""
  bytes_rx       <- 0L
  t_start        <- proc.time()[["elapsed"]]

  callback <- function(chunk) {
    bytes_rx   <<- bytes_rx + length(chunk)
    text       <- paste0(partial, rawToChar(chunk))
    parts      <- strsplit(text, "\n", fixed = TRUE)[[1L]]
    if (endsWith(text, "\n")) {
      complete_lines <<- c(complete_lines, parts)
      partial        <<- ""
    } else {
      complete_lines <<- c(complete_lines, parts[-length(parts)])
      partial        <<- parts[length(parts)]
    }
    if (length(complete_lines) >= n + 1L) return(FALSE)
    TRUE
  }

  tryCatch(
    httr2::request(url) |>
      httr2::req_timeout(30L) |>
      httr2::req_perform_stream(callback, buffer_kb = 32L),
    error = function(e) NULL
  )

  list(
    lines   = head(complete_lines, n + 1L),
    bytes   = bytes_rx,
    seconds = max(proc.time()[["elapsed"]] - t_start, 0.001)
  )
}


#' Parse streamed lines to a tibble (mirrors .download_data_table logic)
#'
#' @noRd
.parse_streamed_lines <- function(lines) {
  if (length(lines) < 2L) return(NULL)
  header  <- lines[1L]
  n_tab   <- stringr::str_count(header, "\t")
  n_comma <- stringr::str_count(header, ",")
  delim   <- if (isTRUE(n_tab > n_comma)) "\t" else ","
  text    <- paste(lines, collapse = "\n")
  tryCatch(
    readr::read_delim(text, delim = delim,
                      show_col_types = FALSE, name_repair = "minimal"),
    error = function(e) NULL
  )
}


#' Construct scientificName from genus + specificEpithet where absent
#'
#' Mirrors the logic in .standardize_to_dwc() so preview and fetch agree.
#'
#' @noRd
.build_scientific_name <- function(df) {
  if ("scientificName" %in% names(df)) {
    sn <- as.character(df$scientificName)
    if (!all(is.na(sn))) return(sn)
  }
  has_genus   <- "genus"           %in% names(df)
  has_epithet <- "specificEpithet" %in% names(df)
  if (has_genus && has_epithet) {
    g  <- ifelse(is.na(df$genus),           "", as.character(df$genus))
    e  <- ifelse(is.na(df$specificEpithet), "", as.character(df$specificEpithet))
    sn <- stringr::str_trim(paste(g, e))
    return(ifelse(nzchar(sn), sn, NA_character_))
  }
  if (has_genus) return(as.character(df$genus))
  NA_character_
}


#' Apply DWC mapping to a raw data frame; coerce coordinate columns to numeric
#'
#' @noRd
.apply_dwc_mapping <- function(raw_df, dwc_map) {
  mapping    <- .map_columns_to_dwc(names(raw_df), dwc_map)
  mapped     <- mapping[!is.na(mapping)]
  dwc_to_raw <- tapply(names(mapped), mapped, function(x) x[1L])
  std <- tryCatch(
    dplyr::rename(raw_df, dplyr::any_of(dwc_to_raw)),
    error = function(e) raw_df
  )
  if ("decimalLatitude"  %in% names(std)) {
    std$decimalLatitude  <- suppressWarnings(as.numeric(std$decimalLatitude))
  }
  if ("decimalLongitude" %in% names(std)) {
    std$decimalLongitude <- suppressWarnings(as.numeric(std$decimalLongitude))
  }
  std
}


#' Count rows within bbox; NA when coordinate columns are absent
#'
#' @noRd
.count_in_bbox <- function(df, bbox) {
  if (!all(c("decimalLatitude", "decimalLongitude") %in% names(df))) {
    return(NA_integer_)
  }
  in_box <- !is.na(df$decimalLatitude)  &
            !is.na(df$decimalLongitude) &
            df$decimalLatitude  >= bbox$south &
            df$decimalLatitude  <= bbox$north &
            df$decimalLongitude >= bbox$west  &
            df$decimalLongitude <= bbox$east
  as.integer(sum(in_box))
}


#' Process a single entity and return a one-row summary tibble
#'
#' Species-only entities without EML sites are held as provisional "skip" rows
#' with skip_reason = "species only -- checking for spatial join partner" so
#' that .detect_preview_joins() can upgrade them to join_ready / join_large.
#'
#' @noRd
.preview_one_entity <- function(entity, mapping, meta, eml_sites,
                                bbox, n_rows, large_mb, assume_mbps,
                                dwc_map) {

  ename <- entity$entity_name %||% "(unnamed)"
  title <- meta$title         %||% "(no title)"

  make_skip <- function(reason, file_mb = NA_real_, cat = "unknown") {
    tibble::tibble(
      dataset_id    = meta$id,
      dataset_title = title,
      entity_name   = ename,
      status        = "skip",
      skip_reason   = reason,
      file_mb       = file_mb,
      est_min       = NA_real_,
      coord_source  = NA_character_,
      n_bbox        = NA_integer_,
      join_key      = NA_character_,
      first_taxon   = NA_character_,
      large_mb      = large_mb,
      .entity_cat   = cat,
      sample        = list(NULL)
    )
  }

  cat_entity     <- .classify_entity(mapping)
  has_species    <- cat_entity %in% c("complete", "species_only")
  has_coords_col <- cat_entity %in% c("complete", "spatial_only")
  has_eml_sites  <- nrow(eml_sites) > 0L

  if (cat_entity == "no_coords_no_species") {
    return(make_skip("no species or coordinate columns", cat = cat_entity))
  }
  if (!has_species && !has_coords_col) {
    return(make_skip("no species columns", cat = cat_entity))
  }

  data_url <- entity$data_url
  if (is.na(data_url) || !nzchar(data_url)) {
    return(make_skip("no data URL", cat = cat_entity))
  }

  # HEAD request for file size (fast -- no download)
  file_mb <- .get_content_length(data_url)

  # Stream preview rows
  stream     <- .stream_n_rows(data_url, n_rows)
  raw_sample <- .parse_streamed_lines(stream$lines)

  if (is.null(raw_sample) || nrow(raw_sample) == 0L) {
    if (!has_species) return(make_skip("stream returned no data", cat = cat_entity))
    status <- if (is.na(file_mb) || file_mb > large_mb) "large" else "ready"
    return(tibble::tibble(
      dataset_id    = meta$id,
      dataset_title = title,
      entity_name   = ename,
      status        = status,
      skip_reason   = NA_character_,
      file_mb       = file_mb,
      est_min       = if (is.na(file_mb)) NA_real_ else
                        round(file_mb / assume_mbps / 60, 2),
      coord_source  = if (has_coords_col) "columns"
                      else if (has_eml_sites) "eml_sites"
                      else NA_character_,
      n_bbox        = NA_integer_,
      join_key      = NA_character_,
      first_taxon   = NA_character_,
      large_mb      = large_mb,
      .entity_cat   = cat_entity,
      sample        = list(NULL)
    ))
  }

  std_sample <- .apply_dwc_mapping(raw_sample, dwc_map)

  coord_source <- if (has_coords_col) "columns"
                  else if (has_eml_sites) "eml_sites"
                  else NA_character_
  n_bbox <- if (has_coords_col) .count_in_bbox(std_sample, bbox) else NA_integer_

  sci_names   <- .build_scientific_name(std_sample)
  non_na      <- sci_names[!is.na(sci_names) & nzchar(sci_names)]
  first_taxon <- if (length(non_na) > 0L) non_na[1L] else NA_character_

  # Species-only without eml_sites: hold for join detection
  if (has_species && !has_coords_col && !has_eml_sites) {
    return(tibble::tibble(
      dataset_id    = meta$id,
      dataset_title = title,
      entity_name   = ename,
      status        = "skip",
      skip_reason   = "species only -- checking for spatial join partner",
      file_mb       = file_mb,
      est_min       = if (is.na(file_mb)) NA_real_ else
                        round(file_mb / assume_mbps / 60, 2),
      coord_source  = NA_character_,
      n_bbox        = NA_integer_,
      join_key      = NA_character_,
      first_taxon   = first_taxon,
      large_mb      = large_mb,
      .entity_cat   = cat_entity,
      sample        = list(tibble::as_tibble(std_sample))
    ))
  }

  status <- if (is.na(file_mb) || file_mb > large_mb) "large" else "ready"

  tibble::tibble(
    dataset_id    = meta$id,
    dataset_title = title,
    entity_name   = ename,
    status        = status,
    skip_reason   = NA_character_,
    file_mb       = file_mb,
    est_min       = if (is.na(file_mb)) NA_real_ else
                      round(file_mb / assume_mbps / 60, 2),
    coord_source  = coord_source,
    n_bbox        = n_bbox,
    join_key      = NA_character_,
    first_taxon   = first_taxon,
    large_mb      = large_mb,
    .entity_cat   = cat_entity,
    sample        = list(tibble::as_tibble(std_sample))
  )
}


#' Detect spatial+species entity pairs and replace with combined join rows
#'
#' Attempts to identify a join key from the streamed sample rows using the
#' same four strategies as .attempt_dwc_join(). On success, replaces the two
#' individual rows with a single "join_ready" or "join_large" row. Individual
#' rows that formed a successful pair are removed. Unmatched species_only rows
#' receive an updated skip_reason.
#'
#' @noRd
.detect_preview_joins <- function(entity_rows, large_mb, assume_mbps, bbox) {

  if (is.null(entity_rows) || nrow(entity_rows) == 0L) return(entity_rows)

  cats    <- entity_rows$.entity_cat
  sp_idx  <- which(cats == "spatial_only")
  occ_idx <- which(cats == "species_only")

  if (length(sp_idx) == 0L || length(occ_idx) == 0L) {
    # No join possible -- update any pending species_only messages
    pending <- which(
      cats == "species_only" &
      !is.na(entity_rows$skip_reason) &
      entity_rows$skip_reason == "species only -- checking for spatial join partner"
    )
    entity_rows$skip_reason[pending] <-
      "species only -- no spatial join partner found"
    return(entity_rows)
  }

  joined_sp  <- integer(0)
  joined_occ <- integer(0)
  new_rows   <- list()

  for (si in sp_idx) {
    for (oi in occ_idx) {
      if (oi %in% joined_occ) next

      sp_sample  <- entity_rows$sample[[si]]
      occ_sample <- entity_rows$sample[[oi]]
      if (is.null(sp_sample) || is.null(occ_sample)) next

      merged_sample <- tryCatch(
        .attempt_dwc_join(sp_sample, occ_sample, verbose = FALSE),
        error = function(e) NULL
      )
      if (is.null(merged_sample)) next

      # Re-detect key label (mirrors .attempt_dwc_join strategy order)
      join_label <- .detect_join_label(sp_sample, occ_sample)

      mb_a <- entity_rows$file_mb[si]
      mb_b <- entity_rows$file_mb[oi]
      combined_mb  <- if (!is.na(mb_a) && !is.na(mb_b)) mb_a + mb_b
                      else NA_real_
      combined_min <- if (!is.na(combined_mb)) {
        round(combined_mb / assume_mbps / 60, 2)
      } else NA_real_

      sci         <- .build_scientific_name(merged_sample)
      non_na      <- sci[!is.na(sci) & nzchar(sci)]
      first_taxon <- if (length(non_na) > 0L) non_na[1L] else NA_character_
      n_bbox      <- .count_in_bbox(merged_sample, bbox)
      join_status <- if (is.na(combined_mb) || combined_mb > large_mb) {
        "join_large"
      } else {
        "join_ready"
      }

      new_rows[[length(new_rows) + 1L]] <- tibble::tibble(
        dataset_id    = entity_rows$dataset_id[si],
        dataset_title = entity_rows$dataset_title[si],
        entity_name   = paste0(entity_rows$entity_name[si], " + ",
                               entity_rows$entity_name[oi]),
        status        = join_status,
        skip_reason   = NA_character_,
        file_mb       = combined_mb,
        est_min       = combined_min,
        coord_source  = "columns",
        n_bbox        = n_bbox,
        join_key      = join_label,
        first_taxon   = first_taxon,
        large_mb      = large_mb,
        .entity_cat   = "complete",
        sample        = list(tibble::as_tibble(merged_sample))
      )

      joined_sp  <- c(joined_sp,  si)
      joined_occ <- c(joined_occ, oi)
      break  # each spatial entity joins at most one species entity
    }
  }

  remove_idx <- c(joined_sp, joined_occ)
  kept <- entity_rows[setdiff(seq_len(nrow(entity_rows)), remove_idx), ]

  # Update remaining unmatched species_only rows
  still_pending <- which(
    kept$.entity_cat == "species_only" &
    !is.na(kept$skip_reason) &
    kept$skip_reason == "species only -- checking for spatial join partner"
  )
  kept$skip_reason[still_pending] <- "species only -- no key found for spatial join"

  if (length(new_rows) > 0L) {
    dplyr::bind_rows(kept, dplyr::bind_rows(new_rows))
  } else {
    kept
  }
}


#' Re-detect join key label from two sample data frames (no side effects)
#'
#' Mirrors the four strategies in .attempt_dwc_join() but only returns the
#' label string of the best candidate rather than performing the join.
#'
#' @noRd
.detect_join_label <- function(sp_sample, occ_sample) {
  s_lower <- tolower(names(sp_sample))
  o_lower <- tolower(names(occ_sample))

  n_overlap <- function(a, b) {
    length(intersect(as.character(a), as.character(b)))
  }
  cardinality <- function(col) {
    length(unique(col)) / max(length(col), 1L)
  }

  candidates <- list()

  if ("id" %in% s_lower && "id" %in% o_lower) {
    sk <- names(sp_sample)[s_lower  == "id"][1L]
    ok <- names(occ_sample)[o_lower == "id"][1L]
    if (n_overlap(sp_sample[[sk]], occ_sample[[ok]]) > 0L) {
      candidates[["shared_id"]] <- list(
        label = "shared id", card = cardinality(sp_sample[[sk]]))
    }
  }
  if ("id" %in% s_lower && "eventid" %in% o_lower) {
    sk <- names(sp_sample)[s_lower  == "id"][1L]
    ok <- names(occ_sample)[o_lower == "eventid"][1L]
    if (n_overlap(sp_sample[[sk]], occ_sample[[ok]]) > 0L) {
      candidates[["asymmetric"]] <- list(
        label = "event$id <-> occ$eventID",
        card  = cardinality(sp_sample[[sk]]))
    }
  }
  if ("eventid" %in% s_lower && "eventid" %in% o_lower) {
    sk <- names(sp_sample)[s_lower  == "eventid"][1L]
    ok <- names(occ_sample)[o_lower == "eventid"][1L]
    if (n_overlap(sp_sample[[sk]], occ_sample[[ok]]) > 0L) {
      candidates[["shared_eventid"]] <- list(
        label = "shared eventID", card = cardinality(sp_sample[[sk]]))
    }
  }
  s_eid <- names(sp_sample)[grepl("event.?id",  s_lower, perl = TRUE)]
  o_eid <- names(occ_sample)[grepl("event.?id", o_lower, perl = TRUE)]
  for (k in intersect(tolower(s_eid), tolower(o_eid))) {
    if (k %in% c("id", "eventid")) next
    sk <- names(sp_sample)[s_lower  == k][1L]
    ok <- names(occ_sample)[o_lower == k][1L]
    if (n_overlap(sp_sample[[sk]], occ_sample[[ok]]) > 0L) {
      candidates[[paste0("shared_", k)]] <- list(
        label = paste0("shared ", k), card = cardinality(sp_sample[[sk]]))
    }
  }

  if (length(candidates) == 0L) return(NA_character_)
  candidates[[which.max(vapply(candidates, `[[`, 0, "card"))]]$label
}


#' Process all entities for one dataset ID, then detect join pairs
#'
#' @noRd
.preview_one_dataset <- function(dataset_id, bbox, n_rows, large_mb,
                                 assume_mbps, dwc_map, verbose) {

  if (verbose) {
    message(sprintf("\nPreviewing: %s", str_trunc_safe(dataset_id, 70L)))
  }

  meta <- .parse_eml_metadata(dataset_id)
  if (is.null(meta)) return(NULL)

  if (verbose) {
    message(sprintf("  Title   : %s", meta$title %||% "(none)"))
    message(sprintf("  Entities: %d", length(meta$entities)))
  }

  entity_rows <- lapply(meta$entities, function(entity) {
    ename     <- entity$entity_name %||% "(unnamed)"
    col_names <- entity$attributes$attributeName
    if (length(col_names) == 0L || all(is.na(col_names))) col_names <- character(0)
    mapping   <- if (length(col_names) > 0L) {
      .map_columns_to_dwc(col_names, dwc_map)
    } else {
      character(0)
    }

    if (verbose) {
      message(sprintf("  Entity  : %s", str_trunc_safe(ename, 60L)))
    }

    tryCatch(
      .preview_one_entity(entity, mapping, meta, meta$sites,
                          bbox, n_rows, large_mb, assume_mbps, dwc_map),
      error = function(e) {
        if (verbose) {
          message(sprintf("    preview error: %s", conditionMessage(e)))
        }
        NULL
      }
    )
  })

  entity_rows <- Filter(Negate(is.null), entity_rows)
  if (length(entity_rows) == 0L) return(NULL)

  combined <- dplyr::bind_rows(entity_rows)

  # Detect and collapse spatial+species pairs into join rows
  combined <- .detect_preview_joins(combined, large_mb, assume_mbps, bbox)

  # Drop the internal helper column before returning
  combined[, setdiff(names(combined), ".entity_cat"), drop = FALSE]
}