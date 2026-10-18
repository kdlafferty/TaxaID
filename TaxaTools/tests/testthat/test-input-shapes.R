# Input-shape property tests for verify_taxon_names() and fill_higher_ranks().
# Fully offline: rentrez (NCBI, backbone 4) and httr (Global Names, backbone 11)
# are mocked. The slips these guard against are all INPUT-SHAPE bugs: a
# per-unique vector applied per input row, a per-row vector grouped by a
# per-unique key, and a branch indexing `lineage` when it was NULL.

# ---- fixtures ----------------------------------------------------------------

.is_nodes <- function(...) list(...)

# NCBI candidates. Nuda is a homonym pair (genus vs class); Filoreta is unique;
# Gymnophrys is unique with a path that lacks a class.
.is_cands <- list(
  list(name = "Filoreta", taxid = "820001", rank = "genus", division = "protists",
       nodes = list(c("cellular organisms", "no rank"), c("Eukaryota", "superkingdom"),
                    c("Cercozoa", "phylum"), c("Filoretidae", "family"))),
  list(name = "Nuda", taxid = "810001", rank = "genus", division = "excavates",
       nodes = list(c("cellular organisms", "no rank"), c("Eukaryota", "superkingdom"),
                    c("Metamonada", "clade"), c("Preaxostyla", "class"))),
  list(name = "Nuda", taxid = "810002", rank = "class", division = "comb jellies",
       nodes = list(c("cellular organisms", "no rank"), c("Eukaryota", "superkingdom"),
                    c("Metazoa", "kingdom"))),
  list(name = "Gymnophrys", taxid = "830001", rank = "genus", division = "protists",
       nodes = list(c("cellular organisms", "no rank"), c("Eukaryota", "superkingdom"),
                    c("Cercozoa", "phylum")))
)

.is_taxon_xml <- function(cd) {
  lin <- paste(vapply(seq_along(cd$nodes), function(j) sprintf(
    "<Taxon><TaxId>%d</TaxId><ScientificName>%s</ScientificName><Rank>%s</Rank></Taxon>",
    7000L + j, cd$nodes[[j]][1], cd$nodes[[j]][2]), character(1L)), collapse = "")
  sprintf("<Taxon><TaxId>%s</TaxId><ScientificName>%s</ScientificName><Rank>%s</Rank><LineageEx>%s</LineageEx></Taxon>",
          cd$taxid, cd$name, cd$rank, lin)
}

.is_summary <- function(uid, rank, division, scientificname) {
  structure(list(uid = uid, rank = rank, division = division,
                 scientificname = scientificname), class = c("esummary", "list"))
}

.is_ncbi_setup <- function(env = parent.frame()) {
  tid <- vapply(.is_cands, `[[`, "", "taxid")
  nms <- vapply(.is_cands, `[[`, "", "name")
  testthat::local_mocked_bindings(
    entrez_search = function(db, term, ...) {
      ids <- tid[vapply(nms, function(n) grepl(sprintf('"%s"[Scientific Name]', n), term,
                                               fixed = TRUE), logical(1L))]
      list(count = as.character(length(ids)), ids = ids)
    },
    entrez_summary = function(db, id, ...) {
      out <- lapply(match(as.character(id), tid), function(i) .is_summary(
        tid[i], .is_cands[[i]]$rank, .is_cands[[i]]$division, nms[i]))
      if (length(out) == 1L) out[[1L]] else out
    },
    entrez_fetch = function(db, id, rettype, ...) {
      sprintf("<TaxaSet>%s</TaxaSet>", paste(vapply(
        .is_cands[match(as.character(id), tid)], .is_taxon_xml, character(1L)), collapse = ""))
    },
    .package = "rentrez", .env = env
  )
  testthat::local_mocked_bindings(
    .is_interactive_session = function() FALSE, .package = "TaxaTools", .env = env
  )
  invisible(NULL)
}

