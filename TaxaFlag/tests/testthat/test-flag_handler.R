# --- Mock data: camera trap detections at one station ---
# 10 detections over 3 hours; first and last are near edges

mock_camera <- data.frame(
  station    = "StationA",
  datetime   = as.POSIXct(c(
    "2025-06-15 08:00:00",   # setup time (min)
    "2025-06-15 08:05:00",   # 5 min from start
    "2025-06-15 08:20:00",   # 20 min from start
    "2025-06-15 08:35:00",   # 35 min — outside 30-min window
    "2025-06-15 09:00:00",   # well inside
    "2025-06-15 09:30:00",
    "2025-06-15 10:00:00",
    "2025-06-15 10:30:00",   # 30 min from end — edge
    "2025-06-15 10:55:00",   # 5 min from end
    "2025-06-15 11:00:00"    # retrieval time (max)
  )),
  taxon_name = c("Homo sapiens", "Canis lupus", "Odocoileus virginianus",
                 "Odocoileus virginianus", "Lynx rufus", "Lynx rufus",
                 "Mephitis mephitis", "Procyon lotor",
                 "Homo sapiens", "Homo sapiens"),
  stringsAsFactors = FALSE
)


# ===========================================================================
# Basic functionality
# ===========================================================================

test_that("flag_handler adds three columns", {
  result <- flag_handler(mock_camera, group_col = "station",
                         interval_minutes = 30, verbose = FALSE)

  expect_true("flag_handler" %in% names(result))
  expect_true("flag_handler_score" %in% names(result))
  expect_true("flag_handler_reason" %in% names(result))
  expect_equal(nrow(result), nrow(mock_camera))
})

test_that("detections at min/max get score 0", {
  result <- flag_handler(mock_camera, group_col = "station",
                         interval_minutes = 30, verbose = FALSE)

  # Row 1 (setup) and row 10 (retrieval) are at the edges
  expect_equal(result$flag_handler_score[1], 0.0)
  expect_equal(result$flag_handler_score[10], 0.0)
  expect_equal(result$flag_handler[1], "unlikely")
  expect_equal(result$flag_handler[10], "unlikely")
})

test_that("detections outside interval get score 1", {
  result <- flag_handler(mock_camera, group_col = "station",
                         interval_minutes = 30, verbose = FALSE)

  # Rows 5-7 are well inside (60+ min from both edges)
  expect_equal(result$flag_handler_score[5], 1.0)
  expect_equal(result$flag_handler[5], "likely")
})

test_that("scores are linear within interval", {
  result <- flag_handler(mock_camera, group_col = "station",
                         interval_minutes = 30, verbose = FALSE)

  # Row 2 is 5 min from start -> score = 5/30
  expect_equal(result$flag_handler_score[2], 5 / 30, tolerance = 0.001)
  # Row 3 is 20 min from start -> score = 20/30
  expect_equal(result$flag_handler_score[3], 20 / 30, tolerance = 0.001)
})

test_that("scores are between 0 and 1", {
  result <- flag_handler(mock_camera, group_col = "station",
                         interval_minutes = 30, verbose = FALSE)

  expect_true(all(result$flag_handler_score >= 0 &
                  result$flag_handler_score <= 1))
})


# ===========================================================================
# handler_taxa filter
# ===========================================================================

test_that("handler_taxa restricts flagging to specified taxa", {
  result <- flag_handler(mock_camera, group_col = "station",
                         interval_minutes = 30,
                         handler_taxa = "Homo sapiens",
                         verbose = FALSE)

  # Row 2 (Canis lupus, 5 min from start) — not a handler taxon
  expect_equal(result$flag_handler_score[2], 1.0)
  expect_equal(result$flag_handler[2], "likely")

  # Row 1 (Homo sapiens, at start) — handler taxon, still flagged
  expect_equal(result$flag_handler_score[1], 0.0)
  expect_equal(result$flag_handler[1], "unlikely")
})


