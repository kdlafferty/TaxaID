# ---- barcode_length_defaults --------------------------------------------------

test_that("barcode_length_defaults is a named list of 2-element integer vectors", {
  expect_type(barcode_length_defaults, "list")
  expect_true(length(barcode_length_defaults) > 0L)
  for (nm in names(barcode_length_defaults)) {
    v <- barcode_length_defaults[[nm]]
    expect_length(v, 2L)
    expect_true(v[1] < v[2], info = paste0("min < max for '", nm, "'"))
  }
})

test_that("barcode_length_defaults has expected markers", {
  expect_true(all(c("coi", "12s", "its2") %in% names(barcode_length_defaults)))
})

# ---- resolve_barcode_lengths -------------------------------------------------

test_that("resolve_barcode_lengths returns named 2-element integer vector for known marker", {
  out <- resolve_barcode_lengths("COI")
  expect_length(out, 2L)
  expect_named(out, c("min_bp", "max_bp"))
  expect_equal(unname(out), c(300L, 900L))
})

test_that("resolve_barcode_lengths is case-insensitive", {
  expect_equal(resolve_barcode_lengths("coi"), resolve_barcode_lengths("COI"))
})

test_that("resolve_barcode_lengths handles prefix matching (MiFishU -> mifish)", {
  out <- resolve_barcode_lengths("MiFishU")
  expect_named(out, c("min_bp", "max_bp"))
  expect_equal(unname(out), c(130L, 210L))
})

test_that("resolve_barcode_lengths unions multiple markers", {
  out <- resolve_barcode_lengths(c("12S", "16S"))
  expect_equal(out[["min_bp"]], 100L)
  expect_equal(out[["max_bp"]], 700L)
})

test_that("resolve_barcode_lengths allows user overrides", {
  out <- resolve_barcode_lengths("COI", min_len = 500L)
  expect_equal(out[["min_bp"]], 500L)
  expect_equal(out[["max_bp"]], 900L)
})

test_that("resolve_barcode_lengths short-circuits when both overrides given", {
  out <- resolve_barcode_lengths("UNKNOWN_MARKER", min_len = 100, max_len = 500)
  expect_named(out, c("min_bp", "max_bp"))
  expect_equal(unname(out), c(100L, 500L))
})

test_that("resolve_barcode_lengths errors when min_len > max_len", {
  expect_error(
    resolve_barcode_lengths("COI", min_len = 900, max_len = 300),
    "min_len.*greater than max_len"
  )
})

test_that("resolve_barcode_lengths uses fallback for unknown marker", {
  expect_message(
    out <- resolve_barcode_lengths("TOTALLY_UNKNOWN"),
    "No length defaults"
  )
  expect_named(out, c("min_bp", "max_bp"))
  expect_equal(unname(out), c(100L, 2000L))
})

# ---- barcode_primer_defaults / resolve_barcode_primers ----------------------

test_that("barcode_primer_defaults entries have fwd/rev/amplicon_range", {
  expect_true(length(barcode_primer_defaults) > 0L)
  for (nm in names(barcode_primer_defaults)) {
    entry <- barcode_primer_defaults[[nm]]
    expect_true(all(c("fwd", "rev", "amplicon_range") %in% names(entry)), info = nm)
    expect_type(entry$fwd, "character")
    expect_type(entry$rev, "character")
    expect_length(entry$amplicon_range, 2L)
    expect_true(entry$amplicon_range[1] < entry$amplicon_range[2], info = nm)
  }
})

test_that("resolve_barcode_primers exact-matches a specific variant, case/separator-insensitive", {
  out1 <- resolve_barcode_primers("MiFishU")
  out2 <- resolve_barcode_primers("mifish-u")
  out3 <- resolve_barcode_primers("MIFISH_U")
  expect_equal(out1, out2)
  expect_equal(out1, out3)
  expect_equal(out1$fwd, "GTCGGTAAAACTCGTGCCAGC")
  expect_equal(out1$rev, "CATAGTGGGGTATCTAATCCCAGTTTG")
})

test_that("resolve_barcode_primers distinguishes MiFish-U from MiFish-E", {
  u <- resolve_barcode_primers("MiFishU")
  e <- resolve_barcode_primers("MiFishE")
  expect_false(identical(u$fwd, e$fwd))
  expect_false(identical(u$rev, e$rev))
})

test_that("resolve_barcode_primers errors (not guesses) on ambiguous bare 'mifish'", {
  expect_error(resolve_barcode_primers("mifish"), "ambiguous")
})

test_that("resolve_barcode_primers errors clearly on an unregistered marker", {
  expect_error(resolve_barcode_primers("ITS2"), "no primer defaults found")
})

test_that("resolve_barcode_primers resolves bare marker names unambiguously for the mito/chloroplast entries", {
  s16 <- resolve_barcode_primers("16S")
  expect_equal(s16$fwd, "CGCCTGTTTATCAAAAACAT")
  expect_equal(s16$rev, "CCGGTCTGAACTCAGATCACGT")

  coi <- resolve_barcode_primers("COI-Folmer")
  expect_equal(coi$fwd, "GGTCAACAAATCATAAAGATATTGG")
  expect_equal(coi$rev, "TAAACTTCAGGGTGACCAAAAAATCA")

  cytb <- resolve_barcode_primers("cytb")
  expect_equal(cytb$fwd, "CCATCCAACATCTCAGCATGATGAAA")
  expect_equal(cytb$rev, "CCCCTCAGAATGATATTTGTCCTCA")

  rbcl <- resolve_barcode_primers("rbcL")
  expect_equal(rbcl$fwd, "ATGTCACCACAAACAGAGACTAAAGC")
  expect_equal(rbcl$rev, "GTAAAATCAAGTCCACCRCG")

  matk <- resolve_barcode_primers("matK")
  expect_equal(matk$fwd, "CGTACAGTACTTTTGTGTTTACGAG")
  expect_equal(matk$rev, "ACCCAGTCCATCTGGAAATCTTGGTTC")

  trnl <- resolve_barcode_primers("trnL")
  expect_equal(trnl$fwd, "GGGCAATCCTGAGCCAA")
  expect_equal(trnl$rev, "CCATTGAGTCTCTGCACCTATC")
})

