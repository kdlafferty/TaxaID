# ==============================================================================
# Tests for blast_sequences() — input validation and hit filtering
# ==============================================================================

# --- Internal-function wrappers -----------------------------------------------
# Use asNamespace() so tests work both via devtools::test() and on an installed
# package (where load_all() is not in effect and ::: may fail).

.filter_blast_hits  <- function(...) get(".filter_blast_hits",  envir = asNamespace("TaxaMatch"))(...)
.empty_raw_hits     <- function(...) get(".empty_raw_hits",     envir = asNamespace("TaxaMatch"))(...)
.empty_blast_result <- function(...) get(".empty_blast_result", envir = asNamespace("TaxaMatch"))(...)
.parse_blast_xml    <- function(...) get(".parse_blast_xml",    envir = asNamespace("TaxaMatch"))(...)
.parse_taxonomy_xml <- function(...) get(".parse_taxonomy_xml", envir = asNamespace("TaxaMatch"))(...)

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
    length   = rep(150L, 10),
    slen     = c(170, 180, 500, 170, 170, 170, 170, 700, 170, 170),
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

test_that("subject length filter removes out-of-range references", {
  hits <- make_raw_hits()

  result <- .filter_blast_hits(
    hits, min_score = 0, min_query_coverage = 0,
    subject_len_range = c(100L, 300L), score_range = 100, max_hits = 100,
    verbose = FALSE
  )

  # slen = 500 and 700 should be excluded
  expect_true(all(result$slen <= 300))
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

test_that("combined filters work together", {
  hits <- make_raw_hits()

  result <- .filter_blast_hits(
    hits, min_score = 90, min_query_coverage = 85,
    subject_len_range = c(100L, 300L), score_range = 2, max_hits = 3,
    verbose = FALSE
  )

  expect_true(all(result$pident >= 90))
  expect_true(all(result$qcovs >= 85))
  expect_true(all(result$slen >= 100 & result$slen <= 300))

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
