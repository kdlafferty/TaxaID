# ==============================================================================
# read_image_classifiers.R
# TaxaMatch -- Ingest image classifier output into the match object format
#
# Exported functions:
#   read_animl_output()              Ingest Animl (camera trap) CSV results
#   read_inaturalist_cv_output()     Ingest iNaturalist CV API JSON responses
#   read_speciesnet_output()         Ingest real SpeciesNet CLI predictions_json
#     NOTE (2026-07-23): replaces the removed read_wildlife_insights_output(),
#     which targeted a dict-keyed-by-filename JSON shape that matched neither
#     the real Wildlife Insights platform (bulk downloads are a CSV bundle,
#     not JSON) nor the real current SpeciesNet CLI (google/cameratrapai;
#     predictions is a LIST, not a dict) -- see TaxaMatch/CLAUDE.md's
#     2026-07-23 note. Zero real callers existed at removal time.
#
# Internal helpers (@noRd):
#   .parse_animl_file()              Read and validate a single Animl CSV
#   .pivot_wide_animl()              Pivot pred1/score1...predN/scoreN to long format
#   .parse_inat_cv_file()            Parse one iNaturalist CV JSON file
#   .parse_speciesnet_predictions()  Parse one SpeciesNet predictions_json file
#   .parse_speciesnet_label()        Parse a uuid;class;order;family;genus;species;common_name label
#   .speciesnet_detection_coverage() bbox coverage from an image's MegaDetector detections
#   .empty_animl_result()       Shared 0-row constructor for read_animl_output()
#   .empty_inat_result()        Shared 0-row constructor for read_inaturalist_cv_output()
#   .empty_speciesnet_result()  Shared 0-row constructor for read_speciesnet_output()
# ==============================================================================

#' @noRd
.empty_animl_result <- function() {
  data.frame(
    observation_id = character(0), score = numeric(0),
    species = character(0), genus = character(0),
    common_name = character(0), source_file = character(0),
    stringsAsFactors = FALSE
  )
}

