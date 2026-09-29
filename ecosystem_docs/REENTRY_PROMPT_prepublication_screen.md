# Pre-publication screen for TaxaID 1.0

**Status: OPEN. Rewritten 2026-09-20 (Fable 5.1, with the user) to replace the
2026-09-14 version, which was written but never run -- its author session crashed
around 2026-09-15.** The old version's running order, closed-item narratives and
pkgdown contradiction are gone; git has them. Everything below was measured on
2026-09-20 against `main` at `162de62` unless a line says otherwise.

---

## 0a. FREEZE TAGGED, and the Stage B catch-up plan (2026-09-28 night)

`pre-1.0-freeze` = `bd84325`, pushed. The maintainer declared the freeze and
went to bed; this section is the plan being executed, written before execution
so an interruption does not lose it.

**The correction that shapes everything below.** B4 (the per-package checklist)
was run on 2026-09-21 against `b861dd7` and is recorded DONE for eight
packages. The tag is 428 commits later. EVERY package's `R/`, `NAMESPACE` or
`tests/` changed in between, by 13 to 76 files each, and twelve new exports
landed. So every B4 result describes a tree that no longer exists. Protocol
item 5 asks for a Stage B re-run per package after a post-tag change; the whole
delta here is post-B4 and pre-tag, which is the same situation and wants the
same treatment.

**Running tonight, per package**, the decisive and cheap subset of the
checklist: pass 1 debris, pass 2 non-ASCII, pass 4 documentation completeness
(every export with examples and complete parameter docs, the twelve new ones
above all), pass 5 lintr, pass 6 check and test. Order is by risk, newest
surface first: TaxaFlag, TaxaFetch, TaxaTools, TaxaExpect, TaxaLikely, then
TaxaAssign (76 files changed), TaxaMatch, TaxaWizard, TaxaHabitat.

**NOT attempted tonight, each for a stated reason, so nobody records this as a
completed Stage B:**

- **B1 clean-checkout reproducibility.** Needs installs. The 18S accession
  screen holds the shared library, and a fresh `R_LIBS_USER` would not see the
  CRAN dependencies, so a true clean checkout needs a quiet machine and a
  dependency install. The single most valuable outstanding pass.
- **Entry condition 3, reinstall from the tag.** Same blocker.
- **Entry condition 2, all three repositories clean.** The analysis repository
  has 23 uncommitted or untracked paths, several written by sessions other than
  its owner.
- **B2, every number reproduces.** Needs the production runs already enumerated.
- **B5 USGS checklist and B6 licensing.** Document passes needing the
  maintainer.

**So the honest status after tonight will be: Stage B partially re-run against
the tag, with B1, B2, B5 and B6 outstanding and the entry conditions not all
met.** Section 11 says anything less than the full statement is a status
report, not a pass. This is a status report.

## 0b. Stage B re-run against the tag: results so far (2026-09-28 night)

Scope: the 103 package R files that changed between B4's run (`b861dd7`) and
the tag (`bd84325`).

**Passes 1, 2 and 4, all nine packages: CLEAN.** No debris at any package root,
zero non-ASCII characters in any `R/`, and every one of the 228 exports has
examples. The merge standard enforced through the screen has kept these current.

**Pass 5, lintr: 106 lints on the changed surface**, measured with each
package's OWN `.lintr`. My first run overrode those configs with the defaults
and reported about 2,900, most of them line length against a house style that
deliberately allows it. That number was an artefact of the instrument and is
withdrawn; the same mistake would make any future comparison meaningless, so
lint a package with its own config or not at all.

What the 106 contained, and what was done:

- **Six `object_usage_linter` "assigned but may not be used" in TaxaAssign: all
  FALSE POSITIVES**, verified one by one. Every variable is used inside a `cli`
  glue string, which the linter cannot see through. No action, and recorded so
  the next pass does not re-investigate them.
- **One `assignment_linter` on `<<-` in TaxaWizard's pack builder: NOT a
  defect.** It is a closure accumulator assigning to its own enclosing
  function's variable, not a global write. Report-only.
- **28 compound semicolons and 3 brace-style breaks in the new TaxaFlag
  identity-gate code: FIXED** on branch `stageb-lint-catchup`. The compound
  statements were split with a quote-balance rule after a first attempt with an
  inverted guard split only two of them. Both files re-parse, and TaxaFlag is
  925 passing, 0 failures, so the edits are style-only.
- **Remaining and deliberately not touched:** about 50 line-length lints, the
  object-name and object-length lints (B4's convention is report-only, no
  renames), and two brace lints whose fix would restructure a function body
  rather than reformat it.

**Pass 7a, security read of the changed surface: nothing to fix.** Twelve
`system`/`eval`/`parse` sites. The shell calls are fixed literals or pass
quoted arguments through `system2`, which uses no shell. The `eval` sites
evaluate a function's own formals default. One site, TaxaWizard's Shiny
parameter reader, evaluates text matching a `c(...)` literal shape taken from
the user's OWN workflow script, which they are about to run themselves, so it
is not an escalation; a whitelist parser would still be tidier if that code is
ever revisited.

**Pass 6, check and test: NOT RUN TONIGHT.** Available memory sat at 3.3 GB
with the 18S accession screen live and a `blastn` against `core_nt` holding
about 14 GB. Nine checks into that is how a healthy multi-hour run gets killed,
which this project has already done once. The one suite that had to run,
TaxaFlag after the edits, ran alone and passed.

## 0. Open items board (kept current; last edit 2026-09-28)

