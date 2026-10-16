# verify_taxon_names(lineage =) on the 22 real CalIntertidal NCBI homonyms
# (ci_r5 ambiguity report, 2026-10-16) -- fully offline; rentrez is mocked the
# way .mk_ambiguous_search_fixture() in test-ncbi-homonym-decisions.R does.

.mk_lh_summary <- function(uid, rank, division, scientificname) {
  structure(
    list(uid = uid, rank = rank, division = division, scientificname = scientificname),
    class = c("esummary", "list")
  )
}

# kingdom / phylum / class sets, as printed in the report's short lineage
.lh_lin <- list(
  fish  = c("Metazoa", "Chordata", "Actinopteri"),
  eud   = c("Viridiplantae", "Streptophyta", "Magnoliopsida"),
  fung  = c("Fungi", "Ascomycota", "Pezizomycetes"),
  flat  = c("Metazoa", "Platyhelminthes", NA),
  insec = c("Metazoa", "Arthropoda", "Insecta"),
  moss  = c("Viridiplantae", "Streptophyta", "Bryopsida"),
  alga  = c("Viridiplantae", "Chlorophyta", "Ulvophyceae"),
  fern  = c("Viridiplantae", "Streptophyta", "Polypodiopsida")
)

# name, taxid, rank, division, lineage key  (candidate order as reported)
.lh_cands <- do.call(rbind, lapply(list(
  c("Argentina", "3131914", "genus", "eudicots", "eud"),
  c("Argentina", "260511", "genus", "ray-finned fishes", "fish"),
  c("Callionymus", "1147766", "subgenus", "ray-finned fishes", "fish"),
  c("Callionymus", "34784", "genus", "ray-finned fishes", "fish"),
  c("Etheostoma", "909693", "subgenus", "ray-finned fishes", "fish"),
  c("Etheostoma", "54318", "genus", "ray-finned fishes", "fish"),
  c("Apogon", "638272", "subgenus", "ray-finned fishes", "fish"),
  c("Apogon", "83882", "genus", "ray-finned fishes", "fish"),
  c("Ariopsis", "243723", "genus", "ray-finned fishes", "fish"),
  c("Ariopsis", "15023", "genus", "monocots", "eud"),
  c("Decodon", "210583", "genus", "ray-finned fishes", "fish"),
  c("Decodon", "162017", "genus", "eudicots", "eud"),
  c("Coris", "126328", "genus", "ray-finned fishes", "fish"),
  c("Coris", "59971", "genus", "eudicots", "eud"),
  c("Dugesia", "121909", "genus", "eudicots", "eud"),
  c("Dugesia", "6160", "genus", "flatworms", "flat"),
  c("Calamus", "119695", "genus", "ray-finned fishes", "fish"),
  c("Calamus", "4711", "genus", "monocots", "eud"),
  c("Jordania", "3830037", "genus", "eudicots", "eud"),
  c("Jordania", "274763", "genus", "ray-finned fishes", "fish"),
  c("Idiacanthus", "2049632", "genus", "eudicots", "eud"),
  c("Idiacanthus", "314240", "genus", "ray-finned fishes", "fish"),
  c("Heterotis", "1160553", "genus", "eudicots", "eud"),
  c("Heterotis", "91720", "genus", "ray-finned fishes", "fish"),
  c("Hirundichthys", "984836", "subgenus", "ray-finned fishes", "fish"),
  c("Hirundichthys", "76073", "genus", "ray-finned fishes", "fish"),
  c("Ophidion", "210590", "genus", "ray-finned fishes", "fish"),
  c("Ophidion", "125464", "genus", "monocots", "eud"),
  c("Microstoma", "210570", "genus", "ray-finned fishes", "fish"),
  c("Microstoma", "47221", "genus", "ascomycete fungi", "fung"),
  c("Liparis", "183716", "genus", "ray-finned fishes", "fish"),
  c("Liparis", "78793", "genus", "monocots", "eud"),
  c("Schindleria", "1229173", "genus", "eudicots", "eud"),
  c("Schindleria", "166781", "genus", "ray-finned fishes", "fish"),
  c("Ranzania", "210586", "genus", "ray-finned fishes", "fish"),
  c("Ranzania", "63352", "genus", "flowering plants", "eud"),
  c("Trichodon", "209540", "genus", "ray-finned fishes", "fish"),
  c("Trichodon", "98467", "genus", "mosses", "moss"),
  c("Trigonostomum", "465342", "genus", "beetles", "insec"),
  c("Trigonostomum", "162284", "genus", "flatworms", "flat"),
  c("Ulvaria", "262900", "genus", "ray-finned fishes", "fish"),
  c("Ulvaria", "205401", "genus", "green algae", "alga"),
  c("Woodsia", "210574", "genus", "ray-finned fishes", "fish"),
  c("Woodsia", "29610", "genus", "ferns", "fern"),
  # A unique (unambiguous) plant, for the agreement-gate tests
  c("Lonelyplant", "999001", "genus", "eudicots", "eud")
), function(x) data.frame(name = x[1], taxid = x[2], rank = x[3], division = x[4],
                          lin = x[5], stringsAsFactors = FALSE)))

