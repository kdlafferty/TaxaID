# ==============================================================================
# score_image_inat.R
# TaxaMatch -- iNaturalist Computer Vision API image scoring
#
# Exported functions:
#   score_image_inat         -- submit image(s) to iNat CV API; return match object
#
# Internal helpers (@noRd):
#   .resolve_image_files     -- resolve single path / vector / directory to file list
#   .path_folder_components  -- extract nested folder levels from image paths
#   .extract_exif_info       -- pull lat/lng/date from image EXIF (requires exifr)
#   .parse_inat_cv_response  -- parse one iNat CV API JSON response to tibble rows
# ==============================================================================

#' Score images using the iNaturalist Computer Vision API
#'
#' Submits one or more images to the iNaturalist CV API and returns a tidy
#' match object with ranked taxon suggestions and associated scores. When
#' latitude/longitude are supplied (via argument or EXIF), \code{combined_score}
#' reflects iNaturalist's geomodel prior; the ratio
#' \code{combined_score / vision_score} (\code{geo_prior_weight}) recovers the
#' implicit geographic prior weight for each taxon at that location.
#'
#' @param image_path Character. Path to a single JPEG or PNG image file, a
#'   character vector of image file paths, or a path to a directory. When a
#'   directory is given, all \code{.jpg}, \code{.jpeg}, and \code{.png} files
#'   (non-recursive) are processed.
#' @param lat Numeric. Latitude in decimal degrees (optional). When supplied,
#'   this value is used for all images and overrides any EXIF-derived latitude.
#'   Must be supplied together with \code{lng}.
#' @param lng Numeric. Longitude in decimal degrees (optional). When supplied,
#'   this value is used for all images and overrides any EXIF-derived longitude.
#'   Must be supplied together with \code{lat}.
#' @param observed_on Character. Observation date in \code{"YYYY-MM-DD"} format
#'   (optional). When supplied, used for all images and overrides EXIF-derived
#'   dates.
#' @param top_n Integer. Number of top taxon suggestions to return per image.
#'   Default \code{10L}.
#' @param recursive Logical. When \code{image_path} is a directory, also scan
#'   subdirectories recursively. Default \code{FALSE}.
#' @param api_token Character. iNaturalist API token. Defaults to the
#'   \code{INAT_API_TOKEN} environment variable. Obtain a token by visiting
#'   \code{https://www.inaturalist.org/users/api_token} while logged in.
#' @return A tibble with up to \code{top_n} rows per image (one per candidate
#'   taxon; some images may return fewer when the API has fewer suggestions),
#'   containing: \code{observation_id} (image filename stem),
#'   \code{taxon_name}, \code{taxon_name_rank}, \code{score_original}
#'   (identical to \code{combined_score}; kept under the canonical pipeline
#'   name for compatibility with \code{evaluate_likelihoods()}),
#'   \code{genus}, \code{common_name}, \code{iconic_taxon_name},
#'   \code{taxon_id}, \code{n_observations} (global iNat observation count for
#'   the taxon — not location-filtered), \code{vision_score},
#'   \code{combined_score}, \code{freq_score},
#'   \code{geo_prior_weight} (\code{combined_score / vision_score}; the
#'   continuous geographic prior signal), \code{lat}, \code{lng},
#'   \code{observed_on} (per-image location/date metadata), and zero or more
#'   \code{folder_1}, \code{folder_2}, \ldots columns encoding the nested
#'   directory levels between the input base path and each image file.
#'   \strong{Score scale:} all score columns are in iNaturalist's 0--100
#'   softmax convention (scores across candidates sum to approximately 100 per
#'   image). Do not rescale to 0--1 before passing to
#'   \code{TaxaLikely::evaluate_likelihoods()}.
#' @details
#' \strong{Score semantics:} \code{vision_score} is the raw image classifier
#' output (discriminative CNN, no location). \code{combined_score} approximates
#' a Bayesian posterior by weighting \code{vision_score} by the geomodel prior
#' (\code{geo_prior_weight}). \code{freq_score} is a thresholded presence
#' indicator from the iNaturalist geomodel and is not a raw frequency. Neither
#' score is a true likelihood in the Bayesian sense; \code{combined_score} is
#' used as \code{score_original} because it is the most informative predictor
#' when location is available.
#'
#' \strong{EXIF extraction:} When \code{lat}, \code{lng}, or \code{observed_on}
#' are \code{NULL}, the function attempts to read these values from each image's
#' EXIF metadata using the \code{exifr} package (if installed). Install with
#' \code{install.packages("exifr")} and ensure ExifTool is available (see
#' \code{?exifr::read_exif}). When \code{exifr} is not available and no
#' arguments are supplied, the API call omits location and date (vision score
#' only; \code{geo_prior_weight = 1}).
#'
#' \strong{Path metadata:} Directory levels between the input base path and
#' each image are output as \code{folder_1}, \code{folder_2}, ... columns.
#' These may encode site, date, treatment, or other study design information
#' embedded in a nested folder hierarchy (e.g.,
#' \code{images/SiteA/2024-06-01/IMG_001.jpg} yields
#' \code{folder_1 = "SiteA"}, \code{folder_2 = "2024-06-01"}).
#'
#' \strong{Taxonomy normalization:} The CV API returns iNaturalist taxonomy.
#' Before feeding the output into \code{join_priors()}, run
#' \code{TaxaMatch::convert_taxonomy_backbone()} to remap iNat names to the
#' GBIF backbone (or your prior backbone). The \code{family} column is not
#' populated here because it is not returned by the CV API; use
#' \code{TaxaTools::fill_higher_ranks()} to add it after backbone normalization.
#'
#' \strong{Authentication:} Tokens expire periodically. If you receive a 401
#' error, regenerate your token at
#' \code{https://www.inaturalist.org/users/api_token}.
#' @seealso [read_inaturalist_cv_output()], [convert_taxonomy_backbone()],
#'   [standardize_match_data()]
#' @export
score_image_inat <- function(
    image_path,
    lat         = NULL,
    lng         = NULL,
    observed_on = NULL,
    top_n       = 10L,
    recursive   = FALSE,
    api_token   = Sys.getenv("INAT_API_TOKEN")
) {

  # ---- validate token --------------------------------------------------------
  if (!nzchar(api_token)) {
    stop(
      "INAT_API_TOKEN is not set. ",
      "Add it to ~/.Renviron or call Sys.setenv(INAT_API_TOKEN = 'your_token'). ",
      "Generate a token at https://www.inaturalist.org/users/api_token."
    )
  }

  # ---- validate lat/lng (must both be present or both absent) ----------------
  has_lat <- !is.null(lat)
  has_lng <- !is.null(lng)
  if (has_lat != has_lng) {
    stop("`lat` and `lng` must both be supplied or both be NULL.")
  }
  if (has_lat) {
    if (!is.numeric(lat) || length(lat) != 1L || is.na(lat))
      stop("`lat` must be a single non-NA numeric value.")
    if (!is.numeric(lng) || length(lng) != 1L || is.na(lng))
      stop("`lng` must be a single non-NA numeric value.")
  }

  # ---- validate observed_on --------------------------------------------------
  if (!is.null(observed_on)) {
    if (!is.character(observed_on) || length(observed_on) != 1L)
      stop("`observed_on` must be a single character string in 'YYYY-MM-DD' format.")
    if (!grepl("^\\d{4}-\\d{2}-\\d{2}$", observed_on))
      stop("`observed_on` must be in 'YYYY-MM-DD' format.")
  }

  # ---- validate top_n --------------------------------------------------------
  top_n <- as.integer(top_n)
  if (is.na(top_n) || top_n < 1L)
    stop("`top_n` must be a positive integer.")

  # ---- resolve image files ---------------------------------------------------
  resolved   <- .resolve_image_files(image_path, recursive = recursive)
  files      <- resolved$files
  base_dir   <- resolved$base_dir

  if (length(files) == 0L) stop("No JPEG or PNG image files found.")

  # ---- path folder components ------------------------------------------------
  folder_df <- .path_folder_components(files, base_dir)

  # ---- process each image ----------------------------------------------------
  all_rows <- vector("list", length(files))

  for (i in seq_along(files)) {
    f      <- files[[i]]
    obs_id <- tools::file_path_sans_ext(basename(f))

    # Resolve per-image lat/lng/date: user arg > EXIF > NULL
    exif_info <- .extract_exif_info(f)
    img_lat  <- if (has_lat)              lat         else exif_info$lat
    img_lng  <- if (has_lat)              lng         else exif_info$lng
    img_date <- if (!is.null(observed_on)) observed_on else exif_info$observed_on

    # Build multipart body: always include image; add optional fields
    body <- list(image = httr::upload_file(f))
    if (!is.na(img_lat)  && !is.null(img_lat))  body$lat         <- img_lat
    if (!is.na(img_lng)  && !is.null(img_lng))  body$lng         <- img_lng
    if (!is.null(img_date) && !is.na(img_date)) body$observed_on <- img_date

    resp <- tryCatch(
      httr::POST(
        url     = "https://api.inaturalist.org/v1/computervision/score_image",
        httr::add_headers(Authorization = paste("Bearer", api_token)),
        body    = body,
        encode  = "multipart"
      ),
      error = function(e) {
        warning(sprintf(
          "score_image_inat: HTTP request failed for '%s': %s",
          basename(f), conditionMessage(e)
        ), call. = FALSE)
        NULL
      }
    )
    Sys.sleep(0.2)  # avoid rate limits on large batches

    if (is.null(resp)) {
      all_rows[[i]] <- NULL
      next
    }

    status <- httr::status_code(resp)
    if (status == 401L) {
      stop(
        "iNaturalist API returned 401 Unauthorized. ",
        "Your INAT_API_TOKEN may be expired or invalid. ",
        "Generate a new token at https://www.inaturalist.org/users/api_token."
      )
    }
    if (status != 200L) {
      warning(sprintf(
        "score_image_inat: API returned HTTP %d for '%s'; skipping.",
        status, basename(f)
      ), call. = FALSE)
      all_rows[[i]] <- NULL
      next
    }

    parsed <- tryCatch(
      httr::content(resp, as = "parsed", type = "application/json"),
      error = function(e) {
        warning(sprintf(
          "score_image_inat: could not parse response for '%s': %s",
          basename(f), conditionMessage(e)
        ), call. = FALSE)
        NULL
      }
    )
    if (is.null(parsed)) {
      all_rows[[i]] <- NULL
      next
    }

    rows <- .parse_inat_cv_response(parsed, top_n = top_n)

    if (nrow(rows) == 0L) {
      all_rows[[i]] <- NULL
      next
    }

    # Attach observation-level metadata
    rows$observation_id <- obs_id
    rows$lat            <- img_lat
    rows$lng            <- img_lng
    rows$observed_on    <- img_date

    # Attach folder columns
    if (ncol(folder_df) > 0L) {
      for (col in names(folder_df)) {
        rows[[col]] <- folder_df[i, col]
      }
    }

    all_rows[[i]] <- rows
  }

  # ---- combine and reorder columns -------------------------------------------
  non_null <- Filter(Negate(is.null), all_rows)
  if (length(non_null) == 0L) {
    message("score_image_inat: no results returned for any image.")
    return(tibble::tibble())
  }

  out <- dplyr::bind_rows(non_null)

  # Canonical column ordering: match object core → taxonomy → scores → metadata
  core_cols   <- c("observation_id", "taxon_name", "taxon_name_rank",
                   "score_original")
  taxon_cols  <- c("genus", "common_name", "iconic_taxon_name", "taxon_id",
                   "n_observations")
  score_cols  <- c("vision_score", "combined_score", "freq_score",
                   "geo_prior_weight")
  meta_cols   <- c("lat", "lng", "observed_on")
  folder_cols <- grep("^folder_\\d+$", names(out), value = TRUE)

  present <- c(core_cols, taxon_cols, score_cols, meta_cols, folder_cols)
  present <- present[present %in% names(out)]
  extra   <- setdiff(names(out), present)

  out[, c(present, extra), drop = FALSE]
}


