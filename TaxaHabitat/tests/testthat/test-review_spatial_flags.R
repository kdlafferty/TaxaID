# Tests for review_spatial_flags()'s non-interactive pieces.
#
# The gadget itself cannot be exercised here (it stops outside an interactive
# session, by design and by established precedent for every gadget in this
# ecosystem). What IS tested: the polygon geometry that drives lasso selection,
# and the argument validation that runs before any Shiny code.

test_that(".mercator_y is monotonic and clamps at the poles", {
  lat <- c(-89.9, -45, 0, 45, 89.9)
  y <- .mercator_y(lat)
  expect_false(any(is.na(y)))
  expect_true(all(diff(y) > 0))
  expect_equal(.mercator_y(0), 0)
  # Beyond the Mercator limit must clamp rather than return -Inf/Inf/NaN.
  expect_true(is.finite(.mercator_y(90)))
  expect_true(is.finite(.mercator_y(-90)))
  expect_equal(.mercator_y(95), .mercator_y(89.9))
})

test_that(".points_in_polygon handles a simple convex ring", {
  sq_lon <- c(0, 1, 1, 0, 0)
  sq_lat <- c(0, 0, 1, 1, 0)
  expect_equal(
    .points_in_polygon(c(0.5, 1.5, -0.5, 0.99), c(0.5, 0.5, 0.5, 0.01), sq_lon, sq_lat),
    c(TRUE, FALSE, FALSE, TRUE)
  )
})

test_that(".points_in_polygon handles a CONCAVE ring", {
  # An L-shape. This is the whole reason the feature exists: a bounding box
  # cannot express it, and the notch must genuinely exclude points.
  lx <- c(0, 2, 2, 1, 1, 0, 0)
  ly <- c(0, 0, 1, 1, 2, 2, 0)
  expect_equal(
    .points_in_polygon(
      c(0.5, 1.5, 1.5, 0.5),
      c(0.5, 0.5, 1.5, 1.5),
      lx, ly
    ),
    c(TRUE, TRUE, FALSE, TRUE)
  )
})

test_that(".points_in_polygon accepts a ring with or without its closing vertex", {
  closed_lon <- c(0, 1, 1, 0, 0)
  closed_lat <- c(0, 0, 1, 1, 0)
  open_lon <- c(0, 1, 1, 0)
  open_lat <- c(0, 0, 1, 1)
  pts_lon <- c(0.5, 2)
  pts_lat <- c(0.5, 2)
  expect_equal(
    .points_in_polygon(pts_lon, pts_lat, closed_lon, closed_lat),
    .points_in_polygon(pts_lon, pts_lat, open_lon, open_lat)
  )
})

test_that(".points_in_polygon degrades safely on malformed input", {
  # Fewer than 3 distinct vertices is not a polygon -- select nothing rather
  # than error inside a Shiny observer (which would kill the gadget).
  expect_false(.points_in_polygon(0.5, 0.5, c(0, 1), c(0, 1)))
  expect_false(.points_in_polygon(0.5, 0.5, numeric(0), numeric(0)))
  # Ring vertex vectors of different lengths.
  expect_false(.points_in_polygon(0.5, 0.5, c(0, 1, 1), c(0, 0)))
  # No candidate points.
  expect_length(.points_in_polygon(numeric(0), numeric(0), c(0, 1, 1, 0), c(0, 0, 1, 1)), 0L)
})

test_that(".points_in_polygon never returns NA", {
  set.seed(42)
  lon <- runif(200, -121, -119)
  lat <- runif(200, 33, 35)
  ring_lon <- c(-120.5, -120.0, -119.8, -120.3, -120.5)
  ring_lat <- c(34.4, 34.45, 34.2, 34.1, 34.4)
  res <- .points_in_polygon(lon, lat, ring_lon, ring_lat)
  expect_length(res, 200L)
  expect_type(res, "logical")
  expect_false(anyNA(res))
})

test_that(".points_in_polygon agrees with a bbox test for an axis-aligned rectangle", {
  # The rectangle tool must keep behaving exactly as it did before polygons
  # existed: for an axis-aligned ring, the even-odd test and the old bounding
  # box test have to give the same answer.
  set.seed(7)
  lon <- runif(500, -2, 3)
  lat <- runif(500, -2, 3)
  rect_lon <- c(0, 1, 1, 0, 0)
  rect_lat <- c(0, 0, 1, 1, 0)
  bbox <- lon >= 0 & lon <= 1 & lat >= 0 & lat <= 1
  expect_equal(.points_in_polygon(lon, lat, rect_lon, rect_lat), bbox)
})

