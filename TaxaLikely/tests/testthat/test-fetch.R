# tests/testthat/test-fetch.R
# Tests for fetch_ncbi_reference_sequences() and read_reference_fasta() --
# input validation only (network tests are separate)

# ---- fetch_ncbi_reference_sequences validation --------------------------------

test_that("fetch_ncbi_reference_sequences errors on non-character taxa", {
  expect_error(
    fetch_ncbi_reference_sequences(taxa = 123, barcode_term = "COI"),
    "character"
  )
})

test_that("fetch_ncbi_reference_sequences errors on missing barcode_term", {
  expect_error(
    fetch_ncbi_reference_sequences(taxa = "Gadidae"),
    'argument "barcode_term" is missing'
  )
})

# ---- fetch_bold_reference_sequences validation --------------------------------

test_that("fetch_bold_reference_sequences errors on non-character taxa", {
  expect_error(
    fetch_bold_reference_sequences(taxa = 123),
    "character"
  )
})

test_that("fetch_bold_reference_sequences errors on non-character barcode_term", {
  expect_error(
    fetch_bold_reference_sequences(taxa = "Fundulus", barcode_term = 123),
    "barcode_term"
  )
})

test_that("fetch_bold_reference_sequences errors on empty rank_system", {
  expect_error(
    fetch_bold_reference_sequences(taxa = "Fundulus", rank_system = character(0L)),
    "rank_system"
  )
})

test_that("fetch_bold_reference_sequences errors on invalid max_per_species", {
  expect_error(
    fetch_bold_reference_sequences(taxa = "Fundulus", max_per_species = -1),
    "max_per_species"
  )
  expect_error(
    fetch_bold_reference_sequences(taxa = "Fundulus", max_per_species = "a"),
    "max_per_species"
  )
})

# ---- .parse_bold_coord (internal) ---------------------------------------------

test_that(".parse_bold_coord parses a well-formed bracketed coord string", {
  pbc <- TaxaLikely:::.parse_bold_coord
  out <- pbc("[33.1518, -117.181]")
  expect_equal(unname(out["lat"]), 33.1518)
  expect_equal(unname(out["lon"]), -117.181)
})

test_that(".parse_bold_coord returns NA on NA/empty/malformed input", {
  pbc <- TaxaLikely:::.parse_bold_coord
  expect_true(all(is.na(pbc(NA_character_))))
  expect_true(all(is.na(pbc(""))))
  expect_true(all(is.na(pbc("not a coord"))))
  expect_true(all(is.na(pbc(NULL))))
})

# ---- fetch_bold_reference_sequences end-to-end (mocked, offline) -------------
# Mocks the three internal API-calling helpers so the combining/filtering/
# reshape logic is tested without live network calls, matching the mocking
# convention already used in test-build-site-reference.R.

test_that("fetch_bold_reference_sequences combines taxa with different columns (bind_rows, not rbind)", {
  # Real bug found via live testing (Session 136): different taxa can return
  # different column sets from BOLD's TSV export; a plain rbind() errors.
  docs_a <- data.frame(processid = "A1", nuc = "ACGT", marker_code = "COI-5P",
                       family = "Fam1", genus = "G1", species = "G1 s1",
                       coord = "[1.0, 2.0]", `country/ocean` = "USA",
                       check.names = FALSE, stringsAsFactors = FALSE)
  docs_b <- data.frame(processid = "B1", nuc = "TTTT", marker_code = "COI-5P",
                       family = "Fam2", genus = "G2", species = "G2 s2",
                       extra_col_only_here = "x",
                       stringsAsFactors = FALSE)

  local_mocked_bindings(
    .bold_resolve_taxon  = function(taxon) paste0("tax:genus:", taxon),
    .bold_submit_query   = function(triplet, extent = "full") paste0("qid_", triplet),
    .bold_fetch_documents = function(query_id) {
      if (grepl("G1", query_id)) docs_a else docs_b
    },
    .package = "TaxaLikely"
  )

  ref <- suppressMessages(fetch_bold_reference_sequences(taxa = c("G1", "G2")))
  expect_equal(nrow(ref), 2L)
  expect_setequal(ref$composite_id, c("A1", "B1"))
})

test_that("fetch_bold_reference_sequences applies client-side barcode_term filter on marker_code", {
  docs <- data.frame(
    processid   = c("A1", "A2"),
    nuc         = c("ACGT", "TTTT"),
    marker_code = c("COI-5P", "COI-3P"),
    family = "Fam1", genus = "G1", species = c("G1 s1", "G1 s2"),
    stringsAsFactors = FALSE
  )
  local_mocked_bindings(
    .bold_resolve_taxon  = function(taxon) "tax:genus:G1",
    .bold_submit_query   = function(triplet, extent = "full") "qid1",
    .bold_fetch_documents = function(query_id) docs,
    .package = "TaxaLikely"
  )

  ref <- suppressMessages(fetch_bold_reference_sequences(taxa = "G1", barcode_term = "COI-5P"))
  expect_equal(nrow(ref), 1L)
  expect_equal(ref$composite_id, "A1")
})

