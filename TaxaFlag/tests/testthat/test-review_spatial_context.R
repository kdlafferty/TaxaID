# test-review_spatial_context.R
#
# The gadget's reactive logic is tested via shiny::testServer() against
# .build_spatial_context_server() directly, not via a browser -- a page with
# a persistent Shiny websocket connection never reaches the "network idle"
# state standard browser-automation tooling waits for (confirmed directly
# during development: a real running instance responded correctly and fast
# to a plain HTTP request, but every browser-automation tool call against it
# hung at a 45s idle-wait timeout). testServer() is Shiny's own supported
# mechanism for exercising server-side reactive logic without a browser, and
# is what actually caught real issues here -- see the per-test comments.
#
# Network-calling functions (.resolve_gbif_taxon_key(), check_gbif_tile_range(),
# compute_local_occurrence_distance(), review_assignments()) are all mocked
# at the TaxaFlag namespace boundary via testthat::local_mocked_bindings(),
# matching this file's own established mocking convention elsewhere
# (test-check_gbif_tile_range.R). The gadget's UI construction
# (review_spatial_context()'s package/interactive()/input-code-path checks,
# and .review_spatial_context_impl()'s dropdown/conditional-button
# rendering) is exercised only implicitly via a raw-HTML fetch during
# development, not by an automated test -- matching this ecosystem's
# established precedent that fully interactive gadgets (review_spatial_flags(),
# review_institution_flags(), plot_theta_map_interactive()) rely on live
# manual/Chrome verification rather than a testthat suite for their UI shell.

library(testthat)

skip_if_not_installed("shiny")

.make_server <- function(input_df = data.frame(
                            primary_taxon = c("Lepomis peltastes", "Gasterosteus gymnurus", "Barbatula barbatula"),
                            primary_plausibility = c("unprecedented", "unprecedented", "unprecedented"),
                            stringsAsFactors = FALSE
                          ),
                          occurrence_data = NULL,
                          excluded_occurrence_data = NULL,
                          inat_range = NULL,
                          live_inat_check = FALSE,
                          inat_cache_dir = NULL,
                          inat_radius_km = 500,
                          gbif_bin_size = 64L,
                          context = NULL) {
  TaxaFlag:::.build_spatial_context_server(
    input_df = input_df, query_lat = 41.67, query_lon = -87.15,
    taxon_col = "primary_taxon", plausibility_col = "primary_plausibility",
    all_taxa = sort(unique(input_df$primary_taxon)),
    plaus_choices = c("All", sort(unique(input_df$primary_plausibility))),
    occurrence_data = occurrence_data, excluded_occurrence_data = excluded_occurrence_data,
    occurrence_taxon_col = "taxon_name",
    occurrence_lat_col = "decimalLatitude", occurrence_lon_col = "decimalLongitude",
    inat_range = inat_range, inat_taxon_col = "taxon_name",
    live_inat_check = live_inat_check, inat_cache_dir = inat_cache_dir,
    inat_radius_km = inat_radius_km,
    context = context, target_group = "fish", marker = "12S eDNA",
    llm_fn = if (is.null(context)) NULL else function(prompt, ...) "[]",
    tile = "CartoDB.Positron", gbif_style = "classic.point",
    gbif_bin_size = gbif_bin_size, gbif_year_range = NULL
  )
}

test_that("selecting a taxon shows GBIF distance/patch in stats_panel", {
  testthat::local_mocked_bindings(
    .resolve_gbif_taxon_key = function(name) 1L, .package = "TaxaFlag"
  )
  testthat::local_mocked_bindings(
    check_gbif_tile_range = function(...) data.frame(
      dist_nearest_occupied_km = 41.4, patch_diameter_km = 0.9,
      beyond_buffer = FALSE, escalated = FALSE, zoom_used = 6L
    ),
    .package = "TaxaFlag"
  )
  shiny::testServer(.make_server(), {
    session$setInputs(taxon = "Lepomis peltastes")
    expect_match(output$stats_panel$html, "GBIF: nearest occurrence ~41 km away, patch ~0.9 km across")
  })
})

