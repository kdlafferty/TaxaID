# flag_habitat_inconsistencies() itself has no offline code path -- every
# real call downloads live Natural Earth polygons and NOAA GEBCO bathymetry
# (confirmed: rnaturalearth::ne_countries()/ne_coastline() and
# marmap::getNOAA.bathy() are both called unconditionally on any valid
# input). That matches this ecosystem's own established precedent for
# genuinely network-bound functions (e.g. TaxaTools::verify_taxon_names()/
# census_genus_species(), "online tests skipped offline"). What IS tested
# here, offline, is the input validation that runs BEFORE any network call
# -- real, reachable failure modes a user can hit with no network at all.

test_that("stops when a required column is missing", {
  occurrence_data <- data.frame(
    decimalLatitude  = 40.8,
    decimalLongitude = -124.2,
    stringsAsFactors = FALSE
  )
  expect_error(
    flag_habitat_inconsistencies(occurrence_data),
    "main_habitat"
  )
})

test_that("stops when lat_col is missing", {
  occurrence_data <- data.frame(
    decimalLongitude = -124.2,
    main_habitat     = "Marine",
    stringsAsFactors = FALSE
  )
  expect_error(
    flag_habitat_inconsistencies(occurrence_data),
    "decimalLatitude"
  )
})

test_that("stops when lon_col is missing", {
  occurrence_data <- data.frame(
    decimalLatitude = 40.8,
    main_habitat = "Marine",
    stringsAsFactors = FALSE
  )
  expect_error(
    flag_habitat_inconsistencies(occurrence_data),
    "decimalLongitude"
  )
})

test_that("column-existence check reads lat_col/lon_col/habitat_col, not hardcoded defaults", {
  # occurrence_data has a custom-named "hab" column but no "main_habitat" --
  # the error must name "hab" (the value actually supplied via habitat_col),
  # confirming the check is parameterised rather than hardcoded to the
  # default column names.
  occurrence_data <- data.frame(
    lat = 40.8, lon = -124.2,
    stringsAsFactors = FALSE
  )
  expect_error(
    flag_habitat_inconsistencies(
      occurrence_data,
      lat_col = "lat", lon_col = "lon", habitat_col = "hab"
    ),
    "Column 'hab' not found",
    fixed = TRUE
  )
})

# --- 2026-09-15: coastline islands + local projection ------------------------

test_that(".utm_crs_for() picks the right zone and hemisphere", {
  skip_if_not_installed("sf")
  mk <- function(lon, lat) sf::st_sfc(sf::st_point(c(lon, lat)), crs = 4326L)
  expect_equal(.utm_crs_for(mk(-120,   34.4)), 32611L)  # Pt Conception
  expect_equal(.utm_crs_for(mk( -87,   41.6)), 32616L)  # Great Lakes
  expect_equal(.utm_crs_for(mk( -70,  -33.0)), 32719L)  # southern hemisphere
  expect_equal(.utm_crs_for(mk(  10,   86.0)),  5041L)  # UPS North
  expect_warning(.utm_crs_for(sf::st_sfc(
    sf::st_multipoint(rbind(c(-150, 10), c(150, 10))), crs = 4326L)),
    "span")
})

test_that("distance is measured geodesically, not in Web Mercator", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  skip_if_not_installed("rnaturalearthhires")
  # s2 is left ALONE here (it used to be switched off, and never restored).
  # Two reasons. (1) With s2 off, sf::st_distance() on a geographic CRS
  # delegates to lwgeom, which is not a declared dependency and is absent from
  # R CMD check's clean library -- this is what turned CI red on 2026-09-18.
  # (2) sf_use_s2() is GLOBAL, so switching it off here leaked into every test
  # that ran afterwards.
  # The assertion is unaffected: this test checks that distance is geodesic
  # rather than Web Mercator by comparing UTM against a geodesic reference, and
  # s2 supplies one natively -- measured max|utm/geo - 1| = 0.0026 against the
  # 0.01 threshold (lwgeom's path gives 0.0010; both pass comfortably).
  # NOTE the source function is NOT affected: flag_habitat_inconsistencies()
  # calls st_distance() on UTM (projected) coordinates, which is planar and
  # never needs lwgeom. This was only ever a test-side dependency.
  bb <- sf::st_bbox(c(xmin = -123.5, ymin = 31, xmax = -116, ymax = 38.5), crs = 4326L)
  coast <- suppressWarnings(sf::st_crop(
    sf::st_make_valid(rnaturalearth::ne_coastline(scale = "large", returnclass = "sf")), bb))
  set.seed(1)
  p <- sf::st_as_sf(data.frame(lon = runif(50, -120.8, -119.2),
                               lat = runif(50,   33.9,   34.6)),
                    coords = c("lon", "lat"), crs = 4326L)
  d_utm <- apply(sf::st_distance(sf::st_transform(p, 32611L),
                                 sf::st_transform(coast, 32611L)), 1L, min)
  d_geo <- apply(sf::st_distance(p, coast), 1L, min)
  # UTM tracks geodesic closely; Mercator would be ~21% high at this latitude
  expect_lt(max(abs(d_utm / d_geo - 1)), 0.01)
})

