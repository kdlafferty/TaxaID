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
   df              = mock_long,
   control_samples = c("blank_1", "blank_2"),
   verbose         = FALSE
 )

 expect_true("flag_lab_contaminant" %in% names(result))
 expect_true("flag_lab_contaminant_score" %in% names(result))
 expect_true("flag_lab_contaminant_reason" %in% names(result))
 expect_true("mean_prop_field" %in% names(result))
 expect_true("mean_prop_control" %in% names(result))
 # 5 unique taxa with non-zero reads
 expect_equal(nrow(result), 5L)
})

test_that("TaxonA (only in field) gets score 1.0 and flag 'likely'", {
 result <- flag_contaminant(
   df              = mock_long,
   control_samples = c("blank_1", "blank_2"),
   verbose         = FALSE
 )
 a_row <- result[result$taxon_name == "TaxonA", ]
 expect_equal(nrow(a_row), 1L)
 expect_equal(a_row$flag_lab_contaminant_score, 1.0)
 expect_equal(a_row$flag_lab_contaminant, "likely")
})

test_that("TaxonD (only in controls) gets score 0.0 and flag 'unlikely'", {
 result <- flag_contaminant(
   df              = mock_long,
   control_samples = c("blank_1", "blank_2"),
   verbose         = FALSE
 )
 d_row <- result[result$taxon_name == "TaxonD", ]
 expect_equal(d_row$flag_lab_contaminant_score, 0.0)
 expect_equal(d_row$flag_lab_contaminant, "unlikely")
})

test_that("TaxonB (high in controls, low in field) gets low score", {
 result <- flag_contaminant(
   df              = mock_long,
   control_samples = c("blank_1", "blank_2"),
   verbose         = FALSE
 )
 b_row <- result[result$taxon_name == "TaxonB", ]
 # B: field prop ~ 0.005-0.01, control prop ~ 0.5+
 expect_true(b_row$flag_lab_contaminant_score < 0.5)
 expect_equal(b_row$flag_lab_contaminant, "unlikely")
})

test_that("result is sorted by score (contaminants first)", {
 result <- flag_contaminant(
   df              = mock_long,
   control_samples = c("blank_1", "blank_2"),
   verbose         = FALSE
 )
 scores <- result$flag_lab_contaminant_score
 expect_true(all(diff(scores) >= 0))
})

test_that("scores are between 0 and 1", {
 result <- flag_contaminant(
   df              = mock_long,
   control_samples = c("blank_1", "blank_2"),
   verbose         = FALSE
 )
 expect_true(all(result$flag_lab_contaminant_score >= 0 &
                 result$flag_lab_contaminant_score <= 1))
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
   df              = df_typed,
   sample_type_col = "sample_type",
   control_types   = "lab_blank",
   verbose         = FALSE
 )

 expect_true("flag_lab_contaminant" %in% names(result))
 a_row <- result[result$taxon_name == "TaxonA", ]
 expect_equal(a_row$flag_lab_contaminant, "likely")
})


# ===========================================================================
# contaminant_type controls column names
# ===========================================================================

test_that("contaminant_type controls output column names", {
 result <- flag_contaminant(
   df               = mock_long,
   control_samples  = c("blank_1", "blank_2"),
   contaminant_type = "field_contaminant",
   verbose          = FALSE
 )

 expect_true("flag_field_contaminant" %in% names(result))
 expect_true("flag_field_contaminant_score" %in% names(result))
 expect_true("flag_field_contaminant_reason" %in% names(result))
 expect_false("flag_lab_contaminant" %in% names(result))
})

test_that("positive_control type works", {
 result <- flag_contaminant(
   df               = mock_long,
   control_samples  = c("blank_1", "blank_2"),
   contaminant_type = "positive_control",
   verbose          = FALSE
 )

 expect_true("flag_positive_control" %in% names(result))
})


# ===========================================================================
# exclude_samples
# ===========================================================================

test_that("exclude_samples removes samples from proportion calculation", {
 # With both controls: TaxonE is in blank_2 with prop ~ 0.125
 result_both <- flag_contaminant(
   df              = mock_long,
   control_samples = c("blank_1", "blank_2"),
   verbose         = FALSE
 )

 # With only blank_1 (blank_2 excluded): TaxonE is NOT in blank_1
 result_one <- flag_contaminant(
   df              = mock_long,
   control_samples = c("blank_1"),
   exclude_samples = c("blank_2"),
   verbose         = FALSE
 )

 e_both <- result_both[result_both$taxon_name == "TaxonE", ]
 e_one  <- result_one[result_one$taxon_name == "TaxonE", ]

 # TaxonE should have higher score when blank_2 (where it appears) is excluded
 expect_true(e_one$flag_lab_contaminant_score > e_both$flag_lab_contaminant_score)
})


# ===========================================================================
# Custom score thresholds
# ===========================================================================

test_that("custom score_thresholds change flag assignments", {
 # With very strict thresholds, more taxa become "unlikely"
 result_strict <- flag_contaminant(
   df               = mock_long,
   control_samples  = c("blank_1", "blank_2"),
   score_thresholds = c(0.8, 0.99),
   verbose          = FALSE
 )

 result_default <- flag_contaminant(
   df              = mock_long,
   control_samples = c("blank_1", "blank_2"),
   verbose         = FALSE
 )

 n_unlikely_strict  <- sum(result_strict$flag_lab_contaminant == "unlikely")
 n_unlikely_default <- sum(result_default$flag_lab_contaminant == "unlikely")
 expect_true(n_unlikely_strict >= n_unlikely_default)
})


# ===========================================================================
# Reason strings
# ===========================================================================

test_that("reason strings contain expected information", {
 result <- flag_contaminant(
   df              = mock_long,
   control_samples = c("blank_1", "blank_2"),
   verbose         = FALSE
 )

 reasons <- result$flag_lab_contaminant_reason
 expect_true(all(grepl("field proportion", reasons)))
 expect_true(all(grepl("control proportion", reasons)))
 expect_true(all(grepl("detected in", reasons)))
})


# ===========================================================================
# Edge cases
# ===========================================================================

test_that("taxa with zero reads are excluded from output", {
 df_zeros <- rbind(
   mock_long,
   data.frame(event_id = "field_1", taxon_name = "TaxonF",
              n_reads = 0, stringsAsFactors = FALSE)
 )

 result <- flag_contaminant(
   df              = df_zeros,
   control_samples = c("blank_1", "blank_2"),
   verbose         = FALSE
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
   flag_contaminant(mock_long, reads_col = "nonexistent",
                    control_samples = "blank_1", verbose = FALSE),
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
   flag_contaminant(df_typed, control_samples = "blank_1",
                    sample_type_col = "sample_type", control_types = "x",
                    verbose = FALSE),
   "not both"
 )
})

test_that("error when control_samples not found in data", {
 expect_error(
   flag_contaminant(mock_long, control_samples = c("nonexistent"),
                    verbose = FALSE),
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
