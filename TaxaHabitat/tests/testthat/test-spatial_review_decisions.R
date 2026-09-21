# save_spatial_review_decisions() / apply_spatial_review_decisions() -- 2026-09-12

.flagged <- function() {
  data.frame(
    point_id = c("p1", "p1", "p2", "p3", "p4"),
    taxon_name = c("A", "B", "A", "C", "D"),
    decimalLatitude = c(34.4, 34.4, 34.5, 34.6, 34.7),
    decimalLongitude = -120.4,
    main_habitat = c("Marine", "Marine", "Marine", "Terrestrial", "Marine"),
    spatial_flag = c("questionable", "questionable", "likely", "unlikely", "questionable"),
    spatial_flag_reason = c("r1", "r1", "ok", "r3", "r4"),
    stringsAsFactors = FALSE
  )
}

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
  expect_equal(nrow(dec), 5L)   # one row per (point_id, taxon_name): p1 has taxa A and B
  expect_equal(dec$habitat_reassigned[dec$point_id == "p3"], TRUE)    # Terrestrial -> Marine was the reviewer
  expect_equal(dec$habitat_reassigned[dec$point_id == "p1"], c(FALSE, FALSE))   # p1's habitat is the automatic one
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
  new_row <- data.frame(
    point_id = "p9", taxon_name = "Z", decimalLatitude = 35, decimalLongitude = -120.4,
    main_habitat = "Marine", spatial_flag = "questionable", spatial_flag_reason = "new",
    stringsAsFactors = FALSE
  )
  fresh <- rbind(.flagged(), new_row)
  out <- suppressMessages(apply_spatial_review_decisions(fresh, path))
  expect_equal(attr(out, "pending_point_ids"), "p9")
  later <- .flagged()
  later$spatial_flag[later$point_id == "p4"] <- "likely"
  dec <- suppressMessages(save_spatial_review_decisions(later, path))
  expect_equal(dec$spatial_flag[dec$point_id == "p4"], "likely")
  expect_equal(nrow(dec), 5L)   # one row per (point_id, taxon_name): p1 has taxa A and B
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
  fresh <- .flagged()
  fresh$main_habitat[fresh$point_id == "p2"] <- "Estuarine"   # today's automatic assignment moved
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
  r1 <- .flagged()
  r1$main_habitat[r1$point_id == "p3"] <- "Marine"
  suppressMessages(save_spatial_review_decisions(r1, path, before = .flagged()))
  applied <- suppressMessages(apply_spatial_review_decisions(.flagged(), path))   # p3 now reads Marine
  suppressMessages(save_spatial_review_decisions(applied, path, before = applied))  # reviewer changed nothing
  dec <- readRDS(path)
  expect_true(dec$habitat_reassigned[dec$point_id == "p3"])
})

test_that("two taxa sharing a point_id get their OWN decisions, not each other's (D2, 2026-09-21)", {
  # gull's flag is deliberately left untouched (still needs review); salmon's
  # is fixed by the reviewer. Both share point_id "p1".
  flagged <- data.frame(
    point_id = c("p1", "p1"),
    taxon_name = c("gull", "salmon"),
    decimalLatitude = 34.4, decimalLongitude = -120.4,
    main_habitat = c("Terrestrial", "Terrestrial"),
    spatial_flag = c("unlikely", "unlikely"),
    spatial_flag_reason = c("gull_auto", "salmon_auto"),
    stringsAsFactors = FALSE
  )
  reviewed <- flagged
  reviewed$spatial_flag[reviewed$taxon_name == "salmon"] <- "likely"
  reviewed$main_habitat[reviewed$taxon_name == "salmon"] <- "Marine"
  # gull's row is UNCHANGED -- still needs review.

  path <- file.path(withr::local_tempdir(), "dec.rds")
  dec <- suppressMessages(save_spatial_review_decisions(reviewed, path, before = flagged))
  expect_equal(nrow(dec), 2L)   # one row per (point_id, taxon_name), not one per point_id
  expect_setequal(dec$taxon_name, c("gull", "salmon"))
  expect_equal(dec$main_habitat[dec$taxon_name == "salmon"], "Marine")
  expect_equal(dec$spatial_flag[dec$taxon_name == "gull"], "unlikely")

  out <- suppressMessages(apply_spatial_review_decisions(flagged, path))
  # salmon's fix is applied ...
  expect_equal(out$main_habitat[out$taxon_name == "salmon"], "Marine")
  expect_equal(out$spatial_flag[out$taxon_name == "salmon"], "likely")
  # ... and gull's genuinely-still-wrong flag is NOT silently overwritten with
  # salmon's fix (the D2 failure mode): gull keeps its own saved decision,
  # unchanged, and is not pending -- it WAS reviewed this session (it just
  # was not the row the reviewer chose to change), matching how a point kept
  # "questionable" but present in `reviewed` was already treated as decided
  # before this fix.
  expect_equal(out$main_habitat[out$taxon_name == "gull"], "Terrestrial")
  expect_equal(out$spatial_flag[out$taxon_name == "gull"], "unlikely")
  expect_equal(attr(out, "pending_point_ids"), character(0))
  expect_equal(attr(out, "n_pending_review"), 0L)
})

