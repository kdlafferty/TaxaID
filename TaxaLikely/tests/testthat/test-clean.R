test_that("remove_flagged_references removes likely_mislabeled rows", {
  match_df <- data.frame(
    observation_id = c("S1", "S1", "S2", "S2"),
    accession = c("AB123.1", "CD456.2", "AB123.1", "EF789"),
    score     = c(99, 95, 98, 97),
    taxon_name = c("Sp A", "Sp B", "Sp A", "Sp C"),
    stringsAsFactors = FALSE
  )
  errors <- data.frame(
    id_x       = c("AB123", "GH999"),
    error_type = c("likely_mislabeled", "likely_mislabeled"),
    stringsAsFactors = FALSE
  )

  out <- suppressMessages(remove_flagged_references(match_df, errors))
  expect_equal(nrow(out), 2L)
  expect_false("AB123.1" %in% out$accession)
  expect_true(all(c("CD456.2", "EF789") %in% out$accession))
})

test_that("remove_flagged_references retains unverified singletons by default", {
  match_df <- data.frame(
    observation_id = c("S1", "S1"),
    accession = c("AB123.1", "CD456"),
    score     = c(99, 95),
    stringsAsFactors = FALSE
  )
  errors <- data.frame(
    id_x       = c("AB123", "CD456"),
    error_type = c("likely_mislabeled", "unverified_singleton_high_match"),
    stringsAsFactors = FALSE
  )

  out <- suppressMessages(remove_flagged_references(match_df, errors))
  # Only mislabeled removed, singleton retained

  expect_equal(nrow(out), 1L)
  expect_equal(out$accession, "CD456")
})

test_that("remove_flagged_references removes singletons when requested", {
  match_df <- data.frame(
    observation_id = c("S1", "S1"),
    accession = c("AB123.1", "CD456"),
    score     = c(99, 95),
    stringsAsFactors = FALSE
  )
  errors <- data.frame(
    id_x       = c("AB123", "CD456"),
    error_type = c("likely_mislabeled", "unverified_singleton_high_match"),
    stringsAsFactors = FALSE
  )

  out <- suppressMessages(remove_flagged_references(
    match_df, errors, remove_unverified_singletons = TRUE
  ))
  expect_equal(nrow(out), 0L)
})

test_that("remove_flagged_references warns when no accession column", {
  match_df <- data.frame(
    observation_id = "S1", score = 99, stringsAsFactors = FALSE
  )
  errors <- data.frame(
    id_x = "AB123", error_type = "likely_mislabeled",
    stringsAsFactors = FALSE
  )

  expect_warning(
    out <- remove_flagged_references(match_df, errors),
    "no 'accession' column"
  )
  expect_equal(nrow(out), 1L)
})

test_that("remove_flagged_references returns unchanged when no matches", {
  match_df <- data.frame(
    observation_id = "S1", accession = "ZZ999", score = 99,
    stringsAsFactors = FALSE
  )
  errors <- data.frame(
    id_x = "AB123", error_type = "likely_mislabeled",
    stringsAsFactors = FALSE
  )

  out <- suppressMessages(remove_flagged_references(match_df, errors))
  expect_equal(nrow(out), 1L)
})

test_that("remove_flagged_references returns unchanged when no errors to remove", {
  match_df <- data.frame(
    observation_id = "S1", accession = "AB123", score = 99,
    stringsAsFactors = FALSE
  )
  errors <- data.frame(
    id_x = character(0), error_type = character(0),
    stringsAsFactors = FALSE
  )

  out <- suppressMessages(remove_flagged_references(match_df, errors))
  expect_equal(nrow(out), 1L)
})

test_that("remove_flagged_references validates inputs", {
  expect_error(remove_flagged_references("not_a_df", data.frame(id_x = "a", error_type = "b")),
               "match_df must be a data frame")
  expect_error(remove_flagged_references(data.frame(x = 1), "not_a_df"),
               "reference_errors must be a data frame")
  expect_error(remove_flagged_references(data.frame(x = 1), data.frame(x = 1)),
               "missing required columns")
})
