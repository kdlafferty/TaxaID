# ==============================================================================
# read_image.R
# TaxaMatch -- Ingest image classifier output into the match object format
#
# Exported functions:
#   read_animl_output()    Ingest Animl (camera trap) CSV results
#
# Internal helpers (@noRd):
#   .parse_animl_file()    Read and validate a single Animl CSV
#   .pivot_wide_animl()    Pivot pred1/score1...predN/scoreN to long format
# ==============================================================================


# ==============================================================================
# read_animl_output()
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
#' @seealso [standardize_match_data()],
#'   [`TaxaLikely::build_acoustic_reference()`][TaxaLikely::build_acoustic_reference]
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
                               top_n           = NULL) {

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
      n_candidates    = n_candidates
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
# Internal: .parse_animl_file()
# ==============================================================================

#' Parse a single Animl result CSV into a match-ready data frame
#' @param f Character. Path to a single Animl CSV file.
#' @param file_col,species_col,score_col,common_name_col,n_candidates
#'   Forwarded from [read_animl_output()].
#' @return Data frame with canonical match columns.
#' @noRd
.parse_animl_file <- function(f, file_col, species_col, score_col,
                               common_name_col, n_candidates) {

  df <- tryCatch(
    utils::read.csv(f, check.names = FALSE, stringsAsFactors = FALSE),
    error = function(e) stop(sprintf(
      "read_animl_output: could not read '%s': %s",
      basename(f), conditionMessage(e)
    ))
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

  data.frame(
    observation_id = img_stem,
    score          = score_vals,
    species        = species_vals,
    genus          = genus_vals,
    common_name    = common_vals,
    source_file    = basename(f),
    stringsAsFactors = FALSE
  )
}


# ==============================================================================
# Internal: .pivot_wide_animl()
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
  cand_id <- rep(seq_len(n_candidates), each = n_rows)

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
