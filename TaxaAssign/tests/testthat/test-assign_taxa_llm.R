# test-assign_taxa_llm.R

# Minimal match_df for testing -- 2 samples, 3 candidates each
make_match_df <- function() {
  data.frame(
    observation_id = c("S1", "S1", "S1", "S2", "S2", "S2"),
    score_original = c(99, 93, 85, 100, 88, 82),
    taxon_name = c(
      "Eucyclogobius newberryi", "Quietula y-cauda",
      "Gillichthys mirabilis",
      "Eucyclogobius newberryi", "Clevelandia ios",
      "Gillichthys mirabilis"
    ),
    taxon_name_rank = rep("species", 6),
    testid = rep("MiFishU", 6),
    stringsAsFactors = FALSE
  )
}

# ---- Stub llm_fn -----------------------------------------------------------
# Parses taxon names from "- X (rank)" lines and returns a flat JSON array
# with range_status = "native" and equal prior_weights.
stub_llm <- function(prompt_str) {
  taxa <- regmatches(
    prompt_str,
    gregexpr("(?m)(?<=^- )[^\n(]+(?= \\()", prompt_str,
      perl = TRUE
    )
  )[[1]]
  taxa <- trimws(taxa)
  if (length(taxa) == 0) taxa <- "Eucyclogobius newberryi"
  rows <- paste0(
    vapply(
      taxa, function(t) {
        sprintf('{"taxon_name":"%s","range_status":"native","prior_weight":1}', t)
      },
      character(1)
    ),
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
  expected_cols <- c(
    "observation_id", "taxon_name", "taxon_name_rank",
    "score_likelihood", "score_likelihood_mean", "score_likelihood_sd",
    "prior_mean",
    "posterior_point_est", "posterior_mean", "posterior_sd",
    "confidence_score"
  )
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
  result <- assign_taxa_llm(make_match_df(),
    llm_fn = stub_llm,
    score_threshold = 95, pause_seconds = 0
  )
  taxon_counts <- table(result$observation_id)
  expect_true(all(taxon_counts == 2))
})

test_that("score_sharpness = 0 gives uniform likelihoods for named candidates", {
  result <- assign_taxa_llm(make_match_df(),
    llm_fn = stub_llm,
    score_sharpness = 0, score_threshold = 0,
    pause_seconds = 0
  )
  s1 <- result[result$observation_id == "S1" & !is.na(result$taxon_name), ]
  expect_equal(length(unique(round(s1$score_likelihood, 10))), 1)
})

# ---- LLM call count ---------------------------------------------------------

test_that("one LLM call is made when taxa fit in one batch", {
  calls <- 0L
  counting_llm <- function(p) {
    calls <<- calls + 1L
    stub_llm(p)
  }
  # make_match_df has 4 unique named taxa -- well under default taxa_per_call
  assign_taxa_llm(make_match_df(), llm_fn = counting_llm, pause_seconds = 0)
  expect_equal(calls, 1L)
})

test_that("taxa_per_call splits taxon list into multiple calls", {
  calls <- 0L
  counting_llm <- function(p) {
    calls <<- calls + 1L
    stub_llm(p)
  }
  # 4 unique taxa, taxa_per_call = 2 -> 2 calls
  assign_taxa_llm(make_match_df(),
    llm_fn = counting_llm,
    taxa_per_call = 2, pause_seconds = 0
  )
  expect_equal(calls, 2L)
})

test_that("posteriors sum to 1 with taxa_per_call batching", {
  result <- assign_taxa_llm(make_match_df(),
    llm_fn = stub_llm,
    taxa_per_call = 2, pause_seconds = 0
  )
  totals <- tapply(result$posterior_point_est, result$observation_id, sum)
  expect_equal(as.vector(totals), c(1, 1), tolerance = 1e-9)
})

