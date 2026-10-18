# A name NCBI could not be ASKED about is reported with verified = FALSE and is
# never cached. Before 2026-10-14 the NCBI path reported a failed search batch,
# a failed synonym fallback and a failed lineage fetch all as verified = TRUE /
# matched_name = NA -- byte-identical to a genuine non-match -- and a cache_dir
# then served a network outage as a definitive answer (Mugu: "Notropis" and
# "Atherinops", both valid NCBI genera, cached as non-matches).
# Fully offline: rentrez and httr are mocked at the network boundary.

.lin_xml <- function(ids) {
  parts <- vapply(ids, function(x) sprintf(
    paste0("<Taxon><TaxId>%s</TaxId><ScientificName>%s</ScientificName><Rank>genus</Rank>",
           "<LineageEx><Taxon><TaxId>1</TaxId><ScientificName>Metazoa</ScientificName>",
           "<Rank>kingdom</Rank></Taxon></LineageEx></Taxon>"),
    x, c(`11` = "Aa", `22` = "Bb")[[x]]), character(1L))
  sprintf("<TaxaSet>%s</TaxaSet>", paste(parts, collapse = ""))
}
.summ <- function(uid, name) structure(list(uid = uid, rank = "genus", division = "x", scientificname = name), class = c("esummary", "list"))

# search: Aa -> 11, Bb -> 22; a term containing a name listed in `fail_search`
# errors; an [All Names] term for a name in `fail_fallback` errors; a lineage
# fetch containing a taxid in `fail_fetch` errors.
.mock_ncbi <- function(fail_search = character(0), fail_fallback = character(0), fail_fetch = character(0)) {
  testthat::local_mocked_bindings(
    entrez_search = function(db, term, ...) {
      if (any(vapply(fail_search, function(n) grepl(n, term, fixed = TRUE), logical(1)))) stop("NCBI unreachable")
      if (grepl("[All Names]", term, fixed = TRUE)) {
        if (any(vapply(fail_fallback, function(n) grepl(n, term, fixed = TRUE), logical(1)))) stop("NCBI unreachable")
        return(list(count = "0", ids = character(0)))
      }
      ids <- c(if (grepl("Aa", term, fixed = TRUE)) "11", if (grepl("Bb", term, fixed = TRUE)) "22")
      list(count = as.character(length(ids)), ids = ids)
    },
    entrez_summary = function(db, id, ...) lapply(id, function(i) .summ(i, c(`11` = "Aa", `22` = "Bb")[[i]])),
    entrez_fetch = function(db, id, rettype, ...) {
      if (any(id %in% fail_fetch)) stop("NCBI unreachable")
      .lin_xml(id)
    },
    .package = "rentrez", .env = parent.frame()
  )
  # the GlobalNames fuzzy fallback (Step 1c) must not reach the network either
  testthat::local_mocked_bindings(POST = function(...) stop("offline"), .package = "httr", .env = parent.frame())
}

test_that("a failed search batch reports its names as verified = FALSE, a sibling batch is unaffected", {
  .mock_ncbi(fail_search = "Bb")
  out <- suppressWarnings(suppressMessages(
    TaxaTools:::.verify_via_ncbi(c("Aa", "Bb"), search_batch_size = 1L, fallback_backbone_id = 11L)
  ))
  expect_identical(out$user_supplied_name, c("Aa", "Bb"))
  expect_identical(out$verified, c(TRUE, FALSE))
  expect_identical(out$matched_name, c("Aa", NA_character_))
})

test_that("a failed lineage fetch reports its taxids' names as verified = FALSE", {
  .mock_ncbi(fail_fetch = "22")
  out <- suppressWarnings(suppressMessages(
    TaxaTools:::.verify_via_ncbi(c("Aa", "Bb"), fetch_batch_size = 1L, fallback_backbone_id = 11L)
  ))
  expect_identical(out$verified, c(TRUE, FALSE))
  expect_identical(out$matched_name, c("Aa", NA_character_))
})

test_that("a failed [All Names] synonym check is verified = FALSE; an answered miss is verified = TRUE", {
  .mock_ncbi(fail_fallback = "Cc")
  out <- suppressWarnings(suppressMessages(
    TaxaTools:::.verify_via_ncbi(c("Aa", "Cc", "Dd"), fallback_backbone_id = 11L)
  ))
  expect_identical(out$user_supplied_name, c("Aa", "Cc", "Dd"))
  expect_identical(out$verified, c(TRUE, FALSE, TRUE))   # Dd: searched, nothing found, no error
  expect_true(all(is.na(out$matched_name[2:3])))
})

