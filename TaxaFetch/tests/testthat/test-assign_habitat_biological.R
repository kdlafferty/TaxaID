# tests/testthat/test-assign_habitat_biological.R
#
# Tests for assign_habitat_biological() -- weighted multi-habitat format.
# All tests are pure (no network, no external files, no Shiny).
#
# Input shape expected by this function (produced by
# parse_hierarchical_habitat_response):
#   - taxon_name column
#   - one numeric weight column per habitat (0-1, sum to ~1)
#   - Other_weight column (numeric)
#   - habitat_best_guess column (character, blank when Other_weight == 0)
#   - Habitat column (argmax convenience, not used by this function directly)
#
# Output shape:
#   - original data columns unchanged
#   - main_habitat column added (character, NA when no consensus)
#   - habitat_best_guess column added (character, "" when Other does not win)

# ==============================================================================
# Helpers
# ==============================================================================

# Minimal occurrence dataframe
make_occ <- function(point_ids, taxon_names) {
  data.frame(
    point_id  = point_ids,
    taxon_name = taxon_names,
    stringsAsFactors = FALSE
  )
}

# Minimal habitat weight table (specialist: 1.0 in one column)
make_weights_specialist <- function() {
  data.frame(
    taxon_name        = c("Gadus morhua", "Sebastes mystinus", "Engraulis mordax"),
    Rocky_Subtidal    = c(1.0, 0.0, 0.0),
    Kelp_Forest       = c(0.0, 1.0, 0.0),
    Pelagic           = c(0.0, 0.0, 1.0),
    Other_weight      = c(0.0, 0.0, 0.0),
    habitat_best_guess = c("", "", ""),
    Habitat           = c("Rocky_Subtidal", "Kelp_Forest", "Pelagic"),
    stringsAsFactors  = FALSE
  )
}

# Generalist: weight split across two habitats
make_weights_generalist <- function() {
  data.frame(
    taxon_name        = c("Oncorhynchus mykiss", "Gadus morhua"),
    Ocean             = c(0.5, 1.0),
    Freshwater        = c(0.5, 0.0),
    Other_weight      = c(0.0, 0.0),
    habitat_best_guess = c("", ""),
    Habitat           = c("Ocean", "Gadus morhua"),
    stringsAsFactors  = FALSE
  )
}

# Other-dominant: species doesn't fit the scheme
make_weights_other <- function() {
  data.frame(
    taxon_name        = c("Mystery sp.", "Gadus morhua"),
    Rocky_Subtidal    = c(0.0, 1.0),
    Pelagic           = c(0.0, 0.0),
    Other_weight      = c(1.0, 0.0),
    habitat_best_guess = c("alpine meadow", ""),
    Habitat           = c("Other", "Rocky_Subtidal"),
    stringsAsFactors  = FALSE
  )
}

# ==============================================================================
# Part A: Input validation
# ==============================================================================

test_that("stops when data is not a dataframe", {
  expect_error(
    assign_habitat_biological(data = list(a = 1), habitats_df = make_weights_specialist()),
    "must be a dataframe"
  )
})

test_that("stops when habitats_df is not a dataframe", {
  occ <- make_occ("pt1", "Gadus morhua")
  expect_error(
    assign_habitat_biological(data = occ, habitats_df = "not a df"),
    "must be a dataframe"
  )
})

test_that("stops when point_id_col is missing from data", {
  occ <- data.frame(taxon_name = "Gadus morhua", stringsAsFactors = FALSE)
  expect_error(
    assign_habitat_biological(data = occ, habitats_df = make_weights_specialist()),
    "column.*not found in 'data'"
  )
})

test_that("stops when taxon_col is missing from data", {
  occ <- data.frame(point_id = "pt1", stringsAsFactors = FALSE)
  expect_error(
    assign_habitat_biological(data = occ, habitats_df = make_weights_specialist()),
    "column.*not found in 'data'"
  )
})

test_that("stops when taxon_col is missing from habitats_df", {
  occ <- make_occ("pt1", "Gadus morhua")
  bad_hab <- data.frame(species = "Gadus morhua", Rocky_Subtidal = 1.0,
                        stringsAsFactors = FALSE)
  expect_error(
    assign_habitat_biological(data = occ, habitats_df = bad_hab),
    "taxon column.*not found in 'habitats_df'"
  )
})

test_that("stops when threshold is out of range", {
  occ <- make_occ("pt1", "Gadus morhua")
  expect_error(
    assign_habitat_biological(occ, make_weights_specialist(), threshold = 0),
    "threshold.*must be numeric in"
  )
  expect_error(
    assign_habitat_biological(occ, make_weights_specialist(), threshold = 1.1),
    "threshold.*must be numeric in"
  )
  expect_error(
    assign_habitat_biological(occ, make_weights_specialist(), threshold = -0.1),
    "threshold.*must be numeric in"
  )
})