test_that("context_group creates one LLM call per unique group", {
  calls <- 0L
  counting_llm <- function(p) {
    calls <<- calls + 1L
    stub_llm(p)
  }
  ctx <- data.frame(
    observation_id = c("S1", "S2"),
    ecoregion = c("Region A", "Region B"),
    stringsAsFactors = FALSE
  )
  assign_taxa_llm(make_match_df(),
    context = ctx, context_group = "ecoregion",
    llm_fn = counting_llm, pause_seconds = 0
  )
  expect_equal(calls, 2L)
})

test_that("shared context_group makes one LLM call", {
  calls <- 0L
  counting_llm <- function(p) {
    calls <<- calls + 1L
    stub_llm(p)
  }
  ctx <- data.frame(
    observation_id = c("S1", "S2"),
    ecoregion = c("Same Region", "Same Region"),
    stringsAsFactors = FALSE
  )
  assign_taxa_llm(make_match_df(),
    context = ctx, context_group = "ecoregion",
    llm_fn = counting_llm, pause_seconds = 0
  )
  expect_equal(calls, 1L)
})

test_that("posteriors sum to 1 for each sample when context_group creates two groups", {
  ctx <- data.frame(
    observation_id = c("S1", "S2"),
    ecoregion = c("Region A", "Region B"),
    stringsAsFactors = FALSE
  )
  result <- assign_taxa_llm(make_match_df(),
    context = ctx,
    context_group = "ecoregion",
    llm_fn = stub_llm, pause_seconds = 0
  )
  totals <- tapply(result$posterior_point_est, result$observation_id, sum)
  expect_equal(as.vector(totals), c(1, 1), tolerance = 1e-9)
})

# ---- Prompt content ---------------------------------------------------------

test_that("prompt contains all unique taxa across samples", {
  captured <- character(0)
  capture_llm <- function(p) {
    captured <<- p
    stub_llm(p)
  }
  assign_taxa_llm(make_match_df(), llm_fn = capture_llm, pause_seconds = 0)
  # All four unique named taxa should appear in the single prompt
  expect_true(grepl("Eucyclogobius newberryi", captured, fixed = TRUE))
  expect_true(grepl("Gillichthys mirabilis", captured, fixed = TRUE))
  expect_true(grepl("Quietula y-cauda", captured, fixed = TRUE))
  expect_true(grepl("Clevelandia ios", captured, fixed = TRUE))
})

test_that("prompt contains PRIOR WEIGHT RULES section", {
  captured <- character(0)
  capture_llm <- function(p) {
    captured <<- p
    stub_llm(p)
  }
  assign_taxa_llm(make_match_df(), llm_fn = capture_llm, pause_seconds = 0)
  expect_true(grepl("PRIOR WEIGHT RULES", captured, fixed = TRUE))
  expect_true(grepl("range_status", captured, fixed = TRUE))
  expect_true(grepl("introduced_established", captured, fixed = TRUE))
})

test_that("broadcast context appears in prompt", {
  captured <- character(0)
  capture_llm <- function(p) {
    captured <<- p
    stub_llm(p)
  }
  ctx <- data.frame(ecoregion = "California Coast", habitat = "estuarine")
  assign_taxa_llm(make_match_df(),
    context = ctx, llm_fn = capture_llm,
    pause_seconds = 0
  )
  expect_true(grepl("California Coast", captured, fixed = TRUE))
})

# ---- Fallback behaviour -----------------------------------------------------

test_that("broken JSON falls back to uniform prior with warning", {
  expect_warning(
    result <- assign_taxa_llm(make_match_df(),
      llm_fn = broken_llm,
      pause_seconds = 0
    ),
    regexp = "uniform prior|Failed to parse"
  )
  # Named taxa should all have equal prior (unreferenced_family is fixed separately)
  s1_named <- result[result$observation_id == "S1" & !is.na(result$taxon_name), ]
  expect_equal(length(unique(round(s1_named$prior_mean, 10))), 1)
})

