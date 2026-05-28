# Edge: taxa -> reference_df  (site reference wrapper, recommended for eDNA)
# Source: TaxaLikely build_site_reference()
# Wraps: fetch_reference_sequences() + audit_barcode_coverage() +
#        write_reference_fasta()
# output_dir writes reference.fasta + reference_taxonomy.tsv to disk.
# DNA / eDNA only. For acoustic, see taxa_to_acoustic_matrix.R.
# NOTE: {{input_var}} should come from a TaxaExpect taxa list (unique genera or
# species from build_priors() or verify_taxon_names() output) for best results.

site_ref <- TaxaLikely::build_site_reference(
  taxa            = unique({{input_var}}),
  barcode_term    = {{barcode_term}},
  rank_system     = {{rank_system}},
  output_dir      = {{output_dir}},
  max_sequences   = {{max_sequences}},
  max_per_species = {{max_per_species}},
  max_date        = {{max_date}},
  ncbi_api_key    = {{ncbi_api_key}},
  flag_errors     = FALSE,
  audit_coverage  = TRUE
)

reference_df     <- site_ref$reference_df
ref_errors       <- site_ref$errors
ref_census       <- site_ref$census
ref_unreferenced <- site_ref$unreferenced

if (nrow(reference_df) == 0L) {
  stop(
    "build_site_reference() returned 0 sequences.\n",
    "Check: NCBI availability, barcode_term spelling, max_sequences limit.\n",
    "Searched taxa: ", paste(unique({{input_var}}), collapse = ", "),
    call. = FALSE
  )
}

if (length(ref_unreferenced) > 0L) {
  message(length(ref_unreferenced), " unreferenced species (no barcode in NCBI):\n",
          paste(" -", ref_unreferenced, collapse = "\n"))
  message("These will appear as H2/H3 hypotheses in TaxaAssign.")
}

message("Site reference: ", nrow(reference_df), " sequences, ",
        length(unique(reference_df$species)), " species")
if (!is.null({{output_dir}}))
  message("Saved to: ", {{output_dir}}, "/reference.fasta + reference_taxonomy.tsv")
reference_df
