# Workflow drift checks

Two checks that catch the class of defect the 2026-09-15 production workflow
structural audit missed. Run BOTH against ALL live workflow files after any
workflow edit, not just the file you touched -- the whole failure mode here is a
broadcast fix reaching some files and not others.

| Script | Finds |
|---|---|
| `check_dead_calls.sh` | Calls to functions that were ARCHIVED out of a package (`Taxa*/archive_*/`) and never re-exported. Catches bare calls, which a namespace sweep does not. |
| `check_stale_arguments.R` | Named arguments that no longer exist in the installed function's formals. Catches a signature change that a structural read cannot see. |

```bash
# from the TaxaID repository root
E="$HOME/My Drive/Rscripts/eDNA"; G="$HOME/My Drive/Stats and Data/GreatLakes data"
FILES=(
  "$E/PtConception/TaxaID_eDNA_Workflow_Template.R"
  "$E/PtConception/PtConceptionWorkflow_12S_single_site.R"
  "$E/PtConception/PtConceptionWorkflow_18S_2_single_site.R"
  "$E/PtConception/PtConceptionWorkflow_12S_multi_site_FAST.R"
  "$E/SepulvedaMugu/MuguFishWorkflow.R"
  "$E/CaliforniaIntertidal/CaliforniaIntertidalWorkflow_multi_marker.R"
  "$G/GreatLakes2023_ConsensusWorkflow.R"
)
bash diagnostics/workflow_checks/check_dead_calls.sh "${FILES[@]}"
Rscript diagnostics/workflow_checks/check_stale_arguments.R "${FILES[@]}"
```

## Reading the output

A dead call is NOT automatically a bug. In the production scripts every one of
them sits inside the `else` of a hardcoded `USE_KERNEL_PRIORS <- TRUE`, behind an
explicit ARCHIVED PATHWAY NOTICE -- documented dead code, deliberately retained
until the GLMM path is formally dropped. Check whether the call is reachable
before touching it (`[[feedback_verify_purpose_before_flagging]]`).

A stale argument is always a hard error, because R matches named arguments
strictly. There is no benign case.

Baseline, 2026-09-17: all six production workflows clean on both checks; the
canonical template clean on both after `5b91fa4`, `d77bc65` and `7e92325`.
