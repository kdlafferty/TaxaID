# The taxon registry: one resolution per name, joins on ids only, and a guard
# that can fail. Offline throughout: real answers come from the recorded
# GNverifier response through a mocked httr (see test-verify_taxon_names_ids.R),
# synthetic ones from .fake_lookup(). Cases are taken from defects measured in
# CalIntertidal r15 (Embiotoca / Hypsurus caryi on one ballot, Platybelone
# argala / argalus, Vertebrata, Carcharodon under two families) plus NEGATIVE
# cases: two taxa that must never be merged.

.gnv_fx <- function() jsonlite::fromJSON(testthat::test_path("fixtures", "gnv_ds11_bestresult.json"), simplifyVector = FALSE)
.mock_gnv_reg <- function(env = parent.frame()) {
  fx <- .gnv_fx(); by_name <- stats::setNames(fx$names, vapply(fx$names, function(n) n$name, ""))
  testthat::local_mocked_bindings(
    POST = function(url, body, ...) structure(list(asked = unlist(body$nameStrings)), class = "mock_response"),
    status_code = function(resp) 200L,
    content = function(resp, ...) list(names = lapply(resp$asked, function(n) by_name[[n]] %||% list(name = n, matchType = "NoMatch"))),
    .package = "httr", .env = env
  )
}
.real_lookup <- function(names, rank, context) {
  rank <- if (all(is.na(rank))) NULL else rank
  context <- if (all(is.na(context))) NULL else context
  suppressMessages(verify_taxon_names(names, backbone_id = 11L, input_rank = rank, lineage = context, return_ids = TRUE))
}

# Synthetic answers: one row per (name, context) in `tbl`; anything else is a non-match.
.fake_lookup <- function(tbl) {
  function(names, rank, context) {
    k <- paste(names, ifelse(is.na(context), "", context), sep = "\r")
    tk <- paste(tbl$q, ifelse(is.na(tbl$ctx), "", tbl$ctx), sep = "\r")
    # a name with no context-specific row falls back to its context-free row (the lookup ignores a context it has
    # no answer for). The earlier fallback compared "name\rcontext" with "name\r" and so never matched.
    nc <- which(is.na(tbl$ctx)); j <- match(names, tbl$q[nc])
    i <- match(k, tk); i[is.na(i)] <- nc[j[is.na(i)]]
    hit <- !is.na(i)
    data.frame(user_supplied_name = names, matched_name = ifelse(hit, tbl$matched[i], NA), matched_rank = ifelse(hit, tbl$rank[i], NA),
               is_synonym = ifelse(hit, tbl$syn[i], NA), classification_path = ifelse(hit, tbl$path[i], NA),
               classification_ranks = ifelse(hit, tbl$ranks[i], NA), score = NA_real_, verified = TRUE, matched = hit,
               record_id = ifelse(hit, tbl$rec[i], NA), current_record_id = ifelse(hit, tbl$cur[i], NA),
               classification_ids = ifelse(hit, tbl$ids[i], NA), data_source_id = 11L, entry_date = "2024-01-11",
               match_type = ifelse(hit, tbl$mt[i], NA), stringsAsFactors = FALSE)
  }
}
.row <- function(q, matched, cur, ids, path, ranks = "kingdom|phylum|order|family|genus|species", rec = cur, syn = FALSE,
                 rank = "species", mt = "Exact", ctx = NA_character_) {
  data.frame(q = q, matched = matched, cur = cur, rec = rec, ids = ids, path = path, ranks = ranks, syn = syn, rank = rank,
             mt = mt, ctx = ctx, stringsAsFactors = FALSE)
}
.names <- function(v, tbl, ...) data.frame(verbatim_name = v, source_table = tbl, ..., stringsAsFactors = FALSE)

test_that("a synonym and its accepted name are ONE taxon, as a declared merge", {
  .mock_gnv_reg()
  reg <- build_taxon_registry(rbind(.names("Embiotoca caryi", "reference"), .names("Hypsurus caryi", "priors")),
                              run_id = "t1", lookup = .real_lookup)
  ids <- reg$names$taxon_id[match(c("Embiotoca caryi", "Hypsurus caryi"), reg$names$verbatim_name)]
  expect_identical(ids, c("gbif:2389310", "gbif:2389310"))
  expect_identical(reg$names$status[reg$names$verbatim_name == "Embiotoca caryi"], "synonym")
  expect_identical(reg$names$backend_record_id[reg$names$verbatim_name == "Embiotoca caryi"], "2389311")
  chk <- check_taxon_registry(reg, verbose = FALSE)
  expect_false(any(chk$severity == "error"))
  expect_true(any(chk$kind == "declared_merge" & chk$taxon_id == "gbif:2389310"))
})

test_that("the ancestor tree comes from the ids: parent_at reads it, not a table column", {
  .mock_gnv_reg()
  reg <- build_taxon_registry(.names(c("Embiotoca caryi", "Oxyjulis californica"), "match"), run_id = "t2", lookup = .real_lookup)
  expect_identical(parent_at(c("gbif:2389310", "gbif:2383301"), "family", reg), c("gbif:4269", "gbif:8535"))
  expect_identical(parent_at("gbif:2389310", "genus", reg), "gbif:2389309")
  expect_identical(parent_at("gbif:2389309", "genus", reg), "gbif:2389309")  # a taxon AT the rank is itself
  expect_true(is.na(parent_at("gbif:2389310", "subgenus", reg)))
  expect_identical(reg$taxa$name[reg$taxa$taxon_id == "gbif:4269"], "Embiotocidae")
})

test_that("a gender variant takes its congener's id, is listed, and is not an undeclared merge", {
  .mock_gnv_reg()
  reg <- build_taxon_registry(.names(c("Platybelone argala", "Platybelone argalus"), "reference"), run_id = "t3", lookup = .real_lookup)
  expect_identical(unique(reg$names$taxon_id), "gbif:4286140")
  expect_identical(reg$names$status[reg$names$verbatim_name == "Platybelone argala"], "gender_variant")
  chk <- check_taxon_registry(reg, verbose = FALSE)
  expect_false(any(chk$kind == "undeclared_merge"))
  expect_true(any(chk$kind == "gender_variant"))
})

test_that("a homonym asked with an animal context never takes the alga's id", {
  .mock_gnv_reg()
  reg <- build_taxon_registry(rbind(.names("Vertebrata", "match_algae", rank_given = "genus", context = "Plantae|Rhodophyta"),
                                    .names("Vertebrata", "match_animals", rank_given = "genus", context = "Animalia|Chordata")),
                              run_id = "t4", lookup = .real_lookup)
  alga <- reg$names$taxon_id[reg$names$source_table == "match_algae"]
  animal <- reg$names$taxon_id[reg$names$source_table == "match_animals"]
  expect_identical(alga, "gbif:2660342")
  expect_false(identical(animal, alga))
  expect_match(animal, "^local:")
  # a gate rejection is an answer (homonym_rejected), never a failed lookup
  expect_identical(reg$names$status[reg$names$source_table == "match_animals"], "homonym_rejected")
})

test_that("NEGATIVE: two congeners with near-identical names stay two taxa", {
  lk <- .fake_lookup(rbind(
    .row("Sebastes melanops", "Sebastes melanops", "100", "1|2|3|4|50|100", "Animalia|Chordata|Perciformes|Sebastidae|Sebastes|Sebastes melanops"),
    .row("Sebastes melanostomus", "Sebastes melanostomus", "101", "1|2|3|4|50|101", "Animalia|Chordata|Perciformes|Sebastidae|Sebastes|Sebastes melanostomus")))
  reg <- build_taxon_registry(.names(c("Sebastes melanops", "Sebastes melanostomus"), "match"), run_id = "n1", lookup = lk)
  expect_identical(sort(reg$names$taxon_id), c("gbif:100", "gbif:101"))
  chk <- check_taxon_registry(reg, verbose = FALSE)
  expect_false(any(chk$kind %in% c("declared_merge", "undeclared_merge")))
})

