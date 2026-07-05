# Re-entry Prompt — Session 134b: spatial grouping implemented, fetch-scope wiring next

**Status:** The automatic spatial grouping mechanism from
`REENTRY_PROMPT_session134_single_observation_pipeline.md`'s Thread 2 is now
implemented, tested, and `devtools::check()`-clean across three packages. This prompt
picks up the remaining, larger items from that prompt's suggested order (items 2-3
partially done, 4 and 6-8 still open).

---

## Git branch: `single-observation-pipeline`

Same branch as the original session 134 prompt. Confirm before starting:
```
! git -C "~/My Drive/Rscripts/projects/TaxaID" branch
```
Should show `* single-observation-pipeline`.

---

## Two deliberate deviations from the original session 134 prompt

1. **Unboxed observations are not dropped.** The original prompt specified: "Points
   outside every drawn box are dropped from consideration, with a clear alert to the
   user." The user redirected this before any of it was implemented: unboxed /
   out-of-every-box observations are placed in their own single-observation spatial
   group instead, with a `message()` explaining why. This applies whether some points
   fall outside drawn boxes, or the user draws no box at all (in which case every
   observation ends up in its own group). This is now the actual behavior of
   `TaxaFetch::group_observations_by_bbox()` -- treat it as settled, not still open for
   debate.

2. **Naming: `spatial_group_id` / `spatial_group_map`, no separate "independent"
   convention.** The column/param started out as `group_id`/`group_map` with a special
   `"independent_<id>"` string for unboxed observations. The user flagged this before
   committing: bare "group" is already used for unrelated concepts elsewhere in this
   ecosystem (`TaxaAssign::assign_taxa_llm()`'s `context_group`/`.build_group_map()` for
   LLM-batching context groups; `TaxaExpect` also uses "group" for taxonomic grouping),
   and "cluster" -- the other naming candidate -- is *already taken* by `TaxaLikely`'s
   acoustic calibration work (`cluster`/`true_cluster`/`CLUSTER_MAP` = confusable-species
   groups, a completely different concept). Renamed throughout to
   `spatial_group_id`/`spatial_group_map`. Separately, the user also decided there
   should be no distinct naming convention for single-observation groups at all: a
   single-observation spatial group isn't a different *kind* of thing, it's a
   `spatial_group_id` with the same `"spatial_group_<n>"` shape as any other, just with
   one member -- continuing the same sequential numbering rather than a
   `"independent_<id>"` special case. This cost nothing downstream:
   `update_prior_from_consensus()`'s eligibility check already worked by counting how
   many observations share a `spatial_group_id` (`table()` + `>= 2L`), never by
   pattern-matching the id string, so dropping the special prefix required no logic
   changes, only renaming. **If you add more spatial-group-aware code, follow this
   convention** -- distinguish multi-member vs. single-observation groups by counting
   membership, never by a naming pattern.

---

## Round 2: architecture questions raised after reviewing the implementation (not yet resolved)

After the implementation above, the user reviewed it and raised several real design
concerns before agreeing to commit. **None of this is implemented yet** -- the code
described in "What's done" below still reflects the pre-Round-2 design. Read this section
before touching `group_observations_by_bbox()`, `build_site_table()`, or
`update_prior_from_consensus()` again.

