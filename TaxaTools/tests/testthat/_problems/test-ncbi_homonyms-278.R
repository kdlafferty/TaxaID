# Extracted from test-ncbi_homonyms.R:278

# setup ------------------------------------------------------------------------
library(testthat)
test_env <- simulate_test_env(package = "TaxaTools", path = "..")
attach(test_env, warn.conflicts = FALSE)

# prequel ----------------------------------------------------------------------
.mk_esummary_list <- function(rows) {
  # rows: list of named lists (uid, rank, division, genbankdivision, scientificname)
  out <- lapply(rows, function(r) {
    structure(r, class = c("esummary", "list"))
  })
  if (length(out) == 1L) {
    out[[1L]]
  } else {
    structure(out, class = c("esummary_list", "list"))
  }
}
.mk_lineage_xml <- function(taxid, sci_name, rank, lineage) {
  # lineage: named character vector, name = rank, value = scientific name
  lineage_xml <- paste(sprintf(
    "<Taxon><TaxId>%d</TaxId><ScientificName>%s</ScientificName><Rank>%s</Rank></Taxon>",
    seq_along(lineage) + 900000L, lineage, names(lineage)
  ), collapse = "")
  sprintf(
    paste0(
      "<TaxaSet><Taxon><TaxId>%s</TaxId><ScientificName>%s</ScientificName>",
      "<Rank>%s</Rank><LineageEx>%s</LineageEx></Taxon></TaxaSet>"
    ),
    taxid, sci_name, rank, lineage_xml
  )
}

# test -------------------------------------------------------------------------
testthat::local_mocked_bindings(
    entrez_search = function(db, term, retmax, ...) list(count = "1", ids = "9606"),
    entrez_summary = function(db, id, ...) {
      list(`9606` = list(uid = "9606", scientificname = "Homo sapiens", rank = "species"))
    },
    entrez_fetch = function(db, id, rettype, ...) {
      "<TaxaSet><Taxon><TaxId>9606</TaxId><ScientificName>Homo sapiens</ScientificName><Rank>species</Rank><LineageEx></LineageEx></Taxon></TaxaSet>"
    },
    .package = "rentrez"
  )
res <- suppressMessages(suppressWarnings(
    verify_taxon_names(c("Homo sapiens", "Zzznotarealtaxonxyz"), backbone_id = 4, fallback_backbone_id = NA)
  ))
expect_true(all(res$verified))
expect_identical(res$matched, c(TRUE, FALSE))
