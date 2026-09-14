# TaxaLikely (development version)

## 2026-09-14, later

* `fetch_ncbi_reference_sequences()` no longer lets a failed NCBI count query
  silently remove a taxon from the reference database. A count failure sets
  that taxon's count to `NA`, which the sequence-budget step excludes, which
  sets its fetch cap to zero -- so the taxon contributed NO reference
  sequences while emitting only one easily-missed warning. Found on the real
  2026-09-14 PtConception 12S run: 7 taxa failed (the first 7 queried, after
  which every remaining query succeeded) and 352 species-level consensus rows
  were left resting on no reference data of their own, including
  *Medialuna californiensis*, *Zalophus californianus*, *Tursiops truncatus*,
  *Apodichthys flavidus* and *Cymatogaster aggregata*. Re-issuing the
  identical queries afterwards succeeded for all 7, and two earlier runs in
  the same log had executed the identical code path with zero failures, so
  the failures were transient NCBI throttling rather than anything to do with
  the taxa or the search terms. The vulnerable code dates to 2026-05-20; this
  was a latent gap, not a recent regression.
* New `count_attempts` (default `3L`) retries each count query with
  exponential backoff, which addresses the actual transient cause.
* New `on_count_failure` (`"warn"`, the default, or `"error"`) decides what
  happens when a count still fails after every attempt. `"warn"` now reports
  every affected taxon BY NAME in a single consolidated warning and message
  that states the consequence rather than just the cause -- the original
  design emitted one warning per taxon, and seven of them went unnoticed in a
  17,000-line log, so the failure mode was silence-by-dilution rather than an
  absent warning. `"error"` suits an unattended production run, where a
  silently degraded reference database is worse than a failed run.
* The returned `reference_df` now always carries a `count_failures` attribute
  naming any dropped taxa, so a workflow can assert on
  `attr(reference_df, "count_failures")` instead of parsing the log.
* Sampling semantics are deliberately unchanged: a taxon whose count is
  unknown is still excluded rather than fetched under a guessed cap. Whether
  an unknown count should instead fall back to `min_per_taxon` is a real
  design question, left open rather than decided as part of a bug fix.

## 2026-09-14

* Fixes a false positive in the 2026-09-13 bimodality diagnostic
  (`R/bimodality.R`), found on the real PtConception 12S production run:
  percent identity on a short, fixed-length amplicon is DISCRETE, not
  continuous (a ~167bp amplicon can only take values spaced by roughly one
  mismatch's worth of identity -- measured `0.6` apart on that run, e.g.
  98.8/99.4/98.2). Real match-score data therefore forms a "comb" of spikes
  at each mismatch count with LITERAL zero density in the gaps between
  teeth, which the pre-existing density-valley guard read as a genuine
  antimode between two populations, and a 2-component Gaussian mixture
  always wins by a wide margin on comb-like data (`delta_bic` in the
  thousands was routine). `calibrate_query_noise()` warned "H1 scores look
  bimodal: 4% near 95.4 (sd 3.0) and 96% near 98.8 (sd 0.4), delta BIC 8297"
  on data that was genuinely unimodal, and `train_likelihood_model()`'s own
  `Stats$h1_bimodality` independently flagged the identical artifact from
  the training side (weights 0.323/0.677, means 98.3/100, sds 3.26/0.0202 --
  the "second component" was just the reference-matches-itself spike at
  exactly 100, a structural feature of every reference-based dataset).
* New internal `.estimate_score_quantum()` estimates the identity-per-
  mismatch spacing directly from the data (median gap between the
  dominant, by-count, distinct values), returning `NA` -- i.e. "behave
  exactly as before" -- whenever the data don't look discretely comb-shaped
  at all (most continuous data, including a genuine platform mixture,
  estimates no quantum).
* New internal `.smooth_comb()` deterministically smooths a comb-shaped
  vector at its estimated quantum before fitting, by spreading each tied
  group of observations evenly across its own quantum-wide cell -- a
  dependency-free continuity correction (Sheppard's-correction-style
  convolution with a `Uniform(-quantum/2, quantum/2)` kernel) that closes
  the literal zero-density gaps between comb teeth without disturbing a
  real, multi-quantum gap between two genuinely separate populations.
  Deterministic by construction (no `runif()`/`sample()`/`jitter()`): two
  calls on the same input always agree exactly.
* `.bimodality_check()` now additionally requires (on top of the unchanged
  delta-BIC, mean-separation and density-valley conditions from
  2026-09-13): the minority fitted component to hold at least
  `min_minority_weight` (default `0.15`) of the mass -- "a thin tail cannot
  be called a mode," and this alone rejects the real 4%-minority false
  positive above -- and the two fitted means to be separated by more than
  `quanta_separation_multiplier` (default `3`) quanta when a quantum was
  found, not just the flat `1.0` percentage point (which is under two
  mismatches on a 167bp amplicon), rejecting the real 1.7-point/2.83-quanta
  `train_likelihood_model()` false positive above. `.bimodality_check()`'s
  return value gains a `quantum` field.
