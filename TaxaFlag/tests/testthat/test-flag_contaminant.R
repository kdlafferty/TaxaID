# --- Mock data ---
# 3 field samples, 2 controls, 5 taxa
# Taxon A: only in field (clean)
# Taxon B: high in controls, low in field (contaminant)
# Taxon C: equal in both (ambiguous)
# Taxon D: only in controls (strong contaminant)
# Taxon E: in field and 1 of 2 controls, low proportion (mild)

mock_long <- data.frame(
  event_id = c(
    # Field samples
    rep("field_1", 4), rep("field_2", 3), rep("field_3", 3),
    # Controls
    rep("blank_1", 3), rep("blank_2", 2)
  ),
  taxon_name = c(
    # field_1
    "TaxonA", "TaxonB", "TaxonC", "TaxonE",
    # field_2
    "TaxonA", "TaxonC", "TaxonE",
    # field_3
    "TaxonA", "TaxonB", "TaxonE",
    # blank_1
    "TaxonB", "TaxonC", "TaxonD",
    # blank_2
    "TaxonB", "TaxonE"
  ),
  n_reads = c(
    # field_1: 1000 total
    500, 10, 200, 290,
    # field_2: 800 total
    600, 150, 50,
    # field_3: 900 total
    700, 5, 195,
    # blank_1: 100 total
    50, 40, 10,
    # blank_2: 80 total
    70, 10
  ),
  stringsAsFactors = FALSE
)


# ===========================================================================
# Basic control_samples input
# ===========================================================================

test_that("flag_contaminant returns one row per taxon", {
  result <- flag_contaminant(
    input_df = mock_long,
    control_samples = c("blank_1", "blank_2"),
    verbose = FALSE
  )

  expect_true("validity_flag" %in% names(result))
  expect_true("observation_validity" %in% names(result))
  expect_true("validity_reason" %in% names(result))
  expect_true("mean_prop_field" %in% names(result))
  expect_true("mean_prop_control" %in% names(result))
  expect_true("field_rate" %in% names(result))
  expect_true("control_rate" %in% names(result))
  expect_true("n_field_present" %in% names(result))
  expect_true("n_reads_total" %in% names(result))
  # 5 unique taxa with non-zero reads
  expect_equal(nrow(result), 5L)
})

test_that("TaxonA (only in field) gets a high score approaching but not reaching 1.0", {
  # Session 152: shrinkage means "absent from controls" no longer means an
  # absolute 1.0 -- TaxonA has 1800 total reads (500+600+700 across 3 field
  # samples) and 0 control reads, and the default prior_weight = 20
  # (read-equivalent units since Session 152, previously sample-equivalent)
  # pulls the score toward 0.5 from what would otherwise be an exact 1.0
  # (raw_score, before shrinkage, is 1.0 since control_rate = 0). Because
  # TaxonA has substantial READ support despite coming from only 3 samples,
  # shrinkage barely moves it off 1.0 -- this is the intended fix: sample
  # count alone (the pre-152 denominator) would have shrunk this far harder.
  result <- flag_contaminant(
    input_df = mock_long,
    control_samples = c("blank_1", "blank_2"),
    verbose = FALSE
  )
  a_row <- result[result$taxon_name == "TaxonA", ]
  expect_equal(nrow(a_row), 1L)
  expect_true(a_row$observation_validity < 1.0)
  expect_true(a_row$observation_validity > 0.5)
  # w = 1800/(1800+20) = 0.9890110; score = 0.5 + 0.5*w = 0.9945055
  expect_equal(a_row$observation_validity, 0.9945055, tolerance = 1e-6)
})

test_that("TaxonD (only in controls) gets a low score approaching but not reaching 0.0, flag 'invalid_lab_contaminant'", {
  result <- flag_contaminant(
    input_df = mock_long,
    control_samples = c("blank_1", "blank_2"),
    verbose = FALSE
  )
  d_row <- result[result$taxon_name == "TaxonD", ]
  expect_true(d_row$observation_validity > 0.0)
  expect_true(d_row$observation_validity < 0.5)
  expect_equal(d_row$validity_flag, "invalid_lab_contaminant")
})

