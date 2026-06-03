# test-assign_taxa_llm.R

# Minimal match_df for testing -- 2 samples, 3 candidates each
make_match_df <- function() {
  data.frame(
    observation_id        = c("S1","S1","S1","S2","S2","S2"),
    score_original   = c(99, 93, 85,   100, 88, 82),
    taxon_name       = c("Eucyclogobius newberryi", "Quietula y-cauda",
                         "Gillichthys mirabilis",
                         "Eucyclogobius newberryi", "Clevelandia ios",
                         "Gillichthys mirabilis"),
    taxon_name_rank  = rep("species", 6),
    testid           = rep("MiFishU", 6),
    stringsAsFactors = FALSE
  )
}

# ---- Stub llm_fn -----------------------------------------------------------
# Parses taxon names from "- X (rank)" lines and returns a flat JSON array
# with range_status = "native" and equal prior_weights.
stub_llm <- function(prompt_str) {
  taxa <- regmatches(prompt_str,
                     gregexpr("(?m)(?<=^- )[^\n(]+(?= \\()", prompt_str,
                               perl = TRUE))[[1]]
  taxa <- trimws(taxa)
  if (length(taxa) == 0) taxa <- "Eucyclogobius newberryi"
  rows <- paste0(
    vapply(taxa, function(t)
      sprintf('{"taxon_name":"%s","range_status":"native","prior_weight":1}', t),
      character(1)),
    collapse = ",\n  "
  )
  paste0("[\n  ", rows, "\n]")
}

# Returns broken JSON
broken_llm <- function(prompt_str) "not valid json at all!!!"

# Errors on every call
error_llm <- function(prompt_str) stop("API unavailable")


# ---- Core correctness -------------------------------------------------------

test_that("returns a data frame with required columns", {
  result <- assign_taxa_llm(make_match_df(), llm_fn = stub_llm, pause_seconds = 0)
  expect_s3_class(result, "data.frame")
  expected_cols <- c("observation_id", "taxon_name", "taxon_name_rank",
                     "score_likelihood", "score_likelihood_mean", "score_likelihood_sd",
                     "prior_mean",
                     "posterior_point_est", "posterior_mean", "posterior_sd",
                     "confidence_score")
  expect_true(all(expected_cols %in% names(result)))
})

test_that("posteriors per observation_id sum to 1", {
  result <- assign_taxa_llm(make_match_df(), llm_fn = stub_llm, pause_seconds = 0)
  totals <- tapply(result$posterior_point_est, result$observation_id, sum)
  expect_equal(as.vector(totals), c(1, 1), tolerance = 1e-9)
})

test_that("unreferenced_family row is present for each observation_id", {
  result <- assign_taxa_llm(make_match_df(), llm_fn = stub_llm, pause_seconds = 0)
  unk <- result[result$hypothesis_type == "unreferenced_family", ]
  expect_equal(nrow(unk), 2)
})

test_that("score_threshold filters candidates", {
  # Threshold 95 keeps only S1 score-99 and S2 score-100 -> 1 named candidate + unknown
  result <- assign_taxa_llm(make_match_df(), llm_fn = stub_llm,
                             score_threshold = 95, pause_seconds = 0)
  taxon_counts <- table(result$observation_id)
  expect_true(all(taxon_counts == 2))
})

test_that("score_sharpness = 0 gives uniform likelihoods for named candidates", {
  result <- assign_taxa_llm(make_match_df(), llm_fn = stub_llm,
                             score_sharpness = 0, score_threshold = 0,
                             pause_seconds = 0)
  s1 <- result[result$observation_id == "S1" & !is.na(result$taxon_name), ]
  expect_equal(length(unique(round(s1$score_likelihood, 10))), 1)
})

# ---- LLM call count ---------------------------------------------------------

test_that("one LLM call is made when taxa fit in one batch", {
  calls <- 0L
  counting_llm <- function(p) { calls <<- calls + 1L; stub_llm(p) }
  # make_match_df has 4 unique named taxa -- well under default taxa_per_call
  assign_taxa_llm(make_match_df(), llm_fn = counting_llm, pause_seconds = 0)
  expect_equal(calls, 1L)
})

