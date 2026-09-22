# .ncbi_taxid_candidates() / resolve_ncbi_taxid() / check_lineage_agreement()
# Fully offline -- rentrez calls mocked via local_mocked_bindings(.package = "rentrez").

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

test_that("resolve_ncbi_taxid: single hit is 'unique' with no discrimination needed", {
  testthat::local_mocked_bindings(
    entrez_search = function(db, term, ...) list(ids = "42", count = "1"),
    entrez_summary = function(db, id, ...) {
      .mk_esummary_list(list(list(
        uid = "42", rank = "species", division = "vertebrates",
        genbankdivision = "Vertebrates", scientificname = "Homo sapiens"
      )))
    },
    .package = "rentrez"
  )
  r <- resolve_ncbi_taxid("Homo sapiens")
  expect_identical(r$status, "unique")
  expect_identical(r$taxid, "42")
  expect_equal(nrow(r$candidates), 1L)
})

test_that("resolve_ncbi_taxid: no hits is 'not_found'", {
  testthat::local_mocked_bindings(
    entrez_search = function(db, term, ...) list(ids = character(0), count = "0"),
    .package = "rentrez"
  )
  r <- resolve_ncbi_taxid("Nonexistentgenusxyz")
  expect_identical(r$status, "not_found")
  expect_true(is.na(r$taxid))
  expect_equal(nrow(r$candidates), 0L)
})

test_that("resolve_ncbi_taxid: rank alone disambiguates (the Vertebrata case)", {
  testthat::local_mocked_bindings(
    entrez_search = function(db, term, ...) list(ids = c("1261581", "7742"), count = "2"),
    entrez_summary = function(db, id, ...) {
      .mk_esummary_list(list(
        list(uid = "1261581", rank = "genus", division = "red algae",
             genbankdivision = "Plants and Fungi", scientificname = "Vertebrata"),
        list(uid = "7742", rank = "clade", division = "vertebrates",
             genbankdivision = "Vertebrates", scientificname = "Vertebrata")
      ))
    },
    .package = "rentrez"
  )
  r <- resolve_ncbi_taxid("Vertebrata", rank = "genus")
  expect_identical(r$status, "resolved_by_rank")
  expect_identical(r$taxid, "1261581")
  expect_equal(nrow(r$candidates), 2L)
})

test_that("resolve_ncbi_taxid: rank alone insufficient when candidates share rank (the Lobophora case)", {
  testthat::local_mocked_bindings(
    entrez_search = function(db, term, ...) list(ids = c("214189", "157000"), count = "2"),
    entrez_summary = function(db, id, ...) {
      .mk_esummary_list(list(
        list(uid = "214189", rank = "genus", division = "moths & butterflies",
             genbankdivision = "Invertebrates", scientificname = "Lobophora"),
        list(uid = "157000", rank = "genus", division = "brown algae",
             genbankdivision = "Plants and Fungi", scientificname = "Lobophora")
      ))
    },
    .package = "rentrez"
  )
  r <- resolve_ncbi_taxid("Lobophora", rank = "genus")
  expect_identical(r$status, "ambiguous")
  expect_true(is.na(r$taxid))
  expect_equal(nrow(r$candidates), 2L)
})

test_that("resolve_ncbi_taxid: lineage containment resolves what rank alone cannot", {
  testthat::local_mocked_bindings(
    entrez_search = function(db, term, ...) list(ids = c("214189", "157000"), count = "2"),
    entrez_summary = function(db, id, ...) {
      .mk_esummary_list(list(
        list(uid = "214189", rank = "genus", division = "moths & butterflies",
             genbankdivision = "Invertebrates", scientificname = "Lobophora"),
        list(uid = "157000", rank = "genus", division = "brown algae",
             genbankdivision = "Plants and Fungi", scientificname = "Lobophora")
      ))
    },
    entrez_fetch = function(db, id, rettype, ...) {
      if (identical(id, "214189")) {
        .mk_lineage_xml("214189", "Lobophora", "genus",
          c(phylum = "Arthropoda", class = "Insecta", family = "Geometridae"))
      } else {
        .mk_lineage_xml("157000", "Lobophora", "genus",
          c(phylum = "Phaeophyta", class = "Phaeophyceae", family = "Dictyotaceae"))
      }
    },
    .package = "rentrez"
  )
  r <- resolve_ncbi_taxid("Lobophora", rank = "genus",
    lineage_terms = c("Dictyotaceae", "Phaeophyceae"))
  expect_identical(r$status, "resolved_by_lineage")
  expect_identical(r$taxid, "157000")
})

test_that("resolve_ncbi_taxid: lineage disambiguation runs over the full set when rank filter zeroes out", {
  # Caller declares rank = "species" but both real candidates are rank "genus" --
  # the rank filter must not exclude everything and give up; it should fall
  # through to lineage disambiguation over the original candidate set.
  testthat::local_mocked_bindings(
    entrez_search = function(db, term, ...) list(ids = c("214189", "157000"), count = "2"),
    entrez_summary = function(db, id, ...) {
      .mk_esummary_list(list(
        list(uid = "214189", rank = "genus", division = "moths & butterflies",
             genbankdivision = "Invertebrates", scientificname = "Lobophora"),
        list(uid = "157000", rank = "genus", division = "brown algae",
             genbankdivision = "Plants and Fungi", scientificname = "Lobophora")
      ))
    },
    entrez_fetch = function(db, id, rettype, ...) {
      if (identical(id, "214189")) {
        .mk_lineage_xml("214189", "Lobophora", "genus", c(family = "Geometridae"))
      } else {
        .mk_lineage_xml("157000", "Lobophora", "genus", c(family = "Dictyotaceae"))
      }
    },
    .package = "rentrez"
  )
  r <- resolve_ncbi_taxid("Lobophora", rank = "species", lineage_terms = "Dictyotaceae")
  expect_identical(r$status, "resolved_by_lineage")
  expect_identical(r$taxid, "157000")
})

