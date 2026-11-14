# lookup_gbif_taxa(): GBIF backbone answers in verify_taxon_names(return_ids = TRUE) shape, for the
# taxon registry. Offline: rgbif::name_backbone / name_lookup are mocked with records shaped like
# rgbif's (named list of scalars; an absent field is ABSENT). Keys as in GBIF's Backbone (r15 crosswalk).

.accepted_hypsurus <- list(usageKey = 2389310L, matchType = "EXACT", rank = "SPECIES", status = "ACCEPTED", synonym = FALSE,
  canonicalName = "Hypsurus caryi", kingdom = "Animalia", phylum = "Chordata", order = "Perciformes", family = "Embiotocidae",
  genus = "Hypsurus", species = "Hypsurus caryi", kingdomKey = 1L, phylumKey = 44L, orderKey = 587L, familyKey = 4269L,
  genusKey = 2389309L, speciesKey = 2389310L)
# A SYNONYM record that carries NO synonym flag: status and accepted key state the synonymy, the flag is absent.
# The rule p5 used (synonym flag alone) files this as accepted; this fixture is chosen to break that rule.
.synonym_no_flag <- list(usageKey = 2389311L, acceptedUsageKey = 2389310L, matchType = "EXACT", rank = "SPECIES",
  status = "SYNONYM", canonicalName = "Embiotoca caryi", kingdom = "Animalia", phylum = "Chordata", order = "Perciformes",
  family = "Embiotocidae", genus = "Hypsurus", species = "Hypsurus caryi", kingdomKey = 1L, phylumKey = 44L, orderKey = 587L,
  familyKey = 4269L, genusKey = 2389309L, speciesKey = 2389310L)
# synonymy stated ONLY by the accepted key (no flag, no status)
.synonym_key_only <- within(.synonym_no_flag, { status <- NULL; canonicalName <- "Embiotoca caryi" })
.higherrank_genus <- list(usageKey = 9460134L, matchType = "HIGHERRANK", rank = "GENUS", status = "ACCEPTED", synonym = FALSE,
  canonicalName = "Gelidium", kingdom = "Plantae", phylum = "Rhodophyta", class = "Florideophyceae", order = "Gelidiales",
  family = "Gelidiaceae", genus = "Gelidium", kingdomKey = 6L, phylumKey = 106L, classKey = 342L, orderKey = 900L,
  familyKey = 901L, genusKey = 9460134L)
.fuzzy <- within(.accepted_hypsurus, matchType <- "FUZZY")
# PROVISIONALLY_ACCEPTED with its accepted key equal to its own (206 live records were this): its own taxon, NOT a synonym.
# A rule of "status != ACCEPTED" calls it a synonym; this fixture breaks that rule.
.provisional <- within(.accepted_hypsurus, { status <- "PROVISIONALLY_ACCEPTED"; synonym <- NULL; acceptedUsageKey <- 2389310L })
# VARIANT: GBIF matched a known orthographic variant (live: "Pyrogophorus" -> Pyrgophorus 2299855). Under the old rule
# (EXACT/FUZZY/HIGHERRANK only) this genus answer was unmatched, so names under it got plain local ids.
.variant_genus <- list(usageKey = 2299855L, matchType = "VARIANT", rank = "GENUS", status = "ACCEPTED",
  canonicalName = "Pyrgophorus", kingdom = "Animalia", phylum = "Mollusca", class = "Gastropoda", family = "Cochliopidae",
  genus = "Pyrgophorus", kingdomKey = 1L, phylumKey = 52L, classKey = 225L, familyKey = 2299800L, genusKey = 2299855L)
.variant_species <- within(.accepted_hypsurus, matchType <- "VARIANT")

.backbone <- function(name, ...) switch(name,
  "Hypsurus caryi" = .accepted_hypsurus, "Embiotoca caryi" = .synonym_no_flag, "Embiotoca keyonly" = .synonym_key_only,
  "Gelidium kathyanniae" = .higherrank_genus, "Hypsurus cari" = .fuzzy, "Hypsurus provisional" = .provisional, "Pyrogophorus" = .variant_genus, "Hypsurus karyi" = .variant_species,
  "Notagenus" = list(usageKey = 1L, matchType = "HIGHERRANK", rank = "KINGDOM", kingdom = "Animalia", kingdomKey = 1L),
  "Failname" = stop("HTTP 503"),
  list(matchType = "NONE", confidence = 100L))
