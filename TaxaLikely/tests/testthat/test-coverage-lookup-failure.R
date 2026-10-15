# audit_barcode_coverage(): an NCBI request that could not be made is not an
# answer. Before 2026-10-15 a genus whose enumeration or reverse barcode check
# failed either vanished from $unreferenced (a silently TRUNCATED set -- Mugu
# 12S 59 vs 445, 16S 0 vs 380 during a network outage, then cached by the
# workflow) or had every candidate reported unreferenced. Fully offline:
# rentrez and TaxaTools::resolve_ncbi_taxid() are mocked at the network boundary.

.summ <- function(uid, name) structure(list(uid = uid, rank = "species", scientificname = name), class = c("esummary", "list"))

.mock_coverage_ncbi <- function(fail_enumerate = character(0), fail_reverse = character(0)) {
  taxid_of <- c(Aa = "100", Bb = "200", Cc = "300")
  testthat::local_mocked_bindings(
    resolve_ncbi_taxid = function(name, ...) list(taxid = unname(taxid_of[[name]])),
    .package = "TaxaTools", .env = parent.frame()
  )
  species_of <- list(`100` = c("1", "2"), `200` = c("3", "4"), `300` = c("5"))
  name_of <- c(`1` = "Aa one", `2` = "Aa two", `3` = "Bb one", `4` = "Bb two", `5` = "Cc one")
  testthat::local_mocked_bindings(
    entrez_search = function(db, term, ...) {
      tid <- sub(".*txid([0-9]+).*", "\\1", term)
      genus <- names(taxid_of)[taxid_of == tid]
      if (db == "taxonomy") {
        if (genus %in% fail_enumerate) stop("NCBI unreachable")
        return(list(count = as.character(length(species_of[[tid]])), ids = species_of[[tid]]))
      }
      if (genus %in% fail_reverse) stop("NCBI unreachable")
      list(count = "0", ids = character(0))        # no sequences: every candidate unreferenced
    },
    entrez_summary = function(db, id, ...) lapply(id, function(i) .summ(i, name_of[[i]])),
    .package = "rentrez", .env = parent.frame()
  )
  testthat::local_mocked_bindings(.ncbi_delay = function() 0, .env = parent.frame())
}

.match_df <- data.frame(genus = c("Aa", "Bb", "Cc"), species = c("Aa one", "Bb one", "Cc one"), stringsAsFactors = FALSE)

test_that("a failed species enumeration is reported, named, excluded from $unreferenced and never checkpointed", {
  .mock_coverage_ncbi(fail_enumerate = "Aa")
  cd <- tempfile("covcache_"); dir.create(cd); on.exit(unlink(cd, recursive = TRUE), add = TRUE)
  expect_warning(
    expect_warning(
      out <- suppressMessages(audit_barcode_coverage(.match_df, barcode_term = "12S", cache_dir = cd)),
      "taxonomy query failed for 'Aa'"
    ),
    "lookup FAILED for 1 of 3 genus\\(s\\) \\(Aa\\)"
  )
  expect_identical(attr(out, "lookup_failures"), "Aa")
  expect_identical(out$census$lookup_failed, c(TRUE, FALSE, FALSE))
  expect_false(out$census$is_complete[1])
  expect_setequal(out$unreferenced, "Bb two")          # Aa's species absent, Bb's real answer present
  expect_length(list.files(cd, recursive = TRUE), 0L)  # checkpoint removed on completion; Aa never written
})

test_that("a failed reverse barcode check does not report every candidate unreferenced", {
  .mock_coverage_ncbi(fail_reverse = "Bb")
  out <- suppressWarnings(suppressMessages(
    audit_barcode_coverage(.match_df, barcode_term = "12S", cache_dir = NULL)
  ))
  expect_identical(attr(out, "lookup_failures"), "Bb")
  expect_false("Bb two" %in% out$unreferenced)          # would have been "unreferenced" by default before
  expect_identical(out$unreferenced, "Aa two")           # Aa's genuine answer (no sequences) is kept
})

test_that("on_lookup_failure = 'error' stops instead of returning a truncated set; a clean run returns no failures", {
  .mock_coverage_ncbi(fail_enumerate = "Cc")
  expect_error(
    suppressWarnings(suppressMessages(
      audit_barcode_coverage(.match_df, barcode_term = "12S", cache_dir = NULL, on_lookup_failure = "error")
    )),
    "lookup FAILED"
  )
  .mock_coverage_ncbi()
  out <- suppressMessages(audit_barcode_coverage(.match_df, barcode_term = "12S", cache_dir = NULL))
  expect_identical(attr(out, "lookup_failures"), character(0))
  expect_false(any(out$census$lookup_failed))
})