test_that("taxa_per_call splits taxon list into multiple calls", {
  calls <- 0L
  counting_llm <- function(p) { calls <<- calls + 1L; stub_llm(p) }
  # 4 unique taxa, taxa_per_call = 2 -> 2 calls
  assign_taxa_llm(make_match_df(), llm_fn = counting_llm,
                  taxa_per_call = 2, pause_seconds = 0)
  expect_equal(calls, 2L)
})

test_that("posteriors sum to 1 with taxa_per_call batching", {
  result <- assign_taxa_llm(make_match_df(), llm_fn = stub_llm,
                             taxa_per_call = 2, pause_seconds = 0)
  totals <- tapply(result$posterior_point_est, result$observation_id, sum)
  expect_equal(as.vector(totals), c(1, 1), tolerance = 1e-9)
})

test_that("context_group creates one LLM call per unique group", {
  calls <- 0L
  counting_llm <- function(p) { calls <<- calls + 1L; stub_llm(p) }
  ctx <- data.frame(observation_id = c("S1", "S2"),
                    ecoregion = c("Region A", "Region B"),
                    stringsAsFactors = FALSE)
  assign_taxa_llm(make_match_df(), context = ctx, context_group = "ecoregion",
                  llm_fn = counting_llm, pause_seconds = 0)
  expect_equal(calls, 2L)
})

test_that("shared context_group makes one LLM call", {
  calls <- 0L
  counting_llm <- function(p) { calls <<- calls + 1L; stub_llm(p) }
  ctx <- data.frame(observation_id = c("S1", "S2"),
                    ecoregion = c("Same Region", "Same Region"),
                    stringsAsFactors = FALSE)
  assign_taxa_llm(make_match_df(), context = ctx, context_group = "ecoregion",
                  llm_fn = counting_llm, pause_seconds = 0)
  expect_equal(calls, 1L)
})

test_that("posteriors sum to 1 for each sample when context_group creates two groups", {
  ctx <- data.frame(observation_id = c("S1", "S2"),
                    ecoregion = c("Region A", "Region B"),
                    stringsAsFactors = FALSE)
  result <- assign_taxa_llm(make_match_df(), context = ctx,
                             context_group = "ecoregion",
                             llm_fn = stub_llm, pause_seconds = 0)
  totals <- tapply(result$posterior_point_est, result$observation_id, sum)
  expect_equal(as.vector(totals), c(1, 1), tolerance = 1e-9)
})

# ---- Prompt content ---------------------------------------------------------

test_that("prompt contains all unique taxa across samples", {
  captured <- character(0)
  capture_llm <- function(p) { captured <<- p; stub_llm(p) }
  assign_taxa_llm(make_match_df(), llm_fn = capture_llm, pause_seconds = 0)
  # All four unique named taxa should appear in the single prompt
  expect_true(grepl("Eucyclogobius newberryi", captured, fixed = TRUE))
  expect_true(grepl("Gillichthys mirabilis",   captured, fixed = TRUE))
  expect_true(grepl("Quietula y-cauda",        captured, fixed = TRUE))
  expect_true(grepl("Clevelandia ios",         captured, fixed = TRUE))
})

test_that("prompt contains PRIOR WEIGHT RULES section", {
  captured <- character(0)
  capture_llm <- function(p) { captured <<- p; stub_llm(p) }
  assign_taxa_llm(make_match_df(), llm_fn = capture_llm, pause_seconds = 0)
  expect_true(grepl("PRIOR WEIGHT RULES", captured, fixed = TRUE))
  expect_true(grepl("range_status",       captured, fixed = TRUE))
  expect_true(grepl("introduced_established", captured, fixed = TRUE))
})

test_that("broadcast context appears in prompt", {
  captured <- character(0)
  capture_llm <- function(p) { captured <<- p; stub_llm(p) }
  ctx <- data.frame(ecoregion = "California Coast", habitat = "estuarine")
  assign_taxa_llm(make_match_df(), context = ctx, llm_fn = capture_llm,
                  pause_seconds = 0)
  expect_true(grepl("California Coast", captured, fixed = TRUE))
})

