# Fixture: one taxon per situation the function has to distinguish.
.occ <- function() data.frame(
  taxon_name = c(
    "Resident",   "Resident",      # has a Marine record -> resident row exists
    "UncertainA", "UncertainA",    # only unplaceable records
    "LegacyNA",                    # only unplaceable records, OLD vocabulary
    "MixedSentinel", "MixedSentinel", # both vocabularies, same taxon
    "WrongHabitat"                 # habitat KNOWN and not the site's
  ),
  decimalLatitude  = c(34.40, 34.60, 34.45, 34.50, 34.50, 34.45, 34.80, 35.90),
  decimalLongitude = c(-120.40, -120.40, -120.45, -120.45, -120.50, -120.45, -120.40, -121.50),
  main_habitat     = c("Marine", "Uncertain", "Uncertain", "Uncertain", NA,
                       "Uncertain", NA, "Freshwater"),
  year             = c(2020, 2020, 2015, 2018, 2010, 2012, 2012, 2019),
  stringsAsFactors = FALSE
)

test_that("only taxa with no resident row and unplaceable records are returned", {
  r <- generate_uncertain_habitat_evidence(.occ(), 34.4, -120.4, "Marine", verbose = FALSE)
  # Resident has a Marine record: excluded even though it ALSO has an Uncertain one.
  expect_false("Resident" %in% r$taxon_name)
  # WrongHabitat's habitat is known and is not the site's -- a correct exclusion
  # by estimate_kernel_priors(), and not this function's to undo.
  expect_false("WrongHabitat" %in% r$taxon_name)
  expect_setequal(r$taxon_name, c("UncertainA", "LegacyNA", "MixedSentinel"))
})

test_that("both sentinel vocabularies are treated identically", {
  # The whole point: tables written before 2026-09-19 store NA, after it
  # "Uncertain", and the same code reads both. A taxon known only from NA
  # points must be recovered exactly like one known only from "Uncertain".
  o <- .occ()
  r_mixed <- generate_uncertain_habitat_evidence(o, 34.4, -120.4, "Marine", verbose = FALSE)
  o_all_na <- o; o_all_na$main_habitat[o_all_na$main_habitat == "Uncertain"] <- NA
  r_na <- generate_uncertain_habitat_evidence(o_all_na, 34.4, -120.4, "Marine", verbose = FALSE)
  o_all_unc <- o; o_all_unc$main_habitat[is.na(o_all_unc$main_habitat)] <- "Uncertain"
  r_unc <- generate_uncertain_habitat_evidence(o_all_unc, 34.4, -120.4, "Marine", verbose = FALSE)
  # Resident still has its Marine record in all three, so the recovered set is
  # the same and every weight matches.
  expect_equal(r_na[order(r_na$taxon_name), "weight"],
               r_unc[order(r_unc$taxon_name), "weight"])
  expect_setequal(r_mixed$taxon_name, r_na$taxon_name)
})

test_that("distance is to the taxon's NEAREST unplaceable record, and counts are per taxon", {
  r <- generate_uncertain_habitat_evidence(.occ(), 34.4, -120.4, "Marine", verbose = FALSE)
  d_expect <- 111 * sqrt((34.45 - 34.4)^2 + ((-120.45 + 120.4) * cos(34.4 * pi / 180))^2)
  expect_equal(r$distance_km[r$taxon_name == "UncertainA"], d_expect)
  expect_equal(r$n_records_unassigned[r$taxon_name == "UncertainA"], 2L)
  # MixedSentinel's two records span both vocabularies and must both count.
  expect_equal(r$n_records_unassigned[r$taxon_name == "MixedSentinel"], 2L)
})

test_that("pricing matches generate_regional_proximity_evidence()'s curve", {
  r <- generate_uncertain_habitat_evidence(.occ(), 34.4, -120.4, "Marine",
                                           d_half = 150, w_scale = 0.05, verbose = FALSE)
  expect_equal(r$weight, 0.05 * exp(-r$distance_km / 150))
  expect_true(all(r$p_conc == 1))  # no year_col
})

test_that("year_col produces the age decay, and a missing year stays neutral", {
  o <- .occ(); o$year[o$taxon_name == "LegacyNA"] <- NA
  r <- generate_uncertain_habitat_evidence(o, 34.4, -120.4, "Marine",
                                           year_col = "year", age_half = 15, verbose = FALSE)
  expect_equal(r$p_conc[r$taxon_name == "LegacyNA"], 1)   # unknown age != old
  expect_true(all(r$p_conc[r$taxon_name != "LegacyNA"] < 1))
})

test_that("the schema apply_undetected_evidence() requires is always present", {
  need <- c("taxon_name", "weight", "p_conc", "source")
  r <- generate_uncertain_habitat_evidence(.occ(), 34.4, -120.4, "Marine", verbose = FALSE)
  expect_true(all(need %in% names(r)))
  expect_true(all(r$source == "uncertain_habitat_proximity"))
  # Zero rows must carry the SAME schema, not a bare data.frame: a workflow
  # row-binds this with other evidence and an absent column silently drops it.
  o <- .occ(); o$main_habitat <- "Marine"
  r0 <- generate_uncertain_habitat_evidence(o, 34.4, -120.4, "Marine", verbose = FALSE)
  expect_equal(nrow(r0), 0L)
  expect_true(all(need %in% names(r0)))
  expect_identical(names(r0), names(r))
})

test_that("a site declared with an unassigned-habitat sentinel is refused", {
  for (bad in c("Uncertain", NA_character_, "")) {
    expect_error(
      generate_uncertain_habitat_evidence(.occ(), 34.4, -120.4, bad, verbose = FALSE),
      regexp = "site_habitat"
    )
  }
})

test_that("`taxa` restricts the result without changing resident detection", {
  r <- generate_uncertain_habitat_evidence(.occ(), 34.4, -120.4, "Marine",
                                           taxa = c("UncertainA", "Resident"), verbose = FALSE)
  # Resident is still excluded by its Marine record, not silently admitted
  # just because the caller named it.
  expect_setequal(r$taxon_name, "UncertainA")
})