.lookup <- function(...) list(data = data.frame(rank = "GENUS", nubKey = 777L, kingdom = "Animalia", stringsAsFactors = FALSE))

test_that("a SYNONYM record with no synonym flag is a synonym; the flag-only rule would have called it accepted", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(name_backbone = .backbone, .package = "rgbif")
  g <- suppressMessages(suppressWarnings(get_keys_from_context(data.frame(species = "Embiotoca caryi"), return_keys = TRUE)))
  expect_false(isTRUE(g$gbif_synonym))                     # the old rule's input: it reads accepted here
  x <- suppressMessages(lookup_gbif_taxa("Embiotoca caryi"))
  expect_true(x$is_synonym)
  expect_identical(x$record_id, "2389311")                 # its own record
  expect_identical(x$current_record_id, "2389310")         # its accepted record
  expect_identical(x$matched_name, "Hypsurus caryi")       # the accepted name, not the synonym's own
  expect_identical(x$gbif_status, "SYNONYM")
})

test_that("synonymy stated only by an accepted key different from the record's own key is still a synonym", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(name_backbone = .backbone, .package = "rgbif")
  x <- suppressMessages(lookup_gbif_taxa("Embiotoca keyonly"))
  expect_true(is.na(x$gbif_status))
  expect_true(x$is_synonym)
  expect_identical(x$current_record_id, "2389310")
})

test_that("an accepted record is not a synonym, and its own key is its accepted key", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(name_backbone = .backbone, .package = "rgbif")
  x <- suppressMessages(lookup_gbif_taxa("Hypsurus caryi"))
  expect_false(x$is_synonym)
  expect_identical(x$record_id, x$current_record_id)
  expect_identical(x$match_type, "Exact")
  expect_identical(x$classification_ranks, "kingdom|phylum|order|family|genus|species")
  expect_identical(x$classification_ids, "1|44|587|4269|2389309|2389310")
  expect_identical(x$data_source_id, 11L)
})

test_that("unit: .lgt_is_synonym reads each of the three fields, and none of them means accepted", {
  expect_identical(.lgt_is_synonym(c(TRUE, NA, NA, FALSE, NA), c(NA, "SYNONYM", NA, "ACCEPTED", NA),
                                   c(NA, NA, 5L, NA, NA), c(1L, 1L, 1L, 1L, 1L)),
                   c(TRUE, TRUE, TRUE, FALSE, FALSE))
  expect_true(.lgt_is_synonym(NA, "HETEROTYPIC_SYNONYM", NA_integer_, 1L))
  expect_false(.lgt_is_synonym(FALSE, "ACCEPTED", 1L, 1L))   # accepted key equal to its own: accepted
  expect_identical(.lgt_is_synonym(NA, c("PROVISIONALLY_ACCEPTED", "DOUBTFUL", "PROPARTE_SYNONYM", "MISAPPLIED", "HOMOTYPIC_SYNONYM"),
                                   NA_integer_, 1L), c(FALSE, FALSE, TRUE, TRUE, TRUE))
})

test_that("a PROVISIONALLY_ACCEPTED record whose accepted key is its own is NOT a synonym", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(name_backbone = .backbone, .package = "rgbif")
  x <- suppressMessages(lookup_gbif_taxa("Hypsurus provisional"))
  expect_identical(x$gbif_status, "PROVISIONALLY_ACCEPTED")
  expect_false(x$is_synonym)
  expect_identical(x$record_id, x$current_record_id)
  expect_identical(x$matched_name, "Hypsurus caryi")          # its own canonical name, not a classification lookup
})

test_that("FUZZY is matched with match_type Fuzzy; HIGHERRANK is matched at its coarser rank; both counted", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(name_backbone = .backbone, .package = "rgbif")
  x <- suppressMessages(lookup_gbif_taxa(c("Hypsurus cari", "Gelidium kathyanniae")))
  expect_identical(x$match_type, c("Fuzzy", "Exact"))
  expect_identical(x$matched_rank, c("species", "genus"))
  expect_identical(x$matched_name[2], "Gelidium")
  expect_identical(c(attr(x, "n_fuzzy"), attr(x, "n_higherrank")), c(1L, 1L))
})

