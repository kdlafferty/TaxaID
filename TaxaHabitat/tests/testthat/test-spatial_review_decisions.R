# save_spatial_review_decisions() / apply_spatial_review_decisions() -- 2026-09-12

.flagged <- function() data.frame(
  point_id = c("p1", "p1", "p2", "p3", "p4"),
  taxon_name = c("A", "B", "A", "C", "D"),
  decimalLatitude = c(34.4, 34.4, 34.5, 34.6, 34.7),
  decimalLongitude = -120.4,
  main_habitat = c("Marine", "Marine", "Marine", "Terrestrial", "Marine"),
  spatial_flag = c("questionable", "questionable", "likely", "unlikely", "questionable"),
  spatial_flag_reason = c("r1", "r1", "ok", "r3", "r4"),
  stringsAsFactors = FALSE
)

test_that("no decisions file: nothing applied, every non-likely point is pending", {
  path <- file.path(withr::local_tempdir(), "dec.rds")
  out <- suppressMessages(apply_spatial_review_decisions(.flagged(), path))
  expect_equal(attr(out, "n_applied"), 0L)
  expect_equal(attr(out, "n_pending_review"), 3L)
  expect_setequal(attr(out, "pending_point_ids"), c("p1", "p3", "p4"))
  expect_equal(out$spatial_flag, .flagged()$spatial_flag)
})

test_that("saved decisions are re-applied per point and pending drops to the undecided flagged points", {
  path <- file.path(withr::local_tempdir(), "dec.rds")
  reviewed <- .flagged()
  reviewed$spatial_flag[reviewed$point_id == "p1"] <- "likely"        # reviewer confirmed p1
  reviewed$spatial_flag[reviewed$point_id == "p3"] <- "unlikely"      # reviewer left p3 excluded
  reviewed$main_habitat[reviewed$point_id == "p3"] <- "Marine"        # and reassigned its habitat
  dec <- suppressMessages(save_spatial_review_decisions(reviewed, path, before = .flagged()))
  expect_equal(nrow(dec), 4L)   # one row per point_id
  expect_equal(dec$habitat_reassigned[dec$point_id == "p3"], TRUE)    # Terrestrial -> Marine was the reviewer
  expect_equal(dec$habitat_reassigned[dec$point_id == "p1"], FALSE)   # p1's habitat is the automatic one
  expect_true(file.exists(path))

  fresh <- .flagged()
  fresh$spatial_flag[fresh$point_id == "p1"] <- "questionable"   # auto-flagger flags p1 again
  out <- suppressMessages(apply_spatial_review_decisions(fresh, path))
  expect_equal(out$spatial_flag[out$point_id == "p1"], c("likely", "likely"))
  expect_equal(out$main_habitat[out$point_id == "p3"], "Marine")
  expect_match(out$spatial_flag_reason[out$point_id == "p1"][1], "^reviewer decision")
  expect_equal(attr(out, "n_pending_review"), 0L)   # p4 was reviewed too (kept questionable) -> decided
})

test_that("a new flagged point not on file is pending, and a newer decision replaces an older one", {
  path <- file.path(withr::local_tempdir(), "dec.rds")
  suppressMessages(save_spatial_review_decisions(.flagged(), path))
  fresh <- rbind(.flagged(), data.frame(point_id = "p9", taxon_name = "Z", decimalLatitude = 35, decimalLongitude = -120.4,
                                        main_habitat = "Marine", spatial_flag = "questionable", spatial_flag_reason = "new", stringsAsFactors = FALSE))
  out <- suppressMessages(apply_spatial_review_decisions(fresh, path))
  expect_equal(attr(out, "pending_point_ids"), "p9")
  later <- .flagged(); later$spatial_flag[later$point_id == "p4"] <- "likely"
  dec <- suppressMessages(save_spatial_review_decisions(later, path))
  expect_equal(dec$spatial_flag[dec$point_id == "p4"], "likely")
  expect_equal(nrow(dec), 4L)
})

