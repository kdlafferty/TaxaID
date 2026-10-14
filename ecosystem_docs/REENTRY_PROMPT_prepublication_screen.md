# Pre-publication screen for TaxaID 1.0

**Status: OPEN. Re-baselined 2026-10-11 against `main` at `7a3d13f`; the
export surface was then pruned (section 12), so `main` is now at `b31f188` and
the ecosystem has 223 exports, not 232.** The
2026-10-04 to 2026-10-08 run log (the old sections 7c to 7o, 1,154 lines of merge
ledgers and resolved investigations) moved to
`ARCHIVE_screen_run_log_2026_10.md`; git has every earlier version. The screen
itself -- the passes, the board, the freeze protocol, the definition of done --
is unchanged and still open. Numbers below were measured on 2026-09-20 against
`162de62` unless a line says otherwise, so treat any count as a baseline to
re-measure, not as current state.

**What this screen is FOR, stated once.** It is not internal polish. TaxaID is
public but **not a citable object**; the citable object will be the USGS software
release, and that release requires migration to code.usgs.gov, an IPDS record, a
reserved DOI, an administrative security review, a **technical code review** and a
**domain review** (`reference_usgs_werc_release_process` in memory;
`usgs_release_review/`). The technical criteria -- readable and organised code,
roxygen describing every input and output, all tests passing locally, no
vulnerabilities -- are what Stage B's passes 1 to 7 measure. So the screen is the
pre-submission package for the reviewed version, and an item is worth doing when
a reviewer would ask about it.

**Before starting any pass, read `RULES_OF_ENGAGEMENT_agents.md`** (19
constraints: the shared repository, installing and running R, what may change
under the freeze, how to report). The generated `llm_prompts/CONTEXT_*.md` carry
the current API surface; this document carries the state. Those three are what a
session needs, and none substitutes for another.

**The board's real shape, measured 2026-10-11, because it decides what can
move.** 82 live rows: **48 wait on the maintainer**, 15 on another session, 9 on a
mechanical step (a reinstall, a rebuild, submission), 5 elsewhere, and 5 that were
already closed in their own text have been moved to the archive. Nearly three in
five open items are a decision, not work -- which is why running more passes does
not close this gate, and why a triage pass over section 0 with the maintainer is
the highest-value thing anyone can do to it.

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

**Pass 6, check and test: DONE, all nine, 2026-09-29 morning.** Every package
0 errors; the single warning each is the CRAN incoming feasibility one; notes 0
to 2. Tests: TaxaFlag 925, TaxaFetch 866, TaxaTools 1237, TaxaExpect 763,
TaxaLikely 1531, TaxaAssign 864, TaxaMatch 1423, TaxaWizard 1154, TaxaHabitat
585, zero failures once the one finding below was fixed. Full record in
`TaxaID_dev/screen_records/prepublication_screen_2026-09-20/stageb_pass6_checks.md`.

**THE ONE FINDING, and it was a review miss of mine.** TaxaWizard failed the
guard that checks the root README's Software Inventory against the tree:
TaxaTools' row said 29 test files and the tree held 30. The extra file arrived
with the taxonomy-lookup cache the night before; I verified tests and check on
that merge and did not re-check the inventory. The guard caught what the
reviewer did not, which is the guard working, and the row is corrected. Worth
keeping because it is the second time a test-file count has drifted in two days:
the first was mine too, when an append created a new test file and I caught it
before committing.

**The gate that wasted a night, recorded so it is not repeated.** The first
runner gated each check on 6 GB of AVAILABLE memory. This 36 GB machine sat at
3.4 to 3.6 GB available all night with a large `blastn` resident and swap FLAT
at 0.22 GB, which is a big working set under no pressure. Four packages were
skipped for nothing. Swap is the pressure signal; available memory is not a
budget. Corrected to available above 2.5 GB and swap below 0.6 GB, and the whole
run then finished in 25 minutes alongside the live screen. A guard that is wrong
toward "no" is silent, so confirm a new one LETS WORK THROUGH before trusting it
overnight.

## 0. Open items board (live rows only; last edit 2026-10-11)

Five rows closed in their own text were moved to
`ARCHIVE_screen_run_log_2026_10.md` on 2026-10-11. Every row kept here is
still waiting on someone, named in its own last column.

