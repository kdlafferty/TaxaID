test_that("read_birdnet_output() parses a single BirdNET CSV correctly", {
  tmp <- tempfile(fileext = ".BirdNET.results.csv")
  write.csv(data.frame(
    "Start (s)"       = c(0.0, 0.0, 3.0),
    "End (s)"         = c(3.0, 3.0, 6.0),
    "Scientific name" = c("Turdus migratorius", "Setophaga petechia",
                          "Turdus migratorius"),
    "Common name"     = c("American Robin", "Yellow Warbler", "American Robin"),
    "Confidence"      = c(0.92, 0.45, 0.87),
    check.names = FALSE, stringsAsFactors = FALSE
  ), tmp, row.names = FALSE)
  on.exit(unlink(tmp))

  out <- read_birdnet_output(tmp)

  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 3L)
  expect_true(all(c("observation_id", "score", "species", "genus",
                    "common_name", "start_s", "end_s", "source_file") %in%
                    names(out)))
  expect_equal(out$score, c(0.92, 0.45, 0.87))
  expect_equal(out$genus, c("Turdus", "Setophaga", "Turdus"))
  expect_equal(out$species[1], "Turdus migratorius")
})

test_that("read_birdnet_output() builds observation_id from file stem + window", {
  tmp <- tempfile(fileext = ".BirdNET.results.csv")
  write.csv(data.frame(
    "Start (s)"       = 0.0,
    "End (s)"         = 3.0,
    "Scientific name" = "Corvus brachyrhynchos",
    "Common name"     = "American Crow",
    "Confidence"      = 0.78,
    check.names = FALSE, stringsAsFactors = FALSE
  ), tmp, row.names = FALSE)
  on.exit(unlink(tmp))

  out <- read_birdnet_output(tmp)
  stem <- sub("\\.BirdNET$", "",
              tools::file_path_sans_ext(tools::file_path_sans_ext(basename(tmp))))
  expect_equal(out$observation_id, paste0(stem, "_0-3"))
})

test_that("read_birdnet_output() min_confidence filters correctly", {
  tmp <- tempfile(fileext = ".BirdNET.results.csv")
  write.csv(data.frame(
    "Start (s)"       = c(0.0, 0.0),
    "End (s)"         = c(3.0, 3.0),
    "Scientific name" = c("Turdus migratorius", "Setophaga petechia"),
    "Common name"     = c("American Robin", "Yellow Warbler"),
    "Confidence"      = c(0.92, 0.08),
    check.names = FALSE, stringsAsFactors = FALSE
  ), tmp, row.names = FALSE)
  on.exit(unlink(tmp))

  out <- read_birdnet_output(tmp, min_confidence = 0.10)
  expect_equal(nrow(out), 1L)
  expect_equal(out$species, "Turdus migratorius")
})

test_that("read_birdnet_output() top_n keeps only top detections per window", {
  tmp <- tempfile(fileext = ".BirdNET.results.csv")
  write.csv(data.frame(
    "Start (s)"       = c(0.0, 0.0, 0.0),
    "End (s)"         = c(3.0, 3.0, 3.0),
    "Scientific name" = c("Turdus migratorius", "Setophaga petechia",
                          "Corvus brachyrhynchos"),
    "Common name"     = c("American Robin", "Yellow Warbler", "American Crow"),
    "Confidence"      = c(0.92, 0.55, 0.30),
    check.names = FALSE, stringsAsFactors = FALSE
  ), tmp, row.names = FALSE)
  on.exit(unlink(tmp))

  out <- read_birdnet_output(tmp, top_n = 2L)
  expect_equal(nrow(out), 2L)
  expect_true(all(out$score >= 0.55))
})

test_that("read_birdnet_output() reads multiple files", {
  tmp1 <- tempfile(fileext = ".BirdNET.results.csv")
  tmp2 <- tempfile(fileext = ".BirdNET.results.csv")
  for (f in c(tmp1, tmp2)) {
    write.csv(data.frame(
      "Start (s)"       = 0.0,
      "End (s)"         = 3.0,
      "Scientific name" = "Turdus migratorius",
      "Common name"     = "American Robin",
      "Confidence"      = 0.90,
      check.names = FALSE, stringsAsFactors = FALSE
    ), f, row.names = FALSE)
  }
  on.exit(unlink(c(tmp1, tmp2)))

  out <- read_birdnet_output(c(tmp1, tmp2))
  expect_equal(nrow(out), 2L)
  expect_equal(length(unique(out$source_file)), 2L)
})

test_that("read_birdnet_output() reads all CSVs from a directory", {
  dir <- tempdir()
  f1 <- file.path(dir, "rec1.BirdNET.results.csv")
  f2 <- file.path(dir, "rec2.BirdNET.results.csv")
  for (f in c(f1, f2)) {
    write.csv(data.frame(
      "Start (s)"       = 0.0,
      "End (s)"         = 3.0,
      "Scientific name" = "Turdus migratorius",
      "Common name"     = "American Robin",
      "Confidence"      = 0.85,
      check.names = FALSE, stringsAsFactors = FALSE
    ), f, row.names = FALSE)
  }
  on.exit(unlink(c(f1, f2)))

  out <- read_birdnet_output(dir)
  expect_true(nrow(out) >= 2L)
  expect_true(all(c("observation_id", "score") %in% names(out)))
})

test_that("read_birdnet_output() errors on missing required columns", {
  tmp <- tempfile(fileext = ".BirdNET.results.csv")
  write.csv(data.frame(start = 0, end = 3, species = "Turdus migratorius"),
            tmp, row.names = FALSE)
  on.exit(unlink(tmp))

  expect_error(read_birdnet_output(tmp), "missing required column")
})

test_that("read_birdnet_output() errors on non-existent file", {
  expect_error(read_birdnet_output("does_not_exist.BirdNET.results.csv"),
               "not found")
})

test_that("read_birdnet_output() errors on empty directory", {
  dir <- file.path(tempdir(), "empty_birdnet_dir")
  dir.create(dir, showWarnings = FALSE)
  on.exit(unlink(dir, recursive = TRUE))

  expect_error(read_birdnet_output(dir), "no \\*\\.BirdNET")
})

test_that("read_birdnet_output() derives genus correctly for multi-word names", {
  tmp <- tempfile(fileext = ".BirdNET.results.csv")
  write.csv(data.frame(
    "Start (s)"       = 0.0,
    "End (s)"         = 3.0,
    "Scientific name" = "Melanerpes formicivorus",
    "Common name"     = "Acorn Woodpecker",
    "Confidence"      = 0.75,
    check.names = FALSE, stringsAsFactors = FALSE
  ), tmp, row.names = FALSE)
  on.exit(unlink(tmp))

  out <- read_birdnet_output(tmp)
  expect_equal(out$genus, "Melanerpes")
})
