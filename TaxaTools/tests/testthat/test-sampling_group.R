# test-sampling_group.R
# Tests for default_sampling_scheme()/assign_sampling_group().
# Fully offline -- no network calls (harmonise = TRUE is never exercised here,
# since it requires a live verify_taxon_names() backbone lookup).

library(testthat)

# =============================================================================
# Real drift-incident regression: one row per historical bug
# =============================================================================

test_that("class-less Chordata (ray-finned fish) lands in fishes, not the catch-all", {
  tax <- data.frame(kingdom = "Animalia", phylum = "Chordata", class = NA_character_,
                     order = "Perciformes", stringsAsFactors = FALSE)
  out <- assign_sampling_group(tax, verbose = FALSE)
  expect_equal(out$sampling_group, "fishes")
})

test_that("Elasmobranchii (sharks/rays) lands in fishes, not the catch-all", {
  tax <- data.frame(kingdom = "Animalia", phylum = "Chordata", class = "Elasmobranchii",
                     order = "Carcharhiniformes", stringsAsFactors = FALSE)
  out <- assign_sampling_group(tax, verbose = FALSE)
  expect_equal(out$sampling_group, "fishes")
})

test_that("Phaeophyceae (brown algae/kelp) lands in macroalgae, not the catch-all", {
  tax <- data.frame(kingdom = "Chromista", phylum = "Ochrophyta", class = "Phaeophyceae",
                     order = "Laminariales", stringsAsFactors = FALSE)
  out <- assign_sampling_group(tax, verbose = FALSE)
  expect_equal(out$sampling_group, "macroalgae")
})

test_that("Dinophyceae (dinoflagellates) lands in phytoplankton, not the catch-all", {
  tax <- data.frame(kingdom = "Chromista", phylum = "Myzozoa", class = "Dinophyceae",
                     order = "Gymnodiniales", stringsAsFactors = FALSE)
  out <- assign_sampling_group(tax, verbose = FALSE)
  expect_equal(out$sampling_group, "phytoplankton")
})

test_that("Bacillariophyceae (diatoms) lands in phytoplankton, not macroalgae or the catch-all", {
  # TRAP: phylum is Ochrophyta, the SAME phylum as the kelps -- the rule must
  # be class-level or this would either exclude diatoms or admit kelps wrongly.
  tax <- data.frame(kingdom = "Chromista", phylum = "Ochrophyta", class = "Bacillariophyceae",
                     order = "Naviculales", stringsAsFactors = FALSE)
  out <- assign_sampling_group(tax, verbose = FALSE)
  expect_equal(out$sampling_group, "phytoplankton")
  expect_false(out$sampling_group == "macroalgae")
})

test_that("Copepoda and Hexanauplia both land in zooplankton (same group, both backbone spellings)", {
  tax <- data.frame(
    kingdom = c("Animalia", "Animalia"),
    phylum  = c("Arthropoda", "Arthropoda"),
    class   = c("Copepoda", "Hexanauplia"),
    order   = c(NA_character_, NA_character_),
    stringsAsFactors = FALSE
  )
  out <- assign_sampling_group(tax, verbose = FALSE)
  expect_equal(out$sampling_group, c("zooplankton", "zooplankton"))
  expect_false(any(out$sampling_group == "macroinvertebrates"))
})

# =============================================================================
# Kingdom guard
# =============================================================================

test_that("kingdom guard sends an unmatched non-animal row to NA, not the catch-all", {
  # A protist with no rule anywhere in the scheme.
  tax <- data.frame(kingdom = "Chromista", phylum = "Heliozoa", class = NA_character_,
                     order = NA_character_, stringsAsFactors = FALSE)
  out_guarded <- assign_sampling_group(tax, kingdom_guard = TRUE, verbose = FALSE)
  expect_true(is.na(out_guarded$sampling_group))

  out_unguarded <- assign_sampling_group(tax, kingdom_guard = FALSE, verbose = FALSE)
  expect_equal(out_unguarded$sampling_group, "macroinvertebrates")
})

test_that("a missing kingdom and an unusable phylum are flagged, not kept", {
  # This row used to become "macroinvertebrates": the guard skipped a NA
  # kingdom entirely, so a row with no usable taxonomy kept the
  # animal-flavoured catch-all. It is now refused with a basis that says the
  # decision could not be made -- which is what the guard was always for, to
  # make such a row visible to a caller auditing unmatched rows rather than
  # counting it indefinitely as a benthic invertebrate.
  tax <- data.frame(kingdom = NA_character_, phylum = "Something_unclassified",
                     class = NA_character_, order = NA_character_, stringsAsFactors = FALSE)
  out <- assign_sampling_group(tax, kingdom_guard = TRUE, verbose = FALSE)
  expect_true(is.na(out$sampling_group))
  expect_equal(out$sampling_group_basis, "unknown_phylum")
})

test_that("kingdom guard does not fire for a genuine animal reaching the catch-all", {
  tax <- data.frame(kingdom = "Animalia", phylum = "Mollusca", class = "Gastropoda",
                     order = NA_character_, stringsAsFactors = FALSE)
  out <- assign_sampling_group(tax, kingdom_guard = TRUE, verbose = FALSE)
  expect_equal(out$sampling_group, "macroinvertebrates")
})

# =============================================================================
# Ordering / first-match-wins
# =============================================================================

