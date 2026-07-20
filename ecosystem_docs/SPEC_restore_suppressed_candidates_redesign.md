# Spec: `restore_suppressed_candidates()` redesign

Status: **IMPLEMENTED 2026-07-18** (Sonnet 5) -- `TaxaLikely::restore_suppressed_candidates()`
rewritten end to end against this document (`R/score_collapse.R` +
new `R/restore_hierarchy.R`; `.check_regional_overlap()` in
`R/regional_overlap.R` gained the `return_detail = TRUE` mode Level 4 needs).
`devtools::test()` 0 failures (893), `devtools::check()` 0/0/0. See
`TaxaLikely/CLAUDE.md`'s top session note for the full implementation record
and exactly which design decisions below were carried through as written.
Red flag 5 (accession provenance / tie-handling) and item 7 (generality
beyond the spot-checked genera/datasets) remain open, as this document always
flagged them to be. **Not done as part of this implementation pass:**
rolling the new signature out to any production workflow (PtConception 12S/
18S_2, both Mugu scripts) -- all four still call the pre-redesign signature
and need a deliberate follow-on session before being touched.

Design discussion resolved end to end -- Section 8 items 1-6 and 8-9
all [RESOLVED] (item 7, generality beyond the spot-checked genera/datasets, is
an ongoing caveat rather than a one-shot resolution), and Section 6's red flag
3 (Tier 2 lacked a percent-identity output, a real prerequisite for Section
3a's Level 4) is now also resolved. Follow-on from
`REENTRY_PROMPT_restore_suppressed_candidates_refresher.md`. This document
records the decisions reached and, explicitly, what's still open -- meant to be
re-enterable without re-deriving the reasoning.

---

## 1. Problem statement

`restore_suppressed_candidates()` (`TaxaLikely/R/score_collapse.R`) exists because
upstream pipeline rules (the 100%-identity rule being the main real case) drop
lower-scoring candidates before they ever reach TaxaLikely, hiding referenced
congeners that might have been real competitors. The function's job is to put
plausible competitors back in front of the likelihood/posterior machinery.

### Red flags found in the current implementation (full list, see chat history for detail)
1. `candidate_species_filter`, when supplied, silently zeroes out all restoration
   for an observation with no record -- conflates "no congeners exist" with
   "congeners exist but were filtered," and the latter is exactly the
   informative case for ambiguity detection.
2. The imputed score for a restored row (`anchor_score - delta`, flat constant)
   discards the real alignment/coverage evidence `.check_regional_overlap()`
   computes when it runs.
3. Tier 2's regional-overlap check verifies *position* overlap only (a coverage
   ratio) -- never percent identity -- so "close" can't actually be evaluated
   for a Tier-2-checked candidate, only "same region."
4. The Session 159 fix that decouples per-observation checking from the global
   suppression-rule verdict only applies when `check_regional_overlap = TRUE`;
   plain (non-regional) restoration is still exposed to the same
   never-detects-a-global-rule blind spot by default.
5. Minor: restored rows' `RESTORED_<accession>` provenance always cites the
   *first* reference row for that species, not necessarily the accession that
   passed the check; multi-way ties pick only one arbitrary anchor row for the
   regional-overlap position check.

Items 1 and 2 turned out to be the load-bearing ones and are what this redesign
addresses. Items 3 and 5 remain open (see Section 8).

---

## 2. Reframed purpose

The function's real job is not "restore candidates so more of them can
individually win." It's: **detect whether the anchor's apparent win is real or
an artifact of suppression** -- because if it isn't, the consensus mechanism
downstream (`TaxaAssign::posterior_consensus()`) should be able to back off from
a specific-species call to a coarser (genus/family) one, rather than reporting
false precision.

This splits into two genuinely different purposes, not one restoration list:

- **Purpose A -- competitiveness detection.** "How many candidates are close to
  the anchor? Is there real competition at all?" Prior-agnostic: a candidate
  counts here purely on the strength of its score, with no regard to whether
  local occurrence data supports it. This is the general "is the anchor's win
  margin real" question.

  **Regional-overlap verification, resolved:** Purpose A does NOT need a
  separate position-overlap check layered on top of the score-sourcing
  hierarchy (Section 3a) -- it inherits one for free, split along the same
  Level 0 boundary. Any candidate resolved via hierarchy levels 1-4 is
  position-safe by construction: `seq_matrix` only ever contains properly-sized,
  in-range barcode sequences (never a whole genome), so a high `p_match`
  between two `seq_matrix`-resident sequences already means they were aligned
  across the same genomic window at training time -- there is no "trivially
  overlaps everywhere" risk the way a mitogenome anchor has. The regional-
  overlap concern only bites exactly where Level 0 already fails (an
  off-window/mitogenome-only anchor), which is precisely where the hierarchy
  falls through to Tier 2/2b -- and there, the real regional-overlap check
  remains essential, unchanged from today's mechanism. No new cost, no new
  correctness gap.
