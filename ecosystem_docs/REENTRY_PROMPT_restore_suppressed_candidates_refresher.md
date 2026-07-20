# Reentry prompt: revisit `restore_suppressed_candidates()`

**From:** the "Problem 1" thread in `REENTRY_PROMPT_degraded_species_likelihood_thresholds.md`
(a referenced species can be excluded from the candidate set entirely if it
scores too far below the best match). That thread's rate-estimation attempt
was abandoned (see `[[project_edge_case_error_taxa_design]]` in the memory
system for why -- an external, undocumented scoring tool's measurement noise
turned out to be the same order of magnitude as the effect being measured).
Rather than keep pushing on a population-level rate, the user wants to
revisit `restore_suppressed_candidates()` itself directly.

**Explicit instruction for whoever picks this up:** start with a plain
refresher on what this function currently does -- signature, the three
suppression rules it detects (`detect_suppressed_candidates()`), the
`check_regional_overlap` gate and its three tiers (Tier 1 free `seq_matrix`
lookup, Tier 2a/2b real alignment), and exactly what triggers restoration
today (genus membership in `reference_df`, not a relaxed score window) --
**before** proposing any redesign or improvement. The user has said they
need this refresher before they can suggest improvements themselves; don't
skip straight to design proposals the way the previous (now-deleted) version
of this reentry prompt did.

One design idea to keep in view once the refresher is done, from the user's
own framing: allow `restore_suppressed_candidates()` to look for matches
that fall below the retention gap specifically **when there are no other
plausible candidates** -- not a genus-membership-based restoration (today's
behavior), and not gated on the elaborate likelihood+prior joint signature
the previous version of this doc proposed. What "no other plausible
candidates" should mean precisely (purely structural -- no candidate
survived at all -- vs. occurrence-prior-informed -- no *locally plausible*
candidate survived) was not resolved before this reentry prompt was written;
confirm with the user before implementing either version.

## Where to start

1. `TaxaLikely/R/score_collapse.R` -- `detect_suppressed_candidates()` and
   `restore_suppressed_candidates()` themselves.
2. `TaxaLikely/R/regional_overlap.R` -- `.check_regional_overlap()`'s three
   tiers.
3. `TaxaLikely/CLAUDE.md`'s Session 159 notes (several, search for
   "regional_overlap" and "align_cache") -- the fullest existing narrative
   of how and why this function reached its current form.
4. `diagnostics/referenced_candidate_exclusion_rate*.R` (this session,
   abandoned) -- not a design template to follow, but shows what real
   PtConception 12S data looks like for the genera this function most often
   needs to act on (*Sebastes*, *Citharichthys*, *Clinocottus*, *Gibbonsia*,
   *Embiotoca* recurred repeatedly).