| Item | State | Waiting on |
|---|---|---|
| THE DECOMPOSITION: each marker fails DIFFERENTLY, and genus comes from sequence while species comes from priors | The best result in this whole sequence and it belongs in the MANUSCRIPT, not a review response. Species-call failures decomposed by likelihood ratio, trace row and local record: 18S is a SEQUENCE RESOLUTION problem (76 of 83 fail the likelihood-ratio test, NONE fails on reference coverage), so no reference work fixes it and the calls should be coarser; 12S is mostly an ABUNDANCE problem (70 of 126 on trace rows, no record failures at all); COI is a REFERENCE COVERAGE problem (33 with good support but no local record, which is where candidates for genuine new records live, a discovery story rather than a defect). One count could not have distinguished those, which is why decomposing it mattered. THE CONTINUOUS MEASURE SUPERSEDES THE FLAG: with the baseline fixed as I proposed (named candidates flattened to their mean prior, generic rows left at theirs), `prior_decided` still reads TRUE for 83 of 83 on 18S and 122 of 126 on 12S, so the binary carries almost no information and TRAINS PEOPLE TO IGNORE IT, the same failure as the test suite that fails in every combined run. `likelihood_support`, the reported taxon's share of the baseline, does all the work continuously: species-call medians 0.56 (12S), 0.18 (18S), 0.77 (COI), against GENUS-call medians of 1.00 on all three. RECOMMENDED: keep `likelihood_support`, drop or demote `prior_decided`. THE STRONGEST CONCLUSION AVAILABLE, and the maintainer's to take: on 18S not one species call exceeds 0.5 support and 92 percent fail the likelihood ratio, two measurements agreeing from different directions that 18S species calls are prior assertions rather than sequence findings, so 18S should probably not report species at all, or only with the support value attached. The one-line summary of the pipeline is that it resolves GENERA from sequence and SPECIES from priors, which is more useful than any single accuracy figure. I ALSO RETRACT my concern that the rank leak had inflated saved outputs by an unmeasured amount: measured at 1 of 5,918 (COI), 0 of 9,369 (12S) and 3 of 1,562 (18S), it is negligible, and the reason is an accident worth recording, that the generic-row deletion defect we spent days fixing also protected the saved outputs, since there was nothing to leak. PROCESS NOTE: the branch tip moved four times during one exchange, so I need a tip declared FROZEN to verify for merge, or verification is always of something superseded | RESOLVED 2026-10-12: both likelihood_support figures correct for different runs; report the median WITH the narrowed subset |
| THE AUDIT I ASKED FOR FOUND A BUG IN PRODUCTION, and one number outranks the rest | Asking what the new species calls were MADE OF, rather than accepting the count, found a defect rather than a trade-off. All 90 "new" `credible_node` species calls (18S 48, COI 42) were artefacts: every one had no local record and a likelihood ratio under 1.5, and NONE was clean. Cause: an unsequenced-congener row is named at GENUS but still carried its anchor's SPECIES value in the species column (a "Garveia" row with species "Garveia sp. CC-2005" at posterior 0.934), so any rank-wise sum credited its mass to that species. Fixed at source, `f9462e2`: `.extract_rank_values()` masks values at ranks finer than the row's own rank. Verified by me on a merge: TaxaLikely 1,584 and TaxaAssign 992, no failures. THE LEAK WAS IN PRODUCTION, NOT ONLY IN THE NEW RULE: 18S `lca` species calls go 84 to 83 after the fix, so the DEFAULT rule's `consensus_posterior` was inflated for species calls, and the saved 09-27 outputs carry that inflation by an amount nobody has measured. CREDIBLE_NODE LOOKS BETTER AFTER THE FIX: zero new species calls on any marker, gains entirely at coarser ranks each holding at least 0.9 of total posterior, unresolved falling 285 to 210 (18S) and 311 to 181 (COI). Converting "unresolved" into "family at 0.9" is real information rather than manufactured resolution. THE NUMBER THAT OUTRANKS ALL OF IT: of the KEPT species calls, common to both rules, CLEAN (LR at least 1.5, not trace, has a local record) is 3 of 83 on 18S, 26 of 126 on 12S and 22 of 81 on COI. Under 5 percent on one marker and about a quarter on the others, independent of consensus rule. NOT TO BE QUOTED BEFORE DECOMPOSITION, since "clean" is a conjunction: failing only "has a record" may be a genuine new record and a discovery, failing LR means the sequence does not support the call, and a trace row is an abundance problem. Asked for which condition fails, in what combination, per marker. AND `prior_decided` IS UNINFORMATIVE HERE, WHICH IS MY FAULT: I made the flag a precondition and warned that a uniform baseline over a variable-size candidate set is not neutral, but did not see that it makes the column USELESS rather than merely biased, since flattening every prior lets the ever-present generic rows win almost always and everything reads prior-decided. THE FIX follows from the flag's purpose: flatten priors among SPECIFIC CANDIDATES ONLY, holding generic rows at their actual priors, so the flag means "the prior chose between named species" rather than "the complement would have won under a flat prior", which is trivially true and is the complement's entire job | CLOSED 2026-10-12: the fix (`f9462e2`, .extract_rank_values masking finer ranks) is verified IN MAIN |
| VERIFIED, HELD: `rank-accuracy` @ `f9462e2`, the approved option 1 plus three modelling steps and a rank-leak fix | Verified by me on a merge INCLUDING the CI check that chat had not run: TaxaLikely 1,584 tests and 0 errors / 1 warning / 1 note, TaxaAssign 989 tests and 0 errors / 1 warning / 0 notes, both warnings the standing CRAN-incoming one, no new exports. CONTENTS: `unnamed_in_threshold = TRUE` so unnamed mass counts in the denominator plus an `unnamed_mass` column; a MEASURED H2 gap and `q_identical` mixture for identical-barcode congeners; OUTER RINGS at every rank above family, group-equal-weighted and nested, priced at order and class scope, with the anchor now required to carry a genus; and `consensus_method = "credible_node"` as an opt-in alternative to `lca`. ON THE TWO DEFAULTS, so they do not read as arbitrary beside my `pool_tail` advice: the separating principle is not "does it change calls" but "is it a CORRECTNESS FIX or a REFINEMENT". Ignoring unnamed mass in a denominator makes the number mean something other than what it says, so that fix defaults ON; choosing a different consensus rule is a modelling preference with a measured trade, so it stays OPT-IN; `pool_tail` was a refinement. ONE ASK BEFORE `credible_node` IS ADOPTED, and it is the question the grain test taught: species calls rise 84 to 132 (18S) and 81 to 123 (COI) with unresolved falling, but more resolution is not better by itself, since the ESV-by-site test produced 545 species calls of which only 119 survived scrutiny. The instrument that was missing then now exists, so report how many of the NEW calls are `prior_decided`, on trace rows, or have a winner with no local record. A number moving in the hoped-for direction is not evidence until you know what it is made of, which is precisely how a week of calibration work went wrong. A MEMORY CEILING nobody had stated: COI training peak rises 21.4 to 24.0 GB on a 36 GB machine where a `blastn` against `core_nt` is separately measured at about 14 GB, so 24 plus 14 EXCEEDS the machine and COI training can no longer coexist with a local BLAST, where before it just about could. A scheduling constraint, not a defect, but the swap-keyed guard catching it means killing something. THIRD PLACEHOLDER-NAME DEFECT in this sequence (after the coarse prior rows and the `unk_family` scopes): a blank-genus "Eukaryota" hit was anchoring every ring and NA-naming them. A general guard is overdue, that nothing be selected as anchor, scope or label without a real name at the rank in use | CLOSED 2026-10-11: verified already in `main` (ancestry checked against `02eadbc`) |
| REVERSAL: the contamination produced the whole constant-versus-linear finding, and the lesson outranks it | `review-blockers` @ `4e748d6` and `calib-constant-default` @ `0cd94ad`, verified by me on a combined merge: TaxaLikely 1,562 and TaxaAssign 969, no failures, no new exports. Hold maintained. ON THE CLEAN CONFIDENT SET THE CONSTANT FORM BEATS LINEAR EVERYWHERE (18S Illumina 0.046 against 0.064; COI Illumina 0.109 against 0.117; COI Nanopore 0.079 against 0.080; 12S constant-only), and the negative COI slope was an ARTEFACT of the contamination. So the maintainer's decision, taken for one method and one Methods sentence, turns out to be the empirically best one too, and "chosen for simplicity and later confirmed by measurement" is the sentence to write. Also: 18S placeholder calls 74 to 0, and arm-c species calls rise (12S 126 to 149, 18S 89 to 134, COI to 105). THE METHODOLOGICAL LESSON, which indicts how both this session and that chat worked and belongs in the manuscript findings: a bound was proposed on a correlation that was definitional; I said so; the spread measurement overturned the bound; I objected that leave-one-out was near in-sample and was corrected on the sample size; family-block cross-validation then supported the negative slope and a reference-count control ruled out the obvious confound. Every test agreed with the others, each was more careful than the last, and ALL WERE WRONG, because they shared an input nobody had audited. No amount of better inference would have found it; the review found it by auditing the DATA GOING IN. Five rounds of increasingly sophisticated statistics converged confidently on an artefact. NEW ISSUE, raised by that chat and made WORSE by something I verified: a catch-all row with no real ancestor ends up `taxon_name` NA, and `posterior_consensus` excludes NA-named rows from the cumulative threshold, so its mass is ignored (18S_ESV_001744 calls a genus at 0.53 with 0.47 on the unnamed row; 33 18S calls sit below 0.5). THE COVERAGE DIAGNOSTIC WE AGREED CANNOT SEE IT: `named_all <- chunk[!is.na(chunk$taxon_name), ]` runs first and `tail_mass` derives from `named_all`, so it measures sub-floor mass among NAMED rows only. Both the defect and the diagnostic's blind spot come from one line, and the B1 fix moves mass from "named after a placeholder", wrong and visible, to "unnamed", wrong and INVISIBLE. Remedy: include unnamed rows in the denominator for both the threshold and `tail_mass`, or report `unnamed_mass` separately; the 33 calls are the test set either way | DECIDED 2026-10-12: the CLAIM is withdrawn, the method kept. Docs fixed at `456be1f` |
| INDEPENDENT STATISTICAL REVIEW: four blocking findings, hold MAINTAINED on all three branches | Commissioned by the maintainer before approving anything, computed on real CalIntertidal data. I VERIFIED ONE IN CODE rather than relaying it. B2 CONFIRMED and real: in `posterior_consensus.R`, a generic row qualifies for the taxonomy fill if ANY ONE of its rank columns is NA (`rowSums(is.na(...)) > 0`), and then EVERY rank column is overwritten from the lookup, including ranks that were already correct and including with NA where the lookup resolved nothing. So one missing rank destroys the ranks that were present, which is what drives `consensus_posterior` toward 0. TWO QUALIFICATIONS THAT BOUND IT, which the finding does not state: it applies only to `unreferenced_species` and `unreferenced_genus` rows, not to named candidates, and it is gated behind `lookup_missing_taxonomy`, which DEFAULTS TO FALSE. So the blast radius is generic rows in runs that opted into the lookup, which CalIntertidal does. THE FINDING THAT CHANGES WHAT THE MAINTAINER IS BEING ASKED TO DECIDE is F1: the `calibrate_query_noise()` confident set is contaminated, 72 percent of 18S rows and 60 percent of COI rows not confident, which moves the constant offset (COI -0.221 against -0.069) and UNDERCUTS THE CONSTANT-VERSUS-LINEAR EVIDENCE. Every held-out RMSE number I weighed, including the 9 and 20 percent COI cost of choosing constant, was computed on that set. So the calibration-form decision must NOT be made on those numbers. Note also that this is the SECOND independent contamination of the same object, after the row-counting defect that counted one species once per site, so the confident set has now been wrong in two unrelated ways and every calibration figure derived from it is suspect. B1 is a vacuous-test finding of the kind this screen keeps producing: placeholder ranks such as "unk_family" are treated as real scopes, 78 rows in 18S and 3 in COI gain mass and 74 18S calls go to "unk_family", and the unit test passes ONLY because its fixture contains no local species with that label. B3 bears directly on a check I ASKED FOR and then treated as meaningful: synonyms (*Eisenia arborea* against *Ecklonia arborea*) count as unreferenced relatives and the backbone check is said to report 0 by construction; I have NOT independently confirmed that and flag it as unverified by me. Non-blocking: identical-barcode congeners unrepresentable, the H2/H3 gap feature a hard-coded guess, `combine_multisite_priors` ignoring absence at other sites, `pool_tail` not being a credible set | CLOSED 2026-10-12: B1 and B2 fixed at `4e748d6`; F1 decided (the claim withdrawn, `456be1f`); B3 confirmed as a limitation and documented, 0 same-family synonym candidates among the 410 |
| MERGE LEDGER REBUILT 2026-10-01: ONE candidate, zero conflicts. `support-rule-docs` WITHDRAWN by its author | The row this replaces planned two merges in order with one keep-both conflict. That plan is void. (1) `support-rule-docs` @ `5bbac38` is NO LONGER A CANDIDATE: its author and the maintainer agreed to REMOVE the `min_likelihood_support` rule entirely, keeping the `likelihood_support` COLUMN as a reported diagnostic. The reasoning, which is the part worth keeping: a prior legitimately concentrating mass in a low-diversity local clade is CORRECT INFERENCE, so a rule that penalised it was suppressing a right answer rather than catching a wrong one. REPLACEMENT ARRIVED, FROZEN: `no-support-rule` @ `b1f1a51`, two commits on `5bbac38` -- `29db376` deletes `min_likelihood_support` outright with no deprecation path and takes the lineage-climbing loop with it (no call is moved by sequence support under any rule; `likelihood_support` and `prior_role` stay as reported columns, and the roxygen now says why), and `b1f1a51` adds the TaxaAssign review-response entry under its own dated heading. Verified by me rather than taken on trust: it CONTAINS `rank-accuracy`, `support-rule`, `support-rule-docs`, `prior-decided` and `measured-rings` (all confirmed ancestors), so the ledger is exactly TWO candidates and none of those five merges separately; NO NAMESPACE change anywhere in the nine, so no new exports and no approval needed; `min_likelihood_support` survives only as one line in `taxaassign_review_response.md`, which is allowed to keep history. ONE GAP ITS AUTHOR DID NOT SEE, which I fix on the merge: it adds a new test FILE (`TaxaAssign/tests/testthat/test-placeholder_ranks.R`) and does not touch the root README, so the inventory would read TaxaAssign 16/18 against a tree of 16/19 and the TaxaWizard guard would fail the merge on a file the author never touched -- the same shape as the drift the guard caught on the taxonomy-lookup merge that I had missed. My verification now RECOMPUTES all nine inventory rows from the tree (exports from each NAMESPACE, test files from each tests/testthat) and rewrites any that disagree, so the table is derived rather than transcribed and a drift in any other row surfaces too. I verified the removal is FREE: `min_likelihood_support` appears ZERO times on main across all nine packages (R, Rd, md) and zero times in both live workflow trees, existing only on `support-rule` and `support-rule-docs` in `TaxaAssign/R/posterior_consensus.R` plus its man page and test file. So nothing on main and no production workflow passes it, no deprecation path is needed, and the lineage-climbing loop it gated should be deleted with it or given an explicit new exit condition. (2) `calib-constant-default` @ `0cd94ad` IS THE SOLE HELD CANDIDATE and now stands alone: two commits (`f9127d1` the constant default, `0cd94ad` the confident-set fix), 7 TaxaLikely files, NO NAMESPACE change, no mention of `likelihood_support` anywhere, and NOT a descendant of `support-rule` or `support-rule-docs` (checked with merge-base, both NO). The withdrawal therefore ELIMINATED the only conflict I was holding: verified with a three-way merge preview against merge-base `eb844fd` -- zero conflict markers, clean merge. Its review-response entry is the standard to copy, because it names the marker where the chosen method is WORSE and quantifies it (COI held-out 0.198 against 0.181 Illumina, 0.159 against 0.127 Nanopore, slope intervals excluding zero) and says plainly that constant-everywhere is a choice of one method over a marker-specific gain, not a finding that constant won. THE HABIT THIS EPISODE EARNS: a merge candidate can be withdrawn by a DESIGN decision taken elsewhere, so a verified merge is not a durable one -- re-confirm the ledger from git and from the authors before merging, never from a previous board row. SEQUENCING RISK TO WATCH: the promised replacement will likely append to `TaxaLikely/inst/taxalikely_review_response.md`, the same file and the same insertion point `calib-constant-default` appends to, so merge the calibration branch FIRST or expect that conflict again; the cheap fix remains a dated heading per entry rather than a shared end-of-file insertion point  VERIFIED AS A MERGE, 2026-10-01, and the result is clean: `calib-constant-default` merged clean (7 files), `no-support-rule` conflicted in exactly the predicted place (`taxalikely_review_response.md`, 3 marker lines, resolved keep-both), and the RESULT of both in one tree gives TaxaAssign 1,015 passed / 0 failed (1 skip), TaxaLikely 1,590 / 0, TaxaWizard 1,155 / 0, with CI-equivalent `rcmdcheck(args = c("--no-manual","--as-cran"), build_args = "--no-manual")` at 0 errors / 1 warning / 0 notes on both changed packages, the warning being the standing CRAN-incoming one. THE INVENTORY GUARD EARNED ITS KEEP: it caught TaxaAssign at README 16/18 against a tree of 16/19 and corrected it -- the drift the branch author did not know he had created by adding a test file. Recomputing all nine rows from the tree rather than editing the one number I already knew about is what made that automatic. | CLOSED 2026-10-11: verified already in `main` (ancestry checked against `02eadbc`) |
| VERIFIED AND READY, no approval needed: `fix-refine-unevaluated` @ `909be70`, the split bug fix | The destructive defect from `clade-resolvable-rank`, split out at my request so it does not wait on a design debate: `refine_reference_verdicts()` was refining accessions the screen NEVER EVALUATED, from stale pair-cache rows, producing "remove" verdicts with no evidence -- 159 of them on CalIntertidal 18S. A correction inside an existing function, so the freeze needs no approval for it: 3 files, no NAMESPACE, no man pages, nothing from the design work, inventory unchanged. TWO GUARDS: an accession is refined only when it was evaluated (`hierarchy_flag` non-NA), and a pair row votes only when it was cast under the same `params_key`. I PUSHED BACK ON THE SECOND and the author's measurement, not my argument, is what settled it: the first version let an UNKEYED pair row vote, including on a removal, which treats unverifiable provenance as acceptable; the asymmetry is that ignoring a good row costs one unrefined verdict (visible as `trust_refined` FALSE) while trusting a stale one costs an evidence-free removal. The author then counted the real cache -- 0 NA keys in 317,795 rows, because the writer stamps every row -- so strictness costs NOTHING and the change was free. KEEP THE HABIT: the cheapest way to settle a proposed stricter rule is a count against the real data, not a discussion. THE TESTS ASSERT ABSENCE, which is what this defect class requires: a never-evaluated accession with stale rows that WOULD vote remove gets no verdict, and the assertion sweeps the whole output for a stray "remove" rather than checking one row; plus rows under a different key, and a keyed verdict with unkeyed rows. VERIFIED BY ME ON THE MERGE at both tips: clean merge, inventory matching, TaxaMatch 1,430 / 0 at `3ef0cee` and 1,434 / 0 at `909be70`, CI 0 errors / 1 warning / 0 notes -- including the `rcmdcheck` the author had not re-run for the guard | CLOSED 2026-10-11: verified already in `main` (ancestry checked against `02eadbc`) |
| RELEASE GATE FOUND IN THE CI WARNING WE HAD ALL BEEN CALLING ENVIRONMENTAL: three real bad URLs, one in every README | Every branch this screen reports CI as "0 errors / 1 warning", the warning being CRAN incoming feasibility, and every session (mine included) has waved it through as environmental because an unreleased package genuinely does trip "dependencies not in mainstream repositories". Part of it is NOT environmental. I probed all 62 distinct URLs across the root README and all nine package READMEs, and R CMD check's own text confirms the same three: (1) `https://doi.org/10.5066/xxxxxx` returns 404 and sits in ALL TEN READMEs -- a placeholder USGS DOI, presumably a deliberate release-time step, and the one that would embarrass us if it shipped; (2) `https://claude.ai/code` returns 403 and sits in all NINE package READMEs -- tool-attribution boilerplate that has leaked into release artefacts, and the single URL the check names by itself; (3) `https://insectapp.las.iastate.edu` in TaxaMatch's README fails, and here I CORRECT MY OWN READING: I called it probably dead from a bare connection failure, but the check reports the actual cause -- `libcurl error code 60`, an EXPIRED SSL CERTIFICATE, with "Status without verification: OK". The host is alive; its certificate lapsed. The failure mode and the remedy are different, and a status code alone could not tell them apart -- read the error, not the exit status. FOUR MORE 403s (a PNAS Nexus DOI, a PeerJ preprint, openalex settings, platform.openai.com) are publisher and vendor bot-blocking and resolve fine for a human: not defects. NOT FIXED BY ME: the attribution line is in nine existing files, so it needs the maintainer's word rather than a sweep, and whether the placeholder DOI is a tracked release step or a now-fix is his call | LARGELY CLOSED: placeholder DOI fixed at `7a3d13f`, verified in main. Residual: one third-party host with an expired cert -- keep the link or drop it |
| LINEAGE BACKBONE AUDIT: the answer was NOT the backbone, and the maintainer approved sequencing the cheap fix first | Commissioned to decide where class and order come from for the 5-rank model. Measured, GBIF against NCBI(+genus fallback), on the 09-27 posteriors with ONLY class/order swapped per row: backbone choice moves a few HUNDRED calls (18S favours NCBI, +147 net, class coverage 82.7% against 66.6%; COI a tie; 12S n=31, trivial), and most "different taxon" rows are NOMENCLATURAL VARIANTS (Peronosporea/Peronosporomycetes, Sessilia/Balanomorpha) rather than disagreements -- the genuine difference is 21 sculpins, GBIF Scorpaeniformes against NCBI Perciformes, where NCBI tracks current usage as it did for Urolophus/Urobatis. THE REAL FINDING, from asking what the failures were MADE OF rather than accepting the count: 1,383 18S (25%) and 4,430 COI (34%) observations get NO CALL UNDER EITHER BACKBONE, because their candidates span >= 2 classes (90% / 97%) or >= 2 phyla, and the rank system STOPS AT CLASS so `credible_node` has no node to return. AND AN NA CONSENSUS IS NOT MERELY UNRESOLVED -- IT IS DROPPED: `regenerate_report_tables.R:26,51`, `gbif_edna_gradient.R:40` and `report_tables.R:469,511` all filter `!is.na(consensus_taxon)`, so a quarter to a third of observations leave the dataset silently and a reader of the species table cannot tell they existed. Third independent instance of the NA-dropped-by-export pattern. So raising the ceiling converts SILENT DISAPPEARANCE into an honest coarse call: a correctness change, not presentation. MY OWN FRAMING WAS WRONG AND WAS CORRECTED BY THE AUDIT SESSION, verified by me in the workflow source: I said completing the 2026-07-30 NCBI decision was the compliant path, but CalIntertidal is a LATER DELIBERATE EXCEPTION -- lines 120-127 document MATCH_BACKBONE_ID as unused in Section 8, Step 1.5 harmonises onto GBIF, and PRIOR_BACKBONE_ID = 11 carries "Fixed at the user's direction 2026-09-27" plus "IF NCBI-NAMED OUTPUT IS WANTED, DO IT AS A FINAL RELABEL, NOT HERE". DECIDED BY THE MAINTAINER: sequence the levers -- build the generic missing-rank rule and raise the ceiling to kingdom/phylum FIRST, then RE-MEASURE the backbone gap on the same backbone-neutral population, then decide the backbone; CalIntertidal stays GBIF meanwhile. The reasoning is that the generic rule is needed under EITHER backbone, is backbone-independent so no decision can invalidate it, and removes the only argument for migrating: a row lacking class aggregates at order or phylum instead of producing nothing, so the gap becomes how COARSE some calls are rather than how many are lost. THREE TEST REQUIREMENTS I ATTACHED TO THE SPEC, to be exercised rather than implemented silently: rank-less rows stay in the DENOMINATOR (excluding them inflates every node's support by exactly the mass dropped -- the `named_all`/`tail_mass` defect again); nodes keyed by (rank, name) with each row contributing to every ancestor it actually has, so the ragged case where one row has order without class and another class without order needs no global skip; and a stamp distinguishing THRESHOLD-limited from BACKBONE-limited coarseness, because "the mass is spread" and "this backbone has no class here" are different claims a reader cannot otherwise tell apart. STILL OPEN with the maintainer: whether the unreferenced RINGS extend to phylum. If consensus can aggregate coarser than `train_likelihood_model()` can hypothesise, a query whose best fit is an unsequenced class of a phylum has no hypothesis to land on -- node problem fixed, hypothesis gap created one ring out. Cost estimate requested. If the rings do not extend, the write-up must say so | the maintainer: the rings question. Then the branch comes to me |
| MEASURED, AND IT REACHES A CONCLUSION WE HAVE ALREADY STATED: most 18S TRAINING references do not contain the region the ESVs cover | Reported by `region_matched_references`, measured on 3,000-reference random samples from each marker's own `reference_df` placed against the study's ESVs (8-mer candidates, then overlap alignment, homology tested against a reversed-sequence null that separates cleanly from real scores). Among references ALREADY IN the training `seq_matrix`, the share with NO homology to the ESV region or covering under 80% of it: COI 384 of 2,891 (13%), 12S 680 of 1,939 (35%), 18S 2,047 of 2,809 (73%) -- most 18S training references are V4 deposits or partial genes that do not contain V9 AT ALL. Pairs between two such references are scored over their mutual overlap, which is a DIFFERENT STRETCH OF GENE from the one the queries see. THIS CORRECTS ME: I had argued the training defect was variance rather than location -- the trained spread too TIGHT because two long references share a longer span than the ESVs -- and that `DistanceMatrix(includeTerminalGaps = FALSE)` therefore kept it from being a mislocation. That reasoning is COI-SHAPED and I generalised it; for 12S and 35% of its references, and for 18S and 73%, it is mislocation as well. The opposite loss is real too: COI references over 1 kb and 12S mitogenomes are 90-98% PLACEABLE yet sit outside the matrix today because the length window DROPS rather than trims. WHY IT MATTERS BEYOND THE TRIMMER, and this is the part to put to the maintainer: he has concluded -- correctly on the evidence then -- that 18S is generally poor at discriminating species, that this is DISCERNIBLE FROM THE LIKELIHOOD MODEL as many plausible candidates, and that species calls therefore rest on the prior. If 73% of the 18S training set describes a different region, then some unknown part of that measured poor discrimination is an ARTEFACT OF TRAINING rather than a property of V9. Not a refutation -- V9 is genuinely short and conserved -- but the two causes are confounded today and only one is fixable. The clean test is the one already proposed for the calibration offset, run per marker: does region-matched training improve 18S species discrimination, and does the required calibration offset shrink? Note also that `min_observed_sigma`/`calibrate_sigma` (merged 2026-10-02) and the 'constant offset for every marker' decision (2026-09-30) were both fitted against the CURRENT training set, so both should be re-measured after any region-matching change rather than carried over. ONE METHOD POINT WORTH KEEPING: an identity floor is the WRONG placement test. COI references sit at ~80% identity to their nearest ESV at the median, matching `score_original`'s own median of 79%, so a floor at `1 - max_dist` would discard genuinely homologous references. The homology null is the right instrument. Reverse-complement deposits are under 1% | the maintainer: whether 18S's species-discrimination conclusion should be held open until region-matched training is measured |
| VERIFIED 1.0 DEFECT, reported by a peer and confirmed by me: COI-Leray reference screening compares the WRONG REGION | `.trim_queries_to_amplicon()` gates on `widths > max_bp`, and `resolve_barcode_lengths("COI-Leray")$max_bp` is 900, so a typical 658 bp FOLMER record is never trimmed. I confirmed both directly: the registered max is 900, and a 658 bp sequence comes back the same length. Consequence: `evaluate_reference_accessions(barcode_term = "COI-Leray")` BLASTs whole-Folmer queries while the ESVs are the ~313 bp Leray insert, so the percent identities describe a DIFFERENT REGION than the data being screened -- the same shape as the old MiFish 92/92 miscalibration. Reporter's measurement, relayed: 65,898 core_nt COI deposits, untrimmed median 616 bp; anchoring on mlCOIintF (<= 3 mismatches, either strand) and taking the insert to the reverse site or 313 bp gives a 313 bp median, matching the ESVs. SECOND HALF, which is why trimming also fails when it IS attempted: the reverse primer site is present in only ~3% of records against 92.5% for the forward, because Folmer records end at or before it with the primer stripped -- so primer-PAIR extraction failed on 4 of 4 over-length records. ONE CORRECTION TO THE REPORT: the registered reverse primer is dgHCO2198 (`TAAACTTCAGGGTGACCAAARAAYCA`, degenerate), NOT jgHCO2198 -- jgHCO2198 was deliberately rejected when this marker was registered because it uses inosine, which `Biostrings::DNAString` cannot represent. The SITE argument is unaffected (same site, both versions), but the name matters for anyone chasing it. THE DEFECT IS NARROWNESS, not a wrong value: the gate asks "is this longer than the marker's longest plausible record" when the question is "is this longer than the TARGET AMPLICON" (`amplicon_range` is registered as 350-370 for Leray). A fix therefore has two parts and the second is a real design call, not a one-liner: trim whenever a sequence exceeds the amplicon range rather than `max_bp`, AND decide what to do when the reverse site is absent -- anchor on the forward primer alone and take a fixed insert length, which is what the reporter's prototype does and what the 313 bp median supports. NOT BUILT, NOT PROPOSED AS CODE: it changes trimming for every COI caller and the screen's identities with it. Worked around in `CalIntertidal/accession_screen/build_pool_COI.R` (`leray_trim()`); the package is untouched. THE FIX'S REACH IS NOW MEASURED, on all 65,898 COI pool deposits, and it decides how the proposal should be written: the mlCOIintF site is on the GIVEN strand in 60,638 (92.0%), on the REVERSE COMPLEMENT only in 238 (0.36%), and on NEITHER in 5,022 (7.6%). So (a) assuming one orientation would lose 0.36% and the reverse-complement search is one extra `vmatchPattern` over the misses -- keep it; (b) the mismatch tolerance needed is <= 3 on a 26 bp primer, a rate of 0.115, which sits INSIDE the function's existing `max_mismatch_rate` default of 0.15, so the fix needs no new parameter; and (c) 7.6% OF RECORDS CANNOT BE ANCHORED AT ALL. That last number is the one the report did not draw out and the one I would not let pass silently: under any fix those 5,022 records stay untrimmed, exactly as today, so the fix does NOT make the screen uniform -- it makes 92% of it comparable and leaves 7.6% comparing a different region, indistinguishably from the trimmed majority unless the outcome is STAMPED per record. Absence of an anchor is not evidence that a record is already the right amplicon. So if this is built, the deliverable is trimming PLUS a per-record column saying anchored / reverse-complement-anchored / not anchorable, and the screen's identities read beside it INVESTIGATED FURTHER AND THE SHAPE CHANGED, twice. (1) The untrimmed share is 28,690 of 65,898 (43.5%), NOT 7.6%: besides the 5,022 with no anchor, 23,688 HAVE the forward site but end less than 250 bp after it (partial 500-600 bp Folmer deposits), and only 2,646 are full-length untrimmed (divergent primer sites -- Mollusca 649, Chordata 358, Cnidaria 299). The bias is large and real: untrimmed share runs Rhodophyta 6%, Chordata 20%, Mollusca 21%, Arthropoda 25%, Porifera 31%, Platyhelminthes 47%, CHLOROPHYTA 88%. (2) MY SILENT-WRONG-REGION CONCERN DOES NOT APPLY TO THE REPORTER'S SCREEN, because their prototype gates it: `query_ok` admits trimmed records only, and as subjects a 313 bp query needs >= 80% self-coverage so a partial deposit is never hit. The effect there is LOST COVERAGE, not a hidden mismatch -- 1,480 of 14,832 in-scope references untested, concentrated by phylum, and visible in the coverage columns. THE PACKAGE HAS NO SUCH GATE, which is the decision: I checked, and `evaluate_reference_accessions()` caps query LENGTH only (`max_query_len`, over-length becoming `not_evaluated_oversized`), so a 658 bp Folmer record is submitted as a query over the whole Folmer region. The reporter's screen is safe because of a gate they wrote; any other caller of the package is not. AND A CORRECTION TO MY OWN ASK: the per-record stamp I asked for ALREADY EXISTS -- `query_trim_path` (`as_deposited` / `primer_match` / `feature_table`) with `query_len_submitted` beside it, added 2026-09-01. So a fix EXTENDS that vocabulary (reverse-complement, short-after-anchor) rather than adding a column, and every cached row and consumer already carries the field | the maintainer: fix in the package for 1.0 -- trim against the amplicon range, keep the reverse-complement search, extend `query_trim_path` -- or document the limitation and leave the workflow-side workaround? |
| ACCESSION-SCREEN REMOVAL RULE: decided by the maintainer 2026-10-01, and MY OWN COST ARGUMENT WAS BACKWARDS | Decisions, from the maintainer's own messages in the screening session (my two questions to him were already stale -- he had answered both in one bundle): the test runs at species/genus/family rank, a SINGLE 5% Bayesian FDR with NO stricter removal tier, the two-pass robustness rule for `d` is ADOPTED (output records `selected_pass1`/`selected_pass2`), and "inspect" rather than remove when a removal would leave a species with fewer than 2 references. I HAD THE ASYMMETRY BACKWARDS and told the screening session so before it built on my advice: I argued a false removal costs more than a false retention and floated a stricter FDR for removals. The maintainer's position is the reverse, on domain grounds -- the cost of a false positive is LOW against the cost of a false negative -- and he has the measurement to support it: retraining with up to 200 correct references removed moved pooled parameters by under ~3%. In his terms it is obvious: a wrongly removed reference costs one deposit among several and the species is still callable through the others, while a wrongly RETAINED mislabel manufactures wrong species calls for every matching query, silently, for as long as it sits in the database -- the 159-verdict defect pointed the other way. MY ERROR WAS TREATING "DESTRUCTIVE" AS A SYNONYM FOR "EXPENSIVE": a removal is destructive and cheap; a retained mislabel is non-destructive and expensive. Carry that distinction, because it inverts the conservative instinct on every gate in this screen. REACH CORRECTED, and the 8.2% figure I put in the manuscript column is SUPERSEDED: that was the species-only prototype. Running at the finest testable of species/genus/family, with the nearest other group from a direct broad local BLAST instead of the censored pair cache, 12S is 2,883 of 7,280 testable (39.6%) -- species 1,111, genus 900, family 872. The claim is "5% FDR among testable references (39.6% of 12S)". AND THE COVERAGE GRADIENT IS REAL, NOT ABSENT: Spearman(family size, testable fraction) = 0.35, so testability rises with how well-sequenced a family is and removals concentrate in larger families. That is the measurement I asked for after the first evenness check tested only the two best-covered classes; 0.35 is moderate rather than negligible and belongs in the claim beside the 39.6%, not in a footnote. GUARD RULE: MY RECOMMENDATION WAS TESTED AGAINST GROUND TRUTH AND FAILED, which is the most useful thing that happened here. I argued >= 2 independent batches (against the session's >= 3) straight from the cost ordering: diverting a removal to "inspect" RETAINS a reference, and a retained mislabel is the expensive error, so the guard should be permissive. The session then MEASURED it on the final 12S run. Diversions: >= 2 diverts 24 references (Misgurnus 12, Enchelycore 5, Carassius 3, Pseudorasbora 2, Rhinichthys osculus 2), >= 3 diverts 20, >= 4 diverts 17. Genuineness, from the share of ALL a group's deposit batches closer to the nearest group than to their own: Enchelycore 7 of 10 (a genuine conflict), but Pseudorasbora 0 of 17 -- AND PSEUDORASBORA-TO-CARP IS THE KNOWN MISLABEL, the one piece of ground truth available. So >= 2 diverts a confirmed mislabel, i.e. retains it, i.e. commits exactly the error the cost ordering says is expensive. MY ARGUMENT WAS WRONG BECAUSE A COST ORDERING TELLS YOU WHICH DIRECTION TO ERR, NOT WHERE THE LINE GOES, and I treated a direction as a location. Carry that: a defensible principle with no contact with ground truth produces a confident wrong answer, which is the same shape as the five-round calibration saga. THE SESSION'S REPLACEMENT IS BETTER THAN ANY COUNT and is what I would put to the maintainer: divert only when the GROUP ITSELF IS SPLIT (most of its deposit batches look like the nearest group, as Enchelycore does) and REMOVE the coherent-minority cases (Misgurnus 0 of 51, Carassius 0 of 30, Rhinichthys 1 of 16, Pseudorasbora 0 of 17), where a small dissenting set disagrees with a coherent group -- the mislabel shape. That is a SHAPE test using the group's own distribution as its control, not a tuned constant, which is why it generalises where a count does not. The data cannot separate a cryptic lineage from a replicated mislabel, and under the cost ordering removing both is correct. TWO CAVEATS I ASKED FOR: (a) the share needs a MINIMUM DENOMINATOR -- a group with 2 deposit batches reads 50% split on n = 2 and would be diverted on noise -- with the below-minimum behaviour stated as REMOVE, since abstaining commits the expensive error; (b) the rule is CONSISTENT WITH the only two adjudicated cases, not validated on them (n = 2), and must not be written up as validation. I also asked for the 18S prediction to be PRE-REGISTERED before that run finishes, so the rule gets one genuinely out-of-sample test instead of being fitted to both datasets. DONE, and verified from disk rather than from its author's description: eDNA repo `CaliforniaIntertidal/accession_screen/PREREGISTRATION_split_group_guard_18S.md` (`5416e67`, stage correction `0dcec58`, addendum `0653581`). Four predictions: a 9-30% diversion band (failing in BOTH directions, after I pointed out that ">9%" would be satisfied by 60%); four polyphyletic protist genera NAMED IN ADVANCE (Gymnodinium, Gyrodinium, Navicula, Nitzschia); metazoans mostly coherent-minority; species-rank testability below 12S's 15%. I confirmed every existing 18S artefact predates the commit by a day and no pair-search or test output exists -- but ALSO found `pool.rds` and `neighbours.rds` already on disk, so prediction 4 is graded as made without consulting an answer that PARTLY existed (I had claimed the answer was simply sitting there; its author corrected me, rightly -- the neighbour file is only an UPPER bound, since testability also needs pair-search batch counts and the separation guard). The timestamps corroborate rather than merely fail to contradict: `neighbours.rds` is 15 seconds older than the commit, too little time to read it and shape four predictions. ONE GRADING RULE THAT MAKES THE STRONGEST PREDICTION GRADEABLE instead of arguable, and it is the absence-versus-ineligibility distinction again: each named genus is reported as no candidate / not eligible (<5 deposit batches, below which the guard does not apply and the candidate is REMOVED) / diverted / coherent-minority, and only an ELIGIBLE genus coming back coherent counts against the prediction -- otherwise a thinly-deposited genus the rule never ran on would read as a failed prediction. Branch `reference-mislabel-test` @ `4731566`, NOT yet submitted to me; 18S still running | the maintainer: the conflict-guard counting rule. Then the branch comes to me |
| FOUND BY LISTING BRANCHES, NOT SUBMITTED: `clade-resolvable-rank` @ `6af4073` adds an export and is NOT done | Nobody sent this to me; I found it in the branch list, which is the reason the freeze says new functions are found by `git log pre-1.0-freeze..main` and not by announcement. TaxaMatch only, 3 commits (per-clade judging rank for reference-label votes; cap ties at distinct culprit taxa; hierarchical shrinkage plus never refine an unevaluated accession), 7 files, and `+export(estimate_resolvable_rank)` in NAMESPACE -- which would move the inventory from TaxaMatch 31 exports / 22 test files to 32 / 23, so the root README Software Inventory moves too and the TaxaWizard `test-pack.R` guard would fail a merge that forgot it. ZERO file overlap with the held calibration branch, so holding costs nothing. STATUS FROM ITS AUTHOR, asked directly: still moving, and the export is UNAPPROVED. The maintainer approved the APPROACH ("the estimator and the check sounds good", "this is going in 1.0", "put it in the package") but not this export by name, and approach approval is not export approval -- "put it in the package" does not say exported or internal, and under the removal redesign now in progress (removal to require positive statistical evidence that a sequence came from another species, with FDR control) `estimate_resolvable_rank()` may become an INTERNAL helper needing no approval at all. So I am deliberately NOT putting it to the maintainer yet: asking for a yes/no on an export that may not exist after the redesign spends his attention twice. ONE REAL BUG FIX IS TRAPPED ON THIS BRANCH and is independent of the design: `refine_reference_verdicts()` was refining accessions the screen NEVER EVALUATED, from stale pair-cache rows, producing "remove" verdicts with no evidence -- 159 such cases on CalIntertidal 18S. That is a destructive wrong answer reachable today by anyone re-running the screen against a warm cache, not a missing feature, so I asked for it SPLIT into its own branch with its regression test, no new export: a correction inside an existing function needs no approval under the freeze and should not wait on a policy debate. The test must assert the ABSENCE -- an unevaluated accession must receive no verdict even when a stale pair-cache row exists -- because a test that only confirms surviving verdicts are still correct cannot catch a defect of something APPEARING that should not. FLAGGED FORWARD for when the redesign lands: FDR-controlled removal changes what a cached verdict MEANS, so the cache key must encode the rule or a warm cache will serve old-policy verdicts under the new policy, which is the same defect class as the bug just fixed | DECIDED 2026-10-11: NOT 1.0 -- revisit after the release |
| VERIFIED, HELD: `prior-decided` @ `0db7383`, and `measured-rings` @ `03d349f` | Both verified on a combined merge: TaxaLikely 1,560 and TaxaAssign 974, no failures, no new exports on either. TaxaWizard shows 4 failures but they are IDENTICAL on main under the same ordering, and the count tracks how many siblings are `load_all`'d (2 with two, 4 with three), so that suite is unusable as a signal in a combined run and the skip-guard matters more than I first said. MY VARIANCE DIRECTION HELD FOR ONE MARKER OF THREE: pooled to family-weighted H3 sd goes 0.113 to 0.109 (12S), 0.149 to 0.114 (18S) and 0.066 to 0.078 (COI), so COI behaved as I predicted and 18S did the opposite; my "well-studied families have narrower spread" was an empirical assumption asserted as though structural. BUT THE FIX IS NOT DIRECTION-FREE and that belongs in the roxygen: 18S's sd falls 24 percent, which SHARPENS H3 there, so a high-identity match is explained less well by H3, H1 wins more easily and 18S species calls become somewhat more confident, on the marker where the complement already matters most. THE PRIOR-DECIDED FLAG: `posterior_consensus(likelihood_consensus = TRUE)` re-runs consensus on normalised likelihoods and adds four columns (`likelihood_consensus_taxon`/`_rank`, `prior_role`, `prior_decided`), changing no existing output, with a test asserting identical results on and off, and unverifiable nesting reading "changed" so it flags rather than clears. DEFAULT TRUE IS RIGHT, and the criterion matters so it is not mistaken for inconsistency with my `pool_tail` advice: a PURE ADDITION can default on because it changes nothing for anyone, while `pool_tail` changed calls and so warranted opt-in. REAL DATA vindicates the flag more strongly than expected: 22.9, 32.7 and 38.4 percent of species calls are prior-decided, and MANY AT POSTERIOR NEAR ONE, with *Oligocottus snyderi* resolving to *Oligocottus* and *Crassadoma gigantea* to Pectinidae on likelihood alone. A call at 1.0 the sequence resolves only to genus is indistinguishable in every existing column from one the sequence resolved itself. CAVEAT FOR THE ROXYGEN: "likelihood-only" is really UNIFORM-PRIOR, and uniform over a candidate set is not neutral because the set's SIZE varies by observation, so an observation with many candidates looks more prior-decided than one with few, independent of the prior's actual influence. AND ONE NUMBER PROMOTED OUT OF A FOOTNOTE: re-running reproduces the saved 09-27 calls at 0.995, 0.997 and 0.976, which is the FIRST real-data measurement of what everything merged since then changed, 2.4 percent of 18S calls being the largest | CLOSED 2026-10-11: verified already in `main` (ancestry checked against `02eadbc`) |
| VERIFIED, HELD: `measured-rings` @ `c1ce9d6`, H3 measured instead of heuristic | `train_likelihood_model()` measures H3 from actual confamilial pairs (best match to another genus in the same family, family-equal-weighted) instead of H2 plus 2.0 transform units, with `shift = max(H2 shift, mu - confamilial mean)` keeping the rings NESTED so H3 can never sit closer than H2, and a fallback to the old rule below three contributing families. Verified by me on the merge: TaxaLikely 1,560 passing, no failures, NO export change, four files. Real data, implied H3 mean identity old against measured: 12S 83.3 to 91.8, 18S 85.8 to 95.5, COI 74.6 to 86.8, so H3 becomes MORE competitive and calls coarsen where a family is under-sequenced, which is the intended correction. MY CENSORING CONCERN WAS MEASURED RATHER THAN ARGUED, and the author found a LARGER effect I had missed: because CalIntertidal builds with `by_genus = TRUE` and `max_foreign_reps = 20`, 79, 95 and 93 percent of eligible references hold NO stored confamilial pair, and the stored best is against one sampled genus rather than the closest. The floor effect I raised is small by comparison (3 to 8 percent near the floor). BUT I CHALLENGE THE "NET: CONSERVATIVE" READING, because the sign matters: a too-distant H3 makes a high-identity match less likely under H3, so H1 wins more easily and species calls stay MORE confident, which is the SAME direction as the overconfidence this change corrects. So the residual error under-corrects a known defect rather than erring toward caution; "conservative" describes the size of the change, not the direction of the risk, and in a review response those read as opposites. The accurate statement is that 91.8, 95.5 and 86.8 are LOWER BOUNDS, the true correction is larger, and the shortfall leaves residual overconfidence. Not an argument against merging. MY COUNTS CLAIM WAS WRONG AND I ASSERTED IT: the figures quoted ARE the contributing counts, not set totals, so 18S's 95.5 rests on 702 references across 197 families at about 3.6 each, thin per family but BROAD across them, which is the shape family-equal weighting suits. Second time in two messages I mis-read which population a number described, the error I keep flagging elsewhere. NO BOOTSTRAP IS NEEDED before merge, and the reason is in the code: `h3_var` takes the variance of observed confamilial scores ACROSS references, which is the right quantity for H3's sigma, since H3 models a random confamilial relative and the dispersion of actual confamilial scores IS the predictive variance; a bootstrap would give the uncertainty of the MEAN, which bears on how well delta is pinned and is diagnostic rather than model-relevant. A THIRD BIAS I FOUND, pointing the same way as the other two: the MEAN is family-equal-weighted so no heavily sequenced family can set the ring, but the VARIANCE is pooled unweighted, so such a family dominates the spread while barred from the centre. Well-studied families tend to have narrower confamilial spread, so the pooled variance is likely too SMALL, a too-sharp H3 explains a high-identity match less well, H1 wins more easily, and species calls stay more confident. The fix is a few lines, weighting the variance by family, and is worth doing only because it removes an inconsistency between two quantities computed from the same object; if shipped as is, the roxygen should say so alongside the other two directional notes | CLOSED 2026-10-11: verified already in `main` (ancestry checked against `02eadbc`) |
| Crosswalk CLOSED with a digest stamp; and I CORRECT MY OWN "never ran" claim | The crosswalk holds 1, 18 and 50 species (12S, 18S, COI) referenced under an NCBI name differing from the GBIF prior name, and the earlier 9.6 and 17.6 percent "unmatched" figures counted CANDIDATE names, mostly informal (sp., strain, hybrid) and never entering priors, so that figure measured a SUPERSET and arm (c) was less inflated than either of us thought. The `file.exists()` guard I flagged is fixed, and better than I suggested: the files carry an `attr` digest of the marker's reference species and `.referenced_names()` STOPS on a mismatch, which fails loudly rather than relying on a filename nobody reads; absent is still loud; counts unchanged after the rebuild. MY ERROR, and it is the one I have spent two days flagging in others' work: I read a CODE COMMENT saying Section 8 had never run past its first statement and reported it as the current state. Section 8 DID complete on 2026-09-27; I verified it the way I should have first, and `CalIntertidal_all_posteriors_r2.rds` and `_consensus_final.rds` exist, timestamped 14:00:19 and 14:03:53. One command would have refuted the comment before I told anyone. The sub-case worth remembering: a comment that was TRUE WHEN WRITTEN, describing a defect since fixed, reads in the present tense forever, which is the stale-number trap approached from the other side. THE NARROWER CLAIM STANDS AND IS THE ONE THAT MATTERS: everything added to Section 8 since 09-29, the site-grouped update, blank-to-NA, `pool_tail`, the unreferenced mass, the zero-candidate rows and the new guards, has NOT run end to end, so the arm numbers are harness measurements on the target subset rather than workflow output, and the first combined run remains the first end-to-end test of that accumulated set | that chat, when it re-measures |
| RELAYED, NOT YET CONFIRMED: a six-item missing-tail plan, reported as decided and all 1.0 | Reported to me as the maintainer's decisions in this order: (1) `pool_tail` ON, with CalIntertidal set to TRUE and the package default to be confirmed directly; (2) `add_unreferenced_prior_mass()` wired into Section 8; (3) the RANK-RING LADDER on the likelihood side, measured family, order and class ring likelihoods from the saved reference-pair tables replacing the heuristic H3, post-Step-7 with no likelihood re-run; (4) the prior-decided flag and the likelihood-only consensus; (5) the ESV x site assignment switch and grain test; (6) the NAMED unreferenced-species expansion in CalIntertidal once the flag can mark prior-decided species calls. I WAS ASKED TO RECORD THE RING LADDER AND ESV x SITE AS ACCEPTED DECISIONS AND I AM NOT DOING THAT, for the reason the maintainer corrected me on earlier today: a relayed decision recorded as accepted is an assertion I cannot verify, and letting a relay's vocabulary into this board is exactly how "1.1" spread until he asked where it came from. These stay RELAYED, PENDING DIRECT CONFIRMATION. That is a labelling position only: nobody is blocked from BUILDING, since building is not merging, and I am the gate on `main` rather than on their work. ONE TECHNICAL POINT ON ITEM 3, raised now because it is being built now and was never answered: the distant ring likelihoods would be fitted from the saved reference-pair tables, and `build_sequence_matrix()` retains only pairs at 75 percent identity or better (`max_dist = 0.25`), so class and phylum pairs below that are NOT IN THE SAMPLE AT ALL. The fitted distant rings would therefore sit too high, since only the good tail of distant matches is observable, making the model too willing to say "something in this class". The direction is safer than today's over-confidence, so it is not a blocker, but the rings fitted on censored data must be LABELLED as such, and ideally fitted from a subsample built with a lower floor. The earlier note that H5 and above show likelihood near zero may itself BE this artefact | CLOSED 2026-10-11: verified already in `main` (ancestry checked against `02eadbc`) |
| HELD for the maintainer's direct word: `calib-constant-default` @ `f9127d1`, constant offset for every marker | A relayed decision (option A, constant everywhere, chosen for one method and one Methods sentence), and the relaying chat flagged it as relayed. A default that changes likelihoods for any caller relying on it is a BEHAVIOUR change rather than a scope question, so it waits. VERIFIED at `cfe86b0`, three suites in one session: TaxaLikely 1,554 and TaxaAssign 953 with no failures, and the flipped default is the only signature change. THE COST, FOR THE RECORD rather than as an objection, from the chat's own held-out table: the large win everywhere is NONE to CONSTANT, fivefold on 12S Illumina, so having an offset at all is the essential thing; LINEAR then adds 9 percent on COI Illumina (0.198 to 0.181) and 25 percent on COI Nanopore (0.159 to 0.127), on a slope whose confidence interval (-75 to -25) excludes zero, and nothing measurable on 18S or 12S. So constant-for-every-marker gives up a measured and SUPPORTED marker-specific gain in exchange for methodological uniformity. That is a legitimate trade and the maintainer's to make; the only thing I asked for is that the review response SAY what was given up, so nobody later reads "constant for every marker" as "constant performed best". WORKFLOW STATE, corrected: ALL SIX now read `"constant"` on code lines (CalIntertidal multi_marker and stage_C, PtConception 12S single-site, the eDNA template, Mugu, GreatLakes). My earlier report that three still said `"linear"` was wrong: my grep took the FIRST match per file and caught the COMMENTS left describing the former form, which is a proxy-for-the-thing error of exactly the kind this screen keeps finding, in my own check. The amendment at `f9127d1` touches only the review response, 6 insertions, so the code is identical to the `cfe86b0` I verified across three suites; the entry now quotes the COI held-out column beside the decision and says plainly that this is a choice of one method over a marker-specific gain | CLOSED 2026-10-11: verified already in `main` (ancestry checked against `02eadbc`) |
| PRE-EXISTING TRAP: two TaxaWizard tests fail whenever a sibling is `load_all`'d first | Found while verifying the branch above, and NOT caused by it: `test-pack.R` "generated pack equals the committed copy" and `test-registry.R` "every registry function has a title and description" fail identically on MAIN under the same ordering (1,153 and 2), while TaxaWizard alone passes 1,155 with none. Both read Rd help, and a `load_all`'d sibling supplies it degraded, so running TaxaLikely's suite first makes TaxaWizard's registry read source-derived help instead of installed help. THE HARM is not the two failures but what they train: anyone running a combined local suite sees two failures unrelated to their change in those files, which teaches people to dismiss failures there. THE FIX is a guard, since both tests are only meaningful against INSTALLED builds: skip with a stated reason when a sibling is `load_all`'d rather than fail. THIRD INSTANCE TODAY of a test whose answer depends on which build happens to be loaded, after the integration test asserting a sibling's rule and the author's local check passing against the old installed build | low priority, nobody's yet |
| Installed library is BEHIND main, and the reinstall gate is stricter than I documented | TaxaAssign and TaxaLikely changed with the complement merge and are not rebuilt. MEASURED 2026-09-29: none of the nine packages has `src/`, so none installs a `.so`, and R reads a pure-R package's lazy-load `.rdb` on demand and closes it again, so a LOADED TaxaID package leaves NO open file handle. On the live 18S accession screen (PID 8406) `lsof` shows 18 open library files, EVERY ONE a compiled dependency (Biostrings, IRanges, dplyr, rlang, stringi and the rest) and not a single Taxa file, while the process is plainly running TaxaID code. So `lsof +D <library>` has NEVER been able to see the packages it exists to protect; it only ever detected compiled dependencies, and describing it this morning as the belt to the process check's braces was wrong. The PROCESS check is the only real gate: no `R`, `Rscript`, `rsession`, `radian` or `Rterm` alive at all. A peer's "nothing of mine is running" is ALSO insufficient, since another session's process counts and no session can see what a third has attached. Written into `rebuild_all_nine.sh` and into memory | a machine with no R at all |
| CALIBRATION: model unchanged, DOCS FIXED and merged, and 18S has the opposite problem | `calib-slope-docs` merged at `06f6b08`: roxygen only, no executable change, TaxaLikely 1,553 passing. The roxygen now says the slope is UNCONSTRAINED, what negative and above-one values mean, what COI showed, that the cause is not established, and to inspect the fitted value rather than assume a range; the review response records the withdrawn bound and why. THE SEQUENCE, worth keeping because it corrected twice: a bound was proposed on the strength of `cor(trained, remapped) = -1.00`; I showed that correlation is ARITHMETIC for an affine remap; the spread measurement I asked for OVERTURNED the bound, since the negative slope predicts held-out species better; I then objected that leave-one-out was near-in-sample for a two-parameter fit over thousands of species; and THAT WAS MY ERROR, because the fit is on 69 to 94 species, not thousands, having confused the species being REMAPPED with the species being FIT. TESTS RUN: family-block CV favours unconstrained on COI (0.182 against 0.198, and 0.127 against 0.158) and ties on 18S; the reference-count confound is CONTROLLED, correlation 0.46 with log deposit count but the slope moves only -49.9 to -48.4 when it enters the fit, so deposit count is not the explanation. MY REMAINING CAVEAT: with 69 species across 56 families, about 1.2 per block, family blocking is very nearly leave-one-out again, so the test I asked for could not deliver the separation I wanted; the data lacks within-family replication. The honest position is that the association survives every available test and no available test is strong, and the best evidence remains that the sign is negative on BOTH platforms independently at n of 69 and 94. NEW, FROM THEIR OWN NUMBERS AND IN THE OPPOSITE DIRECTION: for 18S the slope is NOT significant (p 0.3 to 0.4, n of 12 to 13) and family-block CV ties, yet form selection chose LINEAR with slopes of +7.1 and +8.4. That is selecting the more complex form on no evidence, the mirror of the COI case where the slope is supported and the docs said it could not exist. Worth asking whether form selection should require the slope to be SUPPORTED rather than choosing on fit alone; on 18S that would fall back to constant. THE CACHE-KEY BLOCKER STANDS: `.lik_key` omits the TaxaLikely version | DECIDED 2026-10-12: `offset_form = "constant"` stands as a stated default, not a measured winner. Docs fixed at `456be1f` |
| CLOSED: seeding gap fixed, and `complement` @ `ccdfc7f` is VERIFIED AND READY | The author accepted that the predicate selected explicit cases and missed default ones, and seeded every remaining block: 79 more (assign_taxa_llm 53, the pipelines 14, compute_posterior 7, and one each in five other files), 79 against my 76 because a few pass `n_sims = 0` explicitly where a seed is harmless. VERIFIED BY ME with the same script that found the gap: simulating TaxaAssign blocks with no seed is now ZERO, so the suite is deterministic whatever is added later and `setup-seed.R` is back to being only a backstop. Combined run, the ordering that originally failed: TaxaLikely 1,553 and TaxaAssign 953, no failures. 18 commits, still exactly ONE touching Step 7. DEFERRED BY AGREEMENT, and the author's reasoning is right: my `n_sims = 0` suggestion needs each of the roughly 95 blocks read to decide whether it asserts simulated values (`posterior_sd`, `confidence_score`, the presence draws) or only structure, and doing it mechanically would quietly turn a test that exercises the Monte Carlo path into one that does not. Seeds give determinism now; the `n_sims = 0` pass is a speed-and-clarity improvement for its own commit, outside this set. NOTHING IS OUTSTANDING ON MY SIDE for this branch | CLOSED 2026-10-11: verified already in `main` (ancestry checked against `02eadbc`) |
| RESOLVED, and the lesson is not the one I first gave: a cross-package `::` call in a test validates whatever is LOADED | The order-dependent failure is fixed at `complement` f2c5fe3 and verified by me under the exact failing ordering: TaxaLikely then TaxaAssign in one session, 1,553 and 953, no failures; two test-only commits; still exactly one commit touching Step 7. I WAS WRONG TWICE. The mechanism was NOT unseeded Monte Carlo: the test calls `compute_posterior(n_sims = 0)`, which draws nothing, so my inference was ruled out by the call itself. And my claim that CI would stay green was wrong the other way, since its per-package jobs install siblings from the checkout, so CI would have failed too; the combined run caught it earlier and more clearly, which is a smaller claim than the one I made. THE REAL LESSON, worth recording in place of the seed story: a cross-package `::` call inside a test resolves to whatever is LOADED at that moment, so a test can silently validate the INSTALLED sibling while appearing to validate the source. That is why the author's local `rcmdcheck` passed, checking the old installed TaxaLikely and reporting on the branch. Same family as everything else this screen has found, a check reading a proxy for the thing it names. THE FIX IS STRUCTURAL, not cosmetic: the rule assertion moved into the package that OWNS the rule and the integration test keeps only the hand-off, so neither test can be satisfied by the wrong build. STILL ASKED FOR: seeding inside each of the roughly twenty tests that exercise simulation, not only the new package-level `setup-seed.R`. The package-level seed makes a run independent of what PRECEDED it, which was the reported problem, but the stream is still shared within the suite, so adding any simulating test shifts every later test's stream and a future unrelated addition can flip an assertion, which is the same failure arriving months later with no obvious cause | that chat: per-test seeds |
| READY FOR ONE DECISION: integration branch `complement` @ `3dd1f77`, VERIFIED, and it splits into two cost classes | Supersedes the four earlier branches, which are merged into it. VERIFIED BY ME against the merge, not the branch: TaxaAssign 954 passing, TaxaLikely 1,546, no failures; CI invocation 0 errors on both with the standing CRAN-incoming warning and clock note; inventory 16 exports and 18 test files for TaxaAssign with the tree agreeing; exactly ONE new export across all nine NAMESPACEs, `add_unreferenced_prior_mass()`. THE SPLIT THAT MAKES THIS TWO DECISIONS INSTEAD OF ONE, verified by checking all 14 commits rather than taking the claim: exactly one commit touches Step 7 code, `3dd1f77` on `calibrate_query_noise.R`, so THIRTEEN commits cost no likelihood re-run and ONE does, and holding that one back is a clean operation. Contents: the two keep-generic fixes, the new export, blank ranks to NA across six functions, `combine_multisite_priors()` counting each site once (identical repeats dropped with a message, conflicting repeats stopping the call, 527 over-counted rows in Round 1), the species-rank-only scope sum, the single-family genus fill for the homonym fan-out, and tail pooling now OPT-IN with `pool_tail = FALSE` reproducing the existing rule as I asked. Every behaviour fix has a test that fails on the previous code, verified per commit by its author against a package copy. WHAT IS STILL OWED, not on this branch and workflow-side: CalIntertidal Step 5 labelling about 44,000 coarse prior rows as species, the blank-to-NA conversion in `taxonomy_lookup`, and the `referenced_names` crosswalk, without which arm (c) stays unquotable for 18S and COI. MY ASK of the author: report how many species-rank prior names FAIL the binomial filter, since it correctly rejects "sp." and "cf." rows that nonetheless carry real theta, so the 476 qualifying-genus figure is conditional on that exclusion and a reader cannot currently tell | CLOSED 2026-10-11: superseded by `7ae8785`, already in main -- same subject, and 7ae8785's patch is a strict superset (adds the roxygen and the n_qualifying_genera / n_prior_names_not_binomial attributes). 3dd1f77 holds nothing unique and is now unreachable |
| CORRECTED: the coarse prior rows are TWO problems, not one, and only one is cheap | MY "one change, two problems, no re-run" WAS WRONG. `estimate_kernel_priors()` computes theta as a SHARE of one denominator, so the 84,000 coarse records in the pool dilute every species' theta and feed the Good-Turing budget; relabelling a row's rank does not remove it from that denominator. I assumed the coarse rows mattered only as rows to be summed, without checking that the quantity was a share. THE DIGEST-NARROWING IDEA IS CLOSED, and I ran the check that closes it: the consumer, `identify_confident_observations()`, does not merely match names, it filters to species rank then counts `theta_mean > plausibility_threshold` and keeps genera with exactly one plausible species, so it reads theta VALUES. A refit on `pool_at_rank(species)` changes every species' theta because the denominator changes, so the consumer's answer changes whatever the digest sees; the invalidation is correct and narrowing the digest would make the checkpoints stale rather than valid. RELABELLING IS STILL WORTH DOING, for a reason neither chat named: that same consumer filters on `taxon_name_rank == "species"`, and the coarse rows are MISLABELLED as species, so a genus-rank row such as "Icelinus" is counted as a plausible species of its own genus and can push a genus to `n_plausible == 2`, disqualifying it from the `n_plausible == 1` filter. If that fires, the CALIBRATION's training set is silently shrunk, and `calibrate_query_noise()` sets the likelihood calibration, so the mislabelling reaches the likelihood model and not only the priors. That is read from the code, not measured; the cheap test is to count how many genera are disqualified by a coarse row rather than a real second species. THREE-PART POSITION: relabelling fixes the calibration-set contamination; the dilution needs the refit; the refit legitimately costs the Step 7 checkpoints. An 11.5 percent dilution cannot explain *Artedius*'s 300-fold range, so dilution and effort bias are separate contributors and effort dominates there | DECIDED 2026-10-12: DEFERRED past 1.0. Fixing it refits every theta against a new denominator, invalidating the priors table and every likelihood |
| Tail pooling was built DEFAULT-ON, and the arms are now confounded | Contrary to the plan I recommended and the maintainer endorsed, which was the diagnostic default-on as a pure addition and the RULE as an opt-in argument. Isolated on main's arm-a posteriors it takes species calls 544 to 475, creating none, and it does fix what it targeted: all 17 low-posterior 18S calls and all 9 *Littorina* rows go. But it ALSO removes 52 calls at posterior 0.5 to 0.9 (12S 15 with median 0.89, 18S 26, COI 11) including 9 clean calls, so the trade is about three to one against arm (b)'s ten to one. A defensible change on a weaker margin is exactly the profile that should be OPT-IN and measured rather than switched on for everyone; I have asked for the argument with current behaviour as the default. SEPARATELY, the branch's arms now bundle the complement WITH tail pooling (544, 374, 304), so an adopt decision on the complement would rest on a confounded measurement; asked for the arms re-run with tail pooling off so the earlier clean numbers stay comparable. "Zero species calls below 0.5 in every arm" is tail pooling's strongest single argument and deserves reporting as its own result | that chat, then maintainer |
| MEASURED: my bias-direction argument holds for COI only, and a study-wide median hides the case that mattered | Spearman of a family's family-only record fraction against its unreferenced species fraction, per marker: 12S 51 families rho -0.08 (p 0.59), no trend; 18S 123 families rho 0.11 (p 0.23), not significant; COI 255 families rho 0.21 (p 0.0009), a real monotone roughly threefold trend across tertiles. So identification difficulty and reference gaps co-occur in COI and not measurably elsewhere. I am recording that as a small marker-specific effect, not the general principle I proposed, since rho 0.21 explains about four percent of the variance. THE MORE USEFUL FINDING IS THE CAVEAT: 12S's median coarse fraction is 0.004, which reads as "the species-only bound costs little there", yet the one 12S case examined in detail, *Artedius* at Government Point, had a coarse row carrying 74 PERCENT of its scope mass. Both are true only if the distribution is heavy-tailed, so a median over families says nothing about the specific scope that decided a call, and the known case sits in the tail. "The bound costs little in 12S" is therefore true on average and false where it mattered, which is the same error as reading "only 16 ESVs split" as "the rest are the same species everywhere". THE QUANTITY THAT SETTLES IT is per scope, not per family: among the calls that actually changed, what fraction of each scope's total mass was coarse. If several demotions sat on coarse-dominated scopes, 12S needs pro rata or at least the excluded-rows listing doing real interpretive work; if only *Artedius* did, the study-wide reading stands. Asked for before Kevin decides arm (c) | that chat |
| PROPOSED, NOT BUILT: split a coarse prior row's mass pro rata instead of excluding it | That chat's proposal, and examining its assumption FAVOURS it. The assumption is that coarse records are distributed like identified ones, applied at Government Point as 3.8e-4 unreferenced out of total Cottidae species theta, scaled onto the 1.1e-3 family row. The assumption is NOT neutral: a record is identified only to family BECAUSE it was hard to identify, and hard specimens skew toward cryptic, damaged, juvenile and poorly-studied taxa, which are disproportionately the taxa with no reference sequence. So the unreferenced share among family-only records is probably HIGHER than among identified ones, and pro rata would under-credit it, in the SAME direction as the species-only bound it replaces but less far. That makes it a strict improvement on the bound rather than a trade of conservatism for accuracy, which is a stronger case for adopting it than "it turns a bound into an estimate". THE TESTABLE PART: the direct test needs ground truth nobody has, but the BIAS DIRECTION is testable from the occurrence pool alone, by asking whether a family's family-only record fraction correlates with its unreferenced species fraction across families at a site. Two columns and a correlation, and it is worth running even if pro rata is never adopted, because it also says whether the species-only bound is mildly or badly conservative. For 1.0: species-rank only, documented as conservative, excluded rows listed | DECIDED 2026-10-11: NOT 1.0 -- revisit after the release |
| The *Artedius* fourfold resolves to a NAMED cause; arm (c)'s aggregate numbers are VOID | A closed account, not a plausible story: the helper summed three COARSE-RANK prior rows as though they were unreferenced species, "Cottidae" (family rank, theta 1.1e-3, 74 percent of the scope mass), "Icelinus" and "Hemilepidotus" (genus rows). With the 6 real unreferenced cottids that gives 1.48e-3 against the 1.46e-3 reported; species rows alone give 3.8e-4. My `fill_higher_ranks` sibling was explicitly CLEARED as the cause here, family assignment agreeing between the expansion taxonomy and the occurrence pool for every name; it remains a real and separate defect. CONSEQUENCE BIGGER THAN THE TWO ESVs: since 74 percent of that scope's mass was one coarse row, and family-level identifications are common in occurrence data, every scope holding a coarse row was inflated similarly, so arm (c)'s AGGREGATE numbers, the 352 species calls, the marker breakdowns and the clean-call costs, are VOID and must be re-measured rather than adjusted. WHAT SURVIVES: the *Oligocottus* validation, because it rests on two SPECIES-rank rows the fix does not touch. Same shape as the contaminant finding, where the mechanism and named cases stood while every derived number fell. CAVEAT TO DOCUMENT, not debate: summing species rows only makes the scope mass a LOWER BOUND, because a family-rank row IS real evidence of unidentified local relatives but is not DISJOINT from the species rows, a record identified only to family being possibly any local species including a referenced one. Excluding it avoids double-counting at the cost of discarding information, so the mass is conservative BY CONSTRUCTION and a conservative mass UNDER-corrects, which matters when its whole purpose is to stop over-confident species calls. Listing the excluded rows in `scope_members` is the right treatment. FOR THE DESIGN NOTE: this is a GRAIN error, rows of mixed rank summed as one rank, and the thread that produced it began with the question of whether assignment grain should equal prior grain. The confusion that motivated the discussion appeared inside the first function built to address it | that chat, to re-measure |
| SIBLING DEFECT, found by my sweep: `TaxaTools::fill_higher_ranks()` silently picks one family for an ambiguous genus | The second over-count path was traced to homonym genera: `join_priors`'s `fam_lookup <- distinct(genus, family)` left-joined by genus doubles every row where a genus maps to two families, and 27 genera across the match objects do (*Porella* bryozoan and liverwort, *Eisenia* kelp and earthworm, *Mastophora* alga and spider, *Dilophus* alga and fly, and others). That is this project's own recorded lesson recurring: a taxon name is not a key. I SWEPT every join in all nine packages keyed on a bare genus, taxon name, species or family, and found a sibling that fails WORSE. `fill_higher_ranks()` joins by genus in three places, but its lookup ends `distinct(genus, .keep_all = TRUE)`, so it does NOT fan out: it silently keeps ONE family per genus, whichever appears FIRST in the bound sources, with no ambiguity check and no warning anywhere in the function. Opposite failure modes from one root cause: `join_priors` duplicates rows, which inflates a count somebody can measure, while `fill_higher_ranks` returns a confident WRONG family that nobody can count, and its choice depends on input ORDER so it is also not reproducible across runs. It lives in TaxaTools, so its answer propagates into habitat, scope and priors. The fix is the same, key the family fill on the row's own lineage, plus this function must SAY when a genus is ambiguous instead of choosing silently | CLOSED 2026-10-11, both halves. Reporting merged at `cba7842`; the lineage keying merged at `712ed59`. Where a genus maps to more than one value the fill now reads the taxon's OWN row in the caller's sources, a value standing beside this exact name being a statement about this taxon where a genus-keyed one is a statement about whatever else shares the name. MEASURED on the real caller, 3,489 prior taxa against seven sources: 202 of 15,160 genus names in the sources are ambiguous, 74 of those genera reach the taxa being filled and affect 137 of them, all 137 resolved from their own row, 49 fills CHANGED. Unanimous genera are deliberately untouched -- both such changes on this study were WRONG, importing one stray row's error (Grateloupia into Callithamniaceae), so the rule replaces a guess with evidence and never replaces agreement with one row's noise. A RESIDUAL CLASS THAT NO LINEAGE CAN FIX, and worth knowing before the manuscript: 63 of the 137 carry competing family circumscriptions for the SAME organism -- Cyclopsettidae against Paralichthyidae for Citharichthys, Jordaniidae against Cottidae for Jordania, Girellidae against Kyphosidae -- i.e. NCBI against GBIF on one fish, not a homonym. The precedence still settles those and the report names them. A refusal option was OFFERED AND DECLINED by the maintainer. CHANGES RESULTS: a re-run moves 49 of 3,489 family assignments, which feed the coarse-rank expansion and the unreferenced-mass scopes; nothing saved moves until re-run | CLOSED 2026-10-11, both halves: reporting at `cba7842`, lineage keying at `712ed59` |
| ARM (c) MOVES FROM HOLD TO FIX-THEN-ADOPT, on the classified ten | The 12S ten I asked to be classified rather than counted came back split, and the split validates the concept. The *Oligocottus* demotions are CORRECT: two unreferenced local congeners, *O. rubellio* at theta 1.1e-4 against *O. snyderi*'s 1.6e-4 and *O. rimensis* at 9.7e-6, neither with a 12S reference in the fetched set, and the H2 likelihood cannot exclude them, so the species call was over-confident and arm (c) is doing its job on real data. The *Artedius lateralis* demotions are a HELPER BUG: about 3.8e-4 of unreferenced cottid mass is accountable at Government Point against 1.46e-3 actually used, roughly fourfold, with three species untraceable. So the concept is validated and the implementation over-adds through scope membership. I insist the fourfold resolve to a NAMED cause, three specific species, and not to a tuned coefficient; the `scope_members` attribute will produce them, and if it does not, that is the finding. ALSO, on the over-tightening effect: 26 of 518 observations change consensus, but the test arm reaches 45x where production reached 154x, so it is understated BY CONSTRUCTION and "24 of 27 species calls unchanged" is a lower bound, not reassurance. Counterintuitive and worth keeping: 22 observations became MORE resolved once the over-tightening was removed | that chat, then maintainer |
| QUOTABLE AT LAST: adopt arm (b), HOLD arm (c) | Three-arm re-run with empty strings converted to NA, verified 0 duplicate rows, 0 empty genus and 0 species calls named "" in every arm and marker. Species calls 544, 451, 352. ARM (b) IS A CLEAR ADOPT: it removes 68 of 115 no-local-record calls for 7 of 86 clean calls, about ten to one, and 18S falls from 63 to 6, a ninety percent cut in the study's worst pathology. That recommends the TWO keep-generic branches independently of the new export, which reduces the queue from one five-part bundle to an evidenced pair plus a held item. ARM (c) IS HELD, on 12S: its backbone is clean (2 of 2,485 unmatched) so the measurement is interpretable there, and it costs 10 of 38 clean calls with no no-record calls to remove, pure cost in the only marker we can trust. BUT THE TEN MUST BE CLASSIFIED, NOT COUNTED, because "clean" only means likelihood ratio at least 1.5 and not a trace row, which does not mean the call was right. The separating question: is each winner locally RECORDED and decisively discriminated? If yes, arm (c) is over-adding mass and is heavy-handed; if no, the demotion is correct and those ten were over-confident all along, making the "cost" a gain. Ten rows is small enough to read individually and it settles whether the unreferenced mass is calibrated. ALSO RECORDED: the COI anomaly disappearing once empty strings were cleaned confirms that trace was complete rather than partial; and *Littorina* surviving in both b and c on the lone-survivor path confirms the complement and the consensus flaw are INDEPENDENT, so the coverage diagnostic is needed whichever way the complement goes. The over-tightening measurement still comes first, being the only item that concerns results that already exist | STALE AS WRITTEN -- see the 2026-10-12 section: production runs arm (c) ON (ADD_UNREFERENCED_MASS TRUE, and named_rows beyond the tested arm). maintainer: whether to validate before the outputs are used |
| URGENT, and it touches SAVED results rather than experimental arms: possible multi-site prior over-tightening | Traced from the empty-string defect. Match objects store `genus = ""` / `species = ""` for family-level references (COI 19,400 rows); `join_priors.R` around line 1516 builds `fam_lookup` as distinct(genus, family) and left-joins by genus, so every `genus == ""` row joins EVERY family having a "" genus and makes k identical copies of one generic hypothesis. 100 percent of duplicated rows have `genus == ""` (COI 7,286 of 7,286 at ESV x site). In production `combine_multisite_priors()` COLLAPSES those copies, which is why saved Round 1 shows zero duplicates. THE WORRY, reasoned by that chat and not yet measured: the collapse may treat k copies of ONE site's prior as k INDEPENDENT sites, making the combined precision k times too high and over-tightening the prior. If real, this is already baked into saved production results and into anything quoted from them, unlike every other item in this thread, which concerns numbers nobody has published. THE CHEAP DECISIVE TEST I asked for, before the arm re-runs: for observations whose candidate rows carried `genus == ""`, compare `n_sites_combined` against the true number of distinct sites. Exceeding it confirms the mechanism and the ratio gives the magnitude; matching closes the worry. MY DUPLICATE-GUARD OBJECTION IS RESOLVED in the good way, the cause being located, so no guard is needed and the fix belongs at the source. STRUCTURAL POINT: match objects should not write "" for an absent rank at all, or every present and future reader must remember the convention. This is the SECOND time today a correction has had to be applied at N reading sites because a property was not carried on the row, after the exemption lists. MY PREDICTED MECHANISM accounts for 5 of the 37 COI gains, all 5 confirming it, plus 10 or 11 retained 18S calls in arms b and c, so it is real and minor; the other 32 at a median posterior of 0.93 are the empty-string bug | CLOSED 2026-10-12 from the code: the one-site-counts-once guard (`1441ba8`) predates the artefacts |
| DECISION NEEDED: five numbers-changing changes are queued at a tagged freeze | Not a criticism of the work, which is verified; the problem is arithmetic. QUEUED: (1) `keep-generic-unreferenced` f14795b, generic rows survive the redundancy filter; (2) `unreferenced-ring-priors` 3175a41, NEW EXPORT `add_unreferenced_prior_mass()`; (3) `expansion-keep-generic` f30c68a, generic rows kept in the expansion, WHICH ALSO switches on `apply_coverage_constraints()` for the first time (see below); (4) the empty-string fix, a real bug where a family row's `species = ""` is read as a species value and reported unanimous at species with an empty taxon name, accounting for 18 of 23 COI arm-c "gains"; (5) duplicate generic rows between Step 7 and the posterior (12S 72, COI 474 groups), cause UNLOCATED. Plus the consensus coverage rule already recorded. MY PREDICTED MECHANISM FOR THE COI GAIN WAS WRONG and is withdrawn: it is mostly the empty-string bug, not renormalisation pushing competitors below the floor. MY OBJECTION TO ITEM 5's PROPOSED FIX: a silent de-duplication guard for an unlocated cause is the exact shape this screen keeps finding, a correction that removes a symptom and leaves the cause looking fixed; if the duplication is a join fan-out it is probably duplicating other things too. Make it LOUD instead, reporting the count and which observations. THE HEADLINE IS ITEM 3's SIDE EFFECT: `apply_coverage_constraints()` joins its genus census on genus-rank `unreferenced_species` rows, so after the expansion it has had NOTHING to act on in every workflow that ran the expansion. That function has never done its job. It is the FOURTH OR FIFTH never-executed component this screen has found, after the stubbed workflow steps, the dead seed inside a conditional and the guard made unreachable by `pipefail`, and at that count it stops being bad luck and becomes a statement about how this ecosystem is verified. Merges are HELD: I do not act on relayed approval, and five numbers-changing changes at a tagged freeze need ONE decision, not five | CLOSED 2026-10-12: four of the five verified in main, the fifth superseded by `7ae8785` |
| The coverage diagnostic separates PERFECTLY, and the complement makes the consensus flaw fire MORE | Measured on the saved Round-1 posteriors. The 74 low-posterior species calls have a median of 28 hypotheses, 27 of them sub-floor, carrying median sub-floor mass 0.853 with a MINIMUM of 0.505, and 72 of 74 have `n_plausible = 1`. The other 16,775 have a median of 1 hypothesis and median sub-floor mass 0.000. "Sub-floor mass above 0.5" catches 100 percent of the 74 and 0 percent of the rest: a gap, not a tuned threshold, so the diagnostic ships with a stated separator rather than a guessed one. By marker: 18S 56, COI 18, 12S 0. MY BOUND ON ARM (c) WAS WRONG FOR COI and is withdrawn: COI has MORE species calls in arm (c), 136, than in arm (b), 122, with 37 that were not species in arm (a), so added mass does not only push calls off species. THE MECHANISM I PREDICT, testable against columns that chat already has: adding unreferenced mass renormalises every specific candidate downward, which in a large flat set pushes several competitors from just above `min_posterior` to just below it, they are dropped, `n_plausible` collapses to 1, and a LOW-posterior species call appears. That is the 74-type pathology being manufactured by the mass addition rather than a new resolution. The prediction is that those 37 calls carry high sub-floor mass, `n_plausible` of 1 and low `consensus_posterior`. CONSEQUENCE FOR THE FREEZE, and it changes my earlier advice: if the complement makes the consensus flaw fire MORE often, then shipping the complement without at least the coverage diagnostic would make a known defect more frequent while leaving it invisible. The diagnostic therefore ships WITH the complement, or the complement waits. Arm (c) should not be quoted for ANY marker until this resolves, since the mechanism applies wherever candidate sets are large and flat, which is 18S as much as COI | NUMBERS SUPERSEDED 2026-10-12 by the arm (c) counterfactual; the 545-era figures no longer describe the pipeline |
| MEASURED: the complement earns its keep; and a fourth defect, in the consensus itself | Three arms on CalIntertidal real data, reproduced to 1.6e-15 by an independent wrapper. Species calls at ESV x site: 545 as-is, 462 with the generic rows kept, 389 with unreferenced local mass added. Calls whose winner has NO local record: 116, 50, 42, and on 18S 63 down to 1. Clean calls: 86, 79, 69. THE TRADE IS FAVOURABLE, about four pathologies cleared per clean call lost, which is the strongest evidence yet that the complement work is worth its cost. ARM (c) IS INFLATED AND MUST NOT BE QUOTED YET: the backbone check fired at 9.6 percent of 18S and 17.6 percent of COI candidate names unmatched to `referenced_names`, so referenced species are being counted into the unreferenced mass; 389 is a lower bound, the answer lies between 462 and 389, and COI arm (c) is uninterpretable until reference names are crosswalked to GBIF. FOURTH DEFECT, and *Littorina* survives every arm because of it: `posterior_consensus()` calls it species at `consensus_posterior` 0.128 because about twenty competitors each sit just under `min_posterior = 0.05`, are dropped, and the lone survivor becomes the whole plausible set. Study-wide in the saved Round 1, 74 of 16,849 species calls sit below 0.5 and 41 below 0.2. I READ THE CODE: this is DOCUMENTED behaviour, not a code-versus-docs mismatch, since the roxygen says the cumulative mass is taken after excluding sub-floor hypotheses. So it is a DESIGN FLAW, whose assumption is that sub-floor hypotheses are individually noise AND collectively negligible, and that fails for a large flat candidate set where twenty rows at 0.04 hold 0.8 of the mass. MY RECOMMENDATION, to avoid a fourth simultaneous numbers change: first EMIT the fraction of TOTAL posterior the plausible set covers, which is a pure addition that changes no call, ships in 1.0 and makes all 74 visible immediately; then add the rule change (climb rank when total coverage is insufficient) as an argument defaulting to current behaviour, and let a measurement set the default. A species call at 0.128 stops being indistinguishable from one at 0.95 the moment its coverage is printed beside it | ANSWERED 2026-10-12 by the arm (c) counterfactual: the mass only WITHHOLDS (2,079 species calls), named_rows supplies the resolution. The 545/462/389 figures are superseded |
| THE GENERIC COMPLEMENT IS LOST AT THREE SEPARATE PLACES, and the fixes compose into one numbers change | THREE causes, all verified in code, two measured on real data. (1) `evaluate.R` line 948 re-applied the ratio threshold without the exemption line 814 grants; FIXED and merged at `b954b04`, but it is NOT CalIntertidal's cause, because that workflow runs `ratio_threshold = 0`. (2) `join_priors()` calls `TaxaMatch::filter_redundant_hypotheses()` at line 1623 with no exemption, while the same file exempts the same four hypothesis types at line 81; I checked the filter itself and it has NO awareness of `hypothesis_type` at all, so it cannot tell a competing "Sardinops" from a coarse label for "Sardinops sagax". Measured at one 12S site: 9,132 H2 and 9,278 H3 rows in, 106 and 103 out. (3) `expand_unreferenced_hypotheses()` rule 3 drops the generic row when no RECORDED unreferenced species exists for the genus or family, so "no record" is read as "absent" for the very hypothesis whose job is to represent something not in the records. Measured on PtCon 12S it fires for 79.1 percent (H2) and 59.2 percent (H3) of observations and removes BOTH for 42.6 percent; on 18S it is 94.4, 95.7 and 89.8 percent, worst in the low-resolution marker where the complement matters most. THE PATTERN, and it is why fixing three sites is not enough: the exemption is written as an ad hoc `hypothesis_type` list at each filter, one filter cannot see the column, and a fourth site will be found later. The durable fix is to mark the row ONCE, a single predicate the filters respect, instead of N lists. THE SCOPE JUDGEMENT THAT MATTERS: individually these are three bug fixes, but together they mean every observation carries its complement, which moves every posterior in every workflow. That is a numbers-changing change of the same class as the ring ladder and the freeze accounting must treat it as ONE change, not three slipped in as fixes | CLOSED 2026-10-12: all three fixed (`22655fc`, `f14795b`, `f30c68a`), durable fix `63a45fb`; already in R1009f |
| PACKAGE DEFECT: `evaluate_likelihoods()` drops the generic H2/H3 rows, contrary to its own docs | VERIFIED in code by me, not relayed. Line 814 filters with an explicit exemption (`score_likelihood >= ratio_threshold OR hypothesis_type != "specific_candidate"`); line 948 re-applies the threshold to the simulated mean with NO exemption, under a comment reading only "final filter on mean (after simulation)". The exemption would have no purpose if dropping generic rows were intended, so it is an omission and should be fixed in code rather than documented as intended in a release with no predecessor. MY OVERSTATEMENT, CORRECTED: I argued this was the *Littorina* mechanism, reasoning that the restored congener row would carry a far larger prior than the implausible candidate. MEASURED, it does not: the surviving generic rows carry dark-diversity FLOOR priors with medians 5.4e-6 and 3.2e-6 against the candidate's 1e-5, so the restored row has both a weaker likelihood and a weaker prior and rescues nothing. I therefore also WITHDRAW "the architecture may be unnecessary", which was conditional on that mechanism. The correction sharpens the case for the ring ladder instead: its distinctive contribution is the ring PRIOR, the site mass of unreferenced local species at that rank, and a floor prior is a placeholder standing where a real quantity should be, which no filter fix supplies. The case for fixing the filter now rests on correctness alone, which is sufficient. MY MERGE DECISION: merge the fix, do NOT mandate a Section 7 re-run; it corrects future runs, existing checkpoints stay, and what must be recorded is that a checkpoint built before the fix carries no generic rows, so numbers from both sides of that boundary must never appear in one table. Also corrected: the ring ladder runs POST-Step-7 on the likelihood table, so it does not invalidate checkpoints and the filter fix is the only item that would, which withdraws my "the cost is paid once either way" argument | CLOSED: fix merged at `22655fc`, already active in R1009f |
| ALSO: CalIntertidal's steps 8b to 8d are a STUB, so measurements from it characterise the workflow, not the package | `final_likelihoods <- top_likelihoods  ## STUB` at line 2677, with the unreferenced-species list, the iNat range check and the expansion all skipped; the file's own header has said "NOT YET RUNNABLE" since 2026-09-13. PtConception and the template do call the expansion. WHAT THIS DOES AND DOES NOT INVALIDATE: the grain test's COMPARISON between arms stands, since both arms ran the same stubbed pipeline; its ABSOLUTE characterisation does not, so "119 clean of 545" and "291 prior-decided" want re-measuring with the stub filled. I was one step from writing "12S and COI have no implausibility channel" into the package documentation as a known limitation, which would have encoded a workflow stub as a property of the package. Caught by that chat, not by me | that chat, to re-measure |
| CORRECTED: my set-mass floor fails; the model's own "none of the above" channel is the better signal | Tested against the grain-test output and WITHDRAWN. Set mass across the 545 species rows has median 6.9e-4 and the *Littorina* rows sit at about 2e-4, below the median but not in the tail, so no floor separates them: below 1e-4 catches none of the nine, below 1e-3 catches all nine and also 289 rows including 45 of the 86 clean, below 1e-2 catches 454. THE REASON IS THE SCALE: priors sit on the occurrence scale with the ceiling spread over many species, so absolute set mass measures how REGIONALLY RARE a group is, not how locally implausible. A quantity answering a different question cannot be rescued by tuning its cutoff. MY DISCOVERY OBJECTION HELD, though: 15 of the 86 clean rows have a winner with no occurrence record at the site, which a winner-only floor would have flagged, so that condition is withdrawn by its author too. THE BETTER INSTRUMENT, promoted from that chat's hint: the posterior mass on the unreferenced species and genus hypotheses. It is the model's own "none of the above" channel, which I had wrongly said normalisation destroys; it is relative by construction, already computed, needs no constant on the occurrence scale, and its median across species rows is zero so a nonzero value is already unusual. It measures 0.007 to 0.019 on the *Littorina* rows. NOT YET A RESULT: nine rows is not validation, and the test is whether it separates the 86 clean rows from the 291 prior-decided ones. If both carry unreferenced mass it is measuring reference coverage rather than local implausibility and goes the way of the floor. ALSO CORRECTED, and the error was mine: I said the non-splitting calls were "the same species at every site", inferred from "only 16 split" without checking. Of 233 ESVs with any species-level site, only 18 are species at ALL of them; 215 are species at some and coarser at the rest, median half. That is not a defect but what site-varying information looks like, and it wants a reporting convention rather than a statistical fix: three products, what the sequence alone resolves, what each site resolves, and the coarsest label consistent across a sequence's sites. Also recorded so nobody reaches for it by name: `confirmed_without_occurrence_record` does NOT cover those rows, being emitted only on rows raised in round 2, though the underlying condition is already a column | SPLIT 2026-10-12: reporting convention taken at `ceb641c`; the unreferenced-mass instrument waits ON the batched re-run |
| MEASURED: the ESV x site grain test, and what it changes | The CalIntertidal chat ran the number I asked for before anyone set a default, on 1,556 multi-site ESVs with priors pinned across both arms. Species calls go from 10 at ESV grain to 545 at ESV x site, but only 119 are CLEAN: 291 are prior-decided at a likelihood ratio below 1.5, 235 have the prior overriding the sequence's top species (153 of those overriding a species actually recorded at the site), 264 sit on trace rows and 116 have a winner with no occurrence record at the site. THREE CONSEQUENCES. (a) The MOTIVATION needs restating: the case for this change was that congeners segregate geographically so pooling is correct nowhere, and that describes 16 ESVs out of 1,556, some of those splits being wrong. The other 529 are the same species everywhere, resolved because a per-site prior is sharper than a pooled one. Still a benefit, a different one, and the write-up must not keep the original framing. (b) The change is worth 119, not 545, and 545 is the number not to quote anywhere, since a headline counting flagged calls as resolutions is how a flag stops working. (c) MY CHANGE to the proposed second condition: put the floor on the CANDIDATE SET's total prior mass, not on the winner's prior. A winner-only floor misfires both ways, flagging a genuine low-prior discovery won on decisive sequence evidence, which is the case the ecosystem exists to catch, and missing a set whose winner scrapes over while every candidate is locally absurd. The pathology is not an improbable winner but an improbable SET, and normalisation is what hides it, since a posterior conditional on one candidate being right always sums to one and always names a winner. The *Littorina littorea* case, Atlantic, six California and Baja sites, theta about 1e-5, likelihood ratio 0.8, is exactly that. Also: the 116 with no occurrence record may already be covered by the existing `confirmed_without_occurrence_record` column, worth checking before a second signal is built; and both flag inputs should be REPORTED as numbers with documented threshold arguments, since this package replaced binary thresholds with continuous posteriors on purpose | CLOSED 2026-10-12: floor withdrawn, triage not mechanised by decision; the 545/119 counts are SUPERSEDED, use prior_role |
| DESIGN: re-grounding the confirmation update | Critique given, no code. The proposed factorisation, `prior_mean = pi x theta_present` with confirmation bearing only on PRESENCE, is right and removes the ad hoc 0.9-quantile target; it also unifies mixture and ordinary rows. THE MAIN FINDING is the evidence quantity, not the functional form: the `support` fed in is a POSTERIOR share (the code aggregates each observation's best posterior support), so the prior enters the evidence and the evidence then raises the prior. Noisy-OR amplifies that loop where the current rule only leaks, because it saturates exponentially in n. Measured on a worked case: at a site whose prior already favours A 0.5 to 0.01 with non-discriminating likelihoods, every observation's support is about 0.98 with no sequence information in it, and ten such observations take the prior from 5e-3 to its ceiling, against roughly 8.3e-3 under the current rule. a0 CANNOT fix this: it is a uniform multiplier that delays saturation by a constant and never prevents it, which is the same shape as the already-recorded fact that down-weighting a whole group buys no uncertainty discount because effective sample size is scale-invariant. A Beta-Binomial on the expected count does not fix it either, since the confusable-pair case is MUTUAL EXCLUSIVITY, not non-independence, and no model built from independent per-observation evidence can express that evidence for A is evidence against B. RECOMMENDED, one move fixing both: make the confirmation evidence LIKELIHOOD-based rather than posterior-based, weighting each observation by how much the sequence discriminated, so an observation at 0.5/0.5 contributes nothing and an observation decided by the prior contributes nothing. That is the same derivation as the prior-decided flag, so one quantity serves both. Also flagged: theta_present's definition is load-bearing, not an open detail (same prior_mean and evidence give a 56x or a 1.6x response depending on it), and the hard theta_present ceiling is the one respect in which the proposal is WORSE than the current soft target, since an underestimated theta_present silently caps correct local evidence and a bound value looks like a computed one | CLOSED 2026-10-12: answered by `abaa60f` + `b921c00`; the magnitude residual is bounded, not re-grounded |
| DESIGN: assignment grain = prior grain (ASV x site) | Asked by the maintainer through two chats; my opinion given, no code. YES, with the prior-decided flag as a PRECONDITION rather than an addition. The argument neither chat made is the strongest: per-site grain puts every observation in exactly one group, so `update_prior_from_consensus()`'s cross-group averaging collapses to k = 1 and the equal-weight-versus-precision approximation STOPS EXISTING on this path instead of being worked around. The pressure test that makes the flag a precondition: at a thin site with equal likelihoods and priors 0.5 against 0.01, the per-site posterior is 98 percent, and that 98 percent contains ZERO sequence information; it is the prior renormalised and reported as a species call, where pooling would have said genus, wrong but honest. THE NUMBER TO MEASURE BEFORE COMMITTING, one query over existing columns: of the 1,556 multi-site ESVs, how many become species-level per-site, and of those what fraction have a winner-to-runner-up likelihood ratio near one. My four answers: (1) document the principle, and state `combine_multisite_priors()`'s precondition exactly, that pooling is lossless only when the prior RATIO among the candidate set is constant across sites, and give a per-ASV diagnostic for that spread rather than a blanket rule; (2) yes, and cheap, since `winner_prior`, `winner_likelihood` and `consensus_discrimination` already exist and the flag is a derivation from them; (3) NO, keep `add_slash_taxon()` irreducibility dataset-wide, because it is a property of the MARKER and making it site-local would conflate "the sequence cannot separate these" with "the prior separated them here", destroying what the flag exists to carry; (4) yes, the likelihood-only consensus is the cleanest item and is the prior-independent product, which priors moving under a GBIF refetch do not disturb | CLOSED 2026-10-12: settled in the workflow (ASSIGNMENT_GRAIN esv_site, 2026-10-01); combine_multisite_priors does not run |
| BEHAVIOUR CHANGE: `update_prior_from_consensus()` pools evidence WITHIN groups | LANDED. Confirmation evidence was pooled study-wide, so a detection at one site raised priors at every other site. New `detections`, `group_cols` and `marker_col` make the mass, the leave-one-out subtraction, the support-weighted target and the occurrence ceiling all per group. No new exports. THE BREAKING PART, and it is the right direction: with `detections = NULL` the call is now REFUSED when `result` carries multi-site combined priors, where it used to silently pool across sites. A single-site call still works with an informational message. Verified against the merge, not the branch: TaxaAssign 891 pass / 0 fail (the author saw 949 with live tests on), CI invocation 0 errors on TaxaAssign and TaxaMatch. The author also measured the one-group path identical to main on 156,230 real rows, max difference 0. DESIGN POINT, asked by both chats and confirmed: a row in k groups gets the equal-weight MEAN of its per-group gains with singleton groups counting as zero, and k is the number of groups THAT OBSERVATION appears in, not the number in the study. That is arithmetically consistent with a combined prior that is itself an average over sites. Its one stated approximation matters and is now cross-referenced: `combine_multisite_priors()` weights sites by PRECISION and those precisions are not carried on the combined row, so an equal-weight update under-credits corroboration from a data-rich site and over-credits a data-poor one. That is the same gap as the open precision-weighted-combination item, and the two should be fixed together rather than separately | the reinstall, then `llm_prompts/CONTEXT_TaxaAssign.md` regenerated (it still describes the old spatial_group_map semantics) |
| Branch `reference-memory-estimate` (`69e5b3f`) | LANDED (see the counts-path row). Its worktree is still held by the author session, so the branch ref cannot be deleted yet; that is bookkeeping, not work |
| PtCon 12S B2 run | staged (`TaxaID_dev/.../b2_runs/`), driver passes `max_per_genus = NULL` | maintainer's go |
| Cache refetch, TWO causes, ONE refetch if sequenced right | (1) A2 `53f4143` (by design, stays): a cache file with no recorded selection settings is a miss, so every pre-A2 project (PtCon 12S 222 genera, PtCon 18S ~1,400, GreatLakes, Mugu) refetches once at its next Step 7; CalIntertidal is NOT affected (cache built after A2, record present, checked on disk). (2) The memory-estimate branch stores uncapped metadata, so a file written under a cap refetches once more even with the record. Land that branch FIRST, reinstall, then let each project refetch once. The PtCon 12S retention re-run is HELD at Step 7a (backup of 47 outputs made; nothing modified) | maintainer: the memory-branch decisions, then the order |
| README rounds | all carried to main, latest `fdb9de1` (the error-categories prose: scores mistaken for probabilities, blank-based removal contrasted with conventional practice, a continuous spatial prior contrasted with filtering on a regional list, the mislabel rate attributed to NCBI). The shared checkout's working copy still holds that round uncommitted and its branch is behind main, so it will conflict on its next pull; discard the working copy there, main has it | maintainer's next round (tell the screen first) |
| Adaptive genus cap | tracked proposal, not accepted; grid owns the fit; workflow deletes its constants when the package function lands | the memory branch |
| Unidentified | "expanded path length 1024" file.exists warning in long CalIntertidal runs; not from TaxaLikely | a caught call site |
| Pre-security-review submission | no tag, no bump; WERC official path later needs a `1.0.0` branch | VERSION MISMATCH FIXED 2026-10-12: all nine NEWS said 1.0.0 against DESCRIPTION 0.1.0; aligned DOWN to 0.1.0, consistent with the recorded 'no tag, no bump'. maintainer: when to bump and the 1.0.0 branch |
| Production workflows edited for pair retention | eDNA `e621fd6` (PtCon 12S, 18S, Mugu, retired template) and GreatLakes `0c6309b` pass `pair_retention = "best_per_partner"` + `min_pair_coverage`; NOT runnable until the reinstall; then run `TaxaID_dev/diagnostics/workflow_checks/check_stale_arguments.R` on the five files and one cheap real re-run (PtCon 12S) | the reinstall |
| TaxaWizard snippet `refs_to_matrix.R` | calls `build_sequence_matrix()` with defaults only (whole-set alignment, full table); should it carry the production choices (`by_genus = TRUE`, `max_foreign_reps_per_genus = 20L`, `pair_retention = "best_per_partner"`, `min_pair_coverage` matching the training floor)? | maintainer |
| Supplemental methods style | TaxaLikely's carries 96 em dashes (TaxaAssign's and TaxaExpect's carry 0); the README rules were never applied to these files | maintainer: sweep or leave |
| Branch `gbif-facet-priors` (`be9e62f`, one-site wording added at the maintainer's request 2026-09-26; "count based priors" chat) | THREE NEW EXPORTS (`TaxaFetch::fetch_gbif_occurrence_counts()`, `TaxaFetch::plan_gbif_fetch()`, `TaxaExpect::estimate_kernel_priors_from_counts()`), one new arg (`estimate_kernel_priors(count_col =)`, NULL keeps behaviour), one RENAME (`fetch_inat_occurrences()` -> `fetch_inat_occurrence_counts()`, separate commit `9a05644`, no caller outside TaxaFetch/TaxaExpect); reviewed detached against the branch's own library: TaxaFetch 866/0, TaxaExpect 763/0, check 0/0/0 both, READMEs complete, review-response rows in; `ecosystem_docs/HANDOFF_counts_path_prior.md` on the branch belongs in TaxaID_dev; install order TaxaFetch before TaxaExpect | CLOSED 2026-10-11: verified already in `main` (ancestry checked against `02eadbc`) |
| Bimodality warning | DONE: fast-forwarded to `b11814f` (maintainer's go in the optimize-matrix chat); `.bimodality_check()` detects a point mass at the ceiling from repeated raw values and fills `explanation`; `calibrate_query_noise()` gives that reading instead of the platform advice; reviewed detached: TaxaLikely 1431/0, check 0/0/0; review-response row in | the reinstall |
| CalIntertidal workflow (CLOSED: retention lines committed by that chat; the session-local library prepend removed after an identical shared-vs-session BLAST test) | its retention lines sit uncommitted in that chat's working tree with ~920 lines of its own Section 7 work; that chat commits its own file; `MAX_SEQS_PER_GENUS` set to NULL there by the maintainer's decision (uncommitted with that chat's Section 7 work; that chat commits) | that chat's commit |
| CalIntertidal production findings (11, `eDNA/CaliforniaIntertidal/PACKAGE_REVIEW_FINDINGS_2026-09-27.md`) | LANDED `74bc886`: TaxaWizard `annotate_script(mode = "llm")` (positional `llm_fn`, `max_tokens` sized to the prompt, `...` forwarded), `workflow_check()` blastn version + capability note, `sniff_input()` PercMatch and the one-row-per-observation rule, parameter detection of every top-level constant (TaxaWizard 1155/0); `blast_sequences(method = "local")` had never worked (duplicate `-outfmt`), fixed with a test (TaxaMatch 1372/0). TRACKED, not built: `taxa_lineage` silently orphans a name-keyed cache (add a loud message naming the file count); `audit_barcode_coverage()` is a 3-hour I/O-bound tail with possible network calls (batch the reads or make it opt-in, a later release that does not exist); advertise `corroborate_references_locally()` in TaxaMatch's README (removes 53% of the BLAST workload in 0.3 s); lineage-guard report split by whether the disagreement crosses a higher rank; the two memory findings are in the memory brief | maintainer for the tracked four |
| Proposal: static input-availability check for workflow scripts (proposal, not accepted) | From the CalIntertidal chat: Section 8 of its workflow had NEVER executed and hid five defects of one shape, "a step consumes something no upstream step produces" (a renamed list component, two objects assigned nowhere, two per-site tables used as if per-observation). Smaller version first: a lint that flags any symbol a script uses but never assigns and no attached package exports (the wizard's segmenter already classifies every top-level expression); the full version lets graph edges declare produced and required COLUMNS. Screen's view: the lint is cheap and would have caught three of five; the column graph is a proposal nobody has accepted. Also: `evaluate_likelihoods()` reports dropped observations via `warning()` (swallowed into "50 or more warnings" on big runs); `$unresolved` is returned, but a `message()` naming the count is the better channel. Measured on the 3-marker run: COI drops 141 of 13,170 observations, 18S 209 of 5,825, 12S none; the cause (candidates with no usable reference at the requested rank?) is unverified | DECIDED 2026-10-11: NOT 1.0 -- revisit after the release |
| Finding 24: cross-backbone synonymy in the consensus output | The consensus is GBIF-named; every conventional assignment (Jonah Ventures, top hit) is NCBI-named, so a method comparison counts every backbone synonym as a disagreement (19 true differences in 16,923 rows, all same-organism-different-name; the test is set membership, not string equality, and the mapping is one-to-many). Workflow-side shape built by that chat: `consensus_taxon_ncbi` (pipe-delimited), `n_ncbi_names`, `backbone_name_differs`, from the match objects' own name pair, no network. Candidate: `posterior_consensus()` emits them, or TaxaAssign documents the post-step; a node's backbone as a graph attribute belongs with the edge-columns proposal. That chat's local accession screen is PAUSED (300x over-scoped against core_nt; handed to its own chat), so the findings on `investigate_flagged_accessions()`/`review_flagged_accessions()` on real input are later | DECIDED 2026-10-11: NOT 1.0 -- revisit after the release |
| Finding 26: harmonisation coverage per lineage | `harmonize_ranks_to_gbif()` reports pooled coverage (class 98.6 percent) while GBIF has no class node for ray-finned fishes, so `gbif_class` is NA for every Actinopteri row and a consumer preferring the column wholesale lost the largest class at a site. Package ask: report coverage PER LINEAGE (or flag any rank whose blanks concentrate in one clade), and document per-row coalescing | DECIDED 2026-10-11: NOT 1.0 -- revisit after the release |
| Local BLAST database consistency (from the mislabel-screen chat, relayed) | The user's `core_nt` is a MIXED SNAPSHOT: 73 of 91 volumes from one NCBI build, the rest and the index files from another; every per-volume checksum passed, yet accession and taxid lookups return the wrong records (a per-volume checksum cannot report that the SET is inconsistent, the same shape as three earlier findings). Screen verdicts from that database are untrustworthy until refetched. Package ask, rated high by that chat: a cheap consistency check in `blast_sequences(method = "local")` (one build date across volumes; alias count against the remote build), because the failure returns confident wrong taxonomy, not an error. Docs now carry the caution (`blast_sequences()` method) | DECIDED 2026-10-11: NOT 1.0 -- revisit after the release |
| Development records in the released repo | `HANDOFF_index_hopping_filter.md` and `REENTRY_PROMPT_homonym_detection.md` moved to TaxaID_dev (`61df749`). STILL TRACKED and must not ship: `ecosystem_docs/REENTRY_PROMPT_prepublication_screen.md`, this document; move it at submission time, not before, since every session references it | submission |
| Identity gate: three changes requested after the merge | lafferty-09 asked 2026-09-28 to HOLD `sample-identity-gate`, which had already merged at `82d3bd0`. Not reverted: these are behaviour changes to a function that now exists, and a revert would also unpick the TaxaFlag README section, the Software Inventory row and the review-response arithmetic. To land as a follow-up on main: the samples were NOT spiked; the blanks are tap water; a thin study (no blanks, few samples) gets a "no evidence of a problem" status rather than a block. Asked that chat to confirm from the maintainer directly whether that status is a new level or a re-labelling, since that decides whether the returned column gains a level | that chat's follow-up branch |
| eDNA `template-counts-path` (`149c212`) | UNBLOCKED by the reinstall, and NEITHER mine nor the CalIntertidal chat's to merge; that chat has put it to the maintainer. If it goes ahead it goes through `git worktree add`, never a branch switch in the shared checkout, because other sessions are working in that tree. NOT mine to merge. It is 10-plus commits ahead of the eDNA `master`, and the substance is the workflow work itself (per-group kernel fits, the dedupe rebuild, the theta surfaces, the retention lines, then the template's records-or-counts switch), not a small carry. The shared eDNA checkout is on `workflow-ptcon-multisite` with uncommitted CalIntertidal files in it, so switching branches there would disturb another chat's working tree. The CalIntertidal chat owns that repo and owns this merge | that chat |
| Branch and worktree cleanup | `gbif-facet-priors`, `reference-memory-estimate` and `llm-pathway-audit` deleted; the last two had scratchpad worktrees from sessions that have ended, both clean and fully landed, so they were pruned. The remote holds only `main` and `jv-bracket-consensus`, so none of this needed a remote delete. STILL HELD, deliberately: `sample-identity-gate` (lafferty-09's follow-up), `local-comparison-subset-db` (lafferty-dd, in progress), and `flag-failed-libraries`, `flag-hopped-detections`, `local-blast-throughput`, which are clean and fully landed but sit in named worktrees whose owners I did not confirm; removing them loses nothing but would surprise a live session, so they wait for a word from their owners | a word from those owners |
| Subset-database extraction: merged records, and an invisible fallback | LANDED as a follow-up to the row above, found by the live run rather than by review. `core_nt` stores identical sequences as ONE record carrying every accession's defline, so asking `blastdbcmd -entry_batch` for two such accessions returned that record twice under the first accession's id, the database build rejected the duplicate, and the search fell back to a full pass. Fixed with `-target_only`, which labels each copy by the accession actually requested; the real case was *Ronquilus jordani* FJ264437 and FJ264280. The test's stand-in emits the duplicate unless the flag is passed, so removing the flag fails the test. SECOND finding, and the more general one: that fallback warned correctly and NOBODY SAW IT, because `Rscript` defers warnings to exit, so a silent swap of a sub-second extraction for a roughly 20-minute full pass surfaced only after the run. It now emits a `message()` as well as the `warning()`. The same shape is already tracked for `evaluate_likelihoods()`, which reports dropped observations via `warning()` and disappears into "50 or more warnings" on a big run; that one is still OPEN | LANDED; informational |
| BEHAVIOUR CHANGE: `resolve_review_overrides(resolution_rank = "order")` | LANDED, and it CHANGES RESULTS, so it is flagged rather than buried. A marker's resolving power can only fail between close relatives, so a `poor_marker_resolution` or `sister_family_thin_coverage` explanation now overrides a removal only when the accession still agrees with its hits at order or finer. An accession kept under the old rule on a coarse agreement is now removed. Motivating case: nine *Lutjanus johnii* 12S records sharing only CLASS with their hits, 80 to 85 percent identical to both *L. johnii* mitogenomes, kept on a moderate-confidence "poor marker" review. `NULL` restores the old behaviour. Verified not vacuous: `finest_common_rank` is a real produced column, and the test covers class denied, order allowed, a non-resolution explanation unaffected, NA denied, `NULL` disabling, and the column absent. CONSEQUENCE FOR THE MAINTAINER: any reference screen whose kept-accession list was produced under the old rule may differ if re-run, which is a decision about consistency across sites, not a code question | LANDED; informational, and it changes results |
| Retry asymmetry left as the author's call | `.resolve_taxonomy()` now retries five times with exponential backoff, while `.resolve_taxonomy_by_acc()`'s own accession lookup keeps three attempts at 2 then 4 seconds. The HTTP 500 that motivated the change could hit either path, so the reasoning applies to both, but raising it changes timing on a path nobody has measured. Not changed by me; raised with the author | that chat |
| 18S V9 primers registered (`register-18s-v9-primers`) | LANDED. `TaxaTools::barcode_primer_defaults` gains `18s-v9` (1389F/1510R, Amaral-Zettler et al. 2009) with a matching length window and an `18s-v9` to `18S` marker mapping, so one term serves both primer trimming and the NCBI search. Verified in silico against three real 18S genes, every stripped product ending in the same 3' sequence carried by real 18S environmental sequences, which is how the pair was identified. The trap the author's own tests caught is the interesting part: `resolve_barcode_primers()` resolves by unique PREFIX, so registering one 18S region made a bare `"18S"` silently resolve to V9, which would have trimmed a V4 study's references with V9 primers without a word. A bare `18S`, `ITS` or `ITS2` now refuses prefix resolution once a region is registered, and the error names the regions. I checked the regression risk rather than assuming: a bare term ALREADY errored before this change and every caller in the ecosystem wraps the call, so the paths that leave an unregistered marker untrimmed behave exactly as before; bare `18S` length resolution is also unchanged at 100 to 2000. TaxaTools 1223/0, TaxaMatch 1423/0. The accession lookup also gets the five-attempt backoff, closing the asymmetry | the rebuild, held for the live 12S top-up |
| OPEN: does the WoRMS-habitat refusal carry from the gate to `flag_contaminant()`? | The maintainer declined a WoRMS-habitat variant for the identity GATE, which answers "is this blank usable?" using only what exists at ingest. `flag_contaminant()` answers a different question, "may this taxon be removed?", at a different point in the pipeline. A decision on one does not automatically carry to the other, and neither chat is assuming it does or does not. Raised with the maintainer directly | DECIDED 2026-10-11: NOT 1.0 -- revisit after the release |
| Finding 30: `flag_contaminant()` has no notion of WHAT a taxon is | Raised by the maintainer, measured by the CalIntertidal chat, NOT built. MECHANISM (survives, and is the point): a field blank missing its three fresh-water rinses keeps residual SEAWATER from the site, so the blank carries the site's own community. A target-group taxon in a blank is therefore explained by carryover from a place it genuinely lives; a non-target taxon in a blank is not. The score, `field_rate/(field_rate + control_rate)`, cannot tell them apart. WHICH NUMBERS STAND, after that chat tested its own classifier and found it fails: the named losses are real and are the strongest evidence, since they are identified by NAME, not by a lineage rule (*Ulva*, *Schimmelmannia schousboei*, *Hypnea*, *Chondracanthus canaliculatus*, four *Mazzaella*, *Microcladia coulteri*, *Smithora naiadum*); so are the scope-removal fractions, 99.1 percent of real contaminant reads on 18S, 20.8 on COI, 0.0 on 12S, which is the argument that HABITAT and not a proxy is what is wanted; and so is the observation that every non-target read surviving scope is a FRESHWATER species in a MARINE study. WHICH DO NOT: every "target-group" magnitude, including "macroalgae in 30 of 30 blanks at 3.50 percent", the 167 and 102 ESV counts, and the 40-to-1 harm-to-benefit ratio built on them. They came from a phylum rule with BOTH error directions: Jonah Ventures leaves brown algae at `unk_phylum`, so kelp was never counted at all, while plankton (*Pycnococcus provasolii*, 2,465 reads in 21 blanks), a sea pen and a freshwater oligochaete were counted as target. The direction of the error is not even one-sided, so the ratio cannot be repaired by adjustment. PROPOSAL, now LARGELY CLOSED by the maintainer's decision that habitat is out of contamination flagging entirely (see the row above): not a target SHARE but a CONTRADICTION was the proposal, and habitat was the instrument the measurement pointed to, so removing habitat leaves the shape without a demonstrated source. A caller-supplied logical column plus a separate verdict for a removal resting on blank evidence alone remains buildable, but only a caller with outside knowledge can populate it. The sketch is marked superseded and is not wired | DECIDED 2026-10-11: NOT 1.0 -- revisit after the release |
| Finding 29 stands, but no longer blocks the identity gate | `SCOPE_DEFAULT_BUCKET = "macroinvertebrates"` sits inside `SCOPE_IN_GROUPS`, so every unrecognised lineage lands in a target group. Measured: a known-CLEAN blank scores 64.6 percent "target", above known-contaminated blanks at 50 percent. A default bucket that is also an in-scope group makes "is this in scope?" unanswerable for anything unrecognised, which is a defect in its own right and still OPEN for `flag_contaminant()`. It is NOT what blocks the identity gate; see the row below, where the maintainer ruled out the whole approach on other grounds | DECIDED 2026-10-11: NOT 1.0 -- revisit after the release |
| A consensus LABEL is not reproducible from saved inputs | FIXED, after being investigated rather than accepted at face value. The 12S stage_B run reproduced Round 1's posteriors exactly (37,554 rows, max difference 0) but one label changed on identical posteriors, and the screening chat reasonably inferred a `posterior_consensus()` behaviour change. IT WAS NOT: none of the three sources of a consensus label had changed since that run, checked against git. The real cause was that the label for an UNREFERENCED taxon came from an uncached LIVE service call made at run time, so a batch that failed transiently produced NA, and the retry added in `d9f0153` resolves the same name now; NCBI was separately measured failing about half its requests in that window. THE FIX: `verify_taxon_names(cache_dir =, cache_ttl_days =)` writes one file per answered name and NEVER writes a failure, so a cached non-answer can never be served as an answer; the key is the name plus everything that can change what it resolves to, including `decisions` BY CONTENT and a decisions file by its md5, while `batch_size` and `timeout_sec` are excluded because they cannot change a correct answer; the TTL exists so backbone updates reach a long-lived cache. `posterior_consensus()` gains `unreferenced_taxonomy_lookup` (matched / not_found / lookup_failed), taken as the WORST per observation so an `== "matched"` filter can never keep a failure, which is the `verified` versus `matched` lesson applied at design time instead of after. A failure messages as well as warns. Third instance of the absence-as-evidence family, and now the third one closed. TaxaTools 1237/0, TaxaAssign 864/0 | the rebuild, held for the live 18S screen |
| `build_sequence_matrix(seed = )` BUILT, at the maintainer's approval | The draws behind `max_seqs_per_taxon`, the per-genus representative and `max_foreign_reps_per_genus` decide which sequences train the calibration, and therefore every likelihood resting on it. The old contract asked the caller to `set.seed()` beforehand, stated in four roxygen places; measured across FIVE production call sites, none honoured it, and CalIntertidal appeared to while not doing so, holding a seed for this call that was dead code inside a block gated on a constant set to NULL. A seed now fixes the draws inside the call and hands the caller's RNG stream back untouched. THE DEFAULT STAYS NULL, and not for compatibility: `check_cross_genus_sampling_noise()` calls this function repeatedly to MEASURE how much the representative draw moves the estimate, so a fixed default seed would make every replicate identical and it would report zero noise, a plausible wrong number rather than an error. An unseeded build that will draw now says so, stating what is certainly true rather than guessing, because R cannot distinguish a deliberate `set.seed()` from an initialised stream. TaxaLikely 1531/0. The five workflows can now pass `seed =` instead of relying on a convention none of them kept | the workflow chats, to adopt it |
| `validate_controls()` power verdict depended on the RUN, not the data | Found by the identity-gate chat, fix on the held branch. Above `max_null_pairs` (500) the null distribution was an UNSEEDED subsample, so the power verdict for a large site was drawn afresh each call. Measured on CalIntertidal: 32 COI JVB3506 units and one blank (JAC2V5IK 12S) flipped between IDENTICAL calls, and this explains three different "admitted without a discriminating test" counts, 461, 493 and 793, quoted across sessions and all believed at the time. This is NOT gate-specific: it reaches every `validate_controls()` caller on a site large enough to trip the subsample. Fix is a fixed local seed with the caller's `.Random.seed` restored, pinned by a test on both halves. FOURTH member of the family where a result depended on something other than its inputs, after the two TaxaMatch fetch failures and the consensus label, and the only one whose symptom was a NUMBER PEOPLE QUOTED rather than a missing value | with the held branch |
| Sweep: the `ifelse()` length trap elsewhere | `ifelse()` returns the length of its TEST, so a branch that can yield a length-1 value silently collapses the result. Swept all nine packages for a variable assigned `if (...) vec else NA*` that then feeds an `ifelse()`. ONE further instance, in `assign_taxa_llm()`'s prompt builder, and it is HONESTLY benign: `sprintf()` recycles a length-1 argument so every row correctly received the empty string. Fixed anyway, because the LENGTH depended on whether a column existed, which is exactly the shape that bit `.sig_dominance()`. The CalIntertidal chat reports hitting the identical bug in its own helper, so this is three occurrences in one project. `dplyr::if_else()` errors on a length mismatch and would have caught all three; worth considering as a house rule | CLOSED 2026-10-12 by triage, not a sweep: 1 hit on a guaranteed-scalar test across all nine packages and it was SAFE (both branches scalar); converted to `if`/`else` so it stops reading as the trap|
| Memory branch resolution note | its `.matrix_structure()` should use the retention-aware pair formula (TaxaID_dev/ecosystem_docs/DESIGN_seq_matrix_pair_retention.md, Section 6) | the screen session, at resolution |

**22 closed rows moved out on 2026-09-28** to `TaxaID_dev/screen_records/prepublication_screen_2026-09-20/board_closed_items_2026-09-28.md`. The board had reached 59 rows and a reader could no longer tell live work from history. What remains below is live: every row names somebody.


**On release vocabulary, settled by the maintainer 2026-09-29.** THERE IS NO
1.1 AND NOTHING IS DEFERRED. All work in this session goes into 1.0. Earlier
rows used "1.1" as my shorthand for "deferred", compounded by a peer's relayed
wording; I had no authority to scope a release and never claimed any, and the
shorthand was wrong twice over, because "deferred" implies a later release to
be deferred TO. Corrected throughout. The only two categories are: work that
EXISTS, which goes into 1.0, and PROPOSALS NOBODY HAS ACCEPTED, which are not
scheduled work at all. A proposal is not a deferral.

Note on the older sections: Stage A and Stage B text written on 2026-09-20 also
uses "1.1" in three places (a tidy-up item, a zero-external-caller goal, and a
tracked-not-built list). Those predate this session and record earlier planning,
so they are left as written rather than rewritten, but per the maintainer they
are STALE and a reader must not treat them as a roadmap either. My shorthand
picked up the document's own vocabulary, which is how it spread without anyone
deciding it.


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
| `RULES_OF_ENGAGEMENT_agents.md` | the 19 constraints every session works under; read before a pass, not after |
| `AUDIT_prerelease_findings_2026_10_10.md` | the post-publication read-only audit; four findings, each naming the decision it needs |
| `ARCHIVE_screen_run_log_2026_10.md` | this document's own 2026-10-04/08 run log; a record, never an open item |
| `llm_prompts/CONTEXT_*.md` | the generated API surface, regenerated from the installed packages; trust it over memory |

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

- **18S V9's poor species discrimination is a property of the marker, not a
  training artifact** -- MEASURED, 2026-10-04, no longer assumed. A/B over
  untrimmed / region-matched / augmented+region-matched training: single
  competitive species within 10:1 at 27.4 / 31.1 / 27.6%, median top-two
  likelihood ratio 1.12 / 1.17 / 1.14. Region-matching the references does not
  improve species-level resolution, so the limit is the molecule.
- **Region matching and reference augmentation are a PAIR; neither works
  alone.** On CalIntertidal 18S the name-and-marker fetch returned mostly
  non-V9 records, so matching alone discarded most of the usable set and took
  the share of observations won by a referenced species from 10% to 1.6%
  (zeroed rows 11.7% to 30.7%). With the match object's own accessions added
  first, coverage returned (12%). Report them together or not at all.
- **Two measured biases still deflate within-species spread**, both in the same
  direction (making the model overconfident): match-object pairs carry ~60% of
  fetched-pair variance (4.7% of within-species pairs; now guarded by dropping
  them only where the species also has a fetched pair, so no species loses its
  estimate -- the strict rule would have stripped 143 18S and 587 COI species),
  and region mislocation, where 34% of 12S and ~73% of 18S training references
  were off the query region. The `h1-spread` defaults were fitted on data
  containing both, so **re-measure the spread and the calibration offset before
  publishing anything downstream of them**. A third candidate -- duplicate
  accessions fabricating perfect pairs -- was investigated and is VOID; the
  dedupe is upstream of alignment.
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
- Deciding an export is unused takes FIVE searches, not one. A census of the
  production workflows answers none of these on its own, and three removal
  calls on 2026-10-11 were wrong until each was checked: (1) cross-package
  call sites -- `new_report_section()` is called by seven packages'
  `report_*()` functions; (2) intra-package call sites --
  `estimate_sequence_matrix_size()` by `fetch.R`, `annotate_script()` by
  `workflow_app()`; (3) accepted INPUT CLASSES -- removing
  `suggest_unreferenced_species()` orphans a class four live functions take;
  (4) the external workflow directories, which are outside this repo and are
  where `consensus_method = "credible_node"` was hiding, live in CalIntertidal
  by the maintainer's own decision, while a repo-root grep showed zero
  callers; (5) ARGUMENTS, separately from functions -- the 227 exports carry
  1,641 arguments, and an exports diff cannot see any of them.

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

**SUPERSEDED for everything still outstanding, by the maintainer's decision of
2026-10-10.** The table above is the record of how Stages A and B were run; it is
not the plan for what remains. There is **no agent fan-out** for the rest, for a
stated reason: the remaining items are not independent. Cleaning up package
changes, sweeping for debris and making commits all change the tree that a
function-listing, code-review or security pass would be reviewing, so a parallel
fan-out would review a tree that no longer exists -- the same defect that made
every Stage B result from 2026-09-21 describe a vanished tree (section 0a). Two
of the remaining items are also not agent work at all: validating on Mugu and
Great Lakes is a run, and the final look is a fresh session with a fresh prompt.

The approved order is therefore sequential: **audit, clean, re-audit, run, fresh
eyes, push last.** Push is last because a push is outward-facing and gated; it
does not move until the tree it publishes is the one that passed.

## 11. Definition of done

A written statement that Stage B ran against `pre-1.0-freeze` (and names the
commit of every post-tag package re-run), against named commits in the two
workflow repositories, with NCBI healthy, and found nothing material. Anything
less is a status report, not a pass. This document then leaves the repo with
the rest of the dev material.

**Added by the maintainer 2026-10-10: validation on Mugu and Great Lakes is
INSIDE this gate, not after it.** CalIntertidal is the site every recent change
was measured on, so passing there shows the changes work where they were fitted,
not that they generalise. Mugu is the multi-marker instance and Great Lakes
carries the only held-out benchmark in the project (Lamar precision 0.872), so a
regression at either is a 1.0 blocker rather than a later finding. The gate is
not met by a clean screen on CalIntertidal alone.

The screen's own purpose is upstream of this: what it produces is the
pre-submission package for the USGS technical code review and domain review (see
the statement at the top of this document). "Found nothing material" means
nothing a reviewer would raise.

## 12. Export surface pruned (2026-10-11, merged `a6d7ca7` and `b31f188`)

The maintainer's framing, which is the standard to apply to any future export:
the package is already too large for a user to understand well, so a function
earns its place only if a workflow uses it, or it was validated and the result
held, or there is an obvious use nobody has reached yet. A function tried
against a problem and then abandoned goes; a function written for a temporary
internal task goes; a validated function with no workflow caller may stay.

**Removed, nine exports, 232 -> 223.** `correct_training_bias()` (TaxaLikely --
ships at `tau = 0`, which is no correction, because every calibration run found
that exponent optimal, so it had no setting at which it changed a result);
`theta_surface_at()` (TaxaExpect); `verify_local_corroborations()` (TaxaMatch);
`model_cache_info()` (TaxaTools); `build_scheme_prompt()`,
`parse_scheme_response()`, `build_iucn_scheme()` and the orphaned
`print.scheme_prompt()` (TaxaHabitat -- the LLM habitat-scheme generator; the
shipped IUCN scheme and the three-realm default are what callers use); and
`run_bayesian_pipeline()` with `run_llm_pipeline()` (TaxaAssign). The two
wrappers were the advertised front door and no production workflow called
either: of nine current subsystems, SEVEN were absent from them -- the whole
reference screen, `calibrate_query_noise()`,
`restore_suppressed_candidates()`, `apply_undetected_evidence()`,
`compute_group_priors()` and `annotate_reference_support()`. Keeping a second
definition of the pipeline is what let it drift, so everything that advertised
a wrapper now shows the sequence instead, TaxaWizard's two consensus snippets
included. `-60 arguments`, 37 of them on `run_llm_pipeline()` alone.

**Kept deliberately, and not to be re-proposed without new argument.**
`new_report_section()`, `build_report_context()`,
`estimate_sequence_matrix_size()`, `taxaid_build_manifest()`,
`annotate_script()`, `refresh_models()` and `example_habitat_scheme` all have
real callers (see the five-search note in section 9).
`suggest_unreferenced_species()` is kept THOUGH IT NOW HAS NO CALLER AT ALL: it
is the only producer of the `unreferenced_species_result` class that
`posterior_consensus(species_reference=)`, `generate_report()`,
`assign_taxa_llm()` and `TaxaLikely::expand_unreferenced_hypotheses()` accept
as input, so removing it orphans a class four live functions take and means
surgery on `posterior_consensus()` inside the freeze. Maintainer's decision:
keep.

**Verification.** `R CMD check --as-cran` 0 errors on all seven touched
packages, warnings and notes the standing CRAN-incoming ones; 0 test failures
across the nine (TaxaLikely 1986, TaxaAssign 1257, TaxaMatch 1498, TaxaTools
1353, TaxaWizard 1164, TaxaExpect 750, TaxaHabitat 563). All nine reinstalled
from the branch and checked against the INSTALLED namespaces, not the source.
`llm_prompts/` regenerated afterwards, since it is generated from the installed
packages.

**Still open from this thread.** Group 4 of `TRIAGE_board_2026_10_11.md`'s
successor analysis: the DataONE/PDF/literature subsystem (17 exports) is KEPT
by decision; `to_faire()` KEPT; the counts-path prior KEPT (validated within
10x for ~99% of species with `theta >= 1e-4` against the full record set);
TaxaWizard KEPT; the BOLD/CRABS/local-FASTA readers KEPT. A second pass on the
five widest functions' ARGUMENT lists has not been done.

### Decisions taken 2026-10-11, after the prune

**Group A is finished.** All eleven "merge?" rows resolved by measurement
against `main` at `02eadbc`: nine commits are already in `main`
(`f9462e2`, `909be70`, `0db7383`, `03d349f`, `c1ce9d6`, `f9127d1`,
`ccdfc7f`, `be9e62f`, plus the merge ledger); `3dd1f77` is superseded by
`7ae8785`, whose patch is a strict superset; and `6af4073` is the one real
item, deferred below. Those rows are marked CLOSED and need nothing further.

**Deferred past 1.0, maintainer's decision.** Nine rows, each an open
question with no implementation to review, or an unreviewed branch adding
an export under freeze. Marked `DECIDED 2026-10-11: NOT 1.0` in the board
and listed here so the reasons survive:

- splitting a coarse prior row's mass pro rata (proposed, not built)
- the static input-availability check for workflow scripts (a proposal
  never accepted)
- Finding 24, cross-backbone synonymy in the consensus output. Read before
  deferring: the comparison already works workflow-side, the real
  disagreement is measured at 19 rows in 16,923, and all 19 are
  same-organism-different-name. What is left is a convenience -- having
  `posterior_consensus()` emit the columns, or documenting the post-step.
- Finding 26, harmonisation coverage per lineage
- local BLAST database consistency (the row itself says "a later release
  that does not exist")
- whether the WoRMS-habitat refusal carries to `flag_contaminant()`
- Finding 30, `flag_contaminant()` having no notion of what a taxon is
- Finding 29, which the row already says no longer blocks the identity gate
- `clade-resolvable-rank` @ `6af4073`: adds an export, never submitted for
  review, found by listing branches. Preserved on tag
  `archive/clade-resolvable-rank`, so nothing is lost.

**`dplyr::if_else()` adopted as a house rule.** The `ifelse()` length trap
(it returns the length of its TEST, so a branch yielding a length-1 value
silently collapses the result) has now hit this project three times:
`.sig_dominance()`, `assign_taxa_llm()`'s prompt builder, and a
CalIntertidal helper. `dplyr::if_else()` errors on a length mismatch and
would have caught all three. Recorded in the coding conventions.

**The COI-Leray wrong-region defect: reported, not changed.** See the row
for the full measurement. `evaluate_reference_accessions()` now marks every
submitted query longer than the marker's target amplicon in a new
`query_over_amplicon` column and warns once per call with the count and the
median and longest submitted length. What gets submitted is deliberately
unchanged, because changing it would move every cached identity and force a
re-screen of four caches inside the gate; `params_key` is byte-identical,
so no cached row is invalidated. The real trimming fix -- gate on the
amplicon range, keep the reverse-complement search, extend
`query_trim_path` -- lands after 1.0 with the re-screen it needs, and 7.6%
of COI deposits (5,022 of 65,898) cannot be anchored under any fix, so even
then the screen will not be uniform.

### Decisions taken 2026-10-12: the four exports added under the freeze

**Ratified, all four.** Freeze rule 1 says a new export cannot land on `main`
without the maintainer's explicit yes. Four had landed since the tag; asked as
one question, answered yes to all four. The gate is now clear and the rule
holds going forward.

| Export | Package | Entered | Callers |
|---|---|---|---|
| `match_reference_region()` | TaxaLikely | `629b40e` | `stageA_region_lean.R`, the CalIntertidal multi-marker workflow (x4), `wf_section8_validation.R` |
| `annotate_reference_support()` | TaxaLikely | `068d6ff` | `extract_round2_priors.R`, `reference_support.R`, `archive_csv.R` |
| `add_unreferenced_prior_mass()` | TaxaAssign | `0ab8729`, via `complement` | the CalIntertidal multi-marker workflow (x4), `build_referenced_names_crosswalk.R`, `wf_section8_validation.R`, `three_arm_unreferenced_test*.R` |
| `flag_backbone_conflicts()` | TaxaFlag | board row 168/171 thread | `backbone_conflict_flags.R`, `regenerate_report_tables.R`, `archive_csv.R` |

Each meets the maintainer's own standard from section 12 -- a function earns its
place if a workflow uses it -- and each carries one or two test files. None has
an in-repo non-test caller, which is expected: all four are front-door functions
called from workflow scripts, not from inside the packages.

**Two of the four had no approval on record**, and that is why the question was
asked rather than assumed: `add_unreferenced_prior_mass()` entered through the
`complement` integration branch while arm (c), its machinery, was still HELD,
and `flag_backbone_conflicts()` had no yes that could be evidenced. The other
two were substantively approved when their threads closed. Ratifying all four
does not ratify arm (c): that remains held pending its re-measurement.

**This closes the export gate for 1.0, with one exception.** The export on
`clade-resolvable-rank` @ `6af4073` is NOT in this set -- it was deferred past
1.0 in the 2026-10-11 decisions and preserved on tag
`archive/clade-resolvable-rank`.

**The two surface numbers on this board reconcile.** 228 at `pre-1.0-freeze`,
plus these four, is the 232 that section 12's prune starts from; 232 minus the
nine removed is the 223 on `main` now. Neither figure was wrong.

### Decisions taken 2026-10-12: the Round-2 raise, and rows 194 / 198 / 201

**The Round-2 confirmation raise: scale bounded, comparators widened.** Both
merged on the maintainer's approval. The raise rescaled its target onto the
GROUP'S MAX `theta_mean` -- whatever taxon happens to be best recorded at the
site, unrelated to the row being raised. Measured read-only on R1009f: 414 of
13,808 species calls rest on a raised row and Round 2 CREATED every one of
them; the ceiling sat 487x-13,760x above a typical recorded taxon and produced
raises to 64,442x, median 1,535x -- while the raise those calls NEEDED was a
median 5x, and only 7 of 414 needed more. So:

- `max_raise_factor = 2000` (`abaa60f`) bounds a non-mixture raise at that
  multiple of the row's own prior. A measured bound, not a tuned constant: all
  414 calls survive it. Zero call changes.
- G4/G5's comparator set now includes the unreferenced hypotheses (`b921c00`).
  Cost: 37 of 414 calls fall to their own genus (21), family (15) or order (1)
  -- never off-lineage, never to no call. `Holothuria lubrica` is the only
  taxon that stops being named; four others lose one marginal call but keep
  their species x site. `Clupea harengus` and `Littorina littorea` fail the
  widened bar outright, which no scale bound could achieve: they overtake at
  2.3x and 3.5x, BELOW the 414's median need of 5x.

Two mechanisms were killed by measurement before any code: scaling to the
row's own theta (a TaxaExpect `prior_mean` IS `theta_mean`, verified at ratio
1.000 for every raised row, so the target collapses below the existing prior
and Round 2 switches off), and scaling to the taxon's regional theta
(Spearman(needed, cross-site ratio) is 0.23, and the per-site theta is already
the kernel-weighted regional estimate, so borrowing a far site's value undoes
the kernel). **What keeps cross-ocean homonyms out is the eligibility guards,
not the scale.**

**Row 194 -- CLOSED, from the code, no measurement needed.** The feared
mechanism was `combine_multisite_priors()` treating k duplicate copies of one
site as k independent sites. It is guarded at the source: the function
de-duplicates on the full (observation, candidate, site) key, aborts if
repeats disagree, and reports how many it dropped, with the rationale stated
("One site counts once"). That guard is `1441ba8`, which predates the R1009f
checkpoints; and at per-site grain the function is not called at all. The
row's "cheap decisive test" would return clean by construction. What survives
is the structural point -- match objects should not write `""` for an absent
rank -- which is tracked separately and is the maintainer's call.

**Row 198 -- CLOSED.** All three causes were already fixed: the
post-simulation ratio filter (`22655fc`), the redundancy-filter call
(`f14795b`) and `expand_unreferenced_hypotheses()`'s named-row rule
(`f30c68a`). The row's own "durable fix" is now merged too (`63a45fb`):
`.is_complement_type()` asks once what three filters each restated by hand,
which is what let the complement be lost three times. Behaviour-identical,
internal, NAMESPACE unchanged. The combined numbers change lands at the
batched re-run.

**Row 201 -- the convention taken, the instrument deferred, and the reason is
structural.** The proposed instrument is the posterior mass on the
unreferenced hypotheses, which is EXACTLY the quantity row 198's three fixes
change, so it cannot be validated against any artefact built before them. Its
stated validation target (86 clean against 291 prior-decided) also comes from
the superseded grain test; the live split is `prior_role` agrees 11,738,
narrowed 2,063, changed 7. It therefore waits for the batched re-run.

The row's reporting half IS taken (`ceb641c`): a new `@section` on
`posterior_consensus()` states what a per-site call is a call about. Of 233
sequences with any species-level site, only 18 are species at ALL of them --
215 are species at some and coarser at the rest, so this is the common case.
Three questions, three answers: what the SEQUENCE resolves
(`likelihood_consensus_taxon`, prior-independent), what a SITE resolves
(`consensus_taxon`, what the function returns), and the coarsest label
consistent across a sequence's sites, deliberately not computed because it
depends on which sites a reader pools. Documentation only; no export.

**PENDING RE-RUN LEDGER.** Merged and not yet re-run: the `fill_higher_ranks`
lineage keying (49 of 3,489 family assignments), `max_raise_factor` (0
changes), the comparator widening (37 of 414 calls), and row 198's three
complement fixes (every observation now carries its complement, so every
posterior moves). **Decision: the re-run is BATCHED** behind the remaining
numbers-changing rows, because these deltas do NOT compose -- family fills
feed the coarse-rank expansion and the unreferenced-mass scopes, the widening
changes which rows are raised, and the complement fixes change the candidate
sets themselves. One re-run, then ONE combined measurement at the published
unit. Code keeps merging as it validates; only the re-run waits.

**NEW, found while doing the above: pass A1 is incomplete.** The metadiscourse
purge left 27 instances of "previously", "no longer" or "legacy" in ROXYGEN
across eight of the nine packages (TaxaAssign 7, TaxaMatch 5, TaxaExpect 3,
TaxaFetch 3, TaxaLikely 3, TaxaFlag 2, TaxaTools 2, TaxaWizard 2). This is a
release gate by the freeze protocol's own terms. It needs TRIAGE rather than a
sweep: some are genuine version metadiscourse ("a schema this function no
longer reads"), others compare two SETTINGS rather than two versions ("with
the floor on, a call at 0.6 no longer resolves") and are legitimate. Code
comments are out of scope; the rule names roxygen, README, vignettes and NEWS.

### Pass A1 closed 2026-10-12 (merged `70ebbad`)

The metadiscourse purge had left 27 instances in roxygen across eight of the
nine packages. TRIAGED, not swept, because only eight were real:

**Fixed** -- genuine references to a former state of this code:
`posterior_consensus()` (a prior schema it "no longer reads"),
`assign_taxa_llm()` (a paragraph of history: "that ceiling is now 16000", "no
longer has to", "safer than it was", "the new ceiling"), TaxaWizard
`registry.R` ("schema (5): \value is no longer truncated"),
`estimate_kernel_priors()` ("chao_missing no longer sits in that formula"),
`update_prior_from_consensus()` (a column "kept for compatibility" because
"such rows are no longer raised"), `flag_contaminant()` ("no longer gets an
overconfident 0 or 1"), `literature_search()` ("this used to be a hand-rolled
character-sum fingerprint" plus "every previously-written" cache orphaned),
and `parse_habitat_response()` (a "deprecated" mode against the "current"
format).

**Kept deliberately** -- the other nineteen are not metadiscourse: "reopen a
previously drawn polygon" and "any row previously cached as" are the USER's
earlier actions; "the v3/v4 API no longer works", BirdNET's "equivalent legacy
default" and a `404 deprecated` error are EXTERNAL facts; "a call at 0.6 no
longer resolves" and "the row no longer corresponds to a single site" are
consequences of a SETTING. A `sed` sweep would have mangled all nineteen,
which is why this needed triage.

**THE REAL LESSON, and it should go into whatever script enforces the freeze:
the pattern list was the weak point, not the pass.** A1 was run against three
strings, and `literature_search()` leaked because it said "used to be".
Widening the census to used-to-be / formerly / deprecated / renamed-from /
replaced-by / earlier-version / historically / old-default found one further
real case and confirmed the rest are data operations ("weight replaced by the
conditioned value"). Any future check should use the widened list.

**NOT covered, and still open.** Code comments are out of scope by the rule's
own wording (it names roxygen, README, vignettes and NEWS) -- but dated
comments do exist in `posterior_consensus.R` and elsewhere if the maintainer
wants that scope widened. README, vignettes and NEWS have NOT been censused
for this at all.

Documentation only: no code, no exports, no number moves. Rd regenerated for
the six touched packages; TaxaAssign and TaxaFetch check 0 errors / 0
warnings.

### Pass A1: the remaining scope settled 2026-10-12, with no work needed

**README, vignettes and NEWS: censused, already clean.** The widened pattern
list over 9 package READMEs, 10 vignettes and 9 `NEWS.md` found THREE hits in
total, and none needs changing:

- `TaxaLikely/README.md` -- "trims the reference database so that it no longer
  resembles real observations": the effect of an operation, not this code's
  history. Keep.
- `TaxaExpect/vignettes/building-priors.Rmd` -- "can then no longer dilute a
  well-sampled group's estimates": likewise the effect of a method. Keep.
- `usgs_release_review/README.md` -- "Previously called `misc review docs/`" is
  genuine metadiscourse, but that directory is internal review documentation,
  not shipped with any package, and it sits with `ecosystem_docs/` on the
  history-may-be-kept side of the freeze. Keep.

**All nine `NEWS.md` read exactly as a first release should**: "# <pkg> 1.0.0 /
* Initial release." Nothing to purge, and nothing missing. Worth stating
plainly because the freeze rule naming NEWS is easy to misread: NEWS is
conventionally WHERE version history belongs. The rule makes sense for a FIRST
release, which has no public predecessor to report changes against; after 1.0,
`NEWS.md` is the right home for exactly the text the rule currently excludes.

**Code comments: deliberately OUT of scope, on the maintainer's instruction
that metadiscourse be limited to what is conventional.** Three reasons, the
third being the strongest:
1. Convention. User-facing documentation (Rd, README, vignettes) describes
   current behaviour; a released package's internal comments are not expected
   to be history-free.
2. Audience. Comments are read by maintainers, who are the people the history
   helps.
3. This session is the evidence. Row 194 closed WITHOUT a measurement only
   because a code comment preserved the reasoning ("One site counts once.
   Identical repeats ... are the same site's prior, not independent sites"),
   and the G4 comparator question was answerable only because the
   `@section Referenced candidates only` recorded WHY the restriction existed
   -- which is what showed a comparator is neither donor nor receiver.
   Purging that reasoning would have cost two measurements and invited the
   change to be undone by the next reader.

So pass A1 is closed in full: eight roxygen fixes merged at `70ebbad`,
nineteen roxygen matches kept as legitimate, three README/vignette/NEWS hits
kept as legitimate, and code comments out of scope by decision.

### Re-run gate 2026-10-12: the ledger is THREE items, and row 162 is resolved

**Row 198's complement fixes are ALREADY in R1009f, so they are not pending.**
I had listed them as a fourth ledger item; the dates say otherwise and the
workflow session confirmed it from the run logs. R1009f's preflight records
`installed TaxaAssign 0.1.0 built 2026-10-09 04:35:50 UTC`; main's first-parent
tip one minute earlier was `8111dc7`, and `f14795b`, `22655fc` and `f30c68a`
are all ancestors of it -- they first reached main's first parent at `252488f`
(2026-09-29). Any branch cut after that date also contains `252488f`, so the
conclusion holds whether the build came from main or a branch.

**THE LEDGER, pending the batched re-run, is three behaviour changes:**
`712ed59` (49 of 3,489 family assignments), `abaa60f` (zero call changes) and
`b921c00` (37 of 414 species calls go coarser). Everything else merged since
the checkpoints is documentation.

**Row 162 -- RESOLVED, and it needs no code change.** Both `likelihood_support`
figures are correct; they describe different runs, and the board conflated
them.

- `0.56 / 0.18 / 0.77` is the species-call median from the 2026-10-01
  rank-accuracy run, which predates C1, the G1-G6 guards, the k rule and the
  class fill. Stale.
- `0.999 / 0.992 / 0.999` is the species-call median on the live R1009f
  `consensus_final` (n = 10,382 / 188 / 3,238).

**The low medians did not vanish by a change of computation.** Most of the
prior-chosen species calls behind them were REMOVED by the guards, G6 above
all. What remains is a ~2,060-call `"narrowed"` minority that still sits low:

| Subset (12S / 18S / COI) | 12S | 18S | COI |
|---|---|---|---|
| Species calls, `prior_role = "agrees"` | 0.999 (8,945) | 0.992 (179) | 1.000 (2,614) |
| Species calls, `prior_role = "narrowed"` | 0.597 (1,435) | 0.275 (9) | 0.679 (619) |
| All species calls, MEAN | 0.936 | 0.960 | 0.915 |
| Species calls with support >= 0.95 | 83% | 88% | 74% |

**FOR THE MANUSCRIPT: report the overall median WITH the narrowed-subset median
beside it.** Quoting 0.999 alone hides the prior-decided tail, which is the
very thing `likelihood_support` exists to expose.

**THE GATE NOW NEEDS ONE THING: arm (c)'s re-measurement**, owed by the chat
whose coarse-rank grain error voided its aggregates. No local session owns it
-- the workflow session and sampling optimization both disclaim it, and the
row's own `Waiting on` cell says "that chat", meaning a claude.ai
conversation that cannot be messaged from here. Routing it is the
maintainer's.

**A FRAGILITY in how this board is referenced, found when a peer could not
locate "row 194".** The row numbers in this document are LINE NUMBERS in this
file (`awk 'NR==194'`), not stable identifiers. Appending at the end is safe,
but inserting anything above section 0 (line 154) silently renumbers every
row, and any message or note citing a row number becomes wrong. Cite the
row's `Item` text alongside the number.

### Arm (c) 2026-10-12: I WAS WRONG, and the gap is larger than the board says

I argued arm (c) could not gate the re-run because the board records "adopt
arm (b), HOLD arm (c)", so a re-run would reproduce arm (b). **That is wrong,
and the board row is stale in the opposite direction.** Verified by the
workflow session against the production script and the R1009f logs:

- **Arm (b) is no longer a wrapper**: it became package behaviour at `f14795b`,
  on main since `252488f` (2026-09-29) and present in R1009f's TaxaAssign.
- **Arm (c) is ON in production.** `ADD_UNREFERENCED_MASS <- TRUE` at
  `CaliforniaIntertidalWorkflow_multi_marker.R:3764-3765` ("decision
  2026-09-30"), invoked in the per-Site join at `:3935-3940`.
- **And the live form goes BEYOND the tested arm (c).** `named_rows = TRUE`
  (2026-10-01) makes recorded unreferenced local species their OWN rows, not
  merely mass on the generic rows. The three-arm test never evaluated that.
- **It dominates the candidate space.** R1009f's W1 log carries 72
  "Unreferenced named rows at <Site>" messages (Cojo 279,731; Carmel Point
  62,837), and `unreferenced_species` is **5,934,884 of 6,297,713** posterior
  rows in the update input -- 94%.

**So every number measured this week -- the 414 raised-row species calls, the
step-0 z table, the sufficient-raise distribution -- was produced with arm (c)
live, and the re-run will reproduce it.** Arm (c)'s void aggregates are a
VALIDATION GAP ON A LIVE, DOMINANT COMPONENT, not a question about a future
adoption, and cannot be waved through.

**The owner is unreachable.** The sampling-optimization session disclaims it: it
serves the PtConception paper chat, grepped its handoff and study folders, and
found no mention of arm (c), `add_unreferenced_prior_mass()`, the complement or
the coarse-rank grain error. So the row's "that chat" is a claude.ai
conversation none of the local sessions can message.

**Not alarming, recorded so nobody re-raises it:** the per-run check prints
`n_candidates_not_referenced = 0` for every marker. Per
`unreferenced_prior_mass.R:97-99, 191-193` that counts NAMED CANDIDATE rows
missing from `referenced_names` -- a consistency check whose healthy value is
0. It is not a count of unreferenced species.

**Still open, inherited:** `.referenced_names()` once unioned pre-drop sources,
so 24 screen-dropped species counted as "referenced". The current function
filters matches by the final drop list and looks fixed; the crosswalk half has
not been re-verified.

### Arm (c) validation AUTHORISED read-only 2026-10-12; crosswalk CLOSED

**The `.referenced_names()` crosswalk item is CLOSED and clean**, and the
re-examination is the useful part. 43 match-object species have EVERY match row
on the final drop list (12S 19, 18S 2, COI 22); 37 of them still count as
referenced, and each one because it has OTHER, undropped reference sequences in
the post-drop `reference_df`. `Semicossyphus pulcher` is the worked case: its
dropped hit is AY279644, but it carries 2 post-drop references and 39
`specific_candidate` rows -- the dropped-hit replacement recovering sheephead,
not a leak. The crosswalk's stored digest equals `digest(post-drop reference
species)` for all three markers and Section 8 refuses a mismatch, and the
`refs_<MK>.rds` sets carry 0 rows on the drop list. Step 7 names that never
appear as a `specific_candidate` number 427 (12S) and 1,754 (18S) and **zero
are binomials**, so nothing reaches `add_unreferenced_prior_mass()`'s
species-rank mass by that route. So the old "24 leaked species" is retired.

**ARM (c) VALIDATION: authorised read-only at Round-1 level** (~1-1.5 h, peak
4-5 GB, inside the budget the coordinator role may set; above 6 GB needs the
maintainer). No package change, no re-run, and installs are held for the
window. The 1.0 question is the LIVE configuration, not the three-arm
comparison, which needs the worktree harness and belongs after the re-run.

**WHY `named_rows` IS THE SERIOUS HALF, stated precisely:** the tested arm (c)
put mass on GENERIC rows, which can only pull a call COARSER. `named_rows`
creates NAMED COMPETITORS THAT CAN WIN -- that is, it can produce a species
call for a taxon with no reference sequence. No arm measured that behaviour,
and it carries most of the candidate space.

**A CHEAP DECISIVE COUNT WAS ASKED FOR FIRST**, before the counterfactual:
how many species calls resolve to an `unreferenced_species` row. And it must
NOT be read off `winner_hypothesis_type` -- the recorded 2026-10-08 finding is
that the `winner_*` columns describe the top-posterior HYPOTHESIS while the
call is `consensus_taxon` after downranking, and they disagreed on 23 of 48
cases: 48 by `winner_hypothesis_type` against **63** when classified on the
candidate row whose `taxon_name` equals `consensus_taxon`. The join must be on
`consensus_taxon`. G5G6k's 63 within its 2,070 prior-driven calls is the
anchor.

Two scoring requirements were added: report `named_rows` OFF and mass OFF
**separately**, since the first is the untested behaviour and the second the
tested one; and for every call that changes, say whether the pre-change call
was CORRECT where the maintainer has adjudicated the taxon -- "37 calls
change" and "37 right calls become wrong" are different findings and only the
second is a defect.

### named_rows measured 2026-10-12: 410 species calls are named by the RECORDS

Step 0 and its follow-up, read-only on R1009f. **R1009f makes 410 species
calls on taxa with NO reference sequence**: 12S 125/10,382 (1.2%), 18S
**176/188 (93.6%)**, COI 109/3,238 (3.4%). 35 taxa; `Smithora naiadum` alone
is 167 calls at 18 sites.

Classified by joining each species-rank call to the candidate row whose
`taxon_name` equals `consensus_taxon`, NOT by `winner_hypothesis_type`, which
would have said 142/176/84 -- wrong in both directions for 12S and COI, as the
recorded 48-vs-63 finding predicted.

**THE SEQUENCE NEVER CHOOSES THE SPECIES NAME.** `named_rows` copies the ring
row's likelihood onto every member of its scope, so the likelihood spread among
named siblings is EXACTLY 0 across all 410. What the sequence discriminates is
(1) named-unreferenced against every referenced candidate, and (2) which SCOPE
LEVEL (genus, family or order ring). The species name comes from the occurrence
records alone.

- **Sole candidate in scope: 299 of 410** (12S 91, 18S 169, COI 39). These are
  elimination from the record. `Smithora` is 167 of 167 sole, and its scope is
  **Erythropeltidales at ORDER rank** -- the inference reads "an unreferenced
  member of this order; S. naiadum is the only one recorded here; therefore
  S. naiadum".
- **Multi-candidate: 111**, and these are WEAKER, not stronger -- a prior-only
  tie-break among equal-likelihood candidates, the winner holding
  `prior_share_top` 0.93-1.00. `Postelsia palmiformis`: 18 calls, 25 named
  siblings in scope (Phaeophyceae / Laminariales), prior share 0.93.
- `likelihood_consensus_taxon == consensus_taxon` for 356 of 410, confirming
  the likelihood-only pass lands on the same NAME because it reads the same
  records-built candidate set. (Not yet traced: how a likelihood-only pass
  names one of several equal-L siblings, so that 356 wants checking.)

**NOTHING CURRENTLY FLAGS THESE.** `likelihood_support` is ~0.99 (it reports
"an unreferenced relative in scope S beats every referenced candidate", which
is true and says nothing about the name); `prior_role` is `"agrees"` (both
passes read the same candidate set); and `winner_rank_expanded` is a different
mechanism. So a reader AND `review_assignments()`'s LLM reviewer both see these
as well-supported species identifications.

**THIS CORRECTS THE ROW-162 RESOLUTION GIVEN EARLIER THE SAME DAY.** 18S's
median `likelihood_support` of 0.992 IS these calls, and the
"median-plus-narrowed-subset" caveat misses them entirely because they are
`"agrees"`, not `"narrowed"`.

**THE PACKAGE DEFAULT IS SAFE: `named_rows = FALSE`.** The package adds the
recorded species' mass to the ring row, which can only pull a call COARSER.
The CalIntertidal workflow opts IN (`:3935-3940`, `named_rows = TRUE`, decision
2026-10-01). So this is not a package defect; it is an unvalidated workflow
configuration plus a visibility gap. No arm ever tested `named_rows`.

### Arm (c) VALIDATED at Round-1 level 2026-10-12; the gate can close

Read-only counterfactual on R1009f, both halves scored separately, 49,463
units (12S 17,844 / 18S 13,086 / COI 18,533). **Baseline exact: the recompute
reproduced the stored Round-1 consensus 2,000/2,000 per marker**, 0 named
groups failed to find their ring row, 0 network calls, peak 2.65 GB, ~8 min.
Round 1 ONLY -- Round 2 is not replayed.

(Method note worth keeping: a named row is identified by
`unreferenced_species` + species rank + `prior_mean_floor` NA + non-NA scope.
The generic GENUS ring row is ALSO typed `unreferenced_species`, so
`hypothesis_type` alone would have been wrong here too.)

**THE TESTED HALF -- the mass -- IS CONSERVATIVE. It only ever WITHHOLDS.**
Turning it off (= arm b) RAISES species calls: 12S 10,080 -> 10,950, 18S 188
-> 606, COI 3,124 -> 3,555. So the live mass withholds **2,079** species calls,
and **0 referenced species calls change** either way. The withheld set is
mostly well-known local taxa -- `Oligocottus snyderi` 526, `Apodichthys
flavidus` 128, `Alaria marginata` 113, `Mytilus californianus` 72 -- and 797 of
them sit at the genus OF THE SAME GENUS in live. The mass is doing exactly what
the complement was built for: refusing a species call when unreferenced local
congeners could explain the sequence.

**THIS IDENTIFIES THE CAUSE OF THE OPEN `O. snyderi` ITEM.** Its lost species
calls are the unreferenced mass withholding them, 526 of them. Whether that is
right is a biological question for the maintainer, not a defect.

**THE UNTESTED HALF -- `named_rows` -- IS THE ONE THAT ADDS RESOLUTION**, and
it adds far more than the 410. Turning it off moves 12S 224 units, 18S 1,317
and COI 3,643. Besides the 410 species names going coarser to their ring scope
(18S: 167 to ORDER, i.e. `Smithora` -> Erythropeltidales), about **4,700
NON-species calls also lose one rank** -- COI Malacostraca -> Arthropoda
1,497, Anthozoa -> Cnidaria 1,230, Florideophyceae -> Rhodophyta 269; 18S
Laminariales -> Phaeophyceae 436 -- and **349 calls become NO CALL**. It also
coarsens in the other direction for 92 12S units (Chordata -> Actinopteri),
so it is not purely a refinement.

Mechanism: splitting mass onto named members makes a class/order node credible
where a lumped ring at the parent would win. **So roughly 5,100 calls, about
10% of units, take resolution from the occurrence records in scope rather than
from the sequence** -- the same caveat as the 410, applied to 4,700 more calls.

**WHAT IT NEVER DOES:** it never changes a referenced species call (0 in both
halves), never creates a call for the out-of-range controls (`L. littorea` and
`C. harengus` are never called at species in live, (i) or (ii)), and leaves
every one of the maintainer's adjudicated taxa untouched -- Girella 317,
Scomber 156, Gobiesox 42, Sarda 10, M. aurora 9, F. parvipinnis 5, Protohyale
4. Neither half gains an adjudicated taxon either.

**SO THE RISK IS NOT WRONG-PHYLUM FAILURE; IT IS THAT RECORD-DERIVED
RESOLUTION IS PRESENTED AS SEQUENCE-DERIVED.** No call was found right in live
and wrong in a counterfactual, or the reverse, where ground truth exists -- but
the adjudication set is too small and too fish-heavy to score the 2,079 or the
4,700, so that is an absence of evidence, not evidence of absence.

**GATE: closeable.** The validation gap that held the re-run is filled at
Round-1 level, and the three structural properties above (mass only withholds;
`named_rows` never touches a referenced call; no control is ever called) are
unlikely to invert at Round 2. The Round-2 interaction is UNMEASURED and needs
the per-Site update rerun (14 GB peak) to measure, which is the re-run itself.

**CONSEQUENCE FOR THE PROVENANCE COLUMN: it must cover the ~4,700 refined
coarse calls, not only the 410 species calls.**

### Board verification sweep 2026-10-12: 20 maintainer rows down to 11

Six stale rows had surfaced by accident during the day's work, so the whole
"waiting on maintainer" set was checked against `main` rather than trusted.
Eight closed:

- **163** -- its fix `f9462e2` (`.extract_rank_values()` masking values at
  ranks finer than the row's own) is in main. The 90 artefact `credible_node`
  species calls it reported cannot recur.
- **169** -- the placeholder DOI fix `7a3d13f` is in main. Residual is one
  third-party host with an expired certificate: keep the link or drop it.
- **195** -- four of the five queued changes are in main and the fifth is
  superseded by `7ae8785`.
- **166** -- B1 and B2 are BOTH fixed at `4e748d6` ("Placeholder ranks name no
  taxon; taxonomy lookup never overwrites", 2026-10-01), verified in code: the
  taxonomy fill now touches only empty cells, with a comment naming the
  defect, and `.is_placeholder_rank()` exists and is used in TaxaAssign and
  TaxaLikely. F1 and B3 remain.
- **196, 197** -- their figures (545 / 462 / 389 species calls at ESV x site)
  come from the superseded grain test. Today's arm (c) counterfactual answers
  the same question properly: the mass only WITHHOLDS (2,079 species calls),
  and `named_rows` is what supplies resolution (410 species names plus ~4,700
  one-rank refinements).
- **228, 229** -- both say LANDED; informational.

**WHAT GENUINELY REMAINS (11).** The calibration cluster (**165**, **182**, and
166's **F1**) is one decision asked three ways, and F1 settles it: the
`calibrate_query_noise()` confident set is contaminated -- 72% of 18S and 60%
of COI rows not confident, moving the COI constant offset from -0.069 to
-0.221 -- so EVERY held-out RMSE figure, including the 9% and 20% COI costs,
came from that set and **the calibration-form decision cannot be made on those
numbers**. It is also the SECOND independent contamination of the same object.
Then **186** (coarse records diluting every species' theta through a shared
denominator -- real and open), 166's **B3** (the synonym claim its own author
flagged as unverified, cheap to check), and the administrative remainder:
**207** PtCon 12S B2 go, **208** cache-refetch sequencing, **209** README
rounds, **212** pre-security-review submission, **214** TaxaWizard snippet,
**215** supplemental methods style, **219** the tracked four production
findings.

**A CORRECTION to my own earlier recommendation: row 238 is NOT a quick
mechanical sweep.** There are 289 bare `ifelse()` calls across the nine
packages' `R/`, and a blanket substitution would be wrong -- `dplyr::if_else()`
is type-strict as well as length-strict, so swapping it in blindly would turn
working code into errors. The trap only fires where a branch yields a
length-1 value against a longer test, so this needs the same kind of triage
pass A1 needed, not a `sed`.

**THE METHOD, since this keeps paying.** `git log -S "<a distinctive phrase
from the claim>"` plus `git merge-base --is-ancestor <fix> HEAD` settles a row
in one command. The row numbers are LINE numbers and shift, so cite the row's
`Item` text alongside the number.

### The four remaining items, worked 2026-10-12: none gates the re-run

**NONE OF THE FOUR NEEDS TO PRECEDE THE RE-RUN.** The hold is purely on the
maintainer's Drive window. Two of them interact with it and are recorded below.

**B3 (row 166) -- CONFIRMED, as a limitation rather than a bug.** Its author
flagged the claim as unverified; it is right. `flag_backbone_conflicts()`
detects a name carried at MORE THAN ONE RANK, or under more than one PARENT at
the same rank -- that is ONE NAME in many places. A synonym is the exact
inverse, MANY NAMES for one organism, each sitting consistently at one rank
under one parent, so there is no conflict to find. The check cannot see this
class at all, which is a documentation matter, not an implementation gap.

But it has a possible CONSEQUENCE FOR THE 410. `referenced_names` is a plain
character vector of species "on the prior backbone". If harmonisation does not
collapse a synonym pair, then where the reference set holds *Eisenia arborea*
while the records list *Ecklonia arborea*, the latter is absent from
`referenced_names`, becomes a recorded unreferenced local species, gains a
named row under `named_rows = TRUE`, and can WIN -- a record-named species call
for a taxon that IS referenced under its other name. A cheap high-precision
test has been asked for: among the 410, how many have a reference species with
the SAME specific epithet but a different genus in the same family or order
(arborea/arborea)? Zero closes B3 outright; non-zero is a defect in the 410
class and is needed before the manuscript.

**186 AND THE CALIBRATION CLUSTER (165, 182, F1) ARE ONE PROBLEM, NOT FOUR
ROWS.** Verified: `identify_confident_observations()` lives in
`calibrate_query_noise.R` and IS the function that builds the confident set for
calibration. Row 186's finding is that `estimate_kernel_priors()` computes
theta as a SHARE of one denominator, so 84,000 coarse records in the pool
dilute every species' theta. That consumer then reads theta VALUES
(`theta_mean > plausibility_threshold`, keeping genera with exactly one
plausible species). **So the dilution decides which observations are
"confident" -- and the confident set is precisely the object F1 reports as
contaminated** (72% of 18S and 60% of COI rows not confident, moving the COI
constant offset from -0.069 to -0.221). One causal chain:

    coarse records dilute theta  ->  the confident set is wrong
      ->  the calibration offset is wrong  ->  the constant-vs-linear
          evidence is wrong  ->  rows 165, 182 and F1

**THE COST OF FIXING IT, and why it is a 1.0 decision.** A refit on
`pool_at_rank(species)` changes EVERY species' theta because the denominator
changes. That invalidates the TaxaExpect priors table, hence Step 7's
likelihoods, hence everything -- a re-run strictly larger than option (B), and
the priors rebuild is the expensive one. Narrowing the digest to avoid the
invalidation is already CLOSED as wrong: the consumer reads values, not names,
so the checkpoints would be stale rather than valid.

**Recommended:** defer 186 past 1.0 and decline the claim rather than the
method. Keep `offset_form = "constant"` -- a defensible simple default -- but
the Methods must NOT say constant was chosen over linear on held-out RMSE,
because every such figure, including the 9% and 20% COI costs, was computed on
the contaminated set. Deferring introduces no error; it declines to assert
something the numbers cannot support, and it keeps 1.0 shippable. This closes
four rows with one decision and one sentence of honesty in the write-up.

### Maintainer's decision 2026-10-12: defer 186, decline the calibration claim

**Taken, and it closes four rows with one decision.** The coarse-record
dilution is deferred past 1.0; `offset_form = "constant"` is KEPT; what is
withdrawn is the evidential claim behind it. Implemented as documentation at
`456be1f` -- no code, no defaults, no numbers.

`calibrate_query_noise()` had rested its default on held-out comparisons ("it
matched or beat linear everywhere except COI"; "held-out error falling by a
factor of 2 to 5"). Those figures come from the confident set, which cannot
adjudicate the question, because `identify_confident_observations()` thresholds
`theta_mean` and that is a SHARE of a pool denominator containing coarse-rank
records. The docs now say `"constant"` is the simplest correction to state and
applies one method to every marker -- a stated default, not a measured winner
-- with the comparison deferred until a confident set exists on an undiluted
denominator.

**B3 CLOSED with a measurement.** The 35 record-named taxa behind the 410
calls gave 97 shared-epithet pairs against the reference sets, and EVERY one
was in a different family -- homonymous epithets across unrelated groups rather
than synonyms (Fucus / Pleurophycus / Pyropia gardneri; Coilodesme / Ulva /
Dictyota rigida). None of the 35 is referenced under its own name or a
crosswalked one, and the sole-in-scope cases have no same-family hit either, so
no instance of the failure exists in R1009f. The LIMITATION stands and is now
documented on `flag_backbone_conflicts()`: it detects one name in many places,
so synonymy is invisible to it by construction and a zero report says nothing
about it. Two residual limits recorded by the measuring session: the epithet
test cannot see synonyms with a CHANGED epithet, and the NCBI-to-GBIF
crosswalk -- the designed defence -- currently carries only 1 / 13 / few names
for 12S / 18S / COI and does not catch synonymy WITHIN one backbone.

**A STALE `.Rd` FOUND INCIDENTALLY AND FIXED.**
`TaxaLikely/man/apply_coverage_constraints.Rd` still documented
`run_bayesian_pipeline()`, which the export prune REMOVED: the roxygen source
had been corrected and the generated `.Rd` had not been regenerated, so the
shipped documentation referred to a function that no longer exists. Fixed in
the same commit, and `document()` was then run across all nine packages to
check for others -- there are none, so the Rd files are now consistent with
source everywhere. Worth adding to the release checklist: regenerating docs is
a VERIFICATION step, not only a build step.

### B3 closed by measurement, both directions (2026-10-12)

The synonym question is settled on the backbone the priors use, with ~412
lookups. **0 hits in either direction across all 35 record-named taxon x
marker pairs.**

- All 34 distinct names resolve at species rank to THEMSELVES, `is_synonym`
  FALSE. **`Smithora naiadum` -- which carries 167 of the 410 calls alone, at
  ORDER scope -- is ACCEPTED.**
- None of their accepted names appears in the same marker's post-drop
  reference set: 0 of 15 (12S), 0 of 6 (18S), 0 of 14 (COI).
- Reverse direction: all 318 reference species sharing a family with any of the
  35 were resolved (57 / 53 / 208, 3 COI names unmatched); none resolves to one
  of the 35 or its accepted name. So no sequenced organism hides behind another
  name in those families.

**What it does NOT establish**, and the docs now say so: it is that backbone's
taxonomic opinion, obtained through the Global Names Verifier. A pair another
authority treats as synonymous while this backbone keeps it separate would not
show -- consistent with a workflow that harmonises everything to one backbone,
but an opinion rather than ground truth. And the reverse check is bounded to
SAME-FAMILY references, so a synonym the backbone places in a different family
would escape it, though that would itself be a conflict of the kind
`flag_backbone_conflicts()` does detect.

So the limitation recorded on that function is a MEASURED ABSENCE on R1009f's
410 rather than an untested assumption. Row 166 is closed in all four findings.

### Cross-dataset check on Mugu, 2026-10-12: both changes travel

The two merged behaviour changes had only CalIntertidal evidence, which is not
a safe basis for a released package. Checked read-only against Sepulveda/Mugu
(`MuguWilderFish_blast_all_posteriors_r2.rds`, 0.2 MB, 3,087 rows). That
workflow exercises `update_prior_from_consensus()` and `posterior_consensus()`
but does NOT set `ADD_UNREFERENCED_MASS` or `named_rows`, so its unreferenced
rows are generic rings only (560 genus, 146 species) -- which makes it an
independent test of the comparator, and also establishes that **the 410
record-named species calls are a CalIntertidal OPT-IN, not a general property
of the package.**

**A CONFOUND I NEARLY REPORTED AS A RESULT.** The Mugu artefact is from
**Sep 11**; the Round-2 guards landed **Oct 7-8** (`049b0ac`, `436bd42`,
`58d9944`). So that run predates every guard, and a first pass suggested the
widened comparator would block 329 of its 390 raised rows -- which measures
guards-versus-no-guards, a question already settled, not the widening.
Of those 390, only **74 survive the EXISTING referenced-only G4/G5** at all;
the other 316 were raised because nothing was then stopping them.

**The INCREMENTAL effects, which is what was wanted:**

| change | on CalIntertidal | on Mugu |
|---|---|---|
| widened comparator | 37 of 414 calls coarser (9%) | **13 of 74 raised rows** newly blocked (18%) |
| `max_raise_factor = 2000` | 0 of 414 bound | **0 of 74 bound** (47 are above 50x, none above 2000x) |

**So both travel.** The bound is inactive on a second, independent dataset, so
`2000` is behaving as a loose safety rail rather than a tuned constant -- which
is what the maintainer's rule requires and what the CalIntertidal measurement
alone could not establish. The widening's effect is of the same order on both
(9% against 18% of a much smaller raised set), and in the same direction:
withholding a species call where an unreferenced relative explains the sequence
at least as well. Mugu having only GENERIC rings and still showing that effect
is the stronger evidence, since no named-row machinery is involved.

Caveat kept: Mugu's artefact predates the guards, so these are counterfactual
figures on its saved Round-1-equivalent state rather than from a re-run of it.
A Mugu re-run is not proposed; nothing here suggests one is needed.

### Row 238 closed 2026-10-12: the ifelse() trap is triaged, not swept

A sweep would have been wrong twice over: 289 bare `ifelse()` calls across the
nine packages, and `dplyr::if_else()` is TYPE-strict as well as length-strict,
so substituting it blindly turns working code into errors.

**What makes the trap fire, which is what makes the search tractable.**
`ifelse()` returns the length of its TEST, so the damage happens when the test
is SCALAR while a branch is a VECTOR -- the branch is truncated to one element,
silently. The common shape, a vector test with a scalar branch, recycles
correctly and is safe. So the sites at risk are those with a
guaranteed-scalar test: `&&` and `||`, which require scalar operands, plus
`is.null()`, `isTRUE()`, `isFALSE()`, `identical()`, `length()` and `nrow()`.

**Result: ONE hit across all nine packages, and it was already safe** --
`review_sample_identity.R`, where both branches were scalars too, so nothing
could truncate. Two further hand-checked candidates
(`classify_sample_identity.R` lines 686 and 760) are vectors on all three arms.
The three instances that prompted the house rule are fixed, and
`assign_taxa_llm()` carries the reasoning in a comment at the repair site
("rep(), not a bare NA_character_: ifelse() returns the length of its TEST").

The one change made was to stop that call LOOKING like the trap: a scalar test
with scalar branches is an `if`/`else`, and leaving it as `ifelse()` costs
every future sweep a false positive. `dplyr::if_else()` remains the house rule
for NEW code, where its strictness is a feature; retrofitting it across 289
existing call sites is not warranted and is not proposed.

### Row 212, 2026-10-12: a version mismatch across all nine packages

**Every `NEWS.md` announced a 1.0.0 initial release while every `DESCRIPTION`
read 0.1.0.** The repository contradicted itself about its own version, and a
security reviewer opening any package would have seen a 1.0.0 release note on a
0.1.0 package.

**`R CMD check --as-cran` does not compare the two.** It returned 0 errors, 0
warnings and 0 notes on exactly this state -- the fourth time in this screen a
gate turned out to be checked by a proxy narrower than the rule it stands for
(after the exports diff that cannot see a new argument, the board rows that
read as pending while merged, and pass A1's three-string pattern list).

**Aligned DOWN to 0.1.0**, not bumped up, because this row's own recorded
decision is "no tag, no bump" and a 1.0.0 declaration belongs with the release
and its tag rather than preceding the security review. NEWS bodies untouched;
only the headings moved. Bumping all nine is one command when that release is
made, and the WERC official path's `1.0.0` branch remains a separate step and
the maintainer's call on timing.

**HOUSEKEEPING, verified and the maintainer's to run** (git 2.15 has no
`git worktree remove`, and a safety check blocks it from this session): three
local branches are fully merged into `main` with worktrees still attached --
`ambiguous-genus` (`~/taxaid-worktrees/amb`), `blank-ranks`
(`~/taxaid-worktrees/blank`) and `coi-amplicon-gate`
(`~/taxaid-worktrees/coi`). `workflow-ptcon-multisite`, in
`~/My Drive/Rscripts/projects/TaxaID`, is NOT merged and is the one real
outstanding branch.

    rm -rf ~/taxaid-worktrees/{amb,blank,coi} && git worktree prune
    git branch -d ambiguous-genus blank-ranks coi-amplicon-gate

### The option-B run: stopped once by my own commit, then launched (2026-10-13)

**First attempt stopped itself at preflight with VERDICT 20 and nothing ran** --
no archive, no R stage, no network. Cause: `597d40f`, my own commit, which
added a read-only stale-cache `message()` to
`fetch_ncbi_reference_sequences()`. The CalIntertidal refs-freeze key includes
`fetch_code = .code_digest("fetch_ncbi_reference_sequences")`, so any change to
that function's code reads as "the reference set may differ", and there is no
override for that part. `ALLOW_LIVE_PREP = 0`, so the driver refused, exactly
as designed.

**THE ERROR, which is the transferable part.** Before giving the run its GO I
audited all five files whose code had changed and concluded none could reach
the run. That was CORRECT about behaviour -- the message lists files and
matches a regex, and cannot alter a reference set. But **I asked "can this
change results?" where the gate asks "did this code change?"** This is the
fourth proxy-versus-rule failure this screen has recorded (after the exports
diff that cannot see a new argument, board rows reading pending while merged,
A1's three-string pattern list, and `R CMD check` not comparing NEWS to
DESCRIPTION) and the first committed by the reviewing session rather than found
in someone else's work.

**For anyone giving a run its GO: when a key digests CODE, diff the FUNCTIONS
the key names, not the files you judge relevant.**

**Resolved by reverting on main** (`5df0b6e`), not by installing around the
commit, so the installed tree and main stay identical and the run manifest
needs no footnote. TaxaLikely reinstalled from that tree at 08:23:44 UTC;
verified on the INSTALLED namespace that the message is gone. The two
alternatives were both refused, and the reasons matter: **live prep** re-fetches
from NCBI and could admit new unscreened accessions into a set that was
deliberately screened and drop-listed, cascading into the region and matrix
keys and making the result incomparable with R1009f -- which is the point of
the run; a **workflow override switch** would be a permanent knob for a one-off
and a workflow edit needs the maintainer's own word.

**TO RE-LAND `597d40f` after the run: revert `5df0b6e`.** The change and its
four tests are good; they simply cannot be inside this particular run.

**LAUNCHED** `run_next_2026-10-12_2224`, VERDICT 10, start Mon Oct 12 22:24:16
HST 2026 (Tue Oct 13 08:24:16 UTC), ETA report tables ~03:10 HST and complete
~03:25 HST, expected peak 15-17.5 GB in COI training. refs FROZEN for all three
markers with `fetch_code` matching again, matrix reusable, the 10-10 outputs
archived to `archive_2026-10-10_1251_PROVISIONAL/`. Carries four behaviour
changes: `712ed59` (49 of 3,489 family assignments), `abaa60f` (0 call
changes), `b921c00` (37 of 414 species calls coarser) and `08beaca` (provenance
columns, 0 changes). It is also the FIRST end-to-end observation of
`named_rows` interacting with Round 2, so anything outside those four is that
interaction appearing rather than necessarily a fault.

**FINISHED** Tue Oct 13 04:19:35 HST 2026, rc=0 at every stage, run max
**12.8 GB** in W1 -- under the 15-17.5 GB expected, so the COI-training peak
estimate was conservative rather than wrong. Wall clock 5 h 55 min against an
ETA of ~5 h 01 min. Driver exited; no R live at 04:20 HST, installed tip still
`5df0b6e` == main, so the measurement reads exactly the tree the run used.

Measurement runs next in the workflow session (read-only Rscripts): the four
deltas plus any `named_rows` x Round-2 interaction, the provenance columns
against 410 named-unreferenced and 299 sole-in-scope at R1-equivalent units,
and the `fetch_code` check that decides whether re-landing `597d40f` would
re-break the refs key for a future run. **Installs and R stay held in the
coordinator session until that measurement reports.** The `597d40f` re-land
(revert `5df0b6e`) happens after the measurement, not before -- main is not
touched while scripts read the installed tree.

### What the option-B rebuild measured (2026-10-13)

Unit: final consensus, **49,466 observation_ids** (ESV@Site), the same set in both
runs. Measurement scripts peaked at 3.7 GB or less.

**203 units change** -- 159 coarser, 44 finer, **0** to or from no call and **0**
changing taxon at the same rank. Species calls 12S 10,382 -> 10,356, 18S
188 -> 187, COI 3,238 -> 3,222 (net -43). Species LISTS barely move: 12S (168)
and 18S (9) unchanged; COI 239 -> 237, losing *Holothuria lubrica*, *Eucheilota
bakeri* and *Coilodesme rigida*, gaining *Spheciospongia confoederata*.

**The delta decomposes exactly, with no residual: 37 + 67 + 99 = 203.**
- `b921c00` matches its prediction exactly on its 414: 377 unchanged, **37
  coarser** (21 genus, 15 family, 1 order), all with unchanged Round-1 calls.
- `712ed59` accounts for all **67** units whose ROUND-1 call changed (31
  coarser, 36 finer). The lineage tables differ in FAMILY only -- 99
  (marker, taxon) rows across 31 genera, 0 order or class changes. Every
  changed Round-1 taxon pair sits on one of those lineages.
- **99** units are the interaction (finding A below).

`abaa60f` -- **no change is attributable to it, and for the 99 it cannot be
separated from `b921c00` at all.** My "0 call changes" prediction for it was
true of SPECIES calls only; I stated it without that qualifier. A per-commit
recompute would separate the two if the separation is ever wanted.

`08beaca` adds columns only, 0 call changes, present and populated.

**Finding A -- Round 2 at NON-species ranks.** 99 units with unchanged Round-1
calls, outside the 414. 91 lose an old Round-2 refinement (12S
Embiotoca->Embiotocidae 12, Actinopteri->Chordata 10, Rimicola->Gobiesocidae 7;
18S Cheilostomatida->Gymnolaemata 8; COI Bossiella 8, Mazzaella 7) and 8 go
FINER, the old Round 2 having coarsened Perciformes calls to
Chordata/Actinopteri where the new run keeps Perciformes. In **75 of the 99** a
named unreferenced row lies inside the withdrawn taxon, which fits named rows
now acting as G4/G5 comparators -- containment, not proof.

**Finding B -- `712ed59` x `named_rows`.** A family fix moves unreferenced SCOPE
membership, so the record-named species move with it: *Eucheilota bakeri* 13
named Round-1 calls -> 1, *Coilodesme rigida* 1 -> 0, *Spheciospongia
confoederata* 0 -> 4 (scope Clionaidae, 2-3 siblings, so prior-only tie-break
and never sole-in-scope).

**Provenance columns VALIDATED.** New run: 401 named-unreferenced species calls,
295 with `consensus_scope_n_named == 1` (COI 101/36, 12S 125/91, 18S 175/168).
An independent classifier agrees unit by unit, 401/401, `n_sib == n_named` on
all 401; every non-NA `consensus_scope_n_named` sits on a species call of type
`unreferenced_species`. The archive reproduces 410/299 under the same
classifier, so **the 410 -> 401 and 299 -> 295 gap is real and is entirely
finding B** (-13 *Eucheilota*, -1 *Coilodesme*, +4 *Spheciospongia*; all 4 lost
sole-in-scope are *Eucheilota*).

**FOR THE MANUSCRIPT the named-unreferenced figures are now 401 and 295, not 410
and 299.** 18S reports 187 species calls, 175 of them record-named (93.5%, was
176/188 = 93.6%).

**OPEN, small:** the `712ed59` family-change count has two units -- my 49 of
3,489 family assignments and the workflow session's 99 (marker, taxon) rows
across 31 genera. Neither was recomputed against the other. Reconcile before
either number is published.

### `597d40f` should NOT re-land as written (2026-10-13)

`fetch_code = .code_digest("fetch_ncbi_reference_sequences")` hashes the
function's deparsed body AND every package-internal function it reaches.
`597d40f` adds a body block and a newly reachable helper
(`.ref_cache_unreachable`); either alone changes the digest, so the next
frozen-refs run misses the refs key and falls to VERDICT 20 (live prep) -- which
re-fetches from NCBI and admits accessions outside the screened, drop-listed
set, making the result incomparable with R1009f. That is the cost I refused on
the night of the launch, and re-landing the commit pays it later instead.

**The structural consequence, independent of this commit:
`fetch_ncbi_reference_sequences()` and everything it reaches are effectively
FROZEN for as long as runs must stay comparable.** `deparse()` drops comments,
so comment-only and roxygen-only edits are free; any body change at all is not.
Mugu and GreatLakes are inside the gate, so "no further comparable run" is not
true.

Routes, cheapest first:
- **Keep it reverted for 1.0** (coordinator's recommendation). The commit is a
  usability message with zero effect on any result; `5df0b6e` stays and
  `597d40f` remains reachable in main's history.
- **Move the report into `taxalikely_clear_cache(dry_run = TRUE)`**, which
  already exists, already reports cache contents, and is not reached by fetch.
  Zero digest impact, zero new exports, zero workflow edit. Weaker: the caller
  has to ask rather than being told mid-fetch.
- A new export called from a non-digested workflow site also works, but costs a
  new export under freeze AND a workflow edit for a cosmetic gain -- dominated
  by the line above. Note the workflow's own `.prepare_references` is digested
  into `prep_code`, so the check cannot go there either.
- A `TAXAID_LIK_KEY_IGNORE_CODE`-style override remains refused: a permanent
  knob for a one-off, and a workflow change needs Kevin's own word.

**Addendum.** The workflow session confirms the final consensus also carries all
**401** named-unreferenced species calls, so the record-named split holds at the
PUBLISHED unit and not only at R1-equivalent units -- 18S 187 = 12
sequence-identified + 175 record-identified is quotable without a unit caveat.
Within the new run, then, Round 2 coarsens away no named-unreferenced species
call; the 37 coarsenings of `b921c00` are relative to R1009f, not to this run's
own Round 1, so there is no tension with finding A. **The 295 sole-in-scope
figure was measured at R1-equivalent units only** -- confirm it travels to the
final unit before the elimination-from-the-record argument is written, since
that is the half the argument rests on. Option (a) withdrawn by its author;
`prep_code` closes it.

**Closed.** `295` sole-in-scope also holds at the final consensus, matched UNIT
BY UNIT rather than by count (m7.R, read-only): 401 named / 295 sole / 0 NA, by
marker 12S 125/91, 18S 175/168, COI 101/36 -- identical to the R1-equivalent
split. Against this run's own Round 1: R1-only 0, final-only 0, same taxon
401/401, same scope 401/401, same `n_named` 401/401, and non-NA `n_named` on
exactly those 401 rows and no others. **So within this run Round 2 neither
removes nor alters any named-unreferenced species call, and both 401 and 295 are
quotable at the published unit with no caveat.** The
elimination-from-the-record argument can be written on 295. Finding A's
withdrawn refinements are therefore entirely at non-species ranks, as its
heading says -- nothing in it reaches a named species call.

### `5df0b6e` verified against the install for the R1013 deposit (2026-10-13)

Asked by the reports session, because the R1009f README's sentence ("commit
`068d6ff` reproduces all nine installed packages exactly, checked function by
function") rested on a check that had NOT been repeated for `5df0b6e`. My
earlier "installed == main == 5df0b6e" rested only on TaxaLikely's `fetch_code`
digest matching and the reverted message being gone from the installed
namespace -- one package, one function. **Now measured properly**, R 4.5.2,
library `~/Library/R/4.0/library`, method per
`reference_installed_package_to_commit_without_remotesha`:

1. **Code.** 1,068 functions across the nine, `deparse(removeSource())` of the
   installed object against `deparse()` of the parsed source at the commit:
   **0 body or signature differences, 0 functions in source but not installed.**
2. **Verbatim files.** 174 `inst/*`, `NAMESPACE` and `NEWS.md` files
   md5-identical. **DESCRIPTION identical FIELD BY FIELD in all nine, all at
   0.1.0** -- a line-wise diff falsely flags all nine, because install rewraps
   `Imports:`/`Suggests:` onto continuation lines and synthesises `Author:` and
   `Maintainer:` from `Authors@R`.
3. **Documentation.** Rd alias sets identical in all nine. TaxaTools 63/63; its
   apparent single mismatch was Rd escaping, `\%||\%` in the source against
   `%||%` in `help/AnIndex`, not a missing alias.
4. **Reverse direction.** **0 installed files in any package come from outside
   the commit.**

**VERDICT: EXACT on all four.** The sentence is true of `5df0b6e` as written.

Caveats the deposit should carry, none of them a difference:
- **`tests/` is NOT installed in any of the nine** (`--install-tests` not
  used), so the 208 test files in the commit were not compared against the
  library. That is absence, not disagreement. It also differs from the
  2026-10-10 check, where four of nine had tests installed -- the install
  method changed, so do not reuse that detail.
- Package subtrees are **identical** between `5df0b6e` and current main
  `cd9a1ef`; the five commits since are docs-only
  (`ecosystem_docs/REENTRY_PROMPT_prepublication_screen.md`). Both SHAs cite
  the code identically, and **`5df0b6e` is the one to name**, being HEAD when
  the run ran.
- `5df0b6e` is reachable on `origin/main`, so it is citable.
- **Artefact provenance:** references were FROZEN and reused under a matching
  `fetch_code` digest, and the sequence matrix was reused; Step 7 likelihoods
  and everything downstream were rebuilt. A deposit that cites one commit for
  the code should say which artefacts predate the run.

**`calintertidal-R1013` CREATED AND PUSHED** on Kevin's direct approval
(2026-10-13): annotated tag object `3a2a4de8409134a739b44b8826bf087ec84040d1`
on commit `5df0b6e`. Only the tag was pushed.

**Model provenance is BETTER than R1009f's, and was measured not assumed.** Each
`cache_lik/lik_<marker>.dep` records a namespace code digest, and all three
match the installed namespaces exactly, identically across all three markers:
TaxaLikely `f454a32185cdd13072be52ec8092cee1`, TaxaMatch
`a18606a7d9084e8230fc94b16f0dfa00`, TaxaTools
`22234a73a5eaead07b2dbf4d7b619ae4`. The Step 7 checkpoints were rebuilt in the
run by the cited commit, so **R1013 does not carry R1009f's "models predate the
cited commit" caveat.** Frozen references and reused sequence matrices are the
only artefacts predating the run, and the tag message names them. To recompute:
`.ns_code_digest()` at workflow:3528 -- note `Rscript --vanilla` drops
`R_LIBS_USER`, so pass `.libPaths()` explicitly or the packages will not load.

### Microgadus / Catostomus traced: one real defect, and the guards mostly held (2026-10-13)

Read-only trace of the two R1013 calls Kevin flagged as geography/habitat
errors. Peak 3.3 GB. **They have DIFFERENT causes and only one is a package
defect.**

**Shared evidence.** All five ESVs are **single-replicate, single-extraction,
one batch (JVB3735)**, 22-183 reads, zero reads in any blank or lab blank,
`validity = valid`, no hop flag (`p_spill = 0`), no contaminant or
failed-library flag.

**`Catostomus occidentalis` @ Punta Banda -- A REAL DEFECT.**
The input BLAST row has **no genus and no species name**, 99.4% identity and
`# species = 7`: the upstream consensus declined to name even a genus. The
pipeline output a species at `consensus_posterior = 1.00`. Of the unit's 20
hypotheses, *C. occidentalis* ranks **19th by posterior** (2.17e-05 against
*C. macrocheilus* 0.139) and **last by prior** -- it is the one Catostomus with
a modelled kernel prior, and that model says 8.885e-09, **398x BELOW the
3.535e-06 floor its unmodelled congeners receive.** So the prior argued against
it too. `likelihood_support = 0.0084`.

The chain:
1. `estimate_kernel_priors_from_counts(habitat_filter = "none")` -- **the
   package default** -- admits a freshwater sucker into a Marine site's prior
   pool. (`main_habitat` is the SITE's habitat, not the taxon's, so it is not a
   mislabel and TaxaHabitat never asserted "Marine" for this fish. The
   capability exists -- `habitat_filter = "taxon_threshold"` with a
   `build_habitat_lookup()` -- and **was simply not switched on.**)
2. `.credible_node()` CORRECTLY declines a species call: no Catostomus species
   holds the threshold, so it calls **genus Catostomus**.
3. `.downrank_consensus()` finds `species_ref` holds **exactly one** Catostomus
   at that site and relabels the genus call to it.
4. Its `require_candidate` gate passes because *C. occidentalis* **is among the
   scored candidates** -- `is_restored = TRUE`, restored with an imputed score.
   **The gate tests MEMBERSHIP, not SUPPORT.**
5. `.downrank_consensus()` rewrites `consensus_taxon`, `consensus_rank`,
   `is_resolved` and `downranked` -- **and nothing else.** So
   `consensus_posterior` still describes the GENUS node. The reported 1.00 is
   arithmetically right about a proposition nobody asked.

**The defect is narrow.** 724 of 49,466 units are downranked (1.5%), 451 to
species, and their median `likelihood_support` is **0.910** -- downranking is
usually well earned. Only **6** downranked species calls sit below 10% support
(12S 4, COI 2), only **4** of those also report posterior >= 0.99, and only
**one** is below 1%: this call. It is the worst in the dataset.

**`Microgadus proximus` @ Punta Rompiente -- NOT a defect.** BLAST gives
99.4-100% identity with **`# species = 1`**: one species in the hit set, named.
The identification is clean; the biology is wrong, out of range by ~1,500 km.
`likelihood_support` 0.49-0.56, the competitor being the unreferenced
"some other *Microgadus*" ring, and the genus holds two species. The prior was
correctly tiny (1.47e-06) and a saturated likelihood swamped it. That is the
Bayes arithmetic behaving as specified, not a bug. **Worth noting:
`ESV_065368` appears at BOTH Duxbury Reef (in range, 71 reads) and Punta
Rompiente (out of range, 112 reads) in the same batch -- the shape of a
cross-contamination or hop, which the hop filter cleared at `p_spill = 0`.
Unconfirmed; worth a look.**

**The guards mostly HELD, which is the context both errors need.** 12S carries
substantial non-marine fish: *Salmo salar* at 100% with 5,581 reads,
*Platygobio gracilis* (Great Plains) 6,521 reads, *Rhinichthys atratulus*
(eastern US), *Oncorhynchus*, *Prosopium*. Of 62 such consensus units, the
pipeline held **almost all at genus or coarser**: *Platygobio* 12 of 12 genus
despite 100% identity and one species in the hit set; *Catostomus* 12 of 13
genus; *Rhinichthys*, *Cyprinus*, *Cyprinidae* likewise. ***Salmo salar* never
becomes a call at all.** The species-level escapes are *C. occidentalis*,
*Gambusia affinis* (already on the exclusions list), and two defensible ones
(*O. tshawytscha* at Duxbury, *F. parvipinnis*).

**The general vulnerability, in one line:** `.downrank_consensus()` consults
neither the likelihood nor the prior -- it is a reference-set lookup gated on
candidate membership, and it carries the coarse node's posterior onto the finer
label. It will fire wherever a genus has one locally-recorded species and
better-matching non-local congeners, which is common. **`X..species` (the
number of species in the BLAST hit set) is present in the input, is exactly the
discriminating field -- 7 for Catostomus against 1 for Microgadus -- and
nothing gates on it.**

Not fixed; diagnosis only. Also logged, not fixed: `build_context()` returns a
single-ecoregion context and `review_assignments()` uses it as GEOGRAPHY
(TaxaFlag review_assignments.R:1390), a footgun for multi-ecoregion studies.

### The downranking fix, MEASURED -- and my first proposal was wrong (2026-10-13)

**I proposed requiring the relabel target to be the ARGMAX at the finer rank.
The measurement refutes it: that blocks 28 of 451 downranked species calls, and
27 of the 28 look CORRECT.** The downranking is mostly correcting
**reference-database bias** -- choosing the regionally-recorded species over a
better-matching congener that is over-represented in GenBank:
*Kirchenpaueria goodei* over cosmopolitan *K. pinnata* (16 calls, 106 species in
the candidate set), *Ectocarpus commensalis* over the model organism
*E. siliculosus* (5), *Atherinops affinis*, *Hyporhamphus rosae* over the
Panamanian *H. naos*, *Stenobrachius leucopsarus*. Blocking those to fix one bad
call is a bad trade. **Argmax is withdrawn.**

**What separates the bad call is its OWN plausibility, and the separation is
enormous.** Among the 28, own share of species-rank mass: min **2.35e-05**
(*Catostomus occidentalis*), **second lowest 0.120**, median 0.313, max 0.424.
A **5,000x gap** with nothing in between.

**THE FIX: `.downrank_consensus()`'s `require_candidate` gate must require the
proposed taxon to be plausible IN ITS OWN RIGHT -- at or above
`min_posterior` -- not merely a MEMBER of `plausible_taxa`.** The row's
`plausible_taxa` is padded whenever `tail_pooled = TRUE`: the tail block joins
the plausible set, so a taxon holding 2.35e-05 enters the candidate list and
satisfies a membership test. `min_posterior` is **already a parameter of the
call** (0.05 in this run), so this introduces **no new knob**.

Measured over all 451 downranked species calls, own share below:
  0.001 -> 1 blocked | 0.005 -> 1 | 0.01 -> 1 | 0.02 -> 1 | 0.05 -> 1
**Every cutoff across three orders of magnitude blocks exactly the one bad call
and costs none of the other 450.** The result does not depend on the value,
which is what makes it robust rather than tuned.

### The hop check: it never ran, and it is right that this is not a hop

- **NOT WIRED IN.** `DROP_FLAGS <- character(0)` in
  `build_reads_long_hopflagged.R`, and only that builder and
  `failed_library_flags.R` read the hopflagged files -- the main workflow never
  does. **The hop flag has never filtered a detection, R1013 included.** It is
  diagnostic only.
- **It also correctly excludes diffuse hopping here.** All eleven 12S runs:
  `basis = controls`, `spill_reads = 0`, `rate = 0`, `evidence = "bound_only"`.
  JVB3735 (the batch carrying BOTH errors): `rate_upper = 9.57e-06`,
  `n_control_excess = 40`, `rate_untrimmed = 0.0094`. Explaining 112 reads in
  the receiver needs a rate ~4 orders of magnitude above that bound.
  **So my "shape of a hop" remark on ESV_065368 was wrong** -- the estimator
  rules it out quantitatively. The remaining explanations are well-to-well
  contamination or a true detection.
- **The real gap: contamination has NO detector.** The 2026-09-27 decision was
  that `flag_hopped_detections()` stays hops-only and that dropping
  contaminated blanks would be a SEPARATE function. **That second function was
  never built.** So hopping has a detector that is not connected, and
  contamination has none at all.
- `evidence = "bound_only"` on every run means no run ever had positive hop
  evidence, which is why `p_spill = 0` everywhere. `dispersion = Inf` on every
  run deserves one look, but with `rate_upper ~1e-5` the bound is not vacuous.

**Closed, incidentally:** the `712ed59` unit mismatch. `consensus_settings$species_reference`
has **3,489 rows**, so my "49 of 3,489 family assignments" counted changes in
that table and the workflow session's 99 counted (marker, taxon) rows. Both
right, different denominators, now reconciled.

### The fix BUILT on branch `downrank-own-plausibility` (2026-10-13)

Two commits, `e8a952e` then `523acaa`, on a worktree at
`~/taxaid-worktrees/downrank`. **Not merged.**

`.downrank_consensus()`'s `require_candidate` gate now also requires the
plausible set to place at least `min_posterior` on the proposed taxon, **for a
step to the finest rank only**. No new parameter: the floor is `min_posterior`,
already an argument of `posterior_consensus()`. `min_posterior = 0`, a missing
`plausible_posteriors` column, or `require_candidate = FALSE` each leave the
old behaviour byte for byte.

**END-TO-END VALIDATED, not just predicted.** Re-ran the real consensus over
all **724** downranked R1013 observations under main's TaxaAssign and under the
branch's, same settings read off `attr(cf, "consensus_settings")`, offline.
Baseline reproduced the archive exactly (724 rows, 451 species calls).
Branch: **exactly ONE call changes** -- `12S_ESV_145566@Punta Banda`,
*Catostomus occidentalis* (species) -> *Catostomus* (genus). **0 units to or
from no call**, `downranked` count unchanged at 712.

**That end-to-end run EARNED ITS KEEP: it caught a regression the unit tests
and the per-call measurement both missed.** My first version gated every rank
and changed **27** calls -- 26 of them genus falling back to class. Cause: a
coarse node's mass can only be assembled from plausible rows that map into
`species_reference`, while `min_posterior` is read against the WHOLE plausible
set, and the unmappable rows (ring and unreferenced hypotheses, names coarser
than species) are usually most of the mass. **I compared a node's MAPPABLE mass
against a floor derived from TOTAL mass.** The species-only measurement could
not see it because every one of the 26 sits at genus rank.

Two alternatives measured and rejected, both recorded in the roxygen: argmax
(blocks 28, 27 of them the reference-bias correction) and all-rank gating
(blocks 26 more).

**Tests/checks:** TaxaAssign 1371 -> 1395 assertions, 0 failures, warnings
unchanged 57 -> 57. TaxaExpect 811 and TaxaFlag 1016 unchanged, 0 failures,
warnings 60 and 18 unchanged. All three regenerated Rd files validate clean.
**Exports unchanged: 14/17/16.** No public signature changed -- `min_posterior`
already existed on `posterior_consensus()`; `.cand_rank_mass()` is a local
closure inside an `@noRd` internal.

**No NEWS entry, deliberately.** All nine NEWS files say "Initial release" for
0.1.0 and nothing has shipped, so there is no released behaviour to describe a
change against; adding one would be exactly the history-in-NEWS the freeze
forbids.

**RE-RUN COST IS MUCH LOWER THAN I FIRST TOLD KEVIN.** `.LIK_CODE_PKGS` is
`TaxaLikely`, `TaxaMatch`, `TaxaTools` -- **TaxaAssign is in neither the Step 7
code key nor the refs key.** So the reference freeze and the Step 7 likelihood
checkpoints both stay valid and nothing retrains; only the consensus stage
onward needs rerunning. The workflow session should confirm the exact stage
boundary and quote the real cost.

**Doc-only, same branch:** `estimate_kernel_priors_from_counts()` now states
that `habitat_filter = "none"` (the default) admits a taxon of ANY habitat to a
site's composition and that `main_habitat` is the SITE's habitat;
`flag_hopped_detections()` gains "What 'not spillover' does not mean". Two of
the three doc changes I proposed turned out to be **already written** --
`consensus_posterior` already says it reports the pre-downranking node, and the
hop function already carries the `bound_only` caveat and the
`flag_contaminant()` cross-reference -- so only the genuinely missing parts
were added.

### MERGED and INSTALLED, re-run handed off (2026-10-13)

**`dafe7a2`** on main, a `--no-ff` merge of `downrank-own-plausibility`
(`e8a952e`, `523acaa`), pushed. Branch kept for provenance; its worktree
removed with `rm -rf` + `git worktree prune` (git 2.15 has no
`worktree remove`).

**Tests on the MERGED tip:** TaxaAssign 1,395 assertions / 0 failures / 57
warnings, TaxaExpect 811 / 0 / 60, TaxaFlag 1,016 / 0 / 18 -- warning counts
identical to pre-merge main in all three.

**Installed** at 14:46 HST after confirming **no R-family process was alive**:
TaxaAssign, TaxaExpect, TaxaFlag into `~/Library/R/4.0/library`. Verified
function by function against `dafe7a2`: **1,068 functions, 0 body or signature
differences**, 174 verbatim files md5-identical, the only flags being the two
known comparison artefacts (DESCRIPTION line-wrapping, `%||%` Rd escaping).
Exports unchanged 14/17/16; no public signature changed.
*(`devtools::install()` takes neither `lib` nor `upgrade = "never"` -- set
`.libPaths()` so the user library is first, and pass `upgrade = FALSE`.)*

**Re-run handed to the workflow session**, with three things asked of it:
1. **Confirm against the real keys that nothing retrains.** `.LIK_CODE_PKGS` is
   TaxaLikely/TaxaMatch/TaxaTools and `fetch_code` digests
   `fetch_ncbi_reference_sequences`, so TaxaAssign is in neither key and only
   the consensus stage onward should rerun. If a preflight disagrees, stop --
   that would mean the key coverage is wrong.
2. **The expected delta is exactly ONE call**, already validated over all 724
   downranked observations: `12S_ESV_145566@Punta Banda`,
   *Catostomus occidentalis* species -> *Catostomus* genus, 0 to or from no
   call. Anything beyond it is a finding to be named, not reconciled.
3. **Compare at EVERY rank, not just species.** A species-call count alone
   would have read 451 -> 450 and looked perfect while my first version
   silently coarsened 26 genus calls to class.

**Reports session told to HOLD the deposit.** The `calintertidal-R1013` tag and
code zip remain correct *for the R1013 results*, but those results are now to
be superseded, so nothing ships; a new tag and a fresh function-by-function
check follow the re-run. Noted for them that *Catostomus occidentalis* becomes
redundant on the R1013x exclusions list -- the pipeline now declines that
species call itself -- while *Gambusia affinis* and *Microgadus proximus* still
need it, *Microgadus* being a clean identification merely out of range.

### Kevin: re-run and REPLACE the deposit; 13 GB authorised (2026-10-13)

The R1013 deposit had **already shipped** -- the Zegar_Dryad swap finished
13:44 HST, an hour BEFORE the merge (`dafe7a2`, 14:45), and Kevin emailed Alexa
the same day. My "hold the deposit" reached the reports session too late and was
withdrawn as an instruction; moving a public deposit is Kevin's call.

Put to him as two questions. His answers, verbatim: **"Re-run and replace the
deposit"** and **"Authorised, up to 13 GB"**.

**He chose this AGAINST my recommendation.** I argued for leaving the deposit
and documenting the one artefact: the products are unaffected (the genus call
enters no species product and the taxon was already on the reviewed-exclusions
list), the deposit is reproducible from its tag, and the archive keeps
*Microgadus proximus* and *Gambusia affinis* either way -- so a re-run makes it
marginally less wrong rather than safe to use naively. He is error-first and
wants the archive itself correct. Recorded because the reasoning stays useful
even though the decision went the other way.

**The complete set of units that CAN change is the 724 downranked in R1013.**
The fix only ever BLOCKS a downranking step, so it cannot make a row become
downranked; any row not downranked before is untouched by construction. So the
pre-merge validation already covered every changeable unit, and **a changed
unit outside those 724 would mean the mechanism is misunderstood**, not merely
that something unexpected happened. The workflow session was told to call that
out loudly rather than fold it into a count.

**Cost, corrected by the workflow session's dry run (NEXTRUN_DRYRUN=1,
`run_next_2026-10-13_1448.stages`):** ~2.7 h, peak 12.3-12.8 GB, VERDICT 0 full
restore -- refs FROZEN with `fetch_code` and `prep_code` matching, lik RESTORE,
matrix REUSABLE, and `TAXAID_REQUIRE_RESTORE=1` so W1 would STOP rather than
silently retrain. **My "only the consensus stage onward" was wrong:** Round 1's
own consensus calls `posterior_consensus()` and the Round-2 update reads it, so
the boundary is Section 8 Round 1 onward -- Round 1 -> U -> B -> W2 -> P -> D ->
R -> X. "Nothing retrains" held and was confirmed against the real keys.

**On the audit: the INSTALL was my inference, not Kevin's word.** He approved
build ("approved"), merge and re-run ("ok. Note that merge and re-run"); he
never said "install". Left on the record as an inference -- the later re-run
approval does not retroactively authorise it. The offered install rollback to
`5df0b6e` is now moot, since `dafe7a2` is the code that will produce the new
results.

**AFTER THE RUN, do not reuse R1013's paperwork:**
- a FRESH function-by-function check against **`dafe7a2`** -- the commit
  actually installed for the run, not main's tip `868511e`, which is docs-only
  on top (package subtrees identical, so `dafe7a2` is the honest citation);
- the Step 7 provenance check REDONE from the new `lik_*.dep` digests. The run
  is a RESTORE, so **the likelihood models will predate the cited commit and
  R1013's "trained in this run by the cited commit" wording will be FALSE for
  the new deposit** -- it must be rewritten, closer to R1009f's form;
- a new tag. **`calintertidal-R1013` is taken and the run is on the same date,
  so the label collides** (`R1013x` is the report-products label). Waiting on
  Kevin's convention before tagging anything.
- **The correction email to Alexa about which version is current is Kevin's to
  send.** Nobody drafts or sends it on his behalf.

### R1013b re-run LAUNCHED (2026-10-13)

`run_next_2026-10-13_1502`, started **Tue Oct 13 15:02:12 HST 2026**, report
tables ~17:35 HST, all done ~17:47 HST. Preflight **VERDICT 0, full restore**;
installed TaxaAssign built 2026-10-14 00:46:32 UTC, i.e. **`dafe7a2`**. R1013's
outputs archived to `archive_2026-10-13_0406_PROVISIONAL/`, so the live
deposit's source files stay recoverable -- which matters more than usual, the
deposit being already public.

**Ceiling 16 GB on Kevin's direct word** ("16 GB (Recommended)"), chosen over
keeping 13 GB with a watcher and over not re-running. Enforced by an external
sidecar that stops the stage's process group on breach, rather than trusting
the stage to behave. The revised peak range was verified from the `.rss` logs
rather than relayed: `2026-10-09_2123` W1 15.67 / U 14.23, R1009f W1 14.54 / U
14.17, R1013 W1 12.80 / U 11.79 -- two of three over 13 GB. R1013's low reading
is **unexplained**; restore-versus-rebuild is ruled out, R1009f having been a
rebuild at 14.54. Sized for the measured maximum, not for a theory.

**LABEL STILL UNCONFIRMED BY KEVIN. Do not tag.** `R1013b` /
`calintertidal-R1013b` / `code_<date>_R1013b.zip` / products `R1013bx` is the
proposal from the workflow and reports sessions, following the R1009 ->
R1009d/e/f same-date letter habit. I briefly wrote "confirmed as coordinator",
meaning myself as the tag owner; the peer coordinator read "the coordinator" as
itself and both peers then held. **My wording was the fault** -- two sessions
answer to that word -- and the label is back to provisional. Nothing is blocked:
no tag should exist until the run has used `dafe7a2`, since tagging earlier
names a commit as producing results that do not yet exist.

**I did not substitute my GO for the peer coordinator's.** The workflow
session's heavy-run gate is theirs; I sent them Kevin's verbatim words and
asked them to release it, and have asked the workflow session to confirm for
the record that it arrived before launch.

**AFTER THE RUN, four things, none reused from R1013:**
1. fresh function-by-function check against **`dafe7a2`**;
2. Step 7 provenance redone from the new `lik_*.dep` digests -- VERDICT 0 means
   a RESTORE, so the models are unchanged from R1013's and **predate** the cited
   commit; R1013's "trained in this run by the cited commit" wording is FALSE
   here. Frame it positively: models unchanged is what makes the one-call
   difference attributable to the consensus fix alone;
3. the measurement at every rank, both Round-1 and final consensus, the
   `downranked` count (expect 724 -> 723), and **explicitly whether any changed
   unit fell OUTSIDE R1013's 724 downranked units** -- that is the structural
   test, and if it fires my account of the mechanism is wrong and that is the
   headline;
4. the tag, once Kevin names the label.

**The correction email to Alexa is Kevin's.** Both peers told nobody drafts it.

**Both gates CONFIRMED satisfied before launch.** The workflow session reports
the peer coordinator's GO arrived first, relaying Kevin's word "go", and naming
the command, archive-first and the 16 GB hard ceiling. Last pre-launch check
15:02:08 HST, driver start 15:02:12 HST. **It did not launch on my relay of
Kevin's ceiling alone**, which is what I asked it to confirm and the answer I
wanted. Open question closed.

### Archive label convention CHANGED by Kevin (2026-10-13)

`R1013b` is dropped. Kevin chose **release number plus ISO date**, with the
content deliberately OUT of the identifier:

    tag        calintertidal-r<N>-2026-10-13
    zip        code_2026-10-13_r<N>.zip
    run        run_next_2026-10-13_1502
    products   r<N>x

**Digit pending his one-line confirmation; expect `r3`.** His selected preview
mapped `r1` to "R1009f / R1013" jointly, which points one release number at two
different public deposits and two code states -- the very ambiguity a release
number exists to remove. Counting DEPOSITS instead makes each number 1:1 with a
code state: **r1 = R1009f (`068d6ff`), r2 = R1013 (`5df0b6e`), r3 = this one
(`dafe7a2`)**. Put back to him; `r2` is the fallback if he prefers the collapse.
Not treating my own correction as decided.

**Two alternatives rejected, with the reasons, because they will come round
again:**
- **A content slug** (`...-downrank-gate`) asserts what a run is about, and an
  assertion can become WRONG and then cannot be corrected once cited. R1013 is
  the proof: four behaviour changes plus an unmeasured `named_rows` x Round-2
  interaction, so any slug would have misdescribed it. A date or an ordinal can
  never become wrong.
- **Tying the archive label to the package version.** The nine packages are
  0.1.0 heading to 1.0.0; conflating a dataset release with a package release
  confuses both.

**THE CONSEQUENCE THAT MATTERS: with content out of the identifier, the
annotated tag message and `code_notes_*.md` are now the ONLY place the content
lives.** Both must state, explicitly: the commit; that the models were RESTORED
and predate it; the single changed call; and which Dryad state it supersedes.
Told to Intertidal Reports for the notes, and it goes in the tag message too.

**Old tags are NOT renamed.** `calintertidal-R1009f` and `calintertidal-R1013`
correctly identify what they identify; only the r-number mapping is recorded, so
nothing looks retroactively renamed.

**LABEL FINAL: `calintertidal-r2-2026-10-13`** (zip `code_2026-10-13_r2.zip`,
products `r2x`). Kevin chose the **collapse** over my r3 correction: I proposed
counting deposits so each number maps 1:1 to a code state, he considered it and
kept r1 covering both earlier deposits. Recorded so the trail shows the
objection was raised and overruled, not skipped.

**The collapse is coherent on his own scheme, which I missed at first:** the
number is a **RELEASE** ordinal -- r1 the pre-fix analysis, r2 the corrected one
-- not a deposit ordinal. The two r1 deposits were the same analysis era at
different stages of reporting polish. That fits his decision to keep content out
of the identifier.

**What makes it safe:** the mapping must be SPELLED OUT in both the notes and
the annotated tag message, since the number alone no longer disambiguates --

    r1  pre-fix analysis, deposited twice:
          R1009f  068d6ff   (first Zegar_Dryad deposit)
          R1013   5df0b6e   (swapped in 2026-10-13 13:44 HST)
    r2  corrected analysis:
          dafe7a2, run run_next_2026-10-13_1502

Without that block anyone reconciling r1 to a commit gets two answers and no way
to choose. It goes in `code_notes_2026-10-13_r2_taxaid.md` AND in the tag
message, so it is recoverable from the tag alone.

## r2 post-run verification (coordinator, 2026-10-13 17:2x HST)

Run `run_next_2026-10-13_1502` finished **17:14:29 HST**, rc=0 at every stage.
Peaks: W1 13.71 GB, U 11.50, B 3.10, W2 7.68, P 5.68, D 1.52, R 5.35, X 5.96.
The 16 GB sidecar never fired; 13.71 GB sits inside the earlier 12.8-15.7 GB range.

### The call change: one unit, as designed

`12S_ESV_145566@Punta Banda`: `Catostomus occidentalis` (species) ->
`Catostomus` (genus). `likelihood_support` 0.008 -> 0.967. Identical at Round 1
and at the final consensus. `consensus_posterior` unchanged at 0.99999999865 --
which is the point: that number was always the genus node's mass, printed
beside a species whose own posterior was 2.1e-5.

Verified independently at the report-table level by the coordinator, not taken
from the measuring session's report:

- `consensus_rank_summary`: species 13,765/384 -> 13,764/383; genus 5,520 -> 5,521
  (distinct genera stay 263 -- `Catostomus` was already a genus-level call elsewhere).
- `scope_audit`: Chordata 178 -> 177. `site_marker_long`: 12S Punta Banda 46 -> 45.
- `backbone_conflicts_by_observation`: 92 of 49,466 rows differ. Exactly **one**
  differs in a call column (that unit); the other 91 differ only in
  `backbone_conflict_mass`, at a maximum relative difference of **8.37e-15**.

### Two predictions, one of them wrong

- **Structural test PASSES.** 0 changed units fall outside R1013's 724 downranked
  units, at Round 1 and final. The mechanism account holds.
- **`downranked` 724 -> 724, NOT 723. The coordinator's predicted 723 was wrong.**
  The gate `break`s out of the rank walk, so a coarser step already taken in the
  same walk survives: blocking the species step leaves the row downranked **to
  genus** instead of making it not-downranked. The code did what was written; the
  arithmetic prediction misread its own control flow. Any future count of this
  kind must be derived from the loop's exit behaviour, not from "one fewer".

### Install provenance vs dafe7a2 -- fresh, nothing reused from R1013

`1068` source functions across the nine packages; `1068` identical in the
install; 0 missing, 0 differing, 0 namespace-only. `dafe7a2..HEAD` touches only
`ecosystem_docs/`, so the checked tree is dafe7a2's package tree.

### Step 7 provenance: the models PREDATE the cited commit

`lik_{COI,12S,18S}.dep` mtimes are **2026-10-13 01:32:23 / 01:50:21 / 02:06:08
HST** -- the R1013 run. The r2 run did not rewrite them; preflight said
`VERDICT 0: full restore`. The code part of all three keys is
`TaxaLikely=f454a321;TaxaMatch=a18606a7;TaxaTools=22234a73`, and
`git diff 5df0b6e dafe7a2 -- TaxaLikely TaxaMatch TaxaTools` is **empty**, so the
restore is legitimate. But the models were *trained* under 5df0b6e, hours before
dafe7a2 existed.

**R1013's wording "trained in this run by the cited commit" is FALSE for r2 and
must not be carried over.** Correct form: trained 2026-10-13 01:32-02:06 HST
under 5df0b6e; restored unchanged in r2; the three packages in the Step 7 code
key are byte-identical between 5df0b6e and dafe7a2.

`TaxaExpect` and `TaxaFlag` changed in dafe7a2 only in roxygen -- verified: every
changed line in their `R/` sources begins with `#'`. No executable change, so no
prior or theta digest moves.

### Two reproducibility findings, neither changing a call

Both are "same code, same inputs, different numbers". Severity differs by
whether the column is deposited -- checked, not assumed:

1. **`consensus_confidence_score` varies run to run.** 876 final units (881 at
   Round 1), all 24 sites, every rank; median 0.002, p99 0.048, max 0.068.
   Cause: `compute_posterior(likelihoods_ready, n_sims = 1000L)` at
   `workflow:3960` has no `set.seed` before it, so its stream depends on
   everything W1 consumed first, and a restore consumes differently from a
   rebuild. **Does NOT reach the deposit**: the column is in neither
   `ESV_site_calls.csv` (40 columns, checked) nor any report table. The only
   `confidence` column deposited is `habitat_confidence`, unrelated.
   Seeding is a one-line workflow change and would itself move every score, so
   it should ride along with the next run rather than trigger one.
2. **Exactly tied candidates come out in a different order** -- plausible lists
   reordered on 12,816 units, always within equal posteriors. On 4 units the
   order decides which tied candidate makes the cut, so the plausible SET
   differs: `12S_ESV_027411@Landing Cove` (*Gnathophis ginanago* /
   *nystromi*), `12S_ESV_091843@Punta Abreojos` (*Cottus specus* /
   *Cottocomephorus grewingki*), and two 18S no-call units. Calls unchanged.
   **This one DOES reach the deposit**, via `plausible_top` and `n_plausible`.
   A deterministic tie order would be a TaxaAssign change, so it is not a 1.0
   candidate under freeze without the maintainer's word.

The measuring session's guess that Round-1 values carry into the 618
`prior_updated` units of finding 1 is **unverified** and recorded as a guess.

### Still open

The tag `calintertidal-r2-2026-10-13` on `dafe7a2` is NOT created -- it waits on
Kevin. Replacing the Dryad deposit is Kevin's; no session has touched Dryad.

### Tag created 2026-10-13 20:02 HST

Kevin answered "yes" to the coordinator's question, which covered the label and
the push together.

```
calintertidal-r2-2026-10-13
  tag object  b53789aafe53d2a0c9ee5d48b8a91c2ed4fe6005
  commit      dafe7a2d39e2e0592554ef2be2826852375c2d6b
```

Verified against the remote, not only locally. Cite **dafe7a2** in anything that
must resolve to a tree; a tag can be moved, a commit cannot.

The annotated message is self-contained: the r1/r2 mapping with both r1 deposits,
the code change, the one changed call, `downranked` staying 724 and why, the
report-table deltas, the Step 7 paragraph (models trained 01:32-02:06 HST under
5df0b6e, restored unchanged, with an explicit "do not describe these models as
trained by this commit"), the 1068/1068 install check, the 13.71 GB peak, and the
two known-not-fixed reproducibility items.

Remaining and NOT a session's to do: replacing the Dryad deposit, and the
correction email to Alexa about which deposit version is current. Both Kevin's.

## Row 212 actioned: 1.0.0 bump and branch (2026-10-13 20:3x HST)

Maintainer's go. `dae3b9c` bumps 29 files: nine package `DESCRIPTION`s, the root
meta-package `DESCRIPTION`, nine `NEWS.md` headings, nine `inst/CITATION` notes,
and `code.json` (`version` + `lastModified`). Branch `1.0.0` created at
`dae3b9c`.

NEWS headings were **relabelled**, not given a new section: 0.1.0 was never
released (no tag, no bump on record), so a changelog entry for it would describe
a release that does not exist.

### What the bump deliberately does NOT claim

`DISCLAIMER.md` keeps the provisional text and `code.json` keeps
`"status": "Preliminary"`. Maintainer agreed explicitly: "don't touch the
disclaimer". A version number is not a release approval, and the official path
still needs the IPDS record, a reserved DOI, administrative security review,
technical code review, domain review, Research Manager approval, Center Director
approval, and the GitHub -> USGS GitLab migration.

**The `1.0.0` branch is a version marker, not a USGS release candidate.** In the
WERC checklist "create release candidate branch named after version number" sits
*after* those approvals. The name must not be read as implying them.

`inst/*_review_response.md` keep the version each records as reviewed
(e.g. `TaxaMatch 0.1.0`) -- that is a fact about what the reviewer read, and
bumping it would falsify the review record.

### Still to follow

The ten generated `llm_prompts/CONTEXT_*.md` files carry the version and export
counts from `utils::packageDescription()`, i.e. the INSTALLED package, so they
are regenerated by `TaxaWizard::pack()` after an install at 1.0.0 -- never
hand-edited. The install is blocked while any R-family process is alive.

### Verification

Checked CI-style on the BUMPED tree, not before the bump:
`rcmdcheck(args = c("--no-manual", "--as-cran"), build_args = "--no-manual")`
with `_R_CHECK_CRAN_INCOMING_=false` and `_R_CHECK_SYSTEM_CLOCK_=0`, so neither
network-dependent result can wander between runs.

### 1.0.0 install: WINDOW AGREED ~02:00 HST 2026-10-14

Pushed and done: `main` and branch `1.0.0` both at `44e8a6e`. All nine check
`0 errors / 0 warnings / 0 notes` CI-style on the BUMPED tree, with
`_R_CHECK_CRAN_INCOMING_=false` and `_R_CHECK_SYSTEM_CLOCK_=0` so neither
network-dependent result can wander.

`44e8a6e` also fixes a defect the bump did not cause: `review_assignments()`
called `cli::cli_abort()` while TaxaFlag never declared `cli` (introduced
`fbdd99f`, 2026-10-12 22:09). It always resolved -- `cli` is the first entry in
dplyr's own Imports and TaxaFlag imports dplyr -- so it was a declaration bug,
not a runtime failure, and no result anywhere is affected.

**CI could not have caught it.** `.github/workflows/R-CMD-check.yaml:126` sets
`error_on = "error"`, so warnings never fail the build. All nine are now at zero
warnings, which makes `error_on = "warning"` safe to adopt -- a maintainer policy
call, not taken here.

**`dafe7a2` (tag `calintertidal-r2-2026-10-13`) carries the undeclared import.**
The tag stays: reporting already has that SHA, re-pointing a published tag is
worse than the defect, and no deposited number changes. The r2 tree and the
1.0.0 tree differ by exactly that one DESCRIPTION line, so anything citing a
TREE for r2 work cites `dafe7a2`, never `1.0.0`.

### What the install window is for, and why it waited

The `sampling optimization` session runs frame-2 scripts back-to-back until
~02:00 HST. It demonstrated that none of its scripts loads any of the nine, and
that was verified independently here: `lsof` over every live R pid shows no file
open under `Library/R/4.0/library/Taxa*`, and `lsof +D` on TaxaFlag returns zero
handles. So installing early would have been safe in fact.

It waited anyway, for reasons unrelated to that evidence: the maintainer's
condition was "install when the peer's jobs finish", which a peer cannot relax;
and `lsof` reports what is open NOW, not what a later lazy `loadNamespace()`
might open during the remaining batch.

Agreed with that session: it messages at batch end and starts no R until told
the install is done.

### Then, in one unit

1. Install nine at 1.0.0 in CI's topological order (`TaxaTools, TaxaFetch,
   TaxaHabitat, TaxaMatch, TaxaLikely, TaxaExpect, TaxaAssign, TaxaFlag,
   TaxaWizard`), `upgrade = FALSE`, user library first via `.libPaths()`.
2. Confirm the Step 7 code key did NOT move, against the r2 preflight digests
   `TaxaLikely=f454a321... TaxaMatch=a18606a7... TaxaTools=22234a73...`. The
   digest hashes namespace objects and deparsed bodies, not the version string,
   so CalIntertidal should still RESTORE. If any digest moved, the next run
   would RETRAIN and that must reach Kevin before any run is scheduled.
3. Regenerate the ten `llm_prompts/CONTEXT_*.md` with
   `workflow_export_prompts("llm_prompts", overwrite = TRUE)` -- never by hand.
   Baseline to diff against: eight package files totalling **209** exports with
   **no `CONTEXT_TaxaWizard.md` at all**, against a ratified surface of 223. They
   predate the export prune (232 -> 223) and the four later ratifications, so
   the count delta measures how long they had drifted.

## 1.0.0 installed and context files regenerated (2026-10-14, 00:40-01:05 HST)

The `sampling optimization` session reported its frame-2 r2 batch finished at
00:39:44 HST with no R processes left. I confirmed zero R-family processes
myself before touching the library, installed, and messaged it when done; it
held all R for the duration.

**Installed:** all nine at **1.0.0** from this tree, CI's topological order
(TaxaTools, TaxaFetch, TaxaHabitat, TaxaMatch, TaxaLikely, TaxaExpect,
TaxaAssign, TaxaFlag, TaxaWizard), exit 0, every `packageVersion()` 1.0.0.

**Step 7 code key UNCHANGED.** Checked by extracting `.ns_code_digest()` from
the archived r2 workflow and running it verbatim, not by re-implementing it:

    TaxaLikely=f454a32185cdd13072be52ec8092cee1
    TaxaMatch =a18606a7d9084e8230fc94b16f0dfa00
    TaxaTools =22234a73a5eaead07b2dbf4d7b619ae4

identical to the r2 preflight. The next run RESTORES its trained models; it
does not retrain. This is the expected result and the reason is worth keeping:
the digest hashes namespace object names, deparsed function bodies and
`extdata` md5sums -- **the version string is not an input**, so a pure version
bump cannot move the key. Version only reaches the key through the
`stamps:` fallback, which fires when the digest fails or is unstable across
two processes, and which over-rebuilds by design.

**Context files regenerated** (`f644f61`), by
`workflow_export_prompts("llm_prompts", overwrite = TRUE,
placeholder_setup_report = TRUE)` -- never by hand. All nine version strings
now read 1.0.0; `SETUP_REPORT.md` is the placeholder (date only, no key
values).

Export-surface reconciliation against the ratified **223**:

    223 installed exports = 218 functions + 5 data objects
      TaxaTools    57 = 53 fn + 4 (barcode_length_defaults,
                        barcode_primer_defaults, extended_ranks, standard_ranks)
      TaxaHabitat  15 = 14 fn + 1 (example_habitat_scheme)
      TaxaFetch 32, TaxaMatch 30, TaxaLikely 33, TaxaExpect 17,
      TaxaFlag 16, TaxaAssign 14, TaxaWizard 9 -- all functions

The per-file headers count exported FUNCTIONS, and there is no
`CONTEXT_TaxaWizard.md`, so the eight files sum to **209 = 218 - 9**. The
223/209 gap is entirely the five data objects plus TaxaWizard, **not** missing
documentation -- 222 of the 223 are named somewhere in the generated prose.
The single exception is `TaxaTools::extended_ranks`, which no generated file
names; minor, logged, not fixed.

The other non-version diffs are roxygen drift the files had not picked up since
2026-10-10/11, including two newly documented arguments:
`update_prior_from_consensus(max_raise_factor=)` (the Round-2 bound, abaa60f)
and `review_assignments(consensus_provenance=)` (the argument whose
`cli::cli_abort()` exposed the undeclared import).

**Tips now:** `main` at `f644f61`, branch `1.0.0` at `44e8a6e`. The r2 tree
remains `dafe7a2`; anything citing a tree for r2 work cites `dafe7a2`, never
`1.0.0`.

All three items Kevin asked for are closed. Still awaiting his decision:
seeding `workflow:3960`; deterministic tie order (freeze-gated); tightening CI
to `error_on = "warning"` (safe today -- all nine at zero warnings).

## CI has been RED on main for 52 runs (found 2026-10-14 via PR #2)

**This was missed for four days, including by me.** I repeatedly reported "all
nine 0 errors / 0 warnings / 0 notes, CI-style" from LOCAL `rcmdcheck` runs and
never once looked at the actual GitHub Actions status. The local runs were
real; they were a proxy. Actual CI was failing the whole time.

**The streak:** last green run `64b5b37` (2026-10-01 19:39). First failure
`068d6ff` (2026-10-10 23:52). **52 consecutive failing runs** through
`6d5ef70`. Historical record is 137 success / 63 failure, so this is a
regression, not a never-worked state. Every commit in the r2 and 1.0.0 work
was pushed onto a red CI.

**Always the same single job: `Check TaxaMatch`.** Same cause from the first
failure to the last:

    Packages suggested but not available for checking: 'Biostrings', 'rBLAST'
    Error: Package 'Biostrings' is required for barcode_term trimming.
    Status: 1 ERROR, 1 WARNING, 1 NOTE

**Root cause.** `Biostrings` is in `TaxaMatch/DESCRIPTION` Suggests but is a
**Bioconductor** package, so `remotes::install_deps(dependencies = TRUE)`
cannot fetch it and CI installs nothing from Bioconductor at all. This is
exactly the `rnaturalearthhires` situation the CI file already special-cases at
line 122 -- Biostrings was never given the same treatment.
`TaxaMatch/R/trim_query_to_amplicon.R:170` then hard-`stop()`s, and **five**
tests reach that path with no guard:
`test-evaluate-reference-accessions.R:804, 883, 934, 2302, 2343`. Twenty other
Biostrings-dependent tests skip correctly; these five do not.

**Why local never caught it:** `Biostrings` and `rBLAST` are both installed in
`~/Library/R/4.0/library`. A local check exercises the real path; CI skips or
errors. **A local `rcmdcheck` is not CI.** Check the Actions status.

**PR #2 (`ci-warnings-gate`) result: 8 pass, 1 fail.** The failure is this
pre-existing error, NOT the gate change, and the status line proves the change
did what it claimed:

    main   @ 6d5ef70   Status: 1 ERROR, 1 WARNING, 1 NOTE
    branch @ 658a267   Status: 1 ERROR, 1 NOTE          <- warning gone

The ERROR would have failed under the old `error_on = "error"` too. Eight of
nine are green under `error_on = "warning"` on ubuntu with the latest R, which
is the platform risk the PR existed to measure -- it came back clean.

**Proposed fix (NOT built, awaiting Kevin).** Two parts, mirroring the
`rnaturalearthhires` precedent:
  (a) install Biostrings from Bioconductor in CI inside `try()` (non-fatal), so
      the barcode_term trimming path is actually exercised -- this is the
      coi-amplicon-gate code area;
  (b) add `skip_if_not_installed("Biostrings")` to the five tests, so the suite
      degrades to skips instead of errors when Bioconductor is unreachable.
Both: (a) for coverage, (b) so CI is not hostage to Bioconductor uptime.

A warnings gate is worth little on a permanently red CI, so this should land
before or with PR #2.

### PR #2 GREEN: 9/9 pass, Biostrings installs, 25 tests un-skipped (2026-10-14)

Run `38608020222` on `ci-warnings-gate` @ `039c054`: **all nine pass** under
`error_on = "warning"` on ubuntu-latest with the latest R. The 52-run red
streak is fixed, and the gate is enforceable on CI's real platform.

`Biostrings available: TRUE` -- BiocManager got a binary in ~3.5 min, so the
fix restored **coverage**, not skips. `{Biostrings} is not installed` appears
**zero** times in the log, against 20 before, and the five newly guarded tests
ran too: **25 TaxaMatch tests now execute in CI that previously skipped or
errored**, including the coi-amplicon-gate trimming path.

Advisory `Check URLs` step: success on all nine.

**Remaining NOTE, benign and not worth fixing.** Six packages report
`1 NOTE` -> `checking Rd cross-references ... NOTE / Unknown packages ... in
Rd xrefs` (e.g. TaxaTools cites TaxaLikely, TaxaMatch, TaxaFetch). The matrix
installs only the TARGET package's dependencies, so `\link[SiblingPkg]{}`
cross-references cannot resolve in that job. It is structural to the
per-package matrix, it is a NOTE so it does not gate the build, and it does
not appear locally because all nine are installed here. Fixing it would mean
installing all nine siblings in every job (slow, and it discards the isolation
the matrix exists to provide) or dropping cross-package `\link[]{}` refs.
Neither is worth it.

**One correction to the env work:** `_R_CHECK_SYSTEM_CLOCK_` is set to `FALSE`
by `r-lib/actions/setup-r@v2` itself from its own step onward -- the log shows
my `0` in the first three steps, then `FALSE` for the rest. So that pin was
**redundant**; harmless, and it still covers the pre-setup steps.
`_R_CHECK_CRAN_INCOMING_: false` IS load-bearing and survives as mine through
every step -- that is the pin the whole change depended on.

PR #2 is ready to merge on Kevin's word. Nothing is merged.

### MERGED and main is GREEN (2026-10-14)

PR #2 merged as `23215af` (merge commit, matching the repo's 176-merge
convention; both branch commits preserved, not squashed). CI run
`38610650310` on `main` @ `23215af`: **all nine jobs success.**

**The red streak is over at 53 runs** -- `068d6ff` (2026-10-10 23:52) through
`c935885`, ended by `23215af`. main now enforces `error_on = "warning"`.

Cleanup done: worktrees `amb`, `blank`, `coi`, `ciwarn` removed (`rm -rf` +
`git worktree prune`; git 2.15 has no `worktree remove`), each verified clean
and an ancestor of `origin/main` first; local branch refs deleted with
`git branch -d` so git re-checked the merge itself. `~/taxaid-worktrees/` now
holds only `main`. The shared Drive checkout was not touched -- it is on
`workflow-ptcon-multisite`, which is NOT merged and belongs to another session.

Still open, each needing Kevin's word:
- delete `origin/ci-warnings-gate` (merged; outward action on a public repo)
- delete local `downrank-own-plausibility` (`523acaa`, merged). Safe: the r2
  provenance is the TAG `calintertidal-r2-2026-10-13` -> `dafe7a2`, not this
  branch ref.
- **branch `1.0.0` (`44e8a6e`) now sits BEHIND main.** It predates the cli
  fix's CI enforcement, the URL corrections and the Biostrings fix, so it no
  longer marks a tree whose CI passes. At the real USGS release it should be
  re-cut from main rather than reused. Keeping it for now.

## Verified open-items sweep (2026-10-14)

Every claim below was checked against the code, not read off the board. Two of
the four items I had queued as "confident, outstanding" were already done, so
the board is the thing being corrected here.

**STRIKE -- verified closed, do not re-open:**
- Row 215 (em dashes): DONE at `d7f2523`. All three supplemental-methods files
  are at zero em dashes on the house `--`. TaxaLikely 187 double-hyphens.
- Row 219 "advertise `corroborate_references_locally()`": the README already
  had a dedicated section and a "run this before BLASTing anything"
  recommendation. What was missing was the SIZE of the saving; added at
  `88f9fc9` (3,507 of 6,618 accessions, 53%, ~0.3 s), framed as one reference
  set because the saving depends on how densely a set covers its own taxa.
- `TaxaTools::extended_ranks` "undocumented": NEVER A DEFECT. It has roxygen
  and `man/extended_ranks.Rd`. My earlier note conflated "not named in the
  generated CONTEXT prose" (which is just what the generator does with data
  objects) with "undocumented". Correction recorded.
- Row 207 (PtCon 12S B2 run): CLOSED by the maintainer 2026-10-14 --
  CalIntertidal supersedes it. Do not run it.
- Row 209's warning that the shared checkout holds an uncommitted README round
  which will conflict on its next pull: STALE. That checkout is clean; it has
  only four untracked `HANDOFF_*`/`REENTRY_*` files.
- single-ecoregion geography: FIXED at `983324c`, and my logged note had
  OVERSTATED it -- see below.
- Row 208 (cache refetch): AUTHORISED by the maintainer 2026-10-14. Precondition
  was already met (`c9e0a76` in main, reinstall done at 1.0.0). Each pre-A2
  project refetches once at its next Step 7; CalIntertidal unaffected.

**THE ONE SUBSTANTIVE UNFIXED DEFECT.** `restore_suppressed_candidates()` /
`TaxaLikely/R/restore_hierarchy.R` imputes the QUERY's score from
reference-vs-reference identity (median `seq_matrix` `p_match` between the
anchor's and the candidate's references). Valid only when the query matches its
anchor near-exactly. Verified still unfixed: the only "cap" in that file
(`.level4_attempt_allowed`, line 383) counts ALIGNMENT ATTEMPTS and has nothing
to do with the score. Measured scale on the 10-06 rerun's final files: inflated
restored rows are the Round-2 winner for 233 (12S) / 190 (18S) / 403 (COI)
ESV@site and drive species-rank consensus calls for 67 / 20 / 283 = **370
total**; COI excess median 8.7 points, max 30.1. An imputed score above every
observed hit manufactures a confident species call, which is the error
direction the maintainer weights most. Accepted fix framing:
`anchor - (100 - ref_ref)`, a conservative data-derived LOWER estimate, not a
triangle-inequality bound. NEEDS A DECISION -- it changes numbers.

**Open, needs a maintainer decision (all numbers-changing):** the restore
imputation above; deterministic tie ordering (reaches the deposit via
`plausible_top`/`n_plausible` on 4 units, no call changes); seeding
`workflow:3960` (`consensus_confidence_score`, 876 units, median 0.002,
reaches no deposited file); flipping `habitat_filter`'s default (still
`c("none", ...)` at `TaxaExpect/R/estimate_kernel_priors_from_counts.R:158`).

**Open, no decision needed, buildable whenever:**
- `taxa_lineage`'s name-keyed cache orphans silently -- verified no orphan
  handling in `TaxaLikely/R/fetch.R`. Wants a loud message naming the file
  count. Small.
- lineage-guard report split by whether the disagreement crosses a higher rank.
- `audit_barcode_coverage()`: 3-hour I/O-bound tail, possibly network. Batch
  the reads or make it opt-in. Not small.

**Verified NOT built, deferred past 1.0:**
- `DROP_FLAGS` wiring: exists ONLY in workflow scripts
  (`hop_wrapper_r2.R`, `build_reads_long_hopflagged.R`), zero package files.
- `X..species` BLAST hit-set ambiguity gate: absent from all nine packages.
- contaminated-blank detector: PARTIAL, and the board overstates it.
  `contaminated_blank` already exists as a verdict label in
  `review_sample_identity()`'s vocabulary; what does not exist is a standalone
  statistical detector. The only blank/contaminant export is
  `flag_contaminant()`.

**Housekeeping:** branch `1.0.0` (`44e8a6e`) now sits BEHIND main and predates
the CI enforcement -- re-cut it from main at the real USGS release rather than
reuse it. Four untracked files in the shared checkout belong to another session.
