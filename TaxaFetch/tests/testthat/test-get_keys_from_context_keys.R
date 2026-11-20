# get_keys_from_context(return_keys = TRUE, cache_dir =): the identifiers GBIF's own backbone match returns
# (accepted key, status, the key of every rank), which a taxon registry keys on, and a per-row cache.
# Offline: rgbif::name_backbone / name_lookup are mocked. Records are shaped like rgbif's (named list of
# scalars; absent fields absent), with keys taken from GBIF's Backbone as recorded in the r15 crosswalk.

.rec_synonym <- function(...) list(   # Embiotoca caryi: a synonym of Hypsurus caryi
  usageKey = 2389311L, acceptedUsageKey = 2389310L, matchType = "EXACT", rank = "SPECIES", status = "SYNONYM", synonym = TRUE,
  canonicalName = "Embiotoca caryi", kingdom = "Animalia", phylum = "Chordata", order = "Perciformes", family = "Embiotocidae",
  genus = "Hypsurus", species = "Hypsurus caryi", kingdomKey = 1L, phylumKey = 44L, orderKey = 587L, familyKey = 4269L,
  genusKey = 2389309L, speciesKey = 2389310L)
.rec_higherrank <- function(...) list(  # a species the backbone lacks: answered at its genus
  usageKey = 9460134L, matchType = "HIGHERRANK", rank = "GENUS", status = "ACCEPTED", synonym = FALSE, canonicalName = "Gelidium",
  kingdom = "Plantae", phylum = "Rhodophyta", class = "Florideophyceae", order = "Gelidiales", family = "Gelidiaceae", genus = "Gelidium",
  kingdomKey = 6L, phylumKey = 106L, classKey = 342L, orderKey = 900L, familyKey = 901L, genusKey = 9460134L)
.sp <- function(name) data.frame(kingdom = "Animalia", species = name, stringsAsFactors = FALSE)

test_that("default output is unchanged: three columns appended, no gbif_ key columns", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(name_backbone = .rec_synonym, .package = "rgbif")
  out <- suppressMessages(get_keys_from_context(.sp("Embiotoca caryi")))
  expect_identical(setdiff(names(out), names(.sp("x"))), c("usageKey", "matchType", "gbif_rank"))
})

test_that("return_keys: a synonym keeps its OWN usageKey and reports its accepted key and every rank's key", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(name_backbone = .rec_synonym, .package = "rgbif")
  out <- suppressMessages(get_keys_from_context(.sp("Embiotoca caryi"), return_keys = TRUE))
  expect_identical(out$usageKey, 2389311L)
  expect_identical(out$gbif_acceptedUsageKey, 2389310L)
  expect_identical(out$gbif_status, "SYNONYM")
  expect_true(out$gbif_synonym)
  expect_identical(c(out$gbif_familyKey, out$gbif_genusKey, out$gbif_speciesKey), c(4269L, 2389309L, 2389310L))
  expect_identical(out$gbif_species, "Hypsurus caryi")
  expect_true(is.na(out$gbif_classKey))      # absent from the record: NA, not an error
  # the input's own rank columns are untouched (the gbif_ prefix keeps them apart)
  expect_identical(out$species, "Embiotoca caryi")
})

test_that("return_keys: a species answered only at GENUS is visibly a genus (HIGHERRANK, GENUS, no species key)", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(name_backbone = .rec_higherrank, .package = "rgbif")
  out <- suppressMessages(get_keys_from_context(data.frame(kingdom = "Plantae", species = "Gelidium kathyanniae"), return_keys = TRUE))
  expect_identical(out$matchType, "HIGHERRANK")
  expect_identical(out$gbif_rank, "GENUS")
  expect_identical(out$usageKey, out$gbif_genusKey)
  expect_true(is.na(out$gbif_speciesKey))
})

test_that("return_keys: a failed request is ERROR with every key column NA, and it is never cached", {
  skip_if_not_installed("rgbif")
  d <- tempfile()
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE))
  local_mocked_bindings(name_backbone = function(...) stop("HTTP 503"), .package = "rgbif")
  out <- suppressMessages(suppressWarnings(get_keys_from_context(.sp("Embiotoca caryi"), return_keys = TRUE, cache_dir = d)))
  expect_identical(out$matchType, "ERROR")
  expect_true(all(is.na(unlist(out[grepl("^gbif_.*Key$", names(out))]))))
  expect_length(list.files(d), 0L)
})

