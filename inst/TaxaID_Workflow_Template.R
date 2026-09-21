# =============================================================================
# TaxaID single-site workflow template
#
# GENERATED FILE -- do not edit by hand.
#   Source:    the workflow graph's own snippets (TaxaWizard/inst/graph/snippets/)
#   Generator: TaxaWizard/inst/tools/build_workflow_template.R
#   Guarded by: TaxaWizard/tests/testthat/test-workflow-template.R, which
#               regenerates this file and fails if it differs.
#
# Every step below is the same code TaxaWizard generates for that edge, so a
# change to a snippet reaches this template or breaks the build. It is derived
# rather than written because BOTH of this project's previous templates sat
# unrunnable for months while looking maintained.
#
# This is a TEMPLATE, not a worked example: it carries no study's data and no
# real paths. Edit Section 0, supply your own inputs, and run top to bottom.
#
# The path it demonstrates (from the graph, sequences -> reviewed):
#   seq_to_match -> match_to_taxa -> taxa_to_refs -> refs_to_matrix -> matrix_to_model -> model_match_to_lik -> taxa_to_occ -> occ_to_std -> dist_to_priors_by_group -> lik_prior_to_post -> post_to_consensus -> taxa_to_context -> consensus_to_reviewed
# =============================================================================

library(TaxaTools);  library(TaxaFetch);  library(TaxaHabitat)
library(TaxaMatch);  library(TaxaLikely); library(TaxaExpect)
library(TaxaAssign); library(TaxaFlag)

# --- Step 0: does this machine have what the path needs? ---------------------
# Stops here rather than failing deep inside a stage.
.setup <- TaxaWizard::workflow_check(
  edges = c("seq_to_match", "match_to_taxa", "taxa_to_refs", "refs_to_matrix", "matrix_to_model", "model_match_to_lik", "taxa_to_occ", "occ_to_std", "dist_to_priors_by_group", "lik_prior_to_post", "post_to_consensus", "taxa_to_context", "consensus_to_reviewed"),
  verbose = TRUE
)
if (any(.setup$status == "missing")) stop("Setup incomplete -- see the fix column above.")

# =============================================================================
# 0.  CONFIGURATION  (edit this section only)
# =============================================================================

CACHE_ROOT <- file.path(tempdir(), "taxaid_cache")   # point at a durable dir for real runs

# SEQUENCES: the raw input this path starts from. Supply your own.
SEQUENCES <- NULL   # e.g. readRDS("my_esv_table.rds")

MARKER                     <- "MiFish-U"                             # Primer/marker name, as your lab records it
BARCODE_TERM               <- "12S"                                  # NCBI barcode search term for this marker
TARGET_GROUP               <- "fish"                                 # Free-text taxonomic scope of the assay
DATA_TYPE                  <- "eDNA"                                 # Observation signal, passed to review_assignments()/review_spatial_context(); must be one of "eDNA", "acoustic" or "image"
NCBI_EMAIL                 <- Sys.getenv("ENTREZ_EMAIL")             # Required by NCBI for Entrez queries
SITE_LAT                   <- 0                                      # Site latitude, decimal degrees
SITE_LON                   <- 0                                      # Site longitude, decimal degrees
SITE_HABITAT               <- "Marine"                               # Habitat of the sampling site itself
HABITAT_SCHEME             <- NULL                                   # Habitat vocabulary; NULL uses the package default
GEOGRAPHIC_HINT            <- "the study region"                     # Plain-language region, used in LLM prompts
SAMPLING_DATE              <- Sys.Date()                             # Sampling date, or Sys.Date() if not recorded
YEAR_RANGE                 <- "1995,2025"                            # Occurrence year window; set it, do not inherit a default
SEARCH_RADIUS_DEG          <- 2                                      # Occurrence search radius around the site, degrees
GBIF_LIMIT                 <- 50000                                  # Cap on occurrence records fetched
BACKBONE_ID                <- 11                                     # Source taxonomic backbone id
TARGET_BACKBONE_ID         <- 11                                     # Backbone to harmonise onto
RANK_SYSTEM                <- NULL                                   # Rank columns; NULL auto-detects
TAXON_COL                  <- "taxon_name"                           # Column holding the taxon name
TAXON_RANK_COL             <- "taxon_name_rank"                      # Column holding that name's rank
SAMPLING_GROUP_COL         <- "sampling_group"                       # Detection-process grouping; see the note in Section 0
MIN_SCORE                  <- 0                                      # Minimum match score to keep
MIN_ABUNDANCE              <- 1                                      # Minimum read count to keep
CUMULATIVE_THRESHOLD       <- 0.99                                   # Cumulative posterior mass retained per observation
BLAST_METHOD               <- "remote"                               # "remote" needs no local BLAST install
LLM_FN                     <- TaxaTools::call_api                    # Function used for every LLM call
GBIF_CACHE_DIR             <- file.path(CACHE_ROOT, "gbif")          # Occurrence cache
HABITAT_CACHE_DIR          <- file.path(CACHE_ROOT, "habitat")       # Habitat-classification cache
REFERENCE_CACHE_DIR        <- file.path(CACHE_ROOT, "reference")     # Reference-sequence cache
REVIEW_CACHE_DIR           <- file.path(CACHE_ROOT, "review")        # LLM review cache
INCLUDE_DOMESTIC_PRIORS    <- FALSE                                  # Add domestic/food-species priors
INCLUDE_GROUP_PRIORS       <- TRUE                                   # Add group-level prior support
INCLUDE_DOWNRANKING        <- TRUE                                   # Allow posterior downranking
SCREEN_REFERENCE_ACCESSIONS <- FALSE                                  # Screen reference accessions for errors; off by default -- see the comment in Step 1 for why
REVIEW_FLAGGED_REFERENCES  <- TRUE                                   # Send flagged accessions for LLM review
REMOVE_INCONGRUENT_REFERENCES <- TRUE                                   # Drop references failing hierarchy congruence