test_that("first-match-wins is preserved: a row matching two rules takes the first", {
  custom_scheme <- list(
    rules = list(
      list(group = "first_wins", when = list(list(class = "Ambiguity"))),
      list(group = "second_rule", when = list(list(phylum = "Testphylum")))
    ),
    catch_all = "none_matched",
    kingdom_guard_vocabulary = c("Animalia", "Metazoa")
  )
  tax <- data.frame(kingdom = "Animalia", phylum = "Testphylum", class = "Ambiguity",
                     order = NA_character_, stringsAsFactors = FALSE)
  out <- assign_sampling_group(tax, scheme = custom_scheme, kingdom_guard = FALSE, verbose = FALSE)
  expect_equal(out$sampling_group, "first_wins")
})

# =============================================================================
# Custom scheme override
# =============================================================================

test_that("a user-supplied scheme fully overrides the default", {
  custom_scheme <- list(
    rules = list(
      list(group = "custom_group", when = list(list(class = "Foo")))
    ),
    catch_all = "unclassified",
    kingdom_guard_vocabulary = c("Animalia", "Metazoa")
  )
  tax <- data.frame(kingdom = "Animalia", phylum = "Bar", class = "Foo",
                     order = NA_character_, stringsAsFactors = FALSE)
  out <- assign_sampling_group(tax, scheme = custom_scheme, verbose = FALSE)
  expect_equal(out$sampling_group, "custom_group")

  # A row that would have matched the DEFAULT scheme's fishes rule instead
  # falls to this custom scheme's own catch-all, proving the default is not
  # consulted at all.
  tax2 <- data.frame(kingdom = "Animalia", phylum = "Chordata", class = "Elasmobranchii",
                      order = NA_character_, stringsAsFactors = FALSE)
  out2 <- assign_sampling_group(tax2, scheme = custom_scheme, kingdom_guard = FALSE, verbose = FALSE)
  expect_equal(out2$sampling_group, "unclassified")
})

# =============================================================================
# NA / "" handling
# =============================================================================

test_that("empty strings are normalised to NA the same as real NA before matching", {
  tax <- data.frame(
    kingdom = c("Animalia", "Animalia"),
    phylum  = c("Chordata", "Chordata"),
    class   = c("", NA_character_),
    order   = c("", NA_character_),
    stringsAsFactors = FALSE
  )
  out <- assign_sampling_group(tax, verbose = FALSE)
  # "" and NA both fail the class-less-Chordata clause's is.na(class) check
  # identically once normalised -- both rows should classify the same way.
  expect_equal(out$sampling_group[1], out$sampling_group[2])
  expect_equal(out$sampling_group, c("fishes", "fishes"))
})

test_that("a clause naming a rank not present in the input treats it as entirely NA", {
  tax <- data.frame(kingdom = "Animalia", phylum = "Chordata", stringsAsFactors = FALSE)
  # No `class` or `order` column at all.
  out <- assign_sampling_group(tax, verbose = FALSE)
  expect_equal(out$sampling_group, "fishes") # phylum Chordata, class missing entirely
})

# =============================================================================
# Backbone-mismatch warning
# =============================================================================

test_that("harmonise = FALSE warns once on NCBI-only vocabulary", {
  tax <- data.frame(kingdom = "Chromista", phylum = NA_character_,
                     class = "Phytomastigophora", order = NA_character_,
                     stringsAsFactors = FALSE)
  expect_warning(
    assign_sampling_group(tax, harmonise = FALSE, kingdom_guard = FALSE, verbose = FALSE),
    regexp = "backbone mismatch"
  )
})

test_that("no mismatch warning fires on ordinary GBIF-vocabulary input", {
  tax <- data.frame(kingdom = "Animalia", phylum = "Chordata", class = "Aves",
                     order = NA_character_, stringsAsFactors = FALSE)
  expect_no_warning(assign_sampling_group(tax, harmonise = FALSE, verbose = FALSE))
})

test_that("a taxonomy_backbone attribute not matching GBIF triggers the mismatch warning", {
  tax <- data.frame(kingdom = "Animalia", phylum = "Chordata", class = "Aves",
                     order = NA_character_, stringsAsFactors = FALSE)
  attr(tax, "taxonomy_backbone") <- "backbone_4"
  expect_warning(
    assign_sampling_group(tax, harmonise = FALSE, verbose = FALSE),
    regexp = "backbone mismatch"
  )
})

# =============================================================================
# Input validation
# =============================================================================

test_that("stops on a non-data-frame taxonomy", {
  expect_error(assign_sampling_group(list(a = 1)), regexp = "data frame")
})

test_that("stops on a malformed scheme", {
  tax <- data.frame(kingdom = "Animalia")
  expect_error(assign_sampling_group(tax, scheme = list(foo = 1)), regexp = "scheme")
})

test_that("verbose = TRUE prints a group-count table without erroring", {
  tax <- data.frame(kingdom = "Animalia", phylum = "Chordata", class = "Aves",
                     order = NA_character_, stringsAsFactors = FALSE)
  expect_output(assign_sampling_group(tax, verbose = TRUE), "sampling_group counts")
})

# ==============================================================================
# 2026-09-13: Liliopsida gap and the dead Zygnemophyceae spelling
# ==============================================================================