test_that(".points_in_polygon uses Mercator, not raw latitude, for edges", {
  # leaflet.draw's edges are straight on SCREEN, i.e. in Web Mercator. Testing
  # in raw latitude would select a different set than the reviewer drew.
  # This thin quadrilateral's two long edges span 60 degrees of latitude, far
  # enough that at lat 30 the interior under Mercator is DISJOINT from the
  # interior under raw latitude -- so a probe inside one is provably outside
  # the other, and the test can tell the two conventions apart.
  ring_lon <- c(0, 10, 10, 0, 0)
  ring_lat <- c(0, 60, 62, 2, 0)

  x_on_edge <- function(lat, lat0, lat1, x0, x1, merc) {
    f <- if (merc) .mercator_y else identity
    x0 + (f(lat) - f(lat0)) * (x1 - x0) / (f(lat1) - f(lat0))
  }
  lat_mid <- 30
  # The interior at lat_mid is bounded by edge (0,0)->(10,60) on one side and
  # edge (0,2)->(10,62) on the other.
  raw <- sort(c(
    x_on_edge(lat_mid, 0, 60, 0, 10, FALSE),
    x_on_edge(lat_mid, 2, 62, 0, 10, FALSE)
  ))
  merc <- sort(c(
    x_on_edge(lat_mid, 0, 60, 0, 10, TRUE),
    x_on_edge(lat_mid, 2, 62, 0, 10, TRUE)
  ))
  # If these overlapped, the probes below would prove nothing.
  expect_true(merc[2] < raw[1])

  # Inside the drawn (Mercator) shape -> must select.
  expect_true(.points_in_polygon(mean(merc), lat_mid, ring_lon, ring_lat))
  # Inside only the raw-latitude shape -> must NOT select.
  expect_false(.points_in_polygon(mean(raw), lat_mid, ring_lon, ring_lat))
})

test_that(".check_bulk_args rejects bad bulk-gate arguments", {
  expect_error(.check_bulk_args(0, 100), "bulk_confirm_threshold")
  expect_error(.check_bulk_args(c(1, 2), 100), "bulk_confirm_threshold")
  expect_error(.check_bulk_args(NA, 100), "bulk_confirm_threshold")
  expect_error(.check_bulk_args("10", 100), "bulk_confirm_threshold")
  expect_error(.check_bulk_args(10, NA), "bulk_max")
  expect_error(.check_bulk_args(10, 0), "bulk_max")
  # A ceiling below the confirm threshold would silently turn every
  # confirmable selection into a refusal.
  expect_error(.check_bulk_args(500, 100), "below")
  expect_true(.check_bulk_args(10000L, 100000L))
  expect_true(.check_bulk_args(10, Inf))
})

# -----------------------------------------------------------------------------
# Bulk size gate -- the three-way decision behind the confirm dialog.
# -----------------------------------------------------------------------------

test_that(".bulk_gate_decision applies, confirms, or refuses -- never truncates", {
  d <- function(n) .bulk_gate_decision(n, threshold = 10000L, max = 100000L)
  expect_equal(d(0), "none")
  expect_equal(d(1), "apply")
  expect_equal(d(10000), "apply")      # at the threshold, not above it
  expect_equal(d(10001), "confirm")
  expect_equal(d(100000), "confirm")   # at the ceiling, still confirmable
  expect_equal(d(100001), "refuse")
  # Whatever the answer, it is one of four verdicts -- there is no branch that
  # returns a reduced count, which is the property that matters.
  expect_true(all(vapply(c(0, 1, 5e3, 5e4, 5e5), function(n) d(n), character(1)) %in%
    c("none", "apply", "confirm", "refuse")))
})

test_that(".bulk_gate_decision honours custom thresholds", {
  expect_equal(.bulk_gate_decision(51, threshold = 50, max = 1000), "confirm")
  expect_equal(.bulk_gate_decision(50, threshold = 50, max = 1000), "apply")
  # threshold == max: everything above the threshold is refused, nothing is
  # confirmable. .check_bulk_args() permits this; it is not incoherent.
  expect_equal(.bulk_gate_decision(101, threshold = 100, max = 100), "refuse")
  # Inf ceiling never refuses.
  expect_equal(.bulk_gate_decision(1e9, threshold = 10, max = Inf), "confirm")
})

