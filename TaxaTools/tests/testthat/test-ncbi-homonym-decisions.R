# verify_taxon_names(backbone_id = 4)'s decisions workflow -- fully offline.
# ecosystem_docs/REENTRY_PROMPT_homonym_detection.md's follow-up: .verify_via_ncbi()
# used to silently pick whichever candidate its batched summary processed last for
# an ambiguous name. It now reports such a name as an unresolved ambiguity, resolved
# only via a caller-supplied `decisions`, an interactive prompt, or a non-interactive
# stop() -- never a guess.

# ---- .short_ncbi_lineage() ---------------------------------------------------

test_that(".short_ncbi_lineage: picks kingdom/phylum/class when present", {
  out <- TaxaTools:::.short_ncbi_lineage(
    "Eukaryota|Plantae|Rhodophyta|Florideophyceae|Ceramiales|Rhodomelaceae|Vertebrata",
    "superkingdom|kingdom|phylum|class|order|family|genus"
  )
  expect_identical(out, "Plantae > Rhodophyta > Florideophyceae")
})

test_that(".short_ncbi_lineage: falls back to the first 3 ranks when none of k/p/c present", {
  out <- TaxaTools:::.short_ncbi_lineage(
    "cellular organisms|Bacteria|Terrabacteria group|Actinomycetota",
    "no rank|superkingdom|no rank|phylum"
  )
  # phylum IS present here, so it should still pick it out (this fixture has no
  # kingdom/class) -- confirms partial matches work, not just all-or-nothing.
  expect_identical(out, "Actinomycetota")
})

test_that(".short_ncbi_lineage: genuinely empty/no-rank-match path falls back to head(3)", {
  out <- TaxaTools:::.short_ncbi_lineage("A|B|C|D", "no rank|no rank|no rank|no rank")
  expect_identical(out, "A > B > C")
})

# ---- .apply_ncbi_homonym_decisions() -----------------------------------------

test_that(".apply_ncbi_homonym_decisions: an in-memory decisions data frame resolves a covered name", {
  dec <- data.frame(name = "Vertebrata", taxid = "1261581", stringsAsFactors = FALSE)
  out <- TaxaTools:::.apply_ncbi_homonym_decisions(c("Vertebrata", "Lobophora"), decisions = dec)
  expect_identical(unname(out[["Vertebrata"]]), "1261581")
  expect_true(is.na(out[["Lobophora"]]))
  expect_identical(unname(attr(out, "decided")), c(TRUE, FALSE))
})

test_that(".apply_ncbi_homonym_decisions: an explicit skip (taxid = NA) is 'decided'", {
  dec <- data.frame(name = "Vertebrata", taxid = NA_character_, stringsAsFactors = FALSE)
  out <- TaxaTools:::.apply_ncbi_homonym_decisions("Vertebrata", decisions = dec)
  expect_true(is.na(out[["Vertebrata"]]))
  expect_true(unname(attr(out, "decided")))
})

test_that(".apply_ncbi_homonym_decisions: reads from path only when decisions is NULL", {
  path <- tempfile(fileext = ".rds")
  saveRDS(data.frame(name = "Vertebrata", taxid = "1261581", stringsAsFactors = FALSE), path)
  out <- TaxaTools:::.apply_ncbi_homonym_decisions("Vertebrata", path = path)
  expect_identical(unname(out[["Vertebrata"]]), "1261581")

  # decisions (even an empty/irrelevant one) takes precedence over path.
  out2 <- TaxaTools:::.apply_ncbi_homonym_decisions(
    "Vertebrata", path = path,
    decisions = data.frame(name = "Other", taxid = "1", stringsAsFactors = FALSE)
  )
  expect_false(unname(attr(out2, "decided"))[1])
})

test_that(".apply_ncbi_homonym_decisions: everything not-decided when neither path nor decisions given", {
  out <- TaxaTools:::.apply_ncbi_homonym_decisions(c("Vertebrata", "Lobophora"))
  expect_true(all(is.na(out)))
  expect_false(any(attr(out, "decided")))
})

test_that(".apply_ncbi_homonym_decisions: a nonexistent path is treated as no decisions", {
  out <- TaxaTools:::.apply_ncbi_homonym_decisions("Vertebrata", path = tempfile(fileext = ".rds"))
  expect_false(unname(attr(out, "decided")))
})

# ---- .save_ncbi_homonym_decisions() -------------------------------------------

