# ==============================================================================
# extra_functions_review_inputs.R
# TaxaTools -- small, ready-to-run inputs for functions written AFTER this
# package's formal code review (reviewed 2026-06-27)
#
# PURPOSE
# -------
# TaxaTools/inst/taxatools_review.Rmd + taxatools_review_response.md record the
# 2026-06-27 code + domain review. Six functions were written after that
# review closed and so have never had a reviewer-facing runnable example:
#   - .last_classification_rank()  (internal, R/verify_taxon_names.R)
#   - .pts_to_wkt() / .wkt_to_pts() (internal, R/define_search_polygon.R)
#   - define_search_polygon()      (exported, R/define_search_polygon.R)
#   - escalate_taxonomic_rank()    (exported, R/escalate_taxonomic_rank.R)
#   - resolve_barcode_primers()    (exported, R/barcode_utils.R)
# This file gives each one a small, concrete, ready-to-run section, in the
# same style as TaxaLikely/inst/review_function_inputs.R (this whole
# ecosystem's established convention for reviewer-facing runnable examples).
#
# TRIPLE-COLON ACCESS TO INTERNAL (.-PREFIXED) FUNCTIONS IS EXPECTED HERE,
# NOT A BUG. Three of the six functions above are internal (@noRd, not
# exported) -- a normal source install (devtools::install()/load_all()) still
# makes every internal function reachable via TaxaTools:::.function_name(),
# same as any other R package. Reviewers should expect and use this; it is
# not a sign the function should have been exported.
#
# ONE FUNCTION -- define_search_polygon() -- CANNOT BE EXERCISED HERE AT ALL.
# It is a genuine interactive Shiny gadget (miniUI + leaflet map) that opens a
# live viewer pane and blocks waiting for a real mouse click on Done/Cancel.
# See TaxaTools/CLAUDE.md's "Known R Footguns" entry on dialogViewer() vs.
# paneViewer() for this exact gadget's own documented interactive-viewer
# quirk. Its section below deliberately does NOT fabricate a harness --  it
# states the limitation plainly and points the reviewer at calling the
# function directly in their own interactive RStudio session instead.
#
# Inputs are pulled from three sources, cheapest first:
#   1. Existing testthat fixtures reused verbatim -- Section 2's
#      .pts_to_wkt()/.wkt_to_pts() inputs are lifted directly from
#      tests/testthat/test-define_search_polygon.R.
#   2. Existing roxygen @examples -- escalate_taxonomic_rank()'s own \dontrun
#      example (Rhacochilus -> family Embiotocidae) is a real, previously
#      live-verified case (see TaxaTools/CLAUDE.md's Session 137 note); this
#      file uses the same real-genus convention this ecosystem's own
#      TaxaLikely/inst/review_function_inputs.R establishes (small, common,
#      well-referenced genera -- Fundulus), rather than re-deriving a new
#      example from scratch.
#   3. New small synthetic inputs constructed for this file where neither of
#      the above existed -- Section 1's .last_classification_rank() input
#      (no existing test file covers it) and Section 4's
#      resolve_barcode_primers() input (its own existing tests already cover
#      this exact call; reused here for consistency with those tests).
#
# REQUIRES tags (read before running a section):
#   OFFLINE        -- pure function, no network, no credentials
#   NETWORK        -- hits a public API (NCBI via rentrez/xml2, or the Global
#                     Names Verifier API), no credentials needed; scoped to a
#                     single small, well-referenced genus (Fundulus) so it
#                     stays fast, matching this ecosystem's own established
#                     NETWORK-section convention
#   INTERACTIVE, CANNOT BE RUN HERE -- a genuine Shiny/miniUI/leaflet gadget;
#                     see the note above and that section's own comment
#
# NON-DETERMINISM NOTE: the one NETWORK section below hits a real, live NCBI
# taxonomy service. The exact classification path returned can in principle
# drift over time as NCBI's own taxonomy is revised -- that is expected and
# not a bug, matching the same note in TaxaLikely's own review_function_
# inputs.R for its own NETWORK sections.
# ==============================================================================

