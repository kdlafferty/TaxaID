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
#
# 2026-09-14: a SECOND, structurally different false-positive class was found
# on the real PtConception 12S production run (2026-09-14): percent identity
# on a short fixed-length amplicon is DISCRETE, not continuous -- a ~167bp
# amplicon only takes values spaced by one mismatch's worth of identity
# (measured 0.6 apart on that run: 98.8/99.4/98.2/... are the three most
# common of 219 distinct values in the raw match object, 219 distinct values
# across 47,347 rows). A "comb" of spikes at each integer-mismatch position
# has LITERAL zero density in the gaps between teeth -- not a real valley
# between two populations, just quantization -- and a two-component Gaussian
# mixture always beats one component on comb-like data (delta BIC in the
# thousands is routine), while the existing valley guard, which was built to
# reject a smoothly ceiling-skewed unimodal shape, PASSES on a comb precisely
# because a real (if spurious) density dip genuinely sits between the teeth.
# The same artifact showed from the other end in `train_likelihood_model()`'s
# `Stats$h1_bimodality` for that same run: the "second component" it fit was
# just the spike at exactly 100.0 identity, a structural feature of every
# reference-based dataset (every reference matches itself perfectly), not a
# second population.
#
# FIX (do not substitute another approach here either -- this is also a
# user decision, not an implementation detail left open): (1) estimate the
# QUANTUM -- the identity change per mismatch -- directly from the data
# (`.estimate_score_quantum()`), returning `NA` when the data don't look
# discretely comb-shaped at all (few repeated values relative to sample
# size); (2) when a quantum is found, SMOOTH the comb before fitting
# (`.smooth_comb()`) by deterministically spreading each tied group of
# observations evenly across its own quantum-wide cell -- a dependency-free,
# reproducible continuity correction (the classical "Sheppard's correction"
# idea: convolve with a Uniform(-quantum/2, quantum/2) kernel) that closes
# the LITERAL zero-density gaps between comb teeth without disturbing a real
# gap of several quanta between two genuinely separate populations; (3)
# require the minority component to hold real mass (>= `min_minority_weight`,
# default `0.15`) before calling it a mode at all -- a thin tail is not a
# second population; (4) require the two fitted means to be separated by
# more than a few QUANTA (default `3`), not just the pre-existing absolute
# `1.0`, since on a 167bp amplicon `1.0` percentage point is under two
# mismatches. All of this sits ON TOP of the existing delta-BIC, mean-
# separation and density-valley conditions -- none of those three were
# loosened, only tightened. See `.estimate_score_quantum()` and
# `.smooth_comb()`'s own docs for the full mechanism, and
# `calibrate_query_noise()`'s "Bimodality diagnostic" `@section` for how this
# was validated against the real run that found it.

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

