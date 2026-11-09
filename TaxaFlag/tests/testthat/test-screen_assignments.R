mk <- function(taxon = "Fundulus parvipinnis", rank = "species", poor = FALSE,
               geo = "likely", hab = "likely", scp = "likely", bir = "species", ...) {
  data.frame(observation_id = paste0("o", seq_along(taxon)), consensus_taxon = taxon,
             consensus_rank = rank, best_identity_rank = bir, poor_absolute_fit = poor,
             llm_geographic_plausibility = geo, llm_habitat_plausibility = hab,
             llm_scope_plausibility = scp, stringsAsFactors = FALSE, ...)
}
post <- function(obs = "o1", name = c("Fundulus parvipinnis", "Fundulus heteroclitus"),
                 rank = "species", type = c("specific_candidate", "specific_candidate"),
                 genus = "Fundulus", family = "Fundulidae", score = c(1, 0.8),
                 theta = c(NA, 0.2), branch = c("none", "kernel_estimated")) {
  data.frame(observation_id = obs, taxon_name = name, taxon_name_rank = rank,
             hypothesis_type = type, genus = genus, family = family,
             score_likelihood = score, theta_mean = theta, prior_branch = branch,
             stringsAsFactors = FALSE)
}
scr <- function(...) suppressMessages(screen_assignments(...))

test_that("I1 keeps good fit with plausible geography", {
  for (g in c("likely", "possible")) {
    r <- scr(mk(geo = g))
    expect_equal(r$identity_action, "keep")
    expect_equal(r$suggested_action, "keep")
  }
  r <- scr(mk())
  expect_equal(r$identity_taxon_after, "Fundulus parvipinnis")
  expect_match(r$identity_reason, "I1")
})

test_that("I2 without posterior_df is always review, and suggests verify_range not exclude", {
  r <- scr(mk(geo = "unlikely"))
  expect_equal(r$identity_action, "review")
  # NOT "exclude". The CalIntertidal reporting layer drops rows on
  # suggested_action == "exclude" (_setup.R:156-159), so the old mapping dropped
  # a row the screen wanted looked at -- 132 of 191 such rows in the r12c
  # archive. The detection must survive a review.
  expect_equal(r$suggested_action, "verify_range")
  expect_false(r$suggested_action %in% "exclude")
  expect_equal(r$identity_taxon_after, "Fundulus parvipinnis")
  expect_match(r$identity_reason, "suggested_action is verify_range", fixed = TRUE)
})

test_that("blank evidence still overrides a verify_range row to exclude", {
  # The override survives the new value on purpose: contamination evidence is
  # POSITIVE evidence of a problem, unlike an unsettled range question. Without
  # this, "verify_range" would have quietly rescued blank-flagged rows.
  d <- mk(geo = "unlikely")
  d$blank_flag <- TRUE
  r <- scr(d, blank_flag_col = "blank_flag")
  expect_equal(r$identity_action, "review")
  expect_equal(r$suggested_action, "exclude")
  expect_match(r$identity_reason, "blank evidence", fixed = TRUE)
})

test_that("I2 moves up to genus for a qualifying local referenced congener", {
  r <- scr(mk(geo = "unlikely"), post())
  expect_equal(r$identity_action, "move_up")
  expect_equal(r$identity_taxon_after, "Fundulus")
  expect_equal(r$identity_rank_after, "genus")
  expect_equal(r$suggested_action, "move_up")
})

test_that("I2 score gap boundary is inclusive at 0.25", {
  inside <- scr(mk(geo = "unlikely"), post(score = c(1, 0.76)))
  outside <- scr(mk(geo = "unlikely"), post(score = c(1, 0.74)))
  expect_equal(inside$identity_action, "move_up")
  expect_equal(outside$identity_action, "review")
  wide <- scr(mk(geo = "unlikely"), post(score = c(1, 0.5)), relative_score_gap = 0.5)
  expect_equal(wide$identity_action, "move_up")
})

test_that("I2 relative must be local and referenced (Fundulus-like score 0 stays review)", {
  expect_equal(scr(mk(geo = "unlikely"), post(score = c(1, 0)))$identity_action, "review")
  notlocal <- scr(mk(geo = "unlikely"), post(theta = c(NA, NA), branch = c("none", "none")))
  expect_equal(notlocal$identity_action, "review")
  notref <- scr(mk(geo = "unlikely"), post(type = c("specific_candidate", "unreferenced_species")))
  expect_equal(notref$identity_action, "review")
  resident <- scr(mk(geo = "unlikely"), post(theta = c(NA, NA), branch = c("none", "resident_observed")))
  expect_equal(resident$identity_action, "move_up")
  theta_only <- scr(mk(geo = "unlikely"), post(branch = c("none", "none")))
  expect_equal(theta_only$identity_action, "move_up")
})

