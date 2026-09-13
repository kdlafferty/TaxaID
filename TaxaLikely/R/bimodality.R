# bimodality.R
# 2026-09-13: bimodality diagnostic for TaxaLikely's H1 (known-species) score
# distribution. Motivated by a real Nanopore top-hit distribution (measured
# 2026-09-13) with a 20.3% spike at exactly 100 and a tail reaching 94.1 at
# the 10th percentile, alongside a tight, unimodal Illumina distribution for
# the same marker -- mixing the two platforms and fitting one Gaussian (as
# train_likelihood_model() does for H1, and as calibrate_query_noise()'s
# offset_form = "linear" does across species) lands the mean between the two
# modes, where almost nothing is.
#
# USER DECISION (do not substitute another method here): a two-component
# normal mixture fitted by a short base-R EM, compared against a single
# component by BIC, gated additionally by a minimum mean-separation guard.
# No `diptest`, no `mixtools` -- both explicitly rejected to avoid a new
# package dependency. The bimodality coefficient (skewness/kurtosis-based)
# was explicitly rejected too: H1 scores are ceiling-skewed BY CONSTRUCTION
# (real match data piles up near 100% identity with a long left tail), and
# that skew alone would false-positive a bimodality-coefficient test on
# ordinary, genuinely unimodal single-platform data.

#' Fit a 2-component univariate normal mixture by EM (base R only)
#'
#' A short, dependency-free EM for a two-component normal mixture, used by
#' `.bimodality_check()` as the alternative model in its BIC comparison.
#' Deterministic: initialised by splitting the SORTED data at its median into
#' two halves and using each half's own mean/sd/weight as the starting
#' values -- no random restarts, so two calls on the same `x` always return
#' the same fit. Each component's sd is floored at `1%` of the whole
#' sample's own sd (with an absolute floor of `1e-8`) at every M-step, so a
#' component that lands on a single repeated value (e.g. a real platform's
#' spike at exactly 100) cannot collapse its variance to zero and send the
#' likelihood to `Inf` -- a real risk for this specific diagnostic, not a
#' hypothetical one (see the file header).
#'
#' @param x Numeric vector. Non-finite values are dropped before fitting.
#' @param max_iter Integer, maximum EM iterations (default `200L`).
#' @param tol Numeric, EM stops early once the log-likelihood improves by
#'   less than `tol` between iterations (default `1e-8`).
#' @return A list with `weights`, `means`, `sds` (each length 2, ordered by
#'   ascending mean), `loglik`, `n`, and `iter`; or `NULL` when the mixture
#'   cannot be fit at all -- fewer than 4 finite observations, or zero
#'   variance in the data (every value identical).
#' @noRd
.fit_two_component_normal <- function(x, max_iter = 200L, tol = 1e-8) {
  x <- x[is.finite(x)]
  n <- length(x)
  if (n < 4L) {
    return(NULL)
  }

  overall_sd <- stats::sd(x)
  if (!is.finite(overall_sd) || overall_sd <= 0) {
    return(NULL)
  }
  sd_floor <- max(overall_sd * 0.01, 1e-8)

  # Deterministic init: sorted data split at the median into two halves.
  x_sorted <- sort(x)
  mid <- max(floor(n / 2), 1L)
  half1 <- x_sorted[seq_len(mid)]
  half2 <- x_sorted[(mid + 1L):n]
  if (length(half2) == 0L) {
    return(NULL)
  }

  .safe_sd <- function(v) {
    s <- if (length(v) > 1L) stats::sd(v) else NA_real_
    if (!is.finite(s)) sd_floor else max(s, sd_floor)
  }

  mu <- c(mean(half1), mean(half2))
  sigma <- c(.safe_sd(half1), .safe_sd(half2))
  w <- c(length(half1), length(half2)) / n

  .mix_loglik <- function(mu, sigma, w) {
    d1 <- w[1L] * stats::dnorm(x, mu[1L], sigma[1L])
    d2 <- w[2L] * stats::dnorm(x, mu[2L], sigma[2L])
    denom <- d1 + d2
    denom[!is.finite(denom) | denom <= 0] <- .Machine$double.xmin
    list(denom = denom, loglik = sum(log(denom)))
  }

  loglik_prev <- -Inf
  iter_done <- 0L
  for (iter in seq_len(max_iter)) {
    iter_done <- iter
    e <- .mix_loglik(mu, sigma, w)
    d1 <- w[1L] * stats::dnorm(x, mu[1L], sigma[1L])
    r1 <- d1 / e$denom
    r1[!is.finite(r1)] <- 0.5
    r2 <- 1 - r1

    n1 <- sum(r1)
    n2 <- sum(r2)
    if (n1 < 1e-8 || n2 < 1e-8) {
      # A component is collapsing onto (near) zero responsibility -- stop and
      # keep the LAST parameters that had two real components, rather than
      # continuing into a degenerate one-component fit.
      break
    }

    mu1 <- sum(r1 * x) / n1
    mu2 <- sum(r2 * x) / n2
    var1 <- sum(r1 * (x - mu1)^2) / n1
    var2 <- sum(r2 * (x - mu2)^2) / n2
    sigma1 <- max(sqrt(var1), sd_floor)
    sigma2 <- max(sqrt(var2), sd_floor)

    mu_new <- c(mu1, mu2)
    sigma_new <- c(sigma1, sigma2)
    w_new <- c(n1, n2) / n

    if (is.finite(loglik_prev) && abs(e$loglik - loglik_prev) < tol) {
      mu <- mu_new
      sigma <- sigma_new
      w <- w_new
      loglik_prev <- e$loglik
      break
    }

    mu <- mu_new
    sigma <- sigma_new
    w <- w_new
    loglik_prev <- e$loglik
  }

  final <- .mix_loglik(mu, sigma, w)

  ord <- order(mu)
  list(
    weights = w[ord],
    means = mu[ord],
    sds = sigma[ord],
    loglik = final$loglik,
    n = n,
    iter = iter_done
  )
}

