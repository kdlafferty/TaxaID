test_that("read_animl_output() parses long-format CSV correctly", {
  tmp <- tempfile(fileext = ".csv")
  write.csv(data.frame(
    FileName   = c("img001.jpg", "img001.jpg", "img002.jpg"),
    prediction = c("Odocoileus virginianus", "Cervus canadensis", "empty"),
    confidence = c(0.93, 0.05, 0.99),
    stringsAsFactors = FALSE
  ), tmp, row.names = FALSE)
  on.exit(unlink(tmp))

  out <- read_animl_output(tmp)

  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 3L)
  expect_true(all(c("observation_id", "score", "species", "genus",
                    "common_name", "source_file") %in% names(out)))
  expect_equal(out$score, c(0.93, 0.05, 0.99))
  expect_equal(out$species[1], "Odocoileus virginianus")
})

test_that("read_animl_output() derives observation_id from image filename stem", {
  tmp <- tempfile(fileext = ".csv")
  write.csv(data.frame(
    FileName   = "path/to/IMG_1234.JPG",
    prediction = "Odocoileus virginianus",
    confidence = 0.92,
    stringsAsFactors = FALSE
  ), tmp, row.names = FALSE)
  on.exit(unlink(tmp))

  out <- read_animl_output(tmp)
  expect_equal(out$observation_id, "IMG_1234")
})

test_that("read_animl_output() derives genus for binomial names only", {
  tmp <- tempfile(fileext = ".csv")
  write.csv(data.frame(
    FileName   = c("a.jpg", "b.jpg", "c.jpg"),
    prediction = c("Odocoileus virginianus", "empty", "Sus scrofa"),
    confidence = c(0.90, 0.99, 0.80),
    stringsAsFactors = FALSE
  ), tmp, row.names = FALSE)
  on.exit(unlink(tmp))

  out <- read_animl_output(tmp)
  expect_equal(out$genus[out$species == "Odocoileus virginianus"], "Odocoileus")
  expect_true(is.na(out$genus[out$species == "empty"]))
  expect_equal(out$genus[out$species == "Sus scrofa"], "Sus")
})

test_that("read_animl_output() min_confidence filters rows", {
  tmp <- tempfile(fileext = ".csv")
  write.csv(data.frame(
    FileName   = c("img001.jpg", "img001.jpg"),
    prediction = c("Odocoileus virginianus", "Cervus canadensis"),
    confidence = c(0.93, 0.04),
    stringsAsFactors = FALSE
  ), tmp, row.names = FALSE)
  on.exit(unlink(tmp))

  out <- read_animl_output(tmp, min_confidence = 0.10)
  expect_equal(nrow(out), 1L)
  expect_equal(out$species, "Odocoileus virginianus")
})

test_that("read_animl_output() top_n keeps only top candidates per image", {
  tmp <- tempfile(fileext = ".csv")
  write.csv(data.frame(
    FileName   = c("img001.jpg", "img001.jpg", "img001.jpg"),
    prediction = c("Odocoileus virginianus", "Cervus canadensis",
                   "Sus scrofa"),
    confidence = c(0.90, 0.07, 0.02),
    stringsAsFactors = FALSE
  ), tmp, row.names = FALSE)
  on.exit(unlink(tmp))

  out <- read_animl_output(tmp, top_n = 2L)
  expect_equal(nrow(out), 2L)
  expect_true(all(out$score >= 0.07))
})

test_that("read_animl_output() reads multiple files", {
  tmp1 <- tempfile(fileext = ".csv")
  tmp2 <- tempfile(fileext = ".csv")
  for (f in c(tmp1, tmp2)) {
    write.csv(data.frame(
      FileName   = "img001.jpg",
      prediction = "Odocoileus virginianus",
      confidence = 0.88,
      stringsAsFactors = FALSE
    ), f, row.names = FALSE)
  }
  on.exit(unlink(c(tmp1, tmp2)))

  out <- read_animl_output(c(tmp1, tmp2))
  expect_equal(nrow(out), 2L)
  expect_equal(length(unique(out$source_file)), 2L)
})

