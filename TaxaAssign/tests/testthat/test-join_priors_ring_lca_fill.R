# join_priors(registry =): a tied-anchor ring whose candidates' registry lineage is missing for one member clade.
# Measured on CalIntertidal (COI, 18S): a tied candidate with a run-local id the registry could not place (no ancestor)
# made every rank look uncommon, and the ring kept the likelihoods' kingdom label although its member clades share
# one registry phylum. Here the registry's own taxon of the member clade stands in. Fixtures: helper-registry.R plus one
# name the lookup does not answer ("Novogenus ignotus": a run-local id with no parent) and the kingdom "Animalia".

.lf_site <- list(grid_id = "s1", main_habitat = "Rocky")
.lf_registry <- function() {
  a <- .rg_answers()
  look <- function(names, rank, context) {
    out <- .rg_lookup(names, rank, context)
    k <- names == "Animalia"
    if (any(k)) {
      out$matched_name[k] <- "Animalia"; out$matched_rank[k] <- "kingdom"; out$is_synonym[k] <- FALSE
      out$classification_path[k] <- "Animalia"; out$classification_ranks[k] <- "kingdom"; out$classification_ids[k] <- "1"
      out$matched[k] <- TRUE; out$record_id[k] <- "1"; out$current_record_id[k] <- "1"; out$match_type[k] <- "Exact"
    }
    out
  }
  nm <- c(a$q, "Animalia", "Novogenus ignotus"); rk <- c(a$rank, "kingdom", "species")
  tabs <- c("joined", "priors")
  r <- TaxaTools::build_taxon_registry(data.frame(verbatim_name = rep(nm, length(tabs)), source_table = rep(tabs, each = length(nm)),
                                                  rank_given = rep(rk, length(tabs)), stringsAsFactors = FALSE), run_id = "lf1", lookup = look)
  TaxaTools::freeze_taxon_registry(r)
}
.lf_lik <- function(names, family, ring_label, ring_rank, members = "Embiotocidae|Labridae") {
  data.frame(observation_id = "E1", taxon_name = c(names, ring_label), taxon_name_rank = c(rep("species", length(names)), ring_rank),
             hypothesis_type = c(rep("specific_candidate", length(names)), "unreferenced_genus"), score_likelihood = 0.5,
             family = c(family, NA), ring_member_clades = c(rep(NA, length(names)), members),
             ring_lca_status = c(rep(NA, length(names)), "lca"), stringsAsFactors = FALSE)
}
.lf_pri <- function(reg) {
  .rg_stamp(data.frame(taxon_name = c("Embiotoca jacksoni", NA), taxon_name_rank = "species", grid_id = "s1", main_habitat = "Rocky",
                       alpha = c(20, 0.5), beta = c(80, 99.5), undetected_type = c(NA, "tier3"), stringsAsFactors = FALSE), reg, "priors")
}
.lf_jp <- function(lik, reg) {
  suppressWarnings(suppressMessages(join_priors(.rg_stamp(lik, reg, "joined"), .lf_pri(reg), site = .lf_site,
                                                rank_system = c("family", "genus", "species"), backbone_id = 11L, registry = reg)))
}

test_that("fixture: Novogenus ignotus is a run-local id with no registry ancestor", {
  .rg_skip(); reg <- .lf_registry()
  id <- reg$names$taxon_id[reg$names$verbatim_name == "Novogenus ignotus"][1]
  expect_false(is.na(id))
  expect_true(startsWith(id, "local:"))
  expect_true(all(is.na(TaxaTools::parent_at(id, c("family"), reg))))
  expect_identical(reg$taxa$rank[reg$taxa$name == "Labridae"], "family")
})

test_that("an unplaced tied candidate does not block the registry LCA: the ring takes the member clades' shared order, not the kingdom label", {
  .rg_skip(); reg <- .lf_registry()
  # TaxaLikely named the family ring at the kingdom (the unplaced candidate's lineage lacked order), members Embiotocidae|Labridae
  out <- .lf_jp(.lf_lik(c("Embiotoca jacksoni", "Novogenus ignotus"), c("Embiotocidae", "Labridae"), "Animalia", "kingdom"), reg)
  ring <- out[out$hypothesis_type == "unreferenced_genus", ]
  expect_identical(ring$taxon_name, "Perciformes")
  expect_identical(ring$taxon_name_rank, "order")
  expect_identical(ring$ring_lca_status, "lca_registry")
  rk <- attr(out, "ring_rows_rekeyed"); rk <- rk[rk$outcome %in% c("lca_registry", "lca_registry_none"), ]
  expect_identical(rk$outcome, "lca_registry")
  expect_identical(rk$n_unplaced_candidates, 1L)                 # flagged: the unplaced candidate was left out
  expect_identical(rk$member_clades_from_registry, "Labridae")   # flagged: the member clade took the registry's own taxon
})

test_that("a member clade with neither a placed candidate nor a registry taxon is not guessed: the ring keeps its own id", {
  .rg_skip(); reg <- .lf_registry()
  out <- .lf_jp(.lf_lik(c("Embiotoca jacksoni", "Novogenus ignotus"), c("Embiotocidae", "Ignotidae"), "Animalia", "kingdom",
                        members = "Embiotocidae|Ignotidae"), reg)
  ring <- out[out$hypothesis_type == "unreferenced_genus", ]
  expect_identical(ring$taxon_name, "Animalia")
  expect_identical(ring$taxon_name_rank, "kingdom")
  rk <- attr(out, "ring_rows_rekeyed")
  expect_identical(rk$outcome[rk$outcome %in% c("lca_registry", "lca_registry_none")], "lca_registry_none")
  expect_identical(attr(out, "registry_join_counts")$n_lca_rings_registry_none, 1L)
})

test_that("with every member clade placed, the search is unchanged (no candidate left out, no registry stand-in)", {
  .rg_skip(); reg <- .lf_registry()
  out <- .lf_jp(.lf_lik(c("Embiotoca jacksoni", "Oxyjulis californica"), c("Embiotocidae", "Labridae"), "Animalia", "kingdom"), reg)
  ring <- out[out$hypothesis_type == "unreferenced_genus", ]
  expect_identical(ring$taxon_name, "Perciformes")
  rk <- attr(out, "ring_rows_rekeyed"); rk <- rk[rk$outcome %in% "lca_registry", ]
  expect_identical(rk$n_unplaced_candidates, 0L)
  expect_true(is.na(rk$member_clades_from_registry))
})
