utils::globalVariables(c("taxon_name"))

#' Presence Evidence From Records Whose Habitat Could Not Be Resolved
#'
#' Prices the taxa that the kernel estimator cannot see: those with records
#' near the site, all of them at points whose habitat is unassigned, and none
#' in the site's habitat stratum. Returns a standard evidence table for
#' \code{\link{apply_undetected_evidence}}, so these taxa appear in the priors
#' as present in the region instead of vanishing.
#'
#' @details
#' \strong{The gap this closes.} \code{\link{estimate_kernel_priors}} keeps
#' only records whose point carries \code{site_habitat}
#' (\code{keep <- !is.na(hab) & hab == site_habitat}). A point the habitat
#' consensus could not place fails that test whatever it is labelled -- as
#' \code{NA} because it fails \code{!is.na()}, as any other non-matching
#' string because it fails the equality -- so a taxon whose nearby records all
#' sit at such points yields no resident row.
#'
#' \strong{Why \code{habitat_levels} rather than a list of sentinels.} This
#' function has to tell an UNPLACEABLE point (recoverable) from one placed in a
#' DIFFERENT habitat (correctly excluded, not this function's business). The
#' obvious way is to test against the producer's sentinels -- \code{NA},
#' \code{""}, \code{"Uncertain"}. That makes this package responsible for
#' tracking a vocabulary it does not own: add a sentinel in the habitat
#' producer and the test here keeps returning \code{FALSE} for it, silently,
#' with nothing failing. Note also that the producer may not be
#' \code{TaxaHabitat} at all -- a habitat column can come from a polygon
#' layer, which is why TaxaExpect only \emph{Suggests} that package.
#'
#' So the test is CLOSED-WORLD instead: unassigned is anything that is not one
#' of the scheme's own declared habitats, which the caller already has in hand
#' (\code{simple_scheme$l1_name} in the standard workflows). \code{NA} and
#' \code{""} fall out for free, any sentinel invented later is caught without
#' a code change, and so is a typo. The failure mode moves from silent
#' under-recovery to a warning: a label that is neither a declared habitat nor
#' a recognisable no-verdict marker would be RECOVERED as evidence -- the
#' unsafe direction -- so the function names those labels rather than acting on
#' them quietly.
#'
#' Downstream, the standard workflow builds its evidence candidate list as
#' \code{setdiff(match_list, taxaexpect_priors$taxon_name)}: every taxon with
#' no prior row. Such a taxon therefore reaches
#' \code{\link{generate_regional_proximity_evidence}} labelled
#' \strong{zero-bbox} -- priced as having no records in the search polygon at
#' all, and re-queried from GBIF to find its nearest one. That claim is false.
#' The records exist, they are in the bbox, and their distance is already
#' known exactly from the occurrence table. The information was not merely
#' lost; it was discarded and then replaced by a coarser estimate from a
#' second data source, with nothing reporting the substitution.
#'
#' \strong{Not the same thing as a habitat-agnostic prior.} A
#' \code{main_habitat} of \code{NA} in a PRIORS table means "matches any
#' habitat" -- \code{\link{generate_domestic_food_priors}} sets it
#' deliberately, and \code{TaxaAssign::join_priors()} reads it to build the
#' domestic/food wildcard tier. An occurrence whose habitat could not be
#' determined is the opposite claim: a real organism at a real place, whose
#' place could not be classified. Rows from this function are ordinary
#' evidence rows carrying \code{source = "uncertain_habitat_proximity"}; they
#' never enter that wildcard tier.
#'
#' \strong{Pricing.} The same saturating decay
#' \code{\link{generate_regional_proximity_evidence}} uses, on the distance to
#' the taxon's nearest \emph{unassigned-habitat} record:
#' \deqn{w = w_{scale} \times \exp(-d_{nearest} / d_{half})}
#' measured directly from the occurrence table, with no network call. Records
#' at points assigned to a DIFFERENT habitat are ignored: those were excluded
#' because their habitat is known and wrong, which is a correct exclusion and
#' not this function's business.
#'
#' \strong{What is still unknown, and who resolves it.} This weight answers
#' "is the taxon present near the site", not "does it occupy the site
#' habitat" -- the point's habitat is precisely what could not be determined.
#' Pass the result through
#' \code{\link{condition_evidence_on_habitat}} exactly as for the other
#' generators: with the point uninformative, the taxon's own habitat weight
#' is the right fallback, and it is applied on the same footing as every
#' other evidence row rather than as a special case.
#'
#' \strong{The count is a floor, deliberately.} A taxon is skipped when it has
#' ANY record in the focal stratum, because such a taxon normally has a
#' resident row and adding evidence would double-count it. Whether it
#' \emph{actually} has a row can depend on filters
#' \code{\link{estimate_kernel_priors}} applies downstream of the stratum --
#' a year window, for instance. A taxon whose only in-stratum records fall
#' outside such a filter is skipped here, keeps no resident row, and stays on
#' the zero-bbox path exactly as before. That is the pre-existing behaviour and
#' it errs toward under-recovery, which is the safe direction: this function
#' can only ever fail to rescue a taxon, never inflate one. Read the returned
#' row count as a lower bound on the affected population, not the whole of it.
#'
#' \strong{Scale.} On PtConception 12S this population was 31,383 unassigned
#' points before a pre-fetch scope filter and 145 after it -- 99.9% of the
#' records that motivated this function were out-of-scope birds that should
#' never have been fetched. Expect a small residual, and treat a large one as
#' a scope-filter problem first.
#'
#' @param occurrence_data Data frame of cleaned, habitat-labelled occurrence
#'   records (one row per record) -- the same table given to
#'   \code{\link{estimate_kernel_priors}}.
#' @param site_lat,site_lon Numeric scalars. Sampling site coordinates.
#' @param site_habitat Character scalar. The focal habitat. A taxon with ANY
#'   record in this stratum is excluded: it already has a resident prior, and
#'   adding evidence would double-count it. Must be one of
#'   \code{habitat_levels}.
#' @param habitat_levels Character vector of the scheme's real habitat names --
#'   in the standard workflows, \code{simple_scheme$l1_name}. Everything in
#'   \code{habitat_col} that is not one of these is treated as unassigned.
#'   \strong{No default, deliberately}: a default would be a copy of some
#'   producer's sentinel vocabulary living at this function's declaration site,
#'   which is the coupling the closed-world test exists to avoid. See Details.
#' @param taxa Optional character vector restricting the result to taxa of
#'   interest (e.g. the marker's match list). \code{NULL} (default) considers
#'   every taxon in \code{occurrence_data}.
#' @param d_half Numeric > 0. Distance (km) at which the weight is half
#'   \code{w_scale}. Default \code{150}, matching
#'   \code{\link{generate_regional_proximity_evidence}}. Pass the run's own
#'   value so the two sources are priced on one scale.
#' @param w_scale Numeric in (0, 1]. Weight at zero distance. Default
#'   \code{1}. Pass the run's own value.
#' @param year_col Optional column of record years. When supplied,
#'   \code{p_conc = exp(-age_years / age_half)} from the nearest record's
#'   year, matching the regional-proximity generator. \code{NULL} (default)
#'   leaves \code{p_conc = 1}.
#' @param age_half Numeric > 0. Age (years) at which \code{p_conc} halves.
#'   Default \code{15}. Ignored when \code{year_col} is \code{NULL}.
#' @param taxon_col,lat_col,lon_col,habitat_col Column names in
#'   \code{occurrence_data}. Defaults \code{"taxon_name"},
#'   \code{"decimalLatitude"}, \code{"decimalLongitude"},
#'   \code{"main_habitat"}.
#' @param verbose Logical. Report counts. Default \code{TRUE}.
#'
#' @return A data frame, one row per qualifying taxon, with the evidence
#'   schema \code{\link{apply_undetected_evidence}} expects --
#'   \code{taxon_name}, \code{weight}, \code{p_conc}, \code{source} (always
#'   \code{"uncertain_habitat_proximity"}) -- plus audit columns
#'   \code{distance_km} (to the nearest unassigned-habitat record),
#'   \code{n_records_unassigned} (how many such records the taxon has) and
#'   \code{record_year}/\code{age_years} (\code{NA} without \code{year_col}).
#'   Zero rows with the correct schema when nothing qualifies, which is the
#'   expected result on a well-scoped dataset.
#'
#' @seealso \code{\link{estimate_kernel_priors}},
#'   \code{\link{condition_evidence_on_habitat}},
#'   \code{\link{apply_undetected_evidence}},
#'   \code{\link{generate_regional_proximity_evidence}}
#' @export
#' @examples
#' occ <- data.frame(
#'   taxon_name       = c("Sebastes mystinus", "Embiotoca jacksoni", "Gadus morhua"),
#'   decimalLatitude  = c(34.40, 34.45, 34.50),
#'   decimalLongitude = c(-120.40, -120.45, -120.50),
#'   main_habitat     = c("Marine", "Uncertain", NA)
#' )
#' # Sebastes has a Marine record (resident prior exists) and is excluded;
#' # the other two are known only from unplaceable points. "Uncertain" and NA
#' # are both unassigned because neither is in habitat_levels -- the function
#' # is never told what the sentinels are.
#' generate_uncertain_habitat_evidence(
#'   occ, site_lat = 34.4, site_lon = -120.4, site_habitat = "Marine",
#'   habitat_levels = c("Marine", "Estuarine", "Freshwater", "Terrestrial")
#' )
generate_uncertain_habitat_evidence <- function(occurrence_data,
                                                site_lat,
                                                site_lon,
                                                site_habitat,
                                                habitat_levels,
                                                taxa = NULL,
                                                d_half = 150,
                                                w_scale = 1,
                                                year_col = NULL,
                                                age_half = 15,
                                                taxon_col = "taxon_name",
                                                lat_col = "decimalLatitude",
                                                lon_col = "decimalLongitude",
                                                habitat_col = "main_habitat",
                                                verbose = TRUE) {
  if (!is.data.frame(occurrence_data)) {
    stop("generate_uncertain_habitat_evidence: `occurrence_data` must be a data frame.", call. = FALSE)
  }
  for (nm in c(taxon_col, lat_col, lon_col, habitat_col)) {
    if (!nm %in% names(occurrence_data)) {
      stop(sprintf("generate_uncertain_habitat_evidence: `occurrence_data` is missing required column '%s'.", nm), call. = FALSE)
    }
  }
  for (nm in c("site_lat", "site_lon")) {
    v <- get(nm)
    if (!is.numeric(v) || length(v) != 1L || is.na(v)) {
      stop(sprintf("generate_uncertain_habitat_evidence: `%s` must be a single non-NA number.", nm), call. = FALSE)
    }
  }
  if (!is.character(site_habitat) || length(site_habitat) != 1L || is.na(site_habitat)) {
    stop("generate_uncertain_habitat_evidence: `site_habitat` must be a single non-NA habitat name.", call. = FALSE)
  }
  if (missing(habitat_levels) || !is.character(habitat_levels) ||
      length(habitat_levels) == 0L || anyNA(habitat_levels) ||
      !all(nzchar(trimws(habitat_levels)))) {
    stop("generate_uncertain_habitat_evidence: `habitat_levels` must be the scheme's real habitat names, e.g. simple_scheme$l1_name. It has no default on purpose -- see Details.", call. = FALSE)
  }
  habitat_levels <- unique(as.character(habitat_levels))
  if (!site_habitat %in% habitat_levels) {
    stop(sprintf("generate_uncertain_habitat_evidence: `site_habitat` ('%s') is not one of `habitat_levels` (%s). A site must be declared as one of the scheme's own habitats.",
                 site_habitat, paste(habitat_levels, collapse = ", ")), call. = FALSE)
  }
  if (!is.numeric(d_half) || length(d_half) != 1L || is.na(d_half) || d_half <= 0) {
    stop("generate_uncertain_habitat_evidence: `d_half` must be a single positive number.", call. = FALSE)
  }
  if (!is.numeric(w_scale) || length(w_scale) != 1L || is.na(w_scale) || w_scale <= 0 || w_scale > 1) {
    stop("generate_uncertain_habitat_evidence: `w_scale` must be a single number in (0, 1].", call. = FALSE)
  }
  if (!is.null(year_col)) {
    if (!is.character(year_col) || length(year_col) != 1L || !year_col %in% names(occurrence_data)) {
      stop("generate_uncertain_habitat_evidence: `year_col` must name a column of `occurrence_data`, or be NULL.", call. = FALSE)
    }
    if (!is.numeric(age_half) || length(age_half) != 1L || is.na(age_half) || age_half <= 0) {
      stop("generate_uncertain_habitat_evidence: `age_half` must be a single positive number.", call. = FALSE)
    }
  }

  .empty <- data.frame(
    taxon_name = character(0), weight = numeric(0), p_conc = numeric(0),
    source = character(0), distance_km = numeric(0),
    n_records_unassigned = integer(0), record_year = numeric(0),
    age_years = numeric(0), stringsAsFactors = FALSE
  )

  tx  <- as.character(occurrence_data[[taxon_col]])
  hab <- occurrence_data[[habitat_col]]
  la  <- suppressWarnings(as.numeric(occurrence_data[[lat_col]]))
  lo  <- suppressWarnings(as.numeric(occurrence_data[[lon_col]]))
  usable <- !is.na(tx) & !is.na(la) & !is.na(lo)

  # A taxon with ANY record in the focal stratum already has a resident row.
  # CLOSED-WORLD test. "Unassigned" is anything that is not one of the scheme's
  # declared habitats -- not a list of sentinel spellings this package has to
  # keep in step with whoever produced the column. NA and "" fall out for free
  # (`%in%` is FALSE for NA), and so does any sentinel invented later.
  hab_chr <- as.character(hab)
  unassigned <- !(hab_chr %in% habitat_levels)

  # A label that is neither a declared habitat nor a recognisable "no verdict"
  # marker is almost always a typo or a scheme the caller forgot to widen --
  # and it would be silently RECOVERED as evidence, which is the unsafe
  # direction. Say so rather than let it through quietly.
  .odd <- setdiff(unique(hab_chr[unassigned & !is.na(hab_chr)]), c("", "Uncertain"))
  .odd <- .odd[nzchar(trimws(.odd))]
  if (length(.odd)) {
    warning(sprintf(
      "generate_uncertain_habitat_evidence: %d habitat label(s) are not in `habitat_levels` and are being treated as UNASSIGNED: %s. If any of these is a real habitat, add it to `habitat_levels` -- otherwise its records are recovered as evidence.",
      length(.odd), paste(utils::head(.odd, 10), collapse = ", ")), call. = FALSE)
  }

  in_stratum <- usable & hab_chr == site_habitat & !is.na(hab_chr)
  resident_taxa <- unique(tx[in_stratum])

  cand <- usable & unassigned & !(tx %in% resident_taxa)
  if (!is.null(taxa)) cand <- cand & tx %in% as.character(taxa)

  if (!any(cand)) {
    if (isTRUE(verbose)) {
      message(sprintf(
        "generate_uncertain_habitat_evidence: no qualifying taxa -- %d record(s) at unassigned-habitat points, all belonging to taxa that already have '%s' records.",
        sum(usable & unassigned), site_habitat
      ))
    }
    return(.empty)
  }

  # Same cosine-corrected great-circle approximation as estimate_kernel_priors(),
  # so the two distance scales are the same quantity.
  d_km <- 111 * sqrt((la[cand] - site_lat)^2 +
                       ((lo[cand] - site_lon) * cos(site_lat * pi / 180))^2)
  ctx  <- tx[cand]
  cyr  <- if (is.null(year_col)) rep(NA_real_, sum(cand)) else suppressWarnings(as.numeric(occurrence_data[[year_col]][cand]))

  ord <- order(ctx, d_km)
  first <- !duplicated(ctx[ord])
  keep_i <- ord[first]

  out <- data.frame(
    taxon_name           = ctx[keep_i],
    distance_km          = d_km[keep_i],
    n_records_unassigned = as.integer(table(ctx)[ctx[keep_i]]),
    record_year          = cyr[keep_i],
    stringsAsFactors     = FALSE
  )
  out$weight <- w_scale * exp(-out$distance_km / d_half)
  out$age_years <- if (is.null(year_col)) {
    NA_real_
  } else {
    pmax(0, as.numeric(format(Sys.Date(), "%Y")) - out$record_year)
  }
  out$p_conc <- if (is.null(year_col)) 1 else ifelse(is.na(out$age_years), 1, exp(-out$age_years / age_half))
  out$source <- "uncertain_habitat_proximity"
  out <- out[order(-out$weight), c("taxon_name", "weight", "p_conc", "source",
                                   "distance_km", "n_records_unassigned",
                                   "record_year", "age_years")]
  rownames(out) <- NULL

  if (isTRUE(verbose)) {
    message(sprintf(
      "generate_uncertain_habitat_evidence: %d taxon/taxa recovered from %d record(s) at unassigned-habitat points (nearest %.1f km, median %.1f km). These had NO resident row and would otherwise have been priced as zero-bbox.",
      nrow(out), sum(cand), min(out$distance_km), stats::median(out$distance_km)
    ))
  }
  out
}