* Validated: the genuinely bimodal fixture (a real measured Nanopore shape,
  20.3% spike at exactly 100 on an otherwise-continuous population -- itself
  discrete at the spike, the real test of whether this fix throws the baby
  out) still flags, byte-identically to before this fix, since it estimates
  no quantum at all; the existing unimodal and ceiling-skewed-unimodal
  fixtures still do not flag; a new explicit-comb fixture (scores only at
  integer-mismatch positions with a realistic decaying frequency profile and
  no second population) does not flag; and the exact real false-positive
  shapes from both `calibrate_query_noise()` and `train_likelihood_model()`
  are reproduced as synthetic combs and confirmed not to flag, including an
  end-to-end reproduction through `calibrate_query_noise()`'s real call path
  against the actual PtConception 12S checkpoints that produced the original
  warning. `train_likelihood_model()` keeps recording `Stats$h1_bimodality`
  either way -- only the warning is gated by the stricter rule.
* Roxygen on both `calibrate_query_noise()` (new "Percent identity is
  discrete, not continuous" `@section`) and `train_likelihood_model()`
  (updated "H1 bimodality (recorded, not warned)" `@section`) now states the
  discreteness problem and the fix plainly.

## 2026-09-13

* New bimodality diagnostic for H1 (known-species) scores (`R/bimodality.R`):
  `train_likelihood_model()` fits one Gaussian per species, and
  `calibrate_query_noise()`'s `offset_form = "linear"` fits one line across
  species -- both assume a unimodal H1 score distribution, which mixed
  sequencing platforms (or markers, or primer sets) can silently break. New
  internal `.bimodality_check()` fits a 2-component normal mixture by a
  dependency-free base-R EM (`.fit_two_component_normal()`, deterministic
  init, sd-floored so a component landing on a repeated value -- e.g. a real
  platform's spike at exactly 100 -- cannot collapse to zero variance) and
  flags bimodality only when the 2-component fit beats 1 component by
  `delta_bic > 10` (Kass & Raftery 1995's "very strong" evidence band,
  verified against the paper directly), the two means are separated by more
  than 1 percentage point, AND the fitted mixture density has a genuine
  antimode between the two means (`.mixture_has_valley()`) -- the third
  condition, found necessary during testing, is what keeps a ceiling-skewed
  but genuinely unimodal H1 distribution (real match data piles up near 100%
  identity by construction) from false-positiving, exactly the failure mode
  that ruled out a simpler bimodality-coefficient test for this diagnostic.
  `calibrate_query_noise()` now runs this check on the confident-observation
  score vector it already computes and emits ONE `warning()` naming the
  fitted structure in plain numbers when it fires (never changes any fitted
  value, never refuses to calibrate). `train_likelihood_model()` runs the
  identical check on its own real H1 training scores and records the result
  in the new `Stats$h1_bimodality` -- it does not warn (the warning belongs
  at calibration time, per the user's decision, since that is the point a
  single offset/line is actually about to be applied).

## 2026-09-10

* `train_likelihood_model()`: new `min_pair_coverage` (default `0.8`) -- only a
  reference pair at or above the match object's own coverage floor
  (`TaxaMatch::blast_sequences(min_query_coverage)/100`) may define a reference's
  best foreign, congener or conspecific match when the gap feature is trained.
  No pair is removed and no species is dropped. Fixes a real defect: short-overlap
  100%-identity pairs defined 86% of references' "best foreign match" on real 12S
  data, training a negative gap. Every `lik_model` trained before this is stale.
* `train_likelihood_model()`: new `shrinkage = c("empirical_bayes", "fixed")`
  (default `"empirical_bayes"`): per-species H1 mean score/gap shrunk with an
  estimated between-species variance (`tau^2/(tau^2 + sigma^2/N)`) instead of the
  fixed `N/(N + prior_weight)`. `H1_Lookup` gains `shrink_w_score`/`shrink_w_gap`;
  `Stats` gains `shrinkage`, `tau2_score`, `tau2_gap`, `min_pair_coverage`,
  `n_self_fallback`, `n_foreign_unqualified`.
* `evaluate_likelihoods()`: warns when the match object admits lower alignment
  coverage than the model's `min_pair_coverage` (reads the floor recorded by
  `blast_sequences()`, else the observed minimum `query_coverage`).
* Validated on the real GreatLakes workflow code path against the Lamar species
  list: co-detections 593 -> 798, precision 0.805 -> 0.818, 29 -> 41 of 61 species.

## 2026-09-08/09

* `flag_reference_errors()`/`remove_flagged_references()` retired; training
  no longer auto-removes references on that screen (c15f0fe).
* `compute_likelihoods()`/`model_likelihoods()` archived (ad97447).
* 12 fixes from the post-checklist review (8ffba9a).

## Polishing Phase (Sessions 57-59)

* `evaluate_likelihoods()`: new `verbose` param logs species-specific
  parameter fallback to global mean.
* `train_likelihood_model()`: `traitor_threshold` renamed to
  `mislabel_threshold`.
* `.build_search_term()`: protein-coding genes (COI, cytb) use `[GENE]`
  field tags; ribosomal subunits (12S, 16S, 18S, 28S) and primer names
  use `[All Fields]` (NCBI does not reliably index rRNA under [GENE]).
* Internal helpers moved to TaxaTools: `barcode_length_defaults`,
  `resolve_barcode_lengths()`, `is_valid_species_name()`.
* Deleted stale monolithic workflow (`inst/TaxaLikely_workflow.R`).
* Added vignette: score-to-likelihood.Rmd.
* Added tests for `fetch_reference_sequences()`, `read_reference_fasta()`,
  and `.build_search_term()`.

## 0.0.0.9000

* Package created (Session 30, 2026-03-27).
