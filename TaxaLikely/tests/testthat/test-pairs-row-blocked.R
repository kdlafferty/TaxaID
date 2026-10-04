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

# The two steps that followed extraction, also as they were.
.oracle_bind <- function(pieces) {
  n <- length(pieces)
  dplyr::bind_rows(dplyr::bind_rows(pieces[-n]), pieces[[n]])
}
.oracle_ranks <- function(dist_tbl, lookup, rank_cols) {
  dist_tbl |>
    dplyr::left_join(lookup, by = c("id_x" = "composite_id")) |>
    dplyr::rename_with(~ paste0(., ".x"), dplyr::all_of(rank_cols)) |>
    dplyr::left_join(lookup, by = c("id_y" = "composite_id")) |>
    dplyr::rename_with(~ paste0(., ".y"), dplyr::all_of(rank_cols))
}

.oracle_retention <- function(dist_tbl, retain, chunk_rows = NULL) {
  .lab <- function(v, k) if (is.null(v)) NULL else unname(v[k])
  .best_per_partner_keep(
    x = dist_tbl$id_x,
    sp_x = .lab(retain$species, dist_tbl$id_x), sp_y = .lab(retain$species, dist_tbl$id_y),
    gn_x = .lab(retain$genus, dist_tbl$id_x), gn_y = .lab(retain$genus, dist_tbl$id_y),
    fam_x = .lab(retain$family, dist_tbl$id_x), fam_y = .lab(retain$family, dist_tbl$id_y),
    p_match = dist_tbl$p_match, coverage = dist_tbl$coverage, tie = dist_tbl$id_y,
    min_pair_coverage = retain$min_pair_coverage, by = retain$by
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

test_that("rank columns by match() equal the two left_joins, including NA and missing ids", {
  pt <- data.frame(
    id_x = c("a", "b", "zz", NA, "c", "a"),
    id_y = c("b", "zz", "a", "c", NA, "c"),
    p_match = c(.9, .8, .7, .6, .5, .4), coverage = c(1, 1, NA, .5, 1, 1),
    stringsAsFactors = FALSE
  )
  pt <- pt[c(6, 2, 3, 1, 4, 5), ] # non-default row names, as after subsetting
  lk <- data.frame(
    composite_id = c("a", "b", "c", NA),
    family = c("F1", NA, "F2", "Fna"),
    genus = factor(c("G1", "G1", NA, "Gna")),
    species = c("s1", "s2", NA, NA),
    stringsAsFactors = FALSE
  )
  rk <- c("family", "genus", "species")
  expect_identical(.attach_rank_columns(pt, lk, rk), .oracle_ranks(pt, lk, rk))
  # Factor id columns on either side.
  pt_f <- pt
  pt_f$id_x <- factor(pt_f$id_x)
  lk_f <- lk
  lk_f$composite_id <- factor(lk_f$composite_id)
  expect_identical(
    suppressWarnings(.attach_rank_columns(pt, lk_f, rk)),
    suppressWarnings(.oracle_ranks(pt, lk_f, rk))
  )
  # Empty table, and no rank columns at all.
  expect_identical(.attach_rank_columns(pt[0, ], lk, rk), .oracle_ranks(pt[0, ], lk, rk))
  # (The old joins errored with no rank columns; the new code returns the table.)
  no_rk <- pt
  rownames(no_rk) <- NULL
  expect_identical(.attach_rank_columns(pt, lk["composite_id"], character(0)), no_rk)
    # The lookup comes from the deduplicated reference table; a duplicate key
  # would make the old joins add rows, so it is an internal error here.
  lk_dup <- rbind(lk, data.frame(composite_id = "a", family = "F9", genus = "G9", species = "s9"))
  expect_gt(nrow(suppressWarnings(.oracle_ranks(pt, lk_dup, rk))), nrow(pt))
  expect_error(.attach_rank_columns(pt, lk_dup, rk), "duplicated composite_id")
})

test_that("the single bind equals the two-step bind", {
  mk <- function(ids) {
    data.frame(id_x = ids, id_y = rev(ids), p_match = seq_along(ids) / 10,
      coverage = rep(1, length(ids)), stringsAsFactors = FALSE)
  }
  cases <- list(
    list(mk(c("a", "b")), NULL, mk("c"), mk(c("d", "e"))),
    list(NULL, NULL, mk("c")),
    list(mk("a"), mk(character(0))),
    list(NULL, mk(character(0)))
  )
  for (k in seq_along(cases)) {
    got <- .bind_pair_pieces(cases[[k]])
    want <- .oracle_bind(cases[[k]])
    # When every per-genus piece was NULL the old two-step bind returned a
    # tibble (bind_rows() of NULLs is a 0-column tibble); everywhere else it
    # returned a data.frame. The single bind returns a data.frame throughout.
    if (all(vapply(utils::head(cases[[k]], -1L), is.null, NA))) {
      expect_s3_class(want, "tbl_df")
      want <- as.data.frame(want)
    }
    expect_s3_class(got, "data.frame", exact = TRUE)
    expect_identical(got, want, info = as.character(k))
    # Order is the pieces' order: no reliance on the oracle for that.
    expect_identical(got$id_x, unlist(lapply(cases[[k]], `[[`, "id_x")), info = as.character(k))
  }
  # A bind that loses rows is refused.
  testthat::local_mocked_bindings(bind_rows = function(...) data.frame(id_x = "a"), .package = "dplyr")
  expect_error(.bind_pair_pieces(cases[[1]]), "Internal error: binding pair tables")
})

test_that("build_sequence_matrix() output and attributes are unchanged by the new extraction, bind and rank columns", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  ref <- .rb_fixture()
  # NA ranks reach the rank-column step: three references lose their family.
  ref$family[c(2, 17, 40)] <- NA
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
      },
      .bind_pair_pieces = .oracle_bind,
      .attach_rank_columns = .oracle_ranks,
      .retention_keep_chunked = .oracle_retention
    )
    expect_true(anyNA(old$family.x), info = nm)
    for (b in c(2L, 5L, 7L)) {
      new <- local({
        op <- options(TaxaLikely.pair_block_rows = b, TaxaLikely.retention_chunk_rows = b)
        on.exit(options(op))
        do.call(.build, configs[[nm]])
      })
      expect_identical(new, old, info = sprintf("%s, block_rows = %d (as returned)", nm, b))
      expect_identical(.canon(new), .canon(old), info = sprintf("%s, block_rows = %d", nm, b))
      expect_identical(.attrs(new), .attrs(old), info = sprintf("%s attributes, block_rows = %d", nm, b))
    }
    expect_identical(attr(old, "pair_retention")$policy, configs[[nm]]$pair_retention)
  }
})

