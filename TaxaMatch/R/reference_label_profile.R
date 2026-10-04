# Rank profile of reference labels and marker resolution (internal).
#
# One neighbour search per marker, in which every marker-length deposit of the
# pool is a query (.mislabel_search_all()), feeds two separate outputs:
#   .reference_label_profile() -- per reference and rank, the evidence for its
#     label, and the removal decisions of the two-hypothesis test
#     (.test_reference_mislabels()) run at every rank of `rank_system`;
#   .marker_resolution() -- how well the MARKER resolves taxa (best close
#     match by species), which describes the marker, not the references.

#' Bare accession from a BLAST sequence id
#'
#' With `makeblastdb -parse_seqids`, `sseqid` can come back in its database-id form
#' (`"dbj|AB033668|"`), which matches no deposit accession. Keeps the
#' accession between the bars and drops the version.
#' @noRd
.mislabel_bare_acc <- function(x) {
  sub("[.][0-9]+$", "", sub("^[A-Za-z]+\\|([^|]+)\\|.*$", "\\1", x))
}

#' Neighbour search with every marker-length deposit as a query
#'
#' Queries are the references plus every deposit whose query sequence is
#' marker length (0.7 to 1.5 times the references' median query length), so
#' that the distance between groups can be measured from the neighbour hits
#' alone, with no targeted pair searches. Each query keeps its
#' `max_target_seqs` nearest subjects in the whole pool. The search runs as
#' `chunks` parallel blastn processes of `threads` threads each: blastn's own
#' threading scales poorly, and separate processes give identical hits.
#'
#' @param pool From `.mislabel_build_pool()`.
#' @param refs Reference accessions to include as queries.
#' @param queries Optional explicit query accessions (overrides the
#'   marker-length rule).
#' @return data.frame(q, s, pid): best identity per (query, subject), hits
#'   with per-HSP query coverage >= `qcov`.
#' @noRd
.mislabel_search_all <- function(pool, refs, blast_bin, queries = NULL, chunks = 7L, threads = 2L,
                                 qcov = 80, max_target_seqs = 500L, len_range = c(0.7, 1.5)) {
  refs <- intersect(refs, names(pool$amp))
  if (is.null(queries)) {
    L <- nchar(pool$amp); med <- stats::median(L[refs])
    ml <- names(pool$amp)[L >= floor(len_range[1] * med) & L <= ceiling(len_range[2] * med)]
    queries <- union(refs, ml)
  }
  queries <- intersect(queries, names(pool$amp))
  if (!length(queries)) stop("no query sequences.", call. = FALSE)
  # BLAST+ splits file arguments on whitespace even when quoted
  tmp <- tempfile("mislabel_search_")
  dir.create(tmp)
  if (grepl("\\s", tmp)) stop("tempdir() contains whitespace; BLAST+ cannot use it.", call. = FALSE)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  wfa <- function(x, f) writeLines(paste0(">", names(x), "\n", x), f)
  wfa(pool$seq, file.path(tmp, "s.fa"))
  system2(file.path(blast_bin, "makeblastdb"),
          c("-in", file.path(tmp, "s.fa"), "-dbtype nucl -parse_seqids -out", file.path(tmp, "db")),
          stdout = FALSE, stderr = FALSE)
  idx <- split(seq_along(queries), rep_len(seq_len(chunks), length(queries)))
  cmds <- vapply(seq_along(idx), function(i) {
    qf <- file.path(tmp, sprintf("q%d.fa", i))
    wfa(pool$amp[queries[idx[[i]]]], qf)
    sprintf("%s -task blastn -query %s -db %s -outfmt '6 qseqid sseqid pident qcovhsp' -max_target_seqs %d -num_threads %d -out %s 2>/dev/null",
            file.path(blast_bin, "blastn"), qf, file.path(tmp, "db"), as.integer(max_target_seqs),
            as.integer(threads), file.path(tmp, sprintf("h%d.tsv", i)))
  }, character(1))
  system(paste(paste(cmds, collapse = " & "), "& wait"))
  h <- do.call(rbind, lapply(seq_along(idx), function(i) {
    f <- file.path(tmp, sprintf("h%d.tsv", i))
    if (!file.exists(f) || !file.size(f)) {
      stop(sprintf("blastn chunk %d produced no output -- BLAST failed (check blast_bin).", i), call. = FALSE)
    }
    utils::read.delim(f, header = FALSE, col.names = c("q", "s", "pid", "cov"),
                      colClasses = c("character", "character", "numeric", "numeric"))
  }))
  h <- h[h$cov >= qcov, ]
  h$q <- .mislabel_bare_acc(h$q)
  h$s <- .mislabel_bare_acc(h$s)
  stats::aggregate(pid ~ q + s, data = h, FUN = max)
}

