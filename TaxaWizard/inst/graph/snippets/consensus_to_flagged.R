# Edge: consensus -> flagged
# Source: TaxaFlag/inst/contaminant_workflow.R
# NOTE: When data comes from TaxaAssign, the taxon column is "consensus_taxon"
#   and event column is "observation_id". For external data, use actual column names.
# NOTE (2026-07-24 schema): output column NAMES are fixed regardless of
#   contaminant_type -- observation_validity (numeric 0-1, high = genuine),
#   validity_flag ("valid" / "questionable_{contaminant_type}" /
#   "invalid_{contaminant_type}"), validity_reason. contaminant_type no longer
#   changes the column names themselves, only the qualifier embedded in
#   validity_flag's value.

flagged <- TaxaFlag::flag_contaminant(
  df              = {{input_var}},
  control_samples = {{control_samples}},
  event_col       = {{event_col}},
  taxon_col       = {{taxon_col}},
  reads_col       = {{reads_col}},
  contaminant_type = {{contaminant_type}}
)
message("Flagged ", sum(flagged$validity_flag == paste0("invalid_", {{contaminant_type}}), na.rm = TRUE),
        " invalid (probable-contaminant) taxa")
flagged
