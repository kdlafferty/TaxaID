# ==============================================================================
# read_acoustic.R
# TaxaMatch -- Ingest acoustic classifier output into the match object format
#
# Exported functions:
#   read_birdnet_output()   Ingest BirdNET-Analyzer CSV results
#
# Internal helpers (@noRd):
#   .parse_birdnet_file()   Read and validate a single BirdNET CSV
# ==============================================================================


# ==============================================================================
# read_birdnet_output()
# ==============================================================================

#' Read BirdNET-Analyzer Results into a Match Object
#'
#' Reads one or more BirdNET-Analyzer result CSV files and returns a tidy
#' data frame in match object format, ready for
#' [standardize_match_data()] and downstream TaxaLikely processing.
#'
#' @param files Character vector. Paths to BirdNET result CSV files
#'   (typically named `recording.BirdNET.results.csv`). Alternatively, a path
#'   to a directory: all `*.BirdNET.results.csv` files in that directory
#'   (non-recursive) are read.
#' @param min_confidence Numeric. Detections below this confidence are dropped.
#'   Default `0` (keep all). BirdNET's own default threshold is `0.1`.
#' @param top_n Integer or `NULL`. If supplied, only the top `n` detections
#'   (by confidence) within each time window are retained. Default `NULL`
#'   (keep all detections per window). Setting `top_n = 1` retains only the
#'   best species per window; `top_n = 3` reproduces BirdNET's default output
#'   when the tool is run with `--top_n 3`.
#'
#' @return A data frame with one row per file × time-window × detected
#'   species, containing:
#'   \describe{
#'     \item{`observation_id`}{Unique identifier combining file stem and time
#'       window: `"{file_stem}_{start_s}-{end_s}"`. Pass as
#'       `observation_id_col` to [standardize_match_data()].}
#'     \item{`score`}{BirdNET confidence (0–1). Pass as `score_col` to
#'       [standardize_match_data()].}
#'     \item{`species`}{Full scientific binomial as reported by BirdNET.}
#'     \item{`genus`}{Genus name (first word of `species`).}
#'     \item{`common_name`}{English common name.}
#'     \item{`start_s`}{Detection window start time in seconds.}
#'     \item{`end_s`}{Detection window end time in seconds.}
#'     \item{`source_file`}{Basename of the source BirdNET result file.}
#'   }
#'
#' @details
#' **BirdNET output format:** BirdNET-Analyzer (v2.x) produces one CSV per
#' audio file with columns: `Start (s)`, `End (s)`, `Scientific name`,
#' `Common name`, `Confidence`. Each row is one candidate species detection
#' within a 3-second window (BirdNET's default segment length). Multiple
#' rows per window occur when BirdNET returns top-N results.
#'
#' **observation_id encoding:** Each time window in each recording is one
#' `observation_id`. Multiple detections within the same window share the
#' same `observation_id` (analogous to multiple BLAST hits per eDNA query).
#' The gap metric in TaxaLikely is computed as the difference between the
#' top-1 and top-2 confidence scores within each window — so retaining
#' multiple detections per window is important for model training.
#'
#' **Taxonomy:** `genus` is derived as the first word of BirdNET's scientific
#' name. `species` is the full binomial. For the full taxonomic hierarchy
#' (family, order, class), run [TaxaTools::verify_taxon_names()] and
#' [TaxaTools::change_backbone()] on the `species` column after
#' standardization, then re-run [standardize_match_data()].
#'
#' **Downstream workflow:**
#' ```r
#' match_df <- read_birdnet_output("birdnet_results/", min_confidence = 0.1) |>
#'   standardize_match_data(
#'     observation_id_col = "observation_id",
#'     score_col          = "score",
#'     rank_system        = c("genus", "species")
#'   )
#' ```
#'
#' @seealso [standardize_match_data()],
#'   [`TaxaLikely::fetch_reference_recordings()`][TaxaLikely::fetch_reference_recordings]
#'
#' @export
#'
#' @examples
#' # Synthetic BirdNET output for two recordings
#' tmp1 <- tempfile(fileext = ".BirdNET.results.csv")
#' tmp2 <- tempfile(fileext = ".BirdNET.results.csv")
#'
#' write.csv(data.frame(
#'   "Start (s)"       = c(0.0, 0.0, 3.0),
#'   "End (s)"         = c(3.0, 3.0, 6.0),
#'   "Scientific name" = c("Turdus migratorius", "Setophaga petechia",
#'                         "Turdus migratorius"),
#'   "Common name"     = c("American Robin", "Yellow Warbler",
#'                         "American Robin"),
#'   "Confidence"      = c(0.92, 0.45, 0.87),
#'   check.names = FALSE, stringsAsFactors = FALSE
#' ), tmp1, row.names = FALSE)
#'
#' write.csv(data.frame(
#'   "Start (s)"       = 0.0,
#'   "End (s)"         = 3.0,
#'   "Scientific name" = "Corvus brachyrhynchos",
#'   "Common name"     = "American Crow",
#'   "Confidence"      = 0.78,
#'   check.names = FALSE, stringsAsFactors = FALSE
#' ), tmp2, row.names = FALSE)
#'
#' result <- read_birdnet_output(c(tmp1, tmp2), min_confidence = 0.5)
#' head(result)
#' unlink(c(tmp1, tmp2))
read_birdnet_output <- function(files,
                                min_confidence = 0,
                                top_n          = NULL) {

  # ---- validate inputs -------------------------------------------------------
  if (!is.character(files) || length(files) == 0L) {
    stop(
      "read_birdnet_output: 'files' must be a non-empty character vector of ",
      "file paths or a single directory path."
    )
  }
  if (!is.numeric(min_confidence) || length(min_confidence) != 1L ||
      is.na(min_confidence)) {
    stop("read_birdnet_output: 'min_confidence' must be a length-1 numeric.")
  }
  if (!is.null(top_n)) {
    top_n <- as.integer(top_n)
    if (is.na(top_n) || top_n < 1L) {
      stop("read_birdnet_output: 'top_n' must be a positive integer or NULL.")
    }
  }

  # ---- resolve directory vs file list ----------------------------------------
  if (length(files) == 1L && dir.exists(files)) {
    files <- list.files(files, pattern = "\\.BirdNET\\.results\\.csv$",
                        full.names = TRUE, recursive = FALSE)
    if (length(files) == 0L) {
      stop(
        "read_birdnet_output: no *.BirdNET.results.csv files found in directory."
      )
    }
  } else {
    missing_files <- files[!file.exists(files)]
    if (length(missing_files) > 0L) {
      stop(sprintf(
        "read_birdnet_output: file(s) not found:\n  %s",
        paste(missing_files, collapse = "\n  ")
      ))
    }
  }

  # ---- read each file --------------------------------------------------------
  rows <- vector("list", length(files))
  for (i in seq_along(files)) {
    rows[[i]] <- .parse_birdnet_file(files[[i]])
  }
  out <- do.call(rbind, rows)

  # ---- apply filters ---------------------------------------------------------
  out <- out[!is.na(out$score) & out$score >= min_confidence, , drop = FALSE]

  if (!is.null(top_n)) {
    # Within each observation_id keep top-n by score (descending)
    out <- do.call(rbind, lapply(split(out, out$observation_id), function(g) {
      g[order(g$score, decreasing = TRUE), ][seq_len(min(nrow(g), top_n)), ,
                                              drop = FALSE]
    }))
    rownames(out) <- NULL
  }

  out
}