test_that("I2 uses relatives of the same observation only and falls back to family", {
  other <- scr(mk(geo = "unlikely"), post(obs = "oX"))
  expect_equal(other$identity_action, "review")
  fam <- scr(mk(geo = "unlikely"),
             post(name = c("Fundulus parvipinnis", "Lucania parva"), genus = c("Fundulus", "Lucania")))
  expect_equal(fam$identity_action, "move_up")
  expect_equal(fam$identity_taxon_after, "Fundulidae")
  expect_equal(fam$identity_rank_after, "family")
})

test_that("I2 Hemilepidotus-like genus-level move-up", {
  p <- post(name = c("Hemilepidotus hemilepidotus", "Hemilepidotus spinosus"),
            genus = "Hemilepidotus", family = "Cottidae", score = c(0.9, 0.85))
  r <- scr(mk("Hemilepidotus hemilepidotus", geo = "unlikely"), p)
  expect_equal(r$identity_action, "move_up")
  expect_equal(r$identity_taxon_after, "Hemilepidotus")
})

test_that("I3 moves up at the genus boundary and flags coarser calls", {
  sp <- scr(mk(poor = TRUE), post())
  expect_equal(sp$identity_action, "move_up")
  expect_equal(sp$identity_rank_after, "genus")
  expect_equal(sp$identity_taxon_after, "Fundulus")
  ge <- scr(mk("Fundulus", "genus", poor = TRUE, bir = "genus"), post())
  expect_equal(ge$identity_action, "move_up")
  expect_equal(ge$identity_rank_after, "family")
  expect_equal(ge$identity_taxon_after, "Fundulidae")
  fa <- scr(mk("Fundulidae", "family", poor = TRUE, bir = "family"), post())
  expect_equal(fa$identity_action, "keep")
  expect_true(fa$poor_fit_flag)
  expect_equal(sp$poor_fit_flag, FALSE)
  wide <- scr(mk("Fundulidae", "family", poor = TRUE, bir = "family"), post(), move_up_max_rank = "family")
  expect_equal(wide$identity_action, "move_up")
  expect_equal(wide$identity_rank_after, "order")
})

test_that("I3 uses best_identity_rank when coarser than the call", {
  r <- scr(mk(poor = TRUE, bir = "family"), post())
  expect_equal(r$identity_rank_after, "family")
  expect_equal(r$identity_taxon_after, "Fundulidae")
})

test_that("unreferenced exception needs unreferenced winner, species, geography likely", {
  d <- mk(poor = TRUE, winner_hypothesis_type = "unreferenced_species")
  expect_equal(scr(d)$identity_action, "keep")
  expect_false(scr(d)$poor_fit_flag)
  expect_equal(scr(transform(d, llm_geographic_plausibility = "possible"))$identity_action, "move_up")
  expect_equal(scr(transform(d, winner_hypothesis_type = "specific_candidate"))$identity_action, "move_up")
})

test_that("habitat exclusion applies at family or finer, after the exception", {
  expect_equal(scr(mk(poor = TRUE, hab = "unlikely"))$identity_action, "exclude")
  expect_equal(scr(mk("Fundulidae", "family", poor = TRUE, hab = "unlikely"))$identity_action, "exclude")
  o <- scr(mk("Fundulales", "order", poor = TRUE, hab = "unlikely"))
  expect_equal(o$identity_action, "keep")
  expect_true(o$poor_fit_flag)
  o2 <- scr(mk("Fundulales", "order", poor = TRUE, hab = "unlikely"), poor_fit_habitat_exclude_max_rank = "order")
  expect_equal(o2$identity_action, "exclude")
  ex <- scr(mk(poor = TRUE, hab = "unlikely", winner_hypothesis_type = "unreferenced_species"))
  expect_equal(ex$identity_action, "keep")
  good <- scr(mk(hab = "unlikely"))
  expect_equal(good$identity_action, "keep")
})

test_that("I4 excludes poor fit with unlikely geography and clears the taxon", {
  r <- scr(mk(poor = TRUE, geo = "unlikely"))
  expect_equal(r$identity_action, "exclude")
  expect_equal(r$suggested_action, "exclude")
  expect_true(is.na(r$identity_taxon_after))
  expect_true(is.na(r$identity_rank_after))
  expect_true(is.na(r$presence))
})

