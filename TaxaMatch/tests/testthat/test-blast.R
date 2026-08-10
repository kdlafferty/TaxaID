# ==============================================================================
# Tests for blast_sequences() — input validation and hit filtering
# ==============================================================================

# --- Internal-function wrappers -----------------------------------------------
# Use asNamespace() so tests work both via devtools::test() and on an installed
# package (where load_all() is not in effect and ::: may fail).

.filter_blast_hits  <- function(...) get(".filter_blast_hits",  envir = asNamespace("TaxaMatch"))(...)
.attach_taxonomy    <- function(...) get(".attach_taxonomy",    envir = asNamespace("TaxaMatch"))(...)
.empty_raw_hits     <- function(...) get(".empty_raw_hits",     envir = asNamespace("TaxaMatch"))(...)
.empty_blast_result <- function(...) get(".empty_blast_result", envir = asNamespace("TaxaMatch"))(...)
.parse_blast_xml    <- function(...) get(".parse_blast_xml",    envir = asNamespace("TaxaMatch"))(...)
.parse_taxonomy_xml <- function(...) get(".parse_taxonomy_xml", envir = asNamespace("TaxaMatch"))(...)
.parse_lat_lon      <- function(...) get(".parse_lat_lon",      envir = asNamespace("TaxaMatch"))(...)
.resolve_locations_by_acc <- function(...) get(".resolve_locations_by_acc", envir = asNamespace("TaxaMatch"))(...)

# --- Helpers ------------------------------------------------------------------

make_seq_df <- function(n = 5) {
  data.frame(
    asv_id   = paste0("ASV_", seq_len(n)),
    sequence = vapply(seq_len(n), function(i)
      paste0(sample(c("A", "C", "G", "T"), 150, replace = TRUE), collapse = ""),
      character(1L)),
    length    = rep(150L, n),
    abundance = rep(10L, n),
    stringsAsFactors = FALSE
  )
}

make_raw_hits <- function() {
  data.frame(
    qseqid   = c(rep("ASV_1", 6), rep("ASV_2", 4)),
    sseqid   = paste0("ref_", 1:10),
    sacc     = paste0("ACC_", 1:10),
    staxids  = as.character(9000:9009),
    pident   = c(99, 97, 96, 95, 90, 80,   98, 97, 96, 70),
    # Aligned-region length -- this is what the subject-length filter checks
    # (not `slen`, the raw subject accession length -- see below).
    length   = c(170, 180, 500, 170, 170, 170, 170, 700, 170, 170),
    # Deliberately decoupled from `length`: rows 1 and 7 simulate a real hit
    # against a long mitogenome/partial-genome record (slen in the
    # thousands) whose ALIGNED region is still a correctly-sized, in-range
    # match (length = 170) -- exactly the real Ameiurus melas case that
    # motivated checking `length` instead of `slen`.
    slen     = c(16512, 180, 500, 170, 170, 170, 16513, 700, 170, 170),
    qcovs    = c(95, 92, 90, 88, 85, 50,   95, 90, 88, 30),
    mismatch = rep(1L, 10),
    gapopen  = rep(0L, 10),
    evalue   = rep(1e-50, 10),
    bitscore = rep(200, 10),
    stringsAsFactors = FALSE
  )
}


# ==============================================================================
# blast_sequences() — Input validation
# ==============================================================================

test_that("blast_sequences rejects non-data-frame input", {
  expect_error(blast_sequences("not a df"), "must be a data frame")
})

test_that("blast_sequences rejects missing required columns", {
  df <- data.frame(id = "A", seq = "ACGT", stringsAsFactors = FALSE)
  expect_error(blast_sequences(df), "asv_id.*sequence")
})

test_that("blast_sequences rejects empty data frame", {
  df <- data.frame(asv_id = character(), sequence = character(),
                   stringsAsFactors = FALSE)
  expect_error(blast_sequences(df), "no rows")
})

