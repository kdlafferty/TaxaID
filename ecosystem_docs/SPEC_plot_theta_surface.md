# SPEC: plot_theta_surface() -- the KDE prior-field map for the kernel path

Written 2026-09-01 (Fable 5 session, at the user's direction). For a
delegated agent. Design origin: the "Display companion" clause of the
Phase 1 spec in
`ecosystem_docs/REENTRY_PROMPT_evidence_ceiling_and_habitat_bleed.md`.

## Why this exists / what it replaces

`TaxaExpect::plot_theta_map_interactive()` renders per-GRID-CELL theta by
parsing `Grid_<lat>_<lon>` identifiers into centroids. The kernel-priors
redesign produces ONE site row with an opaque `site_id`, so that function
has nothing to draw: it is currently gated OFF on the kernel path in all
five production workflows (`if (!USE_KERNEL_PRIORS) plot_theta_map_...`).
Heat maps were the ORIGINAL motivation for this package's spatial work, so
this is a capability restoration, not a nicety.

`plot_theta_surface()` replaces it for kernel priors by evaluating the SAME
estimator on a lattice of points instead of at one site, so the map IS the
prior field -- not a smoothed picture of something else. Keep
`plot_theta_map_interactive()` as-is for the (deprecated but live) GLMM
path; do not modify or delete it.

## The estimator, on a lattice

For evaluation point x and the habitat-stratified record set (exactly the
stratification `estimate_kernel_priors()` applies):

    w_r(x)      = exp(-d(x, r)/lambda)            [ * optional factors ]
    W(x)        = sum_r w_r(x)
    S2(x)       = sum_r w_r(x)^2
    n_eff(x)    = W(x)^2 / S2(x)                  [Kish]
    c_i(x)      = sum_{r in species i} w_r(x)
    theta_i(x)  = (c_i(x) * n_eff(x)/W(x) + m * p_i) / (n_eff(x) + m)

`p_i` is the same unweighted habitat-stratified regional composition the
estimator uses. This reduces to `estimate_kernel_priors()` exactly when x is
the site -- MAKE THAT A TEST (see Acceptance).

Compute all three surfaces (species-i indicator, all records, all records
with squared weights) by BINNED FFT CONVOLUTION: bin records onto the output
lattice, convolve with the kernel evaluated on the same lattice via
`stats::fft` (zero-padded, standard 2-D circular-convolution avoidance).
Measured budget from the design work: ~0.28 s per 512x512 surface from 1.25M
records. No new package dependency for this -- `stats::fft` is base.

## Covariate and latitude factors

The geographic kernel and the optional absolute-latitude climate factor are
both functions of position, so they belong in the surface. The COVARIATE
factor (e.g. depth) is a per-record attribute, not a function of map
position: a 2-D surface cannot represent it unless the covariate is held
fixed. Provide `covariate_at = NULL` -- when supplied along with
`covariate_col`, records are weighted by `exp(-|c_r - covariate_at|/
lambda_covariate)` (constant across the lattice, so it just reweights
records); when `NULL`, the covariate factor is omitted and the returned
object/plot must SAY SO (documented + a message), never imply the map shows
a depth-conditioned field when it does not.

## Signature (proposed; adjust with reason)

    plot_theta_surface(kernel_fit, occurrence_data, taxon,
                       n_grid = 256L, bbox = NULL, m = NULL,
                       covariate_at = NULL, alpha_by_n_eff = TRUE,
                       n_eff_floor = NULL, interactive = FALSE, ...)

- `kernel_fit`: a `taxaexpect_kernel_priors` object -- the source of
  `lambda_km`, `m`, `lambda_latitude`, `covariate_col`,
  `lambda_covariate`, `site_habitat`, and the site coordinates (mark the
  site on the map). Parameters must default from it so the surface cannot
  silently drift from the priors it claims to depict.
- `taxon`: one species name (a character vector of several is a reasonable
  extension: return a list / facet).
- `alpha_by_n_eff`: shade/fade regions where `n_eff(x)` is low, so a reader
  cannot mistake an extrapolation for an estimate. `n_eff_floor` masks
  outright below a threshold.
- `interactive = TRUE`: leaflet overlay (leaflet is already in TaxaExpect's
  Suggests; guard with `requireNamespace()` exactly as
  `plot_theta_map_interactive()` does). `FALSE` returns a static plot.
- Return the surface data (lattice + theta + n_eff) alongside/attached to
  the plot object so a caller can inspect or re-render without recomputing.

## Acceptance (all offline, synthetic fixtures)

- **Site-identity invariant (the critical one)**: evaluated at the site
  coordinates, the surface's theta for a species equals
  `estimate_kernel_priors()`'s theta for that species to numerical
  tolerance, for the same kernel settings including `m` and (separately)
  with a latitude factor.
- **Top-hat limit**: with a very large lambda the surface flattens to the
  regional composition.
- **n_eff surface**: matches a direct (non-FFT) computation on a small
  fixture -- i.e. verify the FFT convolution against brute force.
- **Covariate honesty**: `covariate_at = NULL` on a fit built WITH a
  covariate emits the documented message and omits the factor.
- **Zero-record species / empty bbox**: returns gracefully, no error.
- Full suite: `devtools::test("TaxaExpect")` 0 failures (current baseline
  829 passing); `devtools::check("TaxaExpect")` 0 errors/0 warnings (a
  pre-existing environmental NOTE is acceptable).

## Deliverables the user explicitly asked for

1. The function, exported, with full roxygen (including a
   `@section Relationship to plot_theta_map_interactive()` stating plainly
   what it replaces and why the old one cannot serve kernel priors).
2. **A written record of what this replaces and every adjustment the
   package/workflows need** -- put it in this spec's Status section AND in
   `TaxaExpect/CLAUDE.md`'s top note. Include: the five workflows'
   `if (!USE_KERNEL_PRIORS) plot_theta_map_interactive(...)` gates that
   should become calls to the new function (list them by file and line;
   DO NOT edit those workflow files -- they live outside this repo and the
   main session will wire them), and any `Suggests`/NAMESPACE changes.
3. Ecosystem `CLAUDE.md` Recent Breaking Changes row (additive) +
   `ecosystem_docs/NAME_CHANGE_HISTORY.md` row.

## Constraints

- NO network calls. NO `devtools::install()` (the main session installs).
- Before any Rscript: `.libPaths(c(path.expand(Sys.getenv("R_LIBS_USER")),
  .libPaths()))`.
- ASCII only; native pipe; `.`-prefixed `@noRd` internals;
  `utils::globalVariables()` first line where NSE is used; no blank lines
  inside `@param`; never split a sprintf format string across arguments.
- Do not modify `estimate_kernel_priors()`'s behavior. If you need a value
  it does not expose, prefer recomputing from `occurrence_data` + `$params`
  over changing the estimator; if a change is genuinely required, make it
  additive and say so prominently in your report.
- Branch `theta-surface`; commits end
  `Co-Authored-By: Claude Sonnet <noreply@anthropic.com>`.

## Status

- 2026-09-01: written, delegated.
