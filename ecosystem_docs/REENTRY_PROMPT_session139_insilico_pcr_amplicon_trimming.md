# Design Task: In-Silico PCR / Amplicon Extraction for Reference Sequences

**STATUS: design task, not started. Written 2026-07-06 (Session 139), branch `main`.**
Not implemented, not scoped in detail -- this document exists to capture the problem and
the open design questions before anyone starts building, per the user's explicit
instruction to treat this as a separate task from the immediate workflow-template fix
(see `ecosystem_docs/REENTRY_PROMPT_session139_gbif_fetch_efficiency.md` for that
fix's own details -- **unrelated document, don't conflate the two** despite both being
Session 139 and both touching reference-sequence handling).

---

## The problem, confirmed real (not hypothetical)

While debugging a live Phase 6 run of `TaxaID_Workflow_Template_TEST.R`, `train_likelihood_model()`
failed outright with "No H1 (within-species) pairs found." Root cause, confirmed directly
against real data: GenBank mixes short, purpose-built barcode submissions (e.g. 843-941bp
for a 12S fragment) with full mitochondrial genomes (~16,500-16,700bp) under the same
species/gene search term -- a whole mitogenome happens to contain the 12S gene
somewhere inside it, so it matches an NCBI search for "12S" just as validly as a
purpose-cut barcode submission does, even though the two are wildly different in scope.

The existing tooling (`TaxaLikely::build_sequence_matrix()`'s `min_seq_len`/`max_seq_len`
defaults, and `fetch_ncbi_reference_sequences()`'s length-aware search via
`TaxaTools::resolve_barcode_lengths()`) handles this by **excluding** anything outside a
plausible barcode-length window. That's the fix already applied to the workflow template
(see the sibling GBIF reentry prompt) -- and it's the right *quick* fix. But it has a real
limitation the user flagged as worth addressing properly: **exclusion throws away
information.** A full mitogenome submission genuinely contains the correct sequence for
the species at that gene -- it's just embedded inside 16kb of irrelevant flanking
sequence. For a well-sampled species (many short submissions available), excluding the
mitogenome costs nothing. For a poorly-sampled or rare species where a mitogenome might
be the *only* sequence available at all for that species, blind exclusion means that
species gets **zero** reference representation instead of one genuine (if currently
unusably-formatted) data point -- exactly backwards from what you'd want for rare-species
coverage, which is already the hardest case for this entire pipeline.

The user's framing: this is a **recurring** problem (not a one-off quirk of this
template's tiny bundled dataset) -- it will resurface any time a candidate species' only
GenBank submissions happen to be long-format ones, which is more likely for exactly the
species this ecosystem cares most about getting right (rare, undersampled, or
regionally-specific taxa).

## What the correct fix looks like, in principle

**In-silico PCR**: given a known primer pair (forward + reverse, typically with some
IUPAC-degenerate positions), locate the primer-binding sites within a longer reference
sequence and extract just the amplicon between them -- turning a 16.5kb mitogenome into
the same ~100-600bp fragment a real PCR reaction targeting that marker would have
produced. This lets a mitogenome contribute genuine same-species evidence at the correct
length, instead of being discarded outright.

**This is exactly what the external CRABS tool does.** This ecosystem already has a
consumer for CRABS's output (`TaxaLikely::read_crabs_output()`), and that function's own
docs explicitly note that primer-based trimming is "CRABS itself" doing the work -- this
ecosystem has never implemented in-silico PCR natively. Confirmed by grep: no
`primer`/`in.silico`/`amplicon` logic exists anywhere in `TaxaMatch` or `TaxaLikely`
beyond that one docs reference and an unrelated `primer_to_locus` NCBI-search-term mapping
in `fetch.R` (maps a primer *name* like "MiFishU" to its gene/locus for search purposes --
does not touch sequence content at all).

**Also checked and ruled out as a shortcut**: BLAST's own alignment coordinates
(hit-start/hit-end within the subject sequence) would be a more surgical way to trim a
long reference sequence to just its matched region, without needing primer sequences at
all -- but `TaxaMatch::blast_sequences()` doesn't currently parse or retain those
coordinates from the BLAST XML output (checked directly, `R/blast.R`). Adding that could
be a smaller, complementary fix worth considering alongside or instead of full in-silico
PCR -- flagged here as an alternative angle, not decided.

## Open design questions (resolve before implementation starts)

