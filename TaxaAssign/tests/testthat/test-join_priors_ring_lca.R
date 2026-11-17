# join_priors() and tied-anchor rings (ring_member_clades set by TaxaLikely): the column arrives in the output on both
# paths, and the registry path keys such a ring at the REGISTRY's lowest common ancestor of the observation's
# candidates in its member clades. Fixtures in helper-registry.R (Labridae and Embiotocidae, order Perciformes).

.lj_site <- list(grid_id = "s1", main_habitat = "Rocky")
.lj_lik <- function(names, ranks, types, members, genus, family) {
  data.frame(observation_id = "E1", taxon_name = names, taxon_name_rank = ranks, hypothesis_type = types,
             score_likelihood = 0.5, genus = genus, family = family, ring_member_clades = members, stringsAsFactors = FALSE)
}
.lj_pri <- function(names, alpha) {
  data.frame(taxon_name = c(names, NA), taxon_name_rank = "species", grid_id = "s1", main_habitat = "Rocky",
             alpha = c(alpha, 0.5), beta = c(100 - alpha, 99.5), undetected_type = c(rep(NA, length(names)), "tier3"),
             stringsAsFactors = FALSE)
}
.lj_jp <- function(...) suppressWarnings(suppressMessages(join_priors(..., site = .lj_site, rank_system = c("family", "genus", "species"), backbone_id = 11L)))
.lj_taxa_id <- function(reg, name) reg$taxa$taxon_id[reg$taxa$name == name][1]

test_that("registry path: a tied-anchor family ring over two families is keyed at their registry order", {
  .rg_skip(); reg <- .rg_registry()
  # candidates in Embiotocidae and Labridae tied; the family ring (unreferenced_genus) lists both families. Its own
  # label must be a registered name (attach_taxon_ids refuses others); the registry LCA replaces it.
  lik <- .lj_lik(c("Embiotoca jacksoni", "Oxyjulis californica", "Embiotocidae"), c("species", "species", "family"),
                 c("specific_candidate", "specific_candidate", "unreferenced_genus"), c(NA, NA, "Embiotocidae|Labridae"),
                 genus = c("Embiotoca", "Oxyjulis", NA), family = c("Embiotocidae", "Labridae", NA))
  out <- .lj_jp(.rg_stamp(lik, reg, "joined"), .rg_stamp(.lj_pri(c("Embiotoca jacksoni", "Oxyjulis californica"), c(20, 5)), reg, "priors"),
                registry = reg)
  ring <- out[out$hypothesis_type == "unreferenced_genus", ]
  expect_identical(ring$taxon_id, .lj_taxa_id(reg, "Perciformes"))
  expect_identical(ring$taxon_name, "Perciformes")
  expect_identical(ring$taxon_name_rank, "order")
  expect_identical(ring$ring_member_clades, "Embiotocidae|Labridae")   # arrives in the output
  rk <- attr(out, "ring_rows_rekeyed")
  expect_identical(rk$outcome[rk$ring == "Embiotocidae"], "lca_registry")
  expect_identical(attr(out, "registry_join_counts")$n_lca_rings_registry, 1L)
})

test_that("registry path: an anchor_fallback ring (the anchor's family kept) is named at the registry LCA, status lca_registry", {
  .rg_skip(); reg <- .rg_registry()
  lik <- .lj_lik(c("Embiotoca jacksoni", "Oxyjulis californica", "Embiotocidae"), c("species", "species", "family"),
                 c("specific_candidate", "specific_candidate", "unreferenced_genus"), c(NA, NA, "Embiotocidae|Labridae"),
                 genus = c("Embiotoca", "Oxyjulis", NA), family = c("Embiotocidae", "Labridae", "Embiotocidae"))
  lik$ring_lca_status <- c(NA, NA, "anchor_fallback")
  out <- .lj_jp(.rg_stamp(lik, reg, "joined"), .rg_stamp(.lj_pri(c("Embiotoca jacksoni", "Oxyjulis californica"), c(20, 5)), reg, "priors"),
                registry = reg)
  ring <- out[out$hypothesis_type == "unreferenced_genus", ]
  expect_identical(ring$taxon_name, "Perciformes"); expect_identical(ring$taxon_name_rank, "order")
  expect_identical(ring$ring_lca_status, "lca_registry")
  expect_true(all(is.na(out$ring_lca_status[out$hypothesis_type == "specific_candidate"])))
})

test_that("registry path: the registry LCA can be FINER than the likelihoods' (Embiotoca caryi is a Hypsurus)", {
  .rg_skip(); reg <- .rg_registry()
  # the likelihoods' own lineage puts the two tied candidates in genera Embiotoca and Hypsurus (LCA: the family); the
  # registry puts both in Hypsurus, so the genus ring is the Hypsurus ring
  lik <- .lj_lik(c("Embiotoca caryi", "Hypsurus caryi", "Embiotocidae"), c("species", "species", "family"),
                 c("specific_candidate", "specific_candidate", "unreferenced_species"), c(NA, NA, "Embiotoca|Hypsurus"),
                 genus = c("Embiotoca", "Hypsurus", NA), family = c("Embiotocidae", "Embiotocidae", "Embiotocidae"))
  out <- .lj_jp(.rg_stamp(lik, reg, "joined"), .rg_stamp(.lj_pri("Hypsurus caryi", 20), reg, "priors"), registry = reg)
  ring <- out[out$hypothesis_type == "unreferenced_species", ]
  expect_identical(ring$taxon_name, "Hypsurus"); expect_identical(ring$taxon_name_rank, "genus")
})

test_that("an untriggered ring is keyed exactly as before (ring_member_clades NA)", {
  .rg_skip(); reg <- .rg_registry()
  lik <- .lj_lik(c("Embiotoca caryi", "Embiotoca"), c("species", "genus"), c("specific_candidate", "unreferenced_species"),
                 c(NA, NA), genus = c("Embiotoca", "Embiotoca"), family = "Embiotocidae")
  pri <- .rg_stamp(.lj_pri("Hypsurus caryi", 20), reg, "priors")
  with_col <- .lj_jp(.rg_stamp(lik, reg, "joined"), pri, registry = reg)
  without <- .lj_jp(.rg_stamp(lik[, setdiff(names(lik), "ring_member_clades")], reg, "joined"), pri, registry = reg)
  expect_identical(with_col$taxon_id, without$taxon_id)
  expect_identical(attr(with_col, "ring_rows_rekeyed")$outcome, "rekeyed")
})

test_that("name path: ring_member_clades arrives in join_priors' output unchanged", {
  lik <- .lj_lik(c("Embiotoca jacksoni", "Perciformes"), c("species", "order"), c("specific_candidate", "unreferenced_family"),
                 c(NA, "Embiotocidae|Labridae"), genus = c("Embiotoca", NA), family = c("Embiotocidae", NA))
  out <- suppressWarnings(suppressMessages(join_priors(lik, .lj_pri("Embiotoca jacksoni", 20), site = .lj_site,
                                                       rank_system = c("family", "genus", "species"), backbone_id = 11L,
                                                       taxonomy_lookup = data.frame(taxon_name = c("Embiotoca jacksoni", "Perciformes"),
                                                         genus = c("Embiotoca", NA), family = c("Embiotocidae", NA),
                                                         order = "Perciformes", stringsAsFactors = FALSE))))
  expect_true("ring_member_clades" %in% names(out))
  expect_identical(out$ring_member_clades[out$hypothesis_type == "unreferenced_family"], "Embiotocidae|Labridae")
})
