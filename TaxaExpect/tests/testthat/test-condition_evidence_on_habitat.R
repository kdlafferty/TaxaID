# condition_evidence_on_habitat() -- 2026-09-12

.ev <- function() {
  data.frame(
    taxon_name = c("Oncorhynchus mykiss", "Cervus elaphus", "Sebastes alutus", "Unknownus taxus"),
    weight     = c(0.046, 0.035, 0.026, 0.02),
    source     = "regional_proximity", stringsAsFactors = FALSE
  )
}
.hab <- function() {
  data.frame(
    taxon_name = c("Oncorhynchus mykiss", "Cervus elaphus", "Sebastes alutus"),
    Marine = c(0.25, 0, 1), Freshwater = c(0.75, 0, 0), Terrestrial = c(0, 1, 0),
    Habitat = c("Freshwater", "Terrestrial", "Marine"), stringsAsFactors = FALSE
  )
}

test_that("weights are multiplied by the site-habitat weight and floored at w_floor", {
  out <- suppressMessages(condition_evidence_on_habitat(.ev(), .hab(), "Marine", w_floor = 6.4e-5))
  expect_equal(out$weight[1], 0.046 * 0.25)          # steelhead keeps a quarter (bleed)
  expect_equal(out$weight[2], 6.4e-5)                 # deer floored, not zeroed
  expect_true(out$habitat_floored[2])
  expect_equal(out$weight[3], 0.026)                  # marine fish unchanged
  expect_equal(out$weight[4], 0.02)                   # unknown taxon unchanged
  expect_true(is.na(out$habitat_weight[4]))
  expect_equal(out$weight_unconditioned, c(0.046, 0.035, 0.026, 0.02))
  expect_equal(out$source, rep("regional_proximity", 4))
})

test_that("a zero floor lets a habitat weight of 0 zero the row", {
  out <- suppressMessages(condition_evidence_on_habitat(.ev(), .hab(), "Marine", w_floor = 0))
  expect_equal(out$weight[2], 0)
})

test_that("the site habitat must be a column of the lookup; inputs are validated", {
  expect_error(condition_evidence_on_habitat(.ev(), .hab(), "Estuarine"), "no column 'Estuarine'")
  expect_error(condition_evidence_on_habitat(.ev()[, "taxon_name", drop = FALSE], .hab(), "Marine"), "weight")
  expect_error(condition_evidence_on_habitat(.ev(), .hab(), "Marine", w_floor = 1), "w_floor")
  bad <- .hab()
  bad$Marine[1] <- 1.5
  expect_error(condition_evidence_on_habitat(.ev(), bad, "Marine"), "outside")
})

test_that("an empty evidence table passes through with the new columns", {
  out <- condition_evidence_on_habitat(.ev()[0, ], .hab(), "Marine")
  expect_equal(nrow(out), 0L)
  expect_true(all(c("habitat_weight", "weight_unconditioned", "habitat_floored") %in% names(out)))
})

test_that("the conditioned table is accepted by apply_undetected_evidence() unchanged in shape", {
  out <- suppressMessages(condition_evidence_on_habitat(.ev(), .hab(), "Marine", w_floor = 6.4e-5))
  expect_true(all(c("taxon_name", "weight", "source") %in% names(out)))
  expect_true(all(out$weight >= 0 & out$weight <= 1))
})

test_that("verbose reports counts", {
  expect_message(
    condition_evidence_on_habitat(.ev(), .hab(), "Marine", w_floor = 6.4e-5),
    "4 row\\(s\\) conditioned on 'Marine' -- 2 unchanged .* 1 reduced, 1 floored"
  )
})