test_that(".save_ncbi_homonym_decisions: writes a fresh file", {
  path <- tempfile(fileext = ".rds")
  new <- data.frame(name = "Vertebrata", taxid = "1261581", stringsAsFactors = FALSE)
  out <- TaxaTools:::.save_ncbi_homonym_decisions(new, path)
  expect_identical(out$name, "Vertebrata")
  saved <- readRDS(path)
  expect_identical(saved$taxid, "1261581")
})

test_that(".save_ncbi_homonym_decisions: a newer decision for the same name replaces the old one", {
  path <- tempfile(fileext = ".rds")
  saveRDS(data.frame(name = "Vertebrata", taxid = "999", stringsAsFactors = FALSE), path)
  new <- data.frame(name = "Vertebrata", taxid = "1261581", stringsAsFactors = FALSE)
  TaxaTools:::.save_ncbi_homonym_decisions(new, path)
  saved <- readRDS(path)
  expect_identical(nrow(saved), 1L)
  expect_identical(saved$taxid, "1261581")
})

test_that(".save_ncbi_homonym_decisions: merges with, rather than overwrites, unrelated names", {
  path <- tempfile(fileext = ".rds")
  saveRDS(data.frame(name = "Lobophora", taxid = "157000", stringsAsFactors = FALSE), path)
  new <- data.frame(name = "Vertebrata", taxid = "1261581", stringsAsFactors = FALSE)
  TaxaTools:::.save_ncbi_homonym_decisions(new, path)
  saved <- readRDS(path)
  expect_setequal(saved$name, c("Lobophora", "Vertebrata"))
})

# ---- .build_ncbi_ambiguous_table() / .format_ncbi_ambiguous_report() ---------

.mk_summary <- function(uid, rank, division, scientificname) {
  structure(
    list(uid = uid, rank = rank, division = division, scientificname = scientificname),
    class = c("esummary", "list")
  )
}

test_that(".build_ncbi_ambiguous_table: one row per candidate, rank/division from ESummary, lineage fetched", {
  ambiguous_summaries <- list(
    Vertebrata = list(
      .mk_summary("1261581", "genus", "red algae", "Vertebrata"),
      .mk_summary("7742", "clade", "vertebrates", "Vertebrata")
    )
  )
  testthat::local_mocked_bindings(
    entrez_fetch = function(db, id, rettype, ...) {
      parts <- vapply(seq_along(id), function(i) {
        sprintf(
          paste0(
            "<Taxon><TaxId>%s</TaxId><ScientificName>Vertebrata</ScientificName>",
            "<Rank>%s</Rank><LineageEx><Taxon><TaxId>1</TaxId>",
            "<ScientificName>%s</ScientificName><Rank>kingdom</Rank></Taxon>",
            "</LineageEx></Taxon>"
          ),
          id[i], if (id[i] == "1261581") "genus" else "clade",
          if (id[i] == "1261581") "Plantae" else "Metazoa"
        )
      }, character(1L))
      sprintf("<TaxaSet>%s</TaxaSet>", paste(parts, collapse = ""))
    },
    .package = "rentrez"
  )
  out <- TaxaTools:::.build_ncbi_ambiguous_table(ambiguous_summaries, delay = 0)
  expect_identical(nrow(out), 2L)
  expect_setequal(out$candidate_taxid, c("1261581", "7742"))
  expect_setequal(out$candidate_lineage, c("Plantae", "Metazoa"))
})

test_that(".format_ncbi_ambiguous_report: contains a pasteable decisions skeleton naming every candidate", {
  ambiguous_df <- data.frame(
    name = c("Vertebrata", "Vertebrata"),
    candidate_taxid = c("1261581", "7742"),
    candidate_rank = c("genus", "clade"),
    candidate_division = c("red algae", "vertebrates"),
    candidate_lineage = c("Plantae > Rhodophyta", "Metazoa > Chordata"),
    stringsAsFactors = FALSE
  )
  out <- TaxaTools:::.format_ncbi_ambiguous_report(ambiguous_df)
  expect_true(grepl("decisions <- data.frame", out, fixed = TRUE))
  expect_true(grepl("1261581", out, fixed = TRUE))
  expect_true(grepl("7742", out, fixed = TRUE))
  expect_true(grepl("NA_integer_", out, fixed = TRUE))
  expect_true(grepl("Vertebrata", out, fixed = TRUE))
})

# ---- .prompt_ncbi_homonym_decisions() (direct, via mocked readline) ----------

