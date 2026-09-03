# Interpreting `evaluate_reference_accessions()` Output

This guide explains what every output column of `TaxaMatch::evaluate_reference_accessions()`
means, how to read them together, and what to actually do about a flagged accession. It is
written for two audiences at once:

1. **A human reviewer** deciding whether a flagged reference accession should be trusted,
   corrected, excluded, or left alone.
2. **The future LLM second-look reviewer function** (see
   `ecosystem_docs/REENTRY_PROMPT_flagged_accession_second_look.md`) -- whatever that function's
   final design, it needs to reproduce the same reasoning a careful human reviewer already does
   by hand, using exactly the columns documented here. Read this guide before designing that
   function's prompt/context.

If you only remember one thing: **`hierarchy_flag` alone is not a verdict.** It is a coarse
summary of a vote among independent BLAST hits, and the same `"incongruent"` value can mean
several structurally different things. The columns below exist specifically to tell those
apart.

---

## What the function actually does, in one paragraph

For each accession, `evaluate_reference_accessions()` BLASTs that accession's own deposited
sequence against a broad NCBI database, keeps hits that are genuinely *independent* (not the
same submission batch as the accession itself -- see "Independence filtering" below), and asks:
at what taxonomic rank do the closest independent hits agree with the accession's own listed
taxon? If most of the closest independent evidence disagrees at or above `family` rank (the
default `min_congruent_rank`), the accession is flagged `"incongruent"` -- its own label may be
wrong, or the comparison itself may be uninformative. The rest of this guide is about telling
those two cases apart.

---

## Quick-reference column table