# sampling_group_col identifies the DETECTION PROCESS a record came from, not
# a taxonomic group. Priors and kernel bandwidth are both estimated within it,
# so pooling unlike processes biases every group toward the largest one.

sequences <- SEQUENCES
if (is.null(sequences)) stop("Set SEQUENCES in Section 0 before running.", call. = FALSE)

# =============================================================================
# STEP 1 of 13 -- BLAST sequences against reference database
#   edge: seq_to_match    sequences -> match_df
# =============================================================================
# Edge: sequences -> match_df
# Source: TaxaMatch/inst/workflow_fastq_to_match.R

seq_df <- TaxaMatch::read_sequence_table(sequences)

filtered_df <- TaxaMatch::filter_sequences(
  seq_df,
  barcode_term  = BARCODE_TERM,
  min_abundance = MIN_ABUNDANCE
)

blast_hits <- TaxaMatch::blast_sequences(
  filtered_df,
  method     = BLAST_METHOD,
  database   = "nt",
  score_range = 8,
  max_hits    = 20,
  min_score   = MIN_SCORE,
  email       = NCBI_EMAIL,
  resolve_taxonomy = TRUE
)

match_df <- TaxaMatch::standardize_match_data(
  data          = blast_hits,
  observation_id_col = "observation_id",
  score_col     = "score",
  rank_system   = RANK_SYSTEM
)

match_df <- TaxaMatch::filter_redundant_hypotheses(match_df)

# Optional: BLAST-based reference-accession quality screening. For each
# reference accession a hypothesis in match_df is based on, checks whether
# independent GenBank evidence agrees taxonomically -- flags likely
# mislabeled/contaminated reference submissions (hierarchy_flag =
# "incongruent") without discarding them outright, since a flag can also
# mean "this marker has poor resolving power here", not necessarily a
# genuine mislabel -- see evaluate_reference_accessions()'s own
# documentation.
#
# OFF by default: it BLASTs every candidate reference accession against
# NCBI, one round-trip per unique accession, which trips NCBI rate limits
# on a real taxon list. On a real 12S study it changed 6 of 13,442 hits.
# Run it as a separate task when you need it -- set
# SCREEN_REFERENCE_ACCESSIONS to TRUE here to fold it back into this
# workflow instead.
if (isTRUE(SCREEN_REFERENCE_ACCESSIONS)) {
  accession_eval <- TaxaMatch::evaluate_reference_accessions(
    accessions = unique(match_df$accession),
    method     = BLAST_METHOD
  )
  match_df <- TaxaMatch::flag_incongruent_references(match_df, accession_eval)
  message(
    "Reference-accession screening: ",
    sum(match_df$hierarchy_flag == "incongruent", na.rm = TRUE),
    " of ", nrow(match_df), " match rows rest on an incongruent reference accession"
  )

  # Optional: LLM second-look review of flagged/borderline accessions
  # (TaxaMatch::review_flagged_accessions()). A raw "incongruent" verdict alone can't
  # distinguish a genuine mislabel from a correctly-labeled record with poor marker
  # resolving power or thin corroborating coverage -- this gives every flagged
  # accession a real LLM second look before anything is ever removed. Never
  # re-decides hierarchy_flag itself; only produces overrides an explicit removal
  # step can choose to honor. Set REVIEW_FLAGGED_REFERENCES to FALSE to skip.
  if (isTRUE(REVIEW_FLAGGED_REFERENCES)) {
    accession_review <- TaxaMatch::review_flagged_accessions(
      accession_eval,
      llm_fn = LLM_FN
    )
    accession_overrides <- TaxaMatch::resolve_review_overrides(accession_review)
    message(
      "LLM review: ", length(accession_overrides),
      " flagged accession(s) confirmed safe to keep (poor marker resolution/thin coverage/hybrid artifact, not a genuine mislabel)"
    )

    # Optional, separately gated: actually DROP rows resting on an accession
    # still judged "remove" after the review overrides above (the harder,
    # deliberate opt-in -- flag_incongruent_references() above already
    # annotated everything without removing anything, the recommended
    # default). Set REMOVE_INCONGRUENT_REFERENCES to TRUE only after
    # reviewing the flags/review comments yourself.
    if (isTRUE(REMOVE_INCONGRUENT_REFERENCES)) {
      match_df <- TaxaMatch::remove_incongruent_references(
        match_df, accession_eval,
        override_accessions = accession_overrides
      )
      message("Removed match rows resting on a reference accession still judged incongruent after review")
    }
  }
}

match_df
match_df <- match_df

# =============================================================================
# STEP 2 of 13 -- Extract unique taxa from match data
#   edge: match_to_taxa    match_df -> taxa
# =============================================================================
# Edge: match_df -> taxa
# Source: TaxaTools create_taxon_names()