test_that("beyond_buffer = TRUE shows the 'no occurrence found' message, not a distance", {
  testthat::local_mocked_bindings(
    .resolve_gbif_taxon_key = function(name) 1L, .package = "TaxaFlag"
  )
  testthat::local_mocked_bindings(
    check_gbif_tile_range = function(...) data.frame(
      dist_nearest_occupied_km = NA_real_, patch_diameter_km = NA_real_,
      beyond_buffer = TRUE, escalated = TRUE, zoom_used = NA_integer_
    ),
    .package = "TaxaFlag"
  )
  shiny::testServer(.make_server(), {
    session$setInputs(taxon = "Barbatula barbatula")
    expect_match(output$stats_panel$html, "GBIF: no occurrence found anywhere globally")
    expect_false(grepl("nearest occurrence", output$stats_panel$html))
  })
})

test_that("an unresolvable taxon name shows the 'could not resolve' message", {
  testthat::local_mocked_bindings(
    .resolve_gbif_taxon_key = function(name) NA_integer_, .package = "TaxaFlag"
  )
  shiny::testServer(.make_server(), {
    session$setInputs(taxon = "Lepomis peltastes")
    expect_match(output$stats_panel$html, "could not resolve a usageKey")
  })
})

test_that("an iNat name mismatch is flagged in stats_panel; an exact match is not", {
  testthat::local_mocked_bindings(
    .resolve_gbif_taxon_key = function(name) 1L, .package = "TaxaFlag"
  )
  testthat::local_mocked_bindings(
    check_gbif_tile_range = function(...) data.frame(
      dist_nearest_occupied_km = 6517.0, patch_diameter_km = 7.3,
      beyond_buffer = FALSE, escalated = TRUE, zoom_used = 3L
    ),
    .package = "TaxaFlag"
  )
  inat <- data.frame(
    taxon_name = c("Lepomis peltastes", "Gasterosteus gymnurus"),
    in_range = TRUE, n_observations = c(1275, 10135),
    matched_name = c("Lepomis peltastes", "Gasterosteus aculeatus"),
    stringsAsFactors = FALSE
  )

  shiny::testServer(.make_server(inat_range = inat), {
    session$setInputs(taxon = "Gasterosteus gymnurus")
    expect_match(output$stats_panel$html, "matched to 'Gasterosteus aculeatus' \\(differs from query!\\)")

    session$setInputs(taxon = "Lepomis peltastes")
    expect_false(grepl("differs from query", output$stats_panel$html))
    expect_match(output$stats_panel$html, "in range")
  })
})

test_that("occurrence_data supplied shows the free/local line with correct count and distance", {
  testthat::local_mocked_bindings(
    .resolve_gbif_taxon_key = function(name) 1L, .package = "TaxaFlag"
  )
  testthat::local_mocked_bindings(
    check_gbif_tile_range = function(...) data.frame(
      dist_nearest_occupied_km = 0.9, patch_diameter_km = 6.6,
      beyond_buffer = FALSE, escalated = FALSE, zoom_used = 6L
    ),
    .package = "TaxaFlag"
  )
  occ <- data.frame(
    taxon_name = c("Neogobius melanostomus", "Neogobius melanostomus"),
    decimalLatitude  = c(41.68, 41.60), decimalLongitude = c(-87.14, -87.30),
    stringsAsFactors = FALSE
  )
  input_df <- data.frame(primary_taxon = "Neogobius melanostomus",
                   primary_plausibility = "expected", stringsAsFactors = FALSE)

  shiny::testServer(.make_server(input_df = input_df, occurrence_data = occ), {
    session$setInputs(taxon = "Neogobius melanostomus")
    expect_match(output$stats_panel$html, "Local \\(free\\): 2 record\\(s\\), nearest 1\\.[0-9]+ km away")
  })
})

test_that("occurrence_data omitted: no 'Local (free)' line at all", {
  testthat::local_mocked_bindings(
    .resolve_gbif_taxon_key = function(name) 1L, .package = "TaxaFlag"
  )
  testthat::local_mocked_bindings(
    check_gbif_tile_range = function(...) data.frame(
      dist_nearest_occupied_km = 41.4, patch_diameter_km = 0.9,
      beyond_buffer = FALSE, escalated = FALSE, zoom_used = 6L
    ),
    .package = "TaxaFlag"
  )
  shiny::testServer(.make_server(), {
    session$setInputs(taxon = "Lepomis peltastes")
    expect_false(grepl("Local \\(free\\)", output$stats_panel$html))
  })
})

