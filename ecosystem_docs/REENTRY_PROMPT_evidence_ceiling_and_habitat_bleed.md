# REENTRY: Evidence-blend ceiling (Task 2) + cross-habitat DNA bleed — DESIGN DISCUSSION, NOT YET DECIDED

Written 2026-08-30 (Fable 5), at the user's request, after one context compaction —
the fine-grained history lives in
`REENTRY_PROMPT_undetected_evidence_mixture_redesign.md` (the D1–D9 ledger; all
implemented) and the memory file `project_uprank_review_mixture_redesign.md`. This
doc holds ONLY the two still-open design questions, so a fresh session can pick
them up without re-deriving anything.

**The user's standing requirement for both questions (their words):** "These rules
are tricky and I want to be sure that they are grounded, defensible, simple and
not ad hoc." Do not ship either change without an explicit user verdict. The user
also said habitat bleed "seems like a parallel issue... and I think it is simpler"
— consider taking Question B first.

> **READ FIRST, 2026-08-30 (late session): the FOCAL-GRID BUG section at the
> bottom of this doc supersedes much of the framing below.** Every PtCon 12S
> number in this doc (nigricans 3.7e-5, singleton mean 7.4e-4, floor 7.1e-7,
> the Girella parity anomaly itself) was computed against priors evaluated at
> a San Diego grid cell 292 km from the site, selected by an alphabetical
> tie-break bug. The bug is fixed (workflows edited, not yet re-run); Question
> A's anomaly may substantially dissolve on re-run. Also read the
> "GENERAL PRIOR-SETTING FRAMEWORK" section — a full design conversation
> (2026-08-30) that reframes Questions A and B inside one budgeted structure.

---

## Question A ("Task 2"): should the evidence-blend ceiling be bounded by observed species' priors?

### How it works TODAY (implemented, on branch undetected-evidence-mixture)

`TaxaExpect::apply_undetected_evidence()` elevates a zero-in-bbox candidate
(regional-proximity / invasive-watch / iNat evidence) to

    theta_e = floor + w * (ceiling - floor)

- `floor` = the dataset's dark-diversity global floor.
- `ceiling` = the **singleton-mirror mean** — "the detection rate of a species
  present but rare enough to have plausibly been detected only once." For
  datasets with no singletons, the D2 anchor ladder substitutes: min modelled
  theta → 1/(median n_obs + 1) → floor + warning.
- `w` = P(locally present | evidence). Calibrated: regional `w_scale = 0.05`
  (GreatLakes checklist, 0/110 zero-bbox candidates present), invasive w = 0.05,
  iNat w = 0.8 (name-gated). Mixture columns
  (`prior_mix_w`/`_theta_present`/`_theta_absent`/`_p_conc`) carry the full
  presence-mixture; `posterior_point_est` (the operative column) sees only the
  blended mean.

**Nothing in this bounds theta_e by what OBSERVED species' fitted priors look
like.** Observed (tier1/tier2) species get model-fitted theta that can range far
BELOW the singleton mean — which is how the anomaly arises.

### The observed anomaly (real PtCon numbers)

*Girella simplicidens* (zero local records, Gulf-of-California endemic, watch
evidence w = 0.05): theta_e = 7.1e-7 + 0.05·(7.4e-4 − 7.1e-7) ≈ **3.7e-5**.
*Girella nigricans* (genuinely observed, tier1-fitted): theta ≈ **3.7e-5**.
Parity between a never-observed candidate and a real local species. (nigricans
survives on likelihood + the watch flag fires 7x on simplicidens, so no wrong
calls — but the user finds the prior ordering indefensible.)

### The user's proposal

"The interval for placing zero-box candidates should not include in-box
candidates... redefine the top of the interval to the minimum prior for an
observed in-box species." I.e. an ordering axiom: every unobserved candidate
sits strictly below every observed species.

### Why the LITERAL minimum is degenerate (computed 2026-08-29, real priors tables)

| | GreatLakes | PtCon |
|---|---|---|
| dark floor | 1.7e-4 | 7.1e-7 |
| singleton mean (current ceiling) | 0.0147 | 7.4e-4 |
| min observed-in-habitat modelled theta | **1.16e-4 — BELOW the floor** | **1e-6 — exactly the theta_epsilon clip** |
| q10 observed-in-habitat theta | 1.0e-3 | 7.7e-6 |

- GreatLakes: raw min < floor → the interval inverts (ceiling below floor).
- PtCon: raw min is the model's own epsilon-clip cluster (~5–10% of modelled
  rows sit at exactly 1e-6, e.g. an island scrub-jay's marine-eDNA share) → the
  interval collapses to ~zero width and w stops doing anything.

So the empirical minimum measures the model's clipping, not "the rarest
genuinely observed species."

### Fable's counterproposal (NOT implemented, awaiting verdict)

    ceiling = min(singleton_mean, quantile(observed-in-habitat modelled theta, ceiling_quantile))

with `ceiling_quantile = 0.10` exposed as a parameter (0 = strict min), and a
guard: if the anchor lands at/below the floor, fall back to the singleton-only
ceiling. Effects: PtCon ceiling 7.4e-4 → 7.7e-6 (simplicidens lands ~35x below
nigricans); GreatLakes ceiling 0.0147 → 1.0e-3 (elevated species drop ~4x —
directionally what the Lamar w-sweep favored). Veto-bound printer,
moment-matching, and mixture columns all recompute automatically.

### Open questions to settle BEFORE implementing (the "grounded, not ad hoc" test)

1. **Is the ordering axiom itself right?** The mixture semantics already encode
   presence uncertainty (theta_e is an *expectation over presence*, and the
   posterior_mean MC path + prior_mix_* columns distinguish simplicidens from
   nigricans even at point-estimate parity). Is bending the ceiling double-
   counting what w already encodes? Counter-argument: the GreatLakes calibration
   showed zero-in-bbox is near-conclusive absence evidence, and lower elevated
   priors validated better on Lamar — the axiom has empirical support.
2. **Is a quantile defensible or just a new magic number?** Alternatives
   considered: exclude exact-theta_epsilon rows from the min (fails: at PtCon
   epsilon=1e-6 > floor=7.1e-7, so a ">floor" filter doesn't remove them; an
   "==epsilon" filter needs theta_epsilon plumbed into the priors table —
   actually maybe the cleanest fix: emit theta_epsilon as an attribute of
   generate_full_priors() output and filter clipped rows exactly).
3. **The scale mismatch may be the REAL problem.** nigricans (detected ≥5
   times, tier1) fits at 3.7e-5 — **20x below the singleton-mirror mean**
   (7.4e-4). A multiply-detected species sitting far below the "detected once"
   anchor means the fitted-tier scale and the mirror scale don't line up at
   this site (grid-scoped, habitat-conditional fitting vs. the mirrors' global
   construction). The user was "surprised it is so rare." Understand this
   before bending the ceiling around it — the anomaly may be an anchor-scale
   artifact, not an ordering flaw.
4. If implemented: GreatLakes changes too → re-run the Lamar held-out check
   (REVIEW_formal_lamar_check.R, GreatLakes data dir) before trusting it.

---

## Question B: cross-habitat DNA bleed (the user's 2026-08-29 question — likely simpler, maybe first)

### The user's framing

"Given the bleed of DNA across habitats, I have to wonder if we are being too
restrictive for the habitat prior WRT DNA vs an organism. We might want a way to
allow cross-habitat contamination. This could be a user-setting. E.g., how much
should we discount a species in the wrong habitat?"

### What exists TODAY

`TaxaAssign::join_priors()`'s scoped Session-117 promotion, clause (b) of the D1
fix: a modelled row with `observed_in_habitat == FALSE` (habitat mismatch) is
**promoted to singleton parity**. This IS a cross-habitat bleed allowance — but
binary, and its magnitude ("all the way to singleton") is arbitrary. It is how
Sus scrofa won 28 PtCon observations: 98 terrestrial records → tier1 modelled →
Marine collapse to 1e-6 → promotion to 6.4e-4.

### The proposal on the table (Fable's, NOT implemented)