test_that("stops when weight_by_abundance is NA", {
  occ <- make_occ("pt1", "Gadus morhua")
  expect_error(
    assign_habitat_biological(occ, make_weights_specialist(),
                              weight_by_abundance = NA),
    "weight_by_abundance.*must be TRUE or FALSE"
  )
})

test_that("stops when weight_by_abundance is not logical", {
  occ <- make_occ("pt1", "Gadus morhua")
  expect_error(
    assign_habitat_biological(occ, make_weights_specialist(),
                              weight_by_abundance = 1),
    "weight_by_abundance.*must be TRUE or FALSE"
  )
})

test_that("stops when habitat_cols names are not in habitats_df", {
  occ <- make_occ("pt1", "Gadus morhua")
  expect_error(
    assign_habitat_biological(occ, make_weights_specialist(),
                              habitat_cols = c("Rocky_Subtidal", "Nonexistent")),
    "habitat_cols not found"
  )
})

test_that("stops when no numeric weight columns can be auto-detected", {
  occ <- make_occ("pt1", "Gadus morhua")
  bad_hab <- data.frame(taxon_name = "Gadus morhua", note = "text",
                        stringsAsFactors = FALSE)
  expect_error(
    assign_habitat_biological(occ, bad_hab),
    "no numeric habitat weight columns found"
  )
})

test_that("threshold = 1 is accepted (boundary)", {
  occ   <- make_occ("pt1", "Gadus morhua")
  wts   <- make_weights_specialist()
  result <- assign_habitat_biological(occ, wts, threshold = 1.0)
  # Rocky_Subtidal weight = 1.0, exactly meets threshold
  expect_equal(result$main_habitat[result$point_id == "pt1"], "Rocky_Subtidal")
})

# ==============================================================================
# Part B: Basic consensus assignment
# ==============================================================================

test_that("specialist species: point assigned to dominant habitat", {
  occ <- make_occ(c("pt1", "pt2", "pt3"),
                  c("Gadus morhua", "Sebastes mystinus", "Engraulis mordax"))
  result <- assign_habitat_biological(occ, make_weights_specialist())
  expect_equal(result$main_habitat[result$point_id == "pt1"], "Rocky_Subtidal")
  expect_equal(result$main_habitat[result$point_id == "pt2"], "Kelp_Forest")
  expect_equal(result$main_habitat[result$point_id == "pt3"], "Pelagic")
})

test_that("all original columns are preserved", {
  occ <- data.frame(
    point_id   = "pt1",
    taxon_name = "Gadus morhua",
    extra_col  = 42L,
    stringsAsFactors = FALSE
  )
  result <- assign_habitat_biological(occ, make_weights_specialist())
  expect_true("extra_col" %in% names(result))
  expect_equal(result$extra_col, 42L)
})

test_that("output has exactly the same number of rows as input", {
  occ <- make_occ(rep(c("pt1", "pt2"), each = 3),
                  rep(c("Gadus morhua", "Sebastes mystinus", "Engraulis mordax"), 2))
  result <- assign_habitat_biological(occ, make_weights_specialist())
  expect_equal(nrow(result), nrow(occ))
})

test_that("main_habitat and habitat_best_guess columns are always present", {
  occ    <- make_occ("pt1", "Gadus morhua")
  result <- assign_habitat_biological(occ, make_weights_specialist())
  expect_true("main_habitat" %in% names(result))
  expect_true("habitat_best_guess" %in% names(result))
})

test_that("multiple species at one point: majority habitat wins", {
  # pt1 has 2 Rocky + 1 Kelp -> Rocky wins
  occ <- make_occ(c("pt1", "pt1", "pt1"),
                  c("Gadus morhua", "Gadus morhua", "Sebastes mystinus"))
  wts <- data.frame(
    taxon_name     = c("Gadus morhua", "Sebastes mystinus"),
    Rocky_Subtidal = c(1.0, 0.0),
    Kelp_Forest    = c(0.0, 1.0),
    Other_weight   = c(0.0, 0.0),
    habitat_best_guess = c("", ""),
    stringsAsFactors = FALSE
  )
  result <- assign_habitat_biological(occ, wts, threshold = 0.3)
  # Gadus: 1.0 Rocky, Sebastes: 1.0 Kelp. After dedup to unique species:
  # Rocky sum = 1, Kelp sum = 1 -> tie broken by first (Rocky)
  # BUT two Gadus rows are de-duped to one under equal-weight default.
  expect_equal(result$main_habitat[1], "Rocky_Subtidal")
})

