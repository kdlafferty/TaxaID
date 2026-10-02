# Local-BLAST measurement for the two-hypothesis mislabel test (internal).
# See reference_mislabel_test.R for the statistics these feed. All three
# helpers run BLAST+ against a local core_nt; nothing here touches NCBI's
# web service.

utils::globalVariables(character(0))

.mislabel_strip_version <- function(x) sub("[.][0-9]+$", "", x)

#' Run blastdbcmd from the database directory
#'
#' blastdbcmd needs the database directory as its working directory to find
#' the taxonomy files, and system2() has no cwd argument.
#' @noRd
.mislabel_blastdbcmd <- function(blast_bin, db_dir, db, args, out) {
  cmd <- sprintf("cd %s && %s -db %s %s > %s 2>/dev/null",
                 shQuote(db_dir), shQuote(file.path(blast_bin, "blastdbcmd")), db,
                 paste(args, collapse = " "), shQuote(out))
  status <- system(cmd)
  if (!file.exists(out)) stop("blastdbcmd produced no output: ", cmd, call. = FALSE)
  invisible(status)
}

#' Build the deposit pool for the mislabel test
#'
#' Every core_nt deposit of every taxid the references carry, filtered to
#' records whose title says they carry the marker, without RefSeq copies
#' (they duplicate primary records), capped at `max_per_batch` deposits per
#' taxon and submission batch (batches are the independence unit, so more
#' copies add nothing). The references themselves are always included.
#'
#' @param lineage data.frame, one row per reference accession: `acc`,
#'   `taxid`, and the `rank_system` columns plus `class`.
#' @param title_pattern Regular expression a deposit's title must match.
#' @param barcode_term Passed to `.trim_queries_to_amplicon()`.
#' @param max_query_len Deposits whose amplicon is still longer than this
#'   after trimming are used as subjects only, never as queries.
#' @return list(deposits = data.frame(acc, taxid, <ranks>, class, batch,
#'   len, is_reference, query_ok), seq = named full sequences, amp = named
#'   query amplicons).
#' @noRd
.mislabel_build_pool <- function(lineage, blast_bin, db_dir, db = "core_nt",
                                 title_pattern, barcode_term,
                                 rank_system = c("species", "genus", "family"),
                                 max_per_batch = 3L, max_len = 50000L,
                                 max_query_len = 1000L, batch_gap = 100,
                                 work_dir = tempfile("mislabel_pool_"),
                                 verbose = TRUE) {
  dir.create(work_dir, showWarnings = FALSE, recursive = TRUE)
  lineage$acc <- .mislabel_strip_version(lineage$acc)
  tx <- unique(stats::na.omit(lineage$taxid))
  writeLines(as.character(tx), file.path(work_dir, "taxids.txt"))
  .mislabel_blastdbcmd(blast_bin, db_dir, db,
    c("-taxidlist", shQuote(file.path(work_dir, "taxids.txt")), "-outfmt", shQuote("%a\t%T\t%l\t%t")),
    file.path(work_dir, "dep.tsv"))
  dep <- utils::read.delim(file.path(work_dir, "dep.tsv"), header = FALSE, quote = "",
    col.names = c("acc", "taxid", "len", "title"),
    colClasses = c("character", "integer", "integer", "character"))
  n0 <- nrow(dep)
  dep$acc <- .mislabel_strip_version(dep$acc)
  dep <- dep[!grepl("^(XM_|XR_|NM_|NC_|NR_|NW_|NZ_)", dep$acc) & dep$len <= max_len &
             grepl(title_pattern, dep$title, ignore.case = TRUE), ]
  dep <- dep[!duplicated(dep$acc), ]
  dep$batch <- .mislabel_batch_of(dep$acc, batch_gap)[dep$acc]
  # keep up to max_per_batch per (taxid, batch); references always kept
  dep <- dep[order(!(dep$acc %in% lineage$acc)), ]
  rk <- stats::ave(seq_len(nrow(dep)), dep$taxid, dep$batch, FUN = seq_along)
  dep <- dep[rk <= max_per_batch | dep$acc %in% lineage$acc, ]
  refs_missing <- setdiff(lineage$acc, dep$acc)
  if (length(refs_missing)) {
    dep <- rbind(dep, data.frame(acc = refs_missing, taxid = lineage$taxid[match(refs_missing, lineage$acc)],
                                 len = NA_integer_, title = NA_character_, batch = NA_character_))
  }
  dep$batch <- .mislabel_batch_of(dep$acc, batch_gap)[dep$acc]
  if (verbose) message(sprintf("mislabel pool: %s core_nt records for %d taxids; %s deposits kept (marker title, no RefSeq, <= %d per batch).",
                               format(n0, big.mark = ","), length(tx), format(nrow(dep), big.mark = ","), max_per_batch))
  writeLines(dep$acc, file.path(work_dir, "dep_acc.txt"))
  .mislabel_blastdbcmd(blast_bin, db_dir, db,
    c("-entry_batch", shQuote(file.path(work_dir, "dep_acc.txt")), "-target_only -outfmt", shQuote("%a\t%s")),
    file.path(work_dir, "dep_seq.tsv"))
  ds <- utils::read.delim(file.path(work_dir, "dep_seq.tsv"), header = FALSE, quote = "",
                          col.names = c("acc", "seq"), colClasses = "character")
  ds$acc <- .mislabel_strip_version(ds$acc)
  ds <- ds[!duplicated(ds$acc), ]
  dep <- dep[dep$acc %in% ds$acc, ]
  seq <- stats::setNames(ds$seq, ds$acc)[dep$acc]
  amp <- .trim_queries_to_amplicon(seq, barcode_term, strip_primers = TRUE, verbose = FALSE)
  amp <- stats::setNames(as.character(amp), dep$acc)
  # lineage by taxid (every deposit taxid is a reference taxid)
  lt <- lineage[!duplicated(lineage$taxid), c("taxid", rank_system, "class")]
  dep <- cbind(dep[, c("acc", "taxid", "batch", "len")], lt[match(dep$taxid, lt$taxid), c(rank_system, "class")])
  dep$is_reference <- dep$acc %in% lineage$acc
  dep$query_ok <- nchar(amp) <= max_query_len
  rownames(dep) <- NULL
  list(deposits = dep, seq = seq, amp = amp[dep$query_ok])
}