The presence-mixture pointed the other way. A zero-bbox candidate is *uncertain
presence x normal rate* (w = P(present)). A wrong-habitat species with real
records is the mirror: **certain presence x discounted transport rate**:

    theta_bleed = cross_habitat_weight * theta_home_habitat   (capped at the singleton ceiling?)

- `cross_habitat_weight` a user setting (site-specific: this beach has a creek
  + tides moving terrestrial/freshwater DNA into marine samples; an offshore
  station wouldn't). Scalar first; a habitat-pair matrix later if needed
  (freshwater→marine at a creek mouth > terrestrial→marine).
- Would SUPERSEDE join_priors' promotion clause (b) — retiring the last
  arbitrary clamp in the system.
- Natural home: a TaxaExpect-side step adjusting collapsed wrong-habitat rows
  before the join (keeps join_priors a pure join).

### Open questions

1. **What is theta_home_habitat concretely?** Does the priors table actually
   carry a fitted row for Sus in a terrestrial habitat category at that grid
   (the model fits per grid x habitat combos of the survey's habitat scheme)?
   If the home-habitat row doesn't exist, what anchors the rate — max theta
   across that species' habitat rows? Verify against the real
   PtConMifishSchulte_taxaexpect_priors.rds before designing further.
2. **Default + calibration path.** w_scale got calibrated against a checklist;
   cross_habitat_weight could be calibrated from the data itself (e.g. the
   observed read share of KNOWN-terrestrial taxa in the marine samples — pigs,
   coyotes, chicken, human are direct measurements of the transport rate).
   That would make it grounded rather than a hand-set 0.1.
3. **Relationship to Question A:** parallel, not identical. Bleed covers
   locally-OBSERVED species in the wrong habitat (presence certain); Question A
   covers NEVER-observed candidates (presence uncertain). Ordering interaction
   is coherent: bleed species may legitimately sit above the observed-in-habitat
   minimum (they ARE locally observed).
4. Interaction with Task 1's `domestic_caveat_type = "local_records"` label
   (shipped): the flag names the allochthonous hypothesis; the bleed weight
   would make the PRIOR honest about it. Both can coexist.

### Empirical findings (2026-08-30, Fable 5 — real PtCon data, all numbers computed, not recalled)

All from `PtConMifishSchulte_taxaexpect_priors.rds` /
`_consensus_final.rds` / `_contaminant_flags.rds` (field_rate = per-ESV
reads-weighted share of field reads) / `_occurrences_clean.rds` (1,809,363
records, habitat-labelled).

**Q1 answered — no fitted home-habitat row exists, and no anchor is needed.**
The priors table's `main_habitat` is Marine-only (766 rows) + NA (10
habitat-agnostic domestic rows): the model fits only the SURVEYED habitats,
and this survey is single-habitat. The occurrence data itself IS
habitat-labelled (Terrestrial 116,266 / Freshwater 35,610 / Estuarine 815
records; all 98 Sus records Terrestrial), so a home-habitat occurrence SHARE
is computable — but it should not be used, because:

**The proportionality assumption of `theta_bleed = w * theta_home` FAILS on
real data.** Across the 10 realized non-marine winners, home-habitat
occurrence share vs. realized bleed: Spearman 0.35 against read share, ~0.0
against ESV count. Killer counterexamples both directions: *Cathartes aura*
(turkey vulture) has the LARGEST home share (6,410 records, 5.5e-2 of
terrestrial records) and nearly the smallest bleed signal (2.2e-7 read
share, 1 ESV); *Canis lupus* has ONE occurrence record (8.6e-6) and the
3rd-most bleed ESVs (18). Occurrence share measures human reporting effort
(birds over-reported, feral/domestic mammals under-reported), not DNA flux
into creeks. The `w * theta_home` form would order the bleed priors
backwards — do not build it.

**Q2 answered — the bleed rate is directly measurable, two ways, and they
cohere:**
- Aggregate read share of the marine field samples: known-terrestrial
  winners 4.4e-4, freshwater 2.3e-4, estuarine 6.5e-5 (marine 0.689).
  Top: Sus 3.3e-4 (28 ESVs), Gasterosteus 1.7e-4, Bison 6.1e-5,
  Ictalurus 5.1e-5, Cervus 3.5e-5, Canis 1.8e-5.
- Realized transport fraction: of the 145 named tier1/tier2 modelled
  candidates with `observed_in_habitat == FALSE`, **7 appeared as resolved
  winners → w_bleed ≈ 0.048** (Sus, Bison, Ictalurus, Cervus, Canis,
  Neotoma bryanti, Capra). Same estimator form as w_scale's checklist
  calibration — and numerically indistinguishable from the independently
  calibrated regional/invasive w = 0.05.
- Per-home-habitat split: terrestrial 6/103 (0.058), freshwater 1/38
  (0.026), estuarine 0/4 — not distinguishable at these n. A SCALAR
  suffices; the habitat-pair matrix is not yet earned by data.

**Revised proposal (supersedes the theta_home form above):** habitat bleed
is the same presence-mixture as the shared applier, with the roles flipped —
organism presence certain, DNA-transport the Bernoulli event:

    theta_bleed = floor + w_bleed * (ceiling - floor),  w_bleed = P(DNA transported | locally present in wrong habitat)

with w_bleed calibrated per-dataset as the realized fraction (0.048 at
PtCon) and the singleton-mirror mean as the conditional-on-transported rate
(realized observation shares of the 7 actual bleed species: 7.4e-5 to
2.1e-3, median ~1e-4 — the ceiling 7.4e-4 is the right order). At PtCon this
gives theta_bleed ≈ 3.6e-5: Sus drops ~18x from today's promoted 6.4e-4.
Today's system is effectively **w_bleed = 1** — overstated ~20x per the
measurement. Natural implementation: a fourth evidence generator feeding
`apply_undetected_evidence()` (mixture columns carry P(transported)), with
the applier's already-modelled exclusion adjusted for this source (these
species ARE modelled — modelled-but-collapsed is the trigger, not absence).

**Two mechanisms must be superseded together or the fix is incomplete:**
(a) `join_priors()` clause (b)'s promotion (covers the 40 tier1
epsilon-collapsed wrong-habitat rows, 39 at exactly 1e-6); (b) a
TaxaExpect-side mechanism not yet traced that already writes the 105 tier2
wrong-habitat rows at EXACTLY the singleton mean (7.4155e-4) into the priors
table itself — singleton parity reaches wrong-habitat species by two routes
today, only one of them via join_priors.

**Still open before shipping:**
1. Trace the tier2-at-singleton-parity mechanism in TaxaExpect (above).
2. Circularity check: the 7 winners were resolved UNDER today's
   singleton-parity priors; if bleed priors drop ~20x, re-run and confirm
   the calibration is stable (expected yes — the Sus autopsy showed these
   calls are likelihood-dominant, and the watch/caveat flags stay).
3. Cross-validate w_bleed on GreatLakes (terrestrial-into-freshwater
   candidates exist there) before trusting 0.05 as a shipped default.
4. Ordering note for Question A: at w ≈ 0.05 both mechanisms land at the
   same theta (~3.6e-5) — bleed species (presence certain) sit at parity
   with, not above, regional-evidence never-observed candidates. The
   point-estimate parity is a coincidence of two independent measurements
   both giving ~0.05, not a design axiom; the mixture columns still
   distinguish the cases (w means P(transported) vs P(present)). Decide
   whether that parity is acceptable or whether presence-certainty should
   buy bleed species anything at point-estimate level.

---

## Status ledger (what is DONE vs pending, as of 2026-08-30)