test_that("NEGATIVE: a within-kingdom homonym in two families stays two taxa, and an ambiguous attach is refused", {
  lk <- .fake_lookup(rbind(
    .row("Homonymus alpha", "Homonymus alpha", "200", "1|2|3|40|60|200", "Animalia|Chordata|Perciformes|Labridae|Homonymus|Homonymus alpha", ctx = "Labridae"),
    .row("Homonymus alpha", "Homonymus alpha", "300", "1|2|3|41|61|300", "Animalia|Chordata|Perciformes|Gobiidae|Homonymus|Homonymus alpha", ctx = "Gobiidae")))
  reg <- freeze_taxon_registry(build_taxon_registry(rbind(.names("Homonymus alpha", "match", context = "Labridae"),
                                                          .names("Homonymus alpha", "match", context = "Gobiidae")),
                                                    run_id = "n2", lookup = lk))
  expect_identical(sort(unique(reg$names$taxon_id)), c("gbif:200", "gbif:300"))
  x <- data.frame(name = c("Homonymus alpha", "Homonymus alpha"), ctx = c("Gobiidae", "Labridae"))
  expect_error(attach_taxon_ids(x, reg, "name", "match"), "context")
  y <- attach_taxon_ids(x, reg, "name", "match", context_col = "ctx")
  expect_identical(y$taxon_id, c("gbif:300", "gbif:200"))
})

test_that("NEGATIVE: a planted undeclared merge (an exact, non-synonym answer naming ANOTHER species) is an error-class finding", {
  lk <- .fake_lookup(rbind(
    .row("Foo baz", "Foo baz", "400", "1|2|3|4|5|400", "Animalia|Chordata|Perciformes|Fooidae|Foo|Foo baz"),
    .row("Foo bar", "Foo baz", "400", "1|2|3|4|5|400", "Animalia|Chordata|Perciformes|Fooidae|Foo|Foo baz")))
  reg <- build_taxon_registry(.names(c("Foo baz", "Foo bar"), "match"), run_id = "n3", lookup = lk)
  chk <- check_taxon_registry(reg, verbose = FALSE)
  expect_true(any(chk$kind == "undeclared_merge" & chk$taxon_id == "gbif:400"))
  expect_error(check_taxon_registry(reg, mode = "error", verbose = FALSE), "undeclared_merge")
})

test_that("a path-less id is named by the lookup's accepted name, even when its synonym arrives first", {
  # p2 (exact F1 reproduction) found 57 false undeclared merges from this: the row was named by the first
  # verbatim name met, a synonym, so the accepted name read as an undeclared second name
  lk <- .fake_lookup(rbind(
    .row("Halichoeres californicus", "Oxyjulis californica", "2383301", NA, NA, ranks = NA, rec = "2383302", syn = TRUE),
    .row("Oxyjulis californica", "Oxyjulis californica", "2383301", NA, NA, ranks = NA)))
  reg <- build_taxon_registry(.names(c("Halichoeres californicus", "Oxyjulis californica"), "priors"), run_id = "p1", lookup = lk)
  expect_identical(reg$taxa$name[reg$taxa$taxon_id == "gbif:2383301"], "Oxyjulis californica")
  chk <- check_taxon_registry(reg, verbose = FALSE)
  expect_false(any(chk$kind == "undeclared_merge"))
  expect_true(any(chk$kind == "declared_merge" & chk$taxon_id == "gbif:2383301"))
})

test_that("a taxon reached only through synonyms (its accepted name in no table) is named by that accepted name, and nothing is flagged", {
  lk <- .fake_lookup(rbind(
    .row("Etrumeus teres", "Etrumeus sadina", "2413189", NA, NA, ranks = NA, rec = "2413183", syn = TRUE),
    .row("Clupea teres", "Etrumeus sadina", "2413189", NA, NA, ranks = NA, rec = "9999999", syn = TRUE)))
  reg <- build_taxon_registry(.names(c("Etrumeus teres", "Clupea teres"), "reference"), run_id = "p2", lookup = lk)
  expect_identical(reg$taxa$name[reg$taxa$taxon_id == "gbif:2413189"], "Etrumeus sadina")
  chk <- check_taxon_registry(reg, verbose = FALSE)
  expect_false(any(chk$severity == "error"))
  expect_true(any(chk$kind == "declared_merge" & chk$taxon_id == "gbif:2413189"))
})

test_that("FIX 1: a binomial answered only at GENUS keeps its own run-local id under that genus, never the genus id", {
  # p3 (live, CI): 1,048 species names took their genus's id this way; 161 false merges (e.g. 5 Gelidium species as one)
  gpath <- "Plantae|Rhodophyta|Florideophyceae|Gelidiales|Gelidiaceae|Gelidium"
  granks <- "kingdom|phylum|class|order|family|genus"
  lk <- .fake_lookup(rbind(
    .row("Gelidium kathyanniae", "Gelidium", "9460134", "6|106|342|900|901|9460134", gpath, ranks = granks, rank = "genus"),
    .row("Gelidium pacificum", "Gelidium", "9460134", "6|106|342|900|901|9460134", gpath, ranks = granks, rank = "genus")))
  reg <- build_taxon_registry(.names(c("Gelidium kathyanniae", "Gelidium pacificum"), "priors"), run_id = "f1", lookup = lk)
  id <- stats::setNames(reg$names$taxon_id, reg$names$verbatim_name)
  expect_identical(unname(id), c("local:9460134:kathyanniae", "local:9460134:pacificum"))
  expect_identical(reg$names$status, c("rank_fallback", "rank_fallback"))
  expect_identical(parent_at(unname(id), "genus", reg), c("gbif:9460134", "gbif:9460134"))
  chk <- check_taxon_registry(reg, verbose = FALSE)
  expect_false(any(chk$kind %in% c("undeclared_merge", "declared_merge")))
  expect_true(any(chk$kind == "rank_fallback" & chk$n == 2L))
})

test_that("FIX 2: a fuzzy answer that is not a gender variant does not resolve the name", {
  # p3 (live, Mugu): Sardinops ocellatus fuzzy-matched to S. sagax and took its id
  path <- "Animalia|Chordata|Clupeiformes|Clupeidae|Sardinops|Sardinops sagax"
  lk <- .fake_lookup(rbind(
    .row("Sardinops sagax", "Sardinops sagax", "2412583", "1|44|538|7690|2412582|2412583", path),
    .row("Sardinops ocellatus", "Sardinops sagax", "2412583", "1|44|538|7690|2412582|2412583", path, mt = "Fuzzy")))
  reg <- build_taxon_registry(.names(c("Sardinops sagax", "Sardinops ocellatus"), "r2"), run_id = "f2", lookup = lk)
  oc <- reg$names[reg$names$verbatim_name == "Sardinops ocellatus", ]
  expect_false(identical(oc$taxon_id, "gbif:2412583"))
  expect_identical(oc$taxon_id, "local:2412582:ocellatus")
  expect_identical(oc$status, "fuzzy_rejected")
  chk <- check_taxon_registry(reg, verbose = FALSE)
  expect_false(any(chk$kind == "undeclared_merge"))
  expect_true(any(chk$kind == "fuzzy_rejected"))
})

test_that("FIX 3: a FAILED lookup is lookup_failed -- no id, not a local id, an error-class finding, refused at attach", {
  lk <- function(names, rank, context) {
    out <- .fake_lookup(.row("Hypsurus caryi", "Hypsurus caryi", "2389310", "1|44|587|4269|2389309|2389310",
                             "Animalia|Chordata|Perciformes|Embiotocidae|Hypsurus|Hypsurus caryi"))(names, rank, context)
    f <- names == "Foo failus"
    out$verified[f] <- FALSE; out$matched[f] <- FALSE
    out
  }
  reg <- build_taxon_registry(.names(c("Hypsurus caryi", "Foo failus"), "r2"), run_id = "f3", lookup = lk)
  ff <- reg$names[reg$names$verbatim_name == "Foo failus", ]
  expect_identical(ff$status, "lookup_failed")
  expect_true(is.na(ff$taxon_id))
  expect_false(any(grepl("Foo failus", reg$taxa$taxon_id, fixed = TRUE)))
  chk <- check_taxon_registry(reg, verbose = FALSE)
  expect_true(any(chk$kind == "lookup_failed" & chk$severity == "error"))
  reg <- freeze_taxon_registry(reg)
  expect_error(attach_taxon_ids(data.frame(n = "Foo failus"), reg, "n", "r2"), "FAILED lookup")
  expect_output(print(reg), "lookup FAILED .*: 1 name")
})

