# ==============================================================================
# extra_functions_review_inputs.R
# TaxaMatch -- small, ready-to-run inputs for 58 functions added AFTER the
# package's formal code review (reviewed 2026-07-13; see
# inst/taxamatch_review.Rmd / inst/taxamatch_review_response.md)
#
# PURPOSE
# -------
# Prepared for external code review: gives the reviewer a concrete, small
# input for each of 58 functions from three feature clusters that landed
# after the review closed, so every one of them can actually be run/inspected
# rather than reverse-engineered from source. Modeled on
# TaxaLikely/inst/review_function_inputs.R (same monorepo, same convention).
#
#   Cluster 1 -- utils_shared.R consolidation (2026-07-20): internal helpers
#     shared across the read_*()/blast_sequences()/score_image_inat() ingest
#     functions, plus read_speciesnet_output() (the one exported function
#     from this cluster).
#   Cluster 2 -- reference-quality / accession-investigation feature
#     (2026-08-03 through 2026-08-11): evaluate_reference_accessions(),
#     investigate_flagged_accession(s)(), check_marker_mismatch(), and the
#     large internal machinery behind them (BLAST-based hierarchy-congruence
#     scoring, persistent caches, hybrid-labeled-accession handling). See
#     TaxaMatch/CLAUDE.md's many session notes on these three functions for
#     the full design history.
#   Cluster 3 -- LLM second-look reviewer (2026-08-13): review_flagged_
#     accessions(), implementing Question 2 of ecosystem_docs/REENTRY_PROMPT_
#     flagged_accession_second_look.md, plus the internal prompt-building/
#     retry/parsing machinery behind it. Also demonstrates
#     best_disagreeing_taxon, a new output column on
#     evaluate_reference_accessions()/.compute_hierarchy_congruence() shipped
#     the same day specifically so this cluster's LLM reviewer can see the
#     disagreeing taxon's NAME, not just its identity percentage -- shown
#     inline in Cluster 2's own .compute_hierarchy_congruence() section
#     below, not counted separately in the function total above.
#
# Inputs are pulled from three sources, cheapest first:
#   1. Existing testthat fixtures reused verbatim or near-verbatim (the large
#      majority of sections below -- test-evaluate-reference-accessions.R,
#      test-investigate-flagged-accession.R, test-check-marker-mismatch.R,
#      test-trim-query-to-amplicon.R, test-blast.R)
#   2. This package's own roxygen @examples (read_speciesnet_output())
#   3. New small synthetic inputs constructed for this file where neither
#      existed (most of Cluster 1's tiny pure helpers)
#
# REQUIRES tags (read before running a section):
#   OFFLINE        -- pure function or fully self-contained input; no network
#   OFFLINE+BIOC   -- offline, but needs Biostrings (Bioconductor, Suggests)
#                     installed; present on this machine
#   OFFLINE(mock)  -- offline, but the section MOCKS a real internal NCBI/
#                     BLAST call via testthat::local_mocked_bindings() --
#                     see "Why some functions are mocked instead of live"
#                     below for which functions this applies to and why.
#   OFFLINE(stub llm_fn) -- offline; the section passes a local stub function
#                     as `llm_fn` (a real, first-class parameter every
#                     LLM-calling function in this ecosystem accepts, not a
#                     workaround) instead of the default
#                     `TaxaTools::call_api`. No network/API call, no cost --
#                     applies only to Cluster 3's review_flagged_accessions().
#   NETWORK        -- hits real NCBI (via rentrez), no BLAST involved, no
#                     credentials needed; every NETWORK section here is a
#                     single small lookup, individually verified live at
#                     under 3 seconds each while preparing this file.
#
# Internal (dot-prefixed) functions are called via TaxaMatch:::.fn_name(...)
# throughout this file. This is EXPECTED and CORRECT for a dev/reviewer
# session against a normal source install -- ::: exposes a package's own
# internal namespace to code outside the package; it is not a bug, a
# workaround, or something that would fail differently in production (an
# installed package's internal functions are always reachable this way).
#
# WHY SOME FUNCTIONS ARE MOCKED INSTEAD OF LIVE
# ----------------------------------------------
# evaluate_reference_accessions(), investigate_flagged_accession(s)(), and
# several internal helpers deep in their call chains
# (.blast_against_comparison_set(), .get_species_comparison_meta(),
# .investigate_flagged_accession_core()) ultimately submit a real remote
# NCBI BLAST job and poll for results -- a single call is realistically
# 30-90+ seconds (submission + polling + an 11-second inter-batch NCBI
# rate-limit sleep baked into blast_sequences() itself), and
# TaxaMatch/CLAUDE.md documents a real NCBI server-side CPU-budget rejection
# this ecosystem's own production use hit on a large real run the same week
# these functions were written. Making this file's correctness depend on
# NCBI's BLAST queue being fast and uncongested at review time would make it
# fragile and slow to run for no real benefit -- the reviewer's goal here is
# to see each function's real call SHAPE and output schema, which a mock
# demonstrates exactly as well as a live call would for a data-flow-only
# review.
#
# Per this task's own instructions, those functions are demonstrated below
# via testthat::local_mocked_bindings(), reusing this package's own
# established test fixtures (test-evaluate-reference-accessions.R /
# test-investigate-flagged-accession.R) verbatim or near-verbatim, tagged
# OFFLINE(mock). The five genuinely cheap NETWORK functions in this cluster
# that make a single fast NCBI lookup with NO BLAST involved
# (.fetch_reference_accession_records(), .search_species_accessions(),
# .attach_taxonomy(), .fetch_marker_annotation(), check_marker_mismatch())
# ARE run live below, against small real accessions/species already used
# elsewhere in this package's own workflows and documentation: OQ846539 (a
# real, small 172bp PtConception 12S MiFish sequence, the same accession
# inst/workflows/blast_sequences_workflow.R uses as a real live query) and
# AY850362 (the real, already-confirmed 16S-vs-12S marker-mislabel case
# documented directly in check_marker_mismatch()'s own roxygen "Why this
# exists" section).
#
# NON-DETERMINISM NOTE: the 5 real NETWORK sections hit live NCBI. Exact
# organism/date/annotation text could in principle drift if a record is ever
# revised -- not expected for these particular long-deposited accessions,
# but worth knowing if a re-run someday shows a different value.
# ==============================================================================

