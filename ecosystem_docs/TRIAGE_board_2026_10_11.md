# Board triage, 2026-10-11: the 49 rows waiting on the maintainer

Derived read-only from section 0 of `REENTRY_PROMPT_prepublication_screen.md`.
Nothing here is new information and nothing was decided; this is that board's
`Item` and `Waiting on` cells, grouped so the open decisions can be read in one
sitting. Each row gives the line in the screen document, where the full `State`
cell (1-7 KB of measurement per row) lives.

Of 82 live board rows: **48 wait on the maintainer alone**, one more
(`clade-resolvable-rank`) waits on its author first and then on him, 15 wait on
another session, 9 on a mechanical step (a reinstall, a rebuild, submission), 5
elsewhere.

The groups are ordered by how cheaply they can be answered, not by importance.

---

## A. One word each: a branch is verified and held, and only needs merge or not

Nothing in this group needs new work or new measurement. Each was verified
against the tip that merges, and is waiting to be told yes.

| L | Branch / item | The question |
|---|---|---|
| 162 | `rank-accuracy` @ `f9462e2` | merge? (approved option 1, plus three modelling steps and a rank-leak fix) |
| 165 | merge ledger rebuilt 2026-10-01 | one candidate, zero conflicts; `support-rule-docs` was withdrawn by its author |
| 166 | `fix-refine-unevaluated` @ `909be70` | the split bug fix; the row says no approval is needed, so this may simply be stale |
| 173 | `prior-decided` @ `0db7383`, `measured-rings` @ `03d349f` | held pending the six-item plan below |
| 174 | `measured-rings` @ `c1ce9d6` | H3 measured instead of heuristic |
| 177 | `calib-constant-default` @ `f9127d1` | constant offset for every marker |
| 181 | `complement` @ `ccdfc7f` | release scope; and separately `7ae8785` |
| 183 | `complement` @ `3dd1f77` | 1.0 or a later release, for the thirteen; plus a new export |
| 197 | `evaluate_likelihoods()` drops generic H2/H3 rows | the fix is queued and waiting to merge |
| 214 | `gbif-facet-priors` @ `be9e62f` | three exports, a rename (A3 said no renames), and the merge |
| 176 | the six-item missing-tail plan | one line confirming the six, and the `pool_tail` default |

A note on three of these: a **new export** cannot land under the freeze without
an explicit yes (rows at 183, 214, and `clade-resolvable-rank` at 172), and an
exports diff cannot see a new *argument* on an existing function, so "no new
exports" is not the same as "no new surface".

## B. Decisions that change published numbers

These are the ones that genuinely need the maintainer, because they change what
the pipeline reports and several are mutually entangled.

| L | Item | The decision |
|---|---|---|
| 160 | each marker fails differently; genus comes from sequence, species from priors | whether 18S should report species at all, or only with `likelihood_support` attached; keep or demote `prior_decided` |
| 163 | the contamination produced the whole constant-versus-linear finding | the order of work |
| 164 | independent statistical review: four blocking findings | the order of work; hold is maintained on all three branches |
| 169 | most 18S *training* references do not contain the region the ESVs cover | hold the 18S species-discrimination conclusion open until region-matched training is measured? |
| 170 | **1.0 defect**: COI-Leray reference screening compares the wrong region | fix in the package for 1.0, or document the limitation and keep the workflow-side workaround? |
| 168, 171 | lineage backbone audit; accession-screen removal rule | the rings question; the conflict-guard counting rule |
| 180 | calibration docs fixed; 18S has the opposite problem | the 18S form-selection question |
| 184, 187 | coarse prior rows are two problems, only one cheap | and whether to split a coarse row's mass pro rata instead of excluding it |
| 191 | arm (b) adoptable, arm (c) held | adopt (b); classify (c)'s ten |
| 193 | five numbers-changing changes queued at a tagged freeze | which, if any, are 1.0 |
| 194, 195, 196 | the generic complement is lost at three places | one decision covering all three; they compose into a single numbers change |
| 199 | the model's own "none of the above" channel beats my set-mass floor | adopt? |
| 200, 201, 202 | ESV x site grain; re-grounding the confirmation update; assignment grain = prior grain | three related design decisions |
| 189 | `fill_higher_ranks()` silently picks one family for an ambiguous genus | fix now or record it |
| 227 | `resolve_review_overrides(resolution_rank = "order")` | re-run the reference screens for consistency? |
| 206 | cache refetch: two causes, one refetch if sequenced right | the memory-branch decisions, then the order |

## C. Open questions with nothing built

Each of these can be answered "not 1.0" in one word, which closes it for this
release without discarding it. That is the cheapest group on the board.

| L | Item |
|---|---|
| 187 | split a coarse prior row's mass pro rata (also listed above) |
| 219 | Finding 24: cross-backbone synonymy in the consensus output |
| 220 | Finding 26: harmonisation coverage per lineage |
| 221 | local BLAST database consistency (the row already says "a later release that does not exist") |
| 230 | does the WoRMS-habitat refusal carry from the gate to `flag_contaminant()`? |
| 232 | Finding 29 stands but no longer blocks the identity gate |
| 218 | proposal: static input-availability check for workflow scripts (proposal, not accepted) |
| 236 | sweep: the `ifelse()` length trap elsewhere |

## D. Small, administrative, or already overtaken

| L | Item | Note |
|---|---|---|
| 167 | "three real bad URLs, one in every README" | **largely closed.** The placeholder DOI was fixed at `7a3d13f`; the `claude.ai/code` attribution link is at 0 occurrences. What remains is one third-party host, `insectapp.las.iastate.edu` in `TaxaMatch/README.md:366`, whose SSL certificate has expired -- the host is alive and the link resolves for a human, so the only question is whether to keep the link |
| 205 | PtCon 12S B2 run | the go |
| 207 | README rounds | the next round |
| 210 | pre-security-review submission | -- |
| 212 | TaxaWizard snippet `refs_to_matrix.R` | -- |
| 213 | supplemental methods style | sweep or leave |
| 217 | CalIntertidal production findings (11) | the tracked four |
| 226 | subset-database extraction | the `evaluate_likelihoods()` half |
| 172 | `clade-resolvable-rank` @ `6af4073` | its author splits the fix first; then the export decision |

---

**How to use this.** Group C is one word per row and closes eight items. Group A
is one word per row and unblocks eleven branches that are already verified.
Group B is the real work and is where the 1.0 content decisions live -- rows
160, 169 and 180 are one question about 18S asked three ways, and 194/195/196
are explicitly one decision.
