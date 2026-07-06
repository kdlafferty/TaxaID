# Reentry Prompt: Multi-Site Posterior Combination (Phase 5 + Phase 6 Kickoff)

**STATUS: Phase 5 COMPLETE (2026-07-05, Session 138).** `join_priors()`'s dedup fixed
(grid_id/main_habitat-aware) and `combine_multisite_priors()` implemented and wired into
`TaxaID_Workflow_Template_TEST.R` Section 7. **The combination rule actually implemented
differs from both options below**: mid-session, the user questioned whether either rule
weights by confidence, and an empirical check (see `TaxaAssign/CLAUDE.md`'s Session 138
note) showed neither did -- the plain product ignores confidence entirely, and full Monte
Carlo simulation shifts weight *toward* a noisy site's minority pick, not away from it.
Implemented instead: precision-weighted combination in logit space (exact
digamma/trigamma mean+variance of a Beta's log-odds, inverse-variance weighted). Phase 6
(the four-scenario real end-to-end test matrix) is NOT done -- still blocked on live
BLAST/NCBI/GBIF + an interactive RStudio session, see that section below, unchanged from
when this was written.

---

**Original status when written: design decided with the user, nothing implemented yet.**
Written 2026-07-05 (Session 137, continued from the observation-pipeline-wiring work),
branch `single-observation-pipeline`. Read this first when re-entering Phase 5 of
`ecosystem_docs/REENTRY_PROMPT_session137_observation_pipeline_wiring.md`.

---

## The one-paragraph version

Phase 4 (DNA/BLAST half) made a real multi-site single observation reachable in this
ecosystem's own bundled test data for the first time (`OQ846725`, real reads at both
`sample_1` and `sample_2` in `TaxaID_Workflow_Template_TEST.R`). Testing what
`TaxaAssign::join_priors()` actually does with such an observation (not just reading the
code) found a real, currently-shipping correctness bug: its multi-site `site` data-frame
path silently keeps only the highest-`prior_mean` site pairing **per candidate taxon**,
via an `arrange(desc(prior_mean)) |> distinct(observation_id, taxon_name,
taxon_name_rank, .keep_all = TRUE)` call that almost certainly exists to dedupe a
different case (coarse-rank-expansion artifacts) and was never designed with multi-site
observations in mind. Each candidate ends up matched to *its own* most favorable site
rather than the site the ASV was actually detected at, which can turn a confident,
correct call into a nonsensical tie (empirically confirmed below). The user decided how
multi-site evidence *should* combine (multiplicatively, treating detection at multiple
sites as independent confirmatory evidence for the same identity) before any
implementation, per this repo's own convention for statistical-design decisions.

---

## The empirical finding (reproduce this before touching code)

Real repro run this session (`TaxaAssign::join_priors()` + `compute_posterior()` +
`posterior_consensus()`, real package functions, tiny synthetic data mirroring the real
`OQ846725` case — not the actual GBIF-fetched values, since those need a live BLAST/GBIF
run):

- One observation, two candidates (`Species_a`, `Species_b`), two sites (`site1`,
  `site2`). `Species_a` has a strong local prior at `site1` (alpha=8,beta=2) and weak at
  `site2` (alpha=1,beta=9); `Species_b` is the mirror image.
- **Site 1 alone:** `Species_a` wins decisively (posterior 0.947 vs 0.053).
- **Site 2 alone:** `Species_b` wins decisively (posterior 0.780 vs 0.220).
- **Current combined (multi-site `site` data frame) behavior:** `Species_a` gets
  matched only to `site1`'s prior (0.8), `Species_b` only to `site2`'s prior (0.8) —
  each candidate cherry-picks its own best site. Posteriors end up 0.692 vs 0.308, and
  `posterior_consensus()` gives up and returns the family-level LCA (`"Familyx"`,
  `n_plausible = 2`) — not a considered combination of the two sites' real evidence, an
  artifact of the `distinct()` call silently discarding the "wrong" site pairing for
  each candidate.

