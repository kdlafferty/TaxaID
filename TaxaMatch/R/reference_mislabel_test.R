# Two-hypothesis mislabel test for reference accessions (internal).
#
# A reference a is listed as group A at rank r (its species, genus or
# family). Its nearest other group at that rank is B. Three statistics,
# each a median over INDEPENDENT submission batches (a's own batch never
# counts, so an error deposited several times cannot vouch for itself):
#   x = a's identity to other members of A
#   y = a's identity to members of B
#   d = the A-B distance, measured from OTHER members of A against B
# Under H_A (label correct) x looks like a within-group identity and y sits
# about d away; under H_B (a is really B) the roles swap:
#   LR(B:A) = f(y) g(x - d) / ( f(x) g(y - d) )
# f is the rank's within-group mismatch density, g the density of the
# residual y - d. An Empirical-Bayes prior pi is estimated by EM over the
# TESTABLE references only (an untested reference is of unknown status, not
# known-correct) and references are selected at a Bayesian FDR.
#
# A reference is testable at rank r only when A and B are farther apart than
# the q-th quantile of within-group mismatch at that rank, learned from the
# data before any LR is computed. Below it the marker cannot separate a
# mislabel from ordinary variation or introgression, and the reference is
# kept. Each reference is tested at the finest rank where it is testable, so
# a species with no other independent deposit can still be tested at genus
# or family rank -- where the most damaging mislabels live.

utils::globalVariables(character(0))

.MISLABEL_RULE_VERSION <- "mislabel_lr_v1"

# --- comb handling ------------------------------------------------------------
# Percent identity on a short amplicon is a comb (one mismatch = one tooth),
# and a density estimate on comb data is acutely bandwidth-sensitive. The two
# helpers below are COPIES of TaxaLikely/R/bimodality.R's
# .estimate_score_quantum() and .smooth_comb() (math unchanged). TaxaMatch
# cannot call TaxaLikely internals, and an export for 1.0 was judged not
# worth it. If either original changes, change these too -- a test in
# tests/testthat/test-reference-mislabel-test.R pins this copy's behaviour so
# a divergence is visible.

#' Estimate the spacing of a comb-shaped vector (copy of TaxaLikely's)
#' @noRd
.estimate_score_quantum <- function(x, min_n = 20L, min_unique = 6L,
                                    mass_fraction = 0.8,
                                    max_unique_frac = 0.3) {
  x <- x[is.finite(x)]
  n <- length(x)
  if (n < min_n) {
    return(NA_real_)
  }
  tab <- table(x)
  uvals <- as.numeric(names(tab))
  counts <- as.numeric(tab)
  ord <- order(uvals)
  uvals <- uvals[ord]
  counts <- counts[ord]
  n_unique <- length(uvals)
  if (n_unique < min_unique) {
    return(NA_real_)
  }
  if (n_unique / n > max_unique_frac) {
    return(NA_real_)
  }
  ord_count <- order(counts, decreasing = TRUE)
  cum_frac <- cumsum(counts[ord_count]) / n
  n_dominant <- which(cum_frac >= mass_fraction)[1L]
  if (is.na(n_dominant)) {
    n_dominant <- n_unique
  }
  n_dominant <- max(n_dominant, 2L)
  dominant_vals <- sort(uvals[ord_count[seq_len(n_dominant)]])
  diffs <- diff(dominant_vals)
  diffs <- diffs[diffs > 0]
  if (length(diffs) < 2L) {
    return(NA_real_)
  }
  stats::median(diffs)
}

#' Deterministically smooth a comb at a given quantum (copy of TaxaLikely's)
#' @noRd
.smooth_comb <- function(x, quantum) {
  if (length(quantum) != 1L || is.na(quantum) || !is.finite(quantum) || quantum <= 0) {
    return(x)
  }
  finite <- is.finite(x)
  if (sum(finite) < 2L) {
    return(x)
  }
  idx <- which(finite)
  x_fin <- x[idx]
  ord <- order(x_fin)
  x_sorted <- x_fin[ord]
  out_sorted <- x_sorted
  n <- length(x_sorted)
  i <- 1L
  while (i <= n) {
    j <- i
    while (j < n && x_sorted[j + 1L] == x_sorted[i]) {
      j <- j + 1L
    }
    grp_n <- j - i + 1L
    if (grp_n > 1L) {
      offsets <- seq(-quantum / 2, quantum / 2, length.out = grp_n + 2L)
      offsets <- offsets[2:(grp_n + 1L)]
      out_sorted[i:j] <- x_sorted[i] + offsets
    }
    i <- j + 1L
  }
  out <- x
  out[idx[ord]] <- out_sorted
  out
}