.is_gn_item <- function(name, canon, path, ranks) {
  list(name = name, bestResult = list(
    matchedCanonicalSimple = canon, currentCanonicalSimple = canon, isSynonym = FALSE,
    classificationPath = path, classificationRanks = ranks, score = 1))
}

.is_gn_setup <- function(items, env = parent.frame()) {
  testthat::local_mocked_bindings(
    POST = function(url, body, ...) structure(list(names = unlist(body$nameStrings)), class = "response"),
    status_code = function(resp) 200L,
    content = function(resp, ...) list(names = unname(items[resp$names])),
    .package = "httr", .env = env
  )
  testthat::local_mocked_bindings(
    .is_interactive_session = function() FALSE, .package = "TaxaTools", .env = env
  )
}

.is_gn_items <- list(
  Filoreta = .is_gn_item("Filoreta", "Filoreta",
    "Chromista|Cercozoa|Filoretidae|Filoreta", "kingdom|phylum|family|genus"),
  Barentsiidae = .is_gn_item("Barentsiidae", "Barentsiidae",
    "Animalia|Entoprocta|Barentsiidae", "kingdom|phylum|family"),
  Nuda = .is_gn_item("Nuda", "Nuda",
    "Chromista|Cercozoa|Nuda", "kingdom|phylum|genus"),
  Gymnophrys = .is_gn_item("Gymnophrys", "Gymnophrys",
    "Chromista|Cercozoa|Monadofilosa|Gymnophrys", "kingdom|phylum|class|genus")
)

.is_quiet <- function(expr) {
  suppressWarnings(suppressMessages(expr))
}

# ---- 1: regression for the HEAD fix -----------------------------------------

test_that("GN path, input_rank given, lineage NULL, same-rank matches: no error", {
  .is_gn_setup(.is_gn_items)
  out <- NULL
  expect_no_error(out <- .is_quiet(verify_taxon_names(
    c("Filoreta", "Barentsiidae"), backbone_id = 11L,
    input_rank = c("genus", "family"))))
  expect_equal(nrow(out), 2L)
  expect_true(all(out$verified))
  expect_equal(out$user_supplied_name, c("Filoreta", "Barentsiidae"))
})

# ---- 2: fill_higher_ranks reaching the GN fallback ---------------------------

test_that("fill_higher_ranks: NCBI path lacks class, GN fallback supplies it (no lineage)", {
  .is_ncbi_setup()
  .is_gn_setup(.is_gn_items)
  out <- NULL
  expect_no_error(out <- .is_quiet(fill_higher_ranks(
    "Gymnophrys cometa", local_sources = list(), fill_ranks = c("phylum", "class"),
    input_rank = "species", record_source = TRUE)))
  expect_equal(nrow(out), 1L)
  expect_equal(out$phylum, "Cercozoa")
  expect_equal(out$class, "Monadofilosa")
  expect_equal(out$class_source, "backbone_11")
})

test_that("fill_higher_ranks: same fill with lineage = 'Cercozoa'", {
  .is_ncbi_setup()
  .is_gn_setup(.is_gn_items)
  out <- NULL
  expect_no_error(out <- .is_quiet(fill_higher_ranks(
    "Gymnophrys cometa", local_sources = list(), fill_ranks = c("phylum", "class"),
    input_rank = "species", lineage = "Cercozoa", record_source = TRUE)))
  expect_equal(nrow(out), 1L)
  expect_equal(out$phylum, "Cercozoa")
  expect_equal(out$class, "Monadofilosa")
  expect_equal(out$class_source, "backbone_11")
})

# ---- 3: property grid --------------------------------------------------------

.is_shapes <- list(
  plain     = c("Filoreta", "Nuda"),
  duplicate = c("Filoreta", "Nuda", "Filoreta"),
  na        = c("Filoreta", NA, "Nuda"),
  empty     = c("Filoreta", "", "Nuda")
)

