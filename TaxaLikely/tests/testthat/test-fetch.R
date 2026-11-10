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
  docs_a <- data.frame(
    processid = "A1", nuc = "ACGT", marker_code = "COI-5P",
    family = "Fam1", genus = "G1", species = "G1 s1",
    coord = "[1.0, 2.0]", `country/ocean` = "USA",
    check.names = FALSE, stringsAsFactors = FALSE
  )
  docs_b <- data.frame(
    processid = "B1", nuc = "TTTT", marker_code = "COI-5P",
    family = "Fam2", genus = "G2", species = "G2 s2",
    extra_col_only_here = "x",
    stringsAsFactors = FALSE
  )

  local_mocked_bindings(
    .bold_resolve_taxon = function(taxon) paste0("tax:genus:", taxon),
    .bold_submit_query = function(triplet, extent = "full") paste0("qid_", triplet),
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
    processid = c("A1", "A2"),
    nuc = c("ACGT", "TTTT"),
    marker_code = c("COI-5P", "COI-3P"),
    family = "Fam1", genus = "G1", species = c("G1 s1", "G1 s2"),
    stringsAsFactors = FALSE
  )
  local_mocked_bindings(
    .bold_resolve_taxon = function(taxon) "tax:genus:G1",
    .bold_submit_query = function(triplet, extent = "full") "qid1",
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
    .bold_resolve_taxon = function(taxon) "tax:genus:G1",
    .bold_submit_query = function(triplet, extent = "full") "qid1",
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
    .bold_resolve_taxon = function(taxon) "tax:genus:G1",
    .bold_submit_query = function(triplet, extent = "full") "qid1",
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
  # Same columns a successful return has (rank_system defaults to
  # family/genus/species, include_location defaults to TRUE) -- a bare
  # composite_id/sequence frame made a caller's ordinary next step
  # (clean_taxon_names(reference_df$species)) fail on NULL. See
  # .empty_reference_df().
  expect_equal(names(ref), c(
    "composite_id", "sequence", "family", "genus",
    "species", "lat", "lon", "country"
  ))
})

# ---- read_reference_fasta validation -----------------------------------------