test_that("read_animl_output() reads all CSVs from a directory", {
  dir <- file.path(tempdir(), "animl_test_dir")
  dir.create(dir, showWarnings = FALSE)
  for (nm in c("batch1.csv", "batch2.csv")) {
    write.csv(data.frame(
      FileName   = "img001.jpg",
      prediction = "Odocoileus virginianus",
      confidence = 0.85,
      stringsAsFactors = FALSE
    ), file.path(dir, nm), row.names = FALSE)
  }
  on.exit(unlink(dir, recursive = TRUE))

  out <- read_animl_output(dir)
  expect_true(nrow(out) >= 2L)
  expect_true(all(c("observation_id", "score") %in% names(out)))
})

test_that("read_animl_output() errors on missing file_col", {
  tmp <- tempfile(fileext = ".csv")
  write.csv(data.frame(path = "img.jpg", pred = "Deer", conf = 0.9),
            tmp, row.names = FALSE)
  on.exit(unlink(tmp))

  expect_error(read_animl_output(tmp, file_col = "FileName"),
               "missing required column 'FileName'")
})

test_that("read_animl_output() errors on missing species_col or score_col", {
  tmp <- tempfile(fileext = ".csv")
  write.csv(data.frame(
    FileName   = "img.jpg",
    species    = "Odocoileus virginianus",
    stringsAsFactors = FALSE
  ), tmp, row.names = FALSE)
  on.exit(unlink(tmp))

  expect_error(read_animl_output(tmp), "missing column")
})

test_that("read_animl_output() errors on non-existent file", {
  expect_error(read_animl_output("does_not_exist.csv"), "not found")
})

test_that("read_animl_output() errors on empty directory", {
  dir <- file.path(tempdir(), "empty_animl_dir")
  dir.create(dir, showWarnings = FALSE)
  on.exit(unlink(dir, recursive = TRUE))

  expect_error(read_animl_output(dir), "no \\*.csv files found")
})

test_that("read_animl_output() handles empty CSV (header only)", {
  tmp <- tempfile(fileext = ".csv")
  write.csv(data.frame(
    FileName   = character(0),
    prediction = character(0),
    confidence = numeric(0),
    stringsAsFactors = FALSE
  ), tmp, row.names = FALSE)
  on.exit(unlink(tmp))

  expect_message(read_animl_output(tmp), "no detections")
  out <- suppressMessages(read_animl_output(tmp))
  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 0L)
  expect_true(all(c("observation_id", "score", "species", "genus",
                    "common_name", "source_file") %in% names(out)))
})

test_that("read_animl_output() handles custom column names", {
  tmp <- tempfile(fileext = ".csv")
  write.csv(data.frame(
    FilePath   = "img001.jpg",
    label      = "Odocoileus virginianus",
    prob       = 0.91,
    stringsAsFactors = FALSE
  ), tmp, row.names = FALSE)
  on.exit(unlink(tmp))

  out <- read_animl_output(tmp,
                            file_col    = "FilePath",
                            species_col = "label",
                            score_col   = "prob")
  expect_equal(nrow(out), 1L)
  expect_equal(out$species, "Odocoileus virginianus")
  expect_equal(out$score, 0.91)
})

test_that("read_animl_output() includes common_name when column present", {
  tmp <- tempfile(fileext = ".csv")
  write.csv(data.frame(
    FileName    = "img001.jpg",
    prediction  = "Odocoileus virginianus",
    confidence  = 0.90,
    common_name = "White-tailed Deer",
    stringsAsFactors = FALSE
  ), tmp, row.names = FALSE)
  on.exit(unlink(tmp))

  out <- read_animl_output(tmp, common_name_col = "common_name")
  expect_equal(out$common_name, "White-tailed Deer")
})

