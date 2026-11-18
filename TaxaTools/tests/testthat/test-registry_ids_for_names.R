# registry_ids_for_names(): the one check every registry = argument runs (class, frozen, unedited since the freeze,
# tables stamped by it), and the three name-to-id rules its callers use. Offline: synthetic GBIF-shaped answers.

.rif_lookup <- function(names, rank, context) {
  t <- data.frame(
    q = c("Embiotoca caryi", "Hypsurus caryi", "Embiotoca jacksoni", "Agathis", "Agathis"),
    ctx = c(NA, NA, NA, "Plantae", "Animalia"),
    matched = c("Hypsurus caryi", "Hypsurus caryi", "Embiotoca jacksoni", "Agathis", "Agathis"),
    rank = c("species", "species", "species", "genus", "genus"),
    path = c("Animalia|Chordata|Embiotocidae|Hypsurus|Hypsurus caryi", "Animalia|Chordata|Embiotocidae|Hypsurus|Hypsurus caryi",
             "Animalia|Chordata|Embiotocidae|Embiotoca|Embiotoca jacksoni", "Plantae|Tracheophyta|Araucariaceae|Agathis",
             "Animalia|Arthropoda|Braconidae|Agathis"),
    ranks = c("kingdom|phylum|family|genus|species", "kingdom|phylum|family|genus|species", "kingdom|phylum|family|genus|species",
              "kingdom|phylum|family|genus", "kingdom|phylum|family|genus"),
    ids = c("1|44|400|410|411", "1|44|400|410|411", "1|44|400|420|421", "6|7707728|3925|2684"  , "1|54|6650|1394"),
    cur = c("411", "411", "421", "2684", "1394"), rec = c("412", "411", "421", "2684", "1394"), syn = c(TRUE, FALSE, FALSE, FALSE, FALSE),
    stringsAsFactors = FALSE)
  k <- paste(names, ifelse(is.na(context), "", context)); tk <- paste(t$q, ifelse(is.na(t$ctx), "", t$ctx))
  i <- match(k, tk); i[is.na(i)] <- match(names[is.na(i)], t$q[is.na(t$ctx)]); hit <- !is.na(i)
  data.frame(user_supplied_name = names, matched_name = ifelse(hit, t$matched[i], NA), matched_rank = ifelse(hit, t$rank[i], NA),
             is_synonym = ifelse(hit, t$syn[i], NA), classification_path = ifelse(hit, t$path[i], NA),
             classification_ranks = ifelse(hit, t$ranks[i], NA), score = NA_real_, verified = TRUE, matched = hit,
             record_id = ifelse(hit, t$rec[i], NA), current_record_id = ifelse(hit, t$cur[i], NA),
             classification_ids = ifelse(hit, t$ids[i], NA), data_source_id = 11L, entry_date = "2024-01-11",
             match_type = ifelse(hit, "Exact", NA), stringsAsFactors = FALSE)
}
.rif_registry <- function(run_id = "rif") {
  nm <- data.frame(verbatim_name = c("Embiotoca caryi", "Hypsurus caryi", "Embiotoca jacksoni", "Agathis", "Agathis"),
                   source_table = c("match", "priors", "priors", "match", "priors"),
                   rank_given = c("species", "species", "species", "genus", "genus"),
                   context = c(NA, NA, NA, "Plantae", "Animalia"), stringsAsFactors = FALSE)
  freeze_taxon_registry(suppressMessages(suppressWarnings(build_taxon_registry(nm, run_id = run_id, lookup = .rif_lookup))))
}
.rif_edit <- function(reg) {   # one name's id changed after the freeze: the content no longer matches the digest
  reg$names$taxon_id[reg$names$verbatim_name == "Embiotoca caryi"] <- reg$names$taxon_id[reg$names$verbatim_name == "Embiotoca jacksoni"][1]
  reg
}

