# TaxaTools 1.0.0

* First public release.
* Cleans, verifies and standardizes taxonomic names, including spell-checking
  and correcting species names, and building standardized labels at any rank.
* Translates names between taxonomic backbones (GBIF, NCBI, WoRMS) and
  retrieves classification hierarchies through their APIs.
* Provides the LLM provider functions the rest of the ecosystem calls
  (Anthropic, OpenAI, Azure OpenAI, Gemini and Ollama), with chunking, a model
  registry with capability tiers, and token accounting.
* Drafts methods and results text, and assembles run reports, for the other
  packages to extend.
* A taxon registry, so that tables are joined on a taxon identifier rather
  than on a name: `build_taxon_registry()` resolves every name a run uses once,
  under one key authority (by default the GBIF Backbone), and records how each
  name got its identifier; `freeze_taxon_registry()`, `attach_taxon_ids()`,
  `join_by_taxon()`, `taxon_in()` and `parent_at()` stamp tables with those
  identifiers and join and test membership on them; `check_taxon_registry()`
  is the guard, listing every identifier reached by two or more names with the
  relationship its backend declared, and reporting an undeclared merge, a
  name with two or more pool keys, the same taxon twice in one observation, or
  a table lineage that contradicts the registry.
* `build_taxon_registry(tiebreak = )` decides between two or more GBIF
  candidate identifiers for one name: the lookup's own answer when it is one
  of the pool's keys, then the lineage of each listed authority (e.g. NCBI,
  then WoRMS). Off by default; candidates with identical lineages are never
  decided.
* A genus answered only by a fuzzy or variant match is taken by the registry
  only where the names under it agree with it at kingdom and phylum, since a
  misspelt genus can match a genus in another kingdom.
* A binomial that GBIF answers as an orthographic variant of its genus, with
  the epithet unchanged, takes GBIF's species under the same kingdom-and-phylum
  check; elsewhere it stays unresolved and is listed.
* `verify_taxon_names(return_ids = TRUE)` adds the record identifiers the
  Global Names Verifier returns (`record_id`, `current_record_id`,
  `classification_ids`, `data_source_id`, `entry_date`, `match_type`).
* `check_taxon_registry(export = TRUE)` holds output tables to the export
  rules: no taxon under two display names and no display name on two taxa,
  both error-class.
