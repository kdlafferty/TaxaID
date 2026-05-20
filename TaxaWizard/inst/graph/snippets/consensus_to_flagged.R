# Edge: consensus -> flagged
# Source: TaxaFlag/inst/contaminant_workflow.R
# NOTE: consensus output has consensus_taxon (not taxon_name).

flagged <- TaxaFlag::flag_contaminant(
  df              = {{input_var}},
  control_samples = {{control_samples}},
  event_col       = "observation_id",
  taxon_col       = "consensus_taxon",
  reads_col       = {{reads_col}},
  contaminant_type = {{contaminant_type}}
)
message("Flagged ", sum(flagged$contaminant_flag == "likely", na.rm = TRUE),
        " likely contaminants")
flagged
