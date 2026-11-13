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
    tk0 <- paste(tbl$q, "", sep = "\r")
    i <- match(k, tk); i[is.na(i)] <- match(k[is.na(i)], tk0)
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

test_that("NEGATIVE: a planted undeclared merge (a fuzzy hit onto another species) is an error-class finding", {
  lk <- .fake_lookup(rbind(
    .row("Foo baz", "Foo baz", "400", "1|2|3|4|5|400", "Animalia|Chordata|Perciformes|Fooidae|Foo|Foo baz"),
    .row("Foo bar", "Foo baz", "400", "1|2|3|4|5|400", "Animalia|Chordata|Perciformes|Fooidae|Foo|Foo baz", mt = "Fuzzy")))
  reg <- build_taxon_registry(.names(c("Foo baz", "Foo bar"), "match"), run_id = "n3", lookup = lk)
  chk <- check_taxon_registry(reg, verbose = FALSE)
  expect_true(any(chk$kind == "undeclared_merge" & chk$taxon_id == "gbif:400"))
  expect_error(check_taxon_registry(reg, mode = "error", verbose = FALSE), "undeclared_merge")
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

test_that("GUARD CAN FAIL: a missing stamp, and a table lineage that contradicts the registry (Carcharodon under Alopiidae)", {
  lk <- .fake_lookup(.row("Carcharodon carcharias", "Carcharodon carcharias", "500", "1|44|900|901|902|500",
                          "Animalia|Chordata|Lamniformes|Lamnidae|Carcharodon|Carcharodon carcharias"))
  reg <- freeze_taxon_registry(build_taxon_registry(.names("Carcharodon carcharias", "r2"), run_id = "g2", lookup = lk))
  t <- attach_taxon_ids(data.frame(observation_id = c("a", "b"), taxon_name = "Carcharodon carcharias", family = c("Lamnidae", "Alopiidae")),
                        reg, "taxon_name", "r2")
  chk <- check_taxon_registry(reg, tables = list(r2 = t, raw = data.frame(taxon_name = "x")), verbose = FALSE)
  expect_true(any(chk$kind == "lineage_disagrees" & chk$n == 1L))
  expect_true(any(chk$kind == "missing_stamp" & chk$table == "raw"))
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
