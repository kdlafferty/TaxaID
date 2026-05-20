# test-dataone_standardize.R
# Tests for DataONE pipeline internals in dataone_standardize.R and
# dataone_geo_screening.R. All pure — no network calls or mocking required.
#
# Covers:
#   .map_columns_to_dwc()     column name → DwC term mapping
#   .classify_entity()        entity category from mapping
#   .find_site_code_column()  overlap-based site code column detection
#   .attempt_odm_join()       ODM observation+location+taxon join
#   build_geo_prompt()        scope_lookup shortcut logic (catalog fixture only)

library(testthat)

# =============================================================================
# Fixtures
# =============================================================================

# Minimal catalog row for build_geo_prompt tests (no network)
.make_catalog <- function() {
  data.frame(
    id                   = c("scope.1.1", "scope.2.1", "other.1.1",
                             "other.2.1", "nodesc.1.1"),
    scope                = c("knb-lter-sbc", "knb-lter-sbc", "knb-lter-fce",
                             "knb-lter-hfr", "knb-lter-arc"),
    geographicdescription = c("Santa Barbara Channel, California",
                              "Santa Barbara Channel, California",
                              "Florida Everglades",
                              "Harvard Forest, Massachusetts",
                              NA_character_),
    is_candidate         = c(TRUE, TRUE, TRUE, TRUE, TRUE),
    stringsAsFactors     = FALSE
  )
}

.sbc_bbox <- c(-120.5, -119.3, 33.8, 34.5)  # Santa Barbara Channel
.fce_bbox <- c(-81.2,  -80.4,  25.1, 25.8)  # Florida Everglades

# Minimal ODM tables
.make_obs <- function() {
  data.frame(
    observation_id = 1:6,
    location_id    = c(1L, 1L, 2L, 2L, 3L, 3L),
    taxon_id       = c(1L, 2L, 1L, 2L, 1L, 2L),
    datetime       = rep("2020-01-10", 6),
    variable_name  = rep("DENSITY", 6),
    value          = c(0, 5, 3, 0, 1, 2),
    unit           = rep("num_per_m2", 6),
    stringsAsFactors = FALSE
  )
}

.make_loc <- function() {
  data.frame(
    location_id      = c("1", "2", "3"),
    location_name    = c("SiteA", "SiteB", "SiteC"),
    latitude         = c(34.4, 34.5, 34.3),
    longitude        = c(-119.8, -119.9, -120.0),
    parent_location_id = c(NA, NA, NA),
    stringsAsFactors = FALSE
  )
}

.make_tax <- function() {
  data.frame(
    taxon_id   = c("1", "2"),
    taxon_name = c("Sebastes mystinus", "Oxyjulis californica"),
    taxon_rank = c("Species", "Species"),
    stringsAsFactors = FALSE
  )
}

# Wrap three tables into entity_info list as .attempt_odm_join expects
.make_entity_info <- function(obs = .make_obs(),
                               loc = .make_loc(),
                               tax = .make_tax()) {
  list(
    list(ename = "observation", raw = obs,
         entity = list(data_url = NA_character_,
                       attributes = data.frame(
                         attributeName = names(obs),
                         stringsAsFactors = FALSE)),
         mapping = character(0), category = "no_coords_no_species"),
    list(ename = "location", raw = loc,
         entity = list(data_url = NA_character_,
                       attributes = data.frame(
                         attributeName = names(loc),
                         stringsAsFactors = FALSE)),
         mapping = character(0), category = "no_coords_no_species"),
    list(ename = "taxon", raw = tax,
         entity = list(data_url = NA_character_,
                       attributes = data.frame(
                         attributeName = names(tax),
                         stringsAsFactors = FALSE)),
         mapping = character(0), category = "species_only")
  )
}

# Minimal meta object for .attempt_odm_join / .finalize_entity
.make_meta <- function() {
  list(
    id       = "test.1.1",
    title    = "Test dataset",
    creator  = "Tester",
    pub_date = "2020-01-01",
    abstract = NA_character_,
    entities = list(),
    sites    = data.frame(site_code = character(0),
                          decimalLatitude  = numeric(0),
                          decimalLongitude = numeric(0),
                          stringsAsFactors = FALSE)
  )
}

