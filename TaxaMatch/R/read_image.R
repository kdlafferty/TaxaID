# ==============================================================================
# read_image.R
# TaxaMatch -- Ingest image classifier output into the match object format
#
# Exported functions:
#   read_animl_output()              Ingest Animl (camera trap) CSV results
#   read_inaturalist_cv_output()     Ingest iNaturalist CV API JSON responses
#   read_wildlife_insights_output()  Ingest SpeciesNet / Wildlife Insights JSON
#
# Internal helpers (@noRd):
#   .parse_animl_file()         Read and validate a single Animl CSV
#   .pivot_wide_animl()         Pivot pred1/score1...predN/scoreN to long format
#   .parse_inat_cv_file()       Parse one iNaturalist CV JSON file
#   .parse_wi_predictions()     Parse SpeciesNet/Wildlife Insights JSON
# ==============================================================================


# ==============================================================================
# read_animl_output
# ==============================================================================

#' Read Animl Camera Trap Results into a Match Object
#'
#' Reads one or more Animl (MegaDetector + SpeciesNet) result CSV files and
#' returns a tidy data frame in match object format, ready for
#' [standardize_match_data()] and downstream TaxaLikely processing.
#'
#' @param files Character vector. Paths to Animl result CSV files. Alternatively,
#'   a path to a directory: all `*.csv` files in that directory (non-recursive)
#'   are read.
#' @param file_col Character. Name of the column containing the image file path
#'   or filename. Default `"FileName"` (Animl R package manifest format).
#' @param species_col Character. Name of the column containing the species
#'   prediction (scientific name). Default `"prediction"`. For wide-format
#'   outputs (multiple candidates per row), set `n_candidates` and this
#'   argument becomes the prefix (e.g., `"pred"` for `pred1`, `pred2`, ...).
#' @param score_col Character. Name of the confidence column. Default
#'   `"confidence"`. For wide-format outputs, this is used as the prefix
#'   (e.g., `"score"` for `score1`, `score2`, ...).
#' @param common_name_col Character or `NULL`. Name of a common name column,
#'   if present. Default `NULL` (common name column set to `NA`).
#' @param n_candidates Integer or `NULL`. If `NULL` (default), expects
#'   **long format** — one row per image × candidate species, with `species_col`
#'   and `score_col` holding the prediction and confidence directly. If a
#'   positive integer, expects **wide format** — one row per image crop with
#'   candidate columns named `paste0(species_col, 1:n_candidates)` and
#'   `paste0(score_col, 1:n_candidates)` (e.g., `pred1`/`score1` through
#'   `pred3`/`score3`). The wide format is pivoted to long before filtering.
#' @param min_confidence Numeric. Detections below this confidence are dropped.
#'   Default `0` (keep all).
#' @param top_n Integer or `NULL`. If supplied, only the top `n` candidates
#'   (by confidence) within each image are retained. Default `NULL` (keep all).
#' @param bbox_cols Character vector of length 2 or `NULL`. Names of the
#'   bounding-box **width** and **height** columns (normalized 0--1, as output
#'   by MegaDetector).  Supply as a named vector
#'   `c(w = "bbox_w", h = "bbox_h")` or positionally `c("bbox_w", "bbox_h")`.
#'   When provided, `coverage = bbox_w * bbox_h` is computed and added to the
#'   output; this area fraction serves as an image-quality analog to BLAST
#'   `qcovs` and is accepted by `TaxaLikely::evaluate_likelihoods(min_coverage=)`.
#'   Default `NULL` (no coverage column).
#'
#' @return A data frame with one row per image × candidate species, containing:
#'   \describe{
#'     \item{`observation_id`}{Unique identifier derived from the image filename
#'       stem (path stripped, extension(s) stripped). Multiple rows with the
#'       same `observation_id` represent alternative species candidates for the
#'       same image/crop — analogous to multiple BLAST hits per eDNA query or
#'       multiple BirdNET candidates per time window.}
#'     \item{`score`}{Animl classifier confidence (0–1). Pass as `score_col`
#'       to [standardize_match_data()].}
#'     \item{`species`}{Species prediction as reported by Animl. May be
#'       `"empty"` (no animal detected), `"human"`, or `"vehicle"` for
#'       non-wildlife detections — filter these out before proceeding.}
#'     \item{`genus`}{Genus name (first word of `species`). `NA` for
#'       non-binomial labels such as `"empty"`.}
#'     \item{`common_name`}{Common name from `common_name_col`, or `NA` if
#'       that column is absent.}
#'     \item{`source_file`}{Basename of the source CSV file.}
#'   }
#'
#' @details
#' **Animl output formats:** The Animl R package
#' (`animl` on CRAN; wraps MegaDetector + SpeciesNet) supports multiple export
#' formats. Two are handled here:
#'
#' *Long format* (default, `n_candidates = NULL`): one row per image crop ×
#' candidate species. Columns: `FileName`, `prediction`, `confidence`. This
#' is the format produced when you export classification results row-by-row.
#'
#' *Wide format* (`n_candidates = 3`): one row per image crop with top-N
#' candidates in columns `pred1`/`score1`, `pred2`/`score2`, `pred3`/`score3`.
#' Pass `species_col = "pred"`, `score_col = "score"`, `n_candidates = 3`.
#'
#' **Filtering non-wildlife detections:** Animl assigns non-animal labels
#' (`"empty"`, `"human"`, `"vehicle"`) to images with no wildlife. Filter
#' these before standardizing:
#' ```r
#' match_df <- read_animl_output("animl_results/") |>
#'   dplyr::filter(!species %in% c("empty", "human", "vehicle"))
#' ```
#'
#' **observation_id encoding:** Each image (or bounding box crop, if cropped
#' images are used) is one `observation_id`. Multiple species candidates for
#' the same image share the same `observation_id`, enabling TaxaLikely's gap
#' metric (top-1 minus top-2 confidence) to operate correctly.
#'
#' **Taxonomy:** `genus` is derived as the first word of the species column.
#' For the full taxonomic hierarchy (family, order), run
#' [TaxaTools::verify_taxon_names()] on the `species` column after filtering,
#' then re-run [standardize_match_data()].
#'
#' **Downstream workflow:**
#' ```r
#' match_df <- read_animl_output("animl_results/", min_confidence = 0.5) |>
#'   dplyr::filter(!species %in% c("empty", "human", "vehicle")) |>
#'   standardize_match_data(
#'     observation_id_col = "observation_id",
#'     score_col          = "score",
#'     rank_system        = c("genus", "species")
#'   )
#' ```
#'
#' @seealso [standardize_match_data()]
#'
#' @export
#'
#' @examples
#' # Long-format Animl output (one row per image x candidate)
#' tmp <- tempfile(fileext = ".csv")
#' write.csv(data.frame(
#'   FileName   = c("img001.jpg", "img001.jpg", "img002.jpg"),
#'   prediction = c("Odocoileus virginianus", "Cervus canadensis", "empty"),
#'   confidence = c(0.93, 0.05, 0.99),
#'   stringsAsFactors = FALSE
#' ), tmp, row.names = FALSE)
#'
#' result <- read_animl_output(tmp)
#' head(result)
#' unlink(tmp)
read_animl_output <- function(files,
                               file_col        = "FileName",
                               species_col     = "prediction",
                               score_col       = "confidence",
                               common_name_col = NULL,
                               n_candidates    = NULL,
                               min_confidence  = 0,
                               top_n           = NULL,
                               bbox_cols       = NULL) {

  # ---- validate inputs -------------------------------------------------------
  if (!is.character(files) || length(files) == 0L) {
    stop(
      "read_animl_output: 'files' must be a non-empty character vector of ",
      "file paths or a single directory path."
    )
  }
  if (!is.character(file_col) || length(file_col) != 1L)
    stop("read_animl_output: 'file_col' must be a length-1 character string.")
  if (!is.character(species_col) || length(species_col) != 1L)
    stop("read_animl_output: 'species_col' must be a length-1 character string.")
  if (!is.character(score_col) || length(score_col) != 1L)
    stop("read_animl_output: 'score_col' must be a length-1 character string.")
  if (!is.null(common_name_col) &&
      (!is.character(common_name_col) || length(common_name_col) != 1L))
    stop("read_animl_output: 'common_name_col' must be a length-1 character string or NULL.")
  if (!is.null(n_candidates)) {
    n_candidates <- as.integer(n_candidates)
    if (is.na(n_candidates) || n_candidates < 1L)
      stop("read_animl_output: 'n_candidates' must be a positive integer or NULL.")
  }
  if (!is.numeric(min_confidence) || length(min_confidence) != 1L ||
      is.na(min_confidence))
    stop("read_animl_output: 'min_confidence' must be a length-1 numeric.")
  if (!is.null(top_n)) {
    top_n <- as.integer(top_n)
    if (is.na(top_n) || top_n < 1L)
      stop("read_animl_output: 'top_n' must be a positive integer or NULL.")
  }
  if (!is.null(bbox_cols)) {
    if (!is.character(bbox_cols) || length(bbox_cols) != 2L)
      stop("read_animl_output: 'bbox_cols' must be a length-2 character vector, e.g. c(w = 'bbox_w', h = 'bbox_h').")
  }

  # ---- resolve directory vs file list ----------------------------------------
  if (length(files) == 1L && dir.exists(files)) {
    files <- list.files(files, pattern = "\\.csv$",
                        full.names = TRUE, recursive = FALSE,
                        ignore.case = TRUE)
    if (length(files) == 0L) {
      stop("read_animl_output: no *.csv files found in directory.")
    }
  } else {
    missing_files <- files[!file.exists(files)]
    if (length(missing_files) > 0L) {
      stop(sprintf(
        "read_animl_output: file(s) not found:\n  %s",
        paste(missing_files, collapse = "\n  ")
      ))
    }
  }

  # ---- read each file --------------------------------------------------------
  rows <- vector("list", length(files))
  for (i in seq_along(files)) {
    rows[[i]] <- .parse_animl_file(
      files[[i]],
      file_col        = file_col,
      species_col     = species_col,
      score_col       = score_col,
      common_name_col = common_name_col,
      n_candidates    = n_candidates,
      bbox_cols       = bbox_cols
    )
  }
  out <- do.call(rbind, rows)

  # ---- apply filters ---------------------------------------------------------
  out <- out[!is.na(out$score) & out$score >= min_confidence, , drop = FALSE]

  if (!is.null(top_n)) {
    out <- do.call(rbind, lapply(split(out, out$observation_id), function(g) {
      g[order(g$score, decreasing = TRUE), ][seq_len(min(nrow(g), top_n)), ,
                                              drop = FALSE]
    }))
    rownames(out) <- NULL
  }

  out
}


