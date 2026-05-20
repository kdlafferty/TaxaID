# TaxaFetch 0.1.0

## Polishing Phase (Sessions 57-59)

* Removed dead code: `combine_occurrence_sources()` (superseded by
  `rename_cols()` + `stack_occurrences()`).
* Deleted stale workflow files: `TaxaFetch_workflow copy.R`,
  `migrate_prompt_api.R`, `habitat_scheme_workflow.R`.
* Removed duplicate `%||%` definition (now imported from TaxaTools).
* Fixed LaTeX escape in `search_literature()` documentation.
* Added vignette: data-acquisition.Rmd.
