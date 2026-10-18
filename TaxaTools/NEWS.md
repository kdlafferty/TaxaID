# TaxaTools 1.0.0

* Initial release.

## New features

* `verify_taxon_names(input_rank =)` takes one rank per input name. On the NCBI
  path a homonym whose candidates include exactly one node at that rank
  resolves to it, from the summaries already fetched, so a name that is both a
  genus and a subgenus does not stop a batch. The rank is part of the cache
  key on the NCBI path only.
* `verify_taxon_names(lineage =)` and `fill_higher_ranks(lineage =)` take one
  pipe-delimited ancestor string per name (for example the GBIF phylum). A
  name is not a key: on NCBI the lineage settles a homonym that rank alone
  cannot, and on every backbone a classification that contradicts the context
  is returned unverified instead of accepted. Only a choice between taxa is
  gated, so a unique node that the backbone words differently is not rejected.
  `verified = FALSE` therefore also marks a deterministic gate rejection, which
  the summary line names separately from API failures.
* `verify_taxon_names()` called non-interactively with `decisions = NULL`
  reports a still-ambiguous name alone as `verified = FALSE` (never cached,
  with the candidate table in a warning) and lets the rest of the batch
  proceed. Supplied `decisions` that do not cover a name still stop the call.
* `fill_higher_ranks(input_rank =)` takes each name's own rank. A single-word
  name whose rank is family or coarser is asked at that rank, so a class-rank
  name is not resolved to a genus that shares its spelling; all other names
  are asked at genus. The ranks to fill are named by `fill_ranks` (the rank
  argument; default `"family"`).
* `fill_higher_ranks(fill_ranks =, record_source =)` fills any rank the
  backbone reports (for example `class`, which GBIF leaves empty for
  ray-finned fishes) and, with `record_source = TRUE`, adds a `<rank>_source`
  column. A rank is filled only where the source above it was silent: local
  sources, then the primary backbone, then the fallback.
* `fill_higher_ranks()` refuses a fallback-backbone value for a genus the
  primary backbone could not place (an ambiguous or failed lookup) and when
  the fallback lineage contradicts the primary at phylum, with a warning
  naming the genus. A name absent from the primary backbone keeps the
  fallback.
* `fill_higher_ranks()` reports a genus that maps to more than one value and
  prefers the taxon's own row in `local_sources` over the genus-keyed value;
  unanimous genera are untouched. The first-source precedence still settles
  genuine disagreements between sources.
* `call_api()` and `call_anthropic_api()` take `temperature` (last argument,
  default `NULL`). `NULL` sends no temperature field, so the provider default
  applies. Some current models reject the parameter outright with HTTP 400, in
  which case the call stops with the provider's message; set it only for a
  model that accepts it.
* `clean_taxon_names()` drops a parenthesised subgenus, returns the genus for a
  `cf.`/`aff.` name (recorded in the `name_qualifier` attribute), and reduces a
  hybrid formula to the shared genus, or `NA` when the parents are in different
  genera. The `clean_reason` attribute names each structural change.

## Bug fixes

* A failed name, lineage or sampling-group lookup is never stored as an
  answer. `verify_taxon_names()` marks it `verified = FALSE` and asks again;
  `assign_sampling_group(harmonise = TRUE)` drops such rows before building its
  cache. A network outage therefore cannot leave a valid genus cached as a
  non-match.
* `fill_higher_ranks(character(0))` returns a zero-row table with the usual
  columns, and a logical all-`NA` `lineage` or `input_rank` means no context
  instead of a type error. Duplicate and `NA` names are read row by row.
* `create_taxon_names()` treats a whitespace-only rank cell as absent, so it
  cannot be reported as the finest rank present.
* The token-usage log labels the calling function when the call comes through
  `do.call()` or an anonymous function, instead of failing after the API reply
  has returned.