test_that("inat_range supplied but taxon has no matching row: explicit 'no data' message, not silence", {
  testthat::local_mocked_bindings(
    .resolve_gbif_taxon_key = function(name) 1L, .package = "TaxaFlag"
  )
  testthat::local_mocked_bindings(
    check_gbif_tile_range = function(...) data.frame(
      dist_nearest_occupied_km = 41.4, patch_diameter_km = 0.9,
      beyond_buffer = FALSE, escalated = FALSE, zoom_used = 6L
    ),
    .package = "TaxaFlag"
  )
  inat_missing_this_taxon <- data.frame(
    taxon_name = "Some Other Species", in_range = TRUE, n_observations = 100,
    matched_name = "Some Other Species", stringsAsFactors = FALSE
  )
  shiny::testServer(.make_server(inat_range = inat_missing_this_taxon), {
    session$setInputs(taxon = "Lepomis peltastes")
    expect_match(output$stats_panel$html, "iNat: no data")
  })
})

test_that("live_inat_check fires when the taxon is absent from the static inat_range", {
  testthat::local_mocked_bindings(
    .resolve_gbif_taxon_key = function(name) 1L, .package = "TaxaFlag"
  )
  testthat::local_mocked_bindings(
    check_gbif_tile_range = function(...) data.frame(
      dist_nearest_occupied_km = 41.4, patch_diameter_km = 0.9,
      beyond_buffer = FALSE, escalated = FALSE, zoom_used = 6L
    ),
    .package = "TaxaFlag"
  )
  inat_missing_this_taxon <- data.frame(
    taxon_name = "Some Other Species", in_range = TRUE, n_observations = 100,
    matched_name = "Some Other Species", stringsAsFactors = FALSE
  )
  skip_if_not_installed("TaxaFetch")
  testthat::local_mocked_bindings(
    check_inat_range = function(taxon_names, lat, lng, ...) data.frame(
      taxon_name = taxon_names, taxon_id = 99L, matched_name = taxon_names,
      in_range = TRUE, n_observations = 250, range_status = "ok",
      stringsAsFactors = FALSE
    ),
    .package = "TaxaFetch"
  )
  shiny::testServer(
    .make_server(inat_range = inat_missing_this_taxon, live_inat_check = TRUE),
    {
      session$setInputs(taxon = "Lepomis peltastes")
      expect_match(output$stats_panel$html, "250 obs")
      expect_false(grepl("no data", output$stats_panel$html))
    }
  )
})

test_that("live_inat_check = FALSE never calls the live fallback, even when inat_range is missing the taxon", {
  testthat::local_mocked_bindings(
    .resolve_gbif_taxon_key = function(name) 1L, .package = "TaxaFlag"
  )
  testthat::local_mocked_bindings(
    check_gbif_tile_range = function(...) data.frame(
      dist_nearest_occupied_km = 41.4, patch_diameter_km = 0.9,
      beyond_buffer = FALSE, escalated = FALSE, zoom_used = 6L
    ),
    .package = "TaxaFlag"
  )
  inat_missing_this_taxon <- data.frame(
    taxon_name = "Some Other Species", in_range = TRUE, n_observations = 100,
    matched_name = "Some Other Species", stringsAsFactors = FALSE
  )
  skip_if_not_installed("TaxaFetch")
  called <- FALSE
  testthat::local_mocked_bindings(
    check_inat_range = function(...) {
      called <<- TRUE
      stop("should not be called when live_inat_check = FALSE")
    },
    .package = "TaxaFetch"
  )
  shiny::testServer(
    .make_server(inat_range = inat_missing_this_taxon, live_inat_check = FALSE),
    {
      session$setInputs(taxon = "Lepomis peltastes")
      expect_match(output$stats_panel$html, "iNat: no data")
    }
  )
  expect_false(called)
})

