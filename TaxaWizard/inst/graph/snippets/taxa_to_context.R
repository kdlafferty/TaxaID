# Edge: taxa -> context_df
# Source: TaxaAssign/inst/TaxaAssign_llm_workflow.R

unique_taxa <- unique({{input_var}}$taxon_name[!is.na({{input_var}}$taxon_name)])

context_df <- TaxaAssign::build_context(
  taxon_names    = unique_taxa,
  geographic_hint = {{geographic_hint}},
  date           = {{date}},
  habitat_scheme = {{habitat_scheme}},
  llm_fn         = {{llm_fn}}
)
message("Context: ecoregion = ", context_df$ecoregion, ", habitat = ", context_df$main_habitat)
context_df
