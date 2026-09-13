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
  dec <- suppressMessages(save_spatial_review_decisions(reviewed, path))
  expect_equal(nrow(dec), 4L)   # one row per point_id
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
