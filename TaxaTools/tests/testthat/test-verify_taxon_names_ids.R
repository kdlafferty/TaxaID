# verify_taxon_names(return_ids = TRUE): the record identifiers the Global Names
# Verifier sends, which the wrapper used to drop. Fully offline: httr is mocked
# at the network boundary and answers from a recorded response
# (fixtures/gnv_ds11_bestresult.json; see fixtures/README.md).

.gnv_fixture <- function() {
  jsonlite::fromJSON(testthat::test_path("fixtures", "gnv_ds11_bestresult.json"), simplifyVector = FALSE)
}

# POST answers only the names asked, from the fixture; a name the fixture lacks
# comes back with no bestResult (a genuine non-match).
.mock_gnv <- function(env = parent.frame()) {
  fx <- .gnv_fixture()
  by_name <- stats::setNames(fx$names, vapply(fx$names, function(n) n$name, ""))
  testthat::local_mocked_bindings(
    POST = function(url, body, ...) structure(list(asked = unlist(body$nameStrings)), class = "mock_response"),
    status_code = function(resp) 200L,
    content = function(resp, ...) list(names = lapply(resp$asked, function(n) by_name[[n]] %||% list(name = n, matchType = "NoMatch"))),
    .package = "httr", .env = env
  )
}

test_that("default output is unchanged: no identifier columns unless asked", {
  .mock_gnv()
  out <- suppressMessages(verify_taxon_names(c("Hypsurus caryi", "Embiotoca caryi"), backbone_id = 11))
  expect_false(any(c("record_id", "current_record_id", "classification_ids", "match_type") %in% names(out)))
})

test_that("return_ids = TRUE gives the record, the accepted record and every ancestor's id", {
  .mock_gnv()
  out <- suppressMessages(verify_taxon_names(c("Hypsurus caryi", "Embiotoca caryi", "Not a taxon"),
                                             backbone_id = 11, return_ids = TRUE))
  expect_identical(utils::tail(names(out), 6L),
                   c("record_id", "current_record_id", "classification_ids", "data_source_id", "entry_date", "match_type"))
  # accepted name: record == current
  expect_identical(out$record_id[1], "2389310")
  expect_identical(out$current_record_id[1], "2389310")
  # the synonym is OBSERVED, not inferred: its own record differs from the accepted one
  expect_identical(out$record_id[2], "2389311")
  expect_identical(out$current_record_id[2], "2389310")
  expect_true(out$is_synonym[2])
  expect_identical(out$classification_ids[2], "1|44|587|4269|2389309|2389310")
  expect_identical(out$entry_date[1], "2024-01-11")
  expect_identical(out$data_source_id[1:2], c(11L, 11L))
  # a non-match has NA ids, not an empty string
  expect_true(is.na(out$record_id[3]) && is.na(out$current_record_id[3]) && is.na(out$classification_ids[3]))
  expect_false(out$matched[3])
})

test_that("a fuzzy answer is labelled as one (it is a different string, never a declared synonym)", {
  .mock_gnv()
  out <- suppressMessages(verify_taxon_names("Platybelone argala", backbone_id = 11, return_ids = TRUE))
  expect_identical(out$match_type, "Fuzzy")
  expect_identical(out$matched_name, "Platybelone argalus")
})

test_that("a lineage-gated homonym loses its ids along with its name", {
  .mock_gnv()
  # GBIF's only Vertebrata is the red-alga genus; asked as the animal clade it must not resolve
  out <- suppressMessages(verify_taxon_names("Vertebrata", backbone_id = 11, input_rank = "genus",
                                             lineage = "Animalia|Chordata", return_ids = TRUE))
  expect_false(out$verified)
  expect_true(is.na(out$current_record_id) && is.na(out$classification_ids))
  # an ANSWER refused by the gate, not a failed request, and labelled as such
  expect_identical(out$match_type, "LineageRejected")
  plain <- suppressMessages(verify_taxon_names("Vertebrata", backbone_id = 11, input_rank = "genus", lineage = "Animalia|Chordata"))
  expect_false("match_type" %in% names(plain))
})

test_that("an entry cached WITHOUT ids is never served to a call asking for them", {
  .mock_gnv()
  d <- withr::local_tempdir()
  a <- suppressMessages(verify_taxon_names("Hypsurus caryi", backbone_id = 11, cache_dir = d))
  expect_false("record_id" %in% names(a))
  b <- suppressMessages(verify_taxon_names("Hypsurus caryi", backbone_id = 11, cache_dir = d, return_ids = TRUE))
  expect_identical(b$current_record_id, "2389310")
  # and the id-bearing answer is itself cached: a second call is served with ids, network off
  testthat::local_mocked_bindings(POST = function(...) stop("network must not be reached"), .package = "httr")
  c2 <- suppressMessages(verify_taxon_names("Hypsurus caryi", backbone_id = 11, cache_dir = d, return_ids = TRUE))
  expect_identical(c2$current_record_id, "2389310")
})

test_that("return_ids must be TRUE or FALSE", {
  expect_error(verify_taxon_names("Hypsurus caryi", backbone_id = 11, return_ids = NA), "return_ids")
})

# --- NCBI path: the taxid it already resolves is kept --------------------------------------
.lin_xml_ids <- function(ids) {
  parts <- vapply(ids, function(x) sprintf(
    paste0("<Taxon><TaxId>%s</TaxId><ScientificName>%s</ScientificName><Rank>genus</Rank>",
           "<LineageEx><Taxon><TaxId>33208</TaxId><ScientificName>Metazoa</ScientificName><Rank>kingdom</Rank></Taxon>",
           "<Taxon><TaxId>7711</TaxId><ScientificName>Chordata</ScientificName><Rank>phylum</Rank></Taxon></LineageEx></Taxon>"),
    x, c(`11` = "Aa", `22` = "Bb")[[x]]), character(1L))
  sprintf("<TaxaSet>%s</TaxaSet>", paste(parts, collapse = ""))
}

test_that("the NCBI path returns the taxid and the ancestors' taxids when asked, and nothing extra when not", {
  testthat::local_mocked_bindings(
    entrez_search = function(db, term, ...) {
      ids <- c(if (grepl("Aa", term, fixed = TRUE)) "11", if (grepl("Bb", term, fixed = TRUE)) "22")
      list(count = as.character(length(ids)), ids = ids)
    },
    entrez_summary = function(db, id, ...) lapply(id, function(i) structure(list(uid = i, rank = "genus", division = "x",
      scientificname = c(`11` = "Aa", `22` = "Bb")[[i]]), class = c("esummary", "list"))),
    entrez_fetch = function(db, id, rettype, ...) .lin_xml_ids(id),
    .package = "rentrez"
  )
  testthat::local_mocked_bindings(POST = function(...) stop("offline"), .package = "httr")
  plain <- suppressWarnings(suppressMessages(TaxaTools:::.verify_via_ncbi(c("Aa", "Bb"), fallback_backbone_id = 11L)))
  expect_false(any(c("record_id", "classification_ids") %in% names(plain)))
  ids <- suppressWarnings(suppressMessages(TaxaTools:::.verify_via_ncbi(c("Aa", "Bb"), fallback_backbone_id = 11L, return_ids = TRUE)))
  expect_identical(ids$record_id, c("11", "22"))
  expect_identical(ids$current_record_id, c("11", "22"))
  expect_identical(ids$classification_ids, c("33208|7711|11", "33208|7711|22"))
  expect_identical(ids$data_source_id, c(4L, 4L))
})