test_that("erroring llm_fn falls back to uniform prior with warning", {
  expect_warning(
    result <- assign_taxa_llm(make_match_df(),
      llm_fn = error_llm,
      pause_seconds = 0
    ),
    regexp = "uniform|failed"
  )
  expect_s3_class(result, "data.frame")
  totals <- tapply(result$posterior_point_est, result$observation_id, sum)
  expect_equal(as.vector(totals), c(1, 1), tolerance = 1e-9)
})

# ---- Context handling -------------------------------------------------------

test_that("broadcast context (no observation_id col) works", {
  ctx <- data.frame(ecoregion = "California Coast", habitat = "estuarine")
  result <- assign_taxa_llm(make_match_df(),
    context = ctx, llm_fn = stub_llm,
    pause_seconds = 0
  )
  expect_s3_class(result, "data.frame")
})

test_that("per-sample context (with observation_id col) works", {
  ctx <- data.frame(
    observation_id = c("S1", "S2"),
    ecoregion = c("California Coast", "California Coast"),
    stringsAsFactors = FALSE
  )
  result <- assign_taxa_llm(make_match_df(),
    context = ctx, llm_fn = stub_llm,
    pause_seconds = 0
  )
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
    regexp = "missing required"
  )
})

test_that("all-equal scores do not trigger NaN from exp overflow", {
  df <- make_match_df()
  df$score_original <- 100
  expect_no_error(assign_taxa_llm(df, llm_fn = stub_llm, pause_seconds = 0))
})

# ---- Unreferenced taxa -------------------------------------------------------------

test_that("unreferenced congener appears in output and is marked unreferenced_species", {
  result <- assign_taxa_llm(make_match_df(),
    llm_fn = stub_llm,
    unreferenced_taxa = "Eucyclogobius pattersoni",
    pause_seconds = 0
  )
  unref_rows <- result[!is.na(result$taxon_name) &
    result$taxon_name == "Eucyclogobius pattersoni", ]
  expect_equal(nrow(unref_rows), 2)
  expect_true(all(unref_rows$hypothesis_type == "unreferenced_species"))
})

test_that("unreferenced species from unrelated genus is excluded", {
  result <- assign_taxa_llm(make_match_df(),
    llm_fn = stub_llm,
    unreferenced_taxa = "Salmo salar",
    pause_seconds = 0
  )
  expect_false("Salmo salar" %in% result$taxon_name)
})

test_that("posteriors sum to 1 with unreferenced taxa", {
  result <- assign_taxa_llm(make_match_df(),
    llm_fn = stub_llm,
    unreferenced_taxa = "Eucyclogobius pattersoni",
    pause_seconds = 0
  )
  totals <- tapply(result$posterior_point_est, result$observation_id, sum)
  expect_equal(as.vector(totals), c(1, 1), tolerance = 1e-9)
})

test_that("unreferenced species likelihood equals median of referenced congener likelihoods", {
  result <- assign_taxa_llm(make_match_df(),
    llm_fn = stub_llm,
    unreferenced_taxa = "Eucyclogobius pattersoni",
    pause_seconds = 0
  )
  # Eucyclogobius newberryi is the only referenced Eucyclogobius --
  # unreferenced species gets the same pre-normalization exp-score, so equal likelihood
  s1 <- result[result$observation_id == "S1" & !is.na(result$taxon_name), ]
  unref_lik <- s1$score_likelihood[s1$taxon_name == "Eucyclogobius pattersoni"]
  newb_lik <- s1$score_likelihood[s1$taxon_name == "Eucyclogobius newberryi"]
  expect_equal(unref_lik, newb_lik, tolerance = 1e-9)
})

test_that("unreferenced species already in candidates is not duplicated", {
  result <- assign_taxa_llm(make_match_df(),
    llm_fn = stub_llm,
    unreferenced_taxa = "Eucyclogobius newberryi",
    pause_seconds = 0
  )
  n_rows <- sum(result$observation_id == "S1" &
    !is.na(result$taxon_name) &
    result$taxon_name == "Eucyclogobius newberryi")
  expect_equal(n_rows, 1L)
})

