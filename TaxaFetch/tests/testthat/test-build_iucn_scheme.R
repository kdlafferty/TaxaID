# tests/testthat/test-build_iucn_scheme.R
#
# Tests for build_iucn_scheme() -- construct IUCN habitat_scheme dataframes.
# All tests are pure (no API calls, no files, no network).
# Uses the internal .iucn_habitat_lookup table via package load_all.

# ==============================================================================
# Part A: Input validation
# ==============================================================================

test_that("stops on invalid realm", {
  expect_error(build_iucn_scheme(realm = "deep_sea"), "realm.*must be one of")
  expect_error(build_iucn_scheme(realm = "Marine"),   "realm.*must be one of")
})

test_that("stops when both l1 and l2 are 'none'", {
  expect_error(build_iucn_scheme(l1 = "none", l2 = "none"),
               "cannot both be")
})

test_that("stops on unrecognised L1 name", {
  expect_error(build_iucn_scheme(l1 = "Deep Ocean"),
               "unrecognised L1")
})

test_that("stops on unrecognised L2 name with helpful hint", {
  # "Rocky Subtidal" exists but only under marine realm
  err <- tryCatch(
    build_iucn_scheme(realm = "freshwater", l2 = "Rocky Subtidal"),
    error = function(e) conditionMessage(e)
  )
  expect_match(err, "unrecognised L2")
  # Should tell user the correct parent
  expect_match(err, "Marine Neritic")
})

test_that("stops on L2 name that doesn't exist in IUCN at all", {
  err <- tryCatch(
    build_iucn_scheme(l2 = "Coral Atoll"),
    error = function(e) conditionMessage(e)
  )
  expect_match(err, "not in the IUCN classification")
})

test_that("l1 non-character stops", {
  expect_error(build_iucn_scheme(l1 = 1), "must be")
})

# ==============================================================================
# Part B: Return structure
# ==============================================================================

test_that("returns a data.frame invisibly", {
  result <- build_iucn_scheme(realm = "marine")
  expect_s3_class(result, "data.frame")
})

test_that("result has required columns", {
  result <- build_iucn_scheme(realm = "marine")
  expect_true(all(c("l1_name", "l2_name", "l2_code", "realm") %in% names(result)))
})

test_that("realm column values are valid", {
  result <- build_iucn_scheme()
  valid  <- c("marine", "freshwater", "terrestrial", NA)
  expect_true(all(result$realm %in% valid))
})

# ==============================================================================
# Part C: Realm filtering
# ==============================================================================

test_that("realm = 'marine' returns only marine L1 groups", {
  result   <- build_iucn_scheme(realm = "marine")
  l1_names <- unique(result$l1_name)
  expect_true(all(grepl("^Marine", l1_names)))
  expect_equal(length(l1_names), 5L)
})

test_that("realm = 'freshwater' returns only Wetlands (inland)", {
  result <- build_iucn_scheme(realm = "freshwater")
  expect_equal(unique(result$l1_name), "Wetlands (inland)")
})

test_that("realm = 'terrestrial' excludes marine and artificial groups", {
  result   <- build_iucn_scheme(realm = "terrestrial")
  l1_names <- unique(result$l1_name)
  expect_false(any(grepl("^Marine|^Artificial", l1_names)))
})

test_that("realm = 'artificial' returns Artificial groups only", {
  result   <- build_iucn_scheme(realm = "artificial")
  l1_names <- unique(result$l1_name)
  expect_true(all(grepl("^Artificial", l1_names)))
  expect_equal(length(l1_names), 2L)
})

test_that("realm = NULL excludes Other and Unknown", {
  result   <- build_iucn_scheme()
  l1_names <- unique(result$l1_name)
  expect_false("Other" %in% l1_names)
  expect_false("Unknown" %in% l1_names)
})

# ==============================================================================
# Part D: l1 parameter
# ==============================================================================

test_that("l1 = 'all' (default) includes all L1 in scope as single-level rows", {
  result    <- build_iucn_scheme(realm = "marine")
  l1_rows   <- result[is.na(result$l2_name), ]
  expect_equal(nrow(l1_rows), 5L)  # 5 marine L1 groups
})

test_that("l1 = 'none' produces no L1-only rows", {
  result  <- build_iucn_scheme(realm = "marine", l1 = "none", l2 = "all")
  l1_rows <- result[is.na(result$l2_name), ]
  expect_equal(nrow(l1_rows), 0L)
})

test_that("l1 vector selects only specified groups", {
  result    <- build_iucn_scheme(realm = "marine",
                                  l1 = "Marine Neritic")
  l1_rows   <- result[is.na(result$l2_name), ]
  expect_equal(nrow(l1_rows), 1L)
  expect_equal(l1_rows$l1_name, "Marine Neritic")
})

test_that("unrecognised L1 in realm scope stops with available options", {
  err <- tryCatch(
    build_iucn_scheme(realm = "marine", l1 = "Forest"),
    error = function(e) conditionMessage(e)
  )
  expect_match(err, "unrecognised L1")
  expect_match(err, "Marine Neritic")
})

# ==============================================================================
# Part E: l2 parameter
# ==============================================================================

test_that("l2 = 'none' (default) gives single-level L1-only scheme", {
  result  <- build_iucn_scheme(realm = "marine")
  l2_rows <- result[!is.na(result$l2_name), ]
  expect_equal(nrow(l2_rows), 0L)
})