test_that(".prompt_ncbi_homonym_decisions: one numbered choice per name, no per-name dialogue", {
  ambiguous_df <- data.frame(
    name = c("Vertebrata", "Vertebrata", "Lobophora", "Lobophora"),
    candidate_taxid = c("1261581", "7742", "214189", "157000"),
    candidate_rank = c("genus", "clade", "genus", "genus"),
    candidate_division = c("red algae", "vertebrates", "moths & butterflies", "brown algae"),
    candidate_lineage = c("Plantae", "Metazoa", "Metazoa", "Plantae"),
    stringsAsFactors = FALSE
  )
  answers <- c("1", "skip") # Vertebrata -> candidate 1; Lobophora -> skip
  i <- 0L
  testthat::local_mocked_bindings(
    readline = function(prompt = "") {
      i <<- i + 1L
      answers[i]
    },
    .package = "base"
  )
  out <- suppressMessages(TaxaTools:::.prompt_ncbi_homonym_decisions(ambiguous_df))
  expect_identical(out$name, c("Vertebrata", "Lobophora"))
  expect_identical(out$taxid[out$name == "Vertebrata"], "1261581")
  expect_true(is.na(out$taxid[out$name == "Lobophora"]))
  expect_identical(i, 2L) # exactly one readline() call per name -- one batch, no re-asking
})

test_that(".prompt_ncbi_homonym_decisions: an invalid choice re-prompts instead of erroring", {
  ambiguous_df <- data.frame(
    name = "Vertebrata", candidate_taxid = c("1261581", "7742"),
    candidate_rank = c("genus", "clade"), candidate_division = c("red algae", "vertebrates"),
    candidate_lineage = c("Plantae", "Metazoa"), stringsAsFactors = FALSE
  )
  answers <- c("bogus", "99", "2")
  i <- 0L
  testthat::local_mocked_bindings(
    readline = function(prompt = "") {
      i <<- i + 1L
      answers[i]
    },
    .package = "base"
  )
  out <- suppressMessages(TaxaTools:::.prompt_ncbi_homonym_decisions(ambiguous_df))
  expect_identical(out$taxid, "7742")
  expect_identical(i, 3L)
})

# ---- Full .verify_via_ncbi() integration (mocked rentrez end to end) ---------

.mk_ambiguous_search_fixture <- function() {
  # "Vertebrata"[Scientific Name] returns 2 real NCBI nodes; every other
  # name in these tests resolves uniquely.
  list(
    entrez_search = function(db, term, ...) {
      if (grepl("Vertebrata", term, fixed = TRUE)) {
        list(count = "2", ids = c("1261581", "7742"))
      } else {
        list(count = "0", ids = character(0))
      }
    },
    entrez_summary = function(db, id, ...) {
      if (identical(db, "taxonomy") && setequal(id, c("1261581", "7742"))) {
        list(
          .mk_summary("1261581", "genus", "red algae", "Vertebrata"),
          .mk_summary("7742", "clade", "vertebrates", "Vertebrata")
        )
      } else {
        list()
      }
    },
    entrez_fetch = function(db, id, rettype, ...) {
      parts <- vapply(id, function(x) {
        sprintf(
          paste0(
            "<Taxon><TaxId>%s</TaxId><ScientificName>Vertebrata</ScientificName>",
            "<Rank>%s</Rank><LineageEx><Taxon><TaxId>1</TaxId>",
            "<ScientificName>%s</ScientificName><Rank>kingdom</Rank></Taxon>",
            "</LineageEx></Taxon>"
          ),
          x, if (x == "1261581") "genus" else "clade",
          if (x == "1261581") "Plantae" else "Metazoa"
        )
      }, character(1L))
      sprintf("<TaxaSet>%s</TaxaSet>", paste(parts, collapse = ""))
    }
  )
}

test_that("verify_taxon_names: non-interactive + no decisions stops with the candidate table", {
  fx <- .mk_ambiguous_search_fixture()
  testthat::local_mocked_bindings(
    entrez_search = fx$entrez_search, entrez_summary = fx$entrez_summary,
    entrez_fetch = fx$entrez_fetch, .package = "rentrez"
  )
  testthat::local_mocked_bindings(.is_interactive_session = function() FALSE, .package = "TaxaTools")
  expect_error(
    suppressMessages(verify_taxon_names("Vertebrata", backbone_id = 4L)),
    "more than one.*NCBI taxonomy node"
  )
})

test_that("verify_taxon_names: non-interactive + a covering data.frame decisions resolves cleanly", {
  fx <- .mk_ambiguous_search_fixture()
  testthat::local_mocked_bindings(
    entrez_search = fx$entrez_search, entrez_summary = fx$entrez_summary,
    entrez_fetch = fx$entrez_fetch, .package = "rentrez"
  )
  testthat::local_mocked_bindings(.is_interactive_session = function() FALSE, .package = "TaxaTools")
  dec <- data.frame(name = "Vertebrata", taxid = "1261581", stringsAsFactors = FALSE)
  out <- suppressMessages(verify_taxon_names("Vertebrata", backbone_id = 4L, decisions = dec))
  expect_identical(out$verified, TRUE)
  # matched_name comes from the lineage XML fixture's own ScientificName field.
  expect_identical(out$matched_name, "Vertebrata")
})