test_that("LOOKUP_RECOVERED is not matched (no lineage) and is counted", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(name_backbone = .backbone, name_lookup = .lookup, .package = "rgbif")
  x <- suppressMessages(lookup_gbif_taxa("Notagenus", context = "Animalia|Chordata"))
  expect_identical(x$gbif_matchType, "LOOKUP_RECOVERED")
  expect_false(x$matched)
  expect_true(x$verified)
  expect_true(is.na(x$current_record_id))
  expect_identical(attr(x, "n_recovered"), 1L)
})

test_that("ERROR is a failed lookup (verified FALSE), counted apart from an unmatched answer", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(name_backbone = .backbone, .package = "rgbif")
  x <- suppressMessages(lookup_gbif_taxa(c("Failname", "Nothing atall")))
  expect_identical(x$gbif_matchType, c("ERROR", "NONE"))
  expect_identical(x$verified, c(FALSE, TRUE))
  expect_identical(x$matched, c(FALSE, FALSE))
  expect_identical(attr(x, "n_error"), 1L)
  expect_identical(attr(x, "n_requested"), 2L)
})

test_that("rank: given where valid, else inferred from word count; a leading kingdom in context is sent", {
  skip_if_not_installed("rgbif")
  seen <- list()
  local_mocked_bindings(name_backbone = function(...) { seen[[length(seen) + 1L]] <<- list(...); list(matchType = "NONE") },
                        .package = "rgbif")
  suppressMessages(lookup_gbif_taxa(c("Embiotocidae", "Hypsurus", "Hypsurus caryi"), rank = c("family", "nonsense", NA),
                                    context = c("Animalia|Chordata", "Chordata", NA)))
  expect_identical(vapply(seen, `[[`, "", "rank"), c("FAMILY", "GENUS", "SPECIES"))
  expect_identical(seen[[1]]$kingdom, "Animalia")
  expect_null(seen[[2]]$kingdom)                            # "Chordata" is not a kingdom: not sent
})

test_that("cache: a second call is served from the cache with the network off, and n_cached says so", {
  skip_if_not_installed("rgbif")
  d <- tempfile()
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE))
  local_mocked_bindings(name_backbone = .backbone, .package = "rgbif")
  a <- suppressMessages(lookup_gbif_taxa(c("Hypsurus caryi", "Embiotoca caryi"), cache_dir = d))
  expect_identical(attr(a, "n_cached"), 0L)
  local_mocked_bindings(name_backbone = function(...) stop("network must not be reached"), .package = "rgbif")
  b <- suppressMessages(lookup_gbif_taxa(c("Hypsurus caryi", "Embiotoca caryi"), cache_dir = d))
  expect_identical(attr(b, "n_cached"), 2L)
  expect_identical(attr(b, "n_error"), 0L)
  strip <- function(x) { attributes(x)[grep("^n_", names(attributes(x)))] <- NULL; x }   # n_cached differs by design
  expect_identical(strip(b), strip(a))
})

test_that("input order is kept and a zero-length input returns the columns with zero counts", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(name_backbone = .backbone, .package = "rgbif")
  x <- suppressMessages(lookup_gbif_taxa(c("Embiotoca caryi", "Hypsurus caryi")))
  expect_identical(x$user_supplied_name, c("Embiotoca caryi", "Hypsurus caryi"))
  z <- lookup_gbif_taxa(character(0))
  expect_identical(nrow(z), 0L)
  expect_identical(attr(z, "n_requested"), 0L)
  expect_error(lookup_gbif_taxa(1), "character")
  expect_error(lookup_gbif_taxa("a", rank = c("x", "y")), "rank")
})

test_that("with the registry: the flagless synonym is a DECLARED merge with its accepted name", {
  skip_if_not_installed("rgbif")
  skip_if_not("build_taxon_registry" %in% getNamespaceExports("TaxaTools"), "TaxaTools without the taxon registry")
  local_mocked_bindings(name_backbone = .backbone, .package = "rgbif")
  reg <- suppressMessages(TaxaTools::build_taxon_registry(
    data.frame(verbatim_name = c("Embiotoca caryi", "Hypsurus caryi"), source_table = "t"),
    run_id = "test", key_backbone_id = 11L, lookup = lookup_gbif_taxa))
  expect_identical(length(unique(reg$names$taxon_id)), 1L)
  expect_identical(sort(reg$names$status), c("accepted", "synonym"))
  chk <- TaxaTools::check_taxon_registry(reg)
  expect_identical(sum(chk$kind == "undeclared_merge"), 0L)
  expect_identical(sum(chk$kind == "declared_merge"), 1L)
})