#' Group columns fit for comparison
#'
#' A placeholder rank value (incertae sedis, unclassified, unknown, `unk_*`)
#' is missing, never a group: otherwise it would form a pseudo-group spanning
#' unrelated taxa. A species group needs a proper binomial: `"Gelidium sp."`,
#' `"Bangia sp. 2BAN"` and `"X cf. y"` are unidentified to species.
#' @noRd
.mislabel_clean_groups <- function(deposits, rank_system) {
  ph <- function(v) is.na(v) | grepl("^unk_|incertae sedis|unclassified|^unknown", v, ignore.case = TRUE)
  for (r in intersect(rank_system, names(deposits))) deposits[[r]][ph(deposits[[r]])] <- NA_character_
  if ("species" %in% names(deposits)) {
    ok <- grepl("^[A-Z][a-z-]+ [a-z][a-z-]+$", deposits$species) &
      !grepl(" (sp|spp|cf|aff)$", deposits$species)
    deposits$species[!ok] <- NA_character_
  }
  deposits
}

#' Nearest other group of each reference at each rank, from the hits
#'
#' The group of the reference's closest hit (from another submission batch)
#' that is not its own group at that rank; `NA` when none appears among its
#' hits.
#' @return Named list (one element per rank) of data.frame(accession, B).
#' @noRd
.mislabel_nearest_other <- function(hits, deposits, refs, rank_system) {
  bat <- stats::setNames(deposits$batch, deposits$acc)
  hh <- hits[hits$q %in% refs & bat[hits$q] != bat[hits$s], ]
  hh <- hh[order(hh$q, -hh$pid), ]
  by_q <- split(hh$s, hh$q)
  lapply(stats::setNames(rank_system, rank_system), function(r) {
    g <- stats::setNames(deposits[[r]], deposits$acc)
    B <- vapply(refs, function(a) {
      s <- by_q[[a]]
      ga <- g[a]
      if (is.null(s) || is.na(ga)) return(NA_character_)
      gs <- g[s]
      gs <- gs[!is.na(gs) & gs != ga]
      if (length(gs)) unname(gs[1]) else NA_character_
    }, character(1))
    data.frame(accession = refs, B = unname(B), stringsAsFactors = FALSE)
  })
}