#' blastn queries against subjects, best identity per pair
#' @noRd
.mislabel_blastn <- function(queries, subjects, blast_bin, work_dir, qcov = 80,
                             max_target_seqs = 100000L, threads = 1L, use_db = FALSE) {
  wfa <- function(x, f) writeLines(paste0(">", names(x), "\n", x), f)
  qf <- file.path(work_dir, "q.fa")
  sf <- file.path(work_dir, "s.fa")
  hf <- file.path(work_dir, "h.tsv")
  unlink(hf)
  wfa(queries, qf)
  wfa(subjects, sf)
  common <- c("-task blastn", "-query", shQuote(qf), "-outfmt",
              shQuote("6 qseqid sseqid pident qcovs"), "-max_target_seqs", max_target_seqs,
              "-out", shQuote(hf))
  if (use_db) {
    # BLAST's -db argument splits on whitespace even when quoted, so the
    # database never goes under work_dir (which may be e.g. "My Drive").
    db_dir <- tempfile("mislabel_db_")
    dir.create(db_dir)
    if (grepl("\\s", db_dir)) stop("tempdir() contains whitespace; BLAST -db cannot use it.", call. = FALSE)
    on.exit(unlink(db_dir, recursive = TRUE), add = TRUE)
    dbp <- file.path(db_dir, "pooldb")
    system2(file.path(blast_bin, "makeblastdb"),
            c("-in", shQuote(sf), "-dbtype nucl -parse_seqids -out", shQuote(dbp)),
            stdout = FALSE, stderr = FALSE)
    system2(file.path(blast_bin, "blastn"), c(common, "-db", shQuote(dbp), "-num_threads", threads),
            stderr = FALSE)
  } else {
    system2(file.path(blast_bin, "blastn"), c(common, "-subject", shQuote(sf)), stderr = FALSE)
  }
  if (!file.exists(hf) || !file.size(hf)) {
    return(data.frame(q = character(0), s = character(0), pid = numeric(0)))
  }
  h <- utils::read.delim(hf, header = FALSE, col.names = c("q", "s", "pid", "qcov"),
                         colClasses = c("character", "character", "numeric", "numeric"))
  h$s <- sub("^[^|]*[|]([^|]+)[|].*$", "\\1", h$s)
  h$q <- .mislabel_strip_version(h$q)
  h$s <- .mislabel_strip_version(h$s)
  h <- h[h$qcov >= qcov & h$q != h$s, ]
  if (!nrow(h)) return(data.frame(q = character(0), s = character(0), pid = numeric(0)))
  stats::aggregate(pid ~ q + s, data = h, FUN = max)
}

