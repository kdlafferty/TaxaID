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

test_that("a weight reduced to exactly zero is flagged and warned about", {
  # This FAILS on main. There, habitat_floored is `w0 * h < w_floor` and
  # w_floor defaults to 0, so for non-negative weights the condition is
  # unsatisfiable: the flag is structurally FALSE and the verbose line's
  # "N floored" always reported zero whatever the habitat did. A habitat
  # weight of 0 meanwhile annihilates the row -- it contributes nothing to the
  # prior, which downstream cannot tell apart from a row that was never
  # generated.
  ev <- data.frame(
    taxon_name = c("Oncorhynchus mykiss", "Cervus elaphus"),
    weight = c(0.046, 0.035), source = "regional_proximity",
    stringsAsFactors = FALSE
  )
  hab <- data.frame(
    taxon_name = c("Oncorhynchus mykiss", "Cervus elaphus"),
    Marine = c(0.25, 0), Freshwater = c(0.75, 0), Terrestrial = c(0, 1),
    stringsAsFactors = FALSE
  )

  # Default w_floor = 0: the terrestrial taxon is annihilated.
  expect_warning(
    out <- suppressMessages(condition_evidence_on_habitat(
      ev, hab, site_habitat = "Marine"
    )),
    "reduced to a weight of exactly 0"
  )
  expect_equal(out$habitat_zeroed, c(FALSE, TRUE))
  expect_equal(out$weight[2], 0)
  # And the old flag is still FALSE here, which is the point: at w_floor = 0
  # nothing can be "floored", so it could never have reported this.
  expect_equal(out$habitat_floored, c(FALSE, FALSE))

  # A positive floor keeps the row contributing, and the two flags swap. They
  # are mutually exclusive by construction.
  out2 <- suppressMessages(condition_evidence_on_habitat(
    ev, hab, site_habitat = "Marine", w_floor = 6.4e-5
  ))
  expect_equal(out2$habitat_zeroed, c(FALSE, FALSE))
  expect_equal(out2$habitat_floored, c(FALSE, TRUE))
  expect_equal(out2$weight[2], 6.4e-5)
  expect_false(any(out2$habitat_zeroed & out2$habitat_floored))

  # The verbose line reports the zeroed count rather than hiding it in "reduced".
  msg <- capture_messages(suppressWarnings(
    condition_evidence_on_habitat(ev, hab, site_habitat = "Marine")
  ))
  expect_match(paste(msg, collapse = " "), "1 reduced to zero", fixed = TRUE)
})

test_that("the zero-row early return carries every flag column", {
  # Same discipline as the populated path: a caller must not have to test
  # whether a column exists before reading it.
  ev <- data.frame(
    taxon_name = character(0), weight = numeric(0), stringsAsFactors = FALSE
  )
  hab <- data.frame(taxon_name = "x", Marine = 1, stringsAsFactors = FALSE)
  out <- condition_evidence_on_habitat(ev, hab, site_habitat = "Marine")
  expect_true(all(
    c("habitat_weight", "weight_unconditioned", "habitat_floored", "habitat_zeroed")
      %in% names(out)
  ))
  expect_equal(nrow(out), 0L)
})