#' Estimate the identity-per-mismatch quantum of a percent-identity vector
#'
#' Percent identity on a fixed-length amplicon is discrete: a query that
#' differs from its reference by one more mismatch loses a fixed, predictable
#' amount of identity (`1/amplicon_length`, e.g. `~0.6` percentage points on
#' a ~167bp MiFish amplicon). Real match-score vectors therefore pile up at a
#' handful of dominant "teeth" spaced one quantum apart, not a continuum --
#' and 2026-09-14's real false positive traced directly to that comb shape,
#' not a genuine second population (see this file's own header note). This
#' function estimates that spacing directly from the data, so the caller can
#' smooth over it (`.smooth_comb()`) and scale its own separation
#' requirements by it, rather than assuming any fixed value.
#'
#' Method: take the smallest set of distinct values (by observation COUNT,
#' descending) whose cumulative count reaches `mass_fraction` of the sample
#' -- the comb's dominant teeth -- and return the median of the positive
#' gaps between them (sorted ascending). Selecting by count rather than by
#' value means an occasional low-count outlier well away from the ceiling
#' never distorts the estimate, and taking several teeth (not just the top
#' one or two) makes the median robust to one tooth's count being unusually
#' close to a neighbour's.
#'
#' Two guards return `NA` (i.e. "behave exactly as before -- no quantum, no
#' smoothing") rather than guessing:
#' \enumerate{
#'   \item **Genuinely continuous data**: if the number of distinct values
#'     present is a large fraction of the sample size (`> max_unique_frac`,
#'     default `0.3`), there is no meaningful repetition to treat as a comb
#'     -- most real-valued draws (e.g. `rnorm()`) are all but unique. This is
#'     checked as a fraction of the WHOLE sample, not of the dominant-tooth
#'     subset -- a comb with genuinely few distinct values (as few as 6-9)
#'     can still need "most of its own small unique set" to reach
#'     `mass_fraction`, which is exactly the comb case, not the continuous
#'     one; scoping the check to overall repetition instead avoids that trap
#'     (confirmed directly against a real quantized-Gaussian fixture during
#'     development -- the naive "fraction of unique values touched" version
#'     wrongly returned `NA` for a textbook comb with only 9 distinct
#'     values).
#'   \item **A real spike sitting on an otherwise-continuous population**
#'     (e.g. a reference-matches-itself spike at exactly 100 on top of an
#'     otherwise-continuous score distribution -- the real Nanopore
#'     motivating case for this whole diagnostic): the spike alone is far
#'     too small a share of the sample's distinct-value count to trip guard
#'     1 by itself once the hundreds of essentially-unique continuum values
#'     are counted too, so the function still correctly reports no
#'     comb-wide quantum and leaves the genuine two-population signal for
#'     `.fit_two_component_normal()`/`.mixture_has_valley()` to find on the
#'     raw data, unsmoothed.
#' }
#' Also returns `NA` for fewer than `min_n` finite observations, fewer than
#' `min_unique` distinct values, or fewer than 2 positive gaps among the
#' selected dominant teeth (e.g. only one tooth reaches `mass_fraction` on
#' its own).
#'
#' @param x Numeric vector. Non-finite values are dropped before estimation.
#' @param min_n Integer, minimum finite observations required (default `20L`).
#' @param min_unique Integer, minimum distinct values required (default `6L`).
#' @param mass_fraction Numeric in (0, 1], the cumulative share of
#'   observations the selected dominant teeth must cover (default `0.8`).
#' @param max_unique_frac Numeric in (0, 1], the continuous-data guard
#'   threshold on `n_distinct / n` described above (default `0.3`).
#' @return A single numeric quantum estimate, or `NA_real_` when the data
#'   don't support one (see the guards above). Never errors.
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

  # Continuous-data guard (see @details guard 1 above): scoped to the WHOLE
  # sample's repetition rate, not the dominant-tooth subset's own size.
  if (n_unique / n > max_unique_frac) {
    return(NA_real_)
  }

  # Dominant teeth: smallest set of distinct values, by count descending,
  # whose cumulative share reaches mass_fraction.
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

#' Deterministically smooth a comb-shaped vector at a given quantum
#'
#' Convolves the empirical distribution of `x` with a
#' `Uniform(-quantum/2, quantum/2)` kernel -- the classical continuity
#' correction for rounded/binned data (cf. Sheppard's correction) -- by
#' spreading each tied group of observations that share one quantized value
#' evenly across that value's own quantum-wide cell. This closes the
#' LITERAL zero-density gaps a comb has between adjacent teeth (the actual
#' mechanism behind 2026-09-14's false positive: `.mixture_has_valley()`
#' correctly finds a real dip in the fitted mixture density there, because
#' raw comb data genuinely has none between quantized values -- an artifact
#' of quantization, not evidence of two populations) while leaving a real,
#' multi-quantum gap between two genuinely separate populations essentially
#' untouched, since a single-quantum nudge cannot bridge it.
#'
#' Deterministic by construction -- each tied group's members are spread
#' across an evenly-spaced sequence of offsets (`seq(-quantum/2, quantum/2,
#' ...)`), not `stats::jitter()`/`runif()`/`sample()` -- so two calls on the
#' same `x` and `quantum` always return byte-identical output, and repeat
#' runs of anything built on this function agree exactly.
#'
#' @param x Numeric vector to smooth (may contain non-finite values; only
#'   finite ones are ever compared for tie-grouping, but the full vector,
#'   non-finite entries included, is returned in its original positions).
#' @param quantum Single numeric quantum, or `NA`/non-finite/non-positive --
#'   in which case `x` is returned completely unchanged (the "genuinely
#'   continuous data" fallback: no smoothing is ever applied without a real
#'   quantum estimate to justify it).
#' @return `x`, with each tied group's values spread evenly across its own
#'   `quantum`-wide cell. Same length and order as `x`.
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
      # grp_n evenly-spaced offsets strictly inside (-quantum/2, quantum/2),
      # excluding the two endpoints so adjacent cells never touch exactly.
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