test_that("prompt contains [no reference sequence] label for unreferenced species", {
  captured <- character(0)
  capture_llm <- function(p) {
    captured <<- p
    stub_llm(p)
  }
  assign_taxa_llm(make_match_df(),
    llm_fn = capture_llm,
    unreferenced_taxa = "Eucyclogobius pattersoni",
    pause_seconds = 0
  )
  expect_true(grepl("no reference sequence", captured, fixed = TRUE))
})

# ---- Family-level unreferenced taxa -----------------------------------------
# match_df with genus/family columns; all candidates in Gobiidae

make_match_df_taxon <- function() {
  data.frame(
    observation_id = c("S1", "S1", "S1"),
    score_original = c(99, 93, 85),
    taxon_name = c(
      "Eucyclogobius newberryi", "Quietula y-cauda",
      "Gillichthys mirabilis"
    ),
    taxon_name_rank = rep("species", 3),
    family = rep("Gobiidae", 3),
    genus = c("Eucyclogobius", "Quietula", "Gillichthys"),
    testid = rep("MiFishU", 3),
    stringsAsFactors = FALSE
  )
}

# Helper: build a minimal unreferenced_species_result with unreferenced_family attribute
make_fam_unref <- function(species, family_name) {
  gfm <- stats::setNames(rep(family_name, length(species)), species)
  structure(
    species,
    unreferenced_family = gfm,
    plausible = list(),
    census = data.frame(),
    family_census = NULL,
    class = c("unreferenced_species_result", "character")
  )
}

test_that("family-level unreferenced taxon (genus absent, family present) appears in output as unreferenced_genus", {
  # Gobioides genus not in candidates; Gobiidae IS represented
  unreferenced_taxa <- make_fam_unref("Gobioides broussonnetii", "Gobiidae")
  result <- assign_taxa_llm(make_match_df_taxon(),
    llm_fn = stub_llm,
    unreferenced_taxa = unreferenced_taxa, pause_seconds = 0
  )
  unref_rows <- result[!is.na(result$taxon_name) &
    result$taxon_name == "Gobioides broussonnetii", ]
  expect_equal(nrow(unref_rows), 1L)
  expect_true(all(unref_rows$hypothesis_type == "unreferenced_genus"))
})

test_that("family-level unreferenced taxon from family absent in candidates is excluded", {
  # Centrarchidae not in candidates (Gobiidae only)
  unreferenced_taxa <- make_fam_unref("Lepomis macrochirus", "Centrarchidae")
  result <- assign_taxa_llm(make_match_df_taxon(),
    llm_fn = stub_llm,
    unreferenced_taxa = unreferenced_taxa, pause_seconds = 0
  )
  expect_false("Lepomis macrochirus" %in% result$taxon_name)
})

test_that("posteriors sum to 1 with family-level unreferenced taxa", {
  unreferenced_taxa <- make_fam_unref("Gobioides broussonnetii", "Gobiidae")
  result <- assign_taxa_llm(make_match_df_taxon(),
    llm_fn = stub_llm,
    unreferenced_taxa = unreferenced_taxa, pause_seconds = 0
  )
  total <- sum(result$posterior_point_est)
  expect_equal(total, 1, tolerance = 1e-9)
})

test_that("unreferenced species with genus in ref_genera is congener (unreferenced_species) even if in unreferenced_family_map", {
  # Eucyclogobius IS a ref genus -> goes through congener path, not family path
  unreferenced_taxa <- make_fam_unref("Eucyclogobius pattersoni", "Gobiidae")
  result <- assign_taxa_llm(make_match_df_taxon(),
    llm_fn = stub_llm,
    unreferenced_taxa = unreferenced_taxa, pause_seconds = 0
  )
  unref_rows <- result[!is.na(result$taxon_name) &
    result$taxon_name == "Eucyclogobius pattersoni", ]
  expect_equal(nrow(unref_rows), 1L)
  expect_true(all(unref_rows$hypothesis_type == "unreferenced_species"))
})