#devtools::load_all()   # or: library(TaxaMatch)
library(TaxaMatch)
library(testthat)   # local_mocked_bindings() -- OFFLINE(mock) sections only


# ==============================================================================
# CLUSTER 1 -- utils_shared.R consolidation (2026-07-20)
# Internal helpers shared across the read_*()/blast_sequences()/
# score_image_inat() ingest functions, plus read_speciesnet_output().
# ==============================================================================

## ---- .check_pkg() ---- OFFLINE -----------------------------------------------
# `stats` is always installed -- demonstrates the pass-through (invisible
# TRUE); the stop() path needs a genuinely uninstalled package to trigger.
TaxaMatch:::.check_pkg("stats")

## ---- .stop_missing_files() ---- OFFLINE ---------------------------------------
# Always stop()s -- that IS its job; tryCatch shows the message it raises.
tryCatch(
  TaxaMatch:::.stop_missing_files(c("nope1.csv", "nope2.csv"), "read_animl_output"),
  error = function(e) message("Caught as expected: ", conditionMessage(e))
)

## ---- .extract_genus() ---- OFFLINE --------------------------------------------
TaxaMatch:::.extract_genus(c("Fundulus heteroclitus", "Genus", "empty"))

## ---- .validate_min_conf_top_n() ---- OFFLINE ----------------------------------
TaxaMatch:::.validate_min_conf_top_n(min_confidence = 0.5, top_n = 5, fn_name = "demo_fn")

## ---- .apply_top_n() ---- OFFLINE -----------------------------------------------
top_n_df <- data.frame(
  observation_id = c("S1", "S1", "S1", "S2"),
  score           = c(95, 80, 60, 70),
  stringsAsFactors = FALSE
)
TaxaMatch:::.apply_top_n(top_n_df, "observation_id", "score", top_n = 2L)

## ---- .check_col_exists() ---- OFFLINE ------------------------------------------
demo_df <- data.frame(ESVId = "S1", PercMatch = 99, stringsAsFactors = FALSE)
TaxaMatch:::.check_col_exists(demo_df, "ESVId", "observation_id_col")

## ---- .check_rename_safe() ---- OFFLINE -----------------------------------------
TaxaMatch:::.check_rename_safe(demo_df, "ESVId", "observation_id")

## ---- .validate_rank_system() ---- OFFLINE ---------------------------------------
TaxaMatch:::.validate_rank_system(c("family", "genus", "species"))

## ---- .warn_duplicate_basenames() ---- OFFLINE -----------------------------------
# Two DIFFERENT directories share a basename -- a real collision this
# function exists to warn about (the long-format case, same path repeated
# across candidate rows, is deliberately NOT a warning -- see its own
# roxygen). The warning below is expected output, not a bug.
dup_paths <- c("siteA/recording.wav", "siteB/recording.wav", "siteA/other.wav")
TaxaMatch:::.warn_duplicate_basenames(dup_paths, "read_birdnet_output")

## ---- .warn_na_coercion() ---- OFFLINE ------------------------------------------
raw_vals     <- c("0.9", "not_a_number", "0.5")
coerced_vals <- suppressWarnings(as.numeric(raw_vals))
TaxaMatch:::.warn_na_coercion(raw_vals, coerced_vals, "Confidence", "demo_source.csv")

## ---- .fmt_time() ---- OFFLINE --------------------------------------------------
TaxaMatch:::.fmt_time(c(3, 3.05, NA))

## ---- .generate_asv_ids() ---- OFFLINE ------------------------------------------
TaxaMatch:::.generate_asv_ids(3L, "ASV")

## ---- .build_core_seq_df() ---- OFFLINE -----------------------------------------
TaxaMatch:::.build_core_seq_df(
  asv_ids    = c("ASV_1", "ASV_2"),
  sequences  = c("ACGTACGT", "GGCCTTAA"),
  abundances = c(10L, 5L)
)

## ---- .empty_acc_taxonomy_result() ---- OFFLINE ----------------------------------
str(TaxaMatch:::.empty_acc_taxonomy_result())

## ---- .empty_animl_result() ---- OFFLINE -----------------------------------------
str(TaxaMatch:::.empty_animl_result())

## ---- .empty_birdnet_result() ---- OFFLINE ---------------------------------------
str(TaxaMatch:::.empty_birdnet_result())

## ---- .empty_inat_result() ---- OFFLINE ------------------------------------------
str(TaxaMatch:::.empty_inat_result())

## ---- .empty_speciesnet_result() ---- OFFLINE ------------------------------------
str(TaxaMatch:::.empty_speciesnet_result(include_coverage = TRUE))