#' Rank profile of reference labels, with the removal decisions
#'
#' For every reference and every rank of `rank_system`, two separate things:
#' \describe{
#'   \item{`screen_status`}{the two-hypothesis test's own diagnostics: whether
#'     the reference could be accused of a mislabel at that rank (`tested`),
#'     or not because its group and the nearest other group are not separated
#'     beyond the marker's normal within-group spread (`below_separation`), or
#'     because there are too few independent batches (`insufficient_evidence`).}
#'   \item{`outcome`}{the evidence for its label at that rank:
#'     `contradicted` (selected by the test at that rank, Bayesian FDR),
#'     `supported` (its own group is closer than the nearest other group by
#'     at least one mismatch over the marker, with at least 2 independent
#'     batches on each side; or no other group appears among its hits although
#'     its hit list was full, so every other group is farther than its
#'     `max_target_seqs`-th neighbour), `cannot_discriminate` (measured,
#'     neither), or `too_few_records` (fewer than 2 independent batches of its
#'     own or of the other group).}
#' }
#' The removal decisions are those of `.test_reference_mislabels()` run with
#' this `rank_system` (two-pass, split-group guard, last-reference rule).
#'
#' @param hits From `.mislabel_search_all()`.
#' @param deposits Pool deposits with `acc`, `batch`, `class` and one column
#'   per rank of `rank_system`.
#' @param refs Reference accessions to profile.
#' @param ref_species Named character, listed species per reference (for the
#'   last-reference rule).
#' @param quantum One mismatch over the marker, in percent identity
#'   (default: 100 / the references' median query length, from `amp`).
#' @param amp Named query sequences (`pool$amp`), used for `quantum`.
#' @param full_list Hit count at which a reference's list counts as full
#'   (`max_target_seqs` of the search, less a margin for collapsed HSPs).
#' @param cores Ranks are computed in parallel (forked) when > 1; the results
#'   are identical to the serial computation.
#' @return list(profile, summary, result): per (reference, rank) rows; one
#'   row per reference (the four columns plus the decision); and the decision
#'   table from `.test_reference_mislabels()`.
#' @noRd
.reference_label_profile <- function(hits, deposits, refs, ref_species,
                                     rank_system = c("species", "genus", "family", "order", "class", "phylum", "kingdom"),
                                     quantum = NULL, amp = NULL, full_list = 450L, cores = 1L, ...) {
  deposits <- .mislabel_clean_groups(deposits, rank_system)
  refs <- intersect(refs, unique(hits$q))
  nb <- .mislabel_nearest_other(hits, deposits, refs, rank_system)
  cls <- stats::setNames(deposits$class, deposits$acc)
  one_rank <- function(r, ex) {
    s <- .mislabel_rank_statistics(hits, deposits, nb[[r]], r, rank_system, exclude = ex)
    s$class <- unname(cls[s$accession])
    s
  }
  stats_fun <- function(ex) {
    out <- if (cores > 1L && .Platform$OS.type == "unix") {
      parallel::mclapply(rank_system, one_rank, ex = ex, mc.cores = min(cores, length(rank_system)),
                         mc.preschedule = FALSE)
    } else {
      lapply(rank_system, one_rank, ex = ex)
    }
    bad <- vapply(out, inherits, logical(1), "try-error")
    if (any(bad)) stop("rank statistics failed at: ", paste(rank_system[bad], collapse = ", "), call. = FALSE)
    do.call(rbind, out)
  }
  st <- stats_fun(character(0))
  prof <- do.call(rbind, lapply(rank_system, function(r) {
    z <- .mislabel_lr_test(st[st$rank == r, ], rank_system = r, ...)
    z$pi_rank <- attr(z, "pi")
    z
  }))
  prof <- prof[prof$accession %in% refs, ]
  prof$ri <- match(prof$rank, rank_system)
  if (is.null(quantum)) {
    if (is.null(amp)) stop("supply `quantum` or `amp`.", call. = FALSE)
    quantum <- 100 / stats::median(nchar(amp[intersect(refs, names(amp))]))
  }
  prof$screen_status <- prof$status
  meas <- prof$x_batches >= 2 & prof$y_batches >= 2 & !is.na(prof$x) & !is.na(prof$y)
  prof$outcome <- ifelse(prof$selected, "contradicted",
                  ifelse(meas & prof$x - prof$y >= quantum - 1e-9, "supported",
                  ifelse(meas, "cannot_discriminate", "too_few_records")))
  n_subj <- table(hits$q[hits$q %in% refs])
  full <- names(n_subj)[n_subj >= full_list]
  prof$censored_support <- is.na(prof$B) & prof$accession %in% full
  prof$outcome[prof$censored_support & prof$outcome != "contradicted"] <- "supported"

  res <- .test_reference_mislabels(stats_fun, ref_species, deposits = deposits, hits = hits,
                                   rank_system = rank_system, ...)
  S <- do.call(rbind, lapply(split(prof, prof$accession), function(p) {
    sup <- p$ri[p$outcome == "supported"]
    con <- p$ri[p$outcome == "contradicted"]
    chk <- p$ri[p$outcome != "too_few_records"]
    scr <- p$ri[p$screen_status == "tested" | p$censored_support]
    data.frame(accession = p$accession[1],
               label_confirmed_to = if (length(sup)) rank_system[min(sup)] else NA_character_,
               highest_contradicted = if (length(con)) rank_system[max(con)] else NA_character_,
               lowest_checkable = if (length(chk)) rank_system[min(chk)] else NA_character_,
               finest_screened = if (length(scr)) rank_system[min(scr)] else NA_character_,
               stringsAsFactors = FALSE)
  }))
  S <- merge(S, res[, c("accession", "rank", "A", "B", "posterior", "action", "reason")],
             by = "accession", all.x = TRUE)
  names(S)[names(S) == "rank"] <- "decision_rank"
  out <- list(profile = prof, summary = S, result = res)
  attr(out, "quantum") <- quantum
  attr(out, "pi") <- attr(res, "pi")
  attr(out, "rule_key") <- paste0(attr(res, "rule_key"), "|ranks=", paste(rank_system, collapse = ","),
                                  "|support=quantum|censored>=", full_list)
  out
}

