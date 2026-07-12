# sebastes_chromis_confirmation.R
#
# Confirm the manuscript claim (BayesianID_perspective, "Modeling likelihoods
# from scores" section): a 99% 12S match within Sebastes (rockfish) may not
# discriminate to species, whereas the same threshold discriminates well in
# a less-radiated genus -- because taxonomic groups differ in within- vs.
# between-species similarity.
#
# Builds two independent, genus-focused reference sequence matrices from real
# NCBI data (not the PtConceptionWorkflow_12S.R detection-only reference set,
# which only contains taxa that happened to be BLAST hits in this survey).
#
# Chromis (damselfish -- includes Chromis punctipinnis, the blacksmith, a
# common Channel Islands/Pt Conception kelp-forest fish) is the comparison
# genus -- fifth choice after four rejected attempts:
#   1. Lythrypnus (real local SoCal goby congeners) -- only 5/13 species had
#      >=2 sequences, too thin.
#   2. Rhinogobius (best depth of an initial 4-genus goby recon) --
#      freshwater, confounding the marine-vs-freshwater habitat axis.
#   3. Trimma (best of a marine-only goby recon) -- fixed habitat, but real
#      cryptic diversity in the genus made p_self unreliably low (0.23).
#   4. Paralabrax (best of a real-California-fish recon, on species-count/
#      depth grounds) -- ecologically ideal (kelp bass/sand bass complex),
#      but ALL 22 fetched "12S" GenBank sequences turned out to be ~500bp
#      fragments with ZERO detectable homology to either MiFish primer (even
#      at 6 mismatches, both strands) -- i.e. real GenBank "12S" records
#      include sequences from unrelated, non-MiFish-window parts of the 12S
#      gene, and Paralabrax's available records happen to be entirely of
#      that kind. This also revealed that build_sequence_matrix()'s default
#      length filter (100-2000bp) is far too wide to enforce "same amplicon
#      window" -- it let all 22 non-MiFish-window Paralabrax sequences
#      straight through, so the earlier Sebastes-vs-Paralabrax comparison
#      was silently comparing two different genomic regions, not a fair
#      test. See TaxaLikely/CLAUDE.md's Known Footguns entry (2026-07-07,
#      updated) for the full record.
# A length-based recon across several real CA marine genera (Paralabrax,
# Citharichthys, Sebastolobus, Girella, Oxyjulis, Semicossyphus, Chromis,
# Hypsypops, Scorpaena), this time explicitly counting sequences in the
# registered MiFish amplicon range (130-210bp, TaxaTools::resolve_barcode_
# lengths("MiFishU")) rather than just raw sequence/species counts, found
# Chromis clearly best: 46 of 49 sequences are genuinely in-window, 25
# species, 12 with >=2 in-window sequences (top depth: C. notata=8,
# yamakawai=4, chrysura=3) -- comparable depth to Rhinogobius, this time
# with confirmed comparable data and a real marine CA fish.
#
# THIS SCRIPT NOW EXPLICITLY FILTERS BOTH GENERA to the registered MiFish
# amplicon length range before build_sequence_matrix(), rather than trusting
# trim_to_amplicon() (empirically a 0% rescue rate on real data for both
# Sebastes and Paralabrax -- see the Known Footguns entry) or
# build_sequence_matrix()'s own default width filter (too wide to enforce
# amplicon-window comparability). This is the methodologically correct fix:
# guarantee both genera's %-match values are computed over the same genomic
# window, rather than relying on incidental DECIPHER distance-filtering to
#
# UPDATE (2026-07-11, ecosystem soundness-review item 13): this manual
# pre-filter pattern is now built into build_sequence_matrix() itself via a
# new barcode_term parameter (build_sequence_matrix(reference_df, ...,
# barcode_term = "MiFishU") resolves and applies the same length window
# automatically). Left as manual code here since this script's whole point
# is demonstrating and explaining the mechanism that new parameter now
# encapsulates -- see TaxaLikely/CLAUDE.md's Session 151 note.
# paper over a window mismatch.
#
# Output: two seq_matrix .rds files. Run compare_sebastes_chromis_
# discrimination.R afterward for the p_self / p_cross_congeneric / LR summary.
# ==============================================================================