test_that("presence precedence: scope wins, then habitat, else resident", {
  expect_equal(scr(mk(scp = "unlikely", hab = "unlikely"))$presence, "out_of_scope")
  expect_equal(scr(mk(hab = "unlikely"))$presence, "off_habitat")
  expect_equal(scr(mk())$presence, "resident")
  expect_equal(scr(mk(hab = "possible"))$presence, "resident")
  r <- scr(mk(scp = "unlikely", hab = "unlikely"))
  expect_equal(r$suggested_action, "keep")
})

test_that("blank_flag_col forces suggested exclude only when TRUE", {
  d <- mk(taxon = c("A a", "B b", "C c"), blank = c(TRUE, FALSE, NA))
  r <- scr(d, blank_flag_col = "blank")
  expect_equal(r$suggested_action, c("exclude", "keep", "keep"))
  expect_equal(r$identity_action, c("keep", "keep", "keep"))
  expect_match(r$identity_reason[1], "blank evidence")
  expect_no_match(r$identity_reason[2], "blank evidence")
  n <- scr(d)
  expect_equal(n$suggested_action, rep("keep", 3))
  expect_error(scr(d, blank_flag_col = "nope"), "blank_flag_col")
})

test_that("isolated_geography_unlikely is TRUE, FALSE or NA", {
  d <- mk(taxon = c("A a", "A a", "B b", "C c"), geo = c("unlikely", "unlikely", "unlikely", "likely"),
          n_tubes = c(1, 2, 4, 1))
  d$observation_id <- paste0("o", 1:4)
  r <- scr(d)
  expect_equal(r$isolated_geography_unlikely, c(TRUE, TRUE, FALSE, FALSE))
  d2 <- d; d2$n_tubes[3] <- NA
  expect_true(is.na(scr(d2)$isolated_geography_unlikely[3]))
  expect_true(all(is.na(scr(mk(geo = "unlikely"))$isolated_geography_unlikely)))
  # A review row: the point is that isolated_geography_unlikely never ACTS, so
  # the suggestion is whatever the identity layer decided -- now verify_range.
  expect_equal(scr(d)$suggested_action[1], "verify_range")
  e <- scr(mk(geo = "likely", n_tubes = 1))
  expect_equal(e$suggested_action, "keep")
})

test_that("NA verdicts trigger no rule", {
  expect_equal(scr(mk(geo = NA_character_))$identity_action, "keep")
  expect_equal(scr(mk(poor = NA))$identity_action, "keep")
  r <- scr(mk(hab = NA_character_, scp = NA_character_))
  expect_true(is.na(r$presence))
  expect_equal(r$suggested_action, "keep")
  p <- scr(mk(poor = TRUE, geo = NA_character_, hab = NA_character_))
  expect_equal(p$identity_action, "move_up")
})

test_that("missing optional columns skip their rules with a message", {
  d <- mk(poor = TRUE, hab = "unlikely", scp = "unlikely")
  d$llm_habitat_plausibility <- NULL
  expect_message(r <- screen_assignments(d), "habitat")
  expect_equal(r$identity_action, "move_up")
  d$llm_scope_plausibility <- NULL
  expect_message(r2 <- screen_assignments(d), "scope")
  expect_true(is.na(r2$presence))
})

test_that("required columns and arguments are validated", {
  d <- mk()
  expect_error(screen_assignments(d[, setdiff(names(d), "poor_absolute_fit")]), "poor_absolute_fit")
  expect_error(screen_assignments(d[, setdiff(names(d), "observation_id")]), "observation_id")
  expect_error(screen_assignments("x"), "data frame")
  expect_error(scr(d, move_up_max_rank = "tribe"), "move_up_max_rank")
  expect_error(scr(d, relative_score_gap = -1), "relative_score_gap")
  expect_error(scr(d, posterior_df = post()[, c("observation_id", "taxon_name")]), "posterior_df")
})

test_that("rows are never dropped and order is preserved", {
  d <- mk(taxon = c("A a", "B b", "C c", "D d"), poor = c(TRUE, FALSE, TRUE, FALSE),
          geo = c("unlikely", "unlikely", "likely", "likely"))
  r <- scr(d)
  expect_equal(nrow(r), 4L)
  expect_equal(r$consensus_taxon, d$consensus_taxon)
  expect_equal(r$observation_id, d$observation_id)
  expect_true(all(names(d) %in% names(r)))
  expect_true(all(c("identity_action", "identity_taxon_after", "identity_rank_after",
                    "identity_reason", "suggested_action", "presence", "poor_fit_flag",
                    "isolated_geography_unlikely") %in% names(r)))
  expect_equal(nrow(scr(d[0, ])), 0L)
})

test_that("custom column names and a per-site geography column work", {
  d <- mk(geo = "likely")
  d$geo_site <- "unlikely"; d$pf <- TRUE
  r <- scr(d, geography_col = "geo_site", poor_fit_col = "pf")
  expect_equal(r$identity_action, "exclude")
})