# bbox as named list (internal format used by .filter_to_bbox_df)
.sbc_bbox_list <- list(west = -120.5, east = -119.3, south = 33.8, north = 34.5)


# =============================================================================
# .map_columns_to_dwc
# =============================================================================

test_that("maps decimalLatitude and decimalLongitude", {
  m <- TaxaFetch:::.map_columns_to_dwc(
    c("decimalLatitude", "decimalLongitude"),
    TaxaFetch:::.default_dwc_map
  )
  expect_equal(unname(m["decimalLatitude"]),  "decimalLatitude")
  expect_equal(unname(m["decimalLongitude"]), "decimalLongitude")
})

test_that("maps bare latitude and longitude (new regex)", {
  m <- TaxaFetch:::.map_columns_to_dwc(
    c("latitude", "longitude"),
    TaxaFetch:::.default_dwc_map
  )
  expect_equal(unname(m["latitude"]),  "decimalLatitude")
  expect_equal(unname(m["longitude"]), "decimalLongitude")
})

test_that("maps lat and lon abbreviations", {
  m <- TaxaFetch:::.map_columns_to_dwc(
    c("lat", "lon"),
    TaxaFetch:::.default_dwc_map
  )
  expect_equal(unname(m["lat"]), "decimalLatitude")
  expect_equal(unname(m["lon"]), "decimalLongitude")
})

test_that("does NOT map scientificNameID to scientificName (regex fix)", {
  m <- TaxaFetch:::.map_columns_to_dwc(
    "scientificNameID",
    TaxaFetch:::.default_dwc_map
  )
  expect_true(is.na(m["scientificNameID"]))
})

test_that("maps scientificName correctly", {
  m <- TaxaFetch:::.map_columns_to_dwc(
    "scientificName",
    TaxaFetch:::.default_dwc_map
  )
  expect_equal(unname(m["scientificName"]), "scientificName")
})

test_that("maps taxon_name to scientificName", {
  m <- TaxaFetch:::.map_columns_to_dwc(
    "taxon_name",
    TaxaFetch:::.default_dwc_map
  )
  expect_equal(unname(m["taxon_name"]), "scientificName")
})

test_that("first match wins — earlier pattern takes priority", {
  # genus_name should map to genus, not be caught by scientificName pattern
  m <- TaxaFetch:::.map_columns_to_dwc(
    "genus_name",
    TaxaFetch:::.default_dwc_map
  )
  expect_equal(unname(m["genus_name"]), "genus")
})

test_that("unrecognised columns return NA", {
  m <- TaxaFetch:::.map_columns_to_dwc(
    c("flarble_xyz", "wombat_code"),
    TaxaFetch:::.default_dwc_map
  )
  expect_true(all(is.na(m)))
})

test_that("matching is case-insensitive", {
  m <- TaxaFetch:::.map_columns_to_dwc(
    c("DECIMALLAT", "Decimal_Longitude"),
    TaxaFetch:::.default_dwc_map
  )
  expect_equal(unname(m["DECIMALLAT"]),       "decimalLatitude")
  expect_equal(unname(m["Decimal_Longitude"]), "decimalLongitude")
})

test_that("returns named vector with input names", {
  m <- TaxaFetch:::.map_columns_to_dwc(
    c("latitude", "taxon_name"),
    TaxaFetch:::.default_dwc_map
  )
  expect_equal(names(m), c("latitude", "taxon_name"))
})

test_that("handles empty input gracefully", {
  m <- TaxaFetch:::.map_columns_to_dwc(character(0),
                                        TaxaFetch:::.default_dwc_map)
  expect_equal(length(m), 0L)
})


# =============================================================================
# .classify_entity
# =============================================================================

test_that("returns 'complete' when lat, lon, and species all present", {
  m <- c(lat = "decimalLatitude", lon = "decimalLongitude",
         sp  = "scientificName")
  expect_equal(TaxaFetch:::.classify_entity(m), "complete")
})

