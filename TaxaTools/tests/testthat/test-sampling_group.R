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

test_that("kingdom guard does not fire when kingdom itself is missing", {
  tax <- data.frame(kingdom = NA_character_, phylum = "Something_unclassified",
                     class = NA_character_, order = NA_character_, stringsAsFactors = FALSE)
  out <- assign_sampling_group(tax, kingdom_guard = TRUE, verbose = FALSE)
  expect_equal(out$sampling_group, "macroinvertebrates")
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