# --- submission batches -------------------------------------------------------

#' Group accessions into submission batches
#'
#' Same accession prefix and numbers within `gap` of each other form one
#' batch. RefSeq copies should be removed before this is called: they
#' duplicate primary records under a different prefix.
#' @noRd
.mislabel_batch_of <- function(acc, gap = 100) {
  acc <- unique(acc)
  pre <- sub("[0-9].*$", "", acc)
  num <- suppressWarnings(as.numeric(sub("^[A-Za-z_]+", "", acc)))
  o <- order(pre, num)
  id <- character(length(acc))
  b <- 0L
  lp <- ""
  ln <- -Inf
  for (i in o) {
    if (pre[i] != lp || is.na(num[i]) || num[i] - ln > gap) b <- b + 1L
    id[i] <- paste0(pre[i], "#", b)
    lp <- pre[i]
    ln <- if (is.na(num[i])) -Inf else num[i]
  }
  stats::setNames(id, acc)
}

# --- statistics ---------------------------------------------------------------

#' Median-over-independent-batches identity statistics at one rank
#'
#' @param hits data.frame with `q`, `s`, `pid`: best percent identity of
#'   query amplicon `q` against deposit `s` (one row per pair).
#' @param deposits data.frame with `acc`, `batch` and one column per rank in
#'   `rank_system`. Every query and subject in `hits` must appear here.
#' @param assign data.frame with `accession`, `B` (the nearest other group
#'   at `rank`, NA when none).
#' @param rank One of `rank_system`.
#' @param rank_system Character, finest first, e.g.
#'   `c("species", "genus", "family")`.
#' @param exclude Accessions dropped from both sides (the second pass of the
#'   robustness rule). The reference under test is never dropped from its
#'   own row.
#' @return data.frame: `accession`, `rank`, `A`, `B`, `x`, `x_batches`, `y`,
#'   `y_batches`, `d`, `d_batches`.
#' @noRd
.mislabel_rank_statistics <- function(hits, deposits, assign, rank,
                                      rank_system = c("species", "genus", "family"),
                                      exclude = character(0)) {
  k <- match(rank, rank_system)
  if (is.na(k)) stop("`rank` must be one of `rank_system`.", call. = FALSE)
  finer <- if (k > 1L) rank_system[k - 1L] else NA_character_
  dep <- deposits[!duplicated(deposits$acc), ]
  grp <- stats::setNames(dep[[rank]], dep$acc)
  fin <- if (is.na(finer)) NULL else stats::setNames(dep[[finer]], dep$acc)
  bat <- stats::setNames(dep$batch, dep$acc)
  hits <- hits[hits$q %in% dep$acc & hits$s %in% dep$acc & hits$q != hits$s, ]
  by_q <- split(hits[, c("s", "pid")], hits$q)
  q_all <- names(by_q)
  memo <- new.env(hash = TRUE)

  # median over batches of the best identity per batch
  med_batch <- function(h) {
    if (!nrow(h)) return(c(NA_real_, 0))
    pb <- tapply(h$pid, bat[h$s], max)
    c(stats::median(pb), length(pb))
  }
  one <- function(a, B) {
    out <- c(x = NA, xb = 0, y = NA, yb = 0, d = NA, db = 0)
    A <- grp[[a]]
    if (is.null(A) || is.na(A)) return(out)
    ba <- bat[[a]]
    # members of A that count: same group, independent of a, not excluded,
    # and (above species rank) not in a's own finer group -- otherwise a
    # genus-rank statistic would just repeat the species-rank one.
    inA <- function(acc) {
      ok <- grp[acc] %in% A & bat[acc] != ba & !(acc %in% exclude)
      if (!is.null(fin)) ok <- ok & !(fin[acc] %in% fin[[a]])
      ok
    }
    ha <- by_q[[a]]
    if (!is.null(ha)) {
      r <- med_batch(ha[inA(ha$s), , drop = FALSE])
      out[c("x", "xb")] <- r
    }
    if (is.na(B)) return(out)
    inB <- function(acc) grp[acc] %in% B & !(acc %in% exclude)
    if (!is.null(ha)) {
      r <- med_batch(ha[inB(ha$s) & bat[ha$s] != ba, , drop = FALSE])
      out[c("y", "yb")] <- r
    }
    # d: every independent member of A, as a query, against B; best per
    # query, median within each A batch, median over A batches. The per-query
    # best is memoised per (A, B, a's finer group) since many references share
    # it; only a's own batch differs between them.
    key <- paste(A, B, if (is.null(fin)) "" else fin[[a]], sep = "\r")
    best <- memo[[key]]
    if (is.null(best)) {
      qa <- q_all[grp[q_all] %in% A & !(q_all %in% exclude)]
      if (!is.null(fin)) qa <- qa[!(fin[qa] %in% fin[[a]])]
      best <- vapply(qa, function(q) {
        h <- by_q[[q]]
        h <- h[inB(h$s) & bat[h$s] != bat[[q]], , drop = FALSE]
        if (nrow(h)) max(h$pid) else NA_real_
      }, numeric(1))
      best <- best[!is.na(best)]
      memo[[key]] <- best
    }
    best <- best[bat[names(best)] != ba]
    if (length(best)) {
      pb <- tapply(best, bat[names(best)], stats::median)
      out[c("d", "db")] <- c(stats::median(pb), length(pb))
    }
    out
  }
  res <- t(vapply(seq_len(nrow(assign)), function(i) one(assign$accession[i], assign$B[i]),
                  numeric(6)))
  data.frame(
    accession = assign$accession, rank = rank,
    A = unname(grp[assign$accession]), B = assign$B,
    x = res[, "x"], x_batches = as.integer(res[, "xb"]),
    y = res[, "y"], y_batches = as.integer(res[, "yb"]),
    d = res[, "d"], d_batches = as.integer(res[, "db"]),
    stringsAsFactors = FALSE, row.names = NULL
  )
}

