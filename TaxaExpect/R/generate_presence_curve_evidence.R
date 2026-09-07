# Presence-curve evidence generators (unobserved-taxa redesign, 2026-08-31).
# One distance curve prices every unobserved claimant; these two generators
# emit evidence frames for the shared applier (apply_undetected_evidence),
# which under pricing = "curve" turns weight w into theta = w * theta_present.

#' Price unobserved candidates on the presence-distance curve
#'
#' @description
#' Emits an evidence frame (for [apply_undetected_evidence()]) pricing each
#' taxon's presence probability from the shared distance curve
#' \deqn{w = w_{scale} \cdot e^{-\min(d, d_{cap}) / (k \cdot d_{half})}}
#' The same curve serves three claimant classes:
#' \itemize{
#'   \item \strong{Distance clamp} (no \code{distance_km} supplied): every
#'     taxon is priced at \code{d_cap} -- the floor for non-regional species.
#'     Beyond the instrument cap, distance stops discriminating (the far tail
#'     is dominated by distance-insensitive human-vectored transport), so the
#'     curve is deliberately flat there rather than extrapolated to zero.
#'   \item \strong{Listed-invader lift} (\code{k > 1}): a watch-listed
#'     species has demonstrably "shortened the distance effect"; stretching
#'     the bandwidth \code{k}-fold is exactly a log-space interpolation
#'     toward full plausibility (\code{exp(-d/(k*lambda)) =
#'     [exp(-d/lambda)]^(1/k)}), so \code{k = 2} is the half-way default.
#'     Supply each species' own \code{distance_km} (nearest record or
#'     nearest established population); a species with no measured distance
#'     is priced at the lifted clamp.
#'   \item \strong{Plain regional pricing} (\code{k = 1} with distances):
#'     equivalent to [generate_regional_proximity_evidence()]'s weight
#'     formula -- use that function when distances still need measuring
#'     (it runs the live GBIF passes); use this one when they are already
#'     in hand.
#' }
#'
#' @param taxon_names Character vector of candidate species names.
#' @param w_scale Numeric scalar in (0, 1]. The curve's ceiling: presence
#'   probability for a species with a record at the site itself. Required,
#'   no default -- calibrate against a local checklist (the GreatLakes value
#'   is 0.05; see the regional-proximity generator's calibration record).
#' @param distance_km Optional numeric vector of distances (km), either
#'   named by taxon or positionally aligned with \code{taxon_names}.
#'   Missing/\code{NA} entries -- and the \code{NULL} default -- price at
#'   \code{d_cap} (the clamp).
#' @param d_half Numeric scalar, the curve's e-folding half-distance in km
#'   (default \code{150}, matching [generate_regional_proximity_evidence()]).
#' @param d_cap Numeric scalar, the instrument-cap distance in km beyond
#'   which the curve is flat (default \code{1000}, the regional generator's
#'   own fetch-buffer cap).
#' @param k Numeric scalar >= 1, the bandwidth stretch for listed invaders
#'   (default \code{1}, no lift).
#' @param p_conc Numeric scalar > 0 passed through to the applier (default
#'   \code{1}).
#' @param source Character scalar stamped on the rows (default
#'   \code{"distance_clamp"} when no distances are supplied,
#'   \code{"presence_curve"} otherwise).
#'
#' @return A data frame with columns \code{taxon_name}, \code{weight},
#'   \code{p_conc}, \code{source}, \code{distance_km}, \code{k} -- ready for
#'   [apply_undetected_evidence()].
#' @seealso [apply_undetected_evidence()] (use \code{pricing = "curve"}),
#'   [generate_regional_proximity_evidence()],
#'   [generate_user_specified_evidence()]
#' @export
generate_presence_curve_evidence <- function(taxon_names,
                                             w_scale,
                                             distance_km = NULL,
                                             d_half = 150,
                                             d_cap = 1000,
                                             k = 1,
                                             p_conc = 1,
                                             source = NULL) {
  if (!is.character(taxon_names) || length(taxon_names) == 0L ||
      anyNA(taxon_names)) {
    stop("generate_presence_curve_evidence: taxon_names must be a non-empty, ",
         "non-NA character vector.")
  }
  if (missing(w_scale)) {
    stop("generate_presence_curve_evidence: w_scale is required and has no ",
         "default -- calibrate it against a local checklist (see ",
         "generate_regional_proximity_evidence()'s calibration record; the ",
         "GreatLakes value is 0.05).")
  }
  .chk <- function(x, nm, lo, hi = Inf) {
    if (!is.numeric(x) || length(x) != 1L || is.na(x) || x < lo || x > hi)
      stop(sprintf("generate_presence_curve_evidence: %s must be a single numeric in [%g, %g].",
                   nm, lo, hi))
  }
  .chk(w_scale, "w_scale", .Machine$double.eps, 1)
  .chk(d_half, "d_half", .Machine$double.eps)
  .chk(d_cap, "d_cap", .Machine$double.eps)
  .chk(k, "k", 1)
  .chk(p_conc, "p_conc", .Machine$double.eps)

  n <- length(taxon_names)
  d <- rep(NA_real_, n)
  if (!is.null(distance_km)) {
    if (!is.numeric(distance_km))
      stop("generate_presence_curve_evidence: distance_km must be numeric (or NULL).")
    if (!is.null(names(distance_km))) {
      d <- unname(distance_km[taxon_names])
    } else if (length(distance_km) == n) {
      d <- distance_km
    } else {
      stop("generate_presence_curve_evidence: distance_km must be named by ",
           "taxon or the same length as taxon_names.")
    }
  }
  clamped <- is.na(d)
  d[clamped] <- d_cap
  if (is.null(source)) {
    source <- if (all(clamped)) "distance_clamp" else "presence_curve"
  }

  data.frame(
    taxon_name  = taxon_names,
    weight      = w_scale * exp(-pmin(d, d_cap) / (k * d_half)),
    p_conc      = p_conc,
    source      = source,
    distance_km = d,
    k           = k,
    stringsAsFactors = FALSE
  )
}