- **Purpose B -- plausible candidate admission.** "Show me the locally plausible
  candidates, even ones that aren't especially close on score." A plausible
  congener already carries independent evidence (an occurrence prior), so it
  doesn't need to be nearly as close on raw score to be a genuine posterior
  competitor -- the prior does some of the work score-closeness would
  otherwise have to do alone.

  **Overlap between A and B, resolved:** the two purposes are not mutually
  exclusive and neither negates the other. Since Purpose B's gap is strictly
  wider than Purpose A's on the same metric, any candidate that is both
  locally plausible and clears the tight gap automatically clears the wide gap
  too -- it satisfies both simultaneously (tagged `"both"` per the admission-
  basis column, Section 2's Q6 resolution) rather than one purpose cancelling
  the other. Purpose A finding real competition elsewhere in the genus does
  NOT excuse skipping Purpose B for a different locally-plausible-but-not-
  tightly-competitive species -- the two purposes sweep different (only
  partially overlapping) candidate pools and each needs its own pass.
  Practical efficiency: for a candidate in both pools, the score only needs to
  be resolved once via the Section 3a hierarchy, then compared against both
  thresholds -- no duplicate work for the overlap.

### Why two different admission thresholds, not one
Initially proposed backwards (tight gap for full admission, loose gap for a
"just count them" bucket) and corrected during discussion: it's the reverse.

- **Purpose A uses a *tight* gap.** There's no prior information to lean on for
  this question -- it has to hold up on score evidence alone, so the bar should
  be strict.
- **Purpose B uses a *wider* gap.** Plausibility substitutes for some of the
  score margin a candidate would otherwise need; requiring the same tight bar
  here would defeat the reason plausible candidates deserve a look in the first
  place.

**Exact thresholds, resolved -- zero new tunable constants, both reuse
already-calibrated parameters rather than inventing raw percentage-point
cutoffs.** A fixed percentage-point gap can't be right for either purpose:
real data already showed natural score dispersion varies a lot by genus
(`Sebastes` congeners cluster ~97-100%; `Fundulus` congeners spread ~81-98%,
Section 5/5a) -- a threshold needs to be relative to the model's own
dispersion, not an absolute cutoff.

- **Purpose A's tight gap = the existing score-only outlier test**
  (`evaluate_likelihoods()`'s chi-squared test, `alpha = 0.001`, ~3.3 sigma,
  `R/evaluate.R` around line 404), applied to whether the candidate's
  hierarchy-derived score (Section 3a) is statistically indistinguishable from
  the anchor's own score relative to `global_sigma[1,1]` (or the
  species-specific sigma when available). Already validated, already
  calibrated, automatically adaptive per genus/marker -- no new number needed.
- **Purpose B's wide gap = no anchor-relative threshold at all,** just the
  existing `build_sequence_matrix()` `max_dist` floor (default 0.25, ~75%
  identity) as a basic sanity check that the candidate isn't some wildly
  unrelated sequence. Satisfied automatically by construction for any
  candidate resolved via hierarchy levels 1-3 (everything in `seq_matrix` is
  already within `max_dist` of something); only does real filtering work for
  Tier-2-resolved candidates, which aren't pre-filtered by `max_dist` at
  alignment time.

### Why both purposes produce ordinary hypothesis rows, not a side channel
Considered building Purpose A's output as a separate summary/count (e.g. "N
close-but-implausible congeners exist") rather than real hypothesis rows, to
save compute. Rejected once we established (`TaxaAssign/R/posterior_consensus.R`)
that `n_plausible`/`plausible_taxa`/`consensus_reason` are POST-posterior
quantities computed by `posterior_consensus()` from whatever hypothesis rows
survive with real posterior mass -- there is no pre-posterior "ambiguity"
concept anywhere in the pipeline today, and match objects only carry raw
candidate rows plus a suppression marker. Building a parallel summary would
mean teaching `posterior_consensus()` to read something new. Simpler and more
correct: let both Purpose A and Purpose B candidates flow through as ordinary
`hypothesis_type = "suppressed_candidate"` rows (admitted under whichever gap
applies), so they pass through `evaluate_likelihoods()` -> prior join ->
`compute_posterior()` exactly like everything else, and whatever `n_plausible`/
upranking logic already exists reflects them for free, correctly discounted by
their own (possibly very low) prior rather than by a hand-built count that
duplicates what the posterior stage already does properly.

This also resolves red flag 1 as a side effect: since Purpose A's admission
does not depend on `candidate_species_filter`/occurrence plausibility at all,
an observation can never again get *zero* signal just because a plausibility
filter emptied out the candidate list.

---

## 3. Compute-budget mechanism

Making Purpose A prior-agnostic reopens a real cost problem `candidate_species_filter`
existed to solve (a genus with 42+ congeners, checked against every anchor
sharing that genus, cost 2,361 alignment pairs / 15+ minutes pre-Session-159).
Resolved via two complementary mechanisms, both grounded in real data checks
(Section 5) rather than assumed:

