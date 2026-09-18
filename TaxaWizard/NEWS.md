# TaxaWizard 0.1.0

## 2026-09-18

* `inst/metadata/*.json` (94 hand-maintained function-signature entries) and
  `R/metadata.R` deleted. New `R/registry.R` / `workflow_registry()`
  introspects the installed TaxaID packages at runtime (`getNamespaceExports()`
  / `formals()` / `tools::Rd_db()`), cached under
  `tools::R_user_dir("TaxaWizard", "cache")` keyed on package version AND
  `packageDescription()$Built`. Every consumer (`workflow_engine()`,
  `.build_phase_prompt()`, `.get_path_context()`, `.extract_param_docs()`,
  `workflow_create()`) now reads the registry instead of the old JSON.
* `workflow_engine(metadata = )` renamed to `workflow_engine(registry = )`;
  `metadata` still accepted with a deprecation warning.
* `inst/prompts/system_prompt.md` and `phase_parameterize.md`: removed every
  sentence that hard-coded a specific function's parameter names or package
  (these are now sourced solely from the generated FUNCTION
  REGISTRY / PARAMETER DOCUMENTATION blocks, so they cannot drift out of
  sync with the installed packages the way hand-typed prompt text could).
* `diagnostics/taxawizard_metadata_audit.R` deleted (nothing left to audit).
* New `tests/testthat/test-registry.R` replaces
  `test-metadata-covers-workflow-functions.R`.

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
