# Re-entry: Axis 2 ("is this observation diagnostic?") — multi-factor redesign

> ## ⚠️ UPDATE 2026-07-27 (later, Opus 5) — READ THIS FIRST; three sections below are now FALSIFIED
>
> Everything below was written before the `Dr = X` assumption was checked against
> source. It was checked, and it is **false**. Three consequences, each verified
> against real Mugu data, not reasoned from the docs:
>
> 1. **`Dr = X` is FALSE — `confusion_risk` is an Empirical-Bayes blend, not a clean
>    per-pair rate.** `support_curves.R`'s `.eb_shrink()` returns
>    `w*rate + (1-w)*pooled_rate` with `w = n/(n+10)`. Real 12S: median `w` = 0.69,
>    minimum 0.17. On real rows, 38 report nonzero risk where the genus's own data
>    says exactly 0, and 7 cross the 0.5 flag threshold purely from shrinkage.
>    Critically `w` is a function of `n` (referenced congener count) — **the very
>    reference-completeness quantity `P` was meant to inject.** `Ds` would have
>    double-counted it.
> 2. **The exact zeros mean the OPPOSITE of what the "Confusion_risk, properly
>    scoped" section claims.** They are not "nothing to compare against". Real 12S:
>    zero rows have median score **100** (range 99.5–100) and 216/296 of them *do*
>    have a real genus-specific congener estimate; nonzero rows median 98.08. The
>    zeros were near-perfect matches beating every congener pair in training. This
>    removes the entire stated motivation for `Ds`.
> 3. **The "153/606 perfect overlap at all three ranks" is explained** — and is not a
>    coverage pattern. It was a **grid-quantization cliff**: the lookup snapped to the
>    nearest 1-point grid threshold, and all three tiers' pooled curves hit 0 at
>    threshold 100, so any row ≥99.5 zeroed at species, genus and family at once.
>
> **`Ds` is DROPPED** (user-approved). Three reasons: its premise is false (2), it
> double-counts completeness (1), and the unreferenced-side `P` is genuinely ~0
> almost everywhere anyway — the "clean null" *was* real, verified with a positive
> control (54/87 census genera and 35/55 unreferenced genera do match
> `taxaexpect_priors`, so the join works; the near-zero species overlap is
> biological, since locally-present species tend to be the well-*referenced* ones).
> The user's Laplace `+1` instinct was right but misplaced — it belongs on the rate
> estimate, not compounded over `P`. See "WHAT SHIPPED" at the bottom of this file.
>
> Still live and unchanged below: the Phase-1/Phase-2 rank-scoping rule, the
> `fit_calibration_basis` need, the `not_modeled` state, and the three named
> execution errors.

Status as of 2026-07-27. This document is a direct continuation of
`REENTRY_PROMPT_posthoc_assessment_axes_redesign.md` (previous session) — read that
first for how the whole axes-redesign task started, and for Axis 1 (prior) and Axis 3
(resolution), both of which remain settled and unchanged by this session. **This
document supersedes that file's entire Axis 2 section** — what looked like a
finished, ready-to-implement Axis 2 (three-tier `diagnostic`/`marginal`/`inconclusive`
on `absolute_fit_pvalue` alone) turned out to be answering only one of several
questions "is this observation diagnostic" actually requires. Read this document
fully; do not trust the prior file's Axis 2 section as current.

## How this session started

Picked up at "Axis 2 finalized: `goodness_of_fit` (renamed from
`absolute_fit_pvalue`), thresholds `diagnostic >= 0.70` / `marginal` / `inconclusive
< 0.05`, plus a `not_modeled` 4th state and a `fit_calibration_basis` companion flag
for markers where `calibrate_query_noise()` never actually calibrated (COI in this
dataset — see below)." The user then asked for a "recap" and pushed back hard: **why
isn't this easier?** Using a worked example (100% match + 2% gap + few unreferenced
taxa = diagnostic; 90% match = not diagnostic; 100% match but many other 100%
candidates = not diagnostic; 100% match but many unreferenced relatives = not
diagnostic), the user showed that a single absolute-fit column structurally cannot
answer several of the sub-questions that go into "is this diagnostic" — it never
sees the competing candidates at all. That reframing is the actual subject of this
whole session. **Do not re-collapse this back into a single-column threshold
question without re-reading this reframing.**

## The real, verified facts about what each existing column can and cannot see

All confirmed by reading `TaxaLikely::evaluate.R` source directly this session, not
assumed:

- `winner_absolute_fit_pvalue` (`.one_sided_fit_pvalue(x, mu, sigma_11)` —
  `pnorm((x-mu)/sqrt(sigma_11))`) is **score-only, univariate**. `sigma_11` is
  literally the `[1,1]` (score-variance-only) element of the covariance matrix. Gap
  never enters this formula. It answers exactly one question: does the winner's own
  score look typical of a genuine same-species/genus match, in isolation.