# --- the test -----------------------------------------------------------------

.mislabel_reflected_kde <- function(m, bw_mult = 1) {
  m <- m[is.finite(m)]
  bw <- max(stats::bw.nrd0(m), 0.1) * bw_mult
  function(q) vapply(q, function(z) mean(stats::dnorm(z, m, bw) + stats::dnorm(-z, m, bw)), 0)
}

#' Two-hypothesis LR test across ranks, one pass
#'
#' @param stats Row-bind of `.mislabel_rank_statistics()` over ranks, plus a
#'   `class` column (used to shrink the within-group density toward the
#'   rank-wide one).
#' @param rank_system Finest first; each accession is tested at the first
#'   rank where it is testable.
#' @param sep_q Quantile of within-group mismatch used as the separation
#'   guard.
#' @param k Shrinkage strength of class-level within-group densities.
#' @param eps Weight of a uniform mixed into f and g, so no observed value
#'   has ~zero density.
#' @param fdr Bayesian FDR for selection.
#' @param min_batches Minimum independent batches behind x, y and d.
#' @param min_within Minimum within-group references needed to learn a
#'   rank's guard and density; a rank with fewer is not tested.
#' @param bw_mult Bandwidth multiplier (sensitivity checks; 1 = default).
#' @return data.frame, one row per accession: the tested rank and its
#'   statistics, `separation`, `logLR`, `posterior`, `selected`, and
#'   `status`. Attributes: `pi`, `guard` (per-rank table), `n_testable`.
#' @noRd
.mislabel_lr_test <- function(stats, rank_system = c("species", "genus", "family"),
                              sep_q = 0.95, k = 20, eps = 0.01, fdr = 0.05,
                              min_batches = 2L, min_within = 20L, bw_mult = 1) {
  if (!"class" %in% names(stats)) stats$class <- NA_character_
  guard <- data.frame(rank = rank_system, n_within = 0L, cutoff = NA_real_,
                      quantum_x = NA_real_, quantum_r = NA_real_, n_measured = 0L,
                      stringsAsFactors = FALSE)
  per_rank <- list()
  for (r in rank_system) {
    s <- stats[stats$rank == r, , drop = FALSE]
    ok_b <- s$x_batches >= min_batches & s$y_batches >= min_batches & s$d_batches >= min_batches
    # Within-group population: references closer to their own group than to
    # the nearest other one. A mislabel is usually the reverse, so it does
    # not inflate the guard it is then tested against.
    w <- s[s$x_batches >= min_batches & !is.na(s$x) & (is.na(s$y) | s$y < s$x), , drop = FALSE]
    gi <- match(r, guard$rank)
    guard$n_within[gi] <- nrow(w)
    if (nrow(w) < min_within) {
      s$status <- "rank_not_learnable"
      per_rank[[r]] <- s
      next
    }
    m <- 100 - w$x
    guard$cutoff[gi] <- as.numeric(stats::quantile(m, sep_q))
    qx <- .estimate_score_quantum(m)
    guard$quantum_x[gi] <- qx
    ms <- .smooth_comb(m, qx)
    f_all <- .mislabel_reflected_kde(ms, bw_mult)
    cls_n <- table(w$class)
    f_cls <- lapply(split(ms, w$class), .mislabel_reflected_kde, bw_mult = bw_mult)
    f <- function(xv, cl) {
      mm <- 100 - xv
      wt <- if (!is.na(cl) && cl %in% names(cls_n)) cls_n[[cl]] / (cls_n[[cl]] + k) else 0
      fc <- if (wt > 0) f_cls[[cl]](mm) else 0
      (1 - eps) * (wt * fc + (1 - wt) * f_all(mm)) + eps * stats::dunif(mm, 0, 50)
    }
    rr <- (s$y - s$d)[ok_b & !is.na(s$y) & !is.na(s$d)]
    guard$n_measured[gi] <- length(rr)
    qr <- .estimate_score_quantum(rr)
    guard$quantum_r[gi] <- qr
    rrs <- .smooth_comb(rr, qr)
    g_bw <- max(stats::bw.nrd0(rrs), 0.1) * bw_mult
    g <- function(z) (1 - eps) * vapply(z, function(v) mean(stats::dnorm(v, rrs, g_bw)), 0) +
      eps * stats::dunif(z, -50, 50)
    s$separation <- 100 - s$d
    testable <- ok_b & !is.na(s$x) & !is.na(s$y) & !is.na(s$d) & s$separation > guard$cutoff[gi]
    s$status <- ifelse(testable, "tested",
                ifelse(!ok_b, "insufficient_evidence", "below_separation"))
    s$logLR <- NA_real_
    if (any(testable)) {
      ti <- which(testable)
      s$logLR[ti] <- log(mapply(f, s$y[ti], s$class[ti])) + log(g(s$x[ti] - s$d[ti])) -
        log(mapply(f, s$x[ti], s$class[ti])) - log(g(s$y[ti] - s$d[ti]))
    }
    per_rank[[r]] <- s
  }
  all <- do.call(rbind, lapply(per_rank, function(s) {
    for (cc in c("separation", "logLR")) if (!cc %in% names(s)) s[[cc]] <- NA_real_
    s
  }))
  # one row per accession: the finest rank where it was tested, otherwise the
  # finest rank's row (so its reason for being untested is reported)
  all$.ord <- match(all$rank, rank_system) + ifelse(all$status == "tested", 0, 100)
  all <- all[order(all$accession, all$.ord), ]
  out <- all[!duplicated(all$accession), ]
  out$.ord <- NULL
  t_idx <- which(out$status == "tested")
  out$posterior <- NA_real_
  out$selected <- FALSE
  pi <- NA_real_
  if (length(t_idx)) {
    lr <- exp(pmin(out$logLR[t_idx], 700))
    pi <- 0.01
    for (it in 1:1000) {
      post <- pi * lr / (pi * lr + 1 - pi)
      pn <- mean(post)
      if (abs(pn - pi) < 1e-10) break
      pi <- pn
    }
    out$posterior[t_idx] <- post
    o <- order(-post)
    bfdr <- cumsum(1 - post[o]) / seq_along(o)
    ncut <- max(c(0L, which(bfdr <= fdr)))
    out$selected[t_idx[o[seq_len(ncut)]]] <- TRUE
  }
  rownames(out) <- NULL
  attr(out, "pi") <- pi
  attr(out, "guard") <- guard
  attr(out, "n_testable") <- table(factor(out$rank[out$status == "tested"], levels = rank_system))
  out
}

