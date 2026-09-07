utils::globalVariables(c(
  "observation_id", "taxon_name", "taxon_name_rank", "grid_id", "main_habitat",
  "prior_alpha", "prior_beta", "prior_mean"
))

# ==============================================================================
# Internal helper: combine one (observation_id, taxon_name, taxon_name_rank)
# candidate's per-site prior rows into one
# ==============================================================================

# .combine_one_multisite_group()
#
# Precision-weighted combination in logit space. logit(Beta(a,b)) has EXACT
# mean = digamma(a) - digamma(b) and variance = trigamma(a) + trigamma(b) (via
# the Gamma-ratio representation of a Beta variate: logit(X) = log(Y1) -
# log(Y2) for Y1 ~ Gamma(a,1), Y2 ~ Gamma(b,1), and log(Gamma(a,1)) has mean
# digamma(a), variance trigamma(a)). Weighting each site's logit mean by the
# inverse of its logit variance is the standard fixed-effect combination for
# estimates of differing precision -- a sparse/uncertain site (small alpha +
# beta, large logit variance) is discounted relative to a well-supported one,
# rather than counted at face value.
#
# The combined Beta's own concentration (phi = alpha + beta) is derived from
# the combined logit variance via the standard large-phi delta-method
# approximation Var(logit(Beta(m*phi, (1-m)*phi))) ~= 1 / (phi * m * (1-m)),
# solved for phi. This ties the output's uncertainty to the pooled precision
# of all combined sites (more/better sites -> tighter combined Beta), so
# compute_posterior()'s existing Beta-sampling Monte Carlo path reflects the
# combination's confidence with no changes needed there.
#' @noRd
.combine_one_multisite_group <- function(rows) {
  n <- nrow(rows)
  if (n == 1L) {
    rows$n_sites_combined <- 1L
    rows$combined_sites   <- NA_character_
    return(rows)
  }

  logit_mean <- digamma(rows$prior_alpha) - digamma(rows$prior_beta)
  logit_var  <- trigamma(rows$prior_alpha) + trigamma(rows$prior_beta)
  w          <- 1 / logit_var

  logit_combined <- sum(logit_mean * w) / sum(w)
  var_combined   <- 1 / sum(w)
  mean_combined  <- stats::plogis(logit_combined)

  phi_combined <- 1 / (var_combined * mean_combined * (1 - mean_combined))

  template <- rows[1L, , drop = FALSE]
  template$prior_alpha     <- mean_combined * phi_combined
  template$prior_beta      <- (1 - mean_combined) * phi_combined
  template$prior_mean      <- mean_combined
  template$grid_id         <- NA_character_
  template$main_habitat    <- NA_character_
  template$n_sites_combined <- n
  template$combined_sites   <- paste(sort(unique(rows$grid_id)), collapse = "|")

  template
}