test_that("blast_sequences rejects invalid score_range", {
  seq_df <- make_seq_df(1)
  expect_error(blast_sequences(seq_df, score_range = -1), "score_range")
  expect_error(blast_sequences(seq_df, score_range = NA), "score_range")
})

test_that("blast_sequences rejects invalid max_hits", {
  seq_df <- make_seq_df(1)
  expect_error(blast_sequences(seq_df, max_hits = 0), "max_hits")
  expect_error(blast_sequences(seq_df, max_hits = NA), "max_hits")
})

test_that("blast_sequences rejects invalid resolve_taxonomy", {
  seq_df <- make_seq_df(1)
  expect_error(blast_sequences(seq_df, resolve_taxonomy = NA), "resolve_taxonomy")
})

test_that("blast_sequences rejects invalid resolve_location", {
  seq_df <- make_seq_df(1)
  expect_error(blast_sequences(seq_df, resolve_location = NA), "resolve_location")
  expect_error(blast_sequences(seq_df, resolve_location = "yes"), "resolve_location")
})

test_that("blast_sequences default score_range is 8 (widened from 2, soundness-review item 14)", {
  expect_equal(formals(blast_sequences)$score_range, 8)
})


# ==============================================================================
# .parse_lat_lon() — INSDC lat_lon qualifier parser
# ==============================================================================

test_that(".parse_lat_lon parses well-formed N/E coordinates", {
  out <- .parse_lat_lon("36.789 N 121.947 E")
  expect_equal(unname(out["lat"]), 36.789)
  expect_equal(unname(out["lon"]), 121.947)
})

test_that(".parse_lat_lon negates S and W", {
  out <- .parse_lat_lon("36.789 S 121.947 W")
  expect_equal(unname(out["lat"]), -36.789)
  expect_equal(unname(out["lon"]), -121.947)
})

test_that(".parse_lat_lon is case-insensitive on hemisphere letters", {
  out <- .parse_lat_lon("36.789 s 121.947 w")
  expect_equal(unname(out["lat"]), -36.789)
  expect_equal(unname(out["lon"]), -121.947)
})

test_that(".parse_lat_lon returns NA on NA/empty/malformed input", {
  expect_true(all(is.na(.parse_lat_lon(NA_character_))))
  expect_true(all(is.na(.parse_lat_lon(""))))
  expect_true(all(is.na(.parse_lat_lon("not a coordinate"))))
})

test_that(".parse_lat_lon returns NA on NULL/multi-length input", {
  expect_true(all(is.na(.parse_lat_lon(NULL))))
  expect_true(all(is.na(.parse_lat_lon(c("1 N 2 E", "3 N 4 E")))))
})

test_that(".resolve_locations_by_acc returns empty typed data frame for no accessions", {
  out <- .resolve_locations_by_acc(character(0L))
  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 0L)
  expect_equal(names(out), c("accession", "lat", "lon", "country"))
})


# ==============================================================================
# .filter_blast_hits() — Score window algorithm
# ==============================================================================

test_that("score window keeps hits within range of top hit", {
  hits <- make_raw_hits()
  # ASV_1 top hit = 99, score_range = 2 → keep >= 97
  # ASV_2 top hit = 98, score_range = 2 → keep >= 96

  result <- .filter_blast_hits(
    hits, min_score = 70, min_query_coverage = 0,
    subject_len_range = NULL, score_range = 2, max_hits = 20,
    verbose = FALSE
  )

  asv1_hits <- result[result$qseqid == "ASV_1", ]
  asv2_hits <- result[result$qseqid == "ASV_2", ]

  expect_true(all(asv1_hits$pident >= 97))
  expect_true(all(asv2_hits$pident >= 96))
})

test_that("min_score filter removes low-scoring hits", {
  hits <- make_raw_hits()

  result <- .filter_blast_hits(
    hits, min_score = 90, min_query_coverage = 0,
    subject_len_range = NULL, score_range = 100, max_hits = 100,
    verbose = FALSE
  )

  expect_true(all(result$pident >= 90))
})