Re-run this repro (script embedded in this session's conversation, not saved to a file
yet) before assuming the bug still reproduces the same way — confirm current behavior
directly rather than trusting this description, per this repo's own standing practice.

---

## Design decision (confirmed with the user this session)

**Combine evidence from all sites multiplicatively, not by picking the most confident
site or averaging.**

Key structural fact: the *likelihood* (sequence-match quality against reference data) is
identical across sites — it's the same physical read. Only the *prior* (local
occurrence probability) differs by site. So this is not "average two noisy estimates of
one number" — it's "does this candidate explain presence at site 1 **and** site 2
simultaneously."

Recommended combination rule: for each candidate species k detected at sites
`{s_1, ..., s_n}`, `prior_combined(k) ∝ prod_i prior_{s_i}(k)`, renormalized across all
candidates so it sums to 1 again. The single shared likelihood is used once (not
duplicated per site). This is the same idea as summing independent log-odds — consistent
with this ecosystem's existing use of logit-style combination elsewhere (e.g.
`TaxaLikely::correct_training_bias()`).

**For the Monte Carlo uncertainty path** (`compute_posterior()`'s existing
Beta-sampling): do the combination *inside* the simulation loop rather than deriving a
closed-form combined Beta (a product of two Betas is not itself Beta-distributed) --
draw `theta_{s_1} ~ Beta(a_1,b_1)`, ..., `theta_{s_n} ~ Beta(a_n,b_n)` independently per
simulation per candidate, multiply, renormalize across candidates within that simulation
draw, then proceed as usual. Confirm this design (vs. a moment-matched Beta
approximation, which is simpler but introduces approximation error) at the start of
implementation -- leaning toward the simulation-based approach for correctness, but not
finally decided.