# ---- Fallback behaviour -----------------------------------------------------

test_that("broken JSON falls back to uniform prior with warning", {
  expect_warning(
    result <- assign_taxa_llm(make_match_df(), llm_fn = broken_llm,
                               pause_seconds = 0),
    regexp = "uniform prior|Failed to parse"
  )
  # Named taxa should all have equal prior (unreferenced_family is fixed separately)
  s1_named <- result[result$observation_id == "S1" & !is.na(result$taxon_name), ]
  expect_equal(length(unique(round(s1_named$prior_mean, 10))), 1)
})

test_that("erroring llm_fn falls back to uniform prior with warning", {
  expect_warning(
    result <- assign_taxa_llm(make_match_df(), llm_fn = error_llm,
                               pause_seconds = 0),
    regexp = "uniform|failed"
  )
  expect_s3_class(result, "data.frame")
  totals <- tapply(result$posterior_point_est, result$observation_id, sum)
  expect_equal(as.vector(totals), c(1, 1), tolerance = 1e-9)
})

# ---- Context handling -------------------------------------------------------

test_that("broadcast context (no observation_id col) works", {
  ctx <- data.frame(ecoregion = "California Coast", habitat = "estuarine")
  result <- assign_taxa_llm(make_match_df(), context = ctx, llm_fn = stub_llm,
                             pause_seconds = 0)
  expect_s3_class(result, "data.frame")
})

test_that("per-sample context (with observation_id col) works", {
  ctx <- data.frame(observation_id = c("S1", "S2"),
                    ecoregion = c("California Coast", "California Coast"),
                    stringsAsFactors = FALSE)
  result <- assign_taxa_llm(make_match_df(), context = ctx, llm_fn = stub_llm,
                             pause_seconds = 0)
  expect_s3_class(result, "data.frame")
})

# ---- Geographic reasoning ---------------------------------------------------

test_that("range_status column is present in output", {
  result <- assign_taxa_llm(make_match_df(), llm_fn = stub_llm, pause_seconds = 0)
  expect_true("range_status" %in% names(result))
})

test_that("range_status is populated for taxa the LLM returned", {
  result <- assign_taxa_llm(make_match_df(), llm_fn = stub_llm, pause_seconds = 0)
  named_filled <- result[!is.na(result$taxon_name) &
                           !is.na(result$range_status), ]
  expect_true(all(named_filled$range_status == "native"))
  unk <- result[result$hypothesis_type == "unreferenced_family", ]
  expect_true(all(unk$range_status == "unknown"))
})

test_that("range_status is NA for named taxa when LLM falls back to uniform prior", {
  result <- suppressWarnings(
    assign_taxa_llm(make_match_df(), llm_fn = broken_llm, pause_seconds = 0)
  )
  named_rows <- result[!is.na(result$taxon_name), ]
  expect_true(all(is.na(named_rows$range_status)))
})

# ---- Input validation -------------------------------------------------------

test_that("invalid match_df raises informative error", {
  expect_error(assign_taxa_llm(data.frame(x = 1), llm_fn = stub_llm),
               regexp = "missing required")
})

test_that("all-equal scores do not trigger NaN from exp overflow", {
  df <- make_match_df()
  df$score_original <- 100
  expect_no_error(assign_taxa_llm(df, llm_fn = stub_llm, pause_seconds = 0))
})

# ---- Unreferenced taxa -------------------------------------------------------------

test_that("unreferenced congener appears in output and is marked unreferenced_species", {
  result <- assign_taxa_llm(make_match_df(), llm_fn = stub_llm,
                             unreferenced_taxa = "Eucyclogobius pattersoni",
                             pause_seconds = 0)
  unref_rows <- result[!is.na(result$taxon_name) &
                         result$taxon_name == "Eucyclogobius pattersoni", ]
  expect_equal(nrow(unref_rows), 2)
  expect_true(all(unref_rows$hypothesis_type == "unreferenced_species"))
})