## ---- .parse_speciesnet_label() ---- OFFLINE -------------------------------------
# Real label shape confirmed directly against SpeciesNet's own shipped
# taxonomy file (see read_speciesnet_output()'s roxygen) -- one species-level
# label, one "blank" (no taxonomic content) label.
TaxaMatch:::.parse_speciesnet_label(c(
  "u1;amphibia;anura;bufonidae;rhinella;marina;cane toad",
  "u2;;;;;;blank"
))

## ---- .speciesnet_detection_coverage() ---- OFFLINE ------------------------------
# Shape matches jsonlite::fromJSON(simplifyVector = FALSE)'s own nested-list
# output for a "detections" array -- category "1" is MegaDetector's "animal"
# class and is used; category "2" (e.g. "vehicle") is correctly excluded.
speciesnet_dets <- list(
  list(category = "1", conf = 0.95, bbox = list(0.1, 0.1, 0.3, 0.4)),
  list(category = "2", conf = 0.99, bbox = list(0.0, 0.0, 0.1, 0.1))
)
TaxaMatch:::.speciesnet_detection_coverage(speciesnet_dets, min_detection_conf = 0)

## ---- .parse_speciesnet_predictions() ---- OFFLINE -------------------------------
# Real synthetic SpeciesNet CLI JSON, reused verbatim from
# read_speciesnet_output()'s own @examples (real label format, uuids
# shortened).
speciesnet_json <- tempfile(fileext = ".json")
writeLines(
  '{"predictions":[
     {"filepath":"IMG_001.jpg",
      "classifications":{
        "classes":[
          "u1;amphibia;anura;bufonidae;rhinella;marina;cane toad",
          "u2;amphibia;anura;ranidae;;;true frogs"],
        "scores":[0.87,0.06]},
      "detections":[{"category":"1","conf":0.95,"bbox":[0.1,0.1,0.3,0.4]}],
      "prediction":"u1;amphibia;anura;bufonidae;rhinella;marina;cane toad",
      "prediction_score":0.87,"prediction_source":"classifier"},
     {"filepath":"IMG_002.jpg",
      "classifications":{
        "classes":["u3;;;;;;blank"],
        "scores":[0.99]},
      "prediction":"u3;;;;;;blank",
      "prediction_score":0.99,"prediction_source":"detector"}
  ]}',
  speciesnet_json
)
str(TaxaMatch:::.parse_speciesnet_predictions(
  speciesnet_json, include_coverage = TRUE, min_detection_conf = 0
))

## ---- read_speciesnet_output() ---- OFFLINE --------------------------------------
# Chained off the same real-shaped fixture file used just above.
speciesnet_out <- read_speciesnet_output(speciesnet_json, include_coverage = TRUE)
speciesnet_out[, c("observation_id", "species", "taxon_rank", "score", "coverage")]
unlink(speciesnet_json)


# ==============================================================================
# CLUSTER 2 -- reference-quality / accession-investigation feature
# (2026-08-03 through 2026-08-11; see TaxaMatch/CLAUDE.md's many session
# notes on evaluate_reference_accessions() / investigate_flagged_accession()
# / check_marker_mismatch())
# ==============================================================================

## ---- .valid_reference_length() ---- OFFLINE -------------------------------------
TaxaMatch:::.valid_reference_length(173)        # TRUE
TaxaMatch:::.valid_reference_length(NA_real_)   # FALSE
TaxaMatch:::.valid_reference_length(NULL)       # FALSE

## ---- .filter_and_cap_accessions() ---- OFFLINE ----------------------------------
# Reused verbatim from tests/testthat/test-investigate-flagged-accession.R --
# mirrors the real MZ605481 case: 2 whole-chromosome-assembly-scale
# candidates (tens of millions of bp) are correctly excluded by the length
# ratio, while a real, length-comparable candidate is kept.
TaxaMatch:::.filter_and_cap_accessions(
  accs = c("MZ605481_LIKE", "CM184582", "CM184583", "PV841430"),
  lens = c(173, 76718285, 69816937, 643),
  exclude = character(0L), max_records = 30L,
  reference_length = 173, max_length_ratio = 3
)

## ---- .build_submission_batch_lookup() ---- OFFLINE ------------------------------
batch_ref_df <- data.frame(
  composite_id = c("MH538728", "MH538729", "XYZ_weird"),
  create_date  = c("2020/01/10", "2020/01/12", NA),
  stringsAsFactors = FALSE
)
TaxaMatch:::.build_submission_batch_lookup(batch_ref_df)

## ---- .same_submission_batch() ---- OFFLINE ---------------------------------------
TaxaMatch:::.same_submission_batch(
  x_date = as.Date("2020-01-10"), x_prefix = "AB", x_num = 100,
  y_date = as.Date("2020-01-12"), y_prefix = "CD", y_num = 999,
  submission_window = 5L
)