#' Combine Per-Site Priors for Multi-Site Observations
#'
#' Bridges [join_priors()] (Session 138: now site-preserving, i.e. one row per
#' `observation_id` x `taxon_name` x `taxon_name_rank` x `grid_id` x
#' `main_habitat`) to [compute_posterior()], which expects exactly one row per
#' candidate hypothesis per observation. When the same `observation_id` was
#' detected at more than one site (e.g. the same eDNA ASV recovered from reads
#' at two different sample sites), each candidate taxon otherwise arrives with
#' one prior row per site. This function combines those rows into one.
#'
#' ## Why this function exists
#' Before Session 138, `join_priors()`'s final deduplication step
#' (`distinct(observation_id, taxon_name, taxon_name_rank, .keep_all = TRUE)`)
#' silently kept only the highest-`prior_mean` site per candidate -- each
#' candidate ended up matched to *its own* most favorable site rather than the
#' site it was actually detected at, which could turn a confident, correct
#' call into a nonsensical tie. `join_priors()` now preserves one row per site
#' (its `distinct()` call additionally keys on `grid_id`/`main_habitat`); this
#' function is the deliberate combination step that must run on that
#' site-preserving output before [compute_posterior()].
#'
#' ## Combination rule: precision-weighted, not a plain product
#' A simpler design (evaluated and rejected during Session 138 design review)
#' would multiply each candidate's per-site `prior_mean` values together and
#' renormalize. That rule treats every site's point estimate as equally
#' trustworthy regardless of how much occurrence data backs it -- a site with
#' almost no data (small `prior_alpha + prior_beta`) counts exactly as much as
#' a site with abundant, high-confidence data. A worked comparison (site A:
#' `phi = 100`, confidently favors candidate X at 0.8; site B: `phi = 5`,
#' weakly favors candidate Y at 0.6 -- i.e. sparse data giving a possibly
#' spurious signal in the *opposite* direction) showed the plain-product rule
#' gives X only 72.7% of the combined mass, and that running a full Monte
#' Carlo simulation (drawing `theta_site1 ~ Beta`, `theta_site2 ~ Beta`,
#' multiplying, renormalizing per draw) does not fix this -- it shifts weight
#' *toward* the noisier site's minority pick (69.2%), a known artifact of
#' averaging a renormalized ratio of random variables, unrelated to
#' confidence. The precision-weighted logit combination implemented here
#' gives X 78.5% -- it is the only one of the three that actually discounts
#' the low-confidence site (about 16x less weight than site A here, from the
#' ratio of their logit variances) rather than counting it at face value or
#' distorting the result in an uncontrolled direction.
#'
#' ## Ecological independence assumption
#' Combining priors multiplicatively/in log-odds across sites assumes the
#' sites are ecologically independent -- knowing the species is present at
#' site 1 tells you nothing extra about site 2 beyond the species' own
#' biology. If two "sites" are actually near-duplicate subsamples of the same
#' real location, this combination double-counts the same evidence and
#' overstates confidence. This is a judgment call for whoever builds the site
#' metadata (see [TaxaMatch::join_event_site_metadata()]'s `site_metadata`
#' table), not something this function can detect or guard against.
#'
#' @param joined Data frame, typically [join_priors()] output. Must contain
#'   `observation_id`, `taxon_name`, `taxon_name_rank`, `grid_id`,
#'   `main_habitat`, `prior_alpha`, `prior_beta`, `prior_mean` (all present in
#'   `join_priors()`'s output). Observations detected at only one site (the
#'   common case) pass through unchanged.
#'
#' @return `joined` with one row per `observation_id` x `taxon_name` x
#'   `taxon_name_rank`, plus two new columns:
#'   \describe{
#'     \item{`n_sites_combined`}{Integer. Number of per-site rows combined
#'       into this row (`1` when the candidate was detected at only one
#'       site).}
#'     \item{`combined_sites`}{Character. Pipe-delimited sorted list of the
#'       combined `grid_id` values, `NA` for single-site rows. `grid_id` and
#'       `main_habitat` themselves are set to `NA` on combined rows, since the
#'       row no longer corresponds to a single site.}
#'   }
#'   `prior_alpha`, `prior_beta`, and `prior_mean` are recomputed for combined
#'   rows; all other columns (likelihood columns, taxonomy, `hypothesis_type`,
#'   etc.) are inherited from one of the per-site rows, since they describe
#'   the same underlying detection and are identical across sites for a given
#'   candidate.
#'
#' @seealso [join_priors()], [compute_posterior()]
#'
#' @examples
#' # A candidate ("Gadus morhua") detected at two sites, plus a single-site
#' # candidate ("Gadus chalcogrammus") for the same observation.
#' joined <- data.frame(
#'   observation_id  = c("ASV_1", "ASV_1", "ASV_1"),
#'   taxon_name      = c("Gadus morhua", "Gadus morhua", "Gadus chalcogrammus"),
#'   taxon_name_rank = "species",
#'   grid_id         = c("Grid_A", "Grid_B", "Grid_A"),
#'   main_habitat    = c("Neritic", "Neritic", "Neritic"),
#'   prior_alpha     = c(80, 3, 10),
#'   prior_beta      = c(20, 2, 90),
#'   prior_mean      = c(0.80, 0.60, 0.10),
#'   stringsAsFactors = FALSE
#' )
#' combined <- combine_multisite_priors(joined)
#' combined
#'
#' \dontrun{
#' joined    <- join_priors(likelihoods, taxaexpect_priors, site = site_df)
#' combined  <- combine_multisite_priors(joined)
#' posterior <- compute_posterior(combined)
#' }
#'
#' @importFrom stats plogis
#' @importFrom dplyr group_split bind_rows arrange desc
#' @export
combine_multisite_priors <- function(joined) {

  if (!is.data.frame(joined)) {
    cli::cli_abort("{.arg joined} must be a data frame.")
  }

  # prior_mean is required, not optional: a single-site row passes through
  # untouched (it keeps whatever prior_mean it arrived with) while a combined
  # row has prior_mean recomputed, so an input lacking the column produced a
  # result where combined rows had a real prior_mean and single-site rows had
  # NA (filled in by bind_rows) -- an NA prior that compute_posterior() then
  # carries straight into the posterior. Fail loudly instead.
  required_cols <- c("observation_id", "taxon_name", "taxon_name_rank",
                     "grid_id", "main_habitat", "prior_alpha", "prior_beta",
                     "prior_mean")
  missing_cols <- setdiff(required_cols, names(joined))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "{.arg joined} is missing required column(s): {.field {missing_cols}}",
      "i" = "Pass {.fn join_priors} output -- its final {.fn distinct} call is grid_id/main_habitat-aware, preserving one row per site."
    ))
  }

  bad_ab <- !is.finite(joined$prior_alpha) | joined$prior_alpha <= 0 |
    !is.finite(joined$prior_beta)  | joined$prior_beta  <= 0
  if (any(bad_ab)) {
    cli::cli_abort(
      "{sum(bad_ab)} row(s) have non-positive or non-finite {.field prior_alpha}/{.field prior_beta}."
    )
  }

  groups <- dplyr::group_split(joined, observation_id, taxon_name, taxon_name_rank)
  group_sizes <- vapply(groups, nrow, integer(1L))

  if (all(group_sizes == 1L)) {
    joined$n_sites_combined <- 1L
    joined$combined_sites   <- NA_character_
    return(joined)
  }

  result <- groups |>
    lapply(.combine_one_multisite_group) |>
    dplyr::bind_rows()

  n_multi <- sum(group_sizes > 1L)
  cli::cli_inform(
    "combine_multisite_priors: combined {n_multi} multi-site candidate(s) via precision-weighted logit combination; {sum(group_sizes == 1L)} single-site candidate(s) passed through unchanged."
  )

  result |> dplyr::arrange(observation_id, dplyr::desc(prior_mean))
}
