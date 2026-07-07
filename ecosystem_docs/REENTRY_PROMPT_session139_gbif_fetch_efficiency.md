# Reentry Prompt: GBIF Fetch Efficiency (Taxon-Centric Query Grouping)

**STATUS: design discussed with the user, not implemented. Written 2026-07-06 (Session
139, continued from Session 138's Phase 6 live-testing work), branch `main`.** Read this
when picking up the GBIF-fetch-efficiency follow-up flagged during Session 138/139's
Phase 6 live run.

---

## Context: how this came up

While the user was running `TaxaID_Workflow_Template_TEST.R` live in RStudio (Phase 6 of
`ecosystem_docs/REENTRY_PROMPT_session138_multisite_posterior_combination.md`), a
headless pre-check (Sections 0-3) surfaced and fixed two real bugs first:

1. **Stale `TaxaTools` install** -- `escalate_taxonomic_rank()` (added Session 137) was
   never reinstalled after being added to source. Fixed by re-running
   `ecosystem_docs/install_all.R`. Not a design issue, just a reminder that the "restart +
   reinstall + restart" convention in `TaxaID/CLAUDE.md` matters across session/day
   boundaries.
2. **Section 3/5 group-vs-multisite conflation** (real bug, now fixed, see below).

While discussing #2's fix, the user asked a sharper question: since a single multi-site
observation's per-site occurrence fetches (Section 3's singleton branch, post-fix) can
have overlapping search areas, are we duplicating GBIF searches / downloaded records?
That question generalized into this reentry prompt's actual subject: **how the whole
occurrence-fetch step should be organized to avoid redundant GBIF queries and duplicate
records, now that fetch geometry and prediction geometry are understood to be separable
concerns.**

---

## Bug #2, fixed this session (already committed... check `git status` before assuming;
## as of this writing it is modified-but-uncommitted in `inst/TaxaID_Workflow_Template_TEST.R`)

**The bug:** Section 3's branch condition (`nrow(group_sites) >= 2L`) and Section 5's
`group_centroids` (`mean(lat), mean(lon)` per `spatial_group_id`) both conflated "multiple
different observations sharing a bounding box" (a real cluster) with "one observation
detected at multiple sites" (the multi-site case Session 138's
`combine_multisite_priors()` was built for). This template's own bundled `OQ846725`/
`ASV_2` case (2 site rows, 1 `observation_id`) triggered the wrong branch: Section 3 tried
to call the interactive `define_search_polygon()` gadget (crashing headlessly, as
expected -- but also *wrong behavior*, not just an interactivity gate), and Section 5
would have averaged its two real, distinct sites into one collapsed centroid, silently
destroying the very per-site distinction `combine_multisite_priors()` needs to combine.
This was flagged but explicitly deferred in Session 137's own Section 0 comment
("KNOWN LIMITATION... not resolved here") and was outside Session 138's scope (which only
touched `join_priors()`/`combine_multisite_priors()`, not the template's fetch/prior
sections). Phase 6 (actually running the pipeline) is exactly what was supposed to catch
this, and did.

**The fix (verified, not just theorized):**
- Section 3: branch on `dplyr::n_distinct(group_sites$observation_id) >= 2L` instead of
  `nrow(group_sites) >= 2L`. The singleton branch now loops the existing escalation-ladder
  fetch over *every* site row belonging to the (single) observation, not just row 1.
  Verified live: re-running headlessly showed genuinely different record counts fetched
  at `ASV_2`'s two real sites (60/192 vs 62/164 for the same genus), and the run
  proceeded cleanly through the rest of Section 3 to the expected Section 4 interactive
  wall (`review_spatial_flags()`), with no other bugs surfacing in the fully
  headless-reachable portion.
