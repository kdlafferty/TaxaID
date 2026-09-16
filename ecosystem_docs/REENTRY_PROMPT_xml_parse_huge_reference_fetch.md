# Fix the XML_PARSE_HUGE failure in the NCBI record fetch

**Status: OPEN, not started. Found 2026-09-15 during the PtCon 18S rerun.**
**Needs a package rebuild, so it belongs with a package-proofing pass rather
than being installed on its own.**

## The bug

`TaxaMatch/R/evaluate_reference_accessions.R:592`

```r
xml_doc <- xml2::read_xml(xml_raw)
```

`xml2::read_xml()` defaults to `options = "NOBLANKS"`, which leaves libxml2's
default text-node size limit in force. A single GenBank record whose
`GBSeq_sequence` exceeds that limit throws:

```
Resource limit exceeded: Text node too long, try XML_PARSE_HUGE [114]
```

**VERIFIED REPRODUCTION** (2026-09-15, synthetic, no NCBI needed):

```r
big <- paste(rep("A", 11e6), collapse = "")   # 11 MB single text node
xml <- paste0("<r><GBSeq><GBSeq_sequence>", big, "</GBSeq_sequence></GBSeq></r>")
xml2::read_xml(xml)
#> Error: Resource limit exceeded: Text node too long, try XML_PARSE_HUGE [114]
xml2::read_xml(xml, options = c("NOBLANKS", "HUGE"))
#> parses
```

Identical error text to the live failure, and the fix resolves it. The
threshold is libxml2's `XML_MAX_TEXT_LENGTH`, 10,000,000 bytes for ONE text
node -- so the trigger is a single record whose sequence exceeds ~10 Mbp
(a chromosome or genome assembly), NOT an ordinary over-length reference.

**WHERE IT FIRED, precisely.** Not the reference fetch and not the
match-candidate screen -- it was `verify_removal_candidates(screen_corroborators
= TRUE)`, the removal audit, fetching the records for its own BLAST HITS:

```
Raw BLAST hits: 2000 across 20 queries
Final: 1912 hits across 20 queries (651 unique taxa)
Looking up taxids for 1671 unique accessions...
Fetching NCBI records: batch 1/17 (100 accessions)...
...
Warning: NCBI record fetch failed for batch 8: ... [114]
```

So the population is 1,671 BLAST-hit accessions, and BLAST against `nt`
routinely returns whole chromosomes and genome assemblies -- the same
reference-genome problem TaxaID/CLAUDE.md already documents for
*Pseudorasbora parva* and *Cyprinus carpio*, which is why `[SLEN]` server-side
length restriction was added to `.search_species_accessions()`. That restriction
does not apply here, because these accessions come from a BLAST hit list rather
than from an Entrez species search.

**The specific culprit accession was NOT identified** -- the hit list is not
checkpointed, so it is not recoverable without re-running the audit. An earlier
draft of this document claimed the offenders were the WGS contigs
(`HBEB01012595` etc.) that the same run flagged `not_evaluated_wrong_marker`;
that was WRONG on two counts and is retracted: those are 3-5 kb, three orders of
magnitude below the limit, and they belong to the match screen's population, not
the removal audit's. Do not go looking for them.

## Why it costs more than one record

The retry loop at line 586 wraps the parse in `for (attempt in 1:3)`. The
failure is **deterministic** -- the same oversized record is in the batch every
time -- so all three attempts fail and the handler returns an empty data frame
for the whole batch. **One bad record discards 99 good ones.**

Batches are 100 accessions (`batch_size <- 100L`, line 574).

**What is actually lost.** Not 100 reference accessions -- 100 BLAST HITS lose
their metadata (organism, create-date, sequence), so they cannot be checked for
taxonomic congruence or same-submission-batch independence and therefore cannot
serve as corroborating partners. The cost is a thinner evidence base under the
20 removal candidates the audit exists to protect: an accession spared only by a
corroborator that happened to sit in batch 8 would instead be removed. On this
run that is 100 of 1,671 hits, ~6%.

## The fix

Two parts. The first is the actual fix; the second stops the failure mode from
being all-or-nothing if some other parser limit turns up later.

1. Enable the parser option:

```r
xml_doc <- xml2::read_xml(xml_raw, options = c("NOBLANKS", "HUGE"))
```

Keep `NOBLANKS` -- it is the xml2 default and dropping it silently changes
whitespace handling in the downstream `xml_text()` calls.

2. On the final failed attempt, split the batch and re-fetch singly, so a
   persistent parse failure degrades to one lost record rather than 100. The
   error handler at line 619 is where this belongs: instead of returning the
   empty data frame immediately, retry `batch` one accession at a time and
   `rbind` whatever parses.

## How to verify

It reproduces synthetically -- an 11 MB text node is enough, no NCBI needed.

- The synthetic reproduction above already proves the fix works and needs no
  network. Run it as a regression test.
- For a real end-to-end confirmation, re-run the PtCon 18S removal audit with
  `SCREENS_FROM_CHECKPOINT <- FALSE` (gate added 2026-09-15) and confirm all 17
  batches parse. Needs NCBI un-throttled, and the batch composition may differ
  from the 2026-09-15 run, so a clean pass is suggestive rather than decisive.

Expect ~100 more BLAST hits to reach the corroboration vote per affected fetch;
`n_corroborators` in `removal_audit.rds` should rise for at least some of the 20
candidates, and `spared` may flip TRUE for some.

## Companion item (small, same area, NOT yet fixed)

`TaxaTools::scientific_to_common()` defaults
`llm_fn = getOption("TaxaID.llm_fn")`, which only `TaxaTools::.onAttach()`'s
provider auto-detection sets. In a clean `Rscript` session that option is
unset and the call dies with

```
Error: No LLM function configured.
```

This is the documented `.onAttach()` footgun (TaxaID/CLAUDE.md) that
`review_assignments()` is already worked around for by passing `llm_fn`
explicitly. It bites any batch (non-RStudio) run that reaches Step 10. Either
give the function a `TaxaTools::call_api` fallback the way `review_assignments()`
documents, or pass `llm_fn` explicitly at the Step 10 call sites in the
workflows. Not fixed on 2026-09-15 because it was out of scope for that
session's edits.
