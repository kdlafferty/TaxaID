# Outer rings when the candidates tied with the unit anchor span clades: the ring is named at the tied candidates'
# lowest common rank (searching candidate_df's coarser lineage columns too), ring_member_clades lists the tied values at
# the ring's own rank, and the ring's value is unchanged.

.lca_params <- function(ring_ranks) {
  nm <- c("score_logit", "gap_logit")
  sig <- matrix(c(2.0, 0.2, 0.2, 1.0), 2L, dimnames = list(nm, nm))
  h2s <- diag(c(1.0, 1.0)); dimnames(h2s) <- list(nm, nm)
  h3s <- diag(c(1.5, 1.0)); dimnames(h3s) <- list(nm, nm)
  rt <- c(order = "unreferenced_family", class = "unreferenced_order", phylum = "unreferenced_class")
  p <- list(
    H1_Global_Mu = c(score_logit = 3.5, gap_logit = 1.5), H1_Sigma = sig,
    H2 = list(delta = 3.0, sigma = h2s), H3 = list(delta = 5.0, sigma = h3s),
    Stats = list(n_species = 1L, n_singletons = 0L), Score_Transform = "logit",
    Rings = stats::setNames(lapply(ring_ranks, function(rk) {
      list(rank = rk, hypothesis_type = rt[[rk]], delta = 6.0, sigma = h3s, n = 10L, n_groups = 4L)
    }), ring_ranks)
  )
  structure(p, class = "taxa_model_params")
}

# 18S_ESV_012025 shape: a shrimp tied with gastropods at one 18S identity
.lca_18s <- function(score = c(97.8, 97.8, 97.8)) {
  data.frame(
    observation_id = "18S_ESV_012025",
    taxon_name = c("Lebbeus polaris", "Littorina littorea", "Buccinum undatum"),
    score = score, taxon_name_rank = "species",
    kingdom = "Eukaryota", phylum = c("Arthropoda", "Mollusca", "Mollusca"),
    class = c("Malacostraca", "Gastropoda", "Gastropoda"),
    order = c("Decapoda", "Littorinimorpha", "Neogastropoda"),
    family = c("Hippolytidae", "Littorinidae", "Buccinidae"),
    genus = c("Lebbeus", "Littorina", "Buccinum"),
    stringsAsFactors = FALSE
  ) |> transform(species = taxon_name)
}

.lca_eval <- function(df, p, rs = c("class", "order", "family", "genus", "species")) {
  as.data.frame(TaxaLikely:::.evaluate_one_query(df, p, rs, ratio_threshold = 0))
}
.ring <- function(out, type) out[out$hypothesis_type == type, , drop = FALSE]

test_that("18S: a shrimp tied with gastropods names both outer rings at their common rank, with the member clades", {
  skip_if_not_installed("TaxaTools")
  out <- .lca_eval(.lca_18s(), .lca_params(c("order", "class")))
  fam <- .ring(out, "unreferenced_family"); ord <- .ring(out, "unreferenced_order")
  expect_equal(nrow(fam), 1L); expect_equal(nrow(ord), 1L)
  # Arthropoda | Mollusca share no phylum: kingdom, from candidate_df's coarser column (rank_system starts at class)
  expect_identical(fam$taxon_name, "Eukaryota"); expect_identical(fam$taxon_name_rank, "kingdom")
  expect_identical(ord$taxon_name, "Eukaryota"); expect_identical(ord$taxon_name_rank, "kingdom")
  expect_identical(fam$ring_member_clades, "Decapoda|Littorinimorpha|Neogastropoda")
  expect_identical(ord$ring_member_clades, "Gastropoda|Malacostraca")
  # every other row carries NA
  expect_true(all(is.na(out$ring_member_clades[!out$hypothesis_type %in% c("unreferenced_family", "unreferenced_order")])))
})

test_that("gastropods of two orders tied: the order ring is named at their class; the class ring is not triggered", {
  skip_if_not_installed("TaxaTools")
  df <- .lca_18s()[2:3, ]
  out <- .lca_eval(df, .lca_params(c("order", "class")))
  fam <- .ring(out, "unreferenced_family"); ord <- .ring(out, "unreferenced_order")
  expect_identical(fam$taxon_name, "Gastropoda"); expect_identical(fam$taxon_name_rank, "class")
  expect_identical(fam$ring_member_clades, "Littorinimorpha|Neogastropoda")
  expect_identical(ord$taxon_name, "Gastropoda"); expect_true(is.na(ord$ring_member_clades))   # D: same name, two types
})

test_that("a common rank must hold for EVERY tied candidate: one missing phylum sends the ring to kingdom", {
  skip_if_not_installed("TaxaTools")
  df <- .lca_18s()[1:2, ]
  df$phylum[2] <- NA            # 18S_ESV_000109 shape: the dinoflagellate carried no phylum
  out <- .lca_eval(df, .lca_params("class"))
  ord <- .ring(out, "unreferenced_order")
  expect_identical(ord$taxon_name, "Eukaryota")   # NOT "Arthropoda", the only phylum present
  expect_identical(ord$taxon_name_rank, "kingdom")
})