test_that("query coverage filter removes partial alignments", {
  hits <- make_raw_hits()

  result <- .filter_blast_hits(
    hits, min_score = 0, min_query_coverage = 80,
    subject_len_range = NULL, score_range = 100, max_hits = 100,
    verbose = FALSE
  )

  expect_true(all(result$qcovs >= 80))
})

test_that("subject length filter removes hits whose aligned region is out of range", {
  hits <- make_raw_hits()

  result <- .filter_blast_hits(
    hits, min_score = 0, min_query_coverage = 0,
    subject_len_range = c(100L, 300L), score_range = 100, max_hits = 100,
    verbose = FALSE
  )

  # length = 500 and 700 should be excluded (aligned-region length, not slen)
  expect_true(all(result$length <= 300))
})

test_that("subject length filter checks the aligned region, not the raw subject accession length", {
  # Rows 1 and 7 simulate a real hit against a long mitogenome (slen in the
  # thousands) whose aligned region is still a correctly-sized match
  # (length = 170) -- these must be RETAINED, not discarded for having a
  # long subject record. This is the real Ameiurus melas case that motivated
  # the fix: checking `slen` instead of `length` silently dropped a genuine,
  # exactly-tied congener hit purely because its reference happened to be a
  # long mitogenome deposit rather than a short standalone barcode
  # submission.
  hits <- make_raw_hits()

  result <- .filter_blast_hits(
    hits, min_score = 0, min_query_coverage = 0,
    subject_len_range = c(100L, 300L), score_range = 100, max_hits = 100,
    verbose = FALSE
  )

  long_subject_rows <- result[result$slen > 1000, ]
  expect_gt(nrow(long_subject_rows), 0L)
  expect_true(all(long_subject_rows$length <= 300))
})

test_that("max_hits safety cap limits per-query results", {
  hits <- make_raw_hits()

  result <- .filter_blast_hits(
    hits, min_score = 0, min_query_coverage = 0,
    subject_len_range = NULL, score_range = 100, max_hits = 2,
    verbose = FALSE
  )

  asv1_count <- sum(result$qseqid == "ASV_1")
  asv2_count <- sum(result$qseqid == "ASV_2")

  expect_lte(asv1_count, 2L)
  expect_lte(asv2_count, 2L)
})

make_raw_hits_dup_taxa <- function() {
  # 6 hits, one query, 2 taxa: taxid 1000 (4 near-duplicate mitogenome
  # deposits, simulating a heavily-resequenced species) and taxid 2000
  # (2 hits, a real but different congener). Without a per-taxon cap,
  # taxid 1000's redundant hits alone would fill a small max_hits budget.
  data.frame(
    qseqid   = rep("ASV_1", 6),
    sseqid   = paste0("ref_", 1:6),
    sacc     = paste0("ACC_", 1:6),
    staxids  = c("1000", "1000", "1000", "1000", "2000", "2000"),
    pident   = c(100, 100, 99.9, 99.8,   98, 97.5),
    length   = rep(170L, 6),
    slen     = rep(170L, 6),
    qcovs    = rep(95, 6),
    mismatch = rep(1L, 6),
    gapopen  = rep(0L, 6),
    evalue   = rep(1e-50, 6),
    bitscore = rep(200, 6),
    stringsAsFactors = FALSE
  )
}

test_that("max_hits_per_taxon caps hits per taxon before max_hits applies", {
  hits <- make_raw_hits_dup_taxa()

  result <- .filter_blast_hits(
    hits, min_score = 0, min_query_coverage = 0,
    subject_len_range = NULL, score_range = 100, max_hits = 3,
    max_hits_per_taxon = 1L, verbose = FALSE
  )

  # Without the per-taxon cap, taxid 1000's 4 hits would fill max_hits = 3
  # entirely and taxid 2000 would never appear. With max_hits_per_taxon = 1,
  # each taxon contributes at most 1 hit, so taxid 2000 survives.
  expect_true("2000" %in% result$staxids)
  expect_equal(sum(result$staxids == "1000"), 1L)
  expect_equal(sum(result$staxids == "2000"), 1L)
})