#' Is a listed group itself split toward its nearest group?
#'
#' For every deposit of group `A` (at `rank`), compares its best identity to
#' the rest of `A` (other batches only) with its best identity to `B`; a tie
#' counts as B-like. Above species rank, members of the deposit's own finer
#' group are excluded from "the rest of A", as in the test. A batch is B-like
#' when most of its deposits are.
#'
#' A maximum rather than the test's median-over-batches is deliberate. With a
#' median, a B-like majority vouches for itself and a split group reads as
#' coherent. With a maximum, the only distortion is that a B-like MINORITY
#' whose members match each other can vouch for itself -- which only makes a
#' group look more coherent, and so only ever leads to removal, the cheap
#' error. The guard therefore diverts only a genuine majority split.
#'
#' @return c(n_batches = batches with both comparisons, n_blike = B-like
#'   batches).
#' @noRd
.mislabel_group_split <- function(hits, deposits, rank, A, B,
                                  rank_system = c("species", "genus", "family")) {
  k <- match(rank, rank_system)
  finer <- if (k > 1L) rank_system[k - 1L] else NA_character_
  inA <- deposits$acc[deposits[[rank]] %in% A]
  inB <- deposits$acc[deposits[[rank]] %in% B]
  bat <- stats::setNames(deposits$batch, deposits$acc)
  fin <- if (is.na(finer)) NULL else stats::setNames(deposits[[finer]], deposits$acc)
  h <- hits[hits$q %in% inA & hits$s %in% c(inA, inB) & hits$q != hits$s, ]
  h <- h[bat[h$q] != bat[h$s], ]
  if (!is.null(fin)) {
    same_finer <- !is.na(fin[h$q]) & !is.na(fin[h$s]) & fin[h$s] == fin[h$q]
    h <- h[!(h$s %in% inA & same_finer), ]
  }
  if (!nrow(h)) return(c(n_batches = 0L, n_blike = 0L))
  per_q <- lapply(split(h, h$q), function(z) {
    a <- z$s %in% inA
    c(toA = if (any(a)) max(z$pid[a]) else NA_real_,
      toB = if (any(!a)) max(z$pid[!a]) else NA_real_)
  })
  m <- do.call(rbind, per_q)
  m <- m[!is.na(m[, "toA"]) & !is.na(m[, "toB"]), , drop = FALSE]
  if (!nrow(m)) return(c(n_batches = 0L, n_blike = 0L))
  blike <- tapply(m[, "toB"] >= m[, "toA"], bat[rownames(m)], mean) > 0.5
  c(n_batches = length(blike), n_blike = sum(blike))
}

