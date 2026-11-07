# F10: the shipped defaults and the values production passes

Fable's final package review (F10) found that every shipped consensus default
is overridden by every production run AND by the workflow template and the
wizard snippet. A default nothing uses is not a default; it is a second,
untested code path that the documentation presents as the normal one.

This document is the pre-registered hunk list for that change, kept because
the list was agreed before the edits were made and the reasoning for what was
left out matters more than what went in.

## What production passes, checked before anything was edited

Each flip below was verified against the live workflow scripts in
`~/My Drive/Rscripts/eDNA` (CalIntertidal, PtConception 12S and 18S,
SepulvedaMugu) and `~/My Drive/Stats and Data/GreatLakes data`, plus the
shipped `inst/TaxaID_Workflow_Template.R` and
`TaxaWizard/inst/graph/snippets/post_to_consensus.R`.

| argument | function | ships | production passes |
|---|---|---|---|
| `consensus_method` | `posterior_consensus()` | `c("credible_node", "lca")` | `"credible_node"` |
| `robust_prior_s` | `posterior_consensus()` | `0` | `0` |
| `cross_phylum_eps` | `posterior_consensus()` | `0` | `0` |
| `n_sims` | `update_prior_from_consensus()` | `1000` | `1000L` |
| `score_transform` | `train_likelihood_model()` | `"sqrt_mismatch"` | `"sqrt_mismatch"` |
| `ratio_threshold` | `evaluate_likelihoods()` | `0` | `0` |
| `check_regional_overlap` | `restore_suppressed_candidates()` | `TRUE` | `TRUE` |

`ratio_threshold = 0` carries a written reason at
`PtConceptionWorkflow_12S_single_site.R:2230`: a positive threshold makes a
cross-rank comparison that can suppress a legitimate but weak H1 match, and H1
rows are already gated by the Mahalanobis and alpha checks.

`robust_prior_s = 1` was the maintainer's decision of 2026-10-01, recorded in
`TaxaAssign/inst/taxaassign_review_response.md` as "on by default,
`robust_prior_s = 0` turns it off, to be revisited if an evaluation says so".
The 2026-10-15 r5 decision (weighted LCA by node summing only) and every
production caller passing `0` are that revisiting, not a reversal of it.

The old values keep a live caller:
`GreatLakes2023_ConsensusWorkflow.R:2284-2285` passes `robust_prior_s = 1` and
`cross_phylum_eps = 0.05` explicitly for its LCA arm. This is a re-default,
not a removal.

## Internal helpers carry the same defaults

One argument must not have two different defaults -- the finding behind PR
#72. Four private helpers take one of these arguments and each had its own
default: `.prep_training_data()`, `.evaluate_one_query()`,
`.consensus_one_observation()` and `.add_prior_role()`. All four now match the
exported value, and tests assert the agreement so it cannot drift back.

## Held, with reasons

- **`lookup_missing_taxonomy = FALSE` stays.** `posterior_consensus()` aborts
  when `backbone_id` is `NULL` and the lookup is on, because the correct
  backbone depends on which one the input taxonomy was verified against. The
  flip would make every default call error, and would make a default call
  issue outbound network requests.
- **`seed = NULL` stays.** `check_cross_genus_sampling_noise()` calls
  `build_sequence_matrix()` once per replicate expecting a different draw each
  time. A fixed default seed would make every replicate identical and that
  diagnostic would report zero noise -- a plausible-looking wrong number
  rather than an error.
- **`max_per_genus = 500L` and `max_seqs_per_taxon = NULL` stay**, by the
  maintainer's decision. Removing the per-genus cap is the one flip where the
  production value is the more expensive one, raising NCBI fetch volume for
  every call that relies on the default.
- **`pair_retention` stays at `"all"`**, by the maintainer's decision of
  2026-11-06. Defaulting to `"best_per_partner"` would make the default
  training call ASSUME H3's gap instead of measuring it: `train.R`'s
  retention-aware fallback measures H3's gap only under `"all"` and
  `"best2_per_partner"`. A default that silently degrades a model parameter is
  the wrong direction, whatever the memory saving.
- **`TaxaLikely/inst/review_function_inputs.R`'s
  `make_calib_model_params(score_transform = "logit")` stays.** Its sigma
  matrix is hard-coded at logit-scale magnitudes on `score_logit`/`gap_logit`
  dimnames; pairing it with a sqrt-scale transform would be wrong, not just
  different.

## Blast radius

354 of 407 test call sites and 85 of 96 shipped call sites rely on at least
one of these defaults. Where a test's SUBJECT is the behaviour the old default
selected, the old value is pinned explicitly rather than the expectation
edited.

`check_regional_overlap = TRUE` is the only flip that can make a default call
ERROR rather than return a different number: `score_collapse.R:673-685` stops
when `match_obj` lacks `accession` or `reference_df` lacks
`composite_id`/`sequence`. The requirement is stated in the argument's own
documentation, and the alignment it enables is local
(`pwalign::pairwiseAlignment`), so no default call reaches the network.