| Item | State | Waiting on |
|---|---|---|
| main | `4203c95`, pushed. TaxaTools, TaxaLikely, TaxaAssign and TaxaFlag are ahead of the installed library; the rebuild is held for the live 18S accession screen, and the order is TaxaTools before TaxaAssign. | -- |
| Installed library | CURRENT with `main`. All nine from `7e0ef06`, then TaxaTools, TaxaMatch and TaxaFlag rebuilt from `5b439bb`, which a source diff shows are the only three that changed since. Verified by reading the INSTALLED builds, not the repository: the 18S V9 pair resolves, a bare `18S` refuses, the taxonomy fetch has five attempts, the resolution-override default is `"order"`, the identity gate has `untested_policy` and `blank_medium`, and `model_label` survived the identity-gate rebase. `llm_prompts/` regenerated | -- |
| Branch `reference-memory-estimate` (`69e5b3f`) | LANDED (see the counts-path row). Its worktree is still held by the author session, so the branch ref cannot be deleted yet; that is bookkeeping, not work |
| PtCon 12S B2 run | staged (`TaxaID_dev/.../b2_runs/`), driver passes `max_per_genus = NULL` | maintainer's go |
| Cache refetch, TWO causes, ONE refetch if sequenced right | (1) A2 `53f4143` (by design, stays): a cache file with no recorded selection settings is a miss, so every pre-A2 project (PtCon 12S 222 genera, PtCon 18S ~1,400, GreatLakes, Mugu) refetches once at its next Step 7; CalIntertidal is NOT affected (cache built after A2, record present, checked on disk). (2) The memory-estimate branch stores uncapped metadata, so a file written under a cap refetches once more even with the record. Land that branch FIRST, reinstall, then let each project refetch once. The PtCon 12S retention re-run is HELD at Step 7a (backup of 47 outputs made; nothing modified) | maintainer: the memory-branch decisions, then the order |
| README rounds | all carried to main, latest `fdb9de1` (the error-categories prose: scores mistaken for probabilities, blank-based removal contrasted with conventional practice, a continuous spatial prior contrasted with filtering on a regional list, the mislabel rate attributed to NCBI). The shared checkout's working copy still holds that round uncommitted and its branch is behind main, so it will conflict on its next pull; discard the working copy there, main has it | maintainer's next round (tell the screen first) |
| Adaptive genus cap | tracked 1.1 candidate; grid owns the fit; workflow deletes its constants when the package function lands | the memory branch |
| Unidentified | "expanded path length 1024" file.exists warning in long CalIntertidal runs; not from TaxaLikely | a caught call site |
| Pre-security-review submission | no tag, no bump; WERC official path later needs a `1.0.0` branch | maintainer |
| Likelihood model rationale | Section 17 of TaxaLikely's supplemental methods (benchmarked model-form decisions) fast-forwarded to main `3fbe3bd` | -- |
| Production workflows edited for pair retention | eDNA `e621fd6` (PtCon 12S, 18S, Mugu, retired template) and GreatLakes `0c6309b` pass `pair_retention = "best_per_partner"` + `min_pair_coverage`; NOT runnable until the reinstall; then run `TaxaID_dev/diagnostics/workflow_checks/check_stale_arguments.R` on the five files and one cheap real re-run (PtCon 12S) | the reinstall |
| TaxaWizard snippet `refs_to_matrix.R` | calls `build_sequence_matrix()` with defaults only (whole-set alignment, full table); should it carry the production choices (`by_genus = TRUE`, `max_foreign_reps_per_genus = 20L`, `pair_retention = "best_per_partner"`, `min_pair_coverage` matching the training floor)? | maintainer |
| Supplemental methods style | TaxaLikely's carries 96 em dashes (TaxaAssign's and TaxaExpect's carry 0); the README rules were never applied to these files | maintainer: sweep or leave |
| Branch `gbif-facet-priors` (`be9e62f`, one-site wording added at the maintainer's request 2026-09-26; "count based priors" chat) | THREE NEW EXPORTS (`TaxaFetch::fetch_gbif_occurrence_counts()`, `TaxaFetch::plan_gbif_fetch()`, `TaxaExpect::estimate_kernel_priors_from_counts()`), one new arg (`estimate_kernel_priors(count_col =)`, NULL keeps behaviour), one RENAME (`fetch_inat_occurrences()` -> `fetch_inat_occurrence_counts()`, separate commit `9a05644`, no caller outside TaxaFetch/TaxaExpect); reviewed detached against the branch's own library: TaxaFetch 866/0, TaxaExpect 763/0, check 0/0/0 both, READMEs complete, review-response rows in; `ecosystem_docs/HANDOFF_counts_path_prior.md` on the branch belongs in TaxaID_dev; install order TaxaFetch before TaxaExpect | maintainer: the three exports, the rename (A3 said no renames), and the merge |
| Bimodality warning | DONE: fast-forwarded to `b11814f` (maintainer's go in the optimize-matrix chat); `.bimodality_check()` detects a point mass at the ceiling from repeated raw values and fills `explanation`; `calibrate_query_noise()` gives that reading instead of the platform advice; reviewed detached: TaxaLikely 1431/0, check 0/0/0; review-response row in | the reinstall |
| Workflow checks after the reinstall | DONE. Stale arguments: the CalIntertidal chat measured 51 TaxaID call sites with known formals and ZERO passing an argument the installed version lacks, so nothing broke under the rebuild. Dead calls: the two-root fix was already in `check_dead_calls.sh`, but the script had a defect of its own, and it is the shape this project keeps finding. Under `set -o pipefail` its first `grep` failed the whole pipeline whenever it matched nothing, so with a wrong `ARCHIVE_ROOT` the script died with NO OUTPUT AT ALL and its own helpful "set ARCHIVE_ROOT" message could never print: a guard that cannot be reached reports nothing, which reads exactly like a clean run. Fixed. The sweep then reports blocks of hits in PtConception 12S, PtConception 18S and Mugu, and EVERY ONE sits inside the retired GLMM else-branch of `if (USE_KERNEL_PRIORS)`, verified by brace position, dead on purpose and documented in place; the canonical template reports none. That reading is now written into the script so the next pass does not re-derive it | -- |
| CalIntertidal workflow (CLOSED: retention lines committed by that chat; the session-local library prepend removed after an identical shared-vs-session BLAST test) | its retention lines sit uncommitted in that chat's working tree with ~920 lines of its own Section 7 work; that chat commits its own file; `MAX_SEQS_PER_GENUS` set to NULL there by the maintainer's decision (uncommitted with that chat's Section 7 work; that chat commits) | that chat's commit |
| CalIntertidal production findings (11, `eDNA/CaliforniaIntertidal/PACKAGE_REVIEW_FINDINGS_2026-09-27.md`) | LANDED `74bc886`: TaxaWizard `annotate_script(mode = "llm")` (positional `llm_fn`, `max_tokens` sized to the prompt, `...` forwarded), `workflow_check()` blastn version + capability note, `sniff_input()` PercMatch and the one-row-per-observation rule, parameter detection of every top-level constant (TaxaWizard 1155/0); `blast_sequences(method = "local")` had never worked (duplicate `-outfmt`), fixed with a test (TaxaMatch 1372/0). TRACKED, not built: `taxa_lineage` silently orphans a name-keyed cache (add a loud message naming the file count); `audit_barcode_coverage()` is a 3-hour I/O-bound tail with possible network calls (batch the reads or make it opt-in, 1.1); advertise `corroborate_references_locally()` in TaxaMatch's README (removes 53% of the BLAST workload in 0.3 s); lineage-guard report split by whether the disagreement crosses a higher rank; the two memory findings are in the memory brief | maintainer for the tracked four |
| Proposal: static input-availability check for workflow scripts (1.1 candidate) | From the CalIntertidal chat: Section 8 of its workflow had NEVER executed and hid five defects of one shape, "a step consumes something no upstream step produces" (a renamed list component, two objects assigned nowhere, two per-site tables used as if per-observation). Smaller version first: a lint that flags any symbol a script uses but never assigns and no attached package exports (the wizard's segmenter already classifies every top-level expression); the full version lets graph edges declare produced and required COLUMNS. Screen's view: the lint is cheap and would have caught three of five; the column graph is a design for 1.1. Also: `evaluate_likelihoods()` reports dropped observations via `warning()` (swallowed into "50 or more warnings" on big runs); `$unresolved` is returned, but a `message()` naming the count is the better channel. Measured on the 3-marker run: COI drops 141 of 13,170 observations, 18S 209 of 5,825, 12S none; the cause (candidates with no usable reference at the requested rank?) is unverified | maintainer |
| Harmonisation direction (CalIntertidal finding 23) | LANDED: `join_priors()`'s `backbone_id` docs say to harmonise the sequence side onto the occurrence backbone, never priors onto NCBI (measured: 29 percent of a marine prior table has no NCBI node, 19 percent more coarsened; the 29 percent re-tested deterministic across two runs on the pre-retry verifier, same 35 names both times, so it is real absence, not throttling; one post-retry re-run is queued after the reinstall and can only lower it; a failed map falls silently to the floor and reads as dark diversity); every call now reports the join rate per rank; TaxaAssign README sentence; test. Finding 22 (workflow passed the match backbone to join_priors/posterior_consensus) fixed workflow-side by that chat. Separable: NCBI-form NAMES can be reported even with a GBIF join (26 differing pairs on COI); docs could say naming and joining are independent | -- |
| Live-service tests and NCBI throttling | CI went red twice on pushes that did not touch TaxaTools: NCBI E-utilities intermittently dropped requests and the NCBI path reported "no match". FIXED both sides: the package's name search retries three times with a growing pause before a batch is reported as unmatched, with a warning that says "unmatched, not absent"; the live tests against NCBI, GlobalNames and WoRMS have provable reachability skips and a `TAXAID_SKIP_LIVE` switch, which CI now sets (19 tests skipped there, stated), so CI is deterministic and live coverage runs locally on demand | -- |
| Finding 24: cross-backbone synonymy in the consensus output | The consensus is GBIF-named; every conventional assignment (Jonah Ventures, top hit) is NCBI-named, so a method comparison counts every backbone synonym as a disagreement (19 true differences in 16,923 rows, all same-organism-different-name; the test is set membership, not string equality, and the mapping is one-to-many). Workflow-side shape built by that chat: `consensus_taxon_ncbi` (pipe-delimited), `n_ncbi_names`, `backbone_name_differs`, from the match objects' own name pair, no network. Candidate: `posterior_consensus()` emits them, or TaxaAssign documents the post-step; a node's backbone as a graph attribute belongs with the edge-columns proposal. That chat's local accession screen is PAUSED (300x over-scoped against core_nt; handed to its own chat), so the findings on `investigate_flagged_accessions()`/`review_flagged_accessions()` on real input are later | maintainer (1.1 design) |
| `verify_taxon_names()` verified flag (CalIntertidal finding, 2026-09-27) | LANDED: `verified` was TRUE on every row the API answered, including 25 of 120 with no match (documented that way, but the name invites `filter(verified)`, which keeps every failure: the checker-cannot-report-absence shape). Now returns `matched` (= verified and a name came back) beside it, documented as the column to filter on; mocked test. Finding 23's figure reworded to 20 to 30 percent on two independent 120-taxon draws (29.2 and 20.8; the seven named taxa still 0 of 7); the homonym gate fires on the second draw (Leptochiton, Idiacanthus) and needs `decisions`, which reproduction steps must say. rBLAST installed into the shared library (a new package; nothing loaded) so `blast_sequences(method = "local")` works from it. Noted for the package: no column says WHICH backbone matched when a fallback is in play; and GBIF has no class node for ray-finned fishes, so consumers must coalesce harmonised and native rank columns per ROW, never prefer a column wholesale | -- |
| Finding 26: harmonisation coverage per lineage | `harmonize_ranks_to_gbif()` reports pooled coverage (class 98.6 percent) while GBIF has no class node for ray-finned fishes, so `gbif_class` is NA for every Actinopteri row and a consumer preferring the column wholesale lost the largest class at a site. Package ask: report coverage PER LINEAGE (or flag any rank whose blanks concentrate in one clade), and document per-row coalescing | maintainer (1.1) |
| Local BLAST database consistency (from the mislabel-screen chat, relayed) | The user's `core_nt` is a MIXED SNAPSHOT: 73 of 91 volumes from one NCBI build, the rest and the index files from another; every per-volume checksum passed, yet accession and taxid lookups return the wrong records (a per-volume checksum cannot report that the SET is inconsistent, the same shape as three earlier findings). Screen verdicts from that database are untrustworthy until refetched. Package ask, rated high by that chat: a cheap consistency check in `blast_sequences(method = "local")` (one build date across volumes; alias count against the remote build), because the failure returns confident wrong taxonomy, not an error. Docs now carry the caution (`blast_sequences()` method) | maintainer (1.1; the docs line is done) |
| Counts path and memory estimator | LANDED at the maintainer's delegation (review to our standards, then commit): `gbif-facet-priors` merged `fe66385` (three exports, the iNat rename accepted, one site per call stated, Software Inventory brought current for three packages, TaxaFlag's README taught its new export, handoff to TaxaID_dev); `reference-memory-estimate` merged `c9e0a76` (`estimate_sequence_matrix_size()`, `fetch_ncbi_reference_sequences(dry_run =)`, the guard, `size_calibration`). Conflict against pair retention resolved by keeping both, and the guard is now RETENTION-AWARE: its model is calibrated on unretained builds, so under a retention policy it reports the ceiling as an upper bound instead of refusing a build that would fit (measured 2 to 6 fold lower). Budget fraction stays 0.7, documented as covering the pair table and training's copies, not reference sequences or aligner structures. TaxaLikely 1505/0, check 0/0/0 | -- |
| TaxaFlag LLM cache keys omit the model | LANDED. Reported by the LLM-pathway chat on `review_assignments()`; `review_sample_identity()`, which landed the same day, had the same key. Both now carry `.review_reviewer_id()`: `options("TaxaID.provider")` plus an identity for `llm_fn` (a package function is identified by its SIGNATURE, so refactoring a body does not orphan a large verdict cache; a caller's own wrapper is identified by its body, which is where a pinned model lives). Neither separates two models from ONE provider, so both functions gained `model_label =`, documented as the way to compare models. Prefixes `v1` to `v2` and `sir-v1` to `sir-v2`, so entries written before the fix are a miss once, which both functions say when the directory already holds entries. An api_key default deparses to the `Sys.getenv()` CALL, never a key value, and a test pins that | -- |
| Response ceiling for reasoning models | LANDED `dc74eb5`: `call_api()` and every provider wrapper raise `max_tokens` from 3000 to 16000. A reasoning model spends part of its budget thinking, so a ceiling sized for the visible answer returned a response with NO TEXT, and that failure covered every LLM path in the ecosystem (habitat, review, the LLM prior, the unreferenced suggester, report drafting, script annotation). Found by the LLM-pathway chat when a real tutorial run died in `build_context()`. Cap not allocation, so the larger default costs nothing; test pins it; `taxa_per_call`'s rationale now says it was measured against the old ceiling | -- |
| Group merge (LANDED `82d3bd0`; superseded row kept for the record) | Merging `flag-failed-libraries` (`ab41741`) then `sample-identity-gate` (`0b409b4`) into main costs two small text conflicts, both in the first (TaxaFlag/CLAUDE.md and the review-response table, where `flag_hopped_detections` already landed); the second merges clean. TaxaFlag would go 12 to 15 exports and 14 to 17 test files, so the root README's Software Inventory row and TaxaFlag's own function list both need the three new names before the merge is to standard. Two handoff documents on those branches move to TaxaID_dev. The LLM branch is VERIFIED at `4d9a097`: 854/0, check 0/0/0, a real tutorial run (374 observations, every prior from the LLM, no fallbacks), and it carries two bug fixes of its own, the per-batch prior normalisation and an omitted taxon receiving prior 0 (silently eliminated with `prior_phi = NULL`, aborting the run otherwise) | the maintainer: the group's go, once the LLM branch is verified and the README round is done |
| Branches awaiting the maintainer's yes (LANDED; superseded row kept for the record) | `flag-failed-libraries` (`ab41741`, now also single-marker run failure and a `failure_basis` column, 672/0), `sample-identity-gate` (`0b409b4`, rebased onto it, 771/0) and `llm-pathway-audit` (`0e639e9`), plus the maintainer's in-progress root README round in the shared checkout. The LLM branch carries a real bug fix (LLM priors were normalised per batch, so a lone implausible taxon in a small final batch could win at posterior 0.495) and one behaviour change consistent with the A3 precedent (`run_llm_pipeline(data_type =)` with no default). The maintainer's decision 2026-09-28: these move forward AS A GROUP, not piecemeal. The two TaxaFlag branches edit the same four files, so they merge in one sitting, oldest first, and this session resolves | maintainer |
| Development records in the released repo | `HANDOFF_index_hopping_filter.md` and `REENTRY_PROMPT_homonym_detection.md` moved to TaxaID_dev (`61df749`). STILL TRACKED and must not ship: `ecosystem_docs/REENTRY_PROMPT_prepublication_screen.md`, this document; move it at submission time, not before, since every session references it | submission |
| Identity gate: three changes requested after the merge | lafferty-09 asked 2026-09-28 to HOLD `sample-identity-gate`, which had already merged at `82d3bd0`. Not reverted: these are behaviour changes to a function that now exists, and a revert would also unpick the TaxaFlag README section, the Software Inventory row and the review-response arithmetic. To land as a follow-up on main: the samples were NOT spiked; the blanks are tap water; a thin study (no blanks, few samples) gets a "no evidence of a problem" status rather than a block. Asked that chat to confirm from the maintainer directly whether that status is a new level or a re-labelling, since that decides whether the returned column gains a level | that chat's follow-up branch |
| eDNA `template-counts-path` (`149c212`) | UNBLOCKED by the reinstall, and NEITHER mine nor the CalIntertidal chat's to merge; that chat has put it to the maintainer. If it goes ahead it goes through `git worktree add`, never a branch switch in the shared checkout, because other sessions are working in that tree. NOT mine to merge. It is 10-plus commits ahead of the eDNA `master`, and the substance is the workflow work itself (per-group kernel fits, the dedupe rebuild, the theta surfaces, the retention lines, then the template's records-or-counts switch), not a small carry. The shared eDNA checkout is on `workflow-ptcon-multisite` with uncommitted CalIntertidal files in it, so switching branches there would disturb another chat's working tree. The CalIntertidal chat owns that repo and owns this merge | that chat |
| Branch and worktree cleanup | `gbif-facet-priors`, `reference-memory-estimate` and `llm-pathway-audit` deleted; the last two had scratchpad worktrees from sessions that have ended, both clean and fully landed, so they were pruned. The remote holds only `main` and `jv-bracket-consensus`, so none of this needed a remote delete. STILL HELD, deliberately: `sample-identity-gate` (lafferty-09's follow-up), `local-comparison-subset-db` (lafferty-dd, in progress), and `flag-failed-libraries`, `flag-hopped-detections`, `local-blast-throughput`, which are clean and fully landed but sit in named worktrees whose owners I did not confirm; removing them loses nothing but would surprise a live session, so they wait for a word from their owners | a word from those owners |
| Local comparison-set search and batched investigation (`local-comparison-subset-db`) | LANDED, reviewed to our standards. Two measured wins in `investigate_flagged_accession()`: the comparison-set search now extracts those accessions through the database's own index into a throwaway database instead of using `-seqidlist`, which restricts the same way but does not skip reading (each search streamed the whole ~270 GB of `core_nt` from an external SSD, about 20 minutes measured, against under three seconds now); and `investigate_flagged_accessions()` does ONE record fetch and ONE disagreeing-taxon search for every uncached accession instead of a full database pass each, which was about 17 hours for 53. No new exports, so freeze rule 2 does not apply; two internal arguments on the core. Reviewed for the absence trap and it is handled: an accession the batch reports through `blast_sequences()`'s own `failed_query_ids` is searched alone, so a failed query is never read as no disagreement, and a test pins that (query counts 2 then 1). Success of the extraction is judged by records extracted, not exit status, because `blastdbcmd` exits non-zero whenever any accession is absent, and a stand-in that exits 1 while emitting a record tests exactly that. TaxaMatch 1401/0, check 0/0/0. The review-response entry I found stale (it still described `-seqidlist`) is rewritten and a second entry added | -- |
| Subset-database extraction: merged records, and an invisible fallback | LANDED as a follow-up to the row above, found by the live run rather than by review. `core_nt` stores identical sequences as ONE record carrying every accession's defline, so asking `blastdbcmd -entry_batch` for two such accessions returned that record twice under the first accession's id, the database build rejected the duplicate, and the search fell back to a full pass. Fixed with `-target_only`, which labels each copy by the accession actually requested; the real case was *Ronquilus jordani* FJ264437 and FJ264280. The test's stand-in emits the duplicate unless the flag is passed, so removing the flag fails the test. SECOND finding, and the more general one: that fallback warned correctly and NOBODY SAW IT, because `Rscript` defers warnings to exit, so a silent swap of a sub-second extraction for a roughly 20-minute full pass surfaced only after the run. It now emits a `message()` as well as the `warning()`. The same shape is already tracked for `evaluate_likelihoods()`, which reports dropped observations via `warning()` and disappears into "50 or more warnings" on a big run; that one is still OPEN | maintainer, for the `evaluate_likelihoods()` half |
| A failed NCBI fetch was being recorded as a verdict | LANDED. Third and largest of the live-run findings. A lineage that could not be FETCHED is empty, and an empty query lineage compares as disagreeing with EVERY hit, so an NCBI server error was being written into the cache as taxonomic incongruence. Two taxonomy batches returned HTTP 500 on a 12S top-up and about 400 accessions would have been cached as incongruent or insufficient; the author killed the run before any chunk cached. Now: five retries with a 2 to 16 second backoff instead of three over six seconds; the two resolvers report which taxids and accessions never resolved; `blast_sequences()` adds a query whose HIT taxonomy failed to `failed_query_ids`; `evaluate_reference_accessions()` sets aside a query whose OWN lineage failed, so it is not BLASTed, not cached, and retried next call. Same absence-as-evidence shape as the rest of the list, and the most expensive instance of it found so far, because the wrong answer was durable. GenBank XML now parses with `HUGE` at all four sites | -- |
| BEHAVIOUR CHANGE: `resolve_review_overrides(resolution_rank = "order")` | LANDED, and it CHANGES RESULTS, so it is flagged rather than buried. A marker's resolving power can only fail between close relatives, so a `poor_marker_resolution` or `sister_family_thin_coverage` explanation now overrides a removal only when the accession still agrees with its hits at order or finer. An accession kept under the old rule on a coarse agreement is now removed. Motivating case: nine *Lutjanus johnii* 12S records sharing only CLASS with their hits, 80 to 85 percent identical to both *L. johnii* mitogenomes, kept on a moderate-confidence "poor marker" review. `NULL` restores the old behaviour. Verified not vacuous: `finest_common_rank` is a real produced column, and the test covers class denied, order allowed, a non-resolution explanation unaffected, NA denied, `NULL` disabling, and the column absent. CONSEQUENCE FOR THE MAINTAINER: any reference screen whose kept-accession list was produced under the old rule may differ if re-run, which is a decision about consistency across sites, not a code question | maintainer: whether to re-run the reference screens for consistency |
| Retry asymmetry left as the author's call | `.resolve_taxonomy()` now retries five times with exponential backoff, while `.resolve_taxonomy_by_acc()`'s own accession lookup keeps three attempts at 2 then 4 seconds. The HTTP 500 that motivated the change could hit either path, so the reasoning applies to both, but raising it changes timing on a path nobody has measured. Not changed by me; raised with the author | that chat |
| 18S V9 primers registered (`register-18s-v9-primers`) | LANDED. `TaxaTools::barcode_primer_defaults` gains `18s-v9` (1389F/1510R, Amaral-Zettler et al. 2009) with a matching length window and an `18s-v9` to `18S` marker mapping, so one term serves both primer trimming and the NCBI search. Verified in silico against three real 18S genes, every stripped product ending in the same 3' sequence carried by real 18S environmental sequences, which is how the pair was identified. The trap the author's own tests caught is the interesting part: `resolve_barcode_primers()` resolves by unique PREFIX, so registering one 18S region made a bare `"18S"` silently resolve to V9, which would have trimmed a V4 study's references with V9 primers without a word. A bare `18S`, `ITS` or `ITS2` now refuses prefix resolution once a region is registered, and the error names the regions. I checked the regression risk rather than assuming: a bare term ALREADY errored before this change and every caller in the ecosystem wraps the call, so the paths that leave an unregistered marker untrimmed behave exactly as before; bare `18S` length resolution is also unchanged at 100 to 2000. TaxaTools 1223/0, TaxaMatch 1423/0. The accession lookup also gets the five-attempt backoff, closing the asymmetry | the rebuild, held for the live 12S top-up |
| METHOD FINDING: our own verification command can invent an error | `devtools::check(args = c("--no-manual", "--no-build-vignettes"))` reports 1 ERROR on TaxaTools, from vignette code, and it is an ARTEFACT of that invocation. Both TaxaTools vignettes deliberately set `eval = FALSE` AND `purl = FALSE`, with a comment in place saying `purl = FALSE` is load-bearing because the check step tangles the vignette; passing `--no-build-vignettes` as a CHECK argument defeats that and the raw chunks get tangled and run, so an illustrative `match_df` and a key-requiring API example both "fail". CI's own invocation, `rcmdcheck(args = c("--no-manual", "--as-cran"), build_args = "--no-manual")`, gives 0 errors, 0 warnings, 1 note, and that is the one to trust. Verified by running the CI command locally rather than by reasoning about it. USE THE CI INVOCATION when verifying a branch, or a future pass will re-chase this and may "fix" two vignettes that are correct | -- |
| Identity gate v2 | LANDED. The maintainer's three corrections from v1 are in, and the answer to the status question was NEW VALUES rather than a relabel: `unassessable` is replaced by `inconclusive` (reason `no_power`) and `untested` (reasons `no_blanks`, `unreplicated`, `uncomparable`), with the reason recorded per row in `identity_status_reason`. A thin study now warns and returns `untested`, where v1 raised an error, and a run with no blank gets `untested/no_blanks` where v1 wrongly called its samples concordant. No spike is assumed: a feature in at least 90 percent of a run's field units that also dominates at least half its blanks is reported as a run-wide ARTIFACT and set aside, and a real spike is declared through `spike_taxa`. `untested_policy` defaults to `admit`, which is what the maintainer asked for, and every run prints how many units were admitted with no discriminating test, in the words "no evidence of a problem, not evidence of none". No new exports. Peer-tested on the real archive including an injected failure (18S JVB5058 thinned to 1 percent), which is caught. TaxaFlag 881/0, inventory unchanged at 15 and 17. I checked the one thing a rebase could have silently dropped: `model_label` and the reviewer in the cache key survive, and the key is now `sir-v4`. Its handoff moved to TaxaID_dev | -- |
| OPEN: does the WoRMS-habitat refusal carry from the gate to `flag_contaminant()`? | The maintainer declined a WoRMS-habitat variant for the identity GATE, which answers "is this blank usable?" using only what exists at ingest. `flag_contaminant()` answers a different question, "may this taxon be removed?", at a different point in the pipeline. A decision on one does not automatically carry to the other, and neither chat is assuming it does or does not. Raised with the maintainer directly | maintainer |
| DECIDED: no deterministic blank "target-share" cut, in any form | The maintainer's decision, relayed 2026-09-28. It covers `classify_sampling_group()`, a phyla list, and a WoRMS-habitat variant alike, so it CLOSES the direction rather than sending it back for a better classifier. Three reasons, and the third is the general one. Taxa do not map cleanly to habitat: a phylum rule's top "target" genus was a freshwater oligochaete, and the same rule silently misses kelp, because Jonah Ventures leaves Phaeophyceae at `unk_phylum`. The gate may use only what exists at INGEST, and the prior table is built downstream. And being out of scope is NOT evidence of contamination, which `review_sample_identity()`'s prompt already says. CONSEQUENCE I am recording against my own earlier row: the phylum-plus-resolved-name classification, which I wrote up as the alternative that works, is ruled out too, and reason one says why it only looked like it worked. Anyone reading the CalIntertidal contaminant sketch should know its target classification rests on the same ruled-out footing | -- |
| DECIDED: the "admitted WITHOUT a discriminating test" line stays inside `verbose` | The maintainer accepted the reading I recorded when landing identity gate v2, so no change. The information is on every row in `identity_status_reason` and `untested_policy` is an explicit argument the caller chose, so the data carries it even when the console does not | -- |
| Finding 30: `flag_contaminant()` has no notion of WHAT a taxon is | Raised by the maintainer, measured by the CalIntertidal chat, NOT built. MECHANISM (survives, and is the point): a field blank missing its three fresh-water rinses keeps residual SEAWATER from the site, so the blank carries the site's own community. A target-group taxon in a blank is therefore explained by carryover from a place it genuinely lives; a non-target taxon in a blank is not. The score, `field_rate/(field_rate + control_rate)`, cannot tell them apart. WHICH NUMBERS STAND, after that chat tested its own classifier and found it fails: the named losses are real and are the strongest evidence, since they are identified by NAME, not by a lineage rule (*Ulva*, *Schimmelmannia schousboei*, *Hypnea*, *Chondracanthus canaliculatus*, four *Mazzaella*, *Microcladia coulteri*, *Smithora naiadum*); so are the scope-removal fractions, 99.1 percent of real contaminant reads on 18S, 20.8 on COI, 0.0 on 12S, which is the argument that HABITAT and not a proxy is what is wanted; and so is the observation that every non-target read surviving scope is a FRESHWATER species in a MARINE study. WHICH DO NOT: every "target-group" magnitude, including "macroalgae in 30 of 30 blanks at 3.50 percent", the 167 and 102 ESV counts, and the 40-to-1 harm-to-benefit ratio built on them. They came from a phylum rule with BOTH error directions: Jonah Ventures leaves brown algae at `unk_phylum`, so kelp was never counted at all, while plankton (*Pycnococcus provasolii*, 2,465 reads in 21 blanks), a sea pen and a freshwater oligochaete were counted as target. The direction of the error is not even one-sided, so the ratio cannot be repaired by adjustment. PROPOSAL, now LARGELY CLOSED by the maintainer's decision that habitat is out of contamination flagging entirely (see the row above): not a target SHARE but a CONTRADICTION was the proposal, and habitat was the instrument the measurement pointed to, so removing habitat leaves the shape without a demonstrated source. A caller-supplied logical column plus a separate verdict for a removal resting on blank evidence alone remains buildable, but only a caller with outside knowledge can populate it. The sketch is marked superseded and is not wired | 1.1, not urgent |
| Finding 29 stands, but no longer blocks the identity gate | `SCOPE_DEFAULT_BUCKET = "macroinvertebrates"` sits inside `SCOPE_IN_GROUPS`, so every unrecognised lineage lands in a target group. Measured: a known-CLEAN blank scores 64.6 percent "target", above known-contaminated blanks at 50 percent. A default bucket that is also an in-scope group makes "is this in scope?" unanswerable for anything unrecognised, which is a defect in its own right and still OPEN for `flag_contaminant()`. It is NOT what blocks the identity gate; see the row below, where the maintainer ruled out the whole approach on other grounds | maintainer, for `flag_contaminant()` |
| Placeholder DOI in all ten READMEs | `https://doi.org/10.5066/xxxxxx` appears in the root README and all nine package READMEs, and the URL check reports it. It is the USGS release DOI, assigned at release, so the placeholder is correct for now and MUST be filled before publication. Noticed because the CI-equivalent check reports it; CI itself passes, since it fails only on errors | submission |
| A consensus LABEL is not reproducible from saved inputs | FIXED, after being investigated rather than accepted at face value. The 12S stage_B run reproduced Round 1's posteriors exactly (37,554 rows, max difference 0) but one label changed on identical posteriors, and the screening chat reasonably inferred a `posterior_consensus()` behaviour change. IT WAS NOT: none of the three sources of a consensus label had changed since that run, checked against git. The real cause was that the label for an UNREFERENCED taxon came from an uncached LIVE service call made at run time, so a batch that failed transiently produced NA, and the retry added in `d9f0153` resolves the same name now; NCBI was separately measured failing about half its requests in that window. THE FIX: `verify_taxon_names(cache_dir =, cache_ttl_days =)` writes one file per answered name and NEVER writes a failure, so a cached non-answer can never be served as an answer; the key is the name plus everything that can change what it resolves to, including `decisions` BY CONTENT and a decisions file by its md5, while `batch_size` and `timeout_sec` are excluded because they cannot change a correct answer; the TTL exists so backbone updates reach a long-lived cache. `posterior_consensus()` gains `unreferenced_taxonomy_lookup` (matched / not_found / lookup_failed), taken as the WORST per observation so an `== "matched"` filter can never keep a failure, which is the `verified` versus `matched` lesson applied at design time instead of after. A failure messages as well as warns. Third instance of the absence-as-evidence family, and now the third one closed. TaxaTools 1237/0, TaxaAssign 864/0 | the rebuild, held for the live 18S screen |
| `build_sequence_matrix(seed = )` BUILT, at the maintainer's approval | The draws behind `max_seqs_per_taxon`, the per-genus representative and `max_foreign_reps_per_genus` decide which sequences train the calibration, and therefore every likelihood resting on it. The old contract asked the caller to `set.seed()` beforehand, stated in four roxygen places; measured across FIVE production call sites, none honoured it, and CalIntertidal appeared to while not doing so, holding a seed for this call that was dead code inside a block gated on a constant set to NULL. A seed now fixes the draws inside the call and hands the caller's RNG stream back untouched. THE DEFAULT STAYS NULL, and not for compatibility: `check_cross_genus_sampling_noise()` calls this function repeatedly to MEASURE how much the representative draw moves the estimate, so a fixed default seed would make every replicate identical and it would report zero noise, a plausible wrong number rather than an error. An unseeded build that will draw now says so, stating what is certainly true rather than guessing, because R cannot distinguish a deliberate `set.seed()` from an initialised stream. TaxaLikely 1531/0. The five workflows can now pass `seed =` instead of relying on a convention none of them kept | the workflow chats, to adopt it |
| `validate_controls()` power verdict depended on the RUN, not the data | Found by the identity-gate chat, fix on the held branch. Above `max_null_pairs` (500) the null distribution was an UNSEEDED subsample, so the power verdict for a large site was drawn afresh each call. Measured on CalIntertidal: 32 COI JVB3506 units and one blank (JAC2V5IK 12S) flipped between IDENTICAL calls, and this explains three different "admitted without a discriminating test" counts, 461, 493 and 793, quoted across sessions and all believed at the time. This is NOT gate-specific: it reaches every `validate_controls()` caller on a site large enough to trip the subsample. Fix is a fixed local seed with the caller's `.Random.seed` restored, pinned by a test on both halves. FOURTH member of the family where a result depended on something other than its inputs, after the two TaxaMatch fetch failures and the consensus label, and the only one whose symptom was a NUMBER PEOPLE QUOTED rather than a missing value | with the held branch |
| `identity-gate-v3` LANDED, after its session ended | The author session ended with the branch unmerged; the CalIntertidal chat verified it, fixed its one blocker and committed the fix so it would not die with the worktree, then handed it over with no claim on it. THE BLOCKER was a plain bug and a good one: in `.sig_dominance()`, `lab <- if ("label_name" %in% names(x)) ... else NA` made `lab` length 1, `ifelse()` returns the length of its TEST, so the vector collapsed and `top_taxon` was NA for EVERY unit while `top_taxon_share` stayed fully populated. A bare share does not merely lack information, it invites the opposite reading: 1.0 means a clean spike-dominated blank or a blank that is 100 percent one local organism, depending entirely on the name. Verified on a 2,157-unit build: both columns 100 percent populated. BEHAVIOUR CHANGES, recorded as such: `confirm_blank` no longer admits every marker of a tube as a control; `llm_role` for a `contaminated_blank` moves from "exclude" to "blank", since identity is per tube and usability per marker; the review cache key goes to `sir-v5`. Additions: `sample_viability`, `control_usability`, per-tube `blank_medium`, dominance columns, `validate_controls(max_null_pairs)` at 5000 with the seed underneath. Verified on the real archive: 122 usable controls, 47 contaminated in marker, 1,931 viable samples, 97 s at the new cap, admitted-without-a-test stable at 493. TaxaFlag 925/0. No new exports | -- |
| DECIDED: no re-run of the reference screens | The maintainer's decision. The stricter `resolve_review_overrides(resolution_rank = "order")` default therefore applies to future runs only, and existing kept-accession lists stand as produced. Nothing further is owed on this | -- |
| DECIDED: habitat is OUT of contamination flagging entirely | The maintainer's decision, and it goes further than the question asked. It is not that a habitat instrument defaults to off; habitat is removed from the design, so there is to be no habitat argument, no habitat source for a corroboration column, and no documentation pointing contamination flagging at TaxaHabitat. Nothing had to be removed from code: `flag_contaminant()` and its help have no habitat coupling today, verified rather than assumed, and the habitat references in TaxaFlag's README all belong to `review_assignments()`, which is a different function and untouched by this. HONEST CONSEQUENCE, recorded so a later pass does not reopen it as if it were narrowing: this largely CLOSES finding 30 rather than trimming it. The measured argument for corroboration was specifically that scope is a poor instrument (it removes 99.1 percent of real contaminant reads on 18S, 20.8 on COI, 0.0 on 12S) and that habitat is the good one, since every non-target read surviving scope was a freshwater species in a marine study. Remove habitat and the proposal keeps its shape but loses the only demonstrated way to populate it from inside the ecosystem. What remains buildable is a caller-supplied logical column plus a separate verdict for a removal resting on blank evidence alone, which requires the caller to bring outside knowledge; whether that is worth an argument is a 1.1 question and no longer an urgent one | -- |
| Sweep: the `ifelse()` length trap elsewhere | `ifelse()` returns the length of its TEST, so a branch that can yield a length-1 value silently collapses the result. Swept all nine packages for a variable assigned `if (...) vec else NA*` that then feeds an `ifelse()`. ONE further instance, in `assign_taxa_llm()`'s prompt builder, and it is HONESTLY benign: `sprintf()` recycles a length-1 argument so every row correctly received the empty string. Fixed anyway, because the LENGTH depended on whether a column existed, which is exactly the shape that bit `.sig_dominance()`. The CalIntertidal chat reports hitting the identical bug in its own helper, so this is three occurrences in one project. `dplyr::if_else()` errors on a length mismatch and would have caught all three; worth considering as a house rule | maintainer |
| Measured result of the two TaxaMatch merges | Stage 2 of the live 12S screen did 53 accessions in 26 MINUTES with the merged fixes. The original code path would have taken roughly 40 to 57 hours on the same work: a full pass over `core_nt` per accession for the disagreeing-taxon search, plus a second full pass per comparison-set search whenever the merged-record duplicate sent it down the fallback. That is the whole case for both merges, measured on real data rather than argued | -- |
| Finding 23 re-run: settled, not moved | The post-retry verifier does NOT lower the unresolved fraction. On the same seeded 120-taxon draw it gives 25 of 120 with no NCBI match, 20.8 percent, which is what the fresh draw gave before the retry fix, so the 29.2 to 20.8 difference was sampling between draws. The docs wording, roughly 20 to 30 percent on two independent draws, stands and needs no edit. Recorded because an untested "should be lower" left lying around costs a later pass an hour. Finding 25 confirmed on the same run: `matched` agrees exactly with the presence of a matched name on all 120 rows while the old `verified` still reports 120 of 120 passing, so adding a column rather than redefining the old one was right | -- |
| CalIntertidal working tree is not one session's | Four untracked directories in that chat's tree were created by PEER sessions, not by it (`hop_validation`, `failed_library_validation`, `identity_gate_validation`, `accession_screen`), and one is still being written by the live screen. Nobody can judge that tree's cleanliness from its status output alone, which is why the eDNA merge below is not a mechanical carry | -- |
| Memory branch resolution note | its `.matrix_structure()` should use the retention-aware pair formula (TaxaID_dev/ecosystem_docs/DESIGN_seq_matrix_pair_retention.md, Section 6) | the screen session, at resolution |

Other chats and what they own: California intertidal multi-marker workflow
(its runs and the eDNA repo); optimize likelihood matrix (pair retention,
landed; its benchmark run); memory estimate (ended; branch above);
workflow scripts verification (ended; all landed); homonym (ended; all
landed); theta-surface rendering (ended; landed).


Every pre-publication pass so far has *added*: a fix, a function, a doc, a
re-entry prompt. Each addition widened the surface the next pass had to check,
which found more, which added more. That loop is why the ecosystem is hard to
finish, review and use. This screen is the first pass allowed to **subtract**,
and it succeeds by *finding nothing material* at the end, not by finding things.

Two consequences shape everything here:

- **From a user's perspective, what ships is TaxaID 1.0.** A 1.0 has no
  predecessor. Nothing user-facing says what a function used to do, when a
  default changed, or which session changed it. Rationale stays ("we chose
  kernels over grids because ..."); history goes.
- **The screen is verification plus subtraction, under a growth freeze.** The
  freeze is a *guide*, not a hard rule: the user prefers splitting to catch-all
  functions, and running real data through the package has been the best way
  to improve it, so some additions during the screen are expected. Each one is
  discussed, ledgered (section 5) and reviewed -- never silent.

## 2. Related documents (read before starting a pass)

| document | role in the screen |
|---|---|
| `REVIEW_PROMPT_full_ecosystem_review_2026_09_13.md` + `fable_ecosystem_review_2026-09-13.md` | the last *discovery* review; this screen is its closing counterpart, not a repeat |
| Claude memory `pre-code-review-package-checklist` (9 passes: debris, non-ASCII, names, doc completeness, lintr, check+test, vulnerabilities/domain, CLAUDE.md, commit) | the **per-package** layer; Stage B runs passes 1-7 per package |
| `inst/Code and Domain Review 2.Rmd` | Micah Wright's review template; applied to post-review functions in A5 |
| `inst/extra_functions_for_review.md` | the 2026-08-11 method for "functions written after the review", with per-package review-pulled dates; regenerated at the freeze tag in A5 |
| `usgs_release_review/README.md` | the WERC *release* review (distinct from Micah's code review); three items undecided, no written response exists |
| `CACHE_POLICY_REVIEW_2026_09_14.md` | the one cache policy; A6 documents it for users, does not reopen it |
| `REENTRY_PROMPT_post_reference_screen_full_workflow_runs.md` | run checklist for B2, not a work order |

## 3. Decisions taken (user, 2026-09-20)

1. **Growth freeze as a guide.** No new exports on `main` without discussion;
   splitting an overgrown function is a legitimate addition.
2. **Freeze mechanics:** a tag, a git-derived ledger, the workflow chat on a
   branch, a tracker chat that keeps the review responses current (section 5).
3. **`*_clear_cache()` x6:** API left alone, pattern documented once
   (assumption from "cache may do work in other projects"; revisit if wrong).
4. **Legacy tolerances are deleted from the repo.** No pre-1.0 string, key or
   file format is recognised by 1.0 code.
5. **Caches:** never in the repo; disk footprint matters. The reference
   mislabel-detection cache (TaxaMatch/TaxaLikely verdicts) is worth keeping
   across projects; the GBIF cache is disposable.
6. **`CLAUDE.md` history stays** (it is agent context, `.Rbuildignore`d, and
   has been useful). **Public-facing surfaces are fixed**: README, roxygen,
   vignettes, NEWS, `ecosystem_docs/`.
7. **`ecosystem_docs/` and `NEWS.md` collapse** to 1.0-appropriate content.
8. **Change-log stamps leave user view** entirely.
9. **Empirical workflows and site analyses leave the TaxaID repo.** The user
   judges this separation to have been done poorly so far.
10. **Multiple chats continue**, partitioned by repository/package, with
    "check the thing" as the tie-breaker when they disagree.

## 4. State on 2026-09-20 (the numbers the passes start from)

- 9 packages, **225 exports**, **101,089 lines** in `R/`, **59,000 lines** of
  tests (7,394 tests green on 2026-09-15).
- **At least 52 exports postdate the per-package review dates**
  (2026-06-27 to 2026-08-09; count uses 2026-08-11 as a floor). Six are
  per-package `*_clear_cache()`.
- Roxygen (user-facing help) carries **295 date stamps, 53 "Session N",
  28 "previously", 26 "no longer", 21 "renamed", 16 "superseded",
  13 "legacy", 12 "retired"**. TaxaMatch 132 hits, TaxaLikely 107.
- Legacy-tolerance *code* (not prose): ~16 grep hits, TaxaLikely 9,
  TaxaAssign 3 (incl. `.KERNEL_BRANCH <- c("kernel_estimated",
  "resident_observed")`), TaxaMatch 2, TaxaExpect 1, TaxaWizard 1; plus
  `TaxaMatch::migrate_reference_cache()`, whose only purpose is pre-1.0 caches.
- `CLAUDE.md` files total **2.1 MB** (root 529 KB, 3,672 lines; TaxaLikely
  422 KB). All `.Rbuildignore`d; all in the public repo.
- Signal neutrality: root README balanced (sequence 36 / image 20 /
  acoustic 17 / eDNA 16). Leaks: TaxaLikely README eDNA x8, TaxaFlag README
  ESV x6.
- Caches: none tracked in the repo. On disk `~/Library/Caches/org.R-project.R/R/`:
  TaxaFetch **2.7 GB**, TaxaLikely 109 MB, TaxaTools 4 KB, TaxaWizard 216 KB;
  TaxaMatch absent (workflows pass explicit `cache_dir`s).
- Empirical/site material inside TaxaID: `diagnostics/` (45 tracked files,
  most site-named), untracked `GL_presentation/` 27 MB,
  `TaxaID_presentation_files/` 6.5 MB, `presentation_analyses/`,
  `taxaid_burns_harbor_app/`, `Claude outputs/`,
  `archive_retired_workflow_template_2026_09_15/`; per-package
  `archive_*` dirs in TaxaLikely (4) and TaxaExpect (1, the GLMM pipeline);
  `TaxaMatch/inst/extdata` is 60 MB.
- Residue: **17 `.bak` files** in TaxaID (2026-09-12..19) and 7 in the two
  workflow repos, all postdating the convention's retirement on 2026-09-13;
  one stash (2026-09-18, `p1b-rd-parse`, llm_prompts regeneration);
  **21 merged branches** undeleted; root strays `KPCO*.csv`,
  `PtCon18SSchulte_*.rds`, `Rplots.pdf`, `README.html(+.bak)`. No git lock,
  merge or rebase state; no untracked files; worktree list clean.
- **Concurrency, live:** a second session is editing `TaxaFlag`,
  `TaxaHabitat` and `eDNA/PtConception/Multi_site_multi_marker/` on `main`
  (7 uncommitted TaxaID files, 2 in eDNA). `CaliforniaIntertidalWorkflow_
  multi_marker.R` has 23 `## STUB`s. This is the "large workflow" of
  section 5; it will run for days.

## 5. Freeze protocol (the cake-and-eat-it mechanism)

The workflow work does not stop, and the screen does not wait for it.

1. **Tag.** When Stage A is done and the user declares the freeze:
   `git tag pre-1.0-freeze` on `main` in TaxaID. Stage B runs against the tag.
2. **The ledger is git, not self-report.** What changed since the freeze is
   `git log pre-1.0-freeze..main --name-status -- '*/R/' '*/NAMESPACE' '*/tests/'`.
   Nobody is asked to remember to announce a function; the query finds it.
3. **The workflow chat works on a branch** (`workflow-<site>`), commits as it
   goes, and merges to `main` only via the tracker. Package fixes it needs are
   committed on the branch with a test.
4. **The tracker chat** (a separate, cheap-model chat the user runs) does three
   things at each checkpoint and nothing else: runs the ledger query; for every
   new or changed exported function, checks a test exists and adds/updates the
   line in that package's `inst/*_review_response.md` "Added after the review"
   section (name, one-line purpose, test file -- no narration); flags to the
   user anything that is a new export, so the freeze-as-guide discussion
   happens. It does not review code; A5/B do.
5. **Every post-tag package change re-runs Stage B for that package only**
   (checklist passes 5-7, tests, check). The final named-commit statement
   cites the last such re-run.
6. **Communication channel to other chats:** a 10-line "Release freeze
   protocol" block at the top of root `CLAUDE.md` pointing here, plus a Claude
   memory entry. Both are the only files every chat reads.

## 6. Stage A -- editorial passes (run now; tolerate a moving tree)

Each pass is per-file and disjoint from the live workflow edits. Discovery on
Sonnet, adjudication on the expensive model, user decides anything marked
*decide*. "Done when" is the check, not the proxy.

### A1. Metadiscourse purge (roxygen, README, vignettes, NEWS)

Three kinds, three treatments:
- **Rationale** (`@section Why the query is the primer-stripped amplicon
  (2026-09-03)`) -- keep the reasoning, delete the date and session.
- **Change-log stamps** ("Default changed (Session 151)", "pre-2026-09-02
  behaviour", "previously computed as ...", "no longer ...") -- delete. Where
  the sentence carries a fact a user still needs, restate it in the present
  tense.
- **Grid/GLMM-style history** in READMEs (root 3 hits, TaxaExpect 6) -- one
  sentence of considered-alternatives-and-why, no chronology.
`NEWS.md` x9 -> a single `1.0.0` entry each. Agent: one Sonnet per package,
edits on a branch, `devtools::document()` after.
Three rules added after the first two packages (TaxaMatch 132 -> 21,
TaxaLikely 107 -> 18 roxygen hits):
- **The literal grep undercounts.** History also reads "widened from an
  earlier default", "restore the old implicit behavior", "the original
  implementation", "before this fix", "now uses". Sweep for these and read
  every `@section`/`@details`.
- **No pointers out of the package.** Help text referenced `CLAUDE.md`
  (29 lines), `ecosystem_docs/` (49), `diagnostics/`, `REENTRY_PROMPT_*`,
  `SPEC_*` and `[[memory]]` names -- none exist in an installed package.
  Delete or restate.
- **Runtime strings are user view.** `message()`/`warning()`/`stop()`
  literals carried "pre-Session-139", "pre-2026-09-02", "added Session 158"
  (found with the R parser's `STR_CONST` tokens, since multi-line `paste0()`
  defeats grep). Wording-only edits to these are in scope. **Done when** the grep of
section 4 returns 0 for session/date/previously/no-longer/renamed/superseded/
legacy/retired in `R/*.R` roxygen, READMEs and vignettes, *and* a reader
opening five random help pages finds the reasoning intact.

### A2. Legacy-tolerance deletion (code)

Delete every code path that recognises a pre-1.0 string, key or file layout
(section 4 list), and `migrate_reference_cache()` (*decide*: it is the one
function whose deletion could strand the user's own mislabel cache -- run it
once on that cache first, then delete). Tests that exercise the tolerance are
deleted with it; tests asserting the *new* behaviour stay. **Done when** the
grep is 0 and every package's tests pass.
**Targets surfaced by A1 (2026-09-20), code + roxygen together:**
- TaxaAssign `kernel_branch.R`: `.KERNEL_BRANCH <- c("kernel_estimated",
  "resident_observed")` -> one label (A1 had rewritten the roxygen to say both
  are "permanently accepted"; decision 4 says otherwise).
- TaxaAssign `posterior_consensus.R` (~371, 391, 884): the "legacy GLMM
  tables" / "table predates the kernel schema" fallback reading.
- TaxaAssign `suggest_unreferenced_species()`: a "deprecated forwarding
  wrapper" to TaxaLikely; nothing to forward from in 1.0. Un-export/delete.
- TaxaLikely `fetch.R`: the `"legacy"` cache-generation status and `n_legacy`
  attribute (a tolerance for pre-versioned cache files).
- TaxaMatch `migrate_reference_cache()`: FIRST the user runs, once, on the
  live reference-evaluation cache directory (path still needed):
  `TaxaMatch::migrate_reference_cache("<cache_dir>")` -- success prints the
  carried-forward / left-under-old-key / already-current counts and writes
  `reference_accession_cache.rds.bak_pre_<version>` beside the cache. THEN
  delete: `R/migrate_reference_cache.R`, `man/migrate_reference_cache.Rd`
  (roxygen does not remove orphaned Rd), the `.old_key_cache()` fixture and
  four tests at the end of `tests/testthat/test-local-corroboration.R`, and
  rewrite ~6 roxygen passages in `evaluate_reference_accessions.R` that
  instruct the reader to run it (~41-52, ~142, ~1513, ~1979, ~2005); then
  `devtools::document()`. All other A2 TaxaMatch work is DONE (branch
  `screen-a2-TaxaMatch`, 544 tests green).
- TaxaExpect `estimate_kernel_priors()` / `generate_undetected_diversity()`:
  the `inherits(model_obj, "biofreq_model")` branches and doc references to
  `train_biodiversity_model()`, a function that exists nowhere in the repo --
  the archived GLMM pipeline's input type.
- TaxaWizard: the unused internal "Legacy System Prompt" assembler
  (`engine.R` ~457) and the `metadata` -> `registry` argument alias with its
  deprecation warning -- tolerances for the pre-restructure API.
- **Caches are the exception to "loud failure"**: an unversioned or legacy
  cache entry is a cache MISS (refetch, with a message), not an error; the
  loud `stop()` rule is for data tables (priors, consensus) whose silent loss
  changes results.
- **Consequence of the TaxaLikely cache rule (measured 2026-09-20, read-only):**
  1,932 of 1,933 meta files in `~/Library/Caches/org.R-project.R/R/TaxaLikely`
  lack `sel_params` and all 1,933 lack `acc_version`, so the next production
  fetch treats the whole 109 MB / 25,945-file store as COLD and re-downloads
  from NCBI (hours, not minutes; NCBI throttling applies). Entries self-heal
  on refetch. Schedule that cold run deliberately, before Stage B2, with NCBI
  healthy -- it is needed for B2 anyway.
- **DESCRIPTION files**: A1 excluded them for safety, but TaxaExpect's
  `Description:` still described the retired grid design and rendered in
  `?TaxaExpect` (fixed on its branch). Check all nine `Title:`/`Description:`
  fields before the tag; `Version:` bumps to 1.0.0 at the tag.
- **Stage B check() items found by A1**: TaxaHabitat roxygen has literal
  `[0, 1]`/`[0, 1.05]` ranges parsed as markdown links (report_habitat.R:140,
  151) and a `[.candidate_habitats()]` link (utils_plot.R:541); em-dashes are
  pervasive in TaxaTools and present in TaxaHabitat/TaxaAssign R files
  (checklist pass 2, non-ASCII).

### A3. Signal-neutrality audit

Classify all 225 exports as *signal-specific* (BLAST, amplicon, ESV readers,
BirdNET/image readers) or *generic*. For the generic set, check roxygen prose,
argument names, README paragraphs and -- the usual leak -- `@examples` use
observation/detection vocabulary and are not all DNA. Do not scrub the
signal-specific set. *Decide* borderline names the agent lists (e.g.
`validate_controls()`). **Decided 2026-09-20 for TaxaFlag** (all 12 exports
generic, 16 vocabulary leaks, 3 API-level leaks): `reads_col` ->
`count_col` (default `"count"`) in `flag_contaminant()`,
`validate_controls()`, `build_review_covariates()`; `taxon_col` default
`"ESVId"` -> `"taxon_id"`; `review_assignments(data_type=)` loses its
`"eDNA"` default. Workflow call sites in all three repos change in the same
commit. **A3 audit COMPLETE for all nine packages (2026-09-20;
`scratchpad/A3_partial_reports.md` + `A3_signal_neutrality_remaining.md`):
of 215 exports after A7, 171 generic / 44 signal-specific (32 DNA, 4 image,
1 acoustic, 7 literature). TaxaAssign, TaxaExpect, TaxaHabitat, TaxaWizard
are 100% generic. TaxaFlag's 16 leaks FIXED on its A1 branch. Remaining: 16
prose leaks (Tools 4, Fetch 2, Match 3, Assign 4, Likely 2, Wizard 2) + the
TaxaHabitat README's "Most eDNA studies" line -- apply after merge; two
API-level items and six borderline names need the user (below). Pattern:
generic packages have zero image/acoustic worked examples (TaxaAssign,
TaxaWizard onboarding); TaxaLikely's model functions are neutral but only a
DNA producer (`build_sequence_matrix()`) feeds them.**
**DONE 2026-09-20** by the workflow chat (TaxaID `6870776` on
`workflow-ptcon-multisite`, eDNA `2819a39`, GreatLakes `4218f37`; 618 tests
pass). As built: `count_col` default `"count"` in all three functions; the
`"ESVId"` default existed only in `build_review_covariates()` and became
`"taxon_id"` there; `review_spatial_context()` gained its own required
`data_type` because it forwards to `review_assignments()`. **Output column
names (`n_reads_total`, `min_reads`, `max_reads`, ...) stay as they are** --
production workflows filter on them; renaming outputs is not a docs pass. **Done when** the classification table exists and
every generic export's help page passes a "would an acoustician read this as
theirs?" read.

### A4. Repository hygiene and separation

- **Empirical material out of TaxaID** (decision 9): `diagnostics/` site
  probes, presentations, the Burns Harbor app, `Claude outputs/`, per-package
  `archive_*` dirs. Destination (decided 2026-09-20): a new git repo at
  `~/My Drive/Rscripts/projects/TaxaID_dev/`. `diagnostics/` moves in its
  entirety EXCEPT (decided after the inventory, 2026-09-20)
  `build_workflow_template.R` and the `fast_workflows/` fixtures, which move
  INTO `TaxaWizard/inst/` because the root README's "confirm your
  installation works" section and TaxaWizard's template regression test
  depend on them; both get repointed. The two external `AuditNCBI.R` scripts
  (eDNA/PtConception, GreatLakes data) are repointed to the CSV's new home.
  `.Rproj.user/` (11 GB, root + all nine packages) is DELETED, not moved --
  only after RStudio is closed. The 2026-09-18 stash: inspect, then drop.
  `TaxaHabitat/inst/extdata/ne_10m_minor_islands_coastline.rds` is
  load-bearing but untracked (blanket `*.rds` ignore): force-add it.
  `usgs_release_review/` STAYS (release provenance, B5 runs against it).
- **`ecosystem_docs/` collapse** (decision 7): keep user-facing docs
  (`ECOSYSTEM_WORKFLOW.md`, `EXTERNAL_DATA_SOURCES.md`,
  `STATISTICAL_COMPONENT_CATALOG.md`); move `NAME_CHANGE_HISTORY.md` (it is
  history), `REENTRY_PROMPT_*`, `REVIEW_PROMPT_*`,
  `fable_ecosystem_review_*`, `RECORD_*`, `SPEC_*`, `WORKFLOW_STRUCTURE_
  AUDIT_*` to the dev folder. This document moves last, after Stage B.
- **Residue**: `.bak` x24 (move to `_archive_...`, never `rm` -- Drive
  multi-parent rule), drop the stash after the user confirms it is dead,
  delete the 21 merged branches, move root strays. **Done when** `git branch
  --merged main` lists only `main`, `find -name '*.bak*'` is empty in all
  three repos, and `git status --ignored` at the TaxaID root shows only
  `.Rproj.user`, `pkgdown_sites/` and `.Rhistory`.
- **`TaxaMatch/inst/extdata` 60 MB**: decided -- a 1.0 user needs almost none
  of it. Keep only files referenced by tests, examples or vignettes; the rest
  goes to `TaxaID_dev`.
**EXECUTED 2026-09-20** (branch `screen-a4-moves`, 6 commits; `TaxaID_dev`
created, 338 MB, 10 commits, `PROVENANCE.md`): all of the above plus 19
merged branches deleted, the coastline `.rds` tracked, extdata 60 -> 9.3 MB,
`ecosystem_docs/session_notes/` (found, moved), the template generator and
fast fixtures relocated into `TaxaWizard/inst/` with the test now failing
loudly, both external `AuditNCBI.R` scripts repointed (uncommitted). LEFT FOR
MERGE TIME: untracked residue still inside `diagnostics/` and
`ecosystem_docs/readmes/` in the main checkout (their tracked siblings live
only on the branch until it merges); `.Rproj.user/` (11 GB, RStudio open);
`jv-bracket-consensus` (merged locally, remote-tracking branch stale --
delete with `-D` and `git push origin --delete` at push time); ~25 prose
citations of moved files in CLAUDE.md/dev comments (historical pointers,
left by decision). `llm_prompts/` is touched by three branches and is a
GENERATED artifact: after all merges and a reinstall, regenerate it with
`TaxaWizard::workflow_export_prompts("llm_prompts", overwrite = TRUE,
placeholder_setup_report = TRUE)` rather than merging it by hand.

### A5. Review responses (Micah's code review + the WERC release review)

1. Regenerate `inst/extra_functions_for_review.md`'s catalogue by its own
   method at the current tree (later re-run at the tag): every exported and
   internal function introduced after each package's review-pulled date.
2. Run Micah's template (`inst/Code and Domain Review 2.Rmd`) over exactly
   those functions -- one Sonnet agent per package, adjudicated.
3. Each `inst/*_review_response.md` gains one section, **"Added after the
   review"**: function, one-line purpose, test file. Nothing about how our own
   review changed the code.
4. Strip existing self-review narration from the responses (TaxaHabitat's
   opens with its own 2026-07-28 review-prep pass; others describe
   "reorganised since the review").
5. **WERC release review**: write the response that `usgs_release_review/
   README.md` says does not exist; its three open items are DECIDED
   (user, 2026-09-21): `CLAUDE.md` files stay where they are (agent-context
   for maintainers, `.Rbuildignore`d, never in the built package);
   `ECOSYSTEM_WORKFLOW.md` linked from the root README (already is, line
   ~878); `PACKAGE_SETUP.md` and `DESCRIPTION.md` no longer exist on `main`,
   so the response records them as retired with their content in the root
   README's installation and package sections. Keep the push-back on
   deleting tests, confirmed with the reviewer.
**Done when** every response has the section, none narrates self-review, and
the release-review response exists in that folder.
**FIRST HALF DONE 2026-09-21** (branch `screen-a5-reviews`): catalogue
regenerated at `inst/extra_functions_for_review.md` -- 64 exported / 294
internal functions postdate the human review (TaxaMatch 15, TaxaTools 15,
TaxaExpect 13, TaxaFlag 6, TaxaHabitat 5, TaxaFetch 4, TaxaWizard 4,
TaxaLikely 2, TaxaAssign 0); 29 exports retired since review. All nine
response files carry one "Added after the review" table; self-review
narration removed (-660 lines net). **Template reviews (read-only, one per
package, `scratchpad/A5_review_<Pkg>.md`)**: TaxaMatch done -- 2 DEFECTS,
both reproduced by the coordinator: `flag_incongruent_references()`
multiplies `match_df` rows when `evaluation` holds two version-suffixed
copies of one accession (dedup keys the raw accession before the stripped
join key); `verify_local_corroborations()` can return `status = "clean"`
from a STALE params_key generation because `match()` takes the first
(oldest) cache row. 1 RISK (`.summarise_corroborators()` reads the pair
cache without a params_key filter). Findings are FIXED in code (branch
`screen-a5-fixes`), never narrated in the response files (rule c).
TaxaTools done -- 1 DEFECT, reproduced: the shared cache-clearing engine
(`report_and_clear_cache()`/`list_cache_files()`, used by every package's
`*_clear_cache()`) has no containment check -- `taxatools_clear_cache(
cache_dir = ".")` deletes a pattern-matching user file from the working
directory. Fix in the engine: refuse cwd/home/root, refuse mixed directories
without `force = TRUE`, do not follow symlinks out of `cache_dir`. 2 RISK
(untrusted `readRDS()` of cache/manifest files), 1 DOC ("eleven groups" is
ten names, eleven rules), 1 STYLE (`write_taxaid_manifest()` validates
nothing). Positive: `assign_sampling_group()` and `fetch_worms_attributes()`
are the best-documented, best-tested code reviewed -- every domain rule has a
cited real case and a fixture test reproducing it.
TaxaExpect done -- 1 DEFECT, reproduced: the equirectangular distance
formula (`111 * sqrt(dlat^2 + (dlon * cos(lat))^2)`, naive `lon1 - lon2`)
does not wrap at the antimeridian; a site at 179.9 with records at -179.9
(22 km) got theta 1e-33 while records 2,000 km away got 1.0. The formula is
copy-pasted in FOUR files (`estimate_kernel_priors`, `calibrate_kernel_
bandwidth`, `plot_theta_surface`, `generate_uncertain_habitat_evidence`);
fix = one internal helper with longitude normalisation, all four call it.
No current site is affected. 6 RISK (unvalidated numeric params in
`generate_regional_proximity_evidence()`, a hard-coded 0.05 veto bound, a
comment overclaiming a circularity guard, no Inf guard on `distance_km`),
3 DOC, 2 STYLE. Every checked formula -- Kish n_eff, Beta variance, Chao1,
presence-mixture moments, log-link curve fit, FFT lattice -- matches its
roxygen; `plot_theta_surface()`'s site-identity invariant verified live.
TaxaFlag done -- 2 DEFECTS in `validate_controls()`, reproduced: an all-zero
control column vanishes from the output (no row, no verdict) against its
"one row per sampled unit" contract; the per-column distance loop is
uncapped, 68.8 s at the 1,151-sample case its own roxygen cites. 3 RISK:
the contaminant evidence gate is a count floor, not a significance test
(honestly disclosed in the roxygen -- the open item from the 2026-09-20
design); LLM prompt text is unescaped user data (bounded: nothing executes
on the reply); returned categories not validated against the enum. API
keys never enter TaxaFlag code; cache paths are hashes; the Shiny gadget
has no `eval`/`parse`/`HTML()` sink.
TaxaHabitat done -- 5 DEFECTS, reproduced (branch `screen-a5-fixes-habitat`):
(1) `save_/apply_spatial_review_decisions()` key on `point_id` alone, so two
taxa sharing a point get one taxon's flag applied to both and the other
never resurfaces -- the user's three real decision files (GreatLakes 5,044
rows, PtCon, Mugu) carry NO taxon column; fix keys on `(point_id,
taxon_name)`, applies old-format files only to single-taxon points, and
reports ambiguous points loudly for re-review; (2) re-applying compounds
the reason prefix while `n_applied` says 0; (3) `.utm_crs_for()` picks the
Greenwich UTM zone for points straddling 180 degrees; (4) decision files
are `readRDS()`'d with no schema check; (5) the end-to-end geography test
passes vacuously when resolution returns NA. Confirmed as documented:
coastline/minor-islands/EPSG rule, UPS above 84 degrees, NA coordinates,
on-coastline points, the occurrence-side vs taxon-side Uncertain routing,
the LLM cache key.
**Seven fixes MERGED 2026-09-21 (`dc820c6`)**: TaxaMatch row multiplication
(highest numeric accession version wins, documented) and stale-generation
corroborator verdicts (lookup restricted to the current params_key, newest
`evaluated_at` wins -- CAVEAT: `verify_local_corroborations()` uses the
DEFAULT params key because it receives no BLAST parameters; a run evaluated
under non-default parameters reads every corroborator as "unchecked" --
conservative, but a follow-up should let the caller pass the key or derive
it from the audited run, as `.summarise_corroborators()` already does);
cache-clear containment in the shared engine (refuse cwd/home/root, refuse
mixed directories without `force = TRUE`, never follow symlinks out);
antimeridian-safe `.approx_distance_km()` replacing four inline copies;
template generator declares `data_type`, its diff test fails rather than
skips, and a new test pins every canonical-path placeholder to CONFIG/
DATAFLOW; `validate_controls()` gives all-zero columns an explicit
`no_detections` row and its distance step is vectorised (1,151-sample case
~16.5 s -> 1.3 s end-to-end, bit-identical). Tests: TaxaMatch 1,364,
TaxaTools 1,174, TaxaExpect 701, TaxaFlag 580, all zero failures. One known
gap until the next reinstall: TaxaWizard's committed-template diff test
compares against the installed library, which predates today's inst/ edits.
TaxaFetch done -- 2 DEFECTS, reproduced (branch `screen-a5-fixes-fetch`):
`check_geographic_outliers()` names its verdict cache by `sum(keys) %% 1e9`
-- not a hash; equal-sum key sets collide and the second call silently
marks every record "insufficient_global_data" (fix: `rlang::hash()` of the
sorted keys + verdict parameters, the package's existing convention, and a
guard treating a file with none of the requested ids as a miss);
`dedupe_occurrences()` crashes when a key column is absent while its docs
promise a no-op (fix: loud `stop()` naming the missing columns). 1 RISK:
iNaturalist calls have no retry/backoff on 429/5xx (fix: reuse the GBIF
retry engine). Open question for someone with API access: whether omitting
iNat's `captive`/`quality_grade` params really means "no filter".
**TaxaHabitat fixes MERGED (`9debda7`)**: decisions key on `(point_id,
taxon_name)` -- `point_id` is a coordinate id from `stack_occurrences()`
shared across taxa, so the collision was real; old-format files apply only
to single-taxon points and ambiguous ones return for review with a
warning; apply is idempotent; `.utm_crs_for()` wraps at the antimeridian
(-179.5/179.5 -> zone 60); decision files are schema-validated; the
geography test skips only when NOAA is provably unreachable. 580 tests,
0 failures. **User-facing consequence**: the next real
`apply_spatial_review_decisions()` run on the GreatLakes/PtCon/Mugu files
reports how many points are ambiguous; re-saving from the review gadget
writes the new key.
**TaxaFetch fixes MERGED (`6a0b2da`)**: verdict cache keyed on
`rlang::hash()` of the sorted species keys + `year_range`/`method`/
`min_occs`/`tdi`/`mltpl`, with a read guard treating a file sharing none of
the requested gbifIDs as a miss (note: `literature_search.R` uses its own
`.query_hash()`, so the package now has two hashing conventions -- a
1.1 tidy-up); `dedupe_occurrences()` stops naming missing key columns;
iNaturalist calls retry 429/5xx with bounded backoff honouring
`Retry-After` (new `retry_attempts`/`retry_wait` arguments, mirroring the
GBIF convention). 824 tests, 0 failures. iNat's omitted `captive`/
`quality_grade` = no filter per the API's documented behaviour; not
live-verified.
TaxaWizard done -- 1 DEFECT, reproduced, CONFIDENTIALITY (branch
`screen-a5-fixes-wizard`): the chat engine's auto-sniff
(`.detect_paths_in_text()` -> `.format_sniff_block()`, graph.R ~583) reads
ANY existing local file whose path is mentioned in chat text and injects
its first line into the prompt sent to the LLM provider -- reproduced with
`/etc/hosts` and a synthetic secret; `.rds` mentions are `readRDS()`'d with
no size cap. Fix: data-extension allow-list, working-directory scope,
never dotfiles/system paths, 1 MB cap for rds, summary-only (column names,
never content) into the prompt. 4 RISK incl. `.validate_one_call()`
SKIPPING when a package fails to load (becomes a failure code). Verified
clean: registry argument parsing (27-parameter function spot-checked live),
cache key sufficient for reinstalls, no key value ever in a prompt or
pack, `workflow_export_prompts()` cannot write outside `dir`.
TaxaLikely done (last of eight) -- 2 DEFECTS, reproduced (branch
`screen-a5-fixes-likely`): `suggest_unreferenced_species()` never checks
that `reference_species` is present for acoustic/image data, so omitting it
silently flags every LLM candidate as unreferenced (the non-eDNA branches
had zero tests); its response parsers accept any two-word string under any
genus ("Ignore priorinstructions" passed under Gadus). 1 RISK (genus column
reaches the prompt unvalidated), 1 DOC (`n_cross_genus_pairs` reports
2x the true count). `check_cross_genus_sampling_noise()`'s resampling and
`taxalikely_clear_cache()`'s patterns verified live.
**A5 first half MERGED (`24c6e5e`)**: catalogue at `inst/extra_functions_
for_review.md`; every response file has its "Added after the review" table;
conflicts with A8's pointer fixes resolved toward A5 (the passages were
deleted), two lost pointer fixes re-applied.
**Template-review tally, all eight packages: 16 reproduced defects in
post-review code, every one fixed or being fixed on a branch; plus the
ecosystem-wide cache-clear containment gap and the stalled template
generator.**
**TaxaWizard fixes MERGED (`8853188`)**: auto-sniff requires a data
extension from a single allow-list (csv/tsv/txt/tab/dat, fasta/fa/fna/fas,
rds, json -- xlsx/rdata were never parsed and are no longer detected), no
dot-segment, a location under the working directory or the session
`tempdir()`, or an explicitly quoted path outside system directories;
`.rds` is size-capped (1 MB) before `readRDS()`; only column names and
counts reach the prompt, never a content line. `.validate_one_call()` now
emits `package_unavailable` (a failure) instead of skipping an unloadable
package; `workflow_check()`'s roxygen states exactly what it checks and
where snippet validation actually lives. 1,084 pass; the one failing test
is the committed-template diff against the stale installed library.
**TaxaLikely fixes MERGED (`06c6d02`)**: `suggest_unreferenced_species()`
stops when `reference_species` is missing for acoustic/image (first tests of
those branches); LLM responses keep only species whose genus matches the
genus asked about, and family-level responses echo a `family` field that
must match; the genus column is validated before it reaches the prompt;
`n_cross_genus_pairs` counts unordered pairs; the single-genus case warns.
1,325 tests, 0 failures. **Every A5 fix branch is now in `main`**; the
16-defect tally is closed in code.
**`ECOSYSTEM_WORKFLOW.md` REWRITTEN and merged (`b5e547b`)**: 402 -> 376
lines; the TaxaExpect section now describes the kernel pipeline as the
template runs it; the TaxaAssign site/prior join describes `join_priors(
site=)`; the "Open Design Issues" changelog is gone; all 81 function
mentions verified against NAMESPACEs. The rewrite exposed a root-README
contradiction (line ~772 pointed new users to a template in the separate
`eDNA` repo; line ~797 named this repo's generated template canonical) and
a history narrative in the README's template section -- both fixed on
`main`, with two more dated passages (the Xeno-canto quality-grade helper's
archival; "there is no longer a standalone inst/ script"). The root README
was never inside an A1 package pass; it has now had the same treatment.
**Second reinstall DONE 2026-09-21** (window verified: the peer's 30-second
probe had finished; RStudio's session held no TaxaID package): nine packages
from `83a3029`, exports 217, `llm_prompts/` regenerated (`0cd1b6c`),
**TaxaWizard 1,093 pass / 0 fail / 0 skip** -- the committed-template diff
test passes against a current library. Stage A is COMPLETE except the
`.Rproj.user/` deletion (RStudio still open).
**WERC release-review response WRITTEN 2026-09-21**
(`usgs_release_review/RESPONSE_to_release_review.md`), answering every
request in the review's table with the three user decisions applied and the
test-deletion push-back kept.
**NEW FINDING (A8 follow-up, 2026-09-21): `ecosystem_docs/ECOSYSTEM_WORKFLOW.md`
is a KEPT user-facing document, but its "PRIOR PIPELINE" section still
describes the archived GLMM/grid design under a dated "Archived pathway"
banner (~line 205 on). It must be rewritten to the kernel pipeline
(`estimate_kernel_priors()` -> evidence layers -> `apply_undetected_evidence()`
-> TaxaAssign), banner removed -- an agent task, queued.

### A6. Caching and resources, for users

No new framework. One root-README section, "Caching and resources": where
`cache_dir` points by default (`tools::R_user_dir(<pkg>, "cache")`), which
caches are worth keeping across projects (the reference mislabel-detection
cache) and which are disposable (GBIF), `taxaid_cache_report(warn_gb=)`, the
`*_clear_cache()` pattern stated once, and which functions are memory-heavy
with their approximate cost (`filter_gbif_quality()` ~4 GB per million rows;
chunk). Then verify: every long-running export documents `cache_dir`; the two
known heavy functions chunk internally. **Done when** the section exists and a
Sonnet agent, given only the README, can answer "where is my cache, how big is
it, how do I clear it, what will blow my RAM" for each package.
**DONE 2026-09-20** (branch `screen-a6-caching`, `02c9012`, 74 lines before
"# Troubleshooting"). Verified facts that corrected the brief: TaxaHabitat and
TaxaFlag cache only when `cache_dir` is passed (workflows do); TaxaTools has a
fixed-path model cache, opt-in lookup caches, and a `taxatools_clear_cache()`
with no default; `taxaid_cache_report()` does not scan TaxaWizard;
`filter_gbif_quality()` does NOT chunk (documented as such). Findings routed
to A8: `harvest_dataone_catalog(cache_file = "pasta_catalog.rds")` defaults to
a RELATIVE path in the working directory (the one off-convention cache);
`generate_regional_proximity_evidence()` caches into TaxaFetch's directory
(intended sharing, document it); the Troubleshooting claim that
`blast_sequences()` takes `cache_dir` was false (fixed on the A6 branch).

### A7. Subtraction

- **Zero-caller list**: every export with no caller in TaxaID (outside its own
  package), the two workflow repos, the workflow template, or TaxaWizard's
  registry. User decides per item: keep / internalise / drop. This is the one
  pass that reverses the growth direction; do it before B.
- **Catch-all check**: exports over ~300 lines or with more than ~12 arguments
  listed for the user; splitting is allowed under the freeze-as-guide.
**Done when** the two lists exist with a user decision on each row.
**Result (2026-09-20):** 225 exports, **20 with no external caller**, 39
catch-alls. User decisions: TaxaFetch literature/DataONE screening subsystem
(`build_taxon_screen_prompt`, `parse_taxon_screening_response`,
`parse_geo_screening_response`, `screen_eml_columns`, `fetch_dataone_eml`,
`call_api_pdf`) -> `TaxaID_dev`; `build_review_covariates`,
`fetch_occurrences_by_taxon`, `drop_stale_seeded_decisions`,
`taxalikely_evict_unreachable_cache` -> `TaxaID_dev`;
`identify_confident_observations` -> un-export; TaxaTools model registry
(`list_models`, `refresh_models`, `set_model`, `model_cache_info`),
`fetch_worms_attributes`, `refine_reference_verdicts`,
`verify_local_corroborations`, `correct_training_bias`,
`audit_inat_coverage` -> keep. **No catch-all is split for 1.0**; splitting
is a 1.1 goal. **Execution refinement (2026-09-20):** "zero external caller"
is not "dead" -- four of the TaxaFetch six (`parse_geo_screening_response`,
`screen_eml_columns`, `fetch_dataone_eml`, `call_api_pdf`) are called from
other TaxaFetch files, so they are INTERNALISED (`@export` dropped,
`@keywords internal`), not removed; only `build_taxon_screen_prompt`,
`parse_taxon_screening_response` and `fetch_occurrences_by_taxon` leave the
package. Removed code is staged in the scratchpad `a7_removed/` and lands in
`TaxaID_dev/removed_functions/`. Apply the same internal-caller check before
removing `build_review_covariates`, `drop_stale_seeded_decisions` and
`taxalikely_evict_unreachable_cache`; when the last one goes, delete its
sentence from the A6 README section. The A7 CSV's test-caller column
was wrong (13 of 15 checked have tests); its external-caller column was
verified by opening files.

### A8. Claims-not-code scan

Grep user-facing prose for absolute claims ("never", "always", "cannot",
"guaranteed", "can never again") and check each against the code; the project
has repeatedly shipped comments asserting behaviour the code did not have.
Also reconcile every remaining doc against every other (the old screen
contradicted itself on pkgdown). **Include the manuscript-facing
`inst/*_supplemental_methods.md` files** (TaxaAssign, TaxaExpect, TaxaLikely):
A2 found TaxaExpect's using the retired `resident_observed` label as current
11 times; A1 never covered `inst/`. Also `inst/TaxaExpect_workflow.R`, a
self-labelled "ARCHIVED PATHWAY" script still shipped in `inst/` -> A4 move.
**Done when** each hit is either verified or rewritten.
**SCAN DONE 2026-09-21** (`scratchpad/A8_claims_scan.md`, read-only): ~85
claims opened against code -- 5 FALSE, 4 UNVERIFIABLE (need a live run:
GreatLakes/Lamar validation numbers, log-loss figures), ~76 verified.
FALSE: root README cites `taxalikely_evict_unreachable_cache()` as callable
(removed); TaxaAssign methods file says the forwarding wrapper "remains"
(removed); TaxaLikely methods file presents `identify_confident_observations()`
as public (internal); TaxaExpect methods file calls a 0-of-221 Jeffreys
quantity "about 2.3e-3" an UPPER BOUND -- 2.3e-3 is the posterior MEAN
(0.5/222, recomputed); the 95% upper bound is ~0.9%; root README Software
Inventory stale in 6 of 9 rows. 12 dead file pointers in R/inst/vignettes/
READMEs. 2 of 90 shipped `inst/` scripts call functions that no longer exist
(`TaxaAssign/inst/workflows/camera_trap_posterior_workflow.R` -> 7 archived
GLMM functions; `TaxaExpect/inst/extra_functions_review_inputs.R` -> 2
internals that never existed); 54 of 90 carry dated/session comments -- A1
never covered `inst/`, so an **inst/ sweep** is a Stage A addition. Fixes
apply on the post-merge branch.

### Merge order for the Stage A branches (decided by topology, 2026-09-20)

1. `workflow-ptcon-multisite` (`6870776`: TaxaFlag renames + call sites in
   TaxaWizard snippets, template, README) merges to `main` FIRST.
   `screen-a1-TaxaFlag` was cut from it; the TaxaWizard branches were cut from
   `main` and their `test-validate.R` fails until `6870776` lands.
2. Then, per package, `screen-a1-<pkg>` followed by `screen-a2-<pkg>` (A2
   branches were cut from their A1 branch, so each pair merges as a unit).
3. Then `screen-a6-caching`, then the A4 execution branch (moves), then A5/A8.
4. Every merge: `devtools::document()` diff must be empty and the package's
   `devtools::test()` green in a fresh R process BEFORE any reinstall; reinstall
   only when no other R session has the package loaded.

Follow-up decisions parked from A2: `TaxaWizard/inst/prompts/system_prompt.md`
is now vestigial except its "Pipeline Awareness" section (still read by
`pack.R`) -- trim or leave; `inst/taxawizard_reviewer_demo.R` carries a dated
"deprecated wrappers removed" note (inst/ was outside A1; A4 moves the demo).

### Merge record

**2026-09-21: all Stage A branches merged to `main` at `7b5b6f6`** (user
go-ahead 2026-09-20 night), in the order above; 21 merges, one conflict set
(`screen-a4-moves` vs the A1 branches, both editing the same roxygen pointer
lines -- A1's stricter text kept, `man/` regenerated). Exports 225 -> 218
(DataONE kept whole by user decision; `fetch_occurrences_by_taxon`,
`build_review_covariates`, `drop_stale_seeded_decisions`,
`taxalikely_evict_unreachable_cache`, TaxaAssign's forwarding wrapper gone;
`identify_confident_observations` and `fetch_dataone_eml` internal).
`migrate_reference_cache()` was RUN on all seven live caches first (every
congruent verdict already current; 199 non-congruent rows left to
re-evaluate; `.bak_pre_v5_amplicon_query` beside each) -- its deletion is
now unblocked. Still to do on `main` (on a branch): delete
`migrate_reference_cache()` per the checklist; the A3 follow-ups (remove
`suggest_unreferenced_species(data_type=)`'s default; 16 prose leaks; the
TaxaHabitat README line; image/acoustic examples for the generic layer);
A5; A8. Deferred until no R session holds the packages: reinstall all nine,
regenerate `llm_prompts/`, re-run TaxaWizard's `test-pack`/`test-validate`.
The workflow chat must merge `main` into `workflow-ptcon-multisite` before
further package edits; the untracked residue under `diagnostics/` and
`ecosystem_docs/readmes/` in its checkout moves to `TaxaID_dev` then.

**Verification of the merged tree (2026-09-21, fresh R per package,
`load_all`, no install):** `document()` a no-op in all nine; tests green in
eight -- TaxaTools 1,155, TaxaFetch 790, TaxaMatch 1,387, TaxaLikely 1,283,
TaxaAssign 811, TaxaExpect 693, TaxaHabitat 545, TaxaFlag 550, zero failures.
TaxaWizard 1,067 pass / 4 fail, both failing tests compare against the
INSTALLED libraries (`test-pack`: generated pack vs committed `llm_prompts/`;
`test-workflow-template`: committed template vs the generator's output) and
five installed packages are stale relative to source (TaxaFetch 32 vs 30
exports, TaxaLikely 33/31, TaxaAssign 16/15, TaxaHabitat 19/18, TaxaFlag
12/11). Re-run both after the reinstall; they are not evidence against the
merge until then.

**Reinstall DONE 2026-09-21 07:57** (window verified clear: RStudio's R
session held no TaxaID package; no other R process). All nine installed from
`b861dd7` (main after the post-merge fix branch) into
`~/Library/R/4.0/library`; exports 56/30/31/31/16/18/15/11/9 = 217.
`llm_prompts/` regenerated from that library (`d4bded6`); **TaxaWizard 1,070
pass / 0 fail** -- both library-dependent tests now green. Trap hit once and
recorded: `R --vanilla` ignores the user library, so a path lookup under
`--vanilla` returns nothing; never use it to locate installed packages.
Post-merge fix branch also landed: `migrate_reference_cache()` deleted,
`suggest_unreferenced_species(data_type=)` required (callers updated in
TaxaAssign, its vignettes and 13 tests; none external), 16 A3 rewordings,
acoustic/image examples added to `score_consensus()`, `join_priors()`,
`posterior_consensus()`, `workflow_engine()`, `sniff_input()`.

## 7. Stage B -- verification (frozen tree, at `pre-1.0-freeze`)

**Entry conditions -- all true, verified, before B1:**
1. No session other than the screen's is editing TaxaID; the workflow chat is
   on its branch.
2. All three repositories (TaxaID, `~/My Drive/Rscripts/eDNA/`,
   `~/My Drive/Stats and Data/GreatLakes data/`) clean and committed.
3. All nine packages `devtools::check()` clean and reinstalled from the tag,
   build timestamps read from the installed `DESCRIPTION`, not assumed. Never
   reinstall while another R process has the package loaded.
4. NCBI healthy (a throttled NCBI is indistinguishable from several defects).
5. Stage A closed, with every *decide* answered.

- **B1. Clean-checkout reproducibility.** Clone the tag to a fresh directory
  with a fresh `R_LIBS_USER`, install in dependency order, `devtools::test()`
  (never bare `test_dir()`) every package. Nothing may depend on state that
  exists only on the author's machine.
- **B2. Every number reproduces.** Each figure in the README, the supplemental
  methods and the manuscript traced to a run that still produces it. The
  recurring failure here is a number true when written and silently stale
  after; the 2.01M-vs-8.11M GBIF row count is the canonical case.
  **Enumeration DONE 2026-09-21** (`scratchpad/B2_numbers.md`, preserved in
  `TaxaID_dev/screen_records/`): ~51 measured numbers -- 6 class A
  (fixture-reproducible), ~30 class B (warm production run), ~8 class C
  (cold network), 7 class D (no locatable producer). Structural finding:
  most GreatLakes/PtCon validation figures exist ONLY as console output typed
  into a document -- no file on disk holds 564, 0.868, 3.659 or their kin.
  **Standing rule from here: a validation claim is written to a file by the
  run that produced it, or it is not published.** Three "Lamar precision"
  figures are three pipeline stages (0.868 kernel-only, 0.818 coverage
  floor + EB, 0.872 full pipeline) cited in three documents without saying
  so -- label each by stage. Shortest covering set of runs: GreatLakes
  consensus workflow (kernel branch, warm, outputs SAVED), the Lamar
  comparison rebuild, PtCon 12S warm, Mugu warm (user decision: all three
  sites), one deliberate cold NCBI reference fetch first, and the external
  API round trips (BOLD/DataONE/PR2/WoRMS). Decisions 2026-09-21: freeze
  NOW (tag after the user's README pass); runs launched by the coordinator
  as background Rscript with the user on call for interactive stops;
  version 1.0.0, tag `v1.0.0`.
  **Revised 2026-09-21 (user):** GreatLakes is NOT in the manuscript; **PtCon
  12S is**, and the user holds its numbers. B2's reproduction target is
  therefore PtCon 12S (one run, isolated `OUT_PREFIX`, outputs saved);
  GreatLakes and Mugu become SUBSET code-path runs under the FAST convention
  (own `OUT_PREFIX`, read-only `REUSE_PREFIX`, no checkpoint of theirs ever
  reused; content-keyed caches shared). The mislabel reference screen is
  NOT re-run in B2: its verdict cache covers only a fraction of accessions,
  so it trips NCBI limits regardless, and it changed 6 of 13,442 hits at
  PtCon -- serve it from checkpoint (`SCREENS_FROM_CHECKPOINT`) or cap it.
  **Decision: the screen is OFF by default in the workflow template**
  (`SCREEN_REFERENCE_ACCESSIONS = FALSE`), on by flag, with its yield and
  NCBI cost stated beside the flag.
  **PtCon 12S B2 run STAGED 2026-09-21** (awaiting the user's go): driver =
  `TaxaID_dev/screen_records/.../b2_runs/PtCon12S_b2_workflow.R`, a copy of
  `eDNA/PtConception/PtConceptionWorkflow_12S_single_site.R` differing in
  ONE line (`OUT_PREFIX <- "PtConMifishSchulte_b2"`); `SUBSET = FALSE`,
  `REUSE_PREFIX = NULL`, `SCREENS_FROM_CHECKPOINT = TRUE` with the three
  production screen checkpoints (match_eval, ref_eval, removal_audit; Sep
  11) copied under the b2 prefix so no BLAST runs; reference-sequence fetch
  cold once; GBIF pool re-downloaded once under hashed names; LLM steps
  warm where cached. Non-interactive stops: `apply_spatial_review_decisions()`
  runs from the saved decisions file (and will report ambiguous points),
  `review_spatial_flags()` and the `interactive()` block are skipped under
  Rscript, `on_unreviewed = "error"` at Step 8 can halt the run. Launched as
  a background Rscript against the installed library from `3909ae6`;
  outputs land as `PtConMifishSchulte_b2_*` beside the production files.
- **B3. The structural guards fire.** Break each deliberately and confirm it is
  caught: vignette-call checking, snippet/graph-edge export checking, the
  sampling-group kingdom guard, `cache_ok()` staleness inputs, `on_unreviewed
  = "error"`, `on_count_failure`.
  **DONE 2026-09-21** (`TaxaID_dev/screen_records/.../B3_guards.md`): eleven
  guards broken one at a time in a scratch worktree; **9 of 11 fired** with
  a real failure. Two gaps, both TaxaWizard tests, fixed in its B4 pass:
  the word-boundary invariant test asserted only the " ..." marker (a hard
  mid-word cut with the marker appended passed); the committed-template
  diff test carried `skip_on_cran()` and silently skipped under a bare
  `test_file()` -- the file's strongest guard as a no-op, the exact shape
  this project forbids. Rule: a guard test never `skip()`s for a reason
  that is not provable at run time; it `fail()`s with the reason.
- **B4. Per-package checklist passes 1-7** (memory `pre-code-review-package-
  checklist`) on every package, including `/security-review`.
  **Before B4 started (2026-09-21)**: the three post-screen follow-ups landed
  (`verify_local_corroborations()` reads the audited run's key; the literature
  cache's character-sum checksum is `rlang::hash()`; iNaturalist's omitted
  `captive`/`quality_grade` verified live = "any": 470,344 / 470,344 /
  434,444), plus `force=` on all five `*_clear_cache()` wrappers, the
  clear-cache tests rewritten to the containment contract, and
  `.gbif_dl_meta_path()`'s equal-sum checksum replaced by `rlang::hash()`
  (existing GBIF download entries become misses; user's disposable-cache
  decision). Real caches verified to PASS the containment check (TaxaFetch 20
  files / 2.7 GB, TaxaLikely 27,881 files). Sibling to fix in TaxaFetch's B4:
  `.gbif_checkpoint_path()` in `fetch_gbif_occurrences.R` has the same
  checksum shape. B4 runs one agent per package, two at a time, branch
  `stageb-b4-<Pkg>`; passes 1-6 executed, pass 3 report-only (no renames),
  7a light read of pre-review functions, 7b done by the A5 template review.
  **TaxaMatch DONE** (`784adcf`): `check()` 0/0/0, 1,368 tests; 61
  non-ASCII characters replaced; `@examples` added to the 10 exports that
  had none (one draft example corrected -- `evaluate_reference_accessions()`
  does not return `reference_action`); stale `.lintr` exclusions removed;
  **`Depends: R (>= 4.1.0)` added** -- the package uses the native pipe but
  declared no minimum R (check every package's DESCRIPTION for the same).
  7a: no `system()`/`eval()`/`parse()` in pre-review code; the local-BLAST
  argument string is built from numeric and literal-set values only.
  **TaxaAssign DONE** (`270337e`, `18c68f0`): `check()` 0/0/1 (timestamp
  NOTE), 811 tests; 87 non-ASCII replaced; **50 auto-extracted scratch
  files under `tests/testthat/_problems/` deleted** (called a helper that
  exists nowhere; committed by accident in an earlier lint sweep); stale
  `.lintr` exclusions for the moved `suggest_unreferenced_species` removed;
  `Depends: R (>= 4.1.0)` added by the coordinator. 7a: no I/O of its own;
  one `eval()` on a function's own default-argument expression, guarded;
  LLM prompts take free text unescaped (same shape as TaxaFlag) but both
  parsers treat the reply as typed data with fallbacks -- worst case a
  biased prior, never execution. Design note for 1.1: delimit free-text
  fields in LLM prompts consistently across TaxaAssign, TaxaFlag,
  TaxaLikely, TaxaHabitat.
  **TaxaFetch DONE** (`14fea3f`): `check()` 0/0/0 (no NOTE), 840 tests;
  `.gbif_checkpoint_path()` checksum -> `rlang::hash()` (old checkpoints
  become misses); `Depends: R (>= 4.1.0)`; tests' non-ASCII fixed; drifted
  `.lintr` lines re-verified one by one. 7a: every user-derived cache path
  hashed or sanitised; URLs `URLencode`d; DataONE downloads gated by a host
  allow-list. **One item for the pre-tag fix pass**: `.pasta_eml_url()`
  (dataone_occurrence_search.R ~626) splices `dataset_id`'s dot-split
  segments into a URL path with no character allow-list -- fixed host, so
  not SSRF, but `/` or `..` in an id changes the requested path; apply the
  `[A-Za-z0-9_-]` sanitiser used in `literature_search.R`.
  **Template default MERGED (`ae25da1`)**: `SCREEN_REFERENCE_ACCESSIONS <-
  FALSE` in the generated template, rationale in Step 1's comment (one BLAST
  round-trip per accession trips NCBI; 6 of 13,442 hits changed on a real
  12S study; run as a separate task).
  **TaxaTools DONE** (`f097ece`): `check()` 0/0/0, 1,174 tests; 94 non-ASCII
  lines fixed incl. an em-dash inside a live `message()` format string; two
  never-read variables deleted; **security fix: Gemini's API key travels in
  the request URL, and `call_api()`'s connection-error handler echoed the
  raw message (URL included) through `stop()` -- the key is now redacted
  before the error surfaces**; no key ever written to a manifest or cache.
  Online name-verifier tests ran for real and passed. Not done, by
  judgement: dated comments in `tests/` (outside A1's scope; tests ship but
  are not user-facing prose) -- decide whether a tests/ sweep is wanted.
  **TaxaLikely DONE** (`882c2cc`): `check()` 0/0/0, 1,335 tests. **It found
  a check() ERROR introduced by A7**: `identify_confident_observations()`
  became internal but its `@examples` still called it unqualified -- the
  example run failed with "could not find function"; fixed with `:::`.
  Lesson for any future internalisation: re-run the examples, not just the
  tests. Also: an `@examples` block added to `check_cross_genus_sampling_
  noise()`; drifted `.lintr` lines re-verified; 9 `object_usage_linter`
  false positives confirmed with `codetools::checkUsage()` (cli glue). 7a:
  cache filenames sanitised (`[^A-Za-z0-9]` -> `_`); no `system()`/`eval()`.
  **TaxaExpect DONE** (`2658f3c`): `check()` 0/0/0 (no NOTE), 701 tests;
  `@examples` added to the five exports that had none (all run under
  `load_all()`); `Depends: R (>= 4.1.0)`; 32 lint findings fixed. Naming
  inconsistencies REPORTED for 1.1, not fixed: `lat`/`lng` in the two
  API-facing generators vs `site_lat`/`site_lon` in the kernel math;
  `sampling_group` (a value) vs `sampling_group_col` (a column). **Process
  rule learned: never `git stash` in a shared-repo worktree** -- worktrees
  share one stash list and the agent popped the workflow chat's WIP stash
  by mistake (restored intact, verified); compare against a baseline with
  `git archive <commit> | tar -x` instead.
  **TaxaFlag DONE** (`90dcf8a`): `check()` 0/0/0 (no NOTE), 580 tests;
  8 non-ASCII fixed; dead `n_bad` removed; stale `.lintr` entry for the
  removed `build_review_covariates.R` dropped; examples run explicitly.
  7a: review cache keyed by hash with the full key re-verified on read; the
  gadget renders via `shiny::p()` (auto-escaped), never `HTML()`.
  **TaxaHabitat DONE**: `check()` 0/0/0 (no NOTE), 580 tests; the three
  roxygen link warnings fixed; `@examples` added to `save_/apply_spatial_
  review_decisions()`; a U+241F glyph used as an in-memory join delimiter
  replaced by the ASCII `\x1f` control character (behaviour verified
  identical); **`flag_habitat_inconsistencies()` now re-attaches the
  `habitat_proportions` attribute explicitly** -- a comment promised it and
  a test asserted it, but the attribute survived only because `left_join`
  happens to preserve attributes on a plain data frame. NOAA and Natural
  Earth downloads ran live and passed.
  **TaxaWizard DONE (`3909ae6`) -- B4 COMPLETE FOR ALL NINE.** 1,106 tests;
  `check()` 0 warnings / 0 notes with one ERROR that is the installed-library
  lag (the regenerated template was verified byte-identical against source
  via `load_all()`); 31 lints -> 0 (prompt-pack literals and a generated
  script line excluded with reasons); the two B3 gaps closed -- a direct
  unit test of `.truncate_at_word()` pins the word-boundary property, and
  `skip_on_cran()` is gone from the committed-template diff test. One
  curly-quote left in `test-registry.R:382` on purpose: it is the pattern
  under test. Reinstall from `3909ae6` follows; TaxaWizard's test and
  `check()` are re-run against the fresh library as the B4 closing check.
  **Third reinstall DONE (from `3909ae6`; pack regenerated `c9d42f2`):
  TaxaWizard 1,107 / 0 -- the committed-template diff test passes against a
  current library with no skip.** `check()` still shows ONE error, and it
  is the B3 fix working: under `R CMD check`'s isolated library path the
  snippet-drift test now reports `package_unavailable` for every sibling
  TaxaID package instead of silently skipping. Diagnosis-and-fix in
  progress: the honest outcome is a `skip()` only when `requireNamespace()`
  provably fails, and a run (not a skip) whenever the siblings are present.
  **B1 DONE 2026-09-21** (clone of `main` at `c9d42f2`, fresh library first
  on `R_LIBS`, all R steps confirmed resolving under it): all nine packages
  install in dependency order with zero warnings and no undeclared
  dependency; eight suites pass at baseline (TaxaTools 1174, TaxaFetch 844,
  TaxaMatch 1368, TaxaLikely 1335, TaxaExpect 701, TaxaHabitat 580,
  TaxaAssign 811, TaxaFlag 580; 0 failures); no hard-coded machine paths,
  every `system.file()` target present in the installed copies; both README
  smoke tests run to `OK` from the fresh install with only the documented
  warnings. **One real defect**: TaxaWizard 1098/9 -- `test-pack.R`'s
  "generated pack equals the committed copy, date stamp aside" fails on
  every clean install because the pack embeds `packageDescription()$Built`
  (second-precision) in the packages table and every `CONTEXT_<pkg>.md`
  header, and `.undate()` excuses only the calendar date. The committed
  pack only ever matched because it was regenerated seconds after the
  install that produced it. Decision: the Built stamp leaves the pack (a
  user-facing document carries the version, not an install wall-clock);
  fix goes on `stageb-wizard-check` with the `check()` fix below. Report:
  `TaxaID_dev/screen_records/.../B1_clean_clone.md`.
  **TaxaWizard `check()` fix (branch `stageb-wizard-check`, `c430a83`)**:
  cause confirmed -- `R CMD check` builds an isolated library from
  DESCRIPTION alone, and seven siblings were undeclared, so the drift test
  ran against a TaxaTools-only registry; and the test's skip fired only at
  ZERO installed siblings. Fix: the seven added to `Suggests`; the skip is
  now per-package and names what is missing. Verified: with siblings
  present the drift test RUNS (1107/0, SKIP 0); with only TaxaTools
  resolvable it skips provably (not fails); `check()` 0/0/0. **Built stamp
  removed** from the pack (`b8ec71a`: packages table is Package | Purpose |
  Version; each header reads "Version x. n exported function(s)."), pack
  regenerated, 1107/0 with SKIP 0, `check()` 0/0/0. **Both MERGED to main
  `c8d1e15`.** The installed TaxaWizard (3909ae6 build) is now behind main
  in `R/pack.R` only; the pre-tag reinstall covers it.
  **Pre-tag fix MERGED (`e9efe23`)**: `.pasta_eml_url()` holds each id
  segment to `[A-Za-z0-9_.-]` with no `..` (34 DataONE tests pass).
  **B3 launched** (scratch worktree, nothing committed): eleven guards each
  broken deliberately and observed -- vignette-call checks, snippet export
  validation, the placeholder-declaration and committed-template tests, the
  registry invariants, the kingdom guard, `cache_ok()` staleness,
  `on_unreviewed = "error"`, `on_count_failure`, cache-clear containment,
  the decision-file schema and ambiguity guards.
- **B5. USGS release checklist** in `usgs_release_review/` with its response.
  **Checked 2026-09-21 against the tracked tree** (every row of
  `RESPONSE_to_release_review.md` re-verified, not read): README title uses
  the colon; `code.json` present, CC0-1.0, `status` Preliminary, version
  0.1.0, `laborHours` 0, `repositoryURL` kdlafferty/TaxaID, lastModified
  2026-06-27; zero LICENSE/DISCLAIMER files inside packages, zero
  disclaimer mentions in package READMEs, one of each at the root; zero
  tracked residue (renv, roadmap, TODO, git-setup, INTRO, qmd,
  PACKAGE_SETUP, DESCRIPTION.md); ECOSYSTEM_WORKFLOW.md linked from the
  README; CLAUDE.md in all nine `.Rbuildignore`s; 174 test files (response
  corrected from 173, `f2c8e32`). **Two process facts from
  `WERC_Software_Checklist.pdf` that bear on the tag**: (1) a PROVISIONAL
  release "may not be cited or referenced by other official USGS
  Information Products (e.g., manuscripts)" -- the PtCon 12S manuscript
  cites TaxaID, so the manuscript needs the OFFICIAL release path (IPDS
  record, reserved DOI, technical code + domain review, RM and CD
  approval); (2) the official path wants a RELEASE-CANDIDATE BRANCH named
  for the version (`1.0.0`), and WERC creates the immutable tag on their
  GitLab, so the local step is "branch `1.0.0` from main" rather than
  "tag `v1.0.0`" unless the user wants both. The official DISCLAIMER and
  `code.json` `status` change only when that path completes.
  **User decisions 2026-09-21 evening**: this version is the
  PRE-SECURITY-REVIEW submission, not a release -- no tag, no version bump,
  no `1.0.0` branch from this chat; the USGS path does those later.
  `repositoryURL` = `kdlafferty/TaxaID` (README, CITATIONs and two
  TaxaWizard strings aligned, `bae1d99`). The maintainer's own README pass
  (all ten READMEs, TaxaExpect figure replaced by `PisasterTheta.png`) was
  applied from the shared checkout onto branch `readme-user-pass`
  (`f461386`); style rules for the review: no em dashes, no ` -- `, no
  bold or italics outside headings, no LLM-style prose, shorter where
  possible, typos and factual errors fixed. Verification asked for: the
  TaxaAssign wrappers `run_bayesian_pipeline()`/`run_llm_pipeline()` and
  every inst/ and production workflow after the data removals; the
  TaxaWizard README's "three ways" claims; the TaxaFlag README's focused
  controls text; the TaxaExpect pooling claim (sharpened, `c3b83bc`: exact
  invariance when every candidate of an observation is rescaled alike).
  The maintainer also asked for a SECOND LOOK at the six `*_clear_cache()`
  functions, which read as redundant in the READMEs.
  **Wrapper and workflow verification DONE 2026-09-21**: every
  `Taxa*/inst/*.R` script and the template parse, reference only existing
  files and exported functions, and call none of the removed functions;
  the six production workflows (PtCon 12S single/multi, 18S, Mugu,
  GreatLakes, California Intertidal) parse with no dead reference into the
  repository tree (two stale prose comments outside the repo recommend the
  removed `migrate_reference_cache()`; Mugu's unreachable GLMM branch calls
  a long-removed `add_pca_covariates()`). `run_llm_pipeline()` intact.
  `run_bayesian_pipeline(generate_report = TRUE)` was BROKEN: it spliced
  `score_transform` into the `generate_report()` call, which has no such
  formal. FIXED (`7172151`): the value travels as the `report_params`
  attribute, both wrappers validate `report_params` names up front, and a
  real run's Methods text now names the square-root-mismatch transform.
  Also found: the shipped fast fixtures still carried the retired
  `resident_observed` label (18S priors 1,522 rows, 12S r2 479, Mugu
  posterior 116), so the 18S and Mugu smoke tests failed under the closed
  `prior_branch` set introduced by this screen; relabelled and re-run
  (18S 813 rows, Mugu 0.3 s). Three graph snippets and the template still
  listed the label; removed. The template guard test regenerated in a
  subprocess from the INSTALLED snippets, so it could not see source
  edits; the generator now reads the repository's graph and snippets and
  a stale template provably fails the guard. The fixture README was a
  205-line dated development log shipped in `inst/`; rewritten as an
  inventory. All merged to main (`6b2e758`); TaxaAssign 815/0, TaxaWizard
  1107/0. The installed library is now behind main in TaxaAssign and
  TaxaWizard: reinstall before submission.
  **README pass COMPLETE and MERGED (`287a219`)**: all ten READMEs read
  by a second pass under the maintainer's rules (no em dashes or ` -- `,
  no bold/italics outside headings except scientific names and journal
  titles, plain prose, no chronology), every function, argument, default,
  path and link verified against NAMESPACE/`formals()`/the tree, and the
  whole-tree grep is 0/0/0 on every file. Factual errors caught and
  fixed: root (a `wi_output` reader that does not exist, a glmmTMB licence
  claim for a dependency TaxaExpect no longer has, Biostrings needed by
  `trim_to_amplicon()` too); TaxaLikely (examples calling
  `fetch_ncbi_reference_sequences(rank=)` and `compute_posterior(priors_df=)`,
  neither exists); TaxaFlag (score described as a mean of proportions; the
  code computes a depth-weighted rate ratio shrunk toward 0.5 by
  `prior_weight`); TaxaFetch (cache prompt threshold is 5 GB not 1 GB;
  overwrite prompt only with `allow_prompts = TRUE`); TaxaHabitat
  (`flag_habitat_inconsistencies()` flags, not `review_spatial_flags()`;
  `build_habitat_prompt()` needs no key); TaxaTools (Azure OpenAI provider
  omitted; `.onAttach()` auto-detect is interactive-only); TaxaWizard (the
  three routes stated as the code has them); TaxaExpect (pooling claim
  made exact; *Pisaster ochraceus*). Reports in
  `TaxaID_dev/screen_records/.../readme_pass/`. Flagged, not changed:
  `assign_scores()` bullet omits `score_type = "direct"`; `cache_ok()`,
  `assign_sampling_group()`, `fetch_worms_attributes()` unmentioned in the
  TaxaTools README; AZURE_OPENAI_API_KEY absent from the root API-key
  table; `resolve_review_overrides()`/`verify_local_corroborations()`
  unmentioned in TaxaMatch's README.
  **Coordination 2026-09-21 night**: the workflow chat has a detached
  Rscript (CalIntertidal Sections 6-7, cold NCBI fetch, ~7 h) holding the
  library until ~02:30 on 2026-09-22; NO REINSTALL before it lands. The
  shared checkout still carries the maintainer's README edits uncommitted
  on the workflow branch; proven lossless against main (seven files
  byte-identical to `f461386`, the other three differ only in the three
  conflict hunks where main's later corrections won), so they can be
  stashed (`git stash push -- README.md Taxa*/README.md`) before that
  branch next merges main. The workflow chat's untracked
  `ecosystem_docs/REENTRY_PROMPT_theta_surface_options.md` is theirs.
  **2026-09-22 decisions**: main PUSHED at `1b7f314`; cache functions =
  OPTION B (API unchanged; each package README states its
  `<pkg>_clear_cache()` in one sentence pointing at the root README's
  Caching and resources section, which is the single full description);
  every package README must list EVERY export (a grep against NAMESPACE
  found 61 unmentioned across eight packages; being added with one-line
  purposes from roxygen); merge, push and reinstall decisions sit with the
  screen session, not the workflow chat; TaxaAssign + TaxaWizard reinstall
  after the CalIntertidal run lands.
  **DONE 2026-09-22**: all nine package READMEs list every export (61
  added; the NAMESPACE-vs-README grep prints nothing for all nine);
  option B applied (one cache sentence per package, root README's Caching
  and resources holds the five-function shared signature, the engine's
  containment rule and `taxaid_cache_report()`); `assign_scores()` lists
  `score_type = "direct"`; `AZURE_OPENAI_API_KEY` in the key table;
  whole-tree style grep 0/0/0 on all ten. Reports in
  `TaxaID_dev/screen_records/.../readme_pass/complete_{A,B}.md`.
  **KNOWN DEFECT reported by the workflow chat 2026-09-22, NOT fixed in
  this screen (the maintainer assigned it its own chat)**:
  `TaxaLikely::fetch_ncbi_reference_sequences()` queries NCBI by name with
  no lineage constraint, so a homonym resolves to whichever node the
  `[ORGN]` search prefers. Live: the red alga *Vertebrata* (taxid 1261581)
  pulled 306,181 vertebrate sequences (taxid 7742, a clade), 28% of a
  1.1M-sequence COI reference set, and returned no Rhodophyta at all; 78
  genera with lineage disagreement, ~11 true homonyms (Vertebrata,
  Digenea, Grania, Contarinia, Acrotylus, Ptilophora, Mastophora, Galene,
  Lobophora, Bulla, Ctenophora, Armadillo), the rest genuine
  reclassifications that must be accepted. Rank alone is not enough
  (*Lobophora* has two genus-rank nodes); the fix needs rank AND lineage
  and probably a signature change: a 1.0 API decision. The empty result
  reads downstream as "no barcode", not "malformed query". Write-up:
  `ecosystem_docs/REENTRY_PROMPT_homonym_detection.md` (untracked, in the
  shared checkout). Same shape as the Polychaeta homonym found 2026-09-15.
  **Shared checkout refreshed 2026-09-22** (`f016809`, main merged into
  `workflow-ptcon-multisite` after the workflow chat's verified all-clear;
  tree identical to main; the maintainer's next README round happens
  there). Two stashes sit in that checkout, NEITHER the workflow chat's:
  stash@{0} = the maintainer's first-round README copies (proven lossless
  vs main); stash@{1} = this screen's own 2026-09-20 draft (510-line
  screen doc, since committed and grown to 1,129 lines on main) plus a
  one-line CLAUDE.md path that main already has in its moved form. Both
  superseded; DROPPED 2026-09-22 on the maintainer's word. Reinstall hold still on.
  **Freeze exception granted by the maintainer 2026-09-22**: the
  theta-surface thread may edit `TaxaExpect::plot_theta_surface()`
  (rendering only: `theta_range`, `palette`, `bg`, `support_panel`/`fade`,
  mask outline, and the static branch's missing colour key). Conditions
  from this screen: no new export and no change to any prior or number;
  branch off main, commit as you go, merge only through this session;
  roxygen and README free of chronology; `devtools::document()`,
  `test()` and `check()` 0/0/0 before merge; the `alpha_by_n_eff` logical
  stays accepted if `fade` supersedes it; `llm_prompts/CONTEXT_TaxaExpect.md`
  embeds the signature, so after the TaxaExpect reinstall the pack must be
  regenerated and its drift test re-run; the TaxaWizard snippet
  `std_to_priors_kernel.R` calls it with `taxon` only, so additive params
  need no snippet or template change; the README figure
  `PisasterTheta.png` was rendered with the old palette and background
  and should be re-rendered under the new defaults or its caption kept
  palette-neutral. No conflict with this screen's plans: no version bump,
  NAMESPACE or NEWS change is scheduled here (pre-security-review
  submission). Reinstall of TaxaExpect goes through the same hold.
  **Homonym fix BUILT by a separate thread 2026-09-22, branch
  `homonym-detection` (off `e01032d`, tip `24775ad`), NOT merged, NOT
  pushed.** TaxaTools gains `R/ncbi_homonyms.R` with THREE NEW EXPORTS
  (`resolve_ncbi_taxid()`, `check_lineage_agreement()`, and a 12-row data
  frame `known_ncbi_homonyms`); `fetch_ncbi_reference_sequences()` gains
  an opt-in `taxa_lineage` (NULL reproduces the old behaviour). Live
  verified: 68/68 Rhodomelaceae for *Vertebrata* with the guard. Tests
  TaxaTools 1209/0, TaxaLikely 1358/0, check 0/0. Rule 1 of the freeze
  applies: the maintainer decides the exports. Screen's recommendation:
  export the two functions (a generic mechanism the `verify_taxon_names()`
  bypass will need too), do NOT export the 12-name list (it is what one
  fetch found, will go stale, and the resolver is the mechanism; keep it
  as test fixture or vignette example). Merge conditions: Micah-template
  review + "Added after the review" entries in both review responses;
  TaxaTools README lists the new exports (completeness rule); pack
  regenerated after reinstall; merged through this session. Left
  unfixed by design: priority_taxa path unwired; `verify_taxon_names(
  backbone_id = 4)`'s own NCBI bypass has the same collision (separate
  decision). **REINSTALL DISCLOSURE**: that thread ran devtools::install()
  for TaxaTools (09:45:53 local) and TaxaLikely (10:01:27) UNDER the
  workflow chat's live 12S run (pid 73144, started 09:12:47), before it
  knew of the hold; the workflow chat has been alerted to check the run.
  The installed TaxaTools and TaxaLikely are therefore an UNMERGED branch
  build, not main; the pre-submission reinstall must rebuild all nine
  from final main regardless.
  **Consequence confirmed by the workflow chat**: its 12S run (pid 73144)
  is VOID; the packages were swapped under it at 09:45:55 and 10:01:29,
  no open handle kept the old .rdb, and evaluate_likelihoods ran through
  the swap. No error surfaced, which is the documented failure mode.
  Its output is being kept renamed `*_SUSPECT_branchbuild.rds` as a
  comparison baseline only. Plan agreed: on that chat's "run ended"
  message this session verifies no R process holds the library (ps/lsof,
  including the homonym thread's R and any rsession) and rebuilds ALL
  NINE packages from main in dependency order, verifies Built stamps and
  suites, then clears both the 12S re-run (~40 min, cache on disk) and
  the homonym thread. Second independent instance of the shared-library
  hazard in this screen; the structural fix (per-session R_LIBS_USER)
  is recorded in memory, not built.
  **Homonym fix MERGED `5ef58e6` and pushed**: the maintainer took the
  screen's recommendation; the thread un-exported the list
  (`.known_ncbi_homonyms`, test fixture and help-page example), added the
  two exports to TaxaTools' inventory and "Added after the review"
  entries to both review responses. Reviewed from a detached worktree:
  TaxaTools 1209/0, TaxaLikely 1358/0, check() 0/0 on both. TaxaTools
  now has 58 exports. The shared checkout, which that thread had switched
  to its branch, is back on `workflow-ptcon-multisite` with main merged
  (`3ae739f`), tree identical to main. Remaining from this thread, own
  decisions later: `verify_taxon_names(backbone_id = 4)` bypass; the
  priority_taxa fetch path; `audit_barcode_coverage()` and
  `suggest_unreferenced_species()` not wired to the resolver. After the
  rebuild: regenerate `llm_prompts/` (CONTEXT_TaxaTools and
  CONTEXT_TaxaLikely embed the changed signatures).
  **LIBRARY REBUILT 2026-09-22 10:38 local from main `7a1467b`**: pre-flight
  clean (no R process, no open handle, worktree clean); all nine installed
  in dependency order, Built stamps 17:38:03-17:38:26 UTC, export counts
  58/30/31/31/16/18/15/11/9; prompt pack regenerated from it and
  committed; TaxaWizard 1107/0 against the installed siblings; the three
  offline smoke tests OK from the installed copies. Both chats cleared:
  the workflow chat re-runs 12S clean (~40 min) and diffs it against the
  quarantined branch-build baseline; the homonym thread may install
  again. The void run finished NORMALLY with zero errors: the hazard is
  that a reinstall under a run does not crash it.
  **Follow-up MERGED**: `audit_barcode_coverage()`/`audit_reference_coverage()`
  had the same unguarded `res$ids[1L]` genus-taxid pick; now resolved
  through `TaxaTools::resolve_ncbi_taxid()` with lineage terms built from
  the caller's own rank columns, no new parameter, no export change;
  TaxaLikely 1371/0, check 0/0/0; reviewed from a detached worktree.
  Deliberately unwired (query volume, species-level names collide far
  less): `suggest_unreferenced_species()` per-species counts and the
  priority_taxa path. Installed TaxaLikely is now behind main by this
  internal change; reinstall at the next safe window, not urgent.
  **PROPOSAL awaiting the maintainer**: `verify_taxon_names(backbone_id = 4)`'s
  backend `.verify_via_ncbi()` overwrites `name_to_taxid[[name]]` per
  returned summary, so a name with two NCBI nodes gets whichever came
  last, silently; it sits under `escalate_taxonomic_rank()`,
  `fill_higher_ranks()` and `assign_sampling_group(harmonise = TRUE)`.
  Option 1: ambiguous name -> NA with a warning naming the candidates
  (honest gap, existing not-found paths fire). Option 2: an
  `expected_rank` hint on `verify_taxon_names()` used as the rank
  discriminator (signature change, three callers). Screen's view: 1
  now, 2 later, and the NA must be accompanied by a warning that lists
  the name and its taxids so a user can pass the right one downstream.
  **Maintainer's DECISION 2026-09-22**: neither option as proposed. An NA
  plus a warning invites a large silent failure in big batches; the user
  must CHOOSE, in one batch. Spec sent to the homonym thread: collect all
  ambiguous names with candidate taxids and lineages; interactive = one
  prompt for the whole batch with numbered candidates and an explicit
  "skip"; non-interactive = stop with the same table and instructions;
  choices are a decisions input (data frame or file, the spatial-review
  decisions convention) that `verify_taxon_names()` accepts and the
  prompt saves; "skip" is the only route to NA and is recorded; the
  three callers pass decisions through. One-argument signature addition
  accepted; any save/apply helper names to be proposed before export.
  Rulings on the thread's proposal: `decisions = NULL` (data frame or
  .rds path) approved, warned-as-unused for other backbones; the
  save/apply helpers stay INTERNAL (no new exports: a two-column data
  frame and `saveRDS()` are the API); NO default persistence location
  (a hidden decisions file is state that changes results without
  appearing in the script, the stale-cache shape again); the
  non-interactive stop prints a ready-to-paste `decisions =
  data.frame(...)` skeleton with candidates as comments; interactive
  saves only to a path the user named, else prints pasteable code; a
  new ambiguity not covered by supplied decisions is treated as
  unresolved, never guessed.
  **BUILT AND MERGED** (`verify-taxon-names-decisions`, tip `c7af511`):
  no new exports; `decisions` on the four functions; internal
  save/apply helpers; no default file; 45 offline tests; TaxaTools
  1250/0 (+1 network skip) from a detached worktree, check() 0/0/0.
  Installed TaxaTools and TaxaLikely are now behind main (this and the
  coverage-audit fix); reinstall both, then regenerate the pack
  (CONTEXT_TaxaTools embeds the four changed signatures), at the next
  window with no R process alive.
  **theta-surface-render MERGED** (maintainer approved both deviations
  2026-09-22): `plot_theta_surface()` gains `theta_range` (default
  "shared"), `palette` ("YlOrRd"), `bg` ("grey92"), `support_panel`
  (TRUE), `support_field`, mask outline and a colour key on both renders, a
  `layout(1)` reset; `alpha_by_n_eff` REMOVED (no caller anywhere;
  n_eff is scale-invariant so opacity misread extrapolation as
  confidence). TWO NEW EXPORTS approved: `as.data.frame()` method for
  the surface and `theta_surface_at()`. Landed with the screen's edits:
  one roxygen chronology line removed, review-response entries for both
  functions and the behaviour change, README section "Reading values
  off a surface" plus both in the function list (completeness grep
  clean, style 0/0/0). TaxaExpect 724/0, check 0/0/0. README figure
  kept as is by the maintainer's decision. Installed TaxaExpect now
  behind main too: the next reinstall window covers TaxaTools,
  TaxaLikely, TaxaExpect and the pack (CONTEXT_TaxaExpect embeds the
  old signature).
  **LIBRARY REBUILT AGAIN 2026-09-22 14:05 local from main `f5a01c0`**
  (maintainer quit both RStudio sessions; pre-flight clean): all nine,
  Built 21:05:33-21:05:55 UTC, TaxaExpect now 17 exports; pack
  regenerated (`c7d5846`, pushed; `alpha_by_n_eff` gone from it,
  `decisions` and `theta_surface_at` present); TaxaWizard 1107/0
  against the installed siblings; three smoke tests OK. Installed
  library == main for every package.
  **Four findings from the workflow chat's wiring of the new APIs
  (2026-09-22 evening), acted on**: (1) `check_lineage_agreement()` was
  DEFEATED by a shared root: "agrees" on any shared term, so full
  NCBI-style lineages agreed on "Eukaryota" for a red alga and a bat.
  FIXED: an `ignore` argument (roots and kingdom-level groups by
  default; `character(0)` restores the old rule) and a section stating
  that a disagreement is a review candidate, not a filter. (2)
  Family-level disagreement cannot separate a homonym from a benign
  revision (~12 of 78 on the real COI set): documented in the same
  section. (3) A homonym can present as ZERO results, invisible to any
  lineage check: `fetch_ncbi_reference_sequences()` now names the
  requested taxa that returned nothing (message + attribute
  `taxa_without_sequences`, also on the all-empty early return). (4)
  `max_per_genus` drops whole species and biases the between-species
  terms; documented, `max_per_species` preferred. The chat's own first
  wiring passed data frames and the error was swallowed by its tryCatch;
  the type error now says what to pass. TaxaTools 1260/0, TaxaLikely
  1371/0, check 0/0/0 both; merged to main. Installed TaxaTools and
  TaxaLikely are behind main by this change; reinstall after the
  workflow chat's COI run lands, then regenerate the pack.
  **CI (GitHub Actions R-CMD-check) had been RED on every push since
  `b2a27d4` (2026-09-21), TaxaWizard only; the maintainer noticed via the
  failure emails.** Cause: the checkpoint-invalidation tests added in the
  screen run a generated script whose Step 0 refused to run because
  `workflow_check(edges = )` reported Biostrings/DECIPHER as "missing"
  regardless of what the selected edges needed, and the runner has no
  Bioconductor packages (the local machine does, so `check()` passed
  here: an environment proxy). FIXED `14b2233`: an absent optional or
  Bioconductor package is "warn" unless a selected edge requires it
  (`refs_to_matrix` still reports it missing; the whole-ecosystem check
  is unchanged); test covers both directions with `requireNamespace`
  mocked. TaxaWizard 1113/0, check 0/0/0. Lesson: a green local check is
  not a green CI; read the CI result after every push. Installed
  TaxaWizard is behind main by this change (internal), same reinstall
  window as TaxaTools/TaxaLikely.
  **Root README round 2 (maintainer's edits, carried onto main and
  proofed)**: 1,253 -> 1,077 lines. Related Software 212 -> 109 (Table 1,
  Table 1b and every named function kept); Interactive Workflow Designer
  section removed and its content folded into "Which Entry Point"
  (START_HERE + CONTEXT_TaxaID paste, workflow_create(), workflow_app());
  Data Outputs compressed to one table (details live in package READMEs);
  seven Pandoc `{.underline}` spans replaced with plain text (GitHub
  renders them as literal brackets); "precision and accuracy" ->
  "precision and recall"; Table 1 caption no longer attributed to
  Orsholm et al. (it is TaxaID's own comparison; the benchmark cite stays
  in the prose); START_HERE path completed. Verified: every script in the
  Workflow Scripts table exists, parses, and calls only exported
  functions (comments in three shipped scripts named a removed function
  or the wrong package; fixed); all nine vignettes exist; both wrapper
  examples use real arguments and both wrappers ran end to end this
  screen; template guarded by its test. NOT executed: the sixteen
  per-stage workflow scripts (they need real data and keys).
  **Staleness audit of the sixteen scripts + two wrappers + template
  (2026-09-22)**: an AST walk checked every named argument of every
  TaxaID call against current `formals()`. One real stale script:
  `TaxaFetch/inst/Merge_sources_workflow.R` passed
  `create_taxon_names(taxonomy_ranks =)` and `rename_cols(df =)`, both
  renamed long ago (now `rank_system =`, `input_df =`); FIXED. All
  others: arguments valid. Last-commit dates are not evidence (most were
  touched by this screen's sweeps). Software Inventory counts were stale
  (TaxaTools 56 -> 58 exports, 27 -> 29 tests; TaxaLikely 30 -> 31 tests;
  TaxaExpect 16 -> 17 exports); corrected, and a TaxaWizard test now
  compares the table with NAMESPACE and tests/ so drift fails CI (proved:
  a wrong count fails). "white lists" -> "regional species lists". The
  execution of the sixteen scripts with real data and keys is a separate
  chat: `TaxaID_dev/ecosystem_docs/REENTRY_PROMPT_workflow_scripts_verification.md`.
  **README rounds carried 2026-09-22 evening**: TaxaExpect README
  (maintainer's edits + the introduction folded into Overview and a new
  Assumptions subsection "Occurrence records are informative but
  biased"; `bb35355`); TaxaAssign README second round (`3e8f3ab`); the
  root README working copy in the shared checkout proved to contain ZERO
  edits beyond round 2 (diff against `8814f23` empty), so its fifteen
  three-way conflicts were all round-2 processing versus the old base
  and resolved to main. All three of the maintainer's patch sets are
  saved in `TaxaID_dev/screen_records/.../readme_pass/maintainer_*.patch`.
  Shared checkout refreshed: `6a26c36`, tree identical to main. Rule
  learned: refresh the shared checkout to main BEFORE the maintainer
  starts a round, not after; an editing base behind main turns every
  later round into a three-way merge.
  **Workflow-scripts verification chat, first report (2026-09-22 night)**:
  three script bugs fixed on its branch and merged (`c4e8601`: an
  undefined `.best_thresh`, an undefined `match_df`, `read_birdnet_output()`
  given a table instead of a path). Six package-level findings, acted on
  here (`1c03f4d`, then `site-priors-guard`): (1) a single-taxon habitat
  request comes back headerless from the model 3/3 times and parsed as
  zero rows; the parser now supplies the header from the prompt's layout
  when the field count matches. (2) `infer_exclude_predicted()` did not
  recognise `composite_id`, the accession column its own upstream
  writes; added. (3) `join_priors()` with a site that matches no prior
  rows: `run_bayesian_pipeline()` died in a bare vapply, and
  `join_priors()` itself completed SILENTLY with every candidate at the
  floor prior; both paths now stop with the grid ids / habitats the
  priors hold. (4) `generate_priors_workflow.R` is named by the tutorial
  chain but was never built: asked the chat to build it. (5) the FASTQ
  tutorial ran live DADA2 and an unconditional Bioconductor install on
  source; Step 0 is now opt-in (`RUN_DADA2`) with a guarded install.
  (6) the merge workflow saved its output INSIDE the installed TaxaFetch
  library; now beside the project. Lesson from this session's own slip:
  a commit chain must GATE on the test result; one merge went to main
  with two failing tests and was repaired within minutes, but CI is the
  backstop, not the check. Installed TaxaHabitat, TaxaAssign, TaxaLikely
  behind main by these fixes; reinstall at the next window.
  **Tutorial chain COMPLETE 2026-09-23**: `TaxaExpect/inst/workflows/
  generate_priors_workflow.R` built and merged (`42514b2`); the TaxaFetch
  tutorial fetch widened from genus *Gadus* to *Gadus* + *Pollachius*
  (totalRecords checked first; family Gadidae rejected at ~92k) so the
  chain fetch -> assign_habitat -> generate_priors -> compute_posteriors
  runs end to end on real data (85 records, 85/85 Marine, 3 kernel + 1
  undetected prior rows, bandwidth calibration with real separation,
  7 Bayesian + 12 LLM posterior rows); merged `75c3b8d`. Root README's
  "Build priors" row points at the script. All run from source via
  `load_all()` because the library rebuild waits on the CalIntertidal
  chat's COI run.
  **Workflow-scripts verification FINAL (2026-09-23)**: all sixteen
  README-listed scripts, two predecessor tutorials and the new
  generate_priors script were RUN with real data and keys; 19 of 20 ran
  to completion (three after script fixes: `.best_thresh`, `match_df`
  and `real_model` undefined in the TaxaAssign Bayesian tutorial and the
  sequence-likelihood tutorial, and BirdNET ingestion given a table not a
  path). The one not run to completion: `2_flag_errors_workflow.R`,
  stopped deliberately after 2 of 7 NCBI chunks with no errors (real
  NCBI volume); acceptable, its code path was exercised. Report with
  per-row evidence: `TaxaID_dev/screen_records/prepublication_screen_2026-09-20/
  workflow_scripts_run.md` (f6273a9). The reentry prompt's own
  predecessor claim for image_acoustic_likelihood_workflow.R was wrong
  (real predecessors are score_image/score_acoustic).
  **Large-reference-set crash FIXED (`62dcd97`)**, reported by the
  workflow chat from a real COI run (915,832 sequences, 153M-pair
  matrix): `.has_seq_matrix_presence()` used every accession of a taxon
  as an R variable name in the align_cache, and `.check_regional_overlap()`
  used the whole query sequence; R caps names at 10,000 bytes, so ~900
  accessions per taxon halted `restore_suppressed_candidates()` after
  minutes of alignment. Keys are now `rlang::hash()` of the material
  (rlang added to TaxaLikely Imports; TaxaTools already uses it), same
  semantics, bounded; test with 2,000 accessions and a 20 kb sequence.
  Latent on small projects, fatal on large ones. The "expanded path
  length 1024" warning in the same run is not from TaxaLikely (its only
  `file.exists()` calls take real paths); source unidentified. Installed
  TaxaLikely behind main by this fix; reinstall at the next window.
  **Tracked, NOT built (1.1 candidate, the maintainer's scope call)**:
  an adaptive `max_per_genus` for `fetch_ncbi_reference_sequences()` /
  `build_sequence_matrix()`. Today the cap is manual with no sizing
  help; guessing it cost two failed COI runs (one kernel-panicked a
  36 GB Mac). A workflow-only prototype lives in
  `eDNA/CaliforniaIntertidal/CaliforniaIntertidalWorkflow_multi_marker.R`
  (~1886-1950): available-memory probe (free+inactive+speculative+
  purgeable via vm_stat, macOS only), a pair-count memory predictor
  (`sum(n(n-1)/2 + FOREIGN*n) * K * BYTES_PER_PAIR`), binary search on the
  genus cap against a budget fraction. Weaknesses to carry with any
  port: K = 2.2545 fitted from ONE build; PEAK = 2.5 is a lower bound
  inferred from a crash; the memory probe is macOS-only; predictions are
  an order-of-magnitude guide. A third calibration point
  (`attr(seq_matrix, "size_calibration")`) is being captured by the COI
  run; port after it lands, as a new export, so not in this submission.
  **Maintainer's decision 2026-09-24: `max_per_genus` defaults to 500**
  (`976639d`); NULL disables. Consequences documented in the roxygen:
  a capped genus can lose whole species; a value different from the one
  a cache was built under is a cache miss, so EVERY existing reference
  cache built under the old NULL default is refetched once on its next
  call unless the caller passes `max_per_genus = NULL` (PtCon, GreatLakes
  and Mugu production workflows included: check whether they pass it);
  `max_per_species` is the gentler lever. The cache tests' seeded entries
  had hard-coded the old default as "the function's defaults"; they now
  read `formals()`.
  Correction from the workflow chat: CalIntertidal passes
  `max_per_genus = NULL` explicitly (it caps post-fetch on purpose, so a
  cap can never invalidate a cached fetch), so its cache survives by
  matching NULL, not 500. TRAP recorded: every explicit `NULL` written
  for clarity is now load-bearing; deleting one flips the call to 500
  and refetches (~21 h of COI there). Roxygen now says so.
  **Maintainer 2026-09-24**: users must be warned about the memory vs
  missed-species tradeoff and given the numbers to decide; the pre-run
  estimate is NOT a dead end (the fetch already holds per-taxon NCBI
  counts before downloading, and memory scales with the square of
  sequences per genus). Spun off to its own chat:
  `TaxaID_dev/ecosystem_docs/REENTRY_PROMPT_reference_memory_estimate.md`
  (dry-run report from the fetch, a stop in build_sequence_matrix() when
  the prediction exceeds available memory, calibration with the third
  point, documented tradeoff, and a numbers-backed default decision).
  Production workflows and the B2 driver now pass max_per_genus = NULL
  explicitly (eDNA d95761d, GreatLakes 5457ebc, TaxaID_dev 6f3adea).
  **LIBRARY REBUILT 2026-09-24 14:56 local from main `61688b4`** after the
  COI run landed (23 h 31 m, 0 errors) and the maintainer quit RStudio;
  pre-flight clean; all nine, Built 21:56:06-21:56:30 UTC; pack
  regenerated; TaxaWizard suite and the four offline smoke tests pass
  from the installed copies. Installed library == main code.
  **LIBRARY REBUILT 2026-09-26 05:34 local from main `0bfbcf9`** once the
  CalIntertidal run_s7b (23 h 56 m, 0 errors), the optimize-matrix runs and
  the counts benchmark had all exited; pre-flight clean; all nine, Built
  12:34:13-12:34:34 UTC; pack regenerated; TaxaWizard suite and the four
  smoke tests pass from the installed copies. Incident: this session's
  main worktree in the scratchpad lost its `.git` link and 796 tracked
  files overnight (cause unknown; nothing uncommitted, main == origin);
  restored from the index. Lesson: the scratchpad worktree is
  recoverable only because everything is pushed; never leave unpushed
  work in it overnight.
  **Pair-retention MERGED (fast-forward to `f019972`, 2026-09-25)** from
  the "optimize likelihood matrix" chat: `build_sequence_matrix(
  pair_retention = c("all", "best_per_partner", "best_per_class"),
  min_pair_coverage = 0.8)`, old behaviour the default; coverage via a
  blocked matrix product (identical values, 36x faster); a train-side
  floor-mismatch warning; no new export; review-response entry present;
  reviewed detached: TaxaLikely 1421/0, check 0/0/0; training output
  verified identical under every policy on real 12S and 18S matrices by
  that chat. Installed TaxaLikely behind main again; next window.
- **B6. Licensing and provenance:** CC0 throughout, `code.json` status matching
  the release type, DISCLAIMER matching provisional vs official.
  **Checked 2026-09-21 (read-only):** `License: CC0` in all nine
  DESCRIPTIONs; one `LICENSE.md` and one `DISCLAIMER.md` at the root, none
  inside packages; `Depends: R (>= 4.1.0)` in all nine. **At the tag,
  four fields change together and need the user**: `code.json` `version`
  0.1.0 -> 1.0.0 and `date.lastModified` (2026-06-27 today); `code.json`
  `status` "Preliminary" and `DISCLAIMER.md`'s "preliminary or provisional"
  text -> the USGS approved-release wording IF the WERC review is signed off
  by then, else both stay provisional (they must agree with each other);
  `code.json` `laborHours` is 0 (USGS asks for an estimate); `code.json`
  `repositoryURL` must match the repository the release is published from
  (see the remote check). All nine `DESCRIPTION` `Version:` -> 1.0.0.

## 8. Findings to carry into the manuscript (not to fix)

- The Axis-1 `expected`/`unexpected` boundary is
  `median(taxaexpect_priors$theta_mean)` of the table being classified, so it
  **floats with the data** (11.7x shift at GreatLakes from refreshing evidence
  rows alone). Report the threshold with any `unexpected` count.
- `prior_branch` names the generator, not the evidence: within the kernel
  branch `effective_records` spans ~10 orders of magnitude (44.9% of PtCon 12S
  rows under one Kish effective record). No default gate.
- **The pipeline is deterministic**: byte-identical consensus across two full
  GreatLakes runs despite 1,000-draw Monte Carlo and no `set.seed()`, because
  the consensus reads `posterior_point_est`. State this in Methods.
- Kish `n_eff` is scale-invariant; down-weighting a group buys no uncertainty
  discount.
- **A workflow written after a package split can silently inherit the old
  behaviour the split warned about** (reported by the workflow chat,
  2026-09-21): the PtCon multi-site occurrence pool never called
  `dedupe_occurrences()`, so it counted reports rather than detection
  occasions -- 21,652,448 rows collapse to 947,674; Kish n_eff at one site
  falls from 8,428,948 to 231,127; the inflation over distinct points from
  191x to 6.6x; one coordinate had filed 263,385 rows. Every published
  pool-size or n_eff figure must state whether it is occasions or reports.
- **A workflow override discarded the reasoning a default carried** (same
  chat, 2026-09-21): the pool build passed `threshold = 0.5` to
  `assign_habitat_biological()` against its own roxygen warning; 15 habitat
  generalists -- every one a land-sea or fresh-salt boundary species, the
  wrong 15 for an intertidal study -- became unassignable. Restoring the
  documented 0.3 took Uncertain points from 13,207 to 0. A methods section
  should state every non-default argument a workflow passes.
- A test failing for a month is evidence, not furniture (the CoordinateCleaner
  `cc_zero(buffer=)` unit change made a null-island check a no-op for weeks
  while labelled "environmental").

## 9. Method notes

- Discovery on Sonnet, adjudication on the expensive model; a spend limit
  killed seven expensive agents mid-flight on 2026-09-13.
- Subagents in scratchpad worktrees commit as they go; the scratchpad dies
  with the session.
- Check the thing, not a proxy: open files rather than counting grep hits;
  read the installed build rather than the diff; `git log -L` rather than the
  current file. Ten defects in two days had the proxy shape.
- A chat's finding about another chat's work is itself a claim; verify it
  before propagating it (the "column never renamed" claim lived two sessions
  and produced dead code).

## 10. Execution plan

| order | pass | model | parallel with | needs user first |
|---|---|---|---|---|
| 0 | CLAUDE.md freeze block + memory entry; workflow chat to a branch | -- (this session) | -- | DONE 2026-09-20 |
| 1 | A7 zero-caller + catch-all lists | Sonnet x1 | A1, A3, A4 | -- |
| 1 | A1 metadiscourse (9 packages) | Sonnet x9, one per package, own branch each | A7, A3 | -- |
| 1 | A3 signal-neutrality table | Sonnet x1 | A1, A7 | -- |
| 1 | A4 hygiene inventory (no moves yet) | Sonnet x1 | all | -- |
| 2 | A2 legacy deletion | Sonnet x1 after A1 merges | A5 | `migrate_reference_cache()` decision |
| 2 | A5 catalogue + Micah template + response sections | Sonnet x9 + adjudication | A2, A6 | 3 WERC items |
| 2 | A6 README caching section | Sonnet x1 | A5 | -- |
| 3 | A4 moves, A8 claims scan | Sonnet x2 | -- | A7 decisions |
| 4 | tag `pre-1.0-freeze` | -- | -- | declare freeze |
| 5 | B1-B6 | Sonnet per package, adjudicated | -- | entry conditions |

Wave 1 is safe against the live workflow chat: none of it touches `TaxaFlag`,
`TaxaHabitat` code, only their roxygen -- and A1's TaxaFlag/TaxaHabitat agents
should wait until that chat's uncommitted edits are on its branch.

## 11. Definition of done

A written statement that Stage B ran against `pre-1.0-freeze` (and names the
commit of every post-tag package re-run), against named commits in the two
workflow repositories, with NCBI healthy, and found nothing material. Anything
less is a status report, not a pass. This document then leaves the repo with
the rest of the dev material.
