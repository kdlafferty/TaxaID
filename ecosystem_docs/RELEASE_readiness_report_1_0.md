# 1.0 readiness report — main `671f6200`

Read-only audit, 2026-10-18, against baseline `44e8a6e` (the 1.0.0 bump, the last
state the pre-release screen covered). Untracked draft. Nothing was fixed.

**Headline:** the packages are in good shape mechanically — 224 exports all
documented, all nine suites green, CI green, no committed secrets, export surface
unchanged throughout. Three things are genuinely not done: **three checklist passes
have never been run against the post-baseline changes** (lintr, security-review,
algorithm review), **TaxaWizard does not reflect any of the new arguments**, and
**NEWS records none of the 24 merged PRs**. One item needs Kevin.

---

## 1. Code review

**Scope since the baseline:** 221 commits, 63 merges, PRs **#8 – #38**.

| package | R files | tests | man | NAMESPACE |
|---|---|---|---|---|
| TaxaTools | 8 | 10 | 5 | unchanged |
| TaxaFetch | 2 | 0 | 2 | unchanged |
| TaxaHabitat | 5 | 3 | 4 | unchanged |
| TaxaMatch | 8 | 4 | 5 | unchanged |
| TaxaLikely | 8 | 8 | 8 | unchanged |
| TaxaExpect | 9 | 3 | 7 | unchanged |
| TaxaAssign | 8 | 9 | 6 | unchanged |
| TaxaFlag | 7 | 4 | 7 | unchanged |
| TaxaWizard | 6 | 3 | 2 | unchanged |