test_that("returns 'spatial_only' when lat+lon but no species", {
  m <- c(lat = "decimalLatitude", lon = "decimalLongitude",
         x   = NA_character_)
  expect_equal(TaxaFetch:::.classify_entity(m), "spatial_only")
})

test_that("returns 'species_only' when species but no coords", {
  m <- c(sp = "scientificName", x = NA_character_)
  expect_equal(TaxaFetch:::.classify_entity(m), "species_only")
})

test_that("returns 'species_only' when genus present but no coords", {
  m <- c(g = "genus", x = NA_character_)
  expect_equal(TaxaFetch:::.classify_entity(m), "species_only")
})

test_that("returns 'species_only' when specificEpithet present but no coords", {
  m <- c(e = "specificEpithet", x = NA_character_)
  expect_equal(TaxaFetch:::.classify_entity(m), "species_only")
})

test_that("returns 'no_coords_no_species' when nothing useful mapped", {
  m <- c(a = "eventDate", b = "locality", c = NA_character_)
  expect_equal(TaxaFetch:::.classify_entity(m), "no_coords_no_species")
})

test_that("returns 'unknown' for empty mapping", {
  expect_equal(TaxaFetch:::.classify_entity(character(0)), "unknown")
})

test_that("requires both lat AND lon for spatial classification", {
  # lat only → not spatial_only
  m <- c(lat = "decimalLatitude", x = NA_character_)
  expect_equal(TaxaFetch:::.classify_entity(m), "no_coords_no_species")
})

test_that("bare latitude/longitude columns classify as complete via new regex", {
  cols <- c("latitude", "longitude", "taxon_name", "eventDate")
  m <- TaxaFetch:::.map_columns_to_dwc(cols, TaxaFetch:::.default_dwc_map)
  expect_equal(TaxaFetch:::.classify_entity(m), "complete")
})


# =============================================================================
# .find_site_code_column
# =============================================================================

test_that("returns column with highest overlap fraction", {
  df <- data.frame(
    site_code  = c("AQUE", "CARP", "MOHK"),
    other_code = c("X1",   "X2",   "X3"),
    stringsAsFactors = FALSE
  )
  result <- TaxaFetch:::.find_site_code_column(df, c("AQUE", "CARP", "MOHK"))
  expect_equal(result, "site_code")
})

test_that("returns NULL when no column exceeds min_overlap_frac", {
  df <- data.frame(
    col_a = c("XX", "YY", "ZZ"),
    stringsAsFactors = FALSE
  )
  result <- TaxaFetch:::.find_site_code_column(df, c("AQUE", "CARP", "MOHK"))
  expect_null(result)
})

test_that("matching is case-insensitive", {
  df <- data.frame(
    site = c("aque", "carp", "mohk"),
    stringsAsFactors = FALSE
  )
  result <- TaxaFetch:::.find_site_code_column(df, c("AQUE", "CARP", "MOHK"))
  expect_equal(result, "site")
})

test_that("returns NULL when site_codes is empty", {
  df <- data.frame(site = c("AQUE", "CARP"), stringsAsFactors = FALSE)
  expect_null(TaxaFetch:::.find_site_code_column(df, character(0)))
})

test_that("returns NULL when df has no columns", {
  df <- data.frame()
  expect_null(TaxaFetch:::.find_site_code_column(df, c("AQUE")))
})

test_that("partial overlap above threshold wins over lower-overlap column", {
  df <- data.frame(
    good = c("AQUE", "CARP", "ZZZZ"),   # 2/3 overlap
    bad  = c("AA",   "BB",   "AQUE"),   # 1/3 overlap
    stringsAsFactors = FALSE
  )
  result <- TaxaFetch:::.find_site_code_column(df, c("AQUE", "CARP", "MOHK"),
                                                min_overlap_frac = 0.5)
  expect_equal(result, "good")
})

test_that("returns NULL when best overlap is exactly at threshold (not above)", {
  df <- data.frame(
    site = c("AQUE", "XXXX"),
    stringsAsFactors = FALSE
  )
  # 1/2 = 0.5 overlap against c("AQUE", "CARP") with threshold 0.5
  # best_frac starts at min_overlap_frac and requires strictly greater
  result <- TaxaFetch:::.find_site_code_column(df, c("AQUE", "CARP"),
                                                min_overlap_frac = 0.5)
  expect_null(result)
})


