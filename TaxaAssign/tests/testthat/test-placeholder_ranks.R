# tests/testthat/test-placeholder_ranks.R
# Placeholder rank labels ("unk_family", "unk_order") from reference
# taxonomies name no taxon. Built from a real 18S case: an 83.7% singleton
# (Neocolponema saponarium) whose family is "unk_family" in the reference.

test_that(".is_placeholder_rank recognises fillers and nothing real", {
  expect_equal(
    .is_placeholder_rank(c("unk_family", "unk_order", "Incertae sedis",
      "unclassified Gastropoda", "unknown", "Colponemida", "Unkia", NA)),
    c(TRUE, TRUE, TRUE, TRUE, TRUE, FALSE, FALSE, FALSE)
  )
})

test_that("placeholder rank values become NA and a placeholder taxon_name is renamed upward", {
  df <- data.frame(
    taxon_name = c("Neocolponema saponarium", "Neocolponema", "unk_family"),
    taxon_name_rank = c("species", "genus", "family"),
    order = "Colponemida", family = "unk_family",
    genus = c("Neocolponema", "Neocolponema", NA), stringsAsFactors = FALSE
  )
  out <- .blank_ranks_to_na(df)
  expect_true(all(is.na(out$family)))
  expect_equal(out$taxon_name[3], "Colponemida")
  expect_equal(out$taxon_name_rank[3], "order")
  expect_equal(out$taxon_name[1:2], df$taxon_name[1:2])
})

test_that("a placeholder taxon_name with no real ancestor becomes NA", {
  df <- data.frame(taxon_name = "unk_family", taxon_name_rank = "family",
    order = "unk_order", family = "unk_family", stringsAsFactors = FALSE)
  out <- .blank_ranks_to_na(df)
  expect_true(is.na(out$taxon_name))
  expect_true(is.na(out$taxon_name_rank))
})

test_that("unrelated species sharing a placeholder family lend no mass to the genus row", {
  joined <- data.frame(
    observation_id = "E1",
    taxon_name = c("Neocolponema saponarium", "Neocolponema", "unk_family"),
    taxon_name_rank = c("species", "genus", "family"),
    hypothesis_type = c("specific_candidate", "unreferenced_species", "unreferenced_genus"),
    order = "Colponemida", family = "unk_family",
    genus = c("Neocolponema", "Neocolponema", NA),
    score_likelihood = c(0.37, 0.77, 1), score_likelihood_mean = c(0.37, 0.77, 1),
    score_likelihood_sd = 0, prior_mean = 3.2e-6, prior_alpha = 0.0032,
    prior_beta = 999.9968, grid_id = "site1", main_habitat = "Marine",
    stringsAsFactors = FALSE
  )
  sp <- c("Triopha catalinae", "Triopha maculata", "Halichondria panicea")
  priors <- data.frame(taxon_name = sp, taxon_name_rank = "species", grid_id = "site1",
    main_habitat = "Marine", theta_mean = c(4e-3, 3e-3, 2.8e-3),
    alpha = c(4, 3, 2.8), beta = c(996, 997, 997.2), stringsAsFactors = FALSE)
  tax <- data.frame(taxon_name = sp, genus = c("Triopha", "Triopha", "Halichondria"),
    family = "unk_family", order = c("Nudibranchia", "Nudibranchia", "Suberitida"),
    stringsAsFactors = FALSE)
  out <- suppressMessages(add_unreferenced_prior_mass(joined, priors, tax,
    referenced_names = "Neocolponema saponarium"))
  fam_row <- out[out$hypothesis_type == "unreferenced_genus", ]
  expect_equal(fam_row$taxon_name, "Colponemida")
  expect_equal(fam_row$taxon_name_rank, "order")
  expect_equal(fam_row$prior_mean, 3.2e-6) # floor only, nothing summed
  # the pre-fix behaviour summed all three into "unk_family"
  expect_false(isTRUE(fam_row$unreferenced_mass > 0))
})

