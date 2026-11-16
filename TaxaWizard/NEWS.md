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
  GBIF accepted names.
