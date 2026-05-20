# Comparison: TaxaExpect_workflow.R parameters vs TaxaWizard-generated parameters
# Purpose: diagnose why the wizard-generated script returns zero GBIF records

library(TaxaExpect)
library(TaxaTools)

# --- Test A: Known-working parameters from TaxaExpect_workflow.R ---
message("=== Test A: TaxaExpect_workflow.R parameters ===")
bp_a <- TaxaExpect::build_priors(
  taxa               = data.frame(family = "Gobiidae"),
  lat                = 34.1,
  lon                = -119.1,
  search_radius_deg  = 2,
  habitat_scheme     = NULL,
  llm_fn             = TaxaTools::call_anthropic_api,
  geographic_context = "Southern California estuary",
  moran_k            = 5L,
  sd_threshold       = 0.20,
  rank_system        = c("kingdom", "phylum", "class", "order",
                         "family", "genus", "species"),
  target_backbone_id = 4L,
  checkpoint_dir     = file.path(tempdir(), "test_a"),
  verbose            = TRUE
)
message("Test A: ", nrow(bp_a$priors), " prior rows, ",
        length(unique(bp_a$priors$taxon_name)), " taxa")

# --- Test B: TaxaWizard-generated parameters (from taxaid_workflow_20260507.R) ---
message("\n=== Test B: TaxaWizard-generated parameters ===")
bp_b <- TaxaExpect::build_priors(
  taxa               = data.frame(family = "Gobiidae"),
  lat                = 37.5,
  lon                = -122.0,
  search_radius_deg  = 5,
  year_range         = c(1990, 2024),
  habitat_scheme     = "IUCN_L2",
  llm_fn             = TaxaTools::call_anthropic_api,
  geographic_context = "Coastal California from the Oregon border to the Mexican border, trimmed to coastal and nearshore areas",
  target_backbone_id = 4L,
  checkpoint_dir     = file.path(tempdir(), "test_b"),
  verbose            = TRUE
)
message("Test B: ", nrow(bp_b$priors), " prior rows, ",
        length(unique(bp_b$priors$taxon_name)), " taxa")

# --- Comparison ---
message("\n=== Summary ===")
message("Test A (workflow example): ", nrow(bp_a$priors), " rows")
message("Test B (wizard generated): ", nrow(bp_b$priors), " rows")