.lh_ambiguous_names <- setdiff(unique(.lh_cands$name), "Lonelyplant")

# Nodes (name, rank) of a candidate: root, superkingdom, kingdom, phylum, class, own
.lh_nodes <- function(i) {
  k <- .lh_lin[[.lh_cands$lin[i]]]
  nodes <- list(c("cellular organisms", "no rank"), c("Eukaryota", "superkingdom"),
                c(k[1], "kingdom"), c(k[2], "phylum"))
  if (!is.na(k[3])) nodes <- c(nodes, list(c(k[3], "class")))
  nodes
}

.lh_taxon_xml <- function(i) {
  nodes <- .lh_nodes(i)
  lin <- paste(vapply(nodes, function(n) sprintf(
    "<Taxon><TaxId>%d</TaxId><ScientificName>%s</ScientificName><Rank>%s</Rank></Taxon>",
    1000L + match(n[1], unique(unlist(lapply(.lh_nodes(i), `[`, 1)))), n[1], n[2]), character(1L)),
    collapse = "")
  sprintf("<Taxon><TaxId>%s</TaxId><ScientificName>%s</ScientificName><Rank>%s</Rank><LineageEx>%s</LineageEx></Taxon>",
          .lh_cands$taxid[i], .lh_cands$name[i], .lh_cands$rank[i], lin)
}

.mk_lineage_homonym_fixture <- function() {
  list(
    entrez_search = function(db, term, ...) {
      hit <- vapply(unique(.lh_cands$name), function(nm)
        grepl(sprintf('"%s"[Scientific Name]', nm), term, fixed = TRUE), logical(1L))
      ids <- .lh_cands$taxid[.lh_cands$name %in% unique(.lh_cands$name)[hit]]
      list(count = as.character(length(ids)), ids = ids)
    },
    entrez_summary = function(db, id, ...) {
      rows <- match(as.character(id), .lh_cands$taxid)
      out <- lapply(rows, function(i) .mk_lh_summary(
        .lh_cands$taxid[i], .lh_cands$rank[i], .lh_cands$division[i], .lh_cands$name[i]))
      if (length(out) == 1L) out[[1L]] else out
    },
    entrez_fetch = function(db, id, rettype, ...) {
      rows <- match(as.character(id), .lh_cands$taxid)
      sprintf("<TaxaSet>%s</TaxaSet>",
              paste(vapply(rows, .lh_taxon_xml, character(1L)), collapse = ""))
    }
  )
}

