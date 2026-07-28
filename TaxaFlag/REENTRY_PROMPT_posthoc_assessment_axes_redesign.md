# Re-entry: `add_posthoc_assessment()` axes redesign + related open threads

Status as of 2026-07-26. This document exists because the session that produced
it covered a lot of ground (a taxonomic-name-fabrication bug chain, then this
design discussion) and the user asked to checkpoint before context runs out.
Read this fully before resuming; it is the authoritative state, not the
in-chat summary that preceded it.

## How we got here

Investigating a real, now-fixed bug (`convert_taxonomy_backbone()`/
`verify_taxon_names()`/`fill_higher_ranks()` mangling informally-named NCBI
references — see TaxaMatch/TaxaTools CLAUDE.md session notes, "Inu Inu"), the
user looked at a real corrected row (`ASV_379`, Mugu 12S data,
`consensus_taxon = "Chaenogobius"`, genus rank) and pointed out it is
ecologically implausible at the site despite passing Bayesian scoring
cleanly. That opened a broader question: how should diagnostics flag
implausible-but-well-scored assignments while staying "within the confines
of Bayes' Theorem"?

Working through real `MuguWilderFish_blast_consensus_final.rds` data (616
obs) against the user's own domain judgment surfaced several genuinely
different phenomena that a single diagnostic cannot address at once — see
"Findings" below. The user then reframed the whole ask: rather than patch
`add_posthoc_assessment()`'s existing category list, redesign it into
orthogonal axes. **That redesign is the current task.** Everything else is a
parked, related thread.

## The core data object (for re-grounding quickly)

`/Users/lafferty/My Drive/Rscripts/eDNA/SepulvedaMugu/MuguWilderFish_blast_consensus_final.rds`
— 616-row output of the real Mugu/Wilder Ranch pipeline. Columns include
`consensus_taxon`/`consensus_rank` (post-LCA display), `winner_prior`/
`winner_likelihood`/`winner_absolute_fit_pvalue`/`winner_hypothesis_type`
(pre-LCA, keyed to `primary_taxon`), `n_plausible`, `slash_taxon_name`/
`consensus_OTU`, `posthoc_assessment`, `confusion_risk_flag`. Reload this
directly for any further empirical grounding — do not trust remembered
numbers past a re-run of the real pipeline.

## Confirmed facts (verified against source + real data this session)

1. **`winner_prior`/`winner_likelihood` describe `primary_taxon`, not
   `consensus_taxon`.** Confirmed by reading `TaxaAssign::posterior_consensus()`'s
   internal `.consensus_one_observation()` (file
   `TaxaAssign/R/posterior_consensus.R`, ~lines 475–593): `winner_row <-
   plausible[1L, ]` pulls prior/likelihood off the single best-scoring
   candidate row; `.find_lca()` (~lines 624–647) runs afterward on the whole
   tied candidate set to build `consensus_taxon`/`consensus_rank`, and never
   touches `winner_prior`. The two are computed independently. This is not a
   bug — but it means a family-level `consensus_taxon` can be paired with a
   species-level `winner_prior` for one specific candidate, which reads
   misleadingly (see ASV_371 example below).

2. **In `add_posthoc_assessment()`** (file `TaxaFlag/R/add_posthoc_assessment.R`):
   Step 1 (`vague_mask <- is.na(rank) | rank != finest_rank`) unconditionally
   assigns `"vague_rank"` and gates `active_mask <- !vague_mask & !modeled_mask`,
   which gates the entire Step 3 tier×likelihood 3×2 table (`sensible`/
   `limited_evidence`/`unexpected`/`suspect`/`unprecedented`) — that table
   *never runs* for non-species-rank calls, regardless of how the evidence
   looks. Step 4 (`"unsupported_rank"`, based on
   `winner_absolute_fit_pvalue < weak_evidence_pvalue`, default `0.001`) is
   not gated by `vague_mask` and can override `"vague_rank"`, but only if the
   p-value clears that strict threshold.