test_that("fetch_bold_reference_sequences parses coord into lat/lon and keeps country", {
  docs <- data.frame(
    processid = "A1", nuc = "ACGT", marker_code = "COI-5P",
    family = "Fam1", genus = "G1", species = "G1 s1",
    coord = "[10.5, -85.2]", `country/ocean` = "Costa Rica",
    check.names = FALSE, stringsAsFactors = FALSE
  )
  local_mocked_bindings(
    .bold_resolve_taxon  = function(taxon) "tax:genus:G1",
    .bold_submit_query   = function(triplet, extent = "full") "qid1",
    .bold_fetch_documents = function(query_id) docs,
    .package = "TaxaLikely"
  )

  ref <- suppressMessages(fetch_bold_reference_sequences(taxa = "G1"))
  expect_equal(ref$lat, 10.5)
  expect_equal(ref$lon, -85.2)
  expect_equal(ref$country, "Costa Rica")
})

test_that("fetch_bold_reference_sequences omits location columns when include_location = FALSE", {
  docs <- data.frame(
    processid = "A1", nuc = "ACGT", marker_code = "COI-5P",
    family = "Fam1", genus = "G1", species = "G1 s1",
    coord = "[10.5, -85.2]", `country/ocean` = "Costa Rica",
    check.names = FALSE, stringsAsFactors = FALSE
  )
  local_mocked_bindings(
    .bold_resolve_taxon  = function(taxon) "tax:genus:G1",
    .bold_submit_query   = function(triplet, extent = "full") "qid1",
    .bold_fetch_documents = function(query_id) docs,
    .package = "TaxaLikely"
  )

  ref <- suppressMessages(fetch_bold_reference_sequences(taxa = "G1", include_location = FALSE))
  expect_false("lat" %in% names(ref))
  expect_false("lon" %in% names(ref))
  expect_false("country" %in% names(ref))
})

test_that("fetch_bold_reference_sequences returns empty typed data frame when a taxon can't be resolved", {
  local_mocked_bindings(
    .bold_resolve_taxon = function(taxon) NA_character_,
    .package = "TaxaLikely"
  )

  ref <- suppressWarnings(suppressMessages(fetch_bold_reference_sequences(taxa = "Nonexistentgenusxyz")))
  expect_equal(nrow(ref), 0L)
  expect_equal(names(ref), c("composite_id", "sequence"))
})

# ---- read_reference_fasta validation -----------------------------------------

test_that("read_reference_fasta errors on non-existent file", {
  expect_error(
    read_reference_fasta("/nonexistent/path.fasta",
                         taxonomy = data.frame(composite_id = "x"),
                         rank_system = "species"),
    "not found"
  )
})

test_that("read_reference_fasta errors on non-data-frame taxonomy", {
  # Create a temp fasta file
  tmp <- tempfile(fileext = ".fasta")
  writeLines(c(">seq1", "ATCG"), tmp)
  on.exit(unlink(tmp))

  expect_error(
    read_reference_fasta(tmp, taxonomy = list(), rank_system = "species"),
    "must be a data frame"
  )
})

test_that("read_reference_fasta errors on empty FASTA", {
  tmp <- tempfile(fileext = ".fasta")
  file.create(tmp)
  on.exit(unlink(tmp))

  expect_error(
    read_reference_fasta(tmp,
                         taxonomy = data.frame(composite_id = "x", species = "A"),
                         rank_system = "species"),
    "empty"
  )
})

# ---- .build_search_term (internal) -------------------------------------------

test_that(".build_search_term builds correct NCBI query with GENE tags", {
  # Access internal function
  bst <- TaxaLikely:::.build_search_term

  out <- bst("Gadidae", "COI")
  expect_true(grepl("Gadidae\\[Organism\\]", out))
  expect_true(grepl("COI\\[GENE\\]", out))
})

test_that(".build_search_term uses All Fields for primer names", {
  bst <- TaxaLikely:::.build_search_term
  out <- bst("Gadidae", "MiFish")
  expect_true(grepl("MiFish\\[All Fields\\]", out))
})

test_that(".build_search_term adds date clause", {
  bst <- TaxaLikely:::.build_search_term
  out <- bst("Gadidae", "12S", min_date = "2020/01/01", max_date = "2024/12/31")
  expect_true(grepl("\\[PDAT\\]", out))
  expect_true(grepl("2020/01/01", out))
})

