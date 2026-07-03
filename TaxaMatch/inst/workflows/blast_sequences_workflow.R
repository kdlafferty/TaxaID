# ==============================================================================
# WORKFLOW: BLAST SEQUENCES AGAINST NCBI (TaxaMatch)
# ==============================================================================
# Purpose: Submit real DNA barcode sequences to live remote NCBI BLAST and
#   standardize the response into a canonical match object, ready for
#   TaxaLikely's sequence-model score-to-likelihood conversion.
#
# Audience: someone learning TaxaMatch's SEQUENCE/eDNA data-type path step by
#   step. This is a SEPARATE tutorial chain from the five-package Gadus/GBIF-
#   occurrence chain (fetch_occurrences_workflow.R etc.) and from the
#   image/acoustic mini-chain (score_image_workflow.R /
#   score_acoustic_workflow.R) -- BLAST/eDNA has no natural connection to
#   either, so this script starts its own real-data story.
#
# THIS SCRIPT IS THE FIRST OF A TWO-PACKAGE MINI-CHAIN:
#   TaxaMatch (this script) -> TaxaLikely (inst/workflows/
#   sequence_likelihood_workflow.R: build_sequence_matrix() ->
#   train_likelihood_model() -> evaluate_likelihoods()).
# This script stops at the canonical match object -- it does not train or
# apply the bivariate-normal likelihood model itself.
#
# NO SYNTHETIC DATA: 5 real 12S MiFish amplicon sequences (~170bp) from the
# user's own PtConception eDNA study (JVB3105-MiFishU-esv-data.csv), deposited
# to NCBI under accessions OQ846539/OQ846195/OQ846544/OQ846550/OQ846725.
# Field-tested in Session 115 (inst/test_blast_remote.R): all 5/5 top BLAST
# hits returned at >=98% identity to the correct species. This script
# reproduces that field test in the Layer-1 workflow-script convention
# (DEBUG_MODE tutorial data, explicit checkpoints, Output block) rather than
# introducing a new example dataset.
#
# Output: taxamatch_blast_match_obj -- see "Output" block at the end of this
#   file for the full column contract passed to TaxaLikely.
# ==============================================================================

# --- Namespaces used in this script (loaded, never attached) ----------------
# TaxaMatch::, TaxaTools::, rentrez::

# ==============================================================================
# CONFIG
# ==============================================================================
# Parameters are grouped here so this script's body can become a wrapper
# function's implementation with minimal changes -- each CONFIG value maps to
# a future function argument.

# DEBUG_MODE = TRUE  -> live-call remote NCBI BLAST on the 5 known
#                       PtConception 12S sequences described above.
# DEBUG_MODE = FALSE -> plug in your own sequence data (see the
#                       "SWAP IN YOUR OWN DATA" block below)
DEBUG_MODE <- TRUE

# NCBI requires a contact email for remote BLAST (usage policy). An NCBI API
# key is optional but raises the rate limit -- read from ENTREZ_KEY in
# ~/.Renviron if set.
MY_EMAIL   <- "lafferty@ucsb.edu"
MY_API_KEY <- Sys.getenv("ENTREZ_KEY", unset = NA_character_)
if (is.na(MY_API_KEY) || !nzchar(MY_API_KEY)) MY_API_KEY <- NULL

# blast_sequences() score-window parameters. These known-reference sequences
# warrant a high min_score (95) -- a real unknown-identity survey would
# typically use a lower floor (e.g. 70, blast_sequences()'s own default) to
# avoid discarding genuine but imperfect matches.
BARCODE_TERM        <- "12S"
SCORE_RANGE         <- 2
MAX_HITS            <- 10L
MIN_SCORE           <- 95
MIN_QUERY_COVERAGE  <- 85