## ---- .compute_hierarchy_congruence() ---- OFFLINE --------------------------------
# Reused verbatim from tests/testthat/test-evaluate-reference-accessions.R --
# a real Menidia beryllina self-consistency case (2 independent agreeing
# hits, 1 disagreeing) that correctly reads "congruent".
congruence_sm <- data.frame(
  id_x = rep("ACC001", 3), id_y = c("HIT_B", "HIT_C", "HIT_D"),
  p_match = c(0.99, 0.98, 0.85),
  family.x = "Atherinopsidae", genus.x = "Menidia", species.x = "Menidia beryllina",
  family.y = c("Atherinopsidae", "Atherinopsidae", "Sparidae"),
  genus.y  = c("Menidia", "Menidia", "Sparus"),
  species.y = c("Menidia beryllina", "Menidia beryllina", "Sparus aurata"),
  stringsAsFactors = FALSE
)
congruence_ref_df <- data.frame(
  composite_id = c("ACC001", "HIT_B", "HIT_C", "HIT_D"),
  create_date  = c("2020/01/10", "2021/06/01", "2019/03/15", "2018/11/20"),
  stringsAsFactors = FALSE
)
congruence_out <- TaxaMatch:::.compute_hierarchy_congruence(
  congruence_sm, congruence_ref_df, rank_system = c("family", "genus", "species"),
  top_n = 5L, min_congruent_rank = "family", submission_window = 5L
)
congruence_out
# best_disagreeing_taxon (new 2026-08-13, Cluster 3): the listed species of
# the SAME highest-identity disagreeing hit best_disagreeing_pident is
# already computed from -- here, HIT_D's "Sparus aurata" -- so a reviewer
# (human or the new LLM second-look reviewer below) sees WHAT disagreed, not
# just BY HOW MUCH.
congruence_out[, c("best_disagreeing_pident", "best_disagreeing_taxon")]

## ---- .blast_server_rejected() ---- OFFLINE ----------------------------------------
# Real captured NCBI server-side CPU-budget rejection message text
# (2026-08-09; see this function's own roxygen for the full incident) --
# not a synthetic guess.
real_rejection_msg <- paste0(
  "<Iteration_message>[blastsrv4.REAL]: Error: CPU usage limit was ",
  "exceeded, resulting in SIGXCPU (24).</Iteration_message>"
)
TaxaMatch:::.blast_server_rejected(real_rejection_msg)                     # TRUE
TaxaMatch:::.blast_server_rejected("<Iteration_hits></Iteration_hits>")    # FALSE

## ---- .resolve_marker_pattern() ---- OFFLINE --------------------------------------
marker_pattern <- TaxaMatch:::.resolve_marker_pattern("12S")
grepl(marker_pattern, "16S ribosomal RNA", ignore.case = TRUE)  # FALSE
grepl(marker_pattern, "12S ribosomal RNA", ignore.case = TRUE)  # TRUE

## ---- .extract_amplicon_one_tm() ---- OFFLINE+BIOC ---------------------------------
# Real, verified MiFish-U primer pair wrapped around a synthetic interior,
# sized to match the real, empirically-measured 221bp full primer-inclusive
# span (see tests/testthat/test-trim-query-to-amplicon.R's own header note).
mf_fwd      <- "GTCGGTAAAACTCGTGCCAGC"
mf_rev      <- "CATAGTGGGGTATCTAATCCCAGTTTG"
mf_rev_rc   <- as.character(Biostrings::reverseComplement(Biostrings::DNAString(mf_rev)))
mf_interior <- paste0(strrep("AAACCCGGGTTT", 14L), "AAAAA")
mf_amplicon <- paste0(mf_fwd, mf_interior, mf_rev_rc)
mf_genome   <- paste0(strrep("N", 300L), mf_amplicon, strrep("A", 300L))

amplicon_result <- TaxaMatch:::.extract_amplicon_one_tm(
  seq_char = mf_genome, fwd_pattern = mf_fwd, rev_pattern_rc = mf_rev_rc,
  fwd_max_mm = 3L, rev_max_mm = 4L, min_len = 100L, max_len = 250L
)
amplicon_result$trimmed                             # TRUE
identical(amplicon_result$sequence, mf_amplicon)     # TRUE

## ---- .trim_queries_to_amplicon() ---- OFFLINE+BIOC --------------------------------
# Chained off the same real primer pair -- over-length genome gets trimmed,
# an already-short (already-barcode-length) sequence is left untouched.
trimmed_seqs <- TaxaMatch:::.trim_queries_to_amplicon(
  c(mf_genome, mf_amplicon), barcode_term = "MiFishU", verbose = FALSE
)
nchar(trimmed_seqs)

## ---- .fetch_reference_accession_records() ---- NETWORK, real small accession -----
# OQ846539: a real, small (172bp) PtConception 12S MiFish sequence, already
# used as a real live query in this package's own
# inst/workflows/blast_sequences_workflow.R -- reused here rather than
# inventing a new query.
acc_record <- TaxaMatch:::.fetch_reference_accession_records(
  "OQ846539", want_sequence = TRUE, verbose = FALSE
)
acc_record[, c("accession", "organism", "create_date")]
nchar(acc_record$sequence)

## ---- .search_species_accessions() ---- NETWORK ------------------------------------
TaxaMatch:::.search_species_accessions(
  acc_record$organism, max_records = 3L, verbose = FALSE
)

## ---- .attach_taxonomy() ---- NETWORK -----------------------------------------------
# A minimal "filtered hits" frame with no staxids (remote BLAST XML never
# populates one -- see this function's own roxygen) -- exercises the
# accession-based taxonomy-resolution fallback path.
attach_hits <- data.frame(sacc = "OQ846539", stringsAsFactors = FALSE)
TaxaMatch:::.attach_taxonomy(attach_hits, ncbi_api_key = NULL, verbose = FALSE)

## ---- .fetch_marker_annotation() ---- NETWORK ---------------------------------------
# AY850362: the real, already-confirmed 16S-vs-12S marker-mislabel case (see
# check_marker_mismatch()'s own roxygen "Why this exists" section).
TaxaMatch:::.fetch_marker_annotation("AY850362", verbose = FALSE)

