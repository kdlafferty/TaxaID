# tests/testthat/test-clean_taxon_names.R
#
# Tests for clean_taxon_names()
# All tests are offline — no API calls.
#
# Design: clean_taxon_names() preserves input length. Invalid names become NA.
# Callers add unique() or na.omit() as needed.

# ==============================================================================
# Input validation
# ==============================================================================

test_that("rejects non-character input", {
  expect_error(clean_taxon_names(123),      "`name_vec` must be a character vector")
  expect_error(clean_taxon_names(TRUE),     "`name_vec` must be a character vector")
  expect_error(clean_taxon_names(list("Homo sapiens")), "`name_vec` must be a character vector")
})

# ==============================================================================
# Length preservation
# ==============================================================================

test_that("output length matches input length", {
  input <- c("Homo sapiens", "mus musculus", NA, "sp.", "Canis lupus sp.")
  out <- clean_taxon_names(input)
  expect_equal(length(out), length(input))
})

# ==============================================================================
# NA and empty handling
# ==============================================================================

test_that("NA inputs become NA in output", {
  out <- clean_taxon_names(c("Homo sapiens", NA))
  expect_equal(out, c("Homo sapiens", NA), ignore_attr = "collapsed_to_genus")
})

test_that("string 'NA' and '<NA>' become NA", {
  out <- clean_taxon_names(c("Homo sapiens", "NA", "<NA>"))
  expect_equal(out, c("Homo sapiens", NA, NA), ignore_attr = "collapsed_to_genus")
})

test_that("all-NA input returns NA vector of same length", {
  out <- clean_taxon_names(c(NA_character_, NA_character_))
  expect_equal(out, c(NA_character_, NA_character_), ignore_attr = "collapsed_to_genus")
})

test_that("empty character vector returns empty character vector", {
  out <- clean_taxon_names(character(0))
  expect_equal(out, character(0), ignore_attr = "collapsed_to_genus")
})

# ==============================================================================
# Case filtering
# ==============================================================================

test_that("names not starting with capital become NA", {
  out <- clean_taxon_names(c("Homo sapiens", "mus musculus", "unknown"))
  expect_equal(out, c("Homo sapiens", NA, NA), ignore_attr = "collapsed_to_genus")
})

# ==============================================================================
# Whitespace normalisation
# ==============================================================================

test_that("trims leading and trailing whitespace", {
  out <- clean_taxon_names(c("  Homo sapiens  "))
  expect_equal(out, "Homo sapiens", ignore_attr = "collapsed_to_genus")
})

test_that("collapses internal whitespace", {
  out <- clean_taxon_names(c("Homo  sapiens"))
  expect_equal(out, "Homo sapiens", ignore_attr = "collapsed_to_genus")
})

# ==============================================================================
# Abbreviation handling
# ==============================================================================

test_that("trims 'sp.' to genus-only", {
  out <- clean_taxon_names(c("Canis sp."))
  expect_equal(out, "Canis", ignore_attr = "collapsed_to_genus")
})

test_that("trims 'spp.' to genus-only", {
  out <- clean_taxon_names(c("Canis spp."))
  expect_equal(out, "Canis", ignore_attr = "collapsed_to_genus")
})

test_that("trims 'spp' (no dot) to genus-only", {
  out <- clean_taxon_names(c("Canis spp"))
  expect_equal(out, "Canis", ignore_attr = "collapsed_to_genus")
})

test_that("trims 'species' to genus-only", {
  out <- clean_taxon_names(c("Canis species"))
  expect_equal(out, "Canis", ignore_attr = "collapsed_to_genus")
})

test_that("trims 'unknown' epithet to genus-only", {
  out <- clean_taxon_names(c("Canis unknown"))
  expect_equal(out, "Canis", ignore_attr = "collapsed_to_genus")
})

test_that("bare abbreviation-only name retains genus", {
  # Starts with capital so passes case filter; no epithet — genus retained.
  out <- clean_taxon_names(c("Sp."))
  expect_equal(out, "Sp.", ignore_attr = "collapsed_to_genus")
})

test_that("valid two-word name is not truncated to genus", {
  out <- clean_taxon_names(c("Homo sapiens"))
  expect_equal(out, "Homo sapiens", ignore_attr = "collapsed_to_genus")
})

# ==============================================================================
# Bracket artefact removal
# ==============================================================================

test_that("strips square brackets around genus", {
  out <- clean_taxon_names(c("[Bacillus] subtilis"))
  expect_equal(out, "Bacillus subtilis", ignore_attr = "collapsed_to_genus")
})

test_that("strips parentheses from names", {
  out <- clean_taxon_names(c("Bacillus (subtilis)"))
  # Epithet is retained but parens removed; re-squished
  expect_false(grepl("[()]", out))
})

# ==============================================================================
# Duplicates are preserved (caller's responsibility to deduplicate)
# ==============================================================================