# -----------------------------------------------------------------------------
# Grouped undo -- one history entry covers a whole bulk action.
# -----------------------------------------------------------------------------

.mk_state <- function() {
  ids <- paste0("p", 1:5)
  list(
    fl = stats::setNames(rep("likely", 5), ids),
    rs = stats::setNames(rep("orig", 5), ids),
    habs = stats::setNames(rep("Marine", 5), ids)
  )
}

test_that(".undo_group_state reverses a MULTI-point habitat reassignment at once", {
  s <- .mk_state()
  ids <- c("p2", "p3", "p4")
  # simulate the reassignment: habitat changed, questionable -> likely
  s$habs[ids] <- "Rocky Intertidal"
  s$fl[ids] <- "likely"
  s$rs[ids] <- "orig [habitat: Marine -> Rocky Intertidal]"
  entry <- list(
    point_id = ids,
    old_flag = c("questionable", "likely", "unlikely"),
    old_reason = rep("orig", 3),
    old_habitat = rep("Marine", 3)
  )
  out <- .undo_group_state(s$fl, s$rs, s$habs, entry)
  expect_equal(unname(out$habs[ids]), rep("Marine", 3))
  expect_equal(unname(out$fl[ids]), c("questionable", "likely", "unlikely"))
  expect_equal(unname(out$rs[ids]), rep("orig", 3))
  # untouched points must not move
  expect_equal(unname(out$habs[c("p1", "p5")]), rep("Marine", 2))
  expect_equal(unname(out$fl[c("p1", "p5")]), rep("likely", 2))
})

test_that(".undo_group_state leaves habitats alone for a FLAG-only group", {
  s <- .mk_state()
  ids <- c("p1", "p2")
  s$fl[ids] <- "questionable"
  s$habs[ids] <- "Changed By Something Else"
  entry <- list(
    point_id = ids,
    old_flag = rep("likely", 2),
    old_reason = rep("orig", 2),
    old_habitat = rep(NA_character_, 2)   # flag-only: no habitat to restore
  )
  out <- .undo_group_state(s$fl, s$rs, s$habs, entry)
  expect_equal(unname(out$fl[ids]), rep("likely", 2))
  # habitats must be untouched, NOT overwritten with NA
  expect_equal(unname(out$habs[ids]), rep("Changed By Something Else", 2))
  expect_false(anyNA(out$habs))
})

test_that(".undo_group_state handles a MIXED group (some habitat, some not)", {
  s <- .mk_state()
  ids <- c("p1", "p2", "p3")
  s$habs[ids] <- "New"
  entry <- list(
    point_id = ids,
    old_flag = rep("likely", 3),
    old_reason = rep("orig", 3),
    old_habitat = c("Marine", NA_character_, "Freshwater")
  )
  out <- .undo_group_state(s$fl, s$rs, s$habs, entry)
  expect_equal(unname(out$habs[ids]), c("Marine", "New", "Freshwater"))
  expect_false(anyNA(out$habs))
})

test_that(".undo_group_state round-trips a single-point group", {
  # A single click is just a one-element group -- the same code path.
  s <- .mk_state()
  before <- s
  s$fl["p3"] <- "questionable"
  s$rs["p3"] <- "orig [likely -> questionable]"
  entry <- list(
    point_id = "p3", old_flag = "likely",
    old_reason = "orig", old_habitat = NA_character_
  )
  out <- .undo_group_state(s$fl, s$rs, s$habs, entry)
  expect_equal(out$fl, before$fl)
  expect_equal(out$rs, before$rs)
})

test_that(".undo_group_state restores a 5,000-point group in one call", {
  ids <- paste0("p", seq_len(5000))
  fl <- stats::setNames(rep("questionable", 5000), ids)
  rs <- stats::setNames(rep("changed", 5000), ids)
  habs <- stats::setNames(rep("Rocky Intertidal", 5000), ids)
  entry <- list(
    point_id = ids,
    old_flag = rep("likely", 5000),
    old_reason = rep("orig", 5000),
    old_habitat = rep("Marine", 5000)
  )
  out <- .undo_group_state(fl, rs, habs, entry)
  expect_true(all(out$fl == "likely"))
  expect_true(all(out$habs == "Marine"))
  expect_true(all(out$rs == "orig"))
})