test_that("match_df without family column ignores unreferenced_family_map", {
  # make_match_df() has no family/genus columns -- should not error, family-level
  # unreferenced taxa are silently skipped, congener unreferenced taxa still work
  unreferenced_taxa <- make_fam_unref("Gobioides broussonnetii", "Gobiidae")
  result <- assign_taxa_llm(make_match_df(),
    llm_fn = stub_llm,
    unreferenced_taxa = unreferenced_taxa, pause_seconds = 0
  )
  expect_s3_class(result, "data.frame")
  expect_false("Gobioides broussonnetii" %in% result$taxon_name)
})

test_that("family-level unreferenced taxon prompt label [no reference sequence] present", {
  captured <- character(0)
  capture_llm <- function(p) {
    captured <<- p
    stub_llm(p)
  }
  unreferenced_taxa <- make_fam_unref("Gobioides broussonnetii", "Gobiidae")
  assign_taxa_llm(make_match_df_taxon(),
    llm_fn = capture_llm,
    unreferenced_taxa = unreferenced_taxa, pause_seconds = 0
  )
  expect_true(grepl("no reference sequence", captured, fixed = TRUE))
})


# ---- known_present / known_absent -------------------------------------------

test_that("known_present appears in prompt under Survey context", {
  captured <- character(0)
  capture_llm <- function(p) {
    captured <<- p
    stub_llm(p)
  }
  assign_taxa_llm(make_match_df(),
    llm_fn = capture_llm,
    known_present = c("Acanthogobius flavimanus", "Tridentiger trigonocephalus"),
    pause_seconds = 0
  )
  expect_true(grepl("Survey context", captured, fixed = TRUE))
  expect_true(grepl("Acanthogobius flavimanus", captured, fixed = TRUE))
})

test_that("known_absent appears in prompt under Survey context", {
  captured <- character(0)
  capture_llm <- function(p) {
    captured <<- p
    stub_llm(p)
  }
  assign_taxa_llm(make_match_df(),
    llm_fn = capture_llm,
    known_absent = "Gillichthys mirabilis",
    pause_seconds = 0
  )
  expect_true(grepl("Confirmed absent", captured, fixed = TRUE))
  expect_true(grepl("Gillichthys mirabilis", captured, fixed = TRUE))
})

test_that("absent species prior is suppressed by (1 - detection_prob)", {
  # Gillichthys mirabilis is a candidate in make_match_df(); mark absent p=0.9
  result_plain <- assign_taxa_llm(make_match_df(),
    llm_fn = stub_llm,
    pause_seconds = 0
  )
  result_absent <- assign_taxa_llm(make_match_df(),
    llm_fn = stub_llm,
    known_absent = data.frame(
      taxon_name     = "Gillichthys mirabilis",
      detection_prob = 0.9
    ),
    pause_seconds = 0
  )
  s1_plain <- result_plain[result_plain$observation_id == "S1" &
    !is.na(result_plain$taxon_name) &
    result_plain$taxon_name == "Gillichthys mirabilis", ]
  s1_absent <- result_absent[result_absent$observation_id == "S1" &
    !is.na(result_absent$taxon_name) &
    result_absent$taxon_name == "Gillichthys mirabilis", ]
  expect_lt(s1_absent$prior_mean, s1_plain$prior_mean)
})

