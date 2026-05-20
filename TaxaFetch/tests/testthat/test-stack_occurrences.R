# Tests for stack_occurrences() — Session 25 changes:
#   - list input pattern
#   - single-frame input (no error)
#   - NULL filtering
#   - tibble return

.make_occ <- function(n = 3L, id_prefix = "A") {
  tibble::tibble(
    occurrenceID       = paste0(id_prefix, seq_len(n)),
    scientificName     = paste0("Species ", id_prefix, seq_len(n)),
    decimalLatitude    = runif(n, 32, 35),
    decimalLongitude   = runif(n, -121, -117),
    datasetID          = "test"
  )
}

test_that("stack_occurrences: two frames via ... works as before", {
  df1 <- .make_occ(3L, "A")
  df2 <- .make_occ(2L, "B")
  result <- stack_occurrences(df1, df2)
  expect_equal(nrow(result), 5L)
  expect_true("point_id" %in% names(result))
})

test_that("stack_occurrences: list input unpacked correctly", {
  df1    <- .make_occ(3L, "A")
  df2    <- .make_occ(2L, "B")
  frames <- list(df1, df2)
  result <- stack_occurrences(frames)
  expect_equal(nrow(result), 5L)
  expect_true("point_id" %in% names(result))
})

test_that("stack_occurrences: named list input works", {
  frames <- list(source1 = .make_occ(3L, "A"),
                 source2 = .make_occ(4L, "B"))
  result <- stack_occurrences(frames)
  expect_equal(nrow(result), 7L)
})

test_that("stack_occurrences: single frame via ... returns with point_id, no error", {
  df     <- .make_occ(5L, "A")
  result <- stack_occurrences(df)
  expect_equal(nrow(result), 5L)
  expect_true("point_id" %in% names(result))
})

test_that("stack_occurrences: single-element list returns with point_id, no error", {
  frames <- list(.make_occ(5L, "A"))
  result <- stack_occurrences(frames)
  expect_equal(nrow(result), 5L)
  expect_true("point_id" %in% names(result))
})

test_that("stack_occurrences: NULL entries in list are dropped silently", {
  frames <- list(
    .make_occ(3L, "A"),
    NULL,
    .make_occ(2L, "C"),
    NULL
  )
  result <- stack_occurrences(frames)
  expect_equal(nrow(result), 5L)
})

test_that("stack_occurrences: all-NULL list produces informative error", {
  frames <- list(NULL, NULL)
  expect_error(stack_occurrences(frames), "no non-NULL data frames")
})

test_that("stack_occurrences: empty list produces informative error", {
  expect_error(stack_occurrences(list()), "no non-NULL data frames")
})

test_that("stack_occurrences: returns a tibble", {
  df     <- .make_occ(3L, "A")
  result <- stack_occurrences(df)
  expect_s3_class(result, "tbl_df")
})

test_that("stack_occurrences: point_id format is lat_lon", {
  df <- tibble::tibble(
    occurrenceID     = "X1",
    decimalLatitude  = 34.123,
    decimalLongitude = -119.456
  )
  result <- stack_occurrences(df)
  expect_equal(result$point_id[1L], "34.123_-119.456")
})

test_that("stack_occurrences: missing coordinate column produces informative error", {
  df_bad <- tibble::tibble(occurrenceID = "X1", decimalLatitude = 34.0)
  expect_error(
    stack_occurrences(df_bad),
    "missing coordinate column"
  )
})

test_that("stack_occurrences: custom lat_col / lon_col work", {
  df1 <- tibble::tibble(id = "A1", lat = 34.0, lon = -119.0)
  df2 <- tibble::tibble(id = "B1", lat = 33.5, lon = -118.5)
  result <- stack_occurrences(df1, df2, lat_col = "lat", lon_col = "lon")
  expect_equal(nrow(result), 2L)
  expect_true("point_id" %in% names(result))
})

test_that("stack_occurrences: pre-existing point_id column is overwritten", {
  df <- tibble::tibble(
    occurrenceID     = "X1",
    decimalLatitude  = 34.0,
    decimalLongitude = -119.0,
    point_id         = "old_value"
  )
  result <- stack_occurrences(df)
  expect_false(result$point_id[1L] == "old_value")
})

test_that("stack_occurrences: columns present in some frames but not others are NA-filled", {
  df1 <- tibble::tibble(
    occurrenceID     = "A1",
    decimalLatitude  = 34.0,
    decimalLongitude = -119.0,
    extra_col        = "present"
  )
  df2 <- tibble::tibble(
    occurrenceID     = "B1",
    decimalLatitude  = 33.0,
    decimalLongitude = -118.0
  )
  result <- stack_occurrences(df1, df2)
  expect_true("extra_col" %in% names(result))
  expect_true(is.na(result$extra_col[result$occurrenceID == "B1"]))
})

test_that("stack_occurrences: workflow list pattern (pdf_occ_list_clean) works end-to-end", {
  # Simulate the pattern used in pdf_workflow_test_v4.R Stage 13
  pdf_occ_list_clean <- list(
    "paper1.pdf" = .make_occ(5L, "P1"),
    "paper2.pdf" = .make_occ(3L, "P2")
  )
  all_pdf_occ <- stack_occurrences(pdf_occ_list_clean)
  expect_equal(nrow(all_pdf_occ), 8L)
  expect_s3_class(all_pdf_occ, "tbl_df")
})