#devtools::load_all()   # or: library(TaxaTools)
library(TaxaTools)


# ==============================================================================
# SECTION 1 -- verify_taxon_names.R internal helper
# .last_classification_rank()
# ==============================================================================

## ---- .last_classification_rank() ---- OFFLINE -------------------------------
# Pure string parser: given a pipe-delimited classification_ranks string (the
# exact shape verify_taxon_names() itself builds from either the Global Names
# Verifier API's classificationRanks field or NCBI's own lineage XML), returns
# the LAST (finest) rank actually present -- the rank a match resolved AT, not
# whatever rank the original query name implied. New synthetic input (no
# existing fixture covers this internal helper directly): a genus-only match,
# the exact real-world case this function exists to report correctly (see its
# own roxygen -- a species-level query that only resolves to genus).
genus_only_ranks <- "kingdom|phylum|class|order|family|genus"
TaxaTools:::.last_classification_rank(genus_only_ranks)   # "genus"

# A full species-level match, for contrast.
species_ranks <- "kingdom|phylum|class|order|family|genus|species"
TaxaTools:::.last_classification_rank(species_ranks)      # "species"

# Edge cases the function is documented to handle: NA and an empty string
# both degrade to NA_character_ rather than erroring.
TaxaTools:::.last_classification_rank(NA_character_)      # NA
TaxaTools:::.last_classification_rank("")                 # NA


# ==============================================================================
# SECTION 2 -- define_search_polygon.R internal helpers
# .pts_to_wkt() / .wkt_to_pts()
# ==============================================================================

## ---- .pts_to_wkt() ---- OFFLINE ----------------------------------------------
# Fixture reused verbatim from tests/testthat/test-define_search_polygon.R --
# a small closed square (SW -> SE -> NE -> NW), the exact starting-polygon
# shape define_search_polygon() itself builds before a user drags any corner.
square_lng <- c(-120, -119, -119, -120)
square_lat <- c(34, 34, 35, 35)
square_wkt <- TaxaTools:::.pts_to_wkt(lng = square_lng, lat = square_lat)
square_wkt
# "POLYGON ((-120.000000 34.000000, -119.000000 34.000000, ...,
#            -120.000000 34.000000))" -- ring closed, first vertex repeated last.

## ---- .wkt_to_pts() ---- OFFLINE ----------------------------------------------
# Round-trips the WKT string built above back into ordered (lng, lat) vectors,
# dropping the duplicated closing vertex -- same fixture, same test file.
parsed_pts <- TaxaTools:::.wkt_to_pts(square_wkt)
parsed_pts
identical(round(parsed_pts$lng, 6), square_lng)   # TRUE
identical(round(parsed_pts$lat, 6), square_lat)   # TRUE


# ==============================================================================
# SECTION 3 -- define_search_polygon.R exported gadget
# define_search_polygon()
# ==============================================================================

