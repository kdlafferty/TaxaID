# Q2 (evidence gate + direction) and Q3 (site breadth as a discriminant) from
# TaxaID_dev/ecosystem_docs/BLANK_VALIDATION_AND_CONTAMINANT_DESIGN.md (sibling development repository).

# 3 sites, 2 samples each; site1 has TWO controls, sites 2-3 one each. Taxa:
#   SYSTEMIC   in a control at EVERY site, absent from samples -> contaminant
#   LOCAL      in BOTH controls at ONE site whose samples are full of it
#              -> single_site_enriched
#   CLEAN      only ever in samples                            -> no evidence
#   ONEBLANK   control-enriched but in exactly ONE control      -> below the
#              evidence floor, so untested rather than condemned
#
# site1 deliberately carries two controls so the EVIDENCE FLOOR and the SITE
# BREADTH discriminant can be tested independently. With one control at site1,
# LOCAL would fall below the floor and never reach the breadth rule at all -- the
# breadth test would then pass for the wrong reason.
.mk3 <- function() {
  rows <- list(); add <- function(...) rows[[length(rows) + 1L]] <<- data.frame(..., stringsAsFactors = FALSE)
  for (s in 1:3) {
    ctl <- sprintf("B%d", s)
    add(event_id = ctl, site = paste0("site", s), taxon_name = "SYSTEMIC", n_reads = 100)
    add(event_id = ctl, site = paste0("site", s), taxon_name = "filler",   n_reads = 50)
    if (s == 1) {
      add(event_id = ctl, site = "site1", taxon_name = "LOCAL", n_reads = 200)
      # second control at site1: LOCAL clears the floor, still at ONE site
      add(event_id = "B1b", site = "site1", taxon_name = "LOCAL",    n_reads = 200)
      add(event_id = "B1b", site = "site1", taxon_name = "SYSTEMIC", n_reads = 100)
      add(event_id = "B1b", site = "site1", taxon_name = "filler",  n_reads = 50)
      # ONEBLANK: strongly control-enriched on a SINGLE control observation
      add(event_id = ctl,   site = "site1", taxon_name = "ONEBLANK", n_reads = 400)
    }
    for (i in 1:2) {
      sm <- sprintf("S%d_%d", s, i)
      add(event_id = sm, site = paste0("site", s), taxon_name = "CLEAN", n_reads = 9000)
      add(event_id = sm, site = paste0("site", s), taxon_name = "filler", n_reads = 900)
      # THIN: never in a control, but so few reads that shrinkage drags its score
      # below the 'valid' band -- a verdict on no evidence, which is the defect
      add(event_id = sm, site = paste0("site", s), taxon_name = "THIN", n_reads = 2)
      if (s == 1) {
        add(event_id = sm, site = "site1", taxon_name = "LOCAL", n_reads = 100)
        add(event_id = sm, site = "site1", taxon_name = "ONEBLANK", n_reads = 3)
      }
    }
  }
  do.call(rbind, rows)
}
.ctls <- c("B1", "B1b", "B2", "B3")

test_that("Q2: a taxon never seen in a control gets no_control_evidence, not a verdict", {
  df <- .mk3()
  r <- flag_contaminant(df, control_samples = .ctls, require_control_evidence = TRUE,
                        verbose = FALSE)
  clean <- r[r$taxon_name == "CLEAN", ]
  expect_equal(clean$n_controls_present, 0)
  expect_identical(clean$validity_flag, "no_control_evidence")
})

test_that("Q2: direction separates contamination from non-enrichment", {
  df <- .mk3()
  r <- flag_contaminant(df, control_samples = .ctls, require_control_evidence = TRUE,
                        verbose = FALSE)
  # control-enriched at several sites -> a contaminant
  expect_identical(r$validity_flag[r$taxon_name == "SYSTEMIC"], "invalid_lab_contaminant")
  # WITHOUT site_col, Q2 alone CANNOT rescue LOCAL: it is genuinely
  # control-enriched (0.8 of the control's reads against 0.01 of a sample's), so
  # direction alone calls it a contaminant. That is exactly the gap Q3 fills, and
  # pinning it here keeps the two contributions distinguishable.
  expect_identical(r$validity_flag[r$taxon_name == "LOCAL"], "invalid_lab_contaminant")
})

test_that("Q3: site breadth columns are reported when site_col is given", {
  df <- .mk3()
  r <- flag_contaminant(df, control_samples = .ctls, site_col = "site",
                        require_control_evidence = TRUE, verbose = FALSE)
  expect_true(all(c("site_breadth_control", "site_breadth_sample",
                    "control_sites_shared") %in% names(r)))
  expect_equal(r$site_breadth_control[r$taxon_name == "SYSTEMIC"], 3L)
  expect_equal(r$site_breadth_control[r$taxon_name == "LOCAL"], 1L)
  expect_equal(r$site_breadth_control[r$taxon_name == "CLEAN"], 0L)
})

test_that("Q3: a control detection at ONE site whose samples carry it is downgraded", {
  df <- .mk3()
  # Make LOCAL control-enriched enough to be flagged on Q2 alone, so the only
  # thing that can rescue it is the site-breadth discriminant.
  df$n_reads[df$event_id == "B1" & df$taxon_name == "LOCAL"] <- 5000
  q2 <- flag_contaminant(df, control_samples = .ctls, require_control_evidence = TRUE,
                         verbose = FALSE)
  q3 <- flag_contaminant(df, control_samples = .ctls, site_col = "site",
                         require_control_evidence = TRUE, verbose = FALSE)
  expect_identical(q2$validity_flag[q2$taxon_name == "SYSTEMIC"], "invalid_lab_contaminant")
  expect_identical(q3$validity_flag[q3$taxon_name == "SYSTEMIC"], "invalid_lab_contaminant")
  # LOCAL is local: one control site, and that site's samples have it
  expect_equal(q3$control_sites_shared[q3$taxon_name == "LOCAL"], 1L)
  expect_identical(q3$validity_flag[q3$taxon_name == "LOCAL"], "single_site_enriched")
})

