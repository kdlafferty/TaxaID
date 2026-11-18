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
  candidate identifiers for one name: the lookup's own answer (the key
  backbone's match) when it is one of the candidates, then the lineage of each
  listed authority (e.g. NCBI, then WoRMS). This covers a conflict between the
  pool's key and the lookup's as well as a name the pool holds under several
  keys: with `gbif_first`, the key backbone decides (the maintainer's rule), and
  every pool key it overrules is listed by `check_taxon_registry()`. Off by
  default; candidates with identical lineages are never decided.
  `gbif_first` names the key authority's own match, whatever `key_backbone_id` is.
* `build_taxon_registry()` treats the rank a table asked a name at as a hint:
  one name in one lineage is one taxon. Above genus the key backbone's own
  classification decides between candidates; at genus and species the name's
  lineage breaks a tie; an undecided name is `lineage_unresolved`
  (error-class), never a guess. A placeholder "<Taxon> gen." is a run-local
  genus under <Taxon>, and a reference label "<binomial>_cluster<n>" answered as
  that binomial is a declared merge (`cluster_label`).
* Every registry node of the key authority has a rank. A name whose accepted
  usage is below species (a synonym of a subspecies, variety or form) takes
  the species its own classification ends at, and the lookup's own id is
  listed. A pool key no lookup described is a species under the one genus its
  genus word names, or under none (a warning) when that word names two or more
  genera or none; a `genus_key` column in `pool_keys` checks that placement
  (`pool_key_parent_mismatch`, error-class). `check_taxon_registry()` lists one
  accepted name at one rank under two or more ids in one kingdom
  (`accepted_name_multiple_ids`, a warning). With
  `tiebreak$merge_species_duplicates = TRUE`, such a name at species rank whose
  ids the run's names both use is merged, as a declared merge, onto the id the
  pool-key tie-break chose or, where it chose none, the id the key authority's
  own lookup gives the bare name, when that is one of the ids; otherwise the
  ids stay apart and the reason is listed. Genus and higher ranks are never
  merged.
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
* `pool_keys` are GBIF Backbone keys: `build_taxon_registry()` accepts them
  only with `key_backbone_id = 11` and stops otherwise.
* `attach_taxon_ids()` refuses a table whose `taxon_id` column it did not
  stamp; a table that carries another source's ids there (OBIS AphiaIDs, say)
  must rename that column before stamping.
* The registry tree holds the key authority's seven major ranks (kingdom to
  species) under any `key_backbone_id`. A name answered at an intermediate rank
  (subclass, infraorder, ...) is a run-local node, and intermediate ranks come
  only from the caller's own lineage columns, which pass through unchanged.