3. User's read of the current category names, which motivated the redesign:
   `vague_rank` is redundant (rank is already its own column, no need for a
   categorical restatement); `unexpected` is really just a statement about
   the *prior*; `limited_evidence` is really just a statement about the
   *likelihood*. I.e. the current column conflates axes that should be
   separated.

## Findings from real-data investigation (the "three classes" — DO NOT re-derive, just re-read)

Collapsing all 102 non-species rows in the real dataset to 18 unique
(taxon, rank, prior) combinations and cross-referencing against the user's
own domain judgment of what's actually suspect at this site produced:

- **`winner_prior` is a shared, per-taxon value at non-species rank** (same
  prior for every read assigned to the same genus/family — it's the
  group-level dark-diversity prior), not a smooth per-read continuum. This
  matters for any thresholding scheme: it naturally clusters by taxon.

- **Genuinely suspect** (per user, real domain judgment): *Chaenogobius*
  (ASV_379, prior 9.17e-06 = dataset floor, likelihood 0.098) and
  *Prosopium* (ASV_30, prior 2.85e-05, likelihood 0.348). A threshold as
  tight as "prior in the bottom ~2 tiers of this dataset (≤ ~3e-05) AND
  likelihood < ~0.5" reproduces exactly these two and nothing else — the
  likelihood gate is essential; prior alone does not separate suspect from
  plausible-but-locally-undocumented taxa (see next point).

- **NOT suspect despite floor-tier prior, because likelihood = 1.0**:
  Salmonidae (ASV_371, family, floor prior, but `primary_taxon = "Salmo
  trutta"`), Sciaenidae (ASV_382, family, floor prior, `primary_taxon =
  "Pseudotolithus senegallus"`), *Salmo* (ASV_26, genus, prior 2.85e-05).
  These are all confident sequence IDs of taxa that are locally implausible
  as *wild populations* for a different reason each (see below) — not weak
  evidence.

- ***Salmo trutta*/Salmonidae (ASV_371)** — confident ID (likelihood 1.0),
  European brown trout, near-zero CA wild-population prior. Per user:
  "unlikely, but could be a food item." This belongs to the already-open
  **domestic/food-species prior** redesign
  (`[[project_taxaflag_domestic_species_floor_note]]` — designed 2026-07-24,
  not yet re-implemented), not to `add_posthoc_assessment()`. Do not build a
  second mechanism for this.

- **Sciaenidae/ASV_382 — a different problem, NOT a posterior-side fix.**
  Winning candidate set is *Pseudotolithus senegallus/epipercus*, *Sciaena
  umbra*, *Atractoscion atelodus* — West African/Mediterranean croakers,
  likelihood 1.0. Notably *Atractoscion atelodus* is in the candidate set
  but the actual local congener (*Atractoscion nobilis*, white seabass) is
  not. Per user: "the slash taxa... are all implausible. It's not clear to
  me why a local Sciaenidae was not proposed here." Read as reference-
  database representation bias (commercially-important Old World Sciaenidae
  overrepresented in NCBI vs. CA natives) — the locally-plausible candidate
  was never in the pool BLAST returned, so no amount of prior/likelihood
  thresholding on the *existing* candidates can fix it. This is the same
  closed-hypothesis-space limitation flagged earlier in this session's
  discussion, now concretely reproducible. **New, separate investigation
  thread**: something like a geographic-plausibility check *at candidate
  generation*, not at final-assignment scoring (distinct from the existing
  `check_geographic_outliers()` in TaxaHabitat, which operates on chosen
  assignments, not BLAST's candidate pool).

- **Gobiidae (ASV_363/ASV_430/ASV_463) — checked, NOT suspect.** Per user,
  slash taxa include *Eucyclogobius newberryi* (tidewater goby — CA-native,
  endangered, genuinely plausible at Mugu Lagoon specifically) and other
  plausible candidates. Good negative-control confirmation that floor-ish
  prior + moderate likelihood (0.45–0.63) does not automatically mean
  suspect — reinforces that any redesigned diagnostic must not sweep this
  case up as a false positive.

- ***Oncorhynchus* (ASV_13)** — plausible genus, but per user only one
  species in the genus (*O. mykiss*) is actually plausible at this site;
  the `slash_taxon_name` lists `kisutch/tshawytscha/mykiss`. Not flagged as
  a problem to fix right now, just domain color noted for whenever
  species-within-genus plausibility becomes relevant.

- ***Urolophus halleri* — prior is puzzlingly low despite being "quite
  plausible" at this site** (user, verbatim). Three reads (ASV_158/249/447,
  likelihood 1.0 each) correctly land on `"unexpected"` under the *existing*
  species-rank mechanism (matches user's judgment: strong evidence + low
  prior reads as "real detection, database/occurrence-record gap," not
  "implausible"). But a fourth read, **ASV_587** (likelihood 0.347, lower
  than its sibling reads — likely a shorter/noisier individual read), gets
  `"suspect"` from the same existing mechanism — a live example of the
  existing species-rank table over-flagging a locally-common species because
  of one noisy read. **Open investigation** (not yet started): why does
  *Urolophus halleri*'s occurrence-prior computation land near the floor at
  all, given it's genuinely common here? Likely relevant to whichever
  upstream prior-source step (TaxaExpect/GBIF fetch, or the dark-diversity
  floor logic in `join_priors()`) is producing this. Investigate before
  assuming any threshold choice is safe — a systematically-mis-set prior for
  a common species will produce false positives under ANY downstream
  diagnostic, no matter how well-designed.