test_that("output keeps every input row, its order and all original column values", {
  d <- mk(taxon = c("A a", "B b", "C c", "D d", "E e"), poor = c(TRUE, FALSE, TRUE, FALSE, TRUE),
          geo = c("unlikely", "unlikely", "likely", "likely", "unlikely"),
          hab = c("likely", "likely", "unlikely", "likely", "likely"))
  d$extra <- letters[1:5]
  r <- scr(d)
  expect_equal(nrow(r), nrow(d))
  expect_true("exclude" %in% r$suggested_action)
  expect_identical(r[names(d)], d)
})

test_that("rule_counts attribute lists every rule and matches a small fixture", {
  d <- mk(taxon = c("A a", "B b", "C c", "D d", "E e", "F f", "G g"),
          rank = c("species", "species", "species", "species", "family", "species", "species"),
          poor = c(FALSE, FALSE, TRUE, TRUE, TRUE, TRUE, TRUE),
          geo = c("likely", "unlikely", "likely", "unlikely", "likely", "likely", "likely"),
          hab = c("likely", "likely", "likely", "likely", "likely", "unlikely", "likely"),
          blank = c(FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE))
  d$winner_hypothesis_type <- c(rep("specific_candidate", 6), "unreferenced_species")
  expect_message(r <- screen_assignments(d, blank_flag_col = "blank"), "I2_relative = not evaluated.*not evaluated \\(no posterior_df\\)")
  rc <- attr(r, "rule_counts")
  expect_s3_class(rc, "data.frame")
  expect_equal(rc$rule, c("I1", "I2_relative", "I2_review", "I3_move_up", "I3_flag_coarse",
                          "I3_exception", "poor_fit_habitat_exclude", "I4", "blank_evidence"))
  expect_equal(rc$n_rows, c(1L, NA, 1L, 1L, 1L, 1L, 1L, 1L, 1L))
  expect_equal(rc$evaluated, c(TRUE, FALSE, rep(TRUE, 7)))
  p <- post(obs = "o2", name = c("B b", "B c"), genus = "B")
  d2 <- d; d2$observation_id <- paste0("o", 1:7)
  expect_message(r2 <- screen_assignments(d2, p), "relative_score_gap = 0.25) fired on 1 rows")
  expect_equal(attr(r2, "rule_counts")$n_rows[2], 1L)
  expect_equal(attr(scr(d[0, ]), "rule_counts")$n_rows, c(0L, NA, rep(0L, 6), NA))
})

test_that("rule_counts distinguishes fired-zero (0, evaluated) from not evaluable (NA)", {
  d <- mk(taxon = c("A a", "B b"))
  expect_message(r <- screen_assignments(d, post(obs = "o9"), blank_flag_col = NULL),
                 "I4 = 0.*fired on 0 rows")
  rc <- attr(r, "rule_counts")
  expect_equal(nrow(rc), 9L)
  expect_equal(rc$n_rows[rc$rule == "I4"], 0L)
  expect_true(rc$evaluated[rc$rule == "I4"])
  expect_equal(rc$n_rows[rc$rule == "I2_relative"], 0L)
  expect_true(rc$evaluated[rc$rule == "I2_relative"])
  expect_true(is.na(rc$n_rows[rc$rule == "blank_evidence"]))
  expect_false(rc$evaluated[rc$rule == "blank_evidence"])
  d$llm_habitat_plausibility <- NULL
  r2 <- suppressMessages(screen_assignments(d))
  rc2 <- attr(r2, "rule_counts")
  expect_true(is.na(rc2$n_rows[rc2$rule == "poor_fit_habitat_exclude"]))
  expect_false(rc2$evaluated[rc2$rule == "poor_fit_habitat_exclude"])
  expect_false(rc2$evaluated[rc2$rule == "I3_exception"])
})

# ---- resolution (flag_resolution) -------------------------------------------
# A row carrying every input the resolution reads, all agreeing with a keep.
rv <- function(..., .drop = character(0)) {
  a <- list(...)
  base <- list(taxon = "Fundulus parvipinnis", rank = "species", poor = FALSE,
               geo = "likely", hab = "likely", scp = "likely", bir = "species")
  extra <- list(likelihood_support = 0.9, consensus_posterior = 0.95, prior_role = "agrees",
                consensus_confidence_score = 0.9, robust_lower_posterior = 0.9,
                winner_has_occurrence_record = TRUE, llm_p_habitat = 0.9,
                llm_p_habitat_lo = 0.8, llm_p_habitat_hi = 0.95)
  base[intersect(names(a), names(base))] <- a[intersect(names(a), names(base))]
  extra[intersect(names(a), names(extra))] <- a[intersect(names(a), names(extra))]
  more <- a[setdiff(names(a), c(names(base), names(extra)))]
  d <- do.call(mk, base)
  for (nm in names(extra)) d[[nm]] <- extra[[nm]]
  for (nm in names(more)) d[[nm]] <- more[[nm]]
  d[setdiff(names(d), .drop)]
}
res <- function(d, ...) scr(d, ...)[c("flag_resolution", "flag_resolution_basis", "flag_consistency_score")]