# Standardize common column name variations
if (!"observation_id" %in% names(match_df)) {
  sid_match <- match(TRUE, tolower(names(match_df)) %in% c("esvid", "esv_id", "asvid", "asv_id", "queryid", "query_id"))
  if (!is.na(sid_match)) {
    message("Renaming '", names(match_df)[sid_match], "' -> 'observation_id'")
    names(match_df)[sid_match] <- "observation_id"
  }
}
if (!"score_original" %in% names(match_df)) {
  sc_match <- match(TRUE, tolower(names(match_df)) %in% c("score", "percmatch", "perc_match", "pident", "percent_identity", "similarity"))
  if (!is.na(sc_match)) {
    message("Renaming '", names(match_df)[sc_match], "' -> 'score_original'")
    names(match_df)[sc_match] <- "score_original"
  }
}

detected_ranks <- TaxaTools::detect_ranks(match_df)
message("Auto-detected rank columns: ", paste(detected_ranks, collapse = ", "))
# Lowercase rank columns to match TaxaID conventions
for (.rk in detected_ranks) {
  .match <- which(tolower(names(match_df)) == .rk)
  if (length(.match) == 1L) names(match_df)[.match] <- .rk
}

# Clean species/genus columns: strip subspecies trinomials, hybrid crosses,
# "sp.", "cf.", and other non-conforming labels to standard binomials.
# This is essential for match data from BLAST or other tools.
if ("species" %in% names(match_df)) {
  n_before <- dplyr::n_distinct(match_df$species, na.rm = TRUE)
  match_df$species <- TaxaTools::clean_taxon_names(match_df$species)
  n_after <- dplyr::n_distinct(match_df$species, na.rm = TRUE)
  if (n_before != n_after) {
    message(sprintf("Cleaned species column: %d -> %d unique names.", n_before, n_after))
  }
}

taxa_df <- TaxaTools::create_taxon_names(
  input_df    = match_df,
  rank_system = detected_ranks
)
message("Unique taxa: ", length(unique(taxa_df$taxon_name)))
taxa_df
taxa <- taxa

# =============================================================================
# STEP 3 of 13 -- Fetch reference sequences from NCBI
#   edge: taxa_to_refs    taxa -> reference_df
# =============================================================================
# Edge: taxa -> reference_df
# Source: TaxaLikely fetch_ncbi_reference_sequences()
# NOTE: Searches by FAMILY to build a comprehensive reference database.
# The model needs within-species variation and between-species distances.
# Species from the match data are prioritized so their sequences are
# always fully represented even when total hits exceed the download budget.

# Normalize primer variant names to NCBI-searchable marker names
.barcode_term <- BARCODE_TERM
.bt_lower <- tolower(trimws(.barcode_term))
if (grepl("^mifish", .bt_lower))   .barcode_term <- "MiFish"
if (grepl("^teleo",  .bt_lower))   .barcode_term <- "12S"
if (grepl("^leray|^mlcoi", .bt_lower)) .barcode_term <- "COI"

# Use families (not individual species) for a proper reference
ref_families <- unique(taxa$family)
ref_families <- ref_families[!is.na(ref_families) & nchar(ref_families) > 0L]
message("Searching NCBI for families: ", paste(ref_families, collapse = ", "))

# Extract species from input as priority taxa for the likelihood model.
# These species get full NCBI representation even when subsampling.
.priority_species <- if ("species" %in% names(taxa)) {
  sp <- unique(taxa$species)
  sp[!is.na(sp) & nchar(sp) > 0L]
} else {
  character(0L)
}
message("Priority species from match data: ", length(.priority_species))

reference_df <- TaxaLikely::fetch_ncbi_reference_sequences(
  taxa           = ref_families,
  barcode_term   = .barcode_term,
  priority_taxa  = if (length(.priority_species) > 0L) .priority_species else NULL,
  # STOP rather than silently ship a degraded reference database. A real
  # PtConception run had seven genera with an NCBI count query fail
  # transiently; each was dropped, taking its entire reference
  # representation with it (78 sequences, 17 species), and the run continued
  # to a finished-looking result. Every production workflow sets "error" for
  # this reason. Use "warn" only when you have decided to accept a degraded
  # database -- the affected taxa are then named in the warning and in
  # attr(reference_df, "count_failures"), checked just below.
  on_count_failure = "error",
  # Per-taxon cache, project-local so it is visible beside the checkpoints it
  # feeds rather than in the hidden tools::R_user_dir() default. A cached
  # taxon issues NO count query at all, which is also what removes the
  # exposure that caused the incident above.
  cache_dir      = REFERENCE_CACHE_DIR
)

# Always look: a non-empty count_failures means taxa are MISSING from the
# reference database even though the fetch returned rows.
if (length(attr(reference_df, "count_failures"))) {
  message("  !! count_failures: ",
          paste(attr(reference_df, "count_failures"), collapse = ", "))
}

if (nrow(reference_df) == 0L) {
  stop(
    "fetch_ncbi_reference_sequences() returned 0 sequences. Possible causes:\n",
    "  - NCBI API rate limit (try again in a few minutes)\n",
    "  - No sequences for these taxa + barcode marker in NCBI\n",
    "  - Network connectivity issue\n",
    "Searched families: ", paste(ref_families, collapse = ", "),
    call. = FALSE
  )
}
message("Fetched ", nrow(reference_df), " reference sequences across ",
        length(unique(reference_df$species)), " species")
reference_df
reference_df <- reference_df

# =============================================================================
# STEP 4 of 13 -- Build pairwise distance matrix
#   edge: refs_to_matrix    reference_df -> reference_matrix
# =============================================================================
# Edge: reference_df -> reference_matrix
# Source: TaxaLikely build_sequence_matrix()