# =============================================================================
# .attempt_odm_join
# =============================================================================

test_that("returns a data frame with expected DwC columns on valid input", {
  ei   <- .make_entity_info()
  meta <- .make_meta()
  bbox <- .sbc_bbox_list

  result <- TaxaFetch:::.attempt_odm_join(
    ei, TaxaFetch:::.default_dwc_map, meta, bbox,
    gbif_hashes  = NULL,
    verbose      = FALSE,
    odm_variable = "DENSITY"
  )

  expect_true(is.data.frame(result))
  expect_true("scientificName"   %in% names(result))
  expect_true("decimalLatitude"  %in% names(result))
  expect_true("decimalLongitude" %in% names(result))
  expect_true("eventDate"        %in% names(result))
})

test_that("filters to odm_variable rows only", {
  obs <- .make_obs()
  obs$variable_name[1:3] <- "BIOMASS"   # mix two variables
  ei   <- .make_entity_info(obs = obs)
  meta <- .make_meta()

  result <- TaxaFetch:::.attempt_odm_join(
    ei, TaxaFetch:::.default_dwc_map, meta, .sbc_bbox_list,
    gbif_hashes = NULL, verbose = FALSE, odm_variable = "DENSITY"
  )

  if (!is.null(result)) {
    expect_true(all(result$variable_name == "DENSITY"))
  }
})

test_that("falls back to all rows when odm_variable absent", {
  obs <- .make_obs()
  obs$variable_name <- rep("COUNT", nrow(obs))
  ei   <- .make_entity_info(obs = obs)
  meta <- .make_meta()

  result <- TaxaFetch:::.attempt_odm_join(
    ei, TaxaFetch:::.default_dwc_map, meta, .sbc_bbox_list,
    gbif_hashes = NULL, verbose = FALSE, odm_variable = "DENSITY"
  )

  expect_true(is.data.frame(result))
  expect_equal(nrow(result), nrow(obs))  # all rows kept
})

test_that("returns NULL when observation entity is missing", {
  ei   <- .make_entity_info()
  ei   <- ei[vapply(ei, function(x) x$ename != "observation", logical(1L))]
  meta <- .make_meta()

  result <- TaxaFetch:::.attempt_odm_join(
    ei, TaxaFetch:::.default_dwc_map, meta, .sbc_bbox_list,
    gbif_hashes = NULL, verbose = FALSE, odm_variable = "DENSITY"
  )
  expect_null(result)
})

test_that("returns NULL when location entity is missing", {
  ei   <- .make_entity_info()
  ei   <- ei[vapply(ei, function(x) x$ename != "location", logical(1L))]
  meta <- .make_meta()

  result <- TaxaFetch:::.attempt_odm_join(
    ei, TaxaFetch:::.default_dwc_map, meta, .sbc_bbox_list,
    gbif_hashes = NULL, verbose = FALSE, odm_variable = "DENSITY"
  )
  expect_null(result)
})

test_that("returns NULL when taxon entity is missing", {
  ei   <- .make_entity_info()
  ei   <- ei[vapply(ei, function(x) x$ename != "taxon", logical(1L))]
  meta <- .make_meta()

  result <- TaxaFetch:::.attempt_odm_join(
    ei, TaxaFetch:::.default_dwc_map, meta, .sbc_bbox_list,
    gbif_hashes = NULL, verbose = FALSE, odm_variable = "DENSITY"
  )
  expect_null(result)
})

test_that("returns NULL when location table has no coordinate rows", {
  loc      <- .make_loc()
  loc$latitude  <- NA_real_
  loc$longitude <- NA_real_
  ei   <- .make_entity_info(loc = loc)
  meta <- .make_meta()

  result <- TaxaFetch:::.attempt_odm_join(
    ei, TaxaFetch:::.default_dwc_map, meta, .sbc_bbox_list,
    gbif_hashes = NULL, verbose = FALSE, odm_variable = "DENSITY"
  )
  expect_null(result)
})

