# tests/testthat/test-site_utils.R
# New file (code review, 2026-08): these internal helpers had no dedicated
# test coverage before -- only indirectly exercised via run_bayesian_pipeline()/
# join_priors() test fixtures.

# ---- .parse_grid_ids() -------------------------------------------------------

test_that(".parse_grid_ids parses lat/lon out of the Grid_{lat}_{lon} encoding", {
  out <- .parse_grid_ids(c("Grid_34p1_m119p1", "Grid_0p0_0p0"))
  expect_equal(out$grid_lat, c(34.1, 0.0))
  expect_equal(out$grid_lon, c(-119.1, 0.0))
})

# ---- .find_nearest_grid() -----------------------------------------------------

test_that(".find_nearest_grid returns the closest cell and a distance", {
  grid_coords <- .parse_grid_ids(c("Grid_34p0_m119p0", "Grid_40p0_m119p0"))
  out <- .find_nearest_grid(34.1, -119.0, grid_coords)
  expect_equal(out$grid_id, "Grid_34p0_m119p0")
  expect_true(out$dist_deg < 1)
})

test_that(".find_nearest_grid's cosine-latitude correction picks the geographically nearer cell at high latitude", {
  # At 60N, 1 degree of longitude is much shorter in real distance than
  # 1 degree of latitude (~cos(60) = 0.5x) -- a naive Euclidean degree
  # distance would treat a 2-degree lat gap and a 4-degree lon gap as
  # equally far (4^2 == 2^2 + ~3.46^2 in real terms), but the real nearer
  # cell is the one with the SMALLER latitude gap once longitude is
  # correctly down-weighted.
  grid_coords <- .parse_grid_ids(c("Grid_60p0_m10p0", "Grid_62p0_m4p0"))
  query_lat <- 60.0
  query_lon <- -8.0
  out <- .find_nearest_grid(query_lat, query_lon, grid_coords)
  expect_equal(out$grid_id, "Grid_60p0_m10p0")
})

test_that(".find_nearest_grid reduces to the closer cell in a simple equatorial case", {
  grid_coords <- .parse_grid_ids(c("Grid_0p0_0p0", "Grid_0p0_5p0"))
  out <- .find_nearest_grid(0, 1, grid_coords)
  expect_equal(out$grid_id, "Grid_0p0_0p0")
})

# ---- .build_context_block() ---------------------------------------------------

test_that(".build_context_block returns empty string for NULL/empty context", {
  expect_equal(.build_context_block(NULL), "")
  expect_equal(.build_context_block(list()), "")
})

test_that(".build_context_block formats populated fields and skips empty ones", {
  ctx <- list(ecoregion = "California Coast", main_habitat = "Estuarine", lat = NA)
  out <- .build_context_block(ctx)
  expect_true(grepl("Ecoregion: California Coast", out, fixed = TRUE))
  expect_true(grepl("Habitat: Estuarine", out, fixed = TRUE))
  expect_false(grepl("Latitude", out, fixed = TRUE))
})

test_that(".build_context_block respects a custom habitat_field name", {
  ctx <- list(habitat = "Marine")
  out <- .build_context_block(ctx, habitat_field = "habitat")
  expect_true(grepl("Habitat: Marine", out, fixed = TRUE))
})

# ---- .check_rank_system_order() -----------------------------------------------

test_that(".check_rank_system_order is silent for a correctly-ordered rank_system", {
  expect_no_warning(.check_rank_system_order(c("family", "genus", "species"), "test"))
})

test_that(".check_rank_system_order warns for a reversed rank_system", {
  expect_warning(
    .check_rank_system_order(c("species", "genus", "family"), "test"),
    "disagrees in.*relative order"
  )
})

test_that(".check_rank_system_order is silent when fewer than 2 ranks overlap with standard_ranks", {
  expect_no_warning(.check_rank_system_order(c("custom_rank_a", "custom_rank_b"), "test"))
  expect_no_warning(.check_rank_system_order(NULL, "test"))
  expect_no_warning(.check_rank_system_order("species", "test"))
})

# ---- .beta_mean() --------------------------------------------------------------

