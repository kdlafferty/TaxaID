# TaxaID Publication Checklist

## Documentation

- [ ] Write README.md for each package (7 files)
  - Purpose, installation, quick example, link to vignette
- [ ] Write ecosystem-level README.md for TaxaID/
  - Pipeline diagram, package table, installation order, link to MEE paper
- [ ] Review/edit Claude Code attribution (`inst/CLAUDE_ATTRIBUTION.md`)
  - Add one-liner to each package README.md
  - Include in MEE manuscript methods section

## Workflow testing and debugging

- [ ] Run Bayesian workflow end-to-end on real eDNA dataset
- [ ] Run LLM workflow end-to-end on same dataset
- [ ] Run wrapper functions (`build_priors()`, `run_bayesian_pipeline()`, `run_llm_pipeline()`) on same dataset
- [ ] Compare Bayesian vs LLM vs score-based consensus results
- [ ] Fix whatever breaks
- [ ] Save worked example outputs for manuscript figures

## MEE manuscript

Target journal: Methods in Ecology and Evolution ("Application" format, ~3000-5000 words)

- [ ] **Introduction** — Taxonomic assignment problem; why Bayesian; gap in tools
- [ ] **Overview** — 7-package pipeline; two workflows; design philosophy
- [ ] **Statistical methods** — Adapt from `TaxaLikely/inst/TaxaLikely_supplemental_methods.md`
  - Hierarchical likelihood model (H1/H2/H3)
  - Prior construction from occurrence data
  - Posterior computation + consensus
- [ ] **Worked example** — Real eDNA data through both pipelines
  - Dataset description
  - Results comparison (Bayesian vs LLM vs score consensus)
  - Sensitivity analysis (threshold, prior weight)
- [ ] **Discussion** — When to use which pathway; limitations; extensibility
- [ ] **Data/code availability** — GitHub URL, CRAN links, data DOI

### Figures

- [ ] Pipeline diagram (text-based or proper figure)
- [ ] Likelihood landscape (adapt from `TaxaLikely/inst/plot_likelihood_landscape.R`)
- [ ] Posterior comparison: Bayesian vs LLM vs score consensus
- [ ] Map of study site with prior surface (TaxaExpect output)
- [ ] Sensitivity analysis plots

### Existing manuscript seeds

- `TaxaLikely/inst/TaxaLikely_supplemental_methods.md` — 10-section statistical methods
- `TaxaExpect/inst/TaxaExpect_supplemental_methods.md` — spatial GLMM prior estimation
- `TaxaAssign/inst/TaxaAssign_supplemental_methods.md` — Bayesian posterior + consensus
- `TaxaTools::draft_methods_text()` — LLM-assisted methods drafting
- `TaxaTools::draft_results_text()` — LLM-assisted results drafting
- `TaxaAssign::generate_report()` — Automated methods + results text

## CRAN preparation (deferred from polishing roadmap)

- [ ] Convert `\dontrun{}` to runnable examples for pure-computation functions
  - Priority: `clean_taxon_names()`, `compute_posterior()`, `score_consensus()`,
    `is_valid_species_name()`, `resolve_barcode_lengths()`
- [ ] Bump versions from 0.0.0.9000 to >= 0.1.0
- [ ] Set up GitHub repos
- [ ] Optional: pkgdown site for each package or unified ecosystem site
- [ ] Submit to CRAN in dependency order:
  TaxaTools → TaxaFetch → TaxaHabitat → TaxaMatch → TaxaLikely → TaxaExpect → TaxaAssign

## Order of operations

1. Workflow testing and debugging (validates the science)
2. MEE manuscript draft (uses worked example outputs)
3. README files (quick, can parallel with manuscript)
4. CRAN deferred items (mechanical, do before submission)
5. GitHub setup + CRAN submission (after manuscript accepted or submitted)