test_that("resolve_ncbi_taxid: remains ambiguous when neither discriminator decides", {
  testthat::local_mocked_bindings(
    entrez_search = function(db, term, ...) list(ids = c("214189", "157000"), count = "2"),
    entrez_summary = function(db, id, ...) {
      .mk_esummary_list(list(
        list(uid = "214189", rank = "genus", division = "moths & butterflies",
             genbankdivision = "Invertebrates", scientificname = "Lobophora"),
        list(uid = "157000", rank = "genus", division = "brown algae",
             genbankdivision = "Plants and Fungi", scientificname = "Lobophora")
      ))
    },
    .package = "rentrez"
  )
  # No lineage_terms supplied at all -- can't disambiguate, must be honest.
  r <- resolve_ncbi_taxid("Lobophora", rank = "genus")
  expect_identical(r$status, "ambiguous")
  expect_true(is.na(r$taxid))
})

test_that("resolve_ncbi_taxid validates input", {
  expect_error(resolve_ncbi_taxid(character(0)), "single non-empty")
  expect_error(resolve_ncbi_taxid(c("A", "B")), "single non-empty")
  expect_error(resolve_ncbi_taxid(NA_character_), "single non-empty")
  expect_error(resolve_ncbi_taxid("Foo", rank = c("a", "b")), "single character string")
  expect_error(resolve_ncbi_taxid("Foo", lineage_terms = 1L), "character vector")
})

test_that(".known_ncbi_homonyms is a well-formed registry containing the Vertebrata case", {
  # Not exported (see its own roxygen for why) -- fully internal to the
  # package, so referenced here by its dotted name only.
  expect_s3_class(.known_ncbi_homonyms, "data.frame")
  expect_true(all(c("name", "lineage_a", "lineage_b") %in% names(.known_ncbi_homonyms)))
  expect_true("Vertebrata" %in% .known_ncbi_homonyms$name)
  expect_true(nrow(.known_ncbi_homonyms) >= 10L)
})

test_that("check_lineage_agreement: shared term anywhere in the lineage agrees", {
  expect_identical(
    check_lineage_agreement("Mollusca|Mytilidae", "Mollusca|Modiolidae"),
    "agrees"
  )
})

test_that("check_lineage_agreement: no shared term disagrees (a likely homonym)", {
  expect_identical(
    check_lineage_agreement("Rhodophyta|Rhodomelaceae", "Chordata|Mammalia"),
    "disagrees"
  )
})

test_that("check_lineage_agreement: missing data on either side is 'unknown', not a guess", {
  expect_identical(check_lineage_agreement("", "Mollusca"), "unknown")
  expect_identical(check_lineage_agreement("Mollusca", NA_character_), "unknown")
  expect_identical(check_lineage_agreement(NA_character_, NA_character_), "unknown")
})

test_that("check_lineage_agreement is vectorised and case-insensitive", {
  out <- check_lineage_agreement(
    declared = c("Rhodophyta|Rhodomelaceae", "MOLLUSCA|Mytilidae", ""),
    returned = c("Chordata|Mammalia", "mollusca|Modiolidae", "Chordata")
  )
  expect_identical(out, c("disagrees", "agrees", "unknown"))
})

test_that("check_lineage_agreement validates input", {
  expect_error(check_lineage_agreement(1L, "a"), "character vectors")
  expect_error(check_lineage_agreement(c("a", "b"), "a"), "same length")
})

test_that("check_lineage_agreement() is not defeated by a shared root or kingdom", {
  alga <- "cellular organisms|Eukaryota|Rhodophyta|Florideophyceae|Ceramiales|Rhodomelaceae"
  bat  <- "cellular organisms|Eukaryota|Metazoa|Chordata|Mammalia|Chiroptera|Phyllostomidae"
  worm <- "cellular organisms|Eukaryota|Metazoa|Annelida|Polychaeta"
  fly  <- "cellular organisms|Eukaryota|Metazoa|Arthropoda|Insecta|Diptera|Tachinidae"
  expect_identical(check_lineage_agreement(alga, bat), "disagrees")
  expect_identical(check_lineage_agreement(worm, fly), "disagrees")
  # a benign revision inside a shared phylum still agrees
  expect_identical(
    check_lineage_agreement("Eukaryota|Metazoa|Mollusca|Mytilidae", "Eukaryota|Metazoa|Mollusca|Modiolidae"),
    "agrees"
  )
  # only the root shared, and nothing else on one side: unknown, not agrees
  expect_identical(check_lineage_agreement("Eukaryota", bat), "unknown")
  # the old behaviour is available explicitly
  expect_identical(check_lineage_agreement(alga, bat, ignore = character(0)), "agrees")
  expect_error(check_lineage_agreement(data.frame(a = 1), "x"), "character vectors")
})