test_that("max_hits_per_taxon always keeps each taxon's own best hit", {
  hits <- make_raw_hits_dup_taxa()

  result <- .filter_blast_hits(
    hits, min_score = 0, min_query_coverage = 0,
    subject_len_range = NULL, score_range = 100, max_hits = 100,
    max_hits_per_taxon = 1L, verbose = FALSE
  )

  taxid_1000_row <- result[result$staxids == "1000", ]
  taxid_2000_row <- result[result$staxids == "2000", ]
  expect_equal(taxid_1000_row$pident, 100)   # best of 100, 100, 99.9, 99.8
  expect_equal(taxid_2000_row$pident, 98)    # best of 98, 97.5
})

test_that("max_hits_per_taxon = NULL preserves existing behavior (no cap)", {
  hits <- make_raw_hits_dup_taxa()

  result <- .filter_blast_hits(
    hits, min_score = 0, min_query_coverage = 0,
    subject_len_range = NULL, score_range = 100, max_hits = 100,
    max_hits_per_taxon = NULL, verbose = FALSE
  )

  expect_equal(nrow(result), 6L)
})

test_that("blast_sequences rejects invalid max_hits_per_taxon", {
  seq_df <- make_seq_df(1)
  expect_error(blast_sequences(seq_df, max_hits_per_taxon = 0), "max_hits_per_taxon")
  expect_error(blast_sequences(seq_df, max_hits_per_taxon = -1), "max_hits_per_taxon")
  expect_error(blast_sequences(seq_df, max_hits_per_taxon = "3"), "max_hits_per_taxon")
})

test_that("max_hits_per_taxon groups by resolved species when staxids is NA (the real remote-BLAST case)", {
  # Mirrors the real Ameiurus case: remote BLAST XML never populates a real
  # staxids (see .parse_blast_xml()), so grouping must fall back to
  # accession-resolved species names. 6 hits, one query: 4 near-duplicate
  # "species A" mitogenome deposits (should collapse to 1 under the cap)
  # and 2 real "species B" hits (should keep its own best).
  hits <- data.frame(
    qseqid   = rep("ASV_1", 6),
    sseqid   = paste0("ref_", 1:6),
    sacc     = paste0("ACC_", 1:6),
    staxids  = NA_character_,
    pident   = c(100, 100, 99.9, 99.8,   96, 95.5),
    length   = rep(170L, 6),
    slen     = rep(170L, 6),
    qcovs    = rep(95, 6),
    mismatch = rep(1L, 6),
    gapopen  = rep(0L, 6),
    evalue   = rep(1e-50, 6),
    bitscore = rep(200, 6),
    stringsAsFactors = FALSE
  )

  fake_tax_map <- data.frame(
    accession = paste0("ACC_", 1:6),
    genus     = rep("Genus", 6),
    species   = c(rep("Genus species_a", 4), rep("Genus species_b", 2)),
    stringsAsFactors = FALSE
  )

  testthat::local_mocked_bindings(
    .resolve_taxonomy_by_acc = function(...) fake_tax_map,
    .package = "TaxaMatch"
  )

  basic <- .filter_blast_hits(
    hits, min_score = 0, min_query_coverage = 0, subject_len_range = NULL,
    score_range = 100, max_hits = 100, verbose = FALSE, stage = "basic"
  )
  basic <- .attach_taxonomy(basic, ncbi_api_key = NULL, verbose = FALSE)
  basic$.taxon_group <- basic$species

  result <- .filter_blast_hits(
    basic, min_score = 0, min_query_coverage = 0, subject_len_range = NULL,
    score_range = 100, max_hits = 100, max_hits_per_taxon = 1L,
    taxon_group_col = ".taxon_group", stage = "rest", verbose = FALSE
  )

  expect_equal(nrow(result), 2L)
  expect_setequal(result$species, c("Genus species_a", "Genus species_b"))
  # each surviving row is that species' own best-scoring hit
  expect_equal(result$pident[result$species == "Genus species_a"], 100)
  expect_equal(result$pident[result$species == "Genus species_b"], 96)
})

