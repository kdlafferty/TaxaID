utils::globalVariables(c("taxon_name"))

#' Condition Presence Evidence on the Site Habitat
#'
#' Multiplies each evidence row's presence weight by the taxon's own weight
#' for the site habitat, floored at the weight a taxon with no evidence at
#' all receives. Applied to the output of
#' \code{\link{generate_regional_proximity_evidence}},
#' \code{\link{generate_presence_curve_evidence}} and
#' \code{\link{generate_inat_range_evidence}} BEFORE
#' \code{\link{apply_undetected_evidence}} prices the rows.
#'
#' @details
#' \strong{Why.} The resident priors are stratified by habitat: a record
#' only enters the site's pool when its point (classified by the community
#' observed there, \code{TaxaHabitat::assign_habitat_biological()}) carries the
#' site habitat. Evidence rows skipped that stratification, so a distant
#' record of a species that never occupies the site habitat was priced more
#' generously than a local population of the same species. A real case:
#' a red deer record 54 km from Point Conception earned a prior
#' 480 times the zero-record floor at a marine site, while the deer living on
#' the site itself sat at that floor; a mountain whitefish record 355 km from
#' Pt. Mugu out-competed four unrecorded congeners at an estuary.
#'
#' \strong{The rule.}
#' \deqn{w_{site} = \max(w \cdot H_{site}, w_{floor})}
#' where \eqn{w} is the generator's own presence weight
#' (P(present in the region | evidence)), \eqn{H_{site}} the taxon's weight
#' for the site habitat from the same LLM habitat lookup that supplies the
#' residents' point votes (P(occupies the site habitat | present in the
#' region)), and \eqn{w_{floor}} the clamp weight every zero-evidence taxon
#' receives. The product is P(present in the site habitat | evidence) under
#' independence of distance and habitat -- the same product-kernel
#' assumption \code{\link{estimate_kernel_priors}} makes for geography and a
#' covariate. Because the rule is linear in \eqn{H_{site}}, habitat bleed
#' survives in proportion: a steelhead with Marine 0.25 keeps a quarter of
#' its regional weight at a marine site; a terrestrial mammal with Marine 0
#' drops to the floor. A taxon absent from \code{habitat_lookup} (or with an
#' \code{NA} weight) is left unchanged and counted in a message -- no
#' information, no change.
#'
#' @param evidence Data frame with \code{taxon_name} and \code{weight}
#'   columns (any evidence generator's output).
#' @param habitat_lookup Data frame from
#'   \code{TaxaHabitat::build_habitat_lookup()}: \code{taxon_name} plus one
#'   numeric weight column per habitat class.
#' @param site_habitat Character scalar naming the site's habitat column in
#'   \code{habitat_lookup}.
#' @param w_floor Numeric in [0, 1). The weight below which no evidence row
#'   may fall -- pass the run's clamp weight (\code{w_scale * exp(-d_cap /
#'   d_half)} under curve pricing). Default \code{0}.
#' @param verbose Logical. Report counts. Default \code{TRUE}.
#' @return \code{evidence} with \code{weight} replaced by the conditioned
#'   weight and three added columns: \code{habitat_weight} (\eqn{H_{site}},
#'   \code{NA} when unknown), \code{weight_unconditioned} (the generator's
#'   original weight) and \code{habitat_floored} (\code{TRUE} where the
#'   product fell below \code{w_floor}).
#' @seealso \code{\link{apply_undetected_evidence}},
#'   \code{\link{generate_regional_proximity_evidence}}
#' @export
#' @examples
#' ev <- data.frame(taxon_name = c("Oncorhynchus mykiss", "Cervus elaphus"),
#'                  weight = c(0.046, 0.035), source = "regional_proximity")
#' hab <- data.frame(taxon_name = c("Oncorhynchus mykiss", "Cervus elaphus"),
#'                   Marine = c(0.25, 0), Freshwater = c(0.75, 0), Terrestrial = c(0, 1))
#' condition_evidence_on_habitat(ev, hab, site_habitat = "Marine", w_floor = 6.4e-5)
condition_evidence_on_habitat <- function(evidence, habitat_lookup, site_habitat,
                                          w_floor = 0, verbose = TRUE) {
  if (!is.data.frame(evidence) || !all(c("taxon_name", "weight") %in% names(evidence))) {
    stop(
      "condition_evidence_on_habitat: `evidence` must be a data frame with ",
      "`taxon_name` and `weight` columns.",
      call. = FALSE
    )
  }
  if (!is.data.frame(habitat_lookup) || !"taxon_name" %in% names(habitat_lookup)) {
    stop(
      "condition_evidence_on_habitat: `habitat_lookup` must be a data frame ",
      "with a `taxon_name` column.",
      call. = FALSE
    )
  }
  if (!is.character(site_habitat) || length(site_habitat) != 1L || is.na(site_habitat)) {
    stop("condition_evidence_on_habitat: `site_habitat` must be a single habitat name.", call. = FALSE)
  }
  if (!site_habitat %in% names(habitat_lookup)) {
    stop(sprintf("condition_evidence_on_habitat: `habitat_lookup` has no column '%s' (columns: %s).",
                 site_habitat, paste(names(habitat_lookup), collapse = ", ")), call. = FALSE)
  }
  if (!is.numeric(w_floor) || length(w_floor) != 1L || is.na(w_floor) || w_floor < 0 || w_floor >= 1) {
    stop("condition_evidence_on_habitat: `w_floor` must be a single number in [0, 1).", call. = FALSE)
  }
  if (nrow(evidence) == 0L) {
    evidence$habitat_weight <- numeric(0)
    evidence$weight_unconditioned <- numeric(0)
    evidence$habitat_floored <- logical(0)
    return(evidence)
  }
  lk <- habitat_lookup[!duplicated(habitat_lookup$taxon_name), , drop = FALSE]
  h <- as.numeric(lk[[site_habitat]])[match(evidence$taxon_name, lk$taxon_name)]
  bad_h <- !is.na(h) & (h < 0 | h > 1)
  if (any(bad_h)) {
    stop(sprintf("condition_evidence_on_habitat: %d habitat weight(s) outside [0, 1].", sum(bad_h)), call. = FALSE)
  }
  w0 <- as.numeric(evidence$weight)
  w1 <- ifelse(is.na(h), w0, pmax(w0 * h, w_floor))
  evidence$habitat_weight <- h
  evidence$weight_unconditioned <- w0
  evidence$habitat_floored <- !is.na(h) & (w0 * h < w_floor)
  evidence$weight <- w1
  if (isTRUE(verbose)) {
    message(sprintf(
      paste0(
        "condition_evidence_on_habitat: %d row(s) conditioned on '%s' -- ",
        "%d unchanged (habitat weight 1 or unknown: %d unknown), %d reduced, ",
        "%d floored at %.3g."
      ),
      nrow(evidence), site_habitat,
      sum(is.na(h) | h >= 1), sum(is.na(h)), sum(!is.na(h) & h < 1 & !evidence$habitat_floored),
      sum(evidence$habitat_floored), w_floor
    ))
  }
  evidence
}