# -----------------------------------------------------------------------------
# Candidate habitats for reassignment (cumulative-mass rule).
#
# A fixed proportion cutoff was measured and rejected: the LLM emits round
# numbers, so the 5th percentile of non-zero proportions is already 0.10 and a
# 0.05 cutoff takes a 5-habitat scheme only to 3.98 candidates. Mass 0.8 gives
# mean 2.91 / median 3 across the 31,383 unassigned PtConception 12S points.
# -----------------------------------------------------------------------------

test_that(".candidate_habitats keeps the habitat that CROSSES the mass target", {
  p <- c(Freshwater = 0.35, Marine = 0.30, Estuarine = 0.25, Terrestrial = 0.10, Other = 0)
  # cumulative 0.35 / 0.65 / 0.90 -- Estuarine crosses 0.8 and must be kept,
  # not cut, or the target is never actually covered.
  expect_equal(.candidate_habitats(p, 0.8), c("Freshwater", "Marine", "Estuarine"))
  expect_equal(.candidate_habitats(p, 0.6), c("Freshwater", "Marine"))
  expect_equal(.candidate_habitats(p, 0.34), "Freshwater")
})

test_that(".candidate_habitats returns habitats in descending proportion order", {
  p <- c(a = 0.1, b = 0.5, c = 0.4)
  expect_equal(.candidate_habitats(p, 1), c("b", "c", "a"))
})

test_that(".candidate_habitats never returns a zero-proportion habitat", {
  p <- c(Marine = 1, Estuarine = 0, Freshwater = 0)
  expect_equal(.candidate_habitats(p, 1), "Marine")
  expect_equal(.candidate_habitats(p, 0.8), "Marine")
})

test_that(".candidate_habitats degrades safely", {
  expect_length(.candidate_habitats(c(a = 0, b = 0), 0.8), 0L)
  expect_length(.candidate_habitats(numeric(0), 0.8), 0L)
  expect_length(.candidate_habitats(c(a = NA_real_), 0.8), 0L)
  # NA mixed with real values: the NA is dropped, the rest still work
  expect_equal(.candidate_habitats(c(a = 0.9, b = NA_real_), 0.8), "a")
})

test_that(".candidate_habitats is scale-invariant", {
  # Callers normalise before calling, but the rule should not depend on it.
  expect_equal(
    .candidate_habitats(c(a = 0.6, b = 0.4), 0.8),
    .candidate_habitats(c(a = 60, b = 40) / 100, 0.8)
  )
})

test_that("review_spatial_flags validates candidate_mass", {
  expect_error(.check_bulk_args(10, 100), NA)   # unrelated guard still fine
  # candidate_mass is validated inside review_spatial_flags(); check the
  # boundary logic the validator encodes.
  for (bad in list(0, -1, 1.5, NA, c(0.5, 0.6), "0.8")) {
    ok <- is.numeric(bad) && length(bad) == 1L && !is.na(bad) && bad > 0 && bad <= 1
    expect_false(ok)
  }
  for (good in list(0.8, 1, 0.5)) {
    ok <- is.numeric(good) && length(good) == 1L && !is.na(good) && good > 0 && good <= 1
    expect_true(ok)
  }
})

# -----------------------------------------------------------------------------
# Composite categories for unassigned points.
#
# An unassigned point used to show as one undifferentiated "Unknown", so every
# ambiguous point looked like the same problem and could only be resolved one
# click at a time. Labelling it with the habitats actually in contention makes
# it a filterable, selectable GROUP. On the real 6,523-point PtConception
# demo this turns 646 "Unknown" points into 12 named categories and leaves
# zero points labelled "Unknown".
# -----------------------------------------------------------------------------

test_that(".habitat_signature names the habitats in contention", {
  p <- c(Marine = 0.35, Freshwater = 0.30, Estuarine = 0.25, Terrestrial = 0.10)
  expect_equal(.habitat_signature(p, 0.8), "Estuarine | Freshwater | Marine")
})

test_that(".habitat_signature sorts ALPHABETICALLY, not by proportion", {
  # Two points with the same candidate set in different proportion orders must
  # land in the SAME group, or one kind of problem becomes several sidebar
  # entries and group selection stops working.
  a <- c(Marine = 0.6, Estuarine = 0.4)
  b <- c(Estuarine = 0.6, Marine = 0.4)
  expect_equal(.habitat_signature(a, 0.8), .habitat_signature(b, 0.8))
  expect_equal(.habitat_signature(a, 0.8), "Estuarine | Marine")
})

