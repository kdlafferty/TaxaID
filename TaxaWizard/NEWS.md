# TaxaWizard 1.0.0

* First public release.
* Interviews the user about a taxonomic identification task and generates a
  self-contained R script, methods text or Shiny application for it.
* Reads the installed TaxaID packages to build its own context, and validates
  its building-block snippets against that registry, so a renamed function or
  a stale argument is caught before a path is offered.
* Checks the local setup -- R, packages, keys, network, caches and external
  binaries -- and repairs a script from an error the user pastes back.
* Supports a CLI (readline) and a Shiny chat interface over a stateless LLM
  engine.