test_that("VARIANT is matched as a fuzzy answer; the old EXACT/FUZZY/HIGHERRANK rule left it unmatched", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(name_backbone = .backbone, .package = "rgbif")
  x <- suppressMessages(lookup_gbif_taxa(c("Pyrogophorus", "Hypsurus karyi")))
  expect_identical(x$gbif_matchType, c("VARIANT", "VARIANT"))
  expect_false(any(x$gbif_matchType %in% c("EXACT", "FUZZY", "HIGHERRANK")))   # the old rule's set: none of these
  expect_identical(x$matched, c(TRUE, TRUE))
  expect_identical(x$match_type, c("Fuzzy", "Fuzzy"))
  expect_identical(x$matched_rank, c("genus", "species"))
  expect_identical(x$current_record_id[1], "2299855")
  expect_identical(attr(x, "n_variant"), 2L)
  expect_identical(attr(x, "n_fuzzy"), 0L)                     # GBIF's own FUZZY count is not merged with VARIANT
})

test_that("with the registry: a VARIANT genus answer gives the genus id where the names' lineage agrees; a VARIANT species answer is not a name match", {
  skip_if_not_installed("rgbif")
  skip_if_not("build_taxon_registry" %in% getNamespaceExports("TaxaTools"), "TaxaTools without the taxon registry")
  local_mocked_bindings(name_backbone = .backbone, .package = "rgbif")
  # the registry takes a non-exact genus answer only where the names' context names its kingdom and phylum
  reg <- suppressMessages(TaxaTools::build_taxon_registry(
    data.frame(verbatim_name = c("Pyrogophorus notadus", "Hypsurus karyi"), source_table = "t",
               context = c("Animalia|Mollusca|Gastropoda", "Animalia|Chordata")),
    run_id = "test", key_backbone_id = 11L, lookup = lookup_gbif_taxa))
  id <- reg$names$taxon_id[match(c("Pyrogophorus notadus", "Hypsurus karyi"), reg$names$verbatim_name)]
  expect_identical(id[1], "local:2299855:notadus")            # under the VARIANT genus key, not plain "local:<name>"
  expect_true("gbif:2299855" %in% reg$taxa$taxon_id)
  st <- reg$names$status[match("Hypsurus karyi", reg$names$verbatim_name)]
  expect_false(st %in% c("accepted", "synonym"))               # a spelling variant never resolves a species by itself
  expect_false(identical(id[2], "gbif:2389310"))
  # without lineage context the same VARIANT genus answer is refused (the registry's genus-pass gate)
  r0 <- suppressMessages(TaxaTools::build_taxon_registry(data.frame(verbatim_name = "Pyrogophorus notadus", source_table = "t"),
                                                         run_id = "test0", key_backbone_id = 11L, lookup = lookup_gbif_taxa))
  expect_identical(r0$names$taxon_id, "local:Pyrogophorus notadus")
  expect_identical(r0$meta$genus_variant_rejected$reason, "no lineage context")
})

# Package review 2026-11-13, F6: the Rd described the registry's use of this lookup as it was before the genus gate
# and the genus_variant rule. FAILS on the reviewed code (2ea632dc).
test_that("REVIEW F6: lookup_gbif_taxa's docs no longer say a fuzzy answer resolves a name only under the gender rule", {
  src <- testthat::test_path("..", "..", "R", "lookup_gbif_taxa.R"); rd <- testthat::test_path("..", "..", "man", "lookup_gbif_taxa.Rd")
  if (!file.exists(src) || !file.exists(rd)) testthat::skip("R/ and man/ not found next to this package (source layout unavailable here)")
  txt <- c(readLines(src, warn = FALSE), readLines(rd, warn = FALSE))
  expect_false(any(grepl("resolves a name by one only", txt, fixed = TRUE)))
})
