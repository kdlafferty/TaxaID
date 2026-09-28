# Handoff: the sample identity gate, v2 (`classify_sample_identity()` + `review_sample_identity()`)

**Status: FOR THE WORKFLOW PEER TO TRY, NOT YET FOR PACKAGE REVIEW.** The user's order is:
1. the CalIntertidal session tests v2 on the real data and sends feedback;
2. this session fixes what it finds;
3. only then does package review get it.

**Where it lives.**

- **Branch:** `identity-gate-v2`, worktree `~/taxaid-worktrees/identity-gate-v2`, cut from main.
- **Main already has v1.** v1 (branch `sample-identity-gate`) was merged into main at 82d3bd0
  before the user's corrections arrived. v2 is a follow-up to that merge, not a replacement.
- **Not installed.** To test, `source()` the files from the worktree, as
  `CaliforniaIntertidal/identity_gate_validation/validate.R` does. Do not reinstall TaxaFlag
  under a live session.

## What the user decided (2026-09-28), and what changed because of it

**1. Scoping comes BEFORE the gate.**

- The gate compares a tube with the other tubes on its run. An out-of-scope sample on a run
  distorts that comparison.
- **What gets scoped out:** GALCXE1W, the Cataviña desert stream; the estuary and sandy-beach
  tubes; and the seven Perkos-mooring offshore bottles (S067801-S067807). All of them are
  out of scope for this study.
- **Blanks are always kept.** A tap-water blank belongs to its **filtering date**, not to a site:
  it was run during the filtering step on the sampling date. So S067800 and S067808 are both in
  scope, even though the offshore bottles next to them are not.

**2. The samples were NOT spiked.**

