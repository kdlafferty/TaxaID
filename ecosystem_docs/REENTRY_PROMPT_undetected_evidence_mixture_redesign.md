# REENTRY: Undetected-evidence mixture redesign (promotion-clamp fix + w-as-probability)

**Status (2026-08-28): ALL ITEMS IMPLEMENTED** on branch `undetected-evidence-mixture`
(commits 7b5b2c5 Phase 1, a2d3271 Phase 2 core, 88926f1 w-calibration, plus the
2026-08-28 remaining-items commit). Ledger:
- D1/D2 clamp scoping + anchor ladder: DONE, live-validated (33 -> 103 species obs).
- D3/D8 mixture semantics + presence-draw sampler + moment-matched n_eff: DONE;
  three-way column experiment run; point_est kept operative.
- D4 w semantics: DONE -- invasive w 0.6 -> 0.05 all 6 workflows; veto bound now
  PRINTED by apply_undetected_evidence(); the likelihood-side surveillance
  guarantee is TaxaFlag::flag_watch_candidates() (wired into GreatLakes 8i.5).
- D5 calibration: DONE via the checklist recipe (0/110 zero-positive bound ->
  w_scale = 0.05, held-out Lamar validated 74 -> 224 co-detections); the generic
  fitter now exists as TaxaExpect::fit_regional_presence_curve() (handles the
  zero-positive bounded case first-class).
- D6 iNat: DONE -- TaxaFetch::check_inat_range() gains a derived name_match
  column (fuzzy-misresolution gate, closes
  [[project_inat_range_backbone_mismatch_todo]]);
  TaxaExpect::generate_inat_range_evidence() feeds the shared applier (w = 0.8);
  TaxaAssign::adjust_inat_range_priors() name-gated (require_name_match = TRUE)
  and marked superseded for the mixture pathway; GreatLakes workflow Step 7a.7d.
- D7 soft confirmation: DONE -- update_prior_from_consensus() rewritten: every
  observation's posterior support aggregates as fractional presence evidence
  (soft EM vs classification EM, Celeux & Govaert 1992), leave-one-out,
  discounted by new `confirmation_discount` a0 = 0.25 (power prior, Ibrahim &
  Chen 2000, Stat Sci 15:46-60 -- VERIFIED citations, plus Dorazio & Erickson
  2018 MER 18:368-380 for the occupancy analog), saturating m/(1+m) move toward
  a support-weighted confirmation quantile; mixture rows update prior_mix_w
  itself (replaces the interim clearing rule); `min_confirmation_confidence`
  REMOVED (breaking) across pipelines/report/vignette/inst workflows; update is
  provably continuous (regression test sweeps the old 0.8 gate).
- D8 leftover: posterior_consensus() default posterior_col aligned to
  "posterior_point_est" (drift resolved).
- D9 domestic sanity: rows verified at design magnitudes (theta 4.8e-4, 5x
  floor, correctly ordered/un-promoted; 6 plausible-set appearances, never win);
  found + fixed: the workflow never passed domestic_taxa to
  add_posthoc_assessment(), so domestic_prior_caveat was silently inert --
  now wired from the priors table.
All four packages test 691/731/434/620 passed 0 failed (TaxaFetch's 2 = the
documented pre-existing CoordinateCleaner/terra environment failures), check
0/0/0 x4. Spans TaxaAssign, TaxaExpect, TaxaFlag, TaxaFetch.

**Origin:** the 2026-08-26 statistical review of GreatLakes2023 conservative upranking
(`GreatLakes data/REVIEW_fable_conservative_upranking.md`, ablation script
`REVIEW_uprank_ablation.R` in the same directory) followed by a multi-round design
discussion with the user. This doc is the implementation spec that discussion converged
on. Read the review first for the full evidence; the short version:

- `TaxaAssign::join_priors()`'s Session-117 "modelled-species floor" promotes **every**
  joined prior row below the singleton-mirror mean up to that mean
  (`has_model <- !is.na(result$alpha)`). Every `evidence_blend` row (and every
  `tier_domestic_food` row) sits below that mean by construction, so all of them are
  clamped to exact singleton parity (θ = 0.0192 in this dataset) regardless of weight.
  The graded `weight = exp(-d/150)` design never reaches the posterior.
