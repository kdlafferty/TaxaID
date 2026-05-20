#now with context.
# ==============================================================================
# Step 1: Build context (replaces the hardcoded extraction in generate_report)
# ==============================================================================

# Extract the same statistics generate_report() computes internally
n_samples    <- length(unique(consensus$observation_id))
n_resolved   <- sum(consensus$is_resolved, na.rm = TRUE)

top_per_esv  <- result |>
  dplyr::group_by(observation_id) |>
  dplyr::slice_max(posterior_mean, n = 1, with_ties = FALSE) |>
  dplyr::ungroup()

# Merge report_params from pipeline objects
rp <- attr(result, "report_params")
cp <- attr(consensus, "report_params")

ctx <- build_report_context(
  study_description = "eDNA survey of a southern California estuary",
  data_type  = "eDNA",
  marker     = "12S MiFish",
  workflow   = "LLM-assisted Bayesian taxonomic assignment",
  packages   = c("TaxaMatch", "TaxaAssign", "TaxaTools"),
  parameters = c(rp, cp),   # score_sharpness, cumulative_threshold, etc.
  statistics = list(
    n_samples              = n_samples,
    n_resolved             = n_resolved,
    resolution_rate        = round(100 * n_resolved / n_samples, 1),
    n_unique_taxa          = length(unique(consensus$consensus_taxon)),
    median_posterior        = round(median(top_per_esv$posterior_mean, na.rm = TRUE), 3),
    rank_breakdown         = paste(names(table(consensus$consensus_rank)),
                                   table(consensus$consensus_rank),
                                   sep = "=", collapse = ", "),
    n_unreferenced_wins    = sum(top_per_esv$hypothesis_type %in%
                                   c("unreferenced_species", "unreferenced_genus"),
                                 na.rm = TRUE)
  ),
  facts = list(
    location = "southern California estuary",
    consensus_type = "posterior (Bayesian)"
  ),
  citations = c(
    "Callahan et al. (2016) DADA2",
    "Miya et al. (2015) MiFish primers"
  )
)

# ==============================================================================
# Step 2: Draft methods from the workflow script
# ==============================================================================

methods <- draft_methods_text(
  code    = system.file("TaxaAssign_llm_workflow.R", package = "TaxaAssign"),
  context = ctx,
  audience = "journal"
)

# ==============================================================================
# Step 3: Draft results from the output objects
# ==============================================================================

results <- draft_results_text(
  result    = result,
  consensus = consensus,
  context   = ctx,
  audience  = "journal"
)

# ==============================================================================
# Compare with generate_report()
# ==============================================================================

report_old <- generate_report(
  result    = result,
  consensus = consensus,
  unreferenced_result = unreferenced_species,
  data_type = "eDNA", marker = "12S MiFish",
  study_description = "eDNA survey of a southern California estuary",
  llm_fn = TaxaTools::call_anthropic_api
)