ref_matrix <- TaxaLikely::build_sequence_matrix(
  reference_df = reference_df
)
message("Built reference matrix: ", nrow(ref_matrix), " pairwise comparisons")
ref_matrix
reference_matrix <- reference_matrix

# =============================================================================
# STEP 5 of 13 -- Train likelihood model
#   edge: matrix_to_model    reference_matrix -> model_params
# =============================================================================
# Edge: reference_matrix -> model_params
# Source: TaxaLikely train_likelihood_model()

model_params <- TaxaLikely::train_likelihood_model(
  raw_df        = reference_matrix,
  # Must equal the coverage floor the match object was built under:
  # TaxaMatch::blast_sequences(min_query_coverage = 80) -> 0.8.
  min_pair_coverage = 0.8,
  anchor_perfect = TRUE
)
message("Model trained: ", model_params$Stats$n_species, " species, AIC = ",
        round(model_params$Stats$AIC_Score, 1))
model_params
model_params <- model_params

# =============================================================================
# STEP 6 of 13 -- Evaluate likelihoods from trained model
#   edge: model_match_to_lik    match_df + model_params -> likelihoods
# =============================================================================
# Edge: match_df + model_params -> likelihoods
# Source: TaxaLikely evaluate_likelihoods() + filter_top_hypotheses()
# NOTE: match_df should be the output of match_to_taxa (taxa_df),
# which already has taxon_name/taxon_name_rank. If not, we add them here.

# Standardize column names if needed
if (!"observation_id" %in% names(match_df)) {
  sid_match <- match(TRUE, tolower(names(match_df)) %in%
    c("esvid", "esv_id", "asvid", "asv_id", "queryid", "query_id"))
  if (!is.na(sid_match)) {
    message("Renaming '", names(match_df)[sid_match], "' -> 'observation_id'")
    names(match_df)[sid_match] <- "observation_id"
  }
}
if (!"score_original" %in% names(match_df)) {
  sc_match <- match(TRUE, tolower(names(match_df)) %in%
    c("score", "percmatch", "perc_match", "pident", "percent_identity", "similarity"))
  if (!is.na(sc_match)) {
    message("Renaming '", names(match_df)[sc_match], "' -> 'score_original'")
    names(match_df)[sc_match] <- "score_original"
  }
}

# Ensure taxon_name exists (added by match_to_taxa step via create_taxon_names)
if (!"taxon_name" %in% names(match_df)) {
  detected_ranks <- TaxaTools::detect_ranks(match_df)
  for (.rk in detected_ranks) {
    .m <- which(tolower(names(match_df)) == .rk)
    if (length(.m) == 1L) names(match_df)[.m] <- .rk
  }
  # Clean species column: strip subspecies, hybrids, sp., cf., etc.
  if ("species" %in% names(match_df)) {
    match_df$species <- TaxaTools::clean_taxon_names(match_df$species)
  }
  match_df <- TaxaTools::create_taxon_names(
    input_df = match_df, rank_system = detected_ranks
  )
  message("Added taxon_name from ranks: ", paste(detected_ranks, collapse = ", "))
}

lik_result <- TaxaLikely::evaluate_likelihoods(
  match_df     = match_df,
  model_params = model_params,
  n_sims       = 200L
)

likelihoods <- TaxaLikely::filter_top_hypotheses(
  lik_result$likelihoods
)
message("Evaluated likelihoods for ", length(unique(likelihoods$observation_id)), " samples")
if (nrow(lik_result$unresolved) > 0L) {
  message("  ", nrow(lik_result$unresolved), " unresolved rows (no usable likelihoods)")
}
likelihoods
likelihoods <- likelihoods

# =============================================================================
# STEP 7 of 13 -- Fetch occurrence records from GBIF
#   edge: taxa_to_occ    taxa -> occurrences
# =============================================================================
# Edge: taxa -> occurrences
# Source: TaxaFetch/inst/GBIF_workflow.R + Define_search_workflow.R

keys <- TaxaFetch::get_keys_from_context(taxa)
bbox_wkt <- TaxaFetch::make_bbox_wkt(
  lat = SITE_LAT, lon = SITE_LON,
  radius_deg = SEARCH_RADIUS_DEG
)
# GBIF_LIMIT WARNING. `limit` caps records PER TAXON KEY, and what survives is
# GBIF's own return order -- a non-random prefix, not a sample. Measured on real
# data: at limit = 10000, 45 of 231 Mugu taxa and 110 of 666 PtConception taxa
# sat exactly at the cap, and because each species' first 10,000 records came
# from the same few large multi-species surveys, every capped taxon emerged with
# an IDENTICAL spatial distribution (per-species median distance 104 km, IQR
# 104-104, against 81-217 for uncapped taxa). Both abundance and spatial pattern
# were then truncation artifacts. Prefer GBIF_LIMIT = NULL. Note this
# function has no on_cap guard -- TaxaFetch::get_gbif_occurrences() does, but it
# routes to the download API above 50 keys, which needs a GBIF account.
occurrences <- TaxaFetch::fetch_gbif_occurrences(
  keys       = keys,
  geometry   = bbox_wkt,
  year_range = YEAR_RANGE,
  limit      = GBIF_LIMIT,
  # Project-local cache, beside the checkpoints it feeds, rather than the
  # hidden tools::R_user_dir("TaxaFetch", "cache") default. GBIF zips are the
  # largest artefact this ecosystem produces -- 23 GB and 17 GB incidents,
  # 38 zips at 17.0 GB against 52 MB for every other cache file combined --
  # and being invisible from the project is why they went unnoticed.
  cache_dir  = GBIF_CACHE_DIR
)
occurrences <- TaxaFetch::filter_gbif_quality(occurrences)
occurrences <- TaxaFetch::dedupe_occurrences(occurrences)
message("Fetched ", nrow(occurrences), " occurrence records")
occurrences
occurrences <- occurrences