- **Gap is not missing, it's just never been looked at.** `score_likelihood`
  (`raw_likelihood / max(raw_likelihood)` within one observation) is 1.0 for the
  winner by construction, which is why it looked useless earlier — but the
  **second-highest `score_likelihood` value among the SAME observation's other
  candidate rows IS the gap signal**: near 1.0 means a near-tie with the runner-up,
  near 0 means a decisive win. No new column needed, just a different aggregation
  (per-observation runner-up, not per-observation winner). This was a real
  correction I made mid-session — I'd first said gap needed a new column; it
  doesn't.
- `n_plausible` (`TaxaAssign::posterior_consensus()`) is **downstream of
  `compute_posterior()`**, i.e. it's a POSTERIOR-based (prior x likelihood) count,
  already computed after the prior is folded in. **Do not reuse it for a
  likelihood-only diagnostic** — for the specific "is a low-prior high-posterior
  result trustworthy" question this whole axis redesign is ultimately in service of,
  using a prior-contaminated count to judge whether the prior's own contest was
  fair is circular. Any "how many candidates competed" statistic for Axis 2 needs
  to be built fresh from `$likelihoods`, before `compute_posterior()` ever runs.
- `raw_likelihood`/`raw_likelihood_cov`/`raw_likelihood_evidence` — see "Real
  TaxaLikely bug found and fixed" below. Tested directly against real data as a
  candidate cross-observation diagnostic (median-based) and **empirically
  REJECTED** — see that section.
- `species_confusion_risk`/`genus_confusion_risk`/`family_confusion_risk`/
  `own_rank_confusion_risk` — extensively re-investigated this session (previous
  session had already rejected these once; that rejection was itself partly a
  category error — see below). Real, substantial finding: **~25-27% of rows across
  all three ranks show an exact-zero confusion_risk simultaneously at species,
  genus, AND family** (153/606 rows, a perfect overlap — verified directly, not
  estimated). This is a structural "nothing to compare against" pattern (monotypic
  or thin reference coverage for that genus/family), not genuine excellent
  evidence — the same "unprecedented-vs-weak" ambiguity Axis 1 already had to
  solve for `winner_prior`, now showing up again here, unsolved. **Do not build a
  `discrimination_rank` label directly on these three raw columns without first
  addressing this** (see "Open, not yet built" below — this is exactly what the
  `Ds` completeness correction is for).

## Real TaxaLikely bug found and fixed this session (already shipped)

`TaxaLikely::evaluate_likelihoods()` computed `raw_likelihood`/`raw_likelihood_cov`/
`raw_likelihood_evidence` (the bivariate density BEFORE ratio-normalization) but
**silently dropped all three columns at TWO separate `select()` calls** before they
ever reached a caller — one inside `.evaluate_one_query()` (`R/evaluate.R`, the real
blocker, since this runs per-query before the outer function even sees the result),
one in the outer `evaluate_likelihoods()` (found and fixed first, but wasn't the
actual problem since the per-query one stripped the columns first). Both fixed —
all three raw columns now present in `$likelihoods`. `devtools::test()` 0 failures
(886), `devtools::check()` 0/0/0, reinstalled to `~/Library/R/4.0/library`. New
roxygen documents what the three columns are and their scale-comparability caveat.
**This fix is real and should stay** — it's genuinely useful raw data, even though
the specific use we tried it for (below) didn't pan out.

## `raw_likelihood`-vs-marker-median: tested, REJECTED