#' @noRd
.empty_inat_result <- function() {
  data.frame(
    observation_id = character(0), score = numeric(0),
    species = character(0), genus = character(0),
    common_name = character(0), taxon_rank = character(0),
    source_file = character(0),
    stringsAsFactors = FALSE
  )
}

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
#' metric (top-1 minus top-2 confidence) to operate correctly. A camera trap
#' image with multiple detected individuals/species yields multiple crops
#' from MegaDetector, each a separate `observation_id` -- if Animl encodes
#' the crop index in the filename (e.g. `IMG_001_crop1.jpg`), these are
#' handled automatically; if the same filename is reused across crops, they
#' will collide under one `observation_id` (a `warning()` is issued when
#' duplicate image basenames are detected in `file_col`).
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
#'   FileName = c("img001.jpg", "img001.jpg", "img002.jpg"),
#'   prediction = c("Odocoileus virginianus", "Cervus canadensis", "empty"),
#'   confidence = c(0.93, 0.05, 0.99),
#'   stringsAsFactors = FALSE
#' ), tmp, row.names = FALSE)
#'
#' result <- read_animl_output(tmp)
#' head(result)
#' unlink(tmp)
read_animl_output <- function(files,
                              file_col = "FileName",
                              species_col = "prediction",
                              score_col = "confidence",
                              common_name_col = NULL,
                              n_candidates = NULL,
                              min_confidence = 0,
                              top_n = NULL,
                              bbox_cols = NULL) {
  # ---- validate inputs -------------------------------------------------------
  if (!is.character(files) || length(files) == 0L) {
    stop(
      "read_animl_output: 'files' must be a non-empty character vector of ",
      "file paths or a single directory path."
    )
  }
  if (!is.character(file_col) || length(file_col) != 1L) {
    stop("read_animl_output: 'file_col' must be a length-1 character string.")
  }
  if (!is.character(species_col) || length(species_col) != 1L) {
    stop("read_animl_output: 'species_col' must be a length-1 character string.")
  }
  if (!is.character(score_col) || length(score_col) != 1L) {
    stop("read_animl_output: 'score_col' must be a length-1 character string.")
  }
  if (!is.null(common_name_col) &&
    (!is.character(common_name_col) || length(common_name_col) != 1L)) {
    stop("read_animl_output: 'common_name_col' must be a length-1 character string or NULL.")
  }
  if (!is.null(n_candidates)) {
    n_candidates <- as.integer(n_candidates)
    if (is.na(n_candidates) || n_candidates < 1L) {
      stop("read_animl_output: 'n_candidates' must be a positive integer or NULL.")
    }
  }
  top_n <- .validate_min_conf_top_n(min_confidence, top_n, "read_animl_output")
  if (!is.null(bbox_cols)) {
    if (!is.character(bbox_cols) || length(bbox_cols) != 2L) {
      stop("read_animl_output: 'bbox_cols' must be a length-2 character vector, e.g. c(w = 'bbox_w', h = 'bbox_h').")
    }
  }

  # ---- resolve directory vs file list ----------------------------------------
  if (length(files) == 1L && dir.exists(files)) {
    files <- list.files(files,
      pattern = "\\.csv$",
      full.names = TRUE, recursive = FALSE,
      ignore.case = TRUE
    )
    if (length(files) == 0L) {
      stop("read_animl_output: no *.csv files found in directory.")
    }
  } else {
    missing_files <- files[!file.exists(files)]
    if (length(missing_files) > 0L) {
      .stop_missing_files(missing_files, "read_animl_output")
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
  out <- .apply_top_n(out, "observation_id", "score", top_n)
  rownames(out) <- NULL

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
  animl_df <- tryCatch(
    utils::read.csv(f, check.names = FALSE, stringsAsFactors = FALSE),
    error = function(e) {
      stop(sprintf(
        "read_animl_output: could not read '%s': %s",
        basename(f), conditionMessage(e)
      ))
    }
  )

  # ---- check file_col --------------------------------------------------------
  if (!file_col %in% names(animl_df)) {
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
    animl_df <- .pivot_wide_animl(
      animl_df, f, file_col, species_col, score_col,
      common_name_col, n_candidates
    )
    # After pivot, columns are named "file_col", "species_col", "score_col",
    # "common_name_col" with the actual column values renamed to standard names
    # below.
    species_actual <- ".animl_species"
    score_actual <- ".animl_score"
    common_name_actual <- ".animl_common_name"
  } else {
    # Long format: columns must exist directly
    missing_cols <- setdiff(
      c(file_col, species_col, score_col),
      names(animl_df)
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
    species_actual <- species_col
    score_actual <- score_col
    common_name_actual <- if (!is.null(common_name_col) &&
      common_name_col %in% names(animl_df)) {
      common_name_col
    } else {
      NULL
    }
  }

  if (nrow(animl_df) == 0L) {
    message(sprintf(
      "read_animl_output: '%s' has no detections (empty file).", basename(f)
    ))
    return(.empty_animl_result())
  }

  # ---- build observation_id from image filename stem -------------------------
  img_paths <- trimws(as.character(animl_df[[file_col]]))
  # Strip all extensions (handles .jpg, .JPG, .tif, .tiff, etc.)
  img_stem <- tools::file_path_sans_ext(basename(img_paths))
  .warn_duplicate_basenames(img_paths, "read_animl_output")

  species_vals <- trimws(as.character(animl_df[[species_actual]]))
  score_vals <- suppressWarnings(as.numeric(animl_df[[score_actual]]))
  common_vals <- if (!is.null(common_name_actual)) {
    trimws(as.character(animl_df[[common_name_actual]]))
  } else {
    rep(NA_character_, nrow(animl_df))
  }

  genus_vals <- .extract_genus(species_vals)

  # Compute coverage from bounding box area (optional) -------------------------
  # bbox_w * bbox_h gives the fractional area of the image occupied by the
  # detection crop (0-1).  A small fraction = distant/partial animal = weaker
  # classification evidence.  Analogous to BLAST qcovs for DNA sequences.
  coverage_vals <- if (!is.null(bbox_cols)) {
    w_col <- if (!is.null(names(bbox_cols)) && "w" %in% names(bbox_cols)) {
      bbox_cols[["w"]]
    } else {
      bbox_cols[[1L]]
    }
    h_col <- if (!is.null(names(bbox_cols)) && "h" %in% names(bbox_cols)) {
      bbox_cols[["h"]]
    } else {
      bbox_cols[[2L]]
    }
    if (!w_col %in% names(animl_df) || !h_col %in% names(animl_df)) {
      warning(sprintf(
        "read_animl_output: bbox_cols '%s'/'%s' not found in '%s'; coverage set to NA.",
        w_col, h_col, basename(f)
      ), call. = FALSE)
      rep(NA_real_, nrow(animl_df))
    } else {
      suppressWarnings(as.numeric(animl_df[[w_col]]) * as.numeric(animl_df[[h_col]]))
    }
  } else {
    NULL
  }

  out_df <- data.frame(
    observation_id = img_stem,
    score = score_vals,
    species = species_vals,
    genus = genus_vals,
    common_name = common_vals,
    source_file = basename(f),
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
.pivot_wide_animl <- function(animl_df, f, file_col, species_prefix, score_prefix,
                              common_name_col, n_candidates) {
  # Build expected column names
  pred_cols <- paste0(species_prefix, seq_len(n_candidates))
  score_cols <- paste0(score_prefix, seq_len(n_candidates))

  missing_pred <- setdiff(pred_cols, names(animl_df))
  missing_score <- setdiff(score_cols, names(animl_df))
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
  n_rows <- nrow(animl_df)
  indices <- rep(seq_len(n_rows), times = n_candidates)

  long <- animl_df[indices, , drop = FALSE]
  rownames(long) <- NULL

  long[[".animl_species"]] <- unlist(
    lapply(seq_len(n_candidates), function(k) animl_df[[pred_cols[k]]]),
    use.names = FALSE
  )
  long[[".animl_score"]] <- unlist(
    lapply(seq_len(n_candidates), function(k) animl_df[[score_cols[k]]]),
    use.names = FALSE
  )
  if (!is.null(common_name_col) && common_name_col %in% names(animl_df)) {
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
#' `POST https://api.inaturalist.org/v1/computervision/score_image` --
#' confirmed live and working (returning HTTP 200 with real results) as of
#' this package's [score_image_inat()], which calls the same v1 endpoint
#' directly rather than saving JSON to disk first. See the `@details`
#' section for a minimal API call example for the save-to-disk path this
#' function reads.
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
#'     \item{`score`}{iNaturalist CV score, passed through unchanged from the
#'       saved JSON's `score_type` field. The live API returns scores on
#'       iNaturalist's 0--100 softmax convention (candidates for one image
#'       sum to approximately 100, not 1) -- confirmed directly against the
#'       real API (see [score_image_inat()]'s matching `@return` note); do
#'       not assume a 0--1 scale or rescale before passing to
#'       `TaxaLikely::evaluate_likelihoods()`.}
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
#' resp <- httr2::request("https://api.inaturalist.org/v1") |>
#'   httr2::req_url_path("/computervision/score_image") |>
#'   httr2::req_body_multipart(
#'     image    = curl::form_file(img_path),
#'     jwt      = your_inat_api_token   # from inaturalist.org
#'   ) |>
#'   httr2::req_perform()
#' json_path <- sub("\\.jpg$", ".json", img_path)
#' writeLines(httr2::resp_body_string(resp), json_path)
#' ```
#' Then: `read_inaturalist_cv_output("field_images/")`. The endpoint is
#' rate-limited (documented at 60 requests/minute for authenticated users);
#' pace calls accordingly when generating many JSON files in a batch.
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
#' # Minimal synthetic iNaturalist CV JSON. Real API responses score
#' # candidates on a 0-100 scale (see @return); this synthetic fixture uses
#' # a couple of plausible values to demonstrate parsing, not a real response.
#' tmp <- tempfile(fileext = ".json")
#' writeLines(
#'   '{"results":[
#'      {"combined_score":72.4,"score":68.1,
#'       "taxon":{"name":"Danaus plexippus","rank":"species",
#'                "preferred_common_name":"Monarch"}},
#'      {"combined_score":5.3,"score":4.7,
#'       "taxon":{"name":"Limenitis archippus","rank":"species",
#'                "preferred_common_name":"Viceroy"}}
#'   ]}',
#'   tmp
#' )
#' result <- read_inaturalist_cv_output(tmp)
#' head(result)
#' unlink(tmp)
read_inaturalist_cv_output <- function(files,
                                       score_type = c("combined_score", "score"),
                                       min_confidence = 0,
                                       top_n = NULL) {
  .check_pkg("jsonlite")

  score_type <- match.arg(score_type)

  if (!is.character(files) || length(files) == 0L) {
    stop("read_inaturalist_cv_output: 'files' must be a non-empty character vector or directory path.")
  }
  top_n <- .validate_min_conf_top_n(min_confidence, top_n, "read_inaturalist_cv_output")

  # ---- resolve directory vs file list ----------------------------------------
  if (length(files) == 1L && dir.exists(files)) {
    files <- list.files(files,
      pattern = "\\.json$",
      full.names = TRUE, recursive = FALSE,
      ignore.case = TRUE
    )
    if (length(files) == 0L) {
      stop("read_inaturalist_cv_output: no *.json files found in directory.")
    }
  } else {
    missing_files <- files[!file.exists(files)]
    if (length(missing_files) > 0L) {
      .stop_missing_files(missing_files, "read_inaturalist_cv_output")
    }
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
  out <- .apply_top_n(out, "observation_id", "score", top_n)
  rownames(out) <- NULL

  out
}


#' Parse one iNaturalist CV JSON response file
#' @noRd
.parse_inat_cv_file <- function(f, score_type) {
  parsed <- tryCatch(
    jsonlite::fromJSON(f, simplifyVector = FALSE),
    error = function(e) {
      stop(sprintf(
        "read_inaturalist_cv_output: could not parse '%s': %s",
        basename(f), conditionMessage(e)
      ))
    }
  )

  obs_id <- tools::file_path_sans_ext(basename(f))

  results <- parsed[["results"]]
  if (is.null(results) || length(results) == 0L) {
    message(sprintf(
      "read_inaturalist_cv_output: '%s' has no results.", basename(f)
    ))
    return(.empty_inat_result())
  }

  rows <- lapply(results, function(r) {
    sc <- if (!is.null(r[[score_type]])) as.numeric(r[[score_type]]) else NA_real_
    tx <- r[["taxon"]]
    nm <- if (!is.null(tx[["name"]])) as.character(tx[["name"]]) else NA_character_
    rank <- if (!is.null(tx[["rank"]])) tolower(as.character(tx[["rank"]])) else NA_character_
    cn <- if (!is.null(tx[["preferred_common_name"]])) as.character(tx[["preferred_common_name"]]) else NA_character_
    genus_val <- .extract_genus(nm)
    data.frame(
      observation_id = obs_id,
      score = sc,
      species = nm,
      genus = genus_val,
      common_name = cn,
      taxon_rank = rank,
      source_file = basename(f),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}


# ==============================================================================
# read_speciesnet_output
# ==============================================================================

#' @noRd
.empty_speciesnet_result <- function(include_coverage = FALSE) {
  out <- data.frame(
    observation_id = character(0), score = numeric(0),
    species = character(0), genus = character(0), family = character(0),
    order = character(0), class = character(0), common_name = character(0),
    taxon_rank = character(0),
    ensemble_prediction = character(0), ensemble_prediction_score = numeric(0),
    ensemble_prediction_source = character(0),
    lat = numeric(0), lon = numeric(0), country = character(0),
    source_file = character(0),
    stringsAsFactors = FALSE
  )
  if (isTRUE(include_coverage)) {
    out$coverage <- numeric(0)
    out$detection_conf <- numeric(0)
  }
  out
}

#' Read SpeciesNet Batch Classification Results into a Match Object
#'
#' Reads one or more real SpeciesNet CLI (`google/cameratrapai`,
#' `python -m speciesnet.scripts.run_model --predictions_json=...`) batch
#' prediction JSON files and returns a tidy data frame in match object
#' format, ready for [standardize_match_data()] and downstream TaxaLikely
#' processing.
#'
#' @param files Character vector. Paths to SpeciesNet `predictions_json`
#'   output files. Alternatively, a path to a directory: all `*.json` files
#'   in that directory (non-recursive) are read. A single file's top-level
#'   `predictions` array may cover many images.
#' @param min_confidence Numeric. Candidates below this classification score
#'   are dropped. Default `0` (keep all).
#' @param top_n Integer or `NULL`. If supplied, only the top `n` candidates
#'   (by score) per image are retained -- SpeciesNet's own classifier already
#'   returns at most 5. Default `NULL` (keep all up to 5).
#' @param include_coverage Logical. If `TRUE`, adds a `coverage` column
#'   (bounding-box area fraction, `bbox_w * bbox_h`) and a `detection_conf`
#'   column, taken from the image's highest-confidence MegaDetector
#'   `"animal"` detection (SpeciesNet detection category `"1"`) -- an
#'   image-quality analog to BLAST `qcovs`, matching [read_animl_output()]'s
#'   `bbox_cols` convention. `NA` for images with no qualifying detection.
#'   Default `FALSE`.
#' @param min_detection_conf Numeric. Only used when `include_coverage =
#'   TRUE`: detections below this MegaDetector confidence are not eligible
#'   to be the representative detection. Default `0`.
#'
#' @return A data frame with one row per image x candidate species,
#'   containing:
#'   \describe{
#'     \item{`observation_id`}{Unique identifier derived from the image
#'       filename stem (`filepath`, path stripped, extension(s) stripped).}
#'     \item{`score`}{SpeciesNet classifier confidence (0--1) for this
#'       candidate, from the RAW top-5 `classifications` block --
#'       pre-geofencing, pre-taxonomic-rollup. This is deliberately NOT the
#'       same as `ensemble_prediction_score` (see `@details`).}
#'     \item{`species`, `genus`, `family`, `order`, `class`}{Parsed from
#'       SpeciesNet's own `uuid;class;order;family;genus;species;common_name`
#'       label string. Any of these may be `NA` -- SpeciesNet's own
#'       classifier taxonomy has 2000+ labels spanning every rank from class
#'       down to species. `species` is the full binomial (genus + epithet,
#'       genus capitalized); the raw label's own species field is the
#'       epithet only.}
#'     \item{`common_name`}{Common name from the label string, or the
#'       non-taxonomic label itself (`"animal"`, `"blank"`, `"vehicle"`,
#'       `"human"`) when no taxonomic rank is populated.}
#'     \item{`taxon_rank`}{Finest populated rank among `species`/`genus`/
#'       `family`/`order`/`class`; `NA` for a non-taxonomic candidate.}
#'     \item{`ensemble_prediction`, `ensemble_prediction_score`,
#'       `ensemble_prediction_source`}{SpeciesNet's own final answer for the
#'       WHOLE IMAGE (constant across every candidate row for that image) --
#'       the label string's own common name, plus the ensemble's confidence
#'       and which internal component produced it (e.g. `"classifier"`,
#'       `"detector"`, `"geofence"`). Kept as reference/diagnostic metadata;
#'       NOT used to build `species`/`score` above -- see `@details`.}
#'     \item{`lat`, `lon`, `country`}{From the prediction's optional
#'       `latitude`/`longitude`/`country` fields, when SpeciesNet was run
#'       with geographic context. `NA` otherwise. Feed directly to
#'       [build_site_table()] (already in the canonical `lat`/`lon` names).}
#'     \item{`coverage`, `detection_conf`}{Only present when
#'       `include_coverage = TRUE`; see that parameter.}
#'     \item{`source_file`}{Basename of the source JSON file.}
#'   }
#'
#' @details
#' **Why `classifications`, not `prediction`:** SpeciesNet's ensemble
#' deliberately rolls a prediction up to genus/family/order/class/kingdom
#' whenever species-level confidence is insufficient (Markoff & Galaktionovs
#' 2025, arXiv:2510.14594 -- precision over recall by design). The raw top-5
#' `classifications` block is the classifier's OWN candidate list, computed
#' before that rollup and before geofencing -- it still carries
#' species-level signal that the ensemble's own `prediction` field has
#' already discarded. This function treats `classifications` as the primary
#' multi-candidate source (mirroring [blast_sequences()]/
#' [read_animl_output()]'s multiple-hypotheses-per-query shape) precisely so
#' that species-level candidates reach TaxaLikely/TaxaAssign's own
#' prior-informed resolution instead of being silently pre-resolved by
#' SpeciesNet's conservative rollup. `ensemble_prediction`/
#' `ensemble_prediction_score` are retained only as reference metadata (e.g.
#' to compare against what TaxaID's own posterior later resolves to), not as
#' an alternative candidate source.
#'
#' **Filtering non-wildlife detections:** SpeciesNet assigns non-taxonomic
#' labels (`"animal"`, `"blank"`, `"human"`, `"vehicle"`) when no wildlife
#' taxon is identified, and a `"no cv result"` placeholder when the
#' classifier itself failed. All of these have `taxon_rank = NA`. Filter
#' before standardizing:
#' ```r
#' match_df <- read_speciesnet_output("speciesnet_predictions.json") |>
#'   dplyr::filter(!is.na(taxon_rank))
#' ```
#'
#' **Running SpeciesNet:**
#' ```bash
#' pip install speciesnet
#' python -m speciesnet.scripts.run_model \
#'   --folders /path/to/images \
#'   --predictions_json speciesnet_predictions.json
#' ```
#' Then:
#' ```r
#' match_df <- read_speciesnet_output("speciesnet_predictions.json") |>
#'   dplyr::filter(!is.na(taxon_rank)) |>
#'   standardize_match_data(
#'     observation_id_col = "observation_id",
#'     score_col          = "score",
#'     rank_system        = c("class", "order", "family", "genus", "species")
#'   )
#' ```
#'
#' **Label format:** SpeciesNet's label strings are confirmed directly
#' against the shipped taxonomy file
#' (`data/model_package/taxonomy_release.txt` in `google/cameratrapai`):
#' `uuid;class;order;family;genus;species;common_name`, e.g.
#' `"...;amphibia;anura;bufonidae;rhinella;marina;cane toad"`. Any of the 5
#' taxonomic fields may be empty (coarser rollup); this function normalizes
#' both an empty field and the literal `"no cv result"` placeholder to `NA`.
#'
#' @seealso [read_animl_output()], [standardize_match_data()]
#'
#' @export
#'
#' @examples
#' # Minimal synthetic SpeciesNet CLI JSON (real label format, uuids shortened)
#' tmp <- tempfile(fileext = ".json")
#' writeLines(
#'   '{"predictions":[
#'      {"filepath":"IMG_001.jpg",
#'       "classifications":{
#'         "classes":[
#'           "u1;amphibia;anura;bufonidae;rhinella;marina;cane toad",
#'           "u2;amphibia;anura;ranidae;;;true frogs"],
#'         "scores":[0.87,0.06]},
#'       "detections":[{"category":"1","conf":0.95,"bbox":[0.1,0.1,0.3,0.4]}],
#'       "prediction":"u1;amphibia;anura;bufonidae;rhinella;marina;cane toad",
#'       "prediction_score":0.87,"prediction_source":"classifier"},
#'      {"filepath":"IMG_002.jpg",
#'       "classifications":{
#'         "classes":["u3;;;;;;blank"],
#'         "scores":[0.99]},
#'       "prediction":"u3;;;;;;blank",
#'       "prediction_score":0.99,"prediction_source":"detector"}
#'   ]}',
#'   tmp
#' )
#' result <- read_speciesnet_output(tmp)
#' head(result)
#' unlink(tmp)
read_speciesnet_output <- function(files,
                                   min_confidence = 0,
                                   top_n = NULL,
                                   include_coverage = FALSE,
                                   min_detection_conf = 0) {
  .check_pkg("jsonlite")

  if (!is.character(files) || length(files) == 0L) {
    stop("read_speciesnet_output: 'files' must be a non-empty character vector or directory path.")
  }
  top_n <- .validate_min_conf_top_n(min_confidence, top_n, "read_speciesnet_output")
  if (!is.logical(include_coverage) || length(include_coverage) != 1L || is.na(include_coverage)) {
    stop("read_speciesnet_output: 'include_coverage' must be a single logical value.")
  }
  if (!is.numeric(min_detection_conf) || length(min_detection_conf) != 1L || is.na(min_detection_conf)) {
    stop("read_speciesnet_output: 'min_detection_conf' must be a single numeric value.")
  }

  # ---- resolve directory vs file list ----------------------------------------
  if (length(files) == 1L && dir.exists(files)) {
    files <- list.files(files,
      pattern = "\\.json$",
      full.names = TRUE, recursive = FALSE,
      ignore.case = TRUE
    )
    if (length(files) == 0L) {
      stop("read_speciesnet_output: no *.json files found in directory.")
    }
  } else {
    missing_files <- files[!file.exists(files)]
    if (length(missing_files) > 0L) {
      .stop_missing_files(missing_files, "read_speciesnet_output")
    }
  }

  # ---- parse each file --------------------------------------------------------
  rows_all <- vector("list", length(files))
  for (i in seq_along(files)) {
    rows_all[[i]] <- .parse_speciesnet_predictions(
      files[[i]],
      include_coverage   = include_coverage,
      min_detection_conf = min_detection_conf
    )
  }
  out <- do.call(rbind, rows_all)

  if (is.null(out) || nrow(out) == 0L) {
    message("read_speciesnet_output: no predictions found across all files.")
    return(.empty_speciesnet_result(include_coverage))
  }

  .warn_duplicate_basenames(out$.filepath, "read_speciesnet_output")
  out$.filepath <- NULL

  # ---- apply filters ---------------------------------------------------------
  out <- out[!is.na(out$score) & out$score >= min_confidence, , drop = FALSE]
  out <- .apply_top_n(out, "observation_id", "score", top_n)
  rownames(out) <- NULL

  out
}


#' Parse one SpeciesNet predictions_json file's "predictions" array
#' @noRd
.parse_speciesnet_predictions <- function(f, include_coverage, min_detection_conf) {
  parsed <- tryCatch(
    jsonlite::fromJSON(f, simplifyVector = FALSE),
    error = function(e) {
      stop(sprintf(
        "read_speciesnet_output: could not parse '%s': %s",
        basename(f), conditionMessage(e)
      ))
    }
  )

  preds <- parsed[["predictions"]]
  if (is.null(preds) || length(preds) == 0L) {
    message(sprintf(
      "read_speciesnet_output: '%s' has no 'predictions' field.", basename(f)
    ))
    return(NULL)
  }

  rows <- lapply(preds, function(p) {
    filepath <- p[["filepath"]]
    if (is.null(filepath) || !nzchar(trimws(as.character(filepath)))) {
      return(NULL)
    }
    obs_id <- tools::file_path_sans_ext(basename(as.character(filepath)))

    classes <- p[["classifications"]][["classes"]]
    scores <- p[["classifications"]][["scores"]]
    if (is.null(classes) || length(classes) == 0L) {
      return(NULL)
    }

    labels <- vapply(classes, as.character, character(1L))
    score_vals <- vapply(scores, function(s) suppressWarnings(as.numeric(s)), numeric(1L))
    tax <- .parse_speciesnet_label(labels)

    ens_label <- p[["prediction"]]
    ens_common <- if (!is.null(ens_label)) {
      .parse_speciesnet_label(as.character(ens_label))$common_name
    } else {
      NA_character_
    }

    lat_val <- p[["latitude"]]
    lat_val <- if (is.null(lat_val)) NA_real_ else as.numeric(lat_val)
    lon_val <- p[["longitude"]]
    lon_val <- if (is.null(lon_val)) NA_real_ else as.numeric(lon_val)
    country_val <- p[["country"]]
    country_val <- if (is.null(country_val)) NA_character_ else as.character(country_val)

    df <- data.frame(
      .filepath = as.character(filepath),
      observation_id = obs_id,
      score = score_vals,
      species = tax$species,
      genus = tax$genus,
      family = tax$family,
      order = tax$order,
      class = tax$class,
      common_name = tax$common_name,
      taxon_rank = tax$taxon_rank,
      ensemble_prediction = ens_common,
      ensemble_prediction_score = if (is.null(p[["prediction_score"]])) NA_real_ else as.numeric(p[["prediction_score"]]),
      ensemble_prediction_source = if (is.null(p[["prediction_source"]])) NA_character_ else as.character(p[["prediction_source"]]),
      lat = lat_val,
      lon = lon_val,
      country = country_val,
      source_file = basename(f),
      stringsAsFactors = FALSE
    )

    if (isTRUE(include_coverage)) {
      cov <- .speciesnet_detection_coverage(p[["detections"]], min_detection_conf)
      df$coverage <- cov$coverage
      df$detection_conf <- cov$detection_conf
    }

    df
  })

  rows <- rows[!vapply(rows, is.null, logical(1L))]
  if (length(rows) == 0L) {
    return(NULL)
  }
  do.call(rbind, rows)
}


#' Parse SpeciesNet's uuid;class;order;family;genus;species;common_name label
#'
#' Real format confirmed directly against the shipped taxonomy file
#' (`data/model_package/taxonomy_release.txt` in `google/cameratrapai`): 7
#' semicolon-delimited fields. Any of the 5 taxonomic fields (class..species)
#' may be empty when the ensemble's prediction is rolled up to a coarser
#' rank; the non-taxonomic labels (`"animal"`/`"blank"`/`"vehicle"`) leave
#' all 5 empty, and `"no cv result"` (the `"unknown"` placeholder) repeats
#' that literal string in all 5 instead of leaving them empty -- both are
#' normalized to NA here. `species` in the raw label is the epithet only
#' (e.g. `"marina"` for `"Rhinella marina"`); genus is capitalized and
#' combined with the epithet into a proper binomial in the returned
#' `species` column.
#' @noRd
.parse_speciesnet_label <- function(labels) {
  n <- length(labels)
  if (n == 0L) {
    return(data.frame(
      class = character(0), order = character(0), family = character(0),
      genus = character(0), species = character(0), common_name = character(0),
      taxon_rank = character(0), stringsAsFactors = FALSE
    ))
  }

  clean <- function(x) {
    x <- trimws(x)
    ifelse(!nzchar(x) | x == "no cv result", NA_character_, x)
  }

  parts <- strsplit(labels, ";", fixed = TRUE)
  ok <- lengths(parts) == 7L
  if (any(!ok)) {
    warning(sprintf(
      paste0(
        "read_speciesnet_output: %d label(s) did not have the expected 7 ",
        "semicolon-delimited fields ('uuid;class;order;family;genus;",
        "species;common_name'); taxonomy left NA for those candidates."
      ),
      sum(!ok)
    ), call. = FALSE)
  }

  class_v <- order_v <- family_v <- genus_v <- epithet_v <- common_v <-
    rep(NA_character_, n)

  if (any(ok)) {
    m <- do.call(rbind, parts[ok])
    class_v[ok] <- clean(m[, 2])
    order_v[ok] <- clean(m[, 3])
    family_v[ok] <- clean(m[, 4])
    genus_v[ok] <- clean(m[, 5])
    epithet_v[ok] <- clean(m[, 6])
    common_v[ok] <- clean(m[, 7])
  }

  genus_cap <- ifelse(
    is.na(genus_v), NA_character_,
    paste0(toupper(substr(genus_v, 1, 1)), substr(genus_v, 2, nchar(genus_v)))
  )
  species_v <- ifelse(
    !is.na(genus_cap) & !is.na(epithet_v),
    paste(genus_cap, epithet_v), NA_character_
  )

  taxon_rank <- ifelse(
    !is.na(species_v), "species", ifelse(
      !is.na(genus_cap), "genus", ifelse(
        !is.na(family_v), "family", ifelse(
          !is.na(order_v), "order", ifelse(
            !is.na(class_v), "class", NA_character_
          )
        )
      )
    )
  )

  data.frame(
    class = class_v, order = order_v, family = family_v,
    genus = genus_cap, species = species_v, common_name = common_v,
    taxon_rank = taxon_rank,
    stringsAsFactors = FALSE
  )
}


#' Compute coverage/detection_conf from an image's MegaDetector detections
#'
#' Coverage is bbox width*height (fractional image area, MegaDetector's own
#' normalized `[xmin, ymin, width, height]` convention) for the
#' highest-confidence `"animal"` (category `"1"`) detection clearing
#' `min_detection_conf`. `NA` if there are no detections, none are category
#' `"1"`, or none clear the threshold.
#' @noRd
.speciesnet_detection_coverage <- function(detections, min_detection_conf) {
  if (is.null(detections) || length(detections) == 0L) {
    return(list(coverage = NA_real_, detection_conf = NA_real_))
  }
  animal_dets <- Filter(function(d) {
    cat_val <- d[["category"]]
    !is.null(cat_val) && as.character(cat_val) == "1"
  }, detections)
  if (length(animal_dets) == 0L) {
    return(list(coverage = NA_real_, detection_conf = NA_real_))
  }
  confs <- vapply(animal_dets, function(d) {
    cv <- d[["conf"]]
    if (is.null(cv)) NA_real_ else as.numeric(cv)
  }, numeric(1L))
  eligible <- which(!is.na(confs) & confs >= min_detection_conf)
  if (length(eligible) == 0L) {
    return(list(coverage = NA_real_, detection_conf = NA_real_))
  }
  best <- eligible[which.max(confs[eligible])]
  bbox <- animal_dets[[best]][["bbox"]]
  cov <- if (!is.null(bbox) && length(bbox) == 4L) {
    as.numeric(bbox[[3]]) * as.numeric(bbox[[4]])
  } else {
    NA_real_
  }
  list(coverage = cov, detection_conf = confs[best])
}