# =============================================================================
# STEP 8 of 13 -- Standardize occurrences and assign habitat
#   edge: occ_to_std    occurrences -> std_occurrences
# =============================================================================
# Edge: occurrences -> std_occurrences
# Source: TaxaHabitat/inst/Habitat_workflow.R + TaxaHabitat/inst/workflows/assign_habitat_workflow.R

occurrences <- occurrences

# Step 0: classify any institution-proximity flags from filter_gbif_quality()
# (institution_flag=TRUE for records near a biodiversity institution -- field
# stations/marine labs are often sited exactly where good habitat is, so
# these are tiered "high"/"low"/"ambiguous" for review, never auto-removed).
# Silently skipped if institution_flag isn't present (e.g. flag_institution
# was FALSE, or occurrences didn't come from filter_gbif_quality()).
if ("institution_flag" %in% names(occurrences)) {
  occurrences <- TaxaHabitat::flag_institution_candidates(occurrences)
  n_high <- sum(occurrences$institution_suspicion == "high", na.rm = TRUE)
  if (n_high > 0L) {
    message(n_high, " record(s) flagged high-suspicion for institution-collection origin -- review before treating as wild detections")
  }
}

# Step 1: Get unique taxa for habitat assignment
unique_taxa <- unique(occurrences$taxon_name)
unique_taxa <- unique_taxa[!is.na(unique_taxa) & nzchar(unique_taxa)]

# Step 2: Build the habitat lookup via the CACHED one-call path
# (TaxaHabitat::build_habitat_lookup()), not the uncached
# build_habitat_prompt() -> LLM_FN loop -> parse_hierarchical_habitat_response()
# chain. All six production workflows use this: a taxon
# already classified under this scheme is served from cache_dir instead of
# re-asked. Uncached, a habitat verdict could flip between runs, moving a
# species' records in or out of the site's habitat stratum and its kernel
# prior by orders of magnitude -- a real GreatLakes run lost 0.05 of
# Lamar precision to exactly this. Same design as review_assignments()'s
# cache. Force fresh verdicts with TaxaHabitat::taxahabitat_clear_cache(<cache_dir>).
habitat_lookup <- TaxaHabitat::build_habitat_lookup(
  unique_taxa,
  habitat_scheme     = HABITAT_SCHEME,
  llm_fn             = LLM_FN,
  geographic_context = GEOGRAPHIC_HINT,
  cache_dir          = HABITAT_CACHE_DIR
)

# Step 3: Assign habitat to occurrences
std_occurrences <- TaxaHabitat::assign_habitat_biological(
  occurrence_data = occurrences,
  habitats_df = habitat_lookup,
  threshold   = 0.5
)
message("Assigned habitat to ", nrow(std_occurrences), " occurrences")
std_occurrences
std_occurrences <- std_occurrences

# =============================================================================
# STEP 9 of 13 -- Build priors from standardized occurrences, grouped by sampling/detection process (kernel path)
#   edge: dist_to_priors_by_group    std_occurrences -> priors
# =============================================================================
# Edge: std_occurrences -> priors (grouped by sampling/detection process, kernel path)
# Source: TaxaExpect kernel-priors redesign + sampling_group_col support,
#   e.g. PtConceptionWorkflow_18S_2_single_site.R
# NOTE: SAMPLING_GROUP_COL identifies which DETECTION METHOD/PROCESS
#   each row belongs to (e.g. "fish" vs "birds" vs "phytoplankton" surveyed
#   with different effort) -- this is NOT the same thing as a physical site.
#   Pooling groups with very different sampling effort into one estimate
#   silently distorts every group's estimated composition AND its Good-Turing
#   budget (a barely-sampled group's singletons inflate f1 -- hence
#   chao_missing, quadratically -- while adding almost nothing to
#   missing_mass). Use this path only when std_occurrences already has a column
#   identifying detection group; otherwise use the plain std_to_priors_kernel
#   path.
# Rewritten from the retired GLMM-path wrapper
#   train_biodiversity_model_by_group() to the kernel-path equivalent. A
#   single estimate_kernel_priors(sampling_group_col=) call handles every
#   group at once (no per-group model-fitting loop needed) -- this snippet
#   works directly on standardized occurrence data, no gridding step
#   (create_sites_from_grid()/the old "distributions" intermediate) needed,
#   so this edge's own `from` is "std_occurrences", not "distributions" --
#   the whole GLMM chain, including "distributions"'s only other consumer,
#   dist_to_priors, is retired.

std_occurrences <- std_occurrences

