# TaxaLikely 1.0.0

* Initial release.
* `train_likelihood_model()` defaults to `score_transform = "sqrt_mismatch"`,
  the scale every production workflow trains on. `-sqrt(1 - p)` treats the
  mismatch side as a rare-event count, which is where real barcode data sits,
  and it recovers the genus-tightness ordering that the logit scale inverts
  for tightly clustered genera. `score_transform = "logit"` selects the logit
  scale; H1, H2 and H3 always share one transform, and
  `model_params$Score_Transform` records which, so `evaluate_likelihoods()`
  reads it without being told.
* `evaluate_likelihoods()` defaults to `ratio_threshold = 0`, retaining every
  specific candidate. A positive threshold compares a specific candidate
  against the best hypothesis of any rank, which can suppress a legitimate but
  weak H1 match that the Mahalanobis and alpha checks already gate; raising it
  trades denominator coverage for a smaller likelihood object.
* `restore_suppressed_candidates()` documents why
  `check_regional_overlap` stays `FALSE` by default: `TRUE` requires a
  `sequence` column on `reference_df`, and this function also serves the image
  and acoustic paths, whose reference tables have none.
* `build_sequence_matrix()` gains `pair_retention = "best2_per_partner"`,
  which keeps every pair `"best_per_partner"` keeps plus the best floored pair
  of each out-of-genus family's second partner species. H3's gap parameters
  are the mean and variance of each reference's best out-of-genus partner
  species' score minus its runner-up's, and with the reference's own genus
  dropped that runner-up is often a second species of its own family, which a
  family stratum holding one species per family discards. So
  `train_likelihood_model()` assumes H3's gap under `"best_per_partner"` and
  `"best_per_class"`, and measures it under `"best2_per_partner"`:
  `Stats$h3_gap_source` reports which. A model trained on a
  `"best2_per_partner"` table is identical to one trained on `"all"` in every
  slot, H3's gap included, at roughly `"best_per_partner"`'s size.
  `evaluate_likelihoods()` reads `H3$gap_mean` as the centre of H3's gap
  dimension, so the value a model carries there reaches its H3 likelihoods and
  its H1/H3 ratios.
* `build_sequence_matrix()`'s pair-retention documentation states which
  quantities a thinned table reproduces exactly. The per-stratum maxima
  argument covers the score maxima; a gap mean and variance are moments of the
  retained distribution rather than maxima of it, and only
  `"best2_per_partner"` and `"all"` supply the partner species H3's needs.
* `evaluate_likelihoods()` warns when the model holds no ring at a rank the
  call asks for, naming that rank and the rank the ladder stops at. A model can
  express an unreferenced hypothesis only where it holds a ring, and a ring is
  fitted only at a rank coarser than the three finest and only where at least
  three groups supply matches -- so a rank can be trained and still have none.
  The check reads the model's own `Rings`, which answers that question
  directly; the rank system it was fitted on does not. A rank the model holds
  and the call omits is not reported, since the ring loop skips it and the call
  gets the ladder it asked for.
* `train_likelihood_model()` returns `Rank_System`, the rank system the model
  was fitted on. `evaluate_likelihoods()` names it in the warning above, and
  reports separately when the call asks for a rank the model never saw that is
  among the three finest, where no ring could be fitted and retraining is the
  only remedy. Evaluating with a model that carries no `Rank_System` reports a
  message and proceeds; the ring check is unaffected, since it does not depend
  on the field.
* `unreferenced_candidates()` takes `match_df` and `rank_system`, and adds two
  hypothesis rows per observation: `"unreferenced_species"` and
  `"unreferenced_genus"`. It offers no coarser catch-all row and no argument to
  request one. A catch-all would carry `hypothesis_type =
  "unreferenced_family"`, which is the name a trained model gives the ring
  anchored at order (`train.R` builds it as `paste0("unreferenced_", child_rk)`),
  so one string would stand for two different hypotheses: a trained,
  order-anchored ring, and an unnamed row weighted by a fixed constant. The
  constant is gone with it. Mass for taxa outside every represented family comes
  from the TaxaExpect occurrence prior, whose distribution already covers them.
  `expand_unreferenced_hypotheses()` still passes any hypothesis type it does
  not model through to the posterior untouched, which is how a trained order
  ring reaches it.
* `fetch_ncbi_reference_sequences()` resolves `class` on every fetch, alongside
  `kingdom` and `phylum`, at no extra taxonomy call -- all three already sit in
  the XML the taxonomy bridge returns. A single definition decides which ranks a
  fetch resolves, so the priority-species path resolves the same set as the
  broad-search path and priority rows arrive with their organism ranks
  populated.
