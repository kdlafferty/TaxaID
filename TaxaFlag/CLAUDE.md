# CLAUDE.md -- TaxaFlag
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-09-04 (Opus 5, branch kernel-priors -- TWO defects that
# together deleted a Lamar-confirmed grass carp detection from GreatLakes, plus a
# review cache).
# (1) review_assignments() joined review results back to input rows by the DISPLAY
# label. That label (consensus_OTU) is ordered by POSTERIOR -- the ecosystem's
# convention, and what primary_taxon reads -- so one biological unit can carry
# "A/B" on one observation and "B/A" on another; as join keys those never match,
# leaving one unreviewed and NA. Now joins on the SORTED candidate set (taxa_sets
# is already sorted) and deduplicates canonically, so a unit that used to be
# reviewed twice under two labels is reviewed once -- one FEWER LLM call. Display
# labels are unchanged. The old comment at :400 asserted "canonical because sets
# are sorted"; it was not.
# (2) .build_taxa_block() renders an unresolved set as
# "- <label> (unresolved candidates; consensus rank: <rank>)" and the model echoes
# that WHOLE decorated string back as taxon_name. The batch reconciliation's
# .norm() -- added 2026-07-14 for exactly this, when a batch returned
# "Cottus (rank: Cottus aleuticus)" -- required the parenthetical to start with
# "rank:", so the unresolved form never normalised: every multi-candidate set was
# logged "LLM omitted N taxa", filled with NA, and then dropped in silence by the
# workflows' export filters. Singletons were unaffected (their "(rank: ...)" WAS
# handled), which is precisely why the loss masqueraded as "coarse ranks are
# excluded on purpose". 113 of 885 GreatLakes rows, every one a slash taxon.
# WATCH FOR: "LLM omitted N taxa. Filling with NA defaults" in a run log -- that
# message is the signal, and it was there all along.
# (3) NEW review_assignments(cache_dir=) + taxaflag_clear_cache(). The review is a
# JUDGEMENT and an uncached one is not reproducible: two GreatLakes runs 50 min
# apart disagreed about Pimephales vigilax ("possible" then "unlikely"), so it was
# in one species list and not the other. One .rds per taxon, keyed on everything
# that can move a verdict; the FULL key is stored in the file and verified on read
# so a hash collision is a miss, never another taxon's verdict. Deliberately the
# file-per-key shape TaxaTools::list_cache_files()/report_and_clear_cache() are
# built for, so it prunes like taxafetch_clear_cache()/taxalikely_clear_cache()
# and does not accumulate. All five workflows pass a project-local cache_dir.
# devtools::test() 456/0, reinstalled. Verified on the real GreatLakes run:
# 72/72 cache hits, 0 LLM calls, verdicts byte-identical.
#
# Last updated: 2026-08-29 (Fable 5, branch undetected-evidence-mixture --
# add_posthoc_assessment() gains domestic_caveat_type (additive character column,
# NA unless domestic_prior_caveat fired): "no_local_records" (primary_plausibility
# "unprecedented" -- classic food/domestic-contamination reading) vs
# "local_records" ("unexpected" -- winner HAS real local records at an implausibly
# low modelled rate, so a genuine allochthonous cross-habitat detection is at
# least as plausible as food contamination; the real Sus scrofa PtCon case, 98
# terrestrial records + Marine collapse, and likely the Canis lupus beach
# dog/coyote calls). Implements the user rule "a food should only get a food
# label IF it has no reports in GBIF" as a relabel, not a silence -- the logical
# flag still fires for both classes. 3 new tests; devtools::test() 443/0,
# check() 0/0/0, reinstalled. Design context + open ceiling/habitat-bleed
# questions: ecosystem_docs/REENTRY_PROMPT_evidence_ceiling_and_habitat_bleed.md.)
# Previous update, 2026-08-28 (Fable 5, branch undetected-evidence-mixture -- NEW
# flag_watch_candidates() (R/flag_watch_candidates.R): the likelihood-side
# watch-list surveillance guarantee (mixture redesign D4, user verdict "make the
# flag report for sure"). With invasive priors calibrated down to honest small
# probabilities (w = 0.05), watch species rarely surface through the posterior --
# this flag fires from RAW match scores alone whenever a watch-list species ties
# or beats the consensus winner's own best match (margin param; winner-is-watch
# and no-watch-candidate cases handled; unreferenced/rank-expanded winners fall
# back to the best non-watch score). Purely informational, never edits consensus
# columns. Wired into GreatLakes2023_ConsensusWorkflow.R Step 8i.5. 5 new tests
# (test-flag_watch_candidates.R). devtools::test() 434/0 (up from 419), check()
# 0/0/0, reinstalled.
# Previous update, 2026-08-21 (Sonnet 5 -- compute_local_occurrence_distance() gains a new
# date_col param (character or NULL, default NULL -- fully backward compatible, all 24
# pre-existing tests pass unchanged with no behavior change). When supplied and present in
# occurrence_data, surfaces the matched nearest record's raw date/year value as a new
# nearest_date output column (no parsing/normalization -- whatever type the source column
# already was, e.g. GBIF's own numeric "year"). Built for
# TaxaExpect::generate_regional_proximity_evidence() (new this session, in the parallel
# design thread ecosystem_docs/REENTRY_PROMPT_regional_proximity_prior_check.md), which
# needs a nearby record's age to size how tightly its evidence should be held (an old
# record could reflect a real unresurveyed population or a genuinely contracted range --
# occurrence data alone can't tell, so age widens/narrows confidence rather than shifting
# the distance-driven mean). A `date_col` naming a column absent from `occurrence_data` is
# silently ignored (no `nearest_date` column at all), matching this function's own
# established "silent no-op on an unavailable optional signal" convention. 4 new tests.
# `devtools::test()` 419/419 (up from 415), `devtools::check()` 0/0/0. Reinstalled to
# `~/Library/R/4.0/library`. See TaxaExpect/CLAUDE.md's and TaxaID/CLAUDE.md's own top
# session notes for the full cross-package record, including a real live-GBIF verification
# against the exact three GreatLakes2023 species that originally motivated this thread.
# Previous update, 2026-08-11 (Sonnet 5 -- closes out the 2026-08-07 review pass: that session
# fixed 2 items (df->input_df rename, a broken build_review_covariates.R \link{}) but never
# produced inst/taxaflag_review_response.md or worked through the remaining file-specific
# comments across all 10 reviewed files -- this session does both. Real fixes, not just
# documentation: (1) TaxaFlag-package.R was missing 5 of 9 exported functions from its own
# package index (add_posthoc_assessment/build_review_covariates/check_gbif_tile_range/
# compute_local_occurrence_distance/review_spatial_context) -- the same discoverability gap
# class TaxaMatch's own review found; two new sections added. (2) add_posthoc_assessment.R's
# `utils::globalVariables(character(0))` removed -- the file has no NSE references at all,
# violating this ecosystem's own documented convention to omit the call entirely in that
# case. (3) check_gbif_tile_range.R's `.fetch_gbif_tile_alpha()` hard-indexed `img[, , 4]`
# (the alpha channel) with no guard; added a defensive dimension check with a clear error
# instead of an opaque "subscript out of bounds" if GBIF's tile format ever changes.
# (4) review_assignments.R gains real functionality: an `attr(result, "llm_prompts")`
# (environment-based accumulator, survives rbind()/retry-recursion, named by batch label)
# directly answering the review's "it would be useful for the user to see the prompts";
# `.normalise_context()` now warns on a multi-row `context` instead of silently discarding
# every row but the first; `make_default()` gained an optional `names` arg, closing a real
# ~15-line duplication with the "LLM omitted these taxa" fallback path; `.safe_col()` now
# takes its source data frame as an explicit argument instead of reading `parsed` via
# lexical closure; `llm_fn`'s own roxygen now points directly at the
# `.resolve_llm_fn()`-silently-degrades footgun already documented ecosystem-wide in
# TaxaID/CLAUDE.md but previously missing from this specific function's own docs, despite
# being one of the five affected call sites named there. (5) flag_contaminant.R's final
# `result <- data.frame(...)` block, which manually re-listed and re-typed every one of
# `.compute_contaminant_scores()`'s output columns by hand, now selects directly out of
# `scores` instead -- removes a real sync-by-hand risk. (6) Four non-runnable `\dontrun{}`-
# only examples (`compute_local_occurrence_distance.R`, `flag_contaminant.R`,
# `flag_handler.R`, `report_flags.R`) now have a small synthetic-data runnable example each,
# verified via R CMD check's own example execution. (7) `flag_handler()`'s
# `interval_minutes`/reason-string interaction the review flagged as possibly backwards
# ("15.0 min from nearest edge; outside 30-min interval") was live-tested directly against
# the current, installed function and found already correct ("within 30-min interval") --
# the reviewer's report doesn't reproduce against current code, most likely predating the
# file's several subsequent rewrites (2026-07-24 unified-validity-schema rename, Session 151
# edge-anchoring redesign). Also verified live (not just re-read): `.dilate8()`'s "only
# replaces the FALSE in the lower right corner" observation is expected 8-connected dilation
# behaviour, confirmed by direct execution, not a bug -- a clarifying comment + roxygen note
# added either way. Several review comments recur across many files ("suggest requiring
# specific column names") and are answered once, as a documented package-wide (in fact
# ecosystem-wide) design convention, in the response doc rather than per file. Full
# file-by-file record in inst/taxaflag_review_response.md, following this ecosystem's
# established TaxaMatch/TaxaLikely/TaxaFetch/TaxaAssign/TaxaHabitat review-response format.
# `devtools::test()` 415/415 (0 failures, 5 pre-existing `expect_warning()` warnings,
# unchanged), `devtools::check()` 0 errors/0 warnings/0 notes, reinstalled and verified at
# ~/Library/R/4.0/library.
# Previous update, 2026-08-07, continued once more (Sonnet 5 -- first full TaxaFlag code +
# domain review against inst/Code and Domain Review 2.Rmd, findings + fixes in one pass,
# recorded in new inst/taxaflag_review.Rmd (matches TaxaFetch/TaxaLikely/TaxaMatch's own
# combined-review convention). Two real bugs fixed: (1) flag_handler()'s internal
# merge(df, group_edges, by=".tmp_group", all.x=TRUE) used base R's default sort=TRUE,
# silently re-sorting the OUTPUT row order by group whenever group_col groups appeared in
# the input in non-alphabetical order -- contradicts the function's own documented "input
# data frame with columns appended" contract, and every pre-existing test's fixture
# happened to already be group-sorted so this was never caught. Fixed with the same
# .row_id-then-resort pattern review_assignments()'s own .join_key merge already uses; new
# regression test constructs an out-of-order-group fixture specifically to catch it.
# (2) build_review_covariates.R's roxygen referenced \code{\link{model_review_classification}}
# twice -- no such function exists anywhere in the package, and this was the real cause of
# the "1 pre-existing unrelated warning+note in build_review_covariates.R" this file's own
# session notes had carried, unresolved, for many sessions; fixed by rewording to plain
# prose. Also: `df` (shadows stats::df()) renamed to `input_df` in flag_contaminant(),
# flag_handler(), review_assignments(), review_spatial_context(), and their internal
# helpers -- the last package in the ecosystem still carrying this exact pattern
# (TaxaTools/TaxaHabitat already fixed their own df/data collisions in earlier reviews).
# Propagated to every real call site found via a full ~/My Drive/Rscripts grep, not just
# this package: TaxaFlag's own tests/inst/vignette, TaxaWizard's two consensus_to_flagged/
# consensus_to_reviewed.R snippets + metadata/TaxaFlag.json, TaxaID/inst/
# TaxaID_Workflow_Template_TEST.R, and all 6 real external eDNA production workflow
# scripts (PtConception x4, SepulvedaMugu x2, outside this monorepo, not under git --
# backed up first as *.bak_pre_input_df_rename). DESCRIPTION also gained a missing
# `Depends: R (>= 4.1.0)` (3 files use the native pipe; confirmed via devtools::build()'s
# own dependency-detection message, matching TaxaHabitat/TaxaLikely/TaxaTools's identical
# fix). New test-build_review_covariates.R (22 expectations) closes the one exported
# function in the package that had zero test coverage before this session -- every
# expected value in it was checked against the function's real live output before being
# written into an assertion. `devtools::test()` 415/415 (up from 382), `devtools::check()`
# 0 errors/0 warnings/0 notes (the long-standing warning is gone). Reinstalled, verified
# at ~/Library/R/4.0/library. Real production impact: any external caller using named
# `df = ...` against these four functions needs `input_df = ...` now -- see TaxaID/
# CLAUDE.md's Recent Breaking Changes table.
# Previous update, 2026-08-07, closing out the review_spatial_context() thread with a
# dedicated test-coverage pass (Sonnet 5). Prompted by the user asking to make sure all
# docs/tests were properly written up after confirming the fourth click-through round's
# fixes worked -- audited what had accumulated purely as inline logic inside the gadget's
# reactive/render closures across nine rounds and was therefore only ever exercised
# implicitly through the full `shiny::testServer()` machinery, never directly. Two pieces
# of real, non-trivial logic extracted into standalone `@noRd` functions specifically so
# they're independently unit-testable: `.gbif_tile_url(taxon_key, style, bin_size,
# year_range)` (the `.point`->`.poly` auto-upgrade + `bin=square`/`squareSize` + Heat-family
# exclusion logic from the GBIF tile layer) and `.gbif_legend_swatch(style)` (the real,
# sampled per-style legend gradient lookup). Both were previously local variables computed
# inline where they were used -- functionally identical behavior, but no way to assert on
# them directly, which is exactly the shape of bug that shipped twice in this thread (a
# real value computed correctly once, then not actually wired to -- or not actually
# re-checked against -- the place a real user's own parameters would reach it). 15 new
# tests added: 5 for `.gbif_tile_url()` (point->poly upgrade, already-.poly passthrough,
# Heat-family exclusion, bin_size=NULL no-op, year_range query), 3 for
# `.gbif_legend_swatch()` (classic .point/.poly parity, purpleHeat's real distinct colors,
# unverified-style gray fallback), 2 for `.fetch_inat_points()` (mocked at
# `httr2::req_perform`, matching this file's own established mocking convention -- real-
# shaped geojson.coordinates extraction, and the empty-results 0-row case), plus the
# existing gadget-level tests already covering the reactive wiring end to end.
# `devtools::test()` 382/382 (up from 360), `devtools::check()` 0 errors/0 notes (1
# pre-existing unrelated warning+note in `build_review_covariates.R`, untouched).
# Reinstalled. Pure refactor + additive tests -- no behavioral change to the gadget itself.
# See [[project_gbif_tile_spatial_review_functions]] for the full nine-round record this
# closes out.
# Previous update, 2026-08-07, fourth round of real click-through feedback (Sonnet 5 --
# review_spatial_context()). Two items. (1) **iNat clustering reverted.** The third round's
# marker clustering + radius bump (2->3) was rolled back completely per direct user
# feedback ("The iNat points were fine before") -- back to plain, unclustered
# `radius=2, color="#16a34a"` circleMarkers with no `clusterOptions`, matching the state
# confirmed good in an earlier round. The `inat_radius_km` param, the dashed search-radius
# circle, and the legend text showing the actual radius (all from the third round) were
# kept -- those were separately confirmed correct, this revert is scoped to clustering/size
# only. (2) **GBIF tiles still too small -- fixed with a verified, correct display-size
# lever this time, explicitly NOT clustering (the user ruled that out directly, and it
# wouldn't apply anyway -- GBIF is a raster tile, not point markers).** Investigated the
# display-size question left open since the original tileSize regression: does forcing
# GBIF's real 512x512 @1x.png image into Leaflet's default 256 CSS-px tile slot actually
# shrink it? Answer: yes, genuinely -- and the fix is Leaflet's own purpose-built lever for
# exactly this shape of provider (`tileOptions(tileSize=512, zoomOffset=-1)`, the standard
# "retina tile" recipe), paired correctly this time rather than applied bare. Verified LIVE
# before shipping, specifically because a prior round's superficially similar bare-tileSize
# change caused a real regression and this thread's own hard lesson is "verify, don't
# repeat a reasoning mistake": built a standalone (non-Shiny) leaflet HTML page, served over
# a local `python3 -m http.server` (Chrome blocks `file://` navigation via the extension),
# with the paired option set alongside the current no-override rendering, side by side --
# screenshotted both via real Chrome browser automation at the gadget's actual initial zoom
# (7) and again after zooming in twice more. Confirmed: visibly ~2x larger squares in both
# dimensions, correctly positioned (same real GreatLakes coordinates/species, Chicago/
# Detroit-area clusters land in the identical real locations), zero tile gaps, zero
# basemap misalignment, zero console errors at either zoom level. Shipped to the GBIF tile
# layer's own `addTiles()` call only -- no other layer touched. `devtools::test()` 360/360
# unchanged, `devtools::check()` 0 errors/0 notes (1 pre-existing unrelated warning+note),
# reinstalled. See `TaxaID/CLAUDE.md`'s "Known R Footguns" tileSize entry (updated with this
# verified-correct paired usage) and [[project_gbif_tile_spatial_review_functions]] for the
# full record.
# Previous update, 2026-08-07, third round of real click-through feedback (Sonnet 5 --
# review_spatial_context()). Study Site marker fix confirmed correct. Three more real
# issues, all fixed with the same "verify, don't guess" discipline as every prior round:
# 1. **GBIF legend color STILL wrong for the user's actual config.** The second round's
# fix hardcoded the "classic" ramp's real sampled colors -- correct for THAT style, but the
# user's own call passes gbif_style="purpleHeat.point", and the legend kept showing
# classic's yellow/orange/red regardless, because the swatch never actually read
# gbif_style at all. Rebuilt as a real lookup keyed on the configured style (stripped of
# its .point/.poly suffix, since binning never changes color family): sampled live purple
# Heat/green Heat/blue Heat/orange Heat tiles the same way classic was sampled last round
# (dense world tile, to see each ramp's true top end) -- purpleHeat genuinely renders
# black -> purple -> magenta -> pink, confirming the user's own "black to yellow" mismatch
# report was about MY swatch being wrong, not GBIF's real rendering being wrong. Any style
# outside this now-5-style verified set falls back to a neutral gray swatch labeled "colors
# unverified for this style" rather than another guess.
# 2. **iNat search radius has no visual boundary.** A taxon with zero visible points within
# the (now 500km) search radius reads identically to "no iNat data exists at all" --
# flagged by the user as a real risk of misreading absence-within-radius as absence-
# entirely. Fixed two ways at once, per the user's own "OR" framing taken as "do both":
# new `inat_radius_km` param (default 500, threaded through all three function layers same
# as gbif_bin_size) now drives BOTH a dashed `leaflet::addCircles()` boundary on the map
# (grouped with the points layer, so toggling one toggles both) AND the legend text itself
# ("iNaturalist observation (dashed circle = 500 km search radius)") -- the actual km value
# is read from the same variable driving the real fetch, so the two can't drift apart.
# 3. **iNat points barely visible when zoomed in, worse since they don't cluster.** A
# fixed-screen-pixel circleMarker (radius=2/3) never grows as you zoom in the way a raster
# tile's own image pixels do, and points that visually overlapped at low zoom spread apart
# and stop reading as a group once zoomed in -- exactly the user's own diagnosis. Fixed
# with `clusterOptions = leaflet::markerClusterOptions()` on the iNat circleMarkers layer
# (confirmed live: Leaflet's bundled clustering plugin is natively supported by
# `leaflet::addCircleMarkers()`, no extra R dependency) -- nearby points now group into a
# numbered badge at low zoom and split apart progressively while zooming in, rather than
# rendering as isolated barely-visible dots throughout. Marker radius also bumped 2 -> 3 as
# a modest additional margin (kept-occurrence points, confirmed "just right" by the user
# two rounds ago, are untouched at radius=2 -- this only affects iNat's own layer, which
# serves a different wide-context purpose).
# `devtools::test()` 360/360 unchanged, `devtools::check()` 0 errors/0 notes (1
# pre-existing unrelated warning+note), reinstalled. Legend gradient lookup and
# `clusterOptions`/`addCircles` construction both live-verified against the real installed
# `leaflet` package before considering this done. See
# [[project_gbif_tile_spatial_review_functions]] for the full record.
# Previous update, 2026-08-07, second round of real click-through feedback on the very same
# fixes just shipped (Sonnet 5 -- review_spatial_context()). Legend/toggles now show
# (structurally working), but 4 more real problems: GBIF legend swatch color wrong, Study
# Site legend swatch didn't match the actual map marker, iNat points newly confined to a
# small region (a real regression from switching off the raster tile), and GBIF tiles
# "not particularly more visible" despite the prior round's bin=square fix. All four
# re-verified against real data rather than patched blind a second time:
# 1. **GBIF legend color wrong.** The prior round's gradient (ffffb2->fd8d3c->bd0026) was a
# guessed ColorBrewer-style ramp, never actually sampled from a real tile. Fetched real
# GBIF "classic" tiles (both a sparse local one and a deliberately dense world tile, to see
# the ramp's true top end) and read back the actual non-transparent pixel RGB values: real
# stops are pure yellow (255,255,0) -> orange (255,152,0) -> dark red (213,10,0), notably
# more vivid/saturated than the guessed pale-yellow start. Legend gradient corrected to
# #ffff00/#ff9800/#d50a00.
# 2. **Study Site marker mismatch.** The prior round's legend used a generic pin emoji
# (unicode U+1F4CD); the actual map marker is `leaflet::addMarkers()`'s own default blue
# teardrop icon, a specific bundled PNG, not something an emoji can approximate. Fixed by
# embedding that EXACT file (`system.file("htmlwidgets/lib/leaflet/images/marker-icon.png",
# package="leaflet")`) as a base64 data URI, generated at runtime (not hardcoded) so it can
# never drift from whatever leaflet version is actually installed -- guaranteed
# pixel-identical to the real marker rather than an approximation of it.
# 3. **iNat points confined to a small region -- a real regression, root-caused, not
# guessed at.** The raster tile layer this replaced last round always covered the FULL
# visible map (it rendered GBIF-style world density, not a distance-limited search), so
# switching to real individual points fetched with a hardcoded 50km search radius
# (fetch_inat_occurrences()'s own default, copied without re-deriving it for this very
# different use case) was a genuine narrowing, not a perceived one. Fixed by raising
# .fetch_inat_points()'s default radius_km 50 -> 500; confirmed live the results genuinely
# spread across a wide real area at 500km (Iowa/Indiana/Ontario/Wisconsin for a real
# Chicago-area test point, not clustered near center), since iNat's own default sort is
# most-recent-first, not nearest-first.
# 4. **GBIF tiles still not noticeably bigger.** The prior round's default
# (gbif_bin_size=64) was chosen from measurements against a maximally COMMON species (house
# sparrow, present literally everywhere) -- the wrong reference case for a tool whose real
# job is reviewing SPARSE "unprecedented" species. Re-measured against this thread's own
# real sparse GreatLakes species (Lepomis peltastes, Neogobius melanostomus) at the exact
# real study-site tile (zoom 7, x=33, y=47 for the GreatLakes2023 coordinates): raw
# .point pixels covered under 0.1% there; squareSize=64 only reached ~1-2.5%, visually
# indistinguishable from unbinned dots on a full map pane -- explaining exactly why the
# user "didn't notice a difference." Default raised to 256L, which reaches ~10-15%
# coverage for those same real sparse species (a ~60-140x increase over raw pixels) while
# the maximally-common reference species only reaches ~26% (still not a solid blob).
# `devtools::test()` 360/360 unchanged (styling/data-source changes only, no new reactive
# branches or signature params needing test-site updates this round), `devtools::check()`
# 0 errors/0 notes (1 pre-existing unrelated warning+note). Reinstalled; the marker data
# URI and the 500km radius bump were both live-verified against the real installed package
# before considering this done (200 real points now spanning ~6.6 degrees latitude / ~10
# degrees longitude, vs. a tight cluster before). See
# [[project_gbif_tile_spatial_review_functions]] for the full record.
# Previous update, 2026-08-07, the FIRST real RStudio click-through, 4 concrete points
# (Sonnet 5 -- review_spatial_context()). The user's assessment: occurrence points are
# "just right" (unchanged), iNat markers too large, GBIF tiles still too small even after
# the zoom-7/bin-size work, no legend, and no toggle switches. Each fix verified live
# against the real APIs before shipping, not guessed:
# 1. **iNat markers too large, no fix via the tile API.** Directly probed
# api.inaturalist.org/v1/points/{z}/{x}/{y}.png with every plausible size param name
# (marker-width/width/radius/dot-radius/size) against a real taxon -- all six produced
# BYTE-IDENTICAL output to a bare request, while `color` measurably changed it, confirming
# the endpoint has no working size control at all (undocumented too -- the
# Windshaft-inaturalist wrapper repo's own real params list is x/y/z/taxon_id/user_id/
# place_id/project_id/color/opacity/border_opacity/ttl, nothing size-related). Replaced the
# raster tile layer entirely with real individual point markers: new internal
# `.fetch_inat_points()` hits the same `/v1/observations` search endpoint
# `TaxaFetch::fetch_inat_occurrences()` already counts against (confirmed live this
# specific public read query needs no Authorization header, so no TaxaFetch dependency
# needed), extracts each result's real `geojson.coordinates`, and draws them with
# `leaflet::addCircleMarkers()` sized to match the gadget's own "just right" occurrence-
# point convention exactly (radius=2) instead of a fixed, uncontrollable server-side dot.
# Capped at `per_page=200` (iNat's real server-side max, confirmed live: requesting 201
# silently returns 200) -- one page, matching this gadget's "cheap context" scope.
# 2. **GBIF tiles still too small.** Root cause this time: `bin=square`/`squareSize`
# binning params (which aggregate raw single-pixel dots into visibly larger squares) are
# silently NO-OPS on any `.point`-suffixed style -- confirmed live, byte-identical response
# with/without them -- and only take effect once the style is switched to its `.poly`
# counterpart. New `gbif_bin_size` param (default `64L`, `NULL` disables) auto-upgrades a
# bare `.point` style to `.poly` and appends the bin params; Heat-family styles (no `.poly`
# counterpart) are left unbinned. Chosen from a real measured sweep across
# squareSize in {16,32,64,128} at zoom 7 for a densely-covering species: 64 gives ~13.6%
# visible tile coverage (~36x the raw `.point` style's ~0.4%) without 128's near-solid-blob
# look. Also confirmed live: pairing a `.poly` style with NO bin params (the naive first
# idea) can render a completely EMPTY tile at a real zoom/species combo -- never applied
# unbinned.
# 3. **Legend added.** Static HTML `leaflet::addControl()` (bottomright, built once,
# doesn't depend on the selected taxon) explaining all 4 toggleable overlays plus the
# always-present study-site marker.
# 4. **Toggle switches re-added.** `leaflet::addLayersControl()` -- removed in an earlier
# round alongside the tileSize regression on the theory its own JS behavior couldn't be
# verified without a browser; now that a real click-through exists and the actual root
# cause of that regression was confirmed to be the tileSize bug (not addLayersControl
# itself), it's back. Re-issued inside `observeEvent(input$taxon)` AFTER the groups are
# rebuilt each time (not once at initial render, when the groups don't exist yet) --
# leaflet's R htmlwidget resolves `overlayGroups` against whatever layers currently carry
# that group name; a repeat call with the same names updates the control in place rather
# than stacking duplicates.
# `devtools::test()` 360/360 unchanged (styling/rendering changes, no new reactive logic
# needing new test coverage beyond the existing `.build_spatial_context_server()` call
# sites, which needed `gbif_bin_size` threaded through the same way `live_inat_check`/
# `inat_cache_dir` did last round), `devtools::check()` 0 errors/0 notes (1 pre-existing
# unrelated warning+note in `build_review_covariates.R`). Reinstalled, `.fetch_inat_points()`
# live-verified against the real installed package (200 real Chicago-area house-sparrow
# points returned). This is genuinely the first round grounded in the user's own real
# browser session rather than `shiny::testServer()`/API-only verification -- see
# [[project_gbif_tile_spatial_review_functions]] for the full record.
# Previous update, 2026-08-07, closing the persistent "no iNat data" gap (Sonnet 5 --
# review_spatial_context() gains an opt-in `live_inat_check`/`inat_cache_dir` fallback in
# its `inat_row()` reactive: when a taxon has no row in the caller-supplied `inat_range`
# (or none was supplied at all), and `live_inat_check` (default TRUE) is enabled and
# `TaxaFetch` is installed, it now calls `TaxaFetch::check_inat_range()` live for just that
# one taxon before giving up. Prompted by the user reporting the same "iNat: no data"
# message across THREE different real taxa (`Salmo trutta`, `Perca flavescens`) spanning
# both "unexpected" and "expected" plausibility tiers -- verified directly against real
# data (not re-guessed) that both taxa are genuinely absent from the real `inat_range.rds`,
# and that `check_inat_range()`'s real scoping only ever covers a pipeline's own
# "unprecedented"-tier undetected-diversity candidate pool, structurally excluding most of
# a real consensus table. This is a coverage workaround, not a fix to the separate,
# still-open `check_inat_range()` name-mismatch bug
# ([[project_inat_range_backbone_mismatch_todo]]) -- a live call can still resolve to the
# wrong species via iNat's own fuzzy matching, same as the static path already could.
# `output$stats_panel`'s iNat message block reworked to match: gates on
# `!is.null(inat_range) || isTRUE(live_inat_check)` instead of only the static
# `inat_range`, and no longer claims "not in the supplied inat_range" when a live check may
# also have run -- surfaces the real `range_status` (e.g. `"taxon_not_found"`/
# `"no_polygon"`) when a check (static or live) genuinely found nothing, distinguishing
# "checked, empty" from "never checked." `TaxaFetch` added to `DESCRIPTION`'s `Suggests`
# (checked lazily via `requireNamespace()`, not required). A real, pre-existing test-suite
# gap was found running the full suite after this change: `.build_spatial_context_server()`
# already required `live_inat_check`/`inat_cache_dir` as REQUIRED params (no default) from
# this same round's own signature threading, but the test file's `.make_server()` helper
# and two standalone direct calls hadn't been updated to pass them -- this didn't error at
# construction (lazy R argument evaluation), only once `inat_row()` actually ran, so it
# surfaced as an opaque "output$ai_panel encountered an unexpected error resolving its
# promise" deep in a `shiny::testServer()` backtrace rather than a clear missing-argument
# message. Fixed by adding both params to `.make_server()` (default `live_inat_check =
# FALSE`, keeping existing tests network-call-free) and both standalone call sites; two new
# tests added (`local_mocked_bindings(check_inat_range = ..., .package = "TaxaFetch")`)
# confirming the live fallback fires when enabled and taxon-absent, and confirming it's
# never called when `live_inat_check = FALSE`. `devtools::test()` 360/360 (up from 356),
# `devtools::check()` 0 errors/0 notes (1 pre-existing unrelated warning+note in
# `build_review_covariates.R`, untouched). Reinstalled. Still not done: the user's own live
# RStudio click-through confirming the live fallback actually renders correctly in a real
# browser session -- every round of this thread so far has been verified via
# `shiny::testServer()`/direct API calls/source reading, never a real click-through by me.
# See [[project_gbif_tile_spatial_review_functions]] for the full record.
# Previous update, 2026-08-07, a real regression found and fixed (Sonnet 5 --
# review_spatial_context()'s previous session's `tileOptions(tileSize = 512)` "fix" was
# ITSELF a genuine bug, not a display tweak gone slightly wrong -- confirmed by reading
# the actual bundled Leaflet.js source (installed at
# leaflet/htmlwidgets/lib/leaflet/leaflet.js) rather than trusting the earlier reasoning:
# `getPixelWorldBounds()` (the MAP's shared world-pixel bounds at a given zoom) is derived
# purely from the map's CRS, independent of any one layer; `_pxBoundsToTileRange()` then
# divides those SAME shared bounds by `this.getTileSize()` -- EACH LAYER's OWN tileSize --
# to compute that layer's tile x/y indices. Two layers at the identical zoom with
# different tileSize therefore request DIFFERENT x/y indices from the identical
# viewport -- GBIF's server-side tile addressing uses the standard 256px-tile-grid
# convention regardless of what pixel resolution its response images actually are, so
# tileSize=512 desynced the requested indices from what GBIF's real addressing expects.
# This is the confirmed, verified cause of the user's real regression: tiles disappeared
# entirely, and the (also newly-added) leaflet::addLayersControl() checkbox didn't
# function correctly either. Fully reverted -- no tileOptions override anywhere now, on
# either the GBIF or the (equally affected) iNat tile layer -- and addLayersControl()/
# clearControls() removed entirely rather than debugged further, since its interactive
# JS behavior can't be verified without a real browser and the added complexity wasn't
# earning its keep. "Bigger-looking density" pursued via a genuinely safe lever instead:
# raised the map's initial zoom 5 -> 7, verified with real check_gbif_tile_range() numbers
# (not assumed) that GBIF's own density-blob pixel footprint DOES grow with zoom up to a
# point (patch_size_px 21 -> 52 -> 95 across zoom 5/6/7 for a real test case) before
# fragmenting into isolated single pixels beyond zoom 7 -- 7 is the measured sweet spot.
# Also added an explicit sidebar note distinguishing "no iNat row at all for this taxon"
# from "row present but no taxon_id" (the map's iNat tile layer specifically needs
# taxon_id), so a taxon with real iNat text data but no map layer doesn't read as broken.
# devtools::test() 356/356 (unchanged from the prior round -- no test asserted on the now-
# removed layers control), devtools::check() 0 errors/0 notes. Reinstalled. Meta-lesson,
# recorded plainly: the FIRST attempt at the tileSize fix was reasoned from memory of how
# Leaflet's tileSize option works, without checking; it was wrong in a way that broke
# something that had been working. Went back and read the actual bundled source this time
# before re-fixing, rather than reasoning from memory a second time. Still the standing
# gap: four rounds of feedback now, all diagnosed via API-level verification, source
# reading, and testServer() -- still no real RStudio click-through confirmation by me
# directly. See [[project_gbif_tile_spatial_review_functions]] for the full record.
# Previous update, 2026-08-07, a third round of real click-through feedback (Sonnet 5 --
# review_spatial_context() again, four fixes, all grounded in direct verification against
# the real GBIF/iNaturalist APIs rather than guessed:
# (1) THE root cause of "GBIF pixels render too small": Leaflet defaults every tile layer
# to 256px unless told otherwise, but GBIF's own @1x.png tiles ARE 512x512 (confirmed
# directly against a real response) -- every GBIF tile was silently being shrunk to half
# its intended on-screen size. Fixed with `tileOptions(tileSize = 512)` on the addTiles()
# call -- a real, well-understood Leaflet mechanism for non-256px tile services (this is
# the standard way "retina"/custom-resolution tiles are integrated), not a workaround.
# Since GBIF's own @1x convention is already ~2x a standard 256px tile's density, this
# alone should roughly double the apparent size of every density pixel -- landing in the
# user's requested "2-3x larger" range without over-correcting via a resolution bump.
# (2) New `gbif_year_range` param (display-only, forwarded as GBIF's own `year` query
# param) -- verified live that it's a real, working filter (byte size of the same tile
# genuinely shrinks with a narrower year range), added to let a user align the visual tile
# layer with their own study's date-bounded fetch. Deliberately NOT threaded into
# check_gbif_tile_range()'s own numeric computation, which stays all-time/global by
# design -- that's the right question for "is this plausible anywhere, ever," and
# narrowing it risks a false beyond_buffer for a genuinely present species with no records
# in one particular window. This also explains a real user observation from this round:
# the density map shows far more points than a study's own year- and quality-filtered GBIF
# fetch, because it's intentionally the FULL, unfiltered, all-time global record by
# default, not a scoped-down comparison.
# (3) Genuinely new: an iNat observation-density tile LAYER, separate from
# check_inat_range()'s own text panel. The user correctly identified that
# check_inat_range()'s tabular output (in_range/n_observations/matched_name, no geometry)
# has nothing to actually draw on a map -- but investigated rather than accepted as a dead
# end: iNaturalist has its OWN live observation-tile endpoint
# (api.inaturalist.org/v1/points/{z}/{x}/{y}.png?taxon_id=), confirmed with a real request
# (512x512, real alpha-channel content, not a placeholder). This is real iNat OBSERVATION
# density, not a computed range boundary -- a genuinely different visualization than GBIF's
# tiles, not a duplicate. Reuses the already-looked-up `inat_row()$taxon_id` (from the
# existing text-panel logic), so no new resolution step or param was needed -- only drawn
# when `inat_range` provides a `taxon_id` for the selected taxon.
# (4) `leaflet::addLayersControl()` added (a real, standard Leaflet UI widget) so a
# reviewer can independently toggle GBIF tiles / iNat tiles / kept points / excluded
# points -- increasingly useful now that up to 4 overlays can be showing at once. Also
# downsized the excluded-records red rings (radius 5->3) to match the earlier round's
# kept-points shrink, per explicit request.
# 2 new tests. devtools::test() 356/356 (up from 354), devtools::check() 0 errors/0 notes
# (same pre-existing warning). Reinstalled. Still the same standing gap: no real RStudio
# click-through of these specific changes yet -- three rounds of feedback now, all
# responded to via API-level verification + testServer(), never seen rendered by me
# directly. See [[project_gbif_tile_spatial_review_functions]] for the full record.
# Previous update, 2026-08-07, yet another round (Sonnet 5 -- review_spatial_context() visual
# tuning from a SECOND round of real click-through feedback: (1) GBIF tiles' fine pixel
# geometry didn't stand out against the default OpenStreetMap basemap. Default `tile`
# changed OpenStreetMap -> "CartoDB.Positron" (a muted, mostly-grayscale basemap chosen so
# GBIF's colours -- not the basemap's own roads/labels/land colour -- carry the visual
# weight). New `gbif_style` param (default "classic.point", GBIF's own map-API `style`
# query parameter) exposes GBIF's colour/aggregation choice directly rather than working
# around it -- verified empirically against the real GBIF tile API before picking a
# default: `.poly`-suffixed styles (area/hexagon aggregation, the plausible "smoother
# rendering" option) can return a completely EMPTY tile at a real zoom/species combination
# where `.point` styles render correctly, ruling them out as a safe default; `.point`
# variants (`purpleHeat.point` etc.) are valid, bolder-coloured alternatives a caller can
# opt into. (2) Occurrence points (`occurrence_data`) were still oversized next to GBIF's
# fine tile pixels even after the FIRST round's radius cut (4->3) -- shrunk further to
# radius=2, weight=0 (no outline, a plain dot rather than a bordered disc). The
# `excluded_occurrence_data` red-ring overlay from the prior round was confirmed working
# well by the user and left unchanged. devtools::test() 354/354, devtools::check() 0
# errors/0 notes. Still the same open item: no real RStudio click-through confirmation of
# THESE specific tuning changes yet -- this is the user's second round of feedback on
# renders they saw live, but I still haven't seen the rendered result myself. See
# [[project_gbif_tile_spatial_review_functions]] for the full record.
# Previous update, 2026-08-07, continued once more (Sonnet 5 -- review_spatial_context()
# refined from the user's first real click-through, three concrete points: (1) the local
# occurrence points overwhelmed the GBIF density tiles visually, and the tiles didn't look
# like GBIF's own rendering -- root cause: an unneeded `tileOptions(opacity = 0.75)`
# override on the tile layer, on top of `occ_points`'s own fairly bold styling (radius=4,
# fillOpacity=0.8). Fixed by dropping the tile opacity override entirely (render GBIF's
# tiles exactly as GBIF serves them -- their own colour ramp already encodes density, a
# second multiplier just makes sparse species harder to see than GBIF's own viewer shows
# them) and toning the occurrence points down (radius=3, fillOpacity=0.45) so both layers
# stay readable together. (2) The iNat panel was silently blank whenever `inat_range` had
# no row for the selected taxon -- a real, common case (`check_inat_range()` only ever
# covers a pipeline's own undetected/unreferenced candidate list, see
# [[project_inat_range_backbone_mismatch_todo]]), but silence reads identically to "iNat
# integration is broken." Fixed: any taxon now shows an explicit iNat line whenever
# `inat_range` was supplied at all -- either the real data or "no data for this taxon" --
# with no line at all only when `inat_range` itself is `NULL` (the "not using this feature"
# case, correctly still silent). (3) The user asked whether records this study's OWN GBIF
# filtering had excluded as questionable could be shown too -- investigated rather than
# guessed at: checked the real GreatLakes2023 checkpoints directly and found 0 geographic-
# outlier removals and 0 institution-flagged removals for this dataset (both real, checked
# numbers, not assumptions), but a real 530 records excluded by
# `TaxaFetch::filter_gbif_quality()` between `raw_gbif` (7287 rows) and `geo_outlier_check`
# (6757 rows) -- recoverable via a plain `anti_join` on `gbifID`, independent of whether
# `filter_gbif_quality()`'s own `removed_records` attribute survived the pipeline intact.
# New `excluded_occurrence_data` param (same schema as `occurrence_data`, reusing its
# column-name params) renders these as hollow red rings, visually distinct from the solid
# blue "kept" points -- shown for provenance, not as evidence of presence. Not computed
# inside the gadget (workflow-specific reconstruction logic); the user's own
# `GreatLakes2023_TestSpatialReviewFunctions.R` (outside this monorepo) was updated with a
# tested, real-data-verified reconstruction snippet (confirmed against the real checkpoint
# files before shipping -- e.g. round goby has 16 of the 530 real exclusions, mostly
# `TAXON_ID_NOT_FOUND`/`COORDINATE_ROUNDED` GBIF issue codes). 4 new tests. `devtools::test()`
# 354/354 (up from 350), `devtools::check()` 0 errors/0 notes (same pre-existing warning).
# Reinstalled. Still same open item as before: a real interactive click-through in RStudio
# hasn't happened yet -- this round's fixes are unverified in the browser itself, only via
# `testServer()` + the real checkpoint-data reconstruction check. See
# [[project_gbif_tile_spatial_review_functions]] for the full record.
# Previous update, 2026-08-07, continued yet further (Sonnet 5 -- new review_spatial_context()
# gadget, the click-through UI from the original brainstorm this whole thread started
# from ("scroll through a list of taxa and generate a GBIF map"). Follows this ecosystem's
# established gadget pattern (leaflet + miniUI + shiny::paneViewer(), matching
# TaxaHabitat::review_spatial_flags()): a taxon dropdown filterable by a plausibility
# column (e.g. add_posthoc_assessment()'s primary_plausibility -- expected/unexpected/
# unprecedented), a sidebar showing the SAME numeric context already built this session
# (check_gbif_tile_range()/compute_local_occurrence_distance(), plus a pre-supplied
# inat_range lookup), and a live, pannable/zoomable leaflet tile layer rendering GBIF's
# real density tiles directly (leaflet::addTiles() with the density-tile URL template --
# the literal one-line idea the whole conversation opened with) rather than a static
# snapshot. A "Run AI Review" button calls review_assignments() live, single-taxon --
# deliberately the ONE thing in this gadget that is never automatic (a real, billed LLM
# call), gated behind an explicit click and only shown at all when context is supplied;
# every other reactive update (taxon selection -> GBIF/iNat/local lookups, map tile
# refresh) is free/cheap and fires automatically.
#
# Verification took a real detour worth recording: standard browser-automation tooling
# (Chrome extension driven via computer-use style tools) hung indefinitely waiting for
# "network idle" against a live running instance of this gadget -- confirmed NOT a bug in
# the gadget itself (a plain curl request got a fast, correct 200 response and structurally
# correct HTML: the right dropdown options, the AI-review section correctly absent when
# context = NULL), but a real mismatch between that tool's idle-wait heuristic and a Shiny
# app's persistent WebSocket connection, which never "finishes" the way a normal page load
# does. Rather than keep fighting that (stopped after 3 identical hangs, matching this
# project's own "avoid rabbit holes" guidance), pivoted to shiny::testServer() -- Shiny's
# own supported non-browser mechanism for exercising server-side reactive logic -- which
# needed one clean refactor first: the server closure was extracted out of
# .review_spatial_context_impl() into a new .build_spatial_context_server() factory so it
# could be driven directly, independent of runGadget()/the interactive()-only gate.
#
# That testing effort was NOT a formality -- it caught one real bug before any user ever
# would have: gbif_res()'s reactive used shiny::req(!is.na(key)) to skip GBIF lookup for
# an unresolvable taxon name, but req()'s silent-stop PROPAGATES to any caller reading that
# reactive -- since output$stats_panel reads gbif_res() unconditionally, an unresolvable
# name would have silently blanked the ENTIRE stats panel (including the Local/iNat
# sections, which don't even depend on GBIF at all), not just shown the intended "could not
# resolve" message. Fixed by returning NULL from the reactive instead of req()'ing --
# req() is for "this whole output has nothing to show," not "handle this input
# differently," and conflating the two is exactly the kind of bug that only surfaces when
# you actually exercise the reactive graph, not by reading the code. 16 new
# testServer()-driven tests (GBIF distance/patch display, beyond_buffer phrasing, the
# unresolvable-name fix itself, iNat mismatch flagging in both directions, the local/free
# panel with and without occurrence_data, map output rendering, the AI-review button's
# success path and its real graceful-NA-degradation-on-LLM-failure path -- NOT a thrown
# error, since review_assignments() already catches that internally, a wrong test premise
# caught and corrected before shipping -- and .resolve_gbif_taxon_key()'s real-response-
# shape parsing). New Suggests: leaflet, miniUI, shiny (all requireNamespace()-guarded,
# matching this file's established convention). devtools::test() 350/350 (0 failures, up
# from 334), devtools::check() 0 errors/0 notes (same pre-existing, unrelated
# build_review_covariates.R warning). Reinstalled; the raw HTTP/HTML structure was also
# re-verified directly against the freshly installed package (not just load_all()).
#
# What's genuinely NOT yet verified: a real interactive click-through in an actual RStudio
# session -- the testServer() suite proves the reactive LOGIC is correct, but the full
# browser-rendered experience (does the leaflet tile layer actually paint GBIF tiles
# correctly on pan/zoom, does the paneViewer() open cleanly in RStudio's own viewer pane)
# still needs the user's own live test, matching this ecosystem's established pattern for
# every other interactive gadget here (review_spatial_flags()/review_institution_flags()/
# plot_theta_map_interactive() were all ultimately validated this way, not by an automated
# suite alone). See [[project_gbif_tile_spatial_review_functions]] for the full record.
# Previous update, 2026-08-07, continued (Sonnet 5 -- review_assignments() wired to the new
# spatial-review functions (check_gbif_tile_range()/compute_local_occurrence_distance(),
# plus TaxaFetch::check_inat_range()), closing out the design conversation from earlier
# the same session. Six new optional _col params (dist_nearest_occupied_km_col,
# patch_diameter_km_col, beyond_buffer_col, inat_in_range_col, inat_n_observations_col,
# inat_matched_name_col), matching this function's existing consensus_posterior_col-style
# convention exactly: real producer column names as defaults, silently skipped when
# absent, purely additive to the PROMPT (no new output columns, no change to which rows
# are reviewed or the dedup key). New internal .summarise_spatial_context() mirrors
# .summarise_pipeline_context()'s O(n) split()-based grouping.
#
# Key design decision, reached with the user before implementing: facts only in the
# per-taxon "[...]" bracket (e.g. "GBIF: nearest occurrence ~6517km away, patch ~7.3km
# across; iNat: matched to 'Gasterosteus aculeatus' (name differs from query), in range,
# 10135 obs") -- no plausibility judgment is pre-computed or baked in server-side. A
# rigid "if sources disagree, downweight" rule was considered and explicitly rejected,
# citing this ecosystem's own precedent (the trusted_rank mechanism, built then removed
# after misfiring on real data -- [[project_rank_trust_mechanism_removed]]). Instead, two
# real interpretive caveats are added as a single conditional GUIDELINES bullet (only
# included when a batch has >=1 spatial note): (1) GBIF's density map is raw/unfiltered,
# so a small isolated patch is weaker evidence than a large one; (2) an iNat matched_name
# that differs from the taxon under review may describe a different species entirely
# (see the iNat TODO below) -- treat that verdict with suspicion, not confirmation.
#
# Prompted by real GreatLakes2023 data, not a hypothetical: comparing the new
# check_gbif_tile_range() against TaxaFetch::check_inat_range() for the same 4
# "unprecedented" taxa found check_inat_range() had resolved Gasterosteus gymnurus (a
# European fish) to Gasterosteus aculeatus (North American/circumpolar) via a fuzzy name
# match, returning a misleading in_range=TRUE -- exactly the scenario matched_name
# exposure now lets a reviewer (human or LLM) catch. That underlying check_inat_range()
# limitation is NOT fixed here -- filed as its own separate TODO,
# [[project_inat_range_backbone_mismatch_todo]], since it's a real bug with its own live
# production consequence (TaxaAssign::adjust_inat_range_priors() already elevates priors
# based on this unchecked verdict) independent of this prompt-wiring work.
#
# Live-verified via a prompt-capturing stub llm_fn (not just output-column assertions,
# since this feature is purely prompt-side) against the exact real 3-species scenario
# (Lepomis peltastes/Gasterosteus gymnurus/Campostoma pullum) -- confirmed correct
# per-taxon alignment, the conditional GUIDELINES bullet appearing only when warranted,
# and the name-mismatch annotation firing/not-firing correctly. One real false-positive
# test failure caught and fixed before shipping: an early assertion checked for the
# literal string "iNat:" anywhere in the whole prompt to confirm a disabled param had no
# effect, but the GUIDELINES bullet's own fixed text legitimately mentions the general
# "GBIF:"/"iNat:" notation concept regardless of which columns are enabled -- fixed by
# scoping the check to the TAXA TO REVIEW section only. 14 new tests.
# devtools::test() 334/334 (0 failures, up from 320), devtools::check() 0 errors/0 notes
# (same pre-existing, unrelated build_review_covariates.R warning). Reinstalled,
# re-verified post-install. See [[project_gbif_tile_spatial_review_functions]] for the
# full cross-session record.
# Previous update, 2026-08-07 (Sonnet 5 -- check_gbif_tile_range() refined from real user
# feedback against the real GreatLakes2023 "unprecedented" test case (below), not a
# hypothetical -- two real flagged taxa this session (Barbatula barbatula, a European
# stone loach; Gasterosteus gymnurus, a European stickleback) came back
# beyond_buffer = TRUE / dist = NA at the default zoom, and the user pointed out that a
# flat NA is a real usability gap: a reviewer wants to know it's very far (consistent
# with a genuine misidentification/contamination flag) rather than an undifferentiated
# "unknown." Two fixes, both additive (no signature removals):
#
# (1) Zoom escalation (new @section "Zoom escalation" in the roxygen): new `escalate`
# (default TRUE) and `min_zoom` (default 0L) params. When nothing is found at the
# requested zoom, the SAME buffer_px window is retried one zoom level coarser
# (geometric doubling of real-world coverage per step) down to min_zoom, stopping as
# soon as something is found. New output columns zoom_requested/zoom_used/escalated
# make the actual precision of the answer legible (compare against zoom_used, not the
# originally requested zoom). `beyond_buffer` is REDEFINED under escalate = TRUE
# (the new default) to mean "not found anywhere down to min_zoom" -- with the default
# min_zoom = 0, this is now a real, decisive finding (absent from GBIF's density map
# entirely), not just "outside this one window." `escalate = FALSE` restores the exact
# original single-zoom behavior byte-for-byte. Directly answers the user's own
# efficiency worry ("doing multiple zooms might not be efficient?") empirically, not
# just by argument: live-verified both real problem species now resolve at zoom 3 (3
# extra steps, 36 total tiles, ~8s) to real, plausible transatlantic distances (6567km
# and 6514km respectively -- sanity-checks correctly against their known European
# ranges), while the already-working round-goby case does NOT escalate at all
# (zoom_used == zoom_requested, same ~3s cost as before) -- escalation only ever costs
# extra when the answer would otherwise have been NA, and even the fully-exhausted
# worst case (a fabricated, real-nowhere taxonKey, escalating all the way to
# min_zoom = 0) took ~12s for 54 tiles, still bounded.
#
# (2) km-scaled patch size (the user's other concrete ask -- "if it is possible to
# report in km dimensions rather than n pixels"): new patch_area_km2
# (`patch_size_px * resolution_km_per_px^2`) and patch_diameter_km
# (`sqrt(patch_size_px) * resolution_km_per_px`, a rough linear scale directly
# comparable to dist_nearest_occupied_km for eyeballing "isolated point N km from a
# patch M km across"). patch_size_px/patch_size_capped are kept (still needed to know
# whether the km values are a lower bound), not replaced.
#
# Refactored the single-zoom tile-fetch/stitch/distance/patch logic out into a new
# internal .check_gbif_tile_range_at_zoom() so the public function can call it
# repeatedly across the escalation loop without duplicating it. Test suite rewritten
# for the new signature/columns plus new escalation-specific tests (a zoom-aware mock
# confirms escalation stops at the first zoom that finds something and does NOT
# continue past it; the min_zoom-exhausted case; the escalate = FALSE opt-out).
# devtools::test() 320/320 (0 failures, up from 297 -- the 5 pre-existing WARN lines are
# unrelated review_assignments() expect_warning() tests). devtools::check() 0 errors/
# 0 notes (same pre-existing, unrelated build_review_covariates.R warning). Reinstalled,
# re-verified post-install via a direct smoke test on one of the two real motivating
# species. The user's own GreatLakes2023_TestSpatialReviewFunctions.R test script
# (outside this monorepo, not under git) updated in parallel to surface
# zoom_used/escalated/patch_area_km2/patch_diameter_km in its comparison table. See
# [[project_gbif_tile_spatial_review_functions]] in the memory system for the full
# record, including the real numeric feedback this session started from.
# Previous update, 2026-08-06 (Sonnet 5 -- two new standalone review-support functions,
# compute_local_occurrence_distance() and check_gbif_tile_range(), from a multi-turn
# design conversation about giving a TaxaFlag reviewer spatial context for a taxon
# flagged "unexpected"/"unprecedented" by add_posthoc_assessment()'s Axis 1. Both answer
# the same question -- "how far is this detection from where this species is normally
# found?" -- at two different cost/precision points, deliberately NOT merged into one
# function since they have genuinely different data sources and cost profiles:
#
# compute_local_occurrence_distance() is free (no network call at all): it reuses
# occurrence data a workflow's own TaxaFetch step already downloaded (e.g.
# GreatLakes2023_ConsensusWorkflow.R's all_occurrences/occurrences_clean), and just
# computes geodesic (haversine) distance from a query point to the nearest already-
# fetched record of a given taxon. A taxon with n_local_records = 0 here is, by
# construction, exactly the situation that produces
# TaxaAssign::compute_group_priors()'s consensus_has_occurrence_record = FALSE -- this
# function answers *why* an "unprecedented" flag fired, using data the pipeline already
# paid for. Scope-limited to whatever bounding box the study's own GBIF fetch covered.
#
# check_gbif_tile_range() covers the wider question the local fetch structurally can't:
# is a species novel to this study also far from its known range everywhere, or just
# novel here because no one sampled here before. Downloads GBIF's occurrence-density map
# tiles (the leaflet PNG endpoint from the user's original idea,
# api.gbif.org/v2/map/occurrence/density/{z}/{x}/{y}@1x.png) around a point and reads
# ONLY the alpha channel (transparent = zero occurrences, any non-zero = at least one) --
# deliberately never tries to decode the colour ramp into a density value, which is
# unreliable. Reports point_occupied, dist_nearest_occupied_km (haversine-equivalent but
# computed in tile-pixel space via the standard Web Mercator ground-resolution formula),
# and patch_size_px (an 8-connected blob size grown from the nearest occupied cell -- a
# weak proxy for "one lone report" vs. "a small cluster of independent nearby reports",
# the geometric signature the user was trying to define for a rare-bird-style vagrancy
# report as distinct from a data error). Explicitly does NOT try to distinguish error
# from genuine rarity -- both produce the identical isolated-point signature; that
# distinction is TaxaFetch::check_geographic_outliers()'s job (a different, prior
# question: is this occurrence plausible at all), not this function's.
#
# Several real facts about GBIF's tile API were verified empirically against live tiles
# before writing any georeferencing math, not assumed: (1) tile_size is 512px for
# @1x.png, not the 256px OSM/slippy-map convention -- confirmed by inspecting a real
# decoded PNG's dimensions. (2) The standard XYZ/Web-Mercator tile formulas and PNG
# row/column orientation (row=y top-down, col=x left-right) were confirmed decisive via
# real presence/absence at known locations (Homo sapiens turned out to be a bad test
# species -- GBIF's density map has only 118/262144 non-transparent pixels for it in a
# populous-region tile, presumably a real data-governance exclusion, not a bug; American
# Robin at Ohio gave alpha=1.000 exactly at the hand-computed pixel, confirming both the
# tile math and array orientation). (3) GBIF returns HTTP 204 (empty body) for a tile
# with zero occurrences rather than a blank PNG -- handled explicitly as an all-zero
# alpha matrix, not an error; found by testing a real ocean tile, which crashed the
# naive first version.
#
# One real, measured performance problem was found and fixed before shipping: the first
# patch-growth implementation (unbounded vectorised region-growing via repeated 8-
# connected dilation) took 13-22s end to end for a real, densely-covering species
# (American Robin) because iteration count scales with the patch's geometric extent, not
# its cell count -- convergence needed 65 iterations across a 3-tile mosaic (measured
# directly via profiling, not guessed). Fixed by capping growth at 15 iterations (chosen
# from the real isolated-patch case -- the actual round-goby/Burns-Harbor detection this
# function is for converges in 9) and adding a patch_size_capped flag: a capped patch is,
# by construction, one already covering a wide area, which IS the "clearly not a rarity
# report" signal on its own -- exact size isn't needed once that's already obvious. Cuts
# worst-case latency from ~22s to ~4s (network-dominated, 9 tile fetches) while leaving
# the small/isolated case this function targets fully exact.
#
# Both functions live-verified against real GBIF data (not just synthetic tests) before
# writing the test suite: round goby (Neogobius melanostomus, a real Great Lakes
# invasive) near-occupied at Burns Harbor (dist 0.91km, patch 52 cells, uncapped) vs. the
# same species query point moved to the Sahara (beyond_buffer = TRUE, correct negative
# control); Salmo salar/genuinely-fictional-species correctly return
# n_local_records = 0/NA in compute_local_occurrence_distance(). Offline test suite mocks
# only the network boundary (.fetch_gbif_tile_alpha(), plus one direct
# httr2::req_perform() mock via the real httr2::response() test constructor for the 204
# case) -- same strategy TaxaFetch's test-check_geographic_outliers.R already uses,
# letting all the real tile math/stitching/distance/patch-growth logic run for real
# underneath the mock. New Imports: rlang (for the .data pronoun in
# compute_local_occurrence_distance()); new Suggests: httr2, png (check_gbif_tile_range()
# hard-stops with an install message if either is missing -- no fallback exists, same
# convention TaxaFetch::check_geographic_outliers() uses for CoordinateCleaner).
# devtools::test() 297/297 (0 failures, up from 232 -- the 5 WARN lines are pre-existing
# review_assignments() tests exercising expect_warning() paths, unrelated).
# devtools::check() 0 errors/0 notes; the sole warning is the pre-existing, unrelated
# build_review_covariates.R Rd cross-reference issue this file has documented for
# sessions. Reinstalled to ~/Library/R/4.0/library, re-verified via a direct post-install
# smoke test (not just the install call's exit status). Not yet wired into
# review_assignments() or any gadget UI -- both are standalone functions a reviewer (or a
# future click-through gadget, still just discussed, not built) can call directly on a
# consensus_final row flagged unexpected/unprecedented.
# Previous update, 2026-07-30 (Sonnet 5 -- add_posthoc_assessment()'s Axis 1 rebuilt around
# theta_mean instead of prior_mean, closing out the 2026-07-28 design's two real weaknesses
# found live-testing against production Mugu data. (1) prior_mean can be substantially
# inflated by TaxaAssign::update_prior_from_consensus()'s cross-observation confirmation
# boost, which has no gate on occurrence-record presence -- measured on real Mugu data,
# EVERY row with prior_mean >= 0.5 was a boosted row, so an "expected" call built on
# prior_mean meant "confirmed elsewhere in this dataset", not "expected here on occurrence
# grounds". theta_mean (TaxaExpect::prepare_model_dataframe()'s raw occurrence-model share)
# is immune to that boost by construction. (2) A single absolute threshold (the previous
# design's fixed 0.5) is a unit mismatch on the theta_mean scale (a share of local records,
# not a presence probability) AND biased across ranks -- a genus/family-level consensus_prior
# (now a SUM over group members, see TaxaAssign/CLAUDE.md's matching note) is mechanically
# larger than any one species' own share just from summing more terms (confirmed: 27/28 real
# Mugu families cleared the species-level median purely by having more members). Fixed:
# winner_prior_col/winner_record_col/consensus_prior_col/expected_prior_threshold=0.5 (the
# 2026-07-28 design) replaced by winner_theta_col/winner_record_col/consensus_prior_col/
# consensus_record_col (new)/expected_theta_threshold (no default, now a NAMED VECTOR keyed
# by rank -- "species" required, genus/family optional; a rank absent from the vector gets
# "not_modeled" rather than an unsafe cross-rank comparison). consensus_record_col
# (default "consensus_has_occurrence_record") reads TaxaAssign::posterior_consensus()'s new
# dedicated presence column directly instead of inferring presence from consensus_prior's
# own NA-ness -- closes a real production bug (100% of 616 real Mugu rows read
# "unprecedented" the moment group_priors was first wired into posterior_consensus(), since
# consensus_prior's NA had started meaning "group_priors never supplied" as well as "checked,
# absent", and the old inference couldn't tell them apart). Also retired posthoc_assessment
# and its supporting params (tiers/taxon_col/tier_col/finest_rank) entirely -- there is no
# replacement for the 3x2 tier-times-likelihood table itself, since primary_plausibility
# (occurrence side, now theta-based) and primary_discrimination (evidence side, Axis 2)
# already answer the same two questions without collapsing them into one column or gating
# either on rank; the retired design's "vague_rank" category had short-circuited 109/616
# real Mugu observations (17.7%) into never being assessed at all. Real end-to-end
# verification via MuguFishWorkflow.R (not just the test suite): after TaxaAssign's own
# group_priors wiring + a full real backbone-architecture fix (see TaxaID/CLAUDE.md's
# 2026-07-30 note), final consensus_plausibility distribution: 519 expected / 93 unexpected /
# 4 unprecedented (the 4 being genus-level taxa already flagged as genuinely suspect in
# earlier project investigation, not a further bug). Fixtures in
# test-add_posthoc_assessment.R updated to carry consensus_has_occurrence_record explicitly.
# devtools::test() 240/240 (0 failures), devtools::check() 0 errors, with the pre-existing
# build_review_covariates.R warning + .data note unchanged. Reinstalled and verified via a
# direct smoke test (not just the reinstall command's exit status -- see TaxaAssign/CLAUDE.md's
# matching note for why a stale-install bug this exact session made that distinction matter).
# See [[project_axis1_consensus_prior_group_priors]] in the TaxaID memory system for the full
# debugging record.
# Previous update, 2026-07-28, later (Opus 5 -- add_posthoc_assessment() gains Axis 1:
# primary_plausibility and consensus_plausibility, each one of "expected"/"unexpected"/
# "unprecedented"/"not_modeled". Four new params (winner_prior_col, winner_record_col,
# consensus_prior_col, expected_prior_threshold = 0.5), all with defaults matching
# TaxaAssign::posterior_consensus()'s real column names and silently skipped (NA output,
# no error) when absent -- this function's established optional-upstream-output
# convention.
#
# "unprecedented" is driven by RECORD PRESENCE, never by a low prior value -- see
# TaxaAssign/CLAUDE.md's same-day note for the real-data evidence (a never-reported taxon
# and a genuine singleton can carry the identical floor prior while meaning opposite
# things, so no threshold on the value can separate them).
#
# The 0.5 break was chosen over a fitted cutoff because it does two jobs at once: it is
# directly interpretable (the taxon is at least as likely present as absent) AND it falls
# in a genuinely empty region of the real prior distribution -- nothing between 0.0865 and
# 0.966, an 11x gap. Same reasoning as Axis 2's 0.05/0.5 breaks.
#
# Reported ALONGSIDE the other columns, never gating them -- which is the specific defect
# "vague_rank" has. Measured on the real 616-observation Mugu dataset: 109 observations
# get "vague_rank" from posthoc_assessment and are therefore left unassessed entirely
# (it short-circuits every non-species rank); Axis 1 classifies all 109 (78 expected,
# 22 unexpected, 9 unprecedented). That is the original ASV_379/Chaenogobius bug this
# whole redesign exists to fix, now demonstrably closed.
#
# Anchor validation -- Axis 1 reproduces the user's own domain judgment unprompted: both
# taxa they independently called genuinely suspect (ASV_379 Chaenogobius, ASV_30
# Prosopium) come out "unprecedented", as do ASV_371 Salmonidae (their read: a food item,
# not a wild population) and ASV_382 Sciaenidae (their read: all candidates implausible);
# the CA-native tidewater-goby-bearing ASV_463 Gobiidae comes out "expected".
#
# Primary and consensus scopes disagree on only 3/616 real observations (vs Axis 2's
# 23/606) -- reported as two columns per the user's explicit requirement that both axes
# carry primary_taxon and consensus_taxon versions. 10 new tests (239 total, up from 222),
# including the two that pin the design: a no-record taxon with a HIGH prior must be
# unprecedented, and a singleton at the floor must NOT be. Full real pipeline
# (posterior_consensus -> add_posthoc_assessment, 616 obs) runs in 1.5 s.
# devtools::test() 239 pass / 0 fail; devtools::check() 0 errors, with the pre-existing
# build_review_covariates.R warning + .data note unchanged. Reinstalled.
# Previous update, 2026-07-28 (Opus 5 -- add_posthoc_assessment() loses the
# "unsupported_rank" category and both params that drove it (absolute_fit_pvalue_col,
# weak_evidence_pvalue), following TaxaLikely's removal of the underlying
# absolute_fit_pvalue column. Decisive evidence: the category fired on 0 of 606 real Mugu
# observations at its shipped 0.001 default and is absent from real posthoc_assessment
# output entirely -- it has never once classified a real row. See
# [[project_absolute_fit_pvalue_retired]] for the full audit (written before the removal,
# at the user's request, to keep revival possible).
#
# confusion_risk_flag is UNTOUCHED and still present. One test
# ("confusion_risk_flag never overrides posthoc_assessment") was rewritten rather than
# deleted -- it had been asserting non-interference by pinning the OTHER column to
# "unsupported_rank"; it now demonstrates the same property directly, by confirming that
# changing the confusion risk leaves posthoc_assessment identical.
#
# Also: REENTRY_PROMPT_*.md added to .Rbuildignore (they were tripping R CMD check's
# top-level-files note). vignettes/quality-flagging.Rmd deliberately NOT given the
# purl = FALSE fix applied to the other 9 ecosystem vignettes -- it has no global
# eval = FALSE and genuinely evaluates. devtools::test() 222 pass / 0 fail;
# devtools::check() 0 errors, with the pre-existing build_review_covariates.R
# warning + .data note unchanged (confirmed untouched). Reinstalled.
# Previous update, 2026-07-24, later still (Sonnet 5 -- review_assignments() wired up to
# TaxaAssign::posterior_consensus()/add_slash_taxon() columns that postdate when this
# function was originally written, prompted by the user asking to tabulate which newer
# consensus columns weren't being taken into account. Four new params, all additive/
# backward-compatible (non-NULL defaults matching the real producer column names,
# silently skipped -- not an error -- when that column is absent from df, matching
# add_posthoc_assessment()'s own established convention for this kind of optional
# pass-through column): consensus_posterior_col ("consensus_posterior"), winner_prior_col
# ("winner_prior"), winner_rank_expanded_col ("winner_rank_expanded"),
# plausible_posteriors_col ("plausible_posteriors"). When present, a compact "[...]"
# annotation is appended to each taxon's line in the LLM prompt: median pipeline
# posterior/occurrence prior across every row sharing that taxon/candidate-set label (so
# the LLM's ecological plausibility judgment can be checked against the pipeline's own
# statistical confidence), a note when the winning call came from join_priors()'s
# coarse-rank expansion with no real sequence discrimination, and -- for multi-candidate
# slash/plus labels -- each candidate's own averaged posterior weight (so review_comment
# can speak to the specific weaker member instead of the undifferentiated group). New
# GUIDELINES bullet tells the LLM what the bracket means and how to use it (flag
# disagreement, don't defer to it). Deliberately did NOT wire in consensus_reason/
# is_resolved/n_plausible/winner_likelihood(_cov)/winner_absolute_fit_pvalue/the four
# winner_*_confusion_risk columns/taxon_changed -- either redundant with what
# add_posthoc_assessment() already does numerically, or judged not worth the added prompt
# tokens for this function's specific (ecological plausibility, not statistical
# confidence) job. Separately, fixed a real label-drift risk found during the same
# discussion: the candidate-set path's label builder (.build_candidate_label(), a
# documented duplicate of add_slash_taxon()'s .make_slash_name()) had no equivalent of
# add_slash_taxon()'s downranked-row NA-clearing logic, so the two could produce DIFFERENT
# labels for the same row once species_reference downranking was in play. Now prefers
# df$consensus_OTU (add_slash_taxon()'s own already-computed, already-correct label) when
# present, falling back to the independent rebuild only when absent -- closing the drift
# without adding a hard TaxaAssign package dependency. Both new helpers
# (.summarise_pipeline_context()/.summarise_candidate_weights()) group via split() (O(n))
# rather than a per-label linear scan, to stay cheap on large datasets. Verified with an
# offline mocked-llm_fn smoke test (median aggregation, rank-expanded flag, and candidate
# weights all confirmed correct against hand-computed expected values) in addition to the
# full test suite. devtools::test() 232/232 (0 failures, unchanged from before -- no
# existing test's df carries these new columns, so backward compatibility is exercised by
# the existing suite passing unchanged), devtools::check() 0 errors/0 warnings (1
# pre-existing, unrelated warning+note in build_review_covariates.R, confirmed untouched
# via git diff). Not yet wired into any real production workflow -- both real PtConception
# review_assignments() calls would need to be updated to pass a consensus_df carrying
# these columns (currently upstream of add_slash_taxon() in at least one of the two
# workflows; not verified this session) before the new context would actually appear in a
# live LLM call.
# Previous update, 2026-07-24, later same day (Sonnet 5 -- the unified validity schema below
# (observation_validity/validity_flag/validity_reason) wired into both real PtConception
# production workflows (PtConceptionWorkflow_12S_single_site.R,
# PtConceptionWorkflow_18S_2_single_site.R -- outside this monorepo, not under git, at
# ~/My Drive/Rscripts/eDNA/PtConception/), backed up first as *.bak_pre_validity_schema.
# Every real lab_contaminant_risk/lab_contaminant_score reference at each file's Step 2
# filter, Step 6/9 provenance joins, and (12S only) the final accurate_precise_consensus
# filter updated to validity_flag == "invalid_lab_contaminant" / observation_validity;
# deliberately left untouched: contamination_risk/spatial_flag/*_plausibility (unrelated
# columns from review_assignments()/flag_habitat_inconsistencies(), confirmed by tracing
# each column's real source before editing, not by name similarity alone). 18S_2's own
# pre-existing Session 101 name-migration block (upgrading a cached RDS's old
# flag_lab_contaminant naming forward) was EXTENDED, not replaced, with a second branch
# migrating lab_contaminant_risk/score/reason values forward to the new schema
# ("high"/"moderate"/"low" -> "invalid_lab_contaminant"/"questionable_lab_contaminant"/
# "valid") -- verified against both real cached *_contaminant_flags.rds checkpoints (12S:
# 43/10300/3254 high/moderate/low; 18S: 1/18693/2503), which are themselves still on the
# pre-2026-07-24 schema, confirming the migration path is genuinely exercised, not
# speculative. Also confirmed the freshly-installed flag_contaminant() itself now emits
# the new schema directly (live-tested against a small synthetic case) -- an initial
# verification attempt without explicitly setting R_LIBS_USER showed the OLD schema,
# which was the documented bare-Rscript library footgun, not a real regression; resolved
# by setting .libPaths() explicitly per that footgun's known fix. Both workflow files
# parse cleanly (parse() check); not yet run end to end (would trigger live GBIF/NCBI/LLM
# calls) -- left for the user to trigger.
# Previous update, 2026-07-24 (Sonnet 5 -- flag_contaminant()/flag_handler() redesigned around a
# unified observation_validity/validity_flag/validity_reason schema, closing out the polarity
# audit's two flagged-but-deferred names (contaminant_score, flag_handler_score) from
# 2026-07-23. Real correction found mid-design: both were mischaracterized in the original
# audit as "high=more risk" (matching contaminant_risk-style naming) -- verified directly
# against source and actually HIGH=GOOD/genuine, LOW=likely contaminant or handler artifact
# (contaminant_score's own roxygen: "Taxa with a higher rate in controls than field samples
# receive low scores"). Renaming them to a "_risk" suffix would have been a backwards, actively
# WRONG fix, not merely a missed opportunity -- caught by reading the real case_when()/
# threshold logic before touching any file, not by trusting the prior day's audit conclusion.
# Final schema (both functions now share it, matching add_posthoc_assessment()'s existing
# "one column, type-qualified values" precedent rather than inventing a new pattern):
# observation_validity (numeric 0-1, high=good, was contaminant_score/flag_handler_score);
# validity_flag (character: "valid"/"questionable_{type}"/"invalid_{type}", was
# {contaminant_type}_risk's high/moderate/low and flag_handler's likely/possible/unlikely);
# validity_reason (was {contaminant_type}_reason/flag_handler_reason). contaminant_type's
# column-NAME-parameterization (e.g. lab_contaminant_risk vs positive_control_risk, letting two
# calls coexist on the same taxa) is gone -- verified first that neither real PtConception
# workflow uses that multi-call pattern -- the type now lives in validity_flag's VALUE instead
# (e.g. "invalid_lab_contaminant"), matching flag_handler()'s fixed-name convention. Kept the
# existing 3-tier severity (not collapsed to binary) per explicit user direction, so no
# information is lost relative to the old high/moderate/low or likely/possible/unlikely scales.
# report_flags() gained a THIRD auto-detection branch (validity_flag-based, additive to the two
# pre-existing naming eras it already supported) since column names alone no longer identify
# which check produced a flag -- reads the type qualifier out of the VALUE instead. Also fixed
# a real citation error in add_posthoc_assessment()'s own confusion_risk_flag docs (written
# 2026-07-23), which had cited contaminant_score as a "high=concern" precedent -- backwards,
# now corrected. devtools::test() 0 failures (123, up from 119 -- 4 new report_flags() tests for
# the new detection branch), devtools::check() 0 errors/0 warnings (1 pre-existing, unrelated
# warning+note in build_review_covariates.R, untouched). Reinstalled to ~/Library/R/4.0/library.
# Previous update, 2026-07-23, later same day (Sonnet 5 -- renamed add_posthoc_assessment()'s
# score_support_flag -> confusion_risk_flag (+ own_rank_support_col -> own_rank_confusion_risk_col,
# weak_score_support_threshold -> high_confusion_risk_threshold, and the two flag values
# "weak_score_support"/"adequate_score_support" -> "high_confusion_risk"/"low_confusion_risk"),
# matching the same-day TaxaLikely/TaxaAssign renames -- see TaxaID/CLAUDE.md's top session
# note for the full cross-package record. Pure rename, no math changed; 7 tests renamed in
# place (not new), same 119 total. The note below (same day, earlier) describes the original
# implementation and now uses the corrected names throughout.
# Previous update, 2026-07-23 (Sonnet 5 -- add_posthoc_assessment() gains a new, deliberately
# SEPARATE confusion_risk_flag column (own_rank_confusion_risk_col default "winner_own_rank_confusion_risk",
# high_confusion_risk_threshold default 0.5) implementing Task 1's TaxaFlag wiring from
# ecosystem_docs/REENTRY_PROMPT_score_support_posthoc_and_rank_thresholds.md (full
# cross-package record in TaxaID/CLAUDE.md's top session note). Reads
# TaxaAssign::posterior_consensus()'s new winner_own_rank_confusion_risk pass-through (itself sourced
# from TaxaLikely::evaluate_likelihoods()'s new species_confusion_risk/genus_confusion_risk/family_confusion_risk --
# a model-independent, score-ONLY diagnostic where LOWER values mean STRONGER evidence).
# Deliberately kept as its OWN new column rather than folded into posthoc_assessment's existing
# override chain the way "unsupported_rank" is -- the explicit design rationale, documented in
# a new @section Confusion-risk flag, is the trusted_rank ladder-walk's own cautionary precedent
# (built 2026-07-19, removed 2026-07-20 after a real ~30% mismatch + a downranking-cancellation
# bug, see [[project_rank_trust_mechanism_removed]]): a mechanism that recomputes/overrides an
# existing categorical judgment is exactly the shape that broke there, so confusion_risk_flag
# stays a plain additive threshold that never interacts with posthoc_assessment. 7 new tests
# added to test-add_posthoc_assessment.R (119 total, up from 112) covering the NA-when-absent
# case, above/below-threshold classification, NA-propagation, custom column name, non-
# interaction with posthoc_assessment, and both new input-validation errors. devtools::test()
# 0 failures (119), devtools::check() 0 errors/0 warnings (1 pre-existing, unrelated warning +
# note in build_review_covariates.R, confirmed untouched this session via git diff).
# Reinstalled to ~/Library/R/4.0/library.
# Previous update, 2026-07-20 (Sonnet 5 -- add_posthoc_assessment()'s "unsupported_rank"
# category (added the day before, see the Session 2026-07-19 note directly below)
# redesigned: `trusted_rank_col` (default `"winner_trusted_rank"`, comparing rank ORDER
# against `consensus_rank_col`) replaced by `absolute_fit_pvalue_col` (default
# `"winner_absolute_fit_pvalue"`) + a new `weak_evidence_pvalue` threshold (default
# `0.001`), comparing the p-value DIRECTLY rather than going through a rank comparison at
# all. Same trigger position (Step 4, still overrides any of the 3x2-table categories
# including "sensible"), same category name, much simpler logic -- no `.std_rank_order`
# constant needed anymore (deleted). Prompted by the user pressure-testing yesterday's
# `winner_trusted_rank`/`uprank_trust_pvalue` mechanism against their own real 12S run:
# a live diagnostic confirmed `winner_trusted_rank` was computed upstream
# (`TaxaLikely::evaluate_likelihoods()`) for that FUNCTION's own top-LIKELIHOOD
# hypothesis, not necessarily the same hypothesis that wins the POSTERIOR reported by
# `TaxaAssign::posterior_consensus()` here -- a confirmed ~30% mismatch on real data,
# meaning `"unsupported_rank"` could fire (or fail to fire) based on the wrong
# candidate's fit. `winner_absolute_fit_pvalue` doesn't have this problem: it is always
# read directly off whichever row `posterior_consensus()` itself treated as the winner,
# with no intermediate ladder-walk to go stale. `TaxaLikely::evaluate_likelihoods()`'s
# entire `min_rank_trust_pvalue`/`trusted_rank`/`rank_trust_basis` mechanism was removed
# the same day (see `TaxaLikely/CLAUDE.md`'s own top note) -- `absolute_fit_pvalue`
# itself is unchanged and still computed unconditionally, only the ladder-walk built on
# top of it is gone. Before implementing, independently re-confirmed
# `absolute_fit_pvalue`'s one-sided design is safe for perfect/near-ceiling matches
# (never penalizes a score better than the trained mean) -- directly answering the
# user's own question about whether this substitution could misfire on exactly the
# cases it's meant to catch. `devtools::test()` 208/208 (0 failures), `devtools::check()`
# clean except the pre-existing, unrelated `build_review_covariates.R`
# warning/note (confirmed via a fresh `check()` mentioning neither
# `add_posthoc_assessment` nor this file). Reinstalled to `~/Library/R/4.0/library`.
# See [[project_rank_trust_mechanism_removed]] in the TaxaID memory system for the full
# investigation record. `add_posthoc_assessment()`'s `"unsupported_rank"` category is
# the intended end state here, not an interim step -- it already says "the evidence may
# be too weak to be confident at the reported rank," which is all that was wanted; no
# further work to suggest a specific replacement rank is planned (confirmed with the
# user, who found an earlier draft of this note over-scoped).
# Previous update, 2026-07-19 (Sonnet 5 -- add_posthoc_assessment() gains a new
# "unsupported_rank" category (Step 4, overrides any of the existing 3x2-table
# categories including "sensible") + new trusted_rank_col param (default
# "winner_trusted_rank", silently skipped when absent from consensus_df -- optional
# upstream output, not required input). Consumes TaxaAssign::posterior_consensus()'s new
# winner_trusted_rank pass-through (see TaxaAssign/CLAUDE.md), itself sourced from
# TaxaLikely::evaluate_likelihoods()'s new rank-trust mechanism (TaxaLikely/CLAUDE.md).
# Real motivation, not hypothetical: winner_likelihood_col is ratio-normalised WITHIN one
# observation (best hypothesis always exactly 1.0 by construction) -- it can read as
# strong evidence even when every candidate fit poorly in absolute terms, simply because
# nothing competitive existed to normalise against (the real motivating case: a
# contamination-pattern detection where every specific candidate species scores poorly
# in absolute terms but the weakest-of-a-bad-lot still "wins" the relative comparison
# outright, landing "sensible" under the old 3x2 logic alone if its prior tier happened
# to be favorable). trusted_rank_col answers a genuinely different, absolute question
# (does this call's own fit to its trained distribution actually hold up at the rank
# being reported), and a mismatch overrides whatever the tier x likelihood table said.
# Purely informational/additive -- never changes consensus_taxon/consensus_rank itself
# (that's TaxaAssign::posterior_consensus()'s own separate, opt-in uprank_trust_pvalue
# mechanism); backward compatible, zero behavior change for any consensus_df lacking the
# new column. REAL BUG found and fixed the same session via a full real 13,442-observation
# PtConception run (not caught by synthetic tests, which all used same-rank-family
# fixtures): the first version used plain string inequality (trusted != consensus_rank),
# which flagged 4,776 real rows -- but 48% (2,275) had trusted_rank FINER than
# consensus_rank, meaning disagreement-based LCA logic had already coarsened the call
# beyond what absolute fit alone requires (not "unsupported" at all, if anything more
# conservative than necessary). Fixed with a new .std_rank_order canonical coarse-to-fine
# constant (mirrors evaluate_likelihoods()'s own auto-detection list) so the mismatch only
# fires when trusted_rank is COARSER than consensus_rank; corrected real count: 2,501/
# 13,442 (18.6%). New regression test reproduces the exact real failure mode. 9 new tests
# total in test-add_posthoc_assessment.R (42 total). devtools::test() 206/206 (0 failures,
# up from 197), devtools::check(): 1 pre-existing warning + 1 pre-existing note in an
# unrelated file (build_review_covariates.R, last touched 2026-07-14, not part of this
# change) -- confirmed via git diff this session touched only add_posthoc_assessment.R/
# .Rd/its test file. Reinstalled to ~/Library/R/4.0/library. Wired into
# PtConceptionWorkflow_12S_single_site.R's add_posthoc_assessment() call
# (trusted_rank_col = "winner_trusted_rank"). See TaxaAssign/CLAUDE.md's and
# TaxaLikely/CLAUDE.md's own session notes for the paired posterior_consensus()
# uprank_trust_pvalue wiring and the full real-data validation record, including the real
# problem this combination caught: 8 real observations confidently called
# Urocyon cinereoargenteus/Canis lupaster (terrestrial canids) at species level in this
# marine 12S survey, absolute_fit_pvalue ~ 0.002-0.004.
# Previous update, 2026-07-11 (Session 152 -- flag_contaminant()'s shrinkage denominator
# changed from SAMPLE count to READ count (n_reads_total = taxon_field_reads +
# taxon_control_reads, replacing n_field_present + n_controls_present), and
# prior_weight's default changed 2 -> 20 to match the new read-equivalent units.
# Session 151's own shrinkage design (0.5 target, applied to the already
# depth-weighted field_rate/control_rate ratio) was correct -- the flaw, found by
# live-testing the Template and both real PtConception workflows
# (ecosystem_docs/REENTRY_PROMPT_session151_debug_template_and_12S_18S.md), was that
# shrinking by SAMPLE count conflated a 2-read detection with a 500,000-read detection
# whenever both happened to come from exactly one sample -- capping BOTH at the same
# distance from 0.5 regardless of actual evidence strength. Concretely: with the
# Session 151 default (prior_weight=2, samples), no taxon detected in 1-8 total samples
# could ever reach "low" risk even with overwhelming read support, and the median real
# taxon in both real PtConception datasets is detected in exactly 1 field sample -- so
# 97% (12S) / 88% (18S) of taxa were capped at "moderate" purely as a sample-count
# artifact, not because the evidence was actually ambiguous.
# Two literature-informed alternatives (decontam's presence/absence prevalence test via
# a hypergeometric test; a depth-weighted binomial-exact test) were prototyped first and
# REJECTED after live-testing against real data: both are one-sided tests where
# "0 control reads" trivially gives p=1 regardless of total evidence, so both degenerate
# almost exactly back to the pre-151 hard-1.0 problem (verified: median score 1.0 on
# both real datasets, undoing Session 151's whole point). A third alternative (Beta-
# Binomial shrinkage toward the study's own depth-based background rate p0) was also
# rejected: it requires anchoring to p0 explicitly and does NOT transfer across studies
# with very different control:field depth ratios -- confirmed directly: it worked
# reasonably on 12S (p0=0.00059) but missed the known real contaminant entirely on 18S
# (p0 rounds to 0, only 1 control/54 field samples) at every prior strength tested.
# Read-count-based shrinkage in the EXISTING depth-normalized rate space needed no new
# anchor point (0.5 remains correct there) and was validated empirically at
# prior_weight in {20, 50, 100, 500}: 100% of known "high"-risk taxa recovered with
# ZERO false positives at every value, on BOTH real datasets, while far more
# well-supported clean taxa correctly reach "low" instead of being capped at
# "moderate" (12S: 330 -> 3263 "low"; 18S: 2503 -> 4140 "low", at the chosen
# prior_weight=20). New `n_reads_total` output column exposes the quantity that now
# drives shrinkage (n_field_present/n_controls_present/n_controls_total remain,
# informational only, unchanged in meaning). Reason string now reports the read count
# used for shrinkage alongside the existing sample-count context. Fully backward
# compatible in shape (no new required params, same column set plus one addition);
# NOT backward compatible in behavior (same as Session 151's own change) -- every
# existing caller relying on the implicit default gets different scores/tiers.
# devtools::test() 185/185 passing (0 failures, 2 pre-existing unrelated warnings in
# review_assignments tests), including a new dedicated test constructing two taxa with
# IDENTICAL sample-count evidence but very different read counts to confirm they now
# score differently, plus rewritten TaxonA/sample_type_col tests reflecting the new
# exact score values. devtools::check() 0 errors/0 warnings/0 notes. See
# ecosystem_docs/REENTRY_PROMPT_session151_debug_template_and_12S_18S.md for the full
# investigative record (the decontam-literature comparison, all three rejected
# prototypes, and the real-data validation) and this file's own flag_contaminant()
# Design section below for the current mechanism.
# Previous update, same day (Session 151, once more -- ecosystem soundness-review item 16
# (flag_handler()'s edge_proximity_score), the LAST of the review's 16 H-priority items,
# fixed: new optional station_metadata param anchors group edges on real per-station
# deploy/retrieve timestamps instead of the detection data's own min/max. The core flaw:
# without real deployment metadata, the very first and last GENUINE wildlife detection at
# a station is always exactly at the data-derived edge and scores maximally suspect,
# purely as an artifact of how "edge" is defined -- not because a handler was ever
# present. station_metadata mirrors the "external attribute lookup table keyed by a
# sample/event identifier" pattern already established in this ecosystem
# (TaxaMatch::join_event_site_metadata(), the BLANKS_MARCH/BLANKS_AUG convention): one row
# per group_col value with deploy_time/retrieve_time (column names configurable via
# deploy_col/retrieve_col). A group present in the data but missing from
# station_metadata (or with an unparseable timestamp) falls back to the data-derived
# min/max for that group only, with an explicit warning() naming it -- a real weakening
# of that group's flag, not a silent one. New edge_anchor_source output column records,
# per row, whether "station_metadata" or "detection_data_fallback" was used. Fully
# additive/backward compatible: station_metadata defaults NULL, and all 36 pre-existing
# tests pass completely unchanged. The vignette (quality-flagging.Rmd) -- still this
# function's only real call site anywhere in the monorepo -- updated to demonstrate the
# new param. 12 new tests. devtools::test() 181/181 (up from 169), devtools::check()
# clean. This closes out the full 16-item H-priority soundness-review walk-through: 16 of
# 16 addressed (fixed/mitigated/reclassified/flagged-by-design -- see
# ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md for the final per-item status;
# "addressed" does not mean every caveat is resolved, several items remain CONDITIONAL
# with explicitly documented open gaps).
# Previous update, same day (Session 151 -- ecosystem soundness-review item 15
# (flag_contaminant()'s contaminant_score) fixed: depth-weighted rates + Empirical Bayes
# shrinkage replace the old unweighted-mean-of-proportions formula with its hard 0.0/1.0
# edge cases. field_rate/control_rate now = sum(taxon reads in group)/sum(total reads in
# that group) -- a proportion from 500,000 reads counts far more than one from 50, fixing
# "read-depth-unweighted." The raw ratio field_rate/(field_rate+control_rate) is then
# shrunk toward 0.5 with weight n_present/(n_present+prior_weight) (default prior_weight=2,
# n_present = total samples across both groups where the taxon was detected) -- a taxon
# absent from controls no longer gets an automatic exact 1.0 when only a couple of controls
# exist. Design bug found and fixed mid-implementation, not just in code review: an earlier
# version shrunk field_rate/control_rate individually toward the taxon's own pooled
# (field+control) rate, which let a taxon's large field read volume leak into its
# control-side prior, systematically understating genuinely clean taxa's scores whenever
# field sequencing depth dominated control depth (the common real case: many field samples,
# few small blanks) -- caught only by running the actual test suite against the mock data
# and seeing TaxonA (a clean, field-only taxon) score "moderate" instead of "low." Fixed by
# shrinking the FINAL ratio toward 0.5 by sample-count replication instead, which keeps the
# two groups' magnitudes fully independent. Also fixed: roxygen no longer calls the score a
# "probability" -- explicit new prose states it's a ranked screening statistic. New
# mean_prop_field/mean_prop_control (unweighted, informational only) vs. field_rate/
# control_rate (depth-weighted, drives the score) distinction throughout docs/reason
# strings. New prior_weight param (default 2, 0 disables shrinkage). Tests updated: two
# tests asserting exact 1.0/0.0 for absent-from-one-side taxa now assert the shrunk,
# non-exact values instead (matching item 11/12's "tests exercising old exact math now pin
# that value explicitly" pattern); new tests cover prior_weight=0 (exact un-shrunk
# boundary), prior_weight sensitivity, and input validation. devtools::test() 169/169,
# devtools::check() clean. See ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md's
# item 15 for the full record.
# Previous update, 2026-07-10 (Session 149 -- add_posthoc_assessment() gains domestic_taxa/
# domestic_prior_source params, implementing the deferred domestic-species-floor design note
# ([[project_taxaflag_domestic_species_floor_note]] in project memory) at the user's direction
# during the ecosystem statistical soundness review walk-through. A strong-likelihood call to a
# user-specified domestic/synanthropic taxon that lands in tier2/tier3_undetected purely because
# GBIF/iNat under-index captive organisms is now re-labelled "domestic_prior_caveat" instead of
# "unexpected"/"unprecedented", so a reviewer sees "trust the ID, question the rarity" rather
# than a generic low-plausibility flag. domestic_taxa defaults to NULL (feature off, matching
# flag_handler()'s handler_taxa convention -- no built-in species list, since "domestic" is
# study-system-specific). domestic_prior_source = "wild" (default) vs "augmented" gives an
# explicit opt-out for pipelines that already augment occurrence data with known local domestic
# presence (the companion prior-side fix: TaxaExpect::generate_undetected_diversity() and
# TaxaAssign::join_priors() both gained a documentation-only note recommending exactly that
# augmentation, rather than TaxaID inventing a fix on the prior side). Backward compatible
# (new params both optional, no behavior change when domestic_taxa is not supplied). 7 new
# tests added to test-add_posthoc_assessment.R (33 test_that blocks total in that file);
# devtools::test() 159/159 passing, 0 failures; devtools::check() 0 errors/0 warnings/1
# pre-existing NOTE (clock-check artifact, same as
# other packages). See this file's own Session 149 note below for the full record, and
# ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md for the review row this resolves.

---

## Package Purpose
Identifies and flags anomalous detections in taxonomic assignment results.
Correct identifications can still be ecologically meaningless due to:
- **Lab contamination** -- human DNA, reagent contaminants, index hopping
- **Field contamination** -- airborne DNA, handler artifacts during collection
- **Allochthonous detections** -- DNA/images/sounds transported from elsewhere
  (e.g., marine fish DNA carried by cormorant into freshwater stream)
- **Taxonomic scope violations** -- taxa outside the study's target group
  (e.g., plant DNA in a fish eDNA survey)

Operates on consensus data frames from TaxaAssign (or any data frame with
a taxon column). Appends categorical flag columns for user-driven filtering.

**Cross-modality:** Functions work for eDNA sequences, camera trap images,
and acoustic detections. Modality-specific logic lives in prompt text and
parameter defaults, not function signatures.

**Status: All core functions implemented and passing devtools::check() (0 errors, 0 warnings).**

---

## Dependency Chain

TaxaAssign -> **TaxaFlag** (post-assignment quality control)

TaxaFlag depends on:
- dplyr, jsonlite, stats (Imports)
- TaxaTools (Imports -- LLM provider functions for review_assignments, report_flags)

---

## Flag Column Convention

**Vocabulary design:** All columns use a consistent direction — higher value = worse for the taxon's credibility as a real detection.

**Data-driven risk columns** (`flag_contaminant`, `flag_handler`) add a triplet:
- `{type}_risk` -- character: `"high"` (probable artifact) / `"moderate"` (uncertain) / `"low"` (likely genuine)
- `{type}_score` -- numeric: interpretable ratio or confidence (0–1; higher = more likely genuine)
- `{type}_reason` -- character: plain-English explanation

**LLM plausibility columns** (`review_assignments`):
- `habitat_plausibility`, `geographic_plausibility`, `scope_plausibility` -- `"likely"` / `"possible"` / `"unlikely"` (higher = more plausible genuine detection)
- `contamination_risk` -- `"high"` / `"moderate"` / `"low"` (higher = more contamination risk)

Note: `{type}_score` (numeric) is NOT the same direction as `{type}_risk` (character). Score near 1.0 = low risk (real detection); score near 0.0 = high risk (contaminant). This asymmetry is intentional: scores are intermediate outputs for threshold-tuning; risk labels are the user-facing result. (`flag_contaminant()`'s score no longer reaches an exact 0.0/1.0 since Session 151's shrinkage fix -- see below.)

`review_assignments()` adds 8 structured LLM assessment columns (see below).

---

## Function Inventory

| Function | File | Status | Description |
|----------|------|--------|-------------|
| `.compute_contaminant_scores()` | `R/flag_contaminant.R` | Written | Internal: proportion-based control comparison algorithm |
| `flag_contaminant()` | `R/flag_contaminant.R` | Written | Compare read proportions between field samples and controls; `contaminant_type` param selects lab vs field vs positive control. **Session 151**: depth-weighted rates + Empirical Bayes shrinkage replace the old unweighted-mean/hard-0-1 formula; score documented as a ranked screening statistic, not a probability. **Session 152**: shrinkage denominator changed from sample count to read count (`prior_weight`, default `20`, now read-equivalent units) -- see "flag_contaminant() Design" below. **2026-07-24**: output columns renamed to the unified schema -- `observation_validity` (was `{contaminant_type}_score`, high=good, unchanged direction/math), `validity_flag` (was `{contaminant_type}_risk`; values now `"valid"`/`"questionable_{contaminant_type}"`/`"invalid_{contaminant_type}"`, was `"low"`/`"moderate"`/`"high"`), `validity_reason` (was `{contaminant_type}_reason`). Column NAMES no longer vary by `contaminant_type` -- the type now lives in `validity_flag`'s value instead. |
| `flag_handler()` | `R/flag_handler.R` | Written | Temporal proximity to start/end of sampling period; placeholder for camera trap handler artifacts. **Session 151**: optional `station_metadata` param anchors edges on real deploy/retrieve timestamps instead of the data's own min/max (opt-in, backward compatible; see "flag_handler() Design" below). **2026-07-24**: output columns renamed to the same unified schema as `flag_contaminant()` -- `observation_validity` (was `flag_handler_score`, high=good, unchanged direction/math), `validity_flag` (was `flag_handler`; values now `"valid"`/`"questionable_handling"`/`"invalid_handling"`, was `"likely"`/`"possible"`/`"unlikely"`), `validity_reason` (was `flag_handler_reason`). `edge_anchor_source` unchanged. |
| `.parse_datetimes()` | `R/flag_handler.R` | Written | Internal: auto-detect datetime format |
| `review_spatial_context()` | `R/review_spatial_context.R` | Written (2026-08-07) | Interactive click-through gadget (leaflet + miniUI + `shiny::paneViewer()`, matching `TaxaHabitat::review_spatial_flags()`'s pattern): taxon dropdown filterable by a plausibility column, a live GBIF density-tile map layer (`leaflet::addTiles()` with the density URL template -- pannable/zoomable, not a static snapshot), a sidebar with `check_gbif_tile_range()`/`compute_local_occurrence_distance()`/pre-supplied `inat_range` context, and an opt-in "Run AI Review" button (`review_assignments()`, the only billed step, never automatic). Server logic factored into internal `.build_spatial_context_server()` specifically so it's testable via `shiny::testServer()` -- standard browser automation hangs against a live Shiny session's persistent WebSocket (confirmed not a gadget bug via a direct `curl` check), so this is the real verification path for the reactive logic; a real bug (an unresolvable taxon name silently blanking the whole stats panel via `shiny::req()`'s propagating silent-stop) was caught this way before shipping. **2026-08-07, refined from first real click-through**: dropped an unneeded tile-opacity override (render GBIF's tiles as GBIF serves them) and toned down the occurrence-point styling so both layers stay readable together; iNat panel now always shows an explicit line when `inat_range` is supplied (real data or "no data for this taxon"), never silence; new `excluded_occurrence_data` param overlays GBIF records this study's own quality/outlier/institution filtering excluded (hollow red rings, distinct from kept points) -- reconstructable via a plain `anti_join` on `gbifID` between `raw_gbif` and a post-filter checkpoint, verified against real GreatLakes2023 data (530 real exclusions found). Not yet live-clicked-through in an actual RStudio session -- see this file's top session note. |
| `review_assignments()` | `R/review_assignments.R` | Written | LLM expert review: habitat, geography, scope, contaminant, alternatives. Default `taxa_per_call = 15` to avoid response truncation. `data_type` param ("eDNA"/"acoustic"/"image") switches contaminant guidance in LLM prompt. **2026-07-24**: gains `consensus_posterior_col`/`winner_prior_col`/`winner_rank_expanded_col`/`plausible_posteriors_col` (all optional, silently skipped when absent) -- when present, appends a compact pipeline-confidence/occurrence-prior/rank-expanded/candidate-weight annotation to each taxon's LLM prompt line, so the LLM's ecological judgment can be checked against the pipeline's own statistics. Also now prefers `df$consensus_OTU` (from `TaxaAssign::add_slash_taxon()`) for candidate-set labels when present, instead of always rebuilding independently -- closes a label-drift risk on downranked rows. **2026-08-07**: gains `dist_nearest_occupied_km_col`/`patch_diameter_km_col`/`beyond_buffer_col` (matching `check_gbif_tile_range()`) and `inat_in_range_col`/`inat_n_observations_col`/`inat_matched_name_col` (matching `TaxaFetch::check_inat_range()`) -- same optional/silently-skipped convention. Facts-only per-taxon annotation (e.g. `"GBIF: nearest occurrence ~41km away, patch ~0.9km across; iNat: in range, 1275 obs"`); a conditional GUIDELINES bullet (only when a batch has a spatial note) carries the interpretive caveats instead of pre-judging server-side -- see this file's top session note for why, and for the real *Gasterosteus gymnurus* case that motivated surfacing `matched_name` specifically. **2026-08-11:** return value gains `attr(result, "llm_prompts")` (named list, one entry per LLM batch call including retry sub-batches) -- see `inst/taxaflag_review_response.md`. |
| `.normalise_context()` | `R/review_assignments.R` | Written | Internal: normalise build_context() or named list to standard fields |
| `.build_review_prompt()` | `R/review_assignments.R` | Written | Internal: construct structured LLM prompt |
| `.parse_review_response()` | `R/review_assignments.R` | Written | Internal: parse + validate LLM JSON response; multi-strategy parser with truncated JSON recovery |
| `.recover_truncated_json()` | `R/review_assignments.R` | Written | Internal: salvage complete JSON objects from truncated LLM response |

| `add_posthoc_assessment()` | `R/add_posthoc_assessment.R` | Written | **Redesigned 2026-07-30, superseding everything below this row from Session 149 onward.** The old single-column `posthoc_assessment` (9 categories, `tiers`/`taxon_col`/`tier_col`/`finest_rank` params, including `"vague_rank"` and `"unsupported_rank"`) is entirely retired -- see this file's top session note. Now appends FIVE columns implementing two independent, orthogonal axes, reported for `primary_taxon` and `consensus_taxon` separately, neither gating the other: **Axis 1** (`primary_plausibility`/`consensus_plausibility`, "how expected is this taxon here?") -- `"expected"`/`"unexpected"`/`"unprecedented"`/`"not_modeled"`, driven by `winner_theta_col` (default `"winner_theta_mean"`) + `winner_record_col` (default `"winner_has_occurrence_record"`) at primary scope, `consensus_prior_col` (default `"consensus_prior"`) + `consensus_record_col` (default `"consensus_has_occurrence_record"`, 2026-07-30 new) at consensus scope, compared against `expected_theta_threshold` -- a REQUIRED named vector keyed by rank (`"species"` mandatory, `genus`/`family` optional; a rank absent from the vector gets `"not_modeled"`). `"unprecedented"` is driven by record presence (the `*_record_col`), never by a low threshold value -- a never-reported taxon and a genuine singleton can share the same numeric floor while meaning opposite things. **Axis 2** (`primary_discrimination`/`consensus_discrimination`, "could the evidence tell this taxon apart from a plausible relative?") -- `"discriminating"`/`"weak"`/`"indistinguishable"`/`"not_modeled"`, driven by `primary_confusion_risk_col`/`consensus_confusion_risk_col` against `discriminating_threshold`/`indistinguishable_threshold` (default 0.05/0.5) -- this is the direct successor to the old `confusion_risk_flag` column (now two rank-scoped columns instead of one). `domestic_prior_caveat` (logical) is unchanged in purpose (Session 149) but now reads `primary_plausibility` instead of the retired tier lookup. See this file's top session note for the full real-data verification record. |

| `compute_local_occurrence_distance()` | `R/compute_local_occurrence_distance.R` | Written (2026-08-06), `date_col` added (2026-08-21) | Free (no network call): geodesic distance from a query point to the nearest already-fetched occurrence of a taxon in a supplied `occurrence_data` frame (e.g. a workflow's own `all_occurrences`/`occurrences_clean`). `n_local_records = 0` is exactly the situation behind an "unprecedented" Axis 1 call -- answers *why*, using data already in hand. Scope-limited to whatever bbox the caller's occurrence data covers. **2026-08-21:** new optional `date_col` param surfaces the matched nearest record's raw date/year value as `nearest_date` -- built for `TaxaExpect::generate_regional_proximity_evidence()`, which uses record age to size confidence independently of distance. `NULL` default, fully backward compatible. |
| `check_gbif_tile_range()` | `R/check_gbif_tile_range.R` | Written (2026-08-06), escalation + km output added (2026-08-07) | Downloads GBIF's occurrence-density map tiles around a point and reads presence/absence from the alpha channel only (never decodes the colour ramp). Reports `point_occupied`, `dist_nearest_occupied_km`, `patch_area_km2`/`patch_diameter_km` (real-world-scaled; `patch_size_px`/`patch_size_capped` kept as the underlying pixel count, capped at 15 growth iterations for bounded latency -- a widespread/capped patch is itself the "not a rarity report" signal). **2026-08-07**: `escalate`/`min_zoom` params (default `TRUE`/`0L`) widen the search to coarser zoom levels when nothing is found at the requested zoom, so a genuinely-far species reports a real (if coarse) distance instead of `NA` -- `zoom_used`/`escalated` expose what actually happened. Complements the function above with the global range context a bbox-limited local fetch can't give, at the cost of a handful of tile downloads (more if escalation fires). Does not distinguish data error from genuine rarity -- see `TaxaFetch::check_geographic_outliers()` for that separate, prior question. Requires `httr2`/`png` (Suggests, hard-stops if missing). |

**Dropped (Session 62):** `flag_allochthonous()` and `flag_taxonomic_scope()` -- absorbed
into `review_assignments()`. One LLM call covers habitat, geography, scope, contaminant
screening, and alternative suggestions more efficiently than separate functions.

**Dropped (Session 63):** `combine_flags()` and `flag_detections()` -- users should
filter on individual flag columns directly. A wrapper that guesses parameters is more
frustrating than helpful; workflow scripts are more transparent.

---

## flag_contaminant() Design

**Input:** Long-format data frame (one row per sample x taxon) with read counts.
**Output:** Per-taxon summary (one row per taxon), sorted by score.

**Key parameters:**
- `event_col` -- column identifying L1 collection events (default `"event_id"`)
- `control_samples` -- character vector of event IDs that are controls (blanks or positive controls)
- `sample_type_col` / `control_types` -- alternative: identify controls via a column
- `exclude_samples` -- remove samples from both control and field calculations
- `contaminant_type` -- controls output column names (`{contaminant_type}_risk`, `{contaminant_type}_score`, `{contaminant_type}_reason`)
- `score_thresholds` -- numeric(2), default `c(0.5, 0.9)`
- `prior_weight` -- numeric, default `20` (**Session 152**; read-equivalent units --
  previously sample-equivalent units, default `2`, through Session 151). Shrinkage
  strength for the final ratio toward 0.5; `0` disables shrinkage.

**Algorithm:** `.compute_contaminant_scores()` (**Session 152** -- see that function's
roxygen "Depth-weighting and shrinkage" and "Reads, not samples, as the shrinkage
denominator" sections for the full real-data motivation, including three rejected
alternatives):
1. Depth-weighted rate per group: `field_rate`/`control_rate` = `sum(taxon reads in group) /
   sum(total reads across samples in that group)` -- a proportion from 500,000 reads now
   counts far more than one from 50. (The old unweighted per-sample-proportion mean is
   still computed as `mean_prop_field`/`mean_prop_control` for reference, but no longer
   drives the score.)
2. Raw ratio: `field_rate / (field_rate + control_rate)`.
3. Shrunk toward 0.5 (maximally uncertain) with weight `n_reads_total / (n_reads_total +
   prior_weight)`, where `n_reads_total` = total READS (field + control combined) for
   that taxon -- same Empirical Bayes form used throughout this ecosystem (e.g.
   `TaxaLikely::train_likelihood_model()`'s per-species shrinkage), but measured in
   reads, not samples (**Session 152** -- Session 151 used sample count
   `n_field_present + n_controls_present`, which conflated a 2-read detection with a
   500,000-read detection whenever both came from one sample; see the CLAUDE.md session
   note above for the real-data evidence and the three alternatives tried and rejected
   before landing here). Applied to the FINAL ratio, not to `field_rate`/`control_rate`
   individually toward a shared reference rate -- an earlier design shrunk each rate
   toward the taxon's own pooled (field+control) rate, which let a taxon's own (usually
   much larger) field read volume leak into its control-side prior and systematically
   understated genuinely clean taxa's scores whenever field depth dominated control
   depth. Caught by actually running the test suite, not by review alone.
4. Taxa absent from controls no longer get an automatic exact 1.0 -- with little total
   read support, real absence is still real evidence, but shrinkage keeps the score
   below 1.0 in proportion to how little total evidence supports it. A taxon with
   substantial read support (even from a single sample) converges close to its raw ratio.
Score is documented as a ranked screening statistic, not a calibrated probability
(the roxygen previously called it one). New `n_reads_total` output column (Session 152)
exposes the read count that now drives shrinkage; `n_field_present`/`n_controls_present`/
`n_controls_total` remain, informational only.

---

## flag_handler() Design

**Input:** Data frame with a datetime column and optionally a grouping column.
**Output:** Input data frame with 4 columns appended (per-row flags; **Session 151** adds
`edge_anchor_source`).

**Key parameters:**
- `datetime_col` -- auto-parsed via `.parse_datetimes()`
- `group_col` -- min/max computed per group (e.g., camera station)
- `interval_minutes` -- flag window from edges
- `handler_taxa` -- optional whitelist (e.g., "Homo sapiens")
- `station_metadata` / `deploy_col` / `retrieve_col` -- **Session 151**, ecosystem
  soundness-review item 16. Optional data frame, one row per `group_col` value, with real
  deploy/retrieve timestamps -- the same "external attribute lookup table keyed by a
  sample/event identifier" pattern already used elsewhere in this ecosystem (e.g.
  `TaxaMatch::join_event_site_metadata()`, the `BLANKS_MARCH`/`BLANKS_AUG` convention).
  When supplied, anchors group edges on the REAL deployment window instead of the
  data's own detection min/max -- fixes the core flaw the review flagged: without this,
  the very first and last genuine wildlife detection at a station is always scored
  maximally suspect, purely because the edge is defined by the data itself, not because a
  handler was ever actually present. A group missing from `station_metadata` (or with an
  unparseable timestamp) falls back to the data-derived min/max for that group only, with
  a `warning()` naming it. Fully backward compatible -- default `NULL`, no behavior change
  for existing callers; every existing test (36) passes unchanged.

**Score:** `min(minutes_to_start, minutes_to_end) / interval_minutes`, clamped [0, 1],
computed against `group_min`/`group_max` -- real deploy/retrieve times when
`station_metadata` covers that group, data-derived min/max otherwise (see
`edge_anchor_source`).

**Still genuinely unfixed (Session 151, honestly recorded, not solved):** when
`station_metadata` is NOT supplied (still the default, and the only mode any real caller
has ever used -- see below), `handler_taxa` remains the sole real protection, exactly as
before this session; the structural bias itself is only fixed when a user actually has and
supplies a real deployment log. No live caller in the monorepo does yet -- `flag_handler()`
still has only one real call site anywhere: `vignettes/quality-flagging.Rmd`'s own example
(now updated to demonstrate `station_metadata`, Session 151). This was the lowest-priority
of the review's 16 H-priority items for exactly this reason (its own row: "no live caller
found yet, which is the only thing keeping this from being worse").

---

## review_assignments() Output Columns

| Column | Type | Values | What it captures |
|--------|------|--------|-----------------|
| `habitat_plausibility` | character | likely / possible / unlikely | Does this taxon live in this habitat? |
| `geographic_plausibility` | character | likely / possible / unlikely | Is this taxon found in this region? |
| `scope_plausibility` | character | likely / possible / unlikely | Target group match (only if `target_group` supplied) |
| `contamination_risk` | character | low / moderate / high | Common lab/field contaminant? |
| `review_alternatives` | character | comma-separated | Plausible alternatives at same rank (when taxon is implausible) |
| `review_lower_hypotheses` | character | comma-separated | Finer-rank taxa expected here (when consensus is coarse-ranked) |
| `review_confidence` | character | high / moderate / low | LLM's overall confidence |
| `review_comment` | character | free text | Anything structured fields don't capture |

**Key distinction:**
- `review_alternatives` = "you might have the wrong taxon" (implausible taxon, plausible relative)
- `review_lower_hypotheses` = "you have the right group, could narrow it down" (coarse consensus, likely species)

**Context input:** Accepts either `build_context()` output (data frame with `ecoregion`, `main_habitat`) or a simple named list (`list(geography = ..., habitat = ...)`).

---

## Workflow Scripts

| File | Purpose |
|------|---------|
| `inst/contaminant_workflow.R` | End-to-end: wide CSV -> pivot -> 3 flag_contaminant() calls (extraction, PCR, positive control) -> combined summary |
| `inst/review_assignments_workflow.R` | LLM review with test consensus data for Palmyra Atoll |

---

## Test Coverage

| File | Functions covered | Notes |
|---|---|---|
| test-flag_contaminant.R | `flag_contaminant()` | Fully offline; covers all risk levels, custom thresholds, positive controls; uses Session 101 vocabulary (low/moderate/high) |
| test-flag_handler.R | `flag_handler()` | Fully offline; covers edge scoring, handler_taxa filtering |
| test-review_spatial_context.R | `review_spatial_context()` / `.build_spatial_context_server()` | 2026-08-07, 16 tests via `shiny::testServer()` (not a browser -- see this file's top session note for why). Covers: GBIF distance/patch display, `beyond_buffer` phrasing, the unresolvable-taxon-name fix (the real bug this suite caught), iNat mismatch flagging correctly firing/not-firing, the local/free panel present-with and absent-without `occurrence_data`, `output$map` rendering without error, the AI-review button's success path AND its real graceful-NA-degradation-on-LLM-failure path (not a thrown error -- `review_assignments()` already catches that), and `.resolve_gbif_taxon_key()`'s real-response-shape parsing. Network-calling functions mocked at the TaxaFlag namespace boundary via `local_mocked_bindings()`, matching `test-check_gbif_tile_range.R`'s convention. The gadget's UI shell (dropdown population, conditional AI-button visibility) is exercised only via a manual raw-HTML fetch during development, not an automated test -- matching this ecosystem's established precedent for fully interactive gadgets. |
| test-review_assignments.R | `review_assignments()` | LLM mocked; covers all 8 output columns, partial response recovery, Session 101 column names/values. **2026-08-07**: 14 new tests for the spatial-context wiring, using a prompt-*capturing* stub (not just canned output, since this feature is purely prompt-side) -- correct per-taxon GBIF/iNat alignment against the real 3-species scenario, the name-mismatch annotation firing/not-firing, `beyond_buffer` phrasing, the conditional GUIDELINES bullet appearing only when warranted, each `_col` param's `NULL` opt-out, and `.summarise_spatial_context()`'s `NULL`-when-nothing-present case. |
| test-report_flags.R | `report_flags()` | Fully offline |
| test-add_posthoc_assessment.R | `add_posthoc_assessment()` | Rewritten 2026-07-30 for the Axis 1/Axis 2 redesign (62 tests) -- the old `posthoc_assessment`-category tests are gone with the column. Covers: Axis 1 expected/unexpected/unprecedented/not_modeled at both scopes, the load-bearing "no-record-but-high-theta is unprecedented" vs "singleton-at-floor is not" pin, rank-relative `expected_theta_threshold` (species-only vs species+genus+family), `consensus_has_occurrence_record`-driven consensus scope (incl. the regression test for the real 100%-unprecedented production bug), Axis 2 discriminating/weak/indistinguishable/not_modeled at both scopes, `domestic_prior_caveat`, NA-when-columns-absent, input validation. |
| test-compute_local_occurrence_distance.R | `compute_local_occurrence_distance()` | 2026-08-06, fully offline. Covers: nearest-of-several-records selection, genuinely-absent taxon (0/NA), NA-coordinate rows excluded from the count, multi-taxon batch calls, duplicate-name collapsing, custom column names, haversine symmetry/zero-distance sanity checks, input validation. |
| test-check_gbif_tile_range.R | `check_gbif_tile_range()` | 2026-08-06, escalation tests added 2026-08-07. Mocks only `.fetch_gbif_tile_alpha()` (plus one `httr2::req_perform()` mock via `httr2::response()` for the real HTTP-204-empty-tile case) so tile math/stitching/distance/patch-growth/escalation all run for real underneath -- same strategy as `TaxaFetch::test-check_geographic_outliers.R`. Covers: point-occupied/zero-distance (incl. patch_area_km2/patch_diameter_km unit checks), nearby-but-not-coincident distance (exact pixel-to-km check), a zoom-aware mock confirming escalation stops at the FIRST zoom that finds something and does not continue past it, `min_zoom`-exhausted `beyond_buffer` (with `zoom_used` NA but `resolution_km_per_px` still reported at the finest attempted zoom), `escalate = FALSE`'s single-zoom opt-out, the real HTTP-204 empty-tile behavior, a fully-occupied mosaic hitting the growth cap, `buffer_px` rounding to whole tiles, Mercator resolution monotonicity, a hand-computed zoom-0 tile-pixel case, `.dilate8()`'s single-seed neighbourhood, input validation (incl. the new `escalate`/`min_zoom` checks). Real end-to-end verification against live GBIF tiles (round goby at Burns Harbor, Sahara negative control, American Robin patch-cap timing, and -- 2026-08-07 -- two real European species that only resolve via escalation) was done manually during development -- see this file's own top session note for the concrete numbers. |

---

## Session Notes

**Session 149 (2026-07-10): add_posthoc_assessment() domestic-species caveat**

Third item on the ecosystem statistical soundness review's H-priority walk-through
(`ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md`) was
`TaxaAssign::join_priors()`'s dark-diversity floor treating domestic/synanthropic species
as exchangeable with genuinely unmodelled wild species -- the deferred design note from
[[project_taxaflag_domestic_species_floor_note]] (single-observation-pipeline work,
2026-07-03), never implemented. The user resolved where this belongs across two
functions rather than one: (1) priors -- a user who knows their study includes domestic
species should augment their occurrence data before training, and TaxaID's job is just
to document that clearly (a note is sufficient; not a code fix); (2) likelihoods --
iNaturalist image recognition and NCBI BLAST already handle domestic-species
classification fine, so the likelihood side needs no change; (3) the one thing worth
building is a small, narrow flag in TaxaFlag for the specific *contrast* -- a strong
likelihood for a domestic species next to a low prior, when that prior came from an
unaugmented wild-species database.

**Implementation:** `add_posthoc_assessment()` gains two new optional params:
- `domestic_taxa = NULL` -- character vector of taxon names the caller considers
  domestic/synanthropic for their study system. No built-in default list (matches
  `flag_handler()`'s `handler_taxa = NULL` convention) -- what counts as "domestic" is
  study-system-specific, so a curated list baked into the package would be either
  incomplete or presumptuous.
- `domestic_prior_source = c("wild", "augmented")` -- default `"wild"`. When a row's
  `consensus_taxon` is in `domestic_taxa` AND its likelihood is above
  `likelihood_threshold` AND it landed in the tier2/tier3_undetected branch (which would
  otherwise emit `"unexpected"`/`"unprecedented"`), the assessment is re-labelled
  `"domestic_prior_caveat"` instead -- signalling "trust the ID, question the rarity"
  rather than a generic low-plausibility flag. Passing `domestic_prior_source =
  "augmented"` disables this entirely, for pipelines that already incorporated known
  local domestic presence into their priors (the low tier is then genuinely
  informative, not a database artifact).

Deliberately narrow: only fires on the strong-likelihood + low-tier combination (a
low-likelihood domestic-species call stays `"suspect"`, correctly -- the caveat is about
the *prior*, not the identification), never invents or elevates a prior itself, and is
opt-in (`NULL` default, zero behavior change for existing callers).

**Companion prior-side documentation fix** (no code change, per the user's steer that a
note is sufficient there): `TaxaExpect::generate_undetected_diversity()` gained a new
`@section Domestic/synanthropic species` explaining the root cause (GBIF/iNat under-index
captive organisms) at the actual point where the floor value is computed, and recommending
occurrence-data augmentation before training as the fix; `TaxaAssign::join_priors()`'s
"Dark diversity fallback" section cross-references it. Both are pure roxygen additions --
`devtools::test()` unchanged (TaxaExpect 383/383, TaxaAssign 544/544), `devtools::check()`
clean on both.

7 new tests added to `test-add_posthoc_assessment.R` covering: default-off behavior,
tier2 and tier3_undetected re-labelling, the low-likelihood non-re-labelling case, no
effect on non-domestic taxa, the `"augmented"` opt-out, and input validation.
`devtools::test()`: 159/159 passing, 0 failures. `devtools::check()`: 0 errors, 0
warnings, 1 pre-existing NOTE (clock-check artifact, unrelated).

Sessions 60–74 archived in ecosystem_docs/session_notes/TaxaFlag_sessions.md.

**Session 79 (2026-05-20)**
- `sample_col` param → `event_col` in `flag_contaminant()` (this param identifies L1 collection
  events, not L2 observations; default changed from `"sample_id"` to `"event_id"`)
- `sample_id` → `observation_id` in all L2 references across R source, tests, vignettes, inst/, README
- `event_col` documented in CLAUDE.md flag_contaminant() design section
- 126 tests passing (2 warnings — pre-existing)

**Session 80 (2026-05-20)**
- GitHub public monorepo created at github.com/kdlafferty/TaxaID; no package-specific changes.

**Session 82 (2026-05-21)**
- License changed MIT → CC0 per USGS policy. DESCRIPTION updated; per-package LICENSE stub removed.
- TaxaTools moved from Suggests to Imports (used unconditionally by `report_flags()` and
  as default in `review_assignments()`).

**Sessions 83–85 (2026-05-21 to 2026-05-23)**
- No TaxaFlag-specific changes. Ecosystem: `call_api()` generic dispatcher (TaxaTools), WERC
  review integration. See TaxaID/CLAUDE.md for full log.

**Session 86 (2026-05-23)**
- `review_assignments()`: `llm_fn` fallback updated from `TaxaTools::call_anthropic_api` to
  `TaxaTools::call_api`. Clears TODO from Sessions 82/85.
- `DISCLAIMER.md` + `LICENSE.md` deleted from package root (centralised at TaxaID/ root).
- Disclaimer section removed from `README.md`.

**Session 89 (2026-05-27)**
- `review_assignments()`: `data_type` param added (`"eDNA"` default / `"acoustic"` / `"image"`). Controls contaminant guidance text in the LLM prompt: eDNA (common lab contaminants: Homo sapiens, Bos taurus, etc.), acoustic (human vocalizations + handler noise near recording equipment), image (handler presence during camera setup/teardown). Also switches the JSON example `comment` value to match the data type. Implemented in `.build_review_prompt()` via `switch(data_type, ...)`.

**Session 101 (2026-06-06): Unified flag vocabulary**
- Renamed `review_assignments()` output columns: `review_habitat` → `habitat_plausibility`, `review_geography` → `geographic_plausibility`, `review_scope` → `scope_plausibility`, `review_contaminant` → `contamination_risk`.
- Updated values: plausibility columns use `"likely"/"possible"/"unlikely"` (positive = plausible genuine detection); `contamination_risk` uses `"low"/"moderate"/"high"` (positive = more risk).
- Renamed `flag_contaminant()` output columns: `flag_{type}` → `{type}_risk`, `flag_{type}_score` → `{type}_score`, `flag_{type}_reason` → `{type}_reason`. Values changed: `"likely"` → `"low"`, `"possible"` → `"moderate"`, `"unlikely"` → `"high"` (direction flipped — old "likely" meant real detection; new "low" risk means real detection; both mean same thing).
- Updated Flag Column Convention in CLAUDE.md; updated workflows, tests, and prompts throughout.

**Session 104 (2026-06-08): add_posthoc_assessment() + NA-rank bug fix**
- `add_posthoc_assessment()` added: single categorical column `posthoc_assessment` combining tier × likelihood into 7 categories (`sensible`, `limited_evidence`, `unexpected`, `suspect`, `unprecedented`, `vague_rank`, `modeled`). Replaces rejected `flag_prior_mismatch()` design.
- Bug fix: `vague_rank` mask was `!is.na(rank) & rank != finest_rank`; NA rank fell through to active path, getting treated as tier2 → "suspect". Fixed to `is.na(rank) | rank != finest_rank` so NA-rank rows correctly receive "vague_rank".
- `flag_prior_mismatch.R` and associated man/tests deleted.
- PtConceptionWorkflow_12S.R and _18S.R updated to use `add_posthoc_assessment()`.

**Session 123 (2026-07-01): Layer-1 workflow script**
- `inst/workflows/flag_detections_workflow.R` added — the FINAL package in the tutorial
  chain (TaxaFetch → TaxaHabitat → TaxaExpect → TaxaAssign → TaxaFlag). Unlike the four
  upstream scripts, both live steps run on 100% real continuity data with no synthetic
  bootstrapping: `review_assignments()` reviews TaxaAssign's real `taxaassign_consensus`
  (irreducible candidate sets via `plausible_taxa_col`), and `add_posthoc_assessment()` uses
  the real `taxaexpect_priors` directly as `tiers` (it only needs `taxon_name` + `model_tier`,
  both already present). `flag_contaminant()` is documented with its full signature and
  algorithm but not run live — it needs lab read-count data (sample × taxon, with blanks) that
  a GBIF-occurrence-based tutorial chain has no honest way to fabricate.
- Live-tested with a real Anthropic LLM call as part of a full 5-package chain (0 errors,
  sensible output — see `ecosystem_docs/LAYER1_WORKFLOWS.md`). One real bug fixed:
  `review_assignments(irreducible_only = TRUE)` hard-errors if zero rows qualify as
  irreducible, which is the *expected* outcome (not bad luck) for TaxaAssign's small
  synthetic species pool — fixed with an adaptive fallback to `irreducible_only = FALSE`.
- Also surfaced (and documented in `TaxaID/CLAUDE.md`'s Known R Footguns): `review_assignments()`
  shares the same `.resolve_llm_fn()` default-degrades-silently issue as TaxaAssign's LLM
  pathway — must pass `llm_fn` explicitly under this ecosystem's fully-namespaced calling style.
