# Tests for compute_group_priors()

.priors <- function() {
  data.frame(
    taxon_name = c("Aa one", "Aa two", "Bb one", "Cc one", "Dd one"),
    theta_mean = c(0.02, 0.05, 0.10, NA_real_, 0.01),
    stringsAsFactors = FALSE
  )
}

.taxonomy <- function() {
  data.frame(
    taxon_name = c("Aa one", "Aa two", "Bb one", "Cc one", "Dd one"),
    genus = c("Aa", "Aa", "Bb", "Cc", NA_character_),
    family = c("Fam1", "Fam1", "Fam2", "Fam3", "Fam1"),
    stringsAsFactors = FALSE
  )
}

test_that("sums theta_mean within each rank group", {
  out <- compute_group_priors(.priors(), .taxonomy())
  genus_aa <- out[out$rank == "genus" & out$taxon == "Aa", ]
  expect_equal(genus_aa$theta_sum, 0.07)
  expect_equal(genus_aa$n_members, 2L)

  fam1 <- out[out$rank == "family" & out$taxon == "Fam1", ]
  # Dd one has theta_mean = 0.01 but NA genus -- still contributes at family
  # rank since family is populated there.
  expect_equal(fam1$theta_sum, 0.08)
  expect_equal(fam1$n_members, 3L)
})

test_that("a taxon with NA theta_mean does not contribute and is not counted", {
  out <- compute_group_priors(.priors(), .taxonomy())
  fam3 <- out[out$rank == "family" & out$taxon == "Fam3", ]
  # Cc one has theta_mean = NA -- Fam3 should be entirely absent, not a zero row.
  expect_equal(nrow(fam3), 0L)
})

test_that("a taxon with NA at one rank is excluded from that rank only", {
  out <- compute_group_priors(.priors(), .taxonomy())
  # Dd one has NA genus -- no genus group should include it.
  genus_taxa <- out$taxon[out$rank == "genus"]
  expect_false("Dd" %in% genus_taxa)
  # but it DOES contribute at family rank (checked above).
})

test_that("theta_sum is capped at 1 as a defensive guard", {
  priors <- data.frame(taxon_name = c("X1", "X2"), theta_mean = c(0.9, 0.9))
  taxonomy <- data.frame(taxon_name = c("X1", "X2"), genus = c("G", "G"))
  out <- compute_group_priors(priors, taxonomy, rank_cols = "genus")
  expect_equal(out$theta_sum[out$taxon == "G"], 1)
})

test_that("output has rank/taxon/theta_sum/n_members columns", {
  out <- compute_group_priors(.priors(), .taxonomy())
  expect_true(all(c("rank", "taxon", "theta_sum", "n_members") %in% names(out)))
})

test_that("custom rank_cols respected", {
  out <- compute_group_priors(.priors(), .taxonomy(), rank_cols = "family")
  expect_true(all(out$rank == "family"))
  expect_false("genus" %in% out$rank)
})

test_that("rank_cols defaults to include species, auto-derived as taxon identity", {
  out <- compute_group_priors(.priors(), .taxonomy())
  sp <- out[out$rank == "species", ]
  # Every priors row with a non-NA theta_mean gets its own species row,
  # theta_sum = its own value, n_members = 1 (a group of one).
  expect_true(all(c("species") %in% out$rank))
  expect_setequal(sp$taxon, .priors()$taxon_name[!is.na(.priors()$theta_mean)])
  expect_true(all(sp$n_members == 1L))
})

test_that("an explicit species column in taxonomy_map is respected, not overwritten", {
  priors <- data.frame(taxon_name = c("X1", "X2"), theta_mean = c(0.1, 0.2))
  taxonomy <- data.frame(taxon_name = c("X1", "X2"), species = c("Resolved A", "Resolved B"))
  out <- compute_group_priors(priors, taxonomy, rank_cols = "species")
  expect_setequal(out$taxon, c("Resolved A", "Resolved B"))
})

test_that("omitting species from rank_cols disables it (no auto-derivation forced)", {
  out <- compute_group_priors(.priors(), .taxonomy(), rank_cols = "family")
  expect_false("species" %in% out$rank)
})