test_that("verify_taxon_names: an explicit skip decision resolves to NA and does not fall through to [All Names]", {
  fx <- .mk_ambiguous_search_fixture()
  all_names_called <- FALSE
  testthat::local_mocked_bindings(
    entrez_search = function(db, term, ...) {
      if (grepl("All Names", term, fixed = TRUE)) all_names_called <<- TRUE
      fx$entrez_search(db, term)
    },
    entrez_summary = fx$entrez_summary, entrez_fetch = fx$entrez_fetch,
    .package = "rentrez"
  )
  testthat::local_mocked_bindings(.is_interactive_session = function() FALSE, .package = "TaxaTools")
  dec <- data.frame(name = "Vertebrata", taxid = NA_character_, stringsAsFactors = FALSE)
  out <- suppressMessages(verify_taxon_names("Vertebrata", backbone_id = 4L, decisions = dec))
  expect_true(is.na(out$matched_name))
  expect_true(out$verified) # a skip is a real, deliberate answer, not an API failure
  expect_false(all_names_called)
})

test_that("verify_taxon_names: interactive session with a decisions path saves the new choice there", {
  fx <- .mk_ambiguous_search_fixture()
  testthat::local_mocked_bindings(
    entrez_search = fx$entrez_search, entrez_summary = fx$entrez_summary,
    entrez_fetch = fx$entrez_fetch, .package = "rentrez"
  )
  testthat::local_mocked_bindings(
    .is_interactive_session = function() TRUE,
    .prompt_ncbi_homonym_decisions = function(ambiguous_df) {
      data.frame(name = "Vertebrata", taxid = "1261581", stringsAsFactors = FALSE)
    },
    .package = "TaxaTools"
  )
  path <- tempfile(fileext = ".rds")
  out <- suppressMessages(verify_taxon_names("Vertebrata", backbone_id = 4L, decisions = path))
  expect_identical(out$matched_name, "Vertebrata")
  saved <- readRDS(path)
  expect_identical(saved$taxid, "1261581")
})

test_that("verify_taxon_names: interactive session with no path prints a pasteable skeleton, writes no file", {
  fx <- .mk_ambiguous_search_fixture()
  testthat::local_mocked_bindings(
    entrez_search = fx$entrez_search, entrez_summary = fx$entrez_summary,
    entrez_fetch = fx$entrez_fetch, .package = "rentrez"
  )
  testthat::local_mocked_bindings(
    .is_interactive_session = function() TRUE,
    .prompt_ncbi_homonym_decisions = function(ambiguous_df) {
      data.frame(name = "Vertebrata", taxid = "1261581", stringsAsFactors = FALSE)
    },
    .package = "TaxaTools"
  )
  expect_message(
    out <- verify_taxon_names("Vertebrata", backbone_id = 4L),
    "decisions <- data.frame"
  )
  expect_identical(out$matched_name, "Vertebrata")
})

test_that("verify_taxon_names: warns that `decisions` is unused for a non-NCBI backbone", {
  testthat::local_mocked_bindings(
    entrez_search = function(...) list(count = "0", ids = character(0)),
    .package = "rentrez"
  )
  dec <- data.frame(name = "Vertebrata", taxid = "1", stringsAsFactors = FALSE)
  expect_warning(
    suppressMessages(verify_taxon_names("Homo sapiens", backbone_id = 11L, decisions = dec)),
    "unused"
  )
})

test_that("verify_taxon_names: an unambiguous name is unaffected by the decisions machinery", {
  testthat::local_mocked_bindings(
    entrez_search = function(db, term, ...) list(count = "1", ids = "9606"),
    entrez_summary = function(db, id, ...) {
      list(.mk_summary("9606", "species", "primates", "Homo sapiens"))
    },
    entrez_fetch = function(db, id, rettype, ...) {
      "<TaxaSet><Taxon><TaxId>9606</TaxId><ScientificName>Homo sapiens</ScientificName><Rank>species</Rank><LineageEx></LineageEx></Taxon></TaxaSet>"
    },
    .package = "rentrez"
  )
  out <- suppressMessages(verify_taxon_names("Homo sapiens", backbone_id = 4L))
  expect_identical(out$matched_name, "Homo sapiens")
  expect_true(out$verified)
})
