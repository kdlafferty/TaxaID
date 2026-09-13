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
    rows$combined_sites <- NA_character_
    return(rows)
  }

  # Logit-space precision weighting needs every site's Beta to be
  # unimodal-ish (alpha and beta comfortably above 1): digamma/trigamma are
  # singular at 0, so a J-shaped prior (alpha << 1 -- the dark-diversity
  # floor gives alpha ~ 2e-6, an evidence-blend row ~ 6e-5) has a logit mean
  # near -1/alpha and plogis() of the combination underflows to exactly 0,
  # from which phi = Inf and alpha = 0 * Inf = NaN. Found 2026-09-12 on the
  # first real multi-site run (PtConception 12S): 349 of 4,469 candidate rows
  # -- most unreferenced-species hypotheses -- came back NaN/Inf and
  # compute_posterior() refused them. Such rows are the majority of real
  # candidates, not an edge case. The logit rule is still right whenever at
  # least one site is informative: a J-shaped site's logit weight is ~alpha^2,
  # so it is correctly ignored in favour of the site with data (a near-zero
  # floor prior is UNINFORMED, not confident -- which is exactly why the
  # probability scale, where its tiny variance would make it look precise,
  # is not used in that case). Only when EVERY site is J-shaped does the
  # logit combination underflow; then combine on the probability scale:
  # precision-weight the Beta means by the inverse of each Beta's own
  # variance m(1-m)/(phi+1) (finite and positive for any alpha, beta > 0)
  # and recover phi from the combined variance. Two identical J-shaped priors
  # combine to the same mean at twice the concentration -- the same
  # "agreement sharpens" behaviour the logit rule gives moderate priors.
  logit_mean <- digamma(rows$prior_alpha) - digamma(rows$prior_beta)
  logit_var <- trigamma(rows$prior_alpha) + trigamma(rows$prior_beta)
  w <- 1 / logit_var
  logit_combined <- sum(logit_mean * w) / sum(w)
  var_combined <- 1 / sum(w)
  mean_combined <- stats::plogis(logit_combined)
  phi_combined <- 1 / (var_combined * mean_combined * (1 - mean_combined))
  alpha_combined <- mean_combined * phi_combined
  beta_combined <- (1 - mean_combined) * phi_combined
  if (!is.finite(alpha_combined) || !is.finite(beta_combined) ||
    alpha_combined <= 0 || beta_combined <= 0) {
    phi_i <- rows$prior_alpha + rows$prior_beta
    m_i <- rows$prior_alpha / phi_i
    v_i <- m_i * (1 - m_i) / (phi_i + 1)
    w <- 1 / v_i
    mean_combined <- sum(m_i * w) / sum(w)
    var_combined <- 1 / sum(w)
    phi_combined <- mean_combined * (1 - mean_combined) / var_combined - 1
    phi_combined <- max(phi_combined, sum(phi_i))   # never LESS concentrated than the sites agree on
    alpha_combined <- mean_combined * phi_combined
    beta_combined <- (1 - mean_combined) * phi_combined
  }

  template <- rows[1L, , drop = FALSE]
  template$prior_alpha <- alpha_combined
  template$prior_beta <- beta_combined
  template$prior_mean <- mean_combined
  template$grid_id <- NA_character_
  template$main_habitat <- NA_character_
  template$n_sites_combined <- n
  template$combined_sites <- paste(sort(unique(rows$grid_id)), collapse = "|")

  # Presence-mixture guard (2026-09-13). compute_posterior()'s Monte Carlo
  # path samples presence from prior_mix_w ALONE for any row carrying the
  # mixture columns, ignoring the recombined alpha/beta. Copying the first
  # site's mixture is exact only when every site row carries the same
  # pricing (the case today: evidence is priced once per study). If the
  # sites disagree, the combined row must not carry one site's Bernoulli, so
  # the mixture columns are blanked and the recombined Beta is sampled
  # instead; the caller warns once per call.
  mix_cols <- grep("^prior_mix_", names(rows), value = TRUE)
  template$.mix_dropped <- FALSE
  if (length(mix_cols) > 0L && any(!is.na(rows$prior_mix_w))) {
    same <- nrow(unique(rows[, mix_cols, drop = FALSE])) == 1L
    if (!same) {
      template[mix_cols] <- NA
      template$.mix_dropped <- TRUE
    }
  }

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
#' ## J-shaped (alpha or beta at or below 1) priors
#' The logit-space rule assumes each site's Beta is reasonably concentrated.
#' Where any site's prior is J-shaped -- the dark-diversity floor
#' (`alpha ~ 2e-6, beta ~ 2`), a singleton mirror, or an evidence-blend row --
#' the logit moments are dominated by digamma's singularity at 0 and the
#' back-transformed mean underflows to exactly 0 (NaN alpha, Inf beta; found
#' on the first real multi-site run, 2026-09-12, on 349 of 4,469 rows). The
#' logit rule still applies whenever at least one site is informative: a
#' J-shaped site's logit weight is about `alpha^2`, so it is ignored in favour
#' of the site with data, as it should be (a floor prior is uninformed, not
#' confident). Only when EVERY site is J-shaped does the logit combination
#' underflow; those candidates are then combined on the probability scale:
#' each site's mean weighted by the inverse of its Beta variance
#' `m(1-m)/(phi+1)`, with the combined concentration recovered from the
#' combined variance (never below the sum of the sites' own concentrations).
#' Moderate priors are unaffected -- the worked numbers above still apply.
#'
#' ## Presence-mixture rows
#' A row carrying `prior_mix_w`/`prior_mix_theta_present`/
#' `prior_mix_theta_absent` (see [TaxaExpect::apply_undetected_evidence()])
#' inherits those columns from its FIRST site row; only `prior_alpha`,
#' `prior_beta` and `prior_mean` are recombined. When the per-site mixture
#' rows are copies of one evidence pricing (the usual case: evidence is priced
#' once per study) this is exact. When the rows DIFFER (site-specific
#' pricing, or sites in different habitats after
#' [TaxaExpect::condition_evidence_on_habitat()]), the mixture columns are set
#' to `NA` on the combined row and a warning names the candidates, because
#' [compute_posterior()]'s Monte Carlo path would otherwise sample presence
#' from one site's `prior_mix_w` alone while `posterior_point_est` used the
#' recombined mean (2026-09-13). The recombined Beta is sampled instead.
#' Recombining the mixture itself across sites is not implemented.
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
#'   observation_id = c("ASV_1", "ASV_1", "ASV_1"),
#'   taxon_name = c("Gadus morhua", "Gadus morhua", "Gadus chalcogrammus"),
#'   taxon_name_rank = "species",
#'   grid_id = c("Grid_A", "Grid_B", "Grid_A"),
#'   main_habitat = c("Neritic", "Neritic", "Neritic"),
#'   prior_alpha = c(80, 3, 10),
#'   prior_beta = c(20, 2, 90),
#'   prior_mean = c(0.80, 0.60, 0.10),
#'   stringsAsFactors = FALSE
#' )
#' combined <- combine_multisite_priors(joined)
#' combined
#'
#' \dontrun{
#' joined <- join_priors(likelihoods, taxaexpect_priors, site = site_df)
#' combined <- combine_multisite_priors(joined)
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
  required_cols <- c(
    "observation_id", "taxon_name", "taxon_name_rank",
    "grid_id", "main_habitat", "prior_alpha", "prior_beta",
    "prior_mean"
  )
  missing_cols <- setdiff(required_cols, names(joined))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "{.arg joined} is missing required column(s): {.field {missing_cols}}",
      "i" = "Pass {.fn join_priors} output -- its final {.fn distinct} call is grid_id/main_habitat-aware, preserving one row per site."
    ))
  }

  bad_ab <- !is.finite(joined$prior_alpha) | joined$prior_alpha <= 0 |
    !is.finite(joined$prior_beta) | joined$prior_beta <= 0
  if (any(bad_ab)) {
    cli::cli_abort(
      "{sum(bad_ab)} row(s) have non-positive or non-finite {.field prior_alpha}/{.field prior_beta}."
    )
  }

  groups <- dplyr::group_split(joined, observation_id, taxon_name, taxon_name_rank)
  group_sizes <- vapply(groups, nrow, integer(1L))

  if (all(group_sizes == 1L)) {
    joined$n_sites_combined <- 1L
    joined$combined_sites <- NA_character_
    return(joined)
  }

  result <- groups |>
    lapply(.combine_one_multisite_group) |>
    dplyr::bind_rows()

  if (".mix_dropped" %in% names(result)) {
    dropped <- result$.mix_dropped %in% TRUE
    if (any(dropped)) {
      taxa <- unique(result$taxon_name[dropped])
      cli::cli_warn(c(
        "combine_multisite_priors: {sum(dropped)} combined row(s) had presence-mixture columns that DIFFER across sites ({.val {utils::head(taxa, 5)}}{if (length(taxa) > 5) ', ...' else ''}).",
        "i" = "The mixture is not recombined across sites, so those columns were set to NA on the combined row and compute_posterior() will sample the recombined Beta prior instead of one site's presence probability."
      ))
    }
    result$.mix_dropped <- NULL
  }

  n_multi <- sum(group_sizes > 1L)
  cli::cli_inform(
    "combine_multisite_priors: combined {n_multi} multi-site candidate(s) via precision-weighted logit combination; {sum(group_sizes == 1L)} single-site candidate(s) passed through unchanged."
  )

  result |> dplyr::arrange(observation_id, dplyr::desc(prior_mean))
}
