# Edge: taxa -> reference_df
# Source: TaxaLikely fetch_ncbi_reference_sequences()
# NOTE: Searches by FAMILY to build a comprehensive reference database.
# The model needs within-species variation and between-species distances.
# Species from the match data are prioritized so their sequences are
# always fully represented even when total hits exceed the download budget.

# Normalize primer variant names to NCBI-searchable marker names
.barcode_term <- {{barcode_term}}
.bt_lower <- tolower(trimws(.barcode_term))
if (grepl("^mifish", .bt_lower))   .barcode_term <- "MiFish"
if (grepl("^teleo",  .bt_lower))   .barcode_term <- "12S"
if (grepl("^leray|^mlcoi", .bt_lower)) .barcode_term <- "COI"

# Use families (not individual species) for a proper reference
ref_families <- unique({{input_var}}$family)
ref_families <- ref_families[!is.na(ref_families) & nchar(ref_families) > 0L]
message("Searching NCBI for families: ", paste(ref_families, collapse = ", "))

# Extract species from input as priority taxa for the likelihood model.
# These species get full NCBI representation even when subsampling.
.priority_species <- if ("species" %in% names({{input_var}})) {
  sp <- unique({{input_var}}$species)
  sp[!is.na(sp) & nchar(sp) > 0L]
} else {
  character(0L)
}
message("Priority species from match data: ", length(.priority_species))

reference_df <- TaxaLikely::fetch_ncbi_reference_sequences(
  taxa           = ref_families,
  barcode_term   = .barcode_term,
  priority_taxa  = if (length(.priority_species) > 0L) .priority_species else NULL,
  # STOP rather than silently ship a degraded reference database. On
  # 2026-09-14 seven genera had their NCBI count query fail transiently on a
  # real PtConception run; each was dropped, taking its entire reference
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
  cache_dir      = {{reference_cache_dir}}
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