test_that("posterior_consensus never reports a placeholder taxon", {
  pd <- data.frame(
    observation_id = "E1",
    taxon_name = c("unk_family", "Neocolponema saponarium"),
    taxon_name_rank = c("family", "species"),
    hypothesis_type = c("unreferenced_genus", "specific_candidate"),
    order = "Colponemida", family = "unk_family", genus = c(NA, "Neocolponema"),
    score_likelihood = c(1, 0.37), posterior_point_est = c(0.99, 0.01),
    stringsAsFactors = FALSE
  )
  out <- suppressMessages(posterior_consensus(pd,
    rank_system = c("order", "family", "genus", "species")))
  expect_false(isTRUE(.is_placeholder_rank(out$consensus_taxon)))
  expect_equal(out$consensus_taxon, "Colponemida")
})

test_that("taxonomy lookup fills only empty rank cells, never overwrites", {
  pd <- data.frame(
    observation_id = "E1",
    taxon_name = c("Oligocottus snyderi", "Oligocottus"),
    taxon_name_rank = c("species", "genus"),
    hypothesis_type = c("specific_candidate", "unreferenced_species"),
    family = c("Cottidae", NA), genus = c("Oligocottus", "Oligocottus"),
    posterior_point_est = c(0.7, 0.3), stringsAsFactors = FALSE
  )
  fake_verify <- function(names, ...) data.frame(user_supplied_name = names,
    verified = TRUE, matched = TRUE, matched_name = names,
    classification_path = "Psychrolutidae|Wrongus", classification_ranks = "family|genus",
    stringsAsFactors = FALSE)
  testthat::local_mocked_bindings(verify_taxon_names = fake_verify, .package = "TaxaTools")
  out <- suppressWarnings(suppressMessages(posterior_consensus(pd,
    rank_system = c("family", "genus", "species"),
    lookup_missing_taxonomy = TRUE, backbone_id = 4)))
  # the empty family cell may be filled; the genus value must stay Oligocottus,
  # so the two rows still share a genus and the call keeps its mass
  expect_equal(out$consensus_taxon, "Oligocottus")
  expect_gt(out$consensus_posterior, 0.99)
})

# ---- unnamed mass counts against the call ------------------------------------
.un_df <- function(post_unnamed) {
  named <- (1 - post_unnamed) * c(0.68, 0.32)
  data.frame(
    observation_id = "E1",
    taxon_name = c(NA, "Neocolponema", "Neocolponema saponarium"),
    taxon_name_rank = c(NA, "genus", "species"),
    hypothesis_type = c("unreferenced_genus", "unreferenced_species", "specific_candidate"),
    genus = c(NA, "Neocolponema", "Neocolponema"),
    posterior_point_est = c(post_unnamed, named), stringsAsFactors = FALSE
  )
}

test_that("a call held by less than the threshold of TOTAL mass is unresolved", {
  out <- suppressWarnings(suppressMessages(posterior_consensus(.un_df(0.468),
    rank_system = c("genus", "species"))))
  expect_true(is.na(out$consensus_taxon))
  expect_equal(out$consensus_reason, "unnamed_mass")
  expect_equal(out$unnamed_mass, 0.468)
})

test_that("unnamed_in_threshold = FALSE restores the named-only threshold", {
  out <- suppressWarnings(suppressMessages(posterior_consensus(.un_df(0.468),
    rank_system = c("genus", "species"), unnamed_in_threshold = FALSE)))
  expect_equal(out$consensus_taxon, "Neocolponema")
  expect_equal(out$unnamed_mass, 0.468)
})

test_that("a small unnamed share does not block a call that still clears the threshold", {
  out <- suppressWarnings(suppressMessages(posterior_consensus(.un_df(0.02),
    rank_system = c("genus", "species"))))
  expect_equal(out$consensus_taxon, "Neocolponema")
})