# ==============================================================================
# Internal: .resolve_image_files
# ==============================================================================

#' Resolve image_path argument to a character vector of image file paths
#'
#' Accepts a single file path, a character vector of file paths, or a directory.
#' Returns a list with \code{files} (character vector) and \code{base_dir}
#' (the common root directory used for folder column derivation).
#' @noRd
.resolve_image_files <- function(image_path, recursive = FALSE) {
  if (!is.character(image_path) || length(image_path) == 0L)
    stop("`image_path` must be a non-empty character vector.")

  img_pattern <- "\\.(jpg|jpeg|png)$"

  if (length(image_path) == 1L && dir.exists(image_path)) {
    # Directory: list image files (recursive if requested)
    base_dir <- normalizePath(image_path, mustWork = TRUE)
    files    <- list.files(base_dir, pattern = img_pattern,
                           full.names = TRUE, recursive = recursive,
                           ignore.case = TRUE)
    if (length(files) == 0L)
      stop(sprintf(
        "score_image_inat: no JPEG or PNG files found in directory '%s'%s.",
        image_path,
        if (recursive) " (recursive)" else " (set recursive = TRUE to scan subdirectories)"
      ))
    return(list(files = files, base_dir = base_dir))
  }

  # Single file or vector of files
  missing_files <- image_path[!file.exists(image_path)]
  if (length(missing_files) > 0L)
    stop(sprintf(
      "score_image_inat: file(s) not found:\n  %s",
      paste(missing_files, collapse = "\n  ")
    ))

  not_image <- image_path[!grepl(img_pattern, image_path, ignore.case = TRUE)]
  if (length(not_image) > 0L)
    stop(sprintf(
      "score_image_inat: only JPEG and PNG files are supported. Not supported:\n  %s",
      paste(not_image, collapse = "\n  ")
    ))

  abs_paths <- normalizePath(image_path, mustWork = TRUE)

  # Base dir: longest common ancestor of all file directories
  dirs      <- unique(dirname(abs_paths))
  base_dir  <- if (length(dirs) == 1L) {
    dirs[[1L]]
  } else {
    # Find longest common path prefix
    parts   <- strsplit(dirs, .Platform$file.sep, fixed = TRUE)
    min_len <- min(vapply(parts, length, integer(1L)))
    common  <- character(0L)
    for (k in seq_len(min_len)) {
      vals <- vapply(parts, `[[`, character(1L), k)
      if (length(unique(vals)) == 1L) common <- c(common, vals[[1L]]) else break
    }
    if (length(common) == 0L) dirname(abs_paths[[1L]]) else
      paste(common, collapse = .Platform$file.sep)
  }

  list(files = abs_paths, base_dir = base_dir)
}