test_that("no common rank at all: every lineage column and taxon_name are NA; the members are still listed", {
  skip_if_not_installed("TaxaTools")
  df <- .lca_18s()[1:2, ]; df$kingdom <- c("Eukaryota", "Metazoa")
  out <- .lca_eval(df, .lca_params("class"))
  ord <- .ring(out, "unreferenced_order")
  expect_equal(nrow(ord), 1L)
  expect_true(is.na(ord$taxon_name)); expect_true(is.na(ord$taxon_name_rank))
  expect_identical(ord$ring_member_clades, "Gastropoda|Malacostraca")
})

test_that("only TIED candidates count: a lower-scoring candidate of another clade does not trigger", {
  skip_if_not_installed("TaxaTools")
  out <- .lca_eval(.lca_18s(score = c(90.0, 97.8, 97.8)), .lca_params("class"))
  ord <- .ring(out, "unreferenced_order")
  expect_identical(ord$taxon_name, "Gastropoda"); expect_true(is.na(ord$ring_member_clades))
})

test_that("a restored candidate of another clade does not trigger when a real hit holds the tie (.pick_anchor's own step)", {
  skip_if_not_installed("TaxaTools")
  df <- .lca_18s(); df$is_restored <- c(TRUE, FALSE, FALSE)
  out <- .lca_eval(df, .lca_params("class"))
  ord <- .ring(out, "unreferenced_order")
  expect_identical(ord$taxon_name, "Gastropoda"); expect_true(is.na(ord$ring_member_clades))
})

test_that("the ring's VALUE is unchanged by the relabel: same anchor, same density", {
  skip_if_not_installed("TaxaTools")
  p <- .lca_params(c("order", "class"))
  trig <- .lca_eval(.lca_18s(), p)
  same <- .lca_18s()                         # identical scores and names; lineage made common, so nothing triggers
  for (r in c("phylum", "class", "order", "family")) same[[r]] <- same[[r]][1L]
  ctl <- .lca_eval(same, p)
  expect_true(all(is.na(ctl$ring_member_clades)))
  for (ty in c("unreferenced_family", "unreferenced_order")) {
    expect_identical(.ring(trig, ty)$raw_likelihood, .ring(ctl, ty)$raw_likelihood)
    expect_identical(.ring(trig, ty)$score_likelihood, .ring(ctl, ty)$score_likelihood)
  }
})

test_that("COI: a chordate tied with a mollusc names the phylum ring at kingdom", {
  skip_if_not_installed("TaxaTools")
  df <- data.frame(
    observation_id = "COI_ESV_280817", taxon_name = c("Aethomys kaiseri", "Mytilus edulis"),
    score = c(88.0, 88.0), taxon_name_rank = "species", kingdom = "Eukaryota",
    phylum = c("Chordata", "Mollusca"), class = c("Mammalia", "Bivalvia"), order = c("Rodentia", "Mytilida"),
    family = c("Muridae", "Mytilidae"), genus = c("Aethomys", "Mytilus"), stringsAsFactors = FALSE
  ) |> transform(species = taxon_name)
  out <- .lca_eval(df, .lca_params(c("order", "class", "phylum")), rs = c("phylum", "class", "order", "family", "genus", "species"))
  cls <- .ring(out, "unreferenced_class")
  expect_identical(cls$taxon_name, "Eukaryota"); expect_identical(cls$taxon_name_rank, "kingdom")
  expect_identical(cls$ring_member_clades, "Chordata|Mollusca")
  expect_identical(.ring(out, "unreferenced_family")$ring_member_clades, "Mytilida|Rodentia")
})

test_that("evaluate_likelihoods() carries ring_member_clades to its output, NA where nothing triggered", {
  skip_if_not_installed("TaxaTools")
  df <- rbind(.lca_18s(), transform(.lca_18s(score = c(90.0, 97.8, 95.0)), observation_id = "untied"))   # one top score: no tie
  res <- suppressWarnings(suppressMessages(TaxaLikely::evaluate_likelihoods(
    match_df = df, model_params = .lca_params(c("order", "class")), rank_system = c("class", "order", "family", "genus", "species"),
    n_sims = 5, ratio_threshold = 0)))$likelihoods
  expect_true("ring_member_clades" %in% names(res))
  a <- res[res$observation_id == "18S_ESV_012025" & res$hypothesis_type == "unreferenced_order", ]
  expect_identical(a$ring_member_clades, "Gastropoda|Malacostraca"); expect_identical(a$taxon_name, "Eukaryota")
  expect_true(all(is.na(res$ring_member_clades[res$observation_id == "untied"])))
  expect_true(all(is.finite(a$score_likelihood_mean)))   # the Monte Carlo maps rings by type, not by name
})
