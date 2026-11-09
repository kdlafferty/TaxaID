# Definition of done — TaxaID 1.0

**Status: adopted. Replaces section 11 of the pre-publication screen's re-entry
prompt, which recorded the old gate as unmeetable as written. That document is now in
the TaxaID_dev repository at `ecosystem_docs/REENTRY_PROMPT_prepublication_screen.md`,
moved there with the development records.**

## Why it is being re-anchored

The existing gate is anchored on `pre-1.0-freeze` (tag object `7025c422`, commit
`bd84325`, 2026-09-28). `main` is now **221 commits beyond `44e8a6e`** and
~580 beyond the freeze, and the release candidate is being re-cut from `main`.
A gate anchored on a tree nobody will ship cannot be met by shipping.

**Re-anchored on the RELEASE TREE: `671f6200`** — `main` after the last content change
before the cut. The one-site-record cap (`50dff2a`) and the cache-no-failure-writes fix
(`42ffc3b`, merged as `3df454d0`) are both in it, as are the twenty-three pull requests
of this cycle, #16 through #38. Every gate below names its evidence against THAT commit,
not against the freeze tag.

## The gates

### 1. CI, 10/10 on the release tree
All ten jobs green on `671f6200`: the nine packages plus
**`TaxaID (meta-package)`**, which exists so the repository root is checked and
not only its children. Includes the **unskippable artefact guards** —
`test-pack.R` and `test-workflow-template.R` must report **0 skipped**, because
both resolve the repo via `.pack_find_repo_root()` and skip silently under
`R CMD check`; a skip is indistinguishable from a pass in a summary.
CI runs `error_on = "warning"`, with `_R_CHECK_CRAN_INCOMING_: "false"` pinned
(the eight packages depending on TaxaTools otherwise WARN permanently on
"Strong dependencies not in mainstream repositories", which is correct and
unfixable while TaxaID releases through USGS rather than CRAN).
**Evidence:** the run URL and its 10 job conclusions. Linux only — B1
clean-checkout reproducibility is covered by CI on Ubuntu and NOT on macOS.

### 2. Validation runs — Mugu and Great Lakes
Per the maintainer 2026-10-10, validation is INSIDE this gate, not after it.

**Per the maintainer 2026-10-15, the gate is Mugu plus Great Lakes. Verbatim:
"all packages are 1.0.0. CI is independent of the packages. we are using it to
test and to analyze data, but not for inclusion in TaxaID."** ("CI" = the
CalIntertidal analysis.)

- **Mugu** (the multi-marker instance): the criterion was never written down. The
  evidence that exists: the 2026-10-14 run produced **0 consensus flips** against the
  previous accepted run, every difference being a coarsening rather than a changed
  call. Recorded here as evidence, NOT as a criterion -- a gate defined by the result
  it already got is not a gate. The maintainer ratifies this wording, or replaces it,
  before the tag.
- **Great Lakes** (the project's only held-out benchmark): Lamar species
  precision **within 0.01 of the 0.872 benchmark**, AND the FP/FN breakdown
  (`ours_only`, `missed`, `other_species`, `withheld_coarser`) reviewed and
  explained.

**CalIntertidal is NOT a gate.** It is a downstream data analysis that CONSUMES
the released packages — the site every recent change was fitted on, so passing
there would show the changes work where they were measured, not that they
generalise. It may be recorded as an informational consumer of the release at
most. Its run tags and reruns do not block 1.0 and do not appear in the release
sequence.

**Tolerance set by the maintainer 2026-10-15.** The gate previously read "a
regression at either is a 1.0 blocker". Verbatim: *"'a regression at either is
a 1.0 blocker'. 0.872 -> 0.865/0.867 This is too extreme (especially if the
drop is due to conservation and overall error reduction)."* A blanket
no-regression rule treats a precision drop bought by catching more errors as
identical to a drop that introduces them, so the gate is now a tolerance plus a
review: the number must be close, and the composition of the errors must be
understood and explained. The review half is the operative one; the tolerance
alone would admit a drop of the kind the blanket rule was meant to catch.

The figures in that quote are the ones that stood when the decision was made.
The tolerance it set is what carries forward; the drop it describes no longer
exists, as the next paragraph records.