# ==============================================================================
# Internal: .path_folder_components
# ==============================================================================

#' Extract nested folder levels between base_dir and each image as columns
#'
#' Returns a data frame with columns \code{folder_1}, \code{folder_2}, ...
#' representing the directory levels between \code{base_dir} and each image
#' file. Rows shorter than the maximum depth are padded with \code{NA}.
#' Returns an empty data frame when all images sit directly in \code{base_dir}.
#' @noRd
.path_folder_components <- function(files, base_dir) {
  base_norm <- normalizePath(base_dir, mustWork = FALSE)

  rel_dirs <- vapply(files, function(f) {
    abs_dir <- normalizePath(dirname(f), mustWork = FALSE)
    if (startsWith(abs_dir, base_norm)) {
      rel <- substr(abs_dir, nchar(base_norm) + 2L, nchar(abs_dir))
    } else {
      rel <- abs_dir
    }
    rel
  }, character(1L))

  parts_list <- strsplit(rel_dirs, .Platform$file.sep, fixed = TRUE)
  parts_list <- lapply(parts_list, function(p) p[nzchar(p)])

  max_depth <- if (length(parts_list) > 0L)
    max(vapply(parts_list, length, integer(1L)))
  else 0L

  if (max_depth == 0L) return(data.frame())

  mat <- matrix(NA_character_, nrow = length(files), ncol = max_depth)
  for (i in seq_along(parts_list)) {
    n <- length(parts_list[[i]])
    if (n > 0L) mat[i, seq_len(n)] <- parts_list[[i]]
  }

  col_names <- paste0("folder_", seq_len(max_depth))
  as.data.frame(
    stats::setNames(as.data.frame(mat, stringsAsFactors = FALSE), col_names),
    stringsAsFactors = FALSE
  )
}