test_that("R7 confirms a keep that every independent vote supports", {
  r <- res(rv())
  expect_equal(r$flag_resolution, "confirmed")
  expect_equal(r$flag_consistency_score, 1)
  expect_match(r$flag_resolution_basis, "^R7; seq=support")
})

test_that("R0: no call, or fewer than two votes cast, is not_assessed", {
  r <- res(rv(taxon = NA_character_))
  expect_equal(r$flag_resolution, "not_assessed")
  d <- rv(poor = NA, geo = NA_character_, likelihood_support = NA_real_,
          winner_has_occurrence_record = NA, llm_p_habitat = NA_real_)
  r <- res(d)
  expect_equal(r$flag_resolution, "not_assessed")
  expect_true(is.na(r$flag_consistency_score))
})

test_that("R1: a blank-evidence exclude is upheld, never softened", {
  r <- res(rv(blank = TRUE), blank_flag_col = "blank")
  expect_equal(r$flag_resolution, "upheld")
  expect_match(r$flag_resolution_basis, "^R1;")
  r <- res(rv(validity_flag = "invalid_lab_contaminant", poor = TRUE, geo = "unlikely",
              likelihood_support = 0.05))
  expect_match(r$flag_resolution_basis, "^R1;")
})

test_that("R2: an exclude the evidence contradicts is conflicted", {
  # I4 exclude (poor fit, geography unlikely) on a call no finer than its best
  # match, with local records and strong sequence support: records vs geography split.
  r <- res(rv(poor = TRUE, geo = "unlikely"))
  expect_equal(scr(rv(poor = TRUE, geo = "unlikely"))$suggested_action, "exclude")
  expect_equal(r$flag_resolution, "conflicted")
  expect_match(r$flag_resolution_basis, "occ=split\\(records yes, geo unlikely\\)")
  # Habitat exclusion while all three votes support.
  d <- rv(poor = TRUE, hab = "unlikely")
  expect_equal(scr(d)$suggested_action, "exclude")
  expect_equal(res(d)$flag_resolution, "conflicted")
})

test_that("R3: an exclude the evidence agrees with is confirmed", {
  d <- rv(poor = TRUE, geo = "unlikely", likelihood_support = 0.05,
          winner_has_occurrence_record = FALSE, llm_p_habitat = 0.05,
          llm_p_habitat_lo = 0.01, llm_p_habitat_hi = 0.2)
  r <- res(d)
  expect_equal(r$flag_resolution, "confirmed")
  expect_equal(r$flag_consistency_score, -1)
})

test_that("R4/R5: verify_range is softened only by the CalIntertidal local-record rule", {
  d <- rv(geo = "possible", llm_geographic_plausibility_site = "unlikely")
  g <- "llm_geographic_plausibility_site"
  expect_equal(scr(d, geography_col = g)$suggested_action, "verify_range")
  expect_equal(res(d, geography_col = g)$flag_resolution, "upheld")          # column absent
  d$geo_local_record_location_n <- 2
  expect_equal(res(d, geography_col = g)$flag_resolution, "upheld")          # 2 < 3
  d$geo_local_record_location_n <- 3
  r <- res(d, geography_col = g)
  expect_equal(r$flag_resolution, "softened")
  expect_match(r$flag_resolution_basis, "^R4;.*local_record_locations=3")
  d2 <- d; d2$llm_geographic_plausibility <- "unlikely"                       # study-wide unlikely
  expect_equal(res(d2, geography_col = g)$flag_resolution, "upheld")
  d3 <- d; d3$likelihood_support <- 0.3                                       # no SEQ support
  expect_equal(res(d3, geography_col = g)$flag_resolution, "upheld")
})

