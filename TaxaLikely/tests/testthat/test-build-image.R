# Tests for build_image_reference()
# All tests are offline (no classifier or image API calls).

# ---- helpers ----------------------------------------------------------------
make_image_df <- function() {
  data.frame(
    observation_id = c("img001", "img001", "img001",
                       "img002", "img002"),
    source_file    = c(rep("animl_results.csv", 5)),
    score          = c(0.92, 0.05, 0.02, 0.88, 0.10),
    species        = c("Odocoileus virginianus", "Cervus canadensis",
                       "Sus scrofa",
                       "Sylvilagus floridanus", "Lepus americanus"),
    genus          = c("Odocoileus", "Cervus", "Sus",
                       "Sylvilagus", "Lepus"),
    stringsAsFactors = FALSE
  )
}

make_images_meta <- function() {
  data.frame(
    image_path = c("ref_images/img001.jpg",
                   "ref_images/img002.jpg"),
    species    = c("Odocoileus virginianus", "Sylvilagus floridanus"),
    genus      = c("Odocoileus", "Sylvilagus"),
    testid     = c("camera_trap", "camera_trap"),
    stringsAsFactors = FALSE
  )
}

# ---- input validation -------------------------------------------------------

test_that("build_image_reference: non-data-frame image_df errors", {
  expect_error(
    build_image_reference(list(), make_images_meta()),
    "must be a data frame"
  )
})

test_that("build_image_reference: non-data-frame images_meta errors", {
  expect_error(
    build_image_reference(make_image_df(), list()),
    "must be a data frame"
  )
})

test_that("build_image_reference: missing image_df columns errors", {
  img <- make_image_df()
  img$score <- NULL
  expect_error(
    build_image_reference(img, make_images_meta()),
    "missing columns.*score"
  )
})

test_that("build_image_reference: missing image_path column in images_meta errors", {
  meta <- make_images_meta()
  meta$image_path <- NULL
  expect_error(
    build_image_reference(make_image_df(), meta),
    "image_path"
  )
})

test_that("build_image_reference: missing rank columns in images_meta errors", {
  meta <- make_images_meta()
  meta$species <- NULL
  expect_error(
    build_image_reference(make_image_df(), meta),
    "missing rank"
  )
})

test_that("build_image_reference: invalid min_confidence errors", {
  expect_error(
    build_image_reference(make_image_df(), make_images_meta(),
                          min_confidence = "high"),
    "min_confidence"
  )
})

test_that("build_image_reference: all filtered by min_confidence errors", {
  expect_error(
    build_image_reference(make_image_df(), make_images_meta(),
                          min_confidence = 0.99),
    "no detections remain"
  )
})

# ---- basic output -----------------------------------------------------------

test_that("build_image_reference: returns data frame with expected columns", {
  out <- suppressMessages(
    build_image_reference(make_image_df(), make_images_meta())
  )
  expect_s3_class(out, "data.frame")
  expect_true(all(c("id_x", "id_y", "p_match", "coverage",
                    "species.x", "species.y",
                    "genus.x", "genus.y",
                    "testid", "source_file") %in% names(out)))
})

test_that("build_image_reference: H1 rows have matching .x and .y species", {
  out <- suppressMessages(
    build_image_reference(make_image_df(), make_images_meta())
  )
  h1 <- out[!is.na(out$species.x) & !is.na(out$species.y) &
              out$species.x == out$species.y, ]
  expect_gt(nrow(h1), 0L)
  # img001: top detection is Odocoileus virginianus == ground truth
  expect_true(any(h1$species.x == "Odocoileus virginianus"))
})

test_that("build_image_reference: H2/H3 rows have mismatched .x and .y species", {
  out <- suppressMessages(
    build_image_reference(make_image_df(), make_images_meta())
  )
  h2h3 <- out[!is.na(out$species.x) & !is.na(out$species.y) &
                out$species.x != out$species.y, ]
  expect_gt(nrow(h2h3), 0L)
})

test_that("build_image_reference: p_match equals original score", {
  out <- suppressMessages(
    build_image_reference(make_image_df(), make_images_meta())
  )
  img_df <- make_image_df()
  # All scores in output must come from the input image_df
  expect_true(all(out$p_match %in% img_df$score))
})

test_that("build_image_reference: id_y is unique per query", {
  out <- suppressMessages(
    build_image_reference(make_image_df(), make_images_meta())
  )
  expect_equal(length(unique(out$id_y)), nrow(out))
})

test_that("build_image_reference: testid is propagated from images_meta", {
  out <- suppressMessages(
    build_image_reference(make_image_df(), make_images_meta())
  )
  expect_true(all(out$testid == "camera_trap"))
})

# ---- coverage handling ------------------------------------------------------

test_that("build_image_reference: coverage from image_df passes through", {
  img <- make_image_df()
  img$coverage <- c(0.80, 0.80, 0.80, 0.65, 0.65)
  out <- suppressMessages(
    build_image_reference(img, make_images_meta())
  )
  expect_true("coverage" %in% names(out))
  expect_true(all(out$coverage %in% c(0.80, 0.65)))
})

test_that("build_image_reference: coverage from images_meta$quality when image_df lacks it", {
  meta <- make_images_meta()
  meta$quality <- c(0.9, 0.7)
  out <- suppressMessages(
    build_image_reference(make_image_df(), meta)
  )
  expect_true("coverage" %in% names(out))
  # coverage sourced from images_meta$quality
  expect_true(all(out$coverage[out$id_x == "img001"] == 0.9))
  expect_true(all(out$coverage[out$id_x == "img002"] == 0.7))
})

test_that("build_image_reference: coverage is NA when neither source present", {
  out <- suppressMessages(
    build_image_reference(make_image_df(), make_images_meta())
  )
  expect_true(all(is.na(out$coverage)))
})

# ---- join coverage warning --------------------------------------------------

test_that("build_image_reference: warns on unmatched image stems", {
  img <- make_image_df()
  img$observation_id[1:3] <- "img_UNKNOWN"
  img$observation_id[4:5] <- "img002"
  warns <- character(0)
  withCallingHandlers(
    build_image_reference(img, make_images_meta()),
    warning = function(w) {
      warns <<- c(warns, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  expect_true(any(grepl("img_UNKNOWN", warns)))
})

# ---- min_confidence filter --------------------------------------------------

test_that("build_image_reference: min_confidence removes low-score detections", {
  out <- suppressMessages(
    build_image_reference(make_image_df(), make_images_meta(),
                          min_confidence = 0.80)
  )
  expect_true(all(out$p_match >= 0.80))
})

# ---- rank_system handling ---------------------------------------------------

test_that("build_image_reference: genus-only rank_system works", {
  meta <- make_images_meta()
  out <- suppressMessages(
    build_image_reference(make_image_df(), meta,
                          rank_system = c("genus"))
  )
  expect_true("genus.x" %in% names(out))
  expect_false("species.x" %in% names(out))
})

test_that("build_image_reference: custom rank_system errors if rank absent from images_meta", {
  expect_error(
    build_image_reference(make_image_df(), make_images_meta(),
                          rank_system = c("family", "genus", "species")),
    "missing rank.*family"
  )
})

# ---- no matches at all ------------------------------------------------------

test_that("build_image_reference: errors when no images join", {
  img <- make_image_df()
  img$observation_id <- c("NOMATCH1", "NOMATCH1", "NOMATCH1",
                          "NOMATCH2", "NOMATCH2")
  expect_error(
    suppressWarnings(build_image_reference(img, make_images_meta())),
    "no rows remain"
  )
})