# ==============================================================================
# Internal: .extract_exif_info
# ==============================================================================

#' Extract latitude, longitude, and date from image EXIF metadata
#'
#' Uses the \code{exifr} package if available. Returns a list with \code{lat},
#' \code{lng}, and \code{observed_on} (all \code{NA} when EXIF is unavailable
#' or the relevant fields are absent).
#' @noRd
.extract_exif_info <- function(path) {
  empty <- list(lat = NA_real_, lng = NA_real_, observed_on = NA_character_)

  if (!requireNamespace("exifr", quietly = TRUE)) return(empty)

  exif <- tryCatch(
    exifr::read_exif(
      path,
      tags = c("GPSLatitude", "GPSLongitude",
               "GPSLatitudeRef", "GPSLongitudeRef",
               "DateTimeOriginal", "CreateDate")
    ),
    error = function(e) NULL
  )
  if (is.null(exif) || nrow(exif) == 0L) return(empty)

  # Latitude (already decimal degrees in exifr output)
  lat_val <- tryCatch(as.numeric(exif$GPSLatitude[[1L]]), error = function(e) NA_real_)
  lat_ref <- tryCatch(as.character(exif$GPSLatitudeRef[[1L]]), error = function(e) NA_character_)
  if (!is.na(lat_val) && identical(lat_ref, "S")) lat_val <- -lat_val

  # Longitude
  lng_val <- tryCatch(as.numeric(exif$GPSLongitude[[1L]]), error = function(e) NA_real_)
  lng_ref <- tryCatch(as.character(exif$GPSLongitudeRef[[1L]]), error = function(e) NA_character_)
  if (!is.na(lng_val) && identical(lng_ref, "W")) lng_val <- -lng_val

  # Date: "YYYY:MM:DD HH:MM:SS" → "YYYY-MM-DD"
  date_str <- tryCatch({
    raw <- if (!is.null(exif$DateTimeOriginal) && !is.na(exif$DateTimeOriginal[[1L]]))
      exif$DateTimeOriginal[[1L]]
    else if (!is.null(exif$CreateDate) && !is.na(exif$CreateDate[[1L]]))
      exif$CreateDate[[1L]]
    else NA_character_
    if (!is.na(raw) && grepl("^\\d{4}:\\d{2}:\\d{2}", raw))
      sub("^(\\d{4}):(\\d{2}):(\\d{2}).*", "\\1-\\2-\\3", raw)
    else NA_character_
  }, error = function(e) NA_character_)

  list(lat = lat_val, lng = lng_val, observed_on = date_str)
}