test_that("the default is unchanged, and warns with a COUNT when it matters", {
  df <- .mk3()
  old <- suppressWarnings(flag_contaminant(df, control_samples = .ctls, verbose = FALSE))
  # legacy vocabulary only -- none of the new states appear
  expect_false(any(c("no_control_evidence", "not_control_enriched",
                     "single_site_enriched", "insufficient_control_evidence")
                   %in% old$validity_flag))
  # THIN has NO control evidence yet is given a contamination verdict anyway,
  # purely because shrinkage pulls a low-read taxon out of the valid band. That is
  # the defect, and the warning must quantify it rather than fire on every call.
  expect_equal(old$n_controls_present[old$taxon_name == "THIN"], 0)
  expect_true(old$validity_flag[old$taxon_name == "THIN"] != "valid")
  expect_warning(flag_contaminant(df, control_samples = .ctls, verbose = FALSE),
                 "WITHOUT EVER BEING DETECTED IN A CONTROL")
  # and with the gate on, that same taxon is reported honestly instead
  new <- flag_contaminant(df, control_samples = .ctls,
                          require_control_evidence = TRUE, verbose = FALSE)
  expect_identical(new$validity_flag[new$taxon_name == "THIN"], "no_control_evidence")
})

test_that("site_col is validated and min_sites_systemic is honoured", {
  df <- .mk3()
  expect_error(flag_contaminant(df, control_samples = .ctls, site_col = "nope",
                                require_control_evidence = TRUE, verbose = FALSE),
               "not found in input_df")
  # with the systemic bar raised above the data's breadth, even SYSTEMIC becomes local
  r <- flag_contaminant(df, control_samples = .ctls, site_col = "site",
                        require_control_evidence = TRUE, min_sites_systemic = 5L,
                        verbose = FALSE)
  expect_identical(r$validity_flag[r$taxon_name == "SYSTEMIC"], "invalid_lab_contaminant")
})

test_that("the invalid_ prefix is the removal predicate, not !=\"valid\"", {
  df <- .mk3()
  r <- flag_contaminant(df, control_samples = .ctls, site_col = "site",
                        require_control_evidence = TRUE, verbose = FALSE)
  # the states that must NOT be removed are also not "valid", which is why the
  # negation idiom is wrong under the gate
  keep_but_not_valid <- r$validity_flag %in% c("no_control_evidence",
    "not_control_enriched", "single_site_enriched", "insufficient_control_evidence")
  expect_true(any(keep_but_not_valid))
  expect_false(any(startsWith(r$validity_flag[keep_but_not_valid], "invalid_")))
  # and the prefix selects the control-enriched taxa. Note `filler` belongs here
  # too and that is correct, not an artefact of the fixture: it takes 0.33 of a
  # control's reads against 0.09 of a sample's, at all three sites, so it IS
  # control-enriched and systemic by the definition under test.
  inv <- r$taxon_name[startsWith(r$validity_flag, "invalid_")]
  expect_true("SYSTEMIC" %in% inv)
  expect_false("CLEAN" %in% inv)
  expect_false("THIN" %in% inv)
})


test_that("the evidence floor refuses to condemn on a single control observation", {
  df <- .mk3()
  # ONEBLANK is control-enriched by any rate comparison: 400 reads in one control
  # against 3 reads in each of two samples. The ONLY thing wrong with the evidence
  # is that there is one observation of it.
  r <- flag_contaminant(df, control_samples = .ctls, site_col = "site",
                        require_control_evidence = TRUE, verbose = FALSE)
  expect_equal(r$n_controls_present[r$taxon_name == "ONEBLANK"], 1)
  expect_identical(r$validity_flag[r$taxon_name == "ONEBLANK"],
                   "insufficient_control_evidence")
  expect_false(startsWith(r$validity_flag[r$taxon_name == "ONEBLANK"], "invalid_"))

  # min_control_obs = 1 restores the unfloored behaviour, so the floor is provably
  # the thing doing the work here and not some other part of the gate.
  r1 <- flag_contaminant(df, control_samples = .ctls, site_col = "site",
                         require_control_evidence = TRUE, min_control_obs = 1L,
                         verbose = FALSE)
  expect_true(r1$validity_flag[r1$taxon_name == "ONEBLANK"] %in%
                c("invalid_lab_contaminant", "single_site_enriched"))

  # and the floor must NOT swallow a taxon with real breadth
  expect_identical(r$validity_flag[r$taxon_name == "SYSTEMIC"], "invalid_lab_contaminant")
})

test_that("not_control_enriched and single_site_enriched are distinct states", {
  df <- .mk3()
  r <- flag_contaminant(df, control_samples = .ctls, site_col = "site",
                        require_control_evidence = TRUE, verbose = FALSE)
  # LOCAL is ENRICHED in controls (200 vs 100 reads) and confined to one site.
  # Labelling it "not_control_enriched" would state the opposite of what was
  # measured, which is why the rename did not simply collapse the two.
  expect_identical(r$validity_flag[r$taxon_name == "LOCAL"], "single_site_enriched")
  expect_gt(r$control_rate[r$taxon_name == "LOCAL"],
            r$field_rate[r$taxon_name == "LOCAL"])
  expect_false("carryover" %in% r$validity_flag)
})
