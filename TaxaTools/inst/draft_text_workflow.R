library(TaxaTools)
# ==============================================================================
# TEST 1: draft_methods_text() on the Palmyra workflow script
# ==============================================================================

# Read the workflow code
methods_text <- draft_methods_text(
  code = file.choose(),  # select the R script to summarize
  description = "eDNA metabarcoding of coral reef fish at Palmyra Atoll using 12S primers",
  audience = "journal"
)

# Try technical style for comparison
methods_tech <- draft_methods_text(
  code = file.choose(),  # select the R script to summarize
  description = "eDNA metabarcoding of coral reef fish at Palmyra Atoll using 12S primers",
  audience = "technical"
)

# ==============================================================================
# TEST 2: draft_results_text() on the BLAST results you have in memory
# ==============================================================================

results_text <- draft_results_text(
  blast_hits = blast_hits,
  filtered_seqs = filtered_df,
  description = "eDNA metabarcoding of coral reef fish at Palmyra Atoll",
  audience = "journal"
)

# ==============================================================================
# TEST 3: draft_results_text() with code context
# ==============================================================================

results_with_code <- draft_results_text(
  blast_hits = blast_hits,
  filtered_seqs = filtered_df,
  description = "eDNA metabarcoding of coral reef fish at Palmyra Atoll",
  code = file.choose(),  # select the R script to summarize
  audience = "journal"
)