test_that("duplicates are preserved in output", {
  out <- clean_taxon_names(c("Homo sapiens", "Homo sapiens", "Homo sapiens"))
  expect_equal(length(out), 3L)
  expect_equal(out, c("Homo sapiens", "Homo sapiens", "Homo sapiens"), ignore_attr = "collapsed_to_genus")
})

# ==============================================================================
# Author string trimming
# ==============================================================================

test_that("drops author string (third+ token)", {
  # "Linnaeus" is the third token — should be discarded
  out <- clean_taxon_names(c("Homo sapiens Linnaeus"))
  expect_equal(out, "Homo sapiens", ignore_attr = "collapsed_to_genus")
})

# ==============================================================================
# Custom remove_abbr
# ==============================================================================

test_that("custom remove_abbr replaces defaults", {
  # "mycustom" is not in the default list — would be kept normally
  # but passing it explicitly should cause it to be stripped
  out <- clean_taxon_names(c("Canis mycustom"), remove_abbr = c("mycustom"))
  expect_equal(out, "Canis", ignore_attr = "collapsed_to_genus")
})

# ==============================================================================
# Mixed input — integration
# ==============================================================================

test_that("handles a realistic mixed vector correctly", {
  input <- c(
    "Homo sapiens",
    "mus musculus",        # lowercase — NA
    NA,                    # NA — NA
    "sp.",                 # no capital — NA
    "Canis lupus sp.",     # "sp." is third token (author position) -> "Canis lupus"
    "Homo sapiens",        # duplicate — preserved
    "[Bacillus] subtilis"  # bracket artefact removed
  )
  out <- clean_taxon_names(input)
  expect_equal(length(out), length(input))
  expect_equal(out[1], "Homo sapiens")
  expect_true(is.na(out[2]))
  expect_true(is.na(out[3]))
  expect_true(is.na(out[4]))
  expect_equal(out[5], "Canis lupus")
  expect_equal(out[6], "Homo sapiens")
  expect_equal(out[7], "Bacillus subtilis")
})

# ==============================================================================
# Underscore-as-space normalisation (Jonah Ventures / SILVA pipelines)
# ==============================================================================

test_that("converts underscore binomial to space-separated", {
  out <- clean_taxon_names("Corallina_officinalis")
  expect_equal(out, "Corallina officinalis", ignore_attr = "collapsed_to_genus")
})

test_that("converts underscore binomial with hyphen in genus", {
  out <- clean_taxon_names("Pseudo-nitzschia_australis")
  expect_equal(out, "Pseudo-nitzschia australis", ignore_attr = "collapsed_to_genus")
})

test_that("does not alter names that already have a space", {
  out <- clean_taxon_names("Corallina officinalis")
  expect_equal(out, "Corallina officinalis", ignore_attr = "collapsed_to_genus")
})

test_that("does not alter OTU codes with uppercase+digit pattern", {
  # OTU_001: epithet starts with a digit, not [a-z] — regex does not match
  out <- clean_taxon_names("OTU_001")
  expect_equal(out, "OTU_001", ignore_attr = "collapsed_to_genus")  # returned unchanged (genus-only, no epithet)
})

test_that("does not alter clade codes like MAST-4", {
  # MAST-4 has no underscore at all — regex does not match
  out <- clean_taxon_names("MAST-4")
  expect_equal(out, "MAST-4", ignore_attr = "collapsed_to_genus")  # returned unchanged
})

test_that("does not alter multi-underscore strings", {
  # Genus_epithet_extra has two underscores — second underscore fails [A-Za-z.-]* anchor
  out <- clean_taxon_names("Genus_epithet_extra")
  expect_equal(out, "Genus_epithet_extra", ignore_attr = "collapsed_to_genus")  # returned unchanged (no conversion)
})

test_that("underscore conversion handles abbreviation stripping correctly", {
  # After conversion "Canis_sp." -> "Canis sp." -> stripped to "Canis"
  # But "Canis_sp." has underscore before "sp." which starts lowercase
  out <- clean_taxon_names("Canis_lupus")
  expect_equal(out, "Canis lupus", ignore_attr = "collapsed_to_genus")
})

test_that("mixed vector with underscore names", {
  input <- c("Corallina_officinalis", "Homo sapiens", "mus_musculus", NA)
  out <- clean_taxon_names(input)
  expect_equal(out[1], "Corallina officinalis")
  expect_equal(out[2], "Homo sapiens")
  expect_true(is.na(out[3]))   # starts lowercase — NA
  expect_true(is.na(out[4]))
})

# ==============================================================================
# strip_modifiers (2026-08-11): leading breeding/ploidy-manipulation terms
# ==============================================================================