### 3a. A cheap-to-expensive score-sourcing hierarchy (replaces the flat `delta` constant)
**Level 0 precheck, added after the Mugu/`Fundulus` check (Section 5a):** before
trying levels 1-3, check whether the *anchor's own species* has *any*
`seq_matrix` representation at all (as `id_x` or `id_y`, against anything, not
just this genus). When it doesn't -- confirmed real for `Fundulus lima`, whose
two accessions are both out-of-range mitogenomes that never entered
`build_sequence_matrix()`'s alignment -- levels 1-3 are all provably futile,
not just unlucky, and trying them sequentially wastes a lookup for nothing.
Route straight to Tier 2 (specifically Tier 2b, since the anchor itself lacks
usable reference content for a reference-vs-reference alignment) in this case.

Otherwise, try each level in order; stop at the first that resolves the
candidate. Only fall through to live Tier 2 alignment when none apply.

1. **Direct accession-pair `p_match`** (what Tier 1 does today) -- lookup in
   `seq_matrix` for the *specific* anchor accession vs. the *specific* candidate
   accession(s). Free (already computed at training time), narrowest coverage.
2. **Any-accession species-pair lookup** (new) -- check *any* reference
   accession of the anchor's species against *any* reference accession of the
   candidate species. Still a free `seq_matrix` lookup, just a broader accession
   set. Real-data check (Section 5) showed this alone can rescue a case where
   the specific accession Tier 1 checks today happens to be an unrepresentative
   outlier -- but Section 5a's `Citharichthys` check found this rescue is NOT
   universal: several real anchors showed zero improvement from level 2 over
   level 1, because the missing pairs were genuinely outside `max_dist`, not an
   artifact of which accession got picked.
3. **Genus-level typical divergence, model-preferred with a no-model fallback**
   (new -- resolved during continued discussion, corrects an ordering bug in
   an earlier draft of this hierarchy). This is one level with an internal
   preference, not two sequential ones: a raw genus-wide median and the
   trained model's own genus-specific estimate answer the *same* question
   (typical congener divergence for this genus) at different levels of rigor,
   so they should be tried as alternatives, not "try the raw version, only
   consult the model as a last resort" -- the raw median would resolve almost
   any genus with *some* cross-species data at all, meaning the model-based
   estimate would rarely ever get reached if ordered strictly after it.
   - **Preferred:** `model_params$H2_Lookup$delta_shrunk` -- the already
     Empirical-Bayes-shrunk, genus-specific congener-divergence estimate
     `train_likelihood_model()` computes (Session 151/158), used when
     `model_params` is supplied (new optional parameter on this function,
     default `NULL`, added specifically to reach this) and has an entry for
     the anchor's genus. Matters most for thin-data genera, where a raw
     median from only 1-2 pairs would be noisy; also keeps a restored
     `suppressed_candidate` row's imputed score consistent with the same
     genus-divergence estimate `evaluate_likelihoods()` already uses for that
     genus's H2 (`unreferenced_species`) rows, rather than two different ad
     hoc numbers for conceptually the same quantity.
   - **Fallback:** median `p_match` across all within-genus, cross-species
     pairs already present in `seq_matrix`, ignoring which two specific
     species are involved -- used when `model_params` is `NULL` or lacks an
     entry for this genus. Free, and covers candidates whose *specific*
     pairing was never retained in `seq_matrix` at all (distance exceeded
     `max_dist` for that specific pair, but not for the genus overall).
   Both require the anchor's species to have *some* `seq_matrix` presence at
   all -- see the Level 0 precheck above for when it doesn't.
4. **Live Tier 2 alignment** -- only when none of the above resolve the
   candidate, or immediately (skipping 1-3) when the Level 0 precheck fails.
   This is the expensive path the budget mechanism below exists to bound.
   **Score output, resolved (closes red flag 3):** `.check_regional_overlap()`
   already builds a `pwalign::pairwiseAlignment()` object to determine position
   overlap -- add `cached$pid <- pwalign::pid(aln)` (default `PID1` type,
   confirmed correct via a real test: `F. parvipinnis` vs. `F. lima`'s
   mitogenome gives 96.43% at the historically-documented position 319-486;
   `PID4`, which normalizes by the full length of the longer/anchor sequence
   rather than the aligned region, gives a meaningless 1.9% and would have been
   the wrong choice) alongside the existing `coverage`/`subj_start`/`subj_end`
   fields -- free, no extra alignment work, just reading a property of the
   alignment object that already exists. This `pid` value is what Level 4 hands
   back for a Tier-2-only-resolved candidate, on the same 0-100 scale
   `seq_matrix`'s `p_match` uses, median-aggregated (Section 4) across multiple
   accessions when more than one gets checked. The existing `coverage`-based
   position-overlap accept/reject decision is unchanged -- `pid` is additive,
   for scoring only, not a new acceptance gate. **Caveat, not a blocker:**
   `pwalign`'s local alignment is a different engine than `seq_matrix`'s
   DECIPHER-based MSA, and this codebase already found alignment-engine changes
   can shift score scale/location non-trivially (the `calibrate_query_noise()`
   train-vs-inference work). Not an active problem today since the hierarchy is
   sequential/exclusive (a candidate resolves via `seq_matrix` OR Tier 2, never
   both pooled) -- would matter if this hierarchy were ever restructured to
   pool across sources.