.lh_setup <- function(env = parent.frame()) {
  fx <- .mk_lineage_homonym_fixture()
  testthat::local_mocked_bindings(
    entrez_search = fx$entrez_search, entrez_summary = fx$entrez_summary,
    entrez_fetch = fx$entrez_fetch, .package = "rentrez", .env = env
  )
  testthat::local_mocked_bindings(
    .is_interactive_session = function() FALSE, .package = "TaxaTools", .env = env
  )
  invisible(fx)
}

# Run verify_taxon_names, capturing messages and warnings separately.
.lh_run <- function(nm, ...) {
  msgs <- character(0L)
  warns <- character(0L)
  out <- withCallingHandlers(
    verify_taxon_names(nm, backbone_id = 4L, ...),
    message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") },
    warning = function(w) { warns <<- c(warns, conditionMessage(w)); invokeRestart("muffleWarning") }
  )
  list(out = out, msgs = paste(msgs, collapse = "\n"), warns = warns)
}

.lh_row <- function(out, nm) out[out$user_supplied_name == nm, , drop = FALSE]

test_that("fixture covers the 22 reported homonyms with two candidates each", {
  expect_length(.lh_ambiguous_names, 22L)
  expect_true(all(table(.lh_cands$name[.lh_cands$name != "Lonelyplant"]) == 2L))
})

# ---- 1 ------------------------------------------------------------------------

test_that("no ranks, no lineage: all homonyms unverified with ONE warning", {
  .lh_setup()
  r <- .lh_run(.lh_ambiguous_names)
  expect_length(r$warns, 1L)
  expect_match(r$warns, "could not be told apart by rank")
  expect_true(all(vapply(.lh_ambiguous_names, grepl, logical(1L), x = r$warns, fixed = TRUE)))
  expect_false(any(r$out$verified))
  expect_true(all(is.na(r$out$matched_name)))
  expect_equal(nrow(r$out), 22L)
})

# ---- 2 ------------------------------------------------------------------------

test_that("ranks = 'genus' resolves exactly the genus-vs-subgenus names", {
  .lh_setup()
  r <- .lh_run(.lh_ambiguous_names, ranks = rep("genus", 22L))
  by_rank <- c("Apogon", "Callionymus", "Etheostoma", "Hirundichthys")
  expect_match(r$msgs, "resolved by the caller's rank")
  expect_true(all(vapply(by_rank, grepl, logical(1L), x = r$msgs, fixed = TRUE)))
  for (nm in by_rank) {
    row <- .lh_row(r$out, nm)
    expect_true(row$verified, info = nm)
    expect_false(is.na(row$matched_name), info = nm)
    expect_equal(row$matched_rank, "genus", info = nm)
    expect_match(row$classification_path, "Chordata", info = nm)
  }
  rest <- setdiff(.lh_ambiguous_names, by_rank)
  expect_false(any(r$out$verified[r$out$user_supplied_name %in% rest]))
  expect_true(all(is.na(r$out$matched_name[r$out$user_supplied_name %in% rest])))
  expect_match(r$warns, "could not be told apart by rank")
})

# ---- 3 ------------------------------------------------------------------------

