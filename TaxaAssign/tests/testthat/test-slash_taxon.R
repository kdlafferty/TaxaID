test_that("add_slash_taxon: same-genus produces abbreviated slash name", {
  df <- data.frame(
    observation_id = "obs1",
    consensus_taxon = "Oncorhynchus",
    stringsAsFactors = FALSE
  )
  df$plausible_taxa <- list(c("Oncorhynchus tshawytscha", "Oncorhynchus kisutch"))
  result <- add_slash_taxon(df)
  expect_equal(result$slash_taxon_name, "Oncorhynchus kisutch/tshawytscha")
})

test_that("add_slash_taxon: mixed-genus produces + separated slash name", {
  df <- data.frame(
    observation_id = "obs1",
    consensus_taxon = "Salmonidae",
    stringsAsFactors = FALSE
  )
  df$plausible_taxa <- list(c("Salmo salar", "Salvelinus leucomaenis"))
  result <- add_slash_taxon(df)
  expect_equal(result$slash_taxon_name, "Salmo salar + Salvelinus leucomaenis")
})

test_that("add_slash_taxon: singleton produces NA slash name", {
  df <- data.frame(
    observation_id = "obs1",
    consensus_taxon = "Oncorhynchus mykiss",
    stringsAsFactors = FALSE
  )
  df$plausible_taxa <- list("Oncorhynchus mykiss")
  result <- add_slash_taxon(df)
  expect_true(is.na(result$slash_taxon_name))
})

test_that("add_slash_taxon: downranked=TRUE, genera inconsistent with consensus -> slash name cleared to NA", {
  # Simulates the Salmo/Salvelinus -> Oncorhynchus downranking case.
  # BLAST returned Salmo + Salvelinus; species_reference downranked to Oncorhynchus.
  # slash_taxon_name should be NA so consensus_OTU falls back to consensus_taxon.
  df <- data.frame(
    observation_id = "obs1",
    consensus_taxon = "Oncorhynchus",
    consensus_rank = "genus",
    downranked = TRUE,
    stringsAsFactors = FALSE
  )
  df$plausible_taxa <- list(c("Salmo salar", "Salvelinus leucomaenis"))
  result <- add_slash_taxon(df)
  expect_true(is.na(result$slash_taxon_name))
})

test_that("add_slash_taxon: downranked=TRUE, genera consistent with consensus -> slash name kept", {
  # downranked fired but plausible_taxa are already the correct genus.
  df <- data.frame(
    observation_id = "obs1",
    consensus_taxon = "Oncorhynchus",
    consensus_rank = "genus",
    downranked = TRUE,
    stringsAsFactors = FALSE
  )
  df$plausible_taxa <- list(c("Oncorhynchus tshawytscha", "Oncorhynchus kisutch"))
  result <- add_slash_taxon(df)
  expect_equal(result$slash_taxon_name, "Oncorhynchus kisutch/tshawytscha")
})

test_that("add_slash_taxon: downranked=FALSE, mixed-genus slash name kept regardless", {
  df <- data.frame(
    observation_id = "obs1",
    consensus_taxon = "Salmonidae",
    consensus_rank = "family",
    downranked = FALSE,
    stringsAsFactors = FALSE
  )
  df$plausible_taxa <- list(c("Salmo salar", "Salvelinus leucomaenis"))
  result <- add_slash_taxon(df)
  expect_equal(result$slash_taxon_name, "Salmo salar + Salvelinus leucomaenis")
})

test_that("add_slash_taxon: posterior ordering — same-genus, highest posterior first", {
  df <- data.frame(
    observation_id = "obs1",
    consensus_taxon = "Oncorhynchus",
    stringsAsFactors = FALSE
  )
  df$plausible_taxa <- list(c("Oncorhynchus tshawytscha", "Oncorhynchus kisutch"))
  df$plausible_posteriors <- list(c(0.7, 0.3)) # tshawytscha higher
  result <- add_slash_taxon(df)
  expect_equal(result$slash_taxon_name, "Oncorhynchus tshawytscha/kisutch")
})

test_that("add_slash_taxon: posterior ordering — mixed-genus, highest posterior first", {
  df <- data.frame(
    observation_id = "obs1",
    consensus_taxon = "Salmonidae",
    stringsAsFactors = FALSE
  )
  df$plausible_taxa <- list(c("Salmo salar", "Salvelinus leucomaenis"))
  df$plausible_posteriors <- list(c(0.2, 0.8)) # Salvelinus higher
  result <- add_slash_taxon(df)
  expect_equal(result$slash_taxon_name, "Salvelinus leucomaenis + Salmo salar")
})

test_that("add_slash_taxon: consensus_OTU/primary_taxon -- slash case falls back to slash_taxon_name", {
  df <- data.frame(
    observation_id = "obs1",
    consensus_taxon = "Oncorhynchus",
    stringsAsFactors = FALSE
  )
  df$plausible_taxa <- list(c("Oncorhynchus tshawytscha", "Oncorhynchus kisutch"))
  result <- add_slash_taxon(df)
  expect_equal(result$consensus_OTU, "Oncorhynchus kisutch/tshawytscha")
  expect_equal(result$primary_taxon, "Oncorhynchus kisutch")
})