The surface moved once, from 223 to **224**, when `TaxaFlag::screen_assignments()` was
added in #35 with Kevin's approval; no other NAMESPACE changed
(57/32/15/30/33/17/14/16/9). Two ratified *signature* additions landed inside that
unchanged surface: `input_rank`/`fill_ranks` (PR #16), `poor_absolute_fit_col` +
`best_identity_col` (PR #21), and `temperature` (PR #30). Each was checked against
Kevin's exact words by requiring main's formal order to be an exact **prefix** of the
branch's, which proves no existing argument moved.

### Checklist status

| pass | status | note |
|---|---|---|
| 1 — debris | **DONE** (by inspection) | no stray `dev/`, `.rds` or `README.Rmd` at package roots |
| 2 — non-ASCII | **DONE** | zero non-ASCII bytes in `R/` across all nine, re-checked today |
| 3 — naming | **DONE** for the changes reviewed | every rename this cycle was checked for call-site coverage across all nine packages and the live workflows |
| 4 — documentation | **DONE** | all **224** exports have a description; functions have `\value` and `\examples`; the four data objects correctly use `\format`; `%||%` is documented in `man/op-null-default.Rd` |
| 5 — lintr | **NOT DONE** | `.lintr` exists in all nine, but `lint_package()` has not been run against the post-baseline changes. ~1–2 h for nine packages, most of it reading false positives |
| 6 — check + test | **DONE** | all nine green, see §4 |
| 7a — vulnerabilities | **NOT DONE** | `/security-review` has not been run on the post-baseline diff. This is the one Kevin's message calls "probably OK" — it is probably OK, but it has not been *run*. ~30–45 min |
| 7b — algorithms | **PARTLY DONE** | tonight's numbers-moving changes were each measured against real tables (Mugu 0/622, GL 0/889, GL 7/889, the grass-carp recovery). Not done as a *systematic* pass over the 24 PRs. ~2 h if wanted |
| 8 — CLAUDE.md | **NOT DONE** | root and per-package `CLAUDE.md` do not mention `input_rank`, the pooled columns, the fit flag, own-genus naming or the ring floor. Only TaxaLikely's has 2 incidental hits. ~45 min |

### Reviewed vs not reviewed against the checklist

- **PRs #10, #12–#31** — reviewed by package review as they merged, each with a formals
  diff, namespace digest, guards, and in most cases an independent before/after
  measurement. Nineteen PRs.
- **PRs #8 and #9** — merged before package review picked up this lane. **Not checked
  against this checklist.** Worth one pass: ~30 min.

### One wording item

`TaxaAssign/R/group_priors.R:87` — *"has a row in the priors table" no longer means
"known locally"* is comparative history in roxygen, which the project rule keeps out.
Minor; the other six candidates I grepped are present-tense or noun phrases
(`previously-computed downsample index`) and are fine.

---

## 2. Security review prep (USGS WERC)

| item | status |
|---|---|
| `usgs_release_review/` exists, outside every package | **DONE** |
| reviewer's comments, checklist, guidance, supplied README + code.json retained | **DONE** |
| **status table currency** | **NOT DONE** — the table reads "checked 2026-09-14", before all 24 PRs |
| committed secrets | **DONE** — none. Every key-shaped string is a placeholder (`sk-ant-your-key-here`, `AIza...`) or a test fixture (`"fake-key"`) |
| key handling | **DONE** — keys are read only via `Sys.getenv()`, 12 call sites across 7 variables; no code path prints, logs or messages a key |
| outbound requests | **DONE, newly verified** — three provider builders; `temperature` is included **only** when non-`NULL`, and `NULL` sends no field. Confirmed with live calls: no temperature returns text, `temperature = 0.2` returns `HTTP 400 temperature is deprecated for this model` |
| `code.json` | **DONE** — TaxaID 1.0.0, `status: Preliminary`, CC0-1.0 |
| disclaimer | **DONE** — provisional language present in the root README |
| file writes / cache dirs | **DONE by design** — every cache is caller-supplied (`cache_dir`) except TaxaWizard's registry and TaxaTools' model registry, both documented in the README's caching table |
| dependencies / licences | **NOT CHECKED this cycle** — no new Imports were added by any of the 24 PRs (NAMESPACE unchanged), so low risk, but a licence sweep has not been re-run. ~20 min |
| **`/security-review` on the diff** | **NOT DONE** — see Pass 7a |

---

## 3. TaxaWizard — **the real gap**

**None of this cycle's arguments appear anywhere in TaxaWizard's source, its `inst/`
snippets, or the workflow template.** Measured: zero files mention `input_rank`,
`fill_ranks`, `lineage`, `compound_rule`, `pooled_n`, `poor_absolute_fit`,
`best_identity`, `temperature`, `credible_node` or `named_rows`.

What that does and does not mean:

- **The prompt pack is current.** It is generated from the installed packages and has
  been regenerated at every merge, so `CONTEXT_*.md` carries all the new arguments,
  and since PR #20 it carries full `\details` and titled sections too.
- **The workflow template is behind.** It calls `verify_taxon_names()` without
  `input_rank`, so a user following it gets the pre-homonym-fix behaviour for
  coarse-rank names — the exact shape that made a class-rank *Nuda* resolve to a
  flagellate genus. It sets no `consensus_method`, so it uses `lca` rather than the
  `credible_node` node-summing Kevin adopted. It passes no fit columns to
  `review_assignments()`.
- **A stale comment.** The template at line 681 states *"verify_taxon_names()'s real
  formals are (name_list, backbone_id, batch_size, timeout_sec,
  fallback_backbone_id)"*. The installed function has **ten**: that list is missing
  `decisions`, `cache_dir`, `cache_ttl_days`, `input_rank` and `lineage`.

**Is template drift caught?** Partly, and the gap is precise.
`test-workflow-template.R` asserts four things: no unresolved placeholders; the
template parses; every `Pkg::fn` it calls is a real export; and every **named argument
is a real formal**. So a *renamed* argument would be caught — if the template still
passed `ranks =`, it would fail. What it cannot catch is an argument the template
simply **does not use**, or a prose comment that misdescribes the formals. Both of
those are what is wrong today.

**Effort:** ~1–2 h to bring the template and snippets up to date, plus a regeneration.
**NEEDS KEVIN** on one point: whether the template should default to
`consensus_method = "credible_node"`, since that changes what the canonical path does.

---

## 4. Tests and CI

All nine suites, each run in its **own** R session. TaxaFlag and TaxaWizard re-measured
at `671f6200`; the other seven are unchanged since `06d3ef3b`, their `R/` and `tests/`
being byte-identical there apart from whitespace:

| package | pass | fail | skip |
|---|---|---|---|
| TaxaTools | 2395 | 0 | 2 |
| TaxaFetch | 866 | 0 | 4 |
| TaxaHabitat | 610 | 0 | 0 |
| TaxaMatch | 1435 | 0 | 0 |
| TaxaLikely | 2440 | 0 | 0 |
| TaxaExpect | 792 | 0 | 1 |
| TaxaAssign | 1808 | 0 | 0 |
| TaxaFlag | 1347 | 0 | 0 |
| TaxaWizard | 1229 | 0 | 0 |

**12,922 passing, 0 failing.** CI on `main` is green at `671f6200`, `06d3ef3b` and
`c22def9b`.

**Known conditional skips** — all legitimate, none hiding a failure:
- TaxaTools 2: NCBI/Global-Names reachability. Flaky by nature; both skipped and
  unskipped within one hour last night depending on the endpoint.
- TaxaFetch 4: optional packages (`rgbif`, `CoordinateCleaner`) absent.
- TaxaExpect 1: the no-`sf` WKT fallback path.

**A methodology caveat worth recording, because it would mislead an auditor.** Running
all nine `devtools::test()` calls in **one** R session reports **57 failures in
TaxaWizard**. They are an artifact: each `devtools::test()` attaches its package, and
by the ninth the session holds eight `load_all()`'d packages, so TaxaWizard's
registry-introspection tests no longer see the installed state. Run alone, TaxaWizard
is 1221/0/0. Anyone verifying "all nine green" must run them **separately**.

---

## 5. Docs

| item | status |
|---|---|
| **PR #11 (root README)** | **OPEN, held.** `readme-root` is **110 commits** behind main. Needs: main merged in; the pack regenerated; the inventory rows (now 34/27/12/22/40/18/24/20/10 — five rows have moved since the branch was cut, TaxaTools' twice); and the content items still outstanding — the TaxaAssign weighted-LCA paragraph, the TaxaLikely closed-genus note, the TaxaExpect habitat arguments. **Plus, new since the branch:** the pooled columns, the fit flag, own-genus naming, the ring floor and `temperature`. ~1–2 h |
| **NEWS** | **NOT DONE.** All nine `NEWS.md` exist and stop at `# <Package> 1.0.0`. **None** mentions any of the 24 merged PRs — zero hits for `input_rank`, `pooled`, `poor_absolute_fit`, `temperature`, own-genus or ring. For a release this is the most visible omission. ~1–1.5 h for nine files |
| **1.1 board** | **CURRENT.** Five items: the `review_assignments` retry summary; `fill_higher_ranks.R:59` roxygen; the `.habitat_record_weights` weight-0 message; `workflow_export_prompts()`'s local-setup-report default; and family-rank rows typed `specific_candidate`. Plus the NA-likelihood + NA-sd `compute_posterior` failure found last night |

---

## 6. Release steps left

In order, with what blocks what:

1. **Finish the checklist passes** — lintr (5), `/security-review` (7a), CLAUDE.md (8),
   and PRs #8–#9 against the checklist. ~3 h total. Nothing else depends on these, but
   7a should precede submitting for external review.
2. **TaxaWizard template + snippets** (§3). Needs Kevin's call on `consensus_method`.
3. **NEWS for all nine** (§5). Independent; can run in parallel with 1–2.
4. **PR #11** — unhold, merge main in, regenerate, fix the inventory rows, add the
   outstanding paragraphs. Should come **after** 2 and 3 so the README describes the
   final state.
5. **Dev-records move (option A)** — **DONE**, #36. The ten `CLAUDE.md` narratives
   (23,197 lines) and seven history files went to TaxaID_dev, copied and verified
   byte-identical before anything was removed; each `CLAUDE.md` is now a current-state
   file, 659 lines in total, with its inventory DERIVED from `NAMESPACE` and the Rd
   titles rather than hand-written. `ecosystem_docs/` holds 13 files.
6. **Re-anchor the release documents** — **DONE** for this report and the definition of
   done, which are now tracked in `ecosystem_docs/` at `671f6200`. The re-cut plan and
   the lintr review went to TaxaID_dev as working records, per Kevin's decision.
7. **`v1.0.0` annotated tag** — not present (`pre-1.0-freeze` and the CalIntertidal
   run tags exist). Last step, after 1–6.

**All of the above are now closed.** Kevin decided the template's `consensus_method`
(weighted LCA by node summing, #33), the lintr buckets (#34), `relative_score_gap`
(keeps 0.25, #35), the dev-records move (#36) and where the ratified surface is stated
(#38). PRs #8–#9 were given the retrospective checklist pass and were clean.

---

# Addendum — the four outstanding passes, run 2026-10-18

Read-only. Findings errors-first.

## Pass 7a — security review: **DONE, no findings**

Scope: the `44e8a6e..06d3ef3b` diff across all nine packages. **One thing this scope
does not cover, stated plainly:** `TaxaFlag::screen_assignments()` and the site-aware
`review_assignments()` arguments landed afterwards, in #35. They were checked for the
same categories when that branch was gated — no `system()`, `eval()` or `parse(text=)`
added, no new deserialization, no `DESCRIPTION` dependency change, no new file writes,
and no key material anywhere; the only outbound change is prompt content, verified with
a real call. They have not had a separate full pass under this heading. The `/security-review`
skill's own harness found nothing to read, because it builds its diff from the current
branch and this work is already merged; the range was supplied manually instead.

| area | result |
|---|---|
| injection / code execution | **clean** — no `system()`, `system2()`, `eval()`, `eval.parent()`, `parse(text=)` or dynamic `do.call(get(...))` added anywhere in the range |
| deserialization | **clean** — no `readRDS`/`unserialize`/`load()` added. One `saveRDS` added (the verify cache), writing to a path built from a numeric hash under a caller-supplied `cache_dir`; the hash renders as `%010.0f-%010.0f-%06d`, digits and hyphens only, so no traversal |
| secrets at rest | **clean** — no key material committed. Every key-shaped string is a placeholder (`sk-ant-your-key-here`, `AIza...`) or a test fixture (`"fake-key"`) |
| key handling | **clean** — keys are read only via `Sys.getenv()`, 12 sites across 7 variables. No path prints, logs or messages a key |
| the new `temperature` field | **clean** — validated (`!is.numeric`, `length != 1`, `!is.finite`, `< 0` all rejected) and included in the request body **only** when non-`NULL`. Confirmed live: absent returns text, `0.2` returns the provider's HTTP 400 |
| dependencies / licences | **clean** — **no DESCRIPTION dependency changed at all** across the 24 PRs, so there is nothing new to vet. All nine are `License: CC0`, consistent with `code.json`'s `CC0-1.0` |
| disclaimer | **present** — provisional wording in the root README; `code.json` says `status: Preliminary` |

**One pre-existing pattern, already mitigated, recorded because a WERC reviewer will
see it.** The Gemini path sends the key as a URL query parameter
(`req_url_query(key = api_key)`, `call_api.R:268`) — that is Google's required scheme,
not a choice. It predates the baseline (`0bd0deb4`), so it is out of scope for a
diff review, but it is the one place a key could reach an error string. The code
already handles it: `call_api.R:749-755` scrubs the key out of `conditionMessage(e)`
before it reaches `stop()`, with a comment naming the exact mechanism. No other
`stop`/`message`/`warning` site (27 of them) includes the URL, endpoint or request.

**Provider auto-detection under `Rscript`** is a usability trap, not a vulnerability:
with a key set but no provider active, `call_api()` fails closed with a clear message.
Passing `provider =` explicitly is the fix. The setup report already warns about it.

## Pass 5 — lintr: **DONE** (Kevin's buckets (a) and (b) merged in #34)

200 lints in `R/` across the nine. None substantive.

| package | lints | | package | lints |
|---|---|---|---|---|
| TaxaAssign | 66 | | TaxaTools | 21 |
| TaxaFlag | 36 | | TaxaWizard | 17 |
| TaxaLikely | 34 | | TaxaFetch | 10 |
| TaxaExpect | 7 | | TaxaMatch | 5 |
| TaxaHabitat | 4 | | | |

By type: `line_length` 105, `semicolon` 21, `object_usage` 18, `brace` 17,
`trailing_whitespace` 11, `assignment` 7, `object_name` 6, `object_length` 3,
`commented_code` 3, `trailing_blank_lines` 1, `seq` 1.

**The 18 `object_usage_linter` hits are all false positives, verified not assumed.**
Every one is "local variable assigned but may not be used", and TaxaAssign interpolates
into `cli` strings that lintr's static analysis cannot see. Checked directly:
`habs` → `{.val {habs}}` two lines later; `taxa` → `{.val {utils::head(taxa, 5)}}`;
`n_named` → `{n_named}`; `n_total` → `{n_total}`; `pool_floor` → `{pool_floor}`. This
is exactly the class the checklist warns about. **No dead code found.**

Note `check()` is already at 0 errors / 0 warnings / 0 notes, which is the checklist's
actual Pass 6 target. Pass 5 is a style target, and the 105 line-length hits exceed the
120-character limit the packages' own `.lintr` sets. **NEEDS KEVIN** on whether
cosmetic lints are worth touching before an external review, given every edit risks a
diff in files already reviewed.

## Pass 8 — CLAUDE.md currency: **DONE** (closed by the dev-records move, #36)

Two distinct gaps.

**1. Stale function inventories.** 16 exported functions are absent from their own
package's `CLAUDE.md`:

| package | missing |
|---|---|
| TaxaTools (3) | `check_taxaid_manifest`, `taxaid_build_manifest`, `write_taxaid_manifest` |
| TaxaFetch (3) | `fetch_gbif_occurrence_counts`, `fetch_inat_occurrence_counts`, `plan_gbif_fetch` |
| TaxaLikely (3) | `annotate_reference_support`, `estimate_sequence_matrix_size`, `match_reference_region` |
| TaxaFlag (3) | `classify_sample_identity`, `flag_backbone_conflicts`, `review_sample_identity` |
| TaxaExpect (2) | `estimate_kernel_priors_from_counts`, `generate_uncertain_habitat_evidence` |
| TaxaHabitat (1) | `resolve_habitat_by_geography` |
| TaxaAssign (1) | `add_unreferenced_prior_mass` |

TaxaMatch and TaxaWizard are complete.

**2. This cycle's behaviour is unrecorded.** Root and per-package `CLAUDE.md` do not
mention `input_rank`, the pooled columns, the fit flag, own-genus naming or the ring
floor. Only TaxaLikely's has two incidental hits.

## Retrospective checklist on PRs #8 and #9: **DONE, no findings**

`97221975` (robust bound keeps a sequence's own node with one recorded member) and
`2815a848` (cap an outside row at one site record; never cache a failed lookup).
Together: 28 files, TaxaAssign, TaxaFlag, TaxaLikely and TaxaTools.

| check | result |
|---|---|
| Pass 2 non-ASCII | 0 |
| dated/historical roxygen | 0 |
| every changed `R/` file has a paired test change | yes, all |
| NAMESPACE touched | no — no new exports |
| `man/` regenerated | 5 files |
| Pass 4 documentation | covered by today's all-223 sweep, clean |
| `inst/*_review_response.md` updated | yes, in all four packages |

They also regenerated `llm_prompts/`, which the pack guard would have caught otherwise.
Nothing to fix.