test_that(".beta_mean computes alpha / (alpha + beta)", {
  expect_equal(.beta_mean(3, 7), 0.3)
  expect_equal(.beta_mean(c(1, 9), c(1, 1)), c(0.5, 0.9))
})

# ---- .resolve_site() -----------------------------------------------------------

.make_taxaexpect_priors_for_site <- function() {
  data.frame(
    taxon_name   = "Gadus morhua",
    grid_id      = "Grid_34p1_m119p1",
    main_habitat = "Estuarine Bay",
    stringsAsFactors = FALSE
  )
}

test_that(".resolve_site handles list(grid_id, main_habitat)", {
  out <- .resolve_site(
    list(grid_id = "Grid_34p1_m119p1", main_habitat = "Estuarine Bay"),
    c("S1", "S2"), .make_taxaexpect_priors_for_site()
  )
  expect_equal(nrow(out), 2L)
  expect_true(all(out$grid_id == "Grid_34p1_m119p1"))
})

test_that(".resolve_site handles list(lat, lon, main_habitat)", {
  out <- suppressWarnings(.resolve_site(
    list(lat = 34.1, lon = -119.1, main_habitat = "Estuarine Bay"),
    "S1", .make_taxaexpect_priors_for_site()
  ))
  expect_equal(out$grid_id, "Grid_34p1_m119p1")
  expect_equal(out$main_habitat, "Estuarine Bay")
})

test_that(".resolve_site handles a multi-site data frame with grid_id/main_habitat", {
  site_df <- data.frame(
    observation_id = c("S1", "S2"),
    grid_id         = c("Grid_34p1_m119p1", "Grid_34p1_m119p1"),
    main_habitat    = c("Estuarine Bay", "Estuarine Bay"),
    stringsAsFactors = FALSE
  )
  out <- .resolve_site(site_df, c("S1", "S2"), .make_taxaexpect_priors_for_site())
  expect_equal(nrow(out), 2L)
})

test_that(".resolve_site errors on an unsupported site format", {
  expect_error(
    .resolve_site("not_a_list_or_df", "S1", .make_taxaexpect_priors_for_site()),
    "must be a named list"
  )
})

test_that(".resolve_site errors when a list lacks both grid_id/main_habitat and lat/lon", {
  expect_error(
    .resolve_site(list(main_habitat = "Estuarine Bay"), "S1", .make_taxaexpect_priors_for_site()),
    "must have either"
  )
})

# ---- .latlon_to_grid() ----------------------------------------------------------

test_that(".latlon_to_grid resolves to the nearest grid with the requested habitat", {
  out <- .latlon_to_grid(34.1, -119.1, "Estuarine Bay", .make_taxaexpect_priors_for_site())
  expect_equal(out$grid_id, "Grid_34p1_m119p1")
  expect_equal(out$main_habitat, "Estuarine Bay")
})

test_that(".latlon_to_grid errors with an informative message when main_habitat is NULL", {
  expect_error(
    .latlon_to_grid(34.1, -119.1, NULL, .make_taxaexpect_priors_for_site()),
    "main_habitat.*required"
  )
})

test_that(".latlon_to_grid errors when main_habitat isn't available at the resolved grid", {
  expect_error(
    .latlon_to_grid(34.1, -119.1, "Freshwater", .make_taxaexpect_priors_for_site()),
    "not found at"
  )
})

test_that(".latlon_to_grid gives a clear error when the nearest grid has no non-NA main_habitat rows at all", {
  priors <- data.frame(
    taxon_name   = "Gadus morhua",
    grid_id      = "Grid_34p1_m119p1",
    main_habitat = NA_character_,
    stringsAsFactors = FALSE
  )
  expect_error(
    .latlon_to_grid(34.1, -119.1, "Estuarine Bay", priors),
    "No prior rows"
  )
})

test_that(".latlon_to_grid warns when the nearest grid is far from the provided coordinates", {
  expect_warning(
    .latlon_to_grid(0, 0, "Estuarine Bay", .make_taxaexpect_priors_for_site()),
    "degrees from provided coordinates"
  )
})