test_that("combined filters work together", {
  hits <- make_raw_hits()

  result <- .filter_blast_hits(
    hits, min_score = 90, min_query_coverage = 85,
    subject_len_range = c(100L, 300L), score_range = 2, max_hits = 3,
    verbose = FALSE
  )

  expect_true(all(result$pident >= 90))
  expect_true(all(result$qcovs >= 85))
  expect_true(all(result$length >= 100 & result$length <= 300))

  for (q in unique(result$qseqid)) {
    qhits <- result[result$qseqid == q, ]
    expect_lte(nrow(qhits), 3L)
    expect_true(all(qhits$pident >= max(qhits$pident) - 2))
  }
})

test_that("empty hits return empty data frame", {
  hits <- .empty_raw_hits()

  result <- .filter_blast_hits(
    hits, min_score = 0, min_query_coverage = 0,
    subject_len_range = NULL, score_range = 2, max_hits = 20,
    verbose = FALSE
  )

  expect_equal(nrow(result), 0L)
})


# ==============================================================================
# .empty_blast_result()
# ==============================================================================

test_that("empty result has correct structure", {
  result <- .empty_blast_result(with_taxonomy = FALSE)
  expect_true(all(c("observation_id", "accession", "score") %in% names(result)))
  expect_false("kingdom" %in% names(result))

  result_tax <- .empty_blast_result(with_taxonomy = TRUE)
  expect_true(all(c("kingdom", "species") %in% names(result_tax)))
})


# ==============================================================================
# .parse_blast_xml() — BLAST XML parsing
# ==============================================================================

test_that("parse_blast_xml extracts hits from BLAST XML", {
  skip_if_not_installed("xml2")

  xml_text <- '<?xml version="1.0"?>
  <BlastOutput>
    <BlastOutput_iterations>
      <Iteration>
        <Iteration_iter-num>1</Iteration_iter-num>
        <Iteration_query-def>ASV_001</Iteration_query-def>
        <Iteration_query-len>200</Iteration_query-len>
        <Iteration_hits>
          <Hit>
            <Hit_num>1</Hit_num>
            <Hit_id>ref|NM_001234|</Hit_id>
            <Hit_def>Homo sapiens gene</Hit_def>
            <Hit_accession>NM_001234</Hit_accession>
            <Hit_len>500</Hit_len>
            <Hit_hsps>
              <Hsp>
                <Hsp_identity>198</Hsp_identity>
                <Hsp_align-len>200</Hsp_align-len>
                <Hsp_gaps>0</Hsp_gaps>
                <Hsp_query-from>1</Hsp_query-from>
                <Hsp_query-to>200</Hsp_query-to>
                <Hsp_evalue>1e-90</Hsp_evalue>
                <Hsp_bit-score>350.5</Hsp_bit-score>
              </Hsp>
            </Hit_hsps>
          </Hit>
          <Hit>
            <Hit_num>2</Hit_num>
            <Hit_id>ref|NM_005678|</Hit_id>
            <Hit_def>Pan troglodytes gene</Hit_def>
            <Hit_accession>NM_005678</Hit_accession>
            <Hit_len>480</Hit_len>
            <Hit_hsps>
              <Hsp>
                <Hsp_identity>190</Hsp_identity>
                <Hsp_align-len>200</Hsp_align-len>
                <Hsp_gaps>1</Hsp_gaps>
                <Hsp_query-from>1</Hsp_query-from>
                <Hsp_query-to>200</Hsp_query-to>
                <Hsp_evalue>1e-80</Hsp_evalue>
                <Hsp_bit-score>310.2</Hsp_bit-score>
              </Hsp>
            </Hit_hsps>
          </Hit>
        </Iteration_hits>
      </Iteration>
    </BlastOutput_iterations>
  </BlastOutput>'

  result <- .parse_blast_xml(xml_text)

  expect_equal(nrow(result), 2L)
  expect_equal(result$qseqid, c("ASV_001", "ASV_001"))
  expect_equal(result$sacc, c("NM_001234", "NM_005678"))
  expect_equal(result$pident, c(99.00, 95.00))
  expect_equal(result$slen, c(500L, 480L))
  expect_equal(result$qcovs, c(100.0, 100.0))
  expect_true(all(!is.na(result$evalue)))
  expect_true(all(!is.na(result$bitscore)))
  # sstart/send absent from this fixture's HSPs -- must come back NA, not error
  expect_true(all(is.na(result$sstart)))
  expect_true(all(is.na(result$send)))
})

