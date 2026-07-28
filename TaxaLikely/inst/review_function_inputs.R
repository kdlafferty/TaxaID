# ==============================================================================
# review_function_inputs.R
# TaxaLikely -- small, ready-to-run inputs for every exported function
#
# PURPOSE
# -------
# Prepared for external code review: gives the reviewer a concrete, small
# input for each of the package's 35 exported functions so it can actually be
# run/tested, without having to reverse-engineer arguments from source or from
# production workflows that fetch/train on thousands of real sequences.
# Modeled on TaxaFetch/inst/review_function_inputs.R (same monorepo).
#
# Three functions deliberately NOT covered here because they no longer exist:
# fetch_reference_sequences() and audit_barcode_coverage_ncbi() were both
# `.Deprecated()` forwarding aliases kept from earlier renames
# (-> fetch_ncbi_reference_sequences() / audit_barcode_coverage());
# expand_consensus_candidates() was a superseded design pathway (deprecated
# Session 99, -> unreferenced_candidates() + assign_scores()), removed along
# with its own dedicated teaching workflow (inst/workflows/
# expand_consensus_demo.R). Since this package has no external users yet,
# keeping (and reviewing/testing) migration paths nobody needs was pure
# unreviewed surface -- all three removed entirely after confirming no real
# production callers remained; fetch_reference_sequences() did have 4 real
# in-monorepo callers (2 vignettes, 2 diagnostics/ scripts), all updated to
# call the current name directly first. See NAME_CHANGE_HISTORY.md.
#
# Inputs are pulled from three sources, cheapest first:
#   1. Existing testthat fixtures (already validated, fully offline) -- the
#      large majority of sections below
#   2. Real small values taken from production workflow scripts / roxygen
#      @examples elsewhere in this package (kept small/limited deliberately)
#   3. New small synthetic inputs constructed for this file where no fixture
#      or workflow example existed, or where a natural (not hand-set) DECIPHER
#      alignment result was wanted (Section 2)
#
# REQUIRES tags (read before running a section):
#   OFFLINE        -- pure function or fully self-contained input; no network
#   OFFLINE+BIOC    -- offline, but needs DECIPHER + Biostrings (Bioconductor,
#                      Suggests) installed; both are present on this machine
#   NETWORK        -- hits a public API, no credentials needed (NCBI via
#                     rentrez, BOLD Systems, iNaturalist); small/fast by
#                     construction here
#   NETWORK+AUTH   -- needs a registered API key in addition to network access
#
# Run OFFLINE/OFFLINE+BIOC/NETWORK sections freely -- none need credentials.
# The one NETWORK+AUTH section (Xeno-canto) is guarded by RUN_XC_FETCH below,
# default FALSE, since a reviewer is unlikely to have their own XC_API_KEY.
#
# GAP NOTE: audit_inat_coverage(), calibrate_coverage_filter(),
# coverage_threshold(), identify_confident_observations(), and
# infer_exclude_predicted() had zero existing testthat coverage before this
# session (confirmed by grepping tests/testthat/ for each name) -- new test
# files were added for all five as part of the same review-prep pass that
# produced this file (test-audit-inat-coverage.R, test-calibrate.R,
# test-identify-confident-observations.R, test-infer-exclude-predicted.R).
# This file's examples for those five are therefore drawn from the same
# fixtures now backing real regression tests, not invented fresh for this
# file alone. (A sixth, audit_barcode_coverage_ncbi(), was also closed this
# way but the function itself was later deleted entirely -- see above.)
#
# NON-DETERMINISM NOTE: Sections tagged NETWORK hit real, live NCBI/BOLD/
# iNaturalist services. Exact counts (e.g. audit_barcode_coverage()'s
# unreferenced-species list) can drift over time as those databases grow --
# that is expected and not a bug. Every NETWORK call here is deliberately
# scoped to a single small, well-referenced genus (Fundulus) so it stays fast
# regardless. Live-verified while preparing this file: audit_reference_
# coverage()'s own per-genus NCBI taxonomy query hit one transient HTTP 502
# ("bad gateway") on a real run -- caught internally by that function's own
# tryCatch and did not affect the final result (real, non-NA census row
# still returned). Occasional transient NCBI errors are a real, expected
# property of live network calls, not a code bug; re-running usually clears
# it, same as TaxaFetch's own review_function_inputs.R documents.
# ==============================================================================

#devtools::load_all()   # or: library(TaxaLikely)
library(TaxaLikely)
library(tibble)

# Flip to TRUE only if you have registered your own Xeno-canto API key
# (https://xeno-canto.org/explore/api) and set XC_API_KEY in ~/.Renviron.
RUN_XC_FETCH <- FALSE


# ==============================================================================
# SECTION 1 -- Reference acquisition (build reference_df)
# fetch_ncbi_reference_sequences() / fetch_bold_reference_sequences() /
# read_crabs_output() / read_reference_fasta() / subset_local_database() /
# trim_to_amplicon()
# ==============================================================================

## ---- fetch_ncbi_reference_sequences() ---- NETWORK, small real genus -------
# Fundulus + MiFishU, capped small (real max_per_species/max_sequences from
# the man page's own example, scaled down further for speed).
ref_ncbi <- fetch_ncbi_reference_sequences(
  taxa            = "Fundulus",
  barcode_term    = "MiFishU",
  max_per_species = 2L,
  max_sequences   = 20L
)
str(ref_ncbi)