- Verified: Ictaluridae example posteriors (0.488/0.355/0.149) are reproduced to 3
  decimals by pure normalized likelihoods — priors contributed nothing but admission.
- Ablation (4 scenarios, fixed seed, from saved checkpoints): dropping the 121 elevated
  rows moves species-resolved observations 33 → 210 (unique species 6 → 18); sweeping
  d_half 75 → 300 km changes **nothing** (byte-identical output — the decay parameters
  are inert in shipped code). 10/12 newly recovered species corroborated by the
  independent Lamar pipeline; suppressed species were yellow perch (78 obs, blocked by
  watch-listed zander), round goby (42, blocked by monkey goby), creek chub (19).
- The residual ~76% of upranks are honest 12S congener ambiguity (median top-candidate
  share 0.46) and survive any prior reconfiguration.

---

## Settled decisions (user verdicts, with rationale)

### D1. Promotion rule: scope by cause; keep promotion for the scoped rows
Restrict the modelled-species floor to rows where the habitat term is demonstrably the
culprit (e.g. `observed_in_habitat == FALSE`, or θ at another habitat in the same grid
exceeds the ceiling while the focal-habitat θ sits below it), AND exclude
`tier_undetected_evidence` / `tier_domestic_food` rows entirely (they encode their own
floor/ceiling; promotion defeats both designs). For the rows that remain in scope,
**keep promoting the mean** (to the D2 ceiling): the widen-instead-of-promote variant
only acts through the MC path, and the operative consensus column is
`posterior_point_est` (see D8) — widening alone would silently resurrect the original
Session-117 inversion. Widening stays a possible later refinement if the MC column ever
becomes operative. Partial pooling of the habitat effect was considered and REJECTED —
the user reports it was tried and shrinkage produced unreasonable out-of-habitat
predictions.

### D2. Ceiling anchor generalizes to a ladder (datasets without singletons)
The upper anchor = "detection rate of a species present but rare enough to have
plausibly escaped local detection." Estimate in descending preference:
1. mean over singleton-mirror rows (current; average over all of them, not one);
2. minimum θ among modelled species when no singletons exist (mild overestimate of the
   present-but-undetected rate — conservative in the safe direction);
3. ~1/(site effort) fallback when the modelled table is degenerate.
Fix `apply_undetected_evidence()`'s current no-singleton behavior (ceiling := floor,
elevation silently a no-op) to degrade down this ladder instead. Note the anchors are
**dataset-specific** (θ_singleton = 0.0192 and θ_floor = 9.6e-5 are Burns Harbor
values); w is the portable quantity.

### D3. w is P(locally present | evidence); n_eff is derived, not chosen
The linear blend `θ = floor + (ceiling − floor)·w` is exactly the mean of a presence
mixture: present w.p. p (θ ~ singleton-like distribution), absent w.p. 1−p (floor).
So **w = p** and linear blending is the principled form (an earlier geometric-blend
idea is withdrawn on this basis). Consequences:
- **n_eff by moment matching, no free parameter.** Mixture variance
  `Var = p·Var_ceiling + (1−p)·Var_floor + p(1−p)(θ_c − θ_f)^2`; match a Beta to
  (mean, Var) and α+β is determined. For this dataset's anchors it comes out ≈ 2 and
  stays O(1–3) across p — the presence-uncertainty term dominates. (The current
  n_eff ≈ 0.28 two-point Betas were an accidental approximation of the mixture's
  genuine bimodality; this formalizes it and removes the knob.)
- **Age enters as uncertainty about p**: p gets a distribution whose mean comes from
  distance and whose concentration decays with record age; marginal mean unchanged,
  marginal variance gains a Var(p) term. This preserves the original "age widens,
  never shifts" design decision and REPLACES the separate `age_half`→n_eff channel.