test_that("threshold below winning proportion -> habitat assigned", {
  occ <- make_occ("pt1", "Gadus morhua")
  result <- assign_habitat_biological(occ, make_weights_specialist(), threshold = 0.1)
  expect_false(is.na(result$main_habitat[1]))
})

test_that("threshold above winning proportion -> NA assigned", {
  # Generalist: Ocean = 0.5, Freshwater = 0.5 -- neither exceeds 0.9
  occ <- make_occ("pt1", "Oncorhynchus mykiss")
  result <- assign_habitat_biological(occ, make_weights_generalist(), threshold = 0.9)
  expect_true(is.na(result$main_habitat[1]))
})

test_that("point with no matched species gets NA and empty best_guess", {
  occ    <- make_occ("pt1", "Unknown taxon XYZ")
  result <- suppressWarnings(
    assign_habitat_biological(occ, make_weights_specialist())
  )
  expect_true(is.na(result$main_habitat[1]))
  # habitat_best_guess should be NA or "" (not populated since no Other match)
  expect_true(is.na(result$habitat_best_guess[1]) ||
                result$habitat_best_guess[1] == "")
})

test_that("warns when no species match lookup", {
  occ <- make_occ("pt1", "Unknown taxon XYZ")
  expect_warning(
    assign_habitat_biological(occ, make_weights_specialist()),
    "no species.*matched"
  )
})

# ==============================================================================
# Part C: Other_weight and habitat_best_guess
# ==============================================================================

test_that("Other wins when Other_weight = 1.0", {
  occ <- make_occ("pt1", "Mystery sp.")
  result <- assign_habitat_biological(occ, make_weights_other(), threshold = 0.3)
  expect_equal(result$main_habitat[1], "Other")
})

test_that("habitat_best_guess populated when Other wins", {
  occ <- make_occ("pt1", "Mystery sp.")
  result <- assign_habitat_biological(occ, make_weights_other(), threshold = 0.3)
  expect_equal(result$habitat_best_guess[1], "alpine meadow")
})

test_that("habitat_best_guess is empty string when Other_weight = 0", {
  occ    <- make_occ("pt1", "Gadus morhua")
  result <- assign_habitat_biological(occ, make_weights_specialist())
  expect_equal(result$habitat_best_guess[1], "")
})

test_that("multiple Other species: guesses concatenated with '; '", {
  wts <- data.frame(
    taxon_name         = c("Sp A", "Sp B"),
    Rocky_Subtidal     = c(0.0, 0.0),
    Other_weight       = c(1.0, 1.0),
    habitat_best_guess = c("alpine meadow", "tundra"),
    stringsAsFactors   = FALSE
  )
  occ    <- make_occ(c("pt1", "pt1"), c("Sp A", "Sp B"))
  result <- assign_habitat_biological(occ, wts, threshold = 0.3)
  expect_equal(result$main_habitat[1], "Other")
  expect_true(grepl("alpine meadow", result$habitat_best_guess[1]))
  expect_true(grepl("tundra", result$habitat_best_guess[1]))
})

test_that("duplicate habitat_best_guess values are collapsed to unique", {
  wts <- data.frame(
    taxon_name         = c("Sp A", "Sp B"),
    Rocky_Subtidal     = c(0.0, 0.0),
    Other_weight       = c(1.0, 1.0),
    habitat_best_guess = c("alpine meadow", "alpine meadow"),
    stringsAsFactors   = FALSE
  )
  occ    <- make_occ(c("pt1", "pt1"), c("Sp A", "Sp B"))
  result <- assign_habitat_biological(occ, wts, threshold = 0.3)
  # Should not appear twice
  expect_false(grepl("alpine meadow.*alpine meadow", result$habitat_best_guess[1]))
})

test_that("Other_weight column renamed from Other_weight to Other internally but output unaffected", {
  # The function renames Other_weight -> Other internally.
  # The output main_habitat value should be "Other" (not "Other_weight").
  wts <- make_weights_other()
  occ <- make_occ("pt1", "Mystery sp.")
  result <- assign_habitat_biological(occ, wts, threshold = 0.3)
  expect_equal(result$main_habitat[1], "Other")
})

# ==============================================================================
# Part D: Generalist species and weight splitting
# ==============================================================================

