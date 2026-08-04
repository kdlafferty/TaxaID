# test-compute_adaptive_sampling_groups.R
# Tests for compute_adaptive_sampling_groups() (Session 149).
#
# Design: greedily merge taxa up rank_system (finest -> ceiling) until each
# group's mean per-site record count clears min_n. Groups that already clear
# it at the finest rank stay there; shortfall groups pool with taxonomic
# siblings at the next rank up; the ceiling rank is never crossed, and a
# group still below min_n at the ceiling is finalized anyway, flagged.

library(testthat)

.make_group_rows <- function(order, class, phylum, n_per_site, grids = paste0("g", 1:10)) {
  do.call(rbind, lapply(grids, function(g) {
    data.frame(
      grid_id = g, order = order, class = class, phylum = phylum,
      taxon_name = paste0(order, "_sp"), stringsAsFactors = FALSE
    )[rep(1, n_per_site), ]
  }))
}

# ---- Partition invariant: every row in exactly one group, none dropped -------

test_that("every row is assigned to exactly one group -- no gaps, no overlaps, no reordering", {
  set.seed(7)
  # A deliberately messy, varied fixture: several orders (some common, some
  # rare) across two classes and two phyla, plus some NA taxonomy at various
  # ranks -- stresses the merge-and-defer logic much harder than the earlier
  # hand-built scenarios.
  specs <- list(
    list(order = "Perciformes",    class = "Actinopteri", phylum = "Chordata", n = 150),
    list(order = "Anguilliformes", class = "Actinopteri", phylum = "Chordata", n = 8),
    list(order = "Clupeiformes",   class = "Actinopteri", phylum = "Chordata", n = 12),
    list(order = "Carnivora",      class = "Mammalia",    phylum = "Chordata", n = 6),
    list(order = "Primates",       class = "Mammalia",    phylum = "Chordata", n = 200),
    list(order = NA_character_,    class = "Actinopteri", phylum = "Chordata", n = 20),
    list(order = NA_character_,    class = NA_character_, phylum = "Chordata", n = 3),
    list(order = NA_character_,    class = NA_character_, phylum = NA_character_, n = 4)
  )
  occ <- do.call(rbind, lapply(specs, function(s) {
    .make_group_rows(s$order, s$class, s$phylum, s$n)
  }))
  occ$row_id <- seq_len(nrow(occ))  # unique identity marker, independent of taxonomy

  out <- compute_adaptive_sampling_groups(occ, rank_system = c("order", "class", "phylum"),
                                          min_n = 100)

  # No gaps: every row has a non-NA sampling_group.
  expect_false(anyNA(out$sampling_group))
  # No rows dropped or duplicated; row identity/order preserved exactly.
  expect_equal(nrow(out), nrow(occ))
  expect_equal(out$row_id, occ$row_id)
  # No overlaps: the total assigned across all groups sums to exactly nrow(occ)
  # (a row counted in two groups would inflate this; a dropped row would
  # deflate it).
  expect_equal(sum(table(out$sampling_group)), nrow(occ))

  # Internal consistency: rows sharing an "order:X" label must all actually
  # have order == X (and never mix with a different order's rows), and same
  # for "class:X" / "phylum:X" labels -- catches any mislabeling, not just a
  # row count coincidence.
  for (lbl in unique(out$sampling_group)) {
    rows <- out[out$sampling_group == lbl, ]
    if (startsWith(lbl, "order:")) {
      expect_equal(unique(rows$order), sub("^order:", "", lbl))
    } else if (startsWith(lbl, "class:")) {
      expect_equal(unique(rows$class), sub("^class:", "", lbl))
    } else if (startsWith(lbl, "phylum:")) {
      expect_equal(unique(rows$phylum), sub("^phylum:", "", lbl))
    }
    # "unknown" rows: no consistency check beyond all-NA taxonomy, already
    # covered by dedicated NA-handling tests above/below.
  }
})

test_that("a group that clears min_n at the finest rank stays at that rank", {
  occ <- .make_group_rows("Perciformes", "Actinopteri", "Chordata", 150)
  out <- compute_adaptive_sampling_groups(occ, rank_system = c("order", "class", "phylum"),
                                          min_n = 100)
  expect_true(all(out$sampling_group == "order:Perciformes"))
  expect_true(all(!out$sampling_group_below_min_n))
})