DONE, shipped, verified:
- **Task 1**: `TaxaFlag::add_posthoc_assessment()` gains `domestic_caveat_type`
  ("no_local_records" = classic food-contamination reading /
  "local_records" = allochthonous-transport hypothesis live, e.g. Sus, beach
  dogs/coyotes as Canis lupus). 443 tests/0 fail, check 0/0/0, reinstalled.
  User must re-run the add_posthoc_assessment() step on the PtCon consensus to
  see the column (expect Sus's 28 rows = "local_records").
- **Task 3**: GreatLakes Step 7a.6 match-candidate accession screen ported to
  `PtConceptionWorkflow_12S_single_site.R` (new Step 7a.10; cache_dir reuses
  ptcon_ref_eval_cache, which already holds MN883227) and
  `MuguFishWorkflow.R` (inside .build_scored_likelihoods(), per marker, shared
  mugu_ref_eval_cache). Both parse; NEITHER HAS BEEN RUN — first run is the
  expensive one (~995 accessions PtCon ≈ overnight at ~1 min/accession NCBI
  pace; Mugu ~226/marker). Needs ENTREZ_KEY set. Screening targets already
  flagged by the review: Paralabrax auroguttatus (24 calls, suspected
  luciae-class), Rimicola muscarum (81), the Canis accessions
  (dog/coyote/wolf resolution — 12S likely can't separate them; the calls are
  probably real beach canids either way).
- Earlier same thread: full mixture redesign D1–D9 (see its own reentry doc),
  Mugu + PtCon 12S workflow runs, Sus autopsy, MN883227 verdict
  (insufficient_independent_evidence; Stoeckle unpublished mid-Atlantic eDNA
  library, isolate MM47).

PENDING (beyond Questions A/B):
- The deferred "deeper statistics look" at the PtCon review output: the
  1,873 species-resolved-but-unexpected block; 72 unprecedented (Platygobio 17,
  Bubalus 9, neon tetra 6); P. auroguttatus / Rimicola / Canis clusters — the
  new Step 7a.10 screen is the first tool to run at them.
- Task 3 follow-ups not yet ported: PtCon 12S multi-site + 18S_2 workflows
  (same block, trivial once single-site verified); optionally GreatLakes Step
  7a.8's training-side verify_flagged_references() analog.

---

## FOCAL-GRID BUG (found + fixed 2026-08-30, NOT YET RE-RUN) — supersedes much of the above

**The bug.** `SITE_GRID_ID` ("focal grid" for prior generation) was derived as
the "most-represented grid_id at the focal habitat" via
`count(grid_id) |> slice_max(n, with_ties = FALSE)`. On a
`prepare_model_dataframe()` frame this is degenerate: the frame is zero-filled
(every taxon x grid combo present), so `count(grid_id)` is a constant — at PtCon
12S, all 19 grids tie at exactly 652 — and `slice_max(with_ties = FALSE)`
silently returns the **alphabetically first** grid id. For PtCon that is
`Grid_32p8_m117p6`: a **San Diego cell 292 km from the site**, across the Point
Conception biogeographic boundary, with 1,566 marine records vs the true site
cell's 50,659. Verified by direct reproduction (rebuild model_data, watch the
19-way tie, watch slice_max pick alphabetically). Every PtCon 12S
posterior/consensus ever produced used priors evaluated at that wrong cell.

**Origin** (answers "why did we do this"): the pattern was introduced to fix a
real problem — hardcoded grid ids go stale when `grid_size` is re-optimized —
and TaxaExpect's own shipped tutorial
(`inst/workflows/generate_priors_workflow.R`) actively RECOMMENDED
"most-frequent grid_id" as the remedy in a KNOWN FOOTGUN comment. Right
diagnosis (never hardcode), wrong invariant (representation instead of
location). Both Mugu workflows and the 18S_2 workflow had already independently
adopted the correct nearest-to-study-coordinates pattern; the master template
(`TaxaID_Workflow_Template_TEST.R`, `.resolve_group_grid_id()`) has the best
version (exact cell from coordinates + explicit fallback).

**Consequences beyond the Girella anomaly:**
- Question A's motivating numbers are artifacts: *G. nigricans* has **0 records
  in the wrong cell** (its 3.7e-5 was interpolation into a cell where it was
  never recorded) but **500 records in the true site cell** (raw share 8.3e-3).
  The "multiply-detected species 20x below the singleton mean" scale-mismatch
  (open question A3) likely dissolves on re-run. Re-measure before bending any
  ceiling.