## The redesign in progress (main task — pick up here)

Decompose `add_posthoc_assessment()`'s single combined category into
(at least) two, possibly three, orthogonal ordinal axes. Semantics come
first; numeric thresholds come only after semantics are agreed (explicit
user instruction — do not skip ahead to picking cutoffs).

**Axis 1 — Prior / occurrence plausibility.** SUPERSEDED 2026-07-26 — do NOT
build this on `model_tier`/tier1/tier2/tier3_undetected. Verified by reading
`TaxaExpect::train_biodiversity_model()`/`generate_full_priors()`/
`generate_undetected_diversity()` directly:
  - tier1/tier2 is a **training-data-sufficiency** distinction, not spatial:
    tier1 = species with >= 5 total detections anywhere in the WHOLE
    training dataset (enough to fit a full spatial GLMM with
    `taxon_name:grid_id` random effects); tier2 = fewer. A tier1 species
    gets predicted at EVERY site via `crossing()`, including sites it's
    never been seen at — tier1 does NOT mean "expected/observed here," it
    means "enough global data existed to fit a real model," and the
    predicted probability at any given low-suitability site can still be
    tiny under a tier1 model.
  - `tier3_undetected` is hardcoded ONLY onto anonymous placeholder rows
    (`taxon_name = NA`: `"singleton_mirror"`, `"global_floor"`) representing
    unmodeled dark diversity. It is NEVER assigned to a real named species.
    A genuinely never-observed named species (e.g. real *Chaenogobius*,
    *Salmo trutta*) has no row in the tier lookup at all, and
    `add_posthoc_assessment()`'s own documented convention treats "not
    found in tiers" as **tier2** — same label as a sparse-but-real record.
  - Consequence: under the CURRENT system, `"unprecedented"` can
    essentially never be assigned to a real taxon — both *Chaenogobius* and
    *Salmo trutta*, despite sitting at the literal numeric prior floor,
    would categorize as tier2/`"unexpected"` if the tier lookup ever ran on
    them (it doesn't in the real data we've been using, because
    `vague_rank` intercepts first at genus/family rank before Step 3 can
    run — meaning the "9 rows near floor" table from earlier in this
    thread never actually exercised this code path). `model_tier` answers
    "was there enough global training data to fit a real statistical
    model for this species" — a methodological question — not "how
    ecologically expected is this species at this location," which is
    what `winner_prior`'s actual VALUE answers. These were conflated in
    the original design.