test_that(".build_search_term uses All Fields for ribosomal subunits", {
  bst <- TaxaLikely:::.build_search_term
  out12 <- bst("Gadidae", "12S")
  expect_true(grepl("12S\\[All Fields\\]", out12))
  out16 <- bst("Gadidae", "16S")
  expect_true(grepl("16S\\[All Fields\\]", out16))
})

test_that(".build_search_term ORs multiple barcode terms", {
  bst <- TaxaLikely:::.build_search_term
  out <- bst("Gadidae", c("12S", "16S"))
  expect_true(grepl("12S\\[All Fields\\]", out))
  expect_true(grepl("16S\\[All Fields\\]", out))
  expect_true(grepl(" OR ", out))
})

test_that(".build_search_term ORs in ribosomal-subunit synonyms for bare 12S/16S", {
  # Real, confirmed gap (Session 154 / Mugu debugging): many GenBank 12S/16S
  # submissions describe the gene as "small/large subunit ribosomal RNA"
  # rather than literally "12S"/"16S" -- a bare marker-name search misses
  # them entirely. Regression-locks the fix, not just the pre-existing
  # substring checks above (which still pass unchanged since "12S[All Fields]"
  # remains one of several OR'd clauses).
  bst <- TaxaLikely:::.build_search_term
  out12 <- bst("Gadidae", "12S")
  expect_true(grepl('"small subunit ribosomal RNA"\\[All Fields\\]', out12))
  expect_true(grepl('"12S ribosomal RNA"\\[All Fields\\]', out12))
  expect_true(grepl('"12S rRNA"\\[All Fields\\]', out12))

  out16 <- bst("Gadidae", "16S")
  expect_true(grepl('"large subunit ribosomal RNA"\\[All Fields\\]', out16))
  expect_true(grepl('"16S ribosomal RNA"\\[All Fields\\]', out16))
  expect_true(grepl('"16S rRNA"\\[All Fields\\]', out16))
})

test_that(".build_search_term does NOT apply ribosomal-subunit synonyms to 18S", {
  # Deliberate scope limit: "small subunit ribosomal RNA" is ambiguous between
  # mitochondrial 12S and nuclear 18S -- reusing it for 18S would trade missed
  # true positives for new false positives, a different tradeoff needing its
  # own design (not attempted here).
  bst <- TaxaLikely:::.build_search_term
  out18 <- bst("Gadidae", "18S")
  expect_false(grepl("subunit ribosomal RNA", out18))
  expect_true(grepl("18S\\[All Fields\\]", out18))
})

test_that(".build_search_term leaves GENE-tagged and primer-name terms unaffected by the synonym fix", {
  bst <- TaxaLikely:::.build_search_term
  expect_identical(bst("Gadidae", "COI"), "Gadidae[Organism] AND COI[GENE]")
  expect_identical(
    bst("Gadidae", "MiFishU"),
    "Gadidae[Organism] AND (MiFishU[All Fields] OR 12S[All Fields])"
  )
})

# ---- .parse_lat_lon (internal) ------------------------------------------------

test_that(".parse_lat_lon parses well-formed N/E coordinates", {
  pll <- TaxaLikely:::.parse_lat_lon
  out <- pll("36.789 N 121.947 E")
  expect_equal(unname(out["lat"]), 36.789)
  expect_equal(unname(out["lon"]), 121.947)
})

test_that(".parse_lat_lon negates S and W", {
  pll <- TaxaLikely:::.parse_lat_lon
  out <- pll("36.789 S 121.947 W")
  expect_equal(unname(out["lat"]), -36.789)
  expect_equal(unname(out["lon"]), -121.947)
})

test_that(".parse_lat_lon is case-insensitive on hemisphere letters", {
  pll <- TaxaLikely:::.parse_lat_lon
  out <- pll("36.789 s 121.947 w")
  expect_equal(unname(out["lat"]), -36.789)
  expect_equal(unname(out["lon"]), -121.947)
})

test_that(".parse_lat_lon returns NA on NA/empty/malformed input", {
  pll <- TaxaLikely:::.parse_lat_lon
  expect_true(all(is.na(pll(NA_character_))))
  expect_true(all(is.na(pll(""))))
  expect_true(all(is.na(pll("not a coordinate"))))
  expect_true(all(is.na(pll("missing: true"))))
})

test_that(".parse_lat_lon returns NA on NULL/multi-length input", {
  pll <- TaxaLikely:::.parse_lat_lon
  expect_true(all(is.na(pll(NULL))))
  expect_true(all(is.na(pll(c("36.789 N 121.947 W", "1 N 2 E")))))
})

# ---- .fetch_locations_batched (internal) --------------------------------------

test_that(".fetch_locations_batched returns empty typed data frame for no accessions", {
  flb <- TaxaLikely:::.fetch_locations_batched
  out <- flb(character(0L))
  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 0L)
  expect_equal(names(out), c("composite_id", "lat", "lon", "country"))
})
