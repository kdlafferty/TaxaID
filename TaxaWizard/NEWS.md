# TaxaWizard 1.0.0

* Initial release.

## Changed behaviour

* The prompt pack written by `workflow_export_prompts()` carries every
  function's `\details` and each titled `\section` after its Value line,
  keeping paragraphs, list items and code, so a context file states the same
  rules, defaults and caveats as the help page.
* The consensus snippets and graph edges teach the individual steps
  (`evaluate_likelihoods()`, `filter_top_hypotheses()`, `join_priors()`,
  `compute_posterior()`, and the two `posterior_consensus()` rounds with
  `update_prior_from_consensus()`) in order.
* The `refs_to_matrix.R` snippet carries the production settings of
  `build_sequence_matrix()` (`by_genus`, `pair_retention`,
  `max_seqs_per_taxon`) with the reason for each, and notes that the build
  draws at random so a seed is required.
* The citation text in the generated app states that the software is
  provisional and not yet citable.