test_that("stops on missing required columns", {
  expect_error(compute_group_priors("x", .taxonomy()), "must be a data frame")
  expect_error(compute_group_priors(.priors(), "x"), "must be a data frame")
  p <- .priors()
  p$theta_mean <- NULL
  expect_error(compute_group_priors(p, .taxonomy()), "theta_mean")
  # A rank named EXPLICITLY and absent is still an error -- you asked for it.
  t <- .taxonomy()
  t$genus <- NULL
  expect_error(
    compute_group_priors(.priors(), t, rank_cols = c("species", "genus")),
    "genus"
  )
})

test_that("a DEFAULT rank absent from taxonomy_map is skipped, not an error", {
  # 2026-09-14: the default widened to reach order/class, so it can no longer
  # abort on a rank the caller never asked for -- most real taxonomy_maps stop
  # at family. Explicit requests stay strict (test above); defaults adapt.
  t <- .taxonomy()
  t$genus <- NULL
  expect_message(
    gp <- compute_group_priors(.priors(), t),
    "skipped"
  )
  expect_false("genus" %in% gp$rank)
  expect_true("family" %in% gp$rank)
})

test_that("order-rank groups are produced when taxonomy_map carries them", {
  # The real defect this closes: a consensus resolving at ORDER rank found no
  # group row, read consensus_has_occurrence_record = FALSE and was reported
  # "unprecedented" from the rank gap alone. Real case, PtConception 12S --
  # the Perciformes unit (Scorpaenichthys + Hexagrammos), 20 observations,
  # dropped from the export after the skepticism gate acted on that flag.
  t <- .taxonomy()
  t$order <- "Perciformes"
  gp <- suppressMessages(compute_group_priors(.priors(), t))
  expect_true("order" %in% gp$rank)
  expect_true("Perciformes" %in% gp$taxon[gp$rank == "order"])
  expect_gt(gp$theta_sum[gp$rank == "order" & gp$taxon == "Perciformes"], 0)
})


test_that("named-evidence rows are excluded but anonymous dark-diversity mirrors are kept (2026-09-13)", {
  pri <- data.frame(
    taxon_name = c("Sebastes miniatus", "Sebastes mystinus", "Cervus elaphus", "Bos taurus", NA),
    theta_mean = c(0.02, 0.01, 1e-6, 5e-4, 3e-6),
    prior_branch = c("kernel_estimated", "kernel_estimated", "resident_undetected",
                     "transport", "resident_undetected"),
    evidence_sources = c(NA, NA, "regional_proximity", NA, NA),
    undetected_type = c(NA, NA, "evidence_blend", NA, "singleton_mirror"),
    genus = c("Sebastes", "Sebastes", "Cervus", "Bos", "Citharichthys"),
    family = c("Sebastidae", "Sebastidae", "Cervidae", "Bovidae", "Paralichthyidae"),
    stringsAsFactors = FALSE
  )
  tax <- pri[, c("taxon_name", "genus", "family")]
  gp <- compute_group_priors(pri, tax)
  # residents and transport survive
  expect_true("Sebastes" %in% gp$taxon[gp$rank == "genus"])
  expect_true("Bos taurus" %in% gp$taxon[gp$rank == "species"])
  # a NAMED evidence row does not support its genus/family
  expect_false("Cervus" %in% gp$taxon)
  expect_false("Cervidae" %in% gp$taxon)
  # the ANONYMOUS dark-diversity mirror DOES: it exists because the group has
  # local records, so its mass is legitimate group support
  expect_true("Citharichthys" %in% gp$taxon[gp$rank == "genus"])
  expect_true("Paralichthyidae" %in% gp$taxon[gp$rank == "family"])
  # opting out restores the pre-2026-09-13 behaviour
  gp_all <- compute_group_priors(pri, tax, exclude_named_evidence = FALSE)
  expect_true("Cervidae" %in% gp_all$taxon)
  # a table with no evidence_sources column is untouched
  gp_legacy <- compute_group_priors(pri[, setdiff(names(pri), "evidence_sources")], tax)
  expect_true("Cervidae" %in% gp_legacy$taxon)
  expect_error(compute_group_priors(pri, tax, exclude_named_evidence = "yes"),
               "exclude_named_evidence")
})