# A per-argument vector of length n for a given mode.
.is_arg <- function(mode, n, given, na_at = 2L) {
  if (mode == "null") return(NULL)
  v <- rep_len(given, n)
  if (mode == "given_na") v[na_at] <- NA_character_
  v
}

.is_grid <- function() {
  expand.grid(
    rank_mode = c("null", "given", "given_na"),
    lin_mode = c("null", "given", "given_na"),
    shape = names(.is_shapes),
    backbone = c(4L, 11L),
    stringsAsFactors = FALSE
  )
}

.is_label <- function(g) sprintf("input_rank=%s lineage=%s names=%s backbone=%d",
                                 g$rank_mode, g$lin_mode, g$shape, g$backbone)

.is_setup_backbone <- function(bb, env = parent.frame()) {
  if (bb == 4L) .is_ncbi_setup(env) else .is_gn_setup(.is_gn_items, env)
}

.is_same_row <- function(df, i, j) {
  isTRUE(all.equal(as.list(df[i, , drop = FALSE]), as.list(df[j, , drop = FALSE]),
                   check.attributes = FALSE))
}

test_that("verify_taxon_names: input_rank x lineage x name shape x backbone grid", {
  grid <- .is_grid()
  for (k in seq_len(nrow(grid))) {
    g <- grid[k, ]
    lab <- .is_label(g)
    nm <- .is_shapes[[g$shape]]
    n <- length(nm)
    .is_setup_backbone(g$backbone)
    rk <- .is_arg(g$rank_mode, n, "genus")
    ln <- .is_arg(g$lin_mode, n, c("Cercozoa", "Metazoa|Chordata|Plantae|Chlorophyta"))
    out <- NULL
    expect_no_error(
      out <- .is_quiet(verify_taxon_names(nm, backbone_id = g$backbone,
                                          input_rank = rk, lineage = ln)),
      message = lab)
    if (is.null(out)) next
    expect_equal(nrow(out), n, info = lab)
    ok <- !is.na(nm)
    expect_equal(out$user_supplied_name[ok], trimws(nm[ok]), info = lab)
    blank <- is.na(nm) | !nzchar(trimws(nm))
    expect_false(any(out$verified[blank]), info = lab)
    if (any(blank)) {
      expect_true(all(is.na(out$matched_name[blank])), info = lab)
    }
    dup <- which(duplicated(nm) & !blank)
    for (j in dup) {
      first <- which(nm == nm[j])[1L]
      expect_true(.is_same_row(out, first, j),
                  info = paste(lab, "duplicate row", j, "differs from row", first))
    }
  }
})

test_that("fill_higher_ranks: input_rank x lineage x name shape x backbone grid", {
  grid <- .is_grid()
  for (k in seq_len(nrow(grid))) {
    g <- grid[k, ]
    lab <- .is_label(g)
    nm <- .is_shapes[[g$shape]]
    n <- length(nm)
    .is_setup_backbone(g$backbone)
    rk <- .is_arg(g$rank_mode, n, "species")
    ln <- .is_arg(g$lin_mode, n, c("Cercozoa", "Metazoa|Chordata|Plantae|Chlorophyta"))
    out <- NULL
    expect_no_error(
      out <- .is_quiet(fill_higher_ranks(
        nm, local_sources = list(), fill_ranks = c("phylum", "class"),
        input_rank = rk, lineage = ln, backbone_id = g$backbone,
        fallback_backbone_id = NULL)),
      message = lab)
    if (is.null(out)) next
    expect_equal(nrow(out), n, info = lab)
    expect_equal(out$taxon_name, nm, info = lab)
    blank <- is.na(nm) | !nzchar(trimws(nm))
    if (any(blank)) {
      expect_true(all(is.na(out$phylum[blank]) & is.na(out$class[blank]) &
                        is.na(out$genus[blank])), info = lab)
    }
    dup <- which(duplicated(nm) & !blank)
    for (j in dup) {
      first <- which(nm == nm[j])[1L]
      expect_true(.is_same_row(out, first, j),
                  info = paste(lab, "duplicate row", j, "differs from row", first))
    }
  }
})