test_that("return_keys: a LOOKUP_RECOVERED key does not borrow the higher-rank record's lineage", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(
    name_backbone = function(...) list(usageKey = 1L, matchType = "HIGHERRANK", rank = "KINGDOM", kingdom = "Animalia", kingdomKey = 1L),
    name_lookup = function(...) list(data = data.frame(rank = "GENUS", nubKey = 777L, kingdom = "Animalia", stringsAsFactors = FALSE)),
    .package = "rgbif")
  out <- suppressMessages(get_keys_from_context(data.frame(kingdom = "Animalia", genus = "Notagenus"), return_keys = TRUE))
  expect_identical(out$matchType, "LOOKUP_RECOVERED")
  expect_identical(out$usageKey, 777L)
  expect_true(is.na(out$gbif_kingdomKey) && is.na(out$gbif_genusKey))
})

test_that("cache_dir: an answered row is served from the cache with the network off; return_keys is part of the key", {
  skip_if_not_installed("rgbif")
  d <- tempfile()
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE))
  local_mocked_bindings(name_backbone = .rec_synonym, .package = "rgbif")
  a <- suppressMessages(get_keys_from_context(.sp("Embiotoca caryi"), return_keys = TRUE, cache_dir = d))
  expect_length(list.files(d), 1L)
  local_mocked_bindings(name_backbone = function(...) stop("network must not be reached"), .package = "rgbif")
  b <- suppressMessages(get_keys_from_context(.sp("Embiotoca caryi"), return_keys = TRUE, cache_dir = d))
  expect_identical(b, a)
  # an entry written WITH keys is not served to a call without them (different key), so this one asks -- and fails
  c2 <- suppressMessages(suppressWarnings(get_keys_from_context(.sp("Embiotoca caryi"), cache_dir = d)))
  expect_identical(c2$matchType, "ERROR")
})

test_that("bad return_keys / cache_dir are refused", {
  expect_error(get_keys_from_context(.sp("x"), return_keys = NA), "return_keys")
  expect_error(get_keys_from_context(.sp("x"), cache_dir = 1), "cache_dir")
})

# Package review 2026-11-13, N1 (taken as F7): a HIGHERRANK answer whose name_lookup() recovery FAILED was cached as a
# final answer, so a transient outage became permanent. FAILS on the reviewed code (2ea632dc): one file is written.
test_that("REVIEW F7: a HIGHERRANK row whose recovery request failed is returned but never cached", {
  skip_if_not_installed("rgbif")
  d <- tempfile()
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE))
  local_mocked_bindings(
    name_backbone = function(...) list(usageKey = 1L, matchType = "HIGHERRANK", rank = "KINGDOM", kingdom = "Animalia", kingdomKey = 1L),
    name_lookup = function(...) stop("HTTP 503"),
    .package = "rgbif")
  out <- suppressMessages(suppressWarnings(get_keys_from_context(data.frame(kingdom = "Animalia", family = "Cyprinidae"), return_keys = TRUE, cache_dir = d)))
  expect_identical(out$matchType, "HIGHERRANK")      # what the caller gets is unchanged
  expect_length(list.files(d), 0L)                  # 2ea632dc: 1 (the degraded row cached as final)
  # so the next call asks again instead of being served the degraded row
  local_mocked_bindings(name_backbone = function(...) stop("asked again"), .package = "rgbif")
  again <- suppressMessages(suppressWarnings(get_keys_from_context(data.frame(kingdom = "Animalia", family = "Cyprinidae"), return_keys = TRUE, cache_dir = d)))
  expect_identical(again$matchType, "ERROR")
})

# Package review 2026-11-13, N2: the cache had no TTL, so a GBIF backbone revision never reached a cached row.
# A row older than 365 days (verify_taxon_names()'s default) is asked again, and so is one with no written_at.
# FAILS on 1f3e31d0: the 400-day-old row is served.
test_that("REVIEW N2: a cached row older than 365 days, or with no written_at, is asked again; a fresh one is served", {
  skip_if_not_installed("rgbif")
  d <- tempfile()
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE))
  local_mocked_bindings(name_backbone = .rec_synonym, .package = "rgbif")
  a <- suppressMessages(get_keys_from_context(.sp("Embiotoca caryi"), return_keys = TRUE, cache_dir = d))
  f <- list.files(d, full.names = TRUE)
  expect_length(f, 1L)
  ent <- readRDS(f)
  local_mocked_bindings(name_backbone = function(...) stop("asked again"), .package = "rgbif")
  ask <- function() suppressMessages(suppressWarnings(get_keys_from_context(.sp("Embiotoca caryi"), return_keys = TRUE, cache_dir = d)))
  ent$written_at <- Sys.time() - 364 * 86400; saveRDS(ent, f)
  expect_identical(ask(), a)                                   # within the TTL: served
  ent$written_at <- Sys.time() - 400 * 86400; saveRDS(ent, f)
  expect_identical(ask()$matchType, "ERROR")                   # 1f3e31d0: the 400-day-old row is served
  ent$written_at <- NULL; saveRDS(ent, f)
  expect_identical(ask()$matchType, "ERROR")                   # no age: cannot prove fresh
})

