# Edge: taxa + reference_df -> ref_gaps
# Source: TaxaLikely/inst/workflows/5_audit_coverage_workflow.R

ref_gaps <- TaxaLikely::audit_barcode_coverage(
  match_df     = {{match_var}},
  barcode_term = {{barcode_term}},
  target_rank  = "genus",
  # Project-local cache: this issues real NCBI census queries, and an
  # uncached re-run re-pays for every one of them.
  cache_dir    = {{reference_cache_dir}}
)
message("Coverage audit: ", sum(ref_gaps$census$unreferenced > 0),
        " genera with unreferenced species")
ref_gaps