**REPLACEMENT design (2026-07-26), grounded in real data**: build Axis 1
directly on `winner_prior`'s own numeric value, not on `model_tier`.
Checked the real 616-row Mugu dataset's full sorted-unique `winner_prior`
distribution: there is an **11x gap with nothing in it** between the low
cluster (9.17e-06 to 0.087) and the high cluster (0.966 to 1.0) — a real,
non-arbitrary bimodal split, not something we have to invent a threshold
for. Within the low cluster, the literal mechanistic floor value itself
(9.17e-06, recurring exactly across many unrelated taxa — see the earlier
per-taxon table in this doc) is a second principled, discrete break: at/near
it means "no real occurrence/training data entered this prior calculation
at all" (fell through to the dark-diversity floor mechanism in
`join_priors()`), anything meaningfully above it means some real signal did.
Candidate 3-way split (thresholds still need final confirmation, but the
BREAKS themselves are real, not chosen):
  - `unprecedented`: at/near the literal floor (~9.17e-06 to 2.85e-05 in
    this dataset)
  - `unexpected`: above the floor, below the big gap (~8.47e-04 to 0.087)
  - `expected`: above the gap (~0.966 to 1.0)

This directly answers the user's original question ("does 'seen regionally
but not at grid' map onto unexpected vs. unprecedented, or do we need a 4th
category?") — no 4th category needed: "seen regionally, not at this grid
cell" produces a nonzero-but-low predicted `winner_prior` (lands in
`unexpected`), while "never seen anywhere" collapses mechanistically to the
floor (`unprecedented`) — the floor is already a real, discrete,
meaningfully-different value from everything above it in this data, not a
fuzzy boundary needing a separate category to approximate.

**Axis 2 — Match quality (absolute fit).** SETTLED naming direction (user,
2026-07-26): **`diagnostic` / `marginal` / `inconclusive`**. `marginal` is
the assistant's proposed middle term (not yet explicitly confirmed by user —
check on resume if unconfirmed). User explicitly rejected reusing
"resolved/partial/unresolved" here because "resolution" already means
something specific in this codebase (see Axis 3) — reusing it for match
quality would collide with that meaning.

CORRECTED 2026-07-26 (source read of `add_posthoc_assessment.R` roxygen):
this axis is driven by **`winner_absolute_fit_pvalue`** specifically (NOT
`winner_likelihood` — see Axis 3 for why that one moved). Per the function's
own "Weak absolute evidence" section, `winner_absolute_fit_pvalue` answers
"is this call's own fit to its trained distribution believable at all,
tested independently of any competing candidate" — a pure absolute-fit
question.

THRESHOLDS SETTLED 2026-07-26, grounded in real Mugu data and confirmed
against source (`TaxaLikely::evaluate_likelihoods()`'s `.one_sided_fit_pvalue()`,
`p = pnorm(z)`, `z = (score_logit - trained_mean) / trained_sd` — a genuine
one-sided Gaussian tail probability against the winning candidate's own
fitted H1/H2/H3 distribution, NOT a raw percent-identity threshold test —
raw BLAST `pident` genuinely exists upstream in the match object but is
discarded before `evaluate_likelihoods()`'s output, confirmed by source
read; user explicitly declined pulling it back through as new plumbing,
"was using it as an example," not needed).

Two rejected attempts before landing here, kept for the record:
  1. Fixed p=0.05 (conventional significance-testing cutoff): FAILED
     completely — every single row in a 21-row taxon list spanning the
     whole earlier discussion (including *Chaenogobius*, the original
     motivating case) landed `"diagnostic"`; only 4/616 rows in the whole
     dataset would ever cross it.
  2. Conventional SD/z-score dispersion bands (1/2/3 SD, real statistical
     convention, not arbitrary): ALSO largely failed — real data's implied
     z-score (`qnorm(winner_absolute_fit_pvalue)`) ranges only
     [-1.92, 0.82] across the whole 616-row dataset; nothing reaches -2SD,
     let alone -3SD. A naive 5-band SD scheme would collapse to 3 populated
     bands out of 5, none near either extreme-tail convention.

