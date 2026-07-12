# test-train_biodiversity_model_by_group.R
# Tests for train_biodiversity_model_by_group() (Session 149).
#
# Raw occurrence data (pre-prepare_model_dataframe) with two sampling groups
# of very different total record counts, so a pooled n_total_at_site would be
# obviously wrong for at least one group -- this is the scenario the function
# exists to handle (e.g. an 18S survey mixing phytoplankton microscopy counts
# with vertebrate eDNA reads).

library(testthat)
library(dplyr)

.make_grouped_raw_occurrences <- function(n_sites = 20, seed = 1) {
  set.seed(seed)
  grids    <- paste0("g", seq_len(n_sites))
  lat_vals <- seq(33, 37, length.out = n_sites)
  lon_vals <- seq(-122, -118.4, length.out = n_sites)
  habitats <- sample(c("Kelp", "Rocky", "Sandy"), n_sites, replace = TRUE)

  site_meta <- data.frame(
    grid_id = grids, lat_r = lat_vals, lon_r = lon_vals,
    main_habitat = habitats, stringsAsFactors = FALSE
  )

  # "vertebrate" group: 2 common species, moderate per-site record counts
  vert_rows <- do.call(rbind, lapply(seq_len(n_sites), function(i) {
    n_rec <- 10L
    data.frame(
      grid_id = grids[i], lat_r = lat_vals[i], lon_r = lon_vals[i],
      main_habitat = habitats[i],
      taxon_name = sample(c("Vert_A", "Vert_B"), n_rec, replace = TRUE,
                          prob = c(0.6, 0.4)),
      sampling_group = "vertebrate",
      stringsAsFactors = FALSE
    )
  }))

  # "phytoplankton" group: much higher per-site record counts (a different
  # detection process/effort scale entirely -- the point of the split)
  phyto_rows <- do.call(rbind, lapply(seq_len(n_sites), function(i) {
    n_rec <- 100L
    data.frame(
      grid_id = grids[i], lat_r = lat_vals[i], lon_r = lon_vals[i],
      main_habitat = habitats[i],
      taxon_name = sample(c("Phyto_A", "Phyto_B"), n_rec, replace = TRUE,
                          prob = c(0.5, 0.5)),
      sampling_group = "phytoplankton",
      stringsAsFactors = FALSE
    )
  }))

  rbind(vert_rows, phyto_rows)
}

test_that("returns a named list of biofreq_model objects, one per group", {
  input <- .make_grouped_raw_occurrences()
  formula <- cbind(n_species, n_other) ~ main_habitat + (1 | taxon_name)

  models <- suppressWarnings(suppressMessages(
    train_biodiversity_model_by_group(
      input, formula = formula, sampling_group_col = "sampling_group",
      verbose = FALSE
    )
  ))

  expect_type(models, "list")
  expect_setequal(names(models), c("vertebrate", "phytoplankton"))
  expect_true(all(vapply(models, inherits, logical(1), "biofreq_model")))
})

test_that("each group's model reflects only its own effort scale (N_total)", {
  input <- .make_grouped_raw_occurrences()
  formula <- cbind(n_species, n_other) ~ main_habitat + (1 | taxon_name)

  models <- suppressWarnings(suppressMessages(
    train_biodiversity_model_by_group(
      input, formula = formula, sampling_group_col = "sampling_group",
      verbose = FALSE
    )
  ))

  # phytoplankton records outnumber vertebrate ~10:1 in this fixture; each
  # group's own N_total must reflect only its own records, not the pooled
  # total across both groups.
  expect_true(models$phytoplankton$N_total > models$vertebrate$N_total)
  expect_equal(models$vertebrate$N_total, 20L * 10L)
  expect_equal(models$phytoplankton$N_total, 20L * 100L)
})

test_that("errors when sampling_group_col is missing", {
  expect_error(
    train_biodiversity_model_by_group(
      .make_grouped_raw_occurrences(),
      formula = cbind(n_species, n_other) ~ main_habitat + (1 | taxon_name)
    ),
    "sampling_group_col"
  )
})

test_that("errors when sampling_group_col is not a column in data", {
  input <- .make_grouped_raw_occurrences()
  input$sampling_group <- NULL
  expect_error(
    train_biodiversity_model_by_group(
      input, formula = cbind(n_species, n_other) ~ main_habitat + (1 | taxon_name),
      sampling_group_col = "sampling_group"
    ),
    "not found"
  )
})

test_that("warns when the grouping column has fewer than 2 distinct values", {
  input <- .make_grouped_raw_occurrences()
  input <- input[input$sampling_group == "vertebrate", ]
  expect_warning(
    suppressMessages(train_biodiversity_model_by_group(
      input, formula = cbind(n_species, n_other) ~ main_habitat + (1 | taxon_name),
      sampling_group_col = "sampling_group", verbose = FALSE
    )),
    "nothing to separate"
  )
})

test_that("one group's fitting failure doesn't crash the whole call (Session 149)", {
  # Found via real-data testing against real PtConception 18S occurrences:
  # a group whose records all share one habitat level degenerates the
  # habitat fixed effect ("contrasts can be applied only to factors with 2
  # or more levels") inside train_biodiversity_model(). Before the tryCatch
  # fix, this crashed train_biodiversity_model_by_group() entirely, losing
  # every other group's (perfectly fittable) result too.
  input <- .make_grouped_raw_occurrences()
  # Collapse the vertebrate group onto a single habitat value only.
  input$main_habitat[input$sampling_group == "vertebrate"] <- "Kelp"
  formula <- cbind(n_species, n_other) ~ main_habitat + (1 | taxon_name)

  expect_warning(
    models <- suppressMessages(
      train_biodiversity_model_by_group(
        input, formula = formula, sampling_group_col = "sampling_group",
        verbose = FALSE
      )
    ),
    "vertebrate"
  )

  expect_setequal(names(models), "phytoplankton")
  expect_true(inherits(models$phytoplankton, "biofreq_model"))
})

test_that("train_biodiversity_model() itself refuses multi-group data", {
  input <- .make_grouped_raw_occurrences()
  model_df <- suppressWarnings(prepare_model_dataframe(
    input, sampling_group_col = "sampling_group"
  ))
  expect_error(
    train_biodiversity_model(
      model_df, formula = cbind(n_species, n_other) ~ main_habitat + (1 | taxon_name)
    ),
    "sampling groups"
  )
})
