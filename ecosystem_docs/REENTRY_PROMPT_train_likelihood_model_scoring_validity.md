---
editor_options: 
  markdown: 
    wrap: 72
---

# Reentry prompt: is `train_likelihood_model()` trained on data comparable to what it's asked to predict?

**Written for a fresh session (possibly a different model) to
independently re-assess.** This is a foundational statistical-validity
question about the TaxaLikely package, not a bug report -- please form
your own judgment on the evidence below rather than assuming the framing
here is correct.

## The TaxaID ecosystem, briefly

TaxaID is an R monorepo for Bayesian taxonomic assignment of eDNA/image/
acoustic detections. The package chain relevant here: `TaxaMatch`
produces match objects (query vs. reference candidate scores);
`TaxaLikely` converts those scores into likelihoods via a trained
statistical model; `TaxaAssign` combines those likelihoods with
occurrence-based priors into posteriors. Full ecosystem context is in
this repo's root `CLAUDE.md`; package-specific detail is in
`TaxaLikely/CLAUDE.md`.

## The question

`TaxaLikely::train_likelihood_model()` fits a bivariate-normal model
(`H1` = known species, `H2`/`H3` = missing species/genus) over
`(score_logit, gap_logit)`, using training data built entirely by
`TaxaLikely::build_sequence_matrix()`. That function:

1.  Takes a `reference_df` of curated reference sequences (real
    NCBI/BOLD accessions, one species' sequences compared against
    another's).
2.  Runs `DECIPHER::AlignSeqs()` -- a **multiple sequence alignment**
    across every reference sequence in a genus at once (not pairwise).
3.  Runs `DECIPHER::DistanceMatrix(includeTerminalGaps = FALSE)` on that
    MSA to get pairwise distances.
4.  Sets `p_match = 1 - distance` (`TaxaLikely/R/build_sequence.R`,
    \~line 288-336) -- this is what "score" means during training, for
    every H1 (within-species) and H2/H3 (cross-species, cross-genus)
    pair the model is fit on.

At **inference** time, `TaxaLikely::evaluate_likelihoods()` takes a real
query's score from `match_obj$score` (or `score_original`) -- a column
whose value was computed by an entirely separate process, upstream,
before TaxaLikely ever sees it: - In the "live" pathway,
`TaxaMatch::blast_sequences()` calls NCBI BLAST (a pairwise,
seed-and-extend local alignment heuristic, not an MSA). - In at least
one real, current production dataset (PtConception 12S,
`PtConMifishSchulte_match_obj.rds`), the match table is **externally
supplied** by a wet-lab bioinformatics pipeline outside this codebase
entirely (`PercMatch`/`Accession` columns) -- the exact tool and
parameters that produced these numbers are undocumented here.

**The question:** is a model trained on DECIPHER's MSA-based `p_match`
statistically valid to apply to scores computed by a structurally
different alignment method (BLAST, or an unknown external tool)? All of
these processes measure something related to "percent sequence
identity," but they are not guaranteed to produce numerically comparable
values for the same sequence pair -- different gap-penalty schemes,
different treatment of terminal/end regions, and (for the MSA case
specifically) a pairwise distance that is influenced by every *other*
sequence in the alignment, not just the two being compared.

## Evidence gathered this session (real data, not simulated)

Working against the real PtConception 12S checkpoint (13,442
observations, `PercMatch`-scored, never passed through
`blast_sequences()`), a query's own raw sequence was aligned directly
against its own retained top-candidate species' reference sequence,
using `pwalign::pairwiseAlignment(type = "local")` +
`pwalign::pid(type = "PID1")` -- a third alignment method, distinct from
both DECIPHER's MSA and whatever produced the recorded `score_original`.
This computes, for a pair where the "correct" answer (`score_original`)
is already known, an independent measurement of the same quantity.

Result (n=76 usable comparisons, real sequences, no synthetic data): -
Mean discrepancy (my method − recorded value): **-1.18 points**, median
-0.5, range -9.48 to +1.80. - Correlation with sequence-length mismatch
between query and reference: \~0 (r=-0.05, not significant) -- ruled out
as an explanation. - Correlation with the recorded identity level
itself: r=-0.20 (p=0.08, n=76 -- suggestive, not conclusive) that the
discrepancy grows as the underlying match gets weaker.

Interpretation, held loosely (small sample, one dataset, one
pairwise-vs- external comparison -- not yet a DECIPHER-vs-BLAST
comparison specifically): different alignment tools can disagree on
%identity for the *identical* sequence pair by several points, the size
of the disagreement is not fully explained by the one covariate tested
(length mismatch), and there's a weak signal that the disagreement may
not be a flat constant across the identity range -- which would matter
most exactly in the weak-match regime this package's downstream design
work (candidate-exclusion and low-confidence upranking, see the
companion doc
`REENTRY_PROMPT_degraded_species_ likelihood_thresholds.md`) is most
focused on.

## Existing mitigation already in the package

`TaxaLikely::calibrate_query_noise()` (Session 155, see
`TaxaLikely/ CLAUDE.md`) already estimates one marker-wide additive
offset (median residual between real query scores and the trained H1
mean, computed against an independent, non-circular
confident-observation set) and shifts the whole model's mean by that
constant. It was empirically validated on this exact real 12S dataset:
H1 win rate went from 1% to 77.5% after applying it. Its own
documentation already frames the residual as "query- side technical
noise" (PCR/sequencing/degradation) that reference-vs- reference
training data can't see -- it does not currently distinguish that
explanation from "the scoring tool itself measures differently than
DECIPHER," and the fix (a single additive shift) is the right form of
correction only if the true gap is a location shift, not something that
also depends on identity level or otherwise varies systematically.

## What to re-assess

1.  Is the empirical evidence above (real, but small-sample and from one
    external dataset) sufficient to treat "DECIPHER-vs-inference-scoring
    mismatch" as a real, general property of this pipeline, or is it
    more likely an artifact specific to this one externally-supplied
    match table? A cleaner test: compare `build_sequence_matrix()`'s
    DECIPHER-MSA `p_match` directly against
    `TaxaMatch::blast_sequences()`'s own BLAST-derived score for the
    *same* reference sequences, isolating "DECIPHER vs. BLAST"
    specifically from "DECIPHER vs. this one unknown external tool."
2.  If a real, general mismatch exists, is `calibrate_query_noise()`'s
    single additive offset an adequate correction, or does the mismatch
    need a richer correction (e.g., something identity-level-dependent,
    or training directly against BLAST-scored reference-vs-reference
    pairs instead of DECIPHER's MSA, so training and inference share one
    measurement process by construction)?
3.  More broadly: should `build_sequence_matrix()` be re-architected to
    score its training pairs using the *same* tool/parameters as
    whatever will score real queries at inference time (BLAST for the
    live pathway; unclear what to do for externally-supplied match
    tables of unknown provenance), rather than always using DECIPHER
    regardless of the inference-time source? Might it be possible to
    reverse engineer this process?
4.  Feel free to take a higher-level reassessment for how we might
    achieve the primary goal: which is to model likelihoods from scores,
    where they scores are provided externally with potentially vague
    methods.

## Where to look

-   `TaxaLikely/R/build_sequence.R` -- `build_sequence_matrix()`, the
    DECIPHER MSA + distance-matrix step (\~lines 280-340).
-   `TaxaLikely/R/train.R` -- `train_likelihood_model()`,
    `.prep_training_data()`.
-   `TaxaLikely/R/evaluate.R` -- `evaluate_likelihoods()`,
    `.evaluate_one_query()`.
-   `TaxaLikely/R/calibrate_query_noise.R` -- the existing mean-offset
    mitigation.
-   `TaxaMatch::blast_sequences()` (`TaxaMatch/R/`) -- the live-pathway
    scoring method that training data should arguably match.
-   `TaxaLikely/CLAUDE.md`'s Session 155-158 notes -- the fullest
    existing record of what's already been tried and found on this
    general topic (query-side noise, sigma correction attempted and
    rejected, evidence-ratio sigma gating).
-   Real data to test against:
    `~/My Drive/Rscripts/eDNA/PtConception/   PtConMifishSchulte_{match_obj,reference_df,seq_matrix,lik_model_calibrated}.rds`.