# Step 1: calibrate the kernel bandwidth with the SAME sampling_group_col the
# estimator uses below.
#
# (lambda_km does NOT describe spatial decay independent of detection-process
# membership -- calibrating it on pooled data is a real, non-obvious trap.
# lambda_km IS spatial decay, but the quantity MINIMISED to estimate it
# is a multinomial composition log-loss, and a composition is a share WITHIN a
# detection process. Pooling therefore lets the largest group choose the
# bandwidth for all of them. It does not announce itself: the fit succeeds and
# returns a plausible number that is simply wrong for every group but the
# dominant one. On a real fixture with 4 km patches in one group and 55 km in
# another, the groups wanted 5 km and 25 km.)
#
# lambda_grid spans 1-100 km deliberately. A grid that cannot express its own
# answer reports a boundary warning pointing the wrong way: PtConception 12S
# measured its optimum at 10 km, INTERIOR, only once 1/2/5 were offered -- the
# old c(25, 50, 100, 200) could not represent 10 at all and would have invited
# widening UPWARD. Keep this in step with the canonical workflow template.
kernel_cal <- TaxaExpect::calibrate_kernel_bandwidth(
  std_occurrences,
  site_habitat       = SITE_HABITAT,
  lambda_grid        = c(1, 2, 5, 10, 25, 50, 100),
  sampling_group_col = SAMPLING_GROUP_COL
)
message(sprintf(
  "Calibrated kernel bandwidth: lambda = %g km (LOBO loss %.3f)",
  kernel_cal$best$lambda_km, kernel_cal$best$weighted_logloss
))

# Step 1b: is the kernel worth having at all? An interior optimum says only
# "best bandwidth offered", never that the kernel beats NOT having one.
# $results carries `regional` and `nearest_block` reference rows, by row name.
.k_loss   <- kernel_cal$best$weighted_logloss
.reg_loss <- kernel_cal$results["regional", "weighted_logloss"]
.nb_loss  <- kernel_cal$results["nearest_block", "weighted_logloss"]
message(sprintf(
  "LOBO log-loss: kernel %.4f | regional %.4f | nearest_block %.4f",
  .k_loss, .reg_loss, .nb_loss
))
.gain <- .reg_loss - .k_loss
.pct  <- 100 * .gain / .reg_loss
if (!is.na(.gain) && .gain <= 0) {
  warning(sprintf(
    paste0("kernel does NOT beat regional (%.4f vs %.4f). The answer is not a ",
           "different lambda but a smaller block_size_deg."),
    .k_loss, .reg_loss
  ), call. = FALSE)
} else {
  message(sprintf("kernel beats regional by %.4f (%.2f%%)", .gain, .pct))
  if (!is.na(.pct) && .pct < 1) {
    warning(sprintf(
      paste0("kernel margin over regional is only %.2f%% -- lambda may be an ",
             "artifact of the CV block geometry rather than a real length scale."),
      .pct
    ), call. = FALSE)
  }
}

# Step 1c: estimate_kernel_priors() takes a SCALAR lambda_km, so it can only
# REPORT a per-group disagreement, never act on one. Read $by_group before
# trusting $best -- calibrate_kernel_bandwidth() warns at >= 2x disagreement.
if (!is.null(kernel_cal$by_group)) {
  message("Per-group optimal lambda (the scalar above is a compromise across these):")
  print(kernel_cal$by_group[
    , intersect(c("sampling_group", "n_records", "n_blocks_scored",
                  "lambda_km", "weighted_logloss"),
                names(kernel_cal$by_group))
  ])
}

# Step 2: estimate site priors, computing composition AND the Good-Turing
# budget WITHIN each sampling_group_col value rather than pooled. With more
# than one group the pooled f1/f2/chao_missing/theta_present scalars are NA
# by design (no single budget exists across detection processes) -- $budget
# is the authoritative per-group table.
kernel_priors_fit <- TaxaExpect::estimate_kernel_priors(
  std_occurrences,
  site_lat           = SITE_LAT,
  site_lon           = SITE_LON,
  site_habitat       = SITE_HABITAT,
  lambda_km          = kernel_cal$best$lambda_km,
  site_id            = sprintf("Site_%.2f_%.2f", SITE_LAT, SITE_LON),
  sampling_group_col = SAMPLING_GROUP_COL
)
print(kernel_priors_fit)
message("Per-group budget:")
print(kernel_priors_fit$budget)

# Step 3: unseen-taxa floor (Good-Turing/Chao-based dark-diversity mirrors,
# stamped with this site's own id). Each singleton mirror is scaled by its
# OWN group's n_eff (not the pooled total), so this single call correctly
# handles every group at once -- no per-group loop needed.
priors_undetected <- TaxaExpect::generate_undetected_diversity(
  model_obj = kernel_priors_fit,
  taxonomy  = std_occurrences
)

priors <- dplyr::bind_rows(kernel_priors_fit$priors, priors_undetected) |>
  dplyr::mutate(taxon_name_rank = "species")

message(sprintf(
  "Generated priors for %d resident taxa + %d undetected/dark-diversity row(s) across %d sampling group(s)",
  sum(priors$prior_branch %in% c("kernel_estimated", "resident_observed"), na.rm = TRUE),
  sum(priors$prior_branch == "resident_undetected", na.rm = TRUE),
  dplyr::n_distinct(std_occurrences[[SAMPLING_GROUP_COL]])
))