test_that("non-seagrass monocots are vascular plants, and seagrasses still win on order", {
  tx <- data.frame(
    kingdom = "Plantae",
    phylum  = "Tracheophyta",
    class   = c("Liliopsida", "Liliopsida", "Liliopsida", "Magnoliopsida"),
    order   = c("Poales", "Arecales", "Alismatales", "Asterales"),
    stringsAsFactors = FALSE
  )
  out <- assign_sampling_group(tx, verbose = FALSE)
  # Poales (Poa, Carex) and Arecales (Washingtonia): land plants, not the catch-all
  expect_equal(out$sampling_group[1:2], c("other_vascular_plants", "other_vascular_plants"))
  # Alismatales carries class Liliopsida too (true of Zostera/Phyllospadix/Posidonia
  # in GBIF's real backbone) -- first-match-wins must keep it in sea_grasses
  expect_equal(out$sampling_group[3], "sea_grasses")
  expect_equal(out$sampling_group[4], "other_vascular_plants")
  expect_false(any(out$sampling_group == "macroinvertebrates"))
})

test_that("Zygnematophyceae (GBIF's accepted spelling) is phytoplankton", {
  tx <- data.frame(
    kingdom = "Plantae", phylum = "Charophyta",
    class = "Zygnematophyceae", order = "Zygnematales",
    stringsAsFactors = FALSE
  )
  expect_equal(assign_sampling_group(tx, verbose = FALSE)$sampling_group, "phytoplankton")
})

test_that("the dead Zygnemophyceae spelling is gone from the default scheme", {
  classes <- unlist(lapply(default_sampling_scheme()$rules, function(r) {
    unlist(lapply(r$when, function(cl) cl$class))
  }))
  expect_false("Zygnemophyceae" %in% classes)
  expect_true("Zygnematophyceae" %in% classes)
  expect_true("Liliopsida" %in% classes)
})

# =============================================================================
# harmonise = TRUE: the rank-agreement gate
# =============================================================================
# These stay offline by mocking verify_taxon_names() only. change_backbone()
# runs for real, so the classification_path parsing is genuinely exercised.
# Every row of the fixture below is a VERIFIED live GBIF answer, captured
# 2026-09-15 against backbone 11 -- including the one that motivated the gate:
# GBIF's backbone holds a tachinid FLY GENUS named "Polychaeta", so the annelid
# class name resolves into Insecta|Diptera.

.gbif_fixture <- data.frame(
  user_supplied_name = c("Polychaeta", "Phyllodocida", "Thalassiosirales",
                         "Calanoida", "Bacillariophyta", "Terebellida",
                         "Ciliophora", "Arthropoda"),
  matched_name = c("Polychaeta", "Phyllodocida", "Thalassiosirales",
                   "Calanoida", "Bacillariophyceae", NA_character_,
                   "Ciliophora", "Arthropoda"),
  matched_rank = c("genus", "order", "order", "order", "class", NA_character_,
                   "genus", "genus"),
  is_synonym = FALSE,
  classification_path = c(
    "Animalia|Arthropoda|Insecta|Diptera|Tachinidae|Polychaeta",
    "Animalia|Annelida|Polychaeta|Phyllodocida",
    "Chromista|Ochrophyta|Bacillariophyceae|Thalassiosirales",
    "Animalia|Arthropoda|Copepoda|Calanoida",
    "Chromista|Ochrophyta|Bacillariophyceae",
    NA_character_,
    "Fungi|Ascomycota|Ciliophora",
    "Animalia|Arthropoda|Arthropoda"
  ),
  classification_ranks = c(
    "kingdom|phylum|class|order|family|genus",
    "kingdom|phylum|class|order",
    "kingdom|phylum|class|order",
    "kingdom|phylum|class|order",
    "kingdom|phylum|class",
    NA_character_,
    "kingdom|phylum|genus",
    "kingdom|phylum|genus"
  ),
  score = c(0.9, 0.9, 0.9, 0.9, 0.9, NA_real_, 0.9, 0.9),
  verified = TRUE,
  stringsAsFactors = FALSE
)

.mock_verify <- function(names, backbone_id = 11L, ...) {
  .gbif_fixture[match(names, .gbif_fixture$user_supplied_name), , drop = FALSE]
}

test_that("a backbone match at the wrong rank is rejected and warns", {
  local_mocked_bindings(verify_taxon_names = .mock_verify)
  tx <- data.frame(kingdom = "Metazoa", phylum = "Annelida",
                   class = "Polychaeta", order = NA_character_,
                   stringsAsFactors = FALSE)
  expect_warning(
    out <- assign_sampling_group(tx, harmonise = TRUE, verbose = FALSE),
    "resolved at the wrong rank"
  )
  # The whole row keeps its ORIGINAL taxonomy -- not just the class column.
  expect_equal(out$kingdom, "Metazoa")
  expect_equal(out$phylum, "Annelida")
  expect_equal(out$class, "Polychaeta")
  expect_true(is.na(out$order))
  expect_equal(out$sampling_group, "macroinvertebrates")
})

test_that("the warning names the taxon, its column rank and the matched rank", {
  local_mocked_bindings(verify_taxon_names = .mock_verify)
  tx <- data.frame(kingdom = "Metazoa", phylum = "Annelida",
                   class = "Polychaeta", order = NA_character_,
                   stringsAsFactors = FALSE)
  w <- tryCatch(assign_sampling_group(tx, harmonise = TRUE, verbose = FALSE),
                warning = conditionMessage)
  expect_match(w, "Polychaeta \\(class column, backbone matched a genus\\)")
})