test_that("inat_range = NULL (not supplied at all): no iNat line, not even a 'no data' message", {
  testthat::local_mocked_bindings(
    .resolve_gbif_taxon_key = function(name) 1L, .package = "TaxaFlag"
  )
  testthat::local_mocked_bindings(
    check_gbif_tile_range = function(...) data.frame(
      dist_nearest_occupied_km = 41.4, patch_diameter_km = 0.9,
      beyond_buffer = FALSE, escalated = FALSE, zoom_used = 6L
    ),
    .package = "TaxaFlag"
  )
  shiny::testServer(.make_server(inat_range = NULL), {
    session$setInputs(taxon = "Lepomis peltastes")
    expect_false(grepl("iNat", output$stats_panel$html))
  })
})

test_that("excluded_occurrence_data supplied: map updates without error", {
  testthat::local_mocked_bindings(
    .resolve_gbif_taxon_key = function(name) 1L, .package = "TaxaFlag"
  )
  testthat::local_mocked_bindings(
    check_gbif_tile_range = function(...) data.frame(
      dist_nearest_occupied_km = 41.4, patch_diameter_km = 0.9,
      beyond_buffer = FALSE, escalated = FALSE, zoom_used = 6L
    ),
    .package = "TaxaFlag"
  )
  excluded <- data.frame(
    taxon_name = "Lepomis peltastes",
    decimalLatitude = 41.90, decimalLongitude = -86.80,
    stringsAsFactors = FALSE
  )
  shiny::testServer(.make_server(excluded_occurrence_data = excluded), {
    session$setInputs(taxon = "Lepomis peltastes")
    expect_true(!is.null(output$map))
    expect_true(!is.null(output$stats_panel))
  })
})

test_that("inat_range with a real taxon_id column adds the iNat tile layer without error", {
  testthat::local_mocked_bindings(
    .resolve_gbif_taxon_key = function(name) 1L, .package = "TaxaFlag"
  )
  testthat::local_mocked_bindings(
    check_gbif_tile_range = function(...) data.frame(
      dist_nearest_occupied_km = 41.4, patch_diameter_km = 0.9,
      beyond_buffer = FALSE, escalated = FALSE, zoom_used = 6L
    ),
    .package = "TaxaFlag"
  )
  # Real check_inat_range() output shape includes taxon_id -- the earlier
  # synthetic fixtures elsewhere in this file deliberately omit it (to
  # confirm the stats_panel/mismatch logic doesn't depend on it), so this
  # test specifically exercises the map tile layer's taxon_id-gated branch.
  inat_real_shape <- data.frame(
    taxon_name = "Lepomis peltastes", taxon_id = 358056L, matched_name = "Lepomis peltastes",
    rank = "species", iconic_taxon_name = "Actinopterygii", inat_kingdom = "Animalia",
    n_observations = 1275, in_range = TRUE, range_status = "in_range",
    stringsAsFactors = FALSE
  )
  shiny::testServer(.make_server(inat_range = inat_real_shape), {
    session$setInputs(taxon = "Lepomis peltastes")
    expect_true(!is.null(output$map))
    expect_match(output$stats_panel$html, "in range")
  })
})

test_that("map output renders without error", {
  testthat::local_mocked_bindings(
    .resolve_gbif_taxon_key = function(name) 1L, .package = "TaxaFlag"
  )
  testthat::local_mocked_bindings(
    check_gbif_tile_range = function(...) data.frame(
      dist_nearest_occupied_km = 41.4, patch_diameter_km = 0.9,
      beyond_buffer = FALSE, escalated = FALSE, zoom_used = 6L
    ),
    .package = "TaxaFlag"
  )
  shiny::testServer(.make_server(), {
    session$setInputs(taxon = "Lepomis peltastes")
    expect_true(!is.null(output$map))
  })
})