## ---- check_marker_mismatch() ---- NETWORK, real confirmed mismatch case -----------
check_marker_mismatch("AY850362", expected_marker = "12S", verbose = FALSE)

## ---- evaluate_reference_accessions() ---- OFFLINE(mock), mocked BLAST/NCBI --------
# Fixture reused verbatim from tests/testthat/test-evaluate-reference-
# accessions.R: 3 accessions -- ACC001 (Menidia beryllina, correctly
# congruent), ACC002 (Cottus asper, mislabeled -- its own independent hits
# all agree with Salmo salar -- incongruent), ACC003 (zero BLAST hits at
# all -- insufficient_independent_evidence, and must still produce a row,
# not silently vanish -- the real regression this fixture guards).
.erc_records_fixture <- function() {
  data.frame(
    accession = c("ACC001", "ACC002", "ACC003",
                 "HIT_A", "HIT_B", "HIT_C", "HIT_D", "HIT_E", "HIT_F", "HIT_G"),
    sequence = c("ACGTACGTACGTACGT", "TTTTGGGGCCCCAAAA", "GATTACAGATTACAGA",
                rep("NNNNNNNNNNNNNNNN", 7)),
    organism = c("Menidia beryllina", "Cottus asper", "Novataxon unicum",
                rep(NA_character_, 7)),
    create_date = c("2020/01/10", "2020/02/01", "2020/03/01",
                    "2020/01/12", "2021/06/01", "2019/03/15", "2018/11/20",
                    "2021/06/01", "2019/03/15", "2018/11/20"),
    stringsAsFactors = FALSE
  )
}
.erc_mock_fetch_records <- function(accessions, want_sequence = TRUE, ncbi_api_key = NULL,
                                    verbose = TRUE) {
  fx <- .erc_records_fixture()
  out <- fx[fx$accession %in% accessions, , drop = FALSE]
  if (!want_sequence) out$sequence <- NA_character_
  rownames(out) <- NULL
  out
}
.erc_hits_fixture <- function() {
  data.frame(
    observation_id = c(rep("ACC001", 5), rep("ACC002", 3)),
    accession       = c("ACC001", "HIT_A", "HIT_B", "HIT_C", "HIT_D",
                       "HIT_E", "HIT_F", "HIT_G"),
    score           = c(100, 99.9, 99, 98, 85, 95, 93, 90),
    query_coverage  = 95,
    kingdom = "Animalia", phylum = "Chordata", class = "Actinopteri",
    order   = c("Atheriniformes", "Atheriniformes", "Atheriniformes",
               "Atheriniformes", "Beloniformes",
               "Scorpaeniformes", "Scorpaeniformes", "Scorpaeniformes"),
    family  = c("Atherinopsidae", "Atherinopsidae", "Atherinopsidae",
               "Atherinopsidae", "Sparidae", "Salmonidae", "Salmonidae", "Salmonidae"),
    genus   = c("Menidia", "Menidia", "Menidia", "Menidia", "Sparus",
               "Salmo", "Salmo", "Salmo"),
    species = c("Menidia beryllina", "Menidia beryllina", "Menidia beryllina",
               "Menidia beryllina", "Sparus aurata",
               "Salmo salar", "Salmo salar", "Salmo salar"),
    stringsAsFactors = FALSE
  )
}
.erc_mock_blast <- function(seq_df, ...) {
  fx <- .erc_hits_fixture()
  fx[fx$observation_id %in% seq_df$asv_id, , drop = FALSE]
}
.erc_query_taxonomy_fixture <- function() {
  data.frame(
    accession = c("ACC001", "ACC002", "ACC003"),
    kingdom = "Animalia", phylum = "Chordata", class = "Actinopteri",
    order   = c("Atheriniformes", "Scorpaeniformes", "Testiformes"),
    family  = c("Atherinopsidae", "Cottidae", "Testifamilia"),
    genus   = c("Menidia", "Cottus", "Novataxon"),
    species = c("Menidia beryllina", "Cottus asper", "Novataxon unicum"),
    stringsAsFactors = FALSE
  )
}
.erc_mock_resolve_taxonomy <- function(accessions, ncbi_api_key = NULL, verbose = TRUE) {
  fx <- .erc_query_taxonomy_fixture()
  out <- fx[fx$accession %in% accessions, , drop = FALSE]
  rownames(out) <- NULL
  out
}
run_erc_mocks <- function(expr) {
  local_mocked_bindings(
    .fetch_reference_accession_records = .erc_mock_fetch_records, .package = "TaxaMatch"
  )
  local_mocked_bindings(blast_sequences = .erc_mock_blast, .package = "TaxaMatch")
  local_mocked_bindings(
    .resolve_taxonomy_by_acc = .erc_mock_resolve_taxonomy, .package = "TaxaMatch"
  )
  force(expr)
}

eval_result <- run_erc_mocks({
  evaluate_reference_accessions(
    c("ACC001", "ACC002", "ACC003"), cache_dir = NULL, verbose = FALSE
  )
})
eval_result[, c("accession", "listed_taxon", "hierarchy_flag", "finest_common_rank")]

## ---- flag_incongruent_references() ---- OFFLINE, chained off eval_result ----------
match_df_demo <- data.frame(
  observation_id = c("obs1", "obs2", "obs3"),
  accession       = c("ACC001.1", "ACC002.1", "ACC003.1"),
  taxon_name      = c("Menidia beryllina", "Cottus asper", "Novataxon unicum"),
  stringsAsFactors = FALSE
)
flagged_demo <- flag_incongruent_references(match_df_demo, eval_result)
flagged_demo[, c("observation_id", "accession", "hierarchy_flag")]