#' Nearest other group per reference and rank
#'
#' One broad search of every reference amplicon against the whole pool. At
#' each rank, B is the group of the best-scoring independent hit outside the
#' reference's own group. Only the identity of B is taken from this search;
#' x, y and d come from the targeted per-pair searches, so the top-hit
#' truncation here cannot censor them.
#' @return named list (one per rank) of data.frame(accession, B).
#' @noRd
.mislabel_neighbours <- function(pool, refs, blast_bin, rank_system = c("species", "genus", "family"),
                                 max_target_seqs = 500L, threads = 4L, qcov = 80,
                                 work_dir = tempfile("mislabel_nb_")) {
  dir.create(work_dir, showWarnings = FALSE, recursive = TRUE)
  dep <- pool$deposits
  refs <- intersect(refs, names(pool$amp))
  h <- .mislabel_blastn(pool$amp[refs], pool$seq, blast_bin, work_dir, qcov = qcov,
                        max_target_seqs = max_target_seqs, threads = threads, use_db = TRUE)
  # Every reference is in the pool and so hits at least itself: an empty
  # result is a failed search, never "no neighbours".
  if (!nrow(h)) {
    stop("the neighbour search returned no hits at all -- BLAST failed (check blast_bin and the database path).",
         call. = FALSE)
  }
  bat <- stats::setNames(dep$batch, dep$acc)
  h <- h[bat[h$q] != bat[h$s], ]
  h <- h[order(h$q, -h$pid), ]
  by_q <- split(h$s, h$q)
  lapply(stats::setNames(rank_system, rank_system), function(r) {
    grp <- stats::setNames(dep[[r]], dep$acc)
    B <- vapply(refs, function(a) {
      s <- by_q[[a]]
      if (is.null(s)) return(NA_character_)
      g <- grp[s]
      g <- g[!is.na(g) & g != grp[[a]]]
      if (length(g)) unname(g[1]) else NA_character_
    }, character(1))
    data.frame(accession = refs, B = unname(B), stringsAsFactors = FALSE)
  })
}

#' Targeted per-pair searches that measure x, y and d
#'
#' For each distinct (rank, A, B): queries are the references in that pair
#' plus every query-capable member of A; subjects are all members of A and B
#' (whole sequences, so a short amplicon-only deposit is not out-scored).
#' Every pair a statistic needs is therefore searched exhaustively.
#' @return data.frame(q, s, pid), best identity per pair over all searches.
#' @noRd
.mislabel_pair_hits <- function(pool, neighbours, blast_bin, rank_system = c("species", "genus", "family"),
                                qcov = 80, work_dir = tempfile("mislabel_pairs_"), verbose = TRUE) {
  dir.create(work_dir, showWarnings = FALSE, recursive = TRUE)
  dep <- pool$deposits
  jobs <- do.call(rbind, lapply(rank_system, function(r) {
    nb <- neighbours[[r]]
    nb$A <- dep[[r]][match(nb$accession, dep$acc)]
    nb <- nb[!is.na(nb$A) & !is.na(nb$B), ]
    if (!nrow(nb)) return(NULL)
    data.frame(rank = r, A = nb$A, B = nb$B, accession = nb$accession, stringsAsFactors = FALSE)
  }))
  if (is.null(jobs) || !nrow(jobs)) {
    stop("no reference has a nearest other group at any rank -- nothing to measure.", call. = FALSE)
  }
  keys <- unique(jobs[, c("rank", "A", "B")])
  if (verbose) message(sprintf("mislabel pair searches: %d (rank, A, B) pairs", nrow(keys)))
  res <- vector("list", nrow(keys))
  t0 <- Sys.time()
  for (i in seq_len(nrow(keys))) {
    r <- keys$rank[i]
    inA <- dep$acc[dep[[r]] %in% keys$A[i]]
    inB <- dep$acc[dep[[r]] %in% keys$B[i]]
    refs_i <- jobs$accession[jobs$rank == r & jobs$A == keys$A[i] & jobs$B == keys$B[i]]
    q <- intersect(unique(c(refs_i, inA)), names(pool$amp))
    s <- intersect(unique(c(inA, inB)), names(pool$seq))
    if (length(q) && length(s)) {
      res[[i]] <- .mislabel_blastn(pool$amp[q], pool$seq[s], blast_bin, work_dir, qcov = qcov)
    }
    if (verbose && i %% 200 == 0) {
      message(sprintf("  pair %d/%d (%.1f min)", i, nrow(keys),
                      as.numeric(difftime(Sys.time(), t0, units = "mins"))))
    }
  }
  h <- do.call(rbind, res)
  if (is.null(h) || !nrow(h)) return(data.frame(q = character(0), s = character(0), pid = numeric(0)))
  stats::aggregate(pid ~ q + s, data = h, FUN = max)
}
