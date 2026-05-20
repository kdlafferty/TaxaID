# Edge: taxa -> reference_df
# Source: TaxaLikely fetch_reference_sequences()
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

reference_df <- TaxaLikely::fetch_reference_sequences(
  taxa           = ref_families,
  barcode_term   = .barcode_term,
  priority_taxa  = if (length(.priority_species) > 0L) .priority_species else NULL
)

if (nrow(reference_df) == 0L) {
  stop(
    "fetch_reference_sequences() returned 0 sequences. Possible causes:\n",
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