test_that("unresolved names get run-local ids: under the resolved genus where it is known", {
  .mock_gnv_reg()
  reg <- build_taxon_registry(.names(c("Hypsurus caryi", "Hypsurus novus", "Zzzus yyyus"), "checklist"), run_id = "t5", lookup = .real_lookup)
  id <- stats::setNames(reg$names$taxon_id, reg$names$verbatim_name)
  expect_identical(unname(id["Hypsurus novus"]), "local:2389309:novus")
  expect_identical(parent_at("local:2389309:novus", "genus", reg), "gbif:2389309")
  expect_identical(unname(id["Zzzus yyyus"]), "local:Zzzus yyyus")
  chk <- check_taxon_registry(reg, verbose = FALSE)
  expect_true(any(chk$kind == "unresolved_local" & chk$n == 2L))
})

test_that("pool keys come first, and a pool key that disagrees with the lookup is an error-class finding", {
  .mock_gnv_reg()
  reg <- build_taxon_registry(.names(c("Hypsurus caryi", "Oxyjulis californica"), "pool"), run_id = "t6", lookup = .real_lookup,
                              pool_keys = data.frame(verbatim_name = c("Hypsurus caryi", "Oxyjulis californica"), species_key = c(2389310L, 999L)))
  expect_identical(reg$names$taxon_id, c("gbif:2389310", "gbif:999"))
  expect_identical(reg$names$status, c("accepted", "pool_key_conflict"))
  chk <- check_taxon_registry(reg, verbose = FALSE)
  expect_true(any(chk$kind == "pool_key_conflict"))
})

test_that("a name the pool holds under 2+ keys is NOT keyed from the pool (no silent first pick) and is an error-class finding", {
  .mock_gnv_reg()
  # the WRONG key listed first: match() on the name would take 999 and file a pool_key_conflict
  pk <- data.frame(verbatim_name = c("Hypsurus caryi", "Hypsurus caryi", "Hypsurus caryi", "Absent name", "Absent name"),
                   species_key = c(999L, 2389310L, 999L, 1L, 2L))
  reg <- build_taxon_registry(.names("Hypsurus caryi", "pool"), run_id = "t6b", lookup = .real_lookup, pool_keys = pk)
  expect_identical(reg$names$taxon_id, "gbif:2389310")          # the lookup's id, not either pool key
  expect_identical(reg$names$status, "accepted")                 # a silent first pick would give gbif:999 / pool_key_conflict
  a <- reg$meta$pool_key_ambiguous
  expect_identical(a$verbatim_name, c("Hypsurus caryi", "Absent name"))
  expect_identical(a$species_keys, c("2389310 | 999", "1 | 2"))
  expect_identical(a$in_names, c(TRUE, FALSE))
  chk <- check_taxon_registry(reg, verbose = FALSE)
  f <- chk[chk$kind == "pool_key_ambiguous", ]
  expect_identical(nrow(f), 2L)
  expect_identical(unique(f$severity), "error")
  expect_error(check_taxon_registry(reg, mode = "error", verbose = FALSE), "pool_key_ambiguous")
  # one key repeated is not ambiguity: the name IS keyed from the pool (999 differs from the lookup, so it shows)
  reg1 <- build_taxon_registry(.names("Hypsurus caryi", "pool"), run_id = "t6c", lookup = .real_lookup,
                               pool_keys = data.frame(verbatim_name = c("Hypsurus caryi", "Hypsurus caryi"), species_key = c(999L, 999L)))
  expect_null(reg1$meta$pool_key_ambiguous)
  expect_identical(reg1$names$taxon_id, "gbif:999")
  expect_identical(reg1$names$status, "pool_key_conflict")
})

# --- freeze, stamp, join --------------------------------------------------------------------
.caryi_reg <- function() {
  build_taxon_registry(rbind(.names(c("Embiotoca caryi", "Oxyjulis californica"), "match"),
                             .names(c("Hypsurus caryi", "Halichoeres californicus"), "priors")),
                       run_id = "j1", lookup = .real_lookup)
}

test_that("ids cannot be attached before the freeze, and an unknown name after it is an error", {
  .mock_gnv_reg()
  reg <- .caryi_reg()
  x <- data.frame(taxon_name = "Embiotoca caryi")
  expect_error(attach_taxon_ids(x, reg, "taxon_name", "match"), "Freeze")
  reg <- freeze_taxon_registry(reg)
  expect_error(attach_taxon_ids(data.frame(taxon_name = "Mola mola"), reg, "taxon_name", "match"), "not in the frozen registry")
})

test_that("a match name and a prior name for one taxon JOIN by id (the r15 caryi and Oxyjulis failures)", {
  .mock_gnv_reg()
  reg <- freeze_taxon_registry(.caryi_reg())
  m <- attach_taxon_ids(data.frame(observation_id = c("o1", "o2"), taxon_name = c("Embiotoca caryi", "Oxyjulis californica")), reg, "taxon_name", "match")
  p <- attach_taxon_ids(data.frame(taxon_name = c("Hypsurus caryi", "Halichoeres californicus"), prior = c(0.3, 0.2)), reg, "taxon_name", "priors")
  j <- suppressMessages(join_by_taxon(m, p, "left"))
  expect_identical(j$prior, c(0.3, 0.2))
  expect_identical(attr(j, "no_partner")[["x_rows"]], 0L)
  expect_identical(attr(j, "taxon_registry"), attr(m, "taxon_registry"))
  # the verbatim names are untouched on both sides
  expect_identical(j$taxon_name.x, c("Embiotoca caryi", "Oxyjulis californica"))
})

test_that("GUARD CAN FAIL: a join on an unstamped table, a dropped stamp, a foreign registry, or a name column is refused", {
  .mock_gnv_reg()
  reg <- freeze_taxon_registry(.caryi_reg())
  m <- attach_taxon_ids(data.frame(taxon_name = "Embiotoca caryi", k = 1), reg, "taxon_name", "match")
  p <- attach_taxon_ids(data.frame(taxon_name = "Hypsurus caryi"), reg, "taxon_name", "priors")
  expect_error(join_by_taxon(data.frame(taxon_id = "gbif:2389310"), p), "no taxon-registry stamp")
  dropped <- merge(m, data.frame(z = 1))                  # an ordinary operation that drops attributes
  expect_null(attr(dropped, "taxon_registry"))
  expect_error(join_by_taxon(dropped, p), "no taxon-registry stamp")
  other <- freeze_taxon_registry(build_taxon_registry(.names("Hypsurus caryi", "priors"), run_id = "other", lookup = .real_lookup))
  p2 <- attach_taxon_ids(data.frame(taxon_name = "Hypsurus caryi"), other, "taxon_name", "priors")
  expect_error(join_by_taxon(m, p2), "different registries")
  expect_error(join_by_taxon(m, p, extra_by = "taxon_name"), "name")
  expect_error(join_by_taxon(m, p, extra_by = "species_ncbi"), "name")
})