#' Run the mislabel test with the two-pass robustness rule and the
#' last-references guard
#'
#' Pass 1 tests every reference. Pass 2 recomputes every statistic with the
#' pass-1 selections removed from both sides (a mislabelled deposit of A can
#' distort A's distance to B) and re-runs the test. A reference is a removal
#' candidate only if BOTH passes select it. A candidate whose removal would
#' leave its listed species with fewer than `min_refs_left` references in
#' `ref_species` becomes `"inspect"` rather than `"remove"`.
#'
#' @param stats_fun function(exclude) returning the per-rank statistics
#'   table for `.mislabel_lr_test()` (it closes over hits/deposits).
#' @param ref_species Named character: listed species per reference
#'   accession, for the last-references guard.
#' @param min_refs_left Integer.
#' @param deposits,hits The deposit pool (`acc`, `batch`, rank columns) and
#'   the pair-search hits, for the taxonomic-conflict guard; either `NULL`
#'   disables it.
#' @param split_share,min_group_batches A selection is a taxonomic conflict,
#'   sent to "inspect", when its listed group has at least
#'   `min_group_batches` independent deposit batches that can be compared
#'   and more than `split_share` of them are closer to the nearest group than
#'   to the rest of their own group (`.mislabel_group_split()`). A coherent
#'   group with a dissenting minority -- the mislabel shape -- is removed, and
#'   so is a group too small to judge.
#' @param ... Passed to `.mislabel_lr_test()`.
#' @return data.frame from pass 1 with `selected_pass1`, `selected_pass2`,
#'   `posterior_pass2`, `refs_left`, `action` (`remove`, `inspect`, `keep`,
#'   `untested`) and `reason`. Attributes: both passes' `pi` and `guard`,
#'   and `rule_key`.
#' @noRd
.test_reference_mislabels <- function(stats_fun, ref_species, min_refs_left = 2L,
                                      deposits = NULL, hits = NULL, split_share = 0.5,
                                      min_group_batches = 5L, ...) {
  dots <- list(...)
  p1 <- do.call(.mislabel_lr_test, c(list(stats = stats_fun(character(0))), dots))
  sel1 <- p1$accession[p1$selected]
  p2 <- do.call(.mislabel_lr_test, c(list(stats = stats_fun(sel1)), dots))
  out <- p1
  names(out)[names(out) == "selected"] <- "selected_pass1"
  j <- match(out$accession, p2$accession)
  out$selected_pass2 <- p2$selected[j] %in% TRUE
  out$posterior_pass2 <- p2$posterior[j]
  both <- out$selected_pass1 & out$selected_pass2
  sp <- ref_species[out$accession]
  removed <- out$accession[both]
  out$refs_left <- vapply(seq_len(nrow(out)), function(i) {
    if (is.na(sp[i])) return(NA_integer_)
    sum(ref_species == sp[i] & !(names(ref_species) %in% removed))
  }, integer(1))
  # Taxonomic-conflict guard. A coherent group with a dissenting minority
  # is the mislabel shape and is removed. When the listed group is itself
  # split -- most of its independent deposit batches look like the nearest
  # group -- its circumscription is in question (an unsettled genus, a
  # cryptic complex), so the selection goes to inspect. A group with fewer
  # than min_group_batches comparable batches is too small to judge, and is
  # removed: a false removal costs much less than a retained mislabel.
  out$group_batches <- NA_integer_
  out$group_batches_blike <- NA_integer_
  out$taxonomic_conflict <- FALSE
  if (!is.null(deposits) && !is.null(hits) && any(both)) {
    rs <- utils::modifyList(list(rank_system = c("species", "genus", "family")), dots)$rank_system
    key <- paste(out$rank, out$A, out$B, sep = "\r")
    for (k in unique(key[both])) {
      sel <- which(key == k & both)
      sp <- .mislabel_group_split(hits, deposits, out$rank[sel[1]], out$A[sel[1]], out$B[sel[1]], rs)
      out$group_batches[sel] <- sp[["n_batches"]]
      out$group_batches_blike[sel] <- sp[["n_blike"]]
      out$taxonomic_conflict[sel] <- sp[["n_batches"]] >= min_group_batches &&
        sp[["n_blike"]] / sp[["n_batches"]] > split_share
    }
  }
  out$action <- ifelse(out$status != "tested", "untested",
                ifelse(!both, "keep",
                ifelse(out$taxonomic_conflict, "inspect",
                ifelse(!is.na(out$refs_left) & out$refs_left < min_refs_left, "inspect", "remove"))))
  out$reason <- ifelse(out$action == "untested", out$status,
                ifelse(out$action == "keep" & out$selected_pass1, "not_selected_in_pass2",
                ifelse(out$action == "keep", "not_selected",
                ifelse(out$taxonomic_conflict, "taxonomic_conflict",
                ifelse(out$action == "inspect", "would_leave_too_few_references",
                       "selected_both_passes")))))
  a <- utils::modifyList(list(rank_system = c("species", "genus", "family"), sep_q = 0.95,
                              k = 20, eps = 0.01, fdr = 0.05, min_batches = 2L,
                              min_within = 20L, bw_mult = 1), dots)
  attr(out, "rule_key") <- paste(.MISLABEL_RULE_VERSION,
    paste0("ranks=", paste(a$rank_system, collapse = ",")), paste0("sep_q=", a$sep_q),
    paste0("k=", a$k), paste0("eps=", a$eps), paste0("fdr=", a$fdr),
    paste0("minb=", a$min_batches), paste0("min_within=", a$min_within),
    paste0("bw=", a$bw_mult), paste0("min_refs_left=", min_refs_left),
    paste0("split_guard=", if (is.null(deposits) || is.null(hits)) "off" else
      paste0(split_share, "/min", min_group_batches)), "two_pass", sep = "|")
  attr(out, "pi") <- c(pass1 = attr(p1, "pi"), pass2 = attr(p2, "pi"))
  attr(out, "guard") <- attr(p1, "guard")
  attr(out, "guard_pass2") <- attr(p2, "guard")
  attr(out, "n_testable") <- attr(p1, "n_testable")
  out
}