| Column | Type | What it tells you |
|---|---|---|
| `accession` | character | Exactly as you supplied it. |
| `listed_taxon` | character | The accession's own GenBank-labeled organism. |
| `hierarchy_flag` | character | `"congruent"` / `"incongruent"` / `"insufficient_independent_evidence"` / `"not_evaluated_oversized"` / `"locally_corroborated"` (2026-09-03, see below) / `NA` (fetch failed, not cached, retried next call). The headline verdict -- see below for what each value actually means and doesn't. |
| `finest_common_rank` | character | Finest rank at which the single best independent hit agrees with `listed_taxon`, walking the *full* `kingdom→species` ladder (not just down to `min_congruent_rank`). `NA` if nothing agrees at all. |
| `n_independent_top_matches` | integer | How many independent, species-resolved hits were actually used for the verdict (`<= top_n`, default 5). Low values (0-2) mean the verdict rests on thin evidence -- see `insufficient_independent_evidence` below. |
| `n_top_matches_available` | integer | All BLAST hits before the independence filter -- diagnostic only, not part of the verdict. A big gap between this and `n_independent_top_matches` usually means most hits were same-submission-batch duplicates. |
| `frac_independent_below_min_congruent_rank` | numeric (0-1) | Jeffreys-smoothed fraction of the independent top-N hits that disagree at or above `min_congruent_rank`. This is the number `hierarchy_incongruent_threshold` (default 0.5) is actually compared against. |
| `best_hit_pident` | numeric (0-100) | Percent identity of the single best independent hit, agreeing or not. |
| `best_agreeing_pident` | numeric (0-100) or `NA` | Percent identity of the highest-identity independent hit that *agrees*, among the top-N slice. `NA` if none agree. |
| `best_disagreeing_pident` | numeric (0-100) or `NA` | Percent identity of the highest-identity independent hit that *disagrees*, among the top-N slice. `NA` if none disagree. **This is the single most important diagnostic for judging an `"incongruent"` flag** -- see below. |
| `congruent_evidence_exists_anywhere` | logical | Unlike `hierarchy_flag` (computed only from the top-N closest hits), this asks: does ANY independent hit *anywhere* in the full BLAST result (up to `max_hits`) agree at or above `min_congruent_rank`? `FALSE` is a much stronger statement than `"incongruent"` alone -- it means the listed rank has zero representation anywhere in this accession's independent evidence, not just none close enough to make the top-N cut. |
| `congruent_evidence_best_pident` | numeric (0-100) or `NA` | Percent identity of that best anywhere-agreeing hit. `NA` when `congruent_evidence_exists_anywhere` is `FALSE`. |
| `taxonomy_resolution_source` | character | `"direct"` (normal case), `"hybrid_maternal_proxy"` (hybrid-labeled accession, coarser ranks resolved from the maternal parent species -- see below), `"hybrid_unresolved"` (detected as hybrid but couldn't extract a usable parent name), or `NA` (fetch failure). |
| `label_confidence` | numeric (0-1) or `NA` | **(2026-09-02)** How confident we are that `listed_taxon` is CORRECT -- high = good, low = concerning. A log-odds sum of the vote (`frac_independent_below_min_congruent_rank`) and the percent-identity margin the vote itself ignores. This is the column downstream models consume; see "The numeric verdict" below. `NA` for `"not_evaluated_oversized"` and fetch failures. |
| `label_identity_margin` | numeric or `NA` | The percent-identity margin behind `label_confidence`: best agreeing identity minus best disagreeing identity, capped at ±5. Positive means the label's own clade matches better than whatever contradicts it. `NA` when there is no identity information at all. |
| `reference_action` | character | **(2026-09-02)** What to DO: `"keep"` / `"caution"` / `"inspect"` / `"remove"` / `"untested"`. Derived from `label_confidence` by documented thresholds, plus two hard vetoes on `"remove"`. This is what `remove_incongruent_references()` reads by default. |
| `action_reason` | character or `NA` | **(2026-09-03)** `"vetoed_by_local_corroboration"` where a BLAST `"remove"` was downgraded to `"inspect"` because the caller's own reference set corroborates the label; `"locally_corroborated_not_blasted"` for a skipped row; `NA` otherwise. |
| `corroboration_source` | character | **(2026-09-03)** Where the corroboration for the label came from: `"blast"` (`congruent_evidence_exists_anywhere`), `"local"` (an independent conspecific in the caller's own reference set at >= 99% identity over >= 80% of the amplicon), `"both"`, or `"none"`. `"local"` on a `"remove"`-shaped row is exactly the disagreement that found the primer-inclusive-query blind spot (`KM057996`). |
| `local_best_independent_pident` | numeric (0-100) or `NA` | **(2026-09-03)** Identity of the best independent local conspecific (from `corroborate_references_locally()`). `NA` when no local table was supplied. |
| `local_n_independent_conspecific` | integer or `NA` | **(2026-09-03)** Its count. |
| `listed_taxon_is_species` | logical or `NA` | `FALSE` when `listed_taxon` doesn't structurally look like a species-level binomial (e.g. `"Serranidae sp. JL-2015"`). Orthogonal to `hierarchy_flag` -- can be `FALSE` even when the accession is internally `"congruent"`. `NA` only for a fetch failure. |
| `evaluated_at` | POSIXct | When this verdict was computed. |
| `cache_hit` | logical | `TRUE` if read from the persistent cache rather than freshly BLASTed this call. |

---

## Reading `hierarchy_flag`: the three (or four) outcomes

- **`"congruent"`** -- most of the independent top-N evidence agrees at or above
  `min_congruent_rank`. The common, default-trusted case (1,141 of 1,183 real GreatLakes
  accessions, as of 2026-08-13). No further review needed by default.

- **`"insufficient_independent_evidence"`** -- fewer than `min_independent_partners` (default 3)
  independent, species-resolved hits were available at all. This is **not** evidence of a
  problem -- it usually means the accession describes a poorly-referenced or taxonomically
  isolated lineage, and NCBI simply doesn't have enough independent material to vote either way.
  Expires from the cache after `insufficient_evidence_ttl_days` (default 180) and is retried,
  since new deposits could genuinely change the answer later.

- **`"incongruent"`** -- most of the independent top-N evidence disagrees. **Do not treat this
  as "confirmed mislabel" on its own.** Cross-check against the diagnostics below before
  deciding anything.

- **`"not_evaluated_oversized"`** -- never submitted to BLAST (still over `max_query_len`
  after primer trimming and the feature-table fallback). Not evidence of anything;
  retried after the TTL.

- **`"locally_corroborated"`** (2026-09-03) -- never submitted to BLAST either, but for the
  opposite reason: an INDEPENDENT conspecific in the caller's own reference set (a different
  submission batch, >= 99% identity over >= 80% of the amplicon, per
  `corroborate_references_locally()`) already corroborates the label, so the BLAST question
  is answered for free. `n_independent_top_matches` and `best_agreeing_pident` hold the local
  numbers; the other diagnostics are `NA`; `reference_action = "keep"`; `label_confidence`
  is `NA` (there is no BLAST evidence to grade). Treated like `"congruent"` everywhere
  downstream: never a flag, never removable, cached indefinitely. Pass
  `skip_locally_corroborated = FALSE` to BLAST these after all.

- **`NA`** -- the accession's own GenBank record couldn't be fetched this call (network/NCBI
  issue). Not cached; retried automatically next call.

---

## The critical follow-up question for `"incongruent"`: is this a real mislabel, or an uninformative comparison?

`hierarchy_flag = "incongruent"` can mean any of the following, and they call for completely
different responses:

### 1. A genuine mislabel (real problem -- consider excluding or correcting)
**Signature:** `best_disagreeing_pident` is very high (~98-100%), `congruent_evidence_exists_anywhere = FALSE` (or `TRUE` but at much lower identity than the disagreeing hit).
**Interpretation:** the deposited sequence is nearly identical to something in a completely
different family/order -- a strong, specific signal that the accession's own label is wrong or
the sequence was contaminated/mismatched at deposition.
**Real example:** `AY850362` (GreatLakes 12S, confirmed 16S-vs-12S marker mislabel via
`check_marker_mismatch()` -- a different but related failure mode: the sequence itself was fine,
the marker annotation was wrong).

### 2. Poor marker resolving power for this lineage (not a mislabel -- accept the flag as correctly earned, but for a different reason)
**Signature:** `best_disagreeing_pident` is high AND `n_independent_top_matches` includes
several real, species-resolved, taxonomically diverse disagreeing hits (not just one), often at
a moderate-to-high identity band (~93-96%).
**Interpretation:** the marker/amplicon region genuinely doesn't discriminate this lineage well
from several unrelated families. The label is very likely correct; the marker just isn't
diagnostic enough at this rank for this clade.
**Real example:** `LC649807`/`MT083886` (*Stereolepis doederleini*, GreatLakes 12S,
2026-08-13). Direct re-BLAST of the amplicon-trimmed sequence found real, independent,
species-resolved hits from FOUR unrelated families (Sinipercidae, Banjosidae, Epigonidae,
Pentacerotidae, all 94.9-95.9% identity) -- genuine competing evidence, not an artifact. The
original working theory (pure taxonomic isolation, driven by a single non-species-resolved
partner) was refuted by this direct check. **Lesson: always re-verify against the pipeline's
actual amplicon-trimmed BLAST, not an ad hoc full-length re-BLAST -- the two can surface
completely different hit pools** (a short, conserved barcode region is far less discriminating
than a full mitogenome-length comparison).

### 3. A sister-family/thin-coverage artifact (weak signal, likely not a mislabel)
**Signature:** `finest_common_rank` reports a real coarser agreement (e.g. `"order"`) rather
than collapsing to `NA`; `best_disagreeing_pident` is only moderate (~85-92%).
**Interpretation:** the closest independent hits are a sister clade within the same order, at an
identity level unremarkable for a conserved/poorly-resolving marker with thin database coverage
at the listed rank. Weak mislabel signal.
**Real example:** `KY594854`/`KX384617` (*Abylopsis eschscholtzii*, PtConception 18S) --
disagreeing hits are consistently Diphyidae, a sister family within Siphonophorae/Calycophorae,
at moderate identity. Likely 18S's documented poor resolving power in this clade plus thin
Abylidae coverage, not a mislabel.

### 4. Hybrid-cross-labeled accession (structural artifact, resolved automatically)
**Signature:** `taxonomy_resolution_source = "hybrid_maternal_proxy"` or `"hybrid_unresolved"`.
**Interpretation:** NCBI's own taxonomy for a hybrid-labeled organism (e.g.
`"Ctenopharyngodon idella x Megalobrama amblycephala"`) is genuinely incomplete -- lineage
terminates at an "unclassified" node with no family/genus/species -- so it can never agree with
anything at fine rank by construction. `"hybrid_maternal_proxy"` means this was already
corrected (coarser ranks resolved from the maternal parent species, since fish mtDNA is
maternally inherited); a residual `"hybrid_unresolved"` means the label's maternal parent name
couldn't be extracted (e.g. an unusual breeding/ploidy-manipulation modifier
`clean_taxon_names()` doesn't yet recognize) -- worth a `clean_taxon_names(strip_modifiers=)`
addition if this recurs.
**Real example:** 10 of the original 13 real GreatLakes "incongruent" flags were this artifact,
not genuine mislabels.

