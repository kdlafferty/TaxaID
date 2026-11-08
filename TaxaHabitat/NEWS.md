# TaxaHabitat 1.0.0

* Initial release.
* `build_habitat_lookup()` names the model behind cached verdicts in its
  verbose cache line. The count of hits alone does not tell a reader whether
  the verdicts they are about to use came from the model they expect.
* `build_habitat_lookup()` records which model answered in every cache entry it
  writes, reports it in the `cache_summary` attribute as `model` and `models`,
  and warns when the verdicts it returns come from more than one -- the state
  that made a habitat weight untraceable and let a re-run mix models silently.
  Entries whose record names no model are counted as `n_model_unknown`,
  because no record is not the same as another model. The record names the
  model the provider resolved, which `TaxaTools::prompt_api()` reports from the
  call, so a capability tier pointed at a different model is visible in the
  record instead of hidden behind the tier's name; an `llm_fn` that reports no
  model falls back to a description of the function, and `cache_tag` = the
  resolved model identifier is the way to pin it in that case.
* The habitat cache key names which VARIANT of the prompt a scheme is asked
  under, rather than which release wrote the entry. The prompt's compound-label
  wording changed, so a scheme that declares compound `parts` could be served a
  verdict given under different wording: its cache is a miss once and is
  re-asked. A scheme that declares no parts is asked the same words as before,
  so its cache still hits, and an entry written by an earlier release is a hit
  that records no model -- which is what `n_model_unknown` counts. A scheme
  that declares parts cannot reuse an entry written without them.
  `test-habitat_prompt_fingerprint.R` fails when the prompt's source changes
  without the token moving, so the guard does not depend on remembering; a
  change to the wording a no-compound scheme is asked under must move both
  values.

## New features

* A habitat scheme may declare a compound label (for example a coastal-stream
  habitat) through an optional `parts` column of pipe-delimited habitat names.
  `build_habitat_prompt()` asks the model for the parts and derives the
  compound's weight from them, and the validators and the data-frame parse path
  keep and use the column. Parts are declared, never read from the label's
  spelling, so splitting at a hyphen cannot credit a species with a habitat it
  does not use.
* `build_habitat_lookup(compound_rule = c("sum", "max"))` sets how a compound
  is derived from its parts: `"sum"` (default, capped at 1) because the parts
  are disjoint shares of a species' habitat use, or `"max"`. The lookup caches
  the parts and derives the compound on every call, so the rule can change
  without a new model call.

## Bug fixes

* A compound none of whose part columns is present derives `NA`, not `0`: a
  zero reads as "does not use this habitat", whereas the habitat is unknown.