test_that("two sparse sibling orders are pooled at their shared class", {
  occ <- rbind(
    .make_group_rows("Anguilliformes", "Actinopteri", "Chordata", 60),
    .make_group_rows("Clupeiformes",   "Actinopteri", "Chordata", 60)
  )
  # Neither order alone clears 100 (60 < 100), but pooled at class they do
  # (120 >= 100).
  out <- compute_adaptive_sampling_groups(occ, rank_system = c("order", "class", "phylum"),
                                          min_n = 100)
  expect_true(all(out$sampling_group == "class:Actinopteri"))
  expect_true(all(!out$sampling_group_below_min_n))
})

test_that("groups that still don't clear min_n even pooled at the ceiling are flagged, not merged further", {
  occ <- rbind(
    .make_group_rows("Anguilliformes", "Actinopteri", "Chordata", 10),
    .make_group_rows("Clupeiformes",   "Actinopteri", "Chordata", 10),
    .make_group_rows("Carnivora",      "Mammalia",    "Chordata", 5)
  )
  out <- compute_adaptive_sampling_groups(occ, rank_system = c("order", "class", "phylum"),
                                          min_n = 100)
  # All three end up pooled at the ceiling (phylum) since neither the order-
  # nor class-level pools reached 100 -- but they are pooled together (all
  # share phylum = Chordata), not left unresolved past the ceiling.
  expect_true(all(out$sampling_group == "phylum:Chordata"))
  expect_true(all(out$sampling_group_below_min_n))
})

test_that("an independently-resolved finer group is not swept into a coarser pool", {
  occ <- rbind(
    .make_group_rows("Perciformes",    "Actinopteri", "Chordata", 150), # clears at order
    .make_group_rows("Anguilliformes", "Actinopteri", "Chordata", 10),  # needs class pooling
    .make_group_rows("Clupeiformes",   "Actinopteri", "Chordata", 10)
  )
  out <- compute_adaptive_sampling_groups(occ, rank_system = c("order", "class", "phylum"),
                                          min_n = 100)
  perci <- out[out$order == "Perciformes", ]
  others <- out[out$order != "Perciformes", ]
  expect_true(all(perci$sampling_group == "order:Perciformes"))
  # The two sparse orders pool at class -- 200 rows / 10 sites = 20 < 100,
  # so they escalate further, to the phylum ceiling (still just themselves,
  # since Perciformes was already excluded).
  expect_true(all(others$sampling_group == "phylum:Chordata"))
})

test_that("never merges across the ceiling rank even when both groups are sparse", {
  occ <- rbind(
    .make_group_rows("Anguilliformes", "Actinopteri", "Chordata",    10),
    .make_group_rows("Rodentia",       "Mammalia",    "Mammalophyta", 10)
  )
  out <- compute_adaptive_sampling_groups(occ, rank_system = c("order", "class", "phylum"),
                                          min_n = 100)
  expect_setequal(unique(out$sampling_group), c("phylum:Chordata", "phylum:Mammalophyta"))
  expect_true(all(out$sampling_group_below_min_n))
})

# ---- NA taxonomy handling -----------------------------------------------------

test_that("NA at the finest rank holds back and resolves at a coarser rank", {
  occ <- data.frame(
    grid_id = rep(paste0("g", 1:5), each = 30),
    order   = NA_character_,
    class   = "Actinopteri",
    phylum  = "Chordata",
    taxon_name = "Unknown_fish",
    stringsAsFactors = FALSE
  )
  out <- compute_adaptive_sampling_groups(occ, rank_system = c("order", "class", "phylum"),
                                          min_n = 100)
  # class = "Actinopteri" is a real (non-NA) value, so this resolves there or
  # escalates further as a normal group -- it must NOT be dumped into
  # "unknown" just because order was NA.
  expect_false(any(out$sampling_group == "unknown"))
  expect_true(all(out$sampling_group == "phylum:Chordata"))  # 150/5 = 30 < 100
})

test_that("NA at every rank finalizes as its own 'unknown' group at the ceiling", {
  occ <- data.frame(
    grid_id = rep(paste0("g", 1:3), each = 5),
    order = NA_character_, class = NA_character_, phylum = NA_character_,
    taxon_name = "Totally_unknown", stringsAsFactors = FALSE
  )
  out <- compute_adaptive_sampling_groups(occ, rank_system = c("order", "class", "phylum"),
                                          min_n = 100)
  expect_true(all(out$sampling_group == "unknown"))
  expect_true(all(out$sampling_group_below_min_n))
})

