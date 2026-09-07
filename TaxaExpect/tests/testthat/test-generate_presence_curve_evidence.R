# Tests for generate_presence_curve_evidence() / generate_user_specified_evidence()
# (unobserved-taxa redesign, 2026-08-31).

test_that("clamp mode prices every taxon at d_cap", {
  ev <- generate_presence_curve_evidence(c("A a", "B b"), w_scale = 0.05)
  expect_equal(ev$weight, rep(0.05 * exp(-1000 / 150), 2))
  expect_equal(ev$source, rep("distance_clamp", 2))
  expect_equal(ev$distance_km, rep(1000, 2))
})

test_that("named distances price on the curve; missing names fall to the clamp", {
  d <- c("A a" = 150, "C c" = 9999)
  ev <- generate_presence_curve_evidence(c("A a", "B b", "C c"),
    w_scale = 0.05, distance_km = d
  )
  expect_equal(ev$weight[1], 0.05 * exp(-1), tolerance = 1e-12) # 150 km
  expect_equal(ev$weight[2], 0.05 * exp(-1000 / 150)) # clamp (no name)
  expect_equal(ev$weight[3], 0.05 * exp(-1000 / 150)) # capped at d_cap
  expect_equal(ev$source, rep("presence_curve", 3))
})

test_that("k stretches the bandwidth (listed-invader lift, log-space halfway)", {
  ev1 <- generate_presence_curve_evidence("A a",
    w_scale = 0.05,
    distance_km = c("A a" = 300)
  )
  ev2 <- generate_presence_curve_evidence("A a",
    w_scale = 0.05,
    distance_km = c("A a" = 300), k = 2
  )
  expect_equal(ev2$weight, 0.05 * exp(-300 / 300))
  # exp(-d/(2*lambda)) = sqrt(w_scale-normalized curve): the log-space halfway
  expect_equal(ev2$weight / 0.05, sqrt(ev1$weight / 0.05), tolerance = 1e-12)
})

test_that("w_scale is required and validation fires", {
  expect_error(generate_presence_curve_evidence("A a"), "w_scale is required")
  expect_error(generate_presence_curve_evidence("A a", w_scale = 2), "w_scale")
  expect_error(generate_presence_curve_evidence("A a", w_scale = 0.05, k = 0.5), "k")
  expect_error(
    generate_presence_curve_evidence("A a",
      w_scale = 0.05,
      distance_km = c(1, 2)
    ),
    "same length"
  )
})

test_that("user-specified evidence carries provenance and discloses high weights", {
  expect_message(
    ev <- generate_user_specified_evidence(c(
      "Gymnocephalus cernua" = 0.3,
      "Alosa alosa" = 0.02
    )),
    "dilution threshold"
  )
  expect_equal(ev$source, rep("user_specified", 2))
  expect_equal(ev$weight, c(0.3, 0.02))
  # no message when everything is below the threshold
  expect_no_message(generate_user_specified_evidence(c("A a" = 0.05)),
    message = "dilution"
  )
  expect_error(generate_user_specified_evidence(c(0.5)), "named")
  expect_error(generate_user_specified_evidence(c("A a" = 1.5)), "0, 1")
})

test_that("generator output flows through curve-pricing applier end to end", {
  occ <- data.frame(
    taxon_name = c("A", "A", "A", "B", "C"),
    decimalLatitude = 34, decimalLongitude = -120,
    main_habitat = "Lentic", stringsAsFactors = FALSE
  )
  kp <- estimate_kernel_priors(occ, 34, -120, "Lentic", lambda_km = 1e9, m = 0)
  ev <- generate_presence_curve_evidence(c("X x", "Y y"), w_scale = 0.05)
  out <- apply_undetected_evidence(kp$priors, kp, ev,
    grid_id = "s",
    main_habitat = "Lentic", pricing = "curve"
  )
  expect_equal(out$theta_mean, ev$weight * kp$theta_present, tolerance = 1e-9)
  expect_true(all(out$evidence_sources == "distance_clamp"))
})
