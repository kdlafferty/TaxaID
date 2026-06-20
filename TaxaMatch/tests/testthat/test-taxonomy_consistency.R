test_that("barnacle example: lowest_consistent_rank = order", {
  m <- data.frame(
    observation_id = rep("obs1", 4),
    order   = rep("Sessilia", 4),
    family  = c("Balanidae", "Archaeobalanidae", "Balanidae", "Chthamalidae"),
    genus   = c("Amphibalanus", "Semibalanus", "Balanus", "Chthamalus"),
    species = c("Amphibalanus improvisus", "Semibalanus balanoides",
                "Balanus balanus", "Chthamalus fragilis")
  )
  out <- add_lowest_consistent_rank(m, rank_system = c("order", "family", "genus", "species"))
  expect_true("lowest_consistent_rank" %in% names(out))
  expect_equal(unique(out$lowest_consistent_rank), "order")
})

test_that("all ranks consistent: finest rank returned", {
  m <- data.frame(
    observation_id = rep("obs1", 2),
    family  = rep("Balanidae", 2),
    genus   = rep("Amphibalanus", 2),
    species = rep("Amphibalanus improvisus", 2)
  )
  out <- add_lowest_consistent_rank(m, rank_system = c("family", "genus", "species"))
  expect_equal(unique(out$lowest_consistent_rank), "species")
})

test_that("all ranks inconsistent: NA returned", {
  m <- data.frame(
    observation_id = rep("obs1", 2),
    family  = c("Balanidae", "Chthamalidae"),
    genus   = c("Balanus", "Chthamalus"),
    species = c("Balanus balanus", "Chthamalus fragilis")
  )
  out <- add_lowest_consistent_rank(m, rank_system = c("family", "genus", "species"))
  expect_true(is.na(unique(out$lowest_consistent_rank)))
})

test_that("single-row observation: finest rank returned", {
  m <- data.frame(
    observation_id = "obs1",
    family  = "Salmonidae",
    genus   = "Salmo",
    species = "Salmo salar"
  )
  out <- add_lowest_consistent_rank(m, rank_system = c("family", "genus", "species"))
  expect_equal(out$lowest_consistent_rank, "species")
})

test_that("NA values ignored by default (na_as_inconsistent = FALSE)", {
  m <- data.frame(
    observation_id = rep("obs1", 3),
    family  = c("Balanidae", "Balanidae", NA),
    genus   = c("Amphibalanus", "Amphibalanus", NA),
    species = c("Amphibalanus improvisus", "Amphibalanus improvisus", NA)
  )
  out <- add_lowest_consistent_rank(m, rank_system = c("family", "genus", "species"))
  # NAs ignored: all non-NA values identical → species is consistent
  expect_equal(unique(out$lowest_consistent_rank), "species")
})

test_that("NA values inconsistent when na_as_inconsistent = TRUE", {
  m <- data.frame(
    observation_id = rep("obs1", 3),
    family  = c("Balanidae", "Balanidae", NA),
    genus   = c("Amphibalanus", "Amphibalanus", NA),
    species = c("Amphibalanus improvisus", "Amphibalanus improvisus", NA)
  )
  out <- add_lowest_consistent_rank(m, rank_system = c("family", "genus", "species"),
                                     na_as_inconsistent = TRUE)
  # NA treated as distinct: species and genus inconsistent; family has non-NA "Balanidae" + NA → inconsistent
  expect_true(is.na(unique(out$lowest_consistent_rank)))
})

test_that("multiple observations handled independently", {
  m <- data.frame(
    observation_id = c(rep("obs1", 2), rep("obs2", 2)),
    family  = c("Balanidae", "Chthamalidae", "Salmonidae", "Salmonidae"),
    genus   = c("Balanus", "Chthamalus",    "Salmo",      "Salmo"),
    species = c("Balanus balanus", "Chthamalus fragilis",
                "Salmo salar",    "Salmo trutta")
  )
  out <- add_lowest_consistent_rank(m, rank_system = c("family", "genus", "species"))
  lcr <- tapply(out$lowest_consistent_rank, out$observation_id, unique)
  expect_true(is.na(lcr[["obs1"]]))     # obs1: all ranks inconsistent
  expect_equal(lcr[["obs2"]], "genus")  # obs2: family + genus consistent, species not
})