test_that("inputs are validated", {
  path <- file.path(withr::local_tempdir(), "dec.rds")
  expect_error(save_spatial_review_decisions(.flagged()[, -1], path), "no column 'point_id'")
  expect_error(apply_spatial_review_decisions(.flagged(), c("a", "b")), "single file path")
  expect_error(apply_spatial_review_decisions("x", path), "data frame")
})


test_that("an automatic habitat is not frozen: only a reviewer reassignment overrides today's assignment", {
  path <- file.path(withr::local_tempdir(), "dec.rds")
  suppressMessages(save_spatial_review_decisions(.flagged(), path, before = .flagged()))   # nothing reassigned
  fresh <- .flagged(); fresh$main_habitat[fresh$point_id == "p2"] <- "Estuarine"   # today's automatic assignment moved
  out <- suppressMessages(apply_spatial_review_decisions(fresh, path))
  expect_equal(out$main_habitat[out$point_id == "p2"], "Estuarine")
  expect_equal(attr(out, "n_applied"), 0L)
  # without `before`, every saved habitat counts as a reassignment (conservative)
  path2 <- file.path(withr::local_tempdir(), "dec2.rds")
  suppressMessages(save_spatial_review_decisions(.flagged(), path2))
  out2 <- suppressMessages(apply_spatial_review_decisions(fresh, path2))
  expect_equal(out2$main_habitat[out2$point_id == "p2"], "Marine")
})

test_that("a reassignment survives a later review that left it in place", {
  path <- file.path(withr::local_tempdir(), "dec.rds")
  r1 <- .flagged(); r1$main_habitat[r1$point_id == "p3"] <- "Marine"
  suppressMessages(save_spatial_review_decisions(r1, path, before = .flagged()))
  applied <- suppressMessages(apply_spatial_review_decisions(.flagged(), path))   # p3 now reads Marine
  suppressMessages(save_spatial_review_decisions(applied, path, before = applied))  # reviewer changed nothing
  dec <- readRDS(path)
  expect_true(dec$habitat_reassigned[dec$point_id == "p3"])
})

test_that("save_spatial_review_decisions warns when before is NULL and habitats would be frozen (2026-09-13)", {
  path <- withr::local_tempfile(fileext = ".rds")
  reviewed <- data.frame(
    point_id = c("p1", "p2"),
    spatial_flag = c("likely", "unlikely"),
    main_habitat = c("Marine", NA_character_),
    stringsAsFactors = FALSE
  )
  expect_warning(
    suppressMessages(save_spatial_review_decisions(reviewed, path)),
    "recorded as habitat REASSIGNMENTS"
  )
  out <- readRDS(path)
  expect_equal(out$habitat_reassigned, c(TRUE, FALSE))

  # With `before`, a merely CONFIRMED habitat is not a reassignment and no warning fires.
  path2 <- withr::local_tempfile(fileext = ".rds")
  before <- data.frame(point_id = c("p1", "p2"), main_habitat = c("Marine", "Lentic"),
                       stringsAsFactors = FALSE)
  expect_no_warning(suppressMessages(
    save_spatial_review_decisions(reviewed, path2, before = before)
  ))
  expect_equal(readRDS(path2)$habitat_reassigned, c(FALSE, FALSE))

  # No non-NA habitat at all: nothing to freeze, so no warning even without `before`.
  path3 <- withr::local_tempfile(fileext = ".rds")
  expect_no_warning(suppressMessages(save_spatial_review_decisions(
    transform(reviewed, main_habitat = NA_character_), path3
  )))
})

# -----------------------------------------------------------------------------
# drop_stale_seeded_decisions()
#
# A seeded decision records "accept the automatic classification". When the
# classifier later changes its mind, that seed silently overrides the new
# verdict and apply_spatial_review_decisions() reports nothing pending. All
# three production files were 100% seeded (244,860 rows, 0 real reviews) as of
# 2026-09-19, so this is the live situation, not a hypothetical.
# -----------------------------------------------------------------------------