- Section 5: replaced the single `group_centroids` (one averaged row per
  `spatial_group_id`) with `prior_units` -- one row per group for real multi-member
  clusters (unchanged, averaged centroid), but one row **per site** for single-observation
  groups (both ordinary singletons and multi-site singletons), using each site's own real
  coordinates directly. `site_for_join` is built to match: multi-member cluster members
  still get one row each; single-observation groups' rows are joined by
  `(spatial_group_id, .site_row)`, so a genuine multi-site observation naturally produces
  multiple `site_for_join` rows -- the exact shape `join_priors()`'s multi-site path (and
  `combine_multisite_priors()`) expect. Verified via an isolated logic test against the
  real `site_table.rds` checkpoint (mocking the actual `TaxaExpect` model calls, since
  Section 4's wall blocks reaching Section 5 in a headless run): `ASV_2` correctly produced
  2 distinct `(grid_id, main_habitat)` rows with genuinely different resolved grid cells;
  `ASV_1`/`ASV_3` (ordinary singletons) were unaffected (1 row each).

**Not yet done:** the user hasn't finished the live RStudio run past Section 4 as of this
prompt being written -- confirm current status before assuming Sections 5-8 work correctly
against real (not mocked) `TaxaExpect`/`TaxaAssign` calls. This fix is **uncommitted** as
of this writing (check `git status` -- only `inst/TaxaID_Workflow_Template_TEST.R` was
modified, nothing else changed since the Session 138 commit).

---

## The GBIF fetch efficiency question (this prompt's actual subject)

### Current state (as of the Section 3/5 fix above)

Every site (whether a real multi-member cluster's pooled centroid, or an individual site
of a singleton/multi-site observation) gets its own independent `get_gbif_occurrences()`
call:
- Multi-member clusters: ONE pooled call across the cluster's own combined candidate
  families, over one interactively-drawn polygon. Already efficient, unchanged by this
  discussion.
- Singletons (including each site of a multi-site observation): ONE call **per (site,
  candidate genus)** pair, each with its own small `SINGLETON_RADIUS_DEG` bbox. No
  combination across sites or observations at all.

### Two real problems checked and confirmed, not assumed

1. **No occurrence-record deduplication anywhere.** Checked directly:
   `TaxaFetch::get_gbif_occurrences()`, `filter_gbif_quality()`, `stack_occurrences()` --
   none dedupe by `gbifID`. If two separately-issued queries have overlapping search
   geometry (confirmed to actually happen in this template's own bundled data -- see
   below), the same GBIF record can be counted twice when results are pooled for model
   training, a real (if likely small) statistical distortion.
2. **The bundled test case is already in the overlap regime.** Checked directly with real
   coordinates: `ASV_2`'s two sites (34.40/-120.41 and 34.47/-120.36, ~9km apart) each get
   a `make_bbox_wkt(radius_deg = 0.05)` box, and `sf::st_intersects()` confirms these two
   boxes genuinely overlap (~15% of either box's area). So this isn't a hypothetical --
   the live Phase 6 run is hitting exactly this scenario right now.

### What GBIF's API actually supports (checked, not assumed)

Checked `rgbif::occ_data()`'s own bundled docs directly (`tools::Rd_db("rgbif")`):
- **`MULTIPOLYGON` is supported** as a `geometry` value, with a real example showing two
  genuinely disjoint boxes in one WKT string. This means a single query can cover several
  site-boxes at once, whether they overlap, are adjacent, or are far apart --
  `sf::st_union()` on a set of boxes does the right thing automatically: overlapping/
  touching boxes get merged into one bigger polygon (removing the duplicate-record risk
  at the source, not just downstream), while disjoint (far-apart) boxes stay as separate
  pieces within the same `MULTIPOLYGON` collection -- no "convex hull balloons over empty
  space between distant sites" problem, since `MULTIPOLYGON` isn't a convex hull.
- **A real, uncharacterized WKT-complexity ceiling exists.** `rgbif::occ_data()` ships a
  `geom_big`/`geom_size`/`geom_n` escape valve (auto-simplifies an overly complex/large
  geometry into a grid of bounding-box cells) -- this only exists because sufficiently
  complex WKT can fail against GBIF's actual API. The exact numeric limit was NOT pinned
  down this session (searched `rgbif`'s bundled docs; found the escape-valve params but
  not an explicit "N points" or "N characters" ceiling stated anywhere accessible without
  live-testing or checking GBIF's own API docs directly). `TaxaFetch::fetch_gbif_occurrences()`
  does not currently expose or use this escape valve at all -- passes `geometry` straight
  through to `occ_data()`'s default (`geom_big = "asis"`).
- **`GBIF_LIMIT` (the per-key record cap) interacts with combining queries.** A combined
  query covering more area or more taxa can return more total matching records than any
  one of the original separate queries would have -- if that exceeds the configured limit,
  results get silently truncated in a way the smaller separate queries wouldn't have hit.
  Not investigated further this session; a real thing to watch in any redesign.

### The case-by-case efficiency analysis (worked through with the user, confirmed correct)

Given two candidate searches, each defined by `(taxon_key_set, geometry)`:

| Case | Taxa | Geometry | Best choice | Why |
|---|---|---|---|---|
| 1 | different | disjoint | **usually separate** (not an absolute rule) | Combining returns each taxon's records in the *other* search's area too -- genuinely wasted/irrelevant matches that must be filtered back out. But combining still saves a round trip, so the right call depends on the actual cost tradeoff (wasted download volume vs. per-call rate-limit/latency overhead), not a fixed rule. |
| 2 | different | same | **combined, clean win** | Zero wasted area either way (same geometry) -- combining only removes a redundant round trip. |
| 3 | same | different | **combined, clean win, better than it looks** | Combining returns exactly the union of what the separate calls would return. If the two geometries happen to overlap, combining *also* eliminates the duplicate-record risk entirely (evaluated as one spatial+taxonomic predicate, not two result sets later concatenated). |
| 4 | partial overlap | adjacent/overlapping | **resolved by reframing, not a bespoke rule** | See below -- this "ambiguous" case dissolves once the fetch loop is organized around taxon keys instead of observations/sites. |

### The key design insight (this is the actual recommendation)

**Stop grouping the fetch loop by observation/site. Group it by taxon key instead.** For
each candidate taxon key needed anywhere in the current fetch scope, take the union
(`sf::st_union()`) of only the site geometries where that taxon is actually a genuine
candidate, and issue exactly one query per taxon over that unioned geometry. Every
resulting query is then automatically shaped like Case 2 or Case 3 above (same taxon,
whatever combined geometry it needs) -- it can never accidentally become Case 1's
wasteful shape, because a given taxon's query is never scoped to include a site that
doesn't actually want that taxon. This is what dissolves Case 4: no "recognize overlap
and decide" heuristic is needed as a separate step: it falls out for free once the loop
is keyed on taxon rather than site.

Done fully, this would **unify Section 3's current two branches** (multi-member cluster
pooled fetch vs. per-observation singleton escalation fetch) into one coherent algorithm:
build a `taxon_key -> unioned geometry` map across the whole fetch scope (spanning
cluster members and singletons/multi-site sites alike), then fetch once per taxon key.
Prediction stays exactly as it is today (per-site, via `TaxaExpect::generate_full_priors()`
resolved at each site's own grid cell) -- this only touches the fetch step, not modeling
or prediction, which are already correctly separated (model training is already one
global `glmmTMB` fit over whatever got fetched; per-site prediction is what the Section
3/5 fix above just made correct).

### A necessary prerequisite: separate box-definition from searching (added same session, during grouping-applet redesign work)

While redesigning the spatial-grouping applet (`TaxaMatch::group_observations_by_bbox()`/
`TaxaTools::define_search_polygon()` -- see those packages' own Session 139 notes for what
changed there), the user pointed out a structural blocker for the taxon-centric design
above: **Section 3's current loop interleaves box-definition and searching for each group
one at a time** (`for` each `spatial_group_id`: draw its box, then immediately fetch for
it, then move to the next group and repeat). That interleaving makes the taxon-centric
union impossible to implement as described -- you can't union group A's and group C's
search geometry for a shared candidate taxon if group C's box hasn't been drawn yet when
group A's fetch runs.

**The fix this implies (not yet built): split Section 3 into two passes.**
1. **Pass 1 -- define geometry only, no fetching.** Loop over every multi-member
   `spatial_group_id` and interactively collect its search polygon (unchanged gadget
   interaction, now with per-group titles/button labels after the applet redesign --
   see below). Singleton/multi-site groups' bboxes are already non-interactive
   (`TaxaFetch::make_bbox_wkt()` + `SINGLETON_RADIUS_DEG`), so this pass just needs to
   also compute those without fetching yet. End of pass 1: every group in the batch has a
   known geometry, nothing has been searched.
2. **Pass 2 -- build the `taxon_key -> unioned geometry` map and fetch once per taxon.**
   Now that every group's geometry is known up front, this is exactly the taxon-centric
   design described above, with no further blocker.

This also directly fixes a rough edge hit live this session: cancelling a multi-member
group's search-area gadget (returns `NULL`) previously crashed several calls downstream
inside `get_gbif_occurrences()` with a confusing "geometry must be a single WKT string"
error, because nothing checked for `NULL` before using it (patched with a direct
`stop()` naming the group, in `inst/TaxaID_Workflow_Template_TEST.R`'s current
single-pass loop -- but a real two-pass split would make this cleaner still, since
pass 1 could just re-prompt or clearly abort the whole batch before any fetching starts,
rather than needing a per-iteration guard inside a loop that also fetches).

**Spatial-grouping applet redesign, done this session (context for whoever reads this
later):** three UI changes landed in `TaxaTools::define_search_polygon()` and
`TaxaMatch::group_observations_by_bbox()`/`.review_drawn_groups()`: (1) `title`/
`done_label`/`cancel_label` parameters (all backward-compatible defaults, matching the
old generic "Define Search Polygon"/"Done"/"Cancel") so a caller embedding the gadget in a
larger workflow can describe what clicking each button actually does in that context --
`group_observations_by_bbox()` now uses "Group These Points"/"No More Groups" with a
per-iteration title showing progress (`"Draw Spatial Group N (M observation(s) still
ungrouped)"`); (2) the initial zoom level is now one step further out than an exact fit,
since session experience showed the un-shrunk initial square's corners could be hard to
see/grab right at the edge of the visible frame; (3) Section 3's own direct
`define_search_polygon()` call (the multi-member fetch's search-area gadget) now shows
`"Define Search Area for <spatial_group_id> (<n> observation(s))"` in the title itself,
not just a console message. None of this touches the fetch-efficiency design above --
it's a usability layer on top of the same interaction model, done in the same session
because the user hit real confusion while testing the multi-scenario comparison (see
`TaxaMatch/CLAUDE.md`'s Session 139 note for the full record, including a real live bug
found this way: accepting the gadget's oversized starting box unshrunk merges everyone
into one cluster, which is expected/correct behavior but easy to trigger by accident).

### Recommended scope split (not yet decided which to do first)

1. **Narrow fix** (smaller, contained): union just one multi-site observation's own site
   geometries per candidate genus, inside the existing singleton branch. Directly fixes
   what Session 138/139's Phase 6 run is looking at; low risk; doesn't touch the
   cluster-vs-singleton branch structure.
2. **General fix** (bigger, more elegant, more testing surface): the taxon-key-centric
   regrouping described above, spanning the whole fetch scope (both branches unified).
   Real efficiency win at scale (many singleton observations, shared candidate genera
   across a study), but a genuine structural change to Section 3, more testing needed
   (WKT-complexity guard, `GBIF_LIMIT` interaction, and confirming the existing
   `.gbif_checkpoint_path()` resume-cache signature -- keyed on exact
   `keys + geometry + year_range + limit` -- still behaves sensibly when `geometry` is
   now a `MULTIPOLYGON` built dynamically per run).

The user has not yet chosen between these two scopes -- that's the first decision to make
when picking this back up. Given the general fix subsumes the narrow one entirely (and
resolves the ambiguous Case 4 for free), it may be worth just doing the general version
directly rather than building the narrow fix first and then redoing it -- but this
tradeoff (contained-and-quick vs. bigger-and-more-final) wasn't explicitly decided with
the user and shouldn't be assumed.

### Also worth doing regardless of the above

Add a cheap `distinct(gbifID)` (or equivalent) dedup step before occurrence records feed
into `model_data`/the spatial model, independent of whether the taxon-centric fetch
redesign happens. This is defense-in-depth: even a well-designed taxon-centric fetch could
still accumulate duplicates from unrelated pooling paths (e.g., the hardcoded
`additional_occurrences` demo row in the template, or genuinely coincidental overlaps
between separately-processed taxon keys). Currently, nothing dedupes at all -- confirmed
by reading `get_gbif_occurrences()`, `filter_gbif_quality()`, and `stack_occurrences()`
directly; none of the three do this.

---

## What to do when picking this back up

1. Check `git status` / recent commits first -- confirm whether the Section 3/5 fix above
   has been committed, and whether the user's live RStudio Phase 6 run completed
   successfully (Sections 4-8, including the real `TaxaExpect`/`TaxaAssign` calls this
   session could only verify via isolated logic tests, not a real end-to-end run).
2. Confirm with the user which scope (narrow vs. general, see above) to implement for the
   GBIF fetch efficiency work, and whether the `distinct(gbifID)` dedup step should land
   first/separately as a quick, low-risk fix regardless of that decision. Either scope
   needs the two-pass split (define all groups' geometry first, fetch second) described
   above as a prerequisite -- confirm that's understood and accepted before starting,
   since it's a real structural change to Section 3's current single-pass loop, not just
   an internal refactor of the fetch call itself.
3. If implementing the general taxon-centric fix: this likely belongs as a real
   `TaxaFetch`-level function (not ad hoc template code), given it's a generalizable
   capability (union geometries per taxon key, fetch once) rather than a
   `TaxaID_Workflow_Template_TEST.R`-specific pattern. Package placement not yet discussed
   with the user -- check for naming collisions first, per this repo's own standing
   practice (see `~/.claude/projects/-Users-lafferty/memory/feedback_naming_collision_check.md`).
4. Verify the actual GBIF WKT-complexity ceiling empirically (or find it in GBIF's live
   API docs) before assuming any particular cap on how many sites can be unioned into one
   query -- this session did not pin down a real number, only confirmed the escape valve
   (`geom_big`) exists in `rgbif` because the ceiling is real.

## Related reading, don't re-derive

- `ecosystem_docs/REENTRY_PROMPT_session138_multisite_posterior_combination.md` -- Phase 5
  (the `join_priors()`/`combine_multisite_priors()` work), now complete. Phase 6 (live
  testing) is what surfaced this prompt's Section 3/5 bug and the GBIF efficiency
  question.
- `TaxaAssign/CLAUDE.md`'s Session 138 note -- the precision-weighted logit combination
  design, upstream of (and unaffected by) everything in this prompt.
- `inst/TaxaID_Workflow_Template_TEST.R` -- Sections 3 and 5 are where the fix already
  landed; Section 0's config comment documents the `ASV_2`/`OQ846725` multi-site test
  case directly.