# ===========================================================================
# group_col = NULL (single group)
# ===========================================================================

test_that("group_col = NULL treats all rows as one group", {
  result <- flag_handler(mock_camera, group_col = NULL,
                         interval_minutes = 30, verbose = FALSE)

  expect_equal(nrow(result), nrow(mock_camera))
  expect_equal(result$flag_handler_score[1], 0.0)
})


# ===========================================================================
# Multiple groups
# ===========================================================================

test_that("min/max computed per group", {
  df2 <- rbind(
    mock_camera,
    data.frame(
      station    = "StationB",
      datetime   = as.POSIXct(c("2025-06-16 12:00:00",
                                 "2025-06-16 12:10:00",
                                 "2025-06-16 13:00:00")),
      taxon_name = c("Homo sapiens", "Lynx rufus", "Lynx rufus"),
      stringsAsFactors = FALSE
    )
  )

  result <- flag_handler(df2, group_col = "station",
                         interval_minutes = 30, verbose = FALSE)

  # StationB row 1 (12:00) is the min for StationB -> score 0

  stb <- result[result$station == "StationB", ]
  expect_equal(stb$flag_handler_score[1], 0.0)
  # StationB row 2 (12:10) is 10 min from start, 50 min from end -> score 10/30
  expect_equal(stb$flag_handler_score[2], 10 / 30, tolerance = 0.001)
})


# ===========================================================================
# Datetime parsing
# ===========================================================================

test_that("character datetimes are auto-parsed", {
  df_char <- mock_camera
  df_char$datetime <- format(df_char$datetime, "%Y-%m-%d %H:%M:%S")

  result <- flag_handler(df_char, group_col = "station",
                         interval_minutes = 30, verbose = FALSE)

  expect_equal(result$flag_handler_score[1], 0.0)
  expect_equal(result$flag_handler_score[5], 1.0)
})

test_that("Date-only input works (all same day -> all near edges)", {
  df_date <- data.frame(
    datetime   = as.Date(c("2025-06-15", "2025-06-16", "2025-06-20")),
    taxon_name = c("A", "B", "C"),
    stringsAsFactors = FALSE
  )

  result <- flag_handler(df_date, interval_minutes = 60 * 24 * 2,
                         verbose = FALSE)

  # First and last rows are at the edges
  expect_equal(result$flag_handler_score[1], 0.0)
  expect_equal(result$flag_handler_score[3], 0.0)
})


# ===========================================================================
# Temporary columns cleaned up
# ===========================================================================

test_that("no temporary columns remain in output", {
  result <- flag_handler(mock_camera, group_col = "station",
                         interval_minutes = 30, verbose = FALSE)

  expect_false("datetime_parsed" %in% names(result))
  expect_false(".tmp_group" %in% names(result))
  expect_false("group_min" %in% names(result))
  expect_false("group_max" %in% names(result))
  expect_false("minutes_to_edge" %in% names(result))
  expect_false("handler_score" %in% names(result))
})


# ===========================================================================
# Input validation
# ===========================================================================

test_that("error when datetime column missing", {
  expect_error(
    flag_handler(mock_camera, datetime_col = "nonexistent", verbose = FALSE),
    "not found"
  )
})

test_that("error when group_col missing", {
  expect_error(
    flag_handler(mock_camera, group_col = "nonexistent", verbose = FALSE),
    "not found"
  )
})

test_that("error when interval_minutes invalid", {
  expect_error(
    flag_handler(mock_camera, interval_minutes = -5, verbose = FALSE),
    "positive number"
  )
  expect_error(
    flag_handler(mock_camera, interval_minutes = "thirty", verbose = FALSE),
    "positive number"
  )
})

test_that("error when all datetimes unparseable", {
  df_bad <- mock_camera
  df_bad$datetime <- "not a date"
  expect_error(
    flag_handler(df_bad, verbose = FALSE),
    "Could not parse"
  )
})
