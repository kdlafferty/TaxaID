# TaxaWizard 1.0.0

* First public release.
* Interviews the user about a taxonomic identification task and generates a
  self-contained R script, methods text or Shiny application for it.
* Reads the installed TaxaID packages to build its own context, so the
  workflows it writes call the functions that exist.
* Checks and repairs a generated script against that context before handing
  it over.
* Supports a CLI (readline) and a Shiny chat interface over a stateless LLM
  engine.
