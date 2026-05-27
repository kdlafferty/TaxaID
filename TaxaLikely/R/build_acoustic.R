# ==============================================================================
# build_acoustic.R
# TaxaLikely -- Build acoustic reference dataset for likelihood model training
#
# Exported functions:
#   build_acoustic_reference()   Join BirdNET detections to Xeno-canto ground
#                                truth, label H1/H2/H3, produce pair format
#                                for train_likelihood_model()
# ==============================================================================


#' Build an Acoustic Reference Dataset for Likelihood Model Training
#'
#' Joins BirdNET-Analyzer detections to Xeno-canto ground-truth labels and
#' produces a pairwise training dataset in the same format as
#' [build_sequence_matrix()], ready for [train_likelihood_model()].
#'
#' Each time window in a reference recording becomes a query (`id_x`).  Each
#' BirdNET detection in that window becomes a candidate match (`id_y`).
#' Windows where BirdNET detects the correct species produce H1
#' (within-species) rows; detections of wrong species produce H2/H3
#' (cross-species) rows.  The match score is BirdNET confidence (0--1).
#'
#' **Controlling for recording type:** The `testid` column stores the
#' Xeno-canto `type` tag (e.g. `"song"`, `"call"`, `"flight call"`).
#' Train a separate model per type -- exactly as you would train a separate
#' model per barcode marker in eDNA.  Filter before training:
#' ```r
#' songs  <- subset(ref_pairs, testid == "song")
#' model_song <- train_likelihood_model(songs,
#'                                      rank_system = c("genus", "species"))
#' calls  <- subset(ref_pairs, testid == "call")
#' model_call <- train_likelihood_model(calls,
#'                                      rank_system = c("genus", "species"))
#' ```
#'
#' **Gap computation:** Set `top_n >= 2` in
#' [TaxaMatch::read_birdnet_output()] so each time window has at least two
#' candidates. The gap (best score minus runner-up score) is the key
#' discriminator in [train_likelihood_model()] and is computed from the pair
#' rows produced here.
#'
#' **Background species:** Recordings often contain species other than the
#' target.  Use the `exclude_background` parameter to drop detections of
#' species listed in `recordings_meta$also_species`, preventing background
#' detections from being mis-labelled as H2/H3 errors.
#'
#' @param birdnet_df Data frame. Output of [TaxaMatch::read_birdnet_output()]
#'   with `top_n >= 2` recommended.  Required columns: `observation_id`,
#'   `score`, `species`, `genus`, `source_file`.
#' @param recordings_meta Data frame. Output of [fetch_reference_recordings()]
#'   with `download = TRUE` so that `local_path` is populated.  Required
#'   columns: `recording_id`, `species`, `genus`, `local_path`.  The `type`
#'   column (when present) is used as `testid`.
#' @param rank_system Character vector of rank names coarse-to-fine.  Default
#'   `c("genus", "species")`.  Must be present in both `birdnet_df` and
#'   `recordings_meta`.
#' @param min_confidence Numeric. Drop BirdNET detections below this threshold
#'   before building pairs.  Default `0` (keep all).
#' @param exclude_background Logical. If `TRUE` (default), drop detections
#'   where the identified species appears in `recordings_meta$also_species`
#'   (background species audible in the recording).  Background detections are
#'   not false positives in the conventional sense and should not train H2/H3.
#'
#' @return A data frame with one row per (time window x BirdNET detection)
#'   pair, containing:
#'   \describe{
#'     \item{`id_x`}{`observation_id` of the time window (the query).}
#'     \item{`id_y`}{Synthetic unique identifier for the detection
#'       (`"{observation_id}_det{rank}"`).}
#'     \item{`p_match`}{BirdNET confidence (0--1).}
#'     \item{`{rank}.x`}{Ground-truth taxonomy from `recordings_meta`.}
#'     \item{`{rank}.y`}{BirdNET-detected taxonomy from `birdnet_df`.}
#'     \item{`testid`}{Xeno-canto recording type (e.g. `"song"`, `"call"`);
#'       `NA` if absent.  Filter on this column to train type-specific models.}
#'     \item{`recording_id`}{Xeno-canto recording ID for traceability.}
#'     \item{`start_s`, `end_s`}{Time window boundaries (seconds).}
#'   }
#'
#' @details
#' **Join key:** `source_file` from `birdnet_df` is matched to `local_path`
#' from `recordings_meta` by comparing file stems (stripping
#' `.BirdNET.results.csv` and the audio extension respectively).  Audio
#' files must have been downloaded with
#' `fetch_reference_recordings(download = TRUE)`.
#'
#' **Output format compatibility:** The `.x`/`.y` suffix convention and
#' `p_match` column name match the output of [build_sequence_matrix()], so
#' [train_likelihood_model()] and [flag_reference_errors()] accept this
#' data frame directly.
#'
#' @seealso [fetch_reference_recordings()],
#'   [TaxaMatch::read_birdnet_output()][TaxaMatch::read_birdnet_output],
#'   [build_sequence_matrix()], [train_likelihood_model()]
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # 1. Fetch reference recordings and download audio
#' recs <- fetch_reference_recordings(
#'   species      = c("Turdus migratorius", "Setophaga petechia"),
#'   quality      = c("A", "B"),
#'   type         = "song",
#'   download     = TRUE,
#'   download_dir = "reference_audio/"
#' )
#'
#' # 2. Run BirdNET-Analyzer on reference_audio/ (Python, outside R)
#' #    pip3 install birdnetlib
#' #    See TaxaMatch README for the analysis script.
#'
#' # 3. Read BirdNET detections (top_n = 3 to enable gap computation)
#' birdnet_df <- TaxaMatch::read_birdnet_output(
#'   "birdnet_results/",
#'   top_n = 3L
#' )
#'
#' # 4. Build pairwise training dataset
#' ref_pairs <- build_acoustic_reference(
#'   birdnet_df      = birdnet_df,
#'   recordings_meta = recs,
#'   rank_system     = c("genus", "species")
#' )
#'
#' # 5. Train one model per recording type
#' model_song <- train_likelihood_model(
#'   subset(ref_pairs, testid == "song"),
#'   rank_system = c("genus", "species")
#' )
#' }
build_acoustic_reference <- function(birdnet_df,
                                     recordings_meta,
                                     rank_system          = c("genus", "species"),
                                     min_confidence       = 0.0,
                                     exclude_background   = TRUE) {

  # ---- input validation -------------------------------------------------------
  if (!is.data.frame(birdnet_df))
    stop("build_acoustic_reference: 'birdnet_df' must be a data frame.")
  if (!is.data.frame(recordings_meta))
    stop("build_acoustic_reference: 'recordings_meta' must be a data frame.")

  needed_bn <- c("observation_id", "score", "species", "genus", "source_file")
  missing_bn <- setdiff(needed_bn, names(birdnet_df))
  if (length(missing_bn) > 0L)
    stop(sprintf(
      "build_acoustic_reference: 'birdnet_df' is missing columns: %s.",
      paste(missing_bn, collapse = ", ")
    ))

  needed_meta <- c("recording_id", "species", "genus", "local_path")
  missing_meta <- setdiff(needed_meta, names(recordings_meta))
  if (length(missing_meta) > 0L)
    stop(sprintf(
      "build_acoustic_reference: 'recordings_meta' is missing columns: %s.",
      paste(missing_meta, collapse = ", ")
    ))

  if (any(is.na(recordings_meta$local_path))) {
    n_na <- sum(is.na(recordings_meta$local_path))
    stop(sprintf(paste0(
      "build_acoustic_reference: %d recording(s) have NA local_path. ",
      "Re-run fetch_reference_recordings() with download = TRUE."
    ), n_na))
  }

  if (!is.numeric(min_confidence) || length(min_confidence) != 1L ||
      is.na(min_confidence))
    stop("build_acoustic_reference: 'min_confidence' must be a single numeric value.")
  if (!is.logical(exclude_background) || length(exclude_background) != 1L ||
      is.na(exclude_background))
    stop("build_acoustic_reference: 'exclude_background' must be TRUE or FALSE.")

  rank_system <- tolower(trimws(rank_system))

  # ---- confidence filter ------------------------------------------------------
  birdnet_df <- birdnet_df[birdnet_df$score >= min_confidence, , drop = FALSE]
  if (nrow(birdnet_df) == 0L)
    stop("build_acoustic_reference: no detections remain after min_confidence filter.")

  # ---- build join key: file stem ----------------------------------------------
  # birdnet source_file:  "XC123456_Turdus_migratorius.BirdNET.results.csv"
  # recordings local_path: "reference_audio/XC123456_Turdus_migratorius.mp3"
  birdnet_df$file_stem <- sub(
    "\\.BirdNET\\.results\\.csv$", "",
    birdnet_df$source_file,
    ignore.case = TRUE
  )
  recordings_meta$file_stem <- tools::file_path_sans_ext(
    basename(recordings_meta$local_path)
  )

  # ---- check join coverage ----------------------------------------------------
  unmatched <- setdiff(unique(birdnet_df$file_stem),
                       unique(recordings_meta$file_stem))
  if (length(unmatched) > 0L) {
    warning(sprintf(
      "build_acoustic_reference: %d BirdNET file stem(s) not found in recordings_meta: %s",
      length(unmatched),
      paste(utils::head(unmatched, 3L), collapse = ", ")
    ), call. = FALSE)
  }

  # ---- exclude background species detections ----------------------------------
  if (isTRUE(exclude_background) && "also_species" %in% names(recordings_meta)) {
    # Build a lookup: file_stem -> character vector of background species
    bg_lookup <- recordings_meta[, c("file_stem", "also_species"), drop = FALSE]
    bg_lookup$also_species[is.na(bg_lookup$also_species)] <- ""
    bg_vec <- stats::setNames(bg_lookup$also_species, bg_lookup$file_stem)

    is_background <- mapply(function(stem, sp) {
      bg_str <- bg_vec[stem]
      if (is.na(bg_str) || !nzchar(bg_str)) return(FALSE)
      # also_species is comma-separated; check if sp appears
      grepl(sp, bg_str, fixed = TRUE)
    }, birdnet_df$file_stem, birdnet_df$species)

    n_bg <- sum(is_background, na.rm = TRUE)
    if (n_bg > 0L)
      message(sprintf(
        "build_acoustic_reference: dropped %d detection(s) of background species.",
        n_bg
      ))
    birdnet_df <- birdnet_df[!is_background, , drop = FALSE]
  }

  # ---- prepare ground-truth lookup --------------------------------------------
  rank_cols_meta <- intersect(rank_system, names(recordings_meta))
  has_type       <- "type" %in% names(recordings_meta)

  meta_keep <- c("file_stem", "recording_id", rank_cols_meta,
                 if (has_type) "type")
  gt_lookup <- recordings_meta[, meta_keep, drop = FALSE]
  # Remove duplicate file stems (guard against multiple downloads)
  gt_lookup <- gt_lookup[!duplicated(gt_lookup$file_stem), , drop = FALSE]

  # ---- join: gt_lookup (x) left-merges onto birdnet_df (y) -------------------
  # Merge order: gt_lookup first so that overlapping rank columns get
  # .x (ground truth / query) and .y (BirdNET detection / match) suffixes,
  # matching the build_sequence_matrix() convention used by train_likelihood_model().
  merged <- merge(gt_lookup, birdnet_df, by = "file_stem", all = FALSE)
  row.names(merged) <- NULL

  n_unjoined_bn <- nrow(birdnet_df) -
    sum(birdnet_df$file_stem %in% gt_lookup$file_stem)
  if (n_unjoined_bn > 0L)
    warning(sprintf(
      "build_acoustic_reference: %d BirdNET row(s) had no matching recording in recordings_meta and were dropped.",
      n_unjoined_bn
    ), call. = FALSE)

  if (nrow(merged) == 0L)
    stop("build_acoustic_reference: no rows remain after joining birdnet_df to recordings_meta.")

  # ---- rank columns: resolve .x/.y naming ------------------------------------
  # After merge(gt_lookup, birdnet_df):
  #   rank.x = ground truth (from gt_lookup)  <- query
  #   rank.y = BirdNET detected (from birdnet_df) <- match
  # Any rank in only one side comes through without a suffix.
  # Ensure both .x and .y columns exist for every rank in rank_system.
  rank_cols_bn <- intersect(rank_system, names(birdnet_df))
  for (rk in rank_system) {
    x_col <- paste0(rk, ".x")
    y_col <- paste0(rk, ".y")
    # If merge didn't add suffixes (column in only one side), rename manually
    if (!x_col %in% names(merged) && rk %in% names(merged)) {
      # Only ground truth side had this rank
      names(merged)[names(merged) == rk] <- x_col
    }
    if (!y_col %in% names(merged)) {
      merged[[y_col]] <- NA_character_
    }
  }

  # ---- sort detections within each window by confidence (desc) ---------------
  merged <- merged[order(merged$observation_id, -merged$score), , drop = FALSE]
  row.names(merged) <- NULL

  # Detection rank within each window (1 = best)
  merged$det_rank <- sequence(rle(merged$observation_id)$lengths)

  # ---- assemble output -------------------------------------------------------
  merged$id_x    <- merged$observation_id
  merged$id_y    <- paste0(merged$observation_id, "_det", merged$det_rank)
  merged$p_match <- merged$score
  merged$testid  <- if (has_type) merged$type else NA_character_

  rank_x_cols <- paste0(intersect(rank_system, gsub("\\.x$", "",
                                   grep("\\.x$", names(merged), value = TRUE))),
                         ".x")
  rank_y_cols <- paste0(intersect(rank_system, gsub("\\.y$", "",
                                   grep("\\.y$", names(merged), value = TRUE))),
                         ".y")

  keep_cols <- c("id_x", "id_y", "p_match",
                 rank_x_cols, rank_y_cols,
                 "testid", "recording_id",
                 if ("start_s" %in% names(merged)) "start_s",
                 if ("end_s"   %in% names(merged)) "end_s")
  keep_cols <- keep_cols[keep_cols %in% names(merged)]

  out <- merged[, keep_cols, drop = FALSE]
  row.names(out) <- NULL

  # ---- summary message -------------------------------------------------------
  finest  <- rank_system[length(rank_system)]
  x_col_f <- paste0(finest, ".x")
  y_col_f <- paste0(finest, ".y")

  n_h1 <- if (x_col_f %in% names(out) && y_col_f %in% names(out))
    sum(!is.na(out[[x_col_f]]) & !is.na(out[[y_col_f]]) &
          out[[x_col_f]] == out[[y_col_f]])
  else NA_integer_

  n_recordings <- length(unique(recordings_meta$recording_id))
  n_windows    <- length(unique(out$id_x))

  if (!is.na(n_h1)) {
    message(sprintf(
      "build_acoustic_reference: %d recording(s), %d time window(s), %d pairs (%d H1, %d H2/H3).",
      n_recordings, n_windows, nrow(out), n_h1, nrow(out) - n_h1
    ))
  } else {
    message(sprintf(
      "build_acoustic_reference: %d recording(s), %d time window(s), %d pairs.",
      n_recordings, n_windows, nrow(out)
    ))
  }

  out
}
