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
#   seq_to_match -> match_to_taxa -> taxa_to_refs -> refs_to_matrix -> matrix_to_model -> model_match_to_lik -> taxa_to_occ -> occ_to_std -> dist_to_priors_by_group -> tables_to_registry -> lik_prior_to_post -> post_to_consensus -> taxa_to_context -> consensus_to_reviewed
# =============================================================================

library(TaxaTools);  library(TaxaFetch);  library(TaxaHabitat)
library(TaxaMatch);  library(TaxaLikely); library(TaxaExpect)
library(TaxaAssign); library(TaxaFlag)

# --- Step 0: does this machine have what the path needs? ---------------------
# Stops here rather than failing deep inside a stage.
.setup <- TaxaWizard::workflow_check(
  edges = c("seq_to_match", "match_to_taxa", "taxa_to_refs", "refs_to_matrix", "matrix_to_model", "model_match_to_lik", "taxa_to_occ", "occ_to_std", "dist_to_priors_by_group", "tables_to_registry", "lik_prior_to_post", "post_to_consensus", "taxa_to_context", "consensus_to_reviewed"),
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
TAXONOMY_CACHE_DIR         <- file.path(CACHE_ROOT, "taxonomy")      # Name-lookup cache shared by every name verification, GBIF key and consensus taxonomy lookup: once filled, a rerun makes no name requests
USE_TAXON_REGISTRY         <- TRUE                                   # Match taxa across tables by GBIF taxon id (one frozen registry per run); outputs carry GBIF accepted names
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

# Objects that a later step looks up with exists() are cleared first, so a run uses only what it built itself,
# never one left in the session by an earlier run (another site's kernel fit, another marker's unresolved set).
# An object of yours under one of these names is removed too, and named in the message: rename it to keep it.
.cleared <- intersect(c("kernel_priors_fit", "lik_unresolved", "taxon_registry"), ls())
if (length(.cleared)) message("Cleared from the session before step 1: ", paste(.cleared, collapse = ", "))
rm(list = .cleared)

# =============================================================================
# STEP 1 of 14 -- BLAST sequences against reference database
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
      llm_fn = LLM_FN,
      # A production run stops rather than carry on with accessions the screen
      # never ruled on: no verdict means no override, so the removal step
      # below -- if it is enabled -- would decide on the screen's own verdict,
      # as if the review had never run.
      on_unreviewed = "error"
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
# STEP 2 of 14 -- Extract unique taxa from match data
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
taxa <- taxa_df

# =============================================================================
# STEP 3 of 14 -- Fetch reference sequences from NCBI
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
# STEP 4 of 14 -- Build pairwise distance matrix
#   edge: refs_to_matrix    reference_df -> reference_matrix
# =============================================================================
# Edge: reference_df -> reference_matrix
# Source: TaxaLikely build_sequence_matrix()

# These are the production choices, not the defaults. Each one changes the
# fitted model, so a run that omits them is fitting something different:
#   by_genus = TRUE          align WITHIN genus. The default (FALSE) aligns the
#                            whole set at once, which is where large reference
#                            sets become unrunnable.
#   pair_retention           keeps every within-species pair and, per sequence,
#     = "best_per_partner"   only its best match to each partner taxon. The
#                            default "all" leaves the between-species pair count
#                            quadratic in genus size.
#   max_seqs_per_taxon = 20L species-stratified cap. Prefer this to a genus cap:
#                            a genus cap drops WHOLE SPECIES, and H2/H3 estimate
#                            BETWEEN-species divergence, so it would bias exactly
#                            the quantity being fitted.
#   min_pair_coverage        must equal train_likelihood_model(min_pair_coverage).
#   seed                     the build draws at random; set it or the matrix is
#                            not reproducible.
ref_matrix <- TaxaLikely::build_sequence_matrix(
  reference_df               = reference_df,
  by_genus                   = TRUE,
  max_seqs_per_taxon         = 20L,
  max_foreign_reps_per_genus = 20L,
  pair_retention             = "best_per_partner",
  min_pair_coverage          = 0.8,
  seed                       = 1L
)
message("Built reference matrix: ", nrow(ref_matrix), " pairwise comparisons")
ref_matrix
reference_matrix <- ref_matrix

# =============================================================================
# STEP 5 of 14 -- Train likelihood model
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
# STEP 6 of 14 -- Evaluate likelihoods from trained model
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

# Likelihoods are evaluated on the ranks the model was fitted on (model_params$Rank_System). Detecting them from the
# match table's columns instead would add any coarser column it carries (kingdom, phylum), on which the model holds no
# ring, and would name a reference identified only at such a rank there instead of returning its observation in
# $unresolved. A model that records no rank system falls back to detection from the match table.
lik_rank_system <- model_params$Rank_System
lik_result <- TaxaLikely::evaluate_likelihoods(
  match_df     = match_df,
  model_params = model_params,
  rank_system  = lik_rank_system,
  n_sims       = 200L
)

# evaluate_likelihoods() also reports the match on its own absolute scale, as
# unit-level columns repeated on every row of the unit: best_identity (the
# unit's best raw identity, percent), best_identity_rank (the finest rank
# whose marker-specific identity threshold it reaches, NA if none) and
# poor_absolute_fit (TRUE when it reaches no rank threshold). Likelihoods are
# normalised to the unit maximum, so the best hypothesis always scores 1 even
# when the match is poor; these three are a FLAG only and never change a
# likelihood or which hypothesis wins. They travel through the posterior and
# consensus tables to review_assignments() (see consensus_to_reviewed).
likelihoods <- TaxaLikely::filter_top_hypotheses(
  lik_result$likelihoods,
  rank_system = lik_rank_system
)
message("Evaluated likelihoods for ", length(unique(likelihoods$observation_id)), " samples")
# An observation whose matches all name a reference only above the rank system
# (only "Eukaryota", say), or whose matches the coverage check removed, has no
# likelihood row; evaluate_likelihoods() returns its match rows in $unresolved.
# They are kept as lik_unresolved, and the consensus step gives each such
# observation a no-call row (consensus_reason "no_usable_likelihood").
lik_unresolved <- lik_result$unresolved
if (nrow(lik_unresolved) > 0L) {
  message("  ", length(unique(lik_unresolved$observation_id)), " observation(s) with no usable likelihood ",
          "(", nrow(lik_unresolved), " match rows); each gets a no-call consensus row")
}
likelihoods
likelihoods <- likelihoods

# =============================================================================
# STEP 7 of 14 -- Fetch occurrence records from GBIF
#   edge: taxa_to_occ    taxa -> occurrences
# =============================================================================
# Edge: taxa -> occurrences
# Source: TaxaFetch/inst/GBIF_workflow.R + Define_search_workflow.R

key_matches <- TaxaFetch::get_keys_from_context(taxa, cache_dir = TAXONOMY_CACHE_DIR)   # answered rows cached: a rerun asks GBIF only for new or failed rows
# fetch_gbif_occurrences() takes the usageKey COLUMN, not the whole table that
# get_keys_from_context() returns: it begins with as.integer(keys), and a data
# frame cannot be coerced to integer. Passing the table raises
# "'list' object cannot be coerced to type 'integer'".
keys <- key_matches$usageKey[!is.na(key_matches$usageKey)]

# --- Check GBIF match quality BEFORE requesting anything ---------------------
# A populated but WRONG key is worse than a missing one, and neither announces
# itself downstream: fetch_gbif_occurrences() drops NA keys silently, so an
# unresolved taxon leaves the occurrence pool without a word, and a FUZZY or
# HIGHERRANK match fetches a DIFFERENT taxon's records under this taxon's name.
# get_keys_from_context()'s own documentation says to review these matchTypes
# before downstream use; this is that review, and it is deliberately a stop.
# What this does NOT catch: an EXACT, ACCEPTED key whose taxon simply holds no
# occurrences in your area. That key is correct and the gap is real data, so
# only a pre-download COUNT can see it -- a separate check, not this one.
# ERROR and NO_DATA rows carry an NA usageKey, so the NA check below covers
# them too. To proceed deliberately, inspect `key_matches`, fix or drop the
# named rows, and re-run -- do not widen the accepted matchTypes.
.key_label <- function(df) {
  out <- rep(NA_character_, nrow(df))
  for (.r in c("species", "genus", "family", "order", "class", "phylum", "kingdom")) {
    .hit <- names(df)[tolower(names(df)) == .r]
    if (!length(.hit)) next
    .v <- trimws(as.character(df[[.hit[1L]]]))
    .fill <- is.na(out) & !is.na(.v) & nzchar(.v)
    out[.fill] <- .v[.fill]
  }
  out
}
# An ALLOWLIST, not a list of known-bad values: GBIF's match API has added
# matchType values before (its v2 has others again), and a value we have never
# seen should stop the run rather than pass unexamined because nobody thought
# to name it. EXACT is the only value that means "this is the taxon you asked
# for".
.suspect <- !(key_matches$matchType %in% "EXACT")
.unresolved <- is.na(key_matches$usageKey)
if (any(.suspect | .unresolved)) {
  .bad <- which(.suspect | .unresolved)
  .labels <- .key_label(key_matches)
  stop(
    "GBIF key lookup: ", length(.bad), " of ", nrow(key_matches),
    " taxa did not resolve to a trustworthy GBIF key.\n",
    paste0("  ", .labels[.bad], " -- matchType ", key_matches$matchType[.bad],
           ", usageKey ", key_matches$usageKey[.bad], collapse = "\n"),
    "\nAn NA key is dropped silently by fetch_gbif_occurrences(); a FUZZY or ",
    "HIGHERRANK key fetches another taxon's records. Resolve or drop these ",
    "rows deliberately, then re-run.",
    call. = FALSE
  )
}
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
# STEP 8 of 14 -- Standardize occurrences and assign habitat
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
  cache_dir          = HABITAT_CACHE_DIR,
  # A scheme label that names several habitats ("Coastal-Marine-Estuary-
  # Stream") can declare its real parts in the scheme's `parts` column
  # (pipe-delimited, e.g. "Marine|Estuary|Stream"). The model then weights the
  # parts, never the compound, and the compound's weight is derived from them:
  # "sum" (default) = the parts' shares added, capped at 1, so a species using
  # ANY part of the site counts for the site; "max" keeps only the largest
  # part and lowers the compound for species spread over several parts. The
  # rule is not in the cache key, so changing it costs no model calls. It has
  # no effect when HABITAT_SCHEME declares no parts.
  compound_rule      = "sum"
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
# STEP 9 of 14 -- Build priors from standardized occurrences, grouped by sampling/detection process (kernel path)
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
# No registry is passed here: the run's taxon registry is built AFTER this step
# (tables_to_registry registers this step's finished prior table), so lineage
# comes from std_occurrences.
priors_undetected <- TaxaExpect::generate_undetected_diversity(
  model_obj = kernel_priors_fit,
  taxonomy  = std_occurrences
)

priors <- dplyr::bind_rows(kernel_priors_fit$priors, priors_undetected) |>
  dplyr::mutate(taxon_name_rank = "species")

message(sprintf(
  "Generated priors for %d resident taxa + %d undetected/dark-diversity row(s) across %d sampling group(s)",
  sum(priors$prior_branch %in% c("kernel_estimated"), na.rm = TRUE),
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
# (name_list, backbone_id, batch_size, timeout_sec, fallback_backbone_id,
# decisions, cache_dir, cache_ttl_days, input_rank, lineage) --
# passing the whole `priors` data frame positionally as
# `name_list` (wrong type: a character vector is expected) and a `taxon_col`
# argument that does not exist, then discarding `priors` by reassigning it
# to the verification result, is a real trap. Verify the taxon names
# informationally without clobbering `priors`.
#
# input_rank is the rank the caller means each name at, one per name_list
# element. A bare name is not a key: "Etheostoma" is a genus and a subgenus,
# and a class-rank name can match a genus of another kingdom. With the rank
# given, a name that resolves to several nodes is settled on the node of that
# rank (NCBI backbone), and a match at another rank is gated on its lineage
# (Global Names backbone). The rank is read from each name's SHAPE, not from
# the priors' taxon_name_rank column: that column is stamped "species" on every
# row above because join_priors() needs a non-NA key, so it is not an
# observation of rank, and asserting "species" for a genus-rank name would pick
# a node and weaken the lineage gate. A plausible binomial is read as species;
# anything else (a single genus name, "sp.", "cf.", an environmental label) as
# genus. Pass your own ranks when your table records them.
# lineage (a pipe-delimited string of ancestor names per name, e.g.
# "Metazoa|Chordata") is the second disambiguator; the priors table carries
# no lineage column, so it is left NULL here -- pass it when your table has one.
.prior_names <- priors[!duplicated(priors$taxon_name) & !is.na(priors$taxon_name), , drop = FALSE]
taxon_verification <- TaxaTools::verify_taxon_names(
  name_list   = .prior_names$taxon_name,
  backbone_id = TARGET_BACKBONE_ID,
  input_rank  = ifelse(TaxaTools::is_plausible_binomial(.prior_names$taxon_name),
                       "species", "genus"),
  cache_dir   = TAXONOMY_CACHE_DIR
)
message(sprintf(
  "Taxon-name verification: %d of %d unique taxon name(s) did not verify against backbone %s",
  sum(!taxon_verification$verified, na.rm = TRUE), nrow(taxon_verification),
  TARGET_BACKBONE_ID
))
# convert_taxonomy_backbone() has no cache of its own; its verify_fn does the lookups. This wrapper adds the run's
# taxonomy cache. It must DECLARE input_rank: convert_taxonomy_backbone() passes each name's rank only to a verify_fn
# whose formals name it, so a function(...) wrapper would silently drop the rank.
.verify_cached <- function(name_list, backbone_id, input_rank = NULL)
  TaxaTools::verify_taxon_names(name_list, backbone_id = backbone_id, input_rank = input_rank,
                                cache_dir = TAXONOMY_CACHE_DIR)
priors <- TaxaMatch::convert_taxonomy_backbone(
  priors,
  target_backbone_id = TARGET_BACKBONE_ID,
  taxon_col           = "taxon_name",
  verify_fn           = .verify_cached
)
message("Generated priors for ", length(unique(priors$taxon_name)), " taxa across ",
        dplyr::n_distinct(std_occurrences[[SAMPLING_GROUP_COL]]), " sampling group(s)")
priors
priors <- priors

# =============================================================================
# STEP 10 of 14 -- Build the run's taxon registry (one GBIF id per taxon)
#   edge: tables_to_registry    match_df + likelihoods + reference_df + std_occurrences + priors -> taxon_registry
# =============================================================================
# Edge: match_df + likelihoods + reference_df + std_occurrences + priors -> taxon_registry
# Source: TaxaTools build_taxon_registry() + freeze_taxon_registry() +
#         check_taxon_registry() + attach_taxon_ids(); TaxaFetch lookup_gbif_taxa()
#
# One taxon registry for the run. Every name the later steps join on is resolved
# ONCE to a GBIF Backbone taxon id: the match object's names and lineage columns,
# the likelihoods' names (candidates and the clades their placeholder rows name),
# the reference database's species, the standardized occurrences, and the FINISHED
# prior table. This step runs after the priors are built, so the names it registers
# for them are the names the posterior step stamps: the names
# convert_taxonomy_backbone() left, plus any domestic/food or evidence rows the prior
# step added, plus each singleton mirror's source species. Answers are cached in TAXONOMY_CACHE_DIR, so a rerun asks nothing.
# The registry is then FROZEN: a name it does not hold is an error later, never a new
# row. The prior and posterior steps reuse this one registry, so a call under a
# synonym meets the prior filed under the accepted name, one taxon under two names is
# one hypothesis, family and order come from the GBIF tree, and outputs carry GBIF
# accepted names (each row keeps its own name in taxon_name_verbatim).
#
# Each name carries its own lineage from these tables as its context (kingdom to
# family, from the match object's lineage columns and any the other tables carry; none
# where the tables disagree). The context refuses an answer in another kingdom or
# phylum (a homonym: "Polyarthra" the rotifer genus vs. an arthropod order) and breaks
# ties between genus or species candidates; at family and above the GBIF backbone's
# own tree decides and the context is not read.
#
# check_taxon_registry(mode = "error") stops here if a lookup FAILED or two different
# taxa were merged with no declared synonymy, rather than guessing. Its full report
# (synonyms merged, names it could only place at genus, run-local names) is kept as
# taxon_registry_report. Set USE_TAXON_REGISTRY to FALSE to join on names instead.
#
# A table that reaches the posterior step without passing through here (prior rows
# added after this step) must have its names added to .reg_names before the freeze.

taxon_registry <- NULL
taxon_registry_report <- NULL
if (isTRUE(USE_TAXON_REGISTRY)) {
  .reg_rows <- function(x, col, tab, rank = NULL) {
    if (is.null(x) || !col %in% names(x)) return(NULL)
    rk <- if (!is.null(rank)) rank else if (col == "taxon_name" && "taxon_name_rank" %in% names(x)) as.character(x$taxon_name_rank) else NA_character_
    d <- unique(data.frame(verbatim_name = as.character(x[[col]]), rank_given = rk, source_table = tab, stringsAsFactors = FALSE))
    d[!is.na(d$verbatim_name) & nzchar(d$verbatim_name), , drop = FALSE]
  }
  .lineage_ranks <- c("kingdom", "phylum", "class", "order", "family", "genus")
  # (name, rank, value) from a table's own lineage: a row's taxon_name takes every column kingdom to family, a lineage
  # value the columns above its own rank
  .ctx_rows <- function(x) {
    lc <- if (is.null(x)) character(0) else intersect(.lineage_ranks, names(x))
    if (!length(lc)) return(NULL)
    x <- as.data.frame(x); out <- list()
    mk <- function(n, r) data.frame(name = as.character(n), rank = r, value = as.character(x[[r]]), stringsAsFactors = FALSE)
    if ("taxon_name" %in% names(x)) for (r in setdiff(lc, "genus")) out[[length(out) + 1L]] <- mk(x$taxon_name, r)
    for (k in seq_along(lc)) for (r in setdiff(lc[seq_len(k - 1L)], "genus")) out[[length(out) + 1L]] <- mk(x[[lc[k]]], r)
    do.call(rbind, out)
  }
  .ctx_long <- unique(do.call(rbind, lapply(list(match_df, likelihoods, reference_df, std_occurrences, priors), .ctx_rows)))
  if (is.null(.ctx_long)) .ctx_long <- data.frame(name = character(0), rank = character(0), value = character(0))
  .ctx_long <- .ctx_long[!is.na(.ctx_long$name) & nzchar(.ctx_long$name) & !is.na(.ctx_long$value) & nzchar(trimws(.ctx_long$value)), , drop = FALSE]
  .ctx_long$rank <- factor(.ctx_long$rank, levels = .lineage_ranks)
  .ctx_of <- vapply(split(.ctx_long, as.character(.ctx_long$name)), function(d) {
    if (any(tapply(d$value, d$rank, function(v) length(unique(v))) > 1L, na.rm = TRUE)) return(NA_character_)   # tables disagree
    d <- d[order(d$rank), , drop = FALSE]; paste(unique(d$value), collapse = "|")
  }, "")
  .reg_names <- rbind(
    .reg_rows(match_df, "taxon_name", "match"),
    do.call(rbind, lapply(.lineage_ranks, function(r) .reg_rows(match_df, r, "match", rank = r))),
    .reg_rows(likelihoods, "taxon_name", "likelihoods"),
    .reg_rows(reference_df, "species", "reference", rank = "species"),
    .reg_rows(std_occurrences, "taxon_name", "occurrences"),
    # the finished prior table, under the table name the posterior step stamps it with
    .reg_rows(priors, "taxon_name", "priors"),
    .reg_rows(priors, "source_taxon_name", "priors", rank = "species")
  )
  .reg_names <- unique(.reg_names)
  .reg_names$context <- unname(.ctx_of[.reg_names$verbatim_name])
  taxon_registry <- TaxaTools::freeze_taxon_registry(TaxaTools::build_taxon_registry(
    .reg_names,
    run_id          = format(Sys.time(), "run-%Y%m%d-%H%M%S"),
    key_backbone_id = 11L,
    lookup          = function(names, rank, context) {
      TaxaFetch::lookup_gbif_taxa(names, rank, context, cache_dir = TAXONOMY_CACHE_DIR)
    }
  ))
  taxon_registry_report <- TaxaTools::check_taxon_registry(taxon_registry, mode = "error")
  std_occurrences <- TaxaTools::attach_taxon_ids(std_occurrences, taxon_registry, "taxon_name", "occurrences")
  message(sprintf("Taxon registry: %d names -> %d taxa (GBIF Backbone); frozen.",
                  length(unique(.reg_names$verbatim_name)), nrow(taxon_registry$taxa)))
}
taxon_registry
taxon_registry <- taxon_registry

# =============================================================================
# STEP 11 of 14 -- Join priors and compute Bayesian posteriors (single site)
#   edge: lik_prior_to_post    likelihoods + priors -> posteriors
# =============================================================================
# Edge: likelihoods + priors -> posteriors
# Source: TaxaAssign join_priors() + compute_posterior()
# NOTE: SITE_HABITAT is the habitat type (e.g. "Freshwater", "Marine",
#   "Estuarine"). This is required — the pipeline does not guess which
#   habitat your samples came from.
# NOTE: BACKBONE_ID is required — no default. Must match whichever
#   taxonomic backbone the input taxonomy was verified against (e.g. 11
#   for GBIF, 4 for NCBI).

# --- Build site specification ---
# The kernel prior is centred on the site: its rows carry the fit's own site id
# (kernel_priors_fit$params$site_id) in their grid_id column, and the site is
# named by that id. Without a kernel fit in the session, the prior table's one
# site id is used.
.site_key <- if (exists("kernel_priors_fit")) kernel_priors_fit$params$site_id else NULL
if (is.null(.site_key)) {
  .site_key <- unique(stats::na.omit(as.character(priors$grid_id)))
  if (length(.site_key) != 1L) {
    stop("lik_prior_to_post: no kernel_priors_fit in the session, and the prior table holds ",
         length(.site_key), " site ids in grid_id (need exactly one); ",
         "use the multi-site step for several sites.")
  }
}
site_spec <- list(grid_id = .site_key, main_habitat = SITE_HABITAT)

# --- The run's taxon registry (taxa matched by GBIF id, not by name) ---
# The registry built once for the run (edge tables_to_registry) is reused here; the
# likelihoods and priors are stamped with it and join_priors() / posterior_consensus()
# match taxa by id. Used on its own (no earlier registry), this step builds one from
# the likelihood and prior names. Set USE_TAXON_REGISTRY to FALSE to join on names.
if (!exists("taxon_registry")) taxon_registry <- NULL
if (isTRUE(USE_TAXON_REGISTRY) && is.null(taxon_registry)) {
  .reg_tab <- function(x, tab) {
    d <- unique(data.frame(verbatim_name = as.character(x$taxon_name),
                           rank_given = if ("taxon_name_rank" %in% names(x)) as.character(x$taxon_name_rank) else NA_character_,
                           source_table = tab, stringsAsFactors = FALSE))
    d[!is.na(d$verbatim_name) & nzchar(d$verbatim_name), , drop = FALSE]
  }
  # each name's own lineage from these tables as its context (kingdom to family; none where the tables disagree): it
  # refuses a cross-phylum homonym and breaks genus/species ties; at family and above the GBIF backbone decides
  .reg_ctx <- function(d, tabs) {
    lr <- c("kingdom", "phylum", "class", "order", "family", "genus")
    rows <- do.call(rbind, lapply(tabs, function(x) {
      lc <- intersect(lr, names(x)); if (!length(lc)) return(NULL); x <- as.data.frame(x); out <- list()
      mk <- function(n, r) data.frame(name = as.character(n), rank = r, value = as.character(x[[r]]), stringsAsFactors = FALSE)
      if ("taxon_name" %in% names(x)) for (r in setdiff(lc, "genus")) out[[length(out) + 1L]] <- mk(x$taxon_name, r)
      for (k in seq_along(lc)) for (r in setdiff(lc[seq_len(k - 1L)], "genus")) out[[length(out) + 1L]] <- mk(x[[lc[k]]], r)
      do.call(rbind, out)
    }))
    d$context <- NA_character_
    if (is.null(rows)) return(d)
    rows <- unique(rows[!is.na(rows$name) & !is.na(rows$value) & nzchar(trimws(rows$value)), , drop = FALSE])
    rows$rank <- factor(rows$rank, levels = lr)
    ctx <- vapply(split(rows, as.character(rows$name)), function(z) {
      if (any(tapply(z$value, z$rank, function(v) length(unique(v))) > 1L, na.rm = TRUE)) return(NA_character_)
      z <- z[order(z$rank), , drop = FALSE]; paste(unique(z$value), collapse = "|")
    }, "")
    d$context <- unname(ctx[d$verbatim_name])
    d
  }
  taxon_registry <- TaxaTools::freeze_taxon_registry(TaxaTools::build_taxon_registry(
    .reg_ctx(rbind(.reg_tab(likelihoods, "likelihoods"), .reg_tab(priors, "priors")), list(likelihoods, priors)),
    run_id = format(Sys.time(), "run-%Y%m%d-%H%M%S"), key_backbone_id = 11L,
    lookup = function(names, rank, context) TaxaFetch::lookup_gbif_taxa(names, rank, context, cache_dir = TAXONOMY_CACHE_DIR)
  ))
  invisible(TaxaTools::check_taxon_registry(taxon_registry, mode = "error"))
}
if (isTRUE(USE_TAXON_REGISTRY)) {
  likelihoods <- TaxaTools::attach_taxon_ids(likelihoods, taxon_registry, "taxon_name", "likelihoods")
  priors <- TaxaTools::attach_taxon_ids(priors, taxon_registry, "taxon_name", "priors")
}

# --- Join + posterior ---
detected_ranks <- TaxaTools::detect_ranks(match_df)

likelihoods_ready <- TaxaAssign::join_priors(
  likelihoods       = likelihoods,
  taxaexpect_priors = priors,
  site              = site_spec,
  taxonomy_lookup   = match_df,
  rank_system       = detected_ranks,
  backbone_id       = BACKBONE_ID,
  taxonomy_cache_dir = TAXONOMY_CACHE_DIR,
  registry          = taxon_registry
)

# compute_posterior() pools named unreferenced rows whose point posterior is
# below 0.05 into their ring (the coarser relative they descend from) instead
# of carrying each as a candidate. Its output always has three pooled columns:
# pooled_n (rows pooled), pooled_prior_mass (their summed prior) and
# pooled_taxa (their names joined by "; "); they are NA on rows that are not
# rings. The pooled rows themselves are in attr(posteriors, "pooled_rows")
# (observation_id, ring_taxon, taxon_name, prior_mean, posterior_point_est).
# Attributes do NOT survive a dplyr verb: read it before any join or mutate.
posteriors <- TaxaAssign::compute_posterior(likelihoods_ready, n_sims = 1000L)
message("Pooled ", nrow(attr(posteriors, "pooled_rows")), " named unreferenced row(s) into rings")
message("Computed posteriors for ", length(unique(posteriors$observation_id)), " samples")
posteriors
posteriors <- posteriors

# =============================================================================
# STEP 12 of 14 -- Posterior consensus via LCA
#   edge: post_to_consensus    posteriors -> consensus
# =============================================================================
# Edge: posteriors -> consensus
# Source: TaxaAssign/inst/TaxaAssign_bayesian_workflow.R

# Checked first, before any consensus is computed: the end of this step gives every observation in
# lik_unresolved (from the likelihood step) a no-call row, so a session without it stops here rather than after
# both consensus rounds.
if (!exists("lik_unresolved") || !is.data.frame(lik_unresolved)) {
  stop(errorCondition(paste0(
    "post_to_consensus: no lik_unresolved data frame in the session. The likelihood step (model_match_to_lik) ",
    "keeps evaluate_likelihoods()'s $unresolved as lik_unresolved so that every observation gets a consensus row; ",
    "without it an observation with no usable likelihood would leave the consensus table unreported. Run that ",
    "step, or after your own evaluate_likelihoods() call set lik_unresolved <- <its result>$unresolved."),
    class = "taxaid_lik_unresolved_missing", call = NULL))
}

# Optional: group-level occurrence priors. consensus_prior
# becomes a real group-level SUM over every locally modelled member sharing
# a rank, instead of a candidate-scoped max -- a materially stronger
# occurrence-plausibility signal, since a single observation's own candidate
# set rarely contains every locally modelled group member. Requires the
# TaxaExpect priors object (priors) and a taxonomy_map
# data frame with real genus/family columns (taxa, e.g. the
# occurrences_clean object from earlier in this pipeline). Set
# INCLUDE_GROUP_PRIORS to FALSE to skip entirely.
# With the run's taxon registry, the map is the registry's own tree over the
# priors' taxon ids, so groups are the clades the consensus is formed on (a
# genus the registry places in another family sums into THAT family) and every
# group name is one the registry holds; posterior_consensus(registry =) refuses
# a group or reference name it cannot resolve.
.consensus_taxonomy_map <- if (exists("taxon_registry") && !is.null(taxon_registry) &&
                               "taxon_id" %in% names(priors)) {
  .tm <- unique(data.frame(taxon_name = as.character(priors$taxon_name),
                           taxon_id = as.character(priors$taxon_id), stringsAsFactors = FALSE))
  .tm <- .tm[!is.na(.tm$taxon_name) & !is.na(.tm$taxon_id) & !duplicated(.tm$taxon_name), , drop = FALSE]
  .reg_nm <- stats::setNames(taxon_registry$taxa$name, taxon_registry$taxa$taxon_id)
  for (.r in c("class", "order", "family", "genus")) .tm[[.r]] <- unname(.reg_nm[TaxaTools::parent_at(.tm$taxon_id, .r, taxon_registry)])
  .tm$taxon_id <- NULL
  .tm
} else {
  taxa
}
group_priors_obj <- if (isTRUE(INCLUDE_GROUP_PRIORS)) {
  TaxaAssign::compute_group_priors(
    taxaexpect_priors = priors,
    taxonomy_map      = .consensus_taxonomy_map
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
  .not_clamp <- if ("prior_branch" %in% names(priors)) priors$prior_branch %in% c("kernel_estimated", "transport") else if ("evidence_sources" %in% names(priors)) !(priors$evidence_sources %in% "distance_clamp") else rep(TRUE, nrow(priors))
  priors[.not_clamp, , drop = FALSE] |>
    dplyr::filter(!is.na(taxon_name)) |>
    dplyr::distinct(taxon_name) |>
    dplyr::left_join(.consensus_taxonomy_map, by = "taxon_name") |>
    unique()
} else {
  NULL
}

# Consensus method: "credible_node" with robust_prior_s = 0 and
# cross_phylum_eps = 0 is the weighted LCA (node summing): the posterior of
# every hypothesis under a taxon is summed rank by rank from the finest, and
# the finest taxon holding at least cumulative_threshold of ALL the
# observation's posterior is reported. robust_prior_s = 0 turns off the
# imprecise-Dirichlet prior check and cross_phylum_eps = 0 the cross-phylum
# withholding, both of which only apply with "credible_node". These three are
# also the package defaults; this template passes them explicitly so the
# choice is visible rather than inherited. Pass consensus_method = "lca" for
# the lowest common taxon of the smallest top set reaching the threshold.
# Use the same three arguments in both calls below.
#
# The posterior table's pooled_n / pooled_prior_mass / pooled_taxa columns
# (see lik_prior_to_post) stay on the table: a ring row stands for the named
# unreferenced rows pooled into it, listed in pooled_taxa. posterior_consensus()
# reads the "pooled_rows" attribute to warn when min_posterior is set below the
# pooling floor (0.05), which would show those rows only through their ring;
# min_posterior = 0.05 below is not below it. The likelihoods' best_identity,
# best_identity_rank and poor_absolute_fit columns are carried onto the
# consensus table as unit-level columns, for review_assignments().
consensus <- TaxaAssign::posterior_consensus(
  posteriors,
  cumulative_threshold   = CUMULATIVE_THRESHOLD,
  min_posterior           = 0.05,
  posterior_col           = "posterior_point_est",
  lookup_missing_taxonomy = TRUE,
  backbone_id             = 4,
  rank_system             = RANK_SYSTEM,
  species_reference       = species_reference_df,
  group_priors            = group_priors_obj,
  consensus_method        = "credible_node",
  robust_prior_s          = 0,
  cross_phylum_eps        = 0,
  taxonomy_cache_dir      = TAXONOMY_CACHE_DIR,
  # the run's taxon registry when the posterior step built one: lineage from its tree, no name lookups
  registry                = if (exists("taxon_registry")) taxon_registry else NULL
)

# Optional: empirical Bayes refinement. n_sims defaults to 1000, which
# propagates uncertainty through the re-run as the production workflows do;
# pass n_sims = 0 for point estimates only if the refinement is being tried
# out rather than reported.
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
  group_priors            = group_priors_obj,
  consensus_method        = "credible_node",
  robust_prior_s          = 0,
  cross_phylum_eps        = 0,
  taxonomy_cache_dir      = TAXONOMY_CACHE_DIR,
  # the run's taxon registry when the posterior step built one: lineage from its tree, no name lookups
  registry                = if (exists("taxon_registry")) taxon_registry else NULL
) |> TaxaAssign::add_slash_taxon()
# add_slash_taxon() derives consensus_OTU + primary_taxon (present whenever
# consensus_taxon is in consensus_final).

# Every observation gets a consensus row. One that evaluate_likelihoods()
# returned in $unresolved (lik_unresolved, from the likelihood step: every match
# names a reference only above the rank system, such as "Eukaryota", or the
# coverage check removed them all) has no likelihood and never reaches
# posterior_consensus(). It gets a no-call row here: consensus_reason
# "no_usable_likelihood", and coarsest_reference_lineage, the lineage its matched
# references share (e.g. "Eukaryota"), which shows how coarsely the references
# were named for this marker. coarsest_reference_lineage is NA on every other row.
consensus_final$coarsest_reference_lineage <- rep(NA_character_, nrow(consensus_final))
if (nrow(lik_unresolved) > 0L) {
  .nu_lin_cols <- intersect(TaxaTools::standard_ranks, names(lik_unresolved))
  .nu_sid <- as.character(lik_unresolved$observation_id)
  .nu_ids <- setdiff(unique(.nu_sid), as.character(consensus_final$observation_id))
  .nu_lineage <- vapply(.nu_ids, function(id) {
    .m <- lik_unresolved[.nu_sid == id, .nu_lin_cols, drop = FALSE]
    .path <- character(0)
    for (.r in .nu_lin_cols) {
      .v <- as.character(.m[[.r]])
      if (all(is.na(.v) | !nzchar(.v))) next
      if (anyNA(.v) || length(unique(.v)) != 1L) break
      .path <- c(.path, .v[1L])
    }
    if (length(.path) > 0L) paste(.path, collapse = "|") else NA_character_
  }, character(1), USE.NAMES = FALSE)
  # the ids take the consensus table's own type: bind_rows() will not join character ids with integer ones
  if (is.factor(consensus_final$observation_id)) consensus_final$observation_id <- as.character(consensus_final$observation_id)
  .nu_oid <- if (is.integer(consensus_final$observation_id)) as.integer(.nu_ids) else if (is.numeric(consensus_final$observation_id)) as.numeric(.nu_ids) else .nu_ids
  .nu_rows <- data.frame(observation_id = .nu_oid,
                         consensus_taxon = rep(NA_character_, length(.nu_ids)),
                         consensus_rank = rep(NA_character_, length(.nu_ids)),
                         consensus_reason = rep("no_usable_likelihood", length(.nu_ids)),
                         is_resolved = rep(FALSE, length(.nu_ids)),
                         coarsest_reference_lineage = .nu_lineage, stringsAsFactors = FALSE)
  .nu_attr <- attributes(consensus_final)
  .nu_attr <- .nu_attr[setdiff(names(.nu_attr), c("names", "row.names", "class"))]
  consensus_final <- dplyr::bind_rows(consensus_final, .nu_rows)
  for (.a in names(.nu_attr)) attr(consensus_final, .a) <- .nu_attr[[.a]]
  message("Consensus: ", length(.nu_ids), " observation(s) with no usable likelihood get a no-call row ",
          "(consensus_reason \"no_usable_likelihood\")")
}
message("Consensus: ", sum(consensus_final$is_resolved), " of ",
        nrow(consensus_final), " samples resolved")
consensus_final
consensus <- consensus_final

# =============================================================================
# STEP 13 of 14 -- Infer ecological context via LLM
#   edge: taxa_to_context    taxa -> context_df
# =============================================================================
# Edge: taxa -> context_df
# Source: TaxaAssign::build_context()

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
# STEP 14 of 14 -- LLM expert review of assignments
#   edge: consensus_to_reviewed    consensus + context_df -> reviewed
# =============================================================================
# Edge: consensus + context_df -> reviewed
# Source: TaxaFlag/inst/review_assignments_workflow.R
# NOTE: When data comes from posterior_consensus() or
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
  # Fit columns from evaluate_likelihoods(), carried through
  # posterior_consensus(). poor_absolute_fit is TRUE when the unit's best raw
  # match identity (best_identity, percent) reaches no rank threshold for the
  # marker: likelihoods are normalised to the unit maximum, so such a call can
  # still carry a high posterior and the raw identity is the only thing that
  # says otherwise. best_identity is quoted for EVERY taxon that has one, not
  # only for a poor fit; where poor_absolute_fit is TRUE the same number is
  # quoted inside that note instead. A column that is absent is skipped; both
  # defaults are shown so the link is visible. NULL turns either off.
  poor_absolute_fit_col = "poor_absolute_fit",
  best_identity_col     = "best_identity",
  # The review is BLIND to this pipeline's own numbers by default: the
  # posterior, the occurrence prior, the GBIF distance and the iNaturalist
  # fields are all NULL unless named, so none of them reaches the prompt. A
  # review shown the pipeline's confidence cannot contradict it independently,
  # and one shown a taxon's GBIF distance cannot catch an error in the
  # occurrence data. What it IS shown is the DNA evidence -- the two arguments
  # just above among them -- and the study's own design. See
  # ?review_assignments, "What the review is shown, and what it is not".
  # consensus_provenance (default TRUE): a call that landed on an UNREFERENCED
  # row gets one note, "named taxon has NO reference sequence". The scope the
  # name came from and how many species the records held there are NOT sent --
  # both report what the occurrence records contain. It reads
  # posterior_consensus()'s consensus_hypothesis_type.
  consensus_provenance  = TRUE,
  # model_label: names the model behind llm_fn in the cache key, so a verdict
  # from one model is never served to a call asking another. NULL derives it
  # from options("TaxaID.provider") and llm_fn; name it yourself when you
  # compare two models from ONE provider.
  model_label    = NULL,
  # Abort rather than export a silently short species list. An LLM review can
  # parse cleanly, return the right number of objects, and still OMIT specific
  # taxa -- consistently the long compound slash labels, i.e. the hardest
  # rows. Those get NA in every llm_ column, and any export filter that tests
  # `llm_* != "unlikely"` DISCARDS NA, so the observation would leave the final
  # species list without a word. Measured on a real PtConception 12S run:
  # 20 observations across 3 plausible local fishes, gone.
  #
  # Note which filter that is. This script and the template drop nothing on an
  # LLM VERDICT -- the template's only subsetting is by expert_excluded, a
  # human decision and empty by default -- so an llm_* filter is one a reader
  # may add downstream of here, not one above.
  # review_assignments() now re-asks for omitted taxa; "error" makes any
  # residue that survives the re-ask stop the run rather than reach such a
  # filter at all.
  on_unreviewed  = "error"
)
message("Reviewed ", nrow(reviewed), " assignments")

# --- Multi-site studies: per-site geography ----------------------------------
# This path reviews one site, so it leaves review_assignments(sites=) unset.
# A study with several sites passes sites = <site table> and site_col =, and
# gets a per-taxon, per-site verdict in llm_geographic_plausibility_site plus
# the parsed rules in attr(reviewed, "geographic_by_site").
#
# Read `how` in that attribute before trusting a per-site verdict. One case
# needs handling outside the package: a rule can name a single latitude bound
# on the wrong side, so a southern range limit written as lat_max puts every
# northern site outside the band. The taxon's study-wide verdict then says
# "likely" while its per-site verdict says "unlikely" everywhere it was
# actually detected. TaxaFlag holds no occurrence data and cannot tell that
# from a correct exclusion, so the check belongs here, where the records and
# the site table already are: count distinct record locations near the site,
# and where there are enough, screen on the study-wide verdict instead.
# Keep the reviewer's own column untouched and write the adjusted verdict to
# its own column, so a report can still say what it did. The worked pattern,
# with the NA-versus-0 rule and the row-count assertion, is in TaxaFlag's
# README under "Overriding a per-site verdict with local records".

# Always check: attributes do NOT survive a dplyr verb, so read this before
# any join or mutate.
if (length(attr(reviewed, "unreviewed_taxa"))) {
  message("  !! unreviewed: ",
          paste(attr(reviewed, "unreviewed_taxa"), collapse = ", "))
}
# --- FLAG, do not drop -------------------------------------------------------
# The review is a judgement: its verdicts can differ between runs on identical
# input, so it must not remove rows from the products. It only FLAGS. The four
# ratings stay as columns, and llm_review_flag is TRUE where any of them reads
# "unlikely" (contamination risk "high"). Every row stays in `reviewed`.
reviewed$llm_review_flag <-
  reviewed$llm_habitat_plausibility    %in% "unlikely" |
  reviewed$llm_geographic_plausibility %in% "unlikely" |
  reviewed$llm_scope_plausibility      %in% "unlikely" |
  reviewed$llm_contamination_risk      %in% "high"

# Expert decisions are DATA, not code: lists of observation_id values that a
# human reviewer decided. Leave both empty until someone has looked at the
# flagged rows (print them with the call below).
#   EXPERT_KEEP_IDS     -- flagged by the LLM, but the reviewer keeps the call.
#   EXPERT_EXCLUDE_IDS  -- withheld from the products, whatever the LLM said.
# Record the reason for each decision beside the list, in a file the run reads.
EXPERT_KEEP_IDS    <- character(0)
EXPERT_EXCLUDE_IDS <- character(0)
unknown_ids <- setdiff(c(EXPERT_KEEP_IDS, EXPERT_EXCLUDE_IDS), reviewed$observation_id)
if (length(unknown_ids)) {
  stop("Expert decision(s) name observation_id(s) not in this run: ",
       paste(unknown_ids, collapse = ", "), call. = FALSE)
}
reviewed$expert_keep      <- reviewed$observation_id %in% EXPERT_KEEP_IDS
reviewed$expert_excluded  <- reviewed$observation_id %in% EXPERT_EXCLUDE_IDS
# An LLM flag stands unless the reviewer keeps the call.
reviewed$review_flag_stands <- reviewed$llm_review_flag & !reviewed$expert_keep
message("LLM-flagged: ", sum(reviewed$llm_review_flag, na.rm = TRUE),
        " (", sum(reviewed$review_flag_stands, na.rm = TRUE), " stand after expert keeps); ",
        "expert-excluded: ", sum(reviewed$expert_excluded))
# To inspect: reviewed[reviewed$review_flag_stands,
#   c("observation_id", "consensus_taxon", "llm_habitat_plausibility",
#     "llm_geographic_plausibility", "llm_scope_plausibility",
#     "llm_contamination_risk", "review_comment")]

# Products carry the flag columns; only expert exclusions leave them.
reviewed_products <- reviewed[!reviewed$expert_excluded, , drop = FALSE]
reviewed
reviewed <- reviewed

# =============================================================================
# Workflow complete. `reviewed` holds the final assignments.
# =============================================================================
