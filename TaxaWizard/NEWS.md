# TaxaWizard 0.1.0

## 2026-09-13

* `.extract_param_docs()` now reads the metadata `inputs` key -- previously
  every function rendered as "(no params)".

## 2026-09-09

* GLMM-path edges `std_to_dist`, `dist_to_priors`, `taxa_to_priors_wrapper`
  deleted; `dist_to_priors_by_group` repointed to `estimate_kernel_priors()`.

## 2026-09-08

* `matrix_to_clean` rewritten around
  `TaxaMatch::corroborate_references_locally()`/`evaluate_reference_accessions()`.

## 2026-09-07

* Metadata resynced against current signatures (1b1af81).
* New `std_to_priors_kernel` edge and reference-screening snippets (4aff5a1).
* Generated files may contain backslashes; app allow-list hardened (1ba54d8).
