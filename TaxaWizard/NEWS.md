# TaxaWizard 1.0.0

* First public release.
* Interviews the user about a taxonomic identification task and generates a
  self-contained R script, methods text or Shiny application for it.
* Reads the installed TaxaID packages to build its own context, and validates
  its building-block snippets against that registry, so a renamed function or
  a stale argument is flagged and that step falls back to the documentation
  rather than to a stale call.
* Checks the local setup -- R, packages, keys, network, caches and external
  binaries -- and repairs a script from an error the user pastes back.
* Supports a CLI (readline) and a Shiny chat interface over a stateless LLM
  engine.
* The workflow snippets build one frozen taxon registry per run
  (`USE_TAXON_REGISTRY`, default `TRUE`) through the GBIF Backbone once the
  priors are built, registering the finished prior table's names, stamp the
  likelihoods and priors, and pass it to `join_priors()` and
  `posterior_consensus()`, so taxa are matched by identifier and outputs carry
  GBIF accepted names. This applies whatever `backbone_id` the match data
  use: with `USE_TAXON_REGISTRY = TRUE` the template makes GBIF Backbone
  lookups and reports GBIF accepted names for NCBI-based (`backbone_id = 4`)
  data too. `FALSE` keeps the names as given and matches tables by name.
* The single-site posterior step names the site by the kernel fit's own site
  id (`kernel_priors_fit$params$site_id`) or, without a kernel fit, by the one
  site id in the prior table's `grid_id`, and stops when that table holds
  several (use the multi-site step for several sites).
* The consensus step stops, before computing any consensus, when the session
  holds no `lik_unresolved` (the likelihood step's `$unresolved`). A script
  with its own likelihood step sets
  `lik_unresolved <- <its evaluate_likelihoods() result>$unresolved`.
* Each template step's output is the object its snippet produces, so the
  review step reads the final consensus: the one after the empirical-Bayes
  update, with `add_slash_taxon()`'s columns and the no-call rows.
* Every observation gets a consensus row. One whose matches all name a
  reference only above the rank system (only "Eukaryota", say), which
  `TaxaLikely::evaluate_likelihoods()` returns in `$unresolved`, gets a no-call
  row with `consensus_reason = "no_usable_likelihood"` and
  `coarsest_reference_lineage`, the lineage its matched references share.
* The likelihood step evaluates likelihoods, and keeps top hypotheses, on the
  ranks the model was fitted on (`model_params$Rank_System`), not on every
  rank column the match table carries. A reference identified only above
  those ranks (only "Eukaryota", say) then returns its observation in
  `$unresolved`, which gets the no-call row. A model that records no rank
  system falls back to the match table's columns.
* The workflow template clears, before its first step, every object a step
  looks up with `exists()` (the run's taxon registry, the kernel fit, the
  likelihood step's unresolved set), so a second run in one R session uses
  only what that run built. The prior step passes no registry: the registry
  is built after it.
