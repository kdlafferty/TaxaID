# Reentry note: metadata-driven blank/control detection (design idea, not built)

**Written 2026-07-13, Session 154, prompted by a real bug found during Task B's Phase 2
work** (see `REENTRY_PROMPT_session153_multisite_workflow_migration.md` and
`TaxaID/CLAUDE.md`'s Session 154 note for the full trace).

## The problem, generalized

`PtConceptionWorkflow_12S_single_site.R`/`_multi_site.R` (and, by pattern, likely
`PtConceptionWorkflow_18S_2_single_site.R` and both Mugu workflows -- not checked yet,
see below) identify blank/control samples via a hand-typed literal vector
(`BLANKS_MARCH`, `BLANKS_AUG`) matched against the read-file's own sample column names.
This has no structural connection to any site/sample metadata table that might exist for
the same study.

Real, confirmed failure mode (Session 154): the March run's `BLANKS_MARCH` was
`c("Blank1.0", "Blank2.0")` -- two literal read-file columns that turned out to have
**zero reads across every ESV in the file** (empty placeholders, not real controls). The
study's real blanks (4 Barcodes flagged `BagID == "BLANK"` in
`Dangermond_Sample_Metadata2_31Jan24.xlsx`) were sequenced through the *ordinary*
barcode-keyed workflow -- indistinguishable from a real field sample by column name
alone -- and were silently counted as field data instead of control data. This wasn't
found by code review; it was found only because Phase 2's work happened to load the
site-metadata spreadsheet for the first time and someone thought to cross-check it
against the blank list.

## The general lesson

**Whenever a site/sample metadata table exists for a study, blank/control identification
should be cross-checked against (or derived from) that table's own control-status
column, not maintained as an independent hand-typed list with no link to it.** A
hand-typed list can silently miss real blanks the moment a lab processes one through the
"normal" sample workflow instead of giving it an obviously-named column.

## Why this is NOT proposed as a rigid package function (yet)

Discussed directly with the user (2026-07-13): there's real hesitation about building a
generic "auto-derive blanks from a metadata file" function into TaxaFlag/TaxaMatch,
because:

- **Metadata conventions vary per study.** This dataset uses `Location == "blank"` /
  `BagID == "BLANK"`; another study might use a dedicated `is_control` boolean, a
  `sample_type` factor, or nothing at all (no metadata table exists). A function that
  assumes one convention is brittle across studies.
- **Not every workflow has site metadata at all.** The user wants blank identification to
  stay directly user-editable (a plain literal vector a workflow author can just look at
  and edit) as the fallback/default path -- not forced through an inference layer that
  could fail silently or require metadata conventions the user hasn't standardized on.
- The fix actually applied this session (see the two PtConception workflows) was
  deliberately scoped narrower: **fix the value** of `BLANKS_MARCH` (correct literal
  list, resolved by hand against the real metadata this one time) rather than **build a
  mechanism** that reads the metadata file and infers blanks automatically every run.
  This preserves the existing "plain user-edited list" pattern while fixing the actual
  bug.

## What a future session should actually consider building

Not a hard requirement, but a design a future session could pursue with the user:

1. **A lightweight, opt-in cross-check, not an inference engine.** E.g. a small helper
   that takes the workflow's own `BLANKS_MARCH`/`BLANKS_AUG`-style list AND a
   site-metadata table with a user-specified control-flag column/value, and *warns* (not
   auto-corrects) if any metadata-flagged control sample is missing from the hand-typed
   list, or if any hand-typed blank has substantial real reads inconsistent with being a
   true negative control. This keeps the user firmly in control of the final list while
   making this exact silent-gap class detectable going forward, without requiring every
   study to conform to one metadata schema.
2. **Audit the other real production workflows for the same gap**, now that one concrete
   instance is confirmed: `PtConceptionWorkflow_18S_2_single_site.R` (uses the same
   March/August read files and presumably the same `BLANKS_MARCH`/`BLANKS_AUG` pattern --
   not yet checked this session), and both Mugu workflows (`MuguFishWorkflow.R`,
   `MuguWilderFishWorkflow.R`, different dataset, own blank-identification logic, also not
   yet checked). Do not assume they have the same bug -- check each one's own blank list
   against whatever metadata exists for that study before concluding anything.
3. **Decide where this would live.** A cross-check helper like this operates on the
   read-level detections table (same shape `TaxaFlag::flag_contaminant()` and
   `TaxaMatch::join_event_site_metadata()` already consume) -- likely TaxaFlag (it's
   fundamentally a contamination-detection input-quality check) or TaxaMatch (it's
   fundamentally a sample-metadata consistency check, adjacent to
   `join_event_site_metadata()`). Not resolved; flag for whoever picks this up.

## Real numbers from the confirmed case, for context

- March run's real blank Barcodes and their actual read counts (12S MiFish-U, JVB3105):
  `2ONWVS29` (153 reads, 1 ESV column), `S067819` (1,092 + 8 reads, 2 columns),
  `PBPUPL5A` (8 reads, 1 column), `XTLNX5VZ` (46,752 + 140 + 37 + 8 + 464 reads, 5
  columns). All four are real, non-trivial control signal that had been going entirely
  unused for March-run contamination detection.
- Post-fix: `flag_contaminant()`'s "control" count rose from 24 (August-only) to 33 (24 +
  9 real March blank read-columns); high-risk contaminant ESV count rose from 22 to 43 on
  the same real 12S dataset -- a substantive change to `decontaminated_esv_data`, and
  therefore to every downstream step of the pipeline.