test_that("empty-string taxonomy (real GBIF data uses '' for unclassified, not always NA) is treated as NA", {
  # Found on real PtConception 18S occurrence data: 13 records had
  # phylum == "" rather than NA. Before the fix, these formed their own
  # literal "phylum:" group instead of holding back to the ceiling's
  # "unknown" bucket alongside genuinely-NA rows.
  occ <- data.frame(
    grid_id = rep(paste0("g", 1:3), each = 5),
    order = "", class = "", phylum = "",
    taxon_name = "Empty_string_taxonomy", stringsAsFactors = FALSE
  )
  out <- compute_adaptive_sampling_groups(occ, rank_system = c("order", "class", "phylum"),
                                          min_n = 100)
  expect_true(all(out$sampling_group == "unknown"))
  expect_false(any(grepl("^order:$|^class:$|^phylum:$", out$sampling_group)))
})

test_that("'unknown' rows are never merged with a named ceiling-rank group", {
  occ <- rbind(
    data.frame(grid_id = rep(paste0("g", 1:5), each = 30),
              order = NA_character_, class = NA_character_, phylum = NA_character_,
              taxon_name = "Totally_unknown", stringsAsFactors = FALSE),
    .make_group_rows("Carnivora", "Mammalia", "Chordata", 5, grids = paste0("g", 1:5))
  )
  out <- compute_adaptive_sampling_groups(occ, rank_system = c("order", "class", "phylum"),
                                          min_n = 100)
  expect_true(all(out$sampling_group[is.na(out$phylum)] == "unknown"))
  expect_true(all(out$sampling_group[!is.na(out$phylum)] == "phylum:Chordata"))
})

# ---- habitat_col --------------------------------------------------------------

test_that("habitat_col makes the effort metric per (grid, habitat) instead of per grid alone", {
  # Same order at the same site but two habitats -- without habitat_col,
  # records from both habitats count toward one site total; with it, each
  # habitat's own total is evaluated separately.
  occ <- data.frame(
    grid_id = "g1", main_habitat = rep(c("Kelp", "Sandy"), each = 60),
    order = "Perciformes", class = "Actinopteri", phylum = "Chordata",
    taxon_name = "Perciformes_sp", stringsAsFactors = FALSE
  )
  out_no_habitat <- compute_adaptive_sampling_groups(
    occ, rank_system = c("order", "class", "phylum"), min_n = 100
  )
  # Pooled across habitats: 120 records at one grid_id -> clears 100.
  expect_false(unique(out_no_habitat$sampling_group_below_min_n))

  out_with_habitat <- compute_adaptive_sampling_groups(
    occ, rank_system = c("order", "class", "phylum"), min_n = 100,
    habitat_col = "main_habitat"
  )
  # Per (grid, habitat): only 60 records each -- does not clear 100 at order,
  # escalates to the phylum ceiling, flagged.
  expect_true(all(out_with_habitat$sampling_group_below_min_n))
})

# ---- Validation -----------------------------------------------------------------

test_that("errors on missing required columns", {
  occ <- .make_group_rows("Perciformes", "Actinopteri", "Chordata", 10)
  occ$class <- NULL
  expect_error(
    compute_adaptive_sampling_groups(occ, rank_system = c("order", "class", "phylum"),
                                      min_n = 100),
    "missing required columns"
  )
})

test_that("errors when min_n is omitted", {
  occ <- .make_group_rows("Perciformes", "Actinopteri", "Chordata", 10)
  expect_error(
    compute_adaptive_sampling_groups(occ),
    "min_n"
  )
})

test_that("errors on invalid min_n", {
  occ <- .make_group_rows("Perciformes", "Actinopteri", "Chordata", 10)
  expect_error(
    compute_adaptive_sampling_groups(occ, min_n = -1),
    "min_n"
  )
  expect_error(
    compute_adaptive_sampling_groups(occ, min_n = c(10, 20)),
    "min_n"
  )
})

test_that("errors on empty rank_system", {
  occ <- .make_group_rows("Perciformes", "Actinopteri", "Chordata", 10)
  expect_error(
    compute_adaptive_sampling_groups(occ, rank_system = character(0)),
    "rank_system"
  )
})
