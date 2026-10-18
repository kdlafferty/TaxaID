# TaxaHabitat 1.0.0

* Initial release.

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
