# Edge: consensus -> flagged
# Source: TaxaFlag/inst/contaminant_workflow.R
# NOTE: When data comes from TaxaAssign, the taxon column is "consensus_taxon"
#   and event column is "observation_id". For external data, use actual column names.

flagged <- TaxaFlag::flag_contaminant(
  df              = {{input_var}},
  control_samples = {{control_samples}},
  event_col       = {{event_col}},
  taxon_col       = {{taxon_col}},
  reads_col       = {{reads_col}},
  contaminant_type = {{contaminant_type}}
)
message("Flagged ", sum(flagged$contaminant_flag == "likely", na.rm = TRUE),
        " likely contaminants")
flagged
