# ==============================================================================
# build_image.R
# TaxaLikely -- Build image-classifier reference dataset for likelihood model
#               training
#
# Exported functions:
#   build_image_reference()   Join classifier detections to ground-truth labels,
#                             label H1/H2/H3, produce pair format for
#                             train_likelihood_model()
# ==============================================================================


#' Build an Image-Classifier Reference Dataset for Likelihood Model Training
#'
#' Joins image classifier detections to ground-truth species labels and
#' produces a pairwise training dataset in the same format as
#' [build_sequence_matrix()] and [build_acoustic_reference()], ready for
#' [train_likelihood_model()].
#'
#' Each reference image becomes a query (`id_x`).  Each classifier
#' detection for that image becomes a candidate match (`id_y`).
#' Detections where the classifier found the correct species produce H1
#' (within-species) rows; detections of wrong species produce H2/H3
#' (cross-species) rows.  The match score is classifier confidence (0--1).
#'
#' **Analogies across data types:**
#' | Data type | Reference unit | Join key | Coverage | testid |
#' |-----------|---------------|----------|----------|--------|
#' | DNA       | sequence      | accession | alignment | barcode marker |
#' | Acoustic  | audio file    | file stem | recording quality | recording type |
#' | Image     | image file    | file stem | bbox area | classifier / image type |
#'
#' **Controlling for image type:** The `testid` column in `images_meta`
#' (optional) stores a category for model stratification — e.g.,
#' `"camera_trap"` vs `"hand_held"`, or classifier name.
#' Train a separate model per type, exactly as you would train a separate model
#' per barcode marker in eDNA or per recording type in acoustics.
#'
#' **Coverage:** If `image_df` includes a `coverage` column (produced by
#' [TaxaMatch::read_animl_output()] when `bbox_cols` is supplied), that value
#' is passed through directly to the output.  Coverage represents the
#' fractional bounding-box area of the image: a small value (distant or
#' partial animal) signals weaker classification evidence.  Where `coverage`
#' is absent from `image_df` but `images_meta$quality` is present (0--1
#' numeric), that quality value is used instead.  If neither is available,
#' `coverage` is `NA`.
#'
#' **Gap computation:** Supply `top_n >= 2` to the reader function
#' ([TaxaMatch::read_animl_output()], etc.) so each image has at least two
#' candidates.  The gap (top-1 minus top-2 confidence) is the key
#' discriminator in [train_likelihood_model()].
#'
#' @param image_df Data frame. Output of [TaxaMatch::read_animl_output()],
#'   [TaxaMatch::read_inaturalist_cv_output()], or any classifier reader with
#'   `top_n >= 2` recommended.  Required columns: `observation_id`, `score`,
#'   `species`, `genus`, `source_file`.
#' @param images_meta Data frame. Ground-truth species labels for reference
#'   images.  Required columns: `image_path` (path to the image file — the
#'   file stem is used as the join key) plus any columns named in
#'   `rank_system` (e.g., `species`, `genus`).  Optional: `testid` (model
#'   stratification category), `quality` (numeric 0--1 image quality score
#'   used as `coverage` when `image_df` lacks a `coverage` column).
#' @param rank_system Character vector of rank names coarse-to-fine.  Default
#'   `c("genus", "species")`.  Must be present in both `image_df` and
#'   `images_meta`.
#' @param min_confidence Numeric. Drop classifier detections below this
#'   threshold before building pairs.  Default `0` (keep all).
#'
#' @return A data frame with one row per (image x classifier detection) pair,
#'   containing:
#'   \describe{
#'     \item{`id_x`}{`observation_id` of the reference image (the query).}
#'     \item{`id_y`}{Synthetic unique identifier for the detection
#'       (`"{observation_id}_det{rank}"`).}
#'     \item{`p_match`}{Classifier confidence (0--1).}
#'     \item{`{rank}.x`}{Ground-truth taxonomy from `images_meta`.}
#'     \item{`{rank}.y`}{Classifier-detected taxonomy from `image_df`.}
#'     \item{`coverage`}{Numeric image quality on a 0 to 1 scale.  Sourced
#'       from `image_df$coverage` (bounding box area fraction) if present,
#'       otherwise from `images_meta$quality`, otherwise `NA`.  Use
#'       [coverage_threshold()] or [calibrate_coverage_filter()] to select
#'       which images to include before calling [train_likelihood_model()].}
#'     \item{`testid`}{Image category from `images_meta$testid`; `NA` if
#'       absent.  Filter on this column to train type-specific models.}
#'     \item{`source_file`}{CSV filename from `image_df` for traceability.}
#'   }
#'
#' @details
#' **Join key:** `observation_id` from `image_df` (the image filename stem as
#' produced by the reader functions) is matched against
#' `tools::file_path_sans_ext(basename(image_path))` from `images_meta`.
#' Ensure image filenames are unique across your reference collection.
#'
#' **Output format compatibility:** The `.x`/`.y` suffix convention and
#' `p_match` column name match the output of [build_sequence_matrix()] and
#' [build_acoustic_reference()], so [train_likelihood_model()] and
#' [flag_reference_errors()] accept this data frame directly.
#'
#' **Non-wildlife detections:** Remove `"empty"`, `"human"`, `"vehicle"` rows
#' from `image_df` before calling this function; they produce uninformative
#' H2/H3 pairs.  See [TaxaMatch::read_animl_output()] for details.
#'
#' @seealso [TaxaMatch::read_animl_output()],
#'   [TaxaMatch::read_inaturalist_cv_output()][TaxaMatch::read_inaturalist_cv_output],
#'   [build_acoustic_reference()], [train_likelihood_model()]
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # 1. Prepare ground-truth reference images
#' # Each row = one reference image + true species label
#' images_meta <- data.frame(
#'   image_path = c("ref_images/img_deer_001.jpg",
#'                  "ref_images/img_deer_002.jpg",
#'                  "ref_images/img_rabbit_001.jpg"),
#'   species    = c("Odocoileus virginianus", "Odocoileus virginianus",
#'                  "Sylvilagus floridanus"),
#'   genus      = c("Odocoileus", "Odocoileus", "Sylvilagus"),
#'   testid     = "camera_trap",
#'   stringsAsFactors = FALSE
#' )
#'
#' # 2. Run Animl on reference images (or any other classifier)
#' animl_df <- TaxaMatch::read_animl_output(
#'   "animl_ref_results/",
#'   min_confidence = 0.1,
#'   top_n          = 3L,
#'   bbox_cols      = c(w = "bbox_w", h = "bbox_h")
#' ) |>
#'   subset(!species %in% c("empty", "human", "vehicle"))
#'
#' # 3. Build pairwise training dataset
#' ref_pairs <- build_image_reference(
#'   image_df    = animl_df,
#'   images_meta = images_meta,
#'   rank_system = c("genus", "species")
#' )
#'
#' # 4. Train model
#' model_camera <- train_likelihood_model(
#'   raw_df      = ref_pairs,
#'   rank_system = c("genus", "species")
#' )
#' }
build_image_reference <- function(image_df,
                                   images_meta,
                                   rank_system    = c("genus", "species"),
                                   min_confidence = 0.0) {

  # ---- input validation -------------------------------------------------------
  if (!is.data.frame(image_df))
    stop("build_image_reference: 'image_df' must be a data frame.")
  if (!is.data.frame(images_meta))
    stop("build_image_reference: 'images_meta' must be a data frame.")

  needed_img <- c("observation_id", "score", "species", "genus", "source_file")
  missing_img <- setdiff(needed_img, names(image_df))
  if (length(missing_img) > 0L)
    stop(sprintf(
      "build_image_reference: 'image_df' is missing columns: %s.",
      paste(missing_img, collapse = ", ")
    ))

  if (!"image_path" %in% names(images_meta))
    stop(paste0(
      "build_image_reference: 'images_meta' must contain an 'image_path' column ",
      "(path to each reference image, used as the join key)."
    ))

  rank_system <- tolower(trimws(rank_system))

  missing_meta_ranks <- setdiff(rank_system, names(images_meta))
  if (length(missing_meta_ranks) > 0L)
    stop(sprintf(
      "build_image_reference: 'images_meta' is missing rank column(s): %s.",
      paste(missing_meta_ranks, collapse = ", ")
    ))

  if (!is.numeric(min_confidence) || length(min_confidence) != 1L ||
      is.na(min_confidence))
    stop("build_image_reference: 'min_confidence' must be a single numeric value.")

  # ---- confidence filter ------------------------------------------------------
  image_df <- image_df[image_df$score >= min_confidence, , drop = FALSE]
  if (nrow(image_df) == 0L)
    stop("build_image_reference: no detections remain after min_confidence filter.")

  # ---- build join key ---------------------------------------------------------
  # image_df$observation_id is already the image file stem (from reader functions)
  # images_meta$image_path -> derive file stem for matching
  image_df$img_stem <- image_df$observation_id
  images_meta$img_stem <- tools::file_path_sans_ext(basename(images_meta$image_path))

  # ---- check join coverage ----------------------------------------------------
  unmatched <- setdiff(unique(image_df$img_stem), unique(images_meta$img_stem))
  if (length(unmatched) > 0L) {
    warning(sprintf(
      "build_image_reference: %d image file stem(s) in image_df not found in images_meta: %s",
      length(unmatched),
      paste(utils::head(unmatched, 3L), collapse = ", ")
    ), call. = FALSE)
  }

  # ---- prepare ground-truth lookup --------------------------------------------
  rank_cols_meta <- intersect(rank_system, names(images_meta))
  has_testid  <- "testid"  %in% names(images_meta)
  has_quality <- "quality" %in% names(images_meta)

  meta_keep <- c("img_stem", rank_cols_meta,
                 if (has_testid)  "testid",
                 if (has_quality) "quality")
  gt_lookup <- images_meta[, meta_keep, drop = FALSE]
  # Remove duplicate file stems (guard against duplicate rows)
  gt_lookup <- gt_lookup[!duplicated(gt_lookup$img_stem), , drop = FALSE]

  # ---- join: gt_lookup (x) left-merges onto image_df (y) ---------------------
  # Merge order: gt_lookup first so that overlapping rank columns get
  # .x (ground truth / query) and .y (classifier detection / match) suffixes,
  # matching the build_sequence_matrix() convention for train_likelihood_model().
  merged <- merge(gt_lookup, image_df, by = "img_stem", all = FALSE)
  row.names(merged) <- NULL

  n_unjoined <- nrow(image_df) -
    sum(image_df$img_stem %in% gt_lookup$img_stem)
  if (n_unjoined > 0L)
    warning(sprintf(
      "build_image_reference: %d image_df row(s) had no matching image in images_meta and were dropped.",
      n_unjoined
    ), call. = FALSE)

  if (nrow(merged) == 0L)
    stop("build_image_reference: no rows remain after joining image_df to images_meta.")

  # ---- rank columns: resolve .x/.y naming ------------------------------------
  # After merge(gt_lookup, image_df):
  #   rank.x = ground truth (from gt_lookup) <- query
  #   rank.y = classifier detected (from image_df) <- match
  # Any rank in only one side comes through without a suffix.
  # Ensure both .x and .y columns exist for every rank in rank_system.
  for (rk in rank_system) {
    x_col <- paste0(rk, ".x")
    y_col <- paste0(rk, ".y")
    if (!x_col %in% names(merged) && rk %in% names(merged)) {
      names(merged)[names(merged) == rk] <- x_col
    }
    if (!y_col %in% names(merged)) {
      merged[[y_col]] <- NA_character_
    }
  }

  # ---- coverage ---------------------------------------------------------------
  # Priority: (1) image_df$coverage (bounding box area, per-detection),
  #           (2) images_meta$quality (recording-level quality, per image),
  #           (3) NA
  has_img_coverage <- "coverage" %in% names(image_df)

  if (has_img_coverage && "coverage" %in% names(merged)) {
    # coverage.x = images_meta quality (if present), coverage.y = image_df coverage
    # We want image_df's per-detection coverage
    if ("coverage.y" %in% names(merged)) {
      merged$coverage <- merged[["coverage.y"]]
      merged[["coverage.x"]] <- NULL
      merged[["coverage.y"]] <- NULL
    }
    # else coverage column came through unsuffixed (only in image_df side)
  } else if (!has_img_coverage && has_quality && "quality" %in% names(merged)) {
    # Use recording-level quality from images_meta
    merged$coverage <- suppressWarnings(as.numeric(merged$quality))
  } else if (!has_img_coverage) {
    merged$coverage <- NA_real_
  }

  # ---- sort detections within each image by confidence (desc) ----------------
  merged <- merged[order(merged$observation_id, -merged$score), , drop = FALSE]
  row.names(merged) <- NULL

  # Detection rank within each image (1 = best)
  merged$det_rank <- sequence(rle(merged$observation_id)$lengths)

  # ---- assemble output -------------------------------------------------------
  merged$id_x    <- merged$observation_id
  merged$id_y    <- paste0(merged$observation_id, "_det", merged$det_rank)
  merged$p_match <- merged$score
  merged$testid  <- if (has_testid) merged$testid else NA_character_

  rank_x_cols <- paste0(
    intersect(rank_system,
              gsub("\\.x$", "", grep("\\.x$", names(merged), value = TRUE))),
    ".x"
  )
  rank_y_cols <- paste0(
    intersect(rank_system,
              gsub("\\.y$", "", grep("\\.y$", names(merged), value = TRUE))),
    ".y"
  )

  keep_cols <- c("id_x", "id_y", "p_match", "coverage",
                 rank_x_cols, rank_y_cols,
                 "testid", "source_file")
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

  n_images  <- length(unique(images_meta$img_stem))
  n_queries <- length(unique(out$id_x))

  if (!is.na(n_h1)) {
    message(sprintf(
      "build_image_reference: %d reference image(s), %d matched image(s), %d pairs (%d H1, %d H2/H3).",
      n_images, n_queries, nrow(out), n_h1, nrow(out) - n_h1
    ))
  } else {
    message(sprintf(
      "build_image_reference: %d reference image(s), %d matched image(s), %d pairs.",
      n_images, n_queries, nrow(out)
    ))
  }

  out
}