- The 12S feature present in every library from Event 5 on (JV's "PositiveControl") is reported
  as a **run-wide artifact to investigate**, with a warning. Nothing assumes it is expected.
- **How it is detected:** a feature in ≥90% of a run's field units (with ≥5 units) AND the
  majority of reads in ≥ half of that run's blanks (`artifact_fraction`). No name is used.
- **What the gate does with it:** sets it aside from identity evidence, because it is in every
  tube whatever the tube is, and lists it in `attr(, "runs")$run_wide_artifacts`.
- **A study that really spikes** declares it in `spike_taxa`. The feature is then set aside
  without a warning and listed in `declared_spikes`.
- **Still open, for JV:** where does this feature come from? It reaches every library.

**3. Blanks are tap water.** Tap water carries freshwater organisms, and its cleanliness varies.

- `review_sample_identity(blank_medium = "tap water")` tells the model that a blank consistent
  with its medium, or with handling, is acceptable.
- A blank carrying the SAMPLED environment's taxa is not acceptable.
- `blank_medium` is part of the cache key.
- This explains the freshwater taxa in the JVB3735 blanks (*Rhinichthys*, *Cottus*, *Physella*,
  *Gonium*), which v1 had left as an open protocol question.

**4. Thin studies are analysed, cautiously.** A run with few samples or no blanks gets "no
evidence of a problem". It is not blocked, and it is never passed off as "checked clean". The
status vocabulary is new:

| `identity_status` | meaning | `identity_status_reason` |
|---|---|---|
| `concordant` / `discordant` / `suspect` | a test ran and answered | `composition`, `diversity`, `diversity_on_failed_run`, `library_failed` |
| `inconclusive` | a test ran and could not discriminate | `no_power` |
| `untested` | no test ran | `no_blanks`, `unreplicated`, `uncomparable` |

- `unassessable` is gone.
- **Admission is set by `untested_policy`:**
  - `"admit"` (default) admits untested and inconclusive units;
  - `"hold_blanks"` holds untested and inconclusive blanks;
  - `"block"` holds all of them.
- **The user's condition: admission without evidence must be transparent.** It is reported in
  two places:
  - every row carries `identity_status_reason`;
  - every run prints `admitted WITHOUT a discriminating test: N unit(s) (untested/no_blanks n,
    inconclusive/no_power m ...)`.
- **A study with no labelled blanks at all** now runs, with a warning, and every unit comes out
  `untested`/`no_blanks`.
- **A run with no blank** gives its samples `untested`/`no_blanks`. They are no longer passed as
  concordant.

**5. The LLM gives a role verdict.** Admission stays the workflow's decision.

- `review_sample_identity()` returns `llm_role`: `blank`, `sample`, `positive_control`,
  `exclude` or `unknown`. This is alongside its verdict and suggested disposition.
- **To admit on the LLM's role**, set `classify_sample_identity(accept_llm_roles = TRUE)`.
  - It maps blank → confirm or reassign to blank, sample → confirm or reassign to sample,
    positive_control → reassign to positive control, and exclude → exclude the tube.
  - A person's recorded disposition always wins.
  - `disposition_source` says whether a disposition came from the `user` or the `llm`.
- **Default FALSE**, so the LLM's advice only.

**6. A neighbour (kNN) composition test was tried and not built.**

- **What it catches:** S067800.
- **Why it wasn't built:**
  - it flags 16 clean blanks, including S067808;
  - it is unstable on runs with only two blanks;
  - it cannot see a set of blanks that are all contaminated the same way;
  - it adds almost nothing on samples.
- **Diagnostic:** `identity_gate_validation/knn_test.R`.

**Unchanged from v1:**

- the unit (sample × marker × run);
- the signals (`validate_controls()` composition, Hill N1 diversity against a marker reference
  built outside the run, cross-marker agreement, and yield from `flag_failed_libraries()`);
- per-tube identity decisions and per-unit library decisions;
- the decision-record CSV;
- held means `pending_review`.

## Real-data result: CalIntertidal, scoped first, v2 (`identity_gate_validation/validate.R`)

**Every §8 check passes.**

| §8 requirement | result |
|---|---|
| S067800 18S + COI flagged | discordant in both, held |
| DWETWXWF, WCOFVUX2, JAC2V5IK (12S) held | held (unit or tube flag) |
| 18S JVB6164 + JVB6334 failed-run samples | all 80 `suspect`/`library_failed`, excluded |
| S067808 not flagged | concordant, admitted as a control |
| JVB5058 not flagged | not flagged |
| `low_yield` units not flagged | 36 units: 5 concordant, 31 inconclusive; none flagged |
| 18S JVB6164 blanks | `untested`/`uncomparable` (a failed run has nothing to compare against), admitted under the default policy |

**Totals.**

- **Samples:** 1,377 concordant, 494 inconclusive (`no_power`), 115 suspect (library), 2 discordant.
- **Blanks:** 118 concordant, 4 discordant, 39 suspect, 8 untested.
- **Held:** 90 units, from 32 tubes.

**Most inconclusive samples are on runs where the composition test has no power.** A test with
no power cannot say a sample is wrong. The v1 gate called these units concordant, which
overstated what had been checked.

**S067800 is only loosely like the offshore bottles.** The Bray-Curtis dissimilarities are:

| comparison | Bray-Curtis |
|---|---|
| S067800 vs the offshore bottles | 0.73 |
| S067800 vs the intertidal samples | 0.80 |
| offshore bottles vs each other | 0.45 |

Blanks are tied to the filtering date, and the offshore bottles were filtered in the same
series. So plankton contamination during filtering fits the data better than a mislabelled
offshore sample does.

The live LLM run on v2 (`identity_gate_validation/llm_review.R`, with `blank_medium =
"tap water"`) saves its output to `llm_review_out.rds` and its log to `llm_review_v2.log`.

## What the workflow peer should try, and report back

**Wiring,** at ingest, in this order:

1. scope;
2. `flag_failed_libraries()`;
3. the gate;
4. everything else, including `flag_hopped_detections()`, `flag_contaminant()` and
   `validate_controls()`.

```r
rl_all <- dplyr::filter(rl_all, is_blank | is_lab_blank | habitat %in% "rocky intertidal")   # 1. scope
ff <- flag_failed_libraries(rl_all, library_col = "event_id", sample_col = "Barcode",
  marker_col = "marker", run_col = "batch", count_col = "n_reads", taxon_col = "ESVId",
  control_samples = CTL)
gate <- classify_sample_identity(rl_all, failed_libraries = ff,
  library_col = "event_id", sample_col = "Barcode", marker_col = "marker", run_col = "batch",
  count_col = "n_reads", taxon_col = "ESVId", taxon_label_col = "name", control_samples = CTL,
  decisions_path = file.path(OUT_DIR, "identity_decisions.csv"), on_pending = "error")
runs_gate <- attr(gate, "runs")   # control_status, run_wide_artifacts: report both in the output
rl_all <- dplyr::filter(gate, admit)
CTL    <- unique(rl_all$Barcode[rl_all$admit_as == "control"])   # the control set from here on
```

**Then, once:**

```r
review_sample_identity(gate, context = CONTEXT, blank_medium = "tap water",
  decisions_path = ..., cache_dir = ...)
```

**Wiring notes.**

- **`taxon_label_col`:** take display names from JV's **consensus** (`read-data.csv`, via
  `identity_gate_validation/build_consensus_names.R`). Do not take them from `esv_data`: that is
  a BLAST hit list, about 5.6 rows per ESV, and naming from its first row put a spurious
  *Trichoplax* into v1's output.
- **Downstream control-set definitions** (`is_blank`) must read `admit_as == "control"`.
  Otherwise a reassigned tube keeps its old role.
- **Run-wide artifacts** must be removed before `flag_hopped_detections()`. Without that, the
  hopping filter falsely flags about 20% of one run.

**Feedback wanted.**

1. Does scope-then-gate fit your ingest? Does any in-scope tube get lost?
2. Are the 32 held tubes the right ones?
3. Is the `admitted WITHOUT a discriminating test` report visible enough in your run log and
   outputs? The user wants this to be transparent.
4. Do the LLM's `llm_role` and rationales make sense for tap-water blanks? Would you run with
   `accept_llm_roles = TRUE`?