* A queried name whose rows describe more than one organism is filtered against
  the dominant organism of the rest of the fetch. Two rows describe different
  organisms when they differ at the finest of `class`, `phylum` and `kingdom`
  that both declare. This reaches cases a kingdom comparison cannot: NCBI
  assigns no `kingdom` to Rhodophyta, Ochrophyta, Bacillariophyta, Ciliophora
  or Chrysophyceae, and two animals share one. In the reference oracle, `class`
  separates 18 of 18 genuine genus homonyms where `kingdom` separates 8. A
  within-class split is a taxonomic revision rather than a homonym and is never
  filtered.
* Priority species are filtered, and vote, like any other queried name: the
  filter runs on the assembled reference after accession de-duplication, so each
  accession casts one vote and a dry run predicts the filtered result. Exemption
  from `max_per_species`/`max_per_genus` does not extend to this filter, which
  is not a cap.
* `queried_taxon` is present on every returned reference, recording which `taxa`
  entry produced each row. It is provenance: it says which query returned the
  row, not anything about the organism.
* The `@return` for `fetch_ncbi_reference_sequences()` distinguishes columns
  from values for `kingdom`, `phylum` and `class`. The columns are always
  present; the values can be `NA`, and an `NA` kingdom is an ordinary NCBI
  result rather than a failure.
* The reference-metadata cache key encodes the ranks a fetch resolves, so a
  cached file is served only to a call whose rank set it can answer. A study
  whose `rank_system` already spans `kingdom` through `species` keys to the same
  name and reuses its files; a study requesting fewer ranks keys to a new name
  and refetches its metadata once. Sequences are unaffected: the FASTA store is
  keyed on accession version alone.
* `annotate_reference_support()` adds four information-only columns saying how
  much per-species reference data the trained model had for a call's taxon:
  `n_references` (`H1_Lookup$n_obs_species`), `reference_weight` (the
  empirical-Bayes weight those observations earned), `reference_basis` (the
  documented reason for every `NA`, including `"no_model_row"` for taxa too
  thinly referenced to have a row at all) and `at_model_max` (the count is
  censored by the matrix build's `max_seqs_per_taxon`). A post-hoc lookup, so
  it annotates results produced earlier without re-evaluating; nothing
  thresholds or filters on it, and a low count is not evidence a call is wrong.
* `restore_suppressed_candidates()` scores a restored congener by aligning the
  query to the candidate's own references (`sequence_col`, `min_query_coverage`),
  reported in `restored_score_source` / `restored_reason`. The hierarchy's
  identities, including Level 4's `pid`, are reference-to-reference (Level 4
  aligns the candidate's reference to the anchor's reference; the query only
  locates the anchor range), so they are used only as an imputed fallback,
  `anchor - (100 - ref_ref)`, which never exceeds the anchor.
* `restore_suppressed_candidates(dropped_matches =)` offers a dropped hit's
  species back through its kept references, scored by the same direct
  alignment, so dropping one accession does not drop a species that has other
  good references.
* `calibrate_query_noise()` measures query noise on OBSERVED rows only: rows
  added by `restore_suppressed_candidates()` are hypotheses and are excluded
  from the confident set (`Query_Calibration$n_restored_rows_excluded`).

## New features

* `evaluate_likelihoods()` builds one unreferenced ring per genus and one per
  family present among the candidates, plus a ring at every coarser rank that
  at least three groups of matches support. Each ring is valued and named at a
  deterministic anchor candidate: the best candidate of that genus, family or
  unit, chosen by transformed score, then a real hit over a restored row, then
  H1 density, then raw identity. Only an exact tie falls to candidate order, so
  rings do not depend on row order. Candidates without a usable genus (blank
  or a placeholder such as "unclassified") are never anchors.
* `evaluate_likelihoods()` returns `best_identity` (the unit's best raw match
  identity, percent), `best_identity_rank` (the finest rank whose Youden's J
  threshold it reaches) and `poor_absolute_fit` (`TRUE` when it reaches none).
  Likelihoods are normalised to the unit maximum, so the best hypothesis of a
  poor match still scores 1; these columns report the match on its own scale.
  They are a flag only: no likelihood or call changes.
* `match_reference_region()` places each reference on the span the study's
  sequences (ESVs) cover, and `build_sequence_matrix()` refuses unplaced rows of a
  region-matched set.

## Changed behaviour

