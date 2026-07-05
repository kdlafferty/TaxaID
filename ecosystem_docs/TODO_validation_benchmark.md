# TODO -- Leave-One-Out Validation Benchmark

**Status: design discussion only, not started.** Explicit user directive
(2026-07-04): do not begin implementation until all planned ecosystem package
functions are complete. This document exists so the design isn't lost between
now and then.

---

## The core idea

For any reference record with a *known* true species identity (a real GenBank/
BOLD sequence, a real vouchered image, a real ID'd recording) and a known
collection location: run it through the normal identification pipeline, but
first remove its own trivial 100%-identity self-match from the reference
database it's being compared against. What the pipeline recovers from the
*next-best* evidence plus the geographic/occurrence prior is a real test of
whether the posterior is trustworthy -- not just whether the pipeline can
find an exact match.

This is leave-one-out cross-validation against ground truth, applied to the
whole assignment pipeline (likelihood + prior + posterior), not just the
likelihood model in isolation.

## Modality scope

- **DNA/sequence: primary target, well-defined.** Self-match exclusion is
  mechanical -- after BLAST, drop the hit whose accession/sequence is
  identical to the query before it ever reaches the likelihood step.
- **Images and sounds: secondary, exclusion mechanism unresolved.** A CV/
  acoustic classifier's "self-match" isn't well-defined the way an exact
  sequence match is -- we don't know whether the query image/recording was in
  the classifier's own training set, since that's a black box (iNaturalist's
  CV model, BirdNET) we don't control. Options to work out later: exclude by
  observation ID if the classifier's training manifest is ever published;
  accept some leakage and treat the images/sounds benchmark as a weaker,
  supplementary check rather than a rigorous LOO test; or restrict to a
  held-out set of images/recordings collected *after* the classifier's
  training cutoff, if that's discoverable. **Do not start on this modality
  until the DNA version is working and the exclusion question has an answer.**

## Sourcing location data from online reference records

The benchmark's whole premise is that the geographic/occurrence prior should
recover a correct call once the trivial exact match is removed -- so every
pulled reference record needs a *real* location, not just a species label.
This is the same standardized-site-table need already tracked in the
ecosystem more broadly (per-observation lat/lon feeding
`TaxaExpect::generate_full_priors()` via `TaxaMatch::build_site_table()`).
A source-by-source check of the actual fetch code (2026-07-05) found the gap
was real for two of three modalities; **Session 135 closed the fetch-side
half of both** (still leaving the actual `build_site_table()` wiring for
harness time -- see below):

- **Images (iNaturalist) -- already solved.** `TaxaMatch::score_image_inat()`
  already extracts `lat`/`lng` per observation, either from EXIF GPS tags (via
  `exifr`) or a user-supplied override applied to all images in a batch. This
  is a real, tested source of ground-truth location and needs no new work for
  the benchmark -- it's the one modality where "pull N reference records with
  known location" is already a solved problem.
- **DNA (GenBank) -- fetch-side solved Session 135; BOLD still open.**
  Neither `TaxaLikely::fetch_reference_sequences()` nor
  `TaxaMatch::blast_sequences()` used to fetch a record that *could* contain
  location -- both only pulled NCBI ESummary metadata or taxonomy-database
  XML (lineage only), never the full GenBank nucleotide record where
  collection location actually lives (the `/country`/`/lat_lon`
  `INSDQualifier` fields, e.g. `lat_lon = "36.789 N 121.947 W"`). Now fixed:
  `fetch_reference_sequences(include_location = TRUE)` and
  `blast_sequences(resolve_location = TRUE)` both fetch the full GBSeq XML
  record per accession and parse those qualifiers. **BOLD's equivalent is
  still unchecked** and a separate TBD -- don't assume it works the same way
  as GenBank's qualifier format.
- **Sounds (Xeno-canto) -- solved Session 135.** The Xeno-canto v3
  `/api/3/recordings` response already returned `lat`/`lng` per recording,
  and `TaxaLikely::.xc_recording_count()` already fetched that exact response
  body -- it just read `numRecordings` off it and discarded the rest. Fixed
  by extracting the shared HTTP call into `.xc_recordings_raw()` (zero
  behavior change for `.xc_recording_count()`) and adding
  `fetch_xc_recording_locations()` as the new per-recording entry point.
  Separately noted in passing (documentation drift, not fixed as part of
  this): `fetch_reference_recordings()` is referenced in
  `README.md`/`CLAUDE.md`/`NAME_CHANGE_HISTORY.md` as an existing, migrated
  function, but no such function actually exists anywhere in
  `TaxaLikely/R/`.

**Standardization target (still open):** whatever gets extracted from each
source should land in the *same* shape `TaxaMatch::build_site_table()`
already expects (long-format, keyed by `observation_id`, allowing more than
one row per observation) -- not a one-off benchmark-specific location column
per modality. The two Session 135 functions produce `lat`/`lon`/`country`
columns compatible with that shape, but nothing calls `build_site_table()`
with them yet -- that join (DNA/acoustic accessions and recordings aren't
naturally keyed by `observation_id` the way an image file is) is real
harness-time wiring, not something to do speculatively before the harness
has an actual caller.

## Comparison methods

Already surveyed in `ecosystem_docs/CONSENSUS_METHODS_COMPARISON.md` -- no new
literature research needed, just a decision on which to actually implement as
baselines:

| Method | Already implemented in this ecosystem? |
|---|---|
| Score threshold (legacy OTU-style cutoff) | No -- would need a small new function |
| 100% match + LCA (Wilderlabs-style, conservative) | No -- would need a small new function |
| `TaxaAssign::score_consensus()` (score threshold + gap + rank_thresholds -- closest existing analog to the Jonah Ventures consensus-LCA style) | **Yes** -- already exported, already wired into `TaxaWizard`'s `match_to_consensus_score` snippet |
| Bootstrap classifier (IDTAXA/SINTAX-style) | No -- real new engineering if included |
| Coverage-weighted LCA (galaxy-tool-lca-style) | No |
| TaxaID Bayesian (`TaxaLikely` + `TaxaExpect` + `TaxaAssign`) -- a few variations (e.g. with/without spatial grouping once that lands, different `presence_multiplier`, with/without dark-diversity floor) | **Yes**, core chain exists (see Pipeline section below) |

Decide the final short-list before implementing -- `score_consensus()` plus
one or two of the simpler baselines (score threshold, 100%-match) is probably
enough to show the tradeoff without building a bootstrap classifier from
scratch.

## Evaluation axes (still being discussed -- not finalized)

Two axes, as the user framed it:

1. **Accuracy** -- was the consensus call correct, at whatever rank it was
   actually made?
2. **Precision** -- what rank was the call made at (species > genus > family
   > order = decreasing precision/specificity)?

Expected result: a classic accuracy-vs-precision tradeoff across methods --
conservative methods (Wilderlabs' 100%-match, high score thresholds) should
show high accuracy but low precision (many calls pushed up to coarse ranks or
dropped entirely); permissive methods should show the opposite. Hope: TaxaID's
Bayesian posterior dominates the tradeoff curve (better accuracy at a given
precision, or vice versa) because it uses the occurrence-based prior that
none of the other methods have.

**Open, to resolve before implementation:**
- Single-point comparison per method (each at its own "sensible" default
  parameter) vs. a full accuracy-precision curve per method by sweeping each
  method's own threshold/confidence parameter?
- How to numerically score "precision" across a rank hierarchy that isn't
  always the same depth (some markers can't resolve past family) -- an
  ordinal rank-distance, or a fixed points table?
- Whether to also report posterior calibration (Brier score / log-loss) and
  rank-of-true-species-in-list as supplementary diagnostics, as discussed
  earlier in this conversation, even if accuracy x precision are the two
  headline axes.

## Confirmed: a real, callable, zero-LLM pipeline already exists

Per the user's requirement (no `TaxaFlag`, no `TaxaHabitat` LLM steps), a
research pass this session confirmed the full non-LLM chain already exists
using only real, tested functions:

```
TaxaMatch::blast_sequences() -> standardize_match_data()
  -> TaxaLikely::fetch_reference_sequences() -> build_sequence_matrix()
     -> train_likelihood_model() -> evaluate_likelihoods()
     -> filter_top_hypotheses()
  -> TaxaExpect (habitat_col = NULL path, added 2026-07-03)
     -> prepare_model_dataframe() -> train_biodiversity_model()
     -> generate_full_priors()
  -> TaxaAssign::join_priors() -> compute_posterior() -> posterior_consensus()
```

`assign_taxa_llm()`, `suggest_unreferenced_species()`, and `build_context()`
(the only LLM-touching functions in `TaxaAssign`) are not needed for this
chain and would not be called.

**Two real gaps, independent of the benchmark itself, worth closing first:**
1. No existing workflow script wires `TaxaLikely`'s real sequence-likelihood
   output into `join_priors()` -- `TaxaAssign/inst/workflows/
   compute_posteriors_workflow.R` currently uses a synthetic likelihood
   stand-in at that join. The benchmark harness would be the first real
   integration test of this handoff.
2. `TaxaExpect`'s `habitat_col = NULL` path (the mechanism that lets prior-
   building skip `TaxaHabitat`'s LLM step) has never been exercised end-to-
   end in a real workflow script for a DNA/eDNA prior build.

Both are natural prerequisites for the benchmark harness and would be good to
wire up as part of (or just before) building it, regardless of the benchmark
metrics discussion above.

## Orchestration

User preference: a plain TaxaID-style workflow (R function/script), matching
the ecosystem's existing Layer-1 workflow pattern -- deterministic,
reproducible, easy to describe in a methods section. Open to considering an
LLM agent for orchestration later if there's a concrete reason (e.g. running
unattended over a very large record set), but that's not a requirement and
shouldn't drive the initial design.

## Rough shape of the harness (not yet designed in detail)

1. Pull N real reference records with known species + known location (source
   TBD -- GenBank/BOLD for DNA; sampling strategy TBD -- random vs. stratified
   by taxon group/region/reference density). See "Sourcing location data from
   online reference records" above -- location extraction is now solved for
   all three modalities (image via `score_image_inat()`; DNA via
   `fetch_reference_sequences(include_location = TRUE)`/`blast_sequences(
   resolve_location = TRUE)`; sound via `fetch_xc_recording_locations()`),
   but routing DNA/acoustic location data through `build_site_table()` is
   still real harness-time wiring, not done yet.
2. For each record: BLAST, drop the self-hit, run the remaining candidates
   through each comparison method (baselines + TaxaID variations) to get a
   consensus/posterior call.
3. Score each call against the known true label on both axes.
4. Aggregate per method; produce the accuracy-precision comparison.

## Before starting implementation, still need to decide

- [ ] Finalize the accuracy/precision metric formulation (see "Open" list above)
- [ ] Final short-list of baseline methods to actually implement
- [ ] Reference-record pull strategy: source, N, stratification
- [ ] Which TaxaID pipeline variations to include as separate "methods"
- [ ] Self-match exclusion approach for images/sounds (or explicitly scope
      them out of v1 and revisit later)
- [ ] Wire `TaxaLikely`'s real sequence-likelihood workflow output into
      `join_priors()` (replacing the synthetic stand-in in
      `compute_posteriors_workflow.R`)
- [ ] Exercise `habitat_col = NULL` end-to-end for a real DNA prior build
- [x] Add GenBank location extraction (`/lat_lon`, `/country` qualifiers from
      the full nucleotide record) to the DNA reference-fetch path -- done
      Session 135: `TaxaLikely::fetch_reference_sequences(include_location =
      TRUE)` and `TaxaMatch::blast_sequences(resolve_location = TRUE)`.
      **BOLD's equivalent is still unchecked** (separate TBD, no BOLD
      integration exists anywhere in the ecosystem).
- [x] Extend Xeno-canto fetching to keep the per-recording `lat`/`lng` fields
      the v3 API already returns -- done Session 135:
      `TaxaLikely::fetch_xc_recording_locations()` (new function; refactored
      `.xc_recording_count()`'s shared HTTP call into `.xc_recordings_raw()`
      rather than modifying its own return type).
- [ ] Route all three modalities' extracted location data through
      `TaxaMatch::build_site_table()`'s existing shape rather than a
      benchmark-local convention -- still open; the two items above produce
      compatible `lat`/`lon` columns but nothing calls `build_site_table()`
      with them yet (that's real harness wiring, not speculative plumbing --
      do it once the harness has an actual caller).