test_that("rank-agreeing matches still harmonise NCBI vocabulary to GBIF", {
  local_mocked_bindings(verify_taxon_names = .mock_verify)
  tx <- data.frame(
    kingdom = c(NA_character_, "Metazoa", "Metazoa"),
    phylum  = c("Bacillariophyta", "Arthropoda", "Annelida"),
    # Thalassiosirophyceae and Copepoda are NCBI-flavoured class names the
    # GBIF-vocabulary scheme cannot read; harmonising is the point of the flag.
    class   = c("Thalassiosirophyceae", "Copepoda", "Polychaeta"),
    order   = c("Thalassiosirales", "Calanoida", "Phyllodocida"),
    stringsAsFactors = FALSE
  )
  out <- expect_no_warning(
    assign_sampling_group(tx, harmonise = TRUE, verbose = FALSE)
  )
  expect_equal(out$class, c("Bacillariophyceae", "Copepoda", "Polychaeta"))
  expect_equal(out$phylum, c("Ochrophyta", "Arthropoda", "Annelida"))
  expect_equal(out$sampling_group,
               c("phytoplankton", "zooplankton", "macroinvertebrates"))
})

test_that("harmonise passes each probe name's source rank as input_rank=", {
  got <- new.env()
  local_mocked_bindings(
    verify_taxon_names = function(names, backbone_id = 11L, input_rank = NULL, ...) {
      got$names <- names
      got$input_rank <- input_rank
      .gbif_fixture[match(names, .gbif_fixture$user_supplied_name), , drop = FALSE]
    }
  )
  tx <- data.frame(
    kingdom = c(NA_character_, "Metazoa"),
    phylum  = c("Bacillariophyta", "Arthropoda"),
    class   = c(NA_character_, "Copepoda"),
    order   = c("Thalassiosirales", "Calanoida"),
    stringsAsFactors = FALSE
  )
  suppressWarnings(assign_sampling_group(tx, harmonise = TRUE, verbose = FALSE))
  expect_equal(got$names, c("Calanoida", "Thalassiosirales"))
  expect_equal(got$input_rank, c("order", "order"))
})

test_that("a name with no backbone match keeps its original value, silently", {
  local_mocked_bindings(verify_taxon_names = .mock_verify)
  tx <- data.frame(kingdom = "Metazoa", phylum = "Annelida",
                   class = "Polychaeta", order = "Terebellida",
                   stringsAsFactors = FALSE)
  # No match is not a rank disagreement, so the gate must stay quiet.
  out <- expect_no_warning(
    suppressMessages(assign_sampling_group(tx, harmonise = TRUE, verbose = FALSE))
  )
  expect_equal(out$order, "Terebellida")
  expect_equal(out$phylum, "Annelida")
  expect_equal(out$sampling_group, "macroinvertebrates")
})

test_that("a rank-mismatched match is rejected even coming from the cache", {
  local_mocked_bindings(verify_taxon_names = .mock_verify)
  cd <- withr::local_tempdir()
  tx <- data.frame(kingdom = "Metazoa", phylum = "Annelida",
                   class = "Polychaeta", order = NA_character_,
                   stringsAsFactors = FALSE)
  suppressWarnings(assign_sampling_group(tx, harmonise = TRUE,
                                         cache_dir = cd, verbose = FALSE))
  lookup <- readRDS(file.path(cd, "sampling_group_harmonise_cache.rds"))
  expect_true("matched_rank" %in% names(lookup))

  # Second call is served entirely from the cache -- the gate must still fire.
  expect_warning(
    out <- assign_sampling_group(tx, harmonise = TRUE, cache_dir = cd,
                                 verbose = FALSE),
    "resolved at the wrong rank"
  )
  expect_equal(out$class, "Polychaeta")
  expect_equal(out$sampling_group, "macroinvertebrates")
})

test_that("a cache written before the gate is discarded, not trusted", {
  local_mocked_bindings(verify_taxon_names = .mock_verify)
  cd <- withr::local_tempdir()
  # Exactly what the 2026-09-15 PtConception run left on disk: the corrupted
  # fly-genus lineage, and no matched_rank column to catch it with.
  saveRDS(
    data.frame(source_name = "Polychaeta", kingdom = "Animalia",
               phylum = "Arthropoda", class = "Insecta", order = "Diptera",
               stringsAsFactors = FALSE),
    file.path(cd, "sampling_group_harmonise_cache.rds")
  )
  tx <- data.frame(kingdom = "Metazoa", phylum = "Annelida",
                   class = "Polychaeta", order = NA_character_,
                   stringsAsFactors = FALSE)
  expect_warning(
    out <- assign_sampling_group(tx, harmonise = TRUE, cache_dir = cd,
                                 verbose = FALSE),
    "resolved at the wrong rank"
  )
  expect_equal(out$phylum, "Annelida")
  expect_equal(out$class, "Polychaeta")
  expect_equal(out$sampling_group, "macroinvertebrates")
})

test_that("merging a fresh batch into a narrower cache does not error", {
  local_mocked_bindings(verify_taxon_names = .mock_verify)
  cd <- withr::local_tempdir()
  # A cached frame carrying FEWER rank columns than the fresh batch will: the
  # old rbind() subset only the cached side and blew up on the width mismatch.
  saveRDS(
    data.frame(source_name = "Bacillariophyta", matched_rank = "class",
               kingdom = "Chromista", phylum = "Ochrophyta",
               stringsAsFactors = FALSE),
    file.path(cd, "sampling_group_harmonise_cache.rds")
  )
  tx <- data.frame(kingdom = c(NA_character_, "Metazoa"),
                   phylum = c("Bacillariophyta", "Arthropoda"),
                   class = c(NA_character_, "Copepoda"),
                   order = c(NA_character_, "Calanoida"),
                   stringsAsFactors = FALSE)
  out <- expect_no_error(
    suppressWarnings(assign_sampling_group(tx, harmonise = TRUE,
                                           cache_dir = cd, verbose = FALSE))
  )
  expect_equal(out$sampling_group[2], "zooplankton")
})