### 3b. Sizing the Tier 2 budget from the floor-vs-documented prior ratio, not a fixed cap
Because `posterior_consensus()`'s `min_posterior` filter (default 0.05) drops
any hypothesis below ~1/19th of total posterior mass, and posterior ~
likelihood x prior, a candidate's *prior* disadvantage alone can make it
mathematically impossible to ever surface in the consensus, regardless of what
score Tier 2 would find. Real data (Section 5) shows this ratio is highly
genus/grid-dependent (real range: ~0.018 to ~6107 within one grid cell) --
**there is no safe universal constant for how much budget implausible
candidates deserve.** Where the ratio is extreme, spending Tier 2 budget on an
implausible congener is pure waste (no realistic score could overcome that
prior gap); where the ratio is near parity, the same congener has a genuine
shot and deserves real budget. The mechanism should look up this ratio (cheaply
available from `taxaexpect_priors`) per genus/grid and size Tier 2 spend
accordingly, rather than applying one fixed cap (e.g. "check at most K
candidates") uniformly.

**Formula, derived (resolved during continued discussion):** since posterior
~ likelihood x prior, and `min_posterior = 0.05` drops anything below ~1/19 of
total posterior mass, an implausible candidate needs
`L_candidate/L_anchor >= (0.05/0.95) x R` to have any chance of surviving,
where `R = P_anchor/P_candidate` is the floor-vs-documented ratio. Bounding
`L_candidate/L_anchor <= 1` (a restored congener can be at best as good as the
anchor it's checked against -- a safe working assumption for a budget
heuristic, not a correctness gate) gives a clean, derived cutoff:
**`R <= 19` -> worth spending Tier 2 budget; `R > 19` -> mathematically
impossible to ever clear `min_posterior`, skip entirely, zero budget.**
Checked against the real 18 genus x grid ratios from Section 5: `Phalacrocorax`
(6107), `Pelecanus` (592), `Larus` (466), `Branta` (125), `Mergus` (123),
`Oncorhynchus` (83) all exceed 19 and get skipped; `Toxostoma` (0.18),
`Spatula` (0.018), `Anser` (1.75), `Morone`/`Urocyon` (1.0), `Aphelocoma`
(10.75), `Bucephala` (16.5) fall under it and get real budget -- a genuinely
selective triage on real data, not "check everything" or "check nothing."

**Fallback for the non-computable case, resolved -- checked empirically, not
guessed.** Checked in 3 real genera (Section 5/5a): only `Sebastes`
(PtConception) had a genus/grid combination with both an observed and an
undetected congener in `taxaexpect_priors` to form a ratio from. Neither
`Citharichthys` (PtConception) nor `Fundulus` (Mugu) had any usable comparison
pair. **This is common, not the exception, and it isn't a data gap.**
Comparing each genus's full `reference_df` species list against
`taxaexpect_priors`: only 3 of `Citharichthys`'s 8 referenced species were
ever proposed as a TaxaExpect candidate at all (5/8 = 63% never got so much as
a floor-prior row); for `Fundulus`, only 1 of 20 referenced species
(`F. parvipinnis`) appears in `taxaexpect_priors` at all -- **19/20 (95%) were
never proposed, including `F. lima` itself**, the real anchor from the
motivating case. `F. lima` is a Baja California/Gulf of California species
genuinely outside Mugu's range -- TaxaExpect's own occurrence-range model
correctly never generated a floor entry for it, which matches real biology,
not an artifact of sparse data. **Resolved default: treat "absent from
`taxaexpect_priors` entirely" the same as `R > 19` -- skip Tier 2 budget,
not a moderate/split-the-difference allocation.** Caveat, kept honest: this
leans on TaxaExpect's candidate generation actually being occurrence-informed
rather than narrow for some unrelated structural reason; if that assumption
fails for some deployment, this could occasionally skip a candidate that
deserved a look -- acceptable for a compute-budget heuristic (a missed extra
ambiguity signal, not a wrong answer), not acceptable if this default were
ever repurposed as a correctness gate.

---

## 4. Score aggregation: median, not max or random, when multiple values exist

When a candidate has more than one `p_match` value at whatever hierarchy level
resolved it (multiple accession pairs, multiple within-genus comparisons),
aggregate via **median**, not max and not a random pick.

**Reasoning:** `max` is a biased-upward statistic as sample size grows (an
order-statistic property) -- a species with more reference accessions gets more
draws, and thus a higher expected max, from the *identical* underlying
similarity distribution as a less-referenced species. Using max as the imputed
score would systematically reward well-referenced congeners for reasons
unrelated to true similarity to the anchor.

**Real-data check, now across 3 genera / 2 datasets (Section 5/5a) -- direction
and magnitude are NOT stable, so this is a principled-default claim, not an
empirically-large-effect claim.**

| Genus (dataset) | cor(n_accs, max) | cor(n_accs, median) | cor(n_accs, spread) | mean spread |
|---|---|---|---|---|
| `Sebastes` (PtConception, n=106) | 0.748 | 0.665 | 0.259 | ~0.0-0.14 pts, rising with accession count |
| `Citharichthys` (PtConception, n=3) | -0.866 | -0.866 | 1.00 | 0.001 pts (n too small to trust the correlation) |
| `Fundulus` (Mugu, n=9) | 0.186 | 0.249 | -0.145 | 0.012 pts |

The correlation between accession count and score flips sign and varies widely
in strength across genera -- it is not a stable, predictable effect size. What
*is* consistent: the (max - median) spread stays modest in absolute terms in
every genus checked so far (roughly 0.1-1.5 percentage points), and the
underlying mechanism for why max is upward-biased (an order-statistic
property: more draws from the same distribution raises the expected max
regardless of the true similarity) is general and never favors max being the
*more* correct choice. **Conclusion: prefer median as the principled default
for the imputed score, but don't claim the data shows a large, predictable
real-world effect -- it doesn't, consistently.**

**Existing precedent in this codebase** (found by grep, not assumed):
- `evaluate_likelihoods()` itself already medians multiple accession scores for
  one candidate taxon before anything else runs
  (`TaxaLikely/R/evaluate.R:139-154`, `p_med <- stats::median(p_norm, ...)`).
- `flag_reference_errors()` draws exactly the same self/foreign distinction:
  `median_self_match` (representative same-taxon similarity) vs.
  `max_foreign_match` (a conservative "how close could something unrelated get"
  bound) (`TaxaLikely/R/train.R:91-100`).

**Resulting rule:** median for the score actually imputed on a restored
hypothesis (needs to be a realistic, unbiased estimate, since it competes in a
real posterior computation); max is reserved specifically for the Purpose A
"is there any real competition" existence question, where a deliberately
optimistic/conservative bound is the *correct* bias (don't prematurely dismiss
possible ambiguity), not a mistake to correct.

---

## 5. Empirical grounding (real PtConception 12S data, this session)

All checks below ran against the real, current checkpoint files at
`~/My Drive/Rscripts/eDNA/PtConception/` (`PtConMifishSchulte_*.rds`) -- not
synthetic fixtures.

- **Floor-vs-documented prior ratio** (`PtConMifishSchulte_taxaexpect_priors.rds`,
  614 rows, one grid cell `Grid_33p1_m117p7`): across 18 genus x grid
  combinations with both an observed and an undetected congener, the ratio of
  `theta_mean` (observed / undetected) ranged from **0.018 to 6107**, median
  ~6.9 but heavily skewed. Two real cases (`Toxostoma`, `Spatula`) had the
  "undetected" congener with a *higher* floor prior than the "observed" one --
  `observed_in_habitat` reflects GBIF habitat-record presence, not eDNA
  detection, so this inversion is real, not a bug.
- **Tier 1 direct-accession coverage** (`Sebastes`, 107 species / 252 reference
  accessions, `PtConMifishSchulte_seq_matrix.rds` / `_reference_df.rds`): 4 of 5
  sampled anchor species resolved 103/106 congeners for free via direct
  accession-pair lookup; one anchor (`Sebastes thompsoni`) resolved only 7/106,
  traced to its first accession (`AB059558`, 1730bp) being a longer/
  differently-windowed fragment than the genus's typical ~387bp barcode length
  -- the same "Paralabrax footgun" cross-window comparability issue already
  documented in `TaxaLikely`'s Known Footguns, not a new problem.
- **Species-pair lookup rescue**: checking `thompsoni`'s other 3 reference
  accessions (it has 4 total) against the same 106 congeners resolved **106/106**
  for free -- the low coverage was an artifact of which single accession got
  picked, not a real data gap.
- **Best-vs-median**: see Section 4 above.

**Caveat, explicit (partially addressed by Section 5a below):** the above was
originally one genus (`Sebastes`) in one real dataset. Section 5a extends this
to two more genus/dataset combinations. Still not checked: other markers
(18S), other congener-rich genera, or a systematic sample rather than a
handful of spot checks. Treat the *mechanisms* as validated, the *exact
numbers* (e.g. "97% Tier 1 coverage is typical") as data points, not a general
constant -- Section 5a shows they vary a lot.

---

## 5a. Cross-validation against a second PtConception genus and Mugu

Checked the same battery (Tier 1 direct-accession vs. species-pair coverage,
best-vs-median, floor-vs-documented ratio) against `Citharichthys` (PtConception,
one of the recurring problem genera named in the original refresher reentry
prompt) and `Fundulus` (Mugu, `MuguWilderFish_blast_*_12S.rds` checkpoints --
the genus behind the *original* Session 159 motivating case). Results
meaningfully complicate the `Sebastes`-only picture and are folded into
Sections 3a, 3b, and 4 above; summarized here for reference.

**`Citharichthys` (23 accessions / 8 species):** species-pair lookup (hierarchy
level 2) provided **zero** additional coverage over direct accession-pair
lookup for every one of 5 sampled anchors (e.g. `minutus` 3/7 both ways,
`spilopterus` 7/7 both ways) -- the missing pairs are genuinely outside
`max_dist`, not an accession-pick artifact the way `Sebastes thompsoni` was.
Floor-vs-documented ratio not computable -- all 4 real `taxaexpect_priors`
entries for this genus are `observed_in_habitat = TRUE`, no undetected
congener to compare against.

**`Fundulus` (74 accessions / 20 species, Mugu):** mixed -- species-pair
rescue worked well for 3 of 5 sampled anchors (`diaphanus` 0/19->9/19,
`notatus` 3/19->9/19, `pulvereus` 0/19->9/19), did nothing for one
already-adequate anchor (`majalis`, 9/19 both ways), and **failed completely
for `Fundulus lima`** (0/19 both direct and species-pair) -- traced to both of
`lima`'s reference accessions being 16506bp complete mitogenomes with
`in_barcode_range = FALSE`, meaning `lima` has zero `seq_matrix`
representation against anything, not just against this genus. This is what
motivated the Level 0 precheck added to Section 3a. Floor-vs-documented ratio
also not computable here -- only one `Fundulus` entry exists in the whole Mugu
priors table (`F. parvipinnis`, `observed_in_habitat = TRUE`), no undetected
congener pair.

**Worked example, roles confirmed precisely (avoid the mix-up made mid-session):**
for the real `F. lima` / `F. parvipinnis` case, `F. lima` is the **anchor** --
already a real, winning `specific_candidate` row from TaxaMatch's own sequence
match, occurrence-*implausible* per TaxaExpect (a downstream prior-discounting
question, not something this function fixes). `F. parvipinnis` is the
**candidate under test for restoration** -- occurrence-*plausible*, a genus-mate
of the anchor in `reference_df`, but not currently a row in `match_obj` for
this observation. The restoration question is specifically about
`F. parvipinnis`: Tier 1 first (checked, confirmed absent for this anchor per
the Level 0 finding above), then Tier 2b (derive the query's real hit position
within `F. lima`'s mitogenome, then check whether `F. parvipinnis`'s own
reference overlaps that position) -- the existing, already-built Session 159
mechanism. This is the trigger condition for Purpose B specifically:
occurrence-plausible per prior, but absent from the current candidate set --
not a separate third category from Purpose B, just Purpose B's highest-value
case, since it's the one where getting the answer right can convert a generic
`unreferenced_species` placeholder into a real, specific, evidence-bearing
hypothesis.

## 5b. Alternative to runtime Tier 2: fix mitogenome-only anchors upstream

Prompted by recognizing that the entire Tier 2/2b mechanism was built
reactively around the `F. lima` case specifically -- worth asking whether a
different, upstream fix could remove the need for most of that runtime cost,
rather than only building more machinery to pay it more cheaply.

**Tested: does `TaxaLikely::trim_to_amplicon()` (Session 140, already built)
rescue `F. lima`'s real mitogenomes?** Result: **no, 0 of 2**, with either
`MiFishU` or `MiFishE` as the registered primer pair --
`"primers_not_found_or_implausible_span"` for both accessions. This is a
*different* failure mode than the documented `Sebastes` footgun
(`TaxaLikely/CLAUDE.md` Known Footguns), where the amplicon region was
genuinely absent because a broad `"12S"` search pulled in sequences from
unrelated primer sets. Direct `Biostrings::matchPattern()` search confirmed why:
the **reverse** MiFish-U primer matches `F. lima`'s mitogenome (`MW033979`)
**exactly** (0 mismatches, position 487-513, antisense strand) -- the true
amplicon region is genuinely present and correctly located. The **forward**
primer needs 5-6 mismatches out of 21bp (~24-29%) to match at all, well past
`trim_to_amplicon()`'s default 15% tolerance -- real, substantial sequence
divergence at that specific primer-binding site in this species, not an
absent region.

**Implication:** a single-primer-anchored extraction strategy (find whichever
primer matches confidently, infer the amplicon boundary using the registered
amplicon-length range rather than requiring both primers to match) would have
recovered `F. lima` as a normal, properly-sized, `seq_matrix`-eligible
reference -- computed *once*, upstream, at reference-building time, benefiting
every future anchor/genus check against this species with no runtime cost, and
giving `train_likelihood_model()` a real `H1_Lookup` entry for it. This is not
implemented -- `trim_to_amplicon()` currently requires both primers to clear
the mismatch tolerance. Real tradeoff: single-primer anchoring trusts the
known amplicon-length range rather than confirming both binding sites
independently, a weaker guarantee than a clean dual-primer match (though
arguably no weaker than what Tier 2b already does today, which also derives
position from one alignment with no independent confirmation).

**Separate, non-code finding worth flagging to whoever owns wet-lab protocol
decisions:** if `F. lima`'s real MiFish-U forward-primer site is this
divergent, a real eDNA survey using standard MiFish-U primers may have genuine
PCR amplification bias/dropout risk against this species, independent of
anything downstream in this pipeline.

**Prevalence check (resolves the "how much does this matter" question):**
counted species with a reference accession in `reference_df` but ZERO
representation anywhere in `seq_matrix` (the `F. lima` pattern) across both
full real datasets, not just the anchors spot-checked above.

| Dataset | Invisible species | Total referenced species | % | Length profile |
|---|---|---|---|---|
| PtConception 12S | 33 | 950 | 3.5% | all >2000bp |
| Mugu Wilder Fish 12S | 156 | 572 | **27.3%** | median 16,591bp -- unambiguously whole mitogenomes |

This is not a rare edge case, at least for Mugu -- over a quarter of its
referenced species are completely invisible to the free-tier hierarchy (levels
1-3), meaning every one of them requires the Level 0 precheck to correctly
route straight to Tier 2b rather than wasting a lookup.

**Resolved:** this redesign depends only on Tier 2b for this failure class,
which is already built and already validated for the real `F. lima` case. The
upstream single-primer-anchor extraction is explicitly OUT OF SCOPE for this
redesign, not just deferred -- one validated data point (`F. lima`) is not
enough to trust a confidently-wrong extraction risk (a bad single-primer
inference could silently inject a mis-positioned "amplicon" into training
data, corrupting `build_sequence_matrix()` for that species in a way that is
*less* visible than today's exclude-and-fall-back-to-Tier-2b behavior). Concrete
bar for revisiting it as a separate follow-on task: validate the
single-primer-anchor approach against a meaningful sample of the 156 real
invisible Mugu species (not just one), with independent position verification
(matching the empirical-cross-check discipline `TaxaTools`'s Session 141
primer additions used against real GenBank data), before it could supplement
or replace Tier 2b for any real anchor.

**Related, explicitly out-of-scope finding:** `audit_barcode_coverage()`
itself likely overstates true *usable* reference coverage for a dataset like
Mugu -- it counts a species as referenced if any GenBank accession exists,
with no check on whether that accession is actually barcode-length-appropriate
and thus usable by the scoring pipeline. For Mugu, roughly a quarter of what
that function would report as "referenced" is functionally invisible
downstream. Not something to fix inside this redesign; flagged here so it
isn't lost -- a natural fix would use the same `in_barcode_range` diagnostic
column `fetch_ncbi_reference_sequences(keep_out_of_range = TRUE)` already adds
(Session 159).

---

## 6. What this resolves vs. leaves open, relative to the original red flags

| # | Red flag | Status under this design |
|---|---|---|
| 1 | `candidate_species_filter` silently zeroes restoration | Resolved -- Purpose A no longer gated by plausibility at all |
| 2 | Imputed score ignores real alignment evidence | Resolved -- score-sourcing hierarchy (Section 3a) uses real `p_match`/`H2_Lookup` data, median-aggregated |
| 3 | Tier 2 checks position only, never identity | **Resolved.** `cached$pid <- pwalign::pid(aln)` added to `.check_regional_overlap()`'s Tier 2 result, free (reads a property of the alignment object already built for position overlap). Verified against the real `F. parvipinnis`/`F. lima` case (96.43% at the historically-documented position). See Section 3a Level 4 for the full resolution, including the `PID1` vs `PID4` choice and the noted-but-inactive alignment-engine-scale caveat. |
| 4 | Global-rule decoupling only applies under `check_regional_overlap=TRUE` | **Resolved as a side effect of the Purpose A/B redesign.** Purpose A sweeps every genus congener for every observation regardless of `detect_suppressed_candidates()`'s global verdict or `check_regional_overlap` -- that's inherent to being prior-agnostic, not a separate fix. The old blind spot (real data never clearing the global purity threshold, so the whole per-observation loop never ran) can't recur under a design that never gates on that verdict in the first place. |
| 5 | Restored-row accession provenance / single-anchor-row-among-ties | **Still open** -- not addressed this design pass |

---

## 7. Downstream mechanics referenced (for context, not changed by this design)

`TaxaAssign::posterior_consensus()` (`R/posterior_consensus.R`):
- `min_posterior` (default 0.05) drops any hypothesis below 5% of total named
  posterior mass, applied *before* anything else.
- `cumulative_threshold` (default 0.90) then keeps the smallest top-set of the
  remainder whose cumulative mass reaches 90%.
- Real sweep already on record (Session 2026-07-09, in the roxygen): `min_posterior`
  does the real work (+8.2 resolution points sweeping 0->0.20); `cumulative_threshold`
  barely matters (-3.3 points sweeping 0.70->0.99). This is why Section 3b sizes
  the Tier 2 budget off the prior ratio feeding `min_posterior`'s bar specifically,
  not off `cumulative_threshold`.
- `n_plausible`, `plausible_taxa`, `plausible_posteriors`, `consensus_reason`
  are all computed here, downstream of `compute_posterior()` -- confirmed there
  is no equivalent concept upstream in `match_obj`/`restore_suppressed_candidates()`
  today (only `hypothesis_type = "suppressed_candidate"` as a marker).

---

## 8. Open questions (explicitly unresolved -- confirm before implementing)

1. **[RESOLVED]** Exact numeric gap thresholds for Purpose A (tight) and
   Purpose B (wide). No new constants -- Purpose A reuses
   `evaluate_likelihoods()`'s existing score-only outlier test
   (`alpha = 0.001`); Purpose B reuses `build_sequence_matrix()`'s existing
   `max_dist` (0.25). See Section 2's "Why two different admission thresholds"
   for the full resolution.
2. **[RESOLVED]** Formula for translating the floor-vs-documented prior ratio
   into a Tier 2 budget, plus the non-computable-case default. Derived from
   `min_posterior = 0.05`: `R <= 19` -> worth checking, `R > 19` -> skip
   (mathematically impossible to clear `min_posterior` regardless of score).
   Non-computable case (absent from `taxaexpect_priors` entirely) treated the
   same as `R > 19` -- confirmed empirically to reflect real occurrence-range
   implausibility (95% of `Fundulus`'s referenced species, including
   `F. lima` itself, were never proposed as TaxaExpect candidates at all), not
   a data-completeness artifact. Full derivation and both real-data checks in
   Section 3b.
3. **[RESOLVED]** Does Purpose A's admission still need `check_regional_overlap`
   position verification? No separate check needed -- see the resolution note
   under Purpose A's definition in Section 2. It's inherited for free from the
   Level 0 boundary already in Section 3a: hierarchy-levels-1-4 candidates are
   position-safe by construction (`seq_matrix` can't contain an off-window
   pair); Level-0-failure candidates fall through to Tier 2/2b, where the real
   check already runs. Agreed during continued discussion.
4. **[RESOLVED]** Does `restore_suppressed_candidates()` need a new
   `model_params` parameter? Yes -- optional, default `NULL`, fully backward
   compatible. `model_params` is already in scope by this point in every real
   workflow (training happens once upfront), so this adds no new ordering
   requirement, just a new pass-through. Folded into a corrected, merged
   Section 3a level 3 (model-preferred with a no-model fallback, replacing the
   earlier draft's strictly-sequential 3-then-4, which had an ordering bug --
   see that section for detail).
5. **[RESOLVED]** Does `candidate_species_filter` still exist as a parameter?
   Yes, re-scoped: it defines Purpose B's "plausible" candidate set only (its
   original intent), and never gates Purpose A, which sweeps every genus
   congener regardless of this filter.
6. **[RESOLVED]** How are Purpose A vs. Purpose B rows distinguished in
   output? A new categorical column (working name `restoration_basis` or
   similar -- exact name not finalized), values along the lines of
   `"competitive_score"` / `"plausible_prior"` / `"both"`. A COLUMN, not an
   attribute -- this codebase already learned attributes don't survive
   `dplyr::left_join()` (see the Session 159 Mugu workflow note capturing
   `attr(match_restored, "regional_unreferenced")` before a join that would
   have silently dropped it). Mirrors the existing `h2_delta_source`
   short-categorical-value idiom. See Section 2's Purpose A/B definitions for
   the overlap ("both") semantics.
7. **Generality beyond `Sebastes`/PtConception 12S** -- partially addressed by
   Section 5a (`Citharichthys`/PtConception, `Fundulus`/Mugu), which found real
   genus-to-genus variation in every mechanism checked (species-pair rescue
   rate, floor-ratio computability, best-vs-median correlation). Not yet
   checked: other markers (18S), a systematic rather than spot-check sample.
8. **[RESOLVED]** Pursue the upstream single-primer-anchor `trim_to_amplicon()`
   extraction, or stay with runtime Tier 2b? This redesign depends only on
   Tier 2b (already built, already validated). The upstream fix is explicitly
   out of scope for this redesign, tracked as a separate follow-on task with a
   concrete validation bar (test against a meaningful sample of the real 156
   invisible Mugu species, with independent position verification, before
   trusting it for any real anchor). See the prevalence check and full
   reasoning in Section 5b.
9. **[RESOLVED]** Name/expose the genuinely-unreferenced vs.
   referenced-but-technically-invisible distinction. Locally in scope: the
   Q6 admission-basis column gains a value for this case (working name
   `"no_reference_data"`, exact naming still open) so a candidate that fails
   the Level 0 precheck and can't be resolved even via Tier 2 is
   distinguishable in output from a regionally-rejected or below-threshold
   candidate. The larger, related fix (`audit_barcode_coverage()` itself
   overstating usable coverage -- see Section 5b) is explicitly out of scope,
   flagged for a future session.

## 9. Implementation status (2026-07-18)
Function signature changes, implementation, and tests are now DONE -- see the
status note at the top of this document and `TaxaLikely/CLAUDE.md`'s top
session note for the full record. Still not started: rolling the new
signature out to any production workflow.
