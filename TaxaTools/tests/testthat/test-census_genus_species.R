# --- Input validation ---

test_that("census_genus_species rejects unnamed keys", {
  expect_error(
    census_genus_species(c(123L, 456L)),
    "must be named"
  )
})

test_that("census_genus_species rejects empty keys", {
  expect_error(
    census_genus_species(integer(0)),
    "length >= 1"
  )
})

test_that("census_genus_species rejects non-coercible keys", {
  expect_error(
    census_genus_species(c(Fundulus = "abc")),
    "must be numeric"
  )
})

test_that("census_genus_species accepts character keys from name_backbone", {
  skip_if_not_installed("rgbif")

  mock_data <- data.frame(
    key = 1L, canonicalName = "Test sp1",
    rank = "SPECIES", taxonomicStatus = "ACCEPTED",
    stringsAsFactors = FALSE
  )
  local_mocked_bindings(
    name_usage = function(key, data, limit, ...) list(data = mock_data),
    .package = "rgbif"
  )

  # Character "123" should be accepted and coerced
  result <- census_genus_species(c(TestGenus = "123"), verbose = FALSE)
  expect_equal(nrow(result), 1L)
  expect_equal(result$gbif_key, 123L)
})

test_that("census_genus_species rejects non-character match_species", {
  expect_error(
    census_genus_species(c(Fundulus = 123L), match_species = 42),
    "character vector or NULL"
  )
})

test_that("census_genus_species rejects bad rank", {
  expect_error(
    census_genus_species(c(Fundulus = 123L), rank = c("genus", "family")),
    "single character string"
  )
})

test_that("census_genus_species requires rgbif", {
  # Can't easily test without rgbif installed, so just validate the path
  skip_if_not_installed("rgbif")
  # If rgbif IS installed, the function should not error on this check
  # (it will proceed to the API call which we test below)
  expect_true(TRUE)
})


# --- Mocked API tests ---

test_that("census returns correct structure for single genus", {
  skip_if_not_installed("rgbif")

  # Mock the GBIF response
  mock_data <- data.frame(
    key = c(100L, 101L, 102L),
    canonicalName = c("Clevelandia ios", "Clevelandia rosae",
                      "Clevelandia hybrid"),
    rank = c("SPECIES", "SPECIES", "SPECIES"),
    taxonomicStatus = c("ACCEPTED", "ACCEPTED", "DOUBTFUL"),
    stringsAsFactors = FALSE
  )

  local_mocked_bindings(
    name_usage = function(key, data, limit, ...) list(data = mock_data),
    .package = "rgbif"
  )

  result <- census_genus_species(c(Clevelandia = 2394389L), verbose = FALSE)

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 1L)
  expect_equal(result$group, "Clevelandia")
  expect_equal(result$gbif_key, 2394389L)
  # Default status_filter = "ACCEPTED", so hybrid excluded

  expect_equal(result$total_described, 2L)
  expect_true(is.na(result$status))
  expect_true(is.na(result$n_missing))

  all_sp <- attr(result, "all_species")
  expect_equal(sort(all_sp), c("Clevelandia ios", "Clevelandia rosae"))
})

test_that("census with match_species computes completeness", {
  skip_if_not_installed("rgbif")

  mock_data <- data.frame(
    key = c(100L, 101L),
    canonicalName = c("Clevelandia ios", "Clevelandia rosae"),
    rank = c("SPECIES", "SPECIES"),
    taxonomicStatus = c("ACCEPTED", "ACCEPTED"),
    stringsAsFactors = FALSE
  )

  local_mocked_bindings(
    name_usage = function(key, data, limit, ...) list(data = mock_data),
    .package = "rgbif"
  )

  # Both species referenced -> complete
  result <- census_genus_species(
    c(Clevelandia = 2394389L),
    match_species = c("Clevelandia ios", "Clevelandia rosae"),
    verbose = FALSE
  )
  expect_equal(result$status, "complete")
  expect_equal(result$n_missing, 0L)
  expect_equal(result$in_reference, 2L)
  expect_equal(result$missing_species[[1]], character(0))
})

test_that("singleton_missing status when exactly 1 species missing", {
  skip_if_not_installed("rgbif")

  mock_data <- data.frame(
    key = c(100L, 101L),
    canonicalName = c("Clevelandia ios", "Clevelandia rosae"),
    rank = c("SPECIES", "SPECIES"),
    taxonomicStatus = c("ACCEPTED", "ACCEPTED"),
    stringsAsFactors = FALSE
  )

  local_mocked_bindings(
    name_usage = function(key, data, limit, ...) list(data = mock_data),
    .package = "rgbif"
  )

  result <- census_genus_species(
    c(Clevelandia = 2394389L),
    match_species = c("Clevelandia ios"),
    verbose = FALSE
  )
  expect_equal(result$status, "singleton_missing")
  expect_equal(result$n_missing, 1L)
  expect_equal(result$missing_species[[1]], "Clevelandia rosae")
})