test_that("a same-clade duplication at a finer rank is ACCEPTED (rule 2)", {
  local_mocked_bindings(verify_taxon_names = .mock_verify)
  # GBIF holds a GENUS Arthropoda inside phylum Arthropoda. matched_rank is
  # "genus" against a phylum column, so rule 1 fails -- but the returned
  # lineage carries "Arthropoda" at PHYLUM rank, which is the row's own clade,
  # so the harmonisation is sound and must not be thrown away.
  tx <- data.frame(kingdom = "Metazoa", phylum = "Arthropoda",
                   class = NA_character_, order = NA_character_,
                   stringsAsFactors = FALSE)
  out <- expect_no_warning(
    assign_sampling_group(tx, harmonise = TRUE, verbose = FALSE)
  )
  expect_equal(out$kingdom, "Animalia")
  expect_equal(out$phylum, "Arthropoda")
})

test_that("a cross-lineage homonym at a finer rank is still REJECTED", {
  local_mocked_bindings(verify_taxon_names = .mock_verify)
  # GBIF holds a FUNGUS genus named Ciliophora. Same rank shape as Arthropoda
  # above (phylum column -> genus match), but the lineage at phylum rank reads
  # "Ascomycota", not "Ciliophora" -- so rule 2 must not rescue it.
  tx <- data.frame(kingdom = "Chromista", phylum = "Ciliophora",
                   class = NA_character_, order = NA_character_,
                   stringsAsFactors = FALSE)
  expect_warning(
    out <- assign_sampling_group(tx, harmonise = TRUE, verbose = FALSE),
    "Ciliophora \\(phylum column, backbone matched a genus\\)"
  )
  expect_equal(out$kingdom, "Chromista")
  expect_equal(out$phylum, "Ciliophora")
})

test_that("harmonise: a name whose lookup FAILED is warned about, left unharmonised and never cached", {
  failing_verify <- function(names, backbone_id = 11L, ...) {
    out <- .mock_verify(names, backbone_id, ...)
    out$verified[out$user_supplied_name == "Polychaeta"] <- FALSE
    out$matched_name[out$user_supplied_name == "Polychaeta"] <- NA_character_
    out$classification_path[out$user_supplied_name == "Polychaeta"] <- NA_character_
    out$classification_ranks[out$user_supplied_name == "Polychaeta"] <- NA_character_
    out
  }
  local_mocked_bindings(verify_taxon_names = failing_verify)
  cd <- withr::local_tempdir()
  tx <- data.frame(kingdom = "Metazoa", phylum = "Annelida",
                   class = "Polychaeta", order = NA_character_,
                   stringsAsFactors = FALSE)
  expect_warning(
    out <- assign_sampling_group(tx, harmonise = TRUE, cache_dir = cd, verbose = FALSE),
    "lookup FAILED for 1 of 1"
  )
  expect_equal(out$class, "Polychaeta")                       # untouched, not fabricated
  expect_false(file.exists(file.path(cd, "sampling_group_harmonise_cache.rds")))
})

test_that("harmonise: an unmarked cache's lineage-less row is re-resolved, a lineage-bearing one is kept", {
  local_mocked_bindings(verify_taxon_names = .mock_verify)
  cd <- withr::local_tempdir()
  saveRDS(
    data.frame(source_name = c("Polychaeta", "Annelida"), matched_rank = c(NA, "phylum"),
               kingdom = c(NA, "Animalia"), phylum = c(NA, "Annelida"), class = NA_character_,
               order = NA_character_, stringsAsFactors = FALSE),
    file.path(cd, "sampling_group_harmonise_cache.rds")     # no answered_only attribute
  )
  tx <- data.frame(kingdom = "Metazoa", phylum = "Annelida",
                   class = "Polychaeta", order = NA_character_, stringsAsFactors = FALSE)
  expect_message(
    suppressWarnings(assign_sampling_group(tx, harmonise = TRUE, cache_dir = cd, verbose = TRUE)),
    "1 unmatched row\\(s\\) cannot be told from failed lookups"
  )
  lookup <- readRDS(file.path(cd, "sampling_group_harmonise_cache.rds"))
  expect_true(isTRUE(attr(lookup, "answered_only")))
  expect_true("Annelida" %in% lookup$source_name)              # kept, not re-asked
  expect_true("Polychaeta" %in% lookup$source_name)            # re-resolved and rewritten
  expect_false(all(is.na(lookup[lookup$source_name == "Polychaeta", c("kingdom", "phylum")])))
})

# ===========================================================================
# The phylum fallback: when the kingdom cannot decide, the phylum does
# ===========================================================================

# A kingdom of "Eukaryota" is true of every taxon this function sees, so it
# decides nothing -- but the allowlist guard read it as "not an animal" and
# refused the catch-all, while a MISSING kingdom was not guarded at all and
# kept it. Both wrong, and in opposite directions. These tests pin the three
# outcomes of the fallback and, as importantly, that it does not reach rows
# the scheme already placed.