test_that("coerces numeric location_id in obs to character for join", {
  obs <- .make_obs()
  obs$location_id <- as.numeric(obs$location_id)  # simulate real EDI data
  ei   <- .make_entity_info(obs = obs)
  meta <- .make_meta()

  result <- TaxaFetch:::.attempt_odm_join(
    ei, TaxaFetch:::.default_dwc_map, meta, .sbc_bbox_list,
    gbif_hashes = NULL, verbose = FALSE, odm_variable = "DENSITY"
  )
  expect_true(is.data.frame(result))
  expect_gt(nrow(result), 0L)
})

test_that("bbox filter removes out-of-range records", {
  # Use a bbox that excludes all fixture sites
  tiny_bbox <- list(west = 0, east = 1, south = 0, north = 1)
  ei   <- .make_entity_info()
  meta <- .make_meta()

  result <- TaxaFetch:::.attempt_odm_join(
    ei, TaxaFetch:::.default_dwc_map, meta, tiny_bbox,
    gbif_hashes = NULL, verbose = FALSE, odm_variable = "DENSITY"
  )
  expect_null(result)  # .finalize_entity returns NULL when 0 rows survive bbox
})

test_that("entity name matching is case-insensitive", {
  ei <- .make_entity_info()
  # Capitalise entity names
  for (i in seq_along(ei)) ei[[i]]$ename <- toupper(ei[[i]]$ename)
  meta <- .make_meta()

  result <- TaxaFetch:::.attempt_odm_join(
    ei, TaxaFetch:::.default_dwc_map, meta, .sbc_bbox_list,
    gbif_hashes = NULL, verbose = FALSE, odm_variable = "DENSITY"
  )
  expect_true(is.data.frame(result))
})

test_that("prefers exact entity name match over partial (obs vs observation_ancillary)", {
  ei <- .make_entity_info()
  # Add an ancillary entity that starts with "observation"
  ancillary <- list(
    ename    = "observation_ancillary",
    raw      = data.frame(x = 1:3),
    entity   = list(data_url = NA_character_,
                    attributes = data.frame(attributeName = "x",
                                            stringsAsFactors = FALSE)),
    mapping  = character(0),
    category = "no_coords_no_species"
  )
  ei_with_anc <- c(ei, list(ancillary))
  meta <- .make_meta()

  result <- TaxaFetch:::.attempt_odm_join(
    ei_with_anc, TaxaFetch:::.default_dwc_map, meta, .sbc_bbox_list,
    gbif_hashes = NULL, verbose = FALSE, odm_variable = "DENSITY"
  )
  # Should still work — exact "observation" preferred over "observation_ancillary"
  expect_true(is.data.frame(result))
})


# =============================================================================
# build_geo_prompt — scope_lookup shortcut logic
# =============================================================================

test_that("scope_lookup = NULL sends all candidates to LLM", {
  cat  <- .make_catalog()
  bbox <- .sbc_bbox

  gp <- build_geo_prompt(cat, bbox, scope_lookup = NULL, verbose = FALSE)

  expect_equal(length(gp$shortcut_accepted), 0L)
  expect_equal(length(gp$shortcut_rejected), 1L)  # nodesc.1.1 only (NA desc)
  # All candidates with descriptions go to LLM
  expect_gt(gp$n_items, 0L)
})

test_that("scope_lookup accepts overlapping scope", {
  cat  <- .make_catalog()
  bbox <- .sbc_bbox

  sl <- data.frame(
    scope = "knb-lter-sbc",
    west  = -120.5, east = -119.3, south = 33.8, north = 34.5,
    label = "SBC LTER"
  )
  gp <- build_geo_prompt(cat, bbox, scope_lookup = sl, verbose = FALSE)

  expect_true("scope.1.1" %in% gp$shortcut_accepted)
  expect_true("scope.2.1" %in% gp$shortcut_accepted)
})

