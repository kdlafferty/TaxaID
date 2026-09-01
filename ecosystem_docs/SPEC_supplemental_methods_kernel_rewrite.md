# SPEC: rewrite TaxaExpect supplemental methods for the kernel-priors era

Written 2026-09-01 (Fable 5 session, at the user's direction). For a
delegated agent. The user is a statistician; this text is manuscript
supplemental material and will be read by reviewers.

## The job

`TaxaExpect/inst/TaxaExpect_supplemental_methods.md` currently documents the
RETIRED grid/GLMM prior architecture (verified 2026-09-01: zero occurrences
of "kernel" in the file). Rewrite the prior-estimation sections to describe
what the package actually does now, preserving the file's existing
structure, numbering, and voice.

## Required reading before writing (in this order)

1. `ecosystem_docs/REENTRY_PROMPT_evidence_ceiling_and_habitat_bleed.md` --
   READ BOTTOM-UP. The last ~6 sections carry the whole arc: the Phase 1
   spec, Phase 2 verdicts, the B8 validation, the curve-pricing design, the
   PtCon control. This is the authoritative design record.
2. `TaxaExpect/R/estimate_kernel_priors.R` and
   `R/calibrate_kernel_bandwidth.R` (the estimator and its calibrator) and
   `R/apply_undetected_evidence.R` (the `pricing = "curve"` path) --
   the code is the final authority on what is actually implemented.
3. `TaxaAssign/R/generate_report.R`, the `kernel_priors` branch of
   `.build_methods_text()` -- an accurate, already-reviewed prose summary of
   the same material. Use it as a starting point; the supplemental version
   should be fuller and more technical.

## What the rewritten sections must cover

- **Kernel estimation**: habitat stratification; the geographic kernel
  `exp(-d/lambda)`; the optional covariate product kernel (depth, validated
  out-of-sample at GreatLakes) and the optional absolute-latitude climate
  factor (implemented, opt-in, and REJECTED by leave-one-block-out at both
  GreatLakes and PtConception at regional scale -- say so plainly, it is an
  honest negative result); the Dirichlet back-off of `m` pseudo-records
  toward regional composition; Kish effective sample size `n_eff` as the
  Beta concentration, so prior spread reflects how much local evidence
  exists.
- **Bandwidth selection by prediction, not fit**: leave-one-block-out
  composition prediction (multinomial log-loss) replaces AIC-based formula
  screening. Report the empirical finding that motivated the pivot: the
  single-nearest-cell predictor (the retired architecture) scored WORSE than
  ignoring space entirely, while the kernel beat both.
- **Unobserved taxa (curve pricing)**: theta = w * theta_present with
  theta_absent = 0; `theta_present` = Good-Turing missing mass divided by
  the Chao estimate of unrecorded-but-present species; the presence-distance
  curve `w = w_scale * exp(-min(d, d_cap)/(k * d_half))` with the
  bandwidth-stretch k for watch-listed species and the distance clamp for
  non-regional species (justified because beyond the search radius the tail
  is dominated by distance-insensitive human-vectored transport); the
  independent-instrument treatment of verified iNaturalist range evidence.
- **The budget audit**: sum of presence probabilities across named
  claimants versus the Chao estimate, in count units -- AUDITED, not
  enforced. State the reasoning for not enforcing: enforcement makes each
  species' prior depend on how many other species happen to be enumerated,
  and probability constraints bind at per-observation renormalization.
- **The compositional framework**: the simplex is the RESIDENT community
  (observed shares plus the Good-Turing unseen mass, whose interior is
  deliberately not enumerated); transport (domestic/food, and bleed when
  built), non-regional species, and invaders are presence-weighted
  hypotheses OUTSIDE that simplex, each calibrated against its own
  measurement, all in commensurable units (expected share of a random
  record) because rows meet inside candidate sets.
- **Schema**: `prior_branch` + `effective_records` replace `model_tier`.
- **The grid/GLMM predecessor**: the user's explicit instruction is to
  mention BRIEFLY that a grid-cell GLMM approach was considered and
  abandoned, with the empirical reason (above). One short paragraph, not a
  section; no extended post-mortem.
- **Validation**, reported as fact with its scope stated: at GreatLakes
  (held-out external checklist), species co-detections rose 237 -> 594 and
  species-level precision 0.748 -> 0.853-0.868 across the kernel and
  curve-pricing changes; at PointConception (a data-rich site used as a
  near-invariance control) the kernel reproduced the GLMM's abundant-species
  estimates within 3-5% (tier1 Spearman 0.927), with divergences confined to
  habitat-bleed and epsilon-clamped rows.

## Citations

These classical references are correct, standard, and may be cited:
Good (1953, Biometrika 40:237-264, population frequencies of species);
Chao (1984, Scand J Stat 11:265-270, nonparametric estimation of the number
of classes); Kish (1965, Survey Sampling, Wiley, design effect / effective
sample size). Any citation already present in the file stays.
DO NOT invent, guess, or "recall" any other reference. If a claim seems to
want a citation you cannot verify from the file or the design record, write
the claim without one and flag it in your final report.

## Constraints

- Preserve the file's existing section structure/numbering and its heading
  style; rewrite prior-estimation content in place rather than appending a
  new parallel section. Sections about other machinery stay untouched.
- ASCII only. No em-dashes rendered as unicode; follow the file's existing
  conventions.
- NOTHING may be claimed that the code does not do. Where the design record
  and the code disagree, the CODE wins -- and say so in your report.
- No package code changes, no tests, no `devtools::install()`. This is a
  documentation task. Running `devtools::check("TaxaExpect")` at the end is
  a courtesy sanity check only (inst/ markdown does not affect it).
- Note in your final report anything you found stale in the file BEYOND the
  prior-estimation sections (do not fix it unilaterally).
- Work on branch `supplemental-methods-kernel`, commit with messages ending
  `Co-Authored-By: Claude Sonnet <noreply@anthropic.com>`.

## Status

- 2026-09-01: written, delegated.
