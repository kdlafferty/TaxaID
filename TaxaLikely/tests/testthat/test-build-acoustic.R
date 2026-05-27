# Tests for build_acoustic_reference()
# All tests are offline (no BirdNET or Xeno-canto calls).

# ---- helpers ----------------------------------------------------------------
make_birdnet <- function() {
  data.frame(
    observation_id = c("XC123_0-3", "XC123_0-3", "XC123_0-3",
                       "XC456_0-3", "XC456_0-3"),
    source_file    = c(rep("XC123_Turdus_migratorius.BirdNET.results.csv", 3),
                       rep("XC456_Setophaga_petechia.BirdNET.results.csv",  2)),
    score          = c(0.9, 0.4, 0.2, 0.8, 0.3),
    species        = c("Turdus migratorius", "Catharus fuscescens",
                       "Hylocichla mustelina",
                       "Setophaga petechia", "Dendroica coronata"),
    genus          = c("Turdus", "Catharus", "Hylocichla",
                       "Setophaga", "Dendroica"),
    start_s        = c(0, 0, 0, 0, 0),
    end_s          = c(3, 3, 3, 3, 3),
    stringsAsFactors = FALSE
  )
}

make_meta <- function() {
  data.frame(
    recording_id = c("XC123", "XC456"),
    species      = c("Turdus migratorius", "Setophaga petechia"),
    genus        = c("Turdus", "Setophaga"),
    type         = c("song", "song"),
    local_path   = c("reference_audio/XC123_Turdus_migratorius.mp3",
                     "reference_audio/XC456_Setophaga_petechia.mp3"),
    stringsAsFactors = FALSE
  )
}

# ---- input validation -------------------------------------------------------

test_that("build_acoustic_reference: non-data-frame birdnet_df errors", {
  expect_error(
    build_acoustic_reference(list(), make_meta()),
    "must be a data frame"
  )
})

test_that("build_acoustic_reference: non-data-frame recordings_meta errors", {
  expect_error(
    build_acoustic_reference(make_birdnet(), list()),
    "must be a data frame"
  )
})

test_that("build_acoustic_reference: missing birdnet_df columns errors", {
  bn <- make_birdnet()
  bn$score <- NULL
  expect_error(
    build_acoustic_reference(bn, make_meta()),
    "missing columns.*score"
  )
})

test_that("build_acoustic_reference: missing recordings_meta columns errors", {
  meta <- make_meta()
  meta$local_path <- NULL
  expect_error(
    build_acoustic_reference(make_birdnet(), meta),
    "missing columns.*local_path"
  )
})

test_that("build_acoustic_reference: NA local_path errors", {
  meta <- make_meta()
  meta$local_path[1] <- NA
  expect_error(
    build_acoustic_reference(make_birdnet(), meta),
    "NA local_path"
  )
})

test_that("build_acoustic_reference: invalid min_confidence errors", {
  expect_error(
    build_acoustic_reference(make_birdnet(), make_meta(), min_confidence = "high"),
    "single numeric"
  )
})

test_that("build_acoustic_reference: invalid exclude_background errors", {
  expect_error(
    build_acoustic_reference(make_birdnet(), make_meta(), exclude_background = NA),
    "TRUE or FALSE"
  )
})

# ---- basic output structure -------------------------------------------------

test_that("build_acoustic_reference: returns a data frame with required columns", {
  out <- build_acoustic_reference(make_birdnet(), make_meta())
  expect_true(is.data.frame(out))
  expect_true(all(c("id_x", "id_y", "p_match",
                    "genus.x", "genus.y",
                    "species.x", "species.y",
                    "testid", "recording_id") %in% names(out)))
})

test_that("build_acoustic_reference: id_y is unique per row", {
  out <- build_acoustic_reference(make_birdnet(), make_meta())
  expect_equal(length(unique(out$id_y)), nrow(out))
})

test_that("build_acoustic_reference: p_match equals BirdNET score", {
  bn   <- make_birdnet()
  out  <- build_acoustic_reference(bn, make_meta())
  # p_match values should be a subset of input scores
  expect_true(all(out$p_match %in% bn$score))
})

