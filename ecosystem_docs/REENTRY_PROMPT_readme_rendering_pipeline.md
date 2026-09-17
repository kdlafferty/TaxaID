# RE-ENTRY PROMPT — Fix the README rendering pipeline

Written 2026-09-17. Scope is **the rendering pipeline only** — do not edit the
substance of any README. Everything below was observed directly this session,
not inferred.

## The task

`ecosystem_docs/readmes/render_readmes.R` converts the ten ecosystem
`README.md` files to PDF. It is currently broken in a way that fails silently
for three packages, and the root `README.html` has no scripted rebuild at all.
Fix both, then verify by mtime rather than by exit status.

## Problem 1 — the script halts partway through, and the halt is invisible

`render_readmes.R` renders in this fixed order:

```
TaxaID, TaxaTools, TaxaFetch, TaxaHabitat, TaxaMatch, TaxaLikely,
TaxaExpect, TaxaAssign, TaxaFlag, TaxaWizard
```

It dies at **TaxaExpect** with:

```
! Unable to load picture or PDF file 'man/figures/theta_surface.png'.
l.183 ...inland.}]{man/figures/theta_surface.png}}
Error: LaTeX failed to compile .../TaxaExpect_README.tex.
Execution halted
```

The file **does exist** (`TaxaExpect/man/figures/theta_surface.png`). The bug
is in the script, not the README: it calls `rmarkdown::render()` without a knit
root / base directory, so TaxaExpect's relative image path cannot resolve from
the output directory. TaxaExpect is the only README with a figure, which is why
nothing else trips it.

Because `render_readmes.R` is a plain `for` loop with no error handling,
`Execution halted` means **TaxaAssign, TaxaFlag and TaxaWizard are never
reached**. Their PDFs are silently left at whatever was last built. As of
2026-09-17 all four (TaxaExpect, TaxaAssign, TaxaFlag, TaxaWizard) were still
dated **Jun 9**, while the six before TaxaExpect were rebuilt that day.

This is pre-existing. TaxaExpect's figure was added around 2026-09-12
(cf. `TaxaExpect/README.md.bak_pre_figure_20260912_141512`) and the script has
evidently not completed since.

### What to do

1. Make the relative figure path resolve. The natural fix is to render each
   README with its **own package directory** as the base — e.g. pass
   `knit_root_dir` / set `intermediates_dir`, or `setwd()` into the package dir
   for the duration of the call and restore after. Whichever you choose, the
   fix must work for a README that references `man/figures/*` relatively,
   because that is the convention the package READMEs use and more figures are
   likely.
2. Wrap each iteration in `tryCatch()` so one package's failure cannot abort
   the other nine. Collect failures and print a summary at the end.
3. Make the ending explicit: print a per-package PASS/FAIL table with each
   output PDF's mtime, and `stop()` at the very end if any failed. Right now a
   partial run and a full run look the same in the console.

## Problem 2 — `README.html` has no scripted rebuild

The root `README.html` (~800 KB) is a full `rmarkdown::render(html_document)`
output: 2 mermaid blocks, 9 tables, MathJax, syntax highlighting. It is **not**
a plain pandoc call, and it is **untracked by git**, so a bad overwrite is not
recoverable through git.

It was rebuilt this session with:

```r
Sys.setenv(RSTUDIO_PANDOC =
  "/Applications/RStudio.app/Contents/Resources/app/quarto/bin/tools/aarch64")
rmarkdown::render("README.md", output_format = "html_document",
                  output_file = "README.html")
```

which reproduced the prior structure exactly (same 2 mermaid blocks, 9 tables,
16 `<h1>`, 7 `<h2>`) plus the new content.

### What to do

Fold this into the same script (or a sibling) so the HTML and the PDFs are
rebuilt together and never drift. Back the existing `README.html` up before
overwriting, since git will not.

## Constraints

- **Do not change any README's content.** If a README looks wrong, report it;
  do not fix it here.
- The `RSTUDIO_PANDOC` path hack at the top of `render_readmes.R` is load-
  bearing on this machine — keep it, but make it a `if (!nzchar(Sys.getenv(...)))`
  guard rather than an unconditional overwrite, so the script also works where
  pandoc is already on the path.
- TinyTeX is already installed; the one-time install branch can stay as-is.

## Definition of done

Run `Rscript ecosystem_docs/readmes/render_readmes.R` and then:

```bash
ls -la ecosystem_docs/readmes/*.pdf
```

**All ten PDFs must carry today's date.** The script must print a PASS/FAIL
line per package. Re-run it with a deliberately broken README (e.g. point a
figure at a nonexistent file in a scratch copy) and confirm the other nine
still render and the summary reports the one failure.

Also confirm `README.html` rebuilds and still contains `class="mermaid"` twice
and `<table` nine times — a silent drop of the mermaid diagrams is the most
likely regression.

## Related

- `reference-render-readmes-taxaexpect-bug` in memory records the symptom.
- The root `README.md` gained a Related Software subsection and four references
  on 2026-09-17 (BIOWATCH / Pest Alert Tool / TaxonTableTools / CRABS), which is
  why the stale renders were noticed. That content is correct and committed —
  it needs re-rendering, not editing.