test_that("unreferenced species from unrelated genus is excluded", {
  result <- assign_taxa_llm(make_match_df(), llm_fn = stub_llm,
                             unreferenced_taxa = "Salmo salar",
                             pause_seconds = 0)
  expect_false("Salmo salar" %in% result$taxon_name)
})

test_that("posteriors sum to 1 with unreferenced taxa", {
  result <- assign_taxa_llm(make_match_df(), llm_fn = stub_llm,
                             unreferenced_taxa = "Eucyclogobius pattersoni",
                             pause_seconds = 0)
  totals <- tapply(result$posterior_point_est, result$observation_id, sum)
  expect_equal(as.vector(totals), c(1, 1), tolerance = 1e-9)
})

test_that("unreferenced species likelihood equals median of referenced congener likelihoods", {
  result <- assign_taxa_llm(make_match_df(), llm_fn = stub_llm,
                             unreferenced_taxa = "Eucyclogobius pattersoni",
                             pause_seconds = 0)
  # Eucyclogobius newberryi is the only referenced Eucyclogobius --
  # unreferenced species gets the same pre-normalization exp-score, so equal likelihood
  s1 <- result[result$observation_id == "S1" & !is.na(result$taxon_name), ]
  unref_lik <- s1$score_likelihood[s1$taxon_name == "Eucyclogobius pattersoni"]
  newb_lik  <- s1$score_likelihood[s1$taxon_name == "Eucyclogobius newberryi"]
  expect_equal(unref_lik, newb_lik, tolerance = 1e-9)
})

test_that("unreferenced species already in candidates is not duplicated", {
  result <- assign_taxa_llm(make_match_df(), llm_fn = stub_llm,
                             unreferenced_taxa = "Eucyclogobius newberryi",
                             pause_seconds = 0)
  n_rows <- sum(result$observation_id == "S1" &
                  !is.na(result$taxon_name) &
                  result$taxon_name == "Eucyclogobius newberryi")
  expect_equal(n_rows, 1L)
})

test_that("prompt contains [no reference sequence] label for unreferenced species", {
  captured <- character(0)
  capture_llm <- function(p) { captured <<- p; stub_llm(p) }
  assign_taxa_llm(make_match_df(), llm_fn = capture_llm,
                  unreferenced_taxa = "Eucyclogobius pattersoni",
                  pause_seconds = 0)
  expect_true(grepl("no reference sequence", captured, fixed = TRUE))
})

# ---- Family-level unreferenced taxa -----------------------------------------
# match_df with genus/family columns; all candidates in Gobiidae

make_match_df_taxon <- function() {
  data.frame(
    observation_id       = c("S1", "S1", "S1"),
    score_original  = c(99, 93, 85),
    taxon_name      = c("Eucyclogobius newberryi", "Quietula y-cauda",
                        "Gillichthys mirabilis"),
    taxon_name_rank = rep("species", 3),
    family          = rep("Gobiidae", 3),
    genus           = c("Eucyclogobius", "Quietula", "Gillichthys"),
    testid          = rep("MiFishU", 3),
    stringsAsFactors = FALSE
  )
}

# Helper: build a minimal unreferenced_species_result with unreferenced_family attribute
make_fam_unref <- function(species, family_name) {
  gfm <- stats::setNames(rep(family_name, length(species)), species)
  structure(
    species,
    unreferenced_family  = gfm,
    plausible     = list(),
    census        = data.frame(),
    family_census = NULL,
    class         = c("unreferenced_species_result", "character")
  )
}

test_that("family-level unreferenced taxon (genus absent, family present) appears in output as unreferenced_genus", {
  # Gobioides genus not in candidates; Gobiidae IS represented
  unreferenced_taxa <- make_fam_unref("Gobioides broussonnetii", "Gobiidae")
  result <- assign_taxa_llm(make_match_df_taxon(), llm_fn = stub_llm,
                             unreferenced_taxa = unreferenced_taxa, pause_seconds = 0)
  unref_rows <- result[!is.na(result$taxon_name) &
                         result$taxon_name == "Gobioides broussonnetii", ]
  expect_equal(nrow(unref_rows), 1L)
  expect_true(all(unref_rows$hypothesis_type == "unreferenced_genus"))
})