test_that("R4 is NOT EVALUABLE when only one geographic scale is present", {
  # A verify_range row reads "unlikely" on the column that RAISED it, so
  # re-reading that same column could never soften it. Under the default
  # geography_col, with no per-site column in the frame, R4 cannot fire at
  # all -- and a count of 0 would read as "fired on nothing", which is a
  # different claim from "could not be asked".
  d <- rv(geo = "unlikely")
  d$geo_local_record_location_n <- 3
  x <- scr(d)
  expect_equal(x$suggested_action, "verify_range")
  rc <- attr(x, "resolution_counts")
  expect_false(rc$evaluated[rc$rule == "R4"])
  expect_true(is.na(rc$n_rows[rc$rule == "R4"]))
  expect_false(identical(x$flag_resolution, "softened"))
  # every other rule stays evaluable, so the flag is specific to R4
  expect_true(all(rc$evaluated[rc$rule != "R4"]))
})

test_that("R4 softens a verify_range row via the SECOND geographic scale", {
  # The study scale raised the flag; the per-site scale is a DIFFERENT reading
  # and can soften it. Under the old rule R4 re-read the study column, which
  # is "unlikely" by construction here, so this row was always upheld.
  d <- rv(geo = "unlikely")
  d$llm_geographic_plausibility_site <- "likely"
  d$geo_local_record_location_n <- 3
  r <- res(d)
  expect_equal(r$flag_resolution, "softened")
  expect_match(r$flag_resolution_basis, "^R4;.*local_record_locations=3")
  rc <- attr(scr(d), "resolution_counts")
  expect_true(rc$evaluated[rc$rule == "R4"])
  expect_equal(rc$n_rows[rc$rule == "R4"], 1L)
})

test_that("R4 is NOT EVALUABLE without the local-record count, however many geographic scales are present", {
  # BOTH geographic scales are here, so a check that only asks "is there a
  # second geography column?" calls R4 evaluable. But R4 also reads
  # geo_local_record_location_n, and without it `!is.na(lrn)` is FALSE on
  # every row, so R4 cannot fire whatever the geography says. "R4 = 0" would
  # be the same zero-versus-never-asked confusion as a missing column.
  d <- rv(geo = "unlikely")
  d$llm_geographic_plausibility_site <- "likely"
  expect_false("geo_local_record_location_n" %in% names(d))   # the missing input
  x <- scr(d)
  expect_equal(x$suggested_action, "verify_range")             # the row reached R4's branch
  rc <- attr(x, "resolution_counts")
  expect_false(rc$evaluated[rc$rule == "R4"])
  expect_true(is.na(rc$n_rows[rc$rule == "R4"]))
  expect_equal(x$flag_resolution, "upheld")                    # R5, not a softening
})

test_that("R4 is NOT EVALUABLE when the second scale is present but says nothing on the row", {
  # Evaluability is per ROW, not per column. The column exists and carries no
  # verdict for this row, so no question was put to the row -- a column-level
  # check would call it evaluable and report a zero it did not earn.
  for (silent in list(NA_character_, "")) {
    d <- rv(geo = "unlikely")
    d$llm_geographic_plausibility_site <- silent
    d$geo_local_record_location_n <- 3
    rc <- attr(scr(d), "resolution_counts")
    expect_false(rc$evaluated[rc$rule == "R4"])
    expect_true(is.na(rc$n_rows[rc$rule == "R4"]))
  }
  # Same again for a present-but-silent local-record count.
  d <- rv(geo = "unlikely")
  d$llm_geographic_plausibility_site <- "likely"
  d$geo_local_record_location_n <- NA_real_
  rc <- attr(scr(d), "resolution_counts")
  expect_false(rc$evaluated[rc$rule == "R4"])
})

test_that("R4 reports a real zero when a row WAS asked and the answer was no", {
  # Every input is present, the row reached the test, and the other scale
  # simply does not support softening. That is a 0 the reader can trust, and
  # the fix for the never-asked case must not swallow it.
  d <- rv(geo = "unlikely")
  d$llm_geographic_plausibility_site <- "unlikely"
  d$geo_local_record_location_n <- 3
  x <- scr(d)
  rc <- attr(x, "resolution_counts")
  expect_true(rc$evaluated[rc$rule == "R4"])
  expect_equal(rc$n_rows[rc$rule == "R4"], 0L)
  expect_equal(x$flag_resolution, "upheld")
  expect_message(screen_assignments(d), "R4 = 0")
})