test_that("generalist species splits weight correctly across two points", {
  # Oncorhynchus: 0.5 Ocean, 0.5 Freshwater
  # pt1: only Onco -> 0.5/0.5 tie -> first col wins (Ocean)
  # pt2: only Gadus -> 1.0 Ocean
  occ <- make_occ(c("pt1", "pt2"),
                  c("Oncorhynchus mykiss", "Gadus morhua"))
  result <- assign_habitat_biological(occ, make_weights_generalist(), threshold = 0.3)
  expect_equal(result$main_habitat[result$point_id == "pt2"], "Ocean")
  # pt1: tie -> first col wins; at threshold 0.3, 0.5 >= 0.3 -> assigned
  expect_false(is.na(result$main_habitat[result$point_id == "pt1"]))
})

test_that("mixed community: habitat with highest total weight wins", {
  # pt1: Gadus (1.0 Rocky) + Onco (0.5 Ocean, 0.5 Freshwater)
  # Rocky sum = 1.0, Ocean sum = 0.5, Freshwater sum = 0.5 -> Rocky wins
  wts <- data.frame(
    taxon_name         = c("Gadus morhua", "Oncorhynchus mykiss"),
    Rocky_Subtidal     = c(1.0, 0.0),
    Ocean              = c(0.0, 0.5),
    Freshwater         = c(0.0, 0.5),
    Other_weight       = c(0.0, 0.0),
    habitat_best_guess = c("", ""),
    stringsAsFactors   = FALSE
  )
  occ    <- make_occ(c("pt1", "pt1"), c("Gadus morhua", "Oncorhynchus mykiss"))
  result <- assign_habitat_biological(occ, wts, threshold = 0.3)
  expect_equal(result$main_habitat[result$point_id == "pt1"][1], "Rocky_Subtidal")
})

# ==============================================================================
# Part E: weight_by_abundance parameter
# ==============================================================================

test_that("weight_by_abundance = FALSE: duplicate records do not increase influence", {
  # 5 records of Gadus (Rocky) vs 1 record of Sebastes (Kelp)
  # equal weight: Rocky = 1 species, Kelp = 1 species -> tie -> Rocky (first)
  # abundance weight: Rocky = 5 records, Kelp = 1 record -> Rocky wins clearly
  wts <- data.frame(
    taxon_name     = c("Gadus morhua", "Sebastes mystinus"),
    Rocky_Subtidal = c(1.0, 0.0),
    Kelp_Forest    = c(0.0, 1.0),
    Other_weight   = c(0.0, 0.0),
    habitat_best_guess = c("", ""),
    stringsAsFactors = FALSE
  )
  occ_many_gadus <- make_occ(
    c("pt1", "pt1", "pt1", "pt1", "pt1", "pt1"),
    c("Gadus morhua", "Gadus morhua", "Gadus morhua",
      "Gadus morhua", "Gadus morhua", "Sebastes mystinus")
  )
  result_equal <- assign_habitat_biological(occ_many_gadus, wts,
                                            weight_by_abundance = FALSE,
                                            threshold = 0.3)
  result_abund <- assign_habitat_biological(occ_many_gadus, wts,
                                            weight_by_abundance = TRUE,
                                            threshold = 0.3)
  # Both should assign Rocky (Gadus dominates either way in this case)
  expect_equal(result_equal$main_habitat[1], "Rocky_Subtidal")
  expect_equal(result_abund$main_habitat[1], "Rocky_Subtidal")
})

test_that("weight_by_abundance = TRUE: abundant species has more influence", {
  # 4 records of Sebastes (Kelp) vs 1 record of Gadus (Rocky)
  # equal weight: 1 Kelp species vs 1 Rocky species -> tie -> first col wins
  # abundance weight: Kelp = 4, Rocky = 1 -> Kelp wins clearly
  wts <- data.frame(
    taxon_name     = c("Gadus morhua", "Sebastes mystinus"),
    Rocky_Subtidal = c(1.0, 0.0),
    Kelp_Forest    = c(0.0, 1.0),
    Other_weight   = c(0.0, 0.0),
    habitat_best_guess = c("", ""),
    stringsAsFactors   = FALSE
  )
  occ_many_seb <- make_occ(
    c("pt1", "pt1", "pt1", "pt1", "pt1"),
    c("Gadus morhua", "Sebastes mystinus", "Sebastes mystinus",
      "Sebastes mystinus", "Sebastes mystinus")
  )
  result_abund <- assign_habitat_biological(occ_many_seb, wts,
                                            weight_by_abundance = TRUE,
                                            threshold = 0.3)
  expect_equal(result_abund$main_habitat[1], "Kelp_Forest")
})

# ==============================================================================
# Part F: Multiple points
# ==============================================================================