test_that("family-level unreferenced taxon from family absent in candidates is excluded", {
  # Centrarchidae not in candidates (Gobiidae only)
  unreferenced_taxa <- make_fam_unref("Lepomis macrochirus", "Centrarchidae")
  result <- assign_taxa_llm(make_match_df_taxon(), llm_fn = stub_llm,
                             unreferenced_taxa = unreferenced_taxa, pause_seconds = 0)
  expect_false("Lepomis macrochirus" %in% result$taxon_name)
})

test_that("posteriors sum to 1 with family-level unreferenced taxa", {
  unreferenced_taxa <- make_fam_unref("Gobioides broussonnetii", "Gobiidae")
  result <- assign_taxa_llm(make_match_df_taxon(), llm_fn = stub_llm,
                             unreferenced_taxa = unreferenced_taxa, pause_seconds = 0)
  total <- sum(result$posterior_point_est)
  expect_equal(total, 1, tolerance = 1e-9)
})

test_that("unreferenced species with genus in ref_genera is congener (unreferenced_species) even if in unreferenced_family_map", {
  # Eucyclogobius IS a ref genus -> goes through congener path, not family path
  unreferenced_taxa <- make_fam_unref("Eucyclogobius pattersoni", "Gobiidae")
  result <- assign_taxa_llm(make_match_df_taxon(), llm_fn = stub_llm,
                             unreferenced_taxa = unreferenced_taxa, pause_seconds = 0)
  unref_rows <- result[!is.na(result$taxon_name) &
                         result$taxon_name == "Eucyclogobius pattersoni", ]
  expect_equal(nrow(unref_rows), 1L)
  expect_true(all(unref_rows$hypothesis_type == "unreferenced_species"))
})

test_that("match_df without family column ignores unreferenced_family_map", {
  # make_match_df() has no family/genus columns -- should not error, family-level
  # unreferenced taxa are silently skipped, congener unreferenced taxa still work
  unreferenced_taxa <- make_fam_unref("Gobioides broussonnetii", "Gobiidae")
  result <- assign_taxa_llm(make_match_df(), llm_fn = stub_llm,
                             unreferenced_taxa = unreferenced_taxa, pause_seconds = 0)
  expect_s3_class(result, "data.frame")
  expect_false("Gobioides broussonnetii" %in% result$taxon_name)
})

test_that("family-level unreferenced taxon prompt label [no reference sequence] present", {
  captured <- character(0)
  capture_llm <- function(p) { captured <<- p; stub_llm(p) }
  unreferenced_taxa <- make_fam_unref("Gobioides broussonnetii", "Gobiidae")
  assign_taxa_llm(make_match_df_taxon(), llm_fn = capture_llm,
                  unreferenced_taxa = unreferenced_taxa, pause_seconds = 0)
  expect_true(grepl("no reference sequence", captured, fixed = TRUE))
})


# ---- known_present / known_absent -------------------------------------------

test_that("known_present appears in prompt under Survey context", {
  captured <- character(0)
  capture_llm <- function(p) { captured <<- p; stub_llm(p) }
  assign_taxa_llm(make_match_df(), llm_fn = capture_llm,
                  known_present = c("Acanthogobius flavimanus", "Tridentiger trigonocephalus"),
                  pause_seconds = 0)
  expect_true(grepl("Survey context", captured, fixed = TRUE))
  expect_true(grepl("Acanthogobius flavimanus", captured, fixed = TRUE))
})

test_that("known_absent appears in prompt under Survey context", {
  captured <- character(0)
  capture_llm <- function(p) { captured <<- p; stub_llm(p) }
  assign_taxa_llm(make_match_df(), llm_fn = capture_llm,
                  known_absent = "Gillichthys mirabilis",
                  pause_seconds = 0)
  expect_true(grepl("Confirmed absent", captured, fixed = TRUE))
  expect_true(grepl("Gillichthys mirabilis", captured, fixed = TRUE))
})

