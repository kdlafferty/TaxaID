# Regression tests for the 2026-09-22 homonym-detection fix
# (ecosystem_docs/REENTRY_PROMPT_homonym_detection.md).
#
# A taxon name is not a key: NCBI can hold several nodes with the same name
# in unrelated lineages, and a name-based [Organism] search silently
# resolves to whichever node the service prefers -- measured live: a
# red-algal genus query for "Vertebrata" returned 306,181 vertebrate
# sequences alongside 68 real red-algal ones. Fully offline: rentrez calls
# are never reached directly here -- TaxaTools::resolve_ncbi_taxid() and
# TaxaTools::check_lineage_agreement() are mocked/exercised for real.

test_that(".resolve_taxa_taxids is a no-op when taxa_lineage is NULL", {
  out <- TaxaLikely:::.resolve_taxa_taxids(c("Fundulus", "Sebastes"), NULL, delay = 0)
  expect_identical(out, stats::setNames(c(NA_character_, NA_character_), c("Fundulus", "Sebastes")))
})

test_that(".resolve_taxa_taxids resolves a taxon taxa_lineage covers, skips one it doesn't", {
  testthat::local_mocked_bindings(
    resolve_ncbi_taxid = function(name, rank = NULL, lineage_terms = NULL) {
      list(taxid = "1261581", status = "resolved_by_rank", candidates = data.frame())
    },
    .package = "TaxaTools"
  )
  taxa <- c("Vertebrata", "Sebastes")
  lineage <- data.frame(taxon = "Vertebrata", rank = "genus",
    phylum = "Rhodophyta", stringsAsFactors = FALSE)
  out <- suppressMessages(TaxaLikely:::.resolve_taxa_taxids(taxa, lineage, delay = 0))
  expect_identical(out[["Vertebrata"]], "1261581")
  expect_true(is.na(out[["Sebastes"]])) # not in taxa_lineage at all -- untouched
})

test_that(".resolve_taxa_taxids leaves an ambiguous taxon as NA (no protection, but no crash)", {
  testthat::local_mocked_bindings(
    resolve_ncbi_taxid = function(name, rank = NULL, lineage_terms = NULL) {
      list(taxid = NA_character_, status = "ambiguous", candidates = data.frame())
    },
    .package = "TaxaTools"
  )
  lineage <- data.frame(taxon = "Lobophora", stringsAsFactors = FALSE)
  out <- suppressMessages(TaxaLikely:::.resolve_taxa_taxids("Lobophora", lineage, delay = 0))
  expect_true(is.na(out[["Lobophora"]]))
})

test_that(".resolve_taxa_taxids reports (not crashes on) a resolver error", {
  testthat::local_mocked_bindings(
    resolve_ncbi_taxid = function(name, rank = NULL, lineage_terms = NULL) stop("network down"),
    .package = "TaxaTools"
  )
  lineage <- data.frame(taxon = "Vertebrata", stringsAsFactors = FALSE)
  expect_warning(
    out <- suppressMessages(TaxaLikely:::.resolve_taxa_taxids("Vertebrata", lineage, delay = 0)),
    "network down"
  )
  expect_true(is.na(out[["Vertebrata"]]))
})

test_that(".resolve_taxa_taxids passes declared rank and lineage terms through", {
  captured <- NULL
  testthat::local_mocked_bindings(
    resolve_ncbi_taxid = function(name, rank = NULL, lineage_terms = NULL) {
      captured <<- list(name = name, rank = rank, lineage_terms = lineage_terms)
      list(taxid = "1", status = "unique", candidates = data.frame())
    },
    .package = "TaxaTools"
  )
  lineage <- data.frame(
    taxon = "Vertebrata", rank = "genus",
    phylum = "Rhodophyta", family = "Rhodomelaceae",
    stringsAsFactors = FALSE
  )
  suppressMessages(TaxaLikely:::.resolve_taxa_taxids("Vertebrata", lineage, delay = 0))
  expect_identical(captured$name, "Vertebrata")
  expect_identical(captured$rank, "genus")
  expect_setequal(captured$lineage_terms, c("Rhodophyta", "Rhodomelaceae"))
})

test_that(".compute_lineage_disagreements flags a row sharing nothing with its declared lineage", {
  ref <- data.frame(
    composite_id = c("A1", "A2"),
    queried_taxon = c("Vertebrata", "Vertebrata"),
    kingdom = c("Plantae", "Metazoa"),
    phylum = c("Rhodophyta", "Chordata"),
    family = c("Rhodomelaceae", "Phyllostomidae"),
    stringsAsFactors = FALSE
  )
  lineage <- data.frame(
    taxon = "Vertebrata", phylum = "Rhodophyta", family = "Rhodomelaceae",
    stringsAsFactors = FALSE
  )
  out <- TaxaLikely:::.compute_lineage_disagreements(ref, lineage)
  expect_identical(out$composite_id, "A2")
})

test_that(".compute_lineage_disagreements finds nothing when everything agrees", {
  ref <- data.frame(
    composite_id = "A1", queried_taxon = "Fundulus",
    family = "Fundulidae", stringsAsFactors = FALSE
  )
  lineage <- data.frame(taxon = "Fundulus", family = "Fundulidae", stringsAsFactors = FALSE)
  out <- TaxaLikely:::.compute_lineage_disagreements(ref, lineage)
  expect_equal(nrow(out), 0L)
})

test_that(".compute_lineage_disagreements does not flag a row taxa_lineage says nothing about", {
  # No shared columns between reference_df and taxa_lineage's own lineage
  # ranks -- both sides reduce to "", which check_lineage_agreement()
  # reports "unknown", not "disagrees" (no evidence is not evidence of a
  # homonym).
  ref <- data.frame(composite_id = "A1", queried_taxon = "Fundulus", stringsAsFactors = FALSE)
  lineage <- data.frame(taxon = "Fundulus", stringsAsFactors = FALSE)
  out <- TaxaLikely:::.compute_lineage_disagreements(ref, lineage)
  expect_equal(nrow(out), 0L)
})

test_that("fetch_ncbi_reference_sequences validates taxa_lineage", {
  expect_error(
    fetch_ncbi_reference_sequences(taxa = "Fundulus", barcode_term = "12S", taxa_lineage = "not a df"),
    "must be a data frame"
  )
  expect_error(
    fetch_ncbi_reference_sequences(
      taxa = "Fundulus", barcode_term = "12S",
      taxa_lineage = data.frame(x = 1)
    ),
    "taxon"
  )
})

test_that(".build_search_term/.ref_cache_file/.ref_cache_grammar agree on the taxid suffix", {
  # A focused end-to-end check of the three pieces the homonym fix touches
  # together, without a live NCBI call: a resolved taxid changes the QUERY
  # (.build_search_term) and the cache KEY (.ref_cache_file), and the key
  # stays reachable by its own grammar.
  bst <- TaxaLikely:::.build_search_term
  term <- bst("Vertebrata", "COI", taxid = "1261581")
  expect_true(grepl("txid1261581\\[ORGN\\]", term))

  f <- basename(TaxaLikely:::.ref_cache_file(
    "/tmp/c", "Vertebrata", "COI", 100L, 900L, NULL, NULL, FALSE, 2L, 200000L,
    c("family", "genus", "species"), taxid = "1261581"
  ))
  expect_true(grepl("_txid1261581_meta\\.rds$", f))
  expect_true(grepl(TaxaLikely:::.ref_cache_grammar(), f))
})
