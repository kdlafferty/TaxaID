utils::globalVariables(c("trim_path"))

# ==============================================================================
# match_reference_region() -- trim every reference to the stretch of the gene
# the study's own ESVs cover, learned from the ESVs rather than from primers.
# ==============================================================================

#' Trim reference sequences to the region the study's ESVs cover
#'
#' The likelihood model is trained on identities between pairs of reference
#' sequences ([build_sequence_matrix()]) and applied to identities between an
#' ESV and a reference. The two scales are comparable only if both are
#' measured over the same stretch of the gene. GenBank deposits rarely are:
#' they may be longer than the amplicon (a full barcode, a whole gene, a
#' mitogenome), cover a different stretch of the same gene (an 18S V4 deposit
#' in a V9 study; a non-MiFish stretch of 12S), or stop part-way into it.
#' [build_sequence_matrix()]'s length window cannot tell these apart: it keeps
#' a 655 bp Folmer record whole in a 313 bp Leray study and keeps an 18S V4
#' record that does not contain V9 at all, while it drops a mitogenome that
#' contains the amplicon.
#'
#' `match_reference_region()` places every reference on the region the ESVs
#' themselves cover, so it needs no primer pair and works for any marker:
#' \enumerate{
#'   \item For each reference (both strands), the ESVs sharing the largest
#'     fraction of their 8-mers with it are taken as candidates.
#'   \item The reference is aligned to each candidate with an overlap
#'     alignment (end gaps free), and the best-scoring alignment is kept.
#'   \item The alignment counts as homologous only if its score exceeds every
#'     score obtained by aligning the REVERSED (not complemented) and the
#'     COMPLEMENTED (not reversed) references to the same ESVs. Both
#'     transforms keep a record's length and base composition and destroy its
#'     homology, so they give an empirical no-homology null without assuming
#'     an identity floor. A shuffled null would also keep composition, but it
#'     needs a random draw, so a result would depend on the RNG state. An
#'     identity floor (for example `1 - max_dist`) would be wrong here: on
#'     CalIntertidal COI the median identity of a GenBank reference to its
#'     closest ESV is about 80%, the same as the median BLAST score of the
#'     study's own match object.
#'   \item The ESV's ends are projected onto the reference, and the reference
#'     is cut to that span. A span covering less than `min_coverage` of the
#'     ESV is a partial deposit and is not placed.
#'   \item References the alignment did not place fall back to primer
#'     anchoring, when a primer pair is available. One primer site is enough:
#'     the span starts after the forward site (or ends before the reverse
#'     site) and runs for the median ESV length.
#' }
#'
#' A reference that cannot be placed is never used whole: absence of an
#' anchor is not evidence that a record already is the amplicon. Unplaced
#' rows are dropped unless `keep_unplaced = TRUE`, and every row records how
#' it was handled in `trim_path`.
#'
#' @section Pipeline placement:
#' Between the reference fetch and [build_sequence_matrix()]:
#' \preformatted{
#' reference_df <- fetch_ncbi_reference_sequences(...)
#' reference_df <- match_reference_region(reference_df,
#'                                        esv_sequences = match_df$sequence,
#'                                        barcode_term  = "COI-Leray")
#' seq_matrix   <- build_sequence_matrix(reference_df, barcode_term = "COI-Leray", ...)
#' }
#' [build_sequence_matrix()] recognises the `trim_path` column and does not
#' apply `barcode_term`'s deposit-length window to region-matched sequences
#' (a Leray region of 250-313 bp would otherwise fail COI's 300-900 bp
#' window).
#'
#' Rebuilding the matrix from region-matched references changes the trained
#' model, so the query-noise calibration and every likelihood computed from
#' the old matrix must be recomputed.
#'
#' @section Region matching needs the study's own matched references:
#' Region matching removes every reference that does not cover the ESV span,
#' so it is only as good as the reference set's coverage of that span. A
#' fetch by taxon name and marker term can return mostly other stretches of
#' the gene: on an 18S V9 study, 73% of the fetched references lacked V9, and
#' only 950 of the 6,902 accessions the ESVs actually matched had been fetched
#' at all. Region matching that set alone cut the trained species from 5,347 to
#' 2,098 and the share of observations won by a referenced species from 10% to
#' 1.6%. Adding the match object's own accessions (they cover the span by
#' construction, since the ESVs matched them) before calling this function
#' restored coverage, and training on the result did no worse than training on
#' the unmatched set (12% won by a referenced species). Do not adopt region
#' matching without that step.
#'
#' The added accessions came to the reference set because the queries matched
#' them, so pairs between two of them are tighter than pairs between fetched
#' references (within-species variance about 60% as large in that study). They
#' were 4.7% of within-species pairs there; keep the share small, or drop
#' pairs whose two references both came from the match object.
#'
#' @section Batch dependence:
#' The homology threshold is the largest null score in the call, so it rises
#' slowly with the number of references, and with only a handful of
#' references it is low. It decides only whether an unplaced record is
#' reported as `"short_of_region"` (homologous but partial) or `"not_placed"`
#' (no homology): a placed record must also cover `min_coverage` of the ESV,
#' which a chance alignment does not. Call this once on the whole reference
#' set rather than on pieces of it; the threshold used is returned in
#' `attr(, "homology_threshold")`.
#'
#' @param reference_df Data frame with at least `composite_id` and `sequence`
#'   (the object [fetch_ncbi_reference_sequences()] returns and
#'   [build_sequence_matrix()] consumes).
#' @param esv_sequences Character vector of the study's ESV (ASV/OTU)
#'   sequences, as submitted to the reference search. Duplicates are ignored.
#'   These define the region.
#' @param barcode_term Character scalar or `NULL`. Used only to look up a
#'   registered primer pair for the fallback, via
#'   [TaxaTools::resolve_barcode_primers()]. A term with no registered pair,
#'   or an ambiguous one such as `"18S"`, simply disables the fallback.
#' @param primer_fwd,primer_rev Character scalars, 5' to 3', IUPAC allowed.
#'   Supply both, or neither (to use `barcode_term`).
#' @param min_coverage Numeric in `(0, 1]` (default `0.8`). Smallest share of
#'   the ESV span a placed reference must cover. Use the same value as
#'   [build_sequence_matrix()]'s `min_pair_coverage`.
#' @param max_mismatch_rate Numeric in `[0, 1)` (default `0.15`). Fraction of
#'   primer positions allowed to mismatch in the primer fallback, as in
#'   [trim_to_amplicon()].
#' @param keep_unplaced Logical (default `FALSE`). `TRUE` keeps unplaced rows,
#'   with their sequence as deposited, so they can be inspected.
#'   [build_sequence_matrix()] refuses such a data frame until they are
#'   dropped.
#' @param n_candidates Integer (default `3L`). Candidate ESVs aligned per
#'   reference.
#' @param n_cores Integer (default `1L`). Forked worker processes
#'   (`parallel::mclapply()`; must be 1 on Windows).
#' @param verbose Logical (default `TRUE`).
#'
#' @return `reference_df`, with `sequence` replaced by the region for placed
#'   rows, unplaced rows dropped (unless `keep_unplaced`), and five columns
#'   added:
#'   \describe{
#'     \item{`trim_path`}{How the row was handled: `"esv_aligned"`,
#'       `"esv_aligned_reverse_complement"`, `"primer_anchored"`,
#'       `"primer_anchored_reverse_complement"` (placed), or
#'       `"short_of_region"`, `"not_placed"`, `"invalid_sequence"`
#'       (unplaced). The vocabulary extends TaxaMatch's `query_trim_path`.}
#'     \item{`len_submitted`}{Length of the sequence as deposited.}
#'     \item{`region_coverage`}{Share of the ESV span the placed sequence
#'       covers.}
#'     \item{`region_identity`}{Identity to the ESV it was aligned to
#'       (`NA` for primer anchoring).}
#'     \item{`homology_score`}{Overlap-alignment score of that alignment.}
#'   }
#'   Attributes: `homology_threshold`, `region_length` (median ESV length),
#'   and `trim_path_counts` (counts over ALL input rows, including dropped
#'   ones).
#'
#' @seealso [build_sequence_matrix()], [trim_to_amplicon()]
#'
#' @examples
#' if (requireNamespace("Biostrings", quietly = TRUE) &&
#'   requireNamespace("pwalign", quietly = TRUE) &&
#'   requireNamespace("Matrix", quietly = TRUE)) {
#'   set.seed(1)
#'   gene <- paste(sample(c("A", "C", "G", "T"), 600, replace = TRUE), collapse = "")
#'   # the study's ESVs cover positions 201-350 of the gene
#'   esvs <- substring(gene, 201, 350)
#'   reference_df <- data.frame(
#'     composite_id = c("long_deposit", "other_stretch"),
#'     sequence = c(
#'       substring(gene, 101, 500), # contains the ESV span
#'       substring(gene, 400, 600) # a different stretch of the same gene
#'     )
#'   )
#'   out <- match_reference_region(reference_df, esvs, keep_unplaced = TRUE)
#'   out[, c("composite_id", "trim_path", "len_submitted", "region_coverage")]
#'   nchar(out$sequence[1]) # 150: cut to the ESV span
#'   attr(out, "trim_path_counts")
#' }
#'
#' \dontrun{
#' # In a workflow, between the reference fetch and the matrix build:
#' reference_df <- match_reference_region(reference_df,
#'   esv_sequences = unique(match_df$sequence), barcode_term = "COI-Leray",
#'   n_cores = 4L
#' )
#' seq_matrix <- build_sequence_matrix(reference_df, barcode_term = "COI-Leray")
#' }
#'
#' @export
match_reference_region <- function(reference_df,
                                   esv_sequences,
                                   barcode_term = NULL,
                                   primer_fwd = NULL,
                                   primer_rev = NULL,
                                   min_coverage = 0.8,
                                   max_mismatch_rate = 0.15,
                                   keep_unplaced = FALSE,
                                   n_candidates = 3L,
                                   n_cores = 1L,
                                   verbose = TRUE) {
  if (!is.data.frame(reference_df)) stop("reference_df must be a data frame")
  missing_cols <- setdiff(c("composite_id", "sequence"), names(reference_df))
  if (length(missing_cols)) {
    stop(sprintf("reference_df is missing required columns: %s", paste(missing_cols, collapse = ", ")))
  }
  if (!is.character(esv_sequences)) stop("esv_sequences must be a character vector")
  if (xor(is.null(primer_fwd), is.null(primer_rev))) {
    stop("match_reference_region: supply both primer_fwd and primer_rev, or neither")
  }
  .check_unit <- function(x, nm, lo_open) {
    ok <- is.numeric(x) && length(x) == 1L && !is.na(x) &&
      (if (lo_open) x > 0 && x <= 1 else x >= 0 && x < 1)
    if (!ok) stop(sprintf("%s must be a single number in %s", nm, if (lo_open) "(0, 1]" else "[0, 1)"))
  }
  .check_unit(min_coverage, "min_coverage", TRUE)
  .check_unit(max_mismatch_rate, "max_mismatch_rate", FALSE)
  for (nm in c("keep_unplaced", "verbose")) {
    v <- get(nm)
    if (!is.logical(v) || length(v) != 1L || is.na(v)) stop(sprintf("%s must be TRUE or FALSE", nm))
  }
  for (nm in c("n_candidates", "n_cores")) {
    v <- get(nm)
    if (!is.numeric(v) || length(v) != 1L || is.na(v) || v < 1) stop(sprintf("%s must be a positive integer", nm))
  }
  n_candidates <- as.integer(n_candidates)
  n_cores <- as.integer(n_cores)
  for (pkg in c("Biostrings", "pwalign", "Matrix")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf("Package '%s' is required for match_reference_region()", pkg))
    }
  }

  esv <- unique(toupper(esv_sequences[!is.na(esv_sequences)]))
  esv <- esv[grepl("^[ACGT]+$", esv)]
  if (!length(esv)) stop("esv_sequences holds no unambiguous ACGT sequence")
  esv_set <- Biostrings::DNAStringSet(esv)
  region_len <- as.integer(stats::median(Biostrings::width(esv_set)))

  # Work on distinct deposited sequences; map results back to rows at the end.
  seq_up <- toupper(reference_df$sequence)
  valid <- !is.na(seq_up) & nzchar(seq_up) & grepl("^[ACGTRYSWKMBDHVN]+$", seq_up)
  uniq <- unique(seq_up[valid])
  if (verbose) {
    message(sprintf(
      "match_reference_region: %s reference row(s) (%s distinct valid sequences) against %s ESV(s); region length %d bp (median ESV).",
      format(nrow(reference_df), big.mark = ","), format(length(uniq), big.mark = ","),
      format(length(esv_set), big.mark = ","), region_len
    ))
  }

  place <- .region_align_all(uniq, esv_set, n_candidates = n_candidates, n_cores = n_cores)
  threshold <- if (any(is.finite(place$null))) max(place$null[is.finite(place$null)]) else 0
  homologous <- is.finite(place$score) & place$score > threshold

  # Project the ESV's ends onto the reference: an overlap alignment may leave
  # a divergent ESV end unaligned, but the region still runs to that end.
  esv_w <- Biostrings::width(esv_set)[place$esv]
  r_start <- place$ps - (place$ss - 1L)
  r_end <- place$pe + (esv_w - place$se)
  r_start <- pmax(1L, r_start)
  r_end <- pmin(nchar(uniq), r_end)
  coverage <- pmin(1, (r_end - r_start + 1) / esv_w)

  path <- rep("not_placed", length(uniq))
  placed <- homologous & coverage >= min_coverage
  path[homologous & !placed] <- "short_of_region"
  path[placed] <- ifelse(place$rc[placed], "esv_aligned_reverse_complement", "esv_aligned")
  out_seq <- rep(NA_character_, length(uniq))
  if (any(placed)) {
    oriented <- ifelse(place$rc, .revcomp_chr(uniq), uniq)
    out_seq[placed] <- substring(oriented[placed], r_start[placed], r_end[placed])
  }
  identity <- ifelse(placed, place$id, NA_real_)
  coverage[!homologous] <- NA_real_

  # Primer fallback, only for records the ESV alignment did not place.
  primers <- .region_primers(barcode_term, primer_fwd, primer_rev, verbose)
  if (!is.null(primers) && any(!placed)) {
    idx <- which(!placed)
    anc <- .region_primer_anchor(uniq[idx], primers, esv_set, region_len, max_mismatch_rate)
    got <- !is.na(anc$start)
    cov_a <- ifelse(got, (anc$end - anc$start + 1) / region_len, NA_real_)
    ok <- got & cov_a >= min_coverage
    path[idx[got & !ok]] <- "short_of_region"
    path[idx[ok]] <- ifelse(anc$rc[ok], "primer_anchored_reverse_complement", "primer_anchored")
    coverage[idx[got]] <- pmin(1, cov_a[got])
    if (any(ok)) {
      oriented <- ifelse(anc$rc[ok], .revcomp_chr(uniq[idx[ok]]), uniq[idx[ok]])
      out_seq[idx[ok]] <- substring(oriented, anc$start[ok], anc$end[ok])
    }
  }

  m <- match(seq_up, uniq)
  row_path <- ifelse(valid, path[m], "invalid_sequence")
  res <- reference_df
  res$len_submitted <- nchar(reference_df$sequence)
  res$trim_path <- row_path
  res$region_coverage <- ifelse(valid, coverage[m], NA_real_)
  res$region_identity <- ifelse(valid, identity[m], NA_real_)
  res$homology_score <- ifelse(valid & is.finite(place$score[m]), place$score[m], NA_real_)
  is_placed <- row_path %in% .REGION_PLACED_PATHS
  res$sequence[is_placed] <- out_seq[m][is_placed]

  counts <- table(factor(row_path, levels = c(.REGION_PLACED_PATHS, .REGION_UNPLACED_PATHS)))
  if (verbose) {
    message(sprintf(
      "match_reference_region: homology threshold %.0f (largest no-homology null score); %s of %s row(s) placed. trim_path: %s.",
      threshold, format(sum(is_placed), big.mark = ","), format(nrow(res), big.mark = ","),
      paste(sprintf("%s=%s", names(counts), format(as.integer(counts), big.mark = ",")), collapse = ", ")
    ))
    if (!keep_unplaced && any(!is_placed)) {
      message(sprintf(
        "match_reference_region: %s unplaced row(s) dropped -- they do not cover the ESV region (keep_unplaced = TRUE to inspect them).",
        format(sum(!is_placed), big.mark = ",")
      ))
    }
  }
  if (!keep_unplaced) res <- res[is_placed, , drop = FALSE]
  attr(res, "homology_threshold") <- threshold
  attr(res, "region_length") <- region_len
  attr(res, "trim_path_counts") <- counts
  res
}