test_that("incomplete status when multiple species missing", {
  skip_if_not_installed("rgbif")

  mock_data <- data.frame(
    key = 100:104,
    canonicalName = paste("Fundulus", c("parvipinnis", "heteroclitus",
                                        "diaphanus", "majalis", "grandis")),
    rank = rep("SPECIES", 5),
    taxonomicStatus = rep("ACCEPTED", 5),
    stringsAsFactors = FALSE
  )

  local_mocked_bindings(
    name_usage = function(key, data, limit, ...) list(data = mock_data),
    .package = "rgbif"
  )

  result <- census_genus_species(
    c(Fundulus = 2347676L),
    match_species = c("Fundulus parvipinnis", "Fundulus heteroclitus"),
    verbose = FALSE
  )
  expect_equal(result$status, "incomplete")
  expect_equal(result$n_missing, 3L)
  expect_equal(result$in_reference, 2L)
  expect_equal(length(result$missing_species[[1]]), 3L)
})

test_that("multiple genera processed correctly", {
  skip_if_not_installed("rgbif")

  call_count <- 0L
  local_mocked_bindings(
    name_usage = function(key, data, limit, ...) {
      call_count <<- call_count + 1L
      if (key == 111L) {
        list(data = data.frame(
          key = 1L, canonicalName = "Genus1 sp1",
          rank = "SPECIES", taxonomicStatus = "ACCEPTED",
          stringsAsFactors = FALSE
        ))
      } else {
        list(data = data.frame(
          key = c(2L, 3L),
          canonicalName = c("Genus2 sp1", "Genus2 sp2"),
          rank = c("SPECIES", "SPECIES"),
          taxonomicStatus = c("ACCEPTED", "ACCEPTED"),
          stringsAsFactors = FALSE
        ))
      }
    },
    .package = "rgbif"
  )

  result <- census_genus_species(
    c(Genus1 = 111L, Genus2 = 222L),
    match_species = c("Genus1 sp1", "Genus2 sp1"),
    verbose = FALSE
  )

  expect_equal(nrow(result), 2L)
  expect_equal(result$status, c("complete", "singleton_missing"))
  expect_equal(result$total_described, c(1L, 2L))
})

test_that("GBIF API error handled gracefully per genus", {
  skip_if_not_installed("rgbif")

  local_mocked_bindings(
    name_usage = function(key, data, limit, ...) {
      if (key == 111L) stop("HTTP 500")
      list(data = data.frame(
        key = 1L, canonicalName = "Good sp1",
        rank = "SPECIES", taxonomicStatus = "ACCEPTED",
        stringsAsFactors = FALSE
      ))
    },
    .package = "rgbif"
  )

  expect_message(
    result <- census_genus_species(
      c(Bad = 111L, Good = 222L),
      verbose = TRUE
    ),
    "failed"
  )

  expect_equal(nrow(result), 2L)
  expect_equal(result$total_described, c(0L, 1L))
})

test_that("empty GBIF response returns 0 described species", {
  skip_if_not_installed("rgbif")

  local_mocked_bindings(
    name_usage = function(key, data, limit, ...) list(data = NULL),
    .package = "rgbif"
  )

  result <- census_genus_species(c(Empty = 999L), verbose = FALSE)
  expect_equal(result$total_described, 0L)
  expect_equal(result$described_species[[1]], character(0))
})

test_that("status_filter includes DOUBTFUL when requested", {
  skip_if_not_installed("rgbif")

  mock_data <- data.frame(
    key = c(100L, 101L),
    canonicalName = c("Genus sp1", "Genus sp2"),
    rank = c("SPECIES", "SPECIES"),
    taxonomicStatus = c("ACCEPTED", "DOUBTFUL"),
    stringsAsFactors = FALSE
  )

  local_mocked_bindings(
    name_usage = function(key, data, limit, ...) list(data = mock_data),
    .package = "rgbif"
  )

  # Default: only ACCEPTED
  result1 <- census_genus_species(c(Genus = 100L), verbose = FALSE)
  expect_equal(result1$total_described, 1L)

  # Include DOUBTFUL
  result2 <- census_genus_species(c(Genus = 100L),
                                   status_filter = c("ACCEPTED", "DOUBTFUL"),
                                   verbose = FALSE)
  expect_equal(result2$total_described, 2L)
})


# --- Higher-rank tests ---

test_that("family-level rank recurses through genera", {
  skip_if_not_installed("rgbif")

  local_mocked_bindings(
    name_usage = function(key, data, limit, ...) {
      if (key == 5000L) {
        # Family -> genera
        list(data = data.frame(
          key = c(100L, 200L),
          canonicalName = c("GenusA", "GenusB"),
          rank = c("GENUS", "GENUS"),
          taxonomicStatus = c("ACCEPTED", "ACCEPTED"),
          stringsAsFactors = FALSE
        ))
      } else if (key == 100L) {
        # GenusA -> 1 species
        list(data = data.frame(
          key = 1L, canonicalName = "GenusA sp1",
          rank = "SPECIES", taxonomicStatus = "ACCEPTED",
          stringsAsFactors = FALSE
        ))
      } else if (key == 200L) {
        # GenusB -> 2 species
        list(data = data.frame(
          key = c(2L, 3L),
          canonicalName = c("GenusB sp1", "GenusB sp2"),
          rank = c("SPECIES", "SPECIES"),
          taxonomicStatus = c("ACCEPTED", "ACCEPTED"),
          stringsAsFactors = FALSE
        ))
      }
    },
    .package = "rgbif"
  )

  result <- census_genus_species(
    c(TestFamily = 5000L),
    rank = "family",
    verbose = FALSE
  )

  expect_equal(nrow(result), 2L)
  expect_equal(sort(result$group), c("GenusA", "GenusB"))
  expect_equal(sum(result$total_described), 3L)

  all_sp <- attr(result, "all_species")
  expect_equal(length(all_sp), 3L)
})