library(TaxaLikely)
library(TaxaTools)
library(dplyr)

# ==============================================================================
# PARAMETERS
# ==============================================================================
BARCODE_TERM    <- "12S"       # for fetch_ncbi_reference_sequences()
RANK_SYSTEM     <- c("family", "genus", "species")
MAX_PER_SPECIES <- 20L         # cap for speed; raise if a genus looks thin
                                # NOTE: fetch_ncbi_reference_sequences()'s cache key does
                                # NOT include max_per_species -- delete CACHE_DIR (or use a
                                # fresh one) after changing this value, or you'll silently
                                # get the old, thinner cached fetch back.

# Registered MiFish-U/E amplicon length bounds -- enforce this explicitly
# rather than trusting build_sequence_matrix()'s much wider 100-2000bp
# default, which does not actually guarantee same-amplicon-window comparability.
MIFISH_LEN <- TaxaTools::resolve_barcode_lengths("MiFishU")

OUT_DIR   <- file.path(
  "/Users/lafferty/My Drive/Rscripts/projects/TaxaID/diagnostics"
)
CACHE_DIR <- file.path(OUT_DIR, "cache_sebastes_chromis")
if (!dir.exists(CACHE_DIR)) dir.create(CACHE_DIR)

GENERA <- list(
  sebastes = "Sebastes",
  chromis  = "Chromis"
)

# ==============================================================================
# FETCH + LENGTH-FILTER + BUILD, ONE GENUS AT A TIME
# ==============================================================================
build_genus_matrix <- function(genus_name, tag) {

  cat(sprintf("\n=== %s (%s) ===\n", tag, genus_name))

  reference_df <- fetch_ncbi_reference_sequences(
    taxa            = genus_name,
    barcode_term    = BARCODE_TERM,
    rank_system     = RANK_SYSTEM,
    max_per_species = MAX_PER_SPECIES,
    cache_dir       = CACHE_DIR
  )
  cat(sprintf("  Fetched %d sequences, %d species.\n",
              nrow(reference_df), length(unique(reference_df$species))))

  lens <- nchar(reference_df$sequence)
  in_window <- lens >= MIFISH_LEN["min_bp"] & lens <= MIFISH_LEN["max_bp"]
  cat(sprintf("  %d of %d sequences are in the registered MiFish window (%d-%dbp); keeping only these.\n",
              sum(in_window), length(in_window), MIFISH_LEN["min_bp"], MIFISH_LEN["max_bp"]))
  reference_df <- reference_df[in_window, ]
  cat(sprintf("  %d sequences, %d species after length filter.\n",
              nrow(reference_df), length(unique(reference_df$species))))

  seq_matrix <- build_sequence_matrix(
    reference_df,
    rank_system        = RANK_SYSTEM,
    filter_unnamed     = TRUE,
    max_seqs_per_taxon = NULL   # MAX_PER_SPECIES already capped at fetch time
  )
  cat(sprintf("  %d pairwise comparisons built.\n", nrow(seq_matrix)))

  out_path <- file.path(OUT_DIR, sprintf("%s_seq_matrix.rds", tag))
  saveRDS(seq_matrix, out_path)
  cat(sprintf("  Saved: %s\n", out_path))

  invisible(seq_matrix)
}

sebastes_matrix <- build_genus_matrix(GENERA$sebastes, "sebastes")
chromis_matrix  <- build_genus_matrix(GENERA$chromis,  "chromis")

# ==============================================================================
# NEXT STEP: run compare_sebastes_chromis_discrimination.R
# ==============================================================================
