utils::globalVariables(c(
  "species", "speciesKey", "decimalLongitude", "decimalLatitude"
))

# ==============================================================================
# check_geographic_outliers.R
# TaxaFetch -- flag bbox-scoped occurrence records that are geographic
# outliers relative to a species' own global GBIF distribution
# ==============================================================================

#' Flag Geographically Isolated Occurrence Records Against a Species' Global Range
#'
#' A bbox-scoped GBIF search (see \code{\link{get_gbif_occurrences}}) can
#' return a single occurrence for a species that is genuinely absent from
#' the study region -- a misidentification, mislabeled specimen, or bad
#' georeference elsewhere in GBIF, sitting far from that species' real
#' range. This function targets exactly that case: for species with few
#' local records, it fetches that species' unrestricted global GBIF
#' occurrences (\code{geometry = NULL}, see \code{\link{fetch_gbif_occurrences}})
#' and tests whether the local record(s) are geographic outliers against
#' that global cloud, via \code{CoordinateCleaner::cc_outl()}. Species with
#' enough local support are never checked -- the global fetch is the
#' expensive step, and a well-supported local species doesn't need it.
#'
#' @param local_occurrences A data frame of bbox-scoped GBIF occurrence
#'   records (e.g. the output of \code{\link{get_gbif_occurrences}} or
#'   \code{\link{filter_gbif_quality}}). Must contain \code{gbifID},
#'   \code{species}, \code{speciesKey}, \code{decimalLatitude}, and
#'   \code{decimalLongitude}.
#' @param min_local_n Integer. Species with fewer than this many records in
#'   \code{local_occurrences} are checked against their global distribution.
#'   Species at or above this count are left untested. Default \code{5L}.
#' @param min_occs Integer. Minimum number of geographically unique global
#'   datapoints required before a species is actually tested by
#'   \code{cc_outl()} -- below this, dispersion statistics are unreliable
#'   and the species is reported as untested rather than silently passed.
#'   Matches \code{CoordinateCleaner::cc_outl()}'s own default. Default
#'   \code{7L}.
#' @param method Character. \code{cc_outl()}'s outlier-detection method:
#'   \code{"distance"} (default here) flags a record whose nearest-neighbour
#'   distance to another same-species record exceeds \code{tdi} -- the most
#'   directly interpretable choice for "isolated from every cluster."
#'   \code{"quantile"} and \code{"mad"} are also available; see
#'   \code{CoordinateCleaner::cc_outl()} for their definitions. Only one of
#'   \code{tdi} (for \code{"distance"}) or \code{mltpl} (for
#'   \code{"quantile"}/\code{"mad"}) is used, depending on \code{method}.
#' @param tdi Numeric. Distance threshold in km, used only when
#'   \code{method = "distance"}. Matches \code{cc_outl()}'s own default,
#'   \code{1000}.
#' @param mltpl Numeric. Interquartile-range/MAD multiplier, used only when
#'   \code{method = "quantile"} or \code{"mad"}. Matches \code{cc_outl()}'s
#'   own default, \code{5}.
#' @param year_range Character. Year range for the global GBIF fetch,
#'   \code{"YYYY,YYYY"}. Default \code{"2000"} through the current year
#'   (computed at call time), matching
#'   \code{\link{fetch_gbif_occurrences}}'s own default. The global fetch
#'   characterizes the species' broader distribution, not just the local
#'   study window -- widen this if a narrow year range risks under-sampling
#'   a species' real range.
#' @param cache_dir Character or \code{NULL}. Forwarded to
#'   \code{\link{fetch_gbif_occurrences}} for checkpointing the global
#'   fetch. Default \code{tools::R_user_dir("TaxaFetch", "cache")}.
#' @param candidate_taxa Optional character vector of taxa that can actually be
#'   ASSIGNED -- typically the species-level match candidates (e.g.
#'   \code{unique(match_obj$taxon_name)}). \code{NULL} (default) preserves the
#'   pre-2026-09-05 behaviour of checking every locally-rare species in the
#'   pool. Supplying it is strongly recommended for a family-derived occurrence
#'   pool: at real PtConception 18S only 387 of 7,392 pool species (5.2%) were
#'   match candidates, so 95% of the per-species GBIF requests protected against
#'   a harm those species cannot cause. A species with 1-4 local records has a
#'   theta far below \code{TaxaAssign::join_priors()}'s
#'   \code{expansion_min_prior}, so it can never be expanded into a hypothesis;
#'   its only residual effect is +1 to the Good-Turing \code{f1}. A locally-rare
#'   MATCH CANDIDATE is the opposite: its prior multiplies its likelihood
#'   directly, which is the misidentified-record failure this check exists for.
#' @param candidate_scope How \code{candidate_taxa} restricts the check.
#'   \code{"genus"} (default) keeps any locally-rare species sharing a genus
#'   with a candidate -- congeners matter because
#'   \code{TaxaLikely::restore_suppressed_candidates()} and
#'   \code{expand_unreferenced_hypotheses()} can promote one into a named
#'   hypothesis. \code{"species"} keeps only exact candidates (tightest).
#'   \code{"all"} ignores \code{candidate_taxa} entirely. Family scoping is
#'   deliberately not offered: an occurrence pool fetched from family keys
#'   already contains only candidate families, so it would restrict nothing.
#' @param verdict_cache Logical, default \code{TRUE}. Cache the per-record
#'   VERDICTS rather than the global occurrence cloud. The cloud is reduced to
#'   one integer per species and one logical per local record and then
#'   discarded, so caching it stores millions of records to preserve a few
#'   thousand numbers. The verdict file is keyed on the species set and the
#'   \code{cc_outl()} parameters, so changing either recomputes.
#' @param verbose Logical. Forwarded to \code{cc_outl()}. Default
#'   \code{FALSE}.
#'
#' @return \code{local_occurrences} with three columns added:
#'   \describe{
#'     \item{\code{local_n}}{Number of records for this species in
#'       \code{local_occurrences}.}
#'     \item{\code{global_n_unique}}{Number of geographically unique global
#'       records found for this species. \code{NA} for species never
#'       checked (\code{local_n >= min_local_n}).}
#'     \item{\code{outlier_status}}{One of \code{"not_tested_sufficient_local_data"}
#'       (local_n >= min_local_n, never checked), \code{"insufficient_global_data"}
#'       (checked, but fewer than \code{min_occs} unique global points --
#'       cannot compute a reliable dispersion statistic),
#'       \code{"outlier"} (flagged by \code{cc_outl()}), or
#'       \code{"consistent"} (checked, not flagged). Never a bare logical --
#'       "not tested" and "tested and passed" are kept distinct throughout,
#'       mirroring \code{\link{check_inat_range}}'s \code{range_status}
#'       convention.}
#'   }
#'
#' @details
#' \strong{Why this needs a global fetch at all:} \code{local_occurrences}
#' comes from a bbox-scoped GBIF search, so a species with one local record
#' has nothing else in the same dataset to compare it against --
#' \code{cc_outl()} needs a real distribution, not one point. The global
#' fetch is gated to only the species below \code{min_local_n}, since a
#' well-supported local species needs no such check and the global fetch is
#' the expensive step. This is a targeted, per-species-rare extension of
#' \code{\link{fetch_gbif_occurrences}} (\code{geometry = NULL}) -- see that
#' function for rate-limit/retry/checkpoint behavior, all inherited
#' unchanged here.
#'
#' \strong{\code{min_occs} is a real floor, not a formality:} a species
#' with too few unique global points (even after the global fetch) simply
#' cannot support a reliable outlier test -- \code{cc_outl()} itself passes
#' such species by default rather than testing them. This function makes
#' that distinction explicit via \code{"insufficient_global_data"} rather
#' than folding it into \code{"consistent"}, so a downstream consumer never
#' mistakes "we couldn't check" for "we checked and it's fine."
#'
#' \strong{\code{cc_outl()} is called once per species, not once for the
#' whole batch:} confirmed on real production data (2026-07-20) that its
#' \code{"distance"} method silently switches EVERY species in a single call
#' to a coarser raster approximation whenever ANY ONE species in that call
#' has 10,000 or more records. A species rare in the local bbox can still be
#' globally common, so calling \code{cc_outl()} once across every rare
#' species let one common species silently degrade every other species'
#' precision -- this cleared a real, obvious ~9,000 km outlier (a Mugu
#' \emph{Pseudotolithus epipercus} record) on first live use. Per-species
#' calls scope that raster decision to each species' own record count,
#' where it belongs; the extra R-level call overhead is negligible next to
#' the GBIF fetch itself.
#'
#' @seealso \code{\link{fetch_gbif_occurrences}}, \code{\link{get_gbif_occurrences}},
#'   \code{\link{filter_gbif_quality}}, \code{\link{check_inat_range}}
#'
#' @importFrom dplyr count distinct
#' @export
#'
#' @examples
#' \dontrun{
#' occ <- get_gbif_occurrences(keys = valid_keys, geometry = bbox)
#' occ <- filter_gbif_quality(occ)
#' occ <- check_geographic_outliers(occ, min_local_n = 5L)
#' occ[occ$outlier_status == "outlier", ]
#' }
check_geographic_outliers <- function(
  local_occurrences,
  min_local_n = 5L,
  min_occs = 7L,
  method = "distance",
  tdi = 1000,
  mltpl = 5,
  year_range = .gbif_default_year_range(),
  cache_dir = tools::R_user_dir("TaxaFetch", "cache"),
  candidate_taxa = NULL,
  candidate_scope = c("genus", "species", "all"),
  verdict_cache = TRUE,
  verbose = FALSE
) {
  candidate_scope <- match.arg(candidate_scope)

  # --- Dependency check ---------------------------------------------------
  if (!requireNamespace("CoordinateCleaner", quietly = TRUE)) {
    stop(
      "check_geographic_outliers: package 'CoordinateCleaner' is required.\n",
      "Install it with: install.packages('CoordinateCleaner')"
    )
  }

  # --- Input checks ---------------------------------------------------------
  if (!is.data.frame(local_occurrences)) {
    stop("check_geographic_outliers: 'local_occurrences' must be a data frame.")
  }
  required_cols <- c(
    "gbifID", "species", "speciesKey",
    "decimalLatitude", "decimalLongitude"
  )
  missing_cols <- setdiff(required_cols, names(local_occurrences))
  if (length(missing_cols) > 0L) {
    stop(
      "check_geographic_outliers: missing required column(s): ",
      paste(missing_cols, collapse = ", ")
    )
  }

  local_occurrences$global_n_unique <- NA_integer_
  local_occurrences$outlier_status <- "not_tested_sufficient_local_data"

  local_counts <- dplyr::count(local_occurrences, species, name = "local_n")
  local_occurrences$local_n <- local_counts$local_n[
    match(local_occurrences$species, local_counts$species)
  ]

  rare_species <- local_counts$species[local_counts$local_n < min_local_n]

  if (length(rare_species) == 0L) {
    message("check_geographic_outliers: every species clears min_local_n -- nothing to check.")
    return(local_occurrences)
  }

  is_rare_row <- local_occurrences$species %in% rare_species

  # ---- Restrict to taxa that can actually reach a hypothesis ---------------
  # A bbox occurrence pool built from FAMILY-level keys is enormously wider
  # than the species-level candidates it exists to support: at PtConception 18S
  # only 387 of 7,392 pool species (5.2%) are match candidates, and only 613 of
  # 3,133 genera contain one. Checking the other 95% costs one GBIF request per
  # species (829 of them, ~14 s each once GBIF starts rate-limiting) to protect
  # against a harm they cannot cause: a species with 1-4 local records has a
  # theta orders of magnitude below join_priors()'s expansion_min_prior, so it
  # can never be expanded into a hypothesis. Its only residual effect is +1 to
  # f1. A locally-rare MATCH CANDIDATE is the opposite case -- its prior
  # multiplies its likelihood directly, which is the misidentified-record
  # failure this whole check was built for.
  #
  # "genus" (default when candidate_taxa is supplied) also keeps congeners,
  # because restore_suppressed_candidates()/expand_unreferenced_hypotheses()
  # can promote a congener of a match candidate into a named hypothesis --
  # the same harm one step removed. "all" restores the pre-2026-09-05 sweep.
  if (!is.null(candidate_taxa) && !identical(candidate_scope, "all")) {
    candidate_taxa <- unique(stats::na.omit(as.character(candidate_taxa)))
    keep_sp <- if (identical(candidate_scope, "species")) {
      rare_species %in% candidate_taxa
    } else {
      cand_genera <- unique(sub(" .*$", "", candidate_taxa))
      sub(" .*$", "", rare_species) %in% cand_genera
    }
    n_before <- length(rare_species)
    rare_species <- rare_species[keep_sp]
    message(sprintf(
      paste0(
        "check_geographic_outliers: %d of %d locally-rare species are ",
        "assignable (candidate_scope = \"%s\"); the other %d cannot reach ",
        "a hypothesis and are not checked."
      ),
      length(rare_species), n_before, candidate_scope, n_before - length(rare_species)
    ))
    if (length(rare_species) == 0L) {
      message("check_geographic_outliers: no assignable rare species -- nothing to check.")
      return(local_occurrences)
    }
    is_rare_row <- local_occurrences$species %in% rare_species
  }

  rare_keys <- unique(local_occurrences$speciesKey[is_rare_row])
  rare_keys <- rare_keys[!is.na(rare_keys)]

  if (length(rare_keys) == 0L) {
    message(
      "check_geographic_outliers: ", length(rare_species),
      " rare species have no usable speciesKey -- cannot fetch global data."
    )
    local_occurrences$outlier_status[is_rare_row] <- "insufficient_global_data"
    return(local_occurrences)
  }

  message(sprintf(
    paste0(
      "check_geographic_outliers: %d/%d species have fewer than %d local ",
      "record(s) -- fetching global GBIF occurrences for outlier testing."
    ),
    length(rare_species), length(unique(local_occurrences$species)), min_local_n
  ))

  # ---- Verdict cache -------------------------------------------------------
  # The global cloud is reduced to TWO durable values -- one integer per
  # species (global_n_unique) and one logical per local record (cc_pass) --
  # and then discarded. Caching the raw cloud therefore stores millions of
  # records to preserve a few thousand numbers. Cache the verdicts instead,
  # keyed by the species set actually checked.
  .verdict_path <- if (isTRUE(verdict_cache) && !is.null(cache_dir)) {
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
    file.path(cache_dir, sprintf(
      "gbif_outlier_verdicts_%dsp_s%d_%s_%s.rds",
      length(rare_keys), as.integer(sum(as.numeric(rare_keys)) %% 1e9),
      gsub("[^0-9]", "", year_range),
      paste0(method, "_", min_occs, "_", tdi, "_", mltpl)
    ))
  } else {
    NULL
  }

  cached_verdicts <- NULL
  if (!is.null(.verdict_path) && file.exists(.verdict_path)) {
    cached_verdicts <- tryCatch(readRDS(.verdict_path), error = function(e) NULL)
    if (!is.null(cached_verdicts)) {
      message(sprintf(
        "check_geographic_outliers: reusing cached verdicts for %d species (%s). Delete to recompute.",
        length(rare_keys), basename(.verdict_path)
      ))
    }
  }

  if (is.null(cached_verdicts)) {
    # Routed through get_gbif_occurrences() (2026-09-05) so this inherits the
    # backend switch: above key_threshold it uses the async download API (one
    # request, one zip) instead of one HTTP request per key. The per-key path
    # earned a GBIF rate-limit block at ~360 keys -- "Too many requests! To
    # download GBIF occurrence data in bulk, please use occ_download()" -- which
    # is GBIF telling us directly to do this. limit = NULL because the default
    # 10,000-per-key cap truncates by RETURN ORDER, and this cloud is the
    # reference the outlier test measures "normal range" against: a
    # dataset-clustered prefix biases the very thing being estimated.
    global_occ <- get_gbif_occurrences(
      keys = rare_keys,
      geometry = NULL,
      year_range = year_range,
      limit = NULL,
      # rank_filter = NULL, NOT the wrapper's "species" default: the previous
      # direct fetch_gbif_occurrences() call applied no rank filter, and this
      # change is a BACKEND switch, not a change to which records qualify.
      # (Genus-only records are excluded from the verdict anyway -- cc_outl() is
      # run per `species`, so a blank species never forms a cloud.) Revisit
      # deliberately if you want them dropped earlier.
      rank_filter = NULL,
      cache_dir = cache_dir
    )

    if (nrow(global_occ) == 0L) {
      local_occurrences$outlier_status[is_rare_row] <- "insufficient_global_data"
      return(local_occurrences)
    }

    global_counts <- global_occ |>
      dplyr::distinct(species, decimalLongitude, decimalLatitude) |>
      dplyr::count(species, name = "global_n_unique")

    global_occ$.global_n_unique <- global_counts$global_n_unique[
      match(global_occ$species, global_counts$species)
    ]

    # cc_outl() is called ONCE PER SPECIES, not once for the whole combined
    # batch -- confirmed on real production data (2026-07-20) that its
    # "distance" method silently switches EVERY species in a single call to a
    # coarser raster approximation whenever ANY ONE species in that call has
    # >=10,000 records (CoordinateCleaner::cc_outl's own
    # `if (any(record_numbers >= 10000)) { warning("Using raster
    # approximation.") ... }`, scoped to the whole call, not per species). A
    # locally-rare species can still be globally common, so batching every
    # rare species into one cc_outl() call let one common species silently
    # degrade every other species' precision -- this cleared a real, obvious
    # ~9,000 km outlier (a Mugu Pseudotolithus epipercus record) that a
    # per-species call correctly flags. Per-species calls scope that raster
    # decision to each species' own record count, where it belongs.
    #
    # cc_outl() also warns about species below min_occs -- suppressed here
    # because check_geographic_outliers() already reports that per-row and
    # explicitly via outlier_status = "insufficient_global_data", not just to
    # the console.
    cc_pass <- rep(NA, nrow(global_occ))
    for (sp in unique(global_occ$species)) {
      sp_rows <- which(global_occ$species == sp)
      cc_pass[sp_rows] <- suppressWarnings(CoordinateCleaner::cc_outl(
        x        = global_occ[sp_rows, , drop = FALSE],
        lon      = "decimalLongitude",
        lat      = "decimalLatitude",
        species  = "species",
        method   = method,
        mltpl    = mltpl,
        tdi      = tdi,
        min_occs = min_occs,
        value    = "flagged",
        verbose  = verbose
      ))
    }
    global_occ$.cc_pass <- cc_pass

    # Reduce to the durable artifact and drop the cloud: one row per global
    # record that a LOCAL rare record can join to, carrying only the two values
    # the verdict needs.
    cached_verdicts <- data.frame(
      gbifID = global_occ$gbifID,
      global_n_unique = global_occ$.global_n_unique,
      cc_pass = global_occ$.cc_pass,
      stringsAsFactors = FALSE
    )
    cached_verdicts <- cached_verdicts[
      cached_verdicts$gbifID %in% local_occurrences$gbifID[is_rare_row], ,
      drop = FALSE
    ]
    if (!is.null(.verdict_path)) {
      saveRDS(cached_verdicts, .verdict_path)
      message(sprintf(
        "check_geographic_outliers: cached %d verdict row(s) (%.2f MB) -- the global cloud itself is not retained.",
        nrow(cached_verdicts), file.info(.verdict_path)$size / 1024^2
      ))
    }
  } # end recompute block

  match_pos <- match(local_occurrences$gbifID[is_rare_row], cached_verdicts$gbifID)

  matched_n_unique <- cached_verdicts$global_n_unique[match_pos]
  matched_cc_pass <- cached_verdicts$cc_pass[match_pos]

  status <- ifelse(
    is.na(matched_n_unique) | matched_n_unique < min_occs,
    "insufficient_global_data",
    ifelse(matched_cc_pass, "consistent", "outlier")
  )

  local_occurrences$global_n_unique[is_rare_row] <- matched_n_unique
  local_occurrences$outlier_status[is_rare_row] <- status

  local_occurrences
}
