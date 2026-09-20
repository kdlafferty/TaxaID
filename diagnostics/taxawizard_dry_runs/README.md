# TaxaWizard dry runs

Scripted checks that the LLM-facing material actually works, run against a real
model. They cost API calls, so they are not tests; run them after changing the
prompt pack (`llm_prompts/`, `TaxaWizard/inst/prompts/pack/`) or the digest
generator (`TaxaWizard/R/pack.R`).

| Script | What it does |
|---|---|
| `console_fixture.R` | Drives the REAL engine (`workflow_engine()`) through classify -> path_select -> parameterize with a scripted user, generates the script console mode would generate, then RUNS it against a fast fixture. Automatic checks: the script parses; Step 0 is present exactly once and names the selected edges; every `Pkg::fn` is a real export; every named argument is a real formal. `P7A_SCRIPT=<path>` re-checks and re-runs an existing script without paying for another interview. The `.rds` fixtures are gitignored, so point `TAXAID_FIXTURES` at a tree that has them. |
| `cold_chat_birdnet.R` | A plain chat model is given ONLY `START_HERE.md`, `CONTEXT_TaxaID.md`, a setup report and the hand-off template, then a scripted naive user with BirdNET data. Automatic checks: declares chat mode; names input/output nodes; plans with edge ids; mentions the LLM-key requirement; asks for a package CONTEXT file before writing code; every `Pkg::fn` it writes is a real export and every named argument is a real formal. Transcript saved to `$P7_OUT`. |

```bash
# from the repository root
P7_OUT=/tmp Rscript diagnostics/taxawizard_dry_runs/cold_chat_birdnet.R fast   # Haiku-class
P7_OUT=/tmp Rscript diagnostics/taxawizard_dry_runs/cold_chat_birdnet.R mid    # Sonnet-class
```

## 2026-09-18 baseline (tier = fast)

First run exposed two pack defects, both fixed the same day: the model wrote
`TaxaMatch::birdnet_to_match()` (an EDGE id used as a function) and wrote stage code
without asking for the package CONTEXT file. `START_HERE.md` now states both rules
explicitly and `CONTEXT_TaxaID.md` lists each edge's real functions beneath it. After
the fix: 10 edge ids in the plan, 0 invented functions, 0 stale arguments, and the
model asks for exact file paths and the package file before writing code.

## 2026-09-18 baseline (tier = mid)

Clean pass, no pack changes needed. Declares chat mode; names `birdnet_detections`
and `reviewed`; 6 edge ids; mentions the LLM-key requirement; asks for
`CONTEXT_TaxaTools.md` by name before writing the next stage; 3 `Pkg::fn` calls, all
real exports; 0 stale named arguments; all four replies end in a question. The turn-4
plan table reproduces `match_to_taxa` / `taxa_to_context` / `match_to_consensus_score` /
`consensus_to_reviewed` with the same in/out nodes and packages the graph records, and
the model stops at the end of stage 1 because it has not been given the CONTEXT files
for the later stages.

Fewer edge ids than the fast run (6 vs 10) is not a regression: mid names only the five
edges on the actual `birdnet_detections -> reviewed` path plus the
`match_to_consensus_llm` alternative, where fast also listed edges off the path.

Note for re-runs: `max_tokens` must be generous. Current Claude models emit `thinking`
blocks before any text, so at `max_tokens = 1800` the mid-tier run returned responses
with no text block at all and died. The script now asks for 6000. `TaxaTools::call_api()`
explains this case by name as of 8ec4a6e.

### Known gap in the automatic checks

The checks validate `Pkg::fn` tokens and named arguments, so they cannot see a package
named only in prose. Turn 4 attributed edges to `TaxaAssign` in a table with no `::`;
that package is real and the attribution is correct, but an invented one would have
passed silently. Same blind spot class as the edge-id-as-function defect: a check that
only validates what is written in code cannot police what is written in prose.


## 2026-09-18 baseline: `console_fixture.R`, score-only arm (tier = mid)

Four turns to a complete 2-step DAG (classify -> path_select -> parameterize),
script generated, **script executed: exit status 0**, 5 of 20 observations
resolved against the real PtCon 12S fixture. All five static checks pass.

This is the only end-to-end exercise of P6, and it earned its keep immediately.

### What it found

The model set `edge_id = "load_match_df"` on its data-loading step. **No such
edge exists**; it invented an identifier for a step the graph does not model.
That id flowed into the generated script's Step 0, and the run reported
`workflow_check: unknown edge id(s) ignored: load_match_df`.

Nothing broke -- `workflow_check()` ignores an unknown id and says so, which is
P3's guard working. But a fabricated identifier had reached a line the user
reads and may copy, and the script claimed to check a requirement it never
checked. `.generate_script()` and `.widen_step0_edges()` now filter edge ids
against the graph (`.keep_known_edges()`), warning rather than dropping
silently, because an invented edge id usually means the LLM invented a STEP.
Re-running the interview reproduced the same invention and the filter removed
it: Step 0 is now `edges = c("match_to_consensus_score")` and the run log is
clean.

### Scope limit, stated rather than skipped

Only the score-only arm is executed. Every Bayesian route from `match_df` in the
graph passes through `taxa_to_refs`/`refs_to_matrix`/`matrix_to_model` -- 5-30
minutes of live NCBI plus a GBIF fetch -- which is not a fast-fixture dry run.
The spec asked for a Bayesian arm too; it is **not** covered here, and running
one needs either a longer budget or a mid-pipeline entry node the graph does not
currently offer.