test_that("read_reference_fasta errors on non-existent file", {
  expect_error(
    read_reference_fasta("/nonexistent/path.fasta",
      taxonomy = data.frame(composite_id = "x"),
      rank_system = "species"
    ),
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
      rank_system = "species"
    ),
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

test_that(".build_search_term uses txid<N>[ORGN] instead of the name when taxid supplied", {
  bst <- TaxaLikely:::.build_search_term
  out <- bst("Vertebrata", "COI", taxid = "1261581")
  expect_true(grepl("txid1261581\\[ORGN\\]", out, fixed = FALSE))
  expect_false(grepl("Vertebrata\\[Organism\\]", out))
})

test_that(".build_search_term ignores an NA or empty taxid", {
  bst <- TaxaLikely:::.build_search_term
  out_na <- bst("Gadidae", "COI", taxid = NA_character_)
  out_empty <- bst("Gadidae", "COI", taxid = "")
  expect_true(grepl("Gadidae\\[Organism\\]", out_na))
  expect_true(grepl("Gadidae\\[Organism\\]", out_empty))
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
  # Deliberate scope limit: "small subunit ribosomal RNA" names both
  # mitochondrial 12S and nuclear 18S, so it cannot identify an 18S record.
  # For 12S and 16S the same ambiguity is handled by searching the phrase only
  # within mitochondrion[FILTER]; that cannot help 18S, whose target IS the
  # nuclear subunit, so 18S still gets no subunit synonym at all.
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
    paste0(
      "Gadidae[Organism] AND (MiFishU[All Fields] OR 12S[All Fields] OR ",
      "\"12S ribosomal RNA\"[All Fields] OR \"12S rRNA\"[All Fields] OR ",
      "(\"small subunit ribosomal RNA\"[All Fields] AND mitochondrion[FILTER]))"
    )
  )
})

test_that(".build_search_term gives a MiFish primer term its marker's 12S synonyms", {
  # "MiFish-U" drives primer trimming in the screen; searched as-is it missed
  # records annotated only by a 12S synonym. One term should serve both jobs.
  bst <- TaxaLikely:::.build_search_term
  for (bt in c("MiFish-U", "MiFishU", "MiFish-E", "MiFish")) {
    out <- bst("Gadidae", bt)
    expect_true(grepl('"12S ribosomal RNA"\\[All Fields\\]', out), info = bt)
    expect_true(grepl('"small subunit ribosomal RNA"\\[All Fields\\]', out), info = bt)
    expect_true(grepl("12S\\[All Fields\\]", out), info = bt)
  }
  # a 16S primer term gets the 16S synonyms, not the 12S ones
  out16 <- bst("Gadidae", "vert02")
  expect_true(grepl('"large subunit ribosomal RNA"', out16))
  expect_false(grepl('"small subunit ribosomal RNA"', out16))
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

test_that(".parse_lat_lon rejects out-of-range (implausible) coordinates", {
  # Regex-matching but physically impossible -- must degrade to NA/NA like
  # any other unparseable input, not propagate an impossible coordinate.
  pll <- TaxaLikely:::.parse_lat_lon
  expect_true(all(is.na(pll("999.0 N 999.0 E"))))
  expect_true(all(is.na(pll("91.0 N 10.0 E")))) # lat just over 90
  expect_true(all(is.na(pll("10.0 N 181.0 E")))) # lon just over 180
})

test_that(".parse_lat_lon does not match a longitude-first string as if it were latitude-first", {
  # Extraction is validated by the hemisphere letter (N/S vs E/W), not
  # blind position -- a lon-then-lat ordering has no N/S letter where the
  # pattern requires one, so it fails to match entirely rather than being
  # silently assigned to the wrong axis.
  pll <- TaxaLikely:::.parse_lat_lon
  expect_true(all(is.na(pll("121.947 W 36.789 N"))))
})

# ---- .fetch_locations_batched (internal) --------------------------------------

test_that(".fetch_locations_batched returns empty typed data frame for no accessions", {
  flb <- TaxaLikely:::.fetch_locations_batched
  out <- flb(character(0L))
  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 0L)
  expect_equal(names(out), c("composite_id", "lat", "lon", "country"))
})

# ---- registered primer-variant terms resolve to their base marker -------------

test_that(".build_search_term resolves a primer-variant name to the marker it amplifies", {
  # A registered TaxaTools::barcode_primer_defaults variant name is correct for
  # primer/length resolution but is NOT indexed by NCBI -- no GenBank record is
  # tagged "Folmer". Before this fix every variant except the MiFish pair fell
  # through to a dead "<variant>[All Fields]" clause and returned zero hits for
  # every taxon (confirmed live: Leptocottus 0 vs 23, Paralabrax 0 vs 46).
  bst <- TaxaLikely:::.build_search_term

  # Each variant must produce EXACTLY the query its base marker produces.
  expect_identical(bst("Gadus", "COI-Folmer"), bst("Gadus", "COI"))
  expect_identical(bst("Gadus", "COI-Leray"), bst("Gadus", "COI"))
  expect_identical(bst("Gadus", "16S-Palumbi"), bst("Gadus", "16S"))
  expect_identical(bst("Gadus", "cytb-Kocher"), bst("Gadus", "cytb"))
  expect_identical(bst("Quercus", "rbcla"), bst("Quercus", "rbcL"))
  expect_identical(bst("Quercus", "matk-kim"), bst("Quercus", "matK"))
  expect_identical(bst("Quercus", "trnl-taberlet"), bst("Quercus", "trnL"))

  # And no variant name may survive into the query as a search clause.
  for (v in c(
    "COI-Folmer", "COI-Leray", "16S-Palumbi", "cytb-Kocher",
    "rbcla", "matk-kim", "trnl-taberlet"
  )) {
    expect_false(grepl(v, bst("Gadus", v), fixed = TRUE),
      info = paste("variant leaked into query:", v)
    )
  }
})

test_that(".build_search_term leaves MiFish primer names as searchable clauses", {
  # MiFish is the one family of primer names NCBI records genuinely do carry,
  # handled by the pre-existing primer_to_locus map -- the variant remap must
  # not swallow it.
  bst <- TaxaLikely:::.build_search_term
  out <- bst("Gadus", "MiFishU")
  expect_true(grepl("MiFishU[All Fields]", out, fixed = TRUE))
  expect_true(grepl("12S[All Fields]", out, fixed = TRUE))
})

# ---- empty reference_df keeps the successful return's shape -------------------

test_that(".empty_reference_df carries the rank columns a caller will index", {
  # A caller's ordinary next step is clean_taxon_names(reference_df$species);
  # returning a bare 2-column frame made that fail with "`name_vec` must be a
  # character vector", burying the real (already-correct) message about why the
  # fetch was empty.
  erd <- TaxaLikely:::.empty_reference_df

  out <- erd(c("family", "genus", "species"))
  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 0L)
  expect_equal(names(out), c("composite_id", "sequence", "family", "genus", "species"))
  expect_type(out$species, "character")

  # The column a caller indexes must be a zero-length vector, never NULL.
  expect_false(is.null(out$species))
  expect_length(out$species, 0L)

  # Location columns appear only when the caller asked for them.
  loc <- erd(c("family", "genus", "species"), include_location = TRUE)
  expect_equal(names(loc), c(
    "composite_id", "sequence", "family", "genus",
    "species", "lat", "lon", "country"
  ))
  expect_type(loc$lat, "double")

  # Rank names are lowercased to match the successful return's own columns.
  expect_equal(
    names(erd(c("Family", "Genus", "Species")))[3:5],
    c("family", "genus", "species")
  )
})

test_that(".parse_fasta_text: a trailing header with no sequence yields an empty sequence", {
  # `(start):(end)` counts DOWN when start > end, which spliced an NA plus the
  # header line itself into the sequence ("NA>A2 y") -- non-empty, so it
  # survived every downstream nchar(sequence) > 0 filter and reached the
  # aligner as a corrupt record.
  out <- TaxaLikely:::.parse_fasta_text(">A1 x\nATGC\n>A2 y")
  expect_identical(out$composite_id, c("A1", "A2"))
  expect_identical(out$sequence, c("ATGC", ""))
})

test_that("fetch_bold_reference_sequences: the no-records early return carries the full schema", {
  skip_if_not_installed("httr2")
  # A bare composite_id/sequence frame makes a caller's ordinary next step
  # (clean_taxon_names(reference_df$species)) fail on NULL, burying this
  # function's own message about why the result was empty.
  testthat::local_mocked_bindings(
    .bold_resolve_taxon = function(taxon) "tax:genus:Nothing",
    .bold_submit_query = function(triplet, extent = "full") "qid",
    .bold_fetch_documents = function(query_id) NULL
  )
  out <- fetch_bold_reference_sequences(
    taxa = "Nothing", rank_system = c("family", "genus", "species"),
    include_location = TRUE
  )
  expect_identical(nrow(out), 0L)
  expect_true(all(c(
    "composite_id", "sequence", "family", "genus", "species",
    "lat", "lon", "country"
  ) %in% names(out)))
})

test_that("the stem is taxon + barcode only -- the term digest is NOT in it", {
  stem <- TaxaLikely:::.ref_cache_stem
  # A per-generation stem would stop stem-scoped eviction recognising the
  # generation it replaces, and would make every pre-change file immortal
  # (the grammar's stem is free text, so such a file still MATCHES). So the
  # stem must stay free of the digest.
  expect_identical(stem("Girella", "12S"), "Girella_12S")
  expect_identical(stem("Girella", "COI"), "Girella_COI")
  expect_identical(stem("Girella", "MiFishU"), "Girella_MiFishU")
  expect_identical(stem("Girella", c("MiFish", "U")), "Girella_MiFish_U")
  expect_false(grepl("_q[0-9a-f]{8}", stem("Girella", "MiFishU")))
})

test_that("the cache key carries a digest of the query, not just the term string", {
  key <- function(bt, name = "Girella") {
    basename(TaxaLikely:::.ref_cache_file(tempdir(), name, bt, 130, 210,
      NULL, NULL, FALSE, 0, 0, TaxaLikely:::.fetch_ranks(c("family", "genus", "species"))))
  }
  # Shape, and the grammar must accept it -- the eviction proof depends on
  # .ref_cache_file() and .ref_cache_grammar() agreeing.
  expect_match(key("12S"), "_q[0-9a-f]{8}_l130_210")
  expect_match(key("12S"), TaxaLikely:::.ref_cache_grammar())

  # Different question, different key.
  expect_false(identical(key("12S"), key("16S")))
  expect_false(identical(key("12S"), key("COI")))
  # Same question, same key (so a re-run hits its own cache).
  expect_identical(key("12S"), key("12S"))

  # The digest is per MARKER, not per taxon: the taxon is already in the stem,
  # so two taxa fetched with one term must share one digest.
  d <- function(k) sub("^.*(_q[0-9a-f]{8}).*$", "\\1", k)
  expect_identical(d(key("12S", "Girella")), d(key("12S", "Sebastes")))
})

test_that("the key moves when the QUERY changes even though the term string does not", {
  # This is the test the old "_syn" suffix could not pass, and the reason the
  # digest exists. That suffix grepped the built query for one phrase, so any
  # other change to the query -- restricting a synonym to
  # mitochondrion[FILTER], re-ordering clauses, adding a filter -- moved the
  # question without moving the key, and the stale cache was served. A cached
  # object is written post-taxonomy-merge, so such a hit bypasses the taxonomy
  # bridge entirely and the stale rows are never looked at again.
  sfx <- TaxaLikely:::.ref_cache_term_sfx
  before <- sfx("12S")
  after <- testthat::with_mocked_bindings(
    .build_search_term = function(taxon, barcode_term, ...) {
      "a deliberately different query for the same term"
    },
    .package = "TaxaLikely",
    code = sfx("12S")
  )
  expect_false(identical(before, after))
  expect_match(after, "^_q[0-9a-f]{8}$")
})

test_that("a cache file written before the digest existed is evictable, not immortal", {
  d <- tempfile("taxalikely_q_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)

  live <- TaxaLikely:::.ref_cache_file(d, "Girella", "12S", 130, 210,
    NULL, NULL, FALSE, 0, 0, TaxaLikely:::.fetch_ranks(c("family", "genus", "species")))
  # The same name as the key used to produce: everything except the digest.
  old <- file.path(d, sub("_q[0-9a-f]{8}", "", basename(live)))
  file.create(live, old)

  unreachable <- TaxaLikely:::.ref_cache_unreachable(d)
  expect_true(old %in% unreachable)
  expect_false(live %in% unreachable)

  # And it is recognised as a previous generation OF THAT TAXON, which is what
  # scopes the automatic write-path eviction.
  scoped <- TaxaLikely:::.ref_cache_unreachable(
    d, TaxaLikely:::.ref_cache_stem("Girella", "12S")
  )
  expect_identical(scoped, old)
})

test_that(".ref_cache_stem_of() strips the digest along with the other components", {
  live <- basename(TaxaLikely:::.ref_cache_file(tempdir(), "Sebastes miniatus",
    "MiFishU", 130, 210, "2000/01/01", NULL, TRUE, 3, 900,
    TaxaLikely:::.fetch_ranks(c("family", "genus", "species")), taxid = "1261581"))
  expect_identical(
    TaxaLikely:::.ref_cache_stem_of(live),
    TaxaLikely:::.ref_cache_stem("Sebastes miniatus", "MiFishU")
  )
})

# ---- network abort rules (2026-10-05) ---------------------------------------
test_that("every rentrez call passes config = .net_config() and every httr2 request goes through .net_req()", {
  files <- list.files(test_path("..", "..", "R"), pattern = "\\.R$", full.names = TRUE)
  skip_if(length(files) == 0L, "package R/ sources not available (installed-package check)")
  n_rentrez <- 0L; bad <- character(0); n_perform <- 0L; bad2 <- character(0)
  walk <- function(e, f) {
    if (is.call(e)) {
      fn <- e[[1]]
      if (is.call(fn) && identical(fn[[1]], as.name("::")) && identical(fn[[2]], as.name("rentrez")) &&
        as.character(fn[[3]]) %in% c("entrez_search", "entrez_summary", "entrez_fetch")) {
        n_rentrez <<- n_rentrez + 1L
        if (!"config" %in% names(as.list(e))) bad <<- c(bad, paste(basename(f), deparse(e)[1]))
      }
      if (is.call(fn) && identical(fn[[1]], as.name("::")) && identical(fn[[2]], as.name("httr2")) &&
        identical(as.character(fn[[3]]), "req_perform")) {
        n_perform <<- n_perform + 1L
        a1 <- e[[2]]
        if (!(is.call(a1) && identical(a1[[1]], as.name(".net_req")))) bad2 <<- c(bad2, paste(basename(f), deparse(e)[1]))
      }
      for (k in as.list(e)[-1]) if (!missing(k)) walk(k, f)
    }
  }
  for (f in files) for (e in parse(f, keep.source = FALSE)) walk(e, f)
  expect_gt(n_rentrez, 0L) # the check is not vacuous
  expect_gt(n_perform, 0L)
  expect_identical(bad, character(0))
  expect_identical(bad2, character(0))
})

test_that("the network limits come from options and are validated", {
  old <- options(TaxaLikely.net_connect_timeout = 7, TaxaLikely.net_low_speed_time = 9,
    TaxaLikely.net_low_speed_limit = 512, TaxaLikely.net_timeout = 99)
  on.exit(options(old), add = TRUE)
  cfg <- TaxaLikely:::.net_config()
  expect_equal(cfg$options$connecttimeout, 7)
  expect_equal(cfg$options$low_speed_time, 9)
  expect_equal(cfg$options$low_speed_limit, 512)
  expect_equal(cfg$options$timeout_ms, 99000)
  options(TaxaLikely.net_timeout = 0)
  expect_error(TaxaLikely:::.net_config(), "positive number")
})

test_that("a connection that never answers is aborted quickly, and the retry fires", {
  skip_if_not(exists("serverSocket", mode = "function"))
  port <- NA
  for (p in sample(40000:60000, 20)) {
    s <- tryCatch(serverSocket(p), error = function(e) NULL)
    if (!is.null(s)) { port <- p; break }
  }
  skip_if(is.na(port), "no free local port")
  on.exit(close(s), add = TRUE)
  # sub-second-scale settings: the stall rule (below 1 KB/s for 1 s) must fire
  old <- options(TaxaLikely.net_connect_timeout = 1, TaxaLikely.net_low_speed_time = 1,
    TaxaLikely.net_low_speed_limit = 1024, TaxaLikely.net_timeout = 10)
  on.exit(options(old), add = TRUE)
  url <- sprintf("http://127.0.0.1:%d/", port)
  # built OUTSIDE expect_error(): only the transfer itself may raise, and the
  # error must be curl's own abort, so a missing helper cannot pass the test
  cfg <- TaxaLikely:::.net_config()
  req <- TaxaLikely:::.net_req(httr2::request(url))
  abort_re <- "too slow|[Tt]imeout|timed out"
  t0 <- Sys.time()
  expect_error(httr::GET(url, cfg), abort_re)
  expect_lt(as.numeric(difftime(Sys.time(), t0, units = "secs")), 8)
  t0 <- Sys.time()
  expect_error(httr2::req_perform(req), abort_re)
  expect_lt(as.numeric(difftime(Sys.time(), t0, units = "secs")), 8)
  n <- 0L
  r <- TaxaLikely:::.retry_fetch(function() { n <<- n + 1L; httr::GET(url, cfg) }, max_attempts = 2L)
  expect_false(r$success)
  expect_equal(n, 2L) # a stalled call now errors, so the retry runs
})

test_that("the SSU/LSU synonyms are searched only within mitochondrion[FILTER]", {
  # The two phrases also name the NUCLEAR rRNA operon's subunits, so searched
  # unrestricted they return 28S/18S/ITS records for the right organism.
  # Measured live: 45 nuclear Cottus records via LSU, 10 via SSU, and 23
  # Castilleja (plant) records for the goby genus Clevelandia.
  t16 <- TaxaLikely:::.build_search_term("Clevelandia", "16S")
  t12 <- TaxaLikely:::.build_search_term("Clevelandia", "12S")

  expect_true(grepl(
    '("large subunit ribosomal RNA"[All Fields] AND mitochondrion[FILTER])',
    t16, fixed = TRUE
  ))
  expect_true(grepl(
    '("small subunit ribosomal RNA"[All Fields] AND mitochondrion[FILTER])',
    t12, fixed = TRUE
  ))

  # The restriction is gone the moment the phrase appears OUTSIDE the
  # parenthesised AND -- which is what a revert, or a move back into
  # marker_synonyms, would produce. Without this the test above still passes
  # while the clause also searches the phrase unrestricted.
  expect_false(grepl('OR "large subunit ribosomal RNA"[All Fields] OR', t16, fixed = TRUE))
  expect_false(grepl('OR "large subunit ribosomal RNA"[All Fields])', t16, fixed = TRUE))
  expect_false(grepl('OR "small subunit ribosomal RNA"[All Fields] OR', t12, fixed = TRUE))
  expect_false(grepl('OR "small subunit ribosomal RNA"[All Fields])', t12, fixed = TRUE))

  # Each marker's own unambiguous names stay UNRESTRICTED. Filtering the whole
  # clause instead drops genuine untagged records (LC342688/LC342689,
  # "Cottus pollux / Cottus reinii gene for 12S ribosomal RNA").
  expect_true(grepl('"16S ribosomal RNA"[All Fields] OR', t16, fixed = TRUE))
  expect_true(grepl('"12S ribosomal RNA"[All Fields] OR', t12, fixed = TRUE))
  expect_false(grepl("AND mitochondrion[FILTER])) AND", t16, fixed = TRUE))

  # Pinned in full, so any reordering or requoting is visible rather than
  # silently equivalent-looking.
  expect_identical(
    t16,
    paste0(
      'Clevelandia[Organism] AND (16S[All Fields] OR "16S ribosomal RNA"[All Fields]',
      ' OR "16S rRNA"[All Fields] OR ("large subunit ribosomal RNA"[All Fields]',
      " AND mitochondrion[FILTER]))"
    )
  )
})

test_that("a primer-set term inherits its marker's RESTRICTED synonym too", {
  # MiFish-U resolves to 12S through primer_to_locus, a second lookup path.
  # Fixing only the direct marker_synonyms path leaves this one unrestricted.
  tm <- TaxaLikely:::.build_search_term("Fundulus", "MiFish-U")
  expect_true(grepl(
    '("small subunit ribosomal RNA"[All Fields] AND mitochondrion[FILTER])',
    tm, fixed = TRUE
  ))
  expect_false(grepl('OR "small subunit ribosomal RNA"[All Fields] OR', tm, fixed = TRUE))
  expect_false(grepl('OR "small subunit ribosomal RNA"[All Fields])', tm, fixed = TRUE))
})

test_that(".report_kingdom_split names every kingdom and drops nothing", {
  meta <- data.frame(
    taxid = as.character(1:28),
    kingdom = c(rep("Viridiplantae", 26), rep("Metazoa", 2)),
    species = c(paste0("Castilleja sp", 1:26), "Clevelandia ios", "Clevelandia ios"),
    stringsAsFactors = FALSE
  )
  # Pinned: both kingdoms AND both counts. A bare expect_message() would pass
  # on any message at all, including one that named only the majority.
  expect_message(
    TaxaLikely:::.report_kingdom_split(meta, "Clevelandia"),
    "CROSS-KINGDOM SPLIT.*Viridiplantae 26.*Metazoa 2"
  )
  expect_message(
    TaxaLikely:::.report_kingdom_split(meta, "Clevelandia"),
    "Clevelandia"
  )
  # It reports; it must not delete. The within-taxon majority here is the
  # CONTAMINANT (26 of 28), so a majority-based drop would discard both real
  # records and keep all 26 plants.
  out <- suppressMessages(TaxaLikely:::.report_kingdom_split(meta, "Clevelandia"))
  expect_identical(nrow(out), 28L)
  expect_identical(sum(out$kingdom == "Metazoa"), 2L)
})

test_that(".report_kingdom_split stays silent when there is nothing to report", {
  one <- data.frame(
    taxid = c("1", "2"), kingdom = c("Metazoa", "Metazoa"),
    stringsAsFactors = FALSE
  )
  expect_silent(TaxaLikely:::.report_kingdom_split(one, "Gillichthys"))
  # No kingdom column at all (a cache written without one) must not error.
  expect_silent(TaxaLikely:::.report_kingdom_split(
    data.frame(taxid = "1", stringsAsFactors = FALSE), "Gillichthys"
  ))
  expect_silent(TaxaLikely:::.report_kingdom_split(
    data.frame(taxid = character(0), kingdom = character(0),
               stringsAsFactors = FALSE), "Gillichthys"
  ))
  # All-NA kingdoms carry no information, so there is no split to claim.
  expect_silent(TaxaLikely:::.report_kingdom_split(
    data.frame(taxid = c("1", "2"), kingdom = c(NA_character_, NA_character_),
               stringsAsFactors = FALSE), "Gillichthys"
  ))
})

# ---- cache keys ignore a string's encoding mark ------------------------------

test_that("a cache key ignores the encoding mark of its strings", {
  # The property is asserted for a UTF-8 native locale, which is what this
  # project runs and what CI runs. In a C or Latin-1 session enc2utf8()
  # transcodes an "unknown" string from the native encoding, so the guarantee
  # is stated for UTF-8 sessions only -- and this test declines there rather
  # than failing, which is what the skip below is for.
  skip_if_not(l10n_info()[["UTF-8"]],
              "encoding-mark property is asserted for UTF-8 sessions only")
  s_utf8 <- "Pt. Mugu, California — estuarine and coastal"
  s_unk <- s_utf8
  Encoding(s_unk) <- "unknown"

  # Guards first. Without these the test could pass by comparing a string with
  # itself: the fixture has to differ in the MARK and in nothing else.
  expect_identical(nchar(s_utf8, "bytes"), nchar(s_unk, "bytes"))
  expect_false(identical(Encoding(s_utf8), Encoding(s_unk)))

  # The defect the helper exists for: rlang::hash() serializes the mark, so the
  # same text hashes two ways. If this expectation ever fails, rlang has fixed
  # it upstream and the helper is no longer earning its keep.
  expect_false(identical(rlang::hash(s_utf8), rlang::hash(s_unk)))

  # The fix.
  expect_identical(.cache_hash(s_utf8), .cache_hash(s_unk))

  # Nested, because most cache keys in this ecosystem are a list() of fields and
  # a top-level normalisation would miss the strings inside.
  expect_identical(
    .cache_hash(list(name = "cymatogaster aggregata", location = s_utf8)),
    .cache_hash(list(name = "cymatogaster aggregata", location = s_unk))
  )
})

test_that("the fix leaves an ASCII or already-UTF-8 key exactly where it was", {
  # Nothing cached before this helper existed may be orphaned by it.
  expect_identical(.cache_hash("abc"), rlang::hash("abc"))
  expect_identical(
    .cache_hash(list(a = 1L, b = "plain ascii")),
    rlang::hash(list(a = 1L, b = "plain ascii"))
  )

  # A real production key, rebuilt as a fixture rather than read from anyone's
  # cache directory. Under rlang 1.3.0 it hashes to
  # 013ed883133c9461d1c3671a4b2be57a, which is the filename it is stored under
  # in a live cache -- but that VALUE is asserted against rlang::hash() rather
  # than pinned as a literal, because rlang::hash() is documented as unstable
  # across rlang versions. Pinning it would turn an rlang upgrade into a red
  # suite for a reason that has nothing to do with this property.
  k <- list(
    name = "paralabrax maculatofasciatus",
    backbone_id = NA_integer_,
    location = "Pt. Mugu, California — estuarine and coastal"
  )
  expect_identical(.cache_hash(k), rlang::hash(k))
})

test_that("the reference cache term suffix is the same under either encoding mark", {
  # Through the call site's own .ref_cache_term_sfx(), which builds its probe
  # with .build_search_term() and makes no network call. A tree without the
  # helper fails here because the two suffixes differ.
  t_utf8 <- "COI — cytochrome c oxidase subunit I"
  t_unk <- t_utf8
  Encoding(t_unk) <- "unknown"
  expect_identical(.ref_cache_term_sfx(t_utf8), .ref_cache_term_sfx(t_unk))
})

test_that("an attributed or classed key is not moved by the fix", {
  k_df <- data.frame(name = "other", taxid = "1", stringsAsFactors = FALSE)
  expect_identical(.cache_hash(k_df), rlang::hash(k_df))
  k_cl <- structure(list(a = "ascii", b = 2L), class = "my_key", extra = "kept")
  expect_identical(.cache_hash(k_cl), rlang::hash(k_cl))
})
