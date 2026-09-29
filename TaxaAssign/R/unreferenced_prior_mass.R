# unreferenced_prior_mass.R
# TaxaAssign package
#
# Gives the generic unreferenced hypotheses (an unsequenced relative in the
# best candidate's genus, family, ...) the prior mass of the local species
# they actually stand for, instead of a dark-diversity floor alone.


#' Add the prior mass of unreferenced local relatives to generic hypotheses
#'
#' A posterior is normalised over the hypotheses an observation carries, so it
#' can only say which of them is best, never that none of them is plausible
#' here. The generic unreferenced rows emitted by
#' `TaxaLikely::evaluate_likelihoods()` (an unsequenced species in the best
#' candidate's genus, an unsequenced genus in its family) are the hypotheses
#' that can absorb that case, but [join_priors()] gives them a
#' dark-diversity floor: the prior of species NEVER RECORDED locally. Species
#' that ARE recorded locally but have no reference sequence belong to the same
#' hypothesis and carry their own occurrence-based prior mass. This function
#' adds that mass.
#'
#' @section What is added:
#' For each generic unreferenced row whose `taxon_name` is a taxon above
#' species (its scope, e.g. genus *Littorina* or family Littorinidae), the
#' added mass is the sum of `theta_mean` over the site's locally modelled
#' species that
#' \itemize{
#'   \item fall inside that scope (by `taxonomy`),
#'   \item are not referenced for this marker (`referenced_names`): a
#'     referenced local species would have matched well had it been the
#'     source, so its likelihood is near zero and it cannot be part of this
#'     hypothesis,
#'   \item are not already a named hypothesis of the same observation, and
#'   \item are not already counted in a finer scope of the same observation
#'     (a family scope excludes the genus already covered by the genus scope).
#' }
#' The floor (unrecorded species) and the added mass (recorded but
#' unreferenced species) describe disjoint sets of species, so they are
#' summed: `prior_mean = floor_mean + added_mass`.
#'
#' @section Beta parameters:
#' The Beta is moment-matched to the summed mean and summed variance, the
#' variance of each species' Beta plus the floor's own variance (treating the
#' shares as independent). When that match is not a valid Beta (variance too
#' large for the mean), the row keeps its original concentration
#' (`prior_alpha + prior_beta`) recentred on the new mean. Rows whose scope
#' adds no mass are returned unchanged.
#'
#' @section Name backbones:
#' `referenced_names` must be on the same backbone as `taxaexpect_priors`. A
#' referenced species whose name fails to match looks unreferenced and
#' silently inflates the added mass. As a check, every named
#' `specific_candidate` in `joined` is a referenced species by construction;
#' the function reports how many of them are missing from `referenced_names`
#' and messages when that fraction exceeds `mismatch_message_fraction`.
#'
#' @param joined Data frame. One site's [join_priors()] output (after, or
#'   instead of, [combine_multisite_priors()]). Must contain
#'   `observation_id`, `taxon_name`, `taxon_name_rank`, `hypothesis_type`,
#'   `prior_mean`, `prior_alpha`, `prior_beta`.
#' @param taxaexpect_priors Data frame. The prior table `joined` was built
#'   from: `taxon_name`, `taxon_name_rank`, `grid_id`, `theta_mean`, and
#'   optionally `alpha`/`beta` (for the variance) and `main_habitat`.
#' @param taxonomy Data frame with `taxon_name` and one column per rank used
#'   as a scope (e.g. `genus`, `family`, `order`, `class`), for the local
#'   species. `TaxaTools::fill_higher_ranks()` output (the `expansion_taxonomy`
#'   of the workflows) fits.
#' @param referenced_names Character vector. Species with a reference sequence
#'   for this marker, on the prior backbone.
#' @param grid_id Character. The site. Default `NULL` reads it from `joined`,
#'   which must then hold exactly one `grid_id`.
#' @param unreferenced_types Character. `hypothesis_type` values treated as
#'   generic unreferenced hypotheses. Default
#'   `c("unreferenced_species", "unreferenced_genus")`.
#' @param mismatch_message_fraction Numeric in \[0, 1\]. Message threshold for
#'   the share of named candidates missing from `referenced_names`. Default
#'   0.05.
#'
#' @return `joined` with `prior_mean`, `prior_alpha` and `prior_beta` updated
#'   on rows that gained mass, plus `prior_mean_floor` (the prior before this
#'   function), `unreferenced_scope`, `unreferenced_scope_rank`,
#'   `unreferenced_mass` and `unreferenced_n_species` (`NA` on rows that are
#'   not generic unreferenced hypotheses). Attribute `unreferenced_mass_check`
#'   holds `n_candidates`, `n_candidates_not_referenced` and
#'   `n_referenced_not_in_priors`.
#'
#' @seealso [join_priors()], [compute_posterior()]
#'
#' @examples
#' joined <- data.frame(
#'   observation_id = "E1",
#'   taxon_name = c("Littorina saxatilis", "Littorina"),
#'   taxon_name_rank = c("species", "genus"),
#'   hypothesis_type = c("specific_candidate", "unreferenced_species"),
#'   prior_mean = c(1e-5, 3e-6), prior_alpha = c(0.01, 0.003),
#'   prior_beta = c(999.99, 999.997), grid_id = "site1"
#' )
#' priors <- data.frame(
#'   taxon_name = c("Littorina saxatilis", "Littorina keenae", "Littorina scutulata"),
#'   taxon_name_rank = "species", grid_id = "site1",
#'   theta_mean = c(1e-5, 4e-3, 2e-3), alpha = c(0.01, 4, 2), beta = c(999.99, 996, 998)
#' )
#' tax <- data.frame(
#'   taxon_name = priors$taxon_name, genus = "Littorina", family = "Littorinidae"
#' )
#' out <- add_unreferenced_prior_mass(joined, priors, tax,
#'   referenced_names = c("Littorina saxatilis", "Littorina scutulata")
#' )
#' out[, c("taxon_name", "prior_mean_floor", "unreferenced_mass", "prior_mean")]
#'
#' @importFrom cli cli_abort cli_inform
#' @export
add_unreferenced_prior_mass <- function(joined,
                                        taxaexpect_priors,
                                        taxonomy,
                                        referenced_names,
                                        grid_id = NULL,
                                        unreferenced_types = c("unreferenced_species", "unreferenced_genus"),
                                        mismatch_message_fraction = 0.05) {
  # --- Validation --------------------------------------------------------------
  req_j <- c(
    "observation_id", "taxon_name", "taxon_name_rank", "hypothesis_type",
    "prior_mean", "prior_alpha", "prior_beta"
  )
  miss <- setdiff(req_j, names(joined))
  if (length(miss)) cli::cli_abort("joined missing required column(s): {.field {miss}}")
  req_p <- c("taxon_name", "taxon_name_rank", "grid_id", "theta_mean")
  miss <- setdiff(req_p, names(taxaexpect_priors))
  if (length(miss)) cli::cli_abort("taxaexpect_priors missing required column(s): {.field {miss}}")
  if (!is.data.frame(taxonomy) || !"taxon_name" %in% names(taxonomy)) {
    cli::cli_abort("{.arg taxonomy} must be a data frame with a {.field taxon_name} column.")
  }
  if (!is.character(referenced_names)) {
    cli::cli_abort("{.arg referenced_names} must be a character vector.")
  }
  if (!is.numeric(mismatch_message_fraction) || length(mismatch_message_fraction) != 1L ||
    is.na(mismatch_message_fraction) || mismatch_message_fraction < 0 || mismatch_message_fraction > 1) {
    cli::cli_abort("{.arg mismatch_message_fraction} must be a single number in [0, 1].")
  }
  if (is.null(grid_id)) {
    if (!"grid_id" %in% names(joined)) {
      cli::cli_abort("Supply {.arg grid_id}: {.arg joined} has no {.field grid_id} column.")
    }
    g <- unique(stats::na.omit(joined$grid_id))
    if (length(g) != 1L) {
      cli::cli_abort(c(
        "{.arg joined} holds {length(g)} grid_id value(s); this function works on one site at a time.",
        "i" = "Call it per site, or pass {.arg grid_id}."
      ))
    }
    grid_id <- g
  }

  out <- joined
  out$prior_mean_floor <- out$prior_mean
  out$unreferenced_scope <- NA_character_
  out$unreferenced_scope_rank <- NA_character_
  out$unreferenced_mass <- NA_real_
  out$unreferenced_n_species <- NA_integer_

  ref <- unique(referenced_names[!is.na(referenced_names)])

  # --- Backbone check ------------------------------------------------------------
  cand <- unique(joined$taxon_name[joined$hypothesis_type == "specific_candidate" &
    joined$taxon_name_rank == "species" & !is.na(joined$taxon_name)])
  n_cand_unref <- sum(!cand %in% ref)
  sp_all <- unique(taxaexpect_priors$taxon_name[taxaexpect_priors$taxon_name_rank == "species"])
  check <- list(
    n_candidates = length(cand),
    n_candidates_not_referenced = n_cand_unref,
    n_referenced_not_in_priors = sum(!ref %in% sp_all)
  )
  if (length(cand) > 0L && n_cand_unref / length(cand) > mismatch_message_fraction) {
    cli::cli_inform(c(
      "!" = "{n_cand_unref} of {length(cand)} named candidate(s) are missing from \\
      {.arg referenced_names}. Every named candidate has a reference, so this suggests \\
      the names are on a different backbone; mismatched referenced species would be \\
      counted as unreferenced and inflate the added mass."
    ))
  }

  # --- Generic rows and their scopes -------------------------------------------
  rank_order <- c("species", "genus", "family", "order", "class", "phylum", "kingdom")
  gen <- which(out$hypothesis_type %in% unreferenced_types &
    !is.na(out$taxon_name) & out$taxon_name_rank %in% setdiff(names(taxonomy), "taxon_name") &
    out$taxon_name_rank != "species")
  out$unreferenced_scope[gen] <- out$taxon_name[gen]
  out$unreferenced_scope_rank[gen] <- out$taxon_name_rank[gen]
  out$unreferenced_mass[gen] <- 0
  out$unreferenced_n_species[gen] <- 0L
  if (length(gen) == 0L) {
    attr(out, "unreferenced_mass_check") <- check
    cli::cli_inform("No generic unreferenced rows with a taxonomic scope; priors unchanged.")
    return(out)
  }

  # --- Local unreferenced species pool --------------------------------------------
  pr <- as.data.frame(taxaexpect_priors)
  pr <- pr[!is.na(pr$grid_id) & pr$grid_id == grid_id & pr$taxon_name_rank == "species" &
    !is.na(pr$taxon_name) & is.finite(pr$theta_mean), , drop = FALSE]
  pr <- pr[!pr$taxon_name %in% ref, , drop = FALSE]
  has_hab <- "main_habitat" %in% names(pr) && "main_habitat" %in% names(out)
  pr$hab <- if (has_hab) pr$main_habitat else NA_character_
  pr$var <- if (all(c("alpha", "beta") %in% names(pr))) {
    a <- pr$alpha
    b <- pr$beta
    v <- a * b / ((a + b)^2 * (a + b + 1))
    v[!is.finite(v)] <- 0
    v
  } else {
    0
  }
  # one row per (habitat, species): the strongest, as join_priors() dedups
  pr <- pr[order(-pr$theta_mean), , drop = FALSE]
  pr <- pr[!duplicated(pr[, c("hab", "taxon_name")]), , drop = FALSE]
  tax <- as.data.frame(taxonomy)
  tax <- tax[!duplicated(tax$taxon_name), , drop = FALSE]
  pr <- merge(pr[, c("taxon_name", "hab", "theta_mean", "var")], tax, by = "taxon_name")

  gdf <- data.frame(
    row = gen,
    observation_id = as.character(out$observation_id[gen]),
    scope = out$taxon_name[gen],
    rank = out$taxon_name_rank[gen],
    hab = if (has_hab) out$main_habitat[gen] else NA_character_,
    stringsAsFactors = FALSE
  )
  named <- unique(data.frame(
    observation_id = as.character(out$observation_id),
    taxon_name = out$taxon_name,
    stringsAsFactors = FALSE
  )[out$taxon_name_rank == "species" & !is.na(out$taxon_name), , drop = FALSE])
  named_key <- paste(named$observation_id, named$taxon_name, sep = "\r")

  claimed <- character(0) # observation \r species already in a finer scope
  members_all <- list()
  for (r in intersect(rank_order, unique(gdf$rank))) {
    gr <- gdf[gdf$rank == r, , drop = FALSE]
    p_r <- pr[!is.na(pr[[r]]), c("taxon_name", "hab", "theta_mean", "var", r), drop = FALSE]
    names(p_r)[5] <- "scope"
    m <- merge(gr, p_r, by = "scope", suffixes = c("", ".p"))
    if (has_hab) m <- m[is.na(m$hab.p) | (!is.na(m$hab) & m$hab == m$hab.p), , drop = FALSE]
    if (nrow(m) == 0L) next
    # a species can match under several habitat rows only if hab.p is NA and
    # a habitat-specific row also exists; keep one per (row, species)
    m <- m[order(-m$theta_mean), , drop = FALSE]
    m <- m[!duplicated(m[, c("row", "taxon_name")]), , drop = FALSE]
    key <- paste(m$observation_id, m$taxon_name, sep = "\r")
    m <- m[!key %in% named_key & !key %in% claimed, , drop = FALSE]
    if (nrow(m) == 0L) next
    claimed <- c(claimed, unique(paste(m$observation_id, m$taxon_name, sep = "\r")))
    members_all[[r]] <- m
  }
  mem <- if (length(members_all)) do.call(rbind, members_all) else NULL

  n_changed <- 0L
  if (!is.null(mem) && nrow(mem) > 0L) {
    mass <- tapply(mem$theta_mean, mem$row, sum)
    varm <- tapply(mem$var, mem$row, sum)
    nsp <- tapply(mem$taxon_name, mem$row, length)
    rows <- as.integer(names(mass))
    out$unreferenced_mass[rows] <- as.numeric(mass)
    out$unreferenced_n_species[rows] <- as.integer(nsp)

    a0 <- out$prior_alpha[rows]
    b0 <- out$prior_beta[rows]
    f <- out$prior_mean[rows]
    vf <- a0 * b0 / ((a0 + b0)^2 * (a0 + b0 + 1))
    vf[!is.finite(vf)] <- 0
    mu <- pmin(f + as.numeric(mass), 1 - 1e-9)
    v <- vf + as.numeric(varm)
    ne <- mu * (1 - mu) / v - 1
    phi0 <- a0 + b0
    use_mm <- is.finite(ne) & ne > 0
    conc <- ifelse(use_mm, ne, phi0)
    out$prior_mean[rows] <- mu
    out$prior_alpha[rows] <- mu * conc
    out$prior_beta[rows] <- (1 - mu) * conc
    n_changed <- length(rows)

    mix_cols <- intersect(
      c(
        "prior_mix_w", "prior_mix_theta_present", "prior_mix_theta_absent",
        "prior_mix_p_conc", "prior_mix_var_present", "prior_mix_var_absent",
        "prior_mix_veto_bound"
      ),
      names(out)
    )
    if ("prior_mix_w" %in% mix_cols) {
      had_mix <- rows[!is.na(out$prior_mix_w[rows])]
      if (length(had_mix)) {
        for (cc in mix_cols) out[[cc]][had_mix] <- NA
        cli::cli_inform(
          "{length(had_mix)} presence-mixture row(s) gained unreferenced mass; their \\
          prior_mix_* columns were cleared so compute_posterior() samples the updated Beta."
        )
      }
    }
  }

  cli::cli_inform(c(
    "Unreferenced prior mass at {.val {grid_id}}: {n_changed} of {length(gen)} generic \\
    row(s) gained mass from unreferenced local relatives \\
    (median added {signif(stats::median(out$unreferenced_mass[gen][out$unreferenced_mass[gen] > 0]), 3)}).",
    "i" = "{check$n_candidates_not_referenced} of {check$n_candidates} named candidate(s) \\
    not in {.arg referenced_names}; {check$n_referenced_not_in_priors} referenced name(s) \\
    absent from the prior table."
  ))
  attr(out, "unreferenced_mass_check") <- check
  out
}