* `fetch_ncbi_reference_sequences()` searches the SSU/LSU synonyms only within
  `mitochondrion[FILTER]`. `"small subunit ribosomal RNA"` and `"large subunit
  ribosomal RNA"` are the standard synonyms for mitochondrial 12S and 16S and
  recover real records a bare marker-name search misses, but they are equally
  the names of the nuclear rRNA operon's subunits, so unrestricted they return
  nuclear rRNA from any organism. Measured against live NCBI across eight
  genera and two markers, with the title of every removed record read:
  restricting the synonym is a precision gain rather than a trade-off, removing
  nuclear ITS/5.8S, 18S and 28S records while keeping the mitochondrial
  barcodes. Two alternatives were measured and rejected: dropping the synonym
  clause entirely loses more than a hundred genuine records in a single genus,
  and restricting the whole barcode clause loses genuine 12S barcodes whose
  records lack the filter flag.
* `fetch_ncbi_reference_sequences()` resolves `kingdom` and `phylum` on every
  fetch, not only when `taxa_lineage` is supplied. Both ranks already sit in
  the XML the taxonomy bridge returns, so this costs no extra request, and a
  kingdom column is what lets a cross-kingdom homonym be seen at all.
* `fetch_ncbi_reference_sequences()` drops cross-kingdom contaminant rows from
  a queried name that returns more than one kingdom, and only when the rest of
  the fetch says which kingdom is the intruder: at least 90% of the other
  queried names must have resolved unambiguously to one kingdom, counted one
  vote per name. A name resolving to a single kingdom is never filtered however
  much it differs from the fetch; a split name casts no vote; a row whose
  kingdom did not resolve is kept; and fewer than three unambiguous names
  establish nothing. Failing those conditions nothing is dropped and the split
  is reported for review. The within-name majority is deliberately not used:
  for a
  real case in this ecosystem the contaminant was 93% of that name's rows, so a
  majority rule would have discarded both genuine records and kept every
  contaminant.
* The reference-metadata cache key records the QUERY a `barcode_term` builds
  rather than the term string, which is the question's label and not the
  question. Any change to how a term becomes an NCBI search now makes that
  term's existing cache files unhittable. **Every reference-cache file changes
  name, including those written under a bare `"12S"` or `"16S"`, so the next
  run re-fetches metadata once per taxon.** Sequences already in the
  per-accession FASTA store are not re-downloaded. The superseded files are
  collectable by `evict_unreachable_cache`, because the new key component is
  unconditional and so provably cannot be produced for any arguments.

* `expand_unreferenced_hypotheses()` copies each genus ring onto the species of
  its own genus only. No family-level ring names a species. A species whose
  genus has references for the marker (a `specific_candidate` row anywhere in
  `likelihood_df`) is withheld from every coarser ring because its genus's
  references were compared with the read and did not match; each withheld
  species is listed in `attr(, "unreferenced_withheld")` with its reason
  (`"genus_referenced_unmatched"` or `"no_own_genus_ring"`). Rows with no
  species name are dropped with a message and a species listed twice for one
  observation scope is one hypothesis.
* `evaluate_likelihoods()` keeps the generic unreferenced rows past the final
  ratio filter, which drops only specific candidates. A genus lookup row with a
  non-finite delta or non-positive variance values its ring from the pooled
  parameters and reports `global_fallback` as the ring's `h2_delta_source`.
* `train_likelihood_model()` measures the genus-to-family step (H3) from
  confamilial pairs, and runs the training passes in blocks of references to
  bound memory.
* `apply_coverage_constraints(constraint_behavior = "relabel")` relabels the
  unsequenced-congener row of a closed genus (every species sequenced) as
  `unresolved_species` and leaves its likelihoods alone; `TaxaAssign::compute_posterior()`
  moves its posterior to the genus's referenced species. `"zero"` mode also
  scales `score_likelihood_sd`, so the Monte Carlo path honours the zero.
* `calibrate_query_noise()` measures query noise on observed rows only and
  excludes rows added by `restore_suppressed_candidates()` from the confident
  set. Its default `offset_form` is `"constant"`.

## New arguments

* `audit_barcode_coverage(on_lookup_failure = c("warn", "error"))` controls a
  failed taxid resolution, species enumeration or barcode check. The failed
  genus is never checkpointed, contributes nothing to `$unreferenced` and has
  `is_complete = FALSE`; the census gains `lookup_failed` and the result
  `attr(, "lookup_failures")`. `"error"` stops an unattended run instead of
  caching a truncated set.
