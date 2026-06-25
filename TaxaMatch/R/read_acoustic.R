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
#' @param files Character vector of paths to BirdNET result CSV files
#'   (typically named `recording.BirdNET.results.csv`); a path to a directory
#'   (all `*.BirdNET.results.csv` files are read non-recursively); or a data
#'   frame already loaded into R. The data frame path accepts both the original
#'   BirdNET column names (`"Start (s)"`, `"Scientific name"`, etc.) and the
#'   R-mangled versions produced by `read.csv()` with `check.names = TRUE`
#'   (`"Start..s."`, `"Scientific.name"`, etc.). A `"File"` column must be
#'   present (Gradio / web interface combined-CSV format) to derive
#'   `observation_id` stems; CLI per-recording CSVs should be passed as file
#'   paths rather than pre-loaded data frames.
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
#' **BirdNET output formats:** Two formats are supported:
#'
#' *CLI format* (recommended): BirdNET-Analyzer (v2.x) run from the command
#' line produces one CSV per audio file, typically named
#' `recording.BirdNET.results.csv`, with columns `Start (s)`, `End (s)`,
#' `Scientific name`, `Common name`, `Confidence`. The recording identity is
#' encoded in the CSV filename and used as the `observation_id` stem.
#' Pass a directory of these files or a character vector of paths.
#'
#' *Combined format*: The BirdNET web interface (Gradio) and some third-party
#' tools export a single CSV covering all recordings, with an additional `File`
#' column containing the audio file path. When a `File` column is present,
#' the `observation_id` stem is derived from the audio filename in that column
#' rather than the CSV filename, so detections from different recordings remain
#' distinct even in a single combined export.
#'
#' Each row is one candidate species detection within a 3-second window
#' (BirdNET's default segment length). Multiple rows per window occur when
#' BirdNET returns top-N results.
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
  if ((!is.character(files) || length(files) == 0L) && !is.data.frame(files)) {
    stop(
      "read_birdnet_output: 'files' must be a non-empty character vector of ",
      "file paths, a single directory path, or a BirdNET results data frame."
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

  # ---- data frame path -------------------------------------------------------
  if (is.data.frame(files)) {
    out <- .parse_birdnet_df(files)
  } else {

    # ---- resolve directory vs file list --------------------------------------
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

    # ---- read each file ------------------------------------------------------
    rows <- vector("list", length(files))
    for (i in seq_along(files)) {
      rows[[i]] <- .parse_birdnet_file(files[[i]])
    }
    out <- do.call(rbind, rows)
  }

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

  if (nrow(df) == 0L) {
    message(sprintf("read_birdnet_output: '%s' has no detections (empty file).",
                    basename(f)))
    return(data.frame(
      observation_id = character(0),
      score          = numeric(0),
      species        = character(0),
      genus          = character(0),
      common_name    = character(0),
      start_s        = numeric(0),
      end_s          = numeric(0),
      source_file    = character(0),
      stringsAsFactors = FALSE
    ))
  }

  start_vals <- as.numeric(df[["Start (s)"]])
  end_vals   <- as.numeric(df[["End (s)"]])

  # Derive recording stem for observation_id.
  # Two supported formats:
  #   CLI format  — one CSV per recording (no "File" column); stem from filename.
  #   Combined format — single CSV covering multiple recordings, "File" column
  #                     holds the audio path (e.g. Gradio / web interface output).
  if ("File" %in% names(df)) {
    # Use audio filename stem from the "File" column, per row
    stem_vals <- tools::file_path_sans_ext(basename(trimws(df[["File"]])))
  } else {
    # Strip .csv, .results, .BirdNET suffixes from the CSV filename
    stem_base <- tools::file_path_sans_ext(
      tools::file_path_sans_ext(basename(f))
    )
    stem_base  <- sub("\\.BirdNET$", "", stem_base)
    stem_vals  <- rep(stem_base, nrow(df))
  }

  data.frame(
    observation_id = paste0(stem_vals, "_", start_vals, "-", end_vals),
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


# ==============================================================================
# Internal: .parse_birdnet_df()
# ==============================================================================

#' Parse an already-loaded BirdNET data frame into a match-ready data frame
#'
#' Accepts both the original BirdNET column names ("Start (s)", "Scientific name",
#' etc.) and the R-mangled versions produced by read.csv() with check.names = TRUE
#' ("Start..s.", "Scientific.name", etc.).
#' @param df Data frame. A BirdNET results table already loaded into R.
#' @return Data frame with canonical match columns.
#' @noRd
.parse_birdnet_df <- function(df) {

  # Map R-mangled names back to canonical BirdNET column names so the rest of
  # the parsing logic is identical regardless of how the CSV was read.
  name_map <- c(
    "Start..s."      = "Start (s)",
    "End..s."        = "End (s)",
    "Scientific.name" = "Scientific name",
    "Common.name"    = "Common name"
  )
  idx <- match(names(df), names(name_map))
  names(df)[!is.na(idx)] <- name_map[idx[!is.na(idx)]]

  required_cols <- c("Start (s)", "End (s)", "Scientific name",
                     "Common name", "Confidence")
  missing_cols <- setdiff(required_cols, names(df))
  if (length(missing_cols) > 0L) {
    stop(sprintf(
      paste0(
        "read_birdnet_output: data frame is missing required column(s): %s\n",
        "Expected BirdNET columns: Start (s), End (s), ",
        "Scientific name, Common name, Confidence."
      ),
      paste(missing_cols, collapse = ", ")
    ))
  }

  if (nrow(df) == 0L) {
    message("read_birdnet_output: data frame has no rows (empty).")
    return(data.frame(
      observation_id = character(0),
      score          = numeric(0),
      species        = character(0),
      genus          = character(0),
      common_name    = character(0),
      start_s        = numeric(0),
      end_s          = numeric(0),
      source_file    = character(0),
      stringsAsFactors = FALSE
    ))
  }

  start_vals <- as.numeric(df[["Start (s)"]])
  end_vals   <- as.numeric(df[["End (s)"]])

  if ("File" %in% names(df)) {
    stem_vals <- tools::file_path_sans_ext(basename(trimws(df[["File"]])))
  } else {
    stop(
      "read_birdnet_output: data frame has no 'File' column. ",
      "Supply file path(s) instead, or add a 'File' column containing the ",
      "audio file path for each row."
    )
  }

  data.frame(
    observation_id = paste0(stem_vals, "_", start_vals, "-", end_vals),
    score          = as.numeric(df[["Confidence"]]),
    species        = trimws(df[["Scientific name"]]),
    genus          = sub("^(\\S+).*", "\\1", trimws(df[["Scientific name"]])),
    common_name    = trimws(df[["Common name"]]),
    start_s        = start_vals,
    end_s          = end_vals,
    source_file    = tools::file_path_sans_ext(basename(trimws(df[["File"]]))),
    stringsAsFactors = FALSE
  )
}