**User's key methodological correction, explaining why extreme-tail bands
are empty**: this data is heavily CENSORED — only top BLAST matches are
kept (often literal 100% identity), so a healthy cluster at/above the
trained mean is the expected shape for this kind of top-hit-only data, not
evidence of a broken metric. That reframing is what led to the working
3-way split.

SUPERSEDED AGAIN, final settled version (2026-07-26, same day, later):
after working through fixed z-SD bands (above) AND raw p=0.05/dispersion
comparisons, the user reframed the actual goal in plain language —
**"probably right, probably wrong, somewhere in-between"** — which resolved
the earlier tension cleanly rather than picking a side. "Probably wrong" is
a STRONG, decisive claim (not "somewhat below average"), which is exactly
what the standard p<0.05 significance-testing bar expresses (a genuine
statistical outlier) — stronger than the z<-1SD/38-row band, which really
described "somewhat below typical" and belongs in the MIDDLE tier instead
of its own. This is the actually-final 3-way split, using `winner_absolute_fit_pvalue`
directly (no z-transform needed for the final version, though z-language is
equivalent):

  - **`probably_right`**: `p >= 0.5` (at/above trained mean) —
    208/616 rows (33.8%)
  - **`in_between`**: `0.05 <= p < 0.5` — 394/616 rows (64.0%)
  - **`probably_wrong`**: `p < 0.05` (true statistical outlier, standard
    significance convention) — 4/616 rows (0.6%)

The lopsided middle tier (64%) is consistent with, not contradicted by, the
user's own censoring point (below): this is top-hit-only data, so most rows
are "the best candidate found," neither a standout match nor a genuine
anomaly — a rare, strict `probably_wrong` tier is the honest shape here, not
evidence the boundary is too strict. NAMING: leaning toward
`probably_right`/`in_between`/`probably_wrong` directly (plainer, clearer to
a reader) rather than the earlier `diagnostic`/`marginal`/`inconclusive` —
not yet explicitly confirmed by user, check on resume if unconfirmed.

(Earlier, superseded attempt, kept for the record — do not re-derive: fixed
symmetric z-SD bands `diagnostic: z>=0` / `marginal: -1<=z<0` /
`inconclusive: z<-1` gave 208/360/38. Both this and the p=0.05 attempt
directly below were real intermediate steps, not dead ends — each one
narrowed down what the FINAL boundary should mean before landing on the
p<0.05/p>=0.5 pair above.)

10 rows remain NA (see "NA mechanism" note below) — need an explicit 4th
state, not silent NA, matching the old design's `"modeled"` precedent.

**Status of the "exceptional fit, could override an unprecedented prior"
idea**: floated by the user same day, explored (a `>+1SD` tier came back
completely empty in real data, 0/616 rows — flagged as possibly a
train/inference calibration artifact, see below, not necessarily a real
absence of outstanding matches), then IMPLICITLY DROPPED once the
"probably right/in-between/probably wrong" reframing landed on a plain
`p>=0.5` threshold for the top tier instead of a stricter exceptional-fit
bar. Not explicitly closed out with the user — worth explicitly asking on
resume whether they still want a distinct, stricter "exceptional, strong
enough to reconsider an unprecedented prior" state ABOVE `probably_right`,
or whether `probably_right` (p>=0.5) is meant to already serve that
purpose. This is a real open loop, not resolved by the final 3-way split
above — don't assume it's been dropped for good without checking.

**Open, deliberately NOT yet investigated**: whether this specific Mugu
likelihood model ever received the DECIPHER-training-vs-external-BLAST-
scoring recalibration fix from
[[project_train_inference_scale_validity]] (`calibrate_query_noise()`,
`offset_form = "linear"`, adopted ecosystem-wide as the new default
2026-07-18). The real distribution's mean sitting slightly negative
(-0.078) and never exceeding +0.82 SD is CONSISTENT WITH either (a) genuine
real-world degradation of field ASVs relative to clean references, which is
expected and fine, or (b) a residual scale-calibration gap this fix was
built to address. These aren't mutually exclusive and this session did not
determine which applies here — flagged so a future session doesn't
over-trust these exact SD boundaries as universal without checking this.