#' User-specified presence evidence for species of special concern
#'
#' @description
#' The explicit policy knob from the unobserved-taxa redesign: a user may
#' assert a presence probability \code{w} for particular species (raising a
#' watch species' chance of \emph{resolving} in consensus -- detection itself
#' is already guaranteed prior-free by
#' \code{TaxaFlag::flag_watch_candidates()}). Rows carry
#' \code{source = "user_specified"} so the provenance survives into
#' \code{evidence_sources} and any downstream caveat can see it.
#'
#' Each weight is reported against the dilution threshold: with the curve
#' pricing's \code{theta_present} at the singleton scale, a weight above
#' \code{~0.11} starts materially diluting a singleton-level observed
#' native's posterior share at likelihood parity. The outright veto bound is
#' unreachable for any \code{w <= 1} under curve pricing -- which is why
#' [apply_undetected_evidence()] stopped printing one for that mode
#' (2026-09-05); it still prints a real, dataset-specific bound under
#' \code{pricing = "blend"}.
#'
#' @param taxon_weights Named numeric vector: names are species, values are
#'   presence probabilities in (0, 1].
#' @param p_conc Numeric scalar > 0 (default \code{1}).
#'
#' @return A data frame with columns \code{taxon_name}, \code{weight},
#'   \code{p_conc}, \code{source} -- ready for [apply_undetected_evidence()].
#' @seealso [generate_presence_curve_evidence()],
#'   [apply_undetected_evidence()]
#' @export
generate_user_specified_evidence <- function(taxon_weights, p_conc = 1) {
  if (!is.numeric(taxon_weights) || length(taxon_weights) == 0L ||
      is.null(names(taxon_weights)) || any(!nzchar(names(taxon_weights))) ||
      anyNA(taxon_weights)) {
    stop("generate_user_specified_evidence: taxon_weights must be a non-empty ",
         "named numeric vector with no NAs.")
  }
  if (any(taxon_weights <= 0 | taxon_weights > 1)) {
    stop("generate_user_specified_evidence: every weight must be in (0, 1].")
  }
  if (!is.numeric(p_conc) || length(p_conc) != 1L || is.na(p_conc) || p_conc <= 0) {
    stop("generate_user_specified_evidence: p_conc must be a single positive numeric.")
  }
  # Dilution threshold: at likelihood parity a native singleton keeps >= 90%
  # of the two-way posterior share while theta_e <= theta_s/9; with
  # theta_present ~ the singleton scale that is w <= 1/9. (The outright veto
  # bound, w > ~19, is unreachable for any admissible weight, which is why the
  # applier no longer prints one under curve pricing -- see its own roxygen.)
  dilution <- 1 / 9
  high <- taxon_weights[taxon_weights > dilution]
  if (length(high) > 0L) {
    message(sprintf(
      paste0("generate_user_specified_evidence: %d weight(s) exceed the ",
             "~%.2f dilution threshold (%s) -- these can materially reduce a ",
             "singleton-level observed native's posterior share at likelihood ",
             "parity. Deliberate surveillance choices are legitimate; this is ",
             "the disclosure."),
      length(high), dilution,
      paste(sprintf("%s = %.2f", names(high), high), collapse = ", ")
    ))
  }
  data.frame(
    taxon_name = names(taxon_weights),
    weight     = unname(taxon_weights),
    p_conc     = p_conc,
    source     = "user_specified",
    stringsAsFactors = FALSE
  )
}
