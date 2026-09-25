# Fake GBIF: species "11" has records at 3, 30 and 300 km; "22" at 60 km;
# every record is inside the polygon. Cumulative facet counts are derived from
# these distances, so the band differencing is checked against known truth.
.fake_records <- data.frame(key = c("11", "11", "11", "11", "22"), d = c(3, 3, 30, 300, 60))

.fake_gbif <- function(urls, max_active = 4L) {
  lapply(urls, function(u) {
    if (grepl("/species/", u)) {
      k <- sub(".*/species/", "", u)
      return(list(species = paste("Species", k), kingdom = "Animalia", phylum = "Chordata",
                  class = "Actinopterygii", order = "O", family = "F", genus = "Species"))
    }
    r <- if (grepl("geoDistance=", u)) {
      e <- as.numeric(sub("km.*", "", sub(".*geoDistance=[^,]+,[^,]+,", "", u)))
      .fake_records[.fake_records$d <= e, ]
    } else {
      .fake_records
    }
    tab <- table(r$key)
    list(count = nrow(r), facets = list(list(field = "SPECIES_KEY", counts = lapply(names(tab), function(k) {
      list(name = k, count = as.integer(tab[[k]]))
    }))))
  })
}

test_that("band counts difference cumulative rings and add the polygon remainder", {
  local_mocked_bindings(.gbif_get_json_parallel = .fake_gbif)
  out <- suppressMessages(fetch_gbif_facet_counts(1, 34, -120,
    geometry = "POLYGON ((0 0, 1 0, 1 1, 0 0))",
    breaks_km = c(10, 100), cache_dir = NULL
  ))
  got <- out[order(out$speciesKey, out$band), c("speciesKey", "band_lo_km", "band_hi_km", "n")]
  expect_equal(got$speciesKey, c("11", "11", "11", "22"))
  expect_equal(got$band_hi_km, c(10, 100, Inf, 100))
  expect_equal(got$n, c(2, 1, 1, 1))
  expect_equal(sum(out$n), nrow(.fake_records))
  expect_equal(unique(out$taxon_name[out$speciesKey == "22"]), "Species 22")
  expect_equal(attr(out, "total_records"), 5)
})

test_that("without geometry there is no remainder band", {
  local_mocked_bindings(.gbif_get_json_parallel = .fake_gbif)
  out <- suppressMessages(fetch_gbif_facet_counts(1, 34, -120, breaks_km = c(10, 100), cache_dir = NULL))
  expect_false(any(is.infinite(out$band_hi_km)))
  expect_equal(sum(out$n), 4) # the 300 km record lies beyond the last ring
})

test_that("default breaks come from lambda_km and include 3 and 6 bandwidths", {
  seen <- character(0)
  local_mocked_bindings(.gbif_get_json_parallel = function(urls, max_active = 4L) {
    seen <<- c(seen, urls)
    .fake_gbif(urls, max_active)
  })
  suppressMessages(fetch_gbif_facet_counts(1, 34, -120, lambda_km = 20, cache_dir = NULL))
  edges <- as.numeric(sub("km.*", "", sub(".*geoDistance=[^,]+,[^,]+,", "", grep("geoDistance", seen, value = TRUE))))
  expect_true(all(c(60, 120) %in% edges))
})

test_that("the cache key encodes the query: a changed argument misses, an identical call hits", {
  n_calls <- 0L
  local_mocked_bindings(.gbif_get_json_parallel = function(urls, max_active = 4L) {
    n_calls <<- n_calls + 1L
    .fake_gbif(urls, max_active)
  })
  cd <- tempfile("facet_cache_")
  on.exit(unlink(cd, recursive = TRUE), add = TRUE)
  suppressMessages(fetch_gbif_facet_counts(1, 34, -120, breaks_km = c(10, 100), cache_dir = cd))
  after_first <- n_calls
  suppressMessages(fetch_gbif_facet_counts(1, 34, -120, breaks_km = c(10, 100), cache_dir = cd))
  expect_equal(n_calls, after_first) # hit: no requests
  suppressMessages(fetch_gbif_facet_counts(1, 34, -120, breaks_km = c(10, 100), year_range = "2010,2020", cache_dir = cd))
  expect_gt(n_calls, after_first) # different question: refetched
  # species names were cached by the first call, so the third made no lookups
  expect_true(file.exists(file.path(cd, "gbif_species_classification.rds")))
})

test_that("a facet page at the limit stops instead of silently truncating", {
  local_mocked_bindings(
    .gbif_get_json_parallel = function(urls, max_active = 4L) {
      lapply(urls, function(u) list(count = 3, facets = list(list(counts = lapply(1:3, function(i) list(name = as.character(i), count = 1L))))))
    },
    .facet_limit = 3L
  )
  expect_error(suppressMessages(fetch_gbif_facet_counts(1, 34, -120, breaks_km = 10, cache_dir = NULL)), "facet limit")
})

test_that("input validation", {
  expect_error(fetch_gbif_facet_counts(numeric(0), 34, -120, lambda_km = 10), "empty")
  expect_error(fetch_gbif_facet_counts(1, 34, -120, cache_dir = NULL), "lambda_km")
  expect_error(fetch_gbif_facet_counts(1, 34, -120, breaks_km = c(10, 5), cache_dir = NULL), "increasing")
})

test_that("estimate_gbif_fetch_cost prices both paths from one count pass", {
  local_mocked_bindings(.gbif_get_json_parallel = function(urls, max_active = 4L) {
    lapply(urls, function(u) list(count = 2e6, facets = list(list(counts = list(
      list(name = "11", count = 1.5e6), list(name = "22", count = 1e5)
    )))))
  })
  x <- suppressMessages(estimate_gbif_fetch_cost(1, lambda_km = 25, cache_dir = NULL, ram_gb = 16))
  expect_equal(x$n_records, 2e6)
  expect_equal(x$n_species, 2L)
  expect_equal(x$record_peak_gb, 8)
  expect_equal(x$recommended, "record") # 8 GB is not over half of 16
  y <- suppressMessages(estimate_gbif_fetch_cost(1, lambda_km = 25, cache_dir = NULL, ram_gb = 8))
  expect_equal(y$recommended, "facet")
  z <- suppressMessages(estimate_gbif_fetch_cost(1, lambda_km = 25, cache_dir = NULL, ram_gb = 1e3, max_records = 1e6))
  expect_equal(z$recommended, "facet")
})
