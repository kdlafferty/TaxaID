# Unreviewed rows are silently dropped from the final export

**Status: RESOLVED 2026-09-14 (Opus 5). Items 1-3 implemented; item 4 was
investigated and found NOT to be a bug -- see "Resolution" at the bottom.
Found 2026-09-14 on the PtConception 12S production run, by a diagnostic a
previous session had written for exactly this purpose and which had never run
because of a syntax error.**

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


---

## Resolution (2026-09-14, Opus 5)

### 1. Retry the omitted taxa -- DONE

`.parse_review_response()` now returns `attr(, "missing_taxa")`, and
`.review_batch_with_retry()` re-asks for exactly those taxa, up to
`max_retries` times, at the terminal path of every batch (so it also covers
the leaves of the halving retry, and the single-taxon batch where halving
cannot fire at all -- `nrow(taxa_batch) > 1L`). It stops early when a re-ask
recovers nothing, and does not retry a hard `llm_fn` error. Cost is
pay-per-failure: it fires only when the model omits, and asks only for what
was omitted.

Worth recording because it shaped the fix: a SHORT response (fewer objects
than expected) sets `status = "truncated"` and the halving retry DOES fire --
but it bottoms out at `max_retries` depth and cannot retry a size-1 batch, so
the omission survives at the leaf. A response that returns the RIGHT NUMBER of
objects while substituting something else for one taxon reads as
`"complete"` and never triggered any retry at all. Both paths now end in the
re-ask.

**A second, unlisted defect found while implementing this: the NA-filled row
was being CACHED.** `cache_dir` persisted it like any other verdict, so every
later run was a cache HIT on a row of NAs and the omission was permanent --
re-running could not recover it, and the retry above would never have got a
chance to fire. Two changes: an unreviewed taxon is never written to the
cache, and a cached entry holding no verdict at all is now treated as a MISS,
so caches written before today heal themselves.

### 2. Make the residue loud -- DONE

`attr(result, "unreviewed_taxa")` (character, possibly empty) and
`attr(result, "n_unreviewed_rows")` (integer) are ALWAYS present, modelled on
`fetch_ncbi_reference_sequences()`'s `count_failures`. New
`on_unreviewed = c("warn", "error", "ignore")` controls escalation; the
package default is `"warn"` (non-breaking). Note attributes do not survive a
`dplyr` verb -- check them immediately after the call.

### 3. Filter semantics -- DECIDED: hard-stop, filters unchanged

User decision. The six export filters stay `!= "unlikely"` (still discarding
`NA`); every production workflow now passes `on_unreviewed = "error"`, so a
run with residue aborts before the export chain rather than producing a
species list that is silently short. Rationale: keeping an unreviewed row
would put an unvetted taxon in the output distinguishable only by its `NA`s,
where stopping makes the decision per-run and explicit. Wired into
`PtConceptionWorkflow_12S_single_site.R`, `_12S_multi_site_FAST.R`,
`_18S_2_single_site.R`, `MuguFishWorkflow.R`,
`GreatLakes2023_ConsensusWorkflow.R`, both workflow templates, and the
CaliforniaIntertidal stub comment.

### 4. Sort the slash label -- NOT A BUG, do not "fix" this

Checked before assuming. `.make_slash_name()` is order-dependent **by
design**: `add_slash_taxon()` orders candidates by descending posterior, which
is documented, and `primary_taxon` reads the first element. Sorting the label
would break that.

The premise that this "splits the review" is also wrong, and the real data
says so directly. `review_assignments()` has joined on the SORTED candidate
set since 2026-09-04, and deduplicates canonically. The 20 affected rows in
`PtConMifishSchulte_reviewed.rds` carry 4 distinct display labels but only
**3 distinct canonical sets** -- the two `Scorpaenichthys` orderings are one
set, were sent to the LLM once, and the model omitted that one request. Both
labels went NA because they share one verdict, not because they were reviewed
separately.

A regression test now pins this (`a candidate set arriving in two posterior
orders is reviewed once`), since nothing asserted it before.

## Verification

`devtools::test()` 530 passed / 0 failed (was 495); `devtools::check()`
0 errors / 0 warnings / 0 notes; reinstalled.

Live, on the real data this prompt names: the 20 unreviewed rows of
`PtConMifishSchulte_reviewed.rds` were re-run through the fixed function with
a real Anthropic call. **3 candidate sets, 1 LLM call, all 20 rows recovered**
(`n_unreviewed_rows` 20 -> 0), and all three units pass the export filters:

| unit | habitat | geographic | contamination |
|---|---|---|---|
| Scorpaenichthys marmoratus + Hexagrammos lagocephalus/decagrammus | likely | possible | low |
| Clinocottus recalvus/globiceps | likely | likely | low |
| Hyperprosopon anale/argenteum + Amphistichus argenteus + Atherinops affinis | possible | likely | low |

So the loss was real and all of it was recoverable: 20 observations of three
plausible local fishes, silently absent from the 12S species list.

That live run did not itself exercise the re-ask (the model answered all three
this time -- the omission is stochastic), which is exactly why the re-ask,
the no-progress stop, the cache behaviour and the `on_unreviewed` escalation
are covered by deterministic unit tests rather than by a live call.