.sg_row <- function(kingdom = NA_character_, phylum = NA_character_,
                    class = NA_character_, order = NA_character_) {
  data.frame(
    kingdom = kingdom, phylum = phylum, class = class, order = order,
    stringsAsFactors = FALSE
  )
}
.sg_one <- function(...) {
  out <- assign_sampling_group(.sg_row(...), verbose = FALSE)
  list(group = out$sampling_group[[1L]], basis = out$sampling_group_basis[[1L]])
}

test_that("a domain-labelled ANIMAL reaches the catch-all", {
  r <- .sg_one(kingdom = "Eukaryota", phylum = "Cnidaria")
  expect_equal(r$group, "macroinvertebrates")
  expect_equal(r$basis, "phylum_animal")
})

test_that("a domain-labelled NON-animal is refused, as a conclusion", {
  # Discosea is an amoebozoan phylum. It is out because it is not in the
  # closed animal list, not because anyone enumerated the protists.
  r <- .sg_one(kingdom = "Eukaryota", phylum = "Discosea")
  expect_true(is.na(r$group))
  expect_equal(r$basis, "phylum_non_animal")
})

test_that("an unknown phylum is undecidable, and says so", {
  # A placeholder string, not NA: a bare is.na() test would read "unk_phylum"
  # as an informative non-animal phylum and DROP the row as a confident
  # non-animal instead of flagging it.
  for (ph in c(NA_character_, "", "unk_phylum", "unknown", "incertae sedis")) {
    r <- .sg_one(kingdom = "Eukaryota", phylum = ph)
    expect_true(is.na(r$group), info = ph %||% "NA")
    expect_equal(r$basis, "unknown_phylum", info = ph %||% "NA")
  }
})

test_that("the fallback never reaches a row a rule already placed", {
  # The regression this test exists for: with the catch-all restriction
  # dropped, "non-animal or unknown phylum -> NA" would override a CLASS rule
  # and refuse domain-labelled macroalgae the scheme gets right.
  r <- .sg_one(kingdom = "Eukaryota", phylum = "unk_phylum", class = "Ulvophyceae")
  expect_equal(r$group, "macroalgae")
  expect_equal(r$basis, "rule")
})

test_that("an informative non-animal kingdom is still refused by the allowlist", {
  # The control label is the real case: kingdom "PositiveControl" is
  # informative under the fallback's test, so the fallback never sees it and
  # the allowlist guard handles it -- which is why the guard is kept.
  r <- .sg_one(kingdom = "PositiveControl")
  expect_true(is.na(r$group))
  expect_equal(r$basis, "kingdom_guard")
})

test_that("a row with an informative kingdom is unchanged by any of this", {
  animal <- .sg_one(kingdom = "Animalia", phylum = "Mollusca")
  expect_equal(animal$group, "macroinvertebrates")
  expect_equal(animal$basis, "catch_all")
  for (k in c("Plantae", "Fungi", "Chromista")) {
    r <- .sg_one(kingdom = k, phylum = "Ascomycota")
    expect_true(is.na(r$group), info = k)
    expect_equal(r$basis, "kingdom_guard", info = k)
  }
})

test_that("a missing kingdom now decides by phylum, not by default", {
  # Previously an NA kingdom was not guarded at all and kept the catch-all
  # whatever its phylum was.
  expect_equal(.sg_one(phylum = "Arthropoda")$basis, "phylum_animal")
  expect_equal(.sg_one(phylum = "Arthropoda")$group, "macroinvertebrates")
  expect_equal(.sg_one(phylum = "Discosea")$basis, "phylum_non_animal")
  expect_true(is.na(.sg_one(phylum = "Discosea")$group))
  # Chlorophyta deliberately NOT used here: a phylum rule claims it for
  # macroalgae, so it never reaches the fallback at all.
  expect_equal(.sg_one(phylum = "Chlorophyta")$basis, "rule")
})

test_that("kingdom_guard = FALSE disables the fallback with the guard", {
  out <- assign_sampling_group(
    .sg_row(kingdom = "Eukaryota", phylum = "Discosea"),
    kingdom_guard = FALSE, verbose = FALSE
  )
  expect_equal(out$sampling_group[[1L]], "macroinvertebrates")
  expect_equal(out$sampling_group_basis[[1L]], "catch_all")
})

test_that("Bacteria and Archaea are conclusive, not uninformative", {
  # A domain label is only "uninformative" if it cannot decide animal from
  # non-animal. Eukaryota cannot. Bacteria and Archaea decide it outright, so
  # the allowlist guard refuses them and the phylum is never consulted -- which
  # matters because a prokaryote row carrying an animal-sounding phylum string
  # must not be let through on that.
  for (k in c("Bacteria", "Archaea")) {
    r <- .sg_one(kingdom = k, phylum = "Arthropoda")
    expect_true(is.na(r$group), info = k)
    expect_equal(r$basis, "kingdom_guard", info = k)
  }
})

test_that("phylum matching ignores case and surrounding space", {
  # The animal list is a closed reference set, so "  cnidaria " is a
  # formatting difference, not a different phylum. Reading it as one would
  # drop the row as a confident non-animal.
  for (ph in c("cnidaria", "CNIDARIA", "  Cnidaria", "Cnidaria  ")) {
    r <- .sg_one(kingdom = "Eukaryota", phylum = ph)
    expect_equal(r$group, "macroinvertebrates", info = ph)
    expect_equal(r$basis, "phylum_animal", info = ph)
  }
})