# Optional: add named domestic/commensal-animal and food-species priors --
# these are a contamination-risk claim, not an occurrence-plausibility one,
# and are deliberately priced on a POOLED fit, not per-group: a domestic/food
# species isn't scoped to one detection process. Set
# INCLUDE_DOMESTIC_PRIORS to FALSE to skip this step entirely.
if (isTRUE(INCLUDE_DOMESTIC_PRIORS)) {
  kernel_priors_pooled <- TaxaExpect::estimate_kernel_priors(
    std_occurrences,
    site_lat     = SITE_LAT,
    site_lon     = SITE_LON,
    site_habitat = SITE_HABITAT,
    lambda_km    = kernel_cal$best$lambda_km,
    site_id      = kernel_priors_fit$params$site_id
  )
  domestic_priors <- TaxaExpect::generate_domestic_food_priors(
    model_obj = kernel_priors_pooled,
    lat       = SITE_LAT,
    lng       = SITE_LON,
    grid_id   = kernel_priors_fit$params$site_id
  )
  priors <- dplyr::bind_rows(priors, domestic_priors)
  message("Added ", nrow(domestic_priors), " domestic/food-species prior row(s)")
}

# verify_taxon_names()'s real formals are
# (name_list, backbone_id, batch_size, timeout_sec, fallback_backbone_id) --
# passing the whole `priors` data frame positionally as
# `name_list` (wrong type: a character vector is expected) and a `taxon_col`
# argument that does not exist, then discarding `priors` by reassigning it
# to the verification result, is a real trap. Verify the taxon names
# informationally without clobbering `priors`.
taxon_verification <- TaxaTools::verify_taxon_names(
  name_list   = unique(priors$taxon_name),
  backbone_id = TARGET_BACKBONE_ID
)
message(sprintf(
  "Taxon-name verification: %d of %d unique taxon name(s) did not verify against backbone %s",
  sum(!taxon_verification$verified, na.rm = TRUE), nrow(taxon_verification),
  TARGET_BACKBONE_ID
))
priors <- TaxaMatch::convert_taxonomy_backbone(
  priors,
  target_backbone_id = TARGET_BACKBONE_ID,
  taxon_col           = "taxon_name"
)
message("Generated priors for ", length(unique(priors$taxon_name)), " taxa across ",
        dplyr::n_distinct(std_occurrences[[SAMPLING_GROUP_COL]]), " sampling group(s)")
priors
priors <- priors

# =============================================================================
# STEP 10 of 13 -- Join priors and compute Bayesian posteriors (single site)
#   edge: lik_prior_to_post    likelihoods + priors -> posteriors
# =============================================================================
# Edge: likelihoods + priors -> posteriors
# Source: TaxaAssign join_priors() + compute_posterior()
# NOTE: SITE_LAT and SITE_LON are numeric coordinates of the sampling site.
#   SITE_HABITAT is the habitat type (e.g. "Freshwater", "Marine",
#   "Estuarine"). This is required — the pipeline does not guess which
#   habitat your samples came from.
# NOTE: BACKBONE_ID is required — no default. Must match whichever
#   taxonomic backbone the input taxonomy was verified against (e.g. 11
#   for GBIF, 4 for NCBI).

# --- Build site specification ---
site_spec <- list(lat = SITE_LAT, lon = SITE_LON, main_habitat = SITE_HABITAT)

# --- Join + posterior ---
detected_ranks <- TaxaTools::detect_ranks(match_df)

likelihoods_ready <- TaxaAssign::join_priors(
  likelihoods       = likelihoods,
  taxaexpect_priors = priors,
  site              = site_spec,
  taxonomy_lookup   = match_df,
  rank_system       = detected_ranks,
  backbone_id       = BACKBONE_ID
)

posteriors <- TaxaAssign::compute_posterior(likelihoods_ready, n_sims = 1000L)
message("Computed posteriors for ", length(unique(posteriors$observation_id)), " samples")
posteriors
posteriors <- posteriors

# =============================================================================
# STEP 11 of 13 -- Posterior consensus via LCA
#   edge: post_to_consensus    posteriors -> consensus
# =============================================================================
# Edge: posteriors -> consensus
# Source: TaxaAssign/inst/TaxaAssign_bayesian_workflow.R

# Optional: group-level occurrence priors. consensus_prior
# becomes a real group-level SUM over every locally modelled member sharing
# a rank, instead of a candidate-scoped max -- a materially stronger
# occurrence-plausibility signal, since a single observation's own candidate
# set rarely contains every locally modelled group member. Requires the
# TaxaExpect priors object (priors) and a taxonomy_map
# data frame with real genus/family columns (taxa, e.g. the
# occurrences_clean object from earlier in this pipeline). Set
# INCLUDE_GROUP_PRIORS to FALSE to skip entirely.
group_priors_obj <- if (isTRUE(INCLUDE_GROUP_PRIORS)) {
  TaxaAssign::compute_group_priors(
    taxaexpect_priors = priors,
    taxonomy_map      = taxa
  )
} else {
  NULL
}

# Optional: species reference for posterior_consensus()'s downranking:
# a genus-level LCA is narrowed to a species only when the
# reference lists exactly one species of that genus. Because the
# priors table also holds a distance-clamp row for EVERY
# zero-record BLAST candidate, "in the priors table" does not mean
# "known locally": at Mugu a genus consensus (Pseudotolithus, three
# plausible congeners) was narrowed to P. senegallus, a West African croaker
# with posterior 0.009 that was never among the plausible set, and reported
# at the genus's 0.89. Clamp-only rows are therefore excluded here; resident,
# singleton-mirror, domestic and real-evidence (regional/invasive/iNat) rows
# stay.
# The exclusion is by prior_branch, not by the
# clamp source string. Every non-resident evidence row (distance clamp, regional
# proximity, watch list, iNat range) is resident_undetected and carries no local
# record, so none may be the sole taxon that narrows a coarse consensus. Residents
# and the named domestic/food (transport) rows remain eligible -- the same rule
# TaxaAssign::compute_group_priors(allowed_branches=) now applies at group scope.
# Set INCLUDE_DOWNRANKING to FALSE to skip entirely.
species_reference_df <- if (isTRUE(INCLUDE_DOWNRANKING)) {
  .not_clamp <- if ("prior_branch" %in% names(priors)) priors$prior_branch %in% c("kernel_estimated", "resident_observed", "transport") else if ("evidence_sources" %in% names(priors)) !(priors$evidence_sources %in% "distance_clamp") else rep(TRUE, nrow(priors))
  priors[.not_clamp, , drop = FALSE] |>
    dplyr::filter(!is.na(taxon_name)) |>
    dplyr::distinct(taxon_name) |>
    dplyr::left_join(taxa, by = "taxon_name") |>
    unique()
} else {
  NULL
}

