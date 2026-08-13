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
| `hierarchy_flag` | character | `"congruent"` / `"incongruent"` / `"insufficient_independent_evidence"` / `NA` (fetch failed, not cached, retried next call). The headline verdict -- see below for what each value actually means and doesn't. |
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
| `hierarchy_flag = "congruent"` | Trust by default. No action. |
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
