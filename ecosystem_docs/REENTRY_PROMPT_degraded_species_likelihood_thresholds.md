# Reentry prompt: degraded/unreferenced-species likelihood thresholds and upranking

**From:** a design conversation (2026-07-17/19-ish) that grew out of the real
PtConception 12S "obvious errors" edge-case review — see
`[[project_edge_case_error_taxa_design]]` in the memory system for the full
list of 14 taxa and their mechanisms, and `ecosystem_docs/reference_gap_modeling.md`
for the related (but distinct) regional-overlap work. This prompt is the
**degradation/likelihood-threshold** half of that conversation, split out at
the user's request so it doesn't get tangled with the separate domestic/food
priors thread (`REENTRY_PROMPT_domestic_food_species_priors.md`).

## ⚠️ Missing input — get this before continuing

The user referenced "a paper on identifying gaps with data in barcodes" they
wanted folded into this work, but **no attachment or link actually came
through** in the message that prompted this reentry prompt. Ask for it before
doing new design work here — it may change the approach.

## Background: two related but distinct numbers already computed

All of the following were computed live against the real PtConception 12S
checkpoints (`PtConMifishSchulte_{seq_matrix,lik_model_calibrated}.rds`,
13,442 real observations) — not simulated or guessed.

### 1. How often does a wrong congener/relative outscore the true species at all?

- **Parametric** (from the trained `lik_model_calibrated`'s H1 vs H2/H3,
  treating scores as independent normals — a known-imperfect approximation,
  see caveat below): pooled within-genus flip rate 26.75%, pooled
  within-family (missing-genus) flip rate 2.43%.
- **Empirical** (direct leave-one-out on `seq_matrix`'s real pairwise
  reference-vs-reference comparisons, no distributional assumption): within-genus
  31.04% (n=2255 real sequences), within-family 16.51% (n=1502). This
  corroborates the parametric number reasonably well at genus rank but
  diverges much more at family rank (11x gap implied by the model vs ~2x gap
  empirically) — **this discrepancy is real and unresolved**, not chased down
  further given the session's context-efficiency constraint.
- Real, biologically-grounded (not an artifact) finding buried in the
  per-genus breakdown: **`Sebastes` (91% at n=155) and `Pseudopleuronectes`
  (85% at n=23) are essentially undiscriminable at the species level by this
  marker** — matches published difficulty distinguishing rockfish/flatfish by
  mitochondrial barcodes (recent radiation, incomplete lineage sorting).
- **Caveat on the parametric approach:** H1 and H2 scores for the same query
  are almost certainly positively correlated in reality (a degraded read
  scores poorly against everything, not just its true species) — the
  independence assumption's effect on the estimate is unclear in sign/magnitude
  and not yet worked out.

### 2. How often does the true species get ENTIRELY DROPPED from the candidate set (the actually consequential question)

**This is the number that matters, not #1.** The user correctly redirected
mid-conversation: it's not "does the wrong species score higher" (a narrow
loss usually doesn't cause real harm — the gap-aware Bayesian machinery can
often still recover the right answer) — it's "does the wrong species outscore
the true species by *more than the existing candidate-retention window*, so
the true species never even becomes a candidate hypothesis at all, with
nothing downstream able to recover it."

This exact question was already answered once before, at small scale:
`diagnostics/score_window_leave_one_out.R` (ecosystem soundness-review item
14, the session that calibrated `TaxaMatch::blast_sequences()`'s
`score_range` default from 2 → 8) — built for exactly this purpose, but only
ever tested on 3 small reference sets (Sebastes 54 species, Chromis 26
species, PtConception 6-genus/10-species).

**Reused that exact logic at real full-dataset scale for the first time**
(PtConception 12S, 2561 real sequences, `score_range=8`, the current
production default):

| | Wrong candidate scores ≥ true species | **True species entirely dropped** |
|---|---|---|
| Within-genus | 9.8% | **0.4%** (10/2561) |
| Within-family (cross-genus) | 11.6% | **0.4%** (11/2561) |

Reassuringly low, and validates the existing `score_range=8` calibration at
much larger scale than the original 3-genus sample.