# ==============================================================================
# Internal: .parse_animl_file
# ==============================================================================

#' Parse a single Animl result CSV into a match-ready data frame
#' @param f Character. Path to a single Animl CSV file.
#' @param file_col,species_col,score_col,common_name_col,n_candidates,bbox_cols
#'   Forwarded from [read_animl_output()].
#' @return Data frame with canonical match columns.
#' @noRd
.parse_animl_file <- function(f, file_col, species_col, score_col,
                               common_name_col, n_candidates,
                               bbox_cols = NULL) {

  df <- tryCatch(
    utils::read.csv(f, check.names = FALSE, stringsAsFactors = FALSE),
    error = function(e) {
      stop(sprintf("read_animl_output: could not read '%s': %s",
                   basename(f), conditionMessage(e)))
    }
  )

  # ---- check file_col --------------------------------------------------------
  if (!file_col %in% names(df)) {
    stop(sprintf(
      paste0(
        "read_animl_output: file '%s' is missing required column '%s'.\n",
        "Set 'file_col' to match your Animl export (e.g., file_col = \"FilePath\")."
      ),
      basename(f), file_col
    ))
  }

  # ---- wide vs long ----------------------------------------------------------
  if (!is.null(n_candidates)) {
    df <- .pivot_wide_animl(df, f, file_col, species_col, score_col,
                             common_name_col, n_candidates)
    # After pivot, columns are named "file_col", "species_col", "score_col",
    # "common_name_col" with the actual column values renamed to standard names
    # below.
    species_actual     <- ".animl_species"
    score_actual       <- ".animl_score"
    common_name_actual <- ".animl_common_name"
  } else {
    # Long format: columns must exist directly
    missing_cols <- setdiff(
      c(file_col, species_col, score_col),
      names(df)
    )
    if (length(missing_cols) > 0L) {
      stop(sprintf(
        paste0(
          "read_animl_output: file '%s' is missing column(s): %s\n",
          "Check 'file_col', 'species_col', 'score_col' arguments, or use ",
          "'n_candidates' for wide-format files."
        ),
        basename(f), paste(missing_cols, collapse = ", ")
      ))
    }
    species_actual     <- species_col
    score_actual       <- score_col
    common_name_actual <- if (!is.null(common_name_col) &&
                               common_name_col %in% names(df))
      common_name_col else NULL
  }

  if (nrow(df) == 0L) {
    message(sprintf(
      "read_animl_output: '%s' has no detections (empty file).", basename(f)
    ))
    return(data.frame(
      observation_id = character(0),
      score          = numeric(0),
      species        = character(0),
      genus          = character(0),
      common_name    = character(0),
      source_file    = character(0),
      stringsAsFactors = FALSE
    ))
  }

  # ---- build observation_id from image filename stem -------------------------
  img_paths <- trimws(as.character(df[[file_col]]))
  # Strip all extensions (handles .jpg, .JPG, .tif, .tiff, etc.)
  img_stem  <- tools::file_path_sans_ext(basename(img_paths))

  species_vals <- trimws(as.character(df[[species_actual]]))
  score_vals   <- suppressWarnings(as.numeric(df[[score_actual]]))
  common_vals  <- if (!is.null(common_name_actual))
    trimws(as.character(df[[common_name_actual]])) else rep(NA_character_, nrow(df))

  # Derive genus: first word of species binomial; NA for non-binomial labels
  genus_vals <- ifelse(
    grepl("^[A-Z][a-z]+ [a-z]", species_vals),
    sub("^(\\S+).*", "\\1", species_vals),
    NA_character_
  )

  # Compute coverage from bounding box area (optional) -------------------------
  # bbox_w * bbox_h gives the fractional area of the image occupied by the
  # detection crop (0-1).  A small fraction = distant/partial animal = weaker
  # classification evidence.  Analogous to BLAST qcovs for DNA sequences.
  coverage_vals <- if (!is.null(bbox_cols)) {
    w_col <- if (!is.null(names(bbox_cols)) && "w" %in% names(bbox_cols))
      bbox_cols[["w"]] else bbox_cols[[1L]]
    h_col <- if (!is.null(names(bbox_cols)) && "h" %in% names(bbox_cols))
      bbox_cols[["h"]] else bbox_cols[[2L]]
    if (!w_col %in% names(df) || !h_col %in% names(df)) {
      warning(sprintf(
        "read_animl_output: bbox_cols '%s'/'%s' not found in '%s'; coverage set to NA.",
        w_col, h_col, basename(f)
      ), call. = FALSE)
      rep(NA_real_, nrow(df))
    } else {
      suppressWarnings(as.numeric(df[[w_col]]) * as.numeric(df[[h_col]]))
    }
  } else {
    NULL
  }

  out_df <- data.frame(
    observation_id = img_stem,
    score          = score_vals,
    species        = species_vals,
    genus          = genus_vals,
    common_name    = common_vals,
    source_file    = basename(f),
    stringsAsFactors = FALSE
  )
  if (!is.null(coverage_vals)) out_df$coverage <- coverage_vals
  out_df
}