## ---- fetch_bold_reference_sequences() ---- NETWORK, real BOLD v5 API -------
ref_bold <- fetch_bold_reference_sequences(
  taxa         = "Fundulus",
  barcode_term = "COI-5P",
  max_per_species = 2L
)
str(ref_bold)

## ---- read_crabs_output() ---- OFFLINE ---------------------------------------
# CRABS internal-format TSV: accession|taxid_string|ncbi_tax_number|kingdom|
# phylum|class|order|family|genus|species|sequence (no header, tab-delimited).
# Pattern reused verbatim from tests/testthat/test-read-crabs.R.
crabs_row <- function(acc, species = "Fundulus heteroclitus", seq = "ATCGATCGATCGATCG") {
  paste(c(acc, "12345", "9999", "Eukaryota", "Chordata", "Actinopteri",
          "Cyprinodontiformes", "Fundulidae", "Fundulus", species, seq),
        collapse = "\t")
}
crabs_file <- tempfile(fileext = ".tsv")
writeLines(c(crabs_row("ACC001.1"),
             crabs_row("ACC002.1", species = "Fundulus parvipinnis",
                       seq = "GCTAGCTAGCTAGCTA")),
           crabs_file)
ref_crabs <- read_crabs_output(crabs_file, rank_system = c("family", "genus", "species"))
ref_crabs

## ---- read_reference_fasta() ---- OFFLINE ------------------------------------
# Option A: taxonomy as a data frame.
fasta_file <- tempfile(fileext = ".fasta")
writeLines(c(">ACC001", "ATCGATCG", ">ACC002", "GCTAGCTA"), fasta_file)
tax_df <- data.frame(
  composite_id = c("ACC001", "ACC002"),
  family       = c("Fundulidae", "Atherinopsidae"),
  genus        = c("Fundulus", "Atherinops"),
  species      = c("Fundulus parvipinnis", "Atherinops affinis"),
  stringsAsFactors = FALSE
)
ref_fasta_a <- read_reference_fasta(fasta_file, taxonomy = tax_df,
                                     rank_system = c("family", "genus", "species"))
ref_fasta_a

# Option B: QIIME2/RESCRIPt-style prefix taxonomy file instead of a data frame.
tax_tsv <- tempfile(fileext = ".tsv")
writeLines("ACC001\tf__Fundulidae;g__Fundulus;s__Fundulus heteroclitus", tax_tsv)
fasta_file_b <- tempfile(fileext = ".fasta")
writeLines(c(">ACC001", "ATCGATCG"), fasta_file_b)
ref_fasta_b <- read_reference_fasta(fasta_file_b,
                                     rank_system   = c("family", "genus", "species"),
                                     taxonomy_file = tax_tsv)
ref_fasta_b

## ---- subset_local_database() ---- OFFLINE -----------------------------------
# Tiny synthetic local FASTA + positional (no-prefix) taxonomy TSV, mirroring
# tests/testthat/test-subset-local-database.R's fixture shape (a real SILVA/
# PR2/MIDORI2/CRUX download is multi-GB and not something to bundle here).
local_fasta <- tempfile(fileext = ".fasta")
writeLines(c(">ACC001 extra header text", "ATCGATCGATCG",
             ">ACC002 extra header text", "GCTAGCTAGCTA",
             ">ACC003 extra header text", "TTTTCCCCAAAA"),
           local_fasta)
local_tax <- tempfile(fileext = ".tsv")
writeLines(c(
  "ACC001\tEukaryota;Chordata;Actinopteri;Cyprinodontiformes;Fundulidae;Fundulus;Fundulus heteroclitus",
  "ACC002\tEukaryota;Chordata;Actinopteri;Cyprinodontiformes;Fundulidae;Fundulus;Fundulus parvipinnis",
  "ACC003\tEukaryota;Chordata;Actinopteri;Gobiiformes;Gobiidae;Gillichthys;Gillichthys mirabilis"
), local_tax)
ref_subset <- subset_local_database(
  local_fasta, taxa = "Fundulidae", rank = "family",
  rank_system   = c("family", "genus", "species"),
  taxonomy_file = local_tax
)
ref_subset

## ---- trim_to_amplicon() ---- OFFLINE+BIOC -----------------------------------
# A broad NCBI text search often returns off-target sequences with NO MiFish
# primer site at all (see this package's own "Known Footguns" note on the
# Sebastes/Paralabrax 0%-rescue finding) -- so a synthetic over-length
# sequence built around the real, literature-verified MiFish-U primer pair is
# used here instead, guaranteeing a real, deterministic rescue for review.
mf_fwd <- "GTCGGTAAAACTCGTGCCAGC"
mf_rev <- "CATAGTGGGGTATCTAATCCCAGTTTG"
mf_rev_rc <- as.character(Biostrings::reverseComplement(Biostrings::DNAString(mf_rev)))
mf_amplicon <- paste0(mf_fwd, paste(rep("AAACCCGGGTTT", 3), collapse = ""), mf_rev_rc)
mf_genome <- paste0(strrep("N", 300L), mf_amplicon, strrep("A", 300L))
ref_overlength <- data.frame(composite_id = "MITO1", sequence = mf_genome,
                             stringsAsFactors = FALSE)
ref_trimmed <- trim_to_amplicon(ref_overlength, barcode_term = "MiFishU",
                                 min_len = 50L, max_len = 100L)
ref_trimmed[, c("composite_id", "amplicon_trimmed", "amplicon_trim_note")]
nchar(ref_trimmed$sequence)   # matches mf_amplicon's own length exactly


# ==============================================================================
# SECTION 2 -- Training (fit model on reference database)
# build_sequence_matrix() -> flag_reference_errors() -> train_likelihood_model()
# ==============================================================================