Open question, unconfirmed: user's "I think it should apply to the
primary_taxon vs the consensus_taxon" — assistant's working interpretation
is that match-quality should be computed/reported for BOTH `primary_taxon`
and `consensus_taxon`, not just `primary_taxon`. Technical open question
this raises: `primary_taxon` is by construction the best-fitting candidate
in the tied set, so a `consensus_taxon`-level version would be asking "how
well does the read fit the *whole* tied set, not just its best member" —
may diverge from primary_taxon's own fit if quality varies a lot across tied
candidates, may not in practice. Check against real data once implementing;
don't assume either way.

**NA mechanism for Axis 2** (confirmed 2026-07-26, real data): the 10 rows
with `winner_absolute_fit_pvalue = NA` are EXACTLY the 10 rows where
`winner_hypothesis_type` is `"unreferenced_genus"`/`"unreferenced_species"`
(606/616 rows are `"specific_candidate"`; only 1 `"unreferenced_genus"` + 9
`"unreferenced_species"`). This is structural, not a data gap: those
hypothesis types represent "something in this genus/species not in the
reference library," so there is no trained per-candidate distribution to
test absolute fit against — nothing to impute. `winner_own_rank_confusion_risk`
is NA on the identical 10 rows, same reason. Needs an explicit 4th Axis-2
state (something like `"not_modeled"`), not silent NA.

**`winner_own_rank_confusion_risk`/`confusion_risk_flag` investigated and
REJECTED as an Axis-2 or Axis-3 candidate driver** (2026-07-26, real data):
checked against the same 13-row taxon subset used throughout this
investigation. Result: does NOT discriminate *Chaenogobius* from the
plausible taxa either (0.204, still landed `"low_confusion_risk"` under the
existing 0.5 threshold) — and actively MISFIRES on Gobiidae/ASV_430 (0.592,
`"high_confusion_risk"`), a taxon the user explicitly confirmed is plausible
(*Eucyclogobius newberryi* among its slash-taxon candidates). Not pursued
further as a driver for any axis in this redesign; existing
`confusion_risk_flag` column can presumably remain exactly as-is,
unrelated to this redesign.

