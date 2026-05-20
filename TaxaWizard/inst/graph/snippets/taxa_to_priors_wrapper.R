# Edge: taxa -> priors (wrapper, recommended)
# Source: TaxaExpect build_priors() — single call encapsulating full pipeline
# NOTE: {{input_var}} must be a data.frame with multiple species (or a
# higher taxonomic rank like family) so the algorithm can estimate sampling
# effort. A single target species is insufficient.

priors_result <- TaxaExpect::build_priors(
  taxa              = {{input_var}},
  lat               = {{lat}},
  lon               = {{lon}},
  search_radius_deg = {{search_radius_deg}},
  year_range        = {{year_range}},
  habitat_scheme    = {{habitat_scheme}},
  llm_fn            = {{llm_fn}},
  geographic_context = {{geographic_hint}},
  target_backbone_id = {{target_backbone_id}},
  verbose           = TRUE
)
priors <- priors_result$priors
priors_occurrences <- priors_result$occurrences
if (is.null(priors) || !is.data.frame(priors) || nrow(priors) == 0L) {
  stop(
    "build_priors() returned no priors. This usually means the spatial model ",
    "could not be fitted — common causes:\n",
    "  - Too few GBIF records in the search area (try a larger search_radius_deg)\n",
    "  - Too many habitat categories for the available data (try habitat_scheme = NULL for 3 categories)\n",
    "  - Too few species found (try a broader taxonomic group)\n",
    "Check the messages above for details.",
    call. = FALSE
  )
}
message("Generated priors for ", length(unique(priors$taxon_name)), " taxa")
priors