- `n_eff_base` is retired along with free n_eff.

### D4. Invasive watch: small user-owned probability + TaxaFlag surveillance guarantee
User's ordering criteria (all verified against the retention math, see Derivations):
tie likelihoods → native wins (outright vs common natives; invader sits at the
retention boundary vs singleton-level natives — outcome grades with the native's own
evidence, a desirable free property); invader with much-higher likelihood (a genuinely
distinct sequence; ratios of 10²–10⁴ occur) → can win; invader always beats
dark-diversity candidates (p·(θ_c/θ_f) ≈ 10× floor at p = 0.05).

The one criterion Bayes cannot honor — "a higher-scoring invader makes the candidate
set FOR SURE" (fails vs abundant natives at steep prior odds) — is satisfied instead by
a **likelihood-side TaxaFlag caveat**: fire whenever a watch-list species outscores the
consensus winner for an ASV, computed from scores alone, independent of posterior mass.
User verdict: "make the flag report for sure." This restores the original intent
(surveillance lives in TaxaFlag) and lets the posterior stay honest.

w for watch lists stays **user-supplied with defined semantics** ("your probability the
listed species is currently present locally") — no baked-in numbers; GLANSIS
establishment history is one example justification available for the Great Lakes test
case, NOT a package dependency (most datasets have no such database; some have no
invaders). The package should compute and print the dataset-specific veto bound at
call time ("with your anchors, w above X can suppress singleton-level natives at
likelihood parity"). Guidance number: the ordering constraint gives
w < (1/19)·(θ_min-observed/θ_ceiling)-scaled ≈ 0.05 at likelihood parity, relaxing to
~0.10–0.15 given the typical 2–3× likelihood edge a truly-present native has. The
current w = 0.6 is ~10× too strong by the user's own ordering criterion.

### D4/D5 CALIBRATION DONE (2026-08-26, GreatLakes2023) -- RESULTS
Calibration truth = the site's expert checklist
(`great_lakes_fish_species_expanded.csv`, 53 species; Lamar SEALED during
calibration so the subsequent check is genuine held-out validation). Finding:
**0 of 110** zero-bbox regional candidates (nearest external record 12-990 km)
and 0 of 223 censored candidates are on the checklist, at ANY distance --
while 44/53 checklist species have in-bbox GBIF records. So zero in-bbox
records is already near-conclusive evidence of local absence, and the raw
`exp(-d/150)` (w = 0.72 at 50 km) overstates presence by an order of
magnitude. Jeffreys 95% upper bounds: 0.107 (<=100 km bin), 0.027 (pooled).
Adopted PRIMARY config, declared a priori before any Lamar-facing output:
**regional w(d) = 0.05 * exp(-d/150)** (new `w_scale` param on
`generate_regional_proximity_evidence()`, default 1 with roxygen calibration
guidance; workflow sets 0.05) and **invasive w = 0.05** (all 6 workflows'
INVASIVE_WATCH_WEIGHT updated 0.6 -> 0.05). Sensitivity (internal only):
w0 = 0.02 -> 344 species obs / 19 unique; 0.05 -> 293/16 (perch + flathead
catfish resolve; the review's Ictaluridae example ends as P. olivaris at
species rank); 0.10 -> 220/15. Round goby resolves only at w0 = 0.02.

**HELD-OUT LAMAR VALIDATION (primary config, 103 matched samples,
REVIEW_formal_lamar_check.R / *_wcal.rds checkpoints):** sample-level species
co-detections **74 -> 224** (ours_only 22 -> 118, ext_only 1007 -> 857);
genus co-detections 504 -> 623; unique species TaxaID 16 / Lamar 61 /
intersection 11 (was 6/61/4). Tiered match of Lamar's 1,081 species calls:
species_exact 224, primary_taxon 339, candidate_list 186, genus/family-
consistent 331, **no_match 1** (Amia calva in one sample). Overconfidence
check: 0 -- TaxaID resolves at least one species in every sample where Lamar
does. Mechanism shift: ambiguous_rank_fallback 515 -> 205,
specific_species_agree 5 -> 112. TaxaID-only species (plausible, for review,
not obvious errors): Luxilus chrysocephalus, Oncorhynchus gorbuscha,
Aphredoderus sayanus, Esox americanus. Caveat: the checklist's provenance/
completeness is an assumption (53 species; a fuller list could raise the
bounds somewhat); the D5 leave-the-bbox-out GBIF regression remains the
package-generic aspiration -- with zero checklist positives the curve SHAPE
is unidentified here, only bounded.

### D5. Regional proximity: per-dataset self-calibrating distance curve
(ORIGINAL DESIGN, retained; the GreatLakes calibration above used the
checklist variant because the zero-positives result made a fitted curve
unidentifiable -- only bounded)
Fit P(present | distance-to-nearest-external-record) from the study's own regional
pool via a leave-the-bbox-out regression: species with in-bbox records are positives;
for every species compute distance to its nearest record OUTSIDE the bbox; regress
presence on distance (record age optionally as a second predictor). GBIF-only, works
for any taxon and geography — satisfies the generality requirement. The current
`exp(-d/150)` becomes the documented FALLBACK shape when the regional pool is too
small to fit, not the definition.

### D6. iNat becomes a third evidence generator (user verdict: yes)
Convert `TaxaAssign::adjust_inat_range_priors()`'s post-join binary elevation into
`generate_inat_range_evidence()` feeding `apply_undetected_evidence()`, so all three
channels share the anchors, moment-matched n_eff, and multi-source combination.
Placement: closer to singleton than to floor but at a "small disadvantage" —
w ≈ 0.7–0.85, the discount explicitly interpretable as P(the range call is actually
about this species), i.e. the citizen-misID / fuzzy-match risk.
**PREREQUISITE:** the check_inat_range() fuzzy-name-match bug
([[project_inat_range_backbone_mismatch_todo]], Gasterosteus gymnurus → aculeatus,
in_range=TRUE wrongly) moves from backlog to blocking — a misresolved name at
near-singleton weight is far more consequential than at the floor.

### D7. Confirmation update: soft aggregation replaces the hard rule (user: confirm)
The current two-pass rule (donor = any observation resolving to species X with
consensus_posterior ≥ 0.8; boost X's prior everywhere) is hard-assignment EM and
produces cliffs: in the baseline, zander holds ~12% in every perch observation, NO
observation clears 90% at pass 1, zero donors, no boost — one marginal candidate
suppresses 78 observations at once, and calibration sweeps show steps, not gradients.
Replace outright (package unreleased) with **soft aggregation + tempering exponent**:
every observation's posterior for X contributes fractionally to site-level presence;
a power exponent a ∈ [0,1] discounts correlated observations (same water/DNA pool —
the codebase already rejected naive noisy-OR across correlated confirmations once,
Session 149). The user's own "posterior to an exponent" proposal is the established
**power prior** (Ibrahim & Chen ~2000); soft-vs-hard assignment is standard EM vs
classification-EM (Celeux & Govaert ~1992); the principled endpoint this approximates
is multi-scale eDNA occupancy (Schmidt et al. 2013; Dorazio & Erickson,
eDNAoccupancy). **LITERATURE CHECK REQUIRED before these citations enter roxygen or
any manuscript — they were recalled from memory, not verified.** Also to decide at
implementation: default tempering exponent and whether/how to estimate it.

### D8. Mixture-aware Monte Carlo posterior — PURSUE (upgraded from back-of-list;
user verdict 2026-08-26: "key structural feature... close to publish time...
more concerned about robustness and defensibility than runtime")

**The column-inconsistency finding (checked, not recalled):** `posterior_consensus()`
defaults to `posterior_mean` (MC), but `run_bayesian_pipeline()` defaults to
`posterior_point_est` (R/run_bayesian_pipeline.R:150), and EVERY production workflow
(GreatLakes, both Mugu, all three PtConception) explicitly passes
`posterior_point_est`. No recorded rationale exists for the override anywhere in the
session notes — it is drift, not a decision. The soundness review even analyzed the MC
path as "the live winner path" based on the low-level default while the real runs
bypass it. Whatever this redesign decides must resolve that inconsistency explicitly.

**Why the CURRENT MC path cannot serve the mixture (verified in source,
`TaxaAssign/R/compute_posterior.R`):** the Session-149 J-shape guard fixes any row
with `prior_alpha <= 1` at `prior_mean` for all sims — which covers every evidence
row, current (alpha 0.0005–0.05) and moment-matched (alpha ~= 0.004) alike. Worse,
the present-state anchor itself (singleton mirror, Beta(0.038, 1.96)) is J-shaped, so
routing evidence rows through Beta sampling can never represent the presence
bimodality — the guard exists precisely because Beta *shape* is a bad carrier for it.
The principled resolution is to carry the mixture explicitly.

**Sampler spec (two-point presence mixture):** rows carrying mixture columns bypass
Beta sampling entirely. Per simulation: draw `z ~ Bernoulli(w)`; set
`theta = z * theta_present + (1-z) * theta_absent`. Two-point (fixed conditional
means) is deliberate for v1: moment matching showed the presence-uncertainty term
dominates the variance, and both conditional Betas are J-shaped (unsampleable) anyway;
giving the present state a proper distribution is a later refinement. Consistency:
`prior_mean = w*theta_present + (1-w)*theta_absent` is exactly the two-point mixture's
expectation, so the point path needs no change and the two paths agree in expectation
by construction. `confidence_score` (fraction of sims won) becomes directly
interpretable as "probability of winning across presence states." The J-guard is
UNCHANGED for non-mixture rows (its rationale stands for genuinely-tiny-theta modelled
rows).

**Schema:** `apply_undetected_evidence()` emits three new columns —
`prior_mix_w` (= the combined presence probability), `prior_mix_theta_present`
(= the D2 ceiling anchor), `prior_mix_theta_absent` (= the floor mean) — alongside the
existing moment-matched alpha/beta (which remain the point-path/summary
representation). `join_priors()` passes them through; `compute_posterior()` uses them
when present and non-NA. iNat and any future evidence generator inherit the same
columns via the shared applier (D6).

**Unification with D7:** for mixture rows, the soft confirmation update should adjust
`prior_mix_w` (presence probability) rather than the Beta parameters — cross-
observation confirmation IS evidence about presence, so the site-level presence
posterior updates w directly. This gives the package one coherent story: prior for an
unobserved-but-plausible species is a presence mixture; the consensus integrates over
presence; confirmation updates presence probability.

**EXPERIMENT RUN (2026-08-26, post-implementation) -- RESULT:** three arms on the
real GreatLakes2023 checkpoints, identical inputs/seed: A point_est 103 species obs
(12 unique, 9 in Lamar); B posterior_mean J-guarded 95 (10, 7); C posterior_mean
mixture-aware 93 (10, 8). The rebuild of the 121 evidence rows under the mixture
schema left every blend mean byte-identical (max delta 1.7e-18), confirming the
point path is untouched. Verdict: the operative-column choice is SECOND-ORDER
relative to w calibration -- at w = 0.6 a blocker draws full singleton parity in
60% of presence states (E[share] ~ 7%, still above the 5% retention floor), and
the MC arms resolve slightly fewer observations because integrating likelihood
uncertainty honestly flattens shares. Recommendation pending user verdict: keep
posterior_point_est operative (auditable, deterministic, best Lamar recall at
statistically indistinguishable precision), align posterior_consensus()'s default
to it, and revisit the column after Phase 2's w calibration (where blockers at
honest small w drop below retention in both paths anyway). The mixture sampler
stays in place regardless -- it is the defensible carrier for presence bimodality
and the Phase 3 soft update operates on prior_mix_w.

**Decision experiment (the original design, retained for reference):**
after Phase 1 + the mixture sampler land, run the ablation harness three ways —
`posterior_point_est`, current J-guarded `posterior_mean`, mixture-aware
`posterior_mean` — on GreatLakes. Predicted direction: uncertain-presence candidates
less obstructive at the 0.05 retention boundary; established species resolve more
often. If confirmed and the changed calls survive the Lamar/checklist sanity check,
make mixture-aware `posterior_mean` the operative column EVERYWHERE (package default,
`run_bayesian_pipeline()`, all six workflows — resolving the inconsistency above), and
keep `posterior_point_est` as the documented audit path (its exact
prior-x-likelihood decomposability is what made the 2026-08-26 review's diagnosis
possible — preserve that virtue in docs). MC cross-seed noise measured at 1/885
observations; runtime is a non-factor (posterior step is not the pipeline bottleneck).

### D9. Domestic-food rows: post-fix calibration sanity pass
They have never operated at design values (inert before the 2026-08-20 join fix,
clamped to 0.0192 after). Once D1 lands they drop to intended magnitudes
(e.g. Gadus morhua θ ≈ 5.7e-4) — verify those magnitudes still serve their purpose as
a small standalone task. They remain OUTSIDE apply_undetected_evidence() by design
(contamination-risk claim, not presence claim — documented in that function's roxygen).

---

## Key derivations (for the implementation and docs)

- **Retention inequality** (min_posterior = 0.05): an elevated candidate stays in the
  plausible set against a competitor when
  `θ_e ≥ (0.05/0.95) · θ_comp · (l_comp/l_e)`. Win (cumulative_threshold = 0.90)
  requires ≈ 9× the summed likelihood-×-prior of everything else. With prior parity
  (the clamp), resolution demands 9–19:1 likelihood ratios; real 12S congener ratios
  run 1.4–3.3:1 — upranking guaranteed. This inequality is also the basis of D4's
  printable veto bound.
- **Moment matching** (D3): m = p·θ_c + (1−p)·θ_f;
  `v = p·Var_c + (1−p)·Var_f + p(1−p)(θ_c−θ_f)²`; `n_eff = m(1−m)/v − 1`;
  α = m·n_eff, β = (1−m)·n_eff. With Var(p) (age): add `E[..]` over p's distribution —
  mean unchanged, v gains `Var(p)·(θ_c−θ_f)²`.
- **Anchors, this dataset:** θ_floor = 9.6e-5 (Beta(1, 1.042e4)); θ_ceiling = 0.01923
  (single singleton mirror, ESS 2 — hence D2's averaging/ladder).

## Implementation phases

1. **Phase 1 — clamp scope + anchors (TaxaAssign::join_priors, TaxaExpect::
   apply_undetected_evidence):** D1 + D2. Regression test: re-run
   `REVIEW_uprank_ablation.R`'s d_half sweep — it currently returns byte-identical
   output and MUST stop doing so; expected post-fix behavior lies near the ablated pole
   (order 150–210 species-resolved observations, subject to Phase-2 w values).
2. **Phase 2 — mixture semantics + mixture-aware sampler (TaxaExpect + TaxaAssign):**
   D3 (moment-matched n_eff, age→Var(p), retire n_eff_base/age_half-as-n_eff-channel),
   D8's schema + sampler (`apply_undetected_evidence()` mixture columns →
   `join_priors()` pass-through → `compute_posterior()` presence draw), then D8's
   three-way decision experiment on the ablation harness, then D5 (distance-curve fit
   + fallback), D6 (iNat generator; fuzzy-match TODO first), D4's w semantics +
   printed veto bound. Resolve the posterior_col default inconsistency per the
   experiment's outcome.
3. **Phase 3 — TaxaFlag surveillance caveat (D4) + soft confirmation update (D7,
   after the literature check; for mixture rows the update operates on prior_mix_w)
   + D9.**

Each phase: devtools::test()/check() clean on touched packages, reinstall via
install_all.R, and the standard restart/install/un-cache/library block
([[feedback_restart_install_cache_library_checklist]]). The GreatLakes workflow's
cached `*_taxaexpect_priors.rds` / downstream checkpoints are STALE after Phase 1+ —
say so explicitly in re-run instructions.