**IMPORTANT COURSE CORRECTION, 2026-07-26 (user)**: earlier in this session
the assistant tried to make Axis 2/3 individually reproduce the
*Chaenogobius*/*Prosopium*-are-suspect judgment from the Axis 1 discussion,
and treated each failure (p=0.05, SD bands, confusion_risk) as a problem
with that axis. User corrected this: **the taxon-suspect discussion was
entirely about PRIOR (Axis 1) plausibility, not about match quality/
likelihood at all** — axes are being kept genuinely INDEPENDENT (not a
single combined diagnostic column like the old `add_posthoc_assessment()`
table did — user: "we might get there eventually," but not now, not the
current goal). It is fine, expected, and NOT a design failure for Axis 2 to
disagree with or fail to reproduce Axis 1's verdict on any given row — they
are answering genuinely different questions. Axis 2's calibration should be
judged only against what IT is supposed to measure (match/fit quality,
analogous to "100% vs 80% match," per the user's own framing), not against
whether it reproduces Axis 1's ecological-plausibility judgment. Keep this
principle in mind for Axis 3 and any future axis work too — do not chase
cross-axis agreement as a validation criterion.

**Axis 3 — Resolution (candidate breadth).** NEW axis, added 2026-07-26 in
response to user agreeing with assistant's earlier question about whether
match-quality needed to split into two things.

SETTLED naming + mechanism (user, 2026-07-26): **`species` / `genus` /
`family` / `unresolved`** — directly reusing `consensus_rank`'s own actual
values as the category set, with `unresolved` as the catch-all for anything
coarser than family (order/class/etc., or a failed/NA LCA). This
deliberately does NOT need `n_plausible` or a taxonomic-span computation at
all — rank itself is already the natural output of how far the LCA had to
climb, which is itself already driven by how many candidates were tied and
how taxonomically spread they were. No new numeric signal or threshold
needed; this axis is just `consensus_rank`, capped/bucketed into 4 levels.
(This resolves the open "n_plausible vs. taxonomic span vs. rank-distance"
question from the previous version of this doc — moot, since rank IS the
signal now.)

Checked real data: in the 616-row Mugu dataset, `consensus_rank` is
`species=514, genus=37, family=65, (coarser than family)=0` — so
`unresolved` is a real, valid category slot but doesn't get exercised in
THIS particular dataset (no order-level-or-coarser LCA calls occurred here).
Keep it in the scheme anyway for generality across other datasets/markers.

Critical distinction from the old `vague_rank`, worth restating clearly
since it's the actual point of this whole redesign: `vague_rank` used
non-species rank to SILENTLY BLOCK Steps 2-4 (the tier x likelihood table)
from running at all. This axis instead gets reported ALONGSIDE Axis 1
(Prior) and Axis 2 (Match quality) for every row, at whatever rank the call
landed at — it never gates or suppresses the other axes. That's what fixes
the original bug (ASV_379/*Chaenogobius* — genus rank — getting no
meaningful assessment at all under the old design).

Example flagged earlier as worth re-checking once this axis is
operationalized (kept for reference, though now lower-priority since this
axis no longer depends on `n_plausible` directly): ASV_371 (Salmonidae) has
`n_plausible = 15` but the visible (truncated in this session's console
output) `slash_taxon_name` only showed *Salmo* species — worth re-pulling
the full untruncated candidate list at some point out of general curiosity
about why the LCA climbed to family, but no longer blocks Axis 3's design.

**Fate of `domestic_prior_caveat` and `modeled` under the new scheme**
(assistant's observation, 2026-07-26, not yet reviewed by user): both get
simpler once the axes are separated. `domestic_prior_caveat` currently a
hardcoded special case inside the combined tier table (Session 149) — under
the new scheme it becomes a plain combination: Axis 1 =
`unexpected`/`unprecedented` + Axis 2 = `diagnostic` + taxon in
`domestic_taxa` — worth considering whether it's still worth a distinct
label or just falls out naturally as "look at these three axes together."
`modeled` (currently: `winner_likelihood` is NA) stays as a genuine
not-computed state, but under the new scheme it should only blank
Axis 2/3 (both currently depend on likelihood-family columns) — Axis 1
(pure prior/tier) doesn't depend on likelihood at all, so a row with no
likelihood computed could still get a real, useful Axis-1 label instead of
being fully opaque the way a single combined column forces it to be today.

**Wrinkle in current Axis 1 source** (found reading `add_posthoc_assessment.R`
directly, 2026-07-26): the existing tier2 branch is
`is.na(tier_vec) | tier_vec == "tier2"` — i.e. "taxon not found in `tiers`
at all" (no occurrence record whatsoever) currently gets the SAME label as
"taxon has a real but weak tier2 record." Under the new Axis 1 naming these
would both be `unexpected` unless we deliberately split them. Not yet
decided whether to split; flagged as a real decision, not an oversight to
silently fix.

**Axis 4 — Posterior / overall confidence.** Renumbered from "Axis 3" in the
original draft of this document. Still not agreed whether this should exist
as a separate categorical column at all. Concern raised (by assistant, not
yet agreed/disagreed by user): may be redundant with existing
`consensus_posterior` (numeric) and `confusion_risk_flag` (existing
categorical, HIGHER = weaker evidence — opposite polarity convention from
most of the rest of the ecosystem, already documented). Decide deliberately
rather than adding a fourth axis by default.

**`vague_rank`**: REVISED verdict (was: "just drop it, redundant with
consensus_rank" — that undersold it). Correct framing: `consensus_rank`
already says *what* rank a call landed at; `vague_rank` was crudely trying
to say *why* (coarse because nothing else was close, vs. coarse because
everything was close) but could only express it as a binary short-circuit
that blocked all other classification for non-species ranks. The new
Resolution axis (Axis 3) properly captures that same information as a
graded signal instead. So: `vague_rank` the *category* still goes away, but
its *intent* is preserved and improved via Axis 3, not simply discarded.

**primary_taxon vs. consensus_taxon**: user asked whether we should (a)
make explicit that current diagnostics describe `primary_taxon`, likely via
a naming fix (candidate: `winner_prior` → something like
`primary_taxon_prior`, not decided/agreed — a real rename would need every
consumer of `winner_prior`/`winner_likelihood` audited, including
`review_assignments()`'s already-wired `winner_prior_col` param from
earlier this session), and (b) *also* compute a parallel assessment for
`consensus_taxon` itself (e.g. "is a family-level *Salmonidae* call
unsurprising"). (b) is NOT just a naming exercise — it requires a genuine
mass-conserving hierarchical/aggregate prior over the consensus taxon's
member taxa, which doesn't exist yet. That is the same open work as
**dark-diversity-redesign Issue 3** (see
`[[project_dark_diversity_redesign]]` in assistant's persistent memory, not
in this repo). Treat (a) as tractable now/soon; treat (b) as blocked on that
larger prerequisite — don't try to build a fake/approximate consensus-taxon
prior just to unblock this column redesign.

## Full open-thread list (carry all of these forward — do not silently drop any)

1. **Main task**: finish axis semantics (this document's "redesign in
   progress" section) → then thresholds → then implement in
   `TaxaFlag/R/add_posthoc_assessment.R` (tests currently pass at
   time of writing; will need substantial new/rewritten tests for whatever
   the final category scheme is, this file currently has no test count
   noted here — check `devtools::test()` fresh before editing).
2. Naming/clarity fix: current diagnostics are primary_taxon-scoped, not
   consensus_taxon-scoped — likely a rename, needs a consumer audit
   (`review_assignments()` at minimum).
3. Hierarchical mass-conserving prior for consensus_taxon (prerequisite for
   full primary_taxon/consensus_taxon parity) — same work as dark-diversity
   Issue 3, tracked in assistant memory, not this repo.
4. *Salmo trutta*/Salmonidae food-item signal — route to the existing,
   already-designed-but-not-yet-reimplemented domestic/food-species prior
   work (`[[project_taxaflag_domestic_species_floor_note]]`). Do not build
   a second mechanism inside `add_posthoc_assessment()` for this.