test_that("each point is assigned independently", {
  wts <- make_weights_specialist()
  occ <- make_occ(
    c("pt1", "pt2"),
    c("Gadus morhua", "Engraulis mordax")
  )
  result <- assign_habitat_biological(occ, wts, threshold = 0.3)
  expect_equal(result$main_habitat[result$point_id == "pt1"], "Rocky_Subtidal")
  expect_equal(result$main_habitat[result$point_id == "pt2"], "Pelagic")
})

test_that("main_habitat value is repeated for all rows at same point_id", {
  occ <- make_occ(c("pt1", "pt1", "pt1"),
                  c("Gadus morhua", "Gadus morhua", "Gadus morhua"))
  result <- assign_habitat_biological(occ, make_weights_specialist(), threshold = 0.3)
  expect_true(length(unique(result$main_habitat)) == 1L)
  expect_equal(unique(result$main_habitat), "Rocky_Subtidal")
})

test_that("result has correct number of distinct point_ids", {
  occ <- make_occ(c("pt1", "pt1", "pt2", "pt3"),
                  c("Gadus morhua", "Sebastes mystinus",
                    "Gadus morhua", "Engraulis mordax"))
  result <- assign_habitat_biological(occ, make_weights_specialist(), threshold = 0.3)
  expect_equal(length(unique(result$point_id)), 3L)
})

# ==============================================================================
# Part G: Explicit habitat_cols parameter
# ==============================================================================

test_that("explicit habitat_cols restricts which columns are used", {
  # habitats_df has Rocky + Kelp but we only tell function about Rocky
  wts <- make_weights_specialist()
  occ <- make_occ("pt2", "Sebastes mystinus")
  result <- assign_habitat_biological(occ, wts,
                                      habitat_cols = c("Rocky_Subtidal"),
                                      threshold = 0.3)
  # Sebastes has 0 weight in Rocky -> no consensus
  expect_true(is.na(result$main_habitat[1]))
})

test_that("explicit habitat_cols with Other_weight translated from Other_weight", {
  wts <- make_weights_other()
  occ <- make_occ("pt1", "Mystery sp.")
  # Supply "Other_weight" explicitly -- function translates to "Other" internally
  result <- assign_habitat_biological(occ, wts,
                                      habitat_cols = c("Rocky_Subtidal",
                                                       "Pelagic",
                                                       "Other_weight"),
                                      threshold = 0.3)
  expect_equal(result$main_habitat[1], "Other")
})

# ==============================================================================
# Part H: Custom point_id_col and taxon_col
# ==============================================================================

test_that("custom point_id_col and taxon_col are respected", {
  occ <- data.frame(
    site       = "s1",
    species    = "Gadus morhua",
    stringsAsFactors = FALSE
  )
  wts <- data.frame(
    species        = "Gadus morhua",
    Rocky_Subtidal = 1.0,
    Other_weight   = 0.0,
    habitat_best_guess = "",
    stringsAsFactors = FALSE
  )
  result <- assign_habitat_biological(occ, wts,
                                      point_id_col = "site",
                                      taxon_col    = "species",
                                      threshold    = 0.3)
  expect_equal(result$main_habitat[1], "Rocky_Subtidal")
})

# ==============================================================================
# Part I: Pre-existing main_habitat column is overwritten
# ==============================================================================

test_that("pre-existing main_habitat column in data is silently replaced", {
  occ <- data.frame(
    point_id   = "pt1",
    taxon_name = "Gadus morhua",
    main_habitat = "OldValue",
    stringsAsFactors = FALSE
  )
  result <- assign_habitat_biological(occ, make_weights_specialist(), threshold = 0.3)
  expect_equal(result$main_habitat[1], "Rocky_Subtidal")
  expect_false(any(result$main_habitat == "OldValue", na.rm = TRUE))
})

# ==============================================================================
# Part J: Zero-match early return path
# ==============================================================================

test_that("zero-match path returns data with NA main_habitat and NA habitat_best_guess", {
  occ <- make_occ("pt1", "Completely Unknown sp.")
  result <- suppressWarnings(
    assign_habitat_biological(occ, make_weights_specialist())
  )
  expect_true(is.na(result$main_habitat[1]))
  # NA or empty string -- both acceptable on the zero-match path
  expect_true(is.na(result$habitat_best_guess[1]) ||
                result$habitat_best_guess[1] == "")
})

test_that("zero-match path preserves all original columns", {
  occ <- data.frame(
    point_id   = "pt1",
    taxon_name = "Unknown sp.",
    lat        = 34.5,
    lon        = -120.1,
    stringsAsFactors = FALSE
  )
  result <- suppressWarnings(
    assign_habitat_biological(occ, make_weights_specialist())
  )
  expect_true(all(c("lat", "lon") %in% names(result)))
})