### 5. Comparison partner itself isn't species-resolved (excluded automatically since 2026-08-13)
**Signature:** would have shown as weak evidence driven by a single low-information partner;
now `require_species_resolved_partner = TRUE` (the default) excludes such partners from the vote
entirely, so this failure mode should no longer surface as `"incongruent"` going forward.
**Interpretation, if you still see it in old cached data:** a comparison partner whose own
listed species isn't resolved to species level (e.g. `"Serranidae sp. JL-2015"` -- a family name
plus an informal specimen code) isn't meaningful evidence, since its own identity is only
fuzzily determined.
**Real example:** `NC_028197` itself was BOTH the accession under test in this role (see next
section) AND, before the fix, the sole disagreeing partner that made `Stereolepis doederleini`
misleadingly read `"incongruent"` for the wrong reason.

---

## The numeric verdict: `label_confidence` and `reference_action` (2026-09-02)

Everything above this section describes evidence a reviewer has to weigh by hand.
`score_reference_labels()` does that weighing arithmetically, and
`evaluate_reference_accessions()` now calls it on its own output, so both columns are
always present.

`label_confidence` combines the two things `hierarchy_flag` keeps separate -- the vote,
and the identity margin the vote ignores:

```
logit(label_confidence) = logit(1 - frac_independent_below_min_congruent_rank)
                          + d / margin_scale

d = (best_agreeing_pident, else congruent_evidence_best_pident)
    - best_disagreeing_pident,      capped to +/- margin_cap (default 5)
```

