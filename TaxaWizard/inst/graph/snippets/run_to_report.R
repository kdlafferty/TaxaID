# Edge: std_occurrences + priors + model_params + posteriors + consensus + reviewed -> report
# Source: eDNA/PtConception/TaxaID_eDNA_Workflow_Template.R, Step 10
#
# Each package reports on its own stage; assemble_report() stitches the sections
# into one markdown document. Added 2026-09-17: the whole report-assembly chain
# was called by three of the five running workflows and appeared in no graph
# edge, so a generated workflow could not express it.
#
# NOTE: report_assign() takes BOTH the posterior table and the consensus table --
#   they are different objects and passing the consensus twice silently produces
#   a report with no posterior summary.
# NOTE: generate_report()'s llm_fn is optional. Pass NULL for a template-only
#   bullet list that costs no tokens; pass a closure to have the Results
#   narrative written by an LLM.

.sec_fetch   <- TaxaFetch::report_fetch({{occurrences_var}}, study_area = {{study_area}})
.sec_habitat <- TaxaHabitat::report_habitat({{habitat_var}})
.sec_priors  <- TaxaExpect::report_priors({{priors_var}})
.sec_lik     <- TaxaLikely::report_likelihood({{model_var}})
.sec_assign  <- TaxaAssign::report_assign(
  result    = {{posteriors_var}},
  consensus = {{consensus_var}},
  data_type = {{data_type}}
)
.sec_flags   <- TaxaFlag::report_flags({{reviewed_var}})

.assembled <- TaxaTools::assemble_report(
  .sec_fetch, .sec_habitat, .sec_priors, .sec_lik, .sec_assign, .sec_flags,
  title             = {{report_title}},
  study_description = {{study_description}}
)
writeLines(.assembled, {{report_path}})
message("  Saved ", {{report_path}})

# LLM-written Results narrative (optional).
.gen_report <- TaxaAssign::generate_report(
  result            = {{posteriors_var}},
  consensus         = {{consensus_var}},
  data_type         = {{data_type}},
  marker            = {{marker}},
  study_description = {{study_description}},
  llm_fn            = {{llm_fn}}
)
writeLines(.gen_report, {{generated_report_path}})
message("  Saved ", {{generated_report_path}})
.assembled
