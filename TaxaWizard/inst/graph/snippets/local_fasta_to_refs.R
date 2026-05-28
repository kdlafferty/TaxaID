# Edge: local_fasta -> reference_df
# Source: TaxaLikely read_crabs_output() or read_reference_fasta()
#
# Two formats supported -- set local_fasta_format to one of:
#   "crabs"  -- CRABS internal format (headerless 11-column TSV: accession...sequence)
#   "fasta"  -- FASTA file + companion taxonomy TSV (QIIME2 / SILVA / custom prefix-style)
#
# For CRABS: {{input_var}} = path to the CRABS .tsv database file
# For FASTA: {{input_var}} = path to the .fasta / .fa file;
#            {{taxonomy_file}} = path to the 2-column taxonomy TSV

.format <- {{local_fasta_format}}

reference_df <- if (.format == "crabs") {

  TaxaLikely::read_crabs_output(
    file            = {{input_var}},
    rank_system     = {{rank_system}},
    require_species = TRUE,
    dereplicate     = TRUE
  )

} else if (.format == "fasta") {

  TaxaLikely::read_reference_fasta(
    fasta_path    = {{input_var}},
    taxonomy_file = {{taxonomy_file}},
    rank_system   = {{rank_system}}
  )

} else {
  stop("local_fasta_format must be 'crabs' or 'fasta'.", call. = FALSE)
}

if (nrow(reference_df) == 0L) {
  stop(
    "Loaded 0 reference sequences from '{{input_var}}'.\n",
    "Check the file path, format setting (local_fasta_format = '", .format, "'),\n",
    "and that the taxonomy columns match rank_system.",
    call. = FALSE
  )
}
message("Loaded ", nrow(reference_df), " reference sequences (",
        length(unique(reference_df$species)), " species) from local database")
reference_df
