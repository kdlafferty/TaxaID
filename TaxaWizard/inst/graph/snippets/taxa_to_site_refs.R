# Edge: taxa -> reference_df  (site reference builder, recommended for eDNA)
# Source: TaxaLikely fetch_ncbi_reference_sequences() + audit_barcode_
#         coverage() + write_reference_fasta()
# NOTE: TaxaLikely::build_site_reference(), a one-call wrapper around the same
# three functions, is retired (zero real callers anywhere in the monorepo);
# this snippet chains the component functions directly, exactly as
# build_site_reference() did internally.
# output_dir writes reference.fasta + reference_taxonomy.tsv to disk.
# DNA / eDNA only. For acoustic, see taxa_to_acoustic_matrix.R.
# NOTE: {{input_var}} should come from a TaxaExpect taxa list (unique genera or
# species from estimate_kernel_priors()'s $priors or verify_taxon_names()
# output) for best results.

reference_df <- TaxaLikely::fetch_ncbi_reference_sequences(
  taxa            = unique({{input_var}}),
  barcode_term    = {{barcode_term}},
  rank_system     = {{rank_system}},
  max_sequences   = {{max_sequences}},
  max_per_species = {{max_per_species}},
  max_date        = {{max_date}},
  # Stop rather than silently ship a degraded reference database -- see
  # taxa_to_refs.R for the 2026-09-14 incident this guards (seven genera lost
  # their entire reference representation to transient NCBI count failures,
  # on a run that finished looking healthy). "warn" accepts the degradation
  # knowingly; the affected taxa are then in attr(, "count_failures").
  on_count_failure = "error",
  # Project-local per-taxon cache. A cached taxon issues NO count query, which
  # is what removes the exposure in the first place.
  cache_dir       = {{reference_cache_dir}},
  ncbi_api_key    = {{ncbi_api_key}}
)

if (length(attr(reference_df, "count_failures"))) {
  message("  !! count_failures: ",
          paste(attr(reference_df, "count_failures"), collapse = ", "))
}

if (nrow(reference_df) == 0L) {
  stop(
    "fetch_ncbi_reference_sequences() returned 0 sequences.\n",
    "Check: NCBI availability, barcode_term spelling, max_sequences limit.\n",
    "Searched taxa: ", paste(unique({{input_var}}), collapse = ", "),
    call. = FALSE
  )
}

ref_coverage     <- TaxaLikely::audit_barcode_coverage(
  reference_df, barcode_term = {{barcode_term}},
  cache_dir = {{reference_cache_dir}}   # shares the fetch's cache; same NCBI queries
)
ref_census       <- ref_coverage$census
ref_unreferenced <- ref_coverage$unreferenced

if (!is.null({{output_dir}})) {
  if (!dir.exists({{output_dir}})) dir.create({{output_dir}}, recursive = TRUE)
  TaxaLikely::write_reference_fasta(
    reference_df,
    file          = file.path({{output_dir}}, "reference.fasta"),
    taxonomy_file = file.path({{output_dir}}, "reference_taxonomy.tsv"),
    rank_system   = {{rank_system}}
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