test_that("prior_weight = 0 disables shrinkage: TaxonA/TaxonD hit the exact un-shrunk 1.0/0.0 boundary", {
  result <- flag_contaminant(
    input_df = mock_long,
    control_samples = c("blank_1", "blank_2"),
    prior_weight = 0,
    verbose = FALSE
  )
  a_row <- result[result$taxon_name == "TaxonA", ]
  d_row <- result[result$taxon_name == "TaxonD", ]
  expect_equal(a_row$observation_validity, 1.0)
  expect_equal(d_row$observation_validity, 0.0)
})

test_that("Session 152: shrinkage is read-count-based, not sample-count-based", {
  # TaxonThin and TaxonRich are BOTH detected in exactly 1 field sample and 0
  # controls -- identical evidence under the pre-152 sample-count scheme,
  # which would have shrunk them identically. TaxonRich has far more reads,
  # so read-count-based shrinkage should treat it as much better-supported
  # (score closer to its raw ratio of 1.0) than TaxonThin. Separate
  # single-taxon calls keep the field/control depth arithmetic simple.
  df_thin <- data.frame(
    event_id = c("field_1", "blank_1"),
    taxon_name = c("TaxonThin", "Other"),
    n_reads = c(5, 10),
    stringsAsFactors = FALSE
  )
  df_rich <- data.frame(
    event_id = c("field_1", "blank_1"),
    taxon_name = c("TaxonRich", "Other"),
    n_reads = c(50000, 10),
    stringsAsFactors = FALSE
  )
  thin <- flag_contaminant(df_thin, control_samples = "blank_1", verbose = FALSE)
  rich <- flag_contaminant(df_rich, control_samples = "blank_1", verbose = FALSE)
  thin_row <- thin[thin$taxon_name == "TaxonThin", ]
  rich_row <- rich[rich$taxon_name == "TaxonRich", ]
  # Both have raw_score = 1.0 (absent from controls), n_field_present = 1,
  # n_controls_present = 0 -- identical sample-count evidence. Read count
  # differs enormously (5 vs 50000), so rich should score much closer to 1.0.
  expect_true(rich_row$observation_validity > thin_row$observation_validity)
  expect_equal(rich_row$validity_flag, "valid")
  expect_equal(thin_row$validity_flag, "questionable_lab_contaminant")
})

test_that("higher prior_weight shrinks a thin-read-count detection harder toward 0.5", {
  # TaxonD has only 10 total reads (control-only) -- thin read support, so it
  # should be pulled toward the neutral 0.5 more strongly as prior_weight
  # (read-equivalent units since Session 152) increases.
  weak_shrink <- flag_contaminant(
    input_df = mock_long,
    control_samples = c("blank_1", "blank_2"),
    prior_weight = 1,
    verbose = FALSE
  )
  strong_shrink <- flag_contaminant(
    input_df = mock_long,
    control_samples = c("blank_1", "blank_2"),
    prior_weight = 200,
    verbose = FALSE
  )
  d_weak <- weak_shrink[weak_shrink$taxon_name == "TaxonD", "observation_validity"]
  d_strong <- strong_shrink[strong_shrink$taxon_name == "TaxonD", "observation_validity"]
  # Stronger shrinkage pulls the score up from near-0 toward 0.5
  expect_true(d_strong > d_weak)
})

test_that("invalid prior_weight errors", {
  expect_error(
    flag_contaminant(mock_long,
      control_samples = "blank_1",
      prior_weight = -1, verbose = FALSE
    ),
    "prior_weight"
  )
  expect_error(
    flag_contaminant(mock_long,
      control_samples = "blank_1",
      prior_weight = NA, verbose = FALSE
    ),
    "prior_weight"
  )
})