if (DEBUG_MODE) {

  # ---- Tutorial example: 5 known real PtConception 12S sequences, fetched --
  # ---- live from NCBI by accession (not bundled -- these are short lookups) -
  message("DEBUG_MODE = TRUE -- fetching 5 known real PtConception 12S MiFish ",
          "sequences from NCBI by accession (field-tested Session 115: 5/5 ",
          "100% correct-species top hits).")

  # true_species is added purely for THIS TUTORIAL's own honesty check below
  # (comparing BLAST's top hit against known ground truth) -- it is not part
  # of the canonical match object contract and is dropped before any
  # downstream use beyond this tutorial.
  TRUE_SPECIES <- c(
    OQ846539 = "Clinocottus recalvus",       # snubnose sculpin
    OQ846195 = "Rhacochilus toxotes",        # rubberlip surfperch
    OQ846544 = "Gibbonsia montereyensis",    # crevice kelpfish
    OQ846550 = "Oligocottus snyderi",        # tidewater sculpin
    OQ846725 = "Embiotoca caryi"             # black perch
  )

  fasta_text <- rentrez::entrez_fetch(
    db = "nucleotide", id = names(TRUE_SPECIES), rettype = "fasta"
  )

  # Minimal FASTA parse preserving the original accession as asv_id (needed
  # to join the honesty check below) -- read_sequence_table()'s own FASTA
  # path discards header identifiers in favor of generated "ASV_001"-style
  # IDs, which would lose that traceability.
  .lines      <- strsplit(fasta_text, "\n")[[1L]]
  .header_idx <- which(startsWith(.lines, ">"))
  .seq_start  <- .header_idx + 1L
  .seq_end    <- c(.header_idx[-1L] - 1L, length(.lines))
  .ids  <- sub("^>([^ .]+).*", "\\1", .lines[.header_idx])
  .seqs <- vapply(seq_along(.header_idx), function(i) {
    paste(.lines[.seq_start[i]:.seq_end[i]], collapse = "")
  }, character(1L))

  seq_df <- data.frame(
    asv_id    = .ids,
    sequence  = .seqs,
    abundance = 1L,
    stringsAsFactors = FALSE
  )
  seq_df <- seq_df[nzchar(seq_df$sequence), ]
  seq_df$length       <- nchar(seq_df$sequence)
  seq_df$true_species  <- TRUE_SPECIES[seq_df$asv_id]

  message(sprintf(
    "  Fetched %d sequence(s), lengths %d-%d bp.",
    nrow(seq_df), min(seq_df$length), max(seq_df$length)
  ))

} else {

  # ==========================================================================
  # >>> SWAP IN YOUR OWN DATA <<<
  # ==========================================================================
  # Replace the block above with your own sequences via
  # TaxaMatch::read_sequence_table(), which accepts a DADA2 sequence table
  # (matrix), a FASTA file path, or a Biostrings::DNAStringSet:
  #
  #   seq_df <- TaxaMatch::read_sequence_table("path/to/your_sequences.fasta")
  #   # or: TaxaMatch::read_sequence_table(seqtab_nochim)  # DADA2 output
  #
  #   (true_species only exists for the honesty check below -- for a real,
  #   unknown-identity survey, skip it and just BLAST your seq_df directly)
  #
  # Set DEBUG_MODE <- FALSE above and fill in the values here.
  # ==========================================================================
  stop("DEBUG_MODE is FALSE but no real sequence data has been supplied. ",
       "Edit the 'SWAP IN YOUR OWN DATA' block in this script.")
}

# Output location for checkpoint files (see explicit-checkpoint pattern below)
OUT_DIR    <- tempdir()
OUT_PREFIX <- "tutorial_ptconception_blast"

# ==============================================================================
# 1.  FILTER SEQUENCES
# ==============================================================================
# Sanity-check step for known reference sequences (all already 12S, all
# abundance = 1 single references) -- a real ASV table from DADA2 would use
# this to drop low-abundance noise before the (rate-limited, slow) BLAST step.
# ==============================================================================

message("\n--- Step 1: Filtering sequences (barcode_term, min_abundance) ---")

seq_df_filtered <- TaxaMatch::filter_sequences(
  seq_df,
  barcode_term  = BARCODE_TERM,
  min_abundance = 1L
)

message(sprintf("  Retained %d/%d sequence(s).", nrow(seq_df_filtered), nrow(seq_df)))

# ==============================================================================
# 2.  BLAST -- LIVE REMOTE NCBI CALL
# ==============================================================================
# Real remote BLAST against NCBI nt. Rate-limited internally (>=10s between
# submission batches, per NCBI usage policy). Expected runtime for this
# 5-sequence, 1-batch tutorial: ~5-10 minutes (mostly server-side queueing,
# not client-side work).
# ==============================================================================

message("\n--- Step 2: BLASTing sequences against NCBI nt (remote, live) ---")
message("  This takes several minutes -- NCBI queues and processes the search ",
        "server-side; polling continues automatically.")

.t0 <- proc.time()[["elapsed"]]

taxamatch_blast_hits <- TaxaMatch::blast_sequences(
  seq_df_filtered,
  method              = "remote",
  database            = "nt",
  score_range         = SCORE_RANGE,
  max_hits            = MAX_HITS,
  min_score           = MIN_SCORE,
  min_query_coverage  = MIN_QUERY_COVERAGE,
  barcode_term        = BARCODE_TERM,
  email               = MY_EMAIL,
  ncbi_api_key        = MY_API_KEY,
  resolve_taxonomy    = TRUE,
  verbose             = TRUE
)

message(sprintf(
  "  BLAST finished in %.0f seconds -- %d hit(s) across %d quer(ies).",
  proc.time()[["elapsed"]] - .t0,
  nrow(taxamatch_blast_hits), length(unique(taxamatch_blast_hits$observation_id))
))