5. Sciaenidae/ASV_382 candidate-generation gap — new thread, needs its own
   investigation into BLAST/reference-database geographic representation,
   likely a candidate-generation-stage check rather than anything in
   `TaxaFlag`.
6. *Urolophus halleri*'s puzzlingly low prior + the ASV_587 over-flag it's
   likely causing under the *existing* mechanism — investigate the
   occurrence-prior computation for this species before finalizing any new
   threshold, since a systematically wrong prior will fool any downstream
   diagnostic regardless of design quality.

## Working style notes for whoever resumes this (may be a fresh Claude session)

- The user pressure-tests every proposal against real data and their own
  domain knowledge before agreeing to any threshold or category scheme —
  expect concrete numeric/taxon-level pushback, and treat it as the primary
  validation mechanism (this document's "Findings" section is the product
  of exactly that process, not of the assistant designing in the abstract).
- Do not pick numeric thresholds before category semantics are agreed —
  explicit instruction this session.
- Do not implement code changes without an explicit go-ahead — established
  pattern all session ("I'm happy with implementing if you are confident
  it's robust", "Yes, go ahead and fix it.").
- Ground every claim about current behavior in the real
  `MuguWilderFish_blast_consensus_final.rds` object or actual source reads,
  not memory of earlier numbers in this thread — the file's own "Findings"
  section should be treated as a checkpoint to re-verify if anything here
  seems inconsistent with a fresh read of the code/data, not an
  unquestionable ground truth.