#' Does a fitted 2-component normal mixture have a genuine antimode?
#'
#' A 2-component Gaussian mixture can fit a skewed but genuinely UNIMODAL
#' distribution well (H1 scores are ceiling-skewed by construction -- mass
#' piles up near 100% identity with a long left tail -- and two Gaussians of
#' different width routinely approximate that shape better than one, which
#' is exactly why the delta-BIC test alone is not sufficient here, and
#' exactly the false-positive failure mode that ruled out a bimodality-
#' coefficient test for this diagnostic in the first place). What a skewed
#' unimodal fit does NOT have, and a genuinely two-humped distribution does,
#' is a real dip (antimode) in the mixture density strictly between the two
#' component means -- checked directly on a fine grid between `means[1]` and
#' `means[2]` rather than assumed. A monotonically-decaying skew produces a
#' mixture whose density between the two means never drops below the lower
#' of the two endpoint densities (no real valley, just interpolation between
#' a narrow tail-fitting component and a broad bulk-fitting one); a real
#' bimodal mixture produces an interior minimum strictly below both.
#' @noRd
.mixture_has_valley <- function(weights, means, sds, n_grid = 201L) {
  ord <- order(means)
  mu <- means[ord]
  w <- weights[ord]
  s <- sds[ord]
  if (!is.finite(mu[1L]) || !is.finite(mu[2L]) || mu[1L] == mu[2L]) {
    return(FALSE)
  }
  grid <- seq(mu[1L], mu[2L], length.out = n_grid)
  dens <- w[1L] * stats::dnorm(grid, mu[1L], s[1L]) + w[2L] * stats::dnorm(grid, mu[2L], s[2L])
  if (length(dens) < 3L) {
    return(FALSE)
  }
  interior <- dens[-c(1L, length(dens))]
  d_end <- c(dens[1L], dens[length(dens)])
  isTRUE(min(interior) < min(d_end))
}