# ==============================================================================
# Internal: .pivot_wide_animl
# ==============================================================================

#' Pivot wide Animl format (pred1/score1 ... predN/scoreN) to long format
#' @noRd
.pivot_wide_animl <- function(df, f, file_col, species_prefix, score_prefix,
                               common_name_col, n_candidates) {

  # Build expected column names
  pred_cols  <- paste0(species_prefix, seq_len(n_candidates))
  score_cols <- paste0(score_prefix,   seq_len(n_candidates))

  missing_pred  <- setdiff(pred_cols,  names(df))
  missing_score <- setdiff(score_cols, names(df))
  if (length(missing_pred) > 0L || length(missing_score) > 0L) {
    stop(sprintf(
      paste0(
        "read_animl_output: wide-format file '%s' is missing column(s): %s\n",
        "Expected columns like '%s1'/'%s1' through '%s%d'/'%s%d'."
      ),
      basename(f),
      paste(c(missing_pred, missing_score), collapse = ", "),
      species_prefix, score_prefix,
      species_prefix, n_candidates, score_prefix, n_candidates
    ))
  }

  # Pivot: replicate each row n_candidates times
  n_rows  <- nrow(df)
  indices <- rep(seq_len(n_rows), times = n_candidates)

  long <- df[indices, , drop = FALSE]
  rownames(long) <- NULL

  long[[".animl_species"]] <- unlist(
    lapply(seq_len(n_candidates), function(k) df[[pred_cols[k]]]),
    use.names = FALSE
  )
  long[[".animl_score"]] <- unlist(
    lapply(seq_len(n_candidates), function(k) df[[score_cols[k]]]),
    use.names = FALSE
  )
  if (!is.null(common_name_col) && common_name_col %in% names(df)) {
    long[[".animl_common_name"]] <- long[[common_name_col]]
  } else {
    long[[".animl_common_name"]] <- NA_character_
  }

  # Drop rows where prediction is NA or empty string (unfilled wide slots)
  keep <- !is.na(long[[".animl_species"]]) & nzchar(trimws(long[[".animl_species"]]))
  long[keep, , drop = FALSE]
}