# ---- Honesty check: does the top BLAST hit match ground truth? -------------
# This is a real accuracy check on real data, not a synthetic sanity check --
# useful to report even though it isn't part of the match object itself.
# CONFIRMED IN SESSION 115's FIELD TEST: 5/5 correct at >=98% identity.
if (DEBUG_MODE) {
  .top1 <- taxamatch_blast_hits[order(
    taxamatch_blast_hits$observation_id, -taxamatch_blast_hits$score
  ), ]
  .top1 <- .top1[!duplicated(.top1$observation_id), ]
  .top1$true_species <- TRUE_SPECIES[.top1$observation_id]
  message(sprintf(
    "  Top-1 BLAST accuracy on this sequence set: %d/%d correct (%.0f%%).",
    sum(.top1$species == .top1$true_species, na.rm = TRUE),
    nrow(.top1),
    100 * mean(.top1$species == .top1$true_species, na.rm = TRUE)
  ))
}

# ==============================================================================
# 3.  STANDARDIZE -- BUILD THE CANONICAL MATCH OBJECT
# ==============================================================================
# blast_sequences() already returns query_coverage (BLAST's own alignment
# quality metric) -- passed through as coverage_col so TaxaLikely's
# evaluate_likelihoods(min_coverage = ...) can use it downstream without an
# extra join.
# ==============================================================================

message("\n--- Step 3: Standardizing to the canonical match object ---")

taxamatch_blast_match_obj <- TaxaMatch::standardize_match_data(
  data                = taxamatch_blast_hits,
  observation_id_col   = "observation_id",
  score_col            = "score",
  rank_system          = c("family", "genus", "species"),
  coverage_col         = "query_coverage"
)

message(sprintf(
  "  Final match object: %d row(s), %d quer(ies), %d unique taxa.",
  nrow(taxamatch_blast_match_obj),
  length(unique(taxamatch_blast_match_obj$observation_id)),
  length(unique(taxamatch_blast_match_obj$taxon_name))
))

# true_species is added purely for THIS TUTORIAL's own honesty check (here and
# in the next script, TaxaLikely's sequence_likelihood_workflow.R) -- it is
# not part of the canonical match object contract. CAUGHT LIVE-TESTING
# sequence_likelihood_workflow.R: this column was documented in this script's
# own Output block but never actually attached to taxamatch_blast_match_obj
# (only to a local copy inside the honesty check above) -- the downstream
# script's re-join failed with "undefined columns selected". Fixed by
# attaching it here, matching the pattern score_image_workflow.R already uses.
taxamatch_blast_match_obj$true_species <-
  TRUE_SPECIES[taxamatch_blast_match_obj$observation_id]

# ---- Explicit checkpoint (not automatic) ------------------------------------
# Save now so a future session (or TaxaLikely's script) can skip Steps 1-3 by
# pasting the readRDS() line below -- no file.exists()-gated auto-reload; you
# decide when to reuse this.
taxamatch_blast_match_obj_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_taxamatch_blast_match_obj.rds"))
saveRDS(taxamatch_blast_match_obj, taxamatch_blast_match_obj_path)
message(sprintf("\n  Saved: %s", taxamatch_blast_match_obj_path))
message(sprintf("  To reuse without re-running BLAST, paste:\n    taxamatch_blast_match_obj <- readRDS(\"%s\")",
                taxamatch_blast_match_obj_path))

message("\nWorkflow complete. Continue with TaxaLikely's sequence Layer-1 ",
        "script (build_sequence_matrix() -> train_likelihood_model() -> ",
        "evaluate_likelihoods()) once it exists -- see ecosystem_docs/",
        "REENTRY_PROMPT_session124_image_acoustic_workflows.md, Stage 2.")

# ==============================================================================
# Output
# ==============================================================================
# taxamatch_blast_match_obj -- one row per query (observation_id) x BLAST hit
#   (up to max_hits rows per query, score-window filtered), REAL live remote
#   NCBI BLAST output for 5 real PtConception 12S MiFish sequences:
#
#   observation_id     -- character; NCBI accession (no version suffix), one
#                         per input sequence
#   score_original      -- numeric; percent identity, 0-100 scale
#   taxon_name          -- character; best (finest-rank) taxon from
#                         TaxaTools::create_taxon_names()
#   taxon_name_rank     -- character; rank of taxon_name (typically "species")
#   family, genus, species -- character; from NCBI taxonomy resolution
#   coverage             -- numeric; BLAST query_coverage (0-100 scale) --
#                         pass to TaxaLikely::evaluate_likelihoods(min_coverage=)
#   accession, evalue, bitscore, alignment_length, subject_length --
#                         see TaxaMatch::blast_sequences()'s own documentation
#   true_species         -- character; TUTORIAL-ONLY ground-truth label for the
#                         honesty check above; NOT part of the canonical match
#                         object contract, harmless extra column for
#                         downstream (build_sequence_matrix() ignores
#                         unrecognized columns)
#
# Consumer: TaxaLikely::inst/workflows/sequence_likelihood_workflow.R -- this
#   is the ONE data type needing the actual bivariate-normal self-vs-non-self
#   model (unlike image/acoustic, which calibrate pre-trained classifiers via
#   unreferenced_candidates() + assign_scores() with no training step).
# ==============================================================================