**The gate is met on the final validation run.** On `_v103finalb` (install
`bd05fcb`), scored against the Lamar survey — a survey, not ground truth, so a
call it does not list is unconfirmed rather than wrong — species precision is
**0.878 under LCA** (794 agreeing of 904 called) and **0.887 under the credible
node** (698 of 787). Both are ABOVE the 0.872 the survey's own comparison
reached, so there is no regression to tolerate: the earlier 0.865 figures, and
the 0.007 shortfall the tolerance was written to accommodate, are superseded.

The review half of the gate is satisfied too, and matters more than the number.
Under LCA, outright misses are **0** (down from 10), `other_species` is **2**,
false positives are **110**, and `withheld_coarser` is **285**. The credible
node withholds more (**381**). Neither rule misses a species outright.

The choice between the two rules is a trade, not a ranking, and it is recorded
here rather than resolved: relative to LCA the credible node avoids **21** calls
the survey does not support and withholds **96** it does — about **4.6 supported
detections given up per unsupported call avoided**. The withheld species are
mostly common ones with several congeners present (*Carpiodes cyprinus* 38,
*Moxostoma macrolepidotum* 24, *Notropis hudsonius* 13, *Percina maculata* 11,
grass carp 8).

**Which rule ships is the maintainer's decision, pending the component report,
and this gate does not presume it.** Both rules clear the tolerance, so the gate
is met either way; the decision is about which error the study would rather
make, not about which rule passes.

**CONFIRMED MET by the maintainer 2026-10-15, verbatim: "4 Y".** The Great Lakes
half of the validation gate is closed. The consensus-rule choice remains open
and does not reopen it.

**But these figures may still move before the release, for one reason and not
the one first recorded here.** The habitat work was narrowed on 2026-10-16 to
the compound-label LLM-score fix alone, with no kernel-side mechanism (Kevin:
*"the covariate approach stays out of the package"*). That fix only moves
labels containing a separator, and Great Lakes' scheme is
`c("Lentic", "Lotic")`, so it cannot change these numbers; only Mugu reruns.

What does keep them provisional is the homonym gate. Kevin: *"I do not want
the package shipped with post-hoc patches."* A general homonym rule is to land
before 1.0, and the Etheostoma lookup failure was a Great Lakes finding, so
these figures stand on a taxonomy that is about to change. The gate is
confirmed met on the numbers as they are, and will need re-confirming after
the homonym rule lands — not because anything here is in doubt, but because
part of the evidence it rests on will be recomputed. See the re-cut plan,
steps 3 and 4.

### 3. Dev-records move complete
Seven `ecosystem_docs/` history files to `TaxaID_dev/ecosystem_docs/`; ten
package `CLAUDE.md` narratives to `TaxaID_dev/session_notes/<pkg>_CLAUDE_2026-10.md`,
each replaced by a current-state file under 150 lines. **Must land BEFORE the
release tag** — see the re-cut plan. **Evidence:** the move commit, plus CI
still 10/10 after it (the artefact guards read repo structure).

### 4. Export surface 223, unchanged and ratified
Verified on the release tree, not asserted:

```
TaxaTools 57  TaxaFetch 32  TaxaHabitat 15  TaxaMatch 30  TaxaLikely 33
TaxaExpect 17  TaxaAssign 14  TaxaFlag 16  TaxaWizard 9      TOTAL 223
= 218 functions + 5 data objects
```
**Evidence:** per-package `export()` counts as above, and a `formals_diff` run
showing 0 signature changes against the previously ratified surface — an exports
diff alone cannot see a new argument or a changed default.

### 5. The written statement (retained from the original gate)
A written statement that Stage B ran against **`671f6200`** — naming the
commit of every post-tag package re-run — against named commits in the **two
workflow repositories**, with **NCBI healthy**, and found nothing material.
Anything less is a status report, not a pass.

## What "done" is for
Unchanged, and worth restating: TaxaID is public but **not a citable object**.
The citable object is the USGS software release, which needs migration to
code.usgs.gov, an IPDS record, a reserved DOI, an administrative security
review, a technical code review and a domain review. "Found nothing material"
means nothing a reviewer would raise. This document leaves the repository with
the rest of the dev material once the gate is met.