test_that("ranks = 'genus' + lineage = 'Chordata': every fish homonym resolves to its fish", {
  .lh_setup()
  r <- .lh_run(.lh_ambiguous_names, ranks = rep("genus", 22L),
               lineage = rep("Chordata", 22L))
  fish <- c("Argentina", "Ariopsis", "Calamus", "Coris", "Heterotis", "Jordania",
            "Liparis", "Ophidion", "Schindleria", "Trichodon", "Woodsia", "Ranzania",
            "Microstoma", "Idiacanthus", "Decodon", "Hirundichthys",
            "Apogon", "Callionymus", "Etheostoma", "Ulvaria")
  fish <- setdiff(fish, "Ulvaria") # Ulvaria is tested with the Chlorophyta context below
  for (nm in fish) {
    row <- .lh_row(r$out, nm)
    expect_true(row$verified, info = nm)
    expect_match(row$classification_path, "Chordata", info = nm)
    expect_false(grepl("Viridiplantae|Streptophyta|Fungi", row$classification_path), info = nm)
  }
  expect_match(r$msgs, "resolved by the caller's lineage")
  # The ones rank cannot separate are named in the lineage message.
  for (nm in c("Argentina", "Ariopsis", "Woodsia")) {
    expect_match(r$msgs, nm, fixed = TRUE)
  }
  # No Chordata candidate at all: stay unverified. (Ulvaria's fish is Chordata,
  # so with 'Chordata' alone it resolves; it is exercised separately below.)
  for (nm in c("Dugesia", "Trigonostomum")) {
    row <- .lh_row(r$out, nm)
    expect_false(row$verified, info = nm)
    expect_true(is.na(row$matched_name), info = nm)
  }
  expect_match(r$warns, "Dugesia", fixed = TRUE)
  expect_match(r$warns, "Trigonostomum", fixed = TRUE)
})

test_that("Ulvaria with lineage 'Chordata|Chlorophyta' stays unverified (both candidates match a term)", {
  .lh_setup()
  r <- .lh_run("Ulvaria", ranks = "genus", lineage = "Chordata|Chlorophyta")
  expect_false(r$out$verified)
  expect_true(is.na(r$out$matched_name))
  expect_match(r$warns, "could not be told apart")
  # ...and a single-term context does separate them.
  r2 <- .lh_run("Ulvaria", ranks = "genus", lineage = "Chlorophyta")
  expect_true(r2$out$verified)
  expect_match(r2$out$classification_path, "Chlorophyta")
})

# ---- 4 ------------------------------------------------------------------------

test_that("decisions still resolve a name that rank and lineage left unverified", {
  .lh_setup()
  dec <- data.frame(name = "Dugesia", taxid = "6160", stringsAsFactors = FALSE)
  r <- .lh_run(c("Argentina", "Dugesia"), ranks = c("genus", "genus"),
               lineage = c("Chordata", NA), decisions = dec)
  expect_true(all(r$out$verified))
  expect_match(.lh_row(r$out, "Dugesia")$classification_path, "Platyhelminthes")
  expect_match(.lh_row(r$out, "Argentina")$classification_path, "Chordata")
  expect_length(r$warns, 0L)
  # A decision that contradicts a supplied lineage is still caught by the gate.
  r2 <- .lh_run("Dugesia", lineage = "Chordata", decisions = dec)
  expect_false(r2$out$verified)
  expect_match(r2$msgs, "contradicts")
})

# ---- 5 ------------------------------------------------------------------------

test_that("the agreement gate turns a contradicting UNIQUE match into an unverified row", {
  .lh_setup()
  bad <- .lh_run("Lonelyplant", lineage = "Chordata")
  expect_false(bad$out$verified)
  expect_true(is.na(bad$out$matched_name))
  expect_match(bad$msgs, "contradicts")

  ok <- .lh_run("Lonelyplant", lineage = "Streptophyta")
  expect_true(ok$out$verified)
  expect_false(is.na(ok$out$matched_name))
  expect_false(grepl("contradicts", ok$msgs))

  none <- .lh_run("Lonelyplant", lineage = NA_character_)
  expect_true(none$out$verified)
  expect_false(is.na(none$out$matched_name))
})

# ---- 6 ------------------------------------------------------------------------

