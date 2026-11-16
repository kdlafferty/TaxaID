# unreferenced_prior_mass.R
# TaxaAssign package
#
# Gives the generic unreferenced hypotheses (an unsequenced relative in the
# best candidate's genus, family, ...) the prior mass of the local species
# they actually stand for, instead of a dark-diversity floor alone.

# Add any of `cols` missing from `df` as NA columns, in `cols` order, so frames
# built from different sources bind.
.fill_cols <- function(df, cols) {
  for (cc in setdiff(cols, names(df))) df[[cc]] <- rep(NA_character_, nrow(df))
  df[, cols, drop = FALSE]
}

# Registry path of add_unreferenced_prior_mass(): the same algorithm, run on working copies keyed by taxon_id.
# `taxon_name` of the copies holds the taxon_id, the lineage columns hold ancestor ids walked up the registry's own
# tree (TaxaTools::parent_at()), and `referenced` is a set of ids, so every membership test, merge and scope match in
# the function compares identifiers, never names. Prior rows of one taxon at one site (synonyms in the pool) are
# reduced to one: the row under the registry's accepted name, else the strongest. Returns the working copies plus the
# maps needed to put names back on the output.
.unref_registry_inputs <- function(joined, priors, referenced, registry, ref_lineage_scope = c("local", "all")) {
  ref_lineage_scope <- match.arg(ref_lineage_scope)
  .registry_check_tables(registry, list(joined = joined, taxaexpect_priors = priors))
  if (!is.character(referenced)) cli::cli_abort("With {.arg registry}, {.arg referenced_names} must be a character vector of taxon ids.")
  ref <- unique(referenced[!is.na(referenced)])
  unk <- setdiff(ref, registry$taxa$taxon_id)
  if (length(unk)) {
    cli::cli_abort("With {.arg registry}, {.arg referenced_names} must hold taxon ids of that registry; {length(unk)} are not (e.g. {.val {utils::head(unk, 3)}}).")
  }
  lin <- c("genus", "family", "order", "class", "phylum")
  ids <- unique(stats::na.omit(c(as.character(joined$taxon_id), as.character(priors$taxon_id), ref)))
  anc <- .registry_ancestors(ids, lin, registry)
  reg_name <- stats::setNames(registry$taxa$name, registry$taxa$taxon_id)
  reg_rank <- stats::setNames(registry$taxa$rank, registry$taxa$taxon_id)

  jw <- as.data.frame(joined)
  jw$taxon_name <- as.character(jw$taxon_id)
  for (r in intersect(lin, names(jw))) jw[[r]] <- unname(anc[[r]][jw$taxon_name])
  # a ring row whose id sits at another rank than the row's own (a name resolved to a coarser taxon) cannot scope
  ring <- !jw$hypothesis_type %in% "specific_candidate" & !is.na(jw$taxon_name) & !jw$taxon_name_rank %in% "species"
  rank_mismatch <- ring & !mapply(identical, unname(reg_rank[jw$taxon_name]), as.character(jw$taxon_name_rank))

  # one prior row per (site, habitat, taxon): the accepted name's row, else the strongest
  kp <- .registry_key_priors(priors, registry)
  pw <- kp$priors
  merged <- kp$merged
  # output names are the registry's accepted names, derived from taxon_id (never the key)
  disp <- reg_name

  # The floor rule reads the referenced taxa's lineages from this table and from the candidates in `joined`. "local"
  # (the default) holds the local prior species only, the scope the name path uses (its `taxonomy` is the local
  # species' table), so converting to ids changes no withholding by itself. "all" adds every referenced species'
  # lineage; it is a separate behaviour change, measured on its own and not reachable from the exported function.
  # A tied-anchor ring lists its member clades by NAME (ring_member_clades, from the likelihoods); each is mapped to
  # one taxon id through the registry's names table, else its accepted name. A name with no id, or with two, maps to
  # NA and that clade is withheld (attr "ring_member_clades_withheld"), never guessed.
  member_id <- character(0)
  if ("ring_member_clades" %in% names(jw)) {
    mn <- unique(unlist(strsplit(stats::na.omit(as.character(jw$ring_member_clades)), "|", fixed = TRUE)))
    if (length(mn)) {
      nt <- registry$names[!is.na(registry$names$verbatim_name) & !is.na(registry$names$taxon_id), c("verbatim_name", "taxon_id")]
      nt <- unique(rbind(nt, data.frame(verbatim_name = registry$taxa$name, taxon_id = registry$taxa$taxon_id, stringsAsFactors = FALSE)))
      nt <- nt[nt$verbatim_name %in% mn, , drop = FALSE]
      n_ids <- tapply(nt$taxon_id, nt$verbatim_name, function(x) length(unique(x)))
      member_id <- stats::setNames(rep(NA_character_, length(mn)), mn)
      one <- names(n_ids)[n_ids == 1L]
      member_id[one] <- nt$taxon_id[match(one, nt$verbatim_name)]
    }
  }
  tx_ids <- if (ref_lineage_scope == "local") unique(pw$taxon_name) else unique(c(pw$taxon_name, ref))
  tax <- data.frame(taxon_name = tx_ids, stringsAsFactors = FALSE)
  for (r in lin) tax[[r]] <- unname(anc[[r]][tx_ids])
  list(
    joined = jw, priors = pw, taxonomy = tax, referenced = ref, display = disp, reg_name = reg_name,
    reg_rank = reg_rank, member_id = member_id,
    ref_genera = unique(stats::na.omit(unname(anc$genus[ref]))), genus_of = anc$genus,
    merged_prior_rows = merged,
    counts = list(
      n_joined_rows_no_id = sum(is.na(joined$taxon_id) & !is.na(joined$taxon_name)),
      n_prior_names_no_id = kp$n_no_id,
      n_ring_rows_rank_mismatch = sum(rank_mismatch),
      n_prior_rows_merged = kp$n_merged
    ),
    rank_mismatch = rank_mismatch
  )
}

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
#'   \item fall inside that scope (by `taxonomy`) and are binomials: a prior
#'     row for a record identified only to genus or family is a coarse sighting
#'     of species already in the pool, not a further species,
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
#'   `c("unreferenced_species", "unreferenced_genus", "unreferenced_family",
#'   "unreferenced_order", "unreferenced_class")`: an unsequenced congener
#'   (scope genus), genus (family), family (order), order (class) or class
#'   (phylum). A ring's scope rank is always one coarser than the rank in its
#'   type, so other `unreferenced_<rank>` values work the same way.
#' @param mismatch_message_fraction Numeric in \[0, 1\]. Message threshold for
#'   the share of named candidates missing from `referenced_names`. Default
#'   0.05.
#' @param named_rows Logical (default `FALSE`). `FALSE` adds each ring row's
#'   recorded unreferenced local species to that row's prior. `TRUE` instead
#'   adds one row per such species (`hypothesis_type = "unreferenced_species"`,
#'   named at species rank) carrying the ring row's likelihood and its own
#'   occurrence prior, and leaves the ring row's prior as it was (the
#'   unrecorded part). The species can then be reported by name when the
#'   prior concentrates on it; the total prior in each scope is the same
#'   either way. Only a species claimed by its OWN genus ring is named: a
#'   family, order, class or phylum ring stands for "some unreferenced taxon
#'   of this clade", so the species it claims add their prior to that ring
#'   row unnamed, exactly as with `FALSE`.
#' @param withhold Character, the rule that keeps a local unreferenced species
#'   out of a ring too coarse for it (see Withheld species). `"finest"`
#'   (default): the species adds its prior only to the ring at the finest rank
#'   where its lineage has a referenced taxon for this marker. `"genus"`: only
#'   a referenced genus withholds a species, so a species whose family has a
#'   reference can still be claimed by an order, class or phylum ring.
#' @param registry `NULL` (default) or a frozen `taxon_registry`
#'   (`TaxaTools::build_taxon_registry()`). `NULL` matches taxa by name, as
#'   described above. Given a registry, taxa are matched by identifier only
#'   (see Matching by taxon identifier): `joined` and `taxaexpect_priors` must
#'   carry a `taxon_id` column stamped by this registry
#'   (`TaxaTools::attach_taxon_ids()`), `referenced_names` holds taxon ids of
#'   the referenced species, and `taxonomy` is not used (it may be `NULL`).
#'
#' @section Matching by taxon identifier:
#'   With `registry`, every test of "is this species referenced?", "is it
#'   already a candidate?" and "does it fall in this ring's scope?" compares
#'   registry taxon ids, and each species' genus, family, order, class and
#'   phylum come from the registry's own tree (`TaxaTools::parent_at()`), not
#'   from any table's lineage columns or from the text of a binomial. A species
#'   held under two names (a synonym in the pool and the accepted name in the
#'   references) is therefore one species: it is referenced if either name is,
#'   and it is counted once. Where the prior table holds one taxon under two
#'   or more names at one site, the row under the registry's accepted name is
#'   kept (else the strongest), and the rows set aside are listed in
#'   `attr(result, "unreferenced_merged_prior_rows")`. `joined` rows keep
#'   their names; a named species row, and the members and withheld tables,
#'   take the registry's accepted name for the taxon id (a display column,
#'   never the key). `unreferenced_mass_check` gains
#'   `n_joined_rows_no_id`, `n_prior_names_no_id`, `n_ring_rows_rank_mismatch`
#'   (ring rows whose id the registry holds at another rank; they gain no
#'   mass) and `n_prior_rows_merged`; the members and withheld tables gain a
#'   `taxon_id` column.
#'
#' @return `joined` with `prior_mean`, `prior_alpha` and `prior_beta` updated
#'   on rows that gained mass, plus `prior_mean_floor` (the prior before this
#'   function), `unreferenced_scope`, `unreferenced_scope_rank`,
#'   `unreferenced_mass` and `unreferenced_n_species` (`NA` on rows that are
#'   not generic unreferenced hypotheses). Attribute `unreferenced_mass_check`
#'   holds `n_candidates`, `n_candidates_not_referenced`,
#'   `n_referenced_not_in_priors` and `n_coarse_prior_rows_excluded` (site prior
#'   rows that are not binomials, such as a family-level record, and so are not
#'   summed); attribute `unreferenced_scope_members` lists
#'   the species behind each added mass (`row`, `observation_id`, `scope`,
#'   `scope_rank`, `taxon_name`, `theta_mean`), so every mass can be traced to
#'   the local species that make it up.
#'
#' @section Withheld species:
#'   A ring row stands for an unsequenced relative at its scope. A local
#'   unreferenced species belongs in that ring only if no finer taxon of its
#'   own lineage was already tested against the read. Under the default
#'   `withhold = "finest"`, a species is claimed only by the ring at the finest
#'   rank where its lineage has a referenced taxon for this marker (its genus,
#'   family, order, ...; the lineages of `referenced_names` in `taxonomy` and
#'   of the named candidates in `joined`). Where the unit has no ring at that
#'   rank, that taxon's references were compared with the read and did not
#'   match, so no coarser ring may name the species; it is withheld with reason
#'   `"genus_referenced_unmatched"` when its genus has a reference and
#'   `"finer_rank_referenced_unmatched"` when the referenced taxon is coarser
#'   (its family, order, ...). Under `withhold = "genus"` only a referenced
#'   genus withholds a species from its family or coarser rings. Withheld species are listed in
#'   `attr(result, "unreferenced_withheld")` (`observation_id`, `taxon_name`,
#'   `scope`, `scope_rank`, `reason`), present on every return.
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
                                        unreferenced_types = c("unreferenced_species", "unreferenced_genus", "unreferenced_family", "unreferenced_order", "unreferenced_class"),
                                        mismatch_message_fraction = 0.05,
                                        named_rows = FALSE,
                                        withhold = c("finest", "genus"),
                                        registry = NULL) {
  # --- Validation --------------------------------------------------------------
  withhold <- match.arg(withhold)
  joined_in <- joined
  rg <- NULL
  if (!is.null(registry)) {
    rg <- .unref_registry_inputs(joined, taxaexpect_priors, referenced_names, registry)
    joined <- rg$joined
    taxaexpect_priors <- rg$priors
    taxonomy <- rg$taxonomy
    referenced_names <- rg$referenced
  }
  # Registry path: put the tables' own names back on the output (the working copies carried ids in taxon_name and
  # in the lineage columns), give each named species row its own taxon_id, and attach the id-side diagnostics.
  .finish <- function(out) {
    if (is.null(rg)) return(out)
    n0 <- nrow(joined_in)
    lin_cols <- intersect(c("genus", "family", "order", "class", "phylum"), names(joined_in))
    scope_name <- stats::setNames(as.character(joined_in$taxon_name), rg$joined$taxon_name)
    scope_name <- scope_name[!is.na(names(scope_name)) & !duplicated(names(scope_name))]
    nm_of <- function(id, pref) { v <- unname(pref[id]); w <- is.na(v) & !is.na(id); v[w] <- unname(rg$reg_name[id[w]]); v }
    sc <- out$unreferenced_scope
    out$unreferenced_scope <- nm_of(sc, scope_name)
    # a tied-anchor ring's scope is already its member clades' names (ring_member_clades), not an id
    if ("ring_member_clades" %in% names(out)) {
      k <- which(!is.na(out$ring_member_clades) & !is.na(sc))
      out$unreferenced_scope[k] <- sc[k]
    }
    idx0 <- seq_len(n0)
    out$taxon_name[idx0] <- as.character(joined_in$taxon_name)
    for (r in lin_cols) out[[r]][idx0] <- joined_in[[r]]
    if (nrow(out) > n0) {
      idx1 <- seq.int(n0 + 1L, nrow(out))
      ids <- as.character(out$taxon_name[idx1])
      out$taxon_id[idx1] <- ids
      out$taxon_name[idx1] <- nm_of(ids, rg$display)
      if ("species" %in% names(out)) out$species[idx1] <- out$taxon_name[idx1]
      for (r in lin_cols) out[[r]][idx1] <- unname(rg$reg_name[as.character(out[[r]][idx1])])
    }
    for (a in c("unreferenced_scope_members", "unreferenced_withheld")) {
      d <- attr(out, a)
      if (is.null(d)) next
      ids <- as.character(d$taxon_name)
      d$taxon_name <- nm_of(ids, rg$display)
      d$scope <- nm_of(as.character(d$scope), scope_name)
      d$taxon_id <- ids
      attr(out, a) <- d
    }
    attr(out, "unreferenced_mass_check") <- c(attr(out, "unreferenced_mass_check"), rg$counts)
    attr(out, "unreferenced_merged_prior_rows") <- rg$merged_prior_rows
    attr(out, "taxon_registry") <- attr(joined_in, "taxon_registry", exact = TRUE)
    out
  }
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

  joined <- .blank_ranks_to_na(joined)
  taxonomy <- .blank_ranks_to_na(taxonomy)
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
    n_referenced_not_in_priors = sum(!ref %in% sp_all),
    n_coarse_prior_rows_excluded = NA_integer_
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
  # A generic row gains mass only at its own ring's rank: an unsequenced
  # congener at genus, an unsequenced genus at family. A row renamed to a
  # coarser real ancestor because its family was a placeholder ("unk_family"
  # -> its order) keeps its floor: its true scope is unknown.
  expected_rank <- .unreferenced_ring_rank(out$hypothesis_type)
  gen <- which(out$hypothesis_type %in% unreferenced_types &
    !is.na(out$taxon_name) & out$taxon_name_rank %in% setdiff(names(taxonomy), "taxon_name") &
    out$taxon_name_rank != "species" &
    (is.na(expected_rank) | out$taxon_name_rank == expected_rank) &
    (if (is.null(rg)) TRUE else !rg$rank_mismatch))
  out$unreferenced_scope[gen] <- out$taxon_name[gen]
  out$unreferenced_scope_rank[gen] <- out$taxon_name_rank[gen]
  out$unreferenced_mass[gen] <- 0
  out$unreferenced_n_species[gen] <- 0L
  # Tied-anchor rings. TaxaLikely names an outer ring at the lowest common rank of the candidates tied with its anchor
  # when they span clades, and lists those clades at the ring's OWN rank in ring_member_clades. Such a ring's scope is
  # the UNION of its member clades at that rank -- not everything under the common rank. The clades are disjoint at
  # that rank, and members are deduplicated per (row, species) below as for any ring, so nothing is counted twice.
  # A row whose ring_member_clades is NA is handled exactly as before.
  lca_rows <- if ("ring_member_clades" %in% names(out)) {
    which(out$hypothesis_type %in% unreferenced_types & !is.na(out$ring_member_clades) & !is.na(expected_rank))
  } else {
    integer(0)
  }
  gen <- setdiff(gen, lca_rows)
  lca_sc <- data.frame(row = integer(0), member = character(0), rank = character(0), scope = character(0), stringsAsFactors = FALSE)
  lca_withheld <- data.frame(observation_id = character(0), row = integer(0), member_clade = character(0),
                             scope_rank = character(0), reason = character(0), stringsAsFactors = FALSE)
  if (length(lca_rows)) {
    mm <- strsplit(as.character(out$ring_member_clades[lca_rows]), "|", fixed = TRUE)
    lca_sc <- data.frame(row = rep(lca_rows, lengths(mm)), member = unlist(mm),
                         rank = rep(expected_rank[lca_rows], lengths(mm)), stringsAsFactors = FALSE)
    lca_sc$scope <- lca_sc$member
    if (!is.null(rg)) {
      lca_sc$scope <- unname(rg$member_id[lca_sc$member])
      bad_rank <- !is.na(lca_sc$scope) & !mapply(identical, unname(rg$reg_rank[lca_sc$scope]), lca_sc$rank)
      why <- dplyr::if_else(is.na(lca_sc$scope), "member_clade_no_registry_id",
                            dplyr::if_else(bad_rank, "member_clade_rank_mismatch", NA_character_))
      if (any(!is.na(why))) {
        w <- !is.na(why)
        lca_withheld <- data.frame(observation_id = as.character(out$observation_id[lca_sc$row[w]]), row = lca_sc$row[w],
                                   member_clade = lca_sc$member[w], scope_rank = lca_sc$rank[w], reason = why[w],
                                   stringsAsFactors = FALSE)
        lca_sc <- lca_sc[!w, , drop = FALSE]
      }
    }
    out$unreferenced_scope[lca_rows] <- as.character(out$ring_member_clades[lca_rows])
    out$unreferenced_scope_rank[lca_rows] <- expected_rank[lca_rows]
    out$unreferenced_mass[lca_rows] <- 0
    out$unreferenced_n_species[lca_rows] <- 0L
  }
  if (length(gen) == 0L && nrow(lca_sc) == 0L) {
    attr(out, "ring_member_clades_withheld") <- lca_withheld
    attr(out, "unreferenced_mass_check") <- check
    attr(out, "unreferenced_withheld") <- data.frame(
      observation_id = character(0), taxon_name = character(0), scope = character(0),
      scope_rank = character(0), reason = character(0), stringsAsFactors = FALSE
    )
    cli::cli_inform("No generic unreferenced rows with a taxonomic scope; priors unchanged.")
    return(.finish(out))
  }

  # --- Local unreferenced species pool --------------------------------------------
  pr <- as.data.frame(taxaexpect_priors)
  pr <- pr[!is.na(pr$grid_id) & pr$grid_id == grid_id & pr$taxon_name_rank == "species" &
    !is.na(pr$taxon_name) & is.finite(pr$theta_mean), , drop = FALSE]
  pr <- pr[!pr$taxon_name %in% ref, , drop = FALSE]
  # Prior tables can carry rows for records identified only to genus or
  # family ("Cottidae", "Icelinus") under taxon_name_rank "species". They are
  # coarse sightings of species already in the pool, not further unsampled
  # species, so only binomials are summed. The excluded rows are counted.
  is_sp <- TaxaTools::is_plausible_binomial(if (is.null(rg)) pr$taxon_name else pr$.verbatim)
  n_coarse_excluded <- length(unique(pr$taxon_name[!is_sp]))
  pr <- pr[is_sp, , drop = FALSE]
  has_hab <- "main_habitat" %in% names(pr) && "main_habitat" %in% names(out)
  pr$hab <- if (has_hab) pr$main_habitat else rep(NA_character_, nrow(pr))
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

  check$n_coarse_prior_rows_excluded <- n_coarse_excluded

  grow <- c(gen, lca_sc$row)
  gdf <- data.frame(
    row = grow,
    observation_id = as.character(out$observation_id[grow]),
    scope = c(out$taxon_name[gen], lca_sc$scope),
    rank = c(out$taxon_name_rank[gen], lca_sc$rank),
    hab = if (has_hab) out$main_habitat[grow] else NA_character_,
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
  # Genera WITH a reference for this marker, from the referenced species
  # themselves. A local unreferenced species of such a genus may be claimed
  # only by its own GENUS ring: that ring is built from its congeners' actual
  # fit to the read. Where no genus ring exists in the unit, the genus's
  # references were compared with the read and did not match, and a family,
  # order, class or phylum ring ("some unreferenced genus of ...") cannot be
  # this species. It is then not claimed at all, and reported.
  # (with a registry, the genus is the registry's ancestor, never the text before the first space)
  ref_genera <- if (is.null(rg)) unique(sub(" .*$", "", ref[!is.na(ref)])) else rg$ref_genera
  genus_word <- if (is.null(rg)) function(x) sub(" .*$", "", x) else function(x) unname(rg$genus_of[x])
  # Referenced taxa at every rank above species, from the referenced species'
  # own lineages: their `taxonomy` rows, and the lineage columns `joined`
  # carries on its named candidates (referenced by construction).
  lin_ranks <- setdiff(intersect(rank_order, unique(c(names(taxonomy), names(joined)))), "species")
  ref_lin <- rbind(
    .fill_cols(taxonomy[taxonomy$taxon_name %in% ref, intersect(lin_ranks, names(taxonomy)), drop = FALSE], lin_ranks),
    .fill_cols(joined[joined$hypothesis_type %in% "specific_candidate", intersect(lin_ranks, names(joined)), drop = FALSE], lin_ranks)
  )
  ref_anc <- lapply(stats::setNames(lin_ranks, lin_ranks), function(rr) unique(stats::na.omit(ref_lin[[rr]])))
  withheld <- list()
  for (r in intersect(rank_order, unique(gdf$rank))) {
    gr <- gdf[gdf$rank == r, , drop = FALSE]
    p_r <- pr[!is.na(pr[[r]]), c("taxon_name", "hab", "theta_mean", "var", r), drop = FALSE]
    names(p_r)[5] <- "scope"
    # the lineage below this ring, for the floor rule
    finer <- if (withhold == "finest") intersect(lin_ranks[seq_len(match(r, lin_ranks) - 1L)], names(pr)) else character(0)
    for (rr in finer) p_r[[paste0(".lin_", rr)]] <- pr[[rr]][!is.na(pr[[r]])]
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
    if (r != "genus") {
      ref_gen <- genus_word(m$taxon_name) %in% ref_genera
      why <- c("finer_rank_referenced_unmatched", "genus_referenced_unmatched")[ref_gen + 1L]
      if (withhold == "finest") {
        for (rr in finer) {
          v <- m[[paste0(".lin_", rr)]]
          ref_gen <- ref_gen | (!is.na(v) & v %in% ref_anc[[rr]])
        }
      }
      if (any(ref_gen)) {
        withheld[[length(withheld) + 1L]] <- data.frame(
          observation_id = m$observation_id[ref_gen], taxon_name = m$taxon_name[ref_gen],
          scope = m$scope[ref_gen], scope_rank = r,
          reason = why[ref_gen],
          stringsAsFactors = FALSE
        )
        # withheld, AND marked claimed so no coarser ring takes them either
        claimed <- c(claimed, unique(paste(m$observation_id[ref_gen], m$taxon_name[ref_gen], sep = "\r")))
        m <- m[!ref_gen, , drop = FALSE]
        if (nrow(m) == 0L) next
      }
    }
    claimed <- c(claimed, unique(paste(m$observation_id, m$taxon_name, sep = "\r")))
    members_all[[r]] <- m[, !startsWith(names(m), ".lin_"), drop = FALSE]
  }
  mem <- if (length(members_all)) do.call(rbind, members_all) else NULL

  n_changed <- 0L
  n_named <- 0L
  # Only a species's OWN genus ring may name it. A family, order, class or
  # phylum ring means "some unreferenced taxon of this clade", whose local
  # members can number in the dozens; naming one is the prior's choice, not
  # the read's (CalIntertidal: Taonia lennebackerae named from a Dictyotaceae
  # ring in 186 units, over a class ring the read fit better). Members claimed
  # by a coarser ring keep their prior mass, added to that ring row unnamed.
  mem_mass <- NULL
  mem_all <- mem
  if (named_rows && !is.null(mem) && nrow(mem) > 0L) {
    coarse <- mem$rank != "genus"
    if (any(coarse)) {
      mem_mass <- mem[coarse, , drop = FALSE]
      mem <- mem[!coarse, , drop = FALSE]
    }
  }
  if (named_rows && !is.null(mem) && nrow(mem) > 0L) {
    # One named row per recorded unreferenced local species, carrying the
    # likelihood of the ring whose scope contains it and its own prior. The
    # ring row keeps its own prior (the unrecorded part only).
    new <- out[mem$row, , drop = FALSE]
    new$taxon_name <- mem$taxon_name
    new$taxon_name_rank <- "species"
    new$hypothesis_type <- "unreferenced_species"
    if ("species" %in% names(new)) new$species <- mem$taxon_name
    tx <- tax[match(mem$taxon_name, tax$taxon_name), , drop = FALSE]
    for (rc in intersect(setdiff(names(tax), "taxon_name"), names(new))) new[[rc]] <- tx[[rc]]
    th <- pmin(pmax(mem$theta_mean, 1e-12), 1 - 1e-9)
    ne <- th * (1 - th) / pmax(mem$var, 1e-30) - 1
    ne <- ifelse(is.finite(ne) & ne > 0, ne, 2)
    new$prior_mean <- th
    new$prior_alpha <- th * ne
    new$prior_beta <- (1 - th) * ne
    new$prior_mean_floor <- NA_real_
    new$unreferenced_scope <- mem$scope
    new$unreferenced_scope_rank <- mem$rank
    new$unreferenced_mass <- NA_real_
    new$unreferenced_n_species <- NA_integer_
    nsp <- tapply(mem$taxon_name, mem$row, length)
    out$unreferenced_n_species[as.integer(names(nsp))] <- as.integer(nsp)
    for (cc in intersect(c("prior_mix_w", "prior_mix_theta_present", "prior_mix_theta_absent",
      "prior_mix_p_conc", "prior_mix_var_present", "prior_mix_var_absent", "prior_mix_veto_bound"), names(new))) {
      new[[cc]] <- NA
    }
    n_named <- nrow(new)
    out <- rbind(out, new)
  }
  mem_m <- if (named_rows) mem_mass else mem
  if (!is.null(mem_m) && nrow(mem_m) > 0L) {
    mem_k <- mem_m
    mass <- tapply(mem_k$theta_mean, mem_k$row, sum)
    varm <- tapply(mem_k$var, mem_k$row, sum)
    nsp <- tapply(mem_k$taxon_name, mem_k$row, length)
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

  if (named_rows) {
    cli::cli_inform("Unreferenced named rows at {.val {grid_id}}: {n_named} recorded \\
      unreferenced local species added under {length(unique(mem$row))} ring row(s).")
  }
  cli::cli_inform(c(
    "Unreferenced prior mass at {.val {grid_id}}: {n_changed} of {length(gen) + length(lca_rows)} generic \\
    row(s) gained mass from unreferenced local relatives \\
    (median added {signif(stats::median(out$unreferenced_mass[gen][out$unreferenced_mass[gen] > 0]), 3)}).",
    "i" = "{check$n_candidates_not_referenced} of {check$n_candidates} named candidate(s) \\
    not in {.arg referenced_names}; {check$n_referenced_not_in_priors} referenced name(s) \\
    absent from the prior table."
  ))
  withheld_df <- if (length(withheld)) do.call(rbind, withheld) else data.frame(
    observation_id = character(0), taxon_name = character(0), scope = character(0),
    scope_rank = character(0), reason = character(0), stringsAsFactors = FALSE
  )
  if (nrow(withheld_df) > 0L) {
    cli::cli_inform(sprintf(
      "add_unreferenced_prior_mass: %d local unreferenced species row(s) withheld in %d observation(s): a finer taxon of their lineage has a reference for this marker that did not match the read, so no coarser ring may name them (attr 'unreferenced_withheld').",
      nrow(withheld_df), length(unique(withheld_df$observation_id))
    ))
  }
  attr(out, "unreferenced_withheld") <- withheld_df
  attr(out, "ring_member_clades_withheld") <- lca_withheld
  attr(out, "unreferenced_mass_check") <- check
  attr(out, "unreferenced_scope_members") <- if (!is.null(mem_all) && nrow(mem_all) > 0L) {
    data.frame(
      row = mem_all$row, observation_id = mem_all$observation_id, scope = mem_all$scope,
      scope_rank = mem_all$rank, taxon_name = mem_all$taxon_name, theta_mean = mem_all$theta_mean,
      stringsAsFactors = FALSE, row.names = NULL
    )
  } else {
    data.frame(
      row = integer(0), observation_id = character(0), scope = character(0),
      scope_rank = character(0), taxon_name = character(0), theta_mean = numeric(0)
    )
  }
  .finish(out)
}