test_that("Run AI Review calls review_assignments() and populates ai_panel", {
  testthat::local_mocked_bindings(
    .resolve_gbif_taxon_key = function(name) 1L, .package = "TaxaFlag"
  )
  testthat::local_mocked_bindings(
    check_gbif_tile_range = function(...) data.frame(
      dist_nearest_occupied_km = 41.4, patch_diameter_km = 0.9,
      beyond_buffer = FALSE, escalated = FALSE, zoom_used = 6L
    ),
    .package = "TaxaFlag"
  )
  ctx <- list(geography = "Lake Michigan", habitat = "harbor")
  stub_llm <- function(prompt, ...) {
    # taxon_name must match the row's VALUE ("Lepomis peltastes"), not the
    # ".taxon" column name the gadget's run_ai handler builds internally --
    # review_assignments() joins its LLM response back onto the input by
    # that value, so a wrong echo here silently falls through to its own
    # "taxon omitted" NA-fill path instead of matching.
    jsonlite::toJSON(list(list(
      taxon_name = "Lepomis peltastes", habitat_plausibility = "likely",
      geographic_plausibility = "likely", scope_plausibility = "likely",
      contamination_risk = "low", review_alternatives = NULL,
      review_lower_hypotheses = NULL, review_confidence = "high",
      review_comment = "Looks fine"
    )), auto_unbox = TRUE, null = "null")
  }
  srv <- TaxaFlag:::.build_spatial_context_server(
    input_df = data.frame(primary_taxon = "Lepomis peltastes", primary_plausibility = "unprecedented"),
    query_lat = 41.67, query_lon = -87.15, taxon_col = "primary_taxon",
    plausibility_col = "primary_plausibility", all_taxa = "Lepomis peltastes",
    plaus_choices = c("All", "unprecedented"), occurrence_data = NULL,
    excluded_occurrence_data = NULL,
    occurrence_taxon_col = "taxon_name", occurrence_lat_col = "decimalLatitude",
    occurrence_lon_col = "decimalLongitude", inat_range = NULL, inat_taxon_col = "taxon_name",
    live_inat_check = FALSE, inat_cache_dir = NULL, inat_radius_km = 500,
    context = ctx, target_group = "fish", marker = "12S eDNA", llm_fn = stub_llm,
    tile = "CartoDB.Positron", gbif_style = "classic.point",
    gbif_bin_size = 64L, gbif_year_range = NULL
  )

  shiny::testServer(srv, {
    session$setInputs(taxon = "Lepomis peltastes")
    session$setInputs(run_ai = 1)
    expect_match(output$ai_panel$html, "Geographic: likely \\| Contamination: low")
    expect_match(output$ai_panel$html, "Looks fine")
  })
})

test_that("Run AI Review degrades gracefully (NA fields, no crash) when llm_fn itself fails", {
  # review_assignments() already catches a hard llm_fn error internally and
  # returns NA-filled defaults with a warning() rather than throwing (see
  # .review_batch_with_retry()'s own "hard llm_fn errors are not retried"
  # design) -- so the gadget's own tryCatch() around review_assignments()
  # is a backstop for a DIFFERENT failure class, not this one. This test
  # asserts the real, graceful-degradation behavior instead of a thrown
  # error that never actually happens here.
  testthat::local_mocked_bindings(
    .resolve_gbif_taxon_key = function(name) 1L, .package = "TaxaFlag"
  )
  testthat::local_mocked_bindings(
    check_gbif_tile_range = function(...) data.frame(
      dist_nearest_occupied_km = 41.4, patch_diameter_km = 0.9,
      beyond_buffer = FALSE, escalated = FALSE, zoom_used = 6L
    ),
    .package = "TaxaFlag"
  )
  ctx <- list(geography = "Lake Michigan", habitat = "harbor")
  failing_llm <- function(prompt, ...) stop("network unreachable")
  srv <- TaxaFlag:::.build_spatial_context_server(
    input_df = data.frame(primary_taxon = "Lepomis peltastes", primary_plausibility = "unprecedented"),
    query_lat = 41.67, query_lon = -87.15, taxon_col = "primary_taxon",
    plausibility_col = "primary_plausibility", all_taxa = "Lepomis peltastes",
    plaus_choices = c("All", "unprecedented"), occurrence_data = NULL,
    excluded_occurrence_data = NULL,
    occurrence_taxon_col = "taxon_name", occurrence_lat_col = "decimalLatitude",
    occurrence_lon_col = "decimalLongitude", inat_range = NULL, inat_taxon_col = "taxon_name",
    live_inat_check = FALSE, inat_cache_dir = NULL, inat_radius_km = 500,
    context = ctx, target_group = "fish", marker = "12S eDNA", llm_fn = failing_llm,
    tile = "CartoDB.Positron", gbif_style = "classic.point",
    gbif_bin_size = 64L, gbif_year_range = NULL
  )

  shiny::testServer(srv, {
    session$setInputs(taxon = "Lepomis peltastes")
    suppressWarnings(session$setInputs(run_ai = 1))
    expect_match(output$ai_panel$html, "Geographic: NA \\| Contamination: NA")
    expect_false(grepl("Error:", output$ai_panel$html))
  })
})

