# Resolving an unassigned habitat from where the point actually is.
#
# A taxon whose weights span freshwater, estuarine and marine is not uncertain
# about its habitat -- it uses all three -- so over open ocean it is marine.
# The consensus threshold cannot express that because it never sees location.

test_that(".habitat_admissible decides at HABITAT level, not realm level", {
  # The case that motivates the whole function. A gull's candidates are
  # Estuarine | Freshwater | Marine; over open ocean BOTH Estuarine and Marine
  # are "marine realm", so a realm rule finds two matches and gives up -- when
  # the answer is plainly Marine. Estuarine is a transitional coastal habitat.
  cd <- c("Estuarine", "Freshwater", "Marine")
  expect_equal(cd[.habitat_admissible(cd, "ocean")], "Marine")
  # Inland excludes Estuarine as well as Marine: an estuary is a coastal
  # feature, so it is no more admissible 50 km inland than open ocean is.
  # That makes an inland Estuarine|Freshwater|Marine point resolve to
  # Freshwater, which is the desired behaviour and not an accident of the
  # pattern matching.
  expect_equal(cd[.habitat_admissible(cd, "inland")], "Freshwater")
  expect_setequal(cd[.habitat_admissible(cd, "coastal")], cd)
})

test_that(".habitat_admissible excludes marine habitats inland", {
  cd <- c("Marine", "Freshwater", "Terrestrial")
  expect_setequal(cd[.habitat_admissible(cd, "inland")], c("Freshwater", "Terrestrial"))
  expect_equal(cd[.habitat_admissible(cd, "ocean")], "Marine")
})

test_that(".habitat_admissible generalises past one scheme's vocabulary", {
  # Derived from the package's realm patterns, not a hard-coded habitat list.
  expect_true(.habitat_admissible("Rocky Subtidal", "ocean"))
  expect_true(.habitat_admissible("Coastal Pelagic", "ocean"))
  expect_false(.habitat_admissible("Estuarine Mudflat", "ocean"))   # estuarine
  expect_false(.habitat_admissible("Lentic", "ocean"))
  expect_true(.habitat_admissible("Lentic", "inland"))
})

test_that(".habitat_admissible returns FALSE for an unknown zone", {
  expect_false(.habitat_admissible("Marine", "somewhere_else"))
})

test_that("resolve_habitat_by_geography returns input unchanged with no attribute", {
  occ <- data.frame(
    point_id = "p1", decimalLatitude = 34, decimalLongitude = -120,
    main_habitat = NA_character_, stringsAsFactors = FALSE
  )
  r <- suppressMessages(resolve_habitat_by_geography(occ))
  expect_true(is.na(r$main_habitat[1]))
  expect_equal(nrow(r), 1L)
})

test_that("resolve_habitat_by_geography does nothing when nothing is unassigned", {
  occ <- data.frame(
    point_id = "p1", decimalLatitude = 34, decimalLongitude = -120,
    main_habitat = "Marine", stringsAsFactors = FALSE
  )
  attr(occ, "habitat_proportions") <- data.frame(
    point_id = "p1", Marine = 1, Estuarine = 0, stringsAsFactors = FALSE
  )
  r <- suppressMessages(resolve_habitat_by_geography(occ))
  expect_equal(r$main_habitat, "Marine")
  expect_equal(r$habitat_source, "consensus")
})

test_that("resolve_habitat_by_geography validates its inputs", {
  expect_error(resolve_habitat_by_geography("nope"), "dataframe")
  expect_error(
    resolve_habitat_by_geography(data.frame(x = 1)),
    "not found"
  )
})

test_that("a resolved point is marked as geography, not consensus", {
  skip_if_not_installed("rnaturalearth")
  skip_if_not_installed("rnaturalearthhires")
  skip_if_not_installed("curl")
  # resolve_habitat_by_geography() needs a real NOAA bathymetry fetch
  # (marmap::getNOAA.bathy(), which hits gis.ngdc.noaa.gov) to classify the
  # offshore point's zone. Checked BEFORE the real assertions run, with an
  # explicit skip() reason, rather than wrapping the assertions themselves
  # in `if (!is.na(...))` -- that pattern let this test report PASS having
  # executed zero assertions on its own claim whenever resolution failed for
  # ANY reason (service down, vendored data missing, a future regression),
  # with no visible signal that nothing was actually checked (D5).
  noaa_reachable <- tryCatch({
    h <- curl::new_handle(timeout_ms = 5000L, connecttimeout_ms = 5000L, nobody = TRUE)
    resp <- curl::curl_fetch_memory("https://gis.ngdc.noaa.gov", handle = h)
    resp$status_code < 500
  }, error = function(e) FALSE)
  if (!noaa_reachable) {
    skip("NOAA bathymetry service (gis.ngdc.noaa.gov) is not reachable from this machine -- resolve_habitat_by_geography() cannot classify elevation without it.")
  }

  # Two points: one far offshore (ocean), one already settled by consensus.
  occ <- data.frame(
    point_id = c("sea", "known"),
    decimalLatitude = c(34.0, 34.4),
    decimalLongitude = c(-121.5, -120.0),
    taxon_name = c("gull", "fish"),
    main_habitat = c(NA_character_, "Marine"),
    stringsAsFactors = FALSE
  )
  attr(occ, "habitat_proportions") <- data.frame(
    point_id = c("sea", "known"),
    Marine     = c(0.35, 1),
    Estuarine  = c(0.33, 0),
    Freshwater = c(0.32, 0),
    stringsAsFactors = FALSE
  )
  r <- suppressMessages(resolve_habitat_by_geography(occ))
  expect_equal(r$habitat_source[r$point_id == "known"], "consensus")
  # The offshore point resolves to Marine and is labelled geography. NOAA
  # reachability was already confirmed above, so a resolution failure here
  # is a real regression, not a flaky network -- these assertions always run.
  expect_false(is.na(r$main_habitat[r$point_id == "sea"]))
  expect_equal(r$main_habitat[r$point_id == "sea"], "Marine")
  expect_equal(r$habitat_source[r$point_id == "sea"], "geography")
  # the proportions are NOT rewritten -- the taxon really does use all three
  expect_equal(attr(r, "habitat_proportions")$Estuarine[1], 0.33)
})
