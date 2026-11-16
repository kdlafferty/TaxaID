# join_priors(registry =): a ring row rekeyed to its candidates' registry clade keeps its own name in
# taxon_name_verbatim. Fixtures in helper-registry.R: Embiotoca caryi is a synonym of Hypsurus caryi, which the
# registry places in genus Hypsurus, so a genus ring "Embiotoca" over that one candidate is rekeyed to Hypsurus.
test_that("a rekeyed ring row keeps its own name as taxon_name_verbatim", {
  .rg_skip(); reg <- .rg_registry()
  lik <- data.frame(observation_id = "E1", taxon_name = c("Embiotoca caryi", "Embiotoca"), taxon_name_rank = c("species", "genus"),
                    hypothesis_type = c("specific_candidate", "unreferenced_genus"), score_likelihood = c(0.8, 0.2),
                    genus = "Embiotoca", family = "Embiotocidae", stringsAsFactors = FALSE)
  lik$score_likelihood_mean <- lik$score_likelihood; lik$score_likelihood_sd <- 0.01
  pri <- data.frame(taxon_name = c("Hypsurus caryi", "Embiotoca jacksoni"), taxon_name_rank = "species", grid_id = "s1",
                    main_habitat = "Rocky", alpha = 20, beta = 80, undetected_type = NA_character_, stringsAsFactors = FALSE)
  jp <- suppressWarnings(suppressMessages(join_priors(.rg_stamp(lik, reg, "joined"), .rg_stamp(pri, reg, "priors"),
          site = list(grid_id = "s1", main_habitat = "Rocky"), rank_system = c("family", "genus", "species"), backbone_id = 11L,
          registry = reg)))
  rk <- attr(jp, "ring_rows_rekeyed")
  expect_true(any(rk$outcome %in% "rekeyed"))             # the fixture exercises the rekey
  ring <- jp[jp$hypothesis_type %in% "unreferenced_genus", , drop = FALSE]
  expect_identical(ring$taxon_name, "Hypsurus")
  expect_identical(ring$taxon_name_verbatim, "Embiotoca")
  cand <- jp[jp$hypothesis_type %in% "specific_candidate", , drop = FALSE]
  expect_identical(cand$taxon_name_verbatim, "Embiotoca caryi")
})