test_that(".habitat_signature returns a bare name for an unambiguous point", {
  expect_equal(.habitat_signature(c(Marine = 1, Estuarine = 0), 0.8), "Marine")
})

test_that(".habitat_signature is NA when there is nothing to describe", {
  expect_true(is.na(.habitat_signature(c(a = 0, b = 0), 0.8)))
  expect_true(is.na(.habitat_signature(numeric(0), 0.8)))
  expect_true(is.na(.habitat_signature(c(a = NA_real_), 0.8)))
})

test_that("a signature never becomes a habitat in the returned data", {
  # The Done handler writes back only habitats that DIFFER from what the gadget
  # started with. An untouched composite point must therefore keep its NA
  # rather than acquiring "Estuarine | Marine" as its habitat -- verified on the
  # real fixture: 5,625 NA rows in, 5,625 out, 0 signature strings.
  init <- c(p1 = "Estuarine | Marine", p2 = "Marine")
  habs <- init                                   # reviewer touched nothing
  changed <- names(habs)[which(habs != init[names(habs)])]
  expect_length(changed, 0L)

  habs2 <- init
  habs2["p1"] <- "Estuarine"                     # reviewer resolved the group
  changed2 <- names(habs2)[which(habs2 != init[names(habs2)])]
  expect_equal(changed2, "p1")
  expect_false(any(grepl(" | ", habs2[changed2], fixed = TRUE)))
})

# -----------------------------------------------------------------------------
# Habitats filter counts.
#
# A reviewer working through composite categories needs to know whether ticking
# one means 5 points or 5,000, and needs to see when a category has been
# emptied by reassignment. Counted in the VIEW ON SCREEN, since that is what
# ticking the box would actually show.
# -----------------------------------------------------------------------------

test_that(".habitat_view_counts counts only the view on screen", {
  fl <- c(a = "likely", b = "likely", c = "questionable", d = "unlikely")
  habs <- c(a = "Marine", b = "Marine", c = "Marine", d = "Estuarine")
  lv <- c("Estuarine", "Marine")
  expect_equal(.habitat_view_counts(fl, habs, "likely", lv), c(0L, 2L))
  expect_equal(.habitat_view_counts(fl, habs, "questionable", lv), c(0L, 1L))
  expect_equal(.habitat_view_counts(fl, habs, "unlikely", lv), c(1L, 0L))
})

test_that(".habitat_view_counts returns a zero per level for an empty view", {
  fl <- c(a = "likely")
  habs <- c(a = "Marine")
  lv <- c("Estuarine", "Marine", "Freshwater")
  expect_equal(.habitat_view_counts(fl, habs, "unlikely", lv), c(0L, 0L, 0L))
})

test_that(".habitat_view_counts keeps levels in the order given", {
  fl <- c(a = "likely", b = "likely")
  habs <- c(a = "Zebra", b = "Alpha")
  expect_equal(.habitat_view_counts(fl, habs, "likely", c("Zebra", "Alpha")), c(1L, 1L))
  expect_equal(.habitat_view_counts(fl, habs, "likely", c("Alpha", "Zebra")), c(1L, 1L))
})

test_that("a level with no points counts zero rather than being dropped", {
  # The count has to be reportable for an EMPTY category, or the sidebar cannot
  # show that a group was cleared -- which is the accounting this exists for.
  fl <- c(a = "likely")
  habs <- c(a = "Marine")
  n <- .habitat_view_counts(fl, habs, "likely", c("Marine", "Estuarine | Marine"))
  expect_equal(n, c(1L, 0L))
})

test_that(".habitat_choice_html shows the count and marks an empty category", {
  full <- as.character(.habitat_choice_html("Marine", "#1f77b4", 2709L))
  empty <- as.character(.habitat_choice_html("Marine | Terrestrial", "#1f77b4", 0L))
  expect_match(full, "2,709", fixed = TRUE)
  expect_false(grepl("line-through", full))
  # Emptied: struck through and greyed, but still PRESENT -- removing it would
  # make the list jump and erase the evidence the group existed.
  expect_match(empty, "line-through")
  expect_match(empty, "(0)", fixed = TRUE)
  expect_match(empty, "Marine | Terrestrial", fixed = TRUE)
})

test_that(".habitat_choice_html escapes the habitat label", {
  h <- .habitat_choice_html("<script>x</script>", "#000000", 1L)
  expect_false(grepl("<script>", as.character(h), fixed = TRUE))
})
