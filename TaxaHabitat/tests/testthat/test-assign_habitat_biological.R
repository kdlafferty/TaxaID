# ---- assign_habitat_biological ------------------------------------------------

test_that("assign_habitat_biological assigns habitat from species weights", {
  data <- data.frame(
    point_id   = c("P1", "P1", "P2", "P2"),
    taxon_name = c("Sp_A", "Sp_B", "Sp_A", "Sp_C"),
    stringsAsFactors = FALSE
  )
  habitats_df <- data.frame(
    taxon_name = c("Sp_A", "Sp_B", "Sp_C"),
    Marine     = c(0.9, 0.8, 0.1),
    Freshwater = c(0.1, 0.2, 0.9),
    stringsAsFactors = FALSE
  )
  out <- assign_habitat_biological(data, habitats_df, threshold = 0.3)
  expect_true("main_habitat" %in% names(out))
  expect_equal(nrow(out), nrow(data))

  # P1 has 2 marine species -> Marine
  p1 <- out$main_habitat[out$point_id == "P1"]
  expect_true(all(p1 == "Marine"))

  # P2 has one marine + one freshwater -> depends on weights
  p2 <- out$main_habitat[out$point_id == "P2"]
  expect_true(all(!is.na(p2)))
})

test_that("assign_habitat_biological returns NA when threshold not met", {
  data <- data.frame(
    point_id   = "P1",
    taxon_name = "Sp_A",
    stringsAsFactors = FALSE
  )
  habitats_df <- data.frame(
    taxon_name = "Sp_A",
    Marine     = 0.4,
    Freshwater = 0.4,
    Terrestrial = 0.2,
    stringsAsFactors = FALSE
  )
  # With threshold = 0.5, no single habitat reaches it for a generalist species
  out <- assign_habitat_biological(data, habitats_df, threshold = 0.5)
  expect_true(is.na(out$main_habitat[1]))
})

test_that("assign_habitat_biological validates input types", {
  expect_error(
    assign_habitat_biological(list(), data.frame()),
    "must be a dataframe"
  )
  expect_error(
    assign_habitat_biological(data.frame(), list()),
    "must be a dataframe"
  )
})

test_that("assign_habitat_biological errors on missing columns", {
  df <- data.frame(x = 1)
  hab <- data.frame(taxon_name = "A", Marine = 1)
  expect_error(assign_habitat_biological(df, hab), "not found")
})

# ---- build_iucn_scheme -------------------------------------------------------

test_that("build_iucn_scheme returns a data frame with expected columns", {
  out <- build_iucn_scheme()
  expect_s3_class(out, "data.frame")
  expect_true("l1_name" %in% names(out))
  expect_true(nrow(out) > 0L)
})

test_that("build_iucn_scheme filters by realm", {
  marine <- build_iucn_scheme(realm = "marine")
  full   <- build_iucn_scheme()
  expect_true(nrow(marine) < nrow(full))
})

# ---- example_habitat_scheme ---------------------------------------------------

test_that("example_habitat_scheme is a data frame with habitat_name column", {
  expect_s3_class(example_habitat_scheme, "data.frame")
  expect_true("l1_name" %in% names(example_habitat_scheme))
  expect_true(nrow(example_habitat_scheme) > 0L)
})