test_that("parse_blast_xml extracts subject-side alignment coordinates (sstart/send)", {
  # Real motivating case (Session 159): a query hitting a long subject (e.g. a
  # complete mitogenome) needs its OWN alignment position within that subject
  # retained, not just the subject's total length -- otherwise a downstream
  # regional-overlap check can't tell two hits against the same long subject
  # apart by genomic position.
  skip_if_not_installed("xml2")

  xml_text <- '<?xml version="1.0"?>
  <BlastOutput>
    <BlastOutput_iterations>
      <Iteration>
        <Iteration_iter-num>1</Iteration_iter-num>
        <Iteration_query-def>ASV_300</Iteration_query-def>
        <Iteration_query-len>99</Iteration_query-len>
        <Iteration_hits>
          <Hit>
            <Hit_num>1</Hit_num>
            <Hit_id>ref|NC_063692|</Hit_id>
            <Hit_def>Fundulus lima mitochondrion, complete genome</Hit_def>
            <Hit_accession>NC_063692</Hit_accession>
            <Hit_len>16506</Hit_len>
            <Hit_hsps>
              <Hsp>
                <Hsp_identity>98</Hsp_identity>
                <Hsp_align-len>99</Hsp_align-len>
                <Hsp_gaps>0</Hsp_gaps>
                <Hsp_query-from>1</Hsp_query-from>
                <Hsp_query-to>99</Hsp_query-to>
                <Hsp_hit-from>515</Hsp_hit-from>
                <Hsp_hit-to>613</Hsp_hit-to>
                <Hsp_evalue>1e-40</Hsp_evalue>
                <Hsp_bit-score>180.0</Hsp_bit-score>
              </Hsp>
            </Hit_hsps>
          </Hit>
        </Iteration_hits>
      </Iteration>
    </BlastOutput_iterations>
  </BlastOutput>'

  result <- .parse_blast_xml(xml_text)

  expect_equal(nrow(result), 1L)
  expect_equal(result$sstart, 515L)
  expect_equal(result$send, 613L)
})

test_that("parse_blast_xml handles status page gracefully", {
  skip_if_not_installed("xml2")
  status_page <- "<p><!--\nQBlastInfoBegin\nStatus=READY\nQBlastInfoEnd\n--></p>"
  result <- .parse_blast_xml(status_page)
  expect_equal(nrow(result), 0L)
})

test_that("parse_blast_xml handles no hits gracefully", {
  skip_if_not_installed("xml2")
  xml_text <- '<?xml version="1.0"?>
  <BlastOutput>
    <BlastOutput_iterations>
      <Iteration>
        <Iteration_query-def>ASV_001</Iteration_query-def>
        <Iteration_query-len>200</Iteration_query-len>
        <Iteration_hits></Iteration_hits>
      </Iteration>
    </BlastOutput_iterations>
  </BlastOutput>'
  result <- .parse_blast_xml(xml_text)
  expect_equal(nrow(result), 0L)
})


