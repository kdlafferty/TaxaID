# Re-entry prompt — update the contaminant snippet, AFTER TaxaFlag is installed

**Written 2026-09-20 by `lafferty-45`.** Queued work that is blocked on an install,
recorded so it is not lost. Nothing here is started.

---

## THE BLOCKER, and why it is not optional

`TaxaWizard/inst/graph/snippets/consensus_to_flagged.R` should pass
`flag_contaminant()`'s new evidence-gating arguments. It cannot yet:
`.validate_snippets()` checks a snippet's named arguments against the **installed**
formals, and installed TaxaFlag (Built 2026-09-19 06:00:01 UTC) has none of
`require_control_evidence`, `site_col`, or the new `validate_controls()` export.
Adding them today makes TaxaWizard's own validator correctly reject the snippet.

**So: install TaxaFlag first, then do the work below.** Confirm with

```r
"require_control_evidence" %in% names(formals(TaxaFlag::flag_contaminant))
"validate_controls" %in% getNamespaceExports("TaxaFlag")
```

Both must be `TRUE` before starting.

---

## WHY IT MATTERS

`flag_contaminant()`'s default path assigns verdicts with no control evidence. On
the real archive the ungated path labels 12,283 of 16,826 12S ESVs and 26,876 of
34,899 COI ESVs non-valid; under the evidence gate the figures are 95 and 2,437.
Two orders of magnitude, and the taxa the ungated path surfaces are the target
community. Generated workflows are new work by definition, so TaxaWizard is
currently manufacturing the deprecated mode at scale, in scripts users run without
reading.

**One correction to carry forward.** The snippet does NOT print the questionable
tier -- it prints only the `invalid_{type}` count (line 20), and `questionable`
appears solely in the header comment at line 7 listing possible `validity_flag`
values. So the exposure is narrower than "a generated script prints that number".
It is still real: the snippet documents the tier with no caveat, and anything
downstream filtering `validity_flag != "valid"` sweeps the whole tier in.

---

## THE WORK

1. **Pass the gate.** `require_control_evidence = TRUE` and `site_col`, both as
   `{{placeholders}}` with Section 0 entries, matching how the snippet already
   handles `event_col`/`taxon_col`.
2. **Print the evidence beside the verdict.** At minimum `n_controls_present` and
   `n_controls_total`. A verdict with its evidence attached cannot be misread the
   way a bare tier count can; this is the change that would have made the problem
   visible years earlier.
3. **Caveat the tier in the header comment.** Say plainly that
   `questionable_{type}` is shrunk in READS and is not a contamination rate.
4. **Regenerate `llm_prompts/`** -- `validate_controls()` is a new export absent
   from the committed pack, so the equality test will fail until you do.
5. **Re-run** `.validate_snippets()`, the TaxaWizard suite, and
   `devtools::check()`.

---

## DO NOT WRITE "CARRYOVER" INTO USER-FACING TEXT YET

The `carryover` state WAS RENAMED, 2026-09-20 (see BLANK_VALIDATION_AND_CONTAMINANT_DESIGN.md). On the real archive it rescues some
*Homo sapiens*, *Sus scrofa* and *Bos* ESVs -- field-handling contamination that is
more abundant in samples than in controls, so it fails the control-enrichment test.
The statistic is right; the label overclaims, because all it establishes is "not
control-enriched" while "carryover" asserted a mechanism. The rename landed as a SPLIT into `not_control_enriched` + `single_site_enriched`, plus a new `insufficient_control_evidence` state from the `min_control_obs` floor. Superseded text follows:
> A rename to
`not_control_enriched` was with the user as of 2026-09-20. **Check what it settled
on before documenting this anywhere.**

---

## A DESIGN QUESTION, NOT PART OF THIS JOB

`.validate_snippets()` could not have caught this. Every argument the snippet
passes is real and valid; the defect is the arguments it OMITS. That is the same
blind spot that let the pooled-lambda snippet through -- a checker on call SHAPE
cannot see a semantically wrong argument SET.

A hardening exists in principle: flag calls omitting arguments a package marks as
recommended-for-new-work. It needs a machine-readable roxygen marker that does not
exist today, so it is a design decision about the ecosystem's documentation
conventions, not a quick fix. Raise it; do not build it as a side effect of this.