#' Compare a 1- vs 2-component normal fit for a score vector (BIC + separation + valley)
#'
#' Fits a single normal and a 2-component normal mixture (`.fit_two_component_normal()`)
#' to `x` and flags `x` as bimodal only when ALL THREE hold:
#' \enumerate{
#'   \item the 2-component fit wins by `delta_bic > 10` -- Kass & Raftery
#'     (1995), "Bayes Factors," *JASA* 90(430):773-795, p.777's own Table:
#'     on the `2*log(Bayes factor)` scale (which a BIC difference
#'     approximates, via Schwarz's 1978 approximation), `> 10` is their
#'     "Very strong" evidence band (verified directly against the paper
#'     before use, not recited from memory -- their scale reads `0-2` "Not
#'     worth more than a bare mention," `2-6` "Positive," `6-10` "Strong,"
#'     `>10` "Very strong"). `delta_bic` here is defined as the 1-component
#'     BIC MINUS the 2-component BIC, so positive favours two components,
#'     matching that same direction;
#'   \item the two fitted means are separated by more than `min_separation`; and
#'   \item the fitted mixture density has a genuine antimode between the two
#'     means (`.mixture_has_valley()`).
#' }
#' All three matter for different reasons, found necessary (not assumed) by
#' testing this function directly against a simulated ceiling-skewed-but-
#' unimodal sample during development: `delta_bic` alone can be driven
#' arbitrarily large by two components fit to a monotonically skewed
#' distribution (one narrow component absorbing the tail, one broad
#' component absorbing the bulk) -- exactly the false-positive mode a
#' bimodality-coefficient test was rejected for, and the delta-BIC test
#' reproduces it unless the valley check is also required; `min_separation`
#' alone, with no model-comparison evidence, would flag any two arbitrary
#' points drawn from a genuinely unimodal, heavy-tailed distribution; and
#' `delta_bic` + `min_separation` together, without the valley check, STILL
#' flag the simulated ceiling-skewed case (confirmed directly: separation
#' ~1.5 units, delta_bic in the hundreds) -- only requiring a genuine density
#' dip between the two means correctly leaves it unflagged while still
#' flagging a real two-platform mixture.
#'
#' @param x Numeric vector of scores. Non-finite values are dropped.
#' @param min_n Integer, minimum number of finite observations required to
#'   attempt a mixture fit (default `50L`). Below this, returns
#'   `flag = FALSE` with an explanation -- never an error.
#' @param min_separation Numeric or `NULL`. Minimum absolute difference
#'   between the two fitted component means required (on top of the BIC
#'   test) before flagging `x` as bimodal. When `NULL` (default), resolves
#'   to `1.0`. **This default assumes `x` is on the same percent-identity-like
#'   scale [`TaxaLikely::calibrate_query_noise()`] checks its own H1 scores
#'   on** -- i.e. `p_norm * 100`, the confident-observation match proportion
#'   rescaled to percent, computed BEFORE that function's own
#'   `score_transform` (logit/sqrt_mismatch) step, not after it. That choice
#'   was made deliberately, not assumed: on the model's own transformed
#'   scale a spike at exactly 100% identity sits at a clipped, arbitrary
#'   boundary value (`logit(1 - epsilon)`) whose distance from a second mode
#'   has no natural interpretation, whereas on the raw percent scale a gap
#'   between modes is directly interpretable identity-percentage-point
#'   separation -- exactly the units the real motivating Nanopore/Illumina
#'   comparison is stated in (a ~2.8-point gap: 100.0 vs 97.2). `1.0`
#'   percentage point is chosen because it sits comfortably below that real
#'   measured gap while sitting above the per-component sd (0.3-1.1 points)
#'   observed in that same real data -- i.e. it separates a genuine
#'   two-platform mixture from ordinary single-platform score noise without
#'   being tuned to the exact motivating numbers. A caller checking a
#'   vector on a different scale (e.g. already logit-transformed) should
#'   supply an explicit `min_separation` appropriate to that scale.
#' @return A list: `n`, `bic_1`, `bic_2`, `delta_bic` (1-component BIC minus
#'   2-component BIC; positive favours two components), `weights`, `means`,
#'   `sds` (each length 2 from the 2-component fit, or `NA` when no fit was
#'   attempted/possible), `flag` (logical, never `NA`), and `explanation`
#'   (character, `NA` when `flag = TRUE` or the two-component structure is
#'   otherwise fully described by the numeric fields; otherwise a short
#'   reason `flag` is `FALSE`). Never errors.
#' @noRd
.bimodality_check <- function(x, min_n = 50L, min_separation = NULL) {
  delta_bic_threshold <- 10

  if (is.null(min_separation)) {
    min_separation <- 1.0
  }

  x <- x[is.finite(x)]
  n <- length(x)

  out <- list(
    n = n,
    bic_1 = NA_real_,
    bic_2 = NA_real_,
    delta_bic = NA_real_,
    weights = c(NA_real_, NA_real_),
    means = c(NA_real_, NA_real_),
    sds = c(NA_real_, NA_real_),
    flag = FALSE,
    explanation = NA_character_
  )

  if (n < min_n) {
    out$explanation <- sprintf(
      "only %d finite observation(s), need >= %d to attempt a mixture fit.",
      n, min_n
    )
    return(out)
  }

  m1 <- mean(x)
  s1 <- stats::sd(x)
  if (!is.finite(s1) || s1 <= 0) {
    out$explanation <- "no variance in the input (every finite value is identical)."
    return(out)
  }

  ll1 <- sum(stats::dnorm(x, m1, s1, log = TRUE))
  k1 <- 2L
  bic1 <- -2 * ll1 + k1 * log(n)
  out$bic_1 <- bic1

  fit2 <- tryCatch(
    .fit_two_component_normal(x),
    error = function(e) NULL
  )
  if (is.null(fit2)) {
    out$explanation <- "two-component mixture could not be fit (degenerate data)."
    return(out)
  }

  k2 <- 5L # 2 means + 2 sds + 1 free weight (the second is 1 - the first)
  bic2 <- -2 * fit2$loglik + k2 * log(n)
  delta_bic <- bic1 - bic2
  sep <- abs(diff(fit2$means))

  out$bic_2 <- bic2
  out$delta_bic <- delta_bic
  out$weights <- fit2$weights
  out$means <- fit2$means
  out$sds <- fit2$sds

  has_valley <- .mixture_has_valley(fit2$weights, fit2$means, fit2$sds)
  out$flag <- isTRUE(delta_bic > delta_bic_threshold) &&
    isTRUE(sep > min_separation) &&
    isTRUE(has_valley)
  if (!out$flag) {
    out$explanation <- sprintf(
      paste0(
        "two-component fit available (delta_bic=%.2f, mean separation=%.3f, ",
        "density has a genuine dip between the two means=%s) but did not clear all three ",
        "thresholds (delta_bic > %d, separation > %.3f, and a real antimode -- a fit that ",
        "only satisfies the first two is the classic false-positive signature of a skewed ",
        "but genuinely unimodal distribution, not a real two-mode mixture)."
      ),
      delta_bic, sep, has_valley, delta_bic_threshold, min_separation
    )
  }

  out
}
