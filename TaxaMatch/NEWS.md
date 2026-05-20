# TaxaMatch (development version)

## Polishing Phase (Sessions 57-59)

* `filter_redundant_hypotheses()`: `rank_order` param renamed to
  `rank_system` for ecosystem consistency.
* Removed duplicate `%||%` definition (now imported from TaxaTools).
* Replaced inline rank definitions with `TaxaTools::standard_ranks`.
* Added vignette: match-standardization.Rmd.
