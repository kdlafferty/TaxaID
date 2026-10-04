# .pairs_from_distance() extracts the pair table in row blocks. These tests pin
# it to the whole-matrix extraction it replaced: identical pairs, order,
# p_match and coverage, with and without pair_filter and best_per_partner
# retention, at block sizes that put boundaries everywhere -- and they check
# that the comparison is sensitive enough to catch a boundary error.
#
# Fixture: 47 real 12S MiFish-region references (6 genera, 27 species) cut by
# match_reference_region() from CalIntertidal's GenBank fetch. 47 is prime, so
# no tested block size divides it.

# The extraction as it was before row blocking, kept verbatim as the oracle.
.oracle_pairs <- function(dist_m, aligned, max_dist, retain = NULL, pair_filter = NULL) {
  empty <- data.frame(
    id_x = character(0L), id_y = character(0L),
    p_match = numeric(0L), coverage = numeric(0L),
    stringsAsFactors = FALSE
  )
  idx <- which(dist_m < max_dist & row(dist_m) != col(dist_m), arr.ind = TRUE)
  if (nrow(idx) == 0L) {
    return(empty)
  }
  i <- idx[, 1L]
  j <- idx[, 2L]
  p_match <- 1 - dist_m[idx]
  rm(idx)
  aln_str <- as.character(aligned)
  seq_names <- names(aligned)
  n_seq <- length(aln_str)
  gap_mat <- matrix(
    as.double(unlist(strsplit(aln_str, "", fixed = TRUE), use.names = FALSE) != "-"),
    nrow = n_seq, byrow = TRUE
  )
  orig_widths <- as.integer(rowSums(gap_mat))
  overlap <- numeric(length(i))
  block <- max(1L, as.integer(floor(3.2e7 / n_seq)))
  ord_i <- order(i)
  i_sorted <- i[ord_i]
  for (s in seq.int(1L, n_seq, by = block)) {
    e <- min(s + block - 1L, n_seq)
    sel <- ord_i[i_sorted >= s & i_sorted <= e]
    if (length(sel) == 0L) next
    ov_block <- tcrossprod(gap_mat[s:e, , drop = FALSE], gap_mat)
    overlap[sel] <- ov_block[cbind(i[sel] - s + 1L, j[sel])]
  }
  min_len <- pmin(orig_widths[i], orig_widths[j])
  coverage <- ifelse(min_len == 0L, NA_real_, overlap / min_len)
  if (!is.null(pair_filter)) {
    elig <- pair_filter(seq_names[i], seq_names[j])
    if (!any(elig)) {
      return(empty)
    }
    i <- i[elig]
    j <- j[elig]
    p_match <- p_match[elig]
    coverage <- coverage[elig]
  }
  if (!is.null(retain)) {
    .lab <- function(v, k) if (is.null(v)) NULL else unname(v[seq_names[k]])
    keep <- .best_per_partner_keep(
      x = i,
      sp_x = .lab(retain$species, i), sp_y = .lab(retain$species, j),
      gn_x = .lab(retain$genus, i), gn_y = .lab(retain$genus, j),
      fam_x = .lab(retain$family, i), fam_y = .lab(retain$family, j),
      p_match = p_match, coverage = coverage, tie = j,
      min_pair_coverage = retain$min_pair_coverage, by = retain$by
    )
    if (!any(keep)) {
      return(empty)
    }
    i <- i[keep]
    j <- j[keep]
    p_match <- p_match[keep]
    coverage <- coverage[keep]
  }
  data.frame(
    id_x = seq_names[i], id_y = seq_names[j],
    p_match = p_match, coverage = coverage, stringsAsFactors = FALSE
  )
}

.rb_fixture <- function() utils::read.csv(test_path("fixtures", "rowblock_12S.csv"), stringsAsFactors = FALSE)

.rb_aligned <- function() {
  ref <- .rb_fixture()
  dna <- Biostrings::DNAStringSet(stats::setNames(ref$sequence, ref$composite_id))
  aligned <- DECIPHER::AlignSeqs(dna, processors = 1L, verbose = FALSE)
  dist_m <- DECIPHER::DistanceMatrix(aligned,
    type = "matrix", includeTerminalGaps = FALSE,
    processors = 1L, verbose = FALSE
  )
  list(ref = ref, aligned = aligned, dist_m = dist_m)
}

