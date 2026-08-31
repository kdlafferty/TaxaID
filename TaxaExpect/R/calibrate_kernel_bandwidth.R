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
#' @param block_size_deg Numeric scalar: CV block size in degrees (default
#'   `0.5`). A block enters scoring only if it holds at least
#'   `min_block_records` records.
#' @param min_block_records Integer, default `20L`.
#' @param smoothing Laplace pseudo-count added to every species when forming
#'   a predicted composition, so held-out species never score `-Inf`
#'   (default `0.5`).
#'
#' @return A list with \describe{
#'   \item{results}{Data frame: one row per parameter combination plus the
#'     `regional` and `nearest_block` references; columns `lambda_km`,
#'     `lambda_covariate`, `m`, `mean_logloss` (simple mean over blocks),
#'     `weighted_logloss` (record-weighted), `blocks_beating_nearest`.}
#'   \item{best}{The row minimizing `weighted_logloss` among kernel rows.}
#'   \item{n_blocks}{Number of scored blocks.}
#' }
#' @seealso [estimate_kernel_priors()]
#' @export
calibrate_kernel_bandwidth <- function(occurrence_data,
                                       site_habitat,
                                       lambda_grid = c(10, 25, 50, 100, 200),
                                       m_grid = 1,
                                       covariate_col = NULL,
                                       lambda_covariate_grid = NULL,
                                       block_size_deg = 0.5,
                                       min_block_records = 20L,
                                       smoothing = 0.5,
                                       taxon_col = "taxon_name",
                                       lat_col = "decimalLatitude",
                                       lon_col = "decimalLongitude",
                                       habitat_col = "main_habitat") {
  if (!is.data.frame(occurrence_data) || nrow(occurrence_data) == 0L)
    stop("occurrence_data must be a non-empty data frame.")
  for (nm in c(taxon_col, lat_col, lon_col, habitat_col))
    if (!nm %in% names(occurrence_data))
      stop(sprintf("occurrence_data is missing required column '%s'.", nm))
  if (!is.numeric(lambda_grid) || length(lambda_grid) < 1L || any(lambda_grid <= 0))
    stop("lambda_grid must be positive numerics.")
  if (!is.numeric(m_grid) || any(m_grid < 0))
    stop("m_grid must be non-negative numerics.")
  use_cov <- !is.null(covariate_col)
  if (use_cov) {
    if (!covariate_col %in% names(occurrence_data))
      stop(sprintf("covariate_col '%s' not found in occurrence_data.", covariate_col))
    if (is.null(lambda_covariate_grid) || any(lambda_covariate_grid <= 0))
      stop("lambda_covariate_grid (positive numerics) is required with covariate_col.")
  } else {
    lambda_covariate_grid <- NA_real_
  }

  hab <- occurrence_data[[habitat_col]]
  keep <- !is.na(hab) & hab == site_habitat & !is.na(occurrence_data[[taxon_col]]) &
    !is.na(occurrence_data[[lat_col]]) & !is.na(occurrence_data[[lon_col]])
  rec <- occurrence_data[keep, , drop = FALSE]
  if (nrow(rec) < 2L * min_block_records)
    stop("Too few records in the focal habitat stratum to cross-validate.")
  taxa <- as.character(rec[[taxon_col]])
  lat <- rec[[lat_col]]; lon <- rec[[lon_col]]
  cov_v <- if (use_cov) rec[[covariate_col]] else NULL

  block <- paste0(floor(lat / block_size_deg), "_", floor(lon / block_size_deg))
  btab <- table(block)
  score_blocks <- names(btab)[btab >= min_block_records]
  if (length(score_blocks) < 3L)
    stop("Fewer than 3 blocks meet min_block_records -- lower block_size_deg or min_block_records.")

  species <- sort(unique(taxa)); S <- length(species)
  km <- function(la1, lo1, la2, lo2, ref_lat)
    111 * sqrt((la1 - la2)^2 + ((lo1 - lo2) * cos(ref_lat * pi / 180))^2)
  logloss <- function(target_counts, w_held, taxa_held) {
    cw <- tapply(w_held, taxa_held, sum)
    q <- stats::setNames(rep(smoothing, S), species)
    q[names(cw)] <- q[names(cw)] + cw
    q <- q / sum(q)
    -sum(target_counts * log(q[names(target_counts)])) / sum(target_counts)
  }

  # block centroids (over ALL blocks, for the nearest-block reference)
  cen <- do.call(rbind, lapply(unique(block), function(b) {
    i <- block == b
    data.frame(block = b, clat = mean(lat[i]), clon = mean(lon[i]),
               ccov = if (use_cov) mean(cov_v[i], na.rm = TRUE) else NA_real_,
               n = sum(i), stringsAsFactors = FALSE)
  }))

  grid <- expand.grid(lambda_km = lambda_grid,
                      lambda_covariate = unique(lambda_covariate_grid),
                      m = m_grid, KEEP.OUT.ATTRS = FALSE)
  n_par <- nrow(grid)
  # loss[block, config]; two extra columns for the references
  loss <- matrix(NA_real_, nrow = length(score_blocks), ncol = n_par + 2L,
                 dimnames = list(score_blocks, c(rep("", n_par), "regional", "nearest_block")))
  n_target <- integer(length(score_blocks))

  for (bi in seq_along(score_blocks)) {
    b <- score_blocks[bi]
    held <- block != b
    tgt <- table(taxa[block == b])
    n_target[bi] <- sum(tgt)
    ci <- cen[cen$block == b, ]
    d <- km(lat[held], lon[held], ci$clat, ci$clon, ci$clat)
    for (gi in seq_len(n_par)) {
      w <- exp(-d / grid$lambda_km[gi])
      if (use_cov && !is.na(grid$lambda_covariate[gi])) {
        w <- w * ifelse(is.na(cov_v[held]), 1,
                        exp(-abs(cov_v[held] - ci$ccov) / grid$lambda_covariate[gi]))
      }
      # m pseudo-records of held-out regional composition
      if (grid$m[gi] > 0) {
        # add regional back-off as extra smoothing mass proportional to p_reg
        cw <- tapply(w, taxa[held], sum)
        p_reg <- table(taxa[held]); p_reg <- p_reg / sum(p_reg)
        q <- stats::setNames(rep(smoothing, S), species)
        q[names(cw)] <- q[names(cw)] + cw
        # scale back-off to the weight scale: m effective records
        Wb <- sum(w); nb <- if (Wb > 0) Wb^2 / sum(w^2) else 0
        sb <- if (Wb > 0) nb / Wb else 0
        q2 <- q * sb
        q2[names(p_reg)] <- q2[names(p_reg)] + grid$m[gi] * as.numeric(p_reg)
        q2 <- q2 / sum(q2)
        loss[bi, gi] <- -sum(tgt * log(q2[names(tgt)])) / sum(tgt)
      } else {
        loss[bi, gi] <- logloss(tgt, w, taxa[held])
      }
    }
    loss[bi, n_par + 1L] <- logloss(tgt, rep(1, sum(held)), taxa[held])
    oth <- cen[cen$block != b, ]
    nb_id <- oth$block[which.min(km(oth$clat, oth$clon, ci$clat, ci$clon, ci$clat))]
    loss[bi, n_par + 2L] <- logloss(tgt, as.numeric(block[held] == nb_id), taxa[held])
  }

  res <- rbind(
    data.frame(grid,
               mean_logloss = colMeans(loss[, seq_len(n_par), drop = FALSE]),
               weighted_logloss = colSums(loss[, seq_len(n_par), drop = FALSE] * n_target) / sum(n_target),
               blocks_beating_nearest = colSums(loss[, seq_len(n_par), drop = FALSE] <
                                                  loss[, n_par + 2L]),
               stringsAsFactors = FALSE),
    data.frame(lambda_km = NA_real_, lambda_covariate = NA_real_, m = NA_real_,
               mean_logloss = c(mean(loss[, "regional"]), mean(loss[, "nearest_block"])),
               weighted_logloss = c(sum(loss[, "regional"] * n_target),
                                    sum(loss[, "nearest_block"] * n_target)) / sum(n_target),
               blocks_beating_nearest = NA_integer_,
               row.names = c("regional", "nearest_block"),
               stringsAsFactors = FALSE)
  )
  kernel_rows <- seq_len(n_par)
  best <- res[kernel_rows, ][which.min(res$weighted_logloss[kernel_rows]), ]
  list(results = res, best = best, n_blocks = length(score_blocks))
}
