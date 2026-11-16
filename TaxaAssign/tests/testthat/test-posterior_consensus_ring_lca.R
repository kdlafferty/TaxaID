# posterior_consensus() and tied-anchor rings named at their lowest common rank (TaxaLikely ring_member_clades): a ring
# named above the consensus rank system (kingdom "Eukaryota") gives no credible node rather than an error or a call in
# one tied clade; a ring at a common class gives that class.

.rl_df <- function(ring_name, ring_rank, phylum, class, order) {
  data.frame(observation_id = "E1",
    taxon_name = c("Lebbeus polaris", "Littorina littorea", ring_name),
    taxon_name_rank = c("species", "species", ring_rank),
    hypothesis_type = c("specific_candidate", "specific_candidate", "unreferenced_family"),
    kingdom = "Eukaryota",
    phylum = c("Arthropoda", "Mollusca", phylum), class = c("Malacostraca", "Gastropoda", class),
    order = c("Decapoda", "Littorinimorpha", order), family = c("Hippolytidae", "Littorinidae", NA),
    genus = c("Lebbeus", "Littorina", NA), species = c("Lebbeus polaris", "Littorina littorea", NA),
    posterior_point_est = c(0.10, 0.10, 0.80), stringsAsFactors = FALSE)
}
.rl_pc <- function(d) as.data.frame(suppressWarnings(suppressMessages(posterior_consensus(d,
  rank_system = c("phylum", "class", "order", "family", "genus", "species"), consensus_method = "credible_node",
  cumulative_threshold = 0.90, min_posterior = 0.05, lookup_missing_taxonomy = FALSE))))

test_that("a ring named at kingdom (no common phylum) gives no credible node, not an error or a one-clade call", {
  old <- .rl_pc(.rl_df("Decapoda", "order", "Arthropoda", "Malacostraca", "Decapoda"))
  expect_identical(old$consensus_taxon, "Decapoda")   # the tie-broken label put 0.8 of the mass in one tied clade
  new <- .rl_pc(.rl_df("Eukaryota", "kingdom", NA, NA, NA))
  expect_equal(nrow(new), 1L)
  expect_true(is.na(new$consensus_taxon))
  expect_identical(new$consensus_reason, "no_credible_node")
})

test_that("a ring named at the tied candidates' common class gives that class", {
  out <- .rl_pc(.rl_df("Gastropoda", "class", "Mollusca", "Gastropoda", NA))
  expect_identical(out$consensus_taxon, "Gastropoda"); expect_identical(out$consensus_rank, "class")
  expect_equal(out$consensus_posterior, 0.9, tolerance = 1e-9)
})