test_that("scope_lookup rejects non-overlapping scope", {
  cat  <- .make_catalog()
  bbox <- .sbc_bbox   # Santa Barbara

  # FCE LTER is in Florida — no overlap with SBC bbox
  sl <- data.frame(
    scope = "knb-lter-fce",
    west  = -81.2, east = -80.4, south = 25.1, north = 25.8,
    label = "FCE LTER"
  )
  gp <- build_geo_prompt(cat, bbox, scope_lookup = sl, verbose = FALSE)

  expect_true("other.1.1" %in% gp$shortcut_rejected)
  expect_false("other.1.1" %in% gp$shortcut_accepted)
})

test_that("scope_lookup handles multiple rows — accept some, reject others", {
  cat  <- .make_catalog()
  bbox <- .sbc_bbox

  sl <- data.frame(
    scope = c("knb-lter-sbc", "knb-lter-fce"),
    west  = c(-120.5, -81.2), east  = c(-119.3, -80.4),
    south = c(33.8,   25.1),  north = c(34.5,   25.8),
    label = c("SBC LTER", "FCE LTER")
  )
  gp <- build_geo_prompt(cat, bbox, scope_lookup = sl, verbose = FALSE)

  expect_true(all(c("scope.1.1", "scope.2.1") %in% gp$shortcut_accepted))
  expect_true("other.1.1" %in% gp$shortcut_rejected)
})

test_that("packages with NA geographicdescription are always excluded from LLM", {
  cat  <- .make_catalog()
  gp   <- build_geo_prompt(cat, .sbc_bbox, scope_lookup = NULL, verbose = FALSE)

  # nodesc.1.1 has NA description — should not appear in LLM descriptions
  expect_false(any(grepl("nodesc", unlist(gp$desc_to_ids))))
})

test_that("deduplication: identical descriptions sent to LLM only once", {
  cat  <- .make_catalog()
  # scope.1.1 and scope.2.1 share the same geographicdescription
  # Without shortcut they should appear as ONE unique description
  gp <- build_geo_prompt(cat, .sbc_bbox, scope_lookup = NULL, verbose = FALSE)

  sbc_descs <- cat$geographicdescription[cat$scope == "knb-lter-sbc" &
                                          !is.na(cat$geographicdescription)]
  n_unique_sbc <- length(unique(sbc_descs))
  # The two SBC packages share one description → deduplicated to 1 LLM call
  expect_equal(n_unique_sbc, 1L)
  # That one description maps to both IDs
  shared_desc <- unique(sbc_descs)[1L]
  expect_equal(length(gp$desc_to_ids[[shared_desc]]), 2L)
})

test_that("scope_lookup missing required columns errors clearly", {
  cat <- .make_catalog()
  sl  <- data.frame(scope = "knb-lter-sbc", west = -120.5)  # missing east/south/north
  expect_error(
    build_geo_prompt(cat, .sbc_bbox, scope_lookup = sl, verbose = FALSE),
    regexp = "scope_lookup.*missing"
  )
})

test_that("scope_lookup = non-dataframe errors clearly", {
  cat <- .make_catalog()
  expect_error(
    build_geo_prompt(cat, .sbc_bbox, scope_lookup = "not_a_df", verbose = FALSE),
    regexp = "scope_lookup"
  )
})

test_that("geo_prompt S3 class is correct", {
  gp <- build_geo_prompt(.make_catalog(), .sbc_bbox,
                          scope_lookup = NULL, verbose = FALSE)
  expect_true(inherits(gp, "geo_prompt"))
  expect_true(inherits(gp, "llm_prompt"))
})

test_that("geo_prompt contains required list elements", {
  gp <- build_geo_prompt(.make_catalog(), .sbc_bbox,
                          scope_lookup = NULL, verbose = FALSE)
  required <- c("prompts", "chunks", "n_chunks", "n_items",
                "descriptions", "desc_to_ids",
                "shortcut_accepted", "shortcut_rejected",
                "catalog", "bbox")
  expect_true(all(required %in% names(gp)))
})

test_that("prompt string contains bbox coordinates", {
  gp <- build_geo_prompt(.make_catalog(), .sbc_bbox,
                          scope_lookup = NULL, verbose = FALSE)
  prompt_text <- gp$prompts[[1L]]
  expect_true(grepl("-120", prompt_text))
  expect_true(grepl("33.8", prompt_text))
})