test_that("n_evaluable counts the rows each rule was ASKED, not the rows it fired on", {
  # Three verify_range rows: two carry both of R4's inputs, the third has no
  # verdict on the second scale. n_evaluable is the denominator n_rows is a
  # numerator of, so it must be 2 -- counting the unaskable row would restate
  # the very confusion the column exists to remove.
  d <- rbind(rv(geo = "unlikely"), rv(geo = "unlikely"), rv(geo = "unlikely"))
  d$observation_id <- c("o1", "o2", "o3")
  d$llm_geographic_plausibility_site <- c("likely", "unlikely", NA_character_)
  d$geo_local_record_location_n <- c(3, 3, 3)
  rc <- attr(scr(d), "resolution_counts")
  expect_equal(rc$n_evaluable[rc$rule == "R4"], 2L)
  expect_true(rc$evaluated[rc$rule == "R4"])
  expect_equal(rc$n_rows[rc$rule == "R4"], 1L)        # only the "likely" row softens
  # R5 is R4's fall-through: the row R4 declined and the row it could not ask.
  expect_equal(rc$n_evaluable[rc$rule == "R5"], 2L)
  expect_equal(rc$n_rows[rc$rule == "R5"], 2L)
  # The gate is put to every row, whatever branch the row then takes.
  expect_equal(rc$n_evaluable[rc$rule == "R0"], 3L)
  # No row took the exclude or keep branch. Those rules could still have
  # fired on a row that reached them, so they are 0 with evaluated TRUE --
  # "nothing asked", which is not "cannot be asked".
  for (r in c("R1", "R2", "R3", "R6", "R7")) {
    expect_equal(rc$n_evaluable[rc$rule == r], 0L)
    expect_true(rc$evaluated[rc$rule == r])
    expect_equal(rc$n_rows[rc$rule == r], 0L)
  }
  # The invariant that makes the pair readable at all.
  expect_true(all(rc$n_rows[rc$evaluated] <= rc$n_evaluable[rc$evaluated]))
})

test_that("n_evaluable is 0 with evaluated FALSE where R4's inputs are absent", {
  d <- rv(geo = "unlikely")
  d$geo_local_record_location_n <- 3                   # present; the scale is not
  rc <- attr(scr(d), "resolution_counts")
  expect_equal(rc$n_evaluable[rc$rule == "R4"], 0L)
  expect_false(rc$evaluated[rc$rule == "R4"])
  expect_true(is.na(rc$n_rows[rc$rule == "R4"]))
  expect_identical(names(rc), c("rule", "n_rows", "evaluated", "n_evaluable"))
})

test_that("R6: a keep resting on weak sequence or on the prior is escalated", {
  expect_equal(res(rv(likelihood_support = 0.05))$flag_resolution, "escalated")
  r <- res(rv(likelihood_support = 0.4, prior_role = "narrowed"))
  expect_equal(r$flag_resolution, "escalated")
  expect_match(r$flag_resolution_basis, "prior_driven=yes")
})

test_that("a move_up is not escalated for the poor match that caused it", {
  d <- rv(poor = TRUE, rank = "species", bir = "genus", genus = "Fundulus")
  expect_equal(scr(d)$suggested_action, "move_up")
  r <- res(d)
  expect_match(r$flag_resolution_basis, "seq=against")
  expect_false(r$flag_resolution %in% "escalated")
})

test_that("circularity guard: a prior-driven call loses its occurrence support", {
  # Same row; only prior_role differs. If OCC support were still counted on the
  # prior-driven row, both would read confirmed with score 1.
  a <- res(rv(likelihood_support = 0.6, prior_role = "agrees"))
  b <- res(rv(likelihood_support = 0.6, prior_role = "narrowed"))
  expect_equal(a$flag_resolution, "confirmed")
  expect_equal(a$flag_consistency_score, 1)
  expect_equal(b$flag_resolution, "upheld")
  expect_equal(b$flag_consistency_score, 2/3)
  expect_match(b$flag_resolution_basis, "occ=support->neutral\\(prior-driven\\)")
  # The ratio route: likelihood_support below half the posterior.
  c <- res(rv(likelihood_support = 0.4, consensus_posterior = 0.95))
  expect_match(c$flag_resolution_basis, "prior_driven=yes")
})

test_that("records and geography cast ONE occurrence vote", {
  # SEQ against, OCC support (records yes, geography likely), ECO against.
  # One OCC vote: (1 - 2) / 3. Counted twice it would be (2 - 2) / 4 = 0.
  # consensus_posterior 0.08 keeps the call from reading prior-driven (0.05 >= 0.04).
  r <- res(rv(likelihood_support = 0.05, consensus_posterior = 0.08, llm_p_habitat = 0.05,
              llm_p_habitat_lo = 0.01, llm_p_habitat_hi = 0.2))
  expect_match(r$flag_resolution_basis, "occ=support;")
  expect_equal(r$flag_consistency_score, -1/3)
})

test_that("domestic caveat: missing records are not evidence against", {
  d <- rv(geo = NA_character_, winner_has_occurrence_record = FALSE)
  a <- res(d)
  d$domestic_prior_caveat <- TRUE
  b <- res(d)
  expect_match(a$flag_resolution_basis, "occ=against")
  expect_equal(a$flag_consistency_score, 1/3)
  expect_match(b$flag_resolution_basis, "occ=neutral\\(domestic caveat\\)")
  expect_equal(b$flag_consistency_score, 2/3)
  expect_false(b$flag_resolution %in% "escalated")
})

