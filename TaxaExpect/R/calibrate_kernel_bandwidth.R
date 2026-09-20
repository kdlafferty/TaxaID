# Companion to estimate_kernel_priors() (kernel-priors redesign, 2026-08-30).
# Chooses the kernel tuning values by out-of-sample composition prediction --
# the redesign's replacement for AIC-based formula screening.

#' Calibrate kernel bandwidths by leave-one-block-out composition prediction
#'
#' Chooses `lambda_km` (and optionally the covariate bandwidth and the
#' back-off mass `m`) for [estimate_kernel_priors()] empirically: records are
#' partitioned into spatial blocks; each block's species composition is
#' predicted from all records \emph{outside} it, using the same kernel
#' machinery evaluated at the block's own data centroid; predictions are
#' scored by per-record multinomial log-loss against the block's actual
#' records. Two reference predictors are always scored alongside for
#' context: `regional` (all held-out records, unweighted -- "is locality
#' worth anything?") and `nearest_block` (the single nearest other block --
#' the retired one-cell architecture).
#'
#' The spatial blocks are a cross-validation device only -- they impose no
#' structure on the estimator being calibrated (this is the one place a grid
#' survives the kernel redesign, and the only job it keeps).
#'
#' @param occurrence_data,site_habitat,taxon_col,lat_col,lon_col,habitat_col
#'   As in [estimate_kernel_priors()].
#' @param lambda_grid Numeric vector of candidate geographic bandwidths (km).
#'   Default `c(10, 25, 50, 100, 200)`.
#' @param m_grid Numeric vector of candidate back-off masses. Default `1`
#'   (calibrate lambda only). Supply several values to tune `m` jointly.
#' @param covariate_col,lambda_covariate_grid Optional: a numeric record
#'   column (e.g. depth) and candidate bandwidths for its kernel factor. When
#'   supplied, every (lambda, lambda_covariate, m) combination is scored; the
#'   block's mean covariate value stands in for the "site" value. `NULL`
#'   (default) disables the covariate factor.
#' @param lambda_latitude_grid Optional numeric vector: candidate bandwidths
#'   (km) for [estimate_kernel_priors()]'s climate-similarity factor on the
#'   absolute-latitude difference. `Inf` (factor off) is always added to the
#'   sweep so the no-factor case competes on equal footing -- a best row with
#'   `lambda_latitude = Inf` means the data rejected the factor. `NULL`
#'   (default) omits the dimension entirely.
#' @param block_size_deg Numeric scalar: CV block size in degrees (default
#'   `0.5`). A block enters scoring only if it holds at least
#'   `min_block_records` records.
#' @param min_block_records Integer, default `20L`.
#' @param sampling_group_col Optional column naming a detection-process
#'   grouping (e.g. `"sampling_group"`) -- the same column passed to
#'   [estimate_kernel_priors()]. `NULL` (default) scores ONE pooled
#'   composition, which reproduces the pre-2026-09-19 behaviour exactly.
#'   **Pass it whenever the estimator will be given it.** See
#'   \verb{Why pooling the groups fits the wrong lambda}.
#' @param min_group_records Minimum records a group must contribute to a block
#'   before that (block, group) cell is scored. `NULL` (default) follows
#'   `min_block_records`, which makes this function's stratified fit agree on
#'   block eligibility with the other way of fitting per group -- subsetting to
#'   one group and calling this function on each subset. Lower it to admit
#'   sparse cells; a thin group's loss curve will flatten when you do. Ignored
#'   without `sampling_group_col`.
#' @param smoothing Laplace pseudo-count added to every species when forming
#'   a predicted composition, so held-out species never score `-Inf`
#'   (default `0.5`).
#'
#' @section Why pooling the groups fits the wrong lambda:
#' Composition is a share WITHIN a detection process. With one pooled
#' composition, a block's log-loss is dominated by whichever group contributed
#' the most records, so lambda is fitted to that group and then handed to
#' every group by [estimate_kernel_priors()]. **It does not announce itself:
#' the fit succeeds and returns a plausible number**, just the wrong one for
#' every group but the dominant one.
#'
#' With `sampling_group_col` set, each (block, group) cell is scored against
#' that group's own composition, over that group's own species universe, and
#' the cells are combined weighting each group by the target records it
#' contributed. A record counts once, so a group's influence is its share of
#' the data -- not one-group-one-vote, which would let a 20-record group
#' outvote a 200,000-record one.
#'
#' Two details that are easy to get wrong and are handled here. The species
#' universe is per group: smoothing a group's composition over the FULL
#' species set would put `smoothing` mass on every species that group can
#' never contain, shrinking its real probabilities by the ratio of the two set
#' sizes -- an invisible, group-size-dependent penalty. And a (block, group)
#' cell is skipped when the group has fewer than 2 target records there or no
#' held-out records at all, since a 1-record target is a degenerate
#' composition; the count of skipped cells is reported.
#'
#' \strong{One lambda is still one lambda.} [estimate_kernel_priors()] takes a
#' scalar `lambda_km`, so this function cannot give each group its own. What it
#' can do is say whether that is defensible: `$by_group` reports each group's
#' own optimum, and a warning fires when they differ by 2x or more. On a
#' fixture with 4 km patches in one group and 55 km patches in another, the
#' groups chose 5 km and 25 km and the record-weighted compromise was 5 km --
#' correct for the dominant group, 5x too narrow for the other. Treat that
#' warning as a prompt to fit the groups separately, not as noise.
#'
#' @return A list with \describe{
#'   \item{results}{Data frame: one row per parameter combination plus the
#'     `regional` and `nearest_block` references; columns `lambda_km`,
#'     `lambda_covariate`, `lambda_latitude`, `m`, `mean_logloss` (simple
#'     mean over blocks),
#'     `weighted_logloss` (record-weighted), `blocks_beating_nearest`.}
#'   \item{best}{The row minimizing `weighted_logloss` among kernel rows.}
#'   \item{n_blocks}{Number of scored blocks.}
#'   \item{by_group}{`NULL` without `sampling_group_col`, or with a single
#'     group. Otherwise one row per group: `sampling_group`, `n_records`,
#'     `n_blocks_scored`, that group's own optimal `lambda_km`,
#'     `lambda_covariate`, `lambda_latitude`, `m`, and its
#'     `weighted_logloss`. Read it before trusting `best`.}
#' }
#' @seealso [estimate_kernel_priors()]
#' @export
calibrate_kernel_bandwidth <- function(occurrence_data,
                                       site_habitat,
                                       lambda_grid = c(10, 25, 50, 100, 200),
                                       m_grid = 1,
                                       covariate_col = NULL,
                                       lambda_covariate_grid = NULL,
                                       lambda_latitude_grid = NULL,
                                       block_size_deg = 0.5,
                                       min_block_records = 20L,
                                       sampling_group_col = NULL,
                                       min_group_records = NULL,
                                       smoothing = 0.5,
                                       taxon_col = "taxon_name",
                                       lat_col = "decimalLatitude",
                                       lon_col = "decimalLongitude",
                                       habitat_col = "main_habitat") {
  if (!is.data.frame(occurrence_data) || nrow(occurrence_data) == 0L) {
    stop("occurrence_data must be a non-empty data frame.")
  }
  for (nm in c(taxon_col, lat_col, lon_col, habitat_col)) {
    if (!nm %in% names(occurrence_data)) {
      stop(sprintf("occurrence_data is missing required column '%s'.", nm))
    }
  }
  if (!is.numeric(lambda_grid) || length(lambda_grid) < 1L || any(lambda_grid <= 0)) {
    stop("lambda_grid must be positive numerics.")
  }
  if (!is.numeric(m_grid) || any(m_grid < 0)) {
    stop("m_grid must be non-negative numerics.")
  }
  use_cov <- !is.null(covariate_col)
  if (use_cov) {
    if (!covariate_col %in% names(occurrence_data)) {
      stop(sprintf("covariate_col '%s' not found in occurrence_data.", covariate_col))
    }
    if (is.null(lambda_covariate_grid) || any(lambda_covariate_grid <= 0)) {
      stop("lambda_covariate_grid (positive numerics) is required with covariate_col.")
    }
  } else {
    lambda_covariate_grid <- NA_real_
  }
  if (!is.null(lambda_latitude_grid)) {
    if (!is.numeric(lambda_latitude_grid) || any(lambda_latitude_grid <= 0)) {
      stop("lambda_latitude_grid must be positive numerics (or NULL).")
    }
    # Include Inf explicitly so the factor-off case competes in the same sweep
    # (exp(-x/Inf) = 1 reproduces the no-factor weights exactly).
    if (!any(is.infinite(lambda_latitude_grid))) {
      lambda_latitude_grid <- c(lambda_latitude_grid, Inf)
    }
  } else {
    lambda_latitude_grid <- NA_real_
  }

  hab <- occurrence_data[[habitat_col]]
  keep <- !is.na(hab) & hab == site_habitat & !is.na(occurrence_data[[taxon_col]]) &
    !is.na(occurrence_data[[lat_col]]) & !is.na(occurrence_data[[lon_col]])
  rec <- occurrence_data[keep, , drop = FALSE]
  if (nrow(rec) < 2L * min_block_records) {
    stop("Too few records in the focal habitat stratum to cross-validate.")
  }
  taxa <- as.character(rec[[taxon_col]])
  lat <- rec[[lat_col]]
  lon <- rec[[lon_col]]
  cov_v <- if (use_cov) rec[[covariate_col]] else NULL

  block <- paste0(floor(lat / block_size_deg), "_", floor(lon / block_size_deg))
  btab <- table(block)
  score_blocks <- names(btab)[btab >= min_block_records]
  if (length(score_blocks) < 3L) {
    stop("Fewer than 3 blocks meet min_block_records -- lower block_size_deg or min_block_records.")
  }

  # --- sampling-group strata -------------------------------------------------
  # Composition is a share WITHIN a detection process. Scoring one pooled
  # composition therefore fits lambda to whichever group contributes the most
  # records and hands that lambda to every group. It does not announce itself:
  # the fit succeeds and returns a number, just the wrong one for every group
  # but the dominant one. NULL (default) = one group = the pre-2026-09-19
  # behaviour, exactly (regression-tested).
  grp <- if (is.null(sampling_group_col)) {
    rep("__all__", nrow(rec))
  } else {
    as.character(rec[[sampling_group_col]])
  }
  grp[is.na(grp)] <- "__ungrouped__"
  grp_levels <- sort(unique(grp))
  # Block ELIGIBILITY is decided at line ~169 from the POOLED record set,
  # before grouping exists. So without a per-group bar, a block qualifies on
  # its pooled count and a group can then join it with a handful of records --
  # which is NOT what you get from the other way of fitting per group, namely
  # subsetting to one group and calling this function on each subset (see
  # eDNA/PtConception/Multi_site_multi_marker/21_calibrate_depth_per_group.R).
  # There a block must carry `min_block_records` of that group's OWN records.
  # Defaulting to min_block_records makes the two routes agree on eligibility,
  # so their answers are comparable; lower it deliberately to admit sparse
  # cells, and expect a flatter loss curve for the thin groups when you do.
  if (is.null(min_group_records)) min_group_records <- min_block_records
  if (!is.numeric(min_group_records) || length(min_group_records) != 1L ||
      is.na(min_group_records) || min_group_records < 2) {
    stop("min_group_records must be a single number >= 2 (a 1-record target is a degenerate composition), or NULL to follow min_block_records.")
  }

  # Each group gets its own species universe. Smoothing a group's composition
  # over the FULL species set would put `smoothing` mass on every species the
  # group can never contain, shrinking its real probabilities by the ratio of
  # the two set sizes -- an invisible, group-size-dependent penalty.
  species_by_g <- lapply(grp_levels, function(g) sort(unique(taxa[grp == g])))
  names(species_by_g) <- grp_levels

  km <- function(la1, lo1, la2, lo2, ref_lat) {
    111 * sqrt((la1 - la2)^2 + ((lo1 - lo2) * cos(ref_lat * pi / 180))^2)
  }
  logloss <- function(target_counts, w_held, taxa_held, g = "__all__") {
    sp_g <- species_by_g[[g]]
    cw <- tapply(w_held, taxa_held, sum)
    q <- stats::setNames(rep(smoothing, length(sp_g)), sp_g)
    q[names(cw)] <- q[names(cw)] + cw
    q <- q / sum(q)
    -sum(target_counts * log(q[names(target_counts)])) / sum(target_counts)
  }

  # block centroids (over ALL blocks, for the nearest-block reference)
  cen <- do.call(rbind, lapply(unique(block), function(b) {
    i <- block == b
    data.frame(
      block = b, clat = mean(lat[i]), clon = mean(lon[i]),
      ccov = if (use_cov) mean(cov_v[i], na.rm = TRUE) else NA_real_,
      n = sum(i), stringsAsFactors = FALSE
    )
  }))

  grid <- expand.grid(
    lambda_km = lambda_grid,
    lambda_covariate = unique(lambda_covariate_grid),
    lambda_latitude = unique(lambda_latitude_grid),
    m = m_grid, KEEP.OUT.ATTRS = FALSE
  )
  n_par <- nrow(grid)
  # loss[block, config]; two extra columns for the references
  loss <- matrix(NA_real_,
    nrow = length(score_blocks), ncol = n_par + 2L,
    dimnames = list(score_blocks, c(rep("", n_par), "regional", "nearest_block"))
  )
  n_target <- integer(length(score_blocks))

  # Per-group loss, same shape as `loss`, so a caller can see whether the
  # groups actually agree on a bandwidth or the single answer is a compromise.
  loss_by_g <- lapply(grp_levels, function(g) {
    matrix(NA_real_, nrow = length(score_blocks), ncol = n_par + 2L,
           dimnames = list(score_blocks, c(rep("", n_par), "regional", "nearest_block")))
  })
  names(loss_by_g) <- grp_levels
  n_target_by_g <- matrix(0L, nrow = length(score_blocks), ncol = length(grp_levels),
                          dimnames = list(score_blocks, grp_levels))
  n_cells_skipped <- 0L

  # One scored cell = (block, config, group). A group contributes to a block's
  # loss only when it has at least `min_group_records` target records there and
  # at least 1 held-out record to predict from. At one group this can never
  # bite: blocks already carry >= min_block_records by construction.
  .score_cell <- function(tgt_g, w_g, taxa_g, m_gi, g) {
    if (m_gi > 0) {
      sp_g <- species_by_g[[g]]
      cw <- tapply(w_g, taxa_g, sum)
      p_reg <- table(taxa_g); p_reg <- p_reg / sum(p_reg)
      q <- stats::setNames(rep(smoothing, length(sp_g)), sp_g)
      q[names(cw)] <- q[names(cw)] + cw
      Wb <- sum(w_g)
      nb <- if (Wb > 0) Wb^2 / sum(w_g^2) else 0
      sb <- if (Wb > 0) nb / Wb else 0
      q2 <- q * sb
      q2[names(p_reg)] <- q2[names(p_reg)] + m_gi * as.numeric(p_reg)
      q2 <- q2 / sum(q2)
      -sum(tgt_g * log(q2[names(tgt_g)])) / sum(tgt_g)
    } else {
      logloss(tgt_g, w_g, taxa_g, g)
    }
  }

  for (bi in seq_along(score_blocks)) {
    b <- score_blocks[bi]
    held <- block != b
    in_b <- block == b
    n_target[bi] <- sum(in_b)
    ci <- cen[cen$block == b, ]
    d <- km(lat[held], lon[held], ci$clat, ci$clon, ci$clat)
    grp_held <- grp[held]
    taxa_held <- taxa[held]
    lat_held <- lat[held]
    cov_held <- if (use_cov) cov_v[held] else NULL
    oth <- cen[cen$block != b, ]
    nb_id <- oth$block[which.min(km(oth$clat, oth$clon, ci$clat, ci$clon, ci$clat))]
    block_held <- block[held]

    # groups that can be scored in this block at all
    gs <- grp_levels[vapply(grp_levels, function(g)
      sum(in_b & grp == g) >= min_group_records && any(grp_held == g), logical(1))]
    n_cells_skipped <- n_cells_skipped + (length(grp_levels) - length(gs))
    if (length(gs) == 0L) next
    for (g in gs) n_target_by_g[bi, g] <- sum(in_b & grp == g)

    for (gi in seq_len(n_par)) {
      w <- exp(-d / grid$lambda_km[gi])
      if (use_cov && !is.na(grid$lambda_covariate[gi])) {
        w <- w * ifelse(is.na(cov_held), 1,
          exp(-abs(cov_held - ci$ccov) / grid$lambda_covariate[gi])
        )
      }
      if (!is.na(grid$lambda_latitude[gi]) && is.finite(grid$lambda_latitude[gi])) {
        w <- w * exp(-111 * abs(abs(lat_held) - abs(ci$clat)) /
          grid$lambda_latitude[gi])
      }
      for (g in gs) {
        hg <- grp_held == g
        loss_by_g[[g]][bi, gi] <- .score_cell(
          table(taxa[in_b & grp == g]), w[hg], taxa_held[hg], grid$m[gi], g)
      }
    }
    for (g in gs) {
      hg <- grp_held == g
      tgt_g <- table(taxa[in_b & grp == g])
      loss_by_g[[g]][bi, n_par + 1L] <- logloss(tgt_g, rep(1, sum(hg)), taxa_held[hg], g)
      loss_by_g[[g]][bi, n_par + 2L] <- logloss(
        tgt_g, as.numeric(block_held[hg] == nb_id), taxa_held[hg], g)
    }
  }

  # Combine groups into the block-level loss, weighting each group by how many
  # target records it contributed to that block. A record counts once, so a
  # group's influence is its share of the data -- not one-group-one-vote, which
  # would let a 20-record group outvote a 200,000-record one.
  for (bi in seq_along(score_blocks)) {
    wts <- n_target_by_g[bi, ]
    if (sum(wts) == 0) next
    for (cj in seq_len(n_par + 2L)) {
      v <- vapply(grp_levels, function(g) loss_by_g[[g]][bi, cj], numeric(1))
      ok <- !is.na(v) & wts > 0
      if (any(ok)) loss[bi, cj] <- sum(v[ok] * wts[ok]) / sum(wts[ok])
    }
  }
  # n_target must match what actually got scored, or the weighted_logloss
  # denominator counts records no cell ever predicted.
  n_target <- as.integer(rowSums(n_target_by_g))
  scored <- n_target > 0L
  if (sum(scored) < 3L) {
    stop("Fewer than 3 blocks could be scored once sampling groups were applied -- lower block_size_deg/min_block_records, or pool groups.")
  }
  if (any(!scored)) {
    loss <- loss[scored, , drop = FALSE]
    n_target <- n_target[scored]
    n_target_by_g <- n_target_by_g[scored, , drop = FALSE]
    loss_by_g <- lapply(loss_by_g, function(m) m[scored, , drop = FALSE])
    score_blocks <- score_blocks[scored]
  }

  res <- rbind(
    data.frame(grid,
      mean_logloss = colMeans(loss[, seq_len(n_par), drop = FALSE]),
      weighted_logloss = colSums(loss[, seq_len(n_par), drop = FALSE] * n_target) / sum(n_target),
      blocks_beating_nearest = colSums(loss[, seq_len(n_par), drop = FALSE] <
        loss[, n_par + 2L]),
      stringsAsFactors = FALSE
    ),
    data.frame(
      lambda_km = NA_real_, lambda_covariate = NA_real_,
      lambda_latitude = NA_real_, m = NA_real_,
      mean_logloss = c(mean(loss[, "regional"]), mean(loss[, "nearest_block"])),
      weighted_logloss = c(
        sum(loss[, "regional"] * n_target),
        sum(loss[, "nearest_block"] * n_target)
      ) / sum(n_target),
      blocks_beating_nearest = NA_integer_,
      row.names = c("regional", "nearest_block"),
      stringsAsFactors = FALSE
    )
  )
  kernel_rows <- seq_len(n_par)
  best <- res[kernel_rows, ][which.min(res$weighted_logloss[kernel_rows]), ]
  # Edge-of-grid check (2026-09-02). The radius of the occurrence fetch cannot
  # be chosen from lambda a priori -- lambda is what this function estimates --
  # so the honest control is a POST-HOC one: if the best lambda sits at the
  # largest value offered, the optimum may lie outside the grid and the fetch
  # radius may be truncating real spatial structure. A lambda at the SMALLEST
  # value is reported too, since that usually means the neighbourhood is
  # dominated by very local records (or, as at Mugu 2026-09-02, that per-key
  # truncation made every species spatially identical).
  if (isTRUE(best$lambda_km >= max(lambda_grid))) {
    warning(sprintf(
      "calibrate_kernel_bandwidth: best lambda_km (%g) is the LARGEST value in lambda_grid -- the optimum may lie beyond it. Widen lambda_grid, and check the fetch radius extends to at least ~6x lambda.",
      best$lambda_km
    ), call. = FALSE)
  } else if (isTRUE(best$lambda_km <= min(lambda_grid)) && length(lambda_grid) > 1L) {
    message(sprintf(
      "  calibrate_kernel_bandwidth: best lambda_km (%g) is the SMALLEST value offered -- extend lambda_grid downward to confirm it is a real interior optimum.",
      best$lambda_km
    ))
  }
  # --- do the groups agree? --------------------------------------------------
  # A single lambda is only defensible if the groups want a similar one.
  # estimate_kernel_priors() takes ONE lambda_km, so this cannot be resolved
  # here -- but it can be reported instead of hidden.
  by_group <- NULL
  if (length(grp_levels) > 1L) {
    by_group <- do.call(rbind, lapply(grp_levels, function(g) {
      L <- loss_by_g[[g]][, seq_len(n_par), drop = FALSE]
      wts <- n_target_by_g[, g]
      ok <- wts > 0 & apply(L, 1, function(r) all(is.finite(r)))
      if (!any(ok)) {
        return(data.frame(sampling_group = g, n_records = sum(grp == g),
                          n_blocks_scored = 0L, lambda_km = NA_real_,
                          lambda_covariate = NA_real_, lambda_latitude = NA_real_,
                          m = NA_real_, weighted_logloss = NA_real_,
                          stringsAsFactors = FALSE))
      }
      wl <- colSums(L[ok, , drop = FALSE] * wts[ok]) / sum(wts[ok])
      k <- which.min(wl)
      data.frame(sampling_group = g, n_records = sum(grp == g),
                 n_blocks_scored = sum(ok),
                 lambda_km = grid$lambda_km[k],
                 lambda_covariate = grid$lambda_covariate[k],
                 lambda_latitude = grid$lambda_latitude[k],
                 m = grid$m[k], weighted_logloss = wl[k],
                 stringsAsFactors = FALSE)
    }))
    rownames(by_group) <- NULL
    lam <- by_group$lambda_km[!is.na(by_group$lambda_km)]
    if (length(lam) > 1L && max(lam) / min(lam) >= 2) {
      warning(sprintf(
        "calibrate_kernel_bandwidth: sampling groups disagree on lambda_km by %.1fx (%s). The single `best` value below is a record-weighted compromise, and estimate_kernel_priors() applies ONE lambda to every group. Inspect $by_group and consider fitting the groups separately.",
        max(lam) / min(lam),
        paste(sprintf("%s %g km", by_group$sampling_group, by_group$lambda_km), collapse = ", ")
      ), call. = FALSE)
    }
    if (n_cells_skipped > 0L) {
      message(sprintf(
        "  calibrate_kernel_bandwidth: %d (block, group) cell(s) skipped -- fewer than 2 target records or no held-out records for that group.",
        n_cells_skipped))
    }
  }

  list(results = res, best = best, n_blocks = length(score_blocks),
       by_group = by_group)
}