test_that("result broadcast to all rows of same observation", {
  m <- data.frame(
    observation_id = rep("obs1", 3),
    family  = rep("Balanidae", 3),
    genus   = c("A", "A", "B"),
    species = c("A a", "A b", "B c")
  )
  out <- add_lowest_consistent_rank(m, rank_system = c("family", "genus", "species"))
  expect_equal(length(unique(out$lowest_consistent_rank)), 1L)
  expect_equal(unique(out$lowest_consistent_rank), "family")
})

test_that("error on missing observation_id_col", {
  m <- data.frame(obs = "x", family = "Salmonidae")
  expect_error(
    add_lowest_consistent_rank(m, rank_system = "family", observation_id_col = "observation_id"),
    "not found"
  )
})

test_that("error when no rank_system columns found", {
  m <- data.frame(observation_id = "x", score = 99)
  expect_error(
    add_lowest_consistent_rank(m, rank_system = c("family", "genus")),
    "none of the rank_system columns"
  )
})

# ==============================================================================
# majority_threshold — majority mode
# ==============================================================================

test_that("majority mode: 4/5 agree on family → family is consistent, outlier flagged", {
  m <- data.frame(
    observation_id = rep("obs1", 5),
    family  = c("Balanidae", "Balanidae", "Balanidae", "Balanidae", "Chthamalidae"),
    genus   = c("Amphibalanus", "Balanus", "Semibalanus", "Tetraclita", "Chthamalus"),
    species = c("Amphibalanus improvisus", "Balanus balanus",
                "Semibalanus balanoides", "Tetraclita rubescens",
                "Chthamalus fragilis")
  )
  out <- add_lowest_consistent_rank(
    m,
    rank_system        = c("family", "genus", "species"),
    majority_threshold = 0.8
  )
  expect_equal(unique(out$lowest_consistent_rank), "family")
  expect_equal(unique(out$rank_majority_value),    "Balanidae")
  expect_equal(unique(out$rank_majority_fraction), 0.8)
  # Only the Chthamalidae row is an outlier
  expect_equal(sum(out$is_rank_outlier), 1L)
  expect_true(out$is_rank_outlier[out$family == "Chthamalidae"])
  expect_true(all(!out$is_rank_outlier[out$family == "Balanidae"]))
})

test_that("majority mode: 3/5 agree — below threshold 0.8, falls back to coarser rank", {
  m <- data.frame(
    observation_id = rep("obs1", 5),
    order  = rep("Sessilia", 5),
    family = c("Balanidae", "Balanidae", "Balanidae", "Chthamalidae", "Chthamalidae"),
    genus  = c("Amphibalanus", "Balanus", "Semibalanus", "Chthamalus", "Euraphia")
  )
  out <- add_lowest_consistent_rank(
    m,
    rank_system        = c("order", "family", "genus"),
    majority_threshold = 0.8
  )
  # 3/5 = 0.6 < 0.8 → family not consistent; order is consistent (100%)
  expect_equal(unique(out$lowest_consistent_rank), "order")
  expect_false(any(out$is_rank_outlier))
})

test_that("majority mode: unanimous agreement → is_rank_outlier all FALSE", {
  m <- data.frame(
    observation_id = rep("obs1", 3),
    family  = rep("Salmonidae", 3),
    genus   = rep("Salmo", 3),
    species = rep("Salmo salar", 3)
  )
  out <- add_lowest_consistent_rank(
    m,
    rank_system        = c("family", "genus", "species"),
    majority_threshold = 0.8
  )
  expect_equal(unique(out$lowest_consistent_rank), "species")
  expect_true(all(!out$is_rank_outlier))
  expect_equal(unique(out$rank_majority_fraction), 1.0)
})

