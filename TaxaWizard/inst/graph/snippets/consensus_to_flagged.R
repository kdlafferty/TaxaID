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
#
# READING THE RESULT (2026-09-20). Two things about validity_flag that are easy
# to get wrong and expensive when you do:
#
#   1. REMOVE ON THE `invalid_` PREFIX, NEVER ON `!= "valid"`. Most taxa are not
#      "valid" and most of those must be kept. With the evidence gate on (below),
#      the majority state is `no_control_evidence` -- an honest unknown, measured
#      at 16,695 of 16,826 ESVs on one real 12S archive -- and removing everything
#      that is not "valid" would delete almost the whole dataset. The predicate is
#      startsWith(flagged$validity_flag, "invalid_"). See
#      ?TaxaFlag::flag_contaminant, section "DO NOT FILTER ON validity_flag !=
#      \"valid\"".
#
#   2. `questionable_{type}` IS NOT A CONTAMINATION RATE. That score is shrunk in
#      READS, so a low-read taxon never seen in any control still falls out of the
#      "valid" band. On a real 12S run 10,300 of 13,597 ESVs were labelled
#      questionable while only 43 had EVER appeared in a control, and the taxa it
#      surfaced were the target community. Quoting that tier as a contamination
#      percentage quotes the read-depth distribution.
#
# The call below passes require_control_evidence = TRUE, which is the recommended
# setting for new work: without it a verdict is assigned to taxa with no control
# evidence at all. The evidence columns are printed beside the verdict on purpose
# -- a count of flagged taxa with no evidence next to it is the shape of number
# that gets misread.

flagged <- TaxaFlag::flag_contaminant(
  input_df        = {{input_var}},
  control_samples = {{control_samples}},
  event_col       = {{event_col}},
  taxon_col       = {{taxon_col}},
  reads_col       = {{reads_col}},
  contaminant_type = {{contaminant_type}},
  # Direction matters: contamination flows control -> sample, and leakage the
  # other way is a different thing that must not be filtered. site_col lets a
  # systemic contaminant (present in controls at many sites) be told apart from
  # one site's leakage; pass NULL if this study has no site structure.
  require_control_evidence = TRUE,
  site_col        = {{site_col}}
)

# Verdict WITH its evidence, never the bare count.
.n_removable <- sum(startsWith(flagged$validity_flag, "invalid_"), na.rm = TRUE)
.n_with_evid <- sum(flagged$n_controls_present > 0, na.rm = TRUE)
message(sprintf(
  "Contaminant screen: %d of %d taxa are removable (validity_flag starts with 'invalid_').",
  .n_removable, nrow(flagged)
))
message(sprintf(
  "  evidence: %d taxon-rows appeared in at least one control; controls examined per taxon: %s.",
  .n_with_evid,
  if (all(is.na(flagged$n_controls_total))) "unknown" else
    paste0(min(flagged$n_controls_total, na.rm = TRUE), "-",
           max(flagged$n_controls_total, na.rm = TRUE))
))
message("  remove with: flagged[!startsWith(flagged$validity_flag, \"invalid_\"), ] -- ",
        "every other state, including no_control_evidence, must be KEPT.")
flagged
