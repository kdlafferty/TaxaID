# TaxaLikely (development version)

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
