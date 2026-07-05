# ==============================================================================
# explore_spatial_grouping_session134b.R
# Exploration script for the Session 134b spatial-grouping rework.
# NOT a Layer-1 workflow, NOT added to any package -- just a scratch script to
# poke at the new pieces interactively. Safe to delete once you're done.
#
# MUST be run in an interactive RStudio session (not Rscript/batch) -- the
# gadget steps call TaxaTools::define_search_polygon(), which requires
# interactive() == TRUE.
#
# Before running: see the "To apply these changes" block at the end of the
# chat message this came with. Four packages changed (TaxaTools, TaxaFetch,
# TaxaMatch, TaxaAssign) so use the install_all.R path, not a single-package
# install.
#
# UX NOTE (fixed after real live-testing): RStudio's dialogViewer() was found
# to silently break the Done button for this specific leaflet-based gadget
# (confirmed reproducible, root-caused, and fixed -- see TaxaTools/CLAUDE.md's
# Session 134b note). define_search_polygon() now defaults to
# shiny::paneViewer(minHeight = 500) instead -- each gadget step opens in
# RStudio's own Viewer pane, matching this ecosystem's other mapping gadgets
# (TaxaHabitat::review_spatial_flags(), TaxaExpect::plot_theta_map_interactive())
# for one consistent map-interaction style. Click Done in the Viewer pane;
# control returns to R automatically.
# ==============================================================================

library(TaxaTools)
library(TaxaMatch)
library(TaxaAssign)

# ------------------------------------------------------------------------------
# 1. Synthetic site data: two real clusters + two far-flung outliers
# ------------------------------------------------------------------------------
# Cluster "SB": 3 observations around Santa Barbara
# Cluster "MB": 2 observations around Monterey Bay
# Outliers: San Diego and Seattle -- too far from anything to belong to a group

match_df <- data.frame(
  observation_id = paste0("obs", 1:7),
  taxon_name      = "placeholder",
  lat = c(34.40, 34.41, 34.39,   36.60, 36.61,   32.72,   47.61),
  lng = c(-119.86, -119.85, -119.87,  -121.90, -121.89,  -117.16,  -122.33),
  observed_on = "2026-07-04",
  stringsAsFactors = FALSE
)

# ------------------------------------------------------------------------------
# 2. build_site_table(): confirm the new spatial_group_id/spatial_group_N defaults
# ------------------------------------------------------------------------------
# Every row should come back with spatial_group_id == its own observation_id,
# and spatial_group_N == 1 -- "everyone is their own singleton group" until you
# actually group something.

sites <- build_site_table(match_df)
print(sites)
stopifnot(all(sites$spatial_group_id == sites$observation_id))
stopifnot(all(sites$spatial_group_N == 1L))

# ------------------------------------------------------------------------------
# 3. group_observations_by_bbox(): the interactive gadget loop
# ------------------------------------------------------------------------------
# What to try when the map opens:
#   - The initial box should already enclose ALL 7 points (the "default
#     starting polygon encloses everything" guarantee from Session 134b).
#   - Shrink/drag it down around the 3 Santa Barbara points only, click Done.
#   - The gadget reopens, re-centred on the 4 remaining points (MB + 2
#     outliers). Draw a box around the 2 Monterey Bay points, click Done.
#   - The gadget reopens again, centred on the 2 outliers (San Diego,
#     Seattle -- far apart). Click Cancel (title-bar X) here without drawing
#     anything -- you're done grouping, they should stay singletons.
#   - You should now see the END-OF-LOOP REVIEW STEP in the R console:
#       1. spatial_group_1 -- 3 observation(s)
#       2. spatial_group_2 -- 2 observation(s)
#     Try each of these before finalizing:
#       a) Enter "1" to reopen group 1's box -- reshape it slightly, click
#          Done. Confirm the review list reappears (not finalized yet).
#       b) Enter "delete 2" -- confirm the message says group 2 was deleted.
#          The review list should now show only 1 group.
#       c) Press Enter (blank) to finalize.
#
# IMPORTANT: run the next line BY ITSELF (place the cursor on it and press
# Cmd/Ctrl+Enter once -- do not select it together with the print() line
# below). The review step reads console input with readline(); if you submit
# both lines together, RStudio queues the print() line as pending console
# text and readline() will silently consume it as its answer instead of
# waiting for you to type one -- this can finalize early or otherwise produce
# a result that doesn't match what you actually drew. Watch the console for
# the "box N captured..." progress messages and the review prompt, answer it,
# and only then run the print() line separately.

grouped <- group_observations_by_bbox(sites)