test_that(paste(
  "an old-format decisions file (no taxon_name) applies nothing at an ambiguous point and warns,",
  "but still applies at an unambiguous one (2026-09-21)"
), {
  flagged <- data.frame(
    point_id = c("p1", "p1", "p2"),
    taxon_name = c("gull", "salmon", "otter"),
    decimalLatitude = 34.4, decimalLongitude = -120.4,
    main_habitat = c("Terrestrial", "Terrestrial", "Terrestrial"),
    spatial_flag = c("unlikely", "unlikely", "unlikely"),
    spatial_flag_reason = c("gull_auto", "salmon_auto", "otter_auto"),
    stringsAsFactors = FALSE
  )
  # An old-format file: no taxon_name column at all, one row per point_id --
  # exactly what save_spatial_review_decisions() wrote before this fix.
  old_format <- data.frame(
    point_id = c("p1", "p2"),
    spatial_flag = c("likely", "likely"),
    main_habitat = c("Marine", "Marine"),
    decided_at = c("2026-01-01 00:00", "2026-01-01 00:00"),
    habitat_reassigned = c(TRUE, TRUE),
    stringsAsFactors = FALSE
  )
  path <- file.path(withr::local_tempdir(), "dec.rds")
  saveRDS(old_format, path)

  # NOTE: testthat 3e's expect_warning() returns the CAPTURED CONDITION, not
  # the wrapped expression's value, when a regexp is supplied -- so `out`
  # must be assigned INSIDE the expression, not from expect_warning()'s
  # own return value.
  expect_warning(
    out <- suppressMessages(apply_spatial_review_decisions(flagged, path)),
    "1 point_id\\(s\\).*no recorded taxon_name.*p1"
  )
  # p1 has 2 taxa in the current data -- ambiguous, nothing applied, still pending.
  expect_equal(out$spatial_flag[out$point_id == "p1"], c("unlikely", "unlikely"))
  expect_equal(out$main_habitat[out$point_id == "p1"], c("Terrestrial", "Terrestrial"))
  expect_true("p1" %in% attr(out, "pending_point_ids"))
  # p2 has exactly 1 taxon -- unambiguous, the old-format decision applies.
  expect_equal(out$spatial_flag[out$point_id == "p2"], "likely")
  expect_equal(out$main_habitat[out$point_id == "p2"], "Marine")
  expect_false("p2" %in% attr(out, "pending_point_ids"))
})

test_that(paste(
  "apply_spatial_review_decisions is idempotent: applying twice does not compound spatial_flag_reason",
  "and n_applied is 0 the second time (2026-09-21)"
), {
  path <- file.path(withr::local_tempdir(), "dec.rds")
  reviewed <- .flagged()
  reviewed$spatial_flag[reviewed$point_id == "p1"] <- "likely"
  suppressMessages(save_spatial_review_decisions(reviewed, path, before = .flagged()))

  once <- suppressMessages(apply_spatial_review_decisions(.flagged(), path))
  expect_true(attr(once, "n_applied") > 0L)
  expect_match(once$spatial_flag_reason[once$point_id == "p1"][1], "^reviewer decision \\(.*\\); auto: r1$")

  twice <- suppressMessages(apply_spatial_review_decisions(once, path))
  expect_equal(attr(twice, "n_applied"), 0L)
  # Same flag/habitat/reason content as after the first apply -- no compounding.
  expect_equal(twice[, c("spatial_flag", "main_habitat", "spatial_flag_reason")],
              once[, c("spatial_flag", "main_habitat", "spatial_flag_reason")])
  expect_false(grepl("reviewer decision.*reviewer decision", twice$spatial_flag_reason[twice$point_id == "p1"][1]))

  # A third application, for good measure -- the marker must not grow.
  thrice <- suppressMessages(apply_spatial_review_decisions(twice, path))
  expect_equal(attr(thrice, "n_applied"), 0L)
  expect_equal(thrice[, c("spatial_flag", "main_habitat", "spatial_flag_reason")],
              twice[, c("spatial_flag", "main_habitat", "spatial_flag_reason")])
})

test_that("a malformed decisions file raises a named, caught error instead of a cryptic base-R one", {
  # A bare atomic vector -- e.g. the path was accidentally overwritten.
  path1 <- withr::local_tempfile(fileext = ".rds")
  saveRDS(1:5, path1)
  expect_error(apply_spatial_review_decisions(.flagged(), path1), "not a data frame")
  expect_error(suppressWarnings(save_spatial_review_decisions(.flagged(), path1)), "not a data frame")

  # An empty list().
  path2 <- withr::local_tempfile(fileext = ".rds")
  saveRDS(list(), path2)
  expect_error(apply_spatial_review_decisions(.flagged(), path2), "not a data frame")
  expect_error(suppressWarnings(save_spatial_review_decisions(.flagged(), path2)), "not a data frame")

  # A data frame missing `point_id` -- previously silently treated as zero
  # usable decisions, with no warning that the file's schema didn't match.
  path3 <- withr::local_tempfile(fileext = ".rds")
  saveRDS(data.frame(spatial_flag = "likely", main_habitat = "Marine",
                     decided_at = "x", habitat_reassigned = FALSE,
                     stringsAsFactors = FALSE), path3)
  expect_error(apply_spatial_review_decisions(.flagged(), path3), "missing required column.*point_id")
  expect_error(suppressWarnings(save_spatial_review_decisions(.flagged(), path3)), "missing required column.*point_id")

  # A data frame with the right columns but the wrong type.
  path4 <- withr::local_tempfile(fileext = ".rds")
  saveRDS(data.frame(point_id = 1L, spatial_flag = "likely", main_habitat = "Marine",
                     decided_at = "x", habitat_reassigned = "not_logical",
                     stringsAsFactors = FALSE), path4)
  expect_error(apply_spatial_review_decisions(.flagged(), path4), "wrong type")
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