.mk_dec <- function(path, flags, decided_at) {
  saveRDS(data.frame(
    point_id = names(flags), spatial_flag = unname(flags),
    main_habitat = "Marine", decided_at = decided_at,
    habitat_reassigned = FALSE, stringsAsFactors = FALSE
  ), path)
}
.mk_occ <- function(flags) {
  data.frame(
    point_id = names(flags), spatial_flag = unname(flags),
    stringsAsFactors = FALSE
  )
}

test_that("a stale SEEDED decision is dropped", {
  p <- withr::local_tempfile(fileext = ".rds")
  .mk_dec(p, c(a = "likely", b = "likely"), "seeded from the completed run of 2026-09-11")
  occ <- .mk_occ(c(a = "unlikely", b = "likely"))   # 'a' has changed
  r <- suppressMessages(drop_stale_seeded_decisions(occ, p, dry_run = FALSE, backup = FALSE))
  expect_equal(r$n_stale, 1L)
  expect_equal(r$stale_point_ids, "a")
  expect_equal(sort(readRDS(p)$point_id), "b")
})

test_that("a REAL reviewer decision survives a classifier change", {
  # The reviewer overrode the classifier deliberately; a later change of the
  # classifier's mind must not erase that judgement.
  p <- withr::local_tempfile(fileext = ".rds")
  .mk_dec(p, c(a = "likely"), "2026-09-14 10:00")
  occ <- .mk_occ(c(a = "unlikely"))
  r <- suppressMessages(drop_stale_seeded_decisions(occ, p, dry_run = FALSE, backup = FALSE))
  expect_equal(r$n_stale, 0L)
  expect_equal(r$n_real, 1L)
  expect_equal(nrow(readRDS(p)), 1L)
})

test_that("an unchanged seeded decision is kept", {
  p <- withr::local_tempfile(fileext = ".rds")
  .mk_dec(p, c(a = "likely"), "seeded from the completed run of 2026-09-11")
  r <- suppressMessages(drop_stale_seeded_decisions(.mk_occ(c(a = "likely")), p,
                                                    dry_run = FALSE, backup = FALSE))
  expect_equal(r$n_stale, 0L)
  expect_equal(nrow(readRDS(p)), 1L)
})

test_that("a point absent from this run is left alone", {
  # Absence from the current data is not evidence the verdict changed.
  p <- withr::local_tempfile(fileext = ".rds")
  .mk_dec(p, c(a = "likely", gone = "likely"), "seeded from x")
  r <- suppressMessages(drop_stale_seeded_decisions(.mk_occ(c(a = "likely")), p,
                                                    dry_run = FALSE, backup = FALSE))
  expect_equal(r$n_stale, 0L)
  expect_equal(nrow(readRDS(p)), 2L)
})

test_that("dry_run writes nothing", {
  p <- withr::local_tempfile(fileext = ".rds")
  .mk_dec(p, c(a = "likely"), "seeded from x")
  before <- readRDS(p)
  r <- suppressMessages(drop_stale_seeded_decisions(.mk_occ(c(a = "unlikely")), p))
  expect_equal(r$n_stale, 1L)
  expect_equal(readRDS(p), before)
})

test_that("drop_stale_seeded_decisions validates its inputs", {
  p <- withr::local_tempfile(fileext = ".rds")
  .mk_dec(p, c(a = "likely"), "seeded from x")
  expect_error(drop_stale_seeded_decisions(data.frame(x = 1), p), "point_id")
  expect_error(drop_stale_seeded_decisions(.mk_occ(c(a = "likely")), "no_such.rds"), "not found")
  expect_error(drop_stale_seeded_decisions("notadf", p), "dataframe")
})