1. **Where do primer sequences come from?** Nothing in this ecosystem currently stores
   primer sequences anywhere (only primer *names* map to loci for NCBI search terms, in
   `TaxaLikely::fetch.R`'s `primer_to_locus`). Would need a new registry, likely analogous
   to `TaxaTools::barcode_length_defaults` -- e.g. `barcode_primer_defaults`, keyed by
   marker/primer-set name, storing forward/reverse primer sequences (IUPAC-degenerate
   character strings). Populating this correctly (citing real primer papers, same pattern
   as `barcode_length_defaults`'s own `@references`) is real work, not a placeholder task.
2. **Matching algorithm.** Exact substring matching won't tolerate real biological
   variation (SNPs in the primer-binding site, degenerate IUPAC bases in the primer
   itself). Needs approximate, IUPAC-aware matching (`Biostrings::matchPattern(fixed =
   "subject")` or similar, with a mismatch tolerance) -- and needs to search both strands
   (a GenBank submission's orientation isn't guaranteed), meaning the reverse primer's
   reverse-complement also needs to be searched for.
3. **Failure mode.** When neither primer site is found within tolerance (sequence doesn't
   actually contain the target region, or diverges too much at the primer sites), fall
   back to today's length-based exclusion rather than erroring -- this needs to degrade
   gracefully per-sequence, not fail the whole fetch.
4. **Package placement and naming** -- not yet checked with the user (a grep for
   `extract_amplicon`/`trim_to_amplicon`/`in_silico_pcr`/`primer_registry`/`amplicon_region`
   found no existing collisions in the monorepo as of this writing, but re-check before
   committing to a name, per this repo's own naming-collision discipline -- see
   `~/.claude/projects/-Users-lafferty/memory/feedback_naming_collision_check.md`).
   `TaxaLikely` is the natural home (owns `fetch_ncbi_reference_sequences()` and
   `build_sequence_matrix()`, the two functions this would sit between), but confirm
   before starting.
5. **Where does this slot into the pipeline?** Two options, not yet decided:
   - A standalone function the caller runs explicitly on `reference_df` between
     `fetch_ncbi_reference_sequences()`/`read_reference_fasta()` and
     `build_sequence_matrix()` -- matches this ecosystem's existing preference for small,
     composable, independently-testable pipeline stages (e.g. `correct_training_bias()`
     is its own stage, not folded into `assign_scores()`).
   - Baked into `fetch_ncbi_reference_sequences()` itself as an opt-in trim step for
     over-length hits, instead of the current outright exclusion.
   Leaning toward the standalone-function option for consistency with the rest of this
   ecosystem's design, but this hasn't been discussed with the user -- confirm before
   building either way.
6. **Scope boundary -- what this is NOT.** Not a request to replicate CRABS in full
   (multi-database curation, dereplication policy, taxonomy reconciliation, etc.) -- just
   the narrow capability of "given a sequence and a primer pair, extract the amplicon
   region or report failure," which is the specific piece that would let an
   otherwise-discarded long-format submission still contribute real same-species
   evidence to this ecosystem's own likelihood-model training.

## How to pick this up

Start by discussing scope and the open questions above with the user directly -- this
document deliberately stops short of a recommended answer to questions 1, 2, and 5,
since none of those were actually decided in the conversation that produced this prompt
(only the *existence* of the problem and the *shape* of a correct fix were established).
Don't start writing code before at least the package-placement/naming question (4) and
the pipeline-slot question (5) are confirmed with the user, consistent with this repo's
standing practice for new cross-package capabilities.

## Related reading

- `ecosystem_docs/REENTRY_PROMPT_session139_gbif_fetch_efficiency.md` -- the *other*
  Session 139 document, covering the immediate workflow-template fix (length-aware
  reference fetch via `fetch_ncbi_reference_sequences()`) and a separate GBIF-fetch-
  efficiency discussion. That fix is already implemented; this document's problem is
  the deeper version of the same underlying issue, deliberately deferred.
- `TaxaLikely/R/read_crabs.R` -- the existing CRABS-output consumer; its own docs are
  where "primer trimming is CRABS's job" is stated explicitly.
- `TaxaLikely/R/fetch.R` -- `fetch_ncbi_reference_sequences()` (the length-exclusion
  fix already applied) and `primer_to_locus` (the existing, unrelated primer-*name*-to-
  locus mapping used only for NCBI search term construction).
- `TaxaTools/R/barcode_utils.R` -- `barcode_length_defaults` / `resolve_barcode_lengths()`,
  the existing pattern a future `barcode_primer_defaults` registry would likely mirror.
