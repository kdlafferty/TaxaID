# Unreviewed rows are silently dropped from the final export

**Status: OPEN, nothing implemented. Found 2026-09-14 on the PtConception 12S
production run, by a diagnostic a previous session had written for exactly
this purpose and which had never run because of a syntax error.**

## The symptom

```r
reviewed |> dplyr::filter(is.na(llm_habitat_plausibility)) |>
  dplyr::select(consensus_taxon, consensus_rank, consensus_OTU) |>
  unique() |> head(30)
```

returns 20 rows across 4 distinct taxa whose LLM review columns are ALL `NA`:

| consensus_taxon | consensus_OTU |
|---|---|
| Perciformes | Scorpaenichthys marmoratus + Hexagrammos lagocephalus/decagrammus |
| Clinocottus | Clinocottus recalvus/globiceps |
| `NA` | Hyperprosopon anale/argenteum + Amphistichus argenteus + Atherinops affinis |
| Perciformes | Scorpaenichthys marmoratus + Hexagrammos decagrammus/lagocephalus |

The diagnostic itself had been written as `... |> unique() |> print(n = 30)`,
which errors with `invalid 'na.print' specification`: `print(n =)` is a tibble
method and `reviewed` is a plain `data.frame`, so `n` reached
`print.data.frame` and was passed through to `na.print`. It has therefore been
failing silently since it was written, which is why this was never seen. The
live workflow now uses `head(30)`.

## Why it matters

All four LLM columns are `NA` on these rows, and every production workflow's
export chain filters with `!= "unlikely"`, which **discards `NA`**. So an
observation the model happened not to answer about is removed from the final
species list without a word. This is the same class of loss as the 2026-09-04
grass-carp incident, where a Lamar-confirmed detection vanished the same way.

## Cause, confirmed from the run log

`TaxaFlag::review_assignments()` batches taxa, asks for a JSON array, and
reconciles the response against the expected taxa. When the model simply omits
an entry, `R/review_assignments.R` (around line 1811) fills it with NA
defaults and warns:

```
Warning:  LLM omitted 1 taxa. Filling with NA defaults: Scorpaenichthys marmoratus + Hexagrammos lagocephalus/decagrammus
Warning:  LLM omitted 10 taxa. Filling with NA defaults: Enophrys taurina/bison, ...
```

There is **no retry for omitted taxa**. The run gives up on them permanently.
The omitted labels are consistently the long compound slash taxa, which is
consistent with the model skipping or truncating the hardest rows.

## A second, probably related bug

Two of the four affected labels are the same biological unit with the epithets
in opposite order:

- `Scorpaenichthys marmoratus + Hexagrammos lagocephalus/decagrammus`
- `Scorpaenichthys marmoratus + Hexagrammos decagrammus/lagocephalus`

The 2026-09-04 fix made `add_slash_taxon()`'s irreducibility signature
order-invariant by sorting the candidate vector, but the **slash label itself**
appears not to be sorted, so one unit can render under two names. That splits
the review, doubles the LLM cost for the unit, and gives the reconciliation two
targets where there should be one. Check `.make_slash_name()` before assuming
this is fixed.

## What to do

1. **Retry the omitted taxa.** After reconciliation, if `missing_taxa` is
   non-empty, re-ask for just those in a second call, then fill NA only for
   what is still missing. Bounded cost: it only fires when the model omits.
2. **Make the residue loud.** A workflow should not have to run a hand-written
   diagnostic to discover unreviewed rows. Return the count on the result as
   an attribute and have the workflows check it, the way
   `count_failures` now works in `fetch_ncbi_reference_sequences()`.
3. **Decide the filter semantics.** `!= "unlikely"` silently means
   "and drop anything unreviewed". If an unreviewed row should be kept for a
   human to look at, the filters in all six production workflows need
   `| is.na(...)`. This is a scientific decision, not a code one.
4. **Sort the slash label**, if `.make_slash_name()` is confirmed order-
   dependent, and add a regression test asserting one unit renders one way.

## Verification

An LLM call is needed, but no NCBI access, so this is testable while NCBI is
throttled. The PtCon 12S run reproduces it: the four labels above are in
`PtConMifishSchulte_reviewed.rds`.