Read the second term plainly: each percent-identity point of margin shifts the odds
that the label is correct by one unit of log-odds (at the default `margin_scale = 1`).
Nothing corroborating and something contradicting gives the full negative cap; something
corroborating and nothing contradicting gives the full positive cap.

`reference_action` turns that number into a decision:

| `reference_action` | When | What it means |
|---|---|---|
| `"keep"` | `label_confidence >= 0.75` | Nothing to do. |
| `"caution"` | `0.25 <= label_confidence < 0.75` | Usable, but the evidence is mixed. Worth knowing about; not worth acting on alone. |
| `"inspect"` | `0.05 <= label_confidence < 0.25` | Look at this one. Often thin coverage rather than a mislabel. |
| `"remove"` | `label_confidence < 0.05` **AND** `hierarchy_flag == "incongruent"` **AND** `congruent_evidence_exists_anywhere == FALSE` | Nothing anywhere corroborates the label and something contradicts it. |
| `"untested"` | `hierarchy_flag` is `"not_evaluated_oversized"` or `NA` | No verdict was computed at all. |

**The local-corroboration veto (2026-09-03).** When `score_reference_labels()` is given the
`corroborate_references_locally()` table, a row that resolves to `"remove"` while the caller's
own reference set corroborates the label (`local_tier = "corroborated"`) is downgraded to
`"inspect"` and `action_reason` says why. `label_confidence` is NOT changed -- it stays the
BLAST-only probability, so the two sources can be seen to disagree. The case that motivated
this: `KM057996` (*Zaniolepis frenata*) was actioned `"remove"` ("no conspecific evidence
anywhere in nt") while `OQ846041`, a 169 bp *Z. frenata* deposit from 2023, sat in the local
reference set at 100% identity over 97% of the amplicon. BLAST never returned it because the
screen's query was the primer-INCLUSIVE 217 bp span, against which a 169 bp perfect match is
out-scored by every full-length relative at >= 93%; the screen now submits the primer-stripped
amplicon (`query_span = "amplicon"`). The overlap floor is not optional: `KM057967`
(*Jordania zonope*) looked corroborated by `LC126244` at "100%" over a 5.6% overlap -- a
different 12S region -- and is a true singleton whose removal stands.

The two extra conditions on `"remove"` are hard vetoes, not additive terms. An
accession that is not `"incongruent"` can never be actioned `"remove"` --
`"insufficient_independent_evidence"` is retryable, not removable. And a single
corroborating record ANYWHERE spares the accession however low its number, because one
independent submitter agreeing with the label at family or finer is qualitatively
different from nobody agreeing.

**What it does on real data.** On the first complete PtConception 12S screen (995
accessions), 919 `"congruent"` accessions are all `"keep"`; of the 12 `"incongruent"`,
4 are `"remove"` (the ones with no corroboration anywhere), 3 are `"inspect"`, 3 are
`"caution"`, and 2 -- including cabezon `OK172573`, behind 1,120 observations -- are
`"keep"`. The old `hierarchy_flag`-only removal would have taken all 12, and the
1,688 observations behind them, to catch the 4 behind 16.

Two things `label_confidence` is deliberately NOT:

- It is not a probability in any calibrated sense. It is a monotone, documented
  summary of the evidence, with one free parameter (`margin_scale`) that is a stated
  convention rather than a fitted value.
- It is not a replacement for `hierarchy_flag`, whose meaning and cached values are
  untouched. Both columns ship side by side, and the derived pair is recomputed
  post-hoc from the cache on every call, so changing `margin_scale` costs nothing.

### Downstream use

`flag_incongruent_references()` joins these columns onto a match object so they travel
with it for review, and `remove_incongruent_references()` reads `reference_action`.

A likelihood-model covariate built on `label_confidence` was prototyped in 2026-09-02
and **removed the same day** -- it is not part of this package. See
`ecosystem_docs/REENTRY_PROMPT_reference_quality_verdicts_and_downstream_use.md` for
what was measured and why it was dropped, before proposing it again.

### Recursive screening: `refine_reference_verdicts()`

An accession judged a likely error should not itself be voting on other references.
`refine_reference_verdicts()` re-runs the vote with each partner weighted by its own
`label_confidence`, iterating to a fixpoint. It needs the per-partner votes, which
`evaluate_reference_accessions()` only began caching (to `reference_pair_cache.rds`)
on 2026-09-02 -- accessions evaluated before that keep their original verdicts until
re-evaluated.

---

## `listed_taxon_is_species = FALSE`: a different, orthogonal problem

This is not about mislabeling at all -- it's about whether the reference is even usable at
species-level resolution to begin with. A reference labeled `"Serranidae sp. JL-2015"` might be
perfectly internally consistent (`hierarchy_flag = "congruent"` or, as in the real case below,
correctly `"incongruent"` because it genuinely can't agree with anything at species rank), but
it can never usefully discriminate a species-level query. Treat `listed_taxon_is_species = FALSE`
as a **"this reference can't help below genus/family, consider excluding it from species-level
match candidates"** signal, independent of whatever `hierarchy_flag` says.

**Real example:** `NC_028197` (`"Serranidae sp. JL-2015"`, GreatLakes) --
`listed_taxon_is_species = FALSE`, `hierarchy_flag = "incongruent"` (its own resolved lineage
only agrees with independent evidence at `finest_common_rank = "class"`). Not a mislabel to
correct -- a reference to flag as not-to-species and likely exclude from species-level
candidate generation.

---

## Decision guide (what to actually do)

| Situation | Recommended action |
|---|---|
| `reference_action = "remove"` | The packaged version of every row below it: nothing corroborates the label anywhere and something contradicts it. `remove_incongruent_references()` drops exactly these by default. |
| `reference_action = "inspect"` | Review by hand (e.g. `investigate_flagged_accession()`). Usually thin coverage rather than a mislabel. |
| `hierarchy_flag = "congruent"` | Trust by default. No action. |
| `hierarchy_flag = "locally_corroborated"` | Trust by default; the caller's own reference set corroborates it. No action. |
| `reference_action = "inspect"`, `action_reason = "vetoed_by_local_corroboration"` | BLAST said remove, the local reference set says the label is corroborated. Read `corroboration_source`/`local_best_independent_pident` beside the BLAST diagnostics; the local evidence is usually right when the BLAST verdict predates the primer-stripped query (2026-09-03). |
| `hierarchy_flag = "insufficient_independent_evidence"` | No action -- not evidence of a problem. Will retry automatically after the TTL. |
| `hierarchy_flag = "incongruent"`, `best_disagreeing_pident` near 100%, `congruent_evidence_exists_anywhere = FALSE` | Strong mislabel candidate -- review the specific accession by hand (e.g. `investigate_flagged_accession()`) before excluding. |
| `hierarchy_flag = "incongruent"`, several real species-resolved disagreeing hits across multiple families at moderate-high identity | Likely genuine poor marker resolving power for this lineage, not a mislabel -- accept the flag as correctly earned; do not "fix" by weighting or overriding. |
| `hierarchy_flag = "incongruent"`, `finest_common_rank` reports a real coarser agreement (e.g. order) at moderate identity | Weak signal, likely sister-clade/thin-coverage artifact -- worth a human glance, low priority. |
| `taxonomy_resolution_source = "hybrid_unresolved"` | Check whether `listed_taxon` has an unrecognized breeding/ploidy modifier prefix; consider extending `TaxaTools::clean_taxon_names(strip_modifiers=)`. |
| `listed_taxon_is_species = FALSE` | Not a mislabel signal -- flag as not-to-species; consider excluding from species-level candidate matching regardless of `hierarchy_flag`. |

---

## Independence filtering, briefly

Two accessions are treated as the *same* evidence (not independent) if they were deposited
within `submission_window` days of each other, or have accession numbers within
`submission_window` of each other under the same prefix. This exists specifically to stop one
contaminated sample submitted as many replicate accessions from looking like several
independent corroborating (or disagreeing) records. `n_top_matches_available` (before this
filter) vs. `n_independent_top_matches` (after) shows how much this filter actually removed for
a given accession.

---

## What this function deliberately does NOT do

- It does not decide anything for you by default -- use `flag_incongruent_references()` (the
  recommended default: annotates, never removes) rather than `remove_incongruent_references()`
  (a deliberate, reviewed opt-in) unless you've already reviewed the diagnostics above.
- It does not currently feed a graded per-accession quality signal into
  `TaxaLikely::evaluate_likelihoods()` -- only the binary `hierarchy_flag` blacklist decision is
  consumed downstream today. Real, agreed-on future work, not yet designed.
- It does not attempt to distinguish "genuine mislabel" from "poor marker resolving power" for
  you automatically -- that judgment call is exactly what this guide (and, eventually, the LLM
  second-look reviewer) exists to make from the diagnostic columns above.

## See also

- `evaluate_reference_accessions()`'s own roxygen (`@return`, `@section Identity diagnostics`,
  `@section Hybrid-labeled accessions`, `@section Species-resolved comparison partners`) for the
  exact mechanics behind each column.
- `ecosystem_docs/REENTRY_PROMPT_flagged_accession_second_look.md` for the LLM second-look
  reviewer design questions this guide is meant to inform.
- `TaxaMatch/CLAUDE.md`'s session notes (search `evaluate_reference_accessions`) for the full
  real-data history behind each of the worked examples above.