5. Anything in the status vocabulary your downstream steps cannot read.

**Still open.**

- **For JV:** where the 12S run-wide feature comes from.
- **For the user:** whether the 18S JVB3735 blank communities are acceptable.
  - **What they hold:** mixed communities at 0.6-3.2x field diversity. The freshwater and
    terrestrial part (Spumella, Bodo, Naididae, Arachnida) fits tap water. Nearly all 29 blanks
    also carry MARINE taxa: Schmidingerella (63k reads), Heterosigma (35k), Oxyrrhis (21k),
    Chaetoceros, Laminariales and Beroe.
  - **What the model said:** with `blank_medium = "tap water"` it called 16 of them
    `clean_blank`, explaining the freshwater part.
  - **The decision:** whether marine carry-over from shared filtering gear counts as acceptable
    handling contamination. Leave `accept_llm_roles = FALSE` until that is decided.
  - **The live LLM review on v2:** 22 clean_blank, 5 contaminated_blank, 3
    sample_labelled_as_blank (S067800 high confidence) and 2 valid_sample, of 32 tubes.

## Round 1 of peer feedback (2026-09-28): what changed

1. **Column renamed.** On `attr(, "units")` and the review queue, `status_reason` is now
   `identity_status_reason`. It pairs with `identity_status` and matches the row output.
2. **The held-units warning is split by why a unit is held.**
   - Before, the count read "concordant 49" inside a not-admitted list, which invited the reader
     to think the gate was wrong.
   - It now reads: "N on their own evidence (discordant d, suspect s); M held only because
     another marker of the same tube was flagged".
3. **New argument: `review_sample_identity(target_groups =)`.** It names the groups the study
   measures.
   - **The prompt rule:** a medium explains its own community, never the target groups. A blank
     holding target-group taxa above a trace (the prompt gives "about 1% of reads, or many
     features") is contaminated, even when a plausible tap-water community is also present.
   - `target_groups` is part of the cache key (`sir-v4`).
   - **Why:** a control carrying the target signal makes `flag_contaminant()` permissive in
     exactly the direction nobody checks, because "invalid" needs control_rate > field_rate.
   - **Why "target groups" and not "marine":** it is the operative category, and it generalises
     to a freshwater study.
4. **The validation no longer names the failed runs.**
   - **What happened:** JV repaired 18S JVB6164/JVB6334 at about 16:00 on 2026-09-28 (91x/101x
     more reads). Those 80 units are now correctly concordant, and `flag_failed_libraries()`
     finds no failed run.
   - **The check now keys on the detector's own output:** every unit whose libraries were ALL
     excluded must be suspect and held. That is 34 units, PASS.
   - **A durable injected failure:** 18S JVB5058 is thinned to 1% of its reads. Its 20 samples
     come out suspect/library_failed and are held (PASS). Its 2 blanks come out
     untested/uncomparable (PASS).
   - `rl_all.rds` was rebuilt from the current archive. The pre-repair copies are kept as
     `*_pre_18S_repair.rds`.

**Re-validation on the repaired data.**

- Every check passes.
- 102 units from 36 samples are held: 49 on their own evidence, 53 by tube.
- 493 units were admitted without a discriminating test, all `inconclusive/no_power`.

**The four repaired-run 18S blanks the peer flagged** are IJR811PZ, NEMYPCAS, QHI6WAEP and
ZH5KVED1.
- They are suspect on diversity (0.53-0.95x the reference) and share nothing with the samples.
- Their 18S is freshwater tap water: Spumella, cercomonads, Characeae, Juncus.
- The model, given target groups, found COI macroalgae in three of them (IJR811PZ ~6%, NEMYPCAS
  ~2.5%, ZH5KVED1 ~1.5%) and called them contaminated.

**Live LLM review with `target_groups = "macroalgae (seaweeds), marine macroinvertebrates,
intertidal fishes"`,** 36 tubes:

| verdict | tubes |
|---|---|
| contaminated_blank | 23 |
| clean_blank | 7 |
| sample_labelled_as_blank | 4 (S067800 high confidence) |
| uncertain | 1 |
| valid_sample | 1 |

- **Tap water only (before target groups):** 22 clean.
- **What swung:** 14 JVB3735 blanks moved from clean to contaminated. Each rationale names its
  target taxa with shares (red and brown macroalgae, sponges, marine plankton).
- **The judgment that decides the borderline tubes** is the "about 1%" trace threshold in the
  prompt. It is not a computed cut.
- **Assumption:** that the study's third target group is intertidal fishes.

## Tests

- **TaxaFlag:** 881 expectations passed, 0 failed, 0 errors; `check()` 0/0/0 (branch tip). On the real data that message reads:
  `admitted WITHOUT a discriminating test: 500 unit(s) (inconclusive/no_power 492,
  untested/uncomparable 8)`.
- **New tests:** `untested_policy`, a no-blanks study, a run without a blank, artifact vs
  `spike_taxa`, `accept_llm_roles`, and `blank_medium` in both the prompt and the cache key.