## ---- remove_incongruent_references() ---- OFFLINE, chained off eval_result --------
remove_incongruent_references(match_df_demo, eval_result)

## ---- .load_reference_accession_cache() / .save_reference_accession_cache() ---- OFFLINE, chained ----
# Reuses eval_result's own row shape as a real persistent-cache entry --
# eval_result carries cache_hit/listed_taxon_is_species (per-call diagnostic
# columns) where the on-disk cache instead carries params_key (the
# staleness-detection key); swap the two.
erc_cache_dir   <- tempfile("erc_cache")
empty_erc_cache <- TaxaMatch:::.load_reference_accession_cache(erc_cache_dir)  # dir doesn't exist yet
nrow(empty_erc_cache)

erc_cache_row <- eval_result[1L, setdiff(names(eval_result), c("cache_hit", "listed_taxon_is_species"))]
erc_cache_row$params_key <- "demo_params_v1"
erc_cache_row <- erc_cache_row[, names(empty_erc_cache)]
erc_cache1 <- rbind(empty_erc_cache, erc_cache_row)
TaxaMatch:::.save_reference_accession_cache(erc_cache_dir, erc_cache1)

erc_cache_reloaded <- TaxaMatch:::.load_reference_accession_cache(erc_cache_dir)
erc_cache_reloaded[, c("accession", "hierarchy_flag", "params_key")]


# ------------------------------------------------------------------------------
# The following investigate_flagged_accession()-family sections all reuse ONE
# shared mocked-fixture set (reused verbatim from tests/testthat/
# test-investigate-flagged-accession.R), mirroring the real MZ605481 case's
# shape: self-consistency with one weak/coverage-failing hit, cross-taxon
# consistency with strong, coverage-safe identity to a disagreeing taxon.
# ------------------------------------------------------------------------------

.iv_records_fixture <- function() {
  data.frame(
    accession = c("ACC_FLAG", "PPARVA_A", "PPARVA_B", "CARPIO_A", "CARPIO_B",
                 "HIT_CARPIO1", "HIT_SAMEBATCH"),
    sequence = c("QUERYSEQ", "PPARVA_A_SEQ", "PPARVA_B_SEQ",
                "CARPIO_A_SEQ", "CARPIO_B_SEQ", "HIT_CARPIO1_SEQ", "HIT_SAMEBATCH_SEQ"),
    organism = c("Pseudorasbora parva", NA, NA, NA, NA, NA, NA),
    create_date = c("2020/01/01", "2019/05/01", "2018/03/01",
                    "2021/07/01", "2021/08/01", "2021/07/15", "2020/01/02"),
    stringsAsFactors = FALSE
  )
}
.iv_mock_fetch_records <- function(accessions, want_sequence = TRUE, ncbi_api_key = NULL,
                                   verbose = TRUE) {
  fx <- .iv_records_fixture()
  out <- fx[fx$accession %in% accessions, , drop = FALSE]
  if (!want_sequence) out$sequence <- NA_character_
  rownames(out) <- NULL
  out
}
.iv_mock_search_species <- function(species, exclude = character(0L), max_records = 30L,
                                    reference_length = NULL, max_length_ratio = 3,
                                    ncbi_api_key = NULL, verbose = TRUE) {
  strip_v <- function(x) sub("\\.[0-9]+$", "", x)
  ids <- if (identical(species, "Pseudorasbora parva")) {
    c("PPARVA_A", "PPARVA_B")
  } else if (identical(species, "Cyprinus carpio")) {
    c("CARPIO_A", "CARPIO_B")
  } else character(0L)
  ids <- ids[!strip_v(ids) %in% strip_v(exclude)]
  utils::head(ids, max_records)
}
# .blast_against_comparison_set()'s own ENTREZ_QUERY-restricted comparison-
# set calls (asv_id always "flagged_query") -- returns the UNION of every
# real comparison accession's own hit; PPARVA_B is deliberately low-coverage
# (15%, below the 50% default floor), the real coverage-blindness case this
# function's Option A fix exists to catch honestly rather than silently.
.iv_mock_blast_remote <- function(seq_df, database, program, megablast, max_target_seqs,
                                  batch_size, email, ncbi_api_key, verbose,
                                  entrez_query = NULL) {
  data.frame(
    sacc = c("PPARVA_A", "PPARVA_B", "CARPIO_A", "CARPIO_B"),
    pident = c(97, 99, 100, 100), qcovs = c(90, 15, 96, 94),
    stringsAsFactors = FALSE
  )
}
# ACC_FLAG's own disagreeing-taxon DISCOVERY re-BLAST (blast_sequences()) --
# HIT_SAMEBATCH is same-submission-batch with ACC_FLAG (dates 2 days apart)
# so gets excluded from the independent-hit set, same independence-filter
# check evaluate_reference_accessions() itself applies.
.iv_mock_blast <- function(seq_df, method = "remote", database = "nt",
                           score_range = 8, min_score = 70, max_hits = 20L,
                           resolve_taxonomy = TRUE, ...) {
  data.frame(
    observation_id = seq_df$asv_id[1L],
    accession = c("HIT_CARPIO1", "HIT_SAMEBATCH"),
    score = c(99.5, 99.8), query_coverage = c(97, 98),
    species = c("Cyprinus carpio", "Cyprinus carpio"),
    stringsAsFactors = FALSE
  )
}
run_iv_mocks <- function(expr) {
  local_mocked_bindings(
    .fetch_reference_accession_records = .iv_mock_fetch_records,
    .search_species_accessions = .iv_mock_search_species,
    blast_sequences = .iv_mock_blast,
    .blast_remote = .iv_mock_blast_remote,
    .package = "TaxaMatch"
  )
  force(expr)
}