test_that("a superseded phylum name is still the same animal phylum", {
  # Each of these is one phylum under another name. Omitting any would read as
  # a confident non-animal.
  for (ph in c("Acoelomorpha", "Nemertinea", "Rhynchocoela", "Pogonophora",
               "Craniata", "Urochordata", "Tunicata")) {
    r <- .sg_one(kingdom = "Eukaryota", phylum = ph)
    expect_equal(r$basis, "phylum_animal", info = ph)
  }
})

test_that("a scheme with no animal_phyla falls back and says so", {
  sch <- default_sampling_scheme()
  sch$animal_phyla <- NULL
  tax <- data.frame(kingdom = "Eukaryota", phylum = "Cnidaria",
                    class = NA_character_, order = NA_character_,
                    stringsAsFactors = FALSE)
  expect_message(
    out <- assign_sampling_group(tax, scheme = sch, verbose = TRUE),
    "no `animal_phyla`"
  )
  # And it still gets the right answer rather than dropping the row.
  expect_equal(out$sampling_group[[1L]], "macroinvertebrates")
  expect_equal(out$sampling_group_basis[[1L]], "phylum_animal")
})

test_that("the kingdom comparisons ignore case and surrounding space too", {
  # The same asymmetry the phylum match had: a formatting difference read as an
  # unrecognised kingdom leaves the row refused, silently and in the direction
  # that loses data. Both the domain list and the animal allowlist are closed
  # reference vocabularies, so both are compared forgivingly.
  for (k in c("eukaryota", "EUKARYOTA", " Eukaryota ")) {
    r <- .sg_one(kingdom = k, phylum = "Cnidaria")
    expect_equal(r$group, "macroinvertebrates", info = k)
    expect_equal(r$basis, "phylum_animal", info = k)
  }
  for (k in c("animalia", "ANIMALIA", " Animalia ")) {
    r <- .sg_one(kingdom = k, phylum = "Mollusca")
    expect_equal(r$group, "macroinvertebrates", info = k)
    expect_equal(r$basis, "catch_all", info = k)
  }
})

test_that("a phylum-only table still gets the phylum rule", {
  # No kingdom COLUMN, but a phylum column: the caller has supplied the rank
  # the fallback needs, so use it.
  animal <- data.frame(phylum = "Mollusca", class = NA_character_,
                       order = NA_character_, stringsAsFactors = FALSE)
  out <- assign_sampling_group(animal, verbose = FALSE)
  expect_equal(out$sampling_group[[1L]], "macroinvertebrates")
  expect_equal(out$sampling_group_basis[[1L]], "phylum_animal")

  other <- data.frame(phylum = "Discosea", class = NA_character_,
                      order = NA_character_, stringsAsFactors = FALSE)
  out2 <- assign_sampling_group(other, verbose = FALSE)
  expect_true(is.na(out2$sampling_group[[1L]]))
  expect_equal(out2$sampling_group_basis[[1L]], "phylum_non_animal")
})

test_that("a class/order-only table keeps the catch-all, and says why", {
  # Neither rank the guard or the fallback reads is present, so there is
  # nothing to decide on. Refusing every unmatched row here would be a mass
  # drop on an input shape this function documents as supported -- a column
  # absent from `taxonomy` is explicitly never an error.
  tax <- data.frame(class = "Gastropoda", order = NA_character_,
                    stringsAsFactors = FALSE)
  expect_warning(
    out <- assign_sampling_group(tax, verbose = FALSE),
    "neither a `kingdom` nor a `phylum` column"
  )
  expect_equal(out$sampling_group[[1L]], "macroinvertebrates")
  expect_equal(out$sampling_group_basis[[1L]], "catch_all")
})

test_that("the missing-column warning does not fire when nothing is unmatched", {
  # A class/order-only table whose rows a rule DID place has nothing for the
  # guard to check, so there is nothing to warn about.
  tax <- data.frame(class = "Insecta", order = NA_character_,
                    stringsAsFactors = FALSE)
  expect_silent(out <- assign_sampling_group(tax, verbose = FALSE))
  expect_equal(out$sampling_group[[1L]], "terrestrial_arthropods")
})

# ===========================================================================
# Catch-all gaps, and Hydrozoa's two habits
# ===========================================================================

# The catch-all is "macroinvertebrates", which in a marine study means a
# benthic marine invertebrate. Anything animal that no rule matched became one,
# so a millipede, a dipluran, a frog and a turtle were all benthic marine
# invertebrates. These are not kingdom problems -- every one of these rows has
# kingdom Animalia -- so the phylum fallback cannot see them.

test_that("terrestrial myriapods and diplurans are terrestrial, not benthic", {
  for (cl in c("Diplopoda", "Diplura")) {
    r <- .sg_one(kingdom = "Animalia", phylum = "Arthropoda", class = cl)
    expect_equal(r$group, "terrestrial_arthropods", info = cl)
    expect_equal(r$basis, "rule", info = cl)
  }
  # The centipedes were already there; this is the sibling that was missing.
  expect_equal(
    .sg_one(kingdom = "Animalia", phylum = "Arthropoda", class = "Chilopoda")$group,
    "terrestrial_arthropods"
  )
})