test_that("read_animl_output() handles wide-format with n_candidates", {
  tmp <- tempfile(fileext = ".csv")
  write.csv(data.frame(
    FileName = c("img001.jpg", "img002.jpg"),
    pred1    = c("Odocoileus virginianus", "Sus scrofa"),
    score1   = c(0.90, 0.80),
    pred2    = c("Cervus canadensis", "Bos taurus"),
    score2   = c(0.08, 0.15),
    pred3    = c("empty", "empty"),
    score3   = c(0.02, 0.05),
    stringsAsFactors = FALSE
  ), tmp, row.names = FALSE)
  on.exit(unlink(tmp))

  out <- read_animl_output(tmp,
                            species_col  = "pred",
                            score_col    = "score",
                            n_candidates = 3L)

  # 2 images × 3 candidates = 6, but "empty" rows have score < min_confidence
  # if not filtered — with default min_confidence = 0, all 6 kept
  expect_equal(nrow(out), 6L)
  # Check wide-to-long mapping
  img1_rows <- out[out$observation_id == "img001", ]
  expect_true("Odocoileus virginianus" %in% img1_rows$species)
  expect_true("Cervus canadensis" %in% img1_rows$species)
})

test_that("read_animl_output() wide-format errors on missing pred/score columns", {
  tmp <- tempfile(fileext = ".csv")
  write.csv(data.frame(
    FileName = "img001.jpg",
    pred1    = "Deer",
    score1   = 0.9,
    stringsAsFactors = FALSE
  ), tmp, row.names = FALSE)
  on.exit(unlink(tmp))

  expect_error(
    read_animl_output(tmp, species_col = "pred", score_col = "score",
                       n_candidates = 3L),
    "missing column"
  )
})


# ==============================================================================
# Tests: read_inaturalist_cv_output()
# ==============================================================================

# ---- helper: write a minimal iNat CV JSON file ------------------------------
write_inat_json <- function(path, obs_id = "IMG_001",
                             scores = c(0.87, 0.07),
                             species = c("Danaus plexippus", "Limenitis archippus"),
                             ranks   = c("species", "species"),
                             common  = c("Monarch", "Viceroy")) {
  results <- lapply(seq_along(scores), function(i) {
    list(
      combined_score = scores[i],
      score          = scores[i],
      taxon          = list(
        name                   = species[i],
        rank                   = ranks[i],
        preferred_common_name  = common[i]
      )
    )
  })
  writeLines(
    jsonlite::toJSON(list(results = results), auto_unbox = TRUE),
    path
  )
  invisible(path)
}

test_that("read_inaturalist_cv_output: parses single JSON file", {
  skip_if_not_installed("jsonlite")
  tmp <- tempfile(fileext = ".json")
  write_inat_json(tmp)
  on.exit(unlink(tmp))

  out <- read_inaturalist_cv_output(tmp)
  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 2L)
  expect_true(all(c("observation_id", "score", "species", "genus",
                    "common_name", "taxon_rank", "source_file") %in% names(out)))
})

test_that("read_inaturalist_cv_output: observation_id is JSON file stem", {
  skip_if_not_installed("jsonlite")
  tmp <- tempfile(fileext = ".json")
  write_inat_json(tmp)
  on.exit(unlink(tmp))

  out <- read_inaturalist_cv_output(tmp)
  expected_id <- tools::file_path_sans_ext(basename(tmp))
  expect_true(all(out$observation_id == expected_id))
})

test_that("read_inaturalist_cv_output: scores match JSON values", {
  skip_if_not_installed("jsonlite")
  tmp <- tempfile(fileext = ".json")
  write_inat_json(tmp, scores = c(0.91, 0.06))
  on.exit(unlink(tmp))

  out <- read_inaturalist_cv_output(tmp, score_type = "score")
  expect_equal(out$score, c(0.91, 0.06))
})