**Settled in Round 2:**
- **`build_site_table()`'s output table gets a `spatial_group_id` column by default,
  defaulting to `observation_id`.** This directly solves the original worry ("downstream
  functions will assume `spatial_group_id` exists; a match object/site table built
  without ever calling `group_observations_by_bbox()` would be missing it") without
  merging site info onto the canonical match object (which would have reversed
  `TaxaMatch/CLAUDE.md`'s documented "sample context is a separate table, not part of the
  match object" rule -- that rule stays intact). Every site table has a valid,
  non-missing `spatial_group_id` from the moment `build_site_table()` produces it -- it
  just starts out as "each observation is its own singleton group" (`spatial_group_id ==
  observation_id`) until the user actually groups anything.
  `group_observations_by_bbox()` should now be reframed as **updating** this
  pre-populated column (for whichever observations the user draws boxes around),
  not creating it from scratch.
- **Manual spatial-group assignment must also be supported**, not just the interactive
  `group_observations_by_bbox()` gadget. The user wants a way to set `spatial_group_id`
  values directly (e.g., for a study where the grouping is already known from metadata,
  or to hand-correct a few observations after the interactive step) without necessarily
  drawing boxes. **Mechanism not yet decided** -- could be as simple as documenting that
  callers may edit the plain `spatial_group_id` column directly (it's an ordinary
  character column, no special encoding), or a small validating helper function (e.g.
  `assign_spatial_group(sites, observation_ids, spatial_group_id)` that checks the target
  id doesn't collide with an existing different group unexpectedly, or that all named
  `observation_id`s exist). Ask the user which they want before building it.

**Still genuinely open -- ask before implementing:**
1. **Package placement -- worth a full discussion, not a quick pick.** The user's own
   framing (2026-07-04): this decision *depends on whether `define_search_polygon()` can
   be generalized to serve both purposes* -- drawing a spatial-group boundary AND drawing
   an occurrence-fetch search area. If one generalized gadget can cleanly do both jobs
   (parameterized by purpose/labels/etc.), that argues for moving it to TaxaTools as a
   shared utility, with TaxaFetch (search-area use) and TaxaMatch (spatial-group use,
   where `group_observations_by_bbox()` would then also live) both calling it. If the two
   purposes actually need meaningfully different gadget behavior (e.g. because of item 2
   below -- multi-group point coloring, editing previously-drawn shapes, default-to
   -enclose-all-points), a shared gadget might not cleanly serve both and the packages
   should stay separate with their own tailored tools. Resolve this by first designing
   what the generalized (or non-generalized) `define_search_polygon()` actually needs to
   do for both use cases (see item 2), *then* decide placement -- don't decide placement
   first and force the design to fit.
2. **Search area vs. spatial group are different things, not yet reconciled in code.**
   The bounding box used to *define which observations belong to a spatial group* and
   the bounding box used to *fetch occurrence/reference data for that group* are
   conceptually distinct -- the fetch search area is often larger/more complex (searching
   beyond the group's own extent produces broader, more useful priors), and a user
   drawing search areas should see the observation points **colored by their already
   -assigned `spatial_group_id`**, so they can confirm each search box contains at least
   one whole spatial group and decide whether spatially-separated groups need separate
   search areas. This is good, accepted design direction, not a fully specified one --
   needs its own design pass (probably as part of item 1, "fetch-scope branching," in the
   "What's still open" list below, since it's the same seam: what happens once
   `spatial_group_id` exists and something needs to actually fetch data for each group).
   Concretely will need: (a) `points` param support for a group/color column (not just a
   flat overlay) in `define_search_polygon()`, and (b) a real decision on whether the
   fetch-search-area step is a separate interactive call per group, an automatic
   buffer/expansion of each group's own bbox, or both (user's choice per group).

**Settled 2026-07-04 (after further review):**
3. **`spatial_group_N` -- keep it.** Confirmed wanted, as a simple, easy-to-maintain
   summary statistic: the group's member count (defaults to 1). Lets consumers check
   `spatial_group_N > 1` directly on a row instead of recomputing
   `table(spatial_group_id)` every time. Should be kept in sync wherever
   `spatial_group_id` is written (both `build_site_table()`'s default and
   `group_observations_by_bbox()`'s/the manual-assignment mechanism's updates).
4. **Overlap rule: last-drawn-wins, with a warning.** Reverses the current code's
   implicit first-drawn-wins behavior in `.assign_spatial_groups_from_polygons()` -- when
   an observation falls inside more than one drawn polygon, the *most recently drawn* one
   should claim it (not the first), and the user should be warned which observations were
   ambiguous. Rationale (implicit in the user's phrasing): a later box is more likely to
   represent a deliberate correction/refinement of an earlier one covering the same area,
   so it should take precedence. **Not yet implemented** -- current code still does
   first-drawn-wins silently; needs updating.
5. **Editing during the drawing process -- new requirement, not yet designed.** The
   interactive loop needs a way to edit/undo a previously-drawn box, not just add new
   ones on top or cancel the whole session. Currently `group_observations_by_bbox()`'s
   loop only supports: draw a box -> Done (records it, continue) or Cancel (stops the
   loop, keeps everything drawn so far) -- there's no way to go back and reshape or
   delete an earlier group's box once recorded. Needs its own design pass: options might
   include re-opening a previously-drawn polygon for editing (by number/label), an
   explicit "undo last group" action, or a review step at the end showing all drawn
   groups with per-group edit/delete controls before finalizing. Not specified further
   than "we need options for this" -- design before implementing.
6. **Default starting polygon should encompass all the (remaining) points.** Currently
   `.bbox_center_radius()` computes a centre + padded half-width square around whichever
   points still need a group -- this already happens to include every remaining point for
   the *first* box (nothing is grouped yet), but the user's framing suggests this should
   be an explicit, deliberate default (start with a box that fully encloses the current
   working set, which the user then shrinks down to carve out the first group) rather than
   an incidental consequence of the padding math. Worth confirming `.bbox_center_radius()`
   -- or its replacement, if the gadget is redesigned per items 1-2 -- actually guarantees
   full enclosure (not just "usually roughly covers everything given the current pad
   factor") before relying on it as a stated design property.

**Do not implement any of "What's done" changes described below as final** -- some of it
(the `group_id`/`independent_*` -> `spatial_group_id` rename, dropping the special
singleton-naming convention) is settled and should stay; but the `spatial_group_id`
default-to-`observation_id` behavior, the package location, the overlap rule change, and
the editing/default-polygon requirements above are all still open (or newly decided but
not yet coded) as of the end of this session. Confirm with the user before changing
`group_observations_by_bbox()`/`build_site_table()`/`update_prior_from_consensus()` again.

---

## What's done (this session, 2026-07-03) -- pre-Round-2 implementation, still accurate for what it covers

1. **`TaxaFetch::define_search_polygon()`** — added `points` param (data frame with
   `lat`/`lng`), overlaid as small non-interactive markers. Backward compatible.
2. **`TaxaFetch::group_observations_by_bbox()`** (new) — loops
   `define_search_polygon()`, re-centring on whichever observations still need a
   group, until the user cancels (signals "done drawing groups", not "discard
   everything"). Point-in-polygon assignment via `sf::st_within()`. Implements both
   deviations above. Internal helpers `.bbox_center_radius()` and
   `.assign_spatial_groups_from_polygons()` are pure and unit-tested (15 tests, fully
   offline) — the interactive loop itself is not (same testing boundary as
   `define_search_polygon()`).
3. **`TaxaMatch::build_site_table()`** (new) — unifies per-observation site info
   (`observation_id`, `lat`, `lon`, `observed_on`) into one long-format table.
   Image pathway: extracted from `score_image_inat()`'s embedded `lat`/`lng`.
   DNA/BLAST and acoustic: confirmed this session that neither carries site info at
   all (`read_birdnet_output()` has zero GPS/site columns — only detection-window
   times and source filename); both require an externally supplied `site_df`, which
   may have more than one row per `observation_id` (the ASV multi-site case). 14
   tests, fully offline.
4. **`TaxaAssign::update_prior_from_consensus()`** — added optional
   `spatial_group_map` param (`observation_id`/`spatial_group_id`). When supplied,
   only observations sharing a `spatial_group_id` with >= 1 other observation (a
   multi-member spatial group) can confirm species or receive the prior boost;
   observations in a single-observation spatial group (including newly-singleton
   unboxed ones) are always returned unchanged. `NULL` default preserves prior
   behavior exactly (non-breaking). 7 new tests.

All three packages: `devtools::document()` + `devtools::test()` + `devtools::check()`
run clean (0 errors, 0 warnings, 0 notes; pre-existing warnings/skips unaffected).
Not yet committed as of this prompt being written — check `git log` / `git status`
before assuming.

---

## What's still open

### 1. Fetch-scope branching (original prompt's item 4) — the actual wiring

`spatial_group_id` now exists as a column (from `group_observations_by_bbox()`), but
nothing yet *consumes* it to change fetch behavior. Needed:
- For a multi-member spatial group: pool candidate species, one shared bbx
  occurrence/reference fetch (existing clustered `build_priors()`/
  `train_biodiversity_model()` design — this part already works, just needs to be
  handed the pooled candidate list).
- For a single-observation spatial group: escalate **that observation's own
  candidates** taxonomically (genus -> family -> order) instead of spatially. **This
  escalation ladder does not exist as reusable code anywhere in the ecosystem yet** —
  it was only validated empirically in ad hoc session scripts in the prior
  (non-branch) session, on real PtConception 12S queries and real GBIF
  bobcat-photo data. Building it as an actual function (something like
  `escalate_taxonomic_scope()` or a new parameter on the existing fetch/reference
  functions) is real new engineering, not just wiring — budget accordingly.
- Determine group size (multi-member vs. single-observation) by counting how many
  rows share a `spatial_group_id` -- do not add a new naming convention to
  distinguish them (see the naming deviation above).

### 2. Reads-table relocation (original prompt's item 2, second half)

`TaxaFlag/inst/contaminant_workflow.R` has an ad hoc `pivot_longer()` step (wide ASV x
sample -> long) but it only extracts `event_id`; it does not parse per-sample place +
time out of the sample-label convention the way the reentry design assumed ("Reads
table... columns = sample labels each carrying an associated place AND time"). Before
relocating this to TaxaMatch as originally proposed, **first verify what a real
Reads-table's sample-label convention actually encodes** (ask the user for a real
example, don't assume) — the design may need adjusting once that's confirmed. This
would feed `build_site_table()`'s `site_df` argument for the sequence pathway.

### 3. `TaxaAssign` `(observation_id, site)` schema (original prompt's item 6)

Still flagged as probably deserving its own session. Depends on item 2 above being
resolved first (the reentry prompt's own suggested order has this last for a reason —
step 2 may surface information that changes how this should be designed).

### 4. Documentation (original prompt's item 7)

Still not started: the "Step 1.5" fork writeup in `TaxaAssign/vignettes/
taxaid-ecosystem.Rmd`, the `README.md` pointer, `ecosystem_docs/ECOSYSTEM_WORKFLOW.md`
technical mechanics, and the `TaxaFetch` vignette cross-reference. Now that
`group_observations_by_bbox()` and `build_site_table()` are real, this can describe
actual function calls rather than speculative ones — but should still wait until
item 1 (fetch-scope wiring) is real too, so the doc describes the whole seam
end-to-end rather than half of it. Use `spatial_group_id`/`spatial_group_map`
terminology throughout, consistent with the naming deviation above.

### 5. Loose thread, still not reconciled

The "likelihood-model registry / prior cache" idea (keyed by marker+family/order for
likelihoods, species+grid_id for priors) from earlier in the original session was never
reconciled with the automatic-grouping framework. Still an open question: does grouping
supersede the need for a cache, or would a cache still help for post-grouping-singleton
escalation (e.g. caching a broadened-fetch model per taxonomic scope, reused across
many unrelated single-observation groups that happen to share a genus)? Flag explicitly,
don't assume either way.

---

## Suggested order for the next session

1. **Design discussion first: can `define_search_polygon()` serve both the spatial
   -group and search-area purposes?** (items 1-2 above). This determines package
   placement and the shape of the multi-group editing UX (item 5) and default-polygon
   behavior (item 6) -- resolve before writing code, since the answer changes which
   package gets which files.
2. Implement the now-settled pieces: `spatial_group_id` (defaulting to `observation_id`)
   + `spatial_group_N` (member count, defaulting to 1) in `build_site_table()`'s output;
   `group_observations_by_bbox()` updates both in place; last-drawn-wins-with-a-warning
   overlap resolution in `.assign_spatial_groups_from_polygons()`; the manual-assignment
   mechanism (shape still TBD -- ask before building); the editing/undo requirement and
   default-encompass-all-points starting behavior (both need their own design pass, see
   items 5-6).
3. Confirm this session's (pre-Round-2) 3-package changes are committed (or commit them
   first if the user wants that) -- check whether the Round 2/3 changes above should go
   in the same commit or a follow-up one.
4. The Reads-table relocation item (verify real Reads-table format with the user) before
   touching the TaxaAssign schema item.
5. Fetch-scope wiring — the escalation ladder is the real engineering lift here, and now
   also carries the search-area-vs-spatial-group design from item 2 above.
6. TaxaAssign `(observation_id, site)` schema once the Reads-table item is resolved.
7. Documentation last, once the mechanics above are real.
