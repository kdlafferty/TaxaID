# test-screen_spatial_formula.R
# testthat tests for screen_spatial_formula().
#
# Part A (input validation) runs without glmmTMB -- always executed.
# Part B (integration) requires glmmTMB and is skipped automatically if absent.

# ---------------------------------------------------------------------------
# Shared helper
# ---------------------------------------------------------------------------
.make_gid_ssf <- function(lat, lon) {
  lat_str <- gsub("\\.", "p", as.character(abs(round(lat, 4))))
  lon_str <- gsub("\\.", "p", as.character(abs(round(lon, 4))))
  paste0("Grid_", lat_str, "_", if (lon < 0) "m" else "", lon_str)
}

# ===========================================================================
# Part A: Input validation -- no glmmTMB required
# ===========================================================================
test_that("non-formula formula_full raises an error", {
  expect_error(
    screen_spatial_formula(data.frame(x = 1), formula_full = "not a formula"),
    regexp = "formula"
  )
})

test_that("NULL formula_full raises an error", {
  expect_error(
    screen_spatial_formula(data.frame(x = 1), formula_full = NULL),
    regexp = "formula"
  )
})

test_that("formula with no Moran or spatial terms raises an error", {
  expect_error(
    screen_spatial_formula(
      data         = data.frame(x = 1, n_species = 1, n_other = 1),
      formula_full = cbind(n_species, n_other) ~ x + (1 | x)
    ),
    regexp = "no Moran"
  )
})

test_that("negative sd_threshold raises an error", {
  f <- cbind(n_species, n_other) ~ main_habitat +
    (1 | taxon_name) + (0 + B1 | taxon_name) +
    (0 + lat_r_s | taxon_name) + (1 | taxon_name:grid_id)
  expect_error(
    screen_spatial_formula(data.frame(), f, sd_threshold = -0.1),
    regexp = "sd_threshold"
  )
})

test_that("zero sd_threshold raises an error", {
  f <- cbind(n_species, n_other) ~ main_habitat +
    (1 | taxon_name) + (0 + B1 | taxon_name) +
    (0 + lat_r_s | taxon_name) + (1 | taxon_name:grid_id)
  expect_error(
    screen_spatial_formula(data.frame(), f, sd_threshold = 0),
    regexp = "sd_threshold"
  )
})

test_that("negative delta_aic_max raises an error", {
  f <- cbind(n_species, n_other) ~ main_habitat +
    (0 + lat_r_s | taxon_name) + (1 | taxon_name:grid_id)
  expect_error(
    screen_spatial_formula(data.frame(), f, delta_aic_max = -1),
    regexp = "delta_aic_max"
  )
})

test_that("missing Moran columns in data raises an error", {
  d <- data.frame(
    taxon_name      = "sp1",
    grid_id         = "Grid_33p0_m119p0",
    n_species       = 1L,
    n_other         = 9L,
    n_total_at_site = 10L,
    main_habitat    = "Rocky",
    lat_r_s         = 0.1,
    lon_r_s         = -0.1
    # B1, B2 intentionally absent
  )
  f <- cbind(n_species, n_other) ~ main_habitat +
    (1 | taxon_name) + (0 + B1 | taxon_name) + (0 + B2 | taxon_name) +
    (0 + lat_r_s | taxon_name) + (1 | taxon_name:grid_id)

  expect_error(screen_spatial_formula(d, f), regexp = "not found in data: B1")
})

test_that("Moran term detection from formula is correct", {
  f <- cbind(n_species, n_other) ~ main_habitat +
    (1 | taxon_name) +
    (0 + B1 | taxon_name) + (0 + B3 | taxon_name) + (0 + B5 | taxon_name) +
    (0 + lat_r_s | taxon_name) + (0 + lon_r_s | taxon_name) +
    (1 | taxon_name:grid_id)

  all_v        <- all.vars(f)
  moran_found  <- sort(grep("^B[0-9]+$", all_v, value = TRUE))
  spatial_found <- intersect(c("lat_r_s", "lon_r_s"), all_v)

  expect_equal(moran_found, c("B1", "B3", "B5"))
  expect_equal(spatial_found, c("lat_r_s", "lon_r_s"))
})

test_that("formula with spatial terms but no Moran terms is detected correctly", {
  f <- cbind(n_species, n_other) ~ main_habitat +
    (0 + lat_r_s | taxon_name) + (0 + lon_r_s | taxon_name) +
    (1 | taxon_name:grid_id)

  all_v         <- all.vars(f)
  moran_found   <- grep("^B[0-9]+$", all_v, value = TRUE)
  spatial_found <- intersect(c("lat_r_s", "lon_r_s"), all_v)

  expect_length(moran_found, 0L)
  expect_length(spatial_found, 2L)
})

# ===========================================================================
# Part B: Integration tests -- skipped if glmmTMB not available
# ===========================================================================