## ---- investigate_flagged_accession() ---- OFFLINE(mock), mocked BLAST/NCBI --------
investigate_result <- run_iv_mocks({
  investigate_flagged_accession("ACC_FLAG", cache_dir = NULL, verbose = FALSE)
})
investigate_result$disagreeing_taxon
investigate_result$conspecific_comparison[, c("accession", "pident", "meets_min_coverage")]

## ---- investigate_flagged_accessions() ---- OFFLINE(mock), plural batch wrapper ----
investigate_batch <- run_iv_mocks({
  investigate_flagged_accessions(c("ACC_FLAG"), cache_dir = NULL, verbose = FALSE)
})
names(investigate_batch)
investigate_batch[["ACC_FLAG"]]$listed_species

## ---- .blast_against_comparison_set() ---- OFFLINE(mock) ---------------------------
run_iv_mocks({
  TaxaMatch:::.blast_against_comparison_set(
    "QUERYSEQ",
    data.frame(accession = c("PPARVA_A", "PPARVA_B"),
              sequence = c("X", "Y"), create_date = c("2019/05/01", "2018/03/01"),
              stringsAsFactors = FALSE),
    min_coverage = 0.5, verbose = FALSE
  )
})

## ---- .get_species_comparison_meta() ---- OFFLINE(mock) ----------------------------
run_iv_mocks({
  TaxaMatch:::.get_species_comparison_meta(
    "Pseudorasbora parva", exclude_accession = "ACC_FLAG", max_related = 30L,
    reference_length = 8, ncbi_api_key = NULL, verbose = FALSE
  )
})

## ---- .investigate_flagged_accession_core() ---- OFFLINE(mock) ---------------------
core_result <- run_iv_mocks({
  TaxaMatch:::.investigate_flagged_accession_core(
    "ACC_FLAG", species = NULL, max_related = 30L, method = "remote", database = "nt",
    score_range = 8, min_score = 70, max_hits = 20L, submission_window = 5L,
    min_coverage = 0.5, ncbi_api_key = NULL, verbose = FALSE
  )
})
core_result$listed_species

## ---- .investigate_verdict() ---- OFFLINE, chained off investigate_result ----------
TaxaMatch:::.investigate_verdict(investigate_result)

## ---- .print_investigation_summary() ---- OFFLINE, chained off investigate_result --
TaxaMatch:::.print_investigation_summary(investigate_result, min_coverage = 0.5)

## ---- .investigate_params_key() ---- OFFLINE ----------------------------------------
iv_params_key <- TaxaMatch:::.investigate_params_key(
  max_related = 30L, method = "remote", database = "nt", score_range = 8,
  min_score = 70, max_hits = 20L, submission_window = 5L, min_coverage = 0.5,
  max_length_ratio = 3
)
iv_params_key

## ---- .load_investigate_cache() / .save_investigate_cache() ---- OFFLINE -----------
iv_cache_dir    <- tempfile("iv_cache")
empty_iv_cache  <- TaxaMatch:::.load_investigate_cache(iv_cache_dir)  # dir doesn't exist yet
nrow(empty_iv_cache)
TaxaMatch:::.save_investigate_cache(iv_cache_dir, empty_iv_cache)
list.files(iv_cache_dir)

## ---- .store_investigate_result() / .lookup_investigate_cache() ---- OFFLINE, chained ----
iv_cache1 <- TaxaMatch:::.store_investigate_result(
  iv_cache_dir, empty_iv_cache, accession = "ACC_FLAG",
  species_key = "Pseudorasbora parva", params_key = iv_params_key,
  result = investigate_result
)
iv_cache_reloaded <- TaxaMatch:::.load_investigate_cache(iv_cache_dir)
TaxaMatch:::.lookup_investigate_cache(
  iv_cache_reloaded, "ACC_FLAG", "Pseudorasbora parva", iv_params_key,
  inconclusive_ttl_days = 30
)$verdict


# ==============================================================================
# CLUSTER 3 -- LLM second-look reviewer (2026-08-13)
# review_flagged_accessions(), implementing Question 2 of ecosystem_docs/
# REENTRY_PROMPT_flagged_accession_second_look.md. Unlike Cluster 2, this
# cluster makes NO network/NCBI/BLAST call of any kind -- every section below
# passes a local stub function as `llm_fn` (a real, first-class parameter,
# not a workaround; see TaxaFlag::review_assignments()'s identical
# convention), so nothing here costs money or requires credentials.
#
# The fixture below (.review_evaluated_df_fixture()) is reused verbatim from
# tests/testthat/test-review-flagged-accessions.R's own .base_evaluated_df()
# -- 4 accessions spanning every scope case: ACC001 (congruent, species-
# resolved -- out of scope by default), ACC002 (incongruent, real diverse
# disagreement -- the Stereolepis doederleini shape), ACC003 (incongruent
# AND not species-resolved -- the NC_028197/"Serranidae sp. JL-2015" shape),
# ACC004 (insufficient_independent_evidence).
# ==============================================================================

