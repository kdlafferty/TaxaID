# Tests for unreferenced_candidates()

.make_uc_match <- function() {
  data.frame(
    observation_id  = c("ESV_001", "ESV_001", "ESV_001", "ESV_002"),
    score_original  = c(95.0, 80.0, 60.0, 70.0),
    taxon_name      = c("Hybognathus nuchalis", "Rhinichthys obtusus",
                        "Campostoma anomalum", "Cottus carolinae"),
    taxon_name_rank = "species",
    family          = c("Leuciscidae", "Leuciscidae", "Leuciscidae", "Cottidae"),
    genus           = c("Hybognathus", "Rhinichthys", "Campostoma", "Cottus"),
    species         = c("Hybognathus nuchalis", "Rhinichthys obtusus",
                        "Campostoma anomalum", "Cottus carolinae"),
    stringsAsFactors = FALSE
  )
}

# ---- basic structure --------------------------------------------------------

test_that("returns data frame with hypothesis_type column", {
  out <- unreferenced_candidates(.make_uc_match(),
                                 rank_system = c("family", "genus", "species"))
  expect_true(is.data.frame(out))
  expect_true("hypothesis_type" %in% names(out))
})

test_that("original rows are labeled specific_candidate", {
  out <- unreferenced_candidates(.make_uc_match(),
                                 rank_system = c("family", "genus", "species"))
  n_orig <- nrow(.make_uc_match())
  expect_equal(sum(out$hypothesis_type == "specific_candidate"), n_orig)
})

test_that("adds unreferenced_species and unreferenced_genus rows", {
  out <- unreferenced_candidates(.make_uc_match(),
                                 rank_system = c("family", "genus", "species"))
  expect_true("unreferenced_species" %in% out$hypothesis_type)
  expect_true("unreferenced_genus"   %in% out$hypothesis_type)
})

test_that("one H2 and one H3 per observation when no H4", {
  out <- unreferenced_candidates(.make_uc_match(),
                                 rank_system = c("family", "genus", "species"))
  n_obs <- length(unique(.make_uc_match()$observation_id))
  expect_equal(sum(out$hypothesis_type == "unreferenced_species"), n_obs)
  expect_equal(sum(out$hypothesis_type == "unreferenced_genus"),   n_obs)
})

test_that("added rows have score_original = NA", {
  out <- unreferenced_candidates(.make_uc_match(),
                                 rank_system = c("family", "genus", "species"))
  added <- out[out$hypothesis_type != "specific_candidate", ]
  expect_true(all(is.na(added$score_original)))
})

# ---- H4 (unreferenced_family) -----------------------------------------------

test_that("no H4 rows by default", {
  out <- unreferenced_candidates(.make_uc_match(),
                                 rank_system = c("family", "genus", "species"))
  expect_false("unreferenced_family" %in% out$hypothesis_type)
})

test_that("H4 rows added when include_unreferenced_family = TRUE", {
  out <- unreferenced_candidates(.make_uc_match(),
                                 rank_system = c("family", "genus", "species"),
                                 include_unreferenced_family = TRUE)
  expect_true("unreferenced_family" %in% out$hypothesis_type)
  n_obs <- length(unique(.make_uc_match()$observation_id))
  expect_equal(sum(out$hypothesis_type == "unreferenced_family"), n_obs)
})

test_that("H4 rows have all rank columns and taxon_name NA", {
  out <- unreferenced_candidates(.make_uc_match(),
                                 rank_system = c("family", "genus", "species"),
                                 include_unreferenced_family = TRUE)
  h4 <- out[out$hypothesis_type == "unreferenced_family", ]
  expect_true(all(is.na(h4$family)))
  expect_true(all(is.na(h4$genus)))
  expect_true(all(is.na(h4$species)))
  expect_true(all(is.na(h4$taxon_name)))
})

# ---- anchor selection -------------------------------------------------------

test_that("H2 anchor uses best-scoring candidate's genus", {
  out <- unreferenced_candidates(.make_uc_match(),
                                 rank_system = c("family", "genus", "species"))
  h2_obs1 <- out[out$hypothesis_type == "unreferenced_species" &
                   out$observation_id == "ESV_001", ]
  # Best candidate is Hybognathus nuchalis (score 95); genus = Hybognathus
  expect_equal(h2_obs1$genus, "Hybognathus")
  expect_true(is.na(h2_obs1$species))
})

# ---- auto-detection ---------------------------------------------------------

test_that("rank_system auto-detected when NULL", {
  # Suppress the auto-detect message
  expect_message(
    out <- unreferenced_candidates(.make_uc_match()),
    "detected rank_system"
  )
  expect_true("unreferenced_species" %in% out$hypothesis_type)
})

# ---- validation errors ------------------------------------------------------

test_that("stops on non-data-frame input", {
  expect_error(unreferenced_candidates("notadf"), "must be a data frame")
})

test_that("stops when required columns missing", {
  bad <- data.frame(x = 1)
  expect_error(unreferenced_candidates(bad, rank_system = c("genus", "species")),
               "missing required column")
})

test_that("stops when rank_system has < 2 ranks", {
  expect_error(
    unreferenced_candidates(.make_uc_match(), rank_system = "species"),
    "at least 2 ranks"
  )
})

# ---- no-score input ---------------------------------------------------------

test_that("works without score_original column", {
  df <- .make_uc_match()
  df$score_original <- NULL
  out <- unreferenced_candidates(df, rank_system = c("family", "genus", "species"))
  expect_true("unreferenced_species" %in% out$hypothesis_type)
})

# ---- pre-labeled hypothesis_type preserved ----------------------------------

test_that("existing hypothesis_type labels are preserved", {
  df <- .make_uc_match()
  df$hypothesis_type <- "specific_candidate"
  out <- unreferenced_candidates(df, rank_system = c("family", "genus", "species"))
  expect_equal(
    sum(out$hypothesis_type == "specific_candidate"),
    nrow(df)
  )
})