consensus <- TaxaAssign::posterior_consensus(
  posteriors,
  cumulative_threshold   = CUMULATIVE_THRESHOLD,
  min_posterior           = 0.05,
  posterior_col           = "posterior_point_est",
  lookup_missing_taxonomy = TRUE,
  backbone_id             = 4,
  rank_system             = RANK_SYSTEM,
  species_reference       = species_reference_df,
  group_priors            = group_priors_obj
)

# Optional: empirical Bayes refinement
posteriors_updated <- TaxaAssign::update_prior_from_consensus(posteriors, consensus)
consensus_final <- TaxaAssign::posterior_consensus(
  posteriors_updated,
  cumulative_threshold   = CUMULATIVE_THRESHOLD,
  min_posterior           = 0.05,
  posterior_col           = "posterior_point_est",
  lookup_missing_taxonomy = TRUE,
  backbone_id             = 4,
  rank_system             = RANK_SYSTEM,
  species_reference       = species_reference_df,
  group_priors            = group_priors_obj
) |> TaxaAssign::add_slash_taxon()
# add_slash_taxon() derives consensus_OTU + primary_taxon (present whenever
# consensus_taxon is in consensus_final).
message("Consensus: ", sum(consensus_final$is_resolved), " of ",
        nrow(consensus_final), " samples resolved")
consensus_final
consensus <- consensus

# =============================================================================
# STEP 12 of 13 -- Infer ecological context via LLM
#   edge: taxa_to_context    taxa -> context_df
# =============================================================================
# Edge: taxa -> context_df
# Source: TaxaAssign/inst/TaxaAssign_llm_workflow.R

unique_taxa <- unique(taxa$taxon_name[!is.na(taxa$taxon_name)])

context_df <- TaxaAssign::build_context(
  taxon_names    = unique_taxa,
  geographic_hint = GEOGRAPHIC_HINT,
  date           = SAMPLING_DATE,
  habitat_scheme = HABITAT_SCHEME,
  llm_fn         = LLM_FN
)
message("Context: ecoregion = ", context_df$ecoregion, ", habitat = ", context_df$main_habitat)
context_df
context_df <- context_df

# =============================================================================
# STEP 13 of 13 -- LLM expert review of assignments
#   edge: consensus_to_reviewed    consensus + context_df -> reviewed
# =============================================================================
# Edge: consensus + context_df -> reviewed
# Source: TaxaFlag/inst/review_assignments_workflow.R
# NOTE: When data comes from posterior_consensus(), run_llm_pipeline(), or
#   score_consensus(), the taxon column is "consensus_taxon" and rank column
#   is "consensus_rank". For external data (e.g. user-supplied CSV), use the
#   actual column names from the data.

# cache_dir: a per-taxon verdict cache, keyed on everything that
# can move a verdict. Without it, the review is not reproducible -- two real
# GreatLakes runs 50 minutes apart on identical input disagreed about a
# species' geographic plausibility ("possible" then "unlikely"), so it
# appeared in one exported species list and not the other. Force fresh
# verdicts with TaxaFlag::taxaflag_clear_cache(<that directory>).
reviewed <- TaxaFlag::review_assignments(
  data_type = DATA_TYPE,
  input_df       = consensus,
  taxon_col      = TAXON_COL,
  taxon_rank_col = TAXON_RANK_COL,
  context        = context_df,
  target_group   = TARGET_GROUP,
  marker         = MARKER,
  llm_fn         = LLM_FN,
  cache_dir      = REVIEW_CACHE_DIR,
  # Abort rather than export a silently short species list. An LLM review can
  # parse cleanly, return the right number of objects, and still OMIT specific
  # taxa -- consistently the long compound slash labels, i.e. the hardest
  # rows. Those get NA in every llm_ column, and the usual export filters
  # (`llm_* != "unlikely"`) DISCARD NA, so the observation leaves the final
  # species list without a word. Measured on a real PtConception 12S run:
  # 20 observations across 3 plausible local fishes, gone. review_assignments()
  # now re-asks for omitted taxa; "error" makes any residue that survives the
  # re-ask stop the run instead of reaching the filters below.
  on_unreviewed  = "error"
)
message("Reviewed ", nrow(reviewed), " assignments")

# Always check: attributes do NOT survive a dplyr verb, so read this before
# any join or mutate.
if (length(attr(reviewed, "unreviewed_taxa"))) {
  message("  !! unreviewed: ",
          paste(attr(reviewed, "unreviewed_taxa"), collapse = ", "))
}
reviewed
reviewed <- reviewed

# =============================================================================
# Workflow complete. `reviewed` holds the final assignments.
# =============================================================================