test_that("resolve_barcode_primers distinguishes COI-Folmer from COI-Leray", {
  folmer <- resolve_barcode_primers("COI-Folmer")
  leray <- resolve_barcode_primers("COI-Leray")
  expect_false(identical(folmer$fwd, leray$fwd))
  expect_false(identical(folmer$rev, leray$rev))
  expect_equal(leray$fwd, "GGWACWGGWTGAACWGTWTAYCCYCC")
  expect_equal(leray$rev, "TAAACTTCAGGGTGACCAAARAAYCA")
})

test_that("resolve_barcode_primers errors (not guesses) on ambiguous bare 'COI' now that two variants are registered", {
  expect_error(resolve_barcode_primers("COI"), "ambiguous")
})

test_that("resolve_barcode_primers validates input", {
  expect_error(resolve_barcode_primers(NULL), "single non-empty string")
  expect_error(resolve_barcode_primers(""), "single non-empty string")
  expect_error(resolve_barcode_primers(c("a", "b")), "single non-empty string")
  expect_error(resolve_barcode_primers(NA_character_), "single non-empty string")
})

# ---- is_plausible_binomial --------------------------------------------------

test_that("is_plausible_binomial accepts valid binomials", {
  expect_true(is_plausible_binomial("Cottus asper"))
  expect_true(is_plausible_binomial("Fundulus parvipinnis"))
})

test_that("is_plausible_binomial rejects sp. and cf.", {
  expect_false(is_plausible_binomial("Cottus sp."))
  expect_false(is_plausible_binomial("cf. Cottus asper"))
  expect_false(is_plausible_binomial("Cottus cf. asper"))
})

test_that("is_plausible_binomial rejects aff. and uncultured", {
  expect_false(is_plausible_binomial("Cottus aff. asper"))
  expect_false(is_plausible_binomial("uncultured bacterium"))
  expect_false(is_plausible_binomial("environmental sample"))
})

test_that("is_plausible_binomial rejects single-word names", {
  expect_false(is_plausible_binomial("Cottus"))
  expect_false(is_plausible_binomial("cottus"))
})

test_that("is_plausible_binomial is vectorized", {
  out <- is_plausible_binomial(c("Cottus asper", "Cottus sp.", "Enophrys bison"))
  expect_equal(out, c(TRUE, FALSE, TRUE))
})

# ---- resolve_barcode_marker --------------------------------------------------
# A primer-variant term is right for primers/lengths but is not indexed by any
# sequence database. Searching on it matches nothing, and "nothing found" is a
# legitimate search result, so the failure is SILENT: downstream it reads as
# "this species has no barcode" rather than "this query was malformed". Multiple
# call sites built queries this way (TaxaLikely's fetch, coverage, and
# suggest_unreferenced_species()), which is why the map lives here.

test_that("resolve_barcode_marker maps every registered primer variant to its marker", {
  expect_identical(resolve_barcode_marker("COI-Folmer"), "COI")
  expect_identical(resolve_barcode_marker("COI-Leray"), "COI")
  expect_identical(resolve_barcode_marker("16S-Palumbi"), "16S")
  expect_identical(resolve_barcode_marker("cytb-Kocher"), "cytb")
  expect_identical(resolve_barcode_marker("rbcLa"), "rbcL")
  expect_identical(resolve_barcode_marker("matK-Kim"), "matK")
  expect_identical(resolve_barcode_marker("trnL-Taberlet"), "trnL")
})

test_that("resolve_barcode_marker is case- and whitespace-insensitive", {
  expect_identical(resolve_barcode_marker("coi-folmer"), "COI")
  expect_identical(resolve_barcode_marker("  COI-FOLMER "), "COI")
})

test_that("resolve_barcode_marker leaves plain markers and unknown terms alone", {
  # A bare marker is already searchable.
  expect_identical(resolve_barcode_marker("12S"), "12S")
  expect_identical(resolve_barcode_marker("COI"), "COI")
  # An unregistered/custom term must still search as itself, not be swallowed.
  expect_identical(resolve_barcode_marker("my-lab-primer"), "my-lab-primer")
})

test_that("resolve_barcode_marker deliberately does NOT remap MiFish terms", {
  # Unlike the others, real records ARE annotated with the MiFish primer name,
  # so the variant is genuinely searchable and callers OR it with 12S.
  expect_identical(resolve_barcode_marker("MiFishU"), "MiFishU")
  expect_identical(resolve_barcode_marker("mifish-e"), "mifish-e")
})

test_that("resolve_barcode_marker is vectorised and NULL/NA-safe", {
  expect_identical(
    resolve_barcode_marker(c("COI-Folmer", "12S", "rbcLa")),
    c("COI", "12S", "rbcL")
  )
  expect_null(resolve_barcode_marker(NULL))
  expect_identical(resolve_barcode_marker(NA_character_), NA_character_)
  expect_error(resolve_barcode_marker(12), "character")
})