# ==============================================================================
# .blast_server_rejected() -- NCBI CPU-budget rejection detection
# ==============================================================================
# Message text below is verbatim from a REAL captured response (2026-08-09,
# a real 20-query batch of mostly full-mitogenome-length sequences against
# nt) -- not a synthetic guess. NCBI reported Status=READY (a real,
# successfully-retrieved document) for this batch; every <Iteration>
# carried both messages below, and .parse_blast_xml() silently returned 0
# hit rows with no indication this wasn't a genuine "found nothing" result.

test_that("blast_server_rejected detects a real NCBI CPU-budget rejection", {
  real_message_1 <- paste0(
    "<Iteration_message>Searches from this IP address have consumed a ",
    "large amount of server CPU time. Future searches may be penalized ",
    "in fairness to other users. Please consider the BLAST+ binaries: ",
    "https://www.ncbi.nlm.nih.gov/books/NBK279690/</Iteration_message>"
  )
  real_message_2 <- paste0(
    "<Iteration_message>[blastsrv4.REAL]: Error: CPU usage limit was ",
    "exceeded, resulting in SIGXCPU (24).</Iteration_message>"
  )
  expect_true(.blast_server_rejected(real_message_1))
  expect_true(.blast_server_rejected(real_message_2))
  expect_true(.blast_server_rejected(paste(real_message_1, real_message_2)))
})

test_that("blast_server_rejected is FALSE for a normal successful response", {
  xml_text <- '<?xml version="1.0"?>
  <BlastOutput>
    <BlastOutput_iterations>
      <Iteration>
        <Iteration_query-def>ASV_001</Iteration_query-def>
        <Iteration_hits><Hit><Hit_accession>X12345</Hit_accession></Hit></Iteration_hits>
      </Iteration>
    </BlastOutput_iterations>
  </BlastOutput>'
  expect_false(.blast_server_rejected(xml_text))
})

test_that("blast_server_rejected is FALSE for an empty-hits (genuine no-match) response", {
  xml_text <- '<?xml version="1.0"?>
  <BlastOutput>
    <BlastOutput_iterations>
      <Iteration>
        <Iteration_query-def>ASV_001</Iteration_query-def>
        <Iteration_hits></Iteration_hits>
      </Iteration>
    </BlastOutput_iterations>
  </BlastOutput>'
  expect_false(.blast_server_rejected(xml_text))
})


# ==============================================================================
# .parse_taxonomy_xml() — XML parsing
# ==============================================================================

test_that("parse_taxonomy_xml extracts lineage correctly", {
  skip_if_not_installed("xml2")

  xml_text <- '<?xml version="1.0" ?>
  <TaxaSet>
    <Taxon>
      <TaxId>9606</TaxId>
      <ScientificName>Homo sapiens</ScientificName>
      <Rank>species</Rank>
      <LineageEx>
        <Taxon><TaxId>33208</TaxId><ScientificName>Metazoa</ScientificName><Rank>kingdom</Rank></Taxon>
        <Taxon><TaxId>7711</TaxId><ScientificName>Chordata</ScientificName><Rank>phylum</Rank></Taxon>
        <Taxon><TaxId>40674</TaxId><ScientificName>Mammalia</ScientificName><Rank>class</Rank></Taxon>
        <Taxon><TaxId>9443</TaxId><ScientificName>Primates</ScientificName><Rank>order</Rank></Taxon>
        <Taxon><TaxId>9604</TaxId><ScientificName>Hominidae</ScientificName><Rank>family</Rank></Taxon>
        <Taxon><TaxId>9605</TaxId><ScientificName>Homo</ScientificName><Rank>genus</Rank></Taxon>
      </LineageEx>
    </Taxon>
  </TaxaSet>'

  result <- .parse_taxonomy_xml(xml_text)

  expect_equal(nrow(result), 1L)
  expect_equal(result$taxid, "9606")
  expect_equal(result$species, "Homo sapiens")
  expect_equal(result$genus, "Homo")
  expect_equal(result$family, "Hominidae")
  expect_equal(result$kingdom, "Metazoa")
})