test_that("the minor-islands coastline contains Anacapa and Santa Barbara Island", {
  skip_if_not_installed("sf")
  skip_if_not_installed("rnaturalearth")
  skip_on_cran()
  # s2 stays ON here on purpose. With s2 switched OFF, sf::st_distance() on a
  # geographic CRS delegates geodesic distance to lwgeom -- which is NOT a
  # declared dependency of this package and is absent on a clean CI runner, so
  # this test failed there while passing locally (R-CMD-check run 35292321705,
  # 2026-09-18: "there is no package called 'lwgeom'"). s2 computes the same
  # distance natively: checked against the s2-off path at 0.137% difference,
  # on an assertion with a 2 km threshold, so nothing about the test weakens.
  mi <- tryCatch(rnaturalearth::ne_download(scale = 10, type = "minor_islands_coastline",
                   category = "physical", returnclass = "sf"), error = function(e) NULL)
  skip_if(is.null(mi), "Natural Earth minor-islands layer unavailable")
  pts <- sf::st_sfc(sf::st_point(c(-119.39, 34.015)),   # Anacapa
                    sf::st_point(c(-119.03, 33.475)),   # Santa Barbara Island
                    crs = 4326L)
  d <- suppressWarnings(as.numeric(sf::st_distance(pts, sf::st_union(sf::st_geometry(mi)))))
  expect_true(all(d / 1000 < 2))   # both within 2 km of a mapped island shore
})

# -----------------------------------------------------------------------------
# Habitat-realm name patterns.
#
# Regression tests for the asymmetry that exempted 529,488 real Mugu rows from
# spatial QC: marine terms were "^"-anchored, freshwater terms were not, so any
# name not STARTING with a marine word fell through to freshwater -- which is
# exempt from verification by design.
# -----------------------------------------------------------------------------

.realm_of <- function(h) {
  h <- tolower(trimws(h))
  if (grepl(.marine_name_pattern, h, perl = TRUE)) {
    "marine"
  } else if (grepl(.freshwater_name_pattern, h, perl = TRUE)) {
    "freshwater"
  } else {
    "unknown"
  }
}

test_that("a multi-realm habitat name resolves MARINE, not freshwater", {
  # The exact name that slipped through on real Mugu data.
  expect_equal(.realm_of("Coastal-Marine-Estuary-Stream"), "marine")
  expect_equal(.realm_of("Estuarine Stream"), "marine")
  # A name with no marine term is still freshwater.
  expect_equal(.realm_of("Coastal-Stream"), "freshwater")
  expect_equal(.realm_of("Lake"), "freshwater")
})

test_that("marine terms are found ANYWHERE in the name, not only at the start", {
  # Every one of these was "unknown" under the anchored pattern, and therefore
  # skipped. They are the vocabulary example_habitat_scheme itself teaches.
  for (h in c(
    "Rocky Intertidal", "Rocky Subtidal", "Sandy Subtidal",
    "Shallow Kelp Forest (<10m)", "Coastal Pelagic", "Deep Kelp Forest (>10m)",
    "Estuarine Open Water", "Muddy Subtidal", "Offshore Pelagic"
  )) {
    expect_equal(.realm_of(h), "marine", info = h)
  }
})

test_that("the freshwater pattern no longer matches terrestrial names by accident", {
  # "pond" inside "Ponderosa" and "fen" inside "Fenced" both matched under the
  # old unanchored pattern, classifying dry-land habitats as freshwater.
  expect_equal(.realm_of("Ponderosa Pine Forest"), "unknown")
  expect_equal(.realm_of("Fenced Grassland"), "unknown")
  # Genuine freshwater inflections must still match.
  for (h in c("Wetlands", "Riverine Forest", "Marshes", "Bogs", "Fens", "Ponds")) {
    expect_equal(.realm_of(h), "freshwater", info = h)
  }
})

test_that("the two realm patterns stay symmetric", {
  # The defect was structural: one anchored, one not. Neither may use "^".
  expect_false(grepl("\\^", .marine_name_pattern))
  expect_false(grepl("\\^", .freshwater_name_pattern))
  expect_true(grepl("\\\\b", .marine_name_pattern))
  expect_true(grepl("\\\\b", .freshwater_name_pattern))
})

test_that("previously-correct classifications are unchanged", {
  expect_equal(.realm_of("Marine"), "marine")
  expect_equal(.realm_of("Estuarine"), "marine")
  expect_equal(.realm_of("Pelagic"), "marine")
  expect_equal(.realm_of("Freshwater"), "freshwater")
  # Not in either vocabulary -- must stay unknown so it gets REPORTED rather
  # than silently absorbed into an exempt realm. (Note "Terrestrial" only
  # reaches the name patterns when no scheme is supplied; the DEFAULT scheme's
  # l1_name matches it first and resolves it to the terrestrial realm.)
  expect_equal(.realm_of("Terrestrial"), "unknown")
})

test_that("'Deepwater' is MARINE, not pelagic and not unknown", {
  # Decided 2026-09-19. Deepwater is a realm term, not a depth term, and not a
  # water-column position. At Mugu it carries demersal taxa -- Microstomus
  # pacificus, Xeneretmus ritteri, Bathyagonus pentacanthus, Icelinus spp. --
  # sitting on the bottom between -798 m and the shelf. Mapping it to Pelagic
  # would assert a water-column position those species do not occupy; leaving
  # it unknown left 72 real marine rows unverified. Depth is carried separately
  # by the bathymetry zones (marine_shallow / marine_deep / marine_abyssal).
  expect_equal(.realm_of("Deepwater"), "marine")
  expect_equal(.realm_of("Deep-water"), "marine")
  # Pelagic remains its own marine term; the two must not collapse into one
  # another, because Mugu's scheme deliberately distinguishes them.
  expect_equal(.realm_of("Pelagic"), "marine")
})