## ---- define_search_polygon() ---- INTERACTIVE, CANNOT BE RUN HERE -----------
# This is a REAL interactive Shiny gadget (miniUI title bar + a live leaflet
# map with draggable vertex markers) that calls shiny::runGadget() and BLOCKS
# waiting for a genuine mouse click on "Done"/"Cancel" (or whatever labels a
# caller supplies via done_label/cancel_label). It cannot be meaningfully
# exercised as a standalone non-interactive call -- there is no fake input
# that substitutes for a real click-through, and define_search_polygon()
# itself refuses to run at all outside an interactive session
# (stop("...must be run in an interactive R session.")). No fake harness is
# built here for that reason -- see this file's own header note.
#
# TO EXERCISE THIS FUNCTION FOR REAL: run the line below directly in your own
# interactive RStudio session (not via Rscript, not via this file's own
# batch execution). It uses the default viewer, shiny::paneViewer(minHeight =
# 500) -- deliberately NOT shiny::dialogViewer(), which TaxaTools/CLAUDE.md's
# own "Known R Footguns" section documents as silently swallowing this exact
# gadget's Done-button click on at least one real RStudio setup (a Leaflet/
# embedded-dialog-webview interaction problem, not a bug in this function).
# paneViewer() (the default) and browserViewer() are both confirmed working;
# only pass dialogViewer() yourself if you've independently confirmed it
# round-trips a real click on your own machine.
#
#   test_polygon <- TaxaTools::define_search_polygon(
#     lat = 34.4, lon = -120.4, radius_deg = 2,
#     title = "Review: define_search_polygon()"
#   )
#   test_polygon   # NULL if you click Cancel; a WKT POLYGON string if Done
#
# Real parameters, per its own roxygen (read define_search_polygon()'s help
# for the full list before using it): lat/lon/radius_deg (required unless
# init_polygon is supplied -- centre point + half-width in decimal degrees
# for the starting square); tile (Leaflet basemap provider, default
# "Esri.OceanBasemap"); points/group_col (optional reference-point overlay,
# e.g. real observation coordinates, optionally colored by an existing
# spatial_group_id column); init_polygon (reopen a previously returned WKT
# string for reshaping instead of starting from a fresh square); title/
# done_label/cancel_label (gadget title-bar wording); viewer (defaults to
# paneViewer(), see above). Returns a closed, counter-clockwise WKT POLYGON
# string on Done, or NULL on Cancel.


# ==============================================================================
# SECTION 4 -- escalate_taxonomic_rank.R
# escalate_taxonomic_rank()
# ==============================================================================

## ---- escalate_taxonomic_rank() ---- NETWORK, small real genus ---------------
# Fundulus (a small, common, well-referenced fish genus, family Fundulidae) --
# same real-genus convention TaxaLikely/inst/review_function_inputs.R
# establishes for this ecosystem's own NETWORK sections. Queries NCBI
# taxonomy directly (backbone_id = 4L, the default) and walks one rank
# coarser than "genus" in the default rank_system.
escalated <- escalate_taxonomic_rank(
  "Fundulus",
  current_rank = "genus",
  verbose      = FALSE
)
escalated
# list(taxon_name = "Fundulidae", rank = "family")

# Already-coarsest-rank short-circuit: no API call is made at all when
# current_rank is already the coarsest rank in rank_system.
escalate_taxonomic_rank("Animalia", current_rank = "kingdom", verbose = FALSE)
# list(taxon_name = NA_character_, rank = NA_character_)


# ==============================================================================
# SECTION 5 -- barcode_utils.R
# resolve_barcode_primers()
# ==============================================================================

## ---- resolve_barcode_primers() ---- OFFLINE ---------------------------------
# Pure lookup against the barcode_primer_defaults registry -- no network call
# despite living alongside barcode/marker-name utilities elsewhere in this
# ecosystem that do hit NCBI; this one is a plain table lookup. MiFishU is the
# one marker with real production use across this ecosystem's own workflows
# (see this function's own roxygen/registry documentation). Input reused from
# tests/testthat/test-barcode_utils.R's own established call.
mifish_u_primers <- resolve_barcode_primers("MiFishU")
mifish_u_primers
# list(fwd = "GTCGGTAAAACTCGTGCCAGC",
#      rev = "CATAGTGGGGTATCTAATCCCAGTTTG",
#      amplicon_range = c(163L, 185L))

# Case/separator-insensitive matching -- same variant, different spelling.
identical(resolve_barcode_primers("mifish-u"), mifish_u_primers)   # TRUE

# Deliberately errors (does not guess) on an ambiguous bare term that matches
# more than one registered variant -- MiFish-U and MiFish-E have genuinely
# different primer sequences, so silently picking one would be a real
# correctness risk, not a convenience.
tryCatch(
  resolve_barcode_primers("mifish"),
  error = function(e) conditionMessage(e)
)
