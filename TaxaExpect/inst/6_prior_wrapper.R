library(TaxaExpect)
bp <- build_priors(
  taxa               = higher_taxa_to_search,
  lat                = 37.1,
  lon                = -122.0,
  geographic_context = "San Francisco Bay estuary",
  llm_fn             = TaxaTools::call_anthropic_api,
  checkpoint_dir     = tempdir()
)