test_that("fixture: Agathis is held under two ids (two kingdoms); Embiotocidae is an accepted name no table registered", {
  reg <- .rif_registry()
  expect_length(unique(reg$names$taxon_id[reg$names$verbatim_name == "Agathis"]), 2L)
  expect_false("Embiotocidae" %in% reg$names$verbatim_name)
  expect_true("Embiotocidae" %in% reg$taxa$name)
})

test_that("the checks: not a registry, not frozen, edited after the freeze, an unstamped table, another registry's stamp", {
  reg <- .rif_registry()
  expect_error(registry_ids_for_names("x", list()), class = "taxon_registry_invalid")
  open_reg <- suppressMessages(suppressWarnings(build_taxon_registry(data.frame(verbatim_name = "Hypsurus caryi", source_table = "priors"),
                                                                     run_id = "open", lookup = .rif_lookup)))
  expect_error(registry_ids_for_names("x", open_reg), "frozen", class = "taxon_registry_invalid")
  expect_error(registry_ids_for_names("x", .rif_edit(reg)), "edited after", class = "taxon_registry_invalid")
  expect_error(registry_ids_for_names(NULL, .rif_edit(reg)), "edited after", class = "taxon_registry_invalid")
  expect_error(registry_ids_for_names(NULL, reg, tables = list(priors = data.frame(taxon_name = "Hypsurus caryi"))),
               "no taxon_id column or no registry stamp", class = "taxon_registry_invalid")
  other <- .rif_registry("another-run")
  st <- attach_taxon_ids(data.frame(taxon_name = "Hypsurus caryi"), other, "taxon_name", "priors")
  expect_false(identical(other$meta$digest, reg$meta$digest))
  expect_error(registry_ids_for_names(NULL, reg, tables = list(priors = st)), "different registry", class = "taxon_registry_invalid")
  expect_error(registry_ids_for_names(NULL, reg, caller = "f"), NA)
  expect_error(registry_ids_for_names(NULL, .rif_edit(reg), caller = "my_fn"), "^my_fn: ")
  ok <- attach_taxon_ids(data.frame(taxon_name = "Hypsurus caryi"), reg, "taxon_name", "priors")
  expect_identical(registry_ids_for_names(NULL, reg, tables = list(priors = ok)), character(0))
})

test_that("resolve = 'names': the name table only; a name under two ids, or not registered, is NA and listed", {
  reg <- .rif_registry(); id <- function(n) unique(reg$names$taxon_id[reg$names$verbatim_name == n])
  out <- registry_ids_for_names(c("Embiotoca caryi", "Agathis", "Embiotocidae", NA, "Embiotoca caryi"), reg)
  expect_identical(as.vector(out), c(id("Embiotoca caryi"), NA, NA, NA, id("Embiotoca caryi")))
  expect_identical(id("Embiotoca caryi"), id("Hypsurus caryi"))      # the synonym and its accepted name: one taxon
  expect_setequal(attr(out, "unresolved"), c("Agathis", "Embiotocidae"))
})

test_that("resolve = 'names_then_accepted': name table, then accepted names, a rank narrows; 'names_or_accepted': one id across both", {
  reg <- .rif_registry(); fam <- reg$taxa$taxon_id[reg$taxa$name == "Embiotocidae"]
  a <- registry_ids_for_names(c("Embiotocidae", "Agathis", "Agathis"), reg, resolve = "names_then_accepted", ranks = c(NA, NA, "genus"))
  expect_identical(as.vector(a)[1], fam)
  expect_true(all(is.na(as.vector(a)[2:3])))                     # both Agathis ids are genera: the rank does not narrow
  b <- registry_ids_for_names(c("Embiotocidae", "Agathis", "Hypsurus caryi"), reg, resolve = "names_or_accepted")
  expect_identical(as.vector(b)[1], fam)
  expect_true(is.na(as.vector(b)[2]))
  expect_identical(as.vector(b)[3], unique(reg$names$taxon_id[reg$names$verbatim_name == "Hypsurus caryi"]))
})