# ==============================================================================
# read_inaturalist_cv_output
# ==============================================================================

#' Read iNaturalist Computer Vision API Results into a Match Object
#'
#' Reads one or more saved JSON files from the iNaturalist computer vision API
#' and returns a tidy data frame in match object format, ready for
#' [standardize_match_data()] and downstream TaxaLikely processing.
#'
#' Each JSON file should be the raw API response for one image, saved to disk
#' after calling the iNaturalist API endpoint
#' `POST https://api.inaturalist.org/v2/computervision/score_image`.
#' See the `@details` section for a minimal API call example.
#'
#' @param files Character vector. Paths to iNaturalist CV JSON files.
#'   Alternatively, a path to a directory: all `*.json` files in that
#'   directory (non-recursive) are read.
#' @param score_type Character. Which score to use from the API response.
#'   `"combined_score"` (default) incorporates community identification
#'   frequency and is generally more calibrated. `"score"` is the raw
#'   computer-vision softmax score.
#' @param min_confidence Numeric. Detections below this score are dropped.
#'   Default `0` (keep all).
#' @param top_n Integer or `NULL`. If supplied, only the top `n` candidates
#'   (by score) within each image are retained. Default `NULL` (keep all).
#'
#' @return A data frame with one row per image x candidate taxon, containing:
#'   \describe{
#'     \item{`observation_id`}{Unique identifier derived from the JSON filename
#'       stem (the name you gave the saved response file, ideally the image
#'       filename stem).}
#'     \item{`score`}{iNaturalist CV score (0--1) as selected by
#'       `score_type`.}
#'     \item{`species`}{Scientific name (binomial) if the API returned a
#'       species-rank taxon; coarser name otherwise.}
#'     \item{`genus`}{Genus name (first word of `species`). `NA` for
#'       non-binomial labels.}
#'     \item{`common_name`}{Common name from the API response, or `NA`.}
#'     \item{`taxon_rank`}{Rank reported by the API (e.g., `"species"`,
#'       `"genus"`). Useful for filtering to species-only suggestions.}
#'     \item{`source_file`}{Basename of the source JSON file.}
#'   }
#'
#' @details
#' **Saving API responses:** Each JSON file must be the API response for
#' exactly one image.  Name the file using the image stem so that
#' `observation_id` is interpretable downstream:
#' ```r
#' # Requires httr2 and jsonlite
#' img_path <- "field_images/IMG_001.jpg"
#' resp <- httr2::request("https://api.inaturalist.org/v2") |>
#'   httr2::req_url_path("/computervision/score_image") |>
#'   httr2::req_body_multipart(
#'     image    = curl::form_file(img_path),
#'     jwt      = your_inat_api_token   # from inaturalist.org
#'   ) |>
#'   httr2::req_perform()
#' json_path <- sub("\\.jpg$", ".json", img_path)
#' writeLines(httr2::resp_body_string(resp), json_path)
#' ```
#' Then: `read_inaturalist_cv_output("field_images/")`.
#'
#' **Species rank filtering:** iNaturalist CV returns suggestions at any rank
#' (species, genus, family, ...). Filter before standardizing:
#' ```r
#' match_df <- read_inaturalist_cv_output("inat_results/") |>
#'   subset(taxon_rank == "species") |>
#'   standardize_match_data(
#'     observation_id_col = "observation_id",
#'     score_col          = "score",
#'     rank_system        = c("genus", "species")
#'   )
#' ```
#'
#' @seealso [read_animl_output()], [standardize_match_data()]
#'
#' @export
#'
#' @examples
#' # Minimal synthetic iNaturalist CV JSON
#' tmp <- tempfile(fileext = ".json")
#' writeLines(
#'   '{"results":[
#'      {"combined_score":0.87,"score":0.91,
#'       "taxon":{"name":"Danaus plexippus","rank":"species",
#'                "preferred_common_name":"Monarch"}},
#'      {"combined_score":0.07,"score":0.06,
#'       "taxon":{"name":"Limenitis archippus","rank":"species",
#'                "preferred_common_name":"Viceroy"}}
#'   ]}',
#'   tmp
#' )
#' result <- read_inaturalist_cv_output(tmp)
#' head(result)
#' unlink(tmp)
read_inaturalist_cv_output <- function(files,
                                        score_type     = c("combined_score", "score"),
                                        min_confidence = 0,
                                        top_n          = NULL) {

  if (!requireNamespace("jsonlite", quietly = TRUE))
    stop(paste0(
      "read_inaturalist_cv_output: package 'jsonlite' is required. ",
      "Install it with: install.packages('jsonlite')"
    ))

  score_type <- match.arg(score_type)

  if (!is.character(files) || length(files) == 0L)
    stop("read_inaturalist_cv_output: 'files' must be a non-empty character vector or directory path.")
  if (!is.numeric(min_confidence) || length(min_confidence) != 1L || is.na(min_confidence))
    stop("read_inaturalist_cv_output: 'min_confidence' must be a single numeric value.")
  if (!is.null(top_n)) {
    top_n <- as.integer(top_n)
    if (is.na(top_n) || top_n < 1L)
      stop("read_inaturalist_cv_output: 'top_n' must be a positive integer or NULL.")
  }

  # ---- resolve directory vs file list ----------------------------------------
  if (length(files) == 1L && dir.exists(files)) {
    files <- list.files(files, pattern = "\\.json$",
                        full.names = TRUE, recursive = FALSE,
                        ignore.case = TRUE)
    if (length(files) == 0L)
      stop("read_inaturalist_cv_output: no *.json files found in directory.")
  } else {
    missing_files <- files[!file.exists(files)]
    if (length(missing_files) > 0L)
      stop(sprintf(
        "read_inaturalist_cv_output: file(s) not found:\n  %s",
        paste(missing_files, collapse = "\n  ")
      ))
  }

  # ---- parse each file -------------------------------------------------------
  rows <- vector("list", length(files))
  for (i in seq_along(files)) {
    rows[[i]] <- .parse_inat_cv_file(files[[i]], score_type = score_type)
  }
  out <- do.call(rbind, rows)

  if (nrow(out) == 0L) {
    message("read_inaturalist_cv_output: no suggestions found across all files.")
    return(out)
  }

  # ---- apply filters ---------------------------------------------------------
  out <- out[!is.na(out$score) & out$score >= min_confidence, , drop = FALSE]

  if (!is.null(top_n)) {
    out <- do.call(rbind, lapply(split(out, out$observation_id), function(g) {
      g[order(g$score, decreasing = TRUE), ][seq_len(min(nrow(g), top_n)), ,
                                              drop = FALSE]
    }))
    rownames(out) <- NULL
  }

  out
}