#' How well a marker resolves taxa: best close match by species
#'
#' One query per (species, submission batch); its nearest sequences from other
#' batches (all tied at the top identity) are compared with the query's own
#' lineage at each rank of `rank_system`: `resolved` (every nearest sequence
#' in the query's group), `ambiguous` (some are), `wrong` (none is). Resolved
#' at a rank implies resolved at every coarser rank. Two scenarios:
#' `present` (the species has other sequences in the pool; needs at least 2
#' batches of it), and `absent` (all its other sequences removed first, as an
#' unreferenced species would be; a rank is not evaluable when the query's
#' group has no other species). Species are weighted equally. This describes
#' the marker within the database -- a best case for sequenced taxa -- and
#' should be reported separately from the label screen.
#'
#' @param exclude Accessions removed from queries and subjects (for example
#'   the label screen's removals).
#' @return list(present, absent): per rank, `n_species` and the shares
#'   resolved / ambiguous / wrong (species-weighted).
#' @noRd
.marker_resolution <- function(hits, deposits, rank_system, exclude = character(0)) {
  deposits <- .mislabel_clean_groups(deposits, rank_system)
  G <- lapply(stats::setNames(rank_system, rank_system), function(r) stats::setNames(deposits[[r]], deposits$acc))
  bat <- stats::setNames(deposits$batch, deposits$acc)
  h <- hits[hits$q %in% deposits$acc & hits$s %in% deposits$acc, ]
  h <- h[bat[h$q] != bat[h$s] & !(h$q %in% exclude) & !(h$s %in% exclude), ]
  cov_acc <- unique(c(h$q, h$s))
  qd <- data.frame(q = unique(h$q), stringsAsFactors = FALSE)
  qd$sp <- unname(G$species[qd$q])
  qd$b <- unname(bat[qd$q])
  qd <- qd[!is.na(qd$sp), ]
  qd <- qd[order(qd$q), ]
  qd <- qd[!duplicated(paste(qd$sp, qd$b)), ]
  by_q <- split(h[, c("s", "pid")], h$q)
  sb <- unique(data.frame(sp = unname(G$species[cov_acc]), b = unname(bat[cov_acc]), stringsAsFactors = FALSE))
  sp_batches <- table(sb$sp[!is.na(sb$sp)])
  n_sp_in <- lapply(stats::setNames(rank_system, rank_system), function(r) {
    d <- unique(data.frame(g = unname(G[[r]][cov_acc]), sp = unname(G$species[cov_acc]), stringsAsFactors = FALSE))
    d <- d[!is.na(d$g) & !is.na(d$sp), ]
    table(d$g)
  })
  classify <- function(q, absent) {
    out <- stats::setNames(rep(NA_character_, length(rank_system)), rank_system)
    z <- by_q[[q]]
    if (absent && !is.null(z)) z <- z[is.na(G$species[z$s]) | G$species[z$s] != G$species[q], , drop = FALSE]
    if (is.null(z) || !nrow(z)) return(out)
    top <- z$s[z$pid >= max(z$pid) - 1e-9]
    for (r in rank_system) {
      gq <- G[[r]][q]
      if (is.na(gq) || (absent && r == "species")) next
      if (absent) {
        k <- n_sp_in[[r]][gq]
        if (is.na(k) || k < 2) { out[r] <- "not_evaluable"; next }
      }
      gt <- G[[r]][top]
      gt <- gt[!is.na(gt)]
      if (!length(gt)) next
      out[r] <- if (all(gt == gq)) "resolved" else if (any(gt == gq)) "ambiguous" else "wrong"
    }
    out
  }
  summarise <- function(absent) {
    q <- if (absent) qd else qd[as.integer(sp_batches[qd$sp]) >= 2, , drop = FALSE]
    if (!nrow(q)) return(NULL)
    m <- matrix(vapply(q$q, classify, character(length(rank_system)), absent = absent),
                nrow = length(rank_system), dimnames = list(rank_system, NULL))
    do.call(rbind, lapply(rank_system, function(r) {
      v <- m[r, ]
      ok <- !is.na(v) & v != "not_evaluable"
      if (!any(ok)) return(NULL)
      d <- data.frame(sp = q$sp[ok], res = v[ok] == "resolved", amb = v[ok] == "ambiguous", wr = v[ok] == "wrong")
      a <- stats::aggregate(cbind(res, amb, wr) ~ sp, data = d, FUN = mean)
      data.frame(rank = r, n_species = nrow(a), resolved = mean(a$res), ambiguous = mean(a$amb),
                 wrong = mean(a$wr), species_not_evaluable = length(unique(q$sp[!is.na(v) & v == "not_evaluable"])))
    }))
  }
  list(present = summarise(FALSE), absent = summarise(TRUE))
}