test_that("TaxonB (high in controls, low in field) gets low score", {
  result <- flag_contaminant(
    input_df = mock_long,
    control_samples = c("blank_1", "blank_2"),
    verbose = FALSE
  )
  b_row <- result[result$taxon_name == "TaxonB", ]
  # B: field prop ~ 0.005-0.01, control prop ~ 0.5+
  expect_true(b_row$observation_validity < 0.5)
  expect_equal(b_row$validity_flag, "invalid_lab_contaminant")
})

test_that("result is sorted by score (contaminants first)", {
  result <- flag_contaminant(
    input_df = mock_long,
    control_samples = c("blank_1", "blank_2"),
    verbose = FALSE
  )
  scores <- result$observation_validity
  expect_true(all(diff(scores) >= 0))
})

test_that("scores are between 0 and 1", {
  result <- flag_contaminant(
    input_df = mock_long,
    control_samples = c("blank_1", "blank_2"),
    verbose = FALSE
  )
  expect_true(all(result$observation_validity >= 0 &
    result$observation_validity <= 1))
})


# ===========================================================================
# sample_type_col input
# ===========================================================================

test_that("flag_contaminant works with sample_type_col", {
  df_typed <- mock_long
  df_typed$sample_type <- ifelse(
    grepl("blank", df_typed$event_id), "lab_blank", "field"
  )

  result <- flag_contaminant(
    input_df = df_typed,
    sample_type_col = "sample_type",
    control_types = "lab_blank",
    verbose = FALSE
  )

  expect_true("validity_flag" %in% names(result))
  a_row <- result[result$taxon_name == "TaxonA", ]
  # Session 152: "valid" because shrinkage is now read-count-based and TaxonA
  # has substantial read support (1800 reads) despite coming from only 3
  # samples -- see the dedicated TaxonA shrinkage test above for the exact
  # value/reasoning.
  expect_equal(a_row$validity_flag, "valid")
})


# ===========================================================================
# contaminant_type controls validity_flag's VALUES (2026-07-24: column names
# are now fixed across every TaxaFlag flag_*() mechanism; contaminant_type
# is embedded in the flag VALUE instead -- see flag_contaminant()'s own
# "Unified validity schema" section)
# ===========================================================================

test_that("contaminant_type is embedded in validity_flag's values, not the column name", {
  result <- flag_contaminant(
    input_df = mock_long,
    control_samples = c("blank_1", "blank_2"),
    contaminant_type = "field_contaminant",
    verbose = FALSE
  )

  # Column names are always the same, regardless of contaminant_type.
  expect_true("validity_flag" %in% names(result))
  expect_true("observation_validity" %in% names(result))
  expect_true("validity_reason" %in% names(result))

  # But the flag VALUES reflect field_contaminant, not the default lab_contaminant.
  d_row <- result[result$taxon_name == "TaxonD", ]
  expect_equal(d_row$validity_flag, "invalid_field_contaminant")
  expect_false(any(grepl("lab_contaminant", result$validity_flag)))
})

test_that("positive_control type works", {
  result <- flag_contaminant(
    input_df = mock_long,
    control_samples = c("blank_1", "blank_2"),
    contaminant_type = "positive_control",
    verbose = FALSE
  )

  expect_true("validity_flag" %in% names(result))
  d_row <- result[result$taxon_name == "TaxonD", ]
  expect_equal(d_row$validity_flag, "invalid_positive_control")
})


# ===========================================================================
# exclude_samples
# ===========================================================================

test_that("exclude_samples removes samples from proportion calculation", {
  # With both controls: TaxonE is in blank_2 with prop ~ 0.125
  result_both <- flag_contaminant(
    input_df = mock_long,
    control_samples = c("blank_1", "blank_2"),
    verbose = FALSE
  )

  # With only blank_1 (blank_2 excluded): TaxonE is NOT in blank_1
  result_one <- flag_contaminant(
    input_df = mock_long,
    control_samples = c("blank_1"),
    exclude_samples = c("blank_2"),
    verbose = FALSE
  )

  e_both <- result_both[result_both$taxon_name == "TaxonE", ]
  e_one <- result_one[result_one$taxon_name == "TaxonE", ]

  # TaxonE should have higher score when blank_2 (where it appears) is excluded
  expect_true(e_one$observation_validity > e_both$observation_validity)
})