# ==============================================================================
# Internal: .parse_birdnet_file()
# ==============================================================================

#' Parse a single BirdNET-Analyzer result CSV into a match-ready data frame
#' @param f Character. Path to a single BirdNET result CSV file.
#' @return Data frame with canonical match columns.
#' @noRd
.parse_birdnet_file <- function(f) {
  required_cols <- c("Start (s)", "End (s)", "Scientific name",
                     "Common name", "Confidence")

  df <- tryCatch(
    utils::read.csv(f, check.names = FALSE, stringsAsFactors = FALSE),
    error = function(e) stop(sprintf(
      "read_birdnet_output: could not read '%s': %s",
      basename(f), conditionMessage(e)
    ))
  )

  missing_cols <- setdiff(required_cols, names(df))
  if (length(missing_cols) > 0L) {
    stop(sprintf(
      paste0(
        "read_birdnet_output: file '%s' is missing required column(s): %s\n",
        "Expected BirdNET-Analyzer CSV with: Start (s), End (s), ",
        "Scientific name, Common name, Confidence."
      ),
      basename(f), paste(missing_cols, collapse = ", ")
    ))
  }

  # Build observation_id: strip extensions .csv -> .results -> .BirdNET
  stem <- tools::file_path_sans_ext(
    tools::file_path_sans_ext(basename(f))   # strips .csv, then .results
  )
  stem <- sub("\\.BirdNET$", "", stem)

  start_vals <- as.numeric(df[["Start (s)"]])
  end_vals   <- as.numeric(df[["End (s)"]])

  data.frame(
    observation_id = paste0(stem, "_", start_vals, "-", end_vals),
    score          = as.numeric(df[["Confidence"]]),
    species        = trimws(df[["Scientific name"]]),
    genus          = sub("^(\\S+).*", "\\1", trimws(df[["Scientific name"]])),
    common_name    = trimws(df[["Common name"]]),
    start_s        = start_vals,
    end_s          = end_vals,
    source_file    = basename(f),
    stringsAsFactors = FALSE
  )
}