## ---- build_sequence_matrix() ---- OFFLINE+BIOC ------------------------------
# 5 synthetic sequences, 2 species in 2 genera. S3 is a truncated copy of S1
# (60bp of a 120bp sequence) so DECIPHER's real alignment produces genuinely
# varying `coverage` values -- deliberately NOT hand-set, so Section 8's
# calibrate_coverage_filter()/coverage_threshold() have real signal to work
# with, not a single constant.
seq_a       <- paste(rep("ATGCATGCATGC", 10), collapse = "")   # 120bp, species Aa
seq_b       <- paste(rep("ATGCATGCATGG", 10), collapse = "")   # 120bp, species Aa
seq_c_short <- substr(seq_a, 1, 60)                            # 60bp,  species Aa (truncated)
seq_d       <- paste(rep("GCTAGCTAGCTA", 10), collapse = "")   # 120bp, species Bb
seq_e       <- paste(rep("GCTAGCTAGCTG", 10), collapse = "")   # 120bp, species Bb

reference_df_train <- data.frame(
  composite_id = c("S1", "S2", "S3", "S4", "S5"),
  sequence     = c(seq_a, seq_b, seq_c_short, seq_d, seq_e),
  genus        = c("A", "A", "A", "B", "B"),
  species      = c("Aa", "Aa", "Aa", "Bb", "Bb"),
  stringsAsFactors = FALSE
)
ref_matrix <- build_sequence_matrix(reference_df_train,
                                     rank_system = c("genus", "species"),
                                     max_dist    = 1.0)
str(ref_matrix)
range(ref_matrix$coverage)   # non-degenerate: truncated S3 pulls some pairs down

## ---- flag_reference_errors() ---- OFFLINE -----------------------------------
# Clean fixture -- expect zero flagged rows by default; return_all = TRUE
# shows the full per-sequence QC table instead (all "clean").
errors_none <- flag_reference_errors(ref_matrix)
nrow(errors_none)                                    # 0
errors_all  <- flag_reference_errors(ref_matrix, return_all = TRUE)
table(errors_all$error_type)

## ---- train_likelihood_model() ---- OFFLINE ----------------------------------
# use_hierarchy = FALSE: this fixture is too small (2 taxonomic levels, 5
# sequences) for lme4's hierarchy fit to be meaningful; the function would
# fall back gracefully anyway (documented in Known Footguns), disabled here
# to keep this section's message output focused on the training step itself.
trained_model <- train_likelihood_model(ref_matrix, rank_system = c("genus", "species"),
                                         use_hierarchy = FALSE)
trained_model$H1_Lookup
trained_model$Stats

## ---- train_likelihood_model(score_transform = "sqrt_mismatch") -------------
# Demonstrates that train_likelihood_model() accepts ANY correctly-shaped
# pairwise data frame (id_x/id_y/species.x/species.y/genus.x/genus.y/p_match),
# not only build_sequence_matrix() output -- and shows the Session 158
# per-genus H2_Lookup (genus-specific congener-divergence delta). Fixture
# reused verbatim from tests/testthat/test-train.R's .make_genus_raw_df():
# two real congener pairs of differing tightness (Fundulus: 0.90: Loose: 0.75)
# plus a monotypic genus (Distant) whose only foreign matches are cross-genus
# and must NOT contaminate the pooled H2 delta (Session 158 fix).
make_genus_raw_df <- function() {
  ids <- c("L1", "L2", "M1", "M2", "A1", "A2", "B1", "B2", "D1", "D2")
  species_map <- c(L1 = "lima", L2 = "lima", M1 = "heteroclitus", M2 = "heteroclitus",
                   A1 = "aa", A2 = "aa", B1 = "bb", B2 = "bb",
                   D1 = "distantus", D2 = "distantus")
  genus_map <- c(L1 = "Fundulus", L2 = "Fundulus", M1 = "Fundulus", M2 = "Fundulus",
                A1 = "Loose", A2 = "Loose", B1 = "Loose", B2 = "Loose",
                D1 = "Distant", D2 = "Distant")
  grid <- expand.grid(id_x = ids, id_y = ids, stringsAsFactors = FALSE)
  grid$species.x <- species_map[grid$id_x]
  grid$species.y <- species_map[grid$id_y]
  grid$genus.x   <- genus_map[grid$id_x]
  grid$genus.y   <- genus_map[grid$id_y]
  grid$p_match <- mapply(function(x, y, sx, sy, gx, gy) {
    if (x == y) return(1.00)
    if (sx == sy) return(0.97)
    if (gx == gy && gx == "Fundulus") return(0.90)
    if (gx == gy && gx == "Loose")    return(0.75)
    0.70
  }, grid$id_x, grid$id_y, grid$species.x, grid$species.y, grid$genus.x, grid$genus.y)
  grid
}
trained_model_sqrt <- train_likelihood_model(make_genus_raw_df(), c("genus", "species"),
                                              use_hierarchy = FALSE, anchor_perfect = FALSE,
                                              score_transform = "sqrt_mismatch")
trained_model_sqrt$H2_Lookup   # Fundulus's tighter delta vs. Loose's looser one


# ==============================================================================
# SECTION 3 -- Unified likelihood pipeline
# unreferenced_candidates() -> assign_scores() -> model_likelihoods() /
# compute_likelihoods()
# ==============================================================================

