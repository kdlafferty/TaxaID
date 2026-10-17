# compute_posterior.R
# TaxaAssign package

#' Compute Bayesian Posterior Probabilities
#'
#' Performs the Bayesian update: Posterior ~ Likelihood * Prior.
#' Adds posterior columns to the input dataframe and returns it with all existing
#' columns (e.g., taxon name, hypothesis type, rank) preserved. The output can
#' have fewer rows than the input: named unreferenced rows with a negligible
#' posterior are pooled into their ring row (see "Pooled unreferenced rows").
#'
#' Two computation paths are available:
#' - **Point estimate path** (fast): uses `score_likelihood` and `prior_mean`
#'   directly. Always computed.
#' - **Monte Carlo path** (robust): samples from prior and likelihood distributions,
#'   propagating uncertainty into the posterior. Likelihoods are sampled from
#'   Normal(mean, sd) truncated at 0 (via exact inverse-CDF sampling, not a
#'   post-hoc clamp -- a clamp would manufacture a spurious point mass at exactly 0
#'   that is not part of the modelled distribution). Priors are sampled from
#'   Beta(alpha, beta) when `prior_alpha` and `prior_beta` columns are present,
#'   correctly bounded on \[0, 1\].
#'   **Exception:** when `prior_alpha <= 1` the Beta distribution has its mode at
#'   (or density strictly decreasing from) 0 and simulation draws are unreliable --
#'   species with tiny but non-zero prior_mean would almost always lose to species
#'   with a well-concentrated prior at a lower mean. For these rows, the prior is
#'   treated as fixed at `prior_mean` in simulation rather than sampled, making the
#'   simulation consistent with the point-estimate path. (This covers
#'   `prior_alpha == 1` exactly, a real, common case, e.g.
#'   `TaxaExpect::generate_undetected_diversity()`'s global floor
#'   `Beta(1, N_total - 1)`.)
#'   Only runs when `n_sims > 0` AND at least one source of uncertainty exists
#'   (non-zero `score_likelihood_sd`, or `prior_alpha`/`prior_beta` columns present).
#'
#' \strong{Why truncated Normal, not the true generative distribution:} this
#' function only receives `score_likelihood_mean`/`score_likelihood_sd` --
#' already-summarized fitted values, not the raw match scores or the model
#' that produced them (e.g. `TaxaLikely::train_likelihood_model()`'s
#' `score_transform`), and `likelihood_w_prior` may come from a non-TaxaLikely
#' source (e.g. `assign_taxa_llm()`'s LLM-derived likelihood proxy). Treating
#' the summary as approximately Normal, truncated only at 0 (no upper
#' truncation, since `score_likelihood` need not sum to 1 across candidates
#' before `normalize_vec()` runs), is a documented approximation, not a claim
#' that match scores are truly Gaussian.
#'
#' \strong{The truncated mean can differ substantially from `mu`:} when
#' `sigma` is large relative to `mu` (e.g. `mu = 0.001`, `sigma = 2`), the
#' truncated mean is pulled well above `mu` (`~1.60` for that pair), per
#' \eqn{E[X \mid X > 0] = \mu + \sigma \cdot \phi(\alpha) / (1 - \Phi(\alpha))},
#' \eqn{\alpha = -\mu/\sigma}. This is the intended behavior of truncation, not
#' a bug, but it means a hypothesis with a small `mu` and large `sigma` is not
#' "mostly sampled near `mu`"; a substantial share of its simulated draws can
#' be far above it.
#'
#' Within each `observation_id`, likelihoods and posteriors are normalized to sum to 1
#' across all competing hypotheses.
#'
#' @param likelihood_w_prior Dataframe. One row per hypothesis per observation.
#'   Must contain columns: `observation_id`, `score_likelihood`, `score_likelihood_mean`,
#'   `score_likelihood_sd`, `prior_mean`.
#'   Optional columns: `prior_alpha` and `prior_beta` (Beta distribution parameters).
#'   When present, Monte Carlo simulation samples priors from Beta(alpha, beta).
#'   When absent, priors are treated as fixed (no prior uncertainty). Not
#'   required unconditionally because a caller can have a genuinely fixed,
#'   non-probabilistic prior with no natural concentration parameter -- e.g.
#'   [assign_taxa_llm()]'s `prior_phi = NULL` disables Beta sampling entirely
#'   when the LLM's per-taxon confidence isn't being modelled as data volume.
#'   All other real callers in this ecosystem (`join_priors()`-derived
#'   TaxaExpect priors) always supply both columns.
#' @param n_sims Integer. Number of Monte Carlo simulations. Default 1000.
#'   Set to 0 to skip simulation and return point estimates only.
#'
#' @return The input dataframe with four new columns added, possibly with fewer
#'   rows (pooled rows are removed):
#'   - `posterior_point_est`: deterministic posterior from point estimates
#'   - `posterior_mean`: mean posterior across Monte Carlo simulations
#'   - `posterior_sd`: SD of posterior across Monte Carlo simulations
#'   - `confidence_score`: fraction of simulations in which this hypothesis won
#'
#'   When rows were pooled, three more columns: `pooled_n` (integer),
#'   `pooled_prior_mass` (numeric) and `pooled_taxa` (character, names joined
#'   by `"; "`). They are `NA` on rows that are not rings; a ring that pooled
#'   nothing has `pooled_n` 0, `pooled_prior_mass` 0 and `pooled_taxa` `NA`.
#'   The attribute `pooled_rows` is a data frame (`observation_id`,
#'   `ring_taxon`, `taxon_name`, `prior_mean`, `posterior_point_est`) of every
#'   pooled row, and `pooled_min_posterior` is the threshold used (0.05); both
#'   are present, the first with zero rows, when nothing was pooled.
#'
#' @section Pooled unreferenced rows:
#' A \emph{named} row is a species-rank row of hypothesis type
#' \code{"unreferenced_species"} or \code{"unreferenced_genus"}: a local
#' species with no reference for the marker, carrying the likelihood of its
#' \emph{ring} (the generic \code{"unreferenced_*"} row above species whose
#' scope contains it) and its own prior. Before simulation, within each
#' observation, a named row whose point posterior is below 0.05 is removed and
#' its prior mass is added to its ring row. The ring is the row named by
#' \code{unreferenced_scope} (with \code{unreferenced_scope_rank}) when those
#' columns exist; otherwise the \code{"unreferenced_species"} ring of the
#' row's genus, or the \code{"unreferenced_genus"} ring of its family. A named
#' row with no such ring row, a different likelihood from its ring's (beyond
#' 1e-12), or a presence-mixture prior is kept, and a ring with a presence
#' mixture takes none.
#'
#' Because a pooled row and its ring share one likelihood, the ring's point
#' posterior after pooling is exactly the sum of its own and the pooled rows'
#' point posteriors before, and no other row's changes; this is checked
#' internally (to 1e-12). The ring's \code{prior_alpha} and \code{prior_beta}
#' are moment-matched to the summed mean and the summed Beta variances
#' (independence assumed).
#'
#' Second pass: where the ring is coarser than genus, the pooled candidates
#' are grouped by genus, and a genus whose pooled rows' posteriors sum to 0.05
#' or more keeps all of them unpooled, since a node below the ring could then
#' be called. The members of each ring are in \code{pooled_taxa}, and every
#' pooled row is in \code{attr(, "pooled_rows")}. A table that already holds
#' \code{pooled_*} columns accumulates onto them. A consumer that reads the
#' output with a \code{min_posterior} below 0.05 sees the pooled rows only
#' through their ring ([posterior_consensus()] warns).
#'
#' @details
#' \strong{Bayesian framework:}
#' Each query (\code{observation_id}) has multiple competing hypotheses (candidate
#' taxa). The posterior probability for hypothesis \eqn{i} is:
#' \deqn{P(H_i | data) = \frac{L(data | H_i) \times \pi(H_i)}{\sum_j L(data | H_j) \times \pi(H_j)}}
#' where \eqn{L} is the likelihood (from TaxaLikely or score-based proxy) and
#' \eqn{\pi} is the prior (from TaxaExpect or LLM-based estimation).
#'
#' \strong{Presence-mixture priors:}
#' rows carrying non-NA \code{prior_mix_w}/\code{prior_mix_theta_present}/
#' \code{prior_mix_theta_absent} (emitted by
#' \code{TaxaExpect::apply_undetected_evidence()} for evidence-elevated
#' species) are presence mixtures: with probability \code{prior_mix_w} the
#' species is locally present (theta at the ceiling-anchor state), otherwise
#' explicitly (\code{z ~ Bernoulli(w)}; \code{theta = z*theta_present +
#' (1-z)*theta_absent}) instead of sampling their J-shaped Beta summary, which
#' the \code{prior_alpha <= 1} guard would pin at its mean and so erase the
#' bimodality the mixture expresses. \code{posterior_mean} therefore
#' integrates over presence states, and \code{confidence_score} reads as the
#' fraction of presence states in which the hypothesis wins. The
#' point-estimate path is unchanged: \code{prior_mean} equals the mixture's
#' exact expectation by construction. Non-mixture rows are unaffected.
#'
#' \strong{Closed-genus placeholders (weight moved, not removed):}
#' a row marked \code{constraint_applied == "census_closed_genus_relabeled"}
#' by \code{TaxaLikely::apply_coverage_constraints(constraint_behavior =
#' "relabel")} is the "unsequenced congener" hypothesis of a genus whose
#' every species is referenced, so it stands for nothing: what the sequence
#' attributes to it belongs to the genus's sequenced members. After the
#' posterior is formed, such a row's posterior is passed to the
#' \code{"specific_candidate"} rows of the same observation and genus, in
#' proportion to their own posteriors (all of it to the one species of a
#' monotypic genus), and the placeholder's posterior is set to 0. The genus
#' keeps exactly the mass it had; only its split among the referenced
#' species changes. This is done per simulation on the Monte Carlo path as
#' well, so \code{posterior_mean}, \code{posterior_sd} and
#' \code{confidence_score} agree with the point estimate. The genus is read
#' from a \code{genus} column when present, else from the placeholder's own
#' name and the first word of each candidate's binomial. A placeholder
#' whose observation holds no referenced member of its genus keeps its
#' both cases.
#'
#' \strong{Prior uncertainty (Beta distribution):}
#' When \code{prior_alpha} and \code{prior_beta} columns are present, the prior
#' for each hypothesis is modelled as \eqn{Beta(\alpha, \beta)} rather than a
#' fixed point. The concentration \eqn{\phi = \alpha + \beta} controls how
#' tightly the prior is held: large \eqn{\phi} (e.g., 50) means high confidence
#' in the prior estimate; small \eqn{\phi} (e.g., 3) means the prior is
#' diffuse. Monte Carlo simulation samples from this Beta distribution to
#' propagate prior uncertainty into the posterior.
#'
#' \strong{hypothesis_type values (inherited from input):}
#' \itemize{
#'   \item \code{"specific_candidate"} -- referenced species with a direct match.
#'   \item \code{"unreferenced_species"} -- species absent from the reference DB
#'     but plausible at this location (from TaxaLikely H2 or LLM suggestion).
#'   \item \code{"unreferenced_genus"} -- genus absent from the reference DB
#'     (from TaxaLikely H3).
#'   \item \code{"unknown_species"} -- catch-all for uncharacterised diversity
#'     (from \code{assign_taxa_llm()}).
#'   \item \code{"unresolved_species"} -- the placeholder of a fully-sampled
#'     genus (from \code{apply_coverage_constraints()}); its posterior is
#'     passed to the genus's referenced members, see above.
#' }
#'
#' @examples
#' likelihood_w_prior <- data.frame(
#'   observation_id = c("S1", "S1", "S1"),
#'   taxon_name = c("Gadus morhua", "Gadus chalcogrammus", "Gadus"),
#'   score_likelihood = c(0.85, 0.30, 0.10),
#'   score_likelihood_mean = c(0.83, 0.31, 0.10),
#'   score_likelihood_sd = c(0.05, 0.04, 0.02),
#'   prior_mean = c(0.60, 0.30, 0.10),
#'   prior_alpha = c(30, 15, 5),
#'   prior_beta = c(20, 35, 45)
#' )
#' result <- compute_posterior(likelihood_w_prior, n_sims = 200)
#' result[, c("observation_id", "taxon_name", "posterior_mean")]
#'
#' @importFrom rlang .data
#' @importFrom stats rbeta sd
#'
#' @export
compute_posterior <- function(likelihood_w_prior, n_sims = 1000) {
  .compute_posterior_impl(likelihood_w_prior, n_sims = n_sims, pool = TRUE)
}