test_that(".resolve_gbif_taxon_key parses a real-shaped GBIF match response", {
  skip_if_not_installed("httr2")
  fake_resp <- httr2::response(
    status_code = 200,
    headers = list(`content-type` = "application/json"),
    body = charToRaw('{"usageKey": 2379089, "scientificName": "Neogobius melanostomus"}')
  )
  testthat::local_mocked_bindings(
    req_perform = function(req) fake_resp, .package = "httr2"
  )
  expect_equal(TaxaFlag:::.resolve_gbif_taxon_key("Neogobius melanostomus"), 2379089L)
})

test_that(".resolve_gbif_taxon_key returns NA when GBIF has no usageKey match", {
  skip_if_not_installed("httr2")
  fake_resp <- httr2::response(
    status_code = 200,
    headers = list(`content-type` = "application/json"),
    body = charToRaw('{"matchType": "NONE"}')
  )
  testthat::local_mocked_bindings(
    req_perform = function(req) fake_resp, .package = "httr2"
  )
  expect_true(is.na(TaxaFlag:::.resolve_gbif_taxon_key("Not A Real Species")))
})

# .gbif_tile_url() -----------------------------------------------------------
# Pure URL-construction logic extracted from the observeEvent(input$taxon)
# call site specifically so the .point->.poly auto-upgrade + bin params +
# Heat-family exclusion can be tested directly, not just exercised
# implicitly through the full gadget.

test_that(".gbif_tile_url() upgrades a bare .point style to .poly and adds bin params when bin_size is supplied", {
  url <- TaxaFlag:::.gbif_tile_url(
    taxon_key = 123L, style = "classic.point", bin_size = 256L, year_range = NULL
  )
  expect_match(url, "style=classic\\.poly", fixed = FALSE)
  expect_match(url, "bin=square&squareSize=256", fixed = TRUE)
  expect_match(url, "taxonKey=123", fixed = TRUE)
})

test_that(".gbif_tile_url() leaves an already-.poly style as-is, still adds bin params", {
  url <- TaxaFlag:::.gbif_tile_url(
    taxon_key = 123L, style = "green.poly", bin_size = 64L, year_range = NULL
  )
  expect_match(url, "style=green\\.poly", fixed = FALSE)
  expect_match(url, "bin=square&squareSize=64", fixed = TRUE)
})

test_that(".gbif_tile_url() leaves Heat-family styles unbinned even when bin_size is supplied", {
  url <- TaxaFlag:::.gbif_tile_url(
    taxon_key = 123L, style = "purpleHeat.point", bin_size = 256L, year_range = NULL
  )
  expect_match(url, "style=purpleHeat\\.point", fixed = FALSE)
  expect_false(grepl("bin=square", url, fixed = TRUE))
})

test_that(".gbif_tile_url() applies no bin params at all when bin_size is NULL", {
  url <- TaxaFlag:::.gbif_tile_url(
    taxon_key = 123L, style = "classic.point", bin_size = NULL, year_range = NULL
  )
  expect_match(url, "style=classic\\.point", fixed = FALSE)
  expect_false(grepl("bin=square", url, fixed = TRUE))
})

test_that(".gbif_tile_url() appends a year query when year_range is supplied", {
  url <- TaxaFlag:::.gbif_tile_url(
    taxon_key = 123L, style = "classic.point", bin_size = NULL, year_range = "1995,2025"
  )
  expect_match(url, "year=1995,2025", fixed = TRUE)
})

# .gbif_legend_swatch() -------------------------------------------------------
# Real, sampled colors (see the function's own roxygen for the live-tile
# verification record) -- these tests guard against the exact bug an
# earlier round shipped: a legend swatch that never actually reflected the
# caller's real gbif_style.