test_that("read_inaturalist_cv_output: combined_score is default", {
  skip_if_not_installed("jsonlite")
  tmp <- tempfile(fileext = ".json")
  write_inat_json(tmp, scores = c(0.87, 0.07))
  on.exit(unlink(tmp))

  out <- read_inaturalist_cv_output(tmp, score_type = "combined_score")
  expect_equal(out$score, c(0.87, 0.07))
})

test_that("read_inaturalist_cv_output: genus derived from binomial", {
  skip_if_not_installed("jsonlite")
  tmp <- tempfile(fileext = ".json")
  write_inat_json(tmp, species = c("Danaus plexippus", "Lepidoptera"))
  on.exit(unlink(tmp))

  out <- read_inaturalist_cv_output(tmp)
  expect_equal(out$genus[out$species == "Danaus plexippus"], "Danaus")
  expect_true(is.na(out$genus[out$species == "Lepidoptera"]))
})

test_that("read_inaturalist_cv_output: min_confidence filter works", {
  skip_if_not_installed("jsonlite")
  tmp <- tempfile(fileext = ".json")
  write_inat_json(tmp, scores = c(0.87, 0.07))
  on.exit(unlink(tmp))

  out <- read_inaturalist_cv_output(tmp, min_confidence = 0.50)
  expect_equal(nrow(out), 1L)
  expect_equal(out$score, 0.87)
})

test_that("read_inaturalist_cv_output: top_n filter works", {
  skip_if_not_installed("jsonlite")
  tmp <- tempfile(fileext = ".json")
  write_inat_json(tmp, scores = c(0.87, 0.07))
  on.exit(unlink(tmp))

  out <- read_inaturalist_cv_output(tmp, top_n = 1L)
  expect_equal(nrow(out), 1L)
  expect_equal(out$score, 0.87)
})

test_that("read_inaturalist_cv_output: reads directory of JSON files", {
  skip_if_not_installed("jsonlite")
  dir <- tempdir()
  f1 <- file.path(dir, "img_a.json")
  f2 <- file.path(dir, "img_b.json")
  write_inat_json(f1, scores = c(0.9))
  write_inat_json(f2, scores = c(0.8))
  on.exit({ unlink(f1); unlink(f2) })

  out <- read_inaturalist_cv_output(c(f1, f2))
  expect_equal(length(unique(out$observation_id)), 2L)
})

test_that("read_inaturalist_cv_output: errors on missing file", {
  skip_if_not_installed("jsonlite")
  expect_error(
    read_inaturalist_cv_output("/nonexistent/path.json"),
    "not found"
  )
})

test_that("read_inaturalist_cv_output: invalid score_type errors", {
  skip_if_not_installed("jsonlite")
  expect_error(
    read_inaturalist_cv_output(tempfile(), score_type = "bad_score"),
    "should be one of"
  )
})


# ==============================================================================
# Tests: read_wildlife_insights_output()
# ==============================================================================

# ---- helper: write a minimal SpeciesNet JSON file ---------------------------
write_speciesnet_json <- function(path,
                                  img_names = c("IMG_001.jpg", "IMG_002.jpg"),
                                  species   = c("Odocoileus virginianus", "blank"),
                                  scores    = c(0.94, 0.99),
                                  cats      = c("animal", "blank")) {
  preds <- stats::setNames(
    lapply(seq_along(img_names), function(i)
      list(list(label    = species[i],
                score    = scores[i],
                category = cats[i]))),
    img_names
  )
  writeLines(
    jsonlite::toJSON(list(predictions = preds), auto_unbox = TRUE),
    path
  )
  invisible(path)
}

test_that("read_wildlife_insights_output: parses single JSON file", {
  skip_if_not_installed("jsonlite")
  tmp <- tempfile(fileext = ".json")
  write_speciesnet_json(tmp)
  on.exit(unlink(tmp))

  out <- read_wildlife_insights_output(tmp)
  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 2L)
  expect_true(all(c("observation_id", "score", "species", "genus",
                    "category", "source_file") %in% names(out)))
})

