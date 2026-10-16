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
  r <- .lh_run(.lh_ambiguous_names, input_rank = rep("genus", 22L))
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
  r <- .lh_run(.lh_ambiguous_names, input_rank = rep("genus", 22L),
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
  r <- .lh_run("Ulvaria", input_rank = "genus", lineage = "Chordata|Chlorophyta")
  expect_false(r$out$verified)
  expect_true(is.na(r$out$matched_name))
  expect_match(r$warns, "could not be told apart")
  # ...and a single-term context does separate them.
  r2 <- .lh_run("Ulvaria", input_rank = "genus", lineage = "Chlorophyta")
  expect_true(r2$out$verified)
  expect_match(r2$out$classification_path, "Chlorophyta")
})

# ---- 4 ------------------------------------------------------------------------

test_that("decisions still resolve a name that rank and lineage left unverified", {
  .lh_setup()
  dec <- data.frame(name = "Dugesia", taxid = "6160", stringsAsFactors = FALSE)
  r <- .lh_run(c("Argentina", "Dugesia"), input_rank = c("genus", "genus"),
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

test_that("reclassification is not a homonym: a UNIQUE match with a contradicting context is accepted", {
  .lh_setup()
  # Lonelyplant has one NCBI node (a plant). Asked with a Chordata context the
  # backbone's placement differs from the caller's, but no choice between taxa
  # existed, so the match stands and nothing is reported as contradicting.
  bad <- .lh_run("Lonelyplant", lineage = "Chordata")
  expect_true(bad$out$verified)
  expect_false(is.na(bad$out$matched_name))
  expect_false(is.na(bad$out$classification_path))
  expect_match(bad$out$classification_path, "Streptophyta")
  expect_false(grepl("contradicts", bad$msgs))
  expect_length(bad$warns, 0L)

  ok <- .lh_run("Lonelyplant", lineage = "Streptophyta")
  expect_true(ok$out$verified)
  expect_false(is.na(ok$out$matched_name))
  expect_false(grepl("contradicts", ok$msgs))

  none <- .lh_run("Lonelyplant", lineage = NA_character_)
  expect_true(none$out$verified)
  expect_false(is.na(none$out$matched_name))
})

# ---- 5b: gate eligibility on the NCBI path -----------------------------------
# A second small fixture with raw lineages: the Nuda-like pair (a genus node in
# Preaxostyla vs a class node in Ctenophora) and a unique protist whose path
# carries no phylum rank.

.lh2_cands <- list(
  list(name = "Nuda", taxid = "810001", rank = "genus", division = "excavates",
       nodes = list(c("cellular organisms", "no rank"), c("Eukaryota", "superkingdom"),
                    c("Metamonada", "clade"), c("Preaxostyla", "class"))),
  list(name = "Nuda", taxid = "810002", rank = "class", division = "comb jellies",
       nodes = list(c("cellular organisms", "no rank"), c("Eukaryota", "superkingdom"),
                    c("Metazoa", "kingdom"))),  # the class node IS Ctenophora; its own name is not in its lineage
  list(name = "Chlamydaster", taxid = "810003", rank = "genus", division = "protists",
       nodes = list(c("cellular organisms", "no rank"), c("Eukaryota", "superkingdom"),
                    c("Haptista", "clade"), c("Centroplasthelida", "class"),
                    c("Pterocystida", "order"), c("Pterocystidae", "family")))
)

.lh2_taxon_xml <- function(cd) {
  lin <- paste(vapply(seq_along(cd$nodes), function(j) sprintf(
    "<Taxon><TaxId>%d</TaxId><ScientificName>%s</ScientificName><Rank>%s</Rank></Taxon>",
    5000L + j, cd$nodes[[j]][1], cd$nodes[[j]][2]), character(1L)), collapse = "")
  sprintf("<Taxon><TaxId>%s</TaxId><ScientificName>%s</ScientificName><Rank>%s</Rank><LineageEx>%s</LineageEx></Taxon>",
          cd$taxid, cd$name, cd$rank, lin)
}

.lh2_setup <- function(env = parent.frame()) {
  tid <- vapply(.lh2_cands, `[[`, "", "taxid")
  nms <- vapply(.lh2_cands, `[[`, "", "name")
  testthat::local_mocked_bindings(
    entrez_search = function(db, term, ...) {
      ids <- tid[vapply(nms, function(n) grepl(sprintf('"%s"[Scientific Name]', n), term, fixed = TRUE), logical(1L))]
      list(count = as.character(length(ids)), ids = ids)
    },
    entrez_summary = function(db, id, ...) {
      out <- lapply(match(as.character(id), tid), function(i) .mk_lh_summary(
        tid[i], .lh2_cands[[i]]$rank, .lh2_cands[[i]]$division, nms[i]))
      if (length(out) == 1L) out[[1L]] else out
    },
    entrez_fetch = function(db, id, rettype, ...) {
      sprintf("<TaxaSet>%s</TaxaSet>", paste(vapply(
        .lh2_cands[match(as.character(id), tid)], .lh2_taxon_xml, character(1L)), collapse = ""))
    },
    .package = "rentrez", .env = env
  )
  testthat::local_mocked_bindings(
    .is_interactive_session = function() FALSE, .package = "TaxaTools", .env = env
  )
  invisible(NULL)
}

test_that("the seven protists: a unique node with no phylum rank is accepted against a differing context", {
  .lh2_setup()
  r <- .lh_run("Chlamydaster", input_rank = "genus", lineage = "Heliozoa")
  expect_true(r$out$verified)
  expect_false(is.na(r$out$matched_name))
  expect_match(r$out$classification_path, "Pterocystidae")
  expect_false(grepl("contradicts", r$msgs))
})

test_that("a multi-candidate name settled by RANK whose node contradicts the context is refused", {
  .lh2_setup()
  r <- .lh_run("Nuda", input_rank = "genus", lineage = "Ctenophora")
  expect_match(r$msgs, "resolved by the caller's rank")
  expect_false(r$out$verified)
  expect_true(is.na(r$out$matched_name))
  expect_match(r$msgs, "contradicts")
  expect_match(r$msgs, "deterministic")
  # ...while a context the rank-chosen genus agrees with is accepted.
  ok <- .lh_run("Nuda", input_rank = "genus", lineage = "Preaxostyla")
  expect_true(ok$out$verified)
  expect_match(ok$out$classification_path, "Preaxostyla")
})

test_that("a multi-candidate name settled by DECISIONS whose node contradicts the context is refused", {
  .lh2_setup()
  dec <- data.frame(name = "Nuda", taxid = "810001", stringsAsFactors = FALSE)
  r <- .lh_run("Nuda", lineage = "Ctenophora", decisions = dec)
  expect_false(r$out$verified)
  expect_true(is.na(r$out$matched_name))
  expect_match(r$msgs, "contradicts")
  expect_match(r$msgs, "deterministic")
})

test_that("a multi-candidate name settled by LINEAGE is accepted", {
  .lh_setup()
  r <- .lh_run("Argentina", input_rank = "genus", lineage = "Chordata")
  expect_true(r$out$verified)
  expect_false(is.na(r$out$matched_name))
  expect_match(r$out$classification_path, "Chordata")
  expect_false(grepl("contradicts", r$msgs))
})

# ---- 5c: gate eligibility on the Global Names path ---------------------------

.lh_gn_item <- function(name, canon, path, ranks) {
  list(name = name, bestResult = list(
    matchedCanonicalSimple = canon, currentCanonicalSimple = canon, isSynonym = FALSE,
    classificationPath = path, classificationRanks = ranks, score = 1))
}

.lh_gn_setup <- function(items, env = parent.frame()) {
  testthat::local_mocked_bindings(
    POST = function(url, body, ...) structure(list(names = unlist(body$nameStrings)), class = "response"),
    status_code = function(resp) 200L,
    content = function(resp, ...) list(names = unname(items[resp$names])),
    .package = "httr", .env = env
  )
}

test_that("Global Names: gated only when the match rank differs from input_rank, or no rank was given", {
  items <- list(
    Appendicularia = .lh_gn_item("Appendicularia", "Appendicularia",
      "Plantae|Tracheophyta|Magnoliopsida|Myrtales|Melastomataceae|Appendicularia",
      "kingdom|phylum|class|order|family|genus"),
    Filoreta = .lh_gn_item("Filoreta", "Filoreta",
      "Chromista|Cercozoa|Filoretidae|Filoreta", "kingdom|phylum|family|genus")
  )
  .lh_gn_setup(items)
  vgn <- function(nm, ...) {
    msgs <- character(0L)
    out <- withCallingHandlers(
      suppressWarnings(verify_taxon_names(nm, backbone_id = 11L, ...)),
      message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") })
    list(out = out, msgs = paste(msgs, collapse = "\n"))
  }
  # (a) asked a class, answered a disjoint genus: the other taxon -> refused
  a <- vgn("Appendicularia", input_rank = "class", lineage = "Chordata")
  expect_false(a$out$verified)
  expect_true(is.na(a$out$matched_name))
  expect_match(a$msgs, "contradicts")
  # (b) same rank, lineage differs: reclassification -> accepted
  b <- vgn("Filoreta", input_rank = "genus", lineage = "Endomyxa")
  expect_true(b$out$verified)
  expect_equal(b$out$matched_name, "Filoreta")
  expect_match(b$out$classification_path, "Cercozoa")
  expect_false(grepl("contradicts", b$msgs))
  # (c) no rank given: the name test alone decides -> refused
  c3 <- vgn("Filoreta", lineage = "Endomyxa")
  expect_false(c3$out$verified)
  expect_true(is.na(c3$out$matched_name))
  expect_match(c3$msgs, "contradicts")
})

test_that(".apply_lineage_gate: only eligible rows are gated", {
  df <- data.frame(
    user_supplied_name = c("A", "B"), verified = TRUE, matched_name = c("A", "B"),
    matched_rank = "genus", is_synonym = FALSE,
    classification_path = "cellular organisms|Eukaryota|Viridiplantae|Streptophyta|X",
    classification_ranks = "superkingdom|kingdom|phylum|genus",
    score = 1, matched = TRUE, stringsAsFactors = FALSE)
  out <- suppressMessages(TaxaTools:::.apply_lineage_gate(df, c("Chordata", "Chordata"), c(FALSE, TRUE)))
  expect_true(out$verified[1])
  expect_false(out$verified[2])
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

# ---- 10: per-row alignment of the NCBI gate -----------------------------------
# Nuda (lh2 fixture) and Argentina (lh fixture) in one mocked rentrez.

.lh3_setup <- function(env = parent.frame()) {
  fx <- .mk_lineage_homonym_fixture()
  tid2 <- vapply(.lh2_cands, `[[`, "", "taxid")
  nms2 <- vapply(.lh2_cands, `[[`, "", "name")
  is2 <- function(id) as.character(id) %in% tid2
  testthat::local_mocked_bindings(
    entrez_search = function(db, term, ...) {
      ids2 <- tid2[vapply(nms2, function(n) grepl(sprintf('"%s"[Scientific Name]', n), term, fixed = TRUE), logical(1L))]
      r1 <- fx$entrez_search(db, term, ...)
      ids <- c(r1$ids, ids2)
      list(count = as.character(length(ids)), ids = ids)
    },
    entrez_summary = function(db, id, ...) {
      out <- lapply(as.character(id), function(i) {
        if (is2(i)) {
          k <- match(i, tid2)
          .mk_lh_summary(i, .lh2_cands[[k]]$rank, .lh2_cands[[k]]$division, nms2[k])
        } else fx$entrez_summary(db, i, ...)
      })
      if (length(out) == 1L) out[[1L]] else out
    },
    entrez_fetch = function(db, id, rettype, ...) {
      parts <- vapply(as.character(id), function(i) {
        if (is2(i)) .lh2_taxon_xml(.lh2_cands[[match(i, tid2)]])
        else .lh_taxon_xml(match(i, .lh_cands$taxid))
      }, character(1L))
      sprintf("<TaxaSet>%s</TaxaSet>", paste(parts, collapse = ""))
    },
    .package = "rentrez", .env = env
  )
  testthat::local_mocked_bindings(
    .is_interactive_session = function() FALSE, .package = "TaxaTools", .env = env
  )
  invisible(NULL)
}

test_that("NCBI gate is aligned per input row with duplicate, NA and empty names", {
  .lh3_setup()
  nm <- c("Nuda", NA, "Nuda", "", "Argentina", "Nuda")
  r <- .lh_run(nm,
               input_rank = c("genus", NA, "genus", NA, "genus", "genus"),
               lineage = c("Ctenophora", NA, "Ctenophora", NA, "Chordata", "Preaxostyla"))
  o <- r$out
  expect_equal(nrow(o), 6L)
  expect_false(o$verified[1]); expect_true(is.na(o$matched_name[1]))
  expect_false(o$verified[3]); expect_true(is.na(o$matched_name[3]))
  expect_true(o$verified[6])
  expect_match(o$classification_path[6], "Preaxostyla")
  expect_true(o$verified[5])
  expect_match(o$classification_path[5], "Chordata")
  expect_false(o$verified[2])
  expect_false(o$verified[4])
  expect_true(is.na(o$user_supplied_name[2]) || o$user_supplied_name[2] == "")
  expect_true(is.na(o$user_supplied_name[4]) || o$user_supplied_name[4] == "")
  expect_equal(o$user_supplied_name[c(1, 3, 5, 6)], c("Nuda", "Nuda", "Argentina", "Nuda"))
})

test_that("NCBI gate: a unique protist duplicated three times is accepted on every row", {
  .lh2_setup()
  r <- .lh_run(rep("Chlamydaster", 3L), input_rank = rep("genus", 3L),
               lineage = rep("Heliozoa", 3L))
  expect_equal(nrow(r$out), 3L)
  expect_true(all(r$out$verified))
  expect_false(any(is.na(r$out$matched_name)))
  expect_false(grepl("contradicts", r$msgs))
})

# ---- 11: Global Names same-rank match gated on kingdom only -------------------

test_that("Global Names: a same-rank match is gated only on a kingdom difference", {
  ulv <- .lh_gn_item("Ulvaria", "Ulvaria",
    "Plantae|Chlorophyta|Ulvophyceae|Ulvales|Ulvaceae|Ulvaria",
    "kingdom|phylum|class|order|family|genus")
  items <- list(
    Ulvaria = ulv,
    Filoreta = .lh_gn_item("Filoreta", "Filoreta",
      "Chromista|Cercozoa|Filoretidae|Filoreta", "kingdom|phylum|family|genus"),
    Appendicularia = .lh_gn_item("Appendicularia", "Appendicularia",
      "Viridiplantae|Streptophyta|Magnoliopsida|Appendicularia",
      "clade|phylum|class|genus")
  )
  .lh_gn_setup(items)
  vgn <- function(nm, ...) {
    msgs <- character(0L)
    out <- withCallingHandlers(
      suppressWarnings(verify_taxon_names(nm, backbone_id = 11L, ...)),
      message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") })
    list(out = out, msgs = paste(msgs, collapse = "\n"))
  }
  refused <- function(x, info) {
    expect_false(x$out$verified, info = info)
    expect_true(is.na(x$out$matched_name), info = info)
    expect_match(x$msgs, "contradicts", info = info)
  }
  # (a) fish context, algal genus at the asked rank
  refused(vgn("Ulvaria", input_rank = "genus", lineage = "Animalia|Chordata|Perciformes"), "a")
  # (b) Metazoa normalises to Animalia
  refused(vgn("Ulvaria", input_rank = "genus", lineage = "Metazoa|Chordata"), "b")
  # (c) same kingdom: reclassification
  cc <- vgn("Filoreta", input_rank = "genus", lineage = "Chromista|Endomyxa")
  expect_true(cc$out$verified)
  expect_equal(cc$out$matched_name, "Filoreta")
  expect_false(grepl("contradicts", cc$msgs))
  # (d) no kingdom in the context: the rule cannot fire
  d <- vgn("Ulvaria", input_rank = "genus", lineage = "Chordata|Perciformes")
  expect_true(d$out$verified)
  expect_false(grepl("contradicts", d$msgs))
  # (e) path without a kingdom rank but with a known kingdom name
  refused(vgn("Appendicularia", input_rank = "genus", lineage = "Animalia|Chordata"), "e")
  # (f) different rank still uses the plain lineage test
  refused(vgn("Appendicularia", input_rank = "class", lineage = "Chordata"), "f")
})

# ---- 12: kingdom helpers ------------------------------------------------------

test_that(".kingdoms_of_context returns the SET of kingdoms named, normalised, empty when none", {
  f <- TaxaTools:::.kingdoms_of_context
  expect_identical(f("Metazoa|Chordata"), "animalia")
  expect_identical(f("Animalia|Chordata"), "animalia")
  expect_identical(f("chordata|Viridiplantae"), "plantae")
  expect_identical(f("Plantae > x"), character(0))  # only the pipe delimits
  expect_identical(f("Fungi|Ascomycota"), "fungi")
  expect_identical(f("Chordata|Perciformes"), character(0))
  expect_identical(f(NA_character_), character(0))
  # a union context names two kingdoms, in either order, once each
  expect_setequal(f("Metazoa|Chordata|Plantae|Chlorophyta"), c("animalia", "plantae"))
  expect_setequal(f("Plantae|Chlorophyta|Metazoa|Chordata|Animalia"), c("animalia", "plantae"))
})

test_that(".kingdom_of_path prefers the kingdom-rank node and handles NA", {
  f <- TaxaTools:::.kingdom_of_path
  expect_identical(f("Plantae|Chlorophyta|Ulvaria", "kingdom|phylum|genus"), "plantae")
  expect_identical(f("Metazoa|Chordata|X", "kingdom|phylum|genus"), "animalia")
  # kingdom-rank node wins over a later known name
  expect_identical(f("Chromista|Fungi|X", "kingdom|phylum|genus"), "chromista")
  # no kingdom rank: first known kingdom name among the nodes
  expect_identical(f("Viridiplantae|Streptophyta|Appendicularia", "clade|phylum|genus"), "plantae")
  expect_identical(f("Viridiplantae|Streptophyta|Fungi", NA_character_), "plantae")
  # kingdom-rank node is not a known kingdom name: fall back to other nodes
  expect_identical(f("Foo|Fungi|X", "kingdom|phylum|genus"), "fungi")
  expect_identical(f("A|B|C", "kingdom|phylum|genus"), NA_character_)
  expect_identical(f(NA_character_, "kingdom"), NA_character_)
  expect_identical(f("", "kingdom"), NA_character_)
})