# ==============================================================================
# Internal: .parse_inat_cv_response
# ==============================================================================

#' Parse iNaturalist CV API JSON response into a match-object tibble
#'
#' Takes the parsed JSON list returned by the iNaturalist CV API and returns
#' a tibble with \code{top_n} rows (or fewer when the API returns fewer
#' results). Does not attach \code{observation_id} — the caller adds that.
#' @noRd
.parse_inat_cv_response <- function(parsed, top_n) {
  results <- parsed[["results"]]
  if (is.null(results) || length(results) == 0L) {
    return(tibble::tibble(
      taxon_name      = character(0),
      taxon_name_rank = character(0),
      score_original  = numeric(0),
      genus           = character(0),
      common_name     = character(0),
      iconic_taxon_name = character(0),
      taxon_id        = integer(0),
      n_observations  = integer(0),
      vision_score    = numeric(0),
      combined_score  = numeric(0),
      freq_score      = numeric(0),
      geo_prior_weight = numeric(0)
    ))
  }

  n_return <- min(length(results), top_n)

  rows <- vector("list", n_return)
  for (i in seq_len(n_return)) {
    r  <- results[[i]]
    tx <- r[["taxon"]]

    vs  <- if (!is.null(r[["vision_score"]]))    as.numeric(r[["vision_score"]])    else NA_real_
    cs  <- if (!is.null(r[["combined_score"]]))  as.numeric(r[["combined_score"]]) else NA_real_
    fs  <- if (!is.null(r[["frequency_score"]])) as.numeric(r[["frequency_score"]]) else NA_real_
    gpw <- if (!is.na(vs) && !is.na(cs) && vs > 0) cs / vs else NA_real_

    nm   <- if (!is.null(tx[["name"]])) as.character(tx[["name"]]) else NA_character_
    rank <- if (!is.null(tx[["rank"]])) tolower(as.character(tx[["rank"]])) else NA_character_
    cn   <- if (!is.null(tx[["preferred_common_name"]])) as.character(tx[["preferred_common_name"]]) else NA_character_
    icon <- if (!is.null(tx[["iconic_taxon_name"]])) as.character(tx[["iconic_taxon_name"]]) else NA_character_
    tid  <- if (!is.null(tx[["id"]])) as.integer(tx[["id"]]) else NA_integer_
    nobs <- if (!is.null(tx[["observations_count"]])) as.integer(tx[["observations_count"]]) else NA_integer_

    # Derive genus from name:
    #   rank == "species"  → first word of binomial
    #   rank == "genus"    → full name
    #   otherwise          → NA
    genus_val <- if (!is.na(nm) && !is.na(rank)) {
      if (identical(rank, "species") && grepl("^[A-Z][a-z]+ [a-z]", nm)) {
        sub("^(\\S+).*", "\\1", nm)
      } else if (identical(rank, "genus")) {
        nm
      } else {
        NA_character_
      }
    } else {
      NA_character_
    }

    rows[[i]] <- tibble::tibble(
      taxon_name        = nm,
      taxon_name_rank   = rank,
      score_original    = cs,
      genus             = genus_val,
      common_name       = cn,
      iconic_taxon_name = icon,
      taxon_id          = tid,
      n_observations    = nobs,
      vision_score      = vs,
      combined_score    = cs,
      freq_score        = fs,
      geo_prior_weight  = gpw
    )
  }

  dplyr::bind_rows(rows)
}
