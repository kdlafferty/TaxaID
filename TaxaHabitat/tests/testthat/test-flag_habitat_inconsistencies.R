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
  sf::sf_use_s2(FALSE)
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
  sf::sf_use_s2(FALSE)
  mi <- tryCatch(rnaturalearth::ne_download(scale = 10, type = "minor_islands_coastline",
                   category = "physical", returnclass = "sf"), error = function(e) NULL)
  skip_if(is.null(mi), "Natural Earth minor-islands layer unavailable")
  pts <- sf::st_sfc(sf::st_point(c(-119.39, 34.015)),   # Anacapa
                    sf::st_point(c(-119.03, 33.475)),   # Santa Barbara Island
                    crs = 4326L)
  d <- suppressWarnings(as.numeric(sf::st_distance(pts, sf::st_union(sf::st_geometry(mi)))))
  expect_true(all(d / 1000 < 2))   # both within 2 km of a mapped island shore
})
