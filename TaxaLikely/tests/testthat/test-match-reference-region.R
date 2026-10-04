# match_reference_region() needs Biostrings, pwalign and Matrix (Suggests).
# Fixture: a random 900 bp "gene"; the study's ESVs cover positions 301-613
# (313 bp, the Leray span), drawn from three ~5%-divergent "species" variants.

.rr_mutate <- function(x, rate, seed) {
  set.seed(seed)
  v <- strsplit(x, "")[[1]]
  hit <- which(stats::runif(length(v)) < rate)
  v[hit] <- vapply(v[hit], function(b) sample(setdiff(c("A", "C", "G", "T"), b), 1L), "")
  paste(v, collapse = "")
}
.rr_random <- function(n, seed) {
  set.seed(seed)
  paste(sample(c("A", "C", "G", "T"), n, replace = TRUE), collapse = "")
}
.rr_rc <- function(x) as.character(Biostrings::reverseComplement(Biostrings::DNAString(x)))

.rr_fixture <- function() {
  gene <- .rr_random(900L, 1L)
  variants <- vapply(1:3, function(i) .rr_mutate(gene, 0.05, 10L + i), "")
  esvs <- substring(variants, 301L, 613L)
  ref <- data.frame(
    composite_id = paste0("R", 1:7),
    sequence = c(
      substring(variants[1], 1L, 700L), # Folmer-like deposit
      .rr_rc(substring(variants[2], 1L, 700L)), # deposited reverse-complemented
      substring(variants[3], 650L, 900L), # a different stretch of the gene
      substring(variants[1], 1L, 450L), # stops part-way into the region
      paste0(.rr_random(5000L, 2L), variants[2], .rr_random(5000L, 3L)), # long genome
      "XYZ", # not DNA
      substring(variants[1], 1L, 700L) # exact duplicate of R1
    ),
    species = c("a", "b", "c", "a", "b", "z", "a"),
    stringsAsFactors = FALSE
  )
  list(ref = ref, esvs = esvs, variants = variants)
}

test_that("match_reference_region validates its inputs", {
  df <- data.frame(composite_id = "A", sequence = "ACGT", stringsAsFactors = FALSE)
  expect_error(match_reference_region(list(), "ACGT"), "must be a data frame")
  expect_error(match_reference_region(df[, "composite_id", drop = FALSE], "ACGT"), "missing required columns")
  expect_error(match_reference_region(df, 1), "esv_sequences must be a character vector")
  expect_error(match_reference_region(df, "ACGT", primer_fwd = "ACGT"), "supply both primer_fwd and primer_rev")
  expect_error(match_reference_region(df, "ACGT", min_coverage = 0), "min_coverage")
  expect_error(match_reference_region(df, "ACGT", max_mismatch_rate = 1), "max_mismatch_rate")
  expect_error(match_reference_region(df, "ACGT", n_cores = 0), "n_cores")
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")
  skip_if_not_installed("Matrix")
  expect_error(match_reference_region(df, "NNNN"), "no unambiguous ACGT")
})

test_that("each record is placed on, or kept off, the ESV region and says how", {
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")
  skip_if_not_installed("Matrix")
  fx <- .rr_fixture()
  out <- suppressMessages(match_reference_region(fx$ref, fx$esvs, keep_unplaced = TRUE))
  path <- stats::setNames(out$trim_path, out$composite_id)
  expect_equal(unname(path[c("R1", "R2", "R5", "R7")]),
               c("esv_aligned", "esv_aligned_reverse_complement", "esv_aligned", "esv_aligned"))
  expect_equal(unname(path["R3"]), "not_placed")
  expect_equal(unname(path["R4"]), "short_of_region")
  expect_equal(unname(path["R6"]), "invalid_sequence")

  placed <- out[out$composite_id %in% c("R1", "R2", "R5"), ]
  # every placed record is the ESV span of its own variant, on the ESV strand
  truth <- substring(fx$variants[c(1, 2, 2)], 301L, 613L)
  expect_equal(placed$sequence, truth)
  expect_true(all(placed$region_coverage == 1))
  expect_true(all(placed$region_identity > 0.85))
  expect_equal(out$len_submitted, nchar(fx$ref$sequence))
  # an unplaced row kept for inspection keeps its sequence as deposited
  expect_equal(out$sequence[out$composite_id == "R3"], fx$ref$sequence[3])
  expect_true(is.na(out$region_identity[out$composite_id == "R4"]))
  expect_true(out$region_coverage[out$composite_id == "R4"] < 0.8)
})

test_that("unplaced rows are dropped by default and counted in the attributes", {
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")
  skip_if_not_installed("Matrix")
  fx <- .rr_fixture()
  expect_message(out <- match_reference_region(fx$ref, fx$esvs), "unplaced row")
  expect_setequal(out$composite_id, c("R1", "R2", "R5", "R7"))
  counts <- attr(out, "trim_path_counts")
  expect_equal(sum(counts), nrow(fx$ref)) # counts cover dropped rows too
  expect_equal(as.integer(counts[c("not_placed", "short_of_region", "invalid_sequence")]), c(1L, 1L, 1L))
  expect_equal(attr(out, "region_length"), 313L)
  expect_true(is.numeric(attr(out, "homology_threshold")))
  # other columns ride along untouched
  expect_equal(out$species[out$composite_id == "R2"], "b")
})