test_that("row-blocked extraction is identical to the whole-matrix extraction at every block size", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  a <- .rb_aligned()
  ref <- a$ref
  retain <- .retention_context(ref, c("family", "genus", "species"), 0.8, "best_per_partner")
  retain_cls <- .retention_context(ref, c("family", "genus", "species"), 0.8, "best_per_class")
  gen <- stats::setNames(ref$genus, ref$composite_id)
  cross_genus_only <- function(x, y) gen[x] != gen[y]
  settings <- list(
    all = list(retain = NULL, pair_filter = NULL),
    best_per_partner = list(retain = retain, pair_filter = NULL),
    best_per_class = list(retain = retain_cls, pair_filter = NULL),
    filter_then_retain = list(retain = retain, pair_filter = cross_genus_only)
  )
  for (nm in names(settings)) {
    st <- settings[[nm]]
    oracle <- .oracle_pairs(a$dist_m, a$aligned, 0.25, st$retain, st$pair_filter)
    expect_gt(nrow(oracle), 0L)
    # 47 rows -> blocks: 47, 24, 16, 10, 7, 2, 1, 1, and 1 at the default size.
    for (b in list(1L, 2L, 3L, 5L, 7L, 46L, 47L, 48L, NULL)) {
      got <- .pairs_from_distance(a$dist_m, a$aligned, 0.25,
        retain = st$retain, pair_filter = st$pair_filter, block_rows = b
      )
      expect_identical(got, oracle, info = sprintf("%s, block_rows = %s", nm, format(b)))
    }
  }
})

test_that("the comparison catches a block-boundary error", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  a <- .rb_aligned()
  oracle <- .oracle_pairs(a$dist_m, a$aligned, 0.25)
  # Off-by-one at every boundary: each block drops its last row.
  broken <- .pairs_from_distance
  body(broken) <- parse(text = sub(
    "e <- min(s + block - 1L, n_seq)", "e <- min(s + block - 2L, n_seq)",
    paste(deparse(body(.pairs_from_distance)), collapse = "\n"), fixed = TRUE
  ))[[1]]
  environment(broken) <- environment(.pairs_from_distance)
  expect_false(identical(broken(a$dist_m, a$aligned, 0.25, block_rows = 5L), oracle))
  # ... and the unbroken function at the same block size matches.
  expect_identical(.pairs_from_distance(a$dist_m, a$aligned, 0.25, block_rows = 5L), oracle)
  # The fixture spans more than one block at this size, so boundaries exist.
  expect_equal(ceiling(nrow(a$dist_m) / 5L), 10)
})

test_that("an empty result keeps the empty-table shape", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  a <- .rb_aligned()
  got <- .pairs_from_distance(a$dist_m, a$aligned, max_dist = 0, block_rows = 3L)
  expect_identical(got, .oracle_pairs(a$dist_m, a$aligned, 0))
  expect_identical(names(got), c("id_x", "id_y", "p_match", "coverage"))
  expect_equal(nrow(got), 0L)
})

test_that("build_sequence_matrix() output and attributes are unchanged by row blocking", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  ref <- .rb_fixture()
  .canon <- function(x) {
    x <- x[order(x$id_x, x$id_y), , drop = FALSE]
    rownames(x) <- NULL
    x
  }
  .attrs <- function(x) {
    a <- attributes(x)
    a[setdiff(names(a), c("row.names", "names"))]
  }
  .build <- function(...) {
    suppressMessages(build_sequence_matrix(ref,
      rank_system = c("family", "genus", "species"),
      min_seq_len = 1L, max_seq_len = 1000L, seed = 1L, verbose = FALSE, ...
    ))
  }
  configs <- list(
    whole_all = list(by_genus = FALSE, pair_retention = "all"),
    whole_bpp = list(by_genus = FALSE, pair_retention = "best_per_partner"),
    genus_all = list(by_genus = TRUE, pair_retention = "all"),
    genus_bpp = list(by_genus = TRUE, pair_retention = "best_per_partner")
  )
  for (nm in names(configs)) {
    old <- testthat::with_mocked_bindings(
      do.call(.build, configs[[nm]]),
      .pairs_from_distance = function(dist_m, aligned, max_dist, retain = NULL,
                                      pair_filter = NULL, block_rows = NULL) {
        .oracle_pairs(dist_m, aligned, max_dist, retain, pair_filter)
      }
    )
    for (b in c(2L, 5L, 7L)) {
      new <- local({
        op <- options(TaxaLikely.pair_block_rows = b)
        on.exit(options(op))
        do.call(.build, configs[[nm]])
      })
      expect_identical(.canon(new), .canon(old), info = sprintf("%s, block_rows = %d", nm, b))
      expect_identical(.attrs(new), .attrs(old), info = sprintf("%s attributes, block_rows = %d", nm, b))
    }
    if (configs[[nm]]$pair_retention != "all") {
      expect_identical(attr(old, "pair_retention")$policy, configs[[nm]]$pair_retention)
    }
  }
})