test_that("read_wildlife_insights_output: observation_id is image file stem", {
  skip_if_not_installed("jsonlite")
  tmp <- tempfile(fileext = ".json")
  write_speciesnet_json(tmp, img_names = c("some/path/IMG_001.jpg"))
  on.exit(unlink(tmp))

  out <- read_wildlife_insights_output(tmp)
  expect_equal(out$observation_id, "IMG_001")
})

test_that("read_wildlife_insights_output: genus derived from binomial species", {
  skip_if_not_installed("jsonlite")
  tmp <- tempfile(fileext = ".json")
  write_speciesnet_json(tmp,
    img_names = "img.jpg",
    species   = "Odocoileus virginianus",
    scores    = 0.94, cats = "animal")
  on.exit(unlink(tmp))

  out <- read_wildlife_insights_output(tmp)
  expect_equal(out$genus, "Odocoileus")
})

test_that("read_wildlife_insights_output: genus is NA for non-binomial labels", {
  skip_if_not_installed("jsonlite")
  tmp <- tempfile(fileext = ".json")
  write_speciesnet_json(tmp,
    img_names = "img.jpg",
    species   = "blank", scores = 0.99, cats = "blank")
  on.exit(unlink(tmp))

  out <- read_wildlife_insights_output(tmp)
  expect_true(is.na(out$genus))
})

test_that("read_wildlife_insights_output: min_confidence filter works", {
  skip_if_not_installed("jsonlite")
  tmp <- tempfile(fileext = ".json")
  write_speciesnet_json(tmp,
    img_names = c("a.jpg", "b.jpg"),
    species   = c("Odocoileus virginianus", "blank"),
    scores    = c(0.94, 0.30),
    cats      = c("animal", "blank"))
  on.exit(unlink(tmp))

  out <- read_wildlife_insights_output(tmp, min_confidence = 0.50)
  expect_equal(nrow(out), 1L)
  expect_equal(out$score, 0.94)
})

test_that("read_wildlife_insights_output: top_n filter works", {
  skip_if_not_installed("jsonlite")
  tmp <- tempfile(fileext = ".json")
  # Two candidates for the same image
  preds <- list(
    list(list(label = "Odocoileus virginianus", score = 0.94, category = "animal"),
         list(label = "Cervus canadensis",      score = 0.04, category = "animal"))
  )
  preds <- stats::setNames(preds, "IMG_001.jpg")
  writeLines(
    jsonlite::toJSON(list(predictions = preds), auto_unbox = TRUE),
    tmp
  )
  on.exit(unlink(tmp))

  out <- read_wildlife_insights_output(tmp, top_n = 1L)
  expect_equal(nrow(out), 1L)
  expect_equal(out$score, 0.94)
})

test_that("read_wildlife_insights_output: category column present", {
  skip_if_not_installed("jsonlite")
  tmp <- tempfile(fileext = ".json")
  write_speciesnet_json(tmp)
  on.exit(unlink(tmp))

  out <- read_wildlife_insights_output(tmp)
  expect_true("category" %in% names(out))
  expect_true("animal" %in% out$category)
})

test_that("read_wildlife_insights_output: errors on missing file", {
  skip_if_not_installed("jsonlite")
  expect_error(
    read_wildlife_insights_output("/nonexistent/path.json"),
    "not found"
  )
})

test_that("read_wildlife_insights_output: custom label_col works", {
  skip_if_not_installed("jsonlite")
  tmp <- tempfile(fileext = ".json")
  # Use 'species' instead of 'label'
  preds <- list(
    list(list(species = "Odocoileus virginianus", score = 0.94, category = "animal"))
  )
  preds <- stats::setNames(preds, "IMG_001.jpg")
  writeLines(
    jsonlite::toJSON(list(predictions = preds), auto_unbox = TRUE),
    tmp
  )
  on.exit(unlink(tmp))

  out <- read_wildlife_insights_output(tmp, label_col = "species")
  expect_equal(out$species, "Odocoileus virginianus")
})