#' Parse one iNaturalist CV JSON response file
#' @noRd
.parse_inat_cv_file <- function(f, score_type) {
  parsed <- tryCatch(
    jsonlite::fromJSON(f, simplifyVector = FALSE),
    error = function(e) {
      stop(sprintf("read_inaturalist_cv_output: could not parse '%s': %s",
                   basename(f), conditionMessage(e)))
    }
  )

  obs_id <- tools::file_path_sans_ext(basename(f))

  results <- parsed[["results"]]
  if (is.null(results) || length(results) == 0L) {
    message(sprintf(
      "read_inaturalist_cv_output: '%s' has no results.", basename(f)
    ))
    return(data.frame(
      observation_id = character(0),
      score          = numeric(0),
      species        = character(0),
      genus          = character(0),
      common_name    = character(0),
      taxon_rank     = character(0),
      source_file    = character(0),
      stringsAsFactors = FALSE
    ))
  }

  rows <- lapply(results, function(r) {
    sc <- if (!is.null(r[[score_type]])) as.numeric(r[[score_type]]) else NA_real_
    tx <- r[["taxon"]]
    nm   <- if (!is.null(tx[["name"]])) as.character(tx[["name"]]) else NA_character_
    rank <- if (!is.null(tx[["rank"]])) tolower(as.character(tx[["rank"]])) else NA_character_
    cn   <- if (!is.null(tx[["preferred_common_name"]])) as.character(tx[["preferred_common_name"]]) else NA_character_
    genus_val <- if (!is.na(nm) && grepl("^[A-Z][a-z]+ [a-z]", nm))
      sub("^(\\S+).*", "\\1", nm) else NA_character_
    data.frame(
      observation_id = obs_id,
      score          = sc,
      species        = nm,
      genus          = genus_val,
      common_name    = cn,
      taxon_rank     = rank,
      source_file    = basename(f),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}


# ==============================================================================
# read_wildlife_insights_output
# ==============================================================================

#' Read Wildlife Insights / SpeciesNet JSON Results into a Match Object
#'
#' Reads one or more JSON output files from the SpeciesNet Python classifier
#' (used by Wildlife Insights and standalone) and returns a tidy data frame
#' in match object format, ready for [standardize_match_data()] and downstream
#' TaxaLikely processing.
#'
#' **Supported format:** SpeciesNet v2+ batch output JSON, which contains a
#' top-level `"predictions"` object keyed by image filename, with each value
#' being a list of prediction objects.  A single JSON file can describe many
#' images.
#'
#' @param files Character vector. Paths to SpeciesNet/Wildlife Insights JSON
#'   files.  Alternatively, a path to a directory: all `*.json` files are
#'   read.  A single JSON file may contain predictions for multiple images.
#' @param min_confidence Numeric. Detections below this score are dropped.
#'   Default `0` (keep all).
#' @param top_n Integer or `NULL`. If supplied, only the top `n` candidates
#'   (by confidence) per image are retained. Default `NULL` (keep all).
#' @param label_col Character. Name of the label/species field inside each
#'   prediction object.  Default `"label"` (SpeciesNet v2 format).
#'   Use `"species"` for older exports.
#' @param score_col Character. Name of the confidence field inside each
#'   prediction object.  Default `"score"`.
#'
#' @return A data frame with one row per image x candidate species, containing:
#'   \describe{
#'     \item{`observation_id`}{Image filename stem (derived from the key in
#'       the `"predictions"` object).}
#'     \item{`score`}{SpeciesNet confidence (0--1).}
#'     \item{`species`}{Species binomial as returned by SpeciesNet. May be
#'       `"blank"`, `"human"`, or other non-wildlife labels — filter these
#'       before proceeding.}
#'     \item{`genus`}{Genus name (first word of `species`). `NA` for
#'       non-binomial labels.}
#'     \item{`category`}{Detection category from the SpeciesNet output (e.g.,
#'       `"animal"`, `"blank"`, `"human"`, `"vehicle"`). `NA` if absent.}
#'     \item{`source_file`}{Basename of the source JSON file.}
#'   }
#'
#' @details
#' **Running SpeciesNet:** SpeciesNet is a Python package from Google /
#' Wildlife Insights:
#' ```bash
#' pip install speciesnet
#' python -m speciesnet.scripts.run_model \
#'   --folders /path/to/images \
#'   --predictions_json speciesnet_output.json
#' ```
#' Then read the output:
#' ```r
#' match_df <- read_wildlife_insights_output("speciesnet_output.json") |>
#'   subset(!species %in% c("blank", "human", "vehicle")) |>
#'   standardize_match_data(
#'     observation_id_col = "observation_id",
#'     score_col          = "score",
#'     rank_system        = c("genus", "species")
#'   )
#' ```
#'
#' **Multiple candidates:** SpeciesNet typically returns only the top
#' prediction per image (one row per image). If your output has multiple
#' candidates per image, use `top_n` to control how many are retained.
#'
#' @seealso [read_animl_output()], [standardize_match_data()]
#'
#' @export
#'
#' @examples
#' # Minimal synthetic SpeciesNet JSON
#' tmp <- tempfile(fileext = ".json")
#' writeLines(
#'   '{"predictions":{
#'      "IMG_001.jpg":[
#'        {"label":"Odocoileus virginianus","score":0.94,"category":"animal"}],
#'      "IMG_002.jpg":[
#'        {"label":"blank","score":0.99,"category":"blank"}]
#'   }}',
#'   tmp
#' )
#' result <- read_wildlife_insights_output(tmp)
#' head(result)
#' unlink(tmp)
read_wildlife_insights_output <- function(files,
                                           min_confidence = 0,
                                           top_n          = NULL,
                                           label_col      = "label",
                                           score_col      = "score") {

  if (!requireNamespace("jsonlite", quietly = TRUE))
    stop(paste0(
      "read_wildlife_insights_output: package 'jsonlite' is required. ",
      "Install it with: install.packages('jsonlite')"
    ))

  if (!is.character(files) || length(files) == 0L)
    stop("read_wildlife_insights_output: 'files' must be a non-empty character vector or directory path.")
  if (!is.numeric(min_confidence) || length(min_confidence) != 1L || is.na(min_confidence))
    stop("read_wildlife_insights_output: 'min_confidence' must be a single numeric value.")
  if (!is.null(top_n)) {
    top_n <- as.integer(top_n)
    if (is.na(top_n) || top_n < 1L)
      stop("read_wildlife_insights_output: 'top_n' must be a positive integer or NULL.")
  }

  # ---- resolve directory vs file list ----------------------------------------
  if (length(files) == 1L && dir.exists(files)) {
    files <- list.files(files, pattern = "\\.json$",
                        full.names = TRUE, recursive = FALSE,
                        ignore.case = TRUE)
    if (length(files) == 0L)
      stop("read_wildlife_insights_output: no *.json files found in directory.")
  } else {
    missing_files <- files[!file.exists(files)]
    if (length(missing_files) > 0L)
      stop(sprintf(
        "read_wildlife_insights_output: file(s) not found:\n  %s",
        paste(missing_files, collapse = "\n  ")
      ))
  }

  # ---- parse each file -------------------------------------------------------
  rows_all <- vector("list", length(files))
  for (i in seq_along(files)) {
    rows_all[[i]] <- .parse_wi_predictions(
      files[[i]],
      label_col = label_col,
      score_col = score_col
    )
  }
  out <- do.call(rbind, rows_all)

  if (is.null(out) || nrow(out) == 0L) {
    message("read_wildlife_insights_output: no predictions found across all files.")
    return(data.frame(
      observation_id = character(0),
      score          = numeric(0),
      species        = character(0),
      genus          = character(0),
      category       = character(0),
      source_file    = character(0),
      stringsAsFactors = FALSE
    ))
  }

  # ---- apply filters ---------------------------------------------------------
  out <- out[!is.na(out$score) & out$score >= min_confidence, , drop = FALSE]

  if (!is.null(top_n)) {
    out <- do.call(rbind, lapply(split(out, out$observation_id), function(g) {
      g[order(g$score, decreasing = TRUE), ][seq_len(min(nrow(g), top_n)), ,
                                              drop = FALSE]
    }))
    rownames(out) <- NULL
  }

  out
}


#' Parse SpeciesNet/Wildlife Insights JSON predictions from one file
#' @noRd
.parse_wi_predictions <- function(f, label_col, score_col) {
  parsed <- tryCatch(
    jsonlite::fromJSON(f, simplifyVector = FALSE),
    error = function(e) {
      stop(sprintf("read_wildlife_insights_output: could not parse '%s': %s",
                   basename(f), conditionMessage(e)))
    }
  )

  preds <- parsed[["predictions"]]
  if (is.null(preds) || length(preds) == 0L) {
    message(sprintf(
      "read_wildlife_insights_output: '%s' has no 'predictions' field.", basename(f)
    ))
    return(data.frame(
      observation_id = character(0),
      score          = numeric(0),
      species        = character(0),
      genus          = character(0),
      category       = character(0),
      source_file    = character(0),
      stringsAsFactors = FALSE
    ))
  }

  img_names <- names(preds)
  rows <- vector("list", length(img_names))
  for (i in seq_along(img_names)) {
    img_key    <- img_names[[i]]
    obs_id     <- tools::file_path_sans_ext(basename(img_key))
    candidates <- preds[[img_key]]
    if (!is.list(candidates) || length(candidates) == 0L) next

    img_rows <- lapply(candidates, function(p) {
      nm  <- if (!is.null(p[[label_col]])) as.character(p[[label_col]]) else NA_character_
      sc  <- if (!is.null(p[[score_col]])) suppressWarnings(as.numeric(p[[score_col]])) else NA_real_
      cat <- if (!is.null(p[["category"]])) as.character(p[["category"]]) else NA_character_
      genus_val <- if (!is.na(nm) && grepl("^[A-Z][a-z]+ [a-z]", nm))
        sub("^(\\S+).*", "\\1", nm) else NA_character_
      data.frame(
        observation_id = obs_id,
        score          = sc,
        species        = nm,
        genus          = genus_val,
        category       = cat,
        source_file    = basename(f),
        stringsAsFactors = FALSE
      )
    })
    rows[[i]] <- do.call(rbind, img_rows)
  }
  rows <- rows[!vapply(rows, is.null, logical(1L))]
  if (length(rows) == 0L) return(NULL)
  do.call(rbind, rows)
}