test_that("build_acoustic_reference: testid populated from type column", {
  out <- build_acoustic_reference(make_birdnet(), make_meta())
  expect_true(all(out$testid == "song"))
})

test_that("build_acoustic_reference: testid is NA when type absent", {
  meta <- make_meta()
  meta$type <- NULL
  out <- build_acoustic_reference(make_birdnet(), meta)
  expect_true(all(is.na(out$testid)))
})

# ---- H1 / H2-H3 labeling (implied by .x / .y columns) ---------------------

test_that("build_acoustic_reference: H1 rows have matching species.x and species.y", {
  out  <- build_acoustic_reference(make_birdnet(), make_meta())
  h1   <- out[!is.na(out$species.x) & !is.na(out$species.y) &
                out$species.x == out$species.y, ]
  expect_true(nrow(h1) >= 1L)
  # Both rows where BirdNET detected the correct species
  expect_true(all(h1$species.x == h1$species.y))
})

test_that("build_acoustic_reference: H2/H3 rows have mismatched species", {
  out    <- build_acoustic_reference(make_birdnet(), make_meta())
  non_h1 <- out[!is.na(out$species.x) & !is.na(out$species.y) &
                  out$species.x != out$species.y, ]
  expect_true(nrow(non_h1) >= 1L)
})

# ---- min_confidence filter --------------------------------------------------

test_that("build_acoustic_reference: min_confidence drops low-score detections", {
  out_all <- build_acoustic_reference(make_birdnet(), make_meta(),
                                      min_confidence = 0)
  out_hi  <- build_acoustic_reference(make_birdnet(), make_meta(),
                                      min_confidence = 0.5)
  expect_true(nrow(out_hi) < nrow(out_all))
  expect_true(all(out_hi$p_match >= 0.5))
})

test_that("build_acoustic_reference: min_confidence above all scores errors", {
  expect_error(
    build_acoustic_reference(make_birdnet(), make_meta(), min_confidence = 1.1),
    "no detections remain"
  )
})

# ---- background exclusion ---------------------------------------------------

test_that("build_acoustic_reference: exclude_background drops also_species detections", {
  meta <- make_meta()
  meta$also_species <- c("Catharus fuscescens", NA)   # background in XC123
  out_with    <- build_acoustic_reference(make_birdnet(), meta,
                                          exclude_background = TRUE)
  out_without <- build_acoustic_reference(make_birdnet(), meta,
                                          exclude_background = FALSE)
  # Catharus fuscescens detection should be absent when exclusion is on
  expect_false("Catharus fuscescens" %in% out_with$species.y)
  expect_true("Catharus fuscescens"  %in% out_without$species.y)
})

# ---- detection rank / id_y encoding ----------------------------------------

test_that("build_acoustic_reference: highest-score detection per window is det1", {
  out <- build_acoustic_reference(make_birdnet(), make_meta())
  # det1 within "XC123_0-3" should be the 0.9-score row
  det1 <- out[grepl("_det1$", out$id_y) & out$id_x == "XC123_0-3", ]
  expect_equal(det1$p_match, 0.9)
})

# ---- join coverage warning --------------------------------------------------

test_that("build_acoustic_reference: unmatched file stems produce a warning", {
  bn <- make_birdnet()
  bn$source_file    <- sub("XC123", "XC999", bn$source_file)
  bn$observation_id <- sub("XC123", "XC999", bn$observation_id)
  # XC999 has no match in recordings_meta — expect at least one warning
  warns <- character(0)
  withCallingHandlers(
    build_acoustic_reference(bn, make_meta()),
    warning = function(w) {
      warns <<- c(warns, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  expect_true(any(grepl("file stem|no matching recording", warns)))
})

# ---- start_s / end_s passthrough -------------------------------------------

test_that("build_acoustic_reference: start_s and end_s in output when present", {
  out <- build_acoustic_reference(make_birdnet(), make_meta())
  expect_true("start_s" %in% names(out))
  expect_true("end_s"   %in% names(out))
})