User's original proposal: use the raw (unnormalized, score+gap-aware) bivariate
density, compare each observation's winner to its own marker's median, as a
calibration-independent cross-marker diagnostic. Tested directly on real data (12S
and COI, using the newly-exposed `raw_likelihood` column) — **empirically fails**.
All three real "not suspect" 12S anchors landed ABOVE their marker's median
(6.63, 10.5, 6.86 vs. median 6.45) — including ASV_379/*Chaenogobius* (now resolving
to genus *Luciogobius* post the 2026-07-25 synonym fixes — confirmed by the user to
be equally implausible under either name, so this doesn't change the case), the
clearest "suspect" case, at 10.5 — the *highest* of the four, near the 80th
percentile. Root cause, verified conceptually not just empirically: a Gaussian
density's peak height is inversely proportional to its fitted sigma
(`dnorm(x,mean,sd)` at the mean = `1/(sd*sqrt(2*pi))`) — a candidate whose reference
sequences are few and near-identical (tight sigma) gets a taller raw density
regardless of true match quality, independent of how good THIS query's match
actually is. This is the same artifact this package's own documented "per-species
sigma floor" design note already flags for a related reason — the floor only sets a
*minimum*, so sigma still varies a lot above it across taxa. **Do not revisit
raw_likelihood as a cross-observation/cross-marker diagnostic** — it is not scale-
comparable across candidates with genuinely different trained sigmas, unlike
`absolute_fit_pvalue`, which is a real probability and IS scale-invariant by
construction.

## Confusion_risk, properly scoped: real, useful, but incomplete on its own

**The user's framing (their words, paraphrased and confirmed correct)**: a high
posterior riding on a very low (unprecedented) prior has ≥3 explanations — genuine
discovery, confusion/lack-of-real-alternatives, or reference-database error. You
can't tell these apart from the posterior alone. But you CAN ask: was the likelihood
mechanism even capable of telling this candidate apart from its relatives? If not
(high confusion risk — the genus/family is inherently hard to resolve with this
marker), a clean "win" is hollow. If it was capable AND the candidate set was fairly
complete (real alternatives were actually allowed to compete), a clean win carries
real weight. This is NOT asking confusion_risk to reproduce Axis 1's ecological-
plausibility verdict (confirmed AGAIN this session that it can't/shouldn't — see
next paragraph) — it's a genuinely different, legitimate question about whether the
evidence-generating process itself had discriminating power.

**Real correlations pulled by the user** (Mugu 12S+16S+COI pooled,
`cor(..., use="pairwise.complete.obs")`):
```
                              winner_likelihood winner_absolute_fit_pvalue winner_species_confusion_risk
winner_likelihood                     1.0000000                  0.6624269                    -0.6872133
winner_absolute_fit_pvalue            0.6624269                  1.0000000                    -0.8206724
winner_species_confusion_risk        -0.6872133                 -0.8206724                     1.0000000
winner_genus_confusion_risk          -0.6039591                 -0.5785451                     0.6916661
winner_family_confusion_risk         -0.3708215                 -0.7654312                     0.7625397
```
`species_confusion_risk` vs. `absolute_fit_pvalue`: r=-0.82 (R²≈0.67) — substantial
but leaves real independent variance; the DIVERGENT cases (decent absolute fit but
still high confusion risk) are exactly where confusion_risk adds value beyond
`goodness_of_fit` alone — "looks like a good match, but a confusable relative would
look almost as good too."

**Category error made TWICE this session, now fixed — read carefully before using
any confusion_risk column**: each `*_confusion_risk` column tests discriminability
against relatives ONE RANK UP from where it's named (`species_confusion_risk` tests
against congeners = same genus different species; `genus_confusion_risk` tests
against confamilials = same family different genus; `family_confusion_risk` tests
against a different family entirely). **The column to use must match the rank of
what's actually being evaluated, not `consensus_rank`.**
- **Phase 1 (`primary_taxon` evaluation, current scope)**: `primary_taxon` is
  (almost always) a species-level candidate → always use `species_confusion_risk`,
  regardless of what `consensus_rank` ended up being after LCA. I got this wrong
  TWICE (first reached for `own_rank_confusion_risk` mismatched to primary_taxon's
  actual rank; second time reached for `genus_confusion_risk` because
  `consensus_rank` said "genus," when Phase 1 should stay anchored to
  `primary_taxon`'s own rank regardless of consensus).
- **Phase 2 (`consensus_taxon` evaluation, deferred)**: match to whatever rank the
  LCA landed at — consensus at genus → `genus_confusion_risk` + a plausible-*other-
  genera-within-family* count; consensus at family → `family_confusion_risk` + a
  plausible-*other-families* count (likely needs order-level occurrence data, not
  yet checked whether that's populated anywhere).

**Verified with the correctly-scoped columns, real data (rank-matched to
`consensus_rank` for this specific check, not yet re-verified against
`primary_taxon`'s own rank for the family-level cases)**:
```
ASV_26  Salmo       genus  not suspect   genus_confusion_risk  = 0.000
ASV_30  Prosopium   genus  SUSPECT       genus_confusion_risk  = 0.000  <- does NOT discriminate
ASV_371 Salmonidae  family not suspect   family_confusion_risk = 0.000
ASV_379 Chaenogobius genus SUSPECT       genus_confusion_risk  = 0.106
ASV_382 Sciaenidae  family not suspect   family_confusion_risk = 0.199
ASV_430 Gobiidae    family not suspect   family_confusion_risk = 0.202
ASV_463 Gobiidae    family not suspect   family_confusion_risk = 0.000
```
Even correctly rank-matched, confusion_risk alone still does NOT reproduce the
suspect/not-suspect verdict (*Prosopium*, suspect, ties *Salmo*, not suspect, at
exactly 0.000). **This is expected, not a failure** — see the framing above:
confusion_risk was never meant to answer the ecological-plausibility question, only
"was there real discriminating power." Re-derive `Dr` values below using the
CORRECTLY Phase-1-scoped `species_confusion_risk`, not the consensus-rank-matched
values in this table (this table predates the Phase-1-scoping fix; the corrected
species-level numbers are in the `Ds` section below).

## The `Ds` completeness correction (Bernoulli/binomial) — settled formula, partially validated

Motivated directly by the confusion_risk zero-inflation problem above, and by the
user's platypus/koala-vs-mouse framing: a low confusion_risk is trustworthy only
when the reference database has sampled a REPRESENTATIVE FRACTION of what's
biologically out there to be confused with — not an absolute count of comparisons
made. **Confirmed explicitly**: the issue is the PROPORTION of potential comparisons
that are referenced, not the raw number of comparisons.

**Settled formula**:
```
Ds = 1 - (1 - Dr)^(P + 1)
```
- `Dr` = the relevant `*_confusion_risk` value, rank-matched to what's being
  evaluated (see scoping rule above). **User's explicit assumption, NOT yet
  independently verified against source**: `Dr = X` directly, i.e. `confusion_risk`
  as currently computed is ALREADY a clean per-candidate-pair rate, no `f(X,R)`
  transform needed. Reasonable given the doc's own phrasing ("P(a real congener...
  *pair*... would score this high or higher)"), but **owed a real check against
  `.compute_rank_score_curves()`/`.lookup_confusion_risk_value()`
  (`TaxaLikely/R/support_curves.R`) before this is final** — specifically whether
  Empirical-Bayes shrinkage (mentioned in that file's own docs) means `X` is a
  blend of a genus-specific rate and a pooled fallback rate when `R` (referenced
  relatives used to compute it) is small, in which case treating `X` as a clean
  `Dr` regardless of `R` could be wrong. This is the single most important
  unverified assumption in this whole document — check it first if picking this
  back up.
- `P` = count of **plausible** (not all) relatives — locally-plausible congeners for
  species-level, locally-plausible confamilial genera for genus-level, etc. "+1" is
  a deliberate Laplace/add-one-style safeguard (explicit user request, and directly
  analogous to this ecosystem's own existing `Beta(1, N_total-1)` dark-diversity
  floor convention): without it, `P=0` gives `Ds=0` (false certainty) whenever no
  local occurrence data exists for ANY relative — indistinguishable from "genuinely
  no other species live here." With the +1, `P=0` correctly reduces `Ds` to `Dr`
  itself (the raw per-pair rate), never claiming more confidence than the raw
  evidence supports just because nothing else happened to turn up.
- `g` = Bernoulli/binomial compounding (`1-(1-Dr)^P` = probability at least one of
  `P` independent real candidates would score this well or better) — same
  mathematical family as a multiple-comparisons/family-wise-error correction.
  **Confirmed by user, this is not proportional, it's the Bernoulli form.**

**`P`'s definition, refined mid-session — READ THIS BEFORE COMPUTING `P` AGAIN**:
initial build used the WRONG population twice. (1) First attempt joined
`taxaexpect_priors` by deriving genus from `taxon_name`'s first word and counting
ALL same-genus rows with `model_tier %in% c("tier1","tier2")` — this actually WAS
roughly right in spirit (locally-plausible congener count) but was paired with the
wrong `Dr` (see scoping error above). (2) When re-checked using the REAL candidate
lists from `plausible_taxa` (`posterior_consensus()` output) joined against
`taxaexpect_priors$taxon_name` directly (exact match, not derived-genus match) for
all 5 anchor observations, **the result was a clean null: ZERO of the specific
candidate species in ANY of the 5 anchor cases' `plausible_taxa` lists appear in
`taxaexpect_priors` at all** (not "mostly floor" — literally absent, every single
candidate, every case). This is real and informative on its own (confirms the
entire local congener/confamilial community is often unmodeled, not just the
winning species, for these specific genus/family-level cases) but means **the
anchor-case set used throughout this whole investigation cannot validate `P` at all
— it's degenerate (P=0) for every case by construction**. A broader, less-degenerate
sample is needed to actually test whether `P`/`Ds` discriminates anything. Do not
conclude `Ds` doesn't work from this — conclude the test was underpowered.

**`P` should be built from PLAUSIBLE relatives, not ALL relatives (explicit user
correction, with a clean example)**: "if we are on an island with three lizard
species, our ability to discriminate is lower than if we are on the mainland where
there are 20" — `P` must reflect the local competitive pool, not global taxonomic
diversity.
- **Referenced side**: NOT simply `n_specific_direct` (raw BLAST-returned candidate
  count) — that was a real execution error this session (see "Real execution
  errors" below), since direct BLAST hits are NOT plausibility-filtered at all
  (only restoration-added candidates go through `candidate_species_filter`). Must
  actually join against `taxaexpect_priors` (or the real candidate list via
  `plausible_taxa`) and count only non-floor/tier1-tier2 entries.
- **Unreferenced side**: needs the real per-genus unreferenced-species NAME list
  (available — see coverage census below) intersected against local plausibility
  the same way. **Never built this join for real** — only got as far as confirming
  the data source exists (see next section). This is the most concrete next step.
- **Weighting**: unweighted (binary plausible/not) was the first-pass choice,
  explicitly because it keeps `P` independent of prior MAGNITUDE (only prior
  PRESENCE gates inclusion) — avoids re-entangling this likelihood-side diagnostic
  with Axis 1's actual numeric values. User is now OPEN to reconsidering an
  abundance-weighted version, "so long as we are not double counting prior
  influence" — **open design question, not resolved**. A weighted version would
  need its own derivation (a straight probability-weighted sum doesn't trivially
  stay a valid Bernoulli-compounded probability) and was not attempted.

## Real coverage-census data source (confirmed to exist, ready to use)

`~/My Drive/Rscripts/eDNA/SepulvedaMugu/MuguWilderFish_blast_coverage_12S.rds`
(equivalent files presumably exist per-marker — only 12S actually inspected this
session). Structure: `list(census, unreferenced)`.
- `census`: one row per genus — `group` (genus name), `total` (real described
  species count, from NCBI taxonomy), `in_reference` (species with barcode refs),
  `has_seqs_not_in_ref`, `has_predicted_only`, `unreferenced` (count),
  `is_complete` (logical). E.g. `Mugil: total=22, in_reference=2, unreferenced=11,
  is_complete=FALSE`.
- `unreferenced`: a flat character vector of ALL unreferenced species names across
  every genus (474 names for 12S) — e.g. `"Mugil setosus"`, `"Mugil brevirostris"`,
  ... — this is exactly what's needed to build the unreferenced-side `P` count
  (intersect with `taxaexpect_priors$taxon_name` per genus, per the plan above).
  **Not yet actually joined or used** — confirmed to exist, structure inspected,
  nothing built on top of it yet.

**Genus-level `P` computed for the 3 genus-consensus anchors (`Salmo`,
`Prosopium`, `Chaenogobius`), REFERENCED side only, via `taxaexpect_priors`
directly (not yet via the coverage-census unreferenced list)**: all three genera
have ZERO rows in `taxaexpect_priors` at all (not just zero non-floor — zero rows,
period) — i.e. `P=0` for all three on the referenced side. Per the `+1` correction,
`Ds` collapses to `Dr` exactly for all three (no compounding effect, since there's
nothing to compound against). Using the CORRECTLY Phase-1-scoped `Dr =
species_confusion_risk`:
```
ASV_26  Salmo trutta             Dr=0.000  P=0  Ds=0.000
ASV_30  Prosopium spilonotus     Dr=0.027  P=0  Ds=0.027
ASV_379 Chaenogobius annularis   Dr=0.204  P=0  Ds=0.204
```
**Family-level `P` (Salmonidae/Sciaenidae/Gobiidae) never computed** —
`taxaexpect_priors` has no populated `genus`/`family` columns of its own (all NA in
the cached object; the real genus/family mapping is built separately in the
workflow script via `fill_higher_ranks()` into an `expansion_taxonomy` object that
is NOT cached anywhere on disk — confirmed via `ls`, nothing found). Would need
either a fresh `fill_higher_ranks()` call (live network lookup) or building that
mapping from scratch to do the family-level check.

## Candidate-pool tabulation — built, but with two real errors, not yet corrected

**What was actually run** (real numbers, from `lik_12s$lik_result$likelihoods` /
`lik_coi$lik_result$likelihoods` after the `raw_likelihood` fix + reinstall):
```
              n_specific_direct  n_specific_restored  has_unref_species  has_unref_genus
ASV_371 (Salmonidae, not susp.)          11                   10              TRUE            TRUE
ASV_382 (Sciaenidae, not susp.)           9                    3              TRUE            TRUE
ASV_26  (Salmo, not susp.)                5                    0              TRUE            TRUE
ASV_379 (Chaenogobius, SUSPECT)           3                    0              TRUE            TRUE
ASV_30  (Prosopium, SUSPECT)              4                    0              TRUE            TRUE
```
**Two real, user-flagged execution errors in this build, not yet fixed**:
1. `n_specific_direct` is a RAW row count from `$likelihoods`, not plausibility-
   filtered. I incorrectly asserted earlier in the session that this was already
   locally-plausible because `restore_suppressed_candidates()`'s
   `candidate_species_filter` gates it — **that's only true for
   `n_specific_restored`**. Direct BLAST-returned candidates are NOT filtered by
   local plausibility at all (confirmed by the actual names: ASV_371's 11 direct
   candidates include Old World Balkan/Caspian trout and Siberian grayling species
   with zero chance of being locally plausible in California). Needs the same
   `taxaexpect_priors` join as the `P` calculation above, applied to BOTH direct
   and restored candidates, not assumed for either.
2. `has_unreferenced_species`/`has_unreferenced_genus` are booleans (presence of
   the H2/H3 placeholder row), which the user explicitly said NOT to build — they
   asked for a COUNT of unreferenced species/genera, not TRUE/FALSE. Confirmed with
   real data that the boolean version is useless anyway — `TRUE` on literally every
   single row checked, zero discriminating power, because the H2/H3 placeholder
   row's mere PRESENCE (not its competitiveness or the number of real species it
   stands in for) is what a boolean captures, and it's always present whenever
   the genus/family is known at all (per the "Single H2/H3 anchor" design —
   `evaluate_likelihoods()` always generates exactly one H2 + one H3 row when
   computable, regardless of how many real unreferenced species actually exist).
   **The correct count is the same coverage-census `unreferenced` per-genus number
   from the section above, intersected with local plausibility** — i.e. Category
   2's unreferenced count and Category 1's `P` (unreferenced side) are the SAME
   underlying quantity from the SAME source, not two separate things to build.

**Also not yet done**: the user asked to compare the plausible-count approach
against a score-weighted alternative (checking whether the H2/H3 placeholder's own
`score_likelihood` is actually competitive, not just present) — never built either
version correctly enough to compare them against each other.

## `goodness_of_fit` (formerly `absolute_fit_pvalue`) — still settled, unchanged by this session

Everything from the previous reentry doc's Axis 2 section on naming/thresholds
remains valid and is NOT superseded:
- Rename `absolute_fit_pvalue` → `goodness_of_fit` (higher = better, fixes the
  backwards-reading p-value name) — confirmed, not yet implemented in code.
- Thresholds: `diagnostic >= 0.70` (real 10x-larger-than-neighboring empty gap,
  0.624-0.746, in the calibrated 12S+16S distribution), `marginal` = [0.05, 0.70),
  `inconclusive < 0.05` (kept at the conventional significance value; no natural
  break found to justify moving it). No 4th "exceptional" tier above `diagnostic`.
- `fit_calibration_basis` companion flag needed (`"calibrated"` vs
  `"uncalibrated_fallback"`) — real, live necessity confirmed on this exact
  dataset: 12S (`offset_form="linear"`, 344 confident obs/34 genera) and 16S
  (`offset_form="linear"`, 162/28) both properly calibrated; COI genuinely was not
  (`offset_logit=0`, only 22 confident observations, needs >=30) — confirmed COI's
  `goodness_of_fit` values (max 0.606) can NEVER reach the 0.70 `diagnostic` bar
  regardless of true match quality, purely because it was never calibrated. Without
  this flag, that reads as "COI evidence is weak" when it's really "COI was never
  calibrated."
- `not_modeled` 4th categorical state confirmed for the 10 structurally-NA rows
  (`unreferenced_genus`/`unreferenced_species` hypothesis types — nothing to test
  absolute fit against).
- Not yet validated against a second dataset (PtConception) — confirmed no usable
  checkpoint currently exists (`real_model.rds` is stale, predates calibration and
  confusion_risk entirely; `PtConMifishSchulte_lik_result.rds`/`_lik_model.rds`
  never saved to disk despite the workflow script being written to do so). Treated
  as an open, disclosed limitation, not blocking.

## Real execution errors this session, named explicitly so they aren't repeated

1. **Category error, twice**: reaching for a confusion_risk column matched to
   `consensus_rank` instead of the rank of what's actually being evaluated
   (`primary_taxon`'s own rank, for Phase 1). Same root mistake as an earlier
   session's `winner_absolute_fit_pvalue`-vs-`consensus_taxon` confusion — the
   general lesson (ANY `winner_*` column describes `primary_taxon`, never
   `consensus_taxon`, unless explicitly rank-matched on purpose) keeps needing
   re-learning. **Check this explicitly, every time, before using any winner_*
   or confusion_risk column.**
2. **Claimed a join was already done when it wasn't**: asserted `n_specific_direct`
   was already locally-plausible-filtered without verifying, when only the
   restored half of the candidate set actually goes through a plausibility gate.
3. **Built presence/absence when a count was explicitly requested**: user had
   already said "we want to count unreferenced species and genera, not ask TF" —
   built a boolean anyway, and it turned out (predictably, in hindsight) to carry
   zero information once checked against real data.

The user asked directly whether this reflects the conversation's length exceeding
what the model can reliably track, and recommended switching to a more capable
model (Opus) for the remainder of this work, including likely the eventual
implementation pass. Take that seriously on resume.

## Concrete next steps, in order

1. **Verify the `Dr = X` assumption** against `.compute_rank_score_curves()`/
   `.lookup_confusion_risk_value()` source (`TaxaLikely/R/support_curves.R`) —
   single most important unverified claim in this document.
2. **Build the unreferenced-side `P`/count properly**: coverage census's
   `unreferenced` species-name list per genus, intersected with local plausibility
   (`taxaexpect_priors$taxon_name`, non-floor). This single join answers both the
   still-open half of `Ds`'s `P` AND Category 2's unreferenced count — they're the
   same quantity.
3. **Rebuild `n_specific_direct`/`n_specific_restored` as plausibility-filtered
   counts**, not raw row counts — same join, applied to both.
4. **Get a non-degenerate test sample** — the current 5-8 anchor cases all have
   `P=0` on the referenced side, so nothing has actually validated whether `P`/`Ds`
   discriminates anything yet. Need cases where local congener/confamilial
   occurrence data genuinely exists to know if this works.
5. **Decide the abundance-weighting question** for `P` (binary plausible/not vs.
   weighted by prior magnitude) — open, not resolved, real double-counting risk to
   think through if weighted.
6. **Family-level `P`** needs `expansion_taxonomy` (genus→family mapping) — not
   cached anywhere for Mugu; needs either a fresh `fill_higher_ranks()` call or
   building it from scratch.
7. Only after 1-6: decide what Axis 2 actually ships as — a single
   `goodness_of_fit` column plus several companion diagnostics read together by a
   human (matching this whole redesign's original "axes are independent, human
   reads them together" philosophy), or some documented combination rule. Not yet
   decided, and shouldn't be guessed at before 1-6 are settled.

## Working style notes (unchanged from the previous reentry doc, worth restating)

- Ground every claim in real data or a real source read before trusting it —
  this session's own repeated errors happened exactly when this discipline
  slipped, even briefly.
- Do not implement code changes without an explicit go-ahead (the one exception
  this session: the `raw_likelihood` TaxaLikely fix, explicitly requested and
  shipped).
- The user pressure-tests every claim with concrete real numbers; treat pushback
  as the primary validation mechanism, not friction to route around.

---

# WHAT SHIPPED, 2026-07-27 (Opus 5) — supersedes the `Ds`/`P` plan above

User-approved decisions this session: (1) drop `Ds`; (2) fix the quantization cliff
first; (3) use a statistically defensible, non-arbitrary, all-rows floor; (4) adopt
`discriminating`/`weak`/`indistinguishable` as the Axis 2 tier names.

## 1. TaxaLikely `R/support_curves.R` — two fixes (SHIPPED, installed)

**Jeffreys floor.** Rate curves now carry the raw empirical proportion (`rate`/
`pooled_rate`) *and* a Jeffreys-smoothed companion (`rate_smooth`/
`pooled_rate_smooth` = `(k + 1/2)/(n + 1)`, the Beta(1/2,1/2) reference prior —
already this ecosystem's own convention, cf. `TaxaExpect::generate_full_priors()`'s
`jeffreys_fallback`, Jeffreys 1946). Chosen over Laplace `(k+1)/(n+2)` and the rule
of three because it is *derived* rather than picked, adds no tunable constant, is one
line of arithmetic on values already computed, and is a continuous estimator that
works on every row (the rule of three is only defined at `k = 0`).

**Interpolation.** `.lookup_confusion_risk_value()` now interpolates linearly
(`stats::approx(rule = 2)`) instead of snapping to the nearest grid threshold. Works
on already-stored curves — no retraining needed for this half.

**Why the raw and smoothed columns are kept separate — do not "simplify" this.**
Replacing `rate` outright was tried first and moved real production thresholds
(12S genus 97→98, 16S genus 96→98, COI species 98→99), because `(k+1/2)/(n+1)`
reweights groups by `n/(n+1)`, partly undoing the deliberate genus-equal weighting.
`compute_rank_thresholds()`'s Youden's J wants the raw empirical ROC; the confusion-risk
lookup wants the smoothed estimate. Splitting the columns leaves all three markers'
`rank_thresholds` **bit-identical to cached** (verified) while fixing the lookup.

Real effect (12S species tier, pooled): 99.4/99.5/99.6 went from `0.279/0.279/0.000`
(a cliff triggered by a 0.1-point score change) to a smooth gradient; a literal 100%
match now reports 0.0393 rather than an impossible exact 0. New
`tests/testthat/test-support-curves.R` (46 assertions) — this file had **no test
coverage at all** before. `devtools::test()` 932 pass / 0 fail; `check()` 0/0/0.

> ⚠️ The Jeffreys half only takes effect on **retrained** models (it changes stored
> curves); the interpolation half applies immediately to existing ones. Cached
> `*_lik_model_*.rds` / `*_lik_result_*.rds` still hold pre-fix values until the
> workflow re-runs `train_likelihood_model()` + `evaluate_likelihoods()`.

## 2. TaxaAssign `posterior_consensus()` — three new columns (SHIPPED, installed)

- **`consensus_confusion_risk`** — confusion risk rank-matched to `consensus_rank`,
  not to `primary_taxon`'s own rank (which is what `winner_own_rank_confusion_risk`
  reports). Differs from it on 72/606 real rows, so the rank-matching does real work.
- **`primary_n_plausible_competitors`** / **`consensus_n_plausible_competitors`** —
  how many locally-plausible RIVAL candidates actually competed. This is Axis 2's
  second half ("did it compete against any plausible candidates"), which no
  confusion-risk value can answer, because confusion risk describes the marker's
  discriminating power in the abstract and never sees the candidate set.

Design points worth not re-litigating:
- "Plausible" is read off **`model_tier`** (from `join_priors()`), *not* off
  `prior_mean`'s value — a never-reported taxon has `model_tier = NA` while a genuine
  singleton has a real tier, even at the same floor prior. This is exactly the
  Axis-1 "a singleton is not unprecedented" distinction, and `prior_mean` alone
  cannot express it. **No new data input, no new join, no network call.**
- Counted over **all named hypotheses** (pre-`min_posterior`) — a candidate that
  competed and lost still competed. Mirrors `consensus_posterior`'s own precedent.
- **The row's own taxon is excluded** (assistant's call, flag if wrong): whether the
  winner itself is plausible is Axis 1's job via `winner_prior`. So `0` means
  "nothing plausible to lose to", never "the winner is implausible".

Real full-dataset verification (616 obs, all 3 markers, **1.4 s** — negligible
PtConception overhead): 58% of observations won with zero plausible rivals. The
counts discriminate the anchors unprompted — ASV_371 (Salmonidae) and ASV_382
(Sciaenidae), both user-flagged as "why was no local congener proposed?", come back
with **0** plausible rivals, while the Gobiidae the user confirmed as fine
(ASV_363/430/463) each have 1. Cross-tab of Axis 2 tier x rival count surfaces a cell
a single column could not: 77 observations are `discriminating` **and** had 0 rivals —
looks clean, never actually competed. 9 new tests; `devtools::test()` 574 pass /
0 fail; `check()` 0/0/0.

## Thresholds / naming

`< 0.05` `discriminating` / `0.05–0.5` `weak` / `>= 0.5` `indistinguishable`. Both
breaks are interpretable statements about a genuine one-sided tail probability (not
fitted cutoffs), and both populate well across all three markers — 12S species
15/31/54%, 16S 14/44/42%, COI 33/9/58% — unlike `goodness_of_fit`'s 4-row top tier.
Polarity runs opposite to the old `probably_right` naming (here HIGH = worse).

## NOT done — next session picks up here

1. **The TaxaFlag categorical column is NOT built.** The names are approved but the
   choice was deliberately left open: which column drives it (`consensus_confusion_risk`
   vs `winner_own_rank_confusion_risk`), whether there are primary AND consensus
   versions, and whether it replaces the existing `confusion_risk_flag` (currently a
   single 0.5 threshold → `high`/`low`). User explicitly warned against column
   inflation, so this needed a decision rather than a guess.
2. **No workflow rewired.** No Mugu/PtConception script updated; nothing re-run. The
   new columns appear automatically once `posterior_consensus()` is next called, but
   the Jeffreys half needs a retrain (see the warning above).
3. **`goodness_of_fit` rename CANCELLED -- the column was RETIRED instead**
   (2026-07-28). An audit the user requested (to avoid column creep) found
   `absolute_fit_pvalue` ~78% redundant with the Axis 2 discrimination signal
   (R^2 = 0.78 against the post-fix confusion_risk), its only consumer firing on
   0/606 real observations, its proposed bottom tier holding 2/792 rows, and severe
   unnormalised marker dependence (median 12S 0.453 / 16S 0.462 / COI 0.032). Removed
   from all three packages. **A revival memory was written first**:
   `[[project_absolute_fit_pvalue_retired]]` -- read it before rebuilding anything
   here, it records what would justify bringing the concept back and two claims in
   THIS document that did not hold up on real data.
4. **FIXED 2026-07-28:** the vignette `R CMD check` failure. Root cause: check's
   "running R code from vignettes" step TANGLES via `knitr::purl()`, which honours
   `purl=`, not `eval=` -- so a documentation-only vignette still executed. All 9
   ecosystem vignettes with a global `eval = FALSE` gained `purl = FALSE`.
   `TaxaFlag/vignettes/quality-flagging.Rmd` deliberately excluded (no global
   `eval = FALSE`; it genuinely evaluates). TaxaLikely now passes a full check
   INCLUDING vignettes.
5. ***Urolophus/Urobatis halleri* synonym-join bug** saved to assistant memory as
   `[[project_urolophus_synonym_join_bug]]`, parked per the user.