# ---- 4: validation shapes ----------------------------------------------------

test_that("wrong-length input_rank / lineage error; all-NA logicals act as NULL", {
  .is_ncbi_setup()
  nm <- c("Filoreta", "Nuda")
  expect_error(verify_taxon_names(nm, backbone_id = 4L, input_rank = "genus"),
               "one rank per element")
  expect_error(verify_taxon_names(nm, backbone_id = 4L, lineage = "Cercozoa"),
               "one lineage context")
  expect_error(fill_higher_ranks(nm, input_rank = "genus", local_sources = list()),
               "one rank per element")
  expect_error(fill_higher_ranks(nm, lineage = "Cercozoa", local_sources = list()),
               "one lineage context")

  base <- .is_quiet(verify_taxon_names(nm, backbone_id = 4L))
  v2 <- .is_quiet(verify_taxon_names(nm, backbone_id = 4L, lineage = c(NA, NA)))
  expect_equal(v2, base)

  fbase <- .is_quiet(fill_higher_ranks(nm, local_sources = list(),
                                       fill_ranks = "phylum", fallback_backbone_id = NULL))
  f1 <- .is_quiet(fill_higher_ranks(nm, local_sources = list(), fill_ranks = "phylum",
                                    fallback_backbone_id = NULL, input_rank = c(NA, NA)))
  f2 <- .is_quiet(fill_higher_ranks(nm, local_sources = list(), fill_ranks = "phylum",
                                    fallback_backbone_id = NULL, lineage = c(NA, NA)))
  expect_equal(f1, fbase)
  expect_equal(f2, fbase)
})

# ---- 5: the same-rank kingdom rule is a SET test (GN path) -------------------

test_that("GN same-rank kingdom rule: a multi-kingdom context is order-free", {
  ulv <- .is_gn_item("Ulvaria", "Ulvaria",
    "Plantae|Chlorophyta|Ulvophyceae|Ulvales|Ulvaceae|Ulvaria",
    "kingdom|phylum|class|order|family|genus")
  .is_gn_setup(list(Ulvaria = ulv))
  run <- function(ctx) {
    msgs <- character(0L)
    out <- withCallingHandlers(
      suppressWarnings(verify_taxon_names("Ulvaria", backbone_id = 11L,
                                          input_rank = "genus", lineage = ctx)),
      message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") })
    list(out = out, msgs = paste(msgs, collapse = "\n"))
  }
  fwd <- run("Metazoa|Chordata|Plantae|Chlorophyta")
  rev <- run("Plantae|Chlorophyta|Metazoa|Chordata")
  one <- run("Metazoa|Chordata")
  expect_true(fwd$out$verified)
  expect_true(rev$out$verified)
  expect_equal(fwd$out$matched_name, "Ulvaria")
  expect_equal(fwd$out$verified, rev$out$verified)
  expect_equal(fwd$out$matched_name, rev$out$matched_name)
  expect_equal(fwd$out$classification_path, rev$out$classification_path)
  expect_false(grepl("contradicts", fwd$msgs))
  expect_false(grepl("contradicts", rev$msgs))
  expect_false(one$out$verified)
  expect_true(is.na(one$out$matched_name))
  expect_match(one$msgs, "contradicts")
})

# Kept in its own test: verify_taxon_names() does not coerce a logical all-NA
# `input_rank` the way it does `lineage` (and the way fill_higher_ranks() does).
test_that("verify_taxon_names: logical all-NA input_rank is accepted as NULL", {
  .is_ncbi_setup()
  nm <- c("Filoreta", "Nuda")
  base <- .is_quiet(verify_taxon_names(nm, backbone_id = 4L))
  v1 <- NULL
  expect_no_error(v1 <- .is_quiet(verify_taxon_names(nm, backbone_id = 4L,
                                                     input_rank = c(NA, NA))))
  expect_equal(v1, base)
})