test_that("GUARD CAN FAIL: one taxon twice in one observation (the r15 Dryad double entry) is an error-class finding", {
  .mock_gnv_reg()
  reg <- freeze_taxon_registry(build_taxon_registry(.names(c("Embiotoca caryi", "Hypsurus caryi"), "r2"), run_id = "g1", lookup = .real_lookup))
  r2 <- attach_taxon_ids(data.frame(observation_id = c("u1", "u1", "u2"), taxon_name = c("Embiotoca caryi", "Hypsurus caryi", "Hypsurus caryi"),
                                    hypothesis_type = "specific_candidate"), reg, "taxon_name", "r2")
  chk <- check_taxon_registry(reg, tables = list(r2 = r2), verbose = FALSE)
  expect_true(any(chk$kind == "taxon_twice_in_observation" & chk$table == "r2"))
  expect_error(check_taxon_registry(reg, tables = list(r2 = r2), mode = "error", verbose = FALSE), "taxon_twice_in_observation")
  # a genus candidate beside its own genus ring is NOT a double entry (different hypothesis types)
  ok <- r2[1:2, ]; ok$hypothesis_type <- c("specific_candidate", "unreferenced_species")
  attr(ok, "taxon_registry") <- attr(r2, "taxon_registry")
  expect_false(any(check_taxon_registry(reg, tables = list(ok = ok), verbose = FALSE)$kind == "taxon_twice_in_observation"))
})

test_that("a FAMILY that differs from the registry's tree is another classification: listed (info), never an error", {
  lk <- .fake_lookup(.row("Carcharodon carcharias", "Carcharodon carcharias", "500", "1|44|900|901|902|500",
                          "Animalia|Chordata|Lamniformes|Lamnidae|Carcharodon|Carcharodon carcharias"))
  reg <- freeze_taxon_registry(build_taxon_registry(.names("Carcharodon carcharias", "r2"), run_id = "g2", lookup = lk))
  t <- attach_taxon_ids(data.frame(observation_id = c("a", "b"), taxon_name = "Carcharodon carcharias", family = c("Lamnidae", "Alopiidae")),
                        reg, "taxon_name", "r2")
  chk <- check_taxon_registry(reg, tables = list(r2 = t, raw = data.frame(taxon_name = "x")), verbose = FALSE)
  w <- chk[chk$kind == "lineage_concept_differs", ]
  expect_identical(nrow(w), 1L)
  expect_identical(c(w$severity, w$n), c("info", "1"))
  expect_match(w$names, "family: table Alopiidae, registry Lamnidae", fixed = TRUE)
  expect_false(any(chk$kind == "lineage_disagrees"))
  expect_true(any(chk$kind == "missing_stamp" & chk$table == "raw"))
  # the family difference alone does not stop an error-mode run
  expect_silent(check_taxon_registry(reg, tables = list(r2 = t), mode = "error", verbose = FALSE))
})

test_that("GUARD CAN FAIL: a GENUS that differs is an error, unless it is the genus of a declared synonym of that taxon", {
  ids <- "1|44|587|4269|2389309|2389310"; path <- "Animalia|Chordata|Perciformes|Embiotocidae|Hypsurus|Hypsurus caryi"
  lk <- .fake_lookup(rbind(.row("Hypsurus caryi", "Hypsurus caryi", "2389310", ids, path),
                           .row("Embiotoca caryi", "Hypsurus caryi", "2389310", ids, path, rec = "2389311", syn = TRUE)))
  reg <- freeze_taxon_registry(build_taxon_registry(.names(c("Hypsurus caryi", "Embiotoca caryi"), "r2"), run_id = "g3", lookup = lk))
  t <- attach_taxon_ids(data.frame(observation_id = c("a", "b", "c"), taxon_name = c("Hypsurus caryi", "Embiotoca caryi", "Hypsurus caryi"),
                                   genus = c("Hypsurus", "Embiotoca", "Damalichthys")), reg, "taxon_name", "r2")
  chk <- check_taxon_registry(reg, tables = list(r2 = t), verbose = FALSE)
  e <- chk[chk$kind == "lineage_disagrees", ]; i <- chk[chk$kind == "lineage_concept_differs", ]
  expect_identical(c(nrow(e), nrow(i)), c(1L, 1L))
  expect_identical(c(e$severity, e$n), c("error", "1"))
  expect_match(e$names, "table Damalichthys", fixed = TRUE)
  expect_identical(c(i$severity, i$n), c("info", "1"))
  expect_match(i$names, "table Embiotoca", fixed = TRUE)
  expect_error(check_taxon_registry(reg, tables = list(r2 = t), mode = "error", verbose = FALSE), "lineage_disagrees")
  # without the declared synonym, the synonym's genus is an error too: the exemption comes from the registry, not the string
  reg1 <- freeze_taxon_registry(build_taxon_registry(.names("Hypsurus caryi", "r2"), run_id = "g4", lookup = lk))
  t1 <- attach_taxon_ids(data.frame(observation_id = "a", taxon_name = "Hypsurus caryi", genus = "Embiotoca"), reg1, "taxon_name", "r2")
  expect_true(any(check_taxon_registry(reg1, tables = list(r2 = t1), verbose = FALSE)$kind == "lineage_disagrees"))
})

test_that("GUARD CAN FAIL: attach_taxon_ids refuses to overwrite a taxon_id column it did not stamp (iNat ids)", {
  .mock_gnv_reg()
  reg <- freeze_taxon_registry(.caryi_reg())
  inat <- data.frame(taxon_name = "Hypsurus caryi", taxon_id = 49917L)        # iNaturalist's own id, as check_inat_range() returns
  expect_error(attach_taxon_ids(inat, reg, "taxon_name", "priors"), "did not stamp")
  # a table this registry stamped is re-attachable, with the same ids
  p <- attach_taxon_ids(data.frame(taxon_name = "Hypsurus caryi"), reg, "taxon_name", "priors")
  expect_identical(attach_taxon_ids(p, reg, "taxon_name", "priors")$taxon_id, p$taxon_id)
  # stamped by ANOTHER registry: refused as well
  other <- freeze_taxon_registry(build_taxon_registry(.names("Hypsurus caryi", "priors"), run_id = "other", lookup = .real_lookup))
  expect_error(attach_taxon_ids(attach_taxon_ids(data.frame(taxon_name = "Hypsurus caryi"), other, "taxon_name", "priors"),
                                reg, "taxon_name", "priors"), "did not stamp")
})

# Genus answers for the unresolved-name pass. Hypnea (red alga) answered as Hypena (moth) is the live p8d case
# (species level); here the same mistake at the genus pass. Pyrgophorus is GBIF's VARIANT for Pyrogophorus.
.gk <- "kingdom|phylum|class|order|family|genus"
.genus_lk <- function() .fake_lookup(rbind(
  .row("Hypnea", "Hypena", "1798000", "1|54|216|797|4532|1798000", "Animalia|Arthropoda|Insecta|Lepidoptera|Erebidae|Hypena",
       ranks = .gk, rank = "genus", mt = "Fuzzy"),
  .row("Pyrogophorus", "Pyrgophorus", "2299855", "1|52|225|1000|2299800|2299855", "Animalia|Mollusca|Gastropoda|Littorinimorpha|Cochliopidae|Pyrgophorus",
       ranks = .gk, rank = "genus", mt = "Fuzzy"),
  .row("Hypsurus", "Hypsurus", "2389309", "1|44|204|587|4269|2389309", "Animalia|Chordata|Actinopterygii|Perciformes|Embiotocidae|Hypsurus",
       ranks = .gk, rank = "genus", mt = "Exact")))

test_that("GUARD CAN FAIL: a fuzzy/variant GENUS answer in another kingdom is refused; without the gate it was taken", {
  reg <- build_taxon_registry(.names("Hypnea nigrescens", "r2", context = "Plantae|Rhodophyta|Florideophyceae"),
                              run_id = "gv1", lookup = .genus_lk())
  expect_identical(reg$names$taxon_id, "local:Hypnea nigrescens")          # NOT local:1798000:nigrescens (under the moth)
  expect_false("gbif:1798000" %in% reg$taxa$taxon_id)
  gvr <- reg$meta$genus_variant_rejected
  expect_identical(c(gvr$genus_word, gvr$answer, gvr$reason), c("Hypnea", "Hypena", "lineage does not agree at kingdom and phylum"))
  chk <- check_taxon_registry(reg, verbose = FALSE)
  expect_identical(chk$severity[chk$kind == "genus_variant_rejected"], "info")
})