test_that("memory reporting is silent by default", {
  expect_silent(.mem_stage("x", verbose = TRUE))
  expect_silent(.mem_stage("x", verbose = FALSE))
  op <- options(TaxaLikely.report_memory = TRUE)
  on.exit(options(op))
  expect_message(.mem_stage("x", verbose = TRUE), "\\[memory\\] x: heap")
  expect_silent(.mem_stage("x", verbose = FALSE))
})

test_that("the chunked final retention pass equals one pass, with chunks cut between id_x values", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  a <- .rb_aligned()
  ref <- a$ref
  all_pairs <- .pairs_from_distance(a$dist_m, a$aligned, 0.25)
  # Mimic the bound table: the same pair can arrive from two alignments with
  # different values, and one id_x's rows are scattered through the table.
  set.seed(7)
  extra <- all_pairs[sample(nrow(all_pairs), 400), ]
  extra$coverage <- pmax(0, extra$coverage - 0.3)
  tied <- all_pairs[sample(nrow(all_pairs), 50), ] # fully tied duplicates
  tbl <- rbind(all_pairs, extra, tied)
  tbl <- tbl[sample(nrow(tbl)), ]
  rownames(tbl) <- NULL
  n <- nrow(tbl)
  for (by in c("best_per_partner", "best_per_class")) {
    retain <- .retention_context(ref, c("family", "genus", "species"), 0.8, by)
    want <- .oracle_retention(tbl, retain)
    xc <- match(tbl$id_x, unique(tbl$id_x))
    for (cr in c(1, 2, 3, 7, 11, 13, 101, n, 2e6)) {
      n_chunks <- length(unique((xc - 1L) %/% ceiling(max(xc) / max(1, ceiling(n / cr)))))
      if (cr <= 101) expect_gt(n_chunks, 1L)
      expect_identical(.retention_keep_chunked(tbl, retain, chunk_rows = cr), want,
        info = sprintf("%s, chunk_rows = %s (%d chunks)", by, cr, n_chunks)
      )
    }
  }
  # The fixture does have id_x values whose rows straddle a naive row cut ...
  cut <- 13
  straddle <- vapply(split(seq_len(n), tbl$id_x), function(r) length(unique((r - 1L) %/% cut)) > 1L, NA)
  expect_true(any(straddle))
  # ... and chunking by row ranges would get the answer wrong there.
  retain <- .retention_context(ref, c("family", "genus", "species"), 0.8, "best_per_partner")
  naive <- logical(n)
  for (rows in split(seq_len(n), (seq_len(n) - 1L) %/% cut)) {
    naive[rows] <- .oracle_retention(tbl[rows, , drop = FALSE], retain)
  }
  expect_false(identical(naive, .oracle_retention(tbl, retain)))
})

test_that("duplicated reference ids: identical copies are announced and kept once, differing copies are refused", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  ref <- .rb_fixture()
  dup <- rbind(ref, ref[c(3, 20), ])
  .build <- function(x) {
    build_sequence_matrix(x,
      rank_system = c("family", "genus", "species"),
      min_seq_len = 1L, max_seq_len = 1000L, seed = 1L, verbose = FALSE
    )
  }
  expect_message(got <- .build(dup), "2 composite_id\\(s\\) appear more than once with identical sequence")
  ref_ids <- ref$composite_id[c(3, 20)]
  # No self-pair from a duplicated id, and the same matrix as without the copies.
  expect_false(any(got$id_x == got$id_y))
  expect_identical(got, suppressMessages(.build(ref)))
  # Copies that disagree are an error, naming the id.
  bad_seq <- dup
  bad_seq$sequence[nrow(bad_seq)] <- paste0(bad_seq$sequence[nrow(bad_seq)], "A")
  expect_error(suppressMessages(.build(bad_seq)), ref_ids[2])
  bad_rank <- dup
  bad_rank$genus[nrow(bad_rank)] <- "Othergenus"
  expect_error(suppressMessages(.build(bad_rank)), "different sequence or different sequence/family/genus/species")
  # A column the matrix does not use may differ (the real case: queried_taxon).
  extra_col <- dup
  extra_col$queried_taxon <- "a"
  extra_col$queried_taxon[nrow(extra_col)] <- "b"
  expect_message(.build(extra_col), "kept one copy")
})
