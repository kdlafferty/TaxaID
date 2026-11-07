# TaxaHabitat 1.0.0

* Initial release.
* `build_habitat_lookup()` records which model answered in every cache entry it
  writes, reports it in the `cache_summary` attribute as `model` and `models`,
  and warns when the verdicts it returns come from more than one -- the state
  that made a habitat weight untraceable and let a re-run mix models silently.
  Entries written before the model was recorded are counted as
  `n_model_unknown`, because no record is not the same as another model. The
  record identifies the function behind `llm_fn`, not the model a capability
  tier resolves to at call time; pass `cache_tag` = the resolved model
  identifier when the record must name the model itself.
* The habitat cache key's version token moves once. The prompt's compound-label
  wording changed under the previous token, so a scheme that declares parts
  could be served a verdict given under different wording. Every cache is a
  miss once and is re-asked. `test-habitat_prompt_fingerprint.R` now fails when
  the prompt's source changes without the token moving, so the guard no longer
  depends on remembering.

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