test_that("amphibians and reptiles get their own group", {
  for (cl in c("Amphibia", "Reptilia")) {
    r <- .sg_one(kingdom = "Animalia", phylum = "Chordata", class = cl)
    expect_equal(r$group, "other_vertebrates", info = cl)
  }
  # Backbones disagree about where the reptile ranks sit, so the ORDER
  # spellings must work with no class supplied.
  for (or in c("Testudines", "Squamata", "Crocodylia")) {
    r <- .sg_one(kingdom = "Animalia", phylum = "Chordata", order = or)
    expect_equal(r$group, "other_vertebrates", info = or)
  }
  # The reptile names at CLASS rank, with no order. GBIF's backbone really
  # does carry class Testudines this way, and a rule that knew Testudines only
  # as an order left those rows in the catch-all as "macroinvertebrates" --
  # found by measuring against real data, not by reading the rule.
  for (cl in c("Testudines", "Squamata", "Crocodylia", "Lepidosauria")) {
    r <- .sg_one(kingdom = "Animalia", phylum = "Chordata", class = cl)
    expect_equal(r$group, "other_vertebrates", info = cl)
    expect_equal(r$basis, "rule", info = cl)
  }
  # And the classes it began with are unaffected.
  expect_equal(
    .sg_one(kingdom = "Animalia", phylum = "Chordata", class = "Aves")$group,
    "birds_mammals"
  )
})

test_that("Hydrozoa splits by habit, and the clause order is the rule", {
  hz <- function(order = NA_character_, family = NA_character_) {
    tax <- data.frame(
      kingdom = "Animalia", phylum = "Cnidaria", class = "Hydrozoa",
      order = order, family = family, stringsAsFactors = FALSE
    )
    out <- assign_sampling_group(tax, verbose = FALSE)
    out$sampling_group[[1L]]
  }
  # Benthic colonial hydroids: macroinvertebrates.
  expect_equal(hz(order = "Leptothecata"), "macroinvertebrates")
  expect_equal(hz(order = "Anthoathecata"), "macroinvertebrates")
  # The floating families are Anthoathecata but pelagic, and must win over the
  # order clause. If these two rules were ever reordered, Porpita and Velella
  # would be sent to the benthos and this is the assertion that says so.
  expect_equal(hz(order = "Anthoathecata", family = "Porpitidae"), "zooplankton")
  expect_equal(hz(order = "Anthoathecata", family = "Velellidae"), "zooplankton")
  expect_equal(hz(order = "Anthoathecata", family = "Hydridae"), "zooplankton")
  # The rest of the class stays zooplankton, via the class clause.
  expect_equal(hz(), "zooplankton")
  expect_equal(hz(order = "Siphonophorae"), "zooplankton")
  # And the true jellyfish beside it are untouched.
  expect_equal(
    .sg_one(kingdom = "Animalia", phylum = "Cnidaria", class = "Scyphozoa")$group,
    "zooplankton"
  )
})

test_that("a family rule still works when no family column is supplied", {
  # The family clause reads the column directly, so a frame without one must
  # simply not match rather than error.
  tax <- data.frame(
    kingdom = "Animalia", phylum = "Cnidaria", class = "Hydrozoa",
    order = "Anthoathecata", stringsAsFactors = FALSE
  )
  out <- assign_sampling_group(tax, verbose = FALSE)
  expect_equal(out$sampling_group[[1L]], "macroinvertebrates")
})

test_that("an explicit fish class beats a contradictory reptile order", {
  # The tetrapod rule runs ahead of the fishes rule, so without a guard on a
  # missing class an explicit fish CLASS would lose to a reptile ORDER. Only
  # contradictory taxonomy reaches this, but class is the more reliable rank
  # and the row should follow it.
  for (cl in c("Actinopteri", "Teleostei", "Chondrichthyes")) {
    r <- .sg_one(kingdom = "Animalia", phylum = "Chordata",
                 class = cl, order = "Testudines")
    expect_equal(r$group, "fishes", info = cl)
  }
  # And a turtle with no class still reaches the tetrapods.
  expect_equal(
    .sg_one(kingdom = "Animalia", phylum = "Chordata", order = "Testudines")$group,
    "other_vertebrates"
  )
  # The tuatara, which has no class in GBIF, now goes with the tetrapods too.
  expect_equal(
    .sg_one(kingdom = "Animalia", phylum = "Chordata", order = "Rhynchocephalia")$group,
    "other_vertebrates"
  )
})

test_that("harmonise = TRUE does not probe the family rank", {
  # family is read by a rule but deliberately kept out of rank_cols, because
  # rank_cols drives the harmonise cascade finest-first: family there would
  # become the finest probe for every row that has one. This asserts the
  # default, so re-adding it fails here rather than silently changing every
  # harmonised lookup.
  # The formal is an unevaluated call, so evaluate it before testing it.
  default_ranks <- eval(formals(assign_sampling_group)$rank_cols)
  expect_false("family" %in% default_ranks)
  expect_equal(default_ranks, c("kingdom", "phylum", "class", "order"))
})

test_that("an empty-string family is still normalised", {
  # It is out of rank_cols but a rule reads it, so its "" must become NA or
  # the family clause could match an empty string.
  tax <- data.frame(
    kingdom = "Animalia", phylum = "Cnidaria", class = "Hydrozoa",
    order = "Anthoathecata", family = "", stringsAsFactors = FALSE
  )
  out <- assign_sampling_group(tax, verbose = FALSE)
  expect_equal(out$sampling_group[[1L]], "macroinvertebrates")
})