#' Compare a 1- vs 2-component normal fit for a score vector (BIC + separation + valley + comb-awareness)
#'
#' Fits a single normal and a 2-component normal mixture (`.fit_two_component_normal()`)
#' to `x` -- SMOOTHED first over any detected quantization comb
#' (`.estimate_score_quantum()` + `.smooth_comb()`, see this file's own
#' 2026-09-14 header note) -- and flags `x` as bimodal only when ALL FOUR hold:
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
#'   \item the two fitted means are separated by more than
#'     `max(min_separation, quanta_separation_multiplier * quantum)` -- see
#'     `@param quanta_separation_multiplier`;
#'   \item the fitted mixture density has a genuine antimode between the two
#'     means (`.mixture_has_valley()`); and
#'   \item the smaller of the two fitted weights is at least
#'     `min_minority_weight` -- see `@param min_minority_weight`.
#' }
#' The first three matter for different reasons, found necessary (not
#' assumed) by testing this function directly against a simulated
#' ceiling-skewed-but-unimodal sample during development: `delta_bic` alone
#' can be driven arbitrarily large by two components fit to a monotonically
#' skewed distribution (one narrow component absorbing the tail, one broad
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
#' @section 2026-09-14: quantization comb-awareness:
#' Those three conditions alone are still not enough once `x` is genuinely
#' discrete (percent identity on a fixed-length amplicon: identical
#' sequences agree at exactly `1 - k/amplicon_length` for integer mismatch
#' count `k`, so real data forms a "comb" of spikes, not a continuum) --
#' confirmed as a real, not hypothetical, second false-positive class on the
#' real 2026-09-14 PtConception 12S production run, in addition to the
#' ceiling-skew case above: a comb has LITERAL zero density in the gaps
#' between teeth, so `.mixture_has_valley()` finds a genuine (if spurious)
#' dip there, and a two-component fit routinely wins by thousands of BIC
#' points. Two more measures, evaluated together with the three above:
#' \enumerate{
#'   \item `x` is smoothed with `.estimate_score_quantum()` +
#'     `.smooth_comb()` BEFORE every downstream computation (the
#'     one-component fit, the two-component fit, and the valley check all
#'     see the same smoothed vector) -- this is what actually closes the
#'     comb's zero-density gaps. When the data don't look comb-shaped at
#'     all (`.estimate_score_quantum()` returns `NA`), `x` passes through
#'     completely unchanged and every downstream computation is exactly the
#'     pre-2026-09-14 calculation -- confirmed by a dedicated regression
#'     test that a genuinely bimodal, continuous two-population sample
#'     (real measured Nanopore shape: a 20.3% spike at exactly 100 sitting
#'     on an otherwise-continuous population) still flags after this
#'     change, byte-identically to before it.
#'   \item the minority-weight floor (condition 4 above,
#'     `min_minority_weight`) is a second, independent guard: on the real
#'     PtConception run this diagnostic was built to fix, smoothing alone
#'     did NOT eliminate the false positive (the two fitted components
#'     stayed genuinely separated post-smoothing, with a real interior dip)
#'     -- what actually disqualified it was that the minority component
#'     held only ~4% of the mass. A thin tail is not a second mode, however
#'     cleanly separated the fitted valley looks.
#' }
#'
#' @param x Numeric vector of scores. Non-finite values are dropped.
#' @param min_n Integer, minimum number of finite observations required to
#'   attempt a mixture fit (default `50L`). Below this, returns
#'   `flag = FALSE` with an explanation -- never an error.
#' @param min_separation Numeric or `NULL`. Minimum absolute difference
#'   between the two fitted component means required (on top of the BIC
#'   test) before flagging `x` as bimodal, UNLESS a quantum was estimated,
#'   in which case `quanta_separation_multiplier * quantum` applies instead
#'   whenever it is larger (see that parameter). When `NULL` (default),
#'   resolves to `1.0`. **This default assumes `x` is on the same
#'   percent-identity-like scale [`TaxaLikely::calibrate_query_noise()`]
#'   checks its own H1 scores on** -- i.e. `p_norm * 100`, the
#'   confident-observation match proportion rescaled to percent, computed
#'   BEFORE that function's own `score_transform` (logit/sqrt_mismatch)
#'   step, not after it. That choice was made deliberately, not assumed: on
#'   the model's own transformed scale a spike at exactly 100% identity sits
#'   at a clipped, arbitrary boundary value (`logit(1 - epsilon)`) whose
#'   distance from a second mode has no natural interpretation, whereas on
#'   the raw percent scale a gap between modes is directly interpretable
#'   identity-percentage-point separation -- exactly the units the real
#'   motivating Nanopore/Illumina comparison is stated in (a ~2.8-point gap:
#'   100.0 vs 97.2). `1.0` percentage point is chosen because it sits
#'   comfortably below that real measured gap while sitting above the
#'   per-component sd (0.3-1.1 points) observed in that same real data --
#'   i.e. it separates a genuine two-platform mixture from ordinary
#'   single-platform score noise without being tuned to the exact motivating
#'   numbers. A caller checking a vector on a different scale (e.g. already
#'   logit-transformed) should supply an explicit `min_separation`
#'   appropriate to that scale.
#' @param min_minority_weight Numeric in `[0, 0.5]` (default `0.15`). The
#'   smaller of the two fitted component weights must be at least this
#'   large before `x` is flagged -- "a thin tail cannot be called a mode"
#'   (2026-09-14 fix requirement 3). `0.15` was chosen from the two real
#'   motivating numbers, not picked in the abstract: it sits comfortably
#'   BELOW the real genuinely-bimodal Nanopore minority share (`20.3%`, so a
#'   real second population is never at risk of being excluded by this
#'   floor) and comfortably ABOVE the real false-positive minority share on
#'   the 2026-09-14 PtConception run that this whole fix addresses (`4%`,
#'   which this floor alone is enough to reject, independent of the
#'   smoothing/quanta-separation changes below -- confirmed directly against
#'   that run's own real data during development).
#' @param quantum_max_unique_frac Numeric in (0, 1] passed straight to
#'   `.estimate_score_quantum(max_unique_frac = )` -- see that function's
#'   own docs. Exposed here (rather than hardcoded) purely so a caller can
#'   re-tune the continuous-vs-comb boundary without editing package code;
#'   the package's own callers never override it.
#' @param quanta_separation_multiplier Numeric (default `3`). When a
#'   quantum was estimated, the two fitted means must be separated by more
#'   than `quanta_separation_multiplier * quantum`, not just the flat
#'   `min_separation`, since on a real amplicon `min_separation`'s own
#'   default (`1.0` percentage point) is under two mismatches. `3` was
#'   chosen because it is exactly what correctly separates the two real
#'   motivating numbers from the same 2026-09-14 production run: the real
#'   FALSE-positive `train_likelihood_model()` `Stats$h1_bimodality` split
#'   (means 98.3/100, separation `1.7`) sits at `2.83` quanta at this run's
#'   own measured `0.6` quantum -- below a `3`-quanta floor (`1.8`), so it
#'   is correctly rejected -- while the real motivating genuinely-bimodal
#'   Nanopore case (a `~2.8`-`3`-point gap on data this check estimates NO
#'   quantum for at all, so `min_separation` alone applies, unaffected by
#'   this parameter) stays flagged.
#' @return A list: `n`, `bic_1`, `bic_2`, `delta_bic` (1-component BIC minus
#'   2-component BIC; positive favours two components), `weights`, `means`,
#'   `sds` (each length 2 from the 2-component fit, or `NA` when no fit was
#'   attempted/possible), `quantum` (the estimated identity-per-mismatch
#'   spacing from `.estimate_score_quantum()`, or `NA_real_` when the data
#'   don't look comb-shaped), `flag` (logical, never `NA`), and
#'   `explanation` (character, `NA` when `flag = TRUE` or the two-component
#'   structure is otherwise fully described by the numeric fields;
#'   otherwise a short reason `flag` is `FALSE`). Never errors.
#' @noRd
.bimodality_check <- function(x, min_n = 50L, min_separation = NULL,
                              min_minority_weight = 0.15,
                              quantum_max_unique_frac = 0.3,
                              quanta_separation_multiplier = 3) {
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
    quantum = NA_real_,
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

  # Comb-awareness (2026-09-14): estimate the identity-per-mismatch quantum
  # and smooth over it BEFORE anything else is computed, so the 1-component
  # fit, the 2-component fit, and the valley check all see the same,
  # consistently-smoothed data. `x_fit` degrades to `x` unchanged whenever
  # no quantum is found (continuous data) -- see .estimate_score_quantum()'s
  # own docs for exactly when that happens.
  quantum <- .estimate_score_quantum(x, max_unique_frac = quantum_max_unique_frac)
  out$quantum <- quantum
  x_fit <- .smooth_comb(x, quantum)

  m1 <- mean(x_fit)
  s1 <- stats::sd(x_fit)
  if (!is.finite(s1) || s1 <= 0) {
    out$explanation <- "no variance in the input (every finite value is identical)."
    return(out)
  }

  ll1 <- sum(stats::dnorm(x_fit, m1, s1, log = TRUE))
  k1 <- 2L
  bic1 <- -2 * ll1 + k1 * log(n)
  out$bic_1 <- bic1

  fit2 <- tryCatch(
    .fit_two_component_normal(x_fit),
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
  min_weight <- min(fit2$weights)

  out$bic_2 <- bic2
  out$delta_bic <- delta_bic
  out$weights <- fit2$weights
  out$means <- fit2$means
  out$sds <- fit2$sds

  # Separation requirement, scaled by the quantum when one was found (2026-
  # 09-14 fix requirement 4) -- see @param quanta_separation_multiplier.
  effective_min_separation <- if (!is.na(quantum)) {
    max(min_separation, quanta_separation_multiplier * quantum)
  } else {
    min_separation
  }

  has_valley <- .mixture_has_valley(fit2$weights, fit2$means, fit2$sds)
  out$flag <- isTRUE(delta_bic > delta_bic_threshold) &&
    isTRUE(sep > effective_min_separation) &&
    isTRUE(has_valley) &&
    isTRUE(min_weight >= min_minority_weight)
  if (!out$flag) {
    out$explanation <- sprintf(
      paste0(
        "two-component fit available (delta_bic=%.2f, mean separation=%.3f, ",
        "density has a genuine dip between the two means=%s, minority weight=%.3f, ",
        "quantum=%s) but did not clear all four thresholds (delta_bic > %d, ",
        "separation > %.3f%s, a real antimode, and minority weight >= %.2f -- a fit ",
        "that only satisfies some of these is the classic false-positive signature of ",
        "either a skewed-but-genuinely-unimodal distribution or a quantized 'comb' of ",
        "discrete score values, not a real two-mode mixture)."
      ),
      delta_bic, sep, has_valley, min_weight,
      if (is.na(quantum)) "NA (no comb detected)" else sprintf("%.4f", quantum),
      delta_bic_threshold, effective_min_separation,
      if (!is.na(quantum)) sprintf(" (%.1f quanta)", quanta_separation_multiplier) else "",
      min_minority_weight
    )
  }

  out
}