**Real structural finding from inspecting the actual 10 dropped cases:**
dominated by species with *sparse/poor own-species reference coverage*
(`Sphyraena` appears 3 times — e.g. `S. obtusata` best-self-match only 80.7%
vs. a 100% congener match, gap 19.3 points), **not** by intrinsically tight
congener pairs. Notably `Sebastes` — despite having by far the worst raw
"congener scores as well or better" rate (91%) — contributes only ONE dropped
case (`S. oculatus`), because Sebastes species cluster tightly together
(constant narrow near-ties that rarely exceed the 8-point drop threshold).
**Open question, not yet checked:** does `H1_Lookup$n_obs_species` (or
`H2_Lookup$n_pairs`) already predict which specific species are at risk of a
total-loss event — i.e., would this just confirm the existing Empirical Bayes
shrinkage machinery is already pointed at the right risk factor, or is there
a gap it doesn't cover?

## New problem to solve (not yet explored) — low likelihood winning by default

The user's own framing, verbatim intent: a recurring failure mode where **a
low-likelihood candidate wins the consensus purely because there's no
competition and no obvious unreferenced-candidate mechanism triggers** — not
the Hylobatidae case (which correctly hedges to family rank because the
generic `unreferenced_genus` placeholder has enough *relative* likelihood to
win), but a case where *neither* a real congener nor a competitive generic
placeholder is available, so a weak, absolute-likelihood-poor match wins
completely unopposed.

**Proposed fix direction (user's framing):** the pipeline currently only
broadens/uprank rank via an LCA-style rule based on candidate *disagreement*
(`TaxaMatch::add_lowest_consistent_rank()`/`filter_redundant_hypotheses()`,
majority-threshold-based; also `TaxaTools::escalate_taxonomic_rank()` for
singleton/no-data cases). Add a **second, complementary uprank trigger**:
broaden rank when the *winning* hypothesis's own likelihood falls below a
threshold derived from the trained likelihood model — a backstop
specifically for reference-database gaps that can't be filled (no congener
exists, no unreferenced-species mechanism fires) and nothing else in the
pipeline would catch a weak, effectively-uncontested match.

**Needs working out, not yet done:** how this relates to the *existing*
Session 121 mechanism (`.evaluate_one_query()`'s score-only chi-squared
outlier test, `alpha=0.001`, zeroes H1 likelihood if the query is
inconsistent with its trained species distribution) — does zeroing H1
already cause a coarser hypothesis to win naturally downstream (in which case
this is already half-solved), or does it need an explicit new uprank action
because the existing mechanism only zeroes one candidate rather than actively
broadening rank?

## Two concrete deliverables the user asked for

1. **A likelihood threshold that triggers upranking.** Derive from the
   trained `lik_model` — candidate approaches: a quantile of the real
   query-vs-own-species score distribution (`H1_Lookup`/`H1_Global_Mu`/
   `sigma_score`); reusing/extending the Session 121 `alpha=0.001` chi-squared
   mechanism's existing threshold logic rather than inventing a new one from
   scratch.
2. **An estimate of the rate at which the true species, even though it IS
   referenced, fails to become a candidate at all** (i.e., the sample was too
   degraded to be recognized, not that no reference exists). This is a direct
   generalization of the "true species entirely dropped" computation above
   (already at 0.4%/0.4% for clean reference-vs-reference data) — the harder,
   not-yet-done part is extending it from clean-reference-vs-reference pairs
   to real degraded QUERY data specifically (the `calibrate_query_noise()`
   confident-observation set, Session 155, is the obvious real data source
   for this — it already isolates real query observations with an
   independently-known true species).

## Where to start re-reading

1. `ecosystem_docs/reference_gap_modeling.md` — the sibling regional-overlap
   mechanism this connects to conceptually (different failure mode, same
   general "reference database gap" family of problems).
2. `diagnostics/score_window_leave_one_out.R` — the existing methodology this
   session reused; extend rather than reinvent.
3. `[[project_edge_case_error_taxa_design]]` (memory) — the real 14-taxa error
   review this all grew out of.
4. `TaxaLikely/CLAUDE.md`'s Session 121 note (outlier/alpha mechanism) and
   Session 151 note (`score_range` calibration) — both directly relevant
   prior art, already in this exact codebase.
5. `TaxaTools::escalate_taxonomic_rank()` / `TaxaMatch::add_lowest_consistent_rank()`
   / `filter_redundant_hypotheses()` — the existing LCA-style upranking
   mechanisms this new likelihood-based rule would sit alongside.
