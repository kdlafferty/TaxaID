# Glossary — overloaded terms across package boundaries

**Written 2026-09-05**, closing finding C of
`critical_fix_review_and_changelog_2026-09-05.md` (itself implementing
`fable_ecosystem_review_2026-09-05.md`'s focus area 2, shared-concept drift). This is a
flag-don't-rename doc: none of the terms below are being renamed. Each already means
something well-defined and internally consistent at its own definition site — the risk
is a reader (or a future consumer) assuming one package-qualified sense applies
everywhere the word appears. Link here from any manuscript-facing doc that uses these
words loosely.

## "confidence"

Five distinct quantities share this word, and none of them numerically touch each
other:

| Name | Package | What it actually is |
|---|---|---|
| `label_confidence` | TaxaMatch (`score_reference_labels()`) | A bounded vote-plus-identity-margin score for whether a reference accession's OWN taxonomic label is correct. **Cannot reach 1** (Jeffreys floors the disagreement fraction at `0.5/(n+1)`) — any future consumer reading it as a ratio where 1 means "no adjustment" must normalize by the per-row achievable ceiling first, or it will silently misfire (this is exactly what went wrong the one time it was wired as a likelihood covariate — see `[[project_reference_quality_verdicts_threads123]]`). `NA` when unearned (zero independent partners).
| `confidence_score` | TaxaAssign (`compute_posterior()`) | Fraction of Monte Carlo simulations in which a given hypothesis had the highest posterior. A frequency, not a probability statement about correctness.
| `consensus_confidence_score` | TaxaAssign (`posterior_consensus()`) | The same MC-simulation-fraction idea, read at consensus (LCA) scope rather than per-hypothesis.
| Support mass in `confirmation_discount` | TaxaAssign (`update_prior_from_consensus()`) | Presence pseudo-observations accumulated from cross-observation support — a count-like quantity feeding a Beta update, not a 0-1 confidence score at all.
| `p_conc` | TaxaExpect (evidence generators, `apply_undetected_evidence()`) | "Presence-claim confidence" in pseudo-observation units — how much weight a presence claim carries against FUTURE evidence (the confirmation update), not the static prior's own strength. Documented as independent of the marginal variance of a two-point presence mixture (see `apply_undetected_evidence()`'s own roxygen).

## "evidence"

Three different substances cross package boundaries under this one word:

- **Query evidence** (TaxaLikely, `evaluate_likelihoods(evidence_col=)`): a per-observation quality covariate (e.g. DNA read depth) modulating H1 sigma.
- **Occurrence/presence evidence** (TaxaExpect, the `evidence` argument to `apply_undetected_evidence()`; `evidence_weight`, `evidence_sources`, `undetected_type = "evidence_blend"`): external data supporting local presence plausibility for an otherwise-undetected species.
- **BLAST corroboration evidence** (TaxaMatch, `congruent_evidence_exists_anywhere`, `insufficient_independent_evidence`): whether independent BLAST hits corroborate a reference accession's own label.

Code always disambiguates by column name; prose ("the evidence supports X") frequently
doesn't. No column rename proposed — just don't assume "evidence" means the same thing
across a sentence that crosses package boundaries.

## "corroboration" — the one genuine drift case

Three trust levels share this word, and the distinction between them is exactly what
the `KJ135626`/`MZ605481` false-rescue finding turned on:

1. **`locally_corroborated`** (TaxaMatch, `corroborate_references_locally()` /
   `evaluate_reference_accessions(skip_locally_corroborated=)`) — the workflow's OWN
   match candidates corroborate an accession's label. Treated as permanently valid
   (infinite TTL, exempt from `refine_reference_verdicts()`'s trust-weighted
   refinement) because the MATCH itself is a permanent fact — but see finding B5:
   the corroborating deposit's own label is exactly as falsifiable as any other
   accession's, which the infinite-TTL treatment doesn't currently account for.
2. **`n_corroborators`/`corroborators`** (TaxaMatch, `verify_removal_candidates()`) —
   arbitrary, UNSCREENED BLAST hits that happen to agree at species rank. Now known to
   be false-rescue-capable (`KJ135626` was spared by `MZ605481`, itself a confirmed
   candidate mislabel) — this is the weakest sense of the three, and the one where
   "corroborated" is most likely to mislead a reader into assuming the corroborator's
   own label was checked.
3. **"Lamar-corroborated"** (session notes, informal) — independent validation against
   an entirely separate identification pipeline (Lamar). The strongest sense.

A reader seeing bare "corroborated" in a message or column name cannot tell which of
these three is meant without checking the source column. Suggest: when describing sense
2 in any future output/message, say "unscreened corroborator(s)" explicitly rather than
bare "corroborated."

## "plausibility"

Lowest-risk of the four surveyed terms — three senses, but well-separated by column
naming throughout:

- TaxaFlag's LLM categorical judgment (`likely`/`possible`/`unlikely`, from
  `review_assignments()`).
- The prior-side plausible-competitor mask read off `prior_branch` (any non-`NA` branch
  = a named row on some branch, used by the veto-bound check in
  `apply_undetected_evidence()`).
- The consensus `plausible_taxa` set (posterior-threshold-derived, from
  `posterior_consensus()`).

No action needed here beyond noting it — included for completeness of the focus-area-2
survey, not because it's actually confusing in practice.
