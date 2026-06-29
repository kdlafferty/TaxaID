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
    observation_id  = "obs1",
    consensus_taxon = "Oncorhynchus",
    consensus_rank  = "genus",
    downranked      = TRUE,
    stringsAsFactors = FALSE
  )
  df$plausible_taxa <- list(c("Salmo salar", "Salvelinus leucomaenis"))
  result <- add_slash_taxon(df)
  expect_true(is.na(result$slash_taxon_name))
})

test_that("add_slash_taxon: downranked=TRUE, genera consistent with consensus -> slash name kept", {
  # downranked fired but plausible_taxa are already the correct genus.
  df <- data.frame(
    observation_id  = "obs1",
    consensus_taxon = "Oncorhynchus",
    consensus_rank  = "genus",
    downranked      = TRUE,
    stringsAsFactors = FALSE
  )
  df$plausible_taxa <- list(c("Oncorhynchus tshawytscha", "Oncorhynchus kisutch"))
  result <- add_slash_taxon(df)
  expect_equal(result$slash_taxon_name, "Oncorhynchus kisutch/tshawytscha")
})

test_that("add_slash_taxon: downranked=FALSE, mixed-genus slash name kept regardless", {
  df <- data.frame(
    observation_id  = "obs1",
    consensus_taxon = "Salmonidae",
    consensus_rank  = "family",
    downranked      = FALSE,
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
  df$plausible_taxa      <- list(c("Oncorhynchus tshawytscha", "Oncorhynchus kisutch"))
  df$plausible_posteriors <- list(c(0.7, 0.3))  # tshawytscha higher
  result <- add_slash_taxon(df)
  expect_equal(result$slash_taxon_name, "Oncorhynchus tshawytscha/kisutch")
})

test_that("add_slash_taxon: posterior ordering — mixed-genus, highest posterior first", {
  df <- data.frame(
    observation_id = "obs1",
    consensus_taxon = "Salmonidae",
    stringsAsFactors = FALSE
  )
  df$plausible_taxa       <- list(c("Salmo salar", "Salvelinus leucomaenis"))
  df$plausible_posteriors <- list(c(0.2, 0.8))  # Salvelinus higher
  result <- add_slash_taxon(df)
  expect_equal(result$slash_taxon_name, "Salvelinus leucomaenis + Salmo salar")
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