.review_evaluated_df_fixture <- function() {
  data.frame(
    accession = c("ACC001", "ACC002", "ACC003", "ACC004"),
    listed_taxon = c("Menidia beryllina", "Stereolepis doederleini",
                     "Serranidae sp. JL-2015", "Cottus asper"),
    hierarchy_flag = c("congruent", "incongruent",
                       "incongruent", "insufficient_independent_evidence"),
    finest_common_rank = c("species", "order", "class", NA_character_),
    best_agreeing_pident = c(99.5, NA_real_, NA_real_, NA_real_),
    best_disagreeing_pident = c(NA_real_, 95.2, 87.3, NA_real_),
    best_disagreeing_taxon = c(NA_character_, "Sinipercidae sp.",
                               "Serranidae sp. JL-2015", NA_character_),
    congruent_evidence_exists_anywhere = c(TRUE, FALSE, FALSE, FALSE),
    congruent_evidence_best_pident = c(99.5, NA_real_, NA_real_, NA_real_),
    taxonomy_resolution_source = c("direct", "direct", "direct", "direct"),
    listed_taxon_is_species = c(TRUE, TRUE, FALSE, TRUE),
    n_independent_top_matches = c(5L, 5L, 1L, 1L),
    n_top_matches_available = c(5L, 5L, 3L, 1L),
    frac_independent_below_min_congruent_rank = c(0.09, 0.9, 0.75, 0.5),
    stringsAsFactors = FALSE
  )
}

# A stub llm_fn that inspects the real prompt content and answers in the
# real requested JSON shape -- demonstrates the actual request/response
# contract review_flagged_accessions() expects from any llm_fn, real or
# stubbed (see TaxaTools::call_api()'s own signature).
.review_stub_llm_fn <- function(prompt, ...) {
  accs <- unique(regmatches(prompt, gregexpr("ACC00[0-9]", prompt))[[1]])
  jsonlite::toJSON(data.frame(
    accession = accs,
    accession_likely_explanation = ifelse(
      accs == "ACC003", "hybrid_or_specimen_code_artifact", "poor_marker_resolution"
    ),
    accession_review_confidence = "high",
    accession_review_comment = paste("Stub reviewer comment for", accs),
    stringsAsFactors = FALSE
  ), auto_unbox = TRUE)
}

## ---- .build_accession_review_prompt() ---- OFFLINE ---------------------------------
# The prompt itself -- includes the evaluation guide's 5-category framework
# and one line per in-scope accession (all 4 shown here regardless of real
# scope, since this internal helper builds a prompt for whatever batch it's
# handed; review_flagged_accessions() itself does the scope filtering before
# calling it).
review_prompt <- TaxaMatch:::.build_accession_review_prompt(.review_evaluated_df_fixture())
cat(substr(review_prompt, 1, 600), "...\n")
grepl("best_disagreeing_taxon=\"Sinipercidae sp.\"", review_prompt, fixed = TRUE)

## ---- .parse_accession_review_response() ---- OFFLINE -------------------------------
raw_response <- .review_stub_llm_fn(review_prompt)
parsed_review <- TaxaMatch:::.parse_accession_review_response(
  raw_response, .review_evaluated_df_fixture()
)
parsed_review[, c("accession", "accession_likely_explanation", "accession_review_comment")]
attr(parsed_review, "status")  # "complete" -- all 4 accessions recovered

## ---- .recover_truncated_accession_json() ---- OFFLINE, truncated-response recovery --
# A response cut off mid-object (e.g. hit a real max_tokens ceiling) --
# salvages every COMPLETE object before the cut, same strategy
# review_assignments()'s own .recover_truncated_json() uses.
truncated_json <- '[{"accession":"ACC002","accession_likely_explanation":"poor_marker_resolution","accession_review_confidence":"high","accession_review_comment":"Real diverse disagreement across families."},{"accession":"ACC003","accession_likely_e'
recovered <- TaxaMatch:::.recover_truncated_accession_json(truncated_json)
recovered$accession  # "ACC002" only -- the second (cut-off) object is correctly dropped

## ---- .review_accession_batch_with_retry() ---- OFFLINE, stub llm_fn ----------------
retry_result <- TaxaMatch:::.review_accession_batch_with_retry(
  .review_evaluated_df_fixture()[2:4, ], llm_fn = .review_stub_llm_fn,
  max_tokens = NULL, verbose = FALSE, pause_seconds = 0,
  batch_label = "1", max_retries = 2L
)
retry_result[, c("accession", "accession_likely_explanation", "accession_review_confidence")]

## ---- review_flagged_accessions() ---- OFFLINE(stub llm_fn) -------------------------
# End-to-end: default scope selects ACC002/ACC003/ACC004 (ACC001 is
# congruent + species-resolved, correctly excluded); ACC003's
# listed_taxon_is_species = FALSE would keep it in scope even if it were
# "congruent" (include_non_species_resolved = TRUE default), demonstrating
# the two scope axes are independent.
reviewed_df <- review_flagged_accessions(
  .review_evaluated_df_fixture(), llm_fn = .review_stub_llm_fn, verbose = FALSE
)
reviewed_df[, c("accession", "hierarchy_flag", "accession_likely_explanation",
                "accession_review_confidence", "accession_review_comment")]

# Real, exact prompt(s) sent, named by batch (with "a"/"b" retry-sub-batch
# suffixes when a batch was split) -- inspect before trusting an unexpected
# review, or when tuning hierarchy_flags/include_non_species_resolved:
names(attr(reviewed_df, "llm_prompts"))