test_that("a fuzzy/variant genus answer whose kingdom AND phylum the names' context gives is taken (Pyrogophorus -> Pyrgophorus)", {
  reg <- build_taxon_registry(.names("Pyrogophorus platyrachis", "r2", context = "Animalia|Mollusca|Gastropoda"),
                              run_id = "gv2", lookup = .genus_lk())
  expect_identical(reg$names$taxon_id, "local:2299855:platyrachis")
  expect_true("gbif:2299855" %in% reg$taxa$taxon_id)
  expect_null(reg$meta$genus_variant_rejected)
})

test_that("GUARD CAN FAIL: no context, or the right kingdom with the wrong phylum, refuses a non-exact genus; EXACT needs neither", {
  r0 <- build_taxon_registry(.names("Pyrogophorus platyrachis", "r2"), run_id = "gv3", lookup = .genus_lk())
  expect_identical(r0$names$taxon_id, "local:Pyrogophorus platyrachis")
  expect_identical(r0$meta$genus_variant_rejected$reason, "no lineage context")
  r1 <- build_taxon_registry(.names("Pyrogophorus platyrachis", "r2", context = "Animalia|Chordata"), run_id = "gv4", lookup = .genus_lk())
  expect_identical(r1$names$taxon_id, "local:Pyrogophorus platyrachis")   # kingdom agrees, phylum does not: refused
  r2 <- build_taxon_registry(.names("Hypsurus notaspecies", "r2"), run_id = "gv5", lookup = .genus_lk())
  expect_identical(r2$names$taxon_id, "local:2389309:notaspecies")         # an EXACT genus answer is unchanged
  expect_null(r2$meta$genus_variant_rejected)
})

# Binomials GBIF answered as a VARIANT of their GENUS, epithet exact: the 9 CI names of p8d. Six are spelling variants
# (Pyrogophorus platyrachis -> Pyrgophorus platyrachis); three land in another kingdom (Hypnea nigrescens, a red alga ->
# Hypena nigrescens, a moth; Physalia minuta, a siphonophore -> Physalis minuta, a plant; Gracilaria parva, a red alga ->
# Gracillaria parva, a moth). Answers carry GBIF's own matchType, as lookup_gbif_taxa() returns it.
.s7 <- "kingdom|phylum|class|order|family|genus|species"
.pyrg_path <- "Animalia|Mollusca|Gastropoda|Littorinimorpha|Cochliopidae|Pyrgophorus|Pyrgophorus platyrachis"
.pyrg_ids <- "1|52|225|1000|2299800|2299855|2299858"
.binvar_tbl <- rbind(
  .row("Pyrogophorus platyrachis", "Pyrgophorus platyrachis", "2299858", .pyrg_ids, .pyrg_path, ranks = .s7, mt = "Fuzzy"),
  .row("Pyrgophorus platyrachis", "Pyrgophorus platyrachis", "2299858", .pyrg_ids, .pyrg_path, ranks = .s7),
  .row("Pyrogophorus platyrachus", "Pyrgophorus platyrachis", "2299858", .pyrg_ids, .pyrg_path, ranks = .s7, mt = "Fuzzy"),
  .row("Pyrogophorus coronatus", "Pyrgophorus coronatus", "2299860", "1|52|225|1000|2299800|2299855|2299860",
       "Animalia|Mollusca|Gastropoda|Littorinimorpha|Cochliopidae|Pyrgophorus|Pyrgophorus coronatus", ranks = .s7, mt = "Fuzzy"),
  .row("Hypnea nigrescens", "Hypena nigrescens", "1800001", "1|54|216|797|4532|1798000|1800001",
       "Animalia|Arthropoda|Insecta|Lepidoptera|Erebidae|Hypena|Hypena nigrescens", ranks = .s7, mt = "Fuzzy"),
  .row("Physalia minuta", "Physalis minuta", "2930001", "6|7707728|220|1176|2928997|2928998|2930001",
       "Plantae|Tracheophyta|Magnoliopsida|Solanales|Solanaceae|Physalis|Physalis minuta", ranks = .s7, mt = "Fuzzy"),
  .row("Gracilaria parva", "Gracillaria parva", "1749713", "1|54|216|797|7015|1749700|1749713",
       "Animalia|Arthropoda|Insecta|Lepidoptera|Gracillariidae|Gracillaria|Gracillaria parva", ranks = .s7, mt = "Fuzzy"))
.binvar_gmt <- c("Pyrogophorus platyrachis" = "VARIANT", "Pyrgophorus platyrachis" = "EXACT", "Pyrogophorus platyrachus" = "VARIANT",
                 "Pyrogophorus coronatus" = "FUZZY", "Hypnea nigrescens" = "VARIANT", "Physalia minuta" = "VARIANT", "Gracilaria parva" = "VARIANT")
.binvar_lk <- function(gmt = TRUE) {
  lk <- .fake_lookup(.binvar_tbl)
  # the answer does not depend on context (as GBIF species/match here); .fake_lookup has no context-free fallback
  function(names, rank, context) {
    out <- lk(names, rank, rep(NA_character_, length(names)))
    if (gmt) out$gbif_matchType <- ifelse(out$matched, unname(.binvar_gmt[names]), NA_character_)
    out
  }
}
.moll <- "Animalia|Mollusca|Gastropoda"

test_that("a binomial answered as a VARIANT of its genus, epithet exact, in the name's own kingdom and phylum takes GBIF's species", {
  reg <- freeze_taxon_registry(build_taxon_registry(rbind(.names("Pyrogophorus platyrachis", "r2", context = .moll),
                                                          .names("Pyrgophorus platyrachis", "priors", context = .moll)),
                                                    run_id = "bv1", lookup = .binvar_lk()))
  n <- reg$names[match(c("Pyrogophorus platyrachis", "Pyrgophorus platyrachis"), reg$names$verbatim_name), ]
  expect_identical(n$taxon_id, c("gbif:2299858", "gbif:2299858"))
  expect_identical(n$status, c("genus_variant", "accepted"))
  expect_null(reg$meta$genus_variant_rejected)
  # one taxon under two spellings: a DECLARED merge; and a table carrying the variant genus is listed, not flagged
  t <- attach_taxon_ids(data.frame(observation_id = c("a", "b"), taxon_name = "Pyrogophorus platyrachis",
                                   genus = c("Pyrogophorus", "Pyrgophorus")), reg, "taxon_name", "r2")
  chk <- check_taxon_registry(reg, tables = list(r2 = t), verbose = FALSE)
  expect_false(any(chk$severity == "error"))
  expect_true(any(chk$kind == "declared_merge" & chk$taxon_id == "gbif:2299858"))
  expect_identical(chk$severity[chk$kind == "genus_variant"], "info")
  expect_match(chk$names[chk$kind == "lineage_concept_differs"], "table Pyrogophorus", fixed = TRUE)
})

test_that("GUARD CAN FAIL: the three cross-kingdom VARIANT answers stay unresolved; the same answer IS taken where the context agrees", {
  ctx <- c("Hypnea nigrescens" = "Plantae|Rhodophyta|Florideophyceae", "Physalia minuta" = "Animalia|Cnidaria|Hydrozoa",
           "Gracilaria parva" = "Plantae|Rhodophyta|Florideophyceae")
  reg <- build_taxon_registry(.names(names(ctx), "r2", context = unname(ctx)), run_id = "bv2", lookup = .binvar_lk())
  n <- reg$names[match(names(ctx), reg$names$verbatim_name), ]
  expect_false(any(n$taxon_id %in% c("gbif:1800001", "gbif:2930001", "gbif:1749713")))
  expect_identical(n$taxon_id, paste0("local:", names(ctx)))
  expect_identical(n$status, rep("fuzzy_rejected", 3L))
  gvr <- reg$meta$genus_variant_rejected
  expect_identical(sort(gvr$query), sort(names(ctx)))
  expect_identical(unique(gvr$pass), "binomial")
  expect_identical(unique(gvr$reason), "lineage does not agree at kingdom and phylum")
  chk <- check_taxon_registry(reg, verbose = FALSE)
  expect_identical(unique(chk$severity[chk$kind == "genus_variant_rejected"]), "info")
  expect_identical(sum(chk$kind == "genus_variant_rejected"), 3L)
  # the gate, not the answer, is what refuses: the moth's own lineage as context takes it
  r1 <- build_taxon_registry(.names("Hypnea nigrescens", "r2", context = "Animalia|Arthropoda|Insecta"), run_id = "bv3", lookup = .binvar_lk())
  expect_identical(c(r1$names$taxon_id, r1$names$status), c("gbif:1800001", "genus_variant"))
})