test_that("demote-only: LLM support without SEQ support is upheld, never confirmed", {
  r <- res(rv(likelihood_support = 0.3, consensus_posterior = 0.35))
  expect_equal(r$flag_consistency_score, 2/3)
  expect_equal(r$flag_resolution, "upheld")
})

test_that("an unstable call cannot be confirmed", {
  expect_equal(res(rv(robust_lower_posterior = 0.3))$flag_resolution, "upheld")
  expect_equal(res(rv(consensus_confidence_score = 0.3))$flag_resolution, "upheld")
})

test_that("a family call is resolved at its own rank, not short-circuited", {
  d <- rv(taxon = "Fundulidae", rank = "family", bir = "family", poor = TRUE,
          consensus_has_occurrence_record = TRUE, winner_has_occurrence_record = FALSE)
  r <- res(d)
  expect_false(r$flag_resolution %in% "not_assessed")
  expect_equal(r$flag_resolution, "confirmed")
  expect_match(r$flag_resolution_basis, "seq=support")
})

test_that("an unreferenced species is not marked down for its expected poor fit", {
  # bir genus: the call is finer than its best match, so for any other species
  # the poor fit would count against.
  d <- rv(poor = TRUE, bir = "genus", winner_hypothesis_type = "unreferenced_species")
  expect_match(res(d)$flag_resolution_basis, "seq=support")
  d$winner_hypothesis_type <- "specific_candidate"
  expect_match(res(d)$flag_resolution_basis, "seq=against")
})

test_that("a habitat range spanning a cut is neutral", {
  expect_match(res(rv(llm_p_habitat = 0.75, llm_p_habitat_lo = 0.05))$flag_resolution_basis, "eco=neutral")
  expect_match(res(rv(llm_p_habitat = 0.05, llm_p_habitat_lo = 0.01,
                      llm_p_habitat_hi = 0.8))$flag_resolution_basis, "eco=neutral")
})

test_that("missing inputs are not_evaluated, with no error", {
  d <- mk()
  r <- res(d)
  expect_match(r$flag_resolution_basis, "eco=not_evaluated")
  expect_false(is.na(r$flag_resolution))
})

test_that("resolve = FALSE returns exactly the pre-resolution result", {
  strip <- function(x) { attr(x, "rule_counts") <- NULL; attr(x, "resolution_counts") <- NULL; x }
  d <- rbind(rv(), rv(poor = TRUE, geo = "unlikely"), rv(likelihood_support = 0.05))
  d$observation_id <- c("o1", "o2", "o3")
  r0 <- scr(d, resolve = FALSE)
  r1 <- scr(d)
  expect_false(any(grepl("^flag_", names(r0))))
  expect_null(attr(r0, "resolution_counts"))
  expect_identical(names(r1)[seq_along(names(r0))], names(r0))
  expect_identical(strip(r1[names(r0)]), strip(r0))
  expect_identical(attr(r1, "rule_counts"), attr(r0, "rule_counts"))
  expect_error(screen_assignments(d, resolve = NA), "resolve")
})

test_that("resolution keeps every row in order and distinguishes a zero from a rule that could not be asked", {
  d <- rbind(rv(), rv(poor = TRUE, geo = "unlikely"), rv(likelihood_support = 0.05),
             rv(taxon = NA_character_))
  d$observation_id <- c("o4", "o1", "o3", "o2")
  r <- scr(d)
  expect_equal(nrow(r), 4L)
  expect_identical(r$observation_id, d$observation_id)
  rc <- attr(r, "resolution_counts")
  expect_identical(rc$rule, paste0("R", 0:7))
  # Every row is accounted for among the rules that COULD be evaluated.
  expect_equal(sum(rc$n_rows, na.rm = TRUE), 4L)
  # A rule that fired on nothing reports 0; a rule that could not be asked
  # reports NA and evaluated = FALSE. Conflating the two is what this test
  # now guards: R4 needs a second geographic scale, and this frame has only
  # the default column, so it is not evaluable rather than zero.
  expect_true(any(rc$n_rows[rc$evaluated] == 0L))
  expect_false(rc$evaluated[rc$rule == "R4"])
  expect_true(is.na(rc$n_rows[rc$rule == "R4"]))
  expect_true(all(rc$evaluated[rc$rule != "R4"]))
  expect_message(screen_assignments(d), "resolution by rule: R0 = 1, R1 = 0")
  expect_message(screen_assignments(d), "R4 = not evaluable")
})