test_that("absent species prior is suppressed by (1 - detection_prob)", {
  # Gillichthys mirabilis is a candidate in make_match_df(); mark absent p=0.9
  result_plain   <- assign_taxa_llm(make_match_df(), llm_fn = stub_llm,
                                     pause_seconds = 0)
  result_absent  <- assign_taxa_llm(make_match_df(), llm_fn = stub_llm,
                                     known_absent = data.frame(
                                       taxon_name     = "Gillichthys mirabilis",
                                       detection_prob = 0.9
                                     ),
                                     pause_seconds = 0)
  s1_plain  <- result_plain[result_plain$observation_id  == "S1" &
                              !is.na(result_plain$taxon_name) &
                              result_plain$taxon_name == "Gillichthys mirabilis", ]
  s1_absent <- result_absent[result_absent$observation_id  == "S1" &
                               !is.na(result_absent$taxon_name) &
                               result_absent$taxon_name == "Gillichthys mirabilis", ]
  expect_lt(s1_absent$prior_mean, s1_plain$prior_mean)
})

test_that("absent species prior suppression scales with detection_prob", {
  make_result <- function(pd) {
    assign_taxa_llm(make_match_df(), llm_fn = stub_llm,
                    known_absent = data.frame(taxon_name = "Gillichthys mirabilis",
                                              detection_prob = pd),
                    pause_seconds = 0)
  }
  r50 <- make_result(0.50)
  r90 <- make_result(0.90)
  # higher detection_prob -> stronger suppression -> lower prior
  p50 <- r50[r50$observation_id == "S1" & !is.na(r50$taxon_name) &
               r50$taxon_name == "Gillichthys mirabilis", "prior_mean"]
  p90 <- r90[r90$observation_id == "S1" & !is.na(r90$taxon_name) &
               r90$taxon_name == "Gillichthys mirabilis", "prior_mean"]
  expect_gt(p50, p90)
})

test_that("posteriors still sum to 1 after absence suppression", {
  result <- assign_taxa_llm(make_match_df(), llm_fn = stub_llm,
                             known_absent = "Gillichthys mirabilis",
                             pause_seconds = 0)
  totals <- tapply(result$posterior_point_est, result$observation_id, sum)
  expect_equal(as.vector(totals), c(1, 1), tolerance = 1e-9)
})

test_that("absent species not in candidates is silently ignored in suppression", {
  # Salmo salar is not in make_match_df(); should not error
  expect_no_error(
    assign_taxa_llm(make_match_df(), llm_fn = stub_llm,
                    known_absent = "Salmo salar",
                    pause_seconds = 0)
  )
})

test_that("known_absent as plain character vector uses absent_detection_prob default", {
  r_default  <- assign_taxa_llm(make_match_df(), llm_fn = stub_llm,
                                 known_absent          = "Gillichthys mirabilis",
                                 absent_detection_prob = 0.80,
                                 pause_seconds = 0)
  r_explicit <- assign_taxa_llm(make_match_df(), llm_fn = stub_llm,
                                 known_absent = data.frame(
                                   taxon_name     = "Gillichthys mirabilis",
                                   detection_prob = 0.80
                                 ),
                                 pause_seconds = 0)
  p_default  <- r_default[r_default$observation_id   == "S1" &
                            r_default$taxon_name  == "Gillichthys mirabilis", "prior_mean"]
  p_explicit <- r_explicit[r_explicit$observation_id  == "S1" &
                             r_explicit$taxon_name == "Gillichthys mirabilis", "prior_mean"]
  expect_equal(p_default, p_explicit, tolerance = 1e-12)
})

test_that("invalid known_present raises error", {
  expect_error(
    assign_taxa_llm(make_match_df(), llm_fn = stub_llm,
                    known_present = 42, pause_seconds = 0),
    regexp = "character"
  )
})

test_that("known_absent data frame without taxon_name column raises error", {
  expect_error(
    assign_taxa_llm(make_match_df(), llm_fn = stub_llm,
                    known_absent = data.frame(species = "Foo bar"),
                    pause_seconds = 0),
    regexp = "taxon_name"
  )
})