**Explicit caveat to document wherever this lands:** this assumes the sites are
*ecologically independent* -- knowing the species is at site 1 tells you nothing extra
about site 2 beyond the species' own biology. If two "sites" are actually near-duplicate
subsamples of the same real location, multiplying double-counts the same evidence and
overstates confidence. This is a judgment call for whoever builds the site metadata
(`TaxaMatch::join_event_site_metadata()`'s `site_metadata` table), not something code can
detect -- state it as a modeling assumption, don't try to guard against it
automatically.

---

## Recommended architecture (confirm before implementing)

1. **Fix `join_priors()`'s dedup to be site-aware, not a full rewrite.** The
   `arrange(desc(prior_mean)) |> distinct(observation_id, taxon_name, taxon_name_rank,
   .keep_all = TRUE)` call (search for it in `R/join_priors.R`, near the end of the
   function) should add `grid_id` (and `main_habitat`) to the `distinct()` columns --
   `distinct(observation_id, taxon_name, taxon_name_rank, grid_id, main_habitat,
   .keep_all = TRUE)`. This preserves one row per (observation, taxon, site) triple
   instead of collapsing across sites, while still deduping whatever same-site
   duplicates the original call was meant to catch (trace `.expand_coarse_rank_rows()`
   first to confirm what those duplicates actually look like before assuming this is
   sufficient).
2. **New function, tentatively `TaxaAssign::combine_multisite_priors()`** (confirm
   name/package placement -- TaxaAssign seems right, it's the schema-owning package),
   inserted between `join_priors()` and `compute_posterior()`. Input: `join_priors()`'s
   (now site-preserving) output. For any `(observation_id, taxon_name)` with more than
   one row (i.e. detected at more than one site), combine per the rule above into one
   row; observations with only one site pass through unchanged. Output: same shape
   `join_priors()` already produces (one row per candidate per observation), so
   **`compute_posterior()`, `posterior_consensus()`, and
   `update_prior_from_consensus()` need no changes** -- they already operate on exactly
   this shape. This keeps the fix small, isolated, and independently testable, matching
   this ecosystem's existing preference for small composable functions over modifying
   `compute_posterior()`'s already-dense internals.
3. **Wire the new step into `TaxaID_Workflow_Template_TEST.R`'s Section 7**, right after
   `join_priors()` and before `compute_posterior()`.

## What's confirmed done (Phases 1-4, don't redo)

- Phase 1: `TaxaTools::escalate_taxonomic_rank()` -- escalation ladder, live-verified.
- Phase 2: `TaxaID_Workflow_Template_TEST.R` wires spatial grouping through Sections
  2.5/3/5/7 (parse-verified + isolated logic tests, not a full live run -- BLAST/GBIF/LLM
  + interactive gadgets are out of scope, deferred to Phase 6).
- Phase 3: `score_image_workflow.R`'s `OVERRIDE_SITE_LATLNG` flag + `build_site_table()`
  call, live-verified against the real bundled photo set (both flag settings).
- Phase 4 (DNA/BLAST half): `TaxaMatch::join_event_site_metadata()`, wired live into
  Section 2.5 using the bundled `Reads_Table`'s real `sample_1`/`sample_2` columns as
  genuinely different sites -- this is what surfaced the bug above. Acoustic half
  deliberately deferred (no real multi-site BirdNET deployment data exists to wire
  against honestly).

See `TaxaTools/CLAUDE.md`, `TaxaMatch/CLAUDE.md`, and `TaxaID/CLAUDE.md`'s Session 137
notes for full detail on each.

## Phase 6 — test matrix (do after Phase 5 lands)

The three scenarios from the original Session 137 plan, now with a concrete real
multi-site case to test against instead of only a hypothetical one:
1. **Single observation** -- escalation ladder path (Phase 1), no pooling.
2. **One clustered group** -- multiple *different* observations sharing one bounding
   box, pooled `build_priors()`-style fetch (already working pre-Session-137).
3. **Multiple independent groups (mixed)** -- some observations cluster, others don't,
   in the same batch.
4. **NEW: one observation, multiple real sites** (`OQ846725`'s exact case) -- verify
   `combine_multisite_priors()` produces a sensible, non-ambiguous combined posterior
   given clearly-differentiated per-site evidence (the repro above is the starting
   fixture), and that it's *never worse* than either site alone in the sense of
   collapsing a clear signal into a tie.

None of these have been run through a real end-to-end workflow yet. A full live run of
`TaxaID_Workflow_Template_TEST.R` needs: live BLAST + NCBI + GBIF calls, an Anthropic API
key, and two interactive Shiny gadgets (habitat review, spatial-group box-drawing) --
plan for an interactive RStudio session, not a headless one, when this phase actually
runs.

## Open questions to resolve at the start of implementation

1. Simulation-based combination (per-draw product + renormalize inside
   `compute_posterior()`-adjacent logic) vs. a moment-matched closed-form Beta
   approximation for `combine_multisite_priors()`'s alpha/beta output -- leaning
   simulation-based for correctness, not finally decided.
2. What `.expand_coarse_rank_rows()` actually produces duplicate-wise -- confirms
   whether the `grid_id`-aware `distinct()` fix (item 1 above) is sufficient on its own
   or needs to run before/after coarse-rank expansion in a specific order.
3. Function name/package placement for the new combination step -- `TaxaAssign`
   assumed, `combine_multisite_priors()` a placeholder name, both worth a quick
   confirm-before-you-build check with the user given this repo's naming-collision
   discipline (see `feedback_naming_collision_check` memory).

## Related reading, don't re-derive

- `ecosystem_docs/REENTRY_PROMPT_session137_observation_pipeline_wiring.md` -- the
  parent plan; Phase 5's original (pre-decision) framing is there.
- `TaxaAssign/R/join_priors.R` -- the `arrange(desc(prior_mean)) |> distinct(...)` call
  near the end of the function is the exact bug location.
- `TaxaAssign/R/compute_posterior.R` -- the Monte Carlo Beta-sampling path this new step
  needs to compose with (or feed into) cleanly.
- `~/.claude/projects/-Users-lafferty/memory/project_single_observation_pipeline_design.md`
  and its linked memories -- ecosystem memory index for this whole branch of work.