test_that("GUARD CAN FAIL: no context, wrong phylum, a FUZZY (not VARIANT) answer, a changed epithet, or no gbif_matchType: not taken", {
  one <- function(nm, ctx = .moll, gmt = TRUE) {
    r <- build_taxon_registry(.names(nm, "r2", context = ctx), run_id = "bv4", lookup = .binvar_lk(gmt))
    c(r$names$taxon_id, r$names$status)
  }
  expect_identical(one("Pyrogophorus platyrachis", NA_character_), c("local:Pyrogophorus platyrachis", "fuzzy_rejected"))
  expect_identical(one("Pyrogophorus platyrachis", "Animalia|Chordata"), c("local:Pyrogophorus platyrachis", "fuzzy_rejected"))
  expect_identical(one("Pyrogophorus coronatus"), c("local:Pyrogophorus coronatus", "fuzzy_rejected"))       # GBIF said FUZZY
  expect_identical(one("Pyrogophorus platyrachus"), c("local:Pyrogophorus platyrachus", "fuzzy_rejected"))   # epithet differs too
  expect_identical(one("Pyrogophorus platyrachis", gmt = FALSE), c("local:Pyrogophorus platyrachis", "fuzzy_rejected"))
  r0 <- build_taxon_registry(.names("Pyrogophorus platyrachis", "r2"), run_id = "bv5", lookup = .binvar_lk())
  expect_identical(r0$meta$genus_variant_rejected$reason, "no lineage context")
})

# Tie-break fixtures. The live case: the CI pool holds Tetraclita rubescens under two GBIF species keys
# (2115806, 9188200); GBIF's species/match answers 9188200. Lineages here are synthetic: the two candidates
# differ only in family, so only an authority naming one of those families can decide.
.tk7 <- "kingdom|phylum|class|order|family|genus|species"
.tetra_lk <- function() .fake_lookup(.row("Tetraclita rubescens", "Tetraclita rubescens", "9188200", "1|18|300|400|500|600|9188200",
  "Animalia|Arthropoda|Thecostraca|Balanomorpha|Tetraclitidae|Tetraclita|Tetraclita rubescens", ranks = .tk7))
.tetra_pool <- function(fam = c("Balanidae", "Tetraclitidae")) data.frame(verbatim_name = "Tetraclita rubescens",
  species_key = c("2115806", "9188200"), kingdom = "Animalia", phylum = "Arthropoda", class = "Thecostraca", order = "Balanomorpha",
  family = fam, genus = "Tetraclita", stringsAsFactors = FALSE)
.lin <- function(fam) function(name) paste("cellular organisms|Eukaryota|Metazoa|Arthropoda|Crustacea|Thecostraca|Balanomorpha", fam, "Tetraclita", sep = "|")
.tb_reg <- function(tiebreak, pool = .tetra_pool()) build_taxon_registry(.names("Tetraclita rubescens", "r2"), run_id = "tb",
  pool_keys = pool, lookup = .tetra_lk(), tiebreak = tiebreak)

test_that("tie-break off (default): a name the pool holds under 2 keys stays an error, as before", {
  reg <- .tb_reg(NULL)
  expect_identical(reg$names$taxon_id, "gbif:9188200")                       # the lookup's id; not keyed from the pool
  expect_null(reg$meta$pool_key_tiebreaks)
  expect_error(check_taxon_registry(reg, mode = "error", verbose = FALSE), "pool_key_ambiguous")
})

test_that("step 0: GBIF's own match, when it is exactly one of the candidates, decides; the finding becomes info", {
  reg <- .tb_reg(list())                                                     # gbif_first defaults to TRUE
  expect_identical(c(reg$names$taxon_id, reg$names$status, reg$names$backend), c("gbif:9188200", "pool_key_tiebreak", "tiebreak:gbif"))
  expect_null(reg$meta$pool_key_ambiguous)
  expect_identical(reg$meta$pool_key_tiebreaks$kind, "pool_key_ambiguous")   # one row: no spurious conflict from a first pick
  chk <- check_taxon_registry(reg, verbose = FALSE)
  expect_identical(chk$severity[chk$kind == "pool_key_tiebroken"], "info")
  expect_false(any(chk$kind == "pool_key_ambiguous"))
  expect_silent(check_taxon_registry(reg, mode = "error", verbose = FALSE))
})

test_that("GUARD CAN FAIL: NCBI decides by the candidates' DISTINGUISHING terms, even against GBIF's match when step 0 is off", {
  reg <- .tb_reg(list(gbif_first = FALSE, authorities = list(ncbi = .lin("Balanidae"), worms = .lin("Tetraclitidae"))))
  expect_identical(c(reg$names$taxon_id, reg$names$backend), c("gbif:2115806", "tiebreak:ncbi"))   # NCBI first, and it names Balanidae
  expect_identical(nrow(reg$meta$pool_key_tiebreaks), 1L)
  expect_true(is.na(reg$names$accepted_lookup))                              # the lookup's name belonged to the other id
  expect_true("gbif:2115806" %in% reg$taxa$taxon_id)
})

test_that("an authority with no answer passes to the next (NCBI silent -> WoRMS decides)", {
  reg <- .tb_reg(list(gbif_first = FALSE, authorities = list(ncbi = function(name) NA_character_, worms = .lin("Tetraclitidae"))))
  expect_identical(c(reg$names$taxon_id, reg$names$backend), c("gbif:9188200", "tiebreak:worms"))
  expect_identical(nrow(reg$meta$pool_key_tiebreaks), 1L)   # a decided ambiguous name is not re-keyed by a first pick (no 2nd, conflict row)
  expect_match(reg$meta$pool_key_tiebreaks$detail, "ncbi: no answer", fixed = TRUE)
})

test_that("GUARD CAN FAIL: identical candidate lineages, or an authority naming both, are NOT decided; the error stays", {
  same <- .tb_reg(list(gbif_first = FALSE, authorities = list(ncbi = .lin("Tetraclitidae"))), pool = .tetra_pool(c("Tetraclitidae", "Tetraclitidae")))
  expect_true(is.na(same$meta$pool_key_tiebreaks$chosen))
  expect_false(identical(same$names$status, "pool_key_tiebreak"))
  expect_error(check_taxon_registry(same, mode = "error", verbose = FALSE), "pool_key_ambiguous")
  expect_true(any(check_taxon_registry(same, verbose = FALSE)$kind == "pool_key_tiebreak_undecided"))
  both <- .tb_reg(list(gbif_first = FALSE, authorities = list(ncbi = function(name) "Arthropoda|Balanidae|Tetraclitidae")))
  expect_true(is.na(both$meta$pool_key_tiebreaks$chosen))
  expect_match(both$meta$pool_key_tiebreaks$detail, "not decided (scores 1/1)", fixed = TRUE)
  nolin <- .tb_reg(list(gbif_first = FALSE, authorities = list(ncbi = .lin("Balanidae"))), pool = .tetra_pool()[, c("verbatim_name", "species_key")])
  expect_true(is.na(nolin$meta$pool_key_tiebreaks$chosen))                   # a candidate with no lineage: never decided by lineage
})