# ===========================================================================
# Custom score thresholds
# ===========================================================================

test_that("custom score_thresholds change validity_flag assignments", {
  # With very strict thresholds, more taxa become "invalid_lab_contaminant"
  result_strict <- flag_contaminant(
    input_df = mock_long,
    control_samples = c("blank_1", "blank_2"),
    score_thresholds = c(0.8, 0.99),
    verbose = FALSE
  )

  result_default <- flag_contaminant(
    input_df = mock_long,
    control_samples = c("blank_1", "blank_2"),
    verbose = FALSE
  )

  n_invalid_strict <- sum(result_strict$validity_flag == "invalid_lab_contaminant")
  n_invalid_default <- sum(result_default$validity_flag == "invalid_lab_contaminant")
  expect_true(n_invalid_strict >= n_invalid_default)
})


# ===========================================================================
# Reason strings
# ===========================================================================

test_that("reason strings contain expected information", {
  result <- flag_contaminant(
    input_df = mock_long,
    control_samples = c("blank_1", "blank_2"),
    verbose = FALSE
  )

  reasons <- result$validity_reason
  expect_true(all(grepl("field rate", reasons)))
  expect_true(all(grepl("control rate", reasons)))
  expect_true(all(grepl("detected in", reasons)))
})


# ===========================================================================
# Edge cases
# ===========================================================================

test_that("taxa with zero reads are excluded from output", {
  df_zeros <- rbind(
    mock_long,
    data.frame(
      event_id = "field_1", taxon_name = "TaxonF",
      n_reads = 0, stringsAsFactors = FALSE
    )
  )

  result <- flag_contaminant(
    input_df = df_zeros,
    control_samples = c("blank_1", "blank_2"),
    verbose = FALSE
  )

  # TaxonF has zero reads everywhere — should not appear in output
  expect_false("TaxonF" %in% result$taxon_name)
  # Original 5 taxa still present
  expect_equal(nrow(result), 5L)
})


# ===========================================================================
# Input validation
# ===========================================================================

test_that("error when required columns missing", {
  expect_error(
    flag_contaminant(mock_long,
      reads_col = "nonexistent",
      control_samples = "blank_1", verbose = FALSE
    ),
    "not found"
  )
})

test_that("error when neither control_samples nor sample_type_col supplied", {
  expect_error(
    flag_contaminant(mock_long, verbose = FALSE),
    "control_samples.*sample_type_col"
  )
})

test_that("error when both control_samples and sample_type_col supplied", {
  df_typed <- mock_long
  df_typed$sample_type <- "field"
  expect_error(
    flag_contaminant(df_typed,
      control_samples = "blank_1",
      sample_type_col = "sample_type", control_types = "x",
      verbose = FALSE
    ),
    "not both"
  )
})

test_that("error when control_samples not found in data", {
  expect_error(
    flag_contaminant(mock_long,
      control_samples = c("nonexistent"),
      verbose = FALSE
    ),
    "None of"
  )
})

test_that("error when no field samples remain", {
  expect_error(
    flag_contaminant(
      mock_long,
      control_samples = c("blank_1", "blank_2"),
      exclude_samples = c("field_1", "field_2", "field_3"),
      verbose = FALSE
    ),
    "No field samples"
  )
})

test_that("error when reads_col is not numeric", {
  bad_df <- mock_long
  bad_df$n_reads <- as.character(bad_df$n_reads)
  expect_error(
    flag_contaminant(bad_df, control_samples = "blank_1", verbose = FALSE),
    "must be numeric"
  )
})

test_that("error when sample_type_col used without control_types", {
  df_typed <- mock_long
  df_typed$sample_type <- "field"
  expect_error(
    flag_contaminant(df_typed, sample_type_col = "sample_type", verbose = FALSE),
    "control_types.*required"
  )
})