# Run this separately, after the console above shows the review step finished:
print(grouped[, c("observation_id", "lat", "lon", "spatial_group_id", "spatial_group_N")])

# Expect (if you followed the script above, including the delete-group-2 step):
#   obs1/obs2/obs3  -> spatial_group_1, spatial_group_N = 3
#   obs4/obs5       -> back to their own observation_id (MB group was deleted
#                      in the review step), spatial_group_N = 1
#   obs6/obs7       -> their own observation_id, spatial_group_N = 1

# ------------------------------------------------------------------------------
# 4. Last-drawn-wins overlap rule
# ------------------------------------------------------------------------------
# Run group_observations_by_bbox() again on a fresh `sites` table and this
# time deliberately draw two OVERLAPPING boxes that both cover obs4 (Monterey
# Bay) -- e.g. first a big box covering obs4+obs5+obs6, click Done, then a
# second, smaller box covering just obs4+obs5, click Done, then Cancel and
# finalize the review step with Enter.
# Expected: a warning naming obs4 (and obs5) as ambiguous, and both end up in
# the SECOND (most recently drawn) group, not the first.
#
# Again: run the group_observations_by_bbox() line by itself, wait for the
# review step to finish in the console, then run the print() line separately.

sites2   <- build_site_table(match_df)
grouped2 <- group_observations_by_bbox(sites2)

# Run this separately, after the console above shows the review step finished:
print(grouped2[, c("observation_id", "spatial_group_id", "spatial_group_N")])

# ------------------------------------------------------------------------------
# 5. assign_spatial_group(): manual assignment + the collision guard
# ------------------------------------------------------------------------------
# No gadget needed here -- purely programmatic.

sites3 <- build_site_table(match_df)

# Say you already know from field metadata that obs6 (San Diego) and obs7
# (Seattle) should NOT be grouped (they're real outliers), but you DO know
# obs1 and obs4 were actually collected as part of the same transect, despite
# being far apart on the map (e.g. a towed sensor). Group them manually:
manual <- assign_spatial_group(sites3, c("obs1", "obs4"), "transect_A")
print(manual[, c("observation_id", "spatial_group_id", "spatial_group_N")])
stopifnot(manual$spatial_group_N[manual$observation_id == "obs1"] == 2L)

# Now try the collision guard: "transect_A" is already used by obs1/obs4.
# Trying to hand it to obs2 WITHOUT including obs1/obs4 in the call should
# fail loudly rather than silently expanding the group:
tryCatch(
  assign_spatial_group(manual, "obs2", "transect_A"),
  error = function(e) message("Got the expected error: ", conditionMessage(e))
)

# To actually merge obs2 into transect_A, include everyone you want in it:
merged <- assign_spatial_group(manual, c("obs1", "obs2", "obs4"), "transect_A")
print(merged[, c("observation_id", "spatial_group_id", "spatial_group_N")])
stopifnot(merged$spatial_group_N[merged$observation_id == "obs1"] == 3L)

# ------------------------------------------------------------------------------
# 6. Bonus: TaxaTools::define_search_polygon() directly, with group coloring
# ------------------------------------------------------------------------------
# This is the new group_col param -- draw any box (content doesn't matter),
# but check the map BEFORE you draw: obs1/obs2/obs4 (transect_A) should render
# in one color and obs3/obs5/obs6/obs7 each in their own, per
# `merged$spatial_group_id`, with a legend in the bottom-right corner.

points_df <- merged
points_df$lng <- points_df$lon  # define_search_polygon()'s points arg wants lat/lng

TaxaTools::define_search_polygon(
  lat = 36.0, lon = -120.0, radius_deg = 8,
  points    = points_df,
  group_col = "spatial_group_id"
)

# Reopening a previously drawn polygon (init_polygon), instead of a fresh square:
first_box <- TaxaTools::define_search_polygon(lat = 36.0, lon = -120.0, radius_deg = 8)
TaxaTools::define_search_polygon(init_polygon = first_box)

# ------------------------------------------------------------------------------
# 7. Bonus: spatial_group_map feeding TaxaAssign::update_prior_from_consensus()
# ------------------------------------------------------------------------------
# Confirms the multi-member-vs-singleton eligibility check still works with
# the new default-to-observation_id shape (no "spatial_group_<n>" string
# required for it to correctly treat singletons as ineligible).

spatial_group_map <- merged[, c("observation_id", "spatial_group_id")]
print(table(spatial_group_map$spatial_group_id))
# transect_A should show 3; every other spatial_group_id should show 1 --
# those 1s are what update_prior_from_consensus(spatial_group_map = ...)
# should skip.