#' @noRd
.REGION_PLACED_PATHS <- c(
  "esv_aligned", "esv_aligned_reverse_complement",
  "primer_anchored", "primer_anchored_reverse_complement"
)
#' @noRd
.REGION_UNPLACED_PATHS <- c("short_of_region", "not_placed", "invalid_sequence")

#' @noRd
.revcomp_chr <- function(x) {
  as.character(Biostrings::reverseComplement(Biostrings::DNAStringSet(x)))
}

#' Sparse 0/1 matrix of 8-mer presence, rows = sequences
#' @noRd
.kmer_presence <- function(set, k = 8L, block = 500L) {
  parts <- lapply(seq(1L, length(set), by = block), function(s) {
    w <- s:min(length(set), s + block - 1L)
    f <- Biostrings::oligonucleotideFrequency(set[w], width = k)
    Matrix::Matrix((f > 0) * 1, sparse = TRUE)
  })
  do.call(rbind, parts)
}

#' Best overlap alignment of every reference to its candidate ESVs, plus the
#' reversed-sequence null score of that same pairing.
#'
#' Long references are cut into overlapping windows (each longer than any ESV
#' by a full ESV length) so the alignment's dynamic-programming matrix stays
#' bounded; the windows are scored as separate records and the best window
#' wins, with its coordinates shifted back.
#' @noRd
.region_align_all <- function(seqs, esv_set, n_candidates, n_cores, chunk = 500L) {
  max_esv <- max(Biostrings::width(esv_set))
  win <- 20L * max_esv
  step <- win - 2L * max_esv
  # windows: (record, offset)
  lens <- nchar(seqs)
  n_win <- ifelse(lens > win, ceiling((lens - win) / step) + 1L, 1L)
  rec <- rep(seq_along(seqs), n_win)
  off <- unlist(lapply(n_win, function(n) (seq_len(n) - 1L) * step), use.names = FALSE)
  wseq <- ifelse(lens[rec] > win, substring(seqs[rec], off + 1L, off + win), seqs[rec])

  esv_k <- .kmer_presence(esv_set)
  esv_n <- pmax(1, Matrix::rowSums(esv_k))
  sm <- pwalign::nucleotideSubstitutionMatrix(match = 1, mismatch = -1, baseOnly = FALSE)
  aln <- function(q, s) {
    pwalign::pairwiseAlignment(q, s,
      type = "overlap", gapOpening = 10, gapExtension = 4,
      substitutionMatrix = sm
    )
  }

  one_chunk <- function(w) {
    plus <- Biostrings::DNAStringSet(wseq[w])
    minus <- Biostrings::reverseComplement(plus)
    sim <- cbind(
      as.matrix(.kmer_presence(plus) %*% Matrix::t(esv_k)),
      as.matrix(.kmer_presence(minus) %*% Matrix::t(esv_k))
    )
    sim <- sweep(sim, 2L, c(esv_n, esv_n), "/")
    n_e <- length(esv_set)
    out <- data.frame(
      score = rep(-Inf, length(w)), esv = NA_integer_, rc = FALSE,
      ps = NA_integer_, pe = NA_integer_, ss = NA_integer_, se = NA_integer_,
      id = NA_real_, null = -Inf
    )
    top <- t(apply(sim, 1L, function(v) order(v, decreasing = TRUE)[seq_len(min(n_candidates, length(v)))]))
    if (length(w) == 1L) top <- matrix(top, nrow = 1L)
    has_kmer <- apply(sim, 1L, max) > 0
    for (t in seq_len(ncol(top))) {
      cand <- top[, t]
      for (key in unique(cand[has_kmer])) {
        i <- which(cand == key & has_kmer)
        j <- ((key - 1L) %% n_e) + 1L
        rc <- key > n_e
        q <- if (rc) minus[i] else plus[i]
        a <- aln(q, esv_set[[j]])
        sc <- pwalign::score(a)
        b <- sc > out$score[i]
        if (!any(b)) next
        i2 <- i[b]
        a <- a[b]
        out$score[i2] <- sc[b]
        out$esv[i2] <- j
        out$rc[i2] <- rc
        out$ps[i2] <- Biostrings::start(pwalign::pattern(a))
        out$pe[i2] <- Biostrings::end(pwalign::pattern(a))
        out$ss[i2] <- Biostrings::start(pwalign::subject(a))
        out$se[i2] <- Biostrings::end(pwalign::subject(a))
        out$id[i2] <- pwalign::pid(a, "PID2") / 100
      }
    }
    for (j in unique(out$esv[!is.na(out$esv)])) {
      i <- which(out$esv %in% j)
      q <- plus[i]
      q[out$rc[i]] <- minus[i][out$rc[i]]
        # two no-homology transforms per record: reversed (not complemented)
      # and complemented (not reversed). Each keeps length and base
      # composition and destroys homology. A shuffled null would keep
      # composition too, but needs a random draw, so a result would depend
      # on the RNG state.
      out$null[i] <- pmax(
        pwalign::score(aln(Biostrings::reverse(q), esv_set[[j]])),
        pwalign::score(aln(Biostrings::complement(q), esv_set[[j]]))
      )
    }
    out
  }

  chunks <- split(seq_along(wseq), ceiling(seq_along(wseq) / chunk))
  parts <- if (n_cores > 1L) {
    parallel::mclapply(chunks, one_chunk, mc.cores = n_cores, mc.preschedule = FALSE)
  } else {
    lapply(chunks, one_chunk)
  }
  bad <- vapply(parts, inherits, logical(1L), "try-error")
  if (any(bad)) stop("match_reference_region: a worker failed: ", as.character(parts[[which(bad)[1L]]]))
  win_res <- do.call(rbind, parts)

  # Coordinates of a window on the minus strand: the window [off+1, off+win] of
  # the plus strand is [L-off-win+1, L-off] of the minus strand.
  wl <- nchar(wseq)
  shift <- ifelse(win_res$rc, lens[rec] - off - wl, off)
  win_res$ps <- win_res$ps + shift
  win_res$pe <- win_res$pe + shift
  win_res$rec <- rec

  # best window per record; the record's null is the largest over its windows
  ord <- order(win_res$rec, -win_res$score)
  best <- win_res[ord, ][!duplicated(win_res$rec[ord]), ]
  best$null <- tapply(win_res$null, win_res$rec, max)[as.character(best$rec)]
  best <- best[order(best$rec), ]
  best[, c("score", "esv", "rc", "ps", "pe", "ss", "se", "id", "null")]
}