test_that("strips a real leading breeding/ploidy modifier word (default list)", {
  # Real GenBank hybrid-cross records, GreatLakes 12S audit, 2026-08-11.
  out <- clean_taxon_names(c(
    "androgenetic Carassius auratus red var. x Megalobrama amblycephala",
    "autodiploid Carassius auratus red var. x Megalobrama amblycephala",
    "autotetraploid Carassius auratus red var. x Megalobrama amblycephala",
    "gynogenetic Carassius auratus", "allotriploid Cyprinus carpio",
    "tetraploid Cyprinus carpio", "polyploid Cyprinus carpio"
  ))
  expect_equal(out, c(rep("Carassius auratus", 4L), rep("Cyprinus carpio", 3L)), ignore_attr = "collapsed_to_genus")
})

test_that("strip_modifiers matching is case-insensitive on the first token only", {
  out <- clean_taxon_names("ANDROGENETIC Carassius auratus")
  expect_equal(out, "Carassius auratus", ignore_attr = "collapsed_to_genus")
})

test_that("strip_modifiers only removes ONE leading word, never a repeated run", {
  # Two leading lowercase words, the second NOT in strip_modifiers -- the
  # regression guard for a real failure mode found before shipping: a
  # repeated strip would consume the literal " x " hybrid marker itself
  # along with both words, silently misattributing the SECOND-listed (and
  # biologically unrelated) taxon as the intended one.
  out <- clean_taxon_names("androgenetic hybrid x Megalobrama amblycephala")
  expect_true(is.na(out))
})

test_that("strip_modifiers does not rescue an uncertainty-hedge word", {
  # Deliberately NOT in the default list -- a hedge should keep failing the
  # capital-letter filter, not get silently rescued into a confident binomial.
  out <- clean_taxon_names(c("possible Homo sapiens", "putative Cottus asper",
                             "cf. Cottus asper"))
  expect_true(all(is.na(out)))
})

test_that("strip_modifiers is a no-op for a name that already starts with a capital letter", {
  out <- clean_taxon_names("Ctenopharyngodon idella x Megalobrama amblycephala")
  expect_equal(out, "Ctenopharyngodon idella", ignore_attr = "collapsed_to_genus")
})

test_that("strip_modifiers = character(0) disables the step entirely", {
  out <- clean_taxon_names(
    "androgenetic Carassius auratus red var. x Megalobrama amblycephala",
    strip_modifiers = character(0)
  )
  expect_true(is.na(out))
})

test_that("strip_modifiers accepts a custom/extended list", {
  out <- clean_taxon_names("mutant Danio rerio", strip_modifiers = "mutant")
  expect_equal(out, "Danio rerio", ignore_attr = "collapsed_to_genus")
})

# ==============================================================================
# collapsed_to_genus attribute (2026-08-21)
# ==============================================================================

test_that("collapsed_to_genus is TRUE when a real epithet was dropped", {
  # Real motivating case: an open-nomenclature NCBI reference label with a
  # specimen voucher tag.
  out <- clean_taxon_names("Ictalurus cf. pricei USON-01120-1")
  expect_equal(out, "Ictalurus", ignore_attr = "collapsed_to_genus")
  expect_true(attr(out, "collapsed_to_genus"))
})

test_that("collapsed_to_genus is FALSE for input that was already genus-only", {
  out <- clean_taxon_names("Ictalurus")
  expect_equal(out, "Ictalurus", ignore_attr = "collapsed_to_genus")
  expect_false(attr(out, "collapsed_to_genus"))
})

test_that("collapsed_to_genus is FALSE for a well-formed binomial (nothing collapsed)", {
  out <- clean_taxon_names("Homo sapiens")
  expect_false(attr(out, "collapsed_to_genus"))
})

test_that("collapsed_to_genus is FALSE for a rejected (NA-output) name", {
  out <- clean_taxon_names(c("mus musculus", NA, "unknown"))
  expect_true(all(is.na(out)))
  expect_equal(attr(out, "collapsed_to_genus"), c(FALSE, FALSE, FALSE))
})

test_that("collapsed_to_genus is elementwise-correct across a mixed vector", {
  input <- c(
    "Ictalurus cf. pricei USON-01120-1",  # collapsed
    "Homo sapiens",                        # kept as binomial
    "Canis",                               # already genus-only
    NA,                                    # rejected
    "Canis sp."                            # collapsed
  )
  out <- clean_taxon_names(input)
  expect_equal(out, c("Ictalurus", "Homo sapiens", "Canis", NA, "Canis"), ignore_attr = "collapsed_to_genus")
  expect_equal(attr(out, "collapsed_to_genus"), c(TRUE, FALSE, FALSE, FALSE, TRUE))
})

test_that("collapsed_to_genus survives strip_modifiers stripping (still measures epithet collapse, not modifier stripping)", {
  # The leading modifier word is stripped BEFORE the genus/epithet split, so
  # this case is a genuine binomial after stripping -- collapsed_to_genus
  # should read FALSE, not TRUE.
  out <- clean_taxon_names("androgenetic Carassius auratus")
  expect_equal(out, "Carassius auratus", ignore_attr = "collapsed_to_genus")
  expect_false(attr(out, "collapsed_to_genus"))
})