# Build synthetic dataset once, reused across Part B tests.
.syn_data <- local({
  skip_if_not_installed("glmmTMB")

  set.seed(42L)
  lats <- seq(33.0, 33.9, by = 0.1)
  lons <- seq(-119.0, -118.7, by = 0.1)
  grid <- expand.grid(lat = lats, lon = lons)
  grid$grid_id <- mapply(.make_gid_ssf, grid$lat, grid$lon)

  grid$lat_r_s <- as.numeric(scale(grid$lat))
  grid$lon_r_s <- as.numeric(scale(grid$lon))

  habitats <- c("Rocky", "Pelagic")
  species  <- paste0("Species_", LETTERS[1:8])
  n_cell   <- 100L

  rows <- do.call(rbind, lapply(grid$grid_id, function(gid) {
    row_g   <- grid[grid$grid_id == gid, ]
    lat_v   <- row_g$lat
    lat_r_s <- row_g$lat_r_s
    lon_r_s <- row_g$lon_r_s
    do.call(rbind, lapply(habitats, function(hab) {
      do.call(rbind, lapply(seq_along(species), function(i) {
        base_p  <- 0.15 + i * 0.03
        lat_eff <- (lat_v - 33.45) * (i %% 3 - 1) * 0.2
        hab_eff <- if (hab == "Rocky") 0.15 else -0.05
        p <- plogis(qlogis(base_p) + lat_eff + hab_eff)
        k <- rbinom(1L, n_cell, p)
        data.frame(
          taxon_name      = species[i],
          grid_id         = gid,
          main_habitat    = hab,
          n_species       = k,
          n_other         = n_cell - k,
          n_total_at_site = n_cell,
          lat_r_s         = lat_r_s,
          lon_r_s         = lon_r_s,
          stringsAsFactors = FALSE
        )
      }))
    }))
  }))

  basis <- suppressMessages(compute_moran_basis(unique(rows$grid_id), k = 3L))
  merge(rows, basis, by = "grid_id", all.x = TRUE)
})

.ssf_args <- list(
  sd_threshold     = 0.20,
  delta_aic_max    = 2.0,
  verbose          = FALSE,
  effort_threshold = 1L
)

.full_formula <- cbind(n_species, n_other) ~
  main_habitat +
  (1 | taxon_name) +
  (0 + B1 | taxon_name) +
  (0 + B2 | taxon_name) +
  (0 + B3 | taxon_name) +
  (0 + lat_r_s | taxon_name) +
  (0 + lon_r_s | taxon_name) +
  (1 | taxon_name:grid_id)

test_that("function runs end-to-end on synthetic data without error", {
  skip_if_not_installed("glmmTMB")
  expect_no_error(
    do.call(screen_spatial_formula,
            c(list(data = .syn_data, formula_full = .full_formula), .ssf_args))
  )
})

test_that("return object has correct top-level structure", {
  skip_if_not_installed("glmmTMB")
  result <- do.call(screen_spatial_formula,
                    c(list(data = .syn_data, formula_full = .full_formula), .ssf_args))
  expect_true("model_selection" %in% names(result))
  expect_true("models"          %in% names(result))
  expect_true("tiers"           %in% names(result))
  expect_true("meta"            %in% names(result))
})

test_that("$model_selection has required elements", {
  skip_if_not_installed("glmmTMB")
  result <- do.call(screen_spatial_formula,
                    c(list(data = .syn_data, formula_full = .full_formula), .ssf_args))
  ms <- result$model_selection
  expect_true("aic_table"           %in% names(ms))
  expect_true("recommended_formula" %in% names(ms))
  expect_true("flagged_terms"       %in% names(ms))
  expect_true("sd_table"            %in% names(ms))
})

test_that("aic_table has correct columns and valid values", {
  skip_if_not_installed("glmmTMB")
  result <- do.call(screen_spatial_formula,
                    c(list(data = .syn_data, formula_full = .full_formula), .ssf_args))
  tbl <- result$model_selection$aic_table
  expect_s3_class(tbl, "data.frame")
  expect_true(all(c("model", "AIC", "delta_AIC", "n_var_params", "recommended") %in% names(tbl)))
  expect_equal(sum(tbl$recommended), 1L)
  expect_equal(min(tbl$delta_AIC), 0.0)
  expect_true(all(tbl$delta_AIC >= 0))
  expect_true(any(grepl("Baseline", tbl$model, ignore.case = TRUE)))
  expect_true(any(grepl("Full",     tbl$model, ignore.case = TRUE)))
})

test_that("sd_table only contains B and lat/lon terms with valid values", {
  skip_if_not_installed("glmmTMB")
  result <- do.call(screen_spatial_formula,
                    c(list(data = .syn_data, formula_full = .full_formula), .ssf_args))
  sd_tbl <- result$model_selection$sd_table
  expect_s3_class(sd_tbl, "data.frame")
  expect_true(all(c("term", "sd", "flagged") %in% names(sd_tbl)))
  expect_true(all(sd_tbl$sd >= 0))
  expect_type(sd_tbl$flagged, "logical")
  expect_true(all(grepl("^B[0-9]+$|^lat_r_s$|^lon_r_s$", sd_tbl$term)))
})

test_that("recommended formula is a valid non-empty string retaining key terms", {
  skip_if_not_installed("glmmTMB")
  result <- do.call(screen_spatial_formula,
                    c(list(data = .syn_data, formula_full = .full_formula), .ssf_args))
  rec_f <- result$model_selection$recommended_formula
  expect_type(rec_f, "character")
  expect_gt(nchar(rec_f), 0L)
  expect_match(rec_f, "cbind")
  expect_match(rec_f, "taxon_name:grid_id")
  expect_match(rec_f, "main_habitat")
})

test_that("recommended model is within delta_aic_max of best", {
  skip_if_not_installed("glmmTMB")
  result <- do.call(screen_spatial_formula,
                    c(list(data = .syn_data, formula_full = .full_formula), .ssf_args))
  tbl     <- result$model_selection$aic_table
  rec_row <- tbl[tbl$recommended, ]
  expect_lte(rec_row$delta_AIC, 2.0)
})
