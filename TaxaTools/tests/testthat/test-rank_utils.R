# ---- standard_ranks and extended_ranks ----------------------------------------

test_that("standard_ranks is a length-7 character vector with expected values", {

  expect_type(standard_ranks, "character")
  expect_length(standard_ranks, 7L)
  expect_true(all(c("kingdom", "family", "genus", "species") %in% standard_ranks))
})

test_that("extended_ranks is character, contains standard_ranks as subset", {
  expect_type(extended_ranks, "character")
  expect_true(length(extended_ranks) > length(standard_ranks))
  expect_true(all(standard_ranks %in% extended_ranks))
  expect_true("subspecies" %in% extended_ranks)
})

# ---- detect_ranks ------------------------------------------------------------

test_that("detect_ranks finds standard rank columns", {
  df <- data.frame(family = "A", genus = "B", species = "C", score = 1)
  out <- detect_ranks(df)
  expect_equal(out, c("family", "genus", "species"))
})

test_that("detect_ranks returns all matching standard ranks in order", {
  df <- data.frame(kingdom = "A", phylum = "B", class = "C",
                   order = "D", family = "E", genus = "F",
                   species = "G", extra = 1)
  out <- detect_ranks(df)
  expect_equal(out, standard_ranks)
})

test_that("detect_ranks uses supplied rank_system", {
  df <- data.frame(family = "A", genus = "B", species = "C")
  out <- detect_ranks(df, rank_system = c("genus", "species"))
  expect_equal(out, c("genus", "species"))
})

test_that("detect_ranks warns when no standard ranks found", {
  df <- data.frame(x = 1, y = 2)
  expect_warning(detect_ranks(df), "no standard rank columns")
})

test_that("detect_ranks errors on non-data-frame", {
  expect_error(detect_ranks(list(a = 1)), "must be a data frame")
})

# ---- find_taxonomy_conflicts ------------------------------------------------

test_that("find_taxonomy_conflicts detects genus under two families", {
  df <- data.frame(
    family  = c("Cottidae", "Scorpaenidae", "Cottidae"),
    genus   = c("Cottus",   "Cottus",        "Enophrys"),
    species = c("Cottus asper", "Cottus rhotheus", "Enophrys bison"),
    stringsAsFactors = FALSE
  )
  out <- find_taxonomy_conflicts(df)
  expect_true(nrow(out) >= 1L)
  expect_true("Cottus" %in% out$taxon_name)
  expect_equal(out$n_values[out$taxon_name == "Cottus" & out$parent_rank == "family"], 2L)
})

test_that("find_taxonomy_conflicts returns empty df when no conflicts", {
  df <- data.frame(
    family  = c("Cottidae", "Cottidae"),
    genus   = c("Cottus",   "Cottus"),
    species = c("Cottus asper", "Cottus rhotheus"),
    stringsAsFactors = FALSE
  )
  out <- find_taxonomy_conflicts(df)
  expect_equal(nrow(out), 0L)
  expect_true(all(c("taxon_name", "taxon_rank", "parent_rank") %in% names(out)))
})

test_that("find_taxonomy_conflicts errors on non-data-frame", {
  expect_error(find_taxonomy_conflicts(list()), "must be a data frame")
})

test_that("find_taxonomy_conflicts handles fewer than 2 rank columns", {
  df <- data.frame(species = c("A", "B"))
  expect_message(find_taxonomy_conflicts(df), "fewer than 2")
})
