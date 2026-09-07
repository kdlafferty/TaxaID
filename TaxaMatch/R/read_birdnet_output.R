# ==============================================================================
# read_birdnet_output.R
# TaxaMatch -- Ingest acoustic classifier output into the match object format
#
# Exported functions:
#   read_birdnet_output()   Ingest BirdNET-Analyzer CSV results
#
# Internal helpers (@noRd):
#   .parse_birdnet_file()   Read and validate a single BirdNET CSV
#   .parse_birdnet_df()     Parse an already-loaded BirdNET data frame
#   .empty_birdnet_result() Shared 0-row constructor for the "no detections" case
# ==============================================================================

#' @noRd
.empty_birdnet_result <- function() {
  data.frame(
    observation_id = character(0), score = numeric(0),
    species = character(0), genus = character(0),
    common_name = character(0), start_s = numeric(0),
    end_s = numeric(0), source_file = character(0),
    stringsAsFactors = FALSE
  )
}


# ==============================================================================
# read_birdnet_output
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
#'       window: `"{file_stem}_{start_s}-{end_s}"`, with `start_s`/`end_s`
#'       formatted to a fixed 1 decimal place so the same window produces the
#'       same ID across platforms/R versions. Pass as `observation_id_col` to
#'       [standardize_match_data()].}
#'     \item{`score`}{BirdNET confidence (0–1). Pass as `score_col` to
#'       [standardize_match_data()].}
#'     \item{`species`}{Full scientific binomial as reported by BirdNET.}
#'     \item{`genus`}{Genus name (first word of `species`); `NA` for
#'       non-standard binomial formats.}
#'     \item{`common_name`}{English common name.}
#'     \item{`start_s`}{Detection window start time in seconds.}
#'     \item{`end_s`}{Detection window end time in seconds.}
#'     \item{`source_file`}{For the file-path input path, the basename of the
#'       source BirdNET result CSV. For the combined/Gradio data-frame input
#'       path, there is no CSV path to report (the data frame was already
#'       loaded before being passed in); this is instead the audio filename
#'       stem from the `File` column, which may equal that column's own
#'       value and should not be assumed to be a CSV filename.}
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
#' distinct even in a single combined export -- except when two different
#' recordings happen to share the same basename (e.g. `recording.wav` from
#' different directories), which produces colliding `observation_id` stems; a
#' `warning()` is issued when this is detected in the `File` column.
#'
#' Only the default CSV output (`--rtype csv`, or the equivalent legacy
#' default) is supported. BirdNET-Analyzer v2.4+'s `--rtype` flag can produce
#' other formats (Audacity, R, kaleidoscope, table); passing one of those
#' files here will fail the required-column check with an uninformative
#' column list rather than a format-specific error. Per-recording metadata
#' some BirdNET output modes include (latitude/longitude, week number,
#' sensitivity) is not read or preserved.
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
#' name (`NA` for non-standard binomial formats such as hybrid notations or
#' undescribed-species placeholders). `species` is the full binomial. For the
#' full taxonomic hierarchy (family, order, class), run
#' [TaxaTools::verify_taxon_names()] and [convert_taxonomy_backbone()] on the
#' `species` column after standardization, then re-run
#' [standardize_match_data()].
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
#' @seealso [standardize_match_data()]
#'
#' @export
#'
#' @examples
#' # Synthetic BirdNET output for two recordings
#' tmp1 <- tempfile(fileext = ".BirdNET.results.csv")
#' tmp2 <- tempfile(fileext = ".BirdNET.results.csv")
#'
#' write.csv(data.frame(
#'   "Start (s)" = c(0.0, 0.0, 3.0),
#'   "End (s)" = c(3.0, 3.0, 6.0),
#'   "Scientific name" = c(
#'     "Turdus migratorius", "Setophaga petechia",
#'     "Turdus migratorius"
#'   ),
#'   "Common name" = c(
#'     "American Robin", "Yellow Warbler",
#'     "American Robin"
#'   ),
#'   "Confidence" = c(0.92, 0.45, 0.87),
#'   check.names = FALSE, stringsAsFactors = FALSE
#' ), tmp1, row.names = FALSE)
#'
#' write.csv(data.frame(
#'   "Start (s)" = 0.0,
#'   "End (s)" = 3.0,
#'   "Scientific name" = "Corvus brachyrhynchos",
#'   "Common name" = "American Crow",
#'   "Confidence" = 0.78,
#'   check.names = FALSE, stringsAsFactors = FALSE
#' ), tmp2, row.names = FALSE)
#'
#' result <- read_birdnet_output(c(tmp1, tmp2), min_confidence = 0.5)
#' head(result)
#' unlink(c(tmp1, tmp2))
read_birdnet_output <- function(files,
                                min_confidence = 0,
                                top_n = NULL) {
  # ---- validate inputs -------------------------------------------------------
  if ((!is.character(files) || length(files) == 0L) && !is.data.frame(files)) {
    stop(
      "read_birdnet_output: 'files' must be a non-empty character vector of ",
      "file paths, a single directory path, or a BirdNET results data frame."
    )
  }
  top_n <- .validate_min_conf_top_n(min_confidence, top_n, "read_birdnet_output")

  # ---- data frame path -------------------------------------------------------
  if (is.data.frame(files)) {
    out <- .parse_birdnet_df(files)
  } else {
    # ---- resolve directory vs file list --------------------------------------
    if (length(files) == 1L && dir.exists(files)) {
      files <- list.files(files,
        pattern = "\\.BirdNET\\.results\\.csv$",
        full.names = TRUE, recursive = FALSE
      )
      if (length(files) == 0L) {
        stop(
          "read_birdnet_output: no *.BirdNET.results.csv files found in directory."
        )
      }
    } else {
      missing_files <- files[!file.exists(files)]
      if (length(missing_files) > 0L) {
        .stop_missing_files(missing_files, "read_birdnet_output")
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

  out <- .apply_top_n(out, "observation_id", "score", top_n)
  rownames(out) <- NULL

  out
}


# ==============================================================================
# Internal: .parse_birdnet_file
# ==============================================================================

#' Parse a single BirdNET-Analyzer result CSV into a match-ready data frame
#' @param f Character. Path to a single BirdNET result CSV file.
#' @return Data frame with canonical match columns.
#' @noRd
.parse_birdnet_file <- function(f) {
  required_cols <- c(
    "Start (s)", "End (s)", "Scientific name",
    "Common name", "Confidence"
  )

  df <- tryCatch(
    utils::read.csv(f, check.names = FALSE, stringsAsFactors = FALSE),
    error = function(e) {
      stop(sprintf(
        "read_birdnet_output: could not read '%s': %s",
        basename(f), conditionMessage(e)
      ))
    }
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
    message(sprintf(
      "read_birdnet_output: '%s' has no detections (empty file).",
      basename(f)
    ))
    return(.empty_birdnet_result())
  }

  start_vals <- as.numeric(df[["Start (s)"]])
  end_vals <- as.numeric(df[["End (s)"]])
  conf_vals <- as.numeric(df[["Confidence"]])
  .warn_na_coercion(df[["Start (s)"]], start_vals, "Start (s)", basename(f))
  .warn_na_coercion(df[["End (s)"]], end_vals, "End (s)", basename(f))
  .warn_na_coercion(df[["Confidence"]], conf_vals, "Confidence", basename(f))

  bad_window <- !is.na(start_vals) & !is.na(end_vals) & end_vals <= start_vals
  if (any(bad_window)) {
    warning(sprintf(
      "read_birdnet_output: '%s' has %d row(s) with End (s) <= Start (s); keeping as-is.",
      basename(f), sum(bad_window)
    ))
  }

  # Derive recording stem for observation_id.
  # Two supported formats:
  #   CLI format  — one CSV per recording (no "File" column); stem from filename.
  #   Combined format — single CSV covering multiple recordings, "File" column
  #                     holds the audio path (e.g. Gradio / web interface output).
  if ("File" %in% names(df)) {
    # Use audio filename stem from the "File" column, per row
    stem_vals <- tools::file_path_sans_ext(basename(trimws(df[["File"]])))
    .warn_duplicate_basenames(df[["File"]], "read_birdnet_output")
  } else {
    # Strip .csv, .results, .BirdNET suffixes from the CSV filename. Kept as
    # a permissive chained strip (not a single fixed-suffix regex) since this
    # function also accepts arbitrary file paths that may not follow the
    # ".BirdNET.results.csv" convention -- a single regex anchored on that
    # exact suffix would leave the extension attached for anything else.
    stem_base <- tools::file_path_sans_ext(
      tools::file_path_sans_ext(basename(f))
    )
    stem_base <- sub("\\.BirdNET$", "", stem_base)
    stem_vals <- rep(stem_base, nrow(df))
  }

  data.frame(
    observation_id = paste0(stem_vals, "_", .fmt_time(start_vals), "-", .fmt_time(end_vals)),
    score = conf_vals,
    species = trimws(df[["Scientific name"]]),
    genus = .extract_genus(trimws(df[["Scientific name"]])),
    common_name = trimws(df[["Common name"]]),
    start_s = start_vals,
    end_s = end_vals,
    source_file = basename(f),
    stringsAsFactors = FALSE
  )
}


# ==============================================================================
# Internal: .parse_birdnet_df
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
    "Start..s." = "Start (s)",
    "End..s." = "End (s)",
    "Scientific.name" = "Scientific name",
    "Common.name" = "Common name"
  )
  idx <- match(names(df), names(name_map))
  names(df)[!is.na(idx)] <- name_map[idx[!is.na(idx)]]

  required_cols <- c(
    "Start (s)", "End (s)", "Scientific name",
    "Common name", "Confidence"
  )
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
    return(.empty_birdnet_result())
  }

  start_vals <- as.numeric(df[["Start (s)"]])
  end_vals <- as.numeric(df[["End (s)"]])
  conf_vals <- as.numeric(df[["Confidence"]])
  .warn_na_coercion(df[["Start (s)"]], start_vals, "Start (s)", "read_birdnet_output")
  .warn_na_coercion(df[["End (s)"]], end_vals, "End (s)", "read_birdnet_output")
  .warn_na_coercion(df[["Confidence"]], conf_vals, "Confidence", "read_birdnet_output")

  bad_window <- !is.na(start_vals) & !is.na(end_vals) & end_vals <= start_vals
  if (any(bad_window)) {
    warning(sprintf(
      "read_birdnet_output: data frame has %d row(s) with End (s) <= Start (s); keeping as-is.",
      sum(bad_window)
    ))
  }

  if ("File" %in% names(df)) {
    stem_vals <- tools::file_path_sans_ext(basename(trimws(df[["File"]])))
    .warn_duplicate_basenames(df[["File"]], "read_birdnet_output")
  } else {
    stop(
      "read_birdnet_output: data frame has no 'File' column. ",
      "Supply file path(s) instead, or add a 'File' column containing the ",
      "audio file path for each row."
    )
  }

  data.frame(
    observation_id = paste0(stem_vals, "_", .fmt_time(start_vals), "-", .fmt_time(end_vals)),
    score = conf_vals,
    species = trimws(df[["Scientific name"]]),
    genus = .extract_genus(trimws(df[["Scientific name"]])),
    common_name = trimws(df[["Common name"]]),
    start_s = start_vals,
    end_s = end_vals,
    # No underlying CSV path exists for the pre-loaded-data-frame input path
    # (that is the point of accepting a data frame directly) -- this is the
    # audio filename stem from the "File" column, not a CSV basename, unlike
    # .parse_birdnet_file()'s source_file. See @return's source_file note.
    source_file = tools::file_path_sans_ext(basename(trimws(df[["File"]]))),
    stringsAsFactors = FALSE
  )
}