test_that(".gbif_legend_swatch() returns the real classic ramp for classic.point/.poly alike", {
  s1 <- TaxaFlag:::.gbif_legend_swatch("classic.point")
  s2 <- TaxaFlag:::.gbif_legend_swatch("classic.poly")
  expect_equal(s1, s2)
  expect_match(s1$gradient, "#ffff00", fixed = TRUE)
  expect_equal(s1$label, "GBIF density")
})

test_that(".gbif_legend_swatch() returns the real purpleHeat colors, not classic's", {
  s <- TaxaFlag:::.gbif_legend_swatch("purpleHeat.point")
  expect_match(s$gradient, "#851284", fixed = TRUE)
  expect_false(grepl("#ffff00", s$gradient, fixed = TRUE))
})

test_that(".gbif_legend_swatch() falls back to a labeled gray gradient for an unverified style", {
  s <- TaxaFlag:::.gbif_legend_swatch("outline.poly")
  expect_match(s$gradient, "#bbbbbb", fixed = TRUE)
  expect_match(s$label, "unverified")
})

# .fetch_inat_points() --------------------------------------------------------
# Network boundary mocked at httr2::req_perform, matching this file's own
# established mocking convention for .resolve_gbif_taxon_key().

test_that(".fetch_inat_points() extracts real-shaped geojson coordinates into lon/lat columns", {
  skip_if_not_installed("httr2")
  fake_body <- jsonlite::toJSON(list(
    results = list(
      list(id = 1, geojson = list(type = "Point", coordinates = list(-87.15, 41.67))),
      list(id = 2, geojson = list(type = "Point", coordinates = list(-88.0, 42.0)))
    )
  ), auto_unbox = TRUE)
  fake_resp <- httr2::response(
    status_code = 200,
    headers = list(`content-type` = "application/json"),
    body = charToRaw(as.character(fake_body))
  )
  testthat::local_mocked_bindings(
    req_perform = function(req) fake_resp, .package = "httr2"
  )
  pts <- TaxaFlag:::.fetch_inat_points(taxon_id = 999L, lat = 41.67, lng = -87.15)
  expect_equal(nrow(pts), 2L)
  expect_equal(pts$lon, c(-87.15, -88.0))
  expect_equal(pts$lat, c(41.67, 42.0))
})

test_that(".fetch_inat_points() returns a 0-row lon/lat frame when there are no results", {
  skip_if_not_installed("httr2")
  fake_resp <- httr2::response(
    status_code = 200,
    headers = list(`content-type` = "application/json"),
    body = charToRaw('{"results": []}')
  )
  testthat::local_mocked_bindings(
    req_perform = function(req) fake_resp, .package = "httr2"
  )
  pts <- TaxaFlag:::.fetch_inat_points(taxon_id = 999L, lat = 41.67, lng = -87.15)
  expect_equal(nrow(pts), 0L)
  expect_equal(names(pts), c("lon", "lat"))
})

test_that("an inat_range without a matched_name column still renders the panel", {
  # matched_name was the one iNat field read without a NULL guard (unlike
  # in_range/n_observations/taxon_id), so a caller-supplied inat_range
  # predating check_inat_range()'s matched_name column made `mismatch` NA and
  # errored the WHOLE stats panel, not just the iNat line.
  testthat::local_mocked_bindings(
    .resolve_gbif_taxon_key = function(name) 1L, .package = "TaxaFlag"
  )
  testthat::local_mocked_bindings(
    check_gbif_tile_range = function(...) data.frame(
      dist_nearest_occupied_km = 41.0, patch_diameter_km = 2.1,
      beyond_buffer = FALSE, escalated = FALSE, zoom_used = 6L
    ),
    .package = "TaxaFlag"
  )
  inat_no_matched_name <- data.frame(
    taxon_name = "Lepomis peltastes", in_range = TRUE, n_observations = 1275,
    stringsAsFactors = FALSE
  )
  shiny::testServer(.make_server(inat_range = inat_no_matched_name), {
    session$setInputs(taxon = "Lepomis peltastes")
    expect_match(output$stats_panel$html, "in range")
    expect_false(grepl("differs from query", output$stats_panel$html))
  })
})