#' Primer pair for the fallback, or NULL when none is available
#' @noRd
.region_primers <- function(barcode_term, primer_fwd, primer_rev, verbose) {
  if (!is.null(primer_fwd)) {
    return(list(fwd = toupper(primer_fwd), rev = toupper(primer_rev)))
  }
  if (is.null(barcode_term)) {
    return(NULL)
  }
  p <- tryCatch(TaxaTools::resolve_barcode_primers(barcode_term), error = function(e) NULL)
  if (is.null(p) && verbose) {
    message(sprintf(
      "match_reference_region: no single registered primer pair for '%s' -- no primer fallback; records with no homology to any ESV stay unplaced.",
      paste(barcode_term, collapse = "/")
    ))
  }
  if (is.null(p)) NULL else list(fwd = p$fwd, rev = p$rev)
}

#' Anchor records on one or both primer sites; region length from the ESVs.
#'
#' Whether the ESVs still carry their primers is read from the ESVs
#' themselves: if most begin with the forward primer, the anchored span
#' includes the primer sites, otherwise it starts just after the forward site
#' (ends just before the reverse site).
#' @return data frame with start, end (on the oriented sequence; NA when no
#'   site was found) and rc.
#' @noRd
.region_primer_anchor <- function(seqs, primers, esv_set, region_len, max_mismatch_rate) {
  fwd <- primers$fwd
  rev_rc <- as.character(Biostrings::reverseComplement(Biostrings::DNAString(primers$rev)))
  fmm <- floor(nchar(fwd) * max_mismatch_rate)
  rmm <- floor(nchar(rev_rc) * max_mismatch_rate)
  esv_head <- Biostrings::subseq(esv_set, 1L, pmin(Biostrings::width(esv_set), nchar(fwd)))
  carries <- mean(Biostrings::width(esv_head) == nchar(fwd) &
    Biostrings::vcountPattern(fwd, esv_head, max.mismatch = fmm, fixed = "subject") > 0L) > 0.5

  out <- data.frame(start = rep(NA_integer_, length(seqs)), end = NA_integer_, rc = FALSE)
  plus <- Biostrings::DNAStringSet(seqs)
  for (strand in c("plus", "minus")) {
    todo <- which(is.na(out$start))
    if (!length(todo)) break
    s <- if (strand == "plus") plus[todo] else Biostrings::reverseComplement(plus[todo])
    fh <- Biostrings::vmatchPattern(fwd, s, max.mismatch = fmm, fixed = "subject")
    rh <- Biostrings::vmatchPattern(rev_rc, s, max.mismatch = rmm, fixed = "subject")
    L <- Biostrings::width(s)
    for (k in seq_along(todo)) {
      f <- fh[[k]]
      r <- rh[[k]]
      st <- en <- NA_integer_
      if (length(f)) {
        f1 <- which.min(Biostrings::start(f))
        st <- if (carries) Biostrings::start(f)[f1] else Biostrings::end(f)[f1] + 1L
        down <- r[Biostrings::start(r) > Biostrings::end(f)[f1]]
        en <- if (length(down)) {
          r1 <- which.min(Biostrings::start(down))
          if (carries) Biostrings::end(down)[r1] else Biostrings::start(down)[r1] - 1L
        } else {
          st + region_len - 1L
        }
      } else if (length(r)) {
        r1 <- which.max(Biostrings::start(r))
        en <- if (carries) Biostrings::end(r)[r1] else Biostrings::start(r)[r1] - 1L
        st <- en - region_len + 1L
      }
      if (is.na(st)) next
      st <- max(1L, st)
      en <- min(L[k], en)
      if (en < st) next
      out$start[todo[k]] <- st
      out$end[todo[k]] <- en
      out$rc[todo[k]] <- strand == "minus"
    }
  }
  out
}