## ---- unreferenced_candidates() ---- OFFLINE ---------------------------------
# Fixture reused verbatim from tests/testthat/test-unreferenced-candidates.R.
make_uc_match <- function() {
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
hyp_df <- unreferenced_candidates(make_uc_match(), rank_system = c("family", "genus", "species"))
table(hyp_df$hypothesis_type)

## ---- assign_scores() ---- OFFLINE --------------------------------------------
# score_type = "none": all likelihoods 1.0 (morphology/expert IDs, no scores).
# hyp_df's own score_original column is non-NA (from make_uc_match()) -- the
# expected "scores will be ignored" warning below is the function correctly
# telling the caller their score column is going unused, not an error.
liks_none <- suppressWarnings(assign_scores(hyp_df, score_type = "none"))
range(liks_none$score_likelihood)

# score_type = "probability" expects scores already on a 0-1 scale (unlike
# "similarity"/"similarity_softmax", which auto-detect and normalize any
# scale) -- rescale make_uc_match()'s 0-100 scores first, matching the
# convention tests/testthat/test-assign-scores.R's own fixture uses.
match_01 <- make_uc_match()
match_01$score_original <- match_01$score_original / 100
hyp_df_01 <- unreferenced_candidates(match_01, rank_system = c("family", "genus", "species"))
liks_prob <- assign_scores(hyp_df_01, score_type = "probability")
liks_prob[liks_prob$observation_id == "ESV_001",
          c("taxon_name", "hypothesis_type", "score_likelihood")]

# score_type = "similarity": adds score_norm only, feeds model_likelihoods().
sc_df <- assign_scores(hyp_df, score_type = "similarity")
sc_df[, c("taxon_name", "hypothesis_type", "score_norm")]

## ---- model_likelihoods() ---- OFFLINE ---------------------------------------
# Minimal hand-built model_params (same fixture pattern as
# tests/testthat/test-compute-likelihoods.R) -- deterministic, avoids
# depending on Section 2's live-trained model matching these taxon names.
make_model_params_small <- function() {
  sigma <- matrix(c(2.0, 0.2, 0.2, 1.0), nrow = 2L,
                  dimnames = list(c("score_logit", "gap_logit"),
                                  c("score_logit", "gap_logit")))
  h2s <- diag(2); rownames(h2s) <- colnames(h2s) <- c("score_logit", "gap_logit")
  h3s <- diag(2); rownames(h3s) <- colnames(h3s) <- c("score_logit", "gap_logit")
  structure(
    list(
      H1_Lookup    = data.frame(lookup_key  = "Hybognathus nuchalis", rank = "species",
                                mu_score = 4.5, mu_gap = 2.0, sigma_score = 2.0,
                                stringsAsFactors = FALSE),
      H1_Global_Mu = c(score_logit = 3.5, gap_logit = 1.5),
      H1_Sigma     = sigma,
      H2           = list(delta = 3.0, sigma = h2s),
      H3           = list(delta = 5.0, sigma = h3s),
      Stats        = list(n_species = 1L, n_singletons = 0L)
    ),
    class = "taxa_model_params"
  )
}
model_small <- make_model_params_small()
model_lik_result <- model_likelihoods(sc_df, model_params = model_small,
                                       rank_system = c("family", "genus", "species"))
head(model_lik_result$likelihoods)

## ---- compute_likelihoods() ---- OFFLINE -------------------------------------
# Orchestrating wrapper: unreferenced_candidates() + assign_scores() +
# (for "similarity") model_likelihoods(), in one call.
# Same expected "scores will be ignored" warning as assign_scores() above.
compute_none <- suppressWarnings(compute_likelihoods(make_uc_match(), score_type = "none"))
head(compute_none$likelihoods)

compute_similarity <- compute_likelihoods(
  make_uc_match(), score_type = "similarity",
  model_params = model_small, rank_system = c("family", "genus", "species"),
  n_sims = 50L
)
head(compute_similarity$likelihoods)


# ==============================================================================
# SECTION 4 -- Training-database bias correction
# correct_training_bias()
# ==============================================================================

## ---- correct_training_bias() ---- OFFLINE -----------------------------------
# Real example from this function's own roxygen: a common species
# (500,000 iNat observations) should not automatically outrank a much rarer
# one (20 observations) purely because it's better-represented in the
# classifier's training data.
scored <- data.frame(
  observation_id = c("obs1", "obs1", "obs2"),
  taxon_name     = c("Turdus migratorius", "Turdus merula", "Limosa fedoa"),
  score_original = c(0.9, 0.85, 0.6),
  n_observations = c(500000, 20, 300)
)
corrected <- correct_training_bias(scored, count_col = "n_observations", tau = 1)
corrected[, c("taxon_name", "score_uncorrected", "score_original", "n_used", "tau_used")]
# Default tau = 0 (Session 151): every real calibration run so far (image,
# acoustic) found tau ~= 0 optimal, so a caller who does nothing gets no
# correction -- confirm this leaves scores unchanged:
identical(correct_training_bias(scored, count_col = "n_observations")$score_original,
          scored$score_original)


# ==============================================================================
# SECTION 5 -- Query-side calibration
# identify_confident_observations() -> calibrate_query_noise()
# ==============================================================================

## ---- identify_confident_observations() ---- OFFLINE -------------------------
# 40 confident observations at 95% identity, one genus with exactly one
# locally-plausible species (the non-circular calibration set) -- fixture
# reused verbatim from tests/testthat/test-calibrate_query_noise.R.
make_calib_match_df <- function() {
  data.frame(observation_id = paste0("Q", 1:40), genus = "Genusone",
             score_original = 95.0, stringsAsFactors = FALSE)
}
make_calib_priors <- function() {
  data.frame(taxon_name = "Genusone speciesa", taxon_name_rank = "species",
             theta_mean = 0.5, stringsAsFactors = FALSE)
}
confident_obs <- identify_confident_observations(make_calib_match_df(), make_calib_priors())
nrow(confident_obs)

## ---- calibrate_query_noise() ---- OFFLINE -----------------------------------
make_calib_model_params <- function(score_transform = "logit") {
  sigma <- matrix(c(2.0, 0.2, 0.2, 1.0), nrow = 2L,
                  dimnames = list(c("score_logit", "gap_logit"),
                                  c("score_logit", "gap_logit")))
  structure(
    list(
      H1_Lookup    = data.frame(lookup_key = "Genusone speciesa", rank = "species",
                                mu_score = 4.5, mu_gap = 2.0, sigma_score = 2.0,
                                stringsAsFactors = FALSE),
      H1_Global_Mu = c(score_logit = 3.5, gap_logit = 1.5),
      H1_Sigma     = sigma,
      H2           = list(delta = 3.0, sigma = diag(2)),
      H3           = list(delta = 5.0, sigma = diag(2)),
      Stats        = list(n_species = 1L, n_singletons = 0L),
      Score_Transform = score_transform
    ),
    class = "taxa_model_params"
  )
}
# offset_form = "constant": this single-species fixture is too thin for the
# affine "linear" fit (needs >= min_calib_species, default 8) -- pass
# "constant" explicitly rather than relying on the (linear, with fallback)
# default, so this section demonstrates the calibration itself, not the
# fallback warning (Section 8's calibrate_coverage_filter... no, see Section
# 5's own multi-species variant below for the "linear" path).
model_calibrated <- calibrate_query_noise(
  make_calib_model_params("logit"), make_calib_match_df(), make_calib_priors(),
  offset_form = "constant", min_confident_obs = 30L
)
model_calibrated$Query_Calibration

# offset_form = "linear": needs multiple confident species spanning a range
# of trained means to fit a slope -- fixture reused from the same test file's
# .make_multi_species_fixture(), 10 species/4 obs each, constant real gap
# (slope should recover ~1, i.e. degrade gracefully to the constant case).
make_multi_species_fixture <- function(n_species = 10L, n_obs_each = 4L,
                                        mu_range = c(3.0, 5.0), score_fn) {
  mu <- seq(mu_range[1L], mu_range[2L], length.out = n_species)
  keys <- sprintf("Genus%02d species%02d", seq_len(n_species), seq_len(n_species))
  h1 <- data.frame(lookup_key = keys, rank = "species", mu_score = mu, mu_gap = 2.0,
                   sigma_score = 2.0, stringsAsFactors = FALSE)
  params <- structure(
    list(H1_Lookup = h1, H1_Global_Mu = c(score_logit = mean(mu), gap_logit = 1.5),
         H1_Sigma = matrix(c(2.0, 0.2, 0.2, 1.0), 2L,
                           dimnames = list(c("score_logit", "gap_logit"),
                                           c("score_logit", "gap_logit"))),
         H2 = list(delta = 3.0, sigma = diag(2)), H3 = list(delta = 5.0, sigma = diag(2)),
         Stats = list(n_species = n_species), Score_Transform = "logit"),
    class = "taxa_model_params")
  rows <- do.call(rbind, lapply(seq_len(n_species), function(i) {
    data.frame(observation_id = sprintf("Q%02d_%d", i, seq_len(n_obs_each)),
               genus = sprintf("Genus%02d", i), score_original = score_fn(mu[i]),
               stringsAsFactors = FALSE)
  }))
  priors <- data.frame(taxon_name = keys, taxon_name_rank = "species",
                       theta_mean = 0.5, stringsAsFactors = FALSE)
  list(params = params, match_df = rows, priors = priors, mu = mu)
}
fx <- make_multi_species_fixture(score_fn = function(mu) rep(100 * stats::plogis(mu - 0.8), 4L))
model_calibrated_linear <- calibrate_query_noise(fx$params, fx$match_df, fx$priors,
                                                  offset_form = "linear",
                                                  min_confident_obs = 30L)
model_calibrated_linear$Query_Calibration[c("offset_form", "slope", "intercept")]


# ==============================================================================
# SECTION 6 -- Inference (apply model to query observations)
# evaluate_likelihoods() -> filter_top_hypotheses()
# ==============================================================================

## ---- evaluate_likelihoods() ---- OFFLINE ------------------------------------
# Fixture reused verbatim from tests/testthat/test-evaluate.R.
make_model_params_eval <- function() {
  sigma <- matrix(c(2.0, 0.2, 0.2, 1.0), nrow = 2L,
                  dimnames = list(c("score_logit", "gap_logit"),
                                  c("score_logit", "gap_logit")))
  h2s <- diag(2); rownames(h2s) <- colnames(h2s) <- c("score_logit", "gap_logit")
  h3s <- diag(2); rownames(h3s) <- colnames(h3s) <- c("score_logit", "gap_logit")
  structure(
    list(
      H1_Lookup    = data.frame(lookup_key  = "Hybognathus nuchalis", rank = "species",
                                mu_score = 4.5, mu_gap = 2.0, sigma_score = 2.0,
                                stringsAsFactors = FALSE),
      H1_Global_Mu = c(score_logit = 3.5, gap_logit = 1.5),
      H1_Sigma     = sigma,
      H2           = list(delta = 3.0, sigma = h2s),
      H3           = list(delta = 5.0, sigma = h3s),
      Stats        = list(n_species = 1L, n_singletons = 0L)
    ),
    class = "taxa_model_params"
  )
}
make_match_df_eval <- function() {
  data.frame(
    observation_id  = "ESV_001",
    score           = c(95.0, 80.0, 60.0),
    taxon_name      = c("Hybognathus nuchalis", "Rhinichthys obtusus", "Campostoma anomalum"),
    taxon_name_rank = "species",
    family          = "Leuciscidae",
    genus           = c("Hybognathus", "Rhinichthys", "Campostoma"),
    species         = c("Hybognathus nuchalis", "Rhinichthys obtusus", "Campostoma anomalum"),
    stringsAsFactors = FALSE
  )
}
eval_result <- evaluate_likelihoods(make_match_df_eval(), make_model_params_eval(),
                                     rank_system = c("family", "genus", "species"),
                                     n_sims = 100L)
eval_result$likelihoods
nrow(eval_result$unresolved)


## ---- filter_top_hypotheses() ---- OFFLINE -----------------------------------
filtered <- filter_top_hypotheses(eval_result$likelihoods,
                                   rank_system = c("family", "genus", "species"))
filtered[, c("taxon_name", "taxon_name_rank", "hypothesis_type")]


# ==============================================================================
# SECTION 7 -- Reference coverage
# infer_exclude_predicted() / audit_barcode_coverage() /
# audit_reference_coverage() / audit_acoustic_coverage() /
# audit_inat_coverage() / fetch_xc_recording_locations() /
# apply_coverage_constraints() / expand_unreferenced_hypotheses()
# ==============================================================================

## ---- infer_exclude_predicted() ---- OFFLINE ---------------------------------
# Real NCBI accession conventions (GenBank + curated RefSeq NR_) -- no XR_/XM_
# predicted records present, so exclude_predicted should be inferred TRUE.
# Fixture ported (with the rest of this function's 4-case coverage) from the
# now-deleted inst/test_infer_exclude_predicted.R into
# tests/testthat/test-infer-exclude-predicted.R this session.
match_ncbi <- data.frame(
  observation_id = paste0("ESV_", 1:6),
  accession      = c("AB123456.1", "KP891234.2", "NR_036856.1",
                     "MH213045.1", "NR_024642.1", "AB987654.1"),
  genus          = "Sebastes", species = "Sebastes mystinus", score_original = 99,
  stringsAsFactors = FALSE
)
exclude_pred <- infer_exclude_predicted(match_ncbi)
exclude_pred            # TRUE
!isFALSE(exclude_pred)  # documented usage pattern feeding exclude_predicted=

## ---- audit_barcode_coverage() ---- NETWORK, real small genus ---------------
ref_species <- data.frame(
  genus = "Fundulus",
  species = c("Fundulus heteroclitus", "Fundulus parvipinnis"),
  stringsAsFactors = FALSE
)
coverage_barcode <- audit_barcode_coverage(
  match_df     = ref_species,
  barcode_term = "12S",
  target_rank  = "genus",
  max_nuccore  = 200L
)
coverage_barcode$census
length(coverage_barcode$unreferenced)

## ---- audit_reference_coverage() ---- NETWORK, non-barcode (images/sounds) --
coverage_reference <- audit_reference_coverage(ref_species, target_rank = "genus")
coverage_reference$census

## ---- audit_acoustic_coverage() ---- OFFLINE (pure set membership) -----------
# Real example from this function's own roxygen.
plausible_birds <- c("Turdus migratorius", "Setophaga petechia",
                     "Limosa fedoa", "Selasphorus calliope")
birdnet_list <- c("Turdus migratorius", "Setophaga petechia",
                  "Turdus merula", "Corvus brachyrhynchos")
coverage_acoustic <- audit_acoustic_coverage(plausible_birds, birdnet_list)
coverage_acoustic$census
coverage_acoustic$unreferenced

## ---- audit_inat_coverage() ---- NETWORK, real species -----------------------
coverage_inat <- audit_inat_coverage(c("Calidris mauri", "Limosa fedoa"))
coverage_inat$census

## ---- fetch_xc_recording_locations() ---- NETWORK+AUTH -----------------------
if (RUN_XC_FETCH) {
  xc_locations <- fetch_xc_recording_locations(c("Turdus migratorius", "Setophaga petechia"))
  head(xc_locations)
}

## ---- apply_coverage_constraints() ---- OFFLINE ------------------------------
# Fixture reused verbatim from tests/testthat/test-coverage.R.
likelihood_df <- tibble::tibble(
  observation_id       = "ESV_001",
  taxon_name           = c("Hybognathus nuchalis", "Hybognathus", "Leuciscidae"),
  taxon_name_rank      = c("species", "genus", "family"),
  hypothesis_type      = c("specific_candidate", "unreferenced_species", "unreferenced_genus"),
  score_likelihood      = c(1.0, 0.5, 0.1),
  score_likelihood_mean = c(1.0, 0.5, 0.1),
  score_likelihood_sd   = c(0, 0, 0)
)
census_result <- data.frame(taxon_name = "Hybognathus", rank = "genus",
                            status = "complete", stringsAsFactors = FALSE)
# Default is "relabel" (non-destructive, Session 151) -- shown alongside the
# opt-in "zero" mode used in the package's own demo workflow.
constrained_relabel <- apply_coverage_constraints(likelihood_df, census_result)
constrained_relabel[, c("taxon_name", "hypothesis_type", "score_likelihood", "constraint_applied")]
constrained_zero <- apply_coverage_constraints(likelihood_df, census_result,
                                                constraint_behavior = "zero")
constrained_zero[, c("taxon_name", "hypothesis_type", "score_likelihood")]

## ---- expand_unreferenced_hypotheses() ---- OFFLINE --------------------------
# Fixture reused verbatim from tests/testthat/test-expand_unreferenced.R.
make_expand_lik <- function() {
  data.frame(
    observation_id        = "ESV_001",
    taxon_name            = c("Atherinops affinis", "Fundulus", "Fundulidae"),
    taxon_name_rank       = c("species", "genus", "family"),
    hypothesis_type       = c("specific_candidate", "unreferenced_species", "unreferenced_genus"),
    score_likelihood      = c(0.95, 0.31, 0.04),
    score_likelihood_mean = c(0.95, 0.31, 0.04),
    score_likelihood_sd   = c(0, 0, 0),
    stringsAsFactors      = FALSE
  )
}
make_unref_df <- function() {
  data.frame(
    species = c("Fundulus parvipinnis", "Fundulus zebrinus", "Lucania parva"),
    genus   = c("Fundulus", "Fundulus", "Lucania"),
    family  = c("Fundulidae", "Fundulidae", "Fundulidae"),
    stringsAsFactors = FALSE
  )
}
expanded <- expand_unreferenced_hypotheses(make_expand_lik(), make_unref_df())
expanded[, c("taxon_name", "taxon_name_rank", "hypothesis_type", "score_likelihood")]


# ==============================================================================
# SECTION 8 -- Coverage quality calibration
# calibrate_coverage_filter() / coverage_threshold()
# Chained directly off Section 2's ref_matrix (real DECIPHER alignment output,
# not hand-set coverage values).
# ==============================================================================

## ---- calibrate_coverage_filter() ---- OFFLINE --------------------------------
coverage_cal <- calibrate_coverage_filter(ref_matrix, rank_system = c("genus", "species"))
coverage_cal[, c("threshold", "breadth", "h1_retention", "h2_retention", "youden_j")]
best_threshold <- coverage_cal[which.max(coverage_cal$youden_j), ]
best_threshold

## ---- coverage_threshold() ---- OFFLINE ---------------------------------------
thresh_90 <- coverage_threshold(ref_matrix, keep_frac = 0.90)
thresh_90


# ==============================================================================
# SECTION 9 -- Score-collapse detection and restoration
# detect_suppressed_candidates() -> restore_suppressed_candidates()
# ==============================================================================

## ---- detect_suppressed_candidates() ---- OFFLINE ----------------------------
suppressed_match <- data.frame(
  observation_id = c("obs1", "obs1", "obs2"),
  score_original = c(100, 100, 99),
  taxon_name     = c("Sp_A", "Sp_B", "Sp_C"),
  stringsAsFactors = FALSE
)
detected <- detect_suppressed_candidates(suppressed_match)
detected$rule_detected
detected$rules

## ---- restore_suppressed_candidates() ---- OFFLINE ---------------------------
# The package's own documented motivating case (Girella simplicidens, Session
# 101/103): a 100%-rule BLAST pipeline suppresses referenced congeners,
# leaving only one H1 candidate. Redesigned 2026-07-18 (see this function's
# own roxygen "Score-sourcing hierarchy"/"Level 4 cost control" sections for
# the full design): admission now requires real evidence -- a bare call with
# no seq_matrix/model_params/check_regional_overlap is correctly a NO-OP
# (BREAKING vs. the pre-redesign flat anchor_score-delta imputation, which
# restored every congener unconditionally). Fixture reused verbatim from
# tests/testthat/test-score-collapse.R, including .simple_model_params().
girella_match <- data.frame(
  observation_id  = "obs1",
  score_original  = 95,
  taxon_name      = "simplicidens",
  taxon_name_rank = "species",
  family          = "Kyphosidae",
  genus           = "Girella",
  species         = "simplicidens",
  stringsAsFactors = FALSE
)
girella_ref <- data.frame(
  family       = "Kyphosidae", genus = "Girella",
  species      = c("simplicidens", "nigricans", "laevifrons"),
  composite_id = c("ACC_simplicidens", "ACC_nigricans", "ACC_laevifrons"),
  stringsAsFactors = FALSE
)

# Bare call, no evidence supplied -- confirms the new no-op default.
restored_noop <- restore_suppressed_candidates(girella_match, girella_ref,
                                                rank_system = c("family", "genus", "species"))
nrow(restored_noop)   # 1 -- nothing restored without evidence

# seq_matrix (build_sequence_matrix()-shaped reference-vs-reference pairs)
# powers the free Levels 1-3 score-sourcing hierarchy. nigricans' p_match
# (0.945) is close enough to the anchor's own 95 to also clear Purpose A's
# tight outlier test (needs model_params); laevifrons (0.80) only clears
# Purpose B's wider plausibility floor.
seq_matrix_girella <- data.frame(
  id_x     = c("ACC_simplicidens", "ACC_simplicidens"),
  id_y     = c("ACC_nigricans", "ACC_laevifrons"),
  p_match  = c(0.945, 0.80),
  coverage = 1.0,
  stringsAsFactors = FALSE
)
simple_model_params <- list(
  H1_Sigma = matrix(c(0.05, 0, 0, 1), nrow = 2,
                    dimnames = list(c("score_logit", "gap_logit"),
                                    c("score_logit", "gap_logit"))),
  H1_Lookup = NULL,
  Score_Transform = "logit"
)
restored <- restore_suppressed_candidates(
  girella_match, girella_ref, rank_system = c("family", "genus", "species"),
  seq_matrix = seq_matrix_girella, model_params = simple_model_params
)
restored[, c("species", "is_restored", "hypothesis_type", "restoration_basis", "score_original")]
# nigricans: "both" (clears Purpose A's tight score-outlier test AND Purpose
# B's wide occurrence-plausibility floor); laevifrons: "plausible_prior" only
# (Purpose B admits it, but it's too far from the anchor's own 95 for
# Purpose A's tight test).
#
# check_regional_overlap = TRUE (needs accession_col in match_obj +
# composite_id/sequence in reference_df) additionally enables Level 4's live
# pairwise alignment for candidates the free hierarchy can't resolve, and
# records anything still unresolved via attr(result, "regional_unreferenced")
# -- not demonstrated here since it needs real sequence content; see
# tests/testthat/test-score-collapse.R's own Tier 1/2a/2b coverage.


# ==============================================================================
# SECTION 10 -- Match object cleaning and export
# remove_flagged_references() / write_reference_fasta() / build_site_reference()
# ==============================================================================

## ---- remove_flagged_references() ---- OFFLINE -------------------------------
# Fixture reused verbatim from tests/testthat/test-clean.R.
match_df_clean <- data.frame(
  observation_id = c("S1", "S1", "S2", "S2"),
  accession      = c("AB123.1", "CD456.2", "AB123.1", "EF789"),
  score          = c(99, 95, 98, 97),
  taxon_name     = c("Sp A", "Sp B", "Sp A", "Sp C"),
  stringsAsFactors = FALSE
)
reference_errors <- data.frame(
  id_x       = c("AB123", "GH999"),
  error_type = c("likely_mislabeled", "likely_mislabeled"),
  stringsAsFactors = FALSE
)
cleaned_match <- remove_flagged_references(match_df_clean, reference_errors)
cleaned_match

## ---- write_reference_fasta() ---- OFFLINE -----------------------------------
ref_for_export <- data.frame(
  composite_id = c("acc1", "acc2"),
  sequence     = c("ACGTACGT", "TTTTCCCC"),
  genus        = c("Fundulus", "Gambusia"),
  species      = c("Fundulus parvipinnis", "Gambusia affinis"),
  stringsAsFactors = FALSE
)
export_fasta <- tempfile(fileext = ".fasta")
export_tsv   <- tempfile(fileext = ".tsv")
write_reference_fasta(ref_for_export, export_fasta, taxonomy_file = export_tsv)
readLines(export_fasta)
readLines(export_tsv)

## ---- build_site_reference() ---- NETWORK, small real taxa -------------------
# High-level wrapper: fetch_ncbi_reference_sequences() -> audit_barcode_
# coverage() -> write_reference_fasta(). flag_errors left FALSE (its TRUE path
# additionally needs build_sequence_matrix(), already exercised in Section 2).
site_ref_dir <- file.path(tempdir(), "review_site_reference")
site_ref <- build_site_reference(
  taxa           = "Fundulus",
  barcode_term   = "MiFishU",
  output_dir     = site_ref_dir,
  flag_errors    = FALSE,
  audit_coverage = TRUE,
  max_sequences  = 20L,
  max_per_species = 2L
)
names(site_ref)
nrow(site_ref$reference_df)
list.files(site_ref_dir)


# ==============================================================================
# SECTION 11 -- Diagnostics
# interpret_model()
# ==============================================================================

## ---- interpret_model() ---- OFFLINE -----------------------------------------
# Chained off Section 2's real trained_model.
model_summary <- interpret_model(trained_model, print_report = FALSE)
model_summary$hypothesis_baselines
model_summary$species_thresholds


# ==============================================================================
# SECTION 12 -- Reporting
# report_likelihood()
# ==============================================================================

## ---- report_likelihood() ---- OFFLINE ---------------------------------------
# A hand-built model_params (fixture reused verbatim from
# tests/testthat/test-report_likelihood.R) rather than Section 2's real
# trained_model, so this section's n_species/n_singletons/n_anchors/AIC/
# reference_errors fields are all populated and non-degenerate -- Section 2's
# 5-sequence fixture trains successfully but doesn't populate every one of
# these diagnostic fields richly enough to demonstrate report_likelihood()'s
# own methods-text generation.
mock_model_for_report <- structure(
  list(
    H1_Lookup = data.frame(
      lookup_key = paste0("sp", 1:30), rank = "species",
      mu_score = stats::runif(30, 3, 5), mu_gap = stats::runif(30, 1, 3),
      sigma_score = stats::runif(30, 0.3, 0.8), stringsAsFactors = FALSE
    ),
    H1_Global_Mu = c(score_logit = 4.2, gap_logit = 2.1),
    H1_Sigma = matrix(c(0.5, 0.1, 0.1, 0.4), 2, 2),
    H2 = list(delta = 3.0, sigma = matrix(c(0.8, 0.2, 0.2, 0.6), 2, 2)),
    H3 = list(delta = 5.0, sigma = matrix(c(1.2, 0.3, 0.3, 0.9), 2, 2)),
    Stats = list(AIC_Score = 200.0, n_species = 35L, n_singletons = 5L, n_anchors = 10L),
    reference_errors = data.frame(
      accession = paste0("NC_", 1:3),
      error_type = c("likely_mislabeled", "likely_mislabeled", "unverified_singleton_high_match"),
      stringsAsFactors = FALSE
    )
  ),
  class = "taxa_model_params"
)
report_section <- report_likelihood(mock_model_for_report)
report_section$statistics
cat(report_section$methods, "\n")