test_that("GUARD CAN FAIL: step 0 never settles a pool_key_conflict (it would always pick the lookup); authorities can", {
  lk <- .fake_lookup(.row("Pachycheles holosericus", "Pachycheles holosericus", "5000", "1|18|300|400|501|601|5000",
                          "Animalia|Arthropoda|Malacostraca|Decapoda|Porcellanidae|Pachycheles|Pachycheles holosericus", ranks = .tk7))
  pool <- data.frame(verbatim_name = "Pachycheles holosericus", species_key = "11156704", kingdom = "Animalia", phylum = "Arthropoda",
                     class = "Malacostraca", order = "Decapoda", family = "Paguridae", genus = "Pachycheles", stringsAsFactors = FALSE)
  .pc <- function(tb) build_taxon_registry(.names("Pachycheles holosericus", "r2"), run_id = "c", pool_keys = pool, lookup = lk, tiebreak = tb)
  for (tb in list(NULL, list(), list(gbif_first = TRUE))) {          # off, and step 0 with no authorities: the conflict stays
    reg <- .pc(tb)
    expect_identical(c(reg$names$taxon_id, reg$names$status), c("gbif:11156704", "pool_key_conflict"))
    expect_error(check_taxon_registry(reg, mode = "error", verbose = FALSE), "pool_key_conflict")
  }
  expect_true(is.na(.pc(list())$meta$pool_key_tiebreaks$chosen))
  on <- .pc(list(authorities = list(ncbi = function(name) "Metazoa|Arthropoda|Malacostraca|Decapoda|Porcellanidae|Pachycheles")))
  expect_identical(c(on$names$taxon_id, on$names$status, on$names$backend, on$names$accepted_lookup),
                   c("gbif:5000", "pool_key_tiebreak", "tiebreak:ncbi", "Pachycheles holosericus"))
  chk <- check_taxon_registry(on, verbose = FALSE)
  expect_false(any(chk$kind == "pool_key_conflict"))
  expect_true(any(chk$kind == "pool_key_tiebroken" & grepl("pool_key_conflict", chk$detail)))
  pool_side <- .pc(list(authorities = list(ncbi = function(name) "Metazoa|Arthropoda|Paguridae")))
  expect_identical(pool_side$names$taxon_id, "gbif:11156704")             # NCBI naming the pool key's family keeps the pool key
  expect_identical(pool_side$names$status, "pool_key_tiebreak")
})

test_that("a malformed tiebreak is refused", {
  expect_error(.tb_reg("ncbi"), "tiebreak")
  expect_error(.tb_reg(list(authorities = list(function(name) NA))), "named list")
})

test_that("taxon_in asks membership of ids, never names, and NA is never a member", {
  expect_identical(taxon_in(c("gbif:1", NA, "gbif:3"), c("gbif:1", NA)), c(TRUE, FALSE, FALSE))
  expect_error(taxon_in(1, "gbif:1"), "character")
})

test_that("bad inputs are refused", {
  expect_error(build_taxon_registry(data.frame(x = 1), run_id = "r"), "verbatim_name")
  expect_error(build_taxon_registry(.names("A b", "t"), run_id = ""), "run_id")
  expect_error(build_taxon_registry(.names("A b", "t"), run_id = "r", lookup = function(...) data.frame(a = 1)), "lookup")
})

# ==== Package review 2026-11-13 (REVIEW_package_taxon_registry): each test below encodes a reviewer's failure scenario
# ==== and FAILS on the code it reviewed (2ea632dc); the fix commit for each finding names its test.

# -- F1: the unresolved-name pass took a genus id by NAME with no context ---------------------------------------
# GBIF's only Vertebrata is the red-alga genus (see test-verify_taxon_names_ids.R). An animal "Vertebrata foo" must
# not be hung under it; the genus lookup must be asked WITH the names' context; two homonymous genus rows already in
# taxa must not be chosen between by match()'s first pick; a homonym_rejected name never takes a congener's id.
.vert_alga <- .row("Vertebrata", "Vertebrata", "2680000", "6|106|342|900|901|2680000", "Plantae|Rhodophyta|Florideophyceae|Ceramiales|Rhodomelaceae|Vertebrata",
                   ranks = .gk, rank = "genus", mt = "Exact")
test_that("REVIEW F1a: an EXACT genus answer outside the names' kingdom/phylum is refused, and the lookup gets the context", {
  ctx_seen <- character(0)
  lk0 <- .fake_lookup(.vert_alga)
  lk <- function(names, rank, context) { if (any(rank %in% "genus")) ctx_seen <<- c(ctx_seen, context[rank %in% "genus"]); lk0(names, rank, context) }
  reg <- build_taxon_registry(.names("Vertebrata foo", "r2", context = "Animalia|Chordata"), run_id = "f1a", lookup = lk)
  expect_false(grepl("2680000", reg$names$taxon_id))                          # 2ea632dc: local:2680000:foo, under the alga
  expect_identical(reg$names$taxon_id, "local:Vertebrata foo")
  expect_true(is.na(parent_at(reg$names$taxon_id, "phylum", reg)))
  expect_identical(ctx_seen, "Animalia|Chordata")                             # 2ea632dc: NA
  expect_true(any(check_taxon_registry(reg, verbose = FALSE)$kind == "genus_variant_rejected"))
  # no context: an EXACT answer is taken as before
  r0 <- build_taxon_registry(.names("Vertebrata foo", "r2"), run_id = "f1a0", lookup = lk)
  expect_identical(r0$names$taxon_id, "local:2680000:foo")
})

test_that("REVIEW F1b: two homonymous genus rows in taxa are not chosen between by a first pick; a context that fits one chooses it", {
  lk <- .fake_lookup(rbind(
    .row("Agathis robusta", "Agathis robusta", "2685701", "6|7707728|194|640|3925|2685700|2685701",
         "Plantae|Tracheophyta|Pinopsida|Pinales|Araucariaceae|Agathis|Agathis robusta", ranks = .s7),
    .row("Agathis montana", "Agathis montana", "1300001", "1|54|216|1457|6658|1300000|1300001",
         "Animalia|Arthropoda|Insecta|Hymenoptera|Braconidae|Agathis|Agathis montana", ranks = .s7)))
  nm <- rbind(.names(c("Agathis robusta", "Agathis montana", "Agathis foo"), "r2", context = NA_character_),
              .names("Agathis bar", "r2", context = "Plantae|Tracheophyta"))
  reg <- build_taxon_registry(nm, run_id = "f1b", lookup = lk)
  id <- stats::setNames(reg$names$taxon_id, reg$names$verbatim_name)
  expect_identical(unname(id["Agathis foo"]), "local:Agathis foo")           # 2ea632dc: local:<first genus row>:foo
  expect_true(any(check_taxon_registry(reg, verbose = FALSE)$kind == "genus_homonym_unresolved"))
  expect_identical(unname(id["Agathis bar"]), "local:2685700:bar")           # the context names the conifer's lineage
})

test_that("REVIEW F1c: a homonym_rejected binomial never takes a resolved congener's id by the gender rule", {
  base <- .fake_lookup(.row("Vertebrata lanosa", "Vertebrata lanosa", "2680001", "6|106|342|900|901|2680000|2680001",
                            "Plantae|Rhodophyta|Florideophyceae|Ceramiales|Rhodomelaceae|Vertebrata|Vertebrata lanosa", ranks = .s7))
  lk <- function(names, rank, context) {
    o <- base(names, rank, context)
    g <- names %in% "Vertebrata lanosus"                                      # the lineage gate refused the alga for the animal name
    o$verified[g] <- FALSE; o$match_type[g] <- "LineageRejected"; o$matched[g] <- FALSE
    o
  }
  reg <- build_taxon_registry(rbind(.names("Vertebrata lanosa", "r2", context = NA_character_), .names("Vertebrata lanosus", "r2", context = "Animalia|Chordata")),
                              run_id = "f1c", lookup = lk)
  ln <- reg$names[reg$names$verbatim_name == "Vertebrata lanosus", ]
  expect_false(identical(ln$taxon_id, "gbif:2680001"))                       # 2ea632dc: gender_variant onto the alga
  expect_false(identical(ln$status, "gender_variant"))
})

