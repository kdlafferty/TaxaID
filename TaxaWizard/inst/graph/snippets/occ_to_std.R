# Edge: occurrences -> std_occurrences
# Source: TaxaHabitat/inst/Habitat_workflow.R + TaxaHabitat/inst/workflows/assign_habitat_workflow.R

occurrences <- {{input_var}}

# Step 0: classify any institution-proximity flags from filter_gbif_quality()
# (institution_flag=TRUE for records near a biodiversity institution -- field
# stations/marine labs are often sited exactly where good habitat is, so
# these are tiered "high"/"low"/"ambiguous" for review, never auto-removed).
# Silently skipped if institution_flag isn't present (e.g. flag_institution
# was FALSE, or occurrences didn't come from filter_gbif_quality()).
if ("institution_flag" %in% names(occurrences)) {
  occurrences <- TaxaHabitat::flag_institution_candidates(occurrences)
  n_high <- sum(occurrences$institution_suspicion == "high", na.rm = TRUE)
  if (n_high > 0L) {
    message(n_high, " record(s) flagged high-suspicion for institution-collection origin -- review before treating as wild detections")
  }
}

# Step 1: Get unique taxa for habitat assignment
unique_taxa <- unique(occurrences$taxon_name)
unique_taxa <- unique_taxa[!is.na(unique_taxa) & nzchar(unique_taxa)]

# Step 2: Build the habitat lookup via the CACHED one-call path
# (TaxaHabitat::build_habitat_lookup()), not the uncached
# build_habitat_prompt() -> {{llm_fn}} loop -> parse_hierarchical_habitat_response()
# chain. All six production workflows use this: a taxon
# already classified under this scheme is served from cache_dir instead of
# re-asked. Uncached, a habitat verdict could flip between runs, moving a
# species' records in or out of the site's habitat stratum and its kernel
# prior by orders of magnitude -- a real GreatLakes run lost 0.05 of
# Lamar precision to exactly this. Same design as review_assignments()'s
# cache. Force fresh verdicts with TaxaHabitat::taxahabitat_clear_cache(<cache_dir>).
habitat_lookup <- TaxaHabitat::build_habitat_lookup(
  unique_taxa,
  habitat_scheme     = {{habitat_scheme}},
  llm_fn             = {{llm_fn}},
  geographic_context = {{geographic_hint}},
  cache_dir          = {{habitat_cache_dir}},
  # A scheme label that names several habitats ("Coastal-Marine-Estuary-
  # Stream") can declare its real parts in the scheme's `parts` column
  # (pipe-delimited, e.g. "Marine|Estuary|Stream"). The model then weights the
  # parts, never the compound, and the compound's weight is derived from them:
  # "sum" (default) = the parts' shares added, capped at 1, so a species using
  # ANY part of the site counts for the site; "max" keeps only the largest
  # part and lowers the compound for species spread over several parts. The
  # rule is not in the cache key, so changing it costs no model calls. It has
  # no effect when {{habitat_scheme}} declares no parts.
  compound_rule      = "sum"
)

# Step 3: Assign habitat to occurrences
std_occurrences <- TaxaHabitat::assign_habitat_biological(
  occurrence_data = occurrences,
  habitats_df = habitat_lookup,
  threshold   = 0.5
)
message("Assigned habitat to ", nrow(std_occurrences), " occurrences")
std_occurrences