test_that(".apply_lineage_gate: disagree -> unverified row; agree/unknown untouched", {
  df <- data.frame(
    user_supplied_name = c("A", "B", "C"),
    verified = TRUE,
    matched_name = c("A", "B", "C"),
    matched_rank = "genus",
    is_synonym = FALSE,
    classification_path = c(
      "cellular organisms|Eukaryota|Viridiplantae|Streptophyta|A",
      "cellular organisms|Eukaryota|Metazoa|Chordata|B",
      "cellular organisms|Eukaryota|Metazoa|Chordata|C"),
    classification_ranks = "superkingdom|kingdom|phylum|genus",
    score = 1, matched = TRUE, stringsAsFactors = FALSE
  )
  out <- suppressMessages(TaxaTools:::.apply_lineage_gate(df, c("Chordata", "Chordata", "Metazoa")))
  expect_false(out$verified[1])
  expect_true(is.na(out$matched_name[1]))
  expect_true(is.na(out$classification_path[1]))
  expect_true(is.na(out$classification_ranks[1]))
  expect_true(is.na(out$matched_rank[1]))
  expect_false(out$matched[1])
  # agrees
  expect_identical(out[2, ], df[2, ])
  # "Metazoa" is a kingdom (ignored) -> unknown -> untouched
  expect_identical(out[3, ], df[3, ])
  expect_message(TaxaTools:::.apply_lineage_gate(df, c("Chordata", "Chordata", "Metazoa")), "contradicts")
  # NULL lineage and NA context are no-ops
  expect_identical(TaxaTools:::.apply_lineage_gate(df, NULL), df)
  expect_identical(TaxaTools:::.apply_lineage_gate(df, rep(NA_character_, 3L)), df)
})

# ---- 7 ------------------------------------------------------------------------

test_that(".lineage_contains: pipe and ' > ' delimiters, case-insensitive, whole-name", {
  f <- TaxaTools:::.lineage_contains
  expect_identical(f(c("Metazoa|Chordata|Actinopteri", "Metazoa > Chordata > Actinopteri"), "Chordata"),
                   c(TRUE, TRUE))
  expect_identical(f("metazoa|CHORDATA", "chordata"), TRUE)
  expect_identical(f("Metazoa|Chordatax", "Chordata"), FALSE)
  expect_identical(f("Metazoa|Chordata", "Chordatax"), FALSE)
  expect_identical(f("Metazoa > Chordatax", "Chordata"), FALSE)
  expect_identical(f("Viridiplantae|Streptophyta", "Chordata|Streptophyta"), TRUE)
  expect_identical(f(c(NA, "Chordata"), "Chordata"), c(FALSE, TRUE))
  expect_identical(f("Chordata", NA_character_), FALSE)
})

# ---- 8 ------------------------------------------------------------------------

test_that(".verify_cache_key: lineage is part of the key; on backbone 11 too (unlike rank)", {
  k <- TaxaTools:::.verify_cache_key
  a <- k("A", 4L, 11L, "fp", rank = NA_character_, lineage = "Chordata")
  b <- k("A", 4L, 11L, "fp", rank = NA_character_, lineage = NA_character_)
  c2 <- k("A", 4L, 11L, "fp", rank = NA_character_, lineage = "Streptophyta")
  expect_false(identical(a, b))
  expect_false(identical(a, c2))
  expect_false(identical(b, c2))
  # backbone 11 (Global Names): rank is ignored, lineage is not
  expect_identical(k("A", 11L, 4L, "fp", rank = "genus", lineage = NA_character_),
                   k("A", 11L, 4L, "fp", rank = NA_character_, lineage = NA_character_))
  expect_false(identical(k("A", 11L, 4L, "fp", lineage = "Chordata"),
                         k("A", 11L, 4L, "fp", lineage = NA_character_)))
  # backbone 4: rank IS in the key
  expect_false(identical(k("A", 4L, 11L, "fp", rank = "genus"),
                         k("A", 4L, 11L, "fp", rank = NA_character_)))
})

# ---- 9 ------------------------------------------------------------------------

test_that("a lineage of the wrong length errors", {
  .lh_setup()
  expect_error(
    verify_taxon_names(c("Argentina", "Coris"), backbone_id = 4L, lineage = "Chordata"),
    "one lineage context"
  )
  expect_error(
    TaxaTools:::.check_verify_lineage(c("a", "b", "c"), c("x", "y")),
    "one lineage context"
  )
})