test_that("l2 = 'all' includes all L2 subcategories", {
  result  <- build_iucn_scheme(realm = "marine", l2 = "all")
  l2_rows <- result[!is.na(result$l2_name), ]
  expect_gt(nrow(l2_rows), 0L)
  # Marine has 31 L2 subcategories
  expect_equal(nrow(l2_rows), 31L)
})

test_that("specific l2 vector selects only named subcategories", {
  result  <- build_iucn_scheme(realm = "marine",
                                l2 = c("Rocky Subtidal", "Estuaries"))
  l2_rows <- result[!is.na(result$l2_name), ]
  expect_equal(nrow(l2_rows), 2L)
  expect_true("Rocky Subtidal" %in% l2_rows$l2_name)
  expect_true("Estuaries" %in% l2_rows$l2_name)
})

test_that("l2 selection auto-adds parent L1 group", {
  result  <- build_iucn_scheme(realm = "marine", l1 = "none",
                                l2 = c("Rocky Subtidal"))
  # l1 = "none" means no L1-only rows, but L1 parent is in l1_name of L2 row
  l2_rows <- result[!is.na(result$l2_name), ]
  expect_equal(unique(l2_rows$l1_name), "Marine Neritic")
})

test_that("l2 auto-adds L1 parent as fallback row when l1 = 'all'", {
  result  <- build_iucn_scheme(l2 = "Rocky Subtidal")
  l1_rows <- result[is.na(result$l2_name), ]
  l1_names <- unique(l1_rows$l1_name)
  # Marine Neritic should be present as an L1 fallback
  expect_true("Marine Neritic" %in% l1_names)
})

test_that("l2_code is populated for L2 rows", {
  result  <- build_iucn_scheme(realm = "marine", l2 = c("Rocky Subtidal"))
  l2_rows <- result[!is.na(result$l2_name), ]
  expect_false(is.na(l2_rows$l2_code[l2_rows$l2_name == "Rocky Subtidal"]))
  expect_equal(l2_rows$l2_code[l2_rows$l2_name == "Rocky Subtidal"], "9.4")
})

# ==============================================================================
# Part F: Duplicate L2 name disambiguation
# ==============================================================================

test_that("duplicate L2 names are disambiguated with L1 parent", {
  # "Boreal" appears under Forest and Shrubland
  result <- build_iucn_scheme(
    l1 = c("Forest", "Shrubland"),
    l2 = "all"
  )
  l2_names <- result$l2_name[!is.na(result$l2_name)]
  # Neither raw "Boreal" should appear -- should be "Boreal (Forest)" etc.
  boreal_raw <- l2_names[l2_names == "Boreal"]
  expect_equal(length(boreal_raw), 0L)
  boreal_disambig <- l2_names[grepl("^Boreal \\(", l2_names)]
  expect_gt(length(boreal_disambig), 0L)
})

test_that("non-duplicate L2 names are not modified", {
  result  <- build_iucn_scheme(realm = "marine", l2 = "all")
  l2_rows <- result[!is.na(result$l2_name), ]
  # Marine L2 names may naturally contain parentheses (e.g. "Seagrass (Beds)",
  # "Pelagic (Supercolumnar)"). Disambiguation adds " (L1 parent)" suffix where
  # the L1 parent name starts with a capital letter and follows a space+paren.
  # Marine L2 names are all unique so none should have been disambiguated.
  # Check that no name ends with a known marine L1 group name in parens.
  marine_l1 <- c("Marine Neritic", "Marine Oceanic", "Marine Deep Ocean Floor",
                  "Marine Intertidal", "Marine Coastal/Supralittoral")
  disambig_pattern <- paste(
    sprintf("\\(%s\\)$", gsub("([/()])", "\\\\\\1", marine_l1)),
    collapse = "|"
  )
  has_disambig <- any(grepl(disambig_pattern, l2_rows$l2_name))
  expect_false(has_disambig)
})

# ==============================================================================
# Part G: Integration with build_habitat_prompt
# ==============================================================================

test_that("result passes to build_habitat_prompt without error", {
  scheme <- build_iucn_scheme(realm = "marine",
                               l2 = c("Rocky Subtidal", "Estuaries"))
  taxa   <- c("Gadus morhua", "Sebastes mystinus")
  expect_no_error(build_habitat_prompt(taxa, habitat_scheme = scheme))
})

test_that("mixed L1+L2 scheme produces correct habitat_cols in prompt", {
  scheme <- build_iucn_scheme(realm = "marine",
                               l2 = c("Rocky Subtidal", "Estuaries"))
  taxa   <- c("Gadus morhua", "Sebastes mystinus")
  prompt <- build_habitat_prompt(taxa, habitat_scheme = scheme)
  # Should include both L2 names and L1 parent names
  expect_true("Rocky Subtidal" %in% prompt$habitat_cols)
  expect_true("Estuaries" %in% prompt$habitat_cols)
  expect_true("Marine Neritic" %in% prompt$habitat_cols)  # L1 fallback
})

test_that("L1-only scheme produces single-level habitat_cols", {
  scheme <- build_iucn_scheme(realm = "marine")  # default: l2 = "none"
  taxa   <- c("Gadus morhua", "Sebastes mystinus")
  prompt <- build_habitat_prompt(taxa, habitat_scheme = scheme)
  # All habitat_cols should be L1 group names
  expect_true(all(prompt$habitat_cols %in% unique(prompt$scheme$l1_name)))
})