test_that("verify_taxon_names(cache_dir=) on the NCBI path never writes a failed name, and re-asks it", {
  .mock_ncbi(fail_fallback = "Cc")
  dir <- withr::local_tempdir()
  out1 <- suppressWarnings(suppressMessages(
    verify_taxon_names(c("Aa", "Cc", "Dd"), backbone_id = 4L, cache_dir = dir)
  ))
  expect_identical(out1$verified, c(TRUE, FALSE, TRUE))
  files <- list.files(dir, "_verified_name\\.rds$", full.names = TRUE)
  expect_length(files, 2L)                                   # Aa and Dd, never Cc
  cached_names <- vapply(files, function(p) readRDS(p)$row$user_supplied_name, character(1))
  expect_setequal(unname(cached_names), c("Aa", "Dd"))
  expect_true(all(vapply(files, function(p) isTRUE(readRDS(p)$answered), logical(1))))
  out2 <- suppressWarnings(suppressMessages(
    verify_taxon_names(c("Aa", "Cc", "Dd"), backbone_id = 4L, cache_dir = dir)
  ))
  expect_identical(out2$verified, c(TRUE, FALSE, TRUE))      # Cc asked again, still unavailable
})

# ---- homonyms: resolved by the caller's rank; an undecidable residue is ----
# ---- isolated (verified = FALSE for that name) instead of aborting the batch --

.mock_homonym_ncbi <- function() {
  # "Ee" is an NCBI homonym: genus 55 and subgenus 56 (the Etheostoma shape);
  # "Aa" resolves uniquely to 11. No name is ever resolved by any fallback.
  .s <- function(uid, rank, name) structure(list(uid = uid, rank = rank, division = "fish", scientificname = name), class = c("esummary", "list"))
  lin <- function(ids) sprintf("<TaxaSet>%s</TaxaSet>", paste(vapply(ids, function(x) sprintf(
    "<Taxon><TaxId>%s</TaxId><ScientificName>%s</ScientificName><Rank>%s</Rank><LineageEx><Taxon><TaxId>1</TaxId><ScientificName>Metazoa</ScientificName><Rank>kingdom</Rank></Taxon></LineageEx></Taxon>",
    x, c(`11` = "Aa", `55` = "Ee", `56` = "Ee")[[x]], c(`11` = "genus", `55` = "genus", `56` = "subgenus")[[x]]), character(1L)), collapse = ""))
  testthat::local_mocked_bindings(
    entrez_search = function(db, term, ...) {
      if (grepl("[All Names]", term, fixed = TRUE)) return(list(count = "0", ids = character(0)))
      ids <- c(if (grepl("Aa", term, fixed = TRUE)) "11", if (grepl("Ee", term, fixed = TRUE)) c("55", "56"))
      list(count = as.character(length(ids)), ids = ids)
    },
    entrez_summary = function(db, id, ...) lapply(id, function(i) switch(i, `11` = .s("11", "genus", "Aa"), `55` = .s("55", "genus", "Ee"), `56` = .s("56", "subgenus", "Ee"))),
    entrez_fetch = function(db, id, rettype, ...) lin(id),
    .package = "rentrez", .env = parent.frame()
  )
  testthat::local_mocked_bindings(.is_interactive_session = function() FALSE, .env = parent.frame())
  testthat::local_mocked_bindings(POST = function(...) stop("offline"), .package = "httr", .env = parent.frame())
}

test_that("a homonym with exactly one candidate at the caller's rank resolves by rank, no decision needed", {
  .mock_homonym_ncbi()
  out <- suppressWarnings(suppressMessages(
    verify_taxon_names(c("Aa", "Ee"), backbone_id = 4L, input_rank = c("genus", "genus"))
  ))
  expect_identical(out$verified, c(TRUE, TRUE))
  expect_identical(out$matched_name, c("Aa", "Ee"))
  expect_identical(out$matched_rank, c("genus", "genus"))      # taxid 55, the genus, not the subgenus
})

test_that("without a rank or decisions, non-interactive: the ambiguous name alone is verified = FALSE and the batch proceeds", {
  .mock_homonym_ncbi()
  expect_warning(
    out <- suppressMessages(verify_taxon_names(c("Aa", "Ee"), backbone_id = 4L)),
    "could not be told apart by rank"
  )
  expect_identical(out$verified, c(TRUE, FALSE))
  expect_identical(out$matched_name, c("Aa", NA_character_))
  dir <- withr::local_tempdir()
  out2 <- suppressWarnings(suppressMessages(verify_taxon_names(c("Aa", "Ee"), backbone_id = 4L, cache_dir = dir)))
  expect_length(list.files(dir, "_verified_name\\.rds$"), 1L)   # Aa cached, Ee never
})

test_that("a rank that does not single out a candidate falls through; decisions supplied but not covering still stop", {
  .mock_homonym_ncbi()
  expect_warning(
    out <- suppressMessages(verify_taxon_names("Ee", backbone_id = 4L, input_rank = "species")),
    "could not be told apart by rank"
  )
  expect_false(out$verified)
  expect_error(
    suppressWarnings(suppressMessages(verify_taxon_names("Ee", backbone_id = 4L,
      decisions = data.frame(name = "Other", taxid = "1", stringsAsFactors = FALSE)))),
    "`decisions` does not cover them"
  )
  expect_error(verify_taxon_names(c("Aa", "Ee"), backbone_id = 4L, input_rank = "genus"), "one rank per element")
})