test_that("add_slash_taxon: consensus_OTU/primary_taxon -- mixed-genus splits on '+'", {
  df <- data.frame(
    observation_id = "obs1",
    consensus_taxon = "Salmonidae",
    stringsAsFactors = FALSE
  )
  df$plausible_taxa <- list(c("Salmo salar", "Salvelinus leucomaenis"))
  result <- add_slash_taxon(df)
  expect_equal(result$consensus_OTU, "Salmo salar + Salvelinus leucomaenis")
  expect_equal(result$primary_taxon, "Salmo salar")
})

test_that("add_slash_taxon: consensus_OTU/primary_taxon -- singleton falls back to consensus_taxon", {
  df <- data.frame(
    observation_id = "obs1",
    consensus_taxon = "Oncorhynchus mykiss",
    stringsAsFactors = FALSE
  )
  df$plausible_taxa <- list("Oncorhynchus mykiss")
  result <- add_slash_taxon(df)
  expect_equal(result$consensus_OTU, "Oncorhynchus mykiss")
  expect_equal(result$primary_taxon, "Oncorhynchus mykiss")
})

test_that("add_slash_taxon: consensus_OTU/primary_taxon omitted when consensus_taxon absent", {
  df <- data.frame(observation_id = "obs1", stringsAsFactors = FALSE)
  df$plausible_taxa <- list(c("Oncorhynchus tshawytscha", "Oncorhynchus kisutch"))
  result <- add_slash_taxon(df)
  expect_false("consensus_OTU" %in% names(result))
  expect_false("primary_taxon" %in% names(result))
})

test_that("add_slash_taxon: irreducible_consensus FALSE when another obs resolves the ambiguity", {
  df <- data.frame(
    observation_id = c("obs1", "obs2"),
    consensus_taxon = c("Oncorhynchus", "Oncorhynchus mykiss"),
    stringsAsFactors = FALSE
  )
  df$plausible_taxa <- list(
    c("Oncorhynchus mykiss", "Oncorhynchus kisutch"),
    "Oncorhynchus mykiss"
  )
  result <- add_slash_taxon(df)
  # obs1 is NOT irreducible because obs2 resolves to a singleton that overlaps
  expect_false(result$irreducible_consensus[[1L]])
  expect_true(result$irreducible_consensus[[2L]])
})

# ------------------------------------------------------------------------------
# Order-invariance of irreducible_consensus (2026-09-04). Candidate sets are
# ordered by POSTERIOR, so one biological unit can arrive in two orders across
# observations. Irreducibility is a property of the SET; the docstring has
# always promised order-invariance, and the implementation hashed the unsorted
# vector. Regression: GreatLakes 2026-09-04 lost a confirmed grass carp
# detection this way.
# ------------------------------------------------------------------------------

test_that("irreducible_consensus ignores the ORDER of taxa within a candidate set", {
  mk <- function(sets) {
    data.frame(
      observation_id = paste0("o", seq_along(sets)),
      consensus_taxon = "Ctenopharyngodon",
      plausible_taxa = I(sets), stringsAsFactors = FALSE
    )
  }

  same <- replicate(4, c("Ctenopharyngodon idella", "Ctenopharyngodon idellus"), simplify = FALSE)
  mixed <- c(same[1:3], list(c("Ctenopharyngodon idellus", "Ctenopharyngodon idella")))

  a <- add_slash_taxon(mk(same))$irreducible_consensus
  b <- add_slash_taxon(mk(mixed))$irreducible_consensus

  expect_true(all(a)) # one order: irreducible, as before
  expect_true(all(b)) # reversed row must not change the verdict
  expect_equal(a, b)
})

test_that("a genuinely reducible set is still FALSE regardless of order", {
  sets <- list(
    c("Genus alpha", "Genus beta"),
    c("Genus beta", "Genus alpha"),
    "Genus alpha"
  ) # smaller set sharing a taxon
  d <- data.frame(
    observation_id = c("o1", "o2", "o3"), consensus_taxon = "Genus",
    plausible_taxa = I(sets), stringsAsFactors = FALSE
  )
  r <- add_slash_taxon(d)$irreducible_consensus
  expect_false(r[1])
  expect_false(r[2]) # both orderings reduce to the singleton
  expect_true(r[3]) # the singleton itself is irreducible
})

test_that("shuffling every set leaves irreducible_consensus unchanged (invariant)", {
  set.seed(42)
  base <- list(c("A a", "A b"), c("A a", "A b", "A c"), "B x", c("B x", "B y"), c("A c", "A a"))
  d1 <- data.frame(
    observation_id = paste0("o", 1:5), consensus_taxon = "X",
    plausible_taxa = I(base), stringsAsFactors = FALSE
  )
  d2 <- d1
  d2$plausible_taxa <- I(lapply(base, sample))
  expect_equal(
    add_slash_taxon(d1)$irreducible_consensus,
    add_slash_taxon(d2)$irreducible_consensus
  )
})