test_that("min_coverage decides when a partial deposit is usable", {
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")
  skip_if_not_installed("Matrix")
  fx <- .rr_fixture()
  out <- suppressMessages(match_reference_region(fx$ref[4, ], fx$esvs,
    min_coverage = 0.4, keep_unplaced = TRUE
  ))
  expect_equal(out$trim_path, "esv_aligned")
  # R4 stops at 450, so its region is 301-450
  expect_equal(out$sequence, substring(fx$variants[1], 301L, 450L))
})

test_that("primer anchoring places only records with no homology to any ESV", {
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")
  skip_if_not_installed("Matrix")
  fx <- .rr_fixture()
  fwd <- "GGTACAGTCAGCTAGTCAGT"
  rev <- "TTGACCGTCAGTTCAGGTCA"
  insert <- .rr_random(313L, 4L) # unrelated to every ESV
  ref <- data.frame(
    composite_id = c("P1", "P2", "P3", "P4"),
    sequence = c(
      paste0(.rr_random(200L, 5L), fwd, insert, .rr_random(200L, 6L)), # forward site only
      .rr_rc(paste0(.rr_random(200L, 5L), fwd, insert, .rr_random(200L, 6L))), # same, other strand
      paste0(.rr_random(100L, 7L), fwd, substring(insert, 1L, 100L)), # ends too soon after the site
      paste0(.rr_random(200L, 8L), insert, .rr_rc(rev), .rr_random(200L, 9L)) # reverse site only
    ),
    stringsAsFactors = FALSE
  )
  ref <- rbind(ref, data.frame(composite_id = "H1", sequence = substring(fx$variants[1], 1L, 700L)))
  out <- suppressMessages(match_reference_region(ref, fx$esvs,
    primer_fwd = fwd, primer_rev = rev, keep_unplaced = TRUE
  ))
  path <- stats::setNames(out$trim_path, out$composite_id)
  expect_equal(unname(path), c("primer_anchored", "primer_anchored_reverse_complement",
                               "short_of_region", "primer_anchored", "esv_aligned"))
  expect_equal(out$sequence[1:2], c(insert, insert))
  expect_equal(out$sequence[4], insert)
  expect_true(all(is.na(out$region_identity[1:4])))

  # without primers the same records stay unplaced: no anchor is not evidence
  # that a record already is the amplicon
  out2 <- suppressMessages(match_reference_region(ref, fx$esvs, keep_unplaced = TRUE))
  expect_true(all(out2$trim_path[1:4] %in% c("not_placed", "short_of_region")))
  expect_equal(out2$sequence[1], ref$sequence[1])
})

test_that("an unregistered or ambiguous barcode_term disables the fallback with a message", {
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")
  skip_if_not_installed("Matrix")
  fx <- .rr_fixture()
  expect_message(
    match_reference_region(fx$ref[1, ], fx$esvs, barcode_term = "18S"),
    "no primer fallback"
  )
})

test_that("records longer than the alignment window are placed through overlapping windows", {
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")
  skip_if_not_installed("Matrix")
  fx <- .rr_fixture()
  # window = 20 x 313 = 6260 bp; put the gene across a window boundary, on both strands
  long <- paste0(.rr_random(5900L, 11L), fx$variants[3], .rr_random(9000L, 12L))
  ref <- data.frame(composite_id = c("L1", "L2"), sequence = c(long, .rr_rc(long)))
  out <- suppressMessages(match_reference_region(ref, fx$esvs))
  expect_equal(out$trim_path, c("esv_aligned", "esv_aligned_reverse_complement"))
  expect_equal(out$sequence, rep(substring(fx$variants[3], 301L, 613L), 2L))
})

test_that("n_cores > 1 gives the same result as a single process", {
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")
  skip_if_not_installed("Matrix")
  skip_on_os("windows")
  fx <- .rr_fixture()
  a <- suppressMessages(match_reference_region(fx$ref, fx$esvs, keep_unplaced = TRUE))
  b <- suppressMessages(match_reference_region(fx$ref, fx$esvs, keep_unplaced = TRUE, n_cores = 2L))
  expect_identical(a, b)
})

test_that("build_sequence_matrix() does not apply the deposit window to a region-matched set", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")
  skip_if_not_installed("Matrix")
  fx <- .rr_fixture()
  ref <- fx$ref[c(1, 2, 5), ]
  ref$genus <- "G"
  ref$species <- c("G a", "G b", "G b")
  rm_ref <- suppressMessages(match_reference_region(ref, fx$esvs))
  # COI-Leray's deposit window (300-900 bp) would keep the 313 bp regions anyway;
  # use a marker whose window excludes them to show the exemption
  expect_message(
    sm <- build_sequence_matrix(rm_ref, rank_system = c("genus", "species"),
                                barcode_term = "MiFishU", verbose = FALSE),
    "region-matched"
  )
  expect_true(nrow(sm) > 0L)
})

test_that("build_sequence_matrix() refuses a region-matched set that still holds unplaced rows", {
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")
  skip_if_not_installed("Matrix")
  fx <- .rr_fixture()
  kept <- suppressMessages(match_reference_region(fx$ref, fx$esvs, keep_unplaced = TRUE))
  expect_error(build_sequence_matrix(kept, rank_system = "species"), "were not placed on the ESV region")
})