# ------------------------------------------------------------------------------
# GBIF Backbone keys under rgbif 3.9.0 and later
# ------------------------------------------------------------------------------
# rgbif 3.9.0 and later match names against the Catalogue of Life Extended Release and return its
# alphanumeric keys (e.g. "Q2M4") unless checklistKey names the GBIF Backbone. These mocks answer the
# way 3.9.0 does: a Catalogue of Life key unless the Backbone checklist is asked for.

.BACKBONE <- "d7dddbf4-2cf0-4f39-9b2a-bb099caae36c"
.nb_390 <- function(...) {
  a <- list(...)
  if (identical(a$checklistKey, .BACKBONE)) {
    list(usageKey = 2367386L, matchType = "EXACT", rank = "SPECIES", status = "ACCEPTED", synonym = FALSE,
         canonicalName = "Cyprinella monacha", kingdom = "Animalia", kingdomKey = 1L,
         species = "Cyprinella monacha", speciesKey = 2367386L)
  } else {
    list(usageKey = "Q2M4", matchType = "EXACT", rank = "SPECIES", status = "ACCEPTED", synonym = FALSE,
         canonicalName = "Cyprinella monacha", kingdom = "Animalia", kingdomKey = "N",
         species = "Cyprinella monacha", speciesKey = "Q2M4")
  }
}
.nb_col_only <- function(...) list(usageKey = "Q2M4", matchType = "EXACT", rank = "SPECIES", kingdom = "Animalia",
                                   kingdomKey = "N", species = "Cyprinella monacha", speciesKey = "Q2M4")
.one <- function() data.frame(kingdom = "Animalia", species = "Cyprinella monacha", stringsAsFactors = FALSE)

test_that("get_keys_from_context asks GBIF for Backbone keys, so rgbif 3.9.0 still returns integer keys", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(name_backbone = .nb_390, .package = "rgbif")
  out <- suppressMessages(get_keys_from_context(.one(), return_keys = TRUE, cache_dir = NULL))
  expect_identical(out$usageKey, 2367386L)
  expect_identical(out$matchType, "EXACT")
  expect_identical(out$gbif_kingdomKey, 1L)
  expect_identical(out$gbif_speciesKey, 2367386L)
})

test_that("a non-Backbone key from name_backbone is an error, never an NA reported as matched, and is not cached", {
  skip_if_not_installed("rgbif")
  d <- tempfile()
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE))
  local_mocked_bindings(name_backbone = .nb_col_only, .package = "rgbif")
  expect_error(suppressMessages(get_keys_from_context(.one(), cache_dir = d)), class = "taxaid_gbif_key_not_backbone")
  expect_length(list.files(d), 0L)
})

test_that("caller-supplied keys that are not Backbone integers are refused before any request", {
  skip_if_not_installed("rgbif")
  expect_error(fetch_gbif_occurrences(c("2367386", "Q2M4"), geometry = "POLYGON((0 0,1 0,1 1,0 1,0 0))"),
               class = "taxaid_gbif_key_not_backbone")
  expect_error(fetch_gbif_occurrence_counts(c("Q2M4"), site_lat = 34, site_lon = -120),
               class = "taxaid_gbif_key_not_backbone")
})

test_that(".gbif_backbone_key keeps integers and NA, and refuses anything else", {
  k <- TaxaFetch:::.gbif_backbone_key
  expect_identical(k(c(1L, NA), "t"), c(1L, NA))
  expect_identical(k(c(2367386, NA), "t"), c(2367386L, NA))
  expect_identical(k(c("12", "", NA), "t"), c(12L, NA, NA))
  expect_identical(k(NULL, "t"), integer(0))
  expect_error(k(c("12", "Q2M4"), "t"), class = "taxaid_gbif_key_not_backbone")
  expect_error(k("Q2M4", "where"), "where: 1 GBIF taxon key", fixed = TRUE)
})