# -- F2: only binomials were checked for a coarser-rank answer ----------------------------------------------------
test_that("REVIEW F2: a uninomial, or a name ASKED at subspecies, answered at a coarser rank is rank_fallback, not accepted", {
  # clean_taxon_names() reduces "Hypsurus caryi foo" to the binomial "Hypsurus caryi" BEFORE the lookup (long-standing
  # v1.0 behaviour; a question for Kevin, not changed here), so the lookup row is keyed on the cleaned name and the
  # subspecies is caught only through rank_given. (This half was first written keyed on the 3-word string, which the
  # cleaned name never matched: it failed under every code version without testing F2. Corrected after Run B.)
  lk <- .fake_lookup(rbind(
    .row("Notagenus", "Embiotocidae", "4269", "1|44|587|4269", "Animalia|Chordata|Perciformes|Embiotocidae", ranks = "kingdom|phylum|order|family", rank = "family"),
    .row("Hypsurus caryi", "Hypsurus caryi", "2389310", "1|44|587|4269|2389309|2389310",
         "Animalia|Chordata|Perciformes|Embiotocidae|Hypsurus|Hypsurus caryi", rank = "species")))
  reg <- build_taxon_registry(rbind(.names("Notagenus", "r2", rank_given = "genus"), .names("Hypsurus caryi foo", "r2", rank_given = "subspecies")),
                              run_id = "f2", lookup = lk)
  n <- reg$names[match(c("Notagenus", "Hypsurus caryi foo"), reg$names$verbatim_name), ]
  expect_identical(n$status, c("rank_fallback", "rank_fallback"))             # 2ea632dc: accepted, accepted
  expect_identical(n$taxon_id, c("local:Notagenus", "local:2389309:caryi"))    # 2ea632dc: gbif:4269, gbif:2389310
  expect_identical(reg$taxa$parent_id[match(n$taxon_id, reg$taxa$taxon_id)], c("gbif:4269", "gbif:2389309"))
  # rank asked inferred from the name when not given: one word = genus
  r1 <- build_taxon_registry(.names("Notagenus", "r2"), run_id = "f2b", lookup = lk)
  expect_identical(r1$names$status, "rank_fallback")
  # KNOWN BEHAVIOUR, recorded not fixed: with no rank_given, the cleaned subspecies name IS its species
  r2 <- build_taxon_registry(.names("Hypsurus caryi foo", "r2"), run_id = "f2c", lookup = lk)
  expect_identical(c(r2$names$name_clean, r2$names$status, r2$names$taxon_id), c("Hypsurus caryi", "accepted", "gbif:2389310"))
})

# -- F3: the tie-break counted a rank one candidate lacks as evidence ---------------------------------------------
test_that("REVIEW F3: only ranks EVERY candidate has, with differing values, decide; a fuller lineage does not win on missing data", {
  lk <- .fake_lookup(.row("Pachycheles holosericus", "Pachycheles holosericus", "5000", "1|18|300|400|501|601|5000",
                          "Animalia|Arthropoda|Malacostraca|Decapoda|Porcellanidae|Pachycheles|Pachycheles holosericus", ranks = .tk7))
  pool <- data.frame(verbatim_name = "Pachycheles holosericus", species_key = "11156704", family = "Paguridae", genus = "Pachycheles",
                     stringsAsFactors = FALSE)                               # only family and genus columns
  ncbi <- function(name) "Metazoa|Arthropoda|Malacostraca|Decapoda|Paguridae|Pachycheles"
  reg <- build_taxon_registry(.names("Pachycheles holosericus", "r2"), run_id = "f3", pool_keys = pool, lookup = lk,
                              tiebreak = list(authorities = list(ncbi = ncbi)))
  expect_identical(reg$meta$pool_key_tiebreaks$chosen, "gbif:11156704")       # 2ea632dc: gbif:5000 (scores 1/3 on missing ranks)
  # no rank that both have and that differs: undecided
  reg2 <- build_taxon_registry(.names("Pachycheles holosericus", "r2"), run_id = "f3b", pool_keys = pool[, c("verbatim_name", "species_key", "genus")],
                               lookup = lk, tiebreak = list(authorities = list(ncbi = ncbi)))
  expect_true(is.na(reg2$meta$pool_key_tiebreaks$chosen))                    # 2ea632dc: gbif:5000
  expect_error(check_taxon_registry(reg2, mode = "error", verbose = FALSE), "pool_key_conflict")
})

# -- F4: a custom lookup missing columns gave silent wrong statuses -----------------------------------------------
test_that("REVIEW F4: a lookup missing verified, matched, matched_rank, is_synonym or match_type is refused, never guessed", {
  base <- .fake_lookup(rbind(
    .row("Embiotoca caryi", "Hypsurus caryi", "2389310", "1|44|587|4269|2389309|2389310", "Animalia|Chordata|Perciformes|Embiotocidae|Hypsurus|Hypsurus caryi",
         rec = "2389311", syn = TRUE),
    .row("Hypsurus caryi", "Hypsurus caryi", "2389310", "1|44|587|4269|2389309|2389310", "Animalia|Chordata|Perciformes|Embiotocidae|Hypsurus|Hypsurus caryi")))
  for (col in c("verified", "matched", "matched_rank", "is_synonym", "match_type")) {
    lk <- local({ cc <- col; function(names, rank, context) { o <- base(names, rank, context); o[[cc]] <- NULL; o } })
    # The condition is CAUGHT, not passed to expect_error(): testthat 3e re-raises a non-matching error, so an incidental
    # crash in the reviewed code (it crashed on a missing `matched`) showed as a test ERROR, not a failure. The fix
    # must refuse with its own classed condition naming the column; anything else fails here by assertion.
    e <- tryCatch(build_taxon_registry(.names(c("Embiotoca caryi", "Hypsurus caryi"), "r2"), run_id = "f4", lookup = lk),
                  error = function(e) e)
    expect_s3_class(e, "taxon_registry_bad_lookup")
    expect_match(if (inherits(e, "condition")) conditionMessage(e) else "", col, fixed = TRUE, info = col)
  }
})

# -- F5: join_by_taxon joined NA ids to each other ----------------------------------------------------------------
test_that("REVIEW F5: an NA taxon_id never joins to another NA, and no-partner counts ignore NA keys' false matches", {
  .mock_gnv_reg()
  reg <- freeze_taxon_registry(.caryi_reg())
  m <- attach_taxon_ids(data.frame(observation_id = c("o1", "o2"), taxon_name = c("Embiotoca caryi", NA)), reg, "taxon_name", "match")
  p <- attach_taxon_ids(data.frame(taxon_name = c("Hypsurus caryi", ""), prior = c(0.3, 0.9)), reg, "taxon_name", "priors")
  expect_true(is.na(m$taxon_id[2]) && is.na(p$taxon_id[2]))
  j <- suppressMessages(join_by_taxon(m, p, "left"))
  expect_identical(nrow(j), 2L)
  expect_true(is.na(j$prior[j$observation_id == "o2"]))                      # 2ea632dc: 0.9 (NA matched NA)
  expect_identical(nrow(suppressMessages(join_by_taxon(m, p, "inner"))), 1L)
  expect_identical(nrow(suppressMessages(join_by_taxon(m, p, "semi"))), 1L)
  expect_identical(nrow(suppressMessages(join_by_taxon(m, p, "anti"))), 1L)
  expect_identical(attr(j, "no_partner")[["x_rows"]], 1L)                   # 2ea632dc: 0
})

# -- F6 (+ N6): docs that no longer described the code, and a dated roxygen line ----------------------------------
test_that("REVIEW F6: build_taxon_registry's docs no longer claim a fuzzy answer survives as status 'fuzzy'; no dated roxygen", {
  src <- testthat::test_path("..", "..", "R", "taxon_registry.R"); rd <- testthat::test_path("..", "..", "man", "build_taxon_registry.Rd")
  if (!file.exists(src) || !file.exists(rd)) testthat::skip("R/ and man/ not found next to this package (source layout unavailable here)")
  txt <- c(readLines(src, warn = FALSE), readLines(rd, warn = FALSE))
  expect_false(any(grepl('kept as \\code{status = "fuzzy"}', txt, fixed = TRUE)))   # 2ea632dc: present in R and Rd
  expect_false(any(grepl("^#'.*20[0-9]{2}-[0-9]{2}-[0-9]{2}", readLines(src, warn = FALSE))))   # 2ea632dc: "(Kevin, 2026-11-13: ...)"
})