# The body of compute_posterior(). `pool = FALSE` skips the pooling of named
# unreferenced rows; kept only so tests can compare the two paths.
#' @noRd
.compute_posterior_impl <- function(likelihood_w_prior, n_sims = 1000, pool = TRUE) {
  # --- Input validation ---
  required_cols <- c(
    "observation_id", "score_likelihood", "score_likelihood_mean",
    "score_likelihood_sd", "prior_mean"
  )
  missing_cols <- setdiff(required_cols, names(likelihood_w_prior))
  if (length(missing_cols) > 0) {
    cli::cli_abort(
      "Input dataframe is missing required column(s): {.field {missing_cols}}"
    )
  }

  # --- Detect prior uncertainty mode ---
  has_alpha <- "prior_alpha" %in% names(likelihood_w_prior)
  has_beta <- "prior_beta" %in% names(likelihood_w_prior)

  if (has_alpha != has_beta) {
    cli::cli_abort(
      "Both {.field prior_alpha} and {.field prior_beta} must be present, or neither."
    )
  }

  use_beta_prior <- has_alpha && has_beta

  if (use_beta_prior) {
    # Validate alpha/beta values
    bad_alpha <- !is.finite(likelihood_w_prior$prior_alpha) |
      likelihood_w_prior$prior_alpha <= 0
    bad_beta <- !is.finite(likelihood_w_prior$prior_beta) |
      likelihood_w_prior$prior_beta <= 0
    n_bad <- sum(bad_alpha | bad_beta)
    if (n_bad > 0) {
      cli::cli_abort(
        "{n_bad} row(s) have non-positive or non-finite {.field prior_alpha}/{.field prior_beta}. All values must be > 0."
      )
    }
  } else {
    cli::cli_inform(
      "No {.field prior_alpha}/{.field prior_beta} columns found. Treating priors as fixed (no prior uncertainty)."
    )
  }

  # Replace any NA likelihood SDs with 0 and warn the user
  na_lik_sd <- sum(is.na(likelihood_w_prior$score_likelihood_sd))
  if (na_lik_sd > 0) {
    cli::cli_warn("{na_lik_sd} NA value(s) in {.field score_likelihood_sd} replaced with 0.")
    likelihood_w_prior$score_likelihood_sd[is.na(likelihood_w_prior$score_likelihood_sd)] <- 0
  }

  # --- Pool named unreferenced rows into their ring ----------------------
  pooled_info <- NULL
  if (pool && !dplyr::is_grouped_df(likelihood_w_prior)) {
    pl <- .pool_unreferenced_rows(likelihood_w_prior, use_beta_prior)
    pooled_info <- pl$pooled
    if (nrow(pooled_info) > 0L) {
      likelihood_w_prior <- pl$df
      pool_floor <- .POOL_MIN_POSTERIOR
      cli::cli_inform(
        "Pooled {nrow(pooled_info)} named unreferenced row(s) (point posterior below \
        {pool_floor}) into their ring rows."
      )
    }
  }

  # --- Detect presence-mixture rows -------------------------------------
  # Rows carrying prior_mix_w / prior_mix_theta_present / prior_mix_theta_absent
  # (from TaxaExpect::apply_undetected_evidence()) are presence MIXTURES: with
  # probability w the species is locally present (theta at the ceiling-anchor
  # state), otherwise absent (theta at the floor). Their Beta alpha/beta summary
  # is J-shaped by construction (alpha << 1), which is exactly the shape the
  # guard below pins at the mean -- Beta shape is a bad carrier for bimodality.
  # In simulation these rows instead draw presence explicitly:
  #   z ~ Bernoulli(w);  theta = z * theta_present + (1 - z) * theta_absent
  # so posterior_mean integrates over presence states and confidence_score
  # reads as "fraction of presence states in which this hypothesis wins."
  # The point-estimate path needs no change: prior_mean equals the mixture's
  # exact expectation by construction.
  mix_cols <- c("prior_mix_w", "prior_mix_theta_present", "prior_mix_theta_absent")
  has_mix_cols <- all(mix_cols %in% names(likelihood_w_prior))
  if (has_mix_cols) {
    is_mix_row <- !is.na(likelihood_w_prior$prior_mix_w) &
      !is.na(likelihood_w_prior$prior_mix_theta_present) &
      !is.na(likelihood_w_prior$prior_mix_theta_absent)
    bad_mix <- is_mix_row &
      (likelihood_w_prior$prior_mix_w < 0 | likelihood_w_prior$prior_mix_w > 1)
    if (any(bad_mix)) {
      cli::cli_abort(
        "{sum(bad_mix)} row(s) have {.field prior_mix_w} outside [0, 1]."
      )
    }
  } else {
    is_mix_row <- rep(FALSE, nrow(likelihood_w_prior))
  }
  any_mix <- any(is_mix_row)

  # Decide whether MC simulation will add any information
  any_lik_uncertainty <- any(likelihood_w_prior$score_likelihood_sd > 0)
  any_prior_uncertainty <- use_beta_prior || any_mix
  run_sims <- n_sims > 0 && (any_lik_uncertainty || any_prior_uncertainty)

  if (n_sims > 0 && !run_sims) {
    cli::cli_inform(
      "No uncertainty to propagate. Skipping Monte Carlo simulation and returning point estimates only."
    )
  }

  # --- Helper: normalize a vector to sum to 1 ---
  # If all values are 0, return uniform distribution (avoids division by zero)
  normalize_vec <- function(x) {
    s <- sum(x, na.rm = TRUE)
    if (s == 0) {
      return(rep(1 / length(x), length(x)))
    }
    x / s
  }

  # --- Helper: sample from Normal(mean, sd) truncated to [0, Inf) ---
  # Exact inverse-CDF truncated-normal sampling avoids manufacturing a
  # spurious point mass at exactly 0 that is not present in the modelled
  # distribution, which a naive rnorm() + clamp-negative-to-0 approach would
  # do. `mean`/`sd` are recycled to length `n`, matching rnorm()'s own
  # recycling behavior. sd == 0
  # is deterministic, matching rnorm(sd = 0) returning `mean` exactly.
  # `stdev` (not `sigma`) -- `stats::sigma()` is a real generic (residual SD
  # extractor for fitted models); a same-named local parameter is harmless
  # here since the body never calls the generic, but avoiding the collision
  # entirely removes any chance of confusion for a future reader/editor.
  rtruncnorm_at_zero <- function(n, mu, stdev) {
    mu <- rep_len(mu, n)
    stdev <- rep_len(stdev, n)
    out <- mu
    pos_sd <- stdev > 0
    if (any(pos_sd)) {
      # Clamp away from exactly 1 to avoid qnorm(1) = Inf for extreme
      # negative-mean/small-sd combinations (probability mass below 0
      # effectively 1 in double precision).
      lower_p <- pmin(stats::pnorm(0, mu[pos_sd], stdev[pos_sd]), 1 - 1e-12)
      u <- stats::runif(sum(pos_sd), min = lower_p, max = 1)
      out[pos_sd] <- stats::qnorm(u, mu[pos_sd], stdev[pos_sd])
    }
    out
  }

  # --- Process each observation_id group ---
  cli::cli_inform("Computing posteriors for {dplyr::n_distinct(likelihood_w_prior$observation_id)} observation(s)...")

  # Each observation's rows by index, in group_split()'s group order (and each
  # group's original row order), so the random draws are made in exactly the
  # same sequence. Results go into preallocated vectors and the output is ONE
  # row-slice of the input, instead of holding the split list, the per-chunk
  # results and their bind_rows() at once (several full-width copies of the
  # table). The output is identical: the same tibble that bind_rows() of the
  # split chunks gave, before the same arrange().
  n_tot <- nrow(likelihood_w_prior)
  if (n_tot == 0L) {
    out <- dplyr::bind_rows(list()) |>
      dplyr::arrange(.data$observation_id, dplyr::desc(.data$posterior_mean))
    attr(out, "report_params") <- list(n_sims = n_sims)
    return(out)
  }
  grp_rows <- if (dplyr::is_grouped_df(likelihood_w_prior)) {
    # The earlier group_split(.data$observation_id) on a grouped input
    # ignored observation_id, said so in a warning, and split by the
    # EXISTING groups. Kept as it was here (this rewrite changes no output);
    # whether to fix it is a separate decision.
    invisible(dplyr::group_split(likelihood_w_prior[0L, ], .data$observation_id))
    dplyr::group_rows(likelihood_w_prior)
  } else {
    dplyr::group_rows(dplyr::group_by(likelihood_w_prior, .data$observation_id))
  }
  obs_col <- likelihood_w_prior$observation_id
  s_lik <- likelihood_w_prior$score_likelihood
  s_mean <- likelihood_w_prior$score_likelihood_mean
  s_sd <- likelihood_w_prior$score_likelihood_sd
  p_mean <- likelihood_w_prior$prior_mean
  p_alpha <- if (use_beta_prior) likelihood_w_prior$prior_alpha else NULL
  p_beta <- if (use_beta_prior) likelihood_w_prior$prior_beta else NULL
  if (has_mix_cols) {
    m_w <- likelihood_w_prior$prior_mix_w
    m_tp <- likelihood_w_prior$prior_mix_theta_present
    m_ta <- likelihood_w_prior$prior_mix_theta_absent
  }
  # --- Closed-genus placeholders: weight is MOVED into the genus -----------
  # A row apply_coverage_constraints("relabel") marked stands for an
  # unsequenced congener a complete census says does not exist. Its posterior
  # (point estimate, and every simulation) goes to the referenced species of
  # the same observation and genus in proportion to their own posteriors, so
  # the genus node keeps its mass and only the split changes. Done on the
  # posterior rather than the likelihood because zeroing the likelihood and
  # renormalising hands the share to every other hypothesis in the
  # observation, outside the genus too.
  closed <- if ("constraint_applied" %in% names(likelihood_w_prior)) {
    likelihood_w_prior$constraint_applied %in% "census_closed_genus_relabeled"
  } else {
    rep(FALSE, n_tot)
  }
  any_closed <- any(closed)
  n_moved <- 0L
  n_kept <- 0L
  if (any_closed) {
    tn <- if ("taxon_name" %in% names(likelihood_w_prior)) {
      as.character(likelihood_w_prior$taxon_name)
    } else {
      rep(NA_character_, n_tot)
    }
    gen <- if ("genus" %in% names(likelihood_w_prior)) {
      as.character(likelihood_w_prior$genus)
    } else {
      rep(NA_character_, n_tot)
    }
    # The placeholder is named by its genus; a candidate's binomial carries
    # the genus as its first word.
    fallback <- ifelse(closed, tn, sub("\\s.*$", "", tn))
    gen <- ifelse(is.na(gen) | !nzchar(gen), fallback, gen)
    recip <- !closed & (
      if ("hypothesis_type" %in% names(likelihood_w_prior)) {
        likelihood_w_prior$hypothesis_type %in% "specific_candidate"
      } else {
        rep(FALSE, n_tot)
      })
  }
  # P: posteriors of one observation's rows, one column per simulation (the
  # point estimate is a one-column matrix). Returns P with every closed row's
  # mass moved onto its genus's referenced rows, column by column.
  move_closed <- function(P, i) {
    for (c in which(closed[i])) {
      r <- which(recip[i] & !is.na(gen[i]) & gen[i] == gen[i][c])
      if (length(r) == 0L) {
        n_kept <<- n_kept + 1L
        next
      }
      share <- P[r, , drop = FALSE]
      cs <- colSums(share)
      w <- sweep(share, 2, ifelse(cs > 0, cs, 1), "/")
      if (any(cs == 0)) w[, cs == 0] <- 1 / length(r)
      P[r, ] <- share + sweep(w, 2, P[c, ], "*")
      P[c, ] <- 0
      n_moved <<- n_moved + 1L
    }
    P
  }

  v_pt <- v_mean <- v_sd <- v_conf <- numeric(n_tot)
  pos <- 0L
  for (gi in seq_along(grp_rows)) {
    i <- grp_rows[[gi]]
    n_rows <- length(i)
    k <- pos + seq_len(n_rows)
    pos <- pos + n_rows

    # --- Point estimate path ---
    # Normalize likelihoods first, then multiply by prior, then normalize again
    norm_lik <- normalize_vec(s_lik[i])
    raw_post <- norm_lik * p_mean[i]
    pt <- normalize_vec(raw_post)
    if (any_closed && any(closed[i])) {
      pt <- as.vector(move_closed(matrix(pt, ncol = 1L), i))
    }
    v_pt[k] <- pt

    # --- Monte Carlo path ---
    if (run_sims) {
      # Sample likelihoods: Normal(mean, sd) truncated at 0 (exact
      # inverse-CDF sampling, not a post-hoc clamp; see
      # rtruncnorm_at_zero() above for why a clamp would be a real bug).
      sim_lik <- matrix(
        rtruncnorm_at_zero(n_rows * n_sims, s_mean[i], s_sd[i]),
        nrow = n_rows
      )

      # Sample priors: Beta(alpha, beta) -- bounded [0, 1] by construction.
      # When prior_alpha <= 1 the Beta's density is at its maximum at (or
      # strictly decreasing from) 0, making simulation draws unreliable: a
      # species with prior_mean = 3e-4 almost never beats one with
      # prior_mean = 6e-6 because its draws are almost always near 0. This
      # arises when theta is tiny (e.g. 0.034%) and the model has high
      # uncertainty (phi = alpha + beta is small).
      # Fix: treat these rows as fixed at prior_mean in simulation. This
      # threshold covers `prior_alpha == 1` exactly (e.g. TaxaExpect's
      # global-floor Beta(1, N_total - 1)), which has the same "always
      # decreasing away from 0" density shape. See compute_posterior()'s
      # roxygen for the still-open question of whether this boundary
      # should extend further.
      if (use_beta_prior) {
        sim_prior <- matrix(
          rbeta(n_rows * n_sims,
            shape1 = p_alpha[i],
            shape2 = p_beta[i]
          ),
          nrow = n_rows
        )
        j_shaped <- p_alpha[i] <= 1
        if (any(j_shaped)) {
          sim_prior[j_shaped, ] <- p_mean[i][j_shaped]
        }
      } else {
        # Fixed priors: replicate prior_mean across all simulations
        sim_prior <- matrix(
          rep(p_mean[i], n_sims),
          nrow = n_rows
        )
      }

      # Presence-mixture rows: explicit Bernoulli presence
      # draw overrides the Beta/J-guard handling above for exactly these
      # rows -- their alpha/beta summary is J-shaped by construction, so the
      # guard would otherwise pin them at the mean and erase the bimodality
      # the mixture exists to express. Vector-over-matrix recycling below is
      # column-major, matching the n_mix-row layout.
      if (has_mix_cols) {
        chunk_mix <- !is.na(m_w[i]) & !is.na(m_tp[i]) & !is.na(m_ta[i])
        if (any(chunk_mix)) {
          n_mix <- sum(chunk_mix)
          z <- matrix(stats::runif(n_mix * n_sims), nrow = n_mix) <
            m_w[i][chunk_mix]
          sim_prior[chunk_mix, ] <- m_ta[i][chunk_mix] +
            z * (m_tp[i][chunk_mix] - m_ta[i][chunk_mix])
        }
      }

      # Normalize likelihoods within each simulation (column = one simulation).
      # When all likelihoods in a simulation are 0, assign uniform weights so
      # the posterior falls back to the prior -- matching normalize_vec() in the
      # point-estimate path.
      col_sums_lik <- colSums(sim_lik)
      all_zero_cols <- col_sums_lik == 0
      n_zero_cols <- sum(all_zero_cols)
      if (n_zero_cols > 0L) {
        cli::cli_warn(
          "{n_zero_cols} of {n_sims} simulation(s) for observation_id \\
          {.val {obs_col[i][1L]}} had all-zero likelihoods; using \\
          uniform fallback for those simulations."
        )
      }
      sim_lik_norm <- sweep(
        sim_lik, 2,
        ifelse(all_zero_cols, 1, col_sums_lik), "/"
      )
      sim_lik_norm[, all_zero_cols] <- 1 / n_rows

      # Bayesian update: normalized likelihood * prior
      sim_raw <- sim_lik_norm * sim_prior

      # Normalize posterior within each simulation.
      # When a simulation draws zero prior for every hypothesis,
      # assign uniform weight so the failed simulation is uninformative.
      col_sums_post <- colSums(sim_raw)
      zero_post_cols <- col_sums_post == 0
      col_sums_post[zero_post_cols] <- 1
      sim_probs <- sweep(sim_raw, 2, col_sums_post, "/")
      sim_probs[, zero_post_cols] <- 1 / n_rows

      # Closed-genus placeholders: the same move, simulation by simulation,
      # so the Monte Carlo summaries agree with the point estimate.
      if (any_closed && any(closed[i])) {
        sim_probs <- move_closed(sim_probs, i)
      }

      # Summarize across simulations
      v_mean[k] <- rowMeans(sim_probs)
      v_sd[k] <- apply(sim_probs, 1, sd)

      # Confidence score: fraction of MC simulations in which this hypothesis
      # had the highest posterior. Complements posterior_mean: a hypothesis can
      # have a high mean posterior but low confidence_score if another hypothesis
      # frequently wins. Analogous to the "posterior probability of being the
      # best hypothesis" in decision theory.
      winners <- apply(sim_probs, 2, which.max)
      win_counts <- table(factor(winners, levels = 1:n_rows))
      v_conf[k] <- as.numeric(win_counts) / n_sims
    } else {
      # No simulation: MC outputs mirror point estimate
      v_mean[k] <- pt
      v_sd[k] <- 0
      v_conf[k] <- as.numeric(pt == max(pt))
    }
  }

  if (any_closed) {
    cli::cli_inform(
      "{n_moved} closed-genus placeholder row(s) passed their posterior to \\
      the genus's referenced species; {n_kept} with no referenced member of \\
      the genus in the observation kept it."
    )
  }

  # Return full dataframe sorted by observation_id, then best hypothesis first
  out <- dplyr::dplyr_row_slice(dplyr::as_tibble(dplyr::ungroup(likelihood_w_prior)), unlist(grp_rows, use.names = FALSE))
  # bind_rows() of the split chunks kept no custom attribute of the input
  attributes(out) <- attributes(out)[c("names", "row.names", "class")]
  out$posterior_point_est <- v_pt
  out$posterior_mean <- v_mean
  out$posterior_sd <- v_sd
  out$confidence_score <- v_conf
  out <- dplyr::arrange(out, .data$observation_id, dplyr::desc(.data$posterior_mean))

  attr(out, "report_params") <- list(n_sims = n_sims)
  if (!is.null(pooled_info)) {
    attr(out, "pooled_rows") <- pooled_info
    attr(out, "pooled_min_posterior") <- .POOL_MIN_POSTERIOR
  }
  out
}