test_that("absent species prior suppression scales with detection_prob", {
  make_result <- function(pd) {
    assign_taxa_llm(make_match_df(),
      llm_fn = stub_llm,
      known_absent = data.frame(
        taxon_name = "Gillichthys mirabilis",
        detection_prob = pd
      ),
      pause_seconds = 0
    )
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
  result <- assign_taxa_llm(make_match_df(),
    llm_fn = stub_llm,
    known_absent = "Gillichthys mirabilis",
    pause_seconds = 0
  )
  totals <- tapply(result$posterior_point_est, result$observation_id, sum)
  expect_equal(as.vector(totals), c(1, 1), tolerance = 1e-9)
})

test_that("absent species not in candidates is silently ignored in suppression", {
  # Salmo salar is not in make_match_df(); should not error
  expect_no_error(
    assign_taxa_llm(make_match_df(),
      llm_fn = stub_llm,
      known_absent = "Salmo salar",
      pause_seconds = 0
    )
  )
})

test_that("known_absent as plain character vector uses absent_detection_prob default", {
  r_default <- assign_taxa_llm(make_match_df(),
    llm_fn = stub_llm,
    known_absent = "Gillichthys mirabilis",
    absent_detection_prob = 0.80,
    pause_seconds = 0
  )
  r_explicit <- assign_taxa_llm(make_match_df(),
    llm_fn = stub_llm,
    known_absent = data.frame(
      taxon_name     = "Gillichthys mirabilis",
      detection_prob = 0.80
    ),
    pause_seconds = 0
  )
  p_default <- r_default[r_default$observation_id == "S1" &
    r_default$taxon_name == "Gillichthys mirabilis", "prior_mean"]
  p_explicit <- r_explicit[r_explicit$observation_id == "S1" &
    r_explicit$taxon_name == "Gillichthys mirabilis", "prior_mean"]
  expect_equal(p_default, p_explicit, tolerance = 1e-12)
})

test_that("invalid known_present raises error", {
  expect_error(
    assign_taxa_llm(make_match_df(),
      llm_fn = stub_llm,
      known_present = 42, pause_seconds = 0
    ),
    regexp = "character"
  )
})

test_that("known_absent data frame without taxon_name column raises error", {
  expect_error(
    assign_taxa_llm(make_match_df(),
      llm_fn = stub_llm,
      known_absent = data.frame(species = "Foo bar"),
      pause_seconds = 0
    ),
    regexp = "taxon_name"
  )
})

# ---- LLM response robustness ------------------------------------------------

test_that("a repeated taxon_name in the LLM response does not duplicate hypothesis rows", {
  # Regression: .parse_taxa_response() passed duplicates straight through, so
  # .merge_llm_priors()'s left_join(by = "taxon_name") fanned out and that
  # taxon competed as two identical rows, taking roughly double its share of
  # the normalized posterior mass.
  dup_llm <- function(prompt_str) {
    taxa <- regmatches(
      prompt_str,
      gregexpr("(?m)(?<=^- )[^\n(]+(?= \\()", prompt_str,
        perl = TRUE
      )
    )[[1]]
    taxa <- trimws(taxa)
    if (length(taxa) == 0) taxa <- "Eucyclogobius newberryi"
    taxa <- c(taxa, taxa[[1L]]) # repeat the first taxon
    rows <- paste0(
      vapply(
        taxa, function(t) {
          sprintf('{"taxon_name":"%s","range_status":"native","prior_weight":1}', t)
        },
        character(1)
      ),
      collapse = ",\n  "
    )
    paste0("[\n  ", rows, "\n]")
  }

  expect_warning(
    result <- assign_taxa_llm(make_match_df(),
      llm_fn = dup_llm,
      pause_seconds = 0
    ),
    "repeated"
  )

  named <- result[!is.na(result$taxon_name), ]
  counts <- table(named$observation_id, named$taxon_name)
  expect_true(all(counts <= 1L))
})

# Stub that answers each prompt with a fixed weight per taxon.
weighted_llm <- function(weights) {
  function(prompt_str) {
    taxa <- trimws(regmatches(
      prompt_str,
      gregexpr("(?m)(?<=^- )[^\n(]+(?= \\()", prompt_str, perl = TRUE)
    )[[1]])
    paste0("[", paste(sprintf(
      '{"taxon_name":"%s","range_status":"native","habitat_fit":"expected","information_quality":"high","prior_weight":%g}',
      taxa, weights[taxa]
    ), collapse = ","), "]")
  }
}

test_that("priors do not depend on how the taxon list is split into batches", {
  # Regression: each batch was normalised by its own sum, so a lone
  # implausible taxon in a small final batch got prior 1/1 and won.
  md <- data.frame(
    observation_id = "A", score_original = 99,
    taxon_name = c(
      "Atherinops affinis", "Atherinopsis californiensis",
      "Leuresthes tenuis", "Zzz implausibilis"
    ),
    taxon_name_rank = "species", stringsAsFactors = FALSE
  )
  w <- c(
    "Atherinops affinis" = 0.9, "Atherinopsis californiensis" = 0.9,
    "Leuresthes tenuis" = 0.9, "Zzz implausibilis" = 0.001
  )
  run <- function(tpc) {
    r <- suppressWarnings(suppressMessages(assign_taxa_llm(md,
      context = data.frame(ecoregion = "Southern California Bight"),
      llm_fn = weighted_llm(w), taxa_per_call = tpc,
      pause_seconds = 0, n_sims = 0L, prior_phi = NULL
    )))
    r <- r[!is.na(r$taxon_name), ]
    stats::setNames(r$prior_mean, r$taxon_name)[names(w)]
  }
  one_batch <- run(15L)
  split <- run(3L)
  expect_equal(split, one_batch, tolerance = 1e-12)
  expect_lt(split[["Zzz implausibilis"]], 0.001)
})

test_that("a failed batch takes the median weight of the batches that answered", {
  md <- data.frame(
    observation_id = "A", score_original = 99,
    taxon_name = c("Aaa one", "Bbb two", "Ccc three"),
    taxon_name_rank = "species", stringsAsFactors = FALSE
  )
  ok <- weighted_llm(c("Aaa one" = 0.8, "Bbb two" = 0.2, "Ccc three" = 0.5))
  flaky <- function(prompt_str) {
    if (grepl("Ccc three", prompt_str, fixed = TRUE)) stop("timeout")
    ok(prompt_str)
  }
  r <- suppressWarnings(suppressMessages(assign_taxa_llm(md,
    llm_fn = flaky, taxa_per_call = 2L, pause_seconds = 0,
    n_sims = 0L, prior_phi = NULL
  )))
  r <- r[!is.na(r$taxon_name), ]
  p <- stats::setNames(r$prior_mean, r$taxon_name)
  # Raw weights 0.8, 0.2 and the fill median(0.8, 0.2) = 0.5, normalised.
  expect_equal(p[["Ccc three"]] / p[["Aaa one"]], 0.5 / 0.8)
  expect_equal(r$prior_source[r$taxon_name == "Ccc three"], "uniform_fallback")
})

test_that("prompt lines carry each taxon's higher lineage", {
  md <- data.frame(
    observation_id = "A", score_original = c(99, 95),
    taxon_name = c("Vertebrata lanosa", "Polysiphonia stricta"),
    taxon_name_rank = "species",
    phylum = "Rhodophyta", class = "Florideophyceae",
    order = "Ceramiales", family = "Rhodomelaceae",
    genus = c("Vertebrata", "Polysiphonia"),
    species = c("Vertebrata lanosa", "Polysiphonia stricta"),
    stringsAsFactors = FALSE
  )
  prompts <- character(0)
  capture <- function(prompt_str) {
    prompts <<- c(prompts, prompt_str)
    weighted_llm(c("Vertebrata lanosa" = 0.5, "Polysiphonia stricta" = 0.5))(prompt_str)
  }
  suppressWarnings(suppressMessages(assign_taxa_llm(md,
    llm_fn = capture, pause_seconds = 0, n_sims = 0L,
    unreferenced_taxa = "Vertebrata fucoides"
  )))
  expect_match(
    prompts[[1]],
    "- Vertebrata lanosa (species; Rhodophyta > Florideophyceae > Ceramiales > Rhodomelaceae)",
    fixed = TRUE
  )
  # The unreferenced congener borrows its lineage.
  expect_match(
    prompts[[1]],
    "- Vertebrata fucoides (species; Rhodophyta > Florideophyceae > Ceramiales > Rhodomelaceae) [no reference sequence]",
    fixed = TRUE
  )
  expect_false(grepl("independent of DNA", prompts[[1]], fixed = TRUE))
})

test_that("the prompt offers a transported range status with its own band", {
  md <- data.frame(
    observation_id = "A", score_original = 99,
    taxon_name = c("Salmo salar", "Oncorhynchus mykiss"),
    taxon_name_rank = "species", stringsAsFactors = FALSE
  )
  prompts <- character(0)
  capture <- function(prompt_str) {
    prompts <<- c(prompts, prompt_str)
    weighted_llm(c("Salmo salar" = 0.1, "Oncorhynchus mykiss" = 0.9))(prompt_str)
  }
  suppressWarnings(suppressMessages(assign_taxa_llm(md,
    llm_fn = capture, pause_seconds = 0, n_sims = 0L
  )))
  expect_match(prompts[[1]], "\"transported\"", fixed = TRUE)
  expect_match(prompts[[1]], "transported (any habitat):               0.03 - 0.15", fixed = TRUE)
})

test_that("a prior_weight_guide without transported gets the default band", {
  old_guide <- list(
    native_expected = c(0.5, 1.0), native_occasional = c(0.03, 0.15),
    native_unlikely = c(0.003, 0.03), nearby_expected = c(0.05, 0.3),
    nearby_occasional_unlikely = c(0.002, 0.05), not_documented = c(0.001, 0.02),
    taxonomically_impossible = c(0.0001, 0.002)
  )
  md <- data.frame(
    observation_id = "A", score_original = 99, taxon_name = "Salmo salar",
    taxon_name_rank = "species", stringsAsFactors = FALSE
  )
  expect_message(
    r <- suppressWarnings(assign_taxa_llm(md,
      llm_fn = weighted_llm(c("Salmo salar" = 0.1)), pause_seconds = 0,
      n_sims = 0L, prior_weight_guide = old_guide
    )),
    "transported"
  )
  expect_equal(attr(r, "report_params")$prior_weight_guide$transported, c(0.03, 0.15))
})

test_that("cache_dir serves a repeated prompt without calling the LLM", {
  dir <- tempfile("llmcache") # R removes its session temp dir on exit
  md <- data.frame(
    observation_id = "A", score_original = c(99, 95),
    taxon_name = c("Aaa one", "Bbb two"),
    taxon_name_rank = "species", stringsAsFactors = FALSE
  )
  n_calls <- 0L
  counting <- function(prompt_str) {
    n_calls <<- n_calls + 1L
    weighted_llm(c("Aaa one" = 0.8, "Bbb two" = 0.2))(prompt_str)
  }
  run <- function(ctx) {
    suppressWarnings(suppressMessages(assign_taxa_llm(md,
      context = ctx, llm_fn = counting, pause_seconds = 0,
      n_sims = 0L, cache_dir = dir
    )))
  }
  ctx <- data.frame(ecoregion = "Southern California Bight")
  r1 <- run(ctx)
  r2 <- run(ctx)
  expect_equal(n_calls, 1L)
  expect_equal(r2$prior_mean, r1$prior_mean)
  # A different context is a different prompt: a miss.
  run(data.frame(ecoregion = "Oregon Coast"))
  expect_equal(n_calls, 2L)
})

test_that("cache_dir never stores an incomplete answer", {
  dir <- tempfile("llmcache") # R removes its session temp dir on exit
  md <- data.frame(
    observation_id = "A", score_original = c(99, 95),
    taxon_name = c("Aaa one", "Bbb two"),
    taxon_name_rank = "species", stringsAsFactors = FALSE
  )
  n_calls <- 0L
  omits <- function(prompt_str) {
    n_calls <<- n_calls + 1L
    '[{"taxon_name":"Aaa one","prior_weight":0.8}]'
  }
  for (i in 1:2) {
    suppressWarnings(suppressMessages(assign_taxa_llm(md,
      llm_fn = omits, pause_seconds = 0, n_sims = 0L, cache_dir = dir
    )))
  }
  expect_equal(n_calls, 2L)
  expect_length(list.files(dir), 0L)
})