test_that("majority mode: NA rows are not flagged as outliers", {
  m <- data.frame(
    observation_id = rep("obs1", 5),
    family  = c("Balanidae", "Balanidae", "Balanidae", "Balanidae", NA),
    genus   = c("Amphibalanus", "Balanus", "Semibalanus", "Tetraclita", NA),
    species = c("Amphibalanus improvisus", "Balanus balanus",
                "Semibalanus balanoides", "Tetraclita rubescens", NA)
  )
  out <- add_lowest_consistent_rank(
    m,
    rank_system        = c("family", "genus", "species"),
    majority_threshold = 0.8
  )
  # 4 non-NA values all agree → family consistent (4/4 = 1.0)
  expect_equal(unique(out$lowest_consistent_rank), "family")
  # NA row has no value to contradict — not an outlier
  expect_false(out$is_rank_outlier[is.na(m$family)])
})

test_that("majority mode: no consistent rank → is_rank_outlier all FALSE", {
  m <- data.frame(
    observation_id = rep("obs1", 4),
    family = c("Balanidae", "Balanidae", "Chthamalidae", "Chthamalidae"),
    genus  = c("Balanus",   "Amphibalanus", "Chthamalus", "Euraphia")
  )
  out <- add_lowest_consistent_rank(
    m,
    rank_system        = c("family", "genus"),
    majority_threshold = 0.8
  )
  # 2/4 = 0.5 < 0.8 at every rank → lowest_consistent_rank = NA
  expect_true(is.na(unique(out$lowest_consistent_rank)))
  expect_true(all(!out$is_rank_outlier))
  expect_true(all(is.na(out$rank_majority_value)))
})

test_that("majority mode: multiple observations handled independently", {
  m <- data.frame(
    observation_id = c(rep("obs1", 5), rep("obs2", 3)),
    family = c("Balanidae", "Balanidae", "Balanidae", "Balanidae", "Chthamalidae",
               "Salmonidae", "Salmonidae", "Salmonidae")
  )
  out <- add_lowest_consistent_rank(
    m,
    rank_system        = "family",
    majority_threshold = 0.8
  )
  obs1_rows <- out[out$observation_id == "obs1", ]
  obs2_rows <- out[out$observation_id == "obs2", ]
  expect_equal(unique(obs1_rows$lowest_consistent_rank), "family")
  expect_equal(sum(obs1_rows$is_rank_outlier), 1L)  # the Chthamalidae row
  expect_equal(unique(obs2_rows$lowest_consistent_rank), "family")
  expect_false(any(obs2_rows$is_rank_outlier))
})

test_that("strict mode (NULL threshold): majority columns not added", {
  m <- data.frame(
    observation_id = rep("obs1", 2),
    family = rep("Balanidae", 2)
  )
  out <- add_lowest_consistent_rank(m, rank_system = "family")
  expect_false("is_rank_outlier"        %in% names(out))
  expect_false("rank_majority_value"    %in% names(out))
  expect_false("rank_majority_fraction" %in% names(out))
})

test_that("error on invalid majority_threshold", {
  m <- data.frame(observation_id = "x", family = "Balanidae")
  expect_error(
    add_lowest_consistent_rank(m, rank_system = "family", majority_threshold = 0),
    "majority_threshold"
  )
  expect_error(
    add_lowest_consistent_rank(m, rank_system = "family", majority_threshold = 1.5),
    "majority_threshold"
  )
  expect_error(
    add_lowest_consistent_rank(m, rank_system = "family", majority_threshold = NA_real_),
    "majority_threshold"
  )
})

# ==============================================================================
# auto-detect rank_system from column names
# ==============================================================================

test_that("auto-detects rank_system from column names", {
  m <- data.frame(
    observation_id = rep("obs1", 2),
    family  = rep("Salmonidae", 2),
    genus   = c("Salmo", "Oncorhynchus"),
    species = c("Salmo salar", "Oncorhynchus mykiss")
  )
  out <- add_lowest_consistent_rank(m)  # rank_system = NULL
  expect_equal(unique(out$lowest_consistent_rank), "family")
})
