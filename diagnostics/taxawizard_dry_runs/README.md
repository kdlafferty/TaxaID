# TaxaWizard dry runs

Scripted checks that the LLM-facing material actually works, run against a real
model. They cost API calls, so they are not tests; run them after changing the
prompt pack (`llm_prompts/`, `TaxaWizard/inst/prompts/pack/`) or the digest
generator (`TaxaWizard/R/pack.R`).

| Script | What it does |
|---|---|
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