- The singleton mean / floor / all Question B calibrations shift: true cell has
  n = 60,443 marine records (1/n = 1.65e-5 vs the wrong cell's 6.4e-4), f1 = 39,
  f2 = 13, Chao1 ~ 59 missing species, Good-Turing missing mass 6.45e-4.
- **GreatLakes had the same bug** (`GreatLakes2023_ConsensusWorkflow.R:647`),
  so the Lamar held-out validation, w_scale = 0.05 calibration, and the
  soft-confirmation comparison were all computed against priors at an arbitrary
  Lentic cell. They need re-validation after a GreatLakes re-run.
- At the TRUE PtCon cell even Sus has 0 in-cell records (its 98 are elsewhere
  in the region) — the bleed design needs an explicit "local" radius
  (watershed-scale), not strict in-cell membership.

**Survey verdicts (agent, all workflows):** BUGGY and now FIXED:
PtCon 12S single-site (:519), PtCon 12S multi-site (:669, byte-identical),
GreatLakes2023_ConsensusWorkflow.R (:647),
TaxaExpect/inst/workflows/generate_priors_workflow.R (:571 + the footgun
comment that recommended the pattern; tutorial gains SITE_LAT/SITE_LON config),
TaxaAssign/inst/workflows/camera_trap_posterior_workflow.R (:361). Already
CORRECT: MuguFishWorkflow.R, MuguWilderFishWorkflow.R, 18S_2 (its dead
hardcode at :71 removed; its count-based join re-derivation at ~:1447 hardened
to tier1/tier2 rows only), master template. N/A: Mugu match-building scripts,
TaxaWizard dist_to_priors snippets (no site selection — but they pass
`grid_id = NA` to generate_domestic_food_priors, noted, not fixed). STILL
STALE, flagged not fixed: PtConception/TaxaID_eDNA_Workflow_Template.R:63
hardcodes "Grid_34p2_m120p7" (live, old local template);
PtConceptionWorkflow_12S_test_genus_fix.R:43 and
PtConception12S_regression_test.R:60 hardcode the same (test scripts).

**The fix (applied):** nearest grid to STUDY coordinates, measured to each
grid's focal-habitat DATA CENTROID with cosine-corrected longitude — data
centroid, not cell center, because STUDY_LON = -120.4 sits exactly on a cell
boundary where center distances tie (and the tie-break would again be
alphabetical). Verified live: picks Grid_34p4_m120p8 (10.6 km, 50,659 marine
records; the model's own n_obs for that cell matches exactly). Single-site +
multi-site carry a hard warning if the pick differs from Grid_34p4_m120p8.
Backups: *.bak_pre_focal_grid_fix beside each non-git workflow file.

**Re-run state (updated later 2026-08-30):** PtCon 12S single-site is ready to
re-run from Step 5 (line ~457); its 4 contaminated checkpoints are parked as
*.stale_pre_grid_fix_20260830 (match/likelihood/census/fetch caches kept).
PtCon Step 7a.10's FIRST attempt was killed mid-run by NCBI CPU-throttling
(circuit breaker fired; ~100 accessions incomplete) — no loss: completed
accessions are in ptcon_ref_eval_cache, the rest auto-retry on the next
evaluate_reference_accessions() call. Resume after NCBI settles (evening/
overnight), with NCBI_EMAIL set in ~/.Renviron (blast_sequences() reads it;
its absence caused the usage-policy warning). **GreatLakes damage quantified:**
old alphabetical pick Grid_41p5_m86p5 = inland-Indiana cell, 40 km from Burns
Harbor, 18 Lentic records; correct cell Grid_41p5_m87p0 = Lake Michigan south
shore, 13 km, 82 Lentic records (grid_size 0.5; study coords approximated
41.62/-87.17 — pick is distance-rank-robust). GL contaminated checkpoints
(taxaexpect_priors/consensus_final/reviewed) parked the same way; GL re-run
from its Step 5 (line ~593) is the active next step — the general prior-
framework exploration moves to GreatLakes; after the re-run, re-validate with
REVIEW_formal_lamar_check.R (w_scale + Lamar numbers were computed against the
wrong cell). GL's goal2_screen_ref_eval_cache means its accession screen
re-run is nearly free (cache-served).

---

## GENERAL PRIOR-SETTING FRAMEWORK (design conversation 2026-08-30, no verdicts yet)

Reached over several rounds with the user; supersedes the piecemeal framing of
Questions A/B above. To be treated as decision points one at a time ("I don't
want to rush into them"), AFTER the post-fix re-run provides trustworthy
numbers. Full worked numbers in the session transcript; key structure:

1. **Compositional definition** (user's correction): theta_i = P(a random
   legitimate DNA record at this site/habitat belongs to species i). Sums to 1;
   only ratios reach posteriors (per-ASV renormalization in
   compute_posterior()). Transported DNA (bleed/domestic/food) is a real
   component of the sample's composition, not an add-on. Count reframing
   (user's): work with predicted counts, floor the zeros, renormalize per
   candidate set — algebraically identical for observed species (denominator
   cancels); ALL substance lives in the zero pseudo-counts. Adopted as
   derivation/audit/manuscript language; storage stays (alpha, beta) — which
   ARE pseudo-counts, so "counts lack spread" is false (alpha+beta = effective
   records = concentration).
2. **Good-Turing/Chao scaffolding**: singleton mean ~ smoothed 1/n; unseen
   species' collective share = f1/n (Good 1953); missing-species count =
   f1^2/(2 f2) (Chao 1984); per-missing share = mass/count ~ singleton rate.
   Empirical coherence at the (wrong-cell) audit: w x singleton_mean =
   GT_mass/claimants; the independently calibrated w_scale = 0.05 matched
   Chao_missing/claimants = 0.062. GT discounted counts r* = (r+1)f(r+1)/f(r)
   give the user's Task-2 ordering axiom a nonparametric foundation
   (observed >= r*(1) > unseen shares).
3. **Branch budgets** (the sum-to-1 rule made operational): resident-undetected
   branch's total = GT mass; transport branch's total = measured cross-habitat
   read share (7.4e-4 at PtCon, wrong-cell). Audit caught the current system
   spending 0.078 (~120 phantom records) on wrong-habitat species vs a ~1
   record budget. Budgets = calibration targets, not runtime constraints;
   per-ASV renormalization is where probability laws bind operationally.
4. **Within-branch allocation**: user's proportional-to-occurrence-share
   estimator is right WITHIN clades (within-mammal Spearman 0.84 vs realized
   bleed) and wrong across clades (cross-clade 0.35; vulture/pig inversion,
   3 orders each way — reporting bias doesn't cancel across the habitat
   boundary). Resolution: clade-partitioned transport budgets measured from
   the sample's own reads (mammals 4.4e-4, birds <=2.2e-7 one-detection bound,
   freshwater fish 2.3e-4), record-share allocation within clade. The clade
   level only binds in branch-MIXED candidate sets (transport vs fitted);
   branch-pure sets cancel it, as the user noted. Open: is a single transport
   rate + per-clade zero-bounds enough?
5. **Multi-category taxa** (watch + out-of-box + food, dog = bleed + domestic):
   NOT previously decided — current behavior is join-precedence accident (Sus's
   domestic row is unreachable dead weight at the focal grid). Proposal:
   disjoint latent routes ADD (each charged to its own budget); same-budget
   evidence combines noisy-OR (~additive, ceiling-capped); flags carry
   interpretation separately.
6. **Ordering**: axioms only where semantics compel (floor bottom; singleton
   ceiling on the resident branch; distance monotonicity; composition never
   lowers theta). Between-category order = measured, checked, not decreed.
   User's "invaders below rare species" accepted as default: an invader with
   no regional record isn't a claimant on the GT mass; current system has
   invader >= out-of-box (both w = 0.05) — backwards; tier invader w by NAS
   establishment evidence.
7. **Censored candidate lists** (Wilderlabs 100%-match rule): candidate-set
   Bayes is valid conditional on coverage; the only honest patch is explicit
   catch-all hypotheses (H2/H3 machinery); count rule: truncation conserves
   counts — dropped candidates' mass flows to the catch-all.

**Decision points queued (one per discussion, pros/cons/alternatives, in
dependency order):** (1) branch-budget rule (enforced vs audited; f1 = 0 case);
(2) within-branch allocation (clade budgets vs flat vs shrinkage lambda);
(3) multi-category additivity + noisy-OR boundary; (4) invader placement;
(5) dark-floor claimant pool (current 7.1e-7 implies ~29,000 claimants — make
it a stated choice). ALL wait for post-fix re-run numbers.

---

## GREATLAKES POST-FIX RE-RUN + LAMAR RE-VALIDATION (2026-08-30 evening)

Clean re-run (fish-scoped re-entry, corrected Grid_41p5_m87p0, 885 obs) vs the
parked Aug-28 wrong-grid baseline — same package state, only the grid differs:

- Species-resolved obs 180 -> 211; unique resolved species 22 -> 16 (6 lost,
  all to COARSER ranks, none to wrong species: Perca flavescens -> Percidae,
  Osmerus mordax -> Osmerus, Morone americana -> Morone, Notropis hudsonius ->
  Leuciscidae, O. gorbuscha -> Oncorhynchus, Esox americanus -> Esox).
  Per-obs taxon agreement 92.2%.
- Formal Lamar re-validation (REVIEW_formal_lamar_check.R, _wcal outputs):
  species co-detections 237 (was 238), ours_only 80 (was 97 — improved),
  species precision both/(both+ours_only) = 0.748 (was 0.710 — improved),
  unique-species intersection with Lamar 13/61 (was 18/61 — reduced breadth).
  Mechanism mix: prior_reranked 620, ambiguous_rank_fallback 199 (was ~205).
- VERDICT SHAPE: corrected grid trades breadth for precision. Cause traced:
  the TRUE cell is data-poor (82 Lentic records; tier2/singleton scale 0.0192,
  evidence rows 1.05e-3), so fitted priors are COMPRESSED — e.g. Perca
  flavescens 0.038 vs Sander vitreus 0.0088 (only ~4:1 where the data-rich
  wrong cell gave much stronger separation), so more congeners clear
  min_posterior and LCA upranks. The upranked calls are honest uncertainty,
  not errors — but 5 of the 6 lost species are Lamar-corroborated reality.
- THE NEW CENTRAL DESIGN QUESTION for the framework discussion: how should
  fitted priors borrow strength when the site cell is data-poor? (Moran
  smoothing already borrows some; grid_size optimization picked 0.5 globally;
  candidate ideas: density-adaptive cell size, hierarchical cell->region
  shrinkage of fitted theta, or a regional prior with a site-level adjustment.)
  This SUPERSEDES the old Question A framing: the fitted-vs-mirror scale
  coherence problem is really a small-n-cell shrinkage problem.
- w_scale = 0.05 survives directionally (precision improved with it in
  place), but a proper w re-sweep at the corrected grid has NOT been done.

---

## PHASE 1 SPEC: KERNEL-AT-PREDICTION SITE PRIORS (drafted 2026-08-30, FOR USER REVIEW — NOT implemented, NOT approved)

Decision-point-1 proposal from the small-n-cell discussion. SUBSUMES old
Question A (the ceiling anomaly is a small-n artifact of single-cell
prediction). The grid-based FIT is deliberately untouched — this spec changes
only the prediction/anchor layer. Touchpoint survey (agent, 2026-08-30):
pivot ~85% contained in TaxaExpect; join/consensus/flag layers treat grid_id
as an opaque key and need no change; `combine_multisite_priors()` already
implements the precision-weighted logit blend; the only cross-package
coupling is TaxaAssign/R/site_utils.R's grid-string parsing (gets simpler).

### Design

1. **Site prior = precision x proximity blend of per-cell predictions.**
   Predict from the existing fitted model at the k nearest cells (k ~ 5);
   blend per taxon in logit space with weights
   w_c ∝ precision_c * exp(-d_c / lambda), d_c = cosine-corrected distance
   from the site to cell c's focal-habitat DATA centroid. Mechanism: the
   `combine_multisite_priors()` math with a proximity factor (additive
   param). Emit ONE blended site row-set BEFORE join_priors (keeps the join
   pure; downstream unchanged).
2. **Budgets/anchors at kernel scale.** Effective counts c_i = sum over
   species-i records of exp(-d/lambda); W = total; Kish n_eff = W^2/sum(w^2).
   Singleton mass = (sum of weights of species with exactly one record in the
   effective neighborhood)/W (reduces to Good-Turing f1/n under a top-hat =
   the grid special case). Ceiling (singleton mean) ~ smoothed 1/n_eff;
   floor and evidence blends recomputed from these. `apply_undetected_
   evidence()` takes the neighborhood/n_eff instead of a scalar focal grid.
   GL arithmetic: n_eff(50km) = 3,162 -> ceiling ~1.6e-3 -> the Osmerus
   eperlanus evidence row falls to ~1.9e-4 and Osmerus mordax (460:0 records)
   resolves at ~23:1; Perca (5:1 at every radius) stays honestly upranked.
3. **lambda calibration, per dataset:** leave-one-cell-out composition
   prediction (multinomial deviance) over a lambda grid; report the chosen
   value + the budget-plateau check. Measured cost: 10-lambda sweep on 1.8M
   records = 0.48 s.
4. **DESIGN BOUNDARY (performance):** NO per-species latent spatial fields
   (GP/SPDE/per-taxon GAMM smooths) — the named hours-scale trap from the
   early model exploration. Kernels here are ESTIMATORS at prediction time,
   never latent models. Measured baselines: full kernel pass on 1.8M records
   0.11 s; Phase 1 total added runtime budget < 10 s.
5. **Display companion (optional):** `plot_theta_surface()` — binned-FFT KDE
   ratio surface (species surface / effort surface, Nadaraya-Watson), same
   lambda as the priors so THE MAP IS THE PRIOR FIELD; alpha-shade by local
   n_eff(x). Measured: 512x512 from 1.25M records = 0.28 s/surface.

### Acceptance tests (GreatLakes Lamar harness, then PtCon after its re-run)

- Recover the evidence-veto losses (Osmerus mordax class).
- Species precision both/(both+ours_only) >= 0.748 (no regression from the
  corrected-grid baseline).
- Perca/Morone-class stay upranked (regional 5:1 / 2:1 ratios — honest
  ambiguity, NOT a failure of this change; their recovery belongs to the
  downstream-evidence thread: why didn't the D7 soft-confirmation update
  lift perch? — separate autopsy, out of scope here).
- Branch-budget audit passes at kernel scale (sum of evidence rows ~ weighted
  GT mass; transport rows within measured bleed budget — Question B).
- Added runtime < 10 s on both datasets.

### Open questions for the verdict

(a) k and the blend's precision definition (trigamma-based, as
combine_multisite_priors) — accept defaults or discuss? (b) lambda shared
across habitats or per-habitat? (c) does clause-(b) wrong-habitat promotion
get retired in the SAME change (it interacts with the rescaled ceiling;
Question B's transport-budget design is the replacement) or separately?
(d) is the Perca/soft-confirmation autopsy in scope now or after Phase 1?

### Phase 2 (CONTINGENT — only if Phase 1 validation shows the fit itself binds)

Kernel-native estimation (weighted-count estimator REPLACES the GLMM fit —
would be faster than today, 0.1 s vs minutes). Open problems before it could
be specced: phi-cap source (currently VarCorr[["taxon_name:grid_id"]] — no
substitute identified), covariate adjustment (depth) and cross-species
shrinkage outside the model, weighted Chao/species-count machinery,
evaluation-point set replacing zero-fill. Fine-scale heatmaps do NOT require
Phase 2 — the KDE surface machinery works off the raw records now.

### USER VERDICT on Phase 1 scope (2026-08-30)

Minimal Phase 1 confirmed: blend TIER1 fitted predictions only; tier2, the
singleton/evidence machinery, clause-(b) promotion, and ALL unobserved-taxa
rules stay untouched (tier2's proper solution expected to differ / belong to
Phase 2). Purpose narrowed to: does kernel borrowing deliver the effective-
sample-size and predictive improvement at a lightly sampled site that
justifies Phase 2? After Phase 2, return to unobserved-taxa priors.
Acceptance tests amended to ESTIMATION-LEVEL: (i) n_eff at site across a
lambda ladder (10/25/50/100 km); (ii) leave-one-cell-out composition
prediction — kernel vs single-nearest-cell vs regional (the "is locality
worth anything" check); (iii) key ratio movement (recorded, not judged).
Lamar/consensus metrics recorded as observational only — minimal Phase 1 is
NOT expected to recover the 6 lost species (that needs the deferred ceiling/
evidence work). Implementation: diagnostic script first
(REVIEW_phase1_kernel_diagnostic.R, GL data dir), zero package/workflow
changes; GL = testbed, PtCon (post re-run) = near-invariance negative
control (its true cell is data-rich, kernel should change it ~nothing).

### Phase 1 diagnostic RESULTS (2026-08-30, REVIEW_phase1_kernel_diagnostic.R, GL data dir)

(1) n_eff at Burns Harbor: in-cell 82 -> kernel 137 (lambda=10km) / 1,222
(25km) / 3,162 (50km) / 4,904 (100km).
(2) LOCO composition prediction, per-record log-loss over 21 cells (lower
better): kernel_25 = 3.267 BEST, kernel_50 = 3.305, kernel_100 = 3.384,
kernel_10 = 3.538, regional = 3.526, **nearest_single_cell = 3.659 WORST** —
the single-cell architecture predicts local composition worse than ignoring
space entirely; the kernel beats both, and locality is confirmed real
(kernel_25 >> regional). Interior optimum at lambda ~ 25 km (17/21 cells
beat nearest-cell). Data-chosen bandwidth, not hand-set.
(3) Model-based k=5 blend at the site (Phase 1's actual mechanism, lambda=50):
gentle, sane movement — median |log10(blend/focal)| = 0.16 (~1.4x typical);
Perca:Sander 4.3:1 -> 6.7:1 (toward the neighborhood record ratio); carp/
bluegill rise (Chicago-shore composition entering — ecologically plausible
for an industrial harbor, worth an eyeball).
Caveats: LOCO tests the record-composition estimator (Phase-2-style), the
blend is the Phase-1 mechanism; site coords approximate; NOTED pre-existing
quirk (also fired in the user's own Step 5e run): generate_full_priors
prints "No taxon_name:grid_id term found ... fallback phi cap 1000" even
though the fitted formula HAS the term — the VarCorr lookup is failing;
separate small bug to chase.
VERDICT per the user's criterion ("desired improvement in effective sample
size"): delivered — awaiting the user's call on proceeding to Phase 2.

### USER VERDICT (2026-08-30): Phase 1 diagnostic = "a strong case for phase 2."

Phase 2 design proposal presented in-session (condensed here; verdicts
pending on the lettered questions):

Core: theta_i(site, habitat) = (c_i + m * p_regional,i) / (W + m), where
c_i = sum of exp(-d/lambda) over species-i records in the habitat stratum,
W = total, n_eff = Kish. One distance pass serves ALL species (0.1 s at 1.8M
records) — the many-species scaling constraint disappears. Job-by-job
replacement of the GLMM: habitat = stratification; cross-species shrinkage =
the m-pseudo-record backoff to regional composition (the count-framework
backoff, m chosen by LOCO); uncertainty = concentration alpha+beta = n_eff+m
by construction (NOTE: the phi cap's VarCorr source is ALREADY broken in
production — falls back to 1000 — so Phase 2 loses nothing there and gains a
principled concentration); covariates (depth) = optional product kernel
exp(-d_geo/lambda)*exp(-|d_cov|/lambda_cov), tested by LOCO; tiers =
continuous in c_i, with a compatibility band-mapping to tier1/tier2 labels
so downstream consumers are untouched; singleton/GT ingredients (n_eff,
weighted f1) emitted but unobserved-taxa RULES unchanged until after Phase 2
per the standing scoping. Model selection = the LOCO predictive harness
(replaces AIC screening). Output keeps the priors-table schema (site id in
the grid_id column — survey confirmed downstream treats it as opaque).
Implementation additive: new estimator function alongside the GLMM path,
workflow flag to switch, old path retained until validated; feature branch
per [[feedback_git_branches]].

Open for verdicts: (a) covariate handling — start geographic-only and let
LOCO decide whether the depth product-kernel earns inclusion? (b) fate of
the retired machinery (optimize_grid_size/Moran/screen_spatial_formula/
train_biodiversity_model): keep as optional model-based mode vs deprecate —
NOTE manuscript supplemental methods currently describe the GLMM;
(c) accept the tier band-mapping compatibility shim? (d) validation gates:
LOCO <= 3.267 (kernel_25 baseline), Lamar precision >= 0.748, runtime
seconds, PtCon-as-data-rich-control near-invariance.

### Phase 2 verdicts (2026-08-30): (a) DEPTH IN from day 1 (user-confirmed
covariate, distinguishes pelagic species) — kernel translation: weight
records by exp(-|depth_record - depth_site|/lambda_d) alongside geographic
distance; lambda_d tuned by LOCO (inclusion not gated, bandwidth is).
(b) DEPRECATE the GLMM machinery, reversibly (archive precedent, e.g. the
DECIPHER module; git history retains; manuscript supplemental methods will
need a rewrite — flagged). (c) PENDING — user needs more info on the tier
shim; explainer given in-session: model_tier's real downstream consumers are
join_priors' promotion-clause exemptions (keys on evidence/domestic tier
VALUES; tier1-vs-tier2 mostly informational there) and — the real interface —
generate_undetected_diversity(), which reads the MODEL OBJECT's singletons/
tiers/N_total; the kernel estimator must emit a compatible structure
(weighted singletons, n_eff as N) even with unobserved-taxa rules unchanged.
Proposed mapping: tier1 = c_i >= T effective records, tier2 = 0 < c_i < T,
singleton set = exactly one record in the effective neighborhood; T chosen
for continuity with the current 76/49 GL split (or T = 5, auditable in count
units). (d) GL-first validation, PtCon deferred but REQUIRED eventually
(data-rich near-invariance control).

### Phase 2 verdict (c) — RESOLVED (2026-08-30): clean interface NOW, no shim.

User: interface decisions are foundational to the post-Phase-2 unobserved-
taxa work — do the clean version first, not the compatibility shim.
DECIDED SCHEMA (names collision-checked against the whole monorepo, virgin):
- `model_tier` is RETIRED. Its two conflated meanings split into:
  - `prior_branch` (character): the framework's branch taxonomy —
    "resident_observed" (kernel estimate from real local evidence),
    "resident_undetected" (floor + evidence-blend rows; the GT-budget
    branch), "transport" (domestic/food now; bleed later). Exact value
    vocabulary finalized at implementation; join_priors' promotion-clause
    exemptions and report/audit displays port from model_tier values to
    prior_branch values.
  - `effective_records` (numeric, continuous): kernel-effective evidence
    c_i backing the row's estimate (count units; replaces tier1/tier2 and
    the informational n_obs role). tier1/tier2 vocabulary disappears.
- `prior_source_type` (existing, domestic rows) stays as the finer
  within-branch provenance; `evidence_sources` likewise.
- generate_undetected_diversity() ports to kernel inputs directly (weighted
  singleton set, n_eff) — rules frozen, plumbing new, no fabricated tiers.
- Ripple surface (from the touchpoint survey): join_priors value keys,
  report_priors, TaxaExpect emitters, tests/fixtures in TaxaExpect+TaxaAssign,
  TaxaWizard metadata text. TaxaFlag untouched (tier-blind). Breaking-change
  row + NAME_CHANGE_HISTORY entry required at implementation.
ALL FOUR PHASE 2 VERDICTS NOW IN. Next session: feature branch (name
suggestion: kernel-priors), build the estimator + LOCO harness first, then
the schema port, GL validation gates per (d).

### PHASE 2 BUILD LEDGER (started 2026-08-30 overnight, branch kernel-priors)

DONE (all ADDITIVE, nothing existing touched, NOT reinstalled -- user's PtCon
re-run was live overnight; install in the morning after it finishes):
- B1. estimate_kernel_priors() -- the estimator, new schema (prior_branch +
  effective_records), n_eff-concentration Betas, weighted GT singletons +
  missing mass emitted. TaxaExpect R/estimate_kernel_priors.R.
- B2. calibrate_kernel_bandwidth() -- LOBO composition prediction over
  lambda/lambda_covariate/m with regional + nearest_block references.
- B3. 29 test assertions (test-estimate_kernel_priors.R), all passing;
  top-hat reduction to classical grid quantities is the key invariant.
- B4. Real-data validation (GL, load_all): calibration reproduces the Phase-1
  diagnostic; depth kernel VALIDATES out-of-sample (3.385 -> 3.267 at
  geo 50 x depth 50); Burns Harbor: n_eff 2,397 (vs 82), Perca:Sander
  8.2:1 (was 4.3), Osmerus 64 effective records.

DONE 2026-08-31 morning:
- B5. generate_undetected_diversity() accepts taxaexpect_kernel_priors
  (adapter: N = Kish n_eff, mirrors = neighborhood singletons stamped with
  the SITE id -- fixing the old dropped-distant-mirror wart; frozen rules
  untouched); emitted rows carry prior_branch = "resident_undetected"
  alongside legacy columns. Kernel priors table gains observed_in_habitat =
  TRUE (true by construction; guards join_priors D1 fallback).
- B6 (partial). join_priors(): prior_branch now gates promotion (only
  resident_observed rows eligible; subsumes the model_tier value checks once
  that column retires); prior_branch/effective_records carried through
  coarse-rank expansion override_cols + habitat-agnostic fallback
  provenance. report_priors() reports by prior_branch when model_tier is
  absent. Tests added both packages; checks pending/green.

TODO (dependency order):
- B6-remainder. Evidence/domestic generators stamp prior_branch
  ("resident_undetected"/"transport") on their rows.
- B7. Deprecate the GLMM fit path (verdict b, archive precedent) + retire
  model_tier vocabulary; breaking-changes row + NAME_CHANGE_HISTORY.
- B8. GL workflow switch + validation gates (LOCO <= 3.267; Lamar precision
  >= 0.748; runtime seconds). Then PtCon control (verdict d).
- B9. Commit conversation: branch inherited a large uncommitted backlog.

### Interim bleed behavior under the kernel path (2026-08-31, user-acknowledged)

The kernel estimator stratifies to the focal habitat, so wrong-habitat
species have NO resident row -- join_priors clause (b) promotion retires
itself (nothing to promote). Interim: listed domestic species keep transport
rows (~5x floor, close to the measured bleed rate); UNLISTED wild bleeders
(elk/woodrat/coyote-class) fall to the dark floor until the bleed generator
exists. REQUIREMENT for the future bleed generator (post-Phase-2 Question B
work): restore coverage for unlisted wild bleeders via the measured
transport budget + within-clade allocation.

### B8 progress (2026-08-31)

- apply_undetected_evidence() + generate_domestic_food_priors() gained kernel
  adapters (read only habitat concept / N; class shim). REAL-DATA COHERENCE
  BUG found in the B5 adapter via dry run and FIXED: mapping the floor's N to
  n_eff inverted the floor/ceiling interval (distance-discounted singleton
  shares sit below 1/n_eff). Two scales now: floor N = raw stratum record
  count ("one detection across all available effort", 1.62e-4 at GL);
  ceiling = site-scale mirror shares (~2.9e-4). Verified to the digit:
  evidence theta = floor + w*(ceiling - floor) exactly. Top-hat limit
  unchanged (scales coincide).
- Full kernel Step 5 dry-run on real GL data PASSED end to end: calibration
  (best 100km x depth 25, LOBO 3.214 -- beats the Phase-1 3.267 baseline
  already), assembly (86 resident + 13 undetected rows), domestic generator
  (2 transport rows), applier (synthetic watch evidence, coherent blend).
- GL WORKFLOW SWITCHED: USE_KERNEL_PRIORS <- TRUE branch in Step 5 (GLMM
  path retained in the else until PtCon migrates -- B7 deferred, "gentle");
  model_fit aliased to the kernel object so all downstream model_obj
  consumers run through the adapters unchanged; session metadata records
  bandwidths/n_eff on the kernel path. Backup:
  *.bak_pre_kernel_switch. GLMM-path outputs parked as
  *.glmm_path_20260831 (the B8 comparison baseline).
- NEXT: user reinstalls TaxaExpect+TaxaAssign (no live NCBI/R jobs), runs GL
  from Step 5, we score the gates (Lamar >= 0.748 precision; runtime;
  branch-budget audit) against the parked baseline.

### B8 VALIDATION RESULT (2026-08-31): KERNEL PATH PASSES DECISIVELY

GL fastpath run (GreatLakes_kernel_fastpath.R, 16.6 min first run, zero NCBI)
vs the parked correct-grid GLMM baseline, scored by REVIEW_formal_lamar_check.R:

| metric | wrong-grid GLMM | correct-grid GLMM | KERNEL |
| species co-detections | 238 | 237 | 564 |
| ours_only | 97 | 80 | 86 |
| precision both/(both+ours) | 0.710 | 0.748 | 0.868 |
| unique species (∩ Lamar) | 23 (18/61) | 16 (13/61) | 29 (27/61) |
| Lamar species we resolved nothing for | 63/1081 | -- | 1/1081 |

Resolution 211 -> 489 of 885 observations. Perca flavescens BACK (78 obs;
walleye ALSO resolves separately -- the depth-sharpened 8.2:1 prior plus
likelihoods now separate the percids instead of LCA-collapsing). Osmerus
mordax back (5), Notropis hudsonius back (13); Morone americana /
O. gorbuscha / E. americanus stay unresolved (honest regional ambiguity).
Gained 15 species (bluegill, alewife, gizzard shad, walleye, darters,
minnows -- the core harbor community), 27/29 Lamar-corroborated. Small real
regressions to note: Pylodictis olivaris + Luxilus chrysocephalus dropped to
coarser ranks (were resolved under GLMM); ours_only 80 -> 86.
Gates: precision 0.868 >= 0.748 PASS; LOCO 3.214 <= 3.267 PASS; runtime PASS.
Still owed: PtCon data-rich near-invariance control (gate d).

NEW ITEMS from the run:
- Posthoc Axis-1 plausibility says 873/885 "unprecedented" -- a SEMANTICS
  SHIFT, not a finding: the kernel table names only locally-evidenced
  species (86) where the GLMM table named all 652 regional taxa, so
  "has occurrence record" needs recalibration for kernel tables (fold into
  the post-Phase-2 prior work).
- Veto-bound printer reports "weight above 0.000" under kernel anchors --
  diagnose during the anchor redesign.
- fill_higher_ranks warning: "Salvenlinus malma" (misspelled genus in the
  unreferenced list) has no family -- upstream data quirk, harmless.
- Fixed live during B8: kingdom-vocabulary false homonym in
  generate_domestic_food_priors (Metazoa vs Animalia -- commit 2aa685a);
  fastpath read_depth join gap.

### B7 DONE -- GENTLE GLMM DEPRECATION (2026-08-31, follow-on session)

Shipped the "gentle" form (full archival deferred to PtCon migration, since
PtCon/Mugu still run the GLMM path while NCBI-throttled):
- All 9 GLMM-chain functions (build_priors, optimize_grid_size,
  prepare_model_dataframe, add_pca_covariates, compute_moran_basis,
  screen_spatial_formula, train_biodiversity_model,
  train_biodiversity_model_by_group, generate_full_priors) emit a
  once-per-session rlang::inform() notice (shared .frequency_id, new internal
  .glmm_deprecation_notice()) + roxygen @section Deprecated pointing at
  estimate_kernel_priors()/calibrate_kernel_bandwidth(). Zero behavior change.
- model_tier doc-deprecated on its four emitters; vocabulary retires fully at
  archival.
- Records: NAME_CHANGE_HISTORY.md row, TaxaID/CLAUDE.md breaking-changes row,
  TaxaExpect/CLAUDE.md top note. Manuscript supplemental methods still
  describe the GLMM -- rewrite remains flagged, its own task.
- devtools::test() 773/0; devtools::check() 0/0/1 (environmental note).
- REMAINING at archival time (PtCon migration): move the chain + its tests to
  an archive dir; retire model_tier emission + join_priors()'s model_tier
  value checks; rewrite supplemental methods.

NEXT UP (user's 2026-08-31 ordering): posthoc Axis-1 recalibration (the
873/885 "unprecedented" semantics shift -- kernel tables name only
locally-evidenced species, so add_posthoc_assessment()'s
"has occurrence record" concept needs rebasing), then the post-Phase-2
unobserved-taxa redesign (the framework decision points queued above).
Iterate via GreatLakes_kernel_fastpath.R (zero NCBI, ~minutes).

### POSTHOC AXIS-1 RECALIBRATION DONE (2026-08-31, follow-on session)

Root cause was sharper than "semantics shift": the legacy reading
(`winner_has_occurrence_record = !is.na(model_tier)`) was fully INVERTED on
kernel tables -- resident rows carry no model_tier (all 86 locally-evidenced
species read FALSE) while the undetected/domestic adapters' legacy columns
made zero-local-record evidence species read TRUE (the 12 "TRUE" winners were
grass carp/L. ardens/P. phoxinus/R. atratulus-class evidence rows). Fix in
TaxaAssign::posterior_consensus(): when `prior_branch` exists,
has-record = `prior_branch == "resident_observed"`; plausible-competitor mask
= any non-NA branch (named row, any branch); legacy model_tier logic retained
byte-for-byte for GLMM tables. Transport winners read FALSE by design
(domestic_prior_caveat carries the interpretation).
consensus_has_occurrence_record needed NO change (group_priors lookup already
branch-agnostic; read TRUE for 883/885 under kernel).
VALIDATED via fastpath re-run (16.7 min): plausibility 2/10/873 ->
860/12/13 expected/unexpected/unprecedented (GLMM baseline 864/15/6); the 13
unprecedented are exactly the evidence-elevated zero-local-record winners;
consensus_taxon/consensus_rank byte-identical to B8 (posthoc-only change,
as designed). B8 pre-recal consensus parked as
*.kernel_b8_pre_axis1_recal. 5 regression tests added; TaxaAssign 700/0,
check 0/0/0, reinstalled.

STILL OPEN from the B8 new-items list: veto-bound printer "weight above
0.000" under kernel anchors (diagnose during the anchor redesign);
"Salvenlinus malma" upstream data quirk (harmless). NEXT: the post-Phase-2
unobserved-taxa redesign -- decision points 1-5 queued above, one per
discussion, now unblocked (post-fix numbers exist).

### UNOBSERVED-TAXA REDESIGN: CURVE PRICING BUILT + GL-VALIDATED (2026-08-31)

Design settled in-session (full derivation in chat; decision points 1-5 all
resolved or dissolved):
- DECISION 1 (branch budget): AUDITED, not enforced. Headline statistic in
  COUNT units: sum(w) over named claimants vs Chao missing-species count
  (theta_present = mass/Chao makes the two audits one identity). Enforcement
  rejected: pool-dependent priors + erases the graded design + f1=0 zeroes
  the branch.
- REFINED FRAMEWORK (user, recorded): the proper P=1 composition is the
  RESIDENT community (observed shares + GT unseen mass, interior not
  enumerated). Non-regional species, invaders, transport (bleed/domestic/
  food), contaminants sit OUTSIDE the simplex as presence-weighted
  hypotheses on their own evidence scales -- commensurable units required
  (rows meet in candidate sets; ratios decide), each branch calibrated
  against its own measurement. Supersedes the 2026-08-30 "transport is part
  of the composition" phrasing (operationally identical).
- THETA_PRESENT: mass/Chao (2.04e-4 at GL) for ALL unseen claimants -- the
  zero-record evidence caps share-if-present regardless of species identity
  (P(0 records in n_eff=2963 | share s) ~ e^(-2963 s)); establishment
  status raises w, never theta_present; abundance shows up in the reads.
  Invader refinement (recency-limited n_eff, record-lag argument) noted,
  needs eventDate (dropped from occurrences_clean) -- deferred.
- PRICING: theta = w * theta_present, theta_absent = 0 (replaces the
  floor-additive blend whose floor term dominated every row ~98%). ONE
  presence-distance curve prices all unobserved claimants:
  w = w_scale*exp(-min(d, d_cap)/d_half); named regional at real distance;
  WATCH species: bandwidth stretched K_LIFT-fold (= log-space "halfway"
  rho = 0.5; formally exp(-d/(k*lambda)) = [exp(-d/lambda)]^(1/k)) at their
  own nearest-record distance; iNat w = 0.8 (own instrument); everything
  else the DISTANCE CLAMP w_scale*exp(-d_cap/d_half) = 6.4e-5 (beyond the
  instrument cap distance stops discriminating -- human-vector-dominated
  tail). Settled: w_scale 0.05, d_half 150, d_cap 1000 km, K_LIFT 2.
  reserve/N floor REJECTED by pressure test (N not enumerable; GL gave
  N=7 -> w=1.03>1). Jeffreys guard: 0 confirmed of 221 clamped
  non-regionals -> 2.3e-3 upper scale; tripwire if any is ever confirmed.
- LATITUDE ANISOTROPY: estimate_kernel_priors(lambda_latitude=) +
  calibrate grid (commit fb9e902) -- absolute-latitude climate factor,
  hemisphere-symmetric. GL LOBO verdict: Inf (off) at regional scale;
  intended scale is the continental curve (evidence generators; not yet
  wired there).

BUILT (commit 0499c24 + fastpath prototype, .bak_pre_curve_pricing):
estimate_kernel_priors() emits f1/f2/chao_missing/theta_present;
apply_undetected_evidence(pricing = "curve"); fastpath USE_CURVE_PRICING
block (distances first over the FULL zero-bbox set incl. watch; watch
k-lift; clamp rows; branch-budget audit print). NOT yet package-ified:
clamp/watch-lift generators, per-species user w override (+provenance +
veto-bound reporting), anisotropic curve in the generators.

VALIDATED (fastpath 70.9 min incl. fresh 376-species distance pass; Lamar):
co-detections 564 -> 594, ours_only 86 -> 102, precision 0.868 -> 0.853
(>= 0.748 gate PASS), unique species 29 -> 33 (28/61 Lamar), missed 1/1081.
STRICTLY ADDITIVE species change: +Percina maculata(8), +Paranotropis
volucellus(4), +Pimephales vigilax(1), +Esox americanus(1 -- one of the six
corrected-grid losses, recovered), 0 lost. Mechanism: floor-deflated
evidence rows stop interfering in LCA contests, residents resolve finer.
Audit at GL: sum(w) = 6.67 vs Chao 14.4 (within budget; iNat 4.0 of it).
Baselines parked: *_consensus_final.rds.blend_pricing_20260831,
*_taxaexpect_priors.rds.blend_pricing_20260831.

STILL OWED: user verdict on adopting curve pricing as default; PtCon
near-invariance control (gate d, both for kernel path and curve pricing);
package-ification of the prototype pieces; A2 discovery-rate cross-check;
manuscript methods rewrite (now covers GLMM deprecation + curve pricing).

### ADOPTION + PACKAGE-IFICATION + PTCON CONTROL (2026-08-31, closing the arc)

USER VERDICTS: curve pricing ADOPTED as GL default (ported to the full
workflow's 7a.7b-e, branch on USE_KERNEL_PRIORS, backup
.bak_pre_curve_pricing; legacy blend in the else); PtCon control next;
package-ify generators + user-w.

PACKAGE-IFIED (commit 52fd9e0, TaxaExpect 818/0, check 0/0/0, reinstalled):
- generate_presence_curve_evidence(): one curve serves clamp (no distances),
  plain regional pricing (distances, k=1), and the listed-invader lift
  (distances, k>1). w_scale required (no default, calibration-forcing).
- generate_user_specified_evidence(): named w vector -> provenance rows
  (source = "user_specified") + dilution-threshold (1/9) disclosure message.
- apply_undetected_evidence() curve mode no longer requires a global_floor
  anchor row (anchors gated to blend mode; curve printer anchors on the
  kernel object's own singleton scale).
- Fastpath + workflow both call the real generators. VERIFIED: fastpath
  re-run reproduces the adopted result exactly (506/885, 33 species,
  audit byte-identical, 17.6 min warm).

PTCON NEAR-INVARIANCE CONTROL (gate d) -- PASS. Priors-level, zero NCBI:
REVIEW_ptcon_kernel_control.R (PtCon data dir; saves *_cmp.rds). The
workflow's exact GLMM Step 5 vs estimate_kernel_priors() on the same Aug-29
occurrence pool (1.25M Marine-stratum records; kernel n_eff 224,780 at
LOBO-chosen lambda = 25 km):
- Abundant head: top-10 GLMM species match within 3-5% (|log10 ratio|
  <= 0.05). All-507 Spearman 0.923; excluding epsilon-clamped GLMM rows
  (theta_glmm = 1e-6 exactly -- NOT model predictions) n = 415, Spearman
  0.919, median |log10 ratio| 0.348; tier1-only n = 347, Spearman 0.927,
  median 0.285 (~1.9x typical).
- The big divergences are the kernel being MORE honest: Microtus/
  Phasianus/Odocoileus carry tier1 "Marine" rows (habitat bleed) that the
  GLMM priced ~1e-6-8e-6 and the kernel prices ~1e-10; Bering-Sea/Atlantic
  fish similarly. Both PtCon LOBO and the earlier GL LOCO already scored the
  kernel ABOVE the single-cell architecture predictively, so the control's
  role (no wild behavior at a data-rich site) is met: head invariant, tail
  corrected, predictive standard favors the kernel.
- lambda_latitude = Inf wins the PtCon LOBO too -- SECOND dataset rejecting
  the climate factor at regional scale (its home remains the continental
  presence curve).
- PtCon curve anchors recorded for the migration: theta_present = 2.59e-6
  (mass 1.86e-4 / Chao 72; f1 48, f2 16) -- a data-rich site prices unseen
  species ~80x finer than Burns Harbor, exactly as it should.
ALL FOUR PHASE-2 VALIDATION GATES NOW MET. Remaining for the PtCon kernel
MIGRATION (its own task, needs no NCBI for priors but a full consensus
re-run does): port Step 5 + 7a.7 to the kernel/curve path as in GL.
Also still open: iNat w = 0.8 calibration check; A2 discovery-rate
cross-check; manuscript supplemental-methods rewrite.

### KERNEL + CURVE MIGRATION: PtCon 12S, PtCon 18S, BOTH MUGU (2026-09-01)

All four remaining workflows migrated (backups *.bak_pre_kernel_migration;
all parse; NONE yet run -- Mugu verification is the next real run, per the
user). Pattern per file: USE_KERNEL_PRIORS switch, GLMM verbatim in the
else, geographic-only kernel (no depth_m at any of these sites --
[[project_depth_covariate_propagation]] still pending), curve-pricing
evidence with the packaged generators, branch-budget audit,
plot_theta_map_interactive gated to the GLMM branch (Grid_*-id parser).
File-specific notes:
- PtCon 12S: straight GL mirror (domestic -> watch-lift -> regional-kept ->
  clamp; no iNat block, matching its legacy scope); metadata conditionals.
  Gate-d control already validated this site (lambda 25 km).
- MuguFishWorkflow: kernel branch has its own PROVENANCE-CHECKED priors
  cache gate (a GLMM-era cached table without resident_observed
  prior_branch rows is regenerated, never silently loaded); interactive
  theta map gated.
- MuguWilderFishWorkflow: same, PLUS the curve branch ADDS the
  regional-proximity distance pass this workflow never had (it is the
  pricing instrument; first run pays the GBIF tile checks). Legacy branch
  untouched (still no regional block there).
- PtCon 18S: PER-SAMPLING-GROUP kernel fits (one estimate_kernel_priors per
  group, mirroring the per-group GLMM loop; composition only means anything
  within a detection-process group), bandwidth calibrated once on the pooled
  stratum, kernel_fits saved as the model_fits analog. Evidence keeps the
  LEGACY SCOPE (domestic + watch only; watch prices at the lifted clamp, no
  distance pass) via the POOLED kernel fit as the applier representative --
  the same cross-group approximation the legacy .domestic_food_model made.
  FLAGGED OPEN (not decided): per-group theta_present for evidence pricing,
  and whether 18S gets the regional distance pass + clamp (costs a large
  GBIF pass over a many-kingdom match list).

NEXT REAL RUNS: Mugu verification (user, next session); full GL workflow
run in flight (user). PtCon accession screen still NCBI-throttled -- advice
given (NCBI_KEY, off-peak, trust_insufficient_evidence / defer the screen).
