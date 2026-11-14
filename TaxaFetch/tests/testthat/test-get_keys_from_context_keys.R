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
