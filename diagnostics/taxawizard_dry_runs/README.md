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
