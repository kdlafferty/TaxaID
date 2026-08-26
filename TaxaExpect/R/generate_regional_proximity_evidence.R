#' Evidence rows for species with a real GBIF record just outside the study bbox
#'
#' A thin, two-stage evidence generator for
#' \code{\link{apply_undetected_evidence}}: for each taxon with no in-bbox
#' occurrence record, cheaply checks whether GBIF has ANY record nearby at
#' all (Stage 1), and only pays for a real, quality-screened fetch to find
#' the actual nearest record and its age for the taxa where that cheap check
#' finds something (Stage 2). Implements
#' \code{ecosystem_docs/REENTRY_PROMPT_regional_proximity_prior_check.md}.
#'
#' @section Stage 1 -- cheap gate, no quality filtering possible:
#' \code{\link[TaxaFlag]{check_gbif_tile_range}} reads presence/
#' absence off GBIF's pre-rendered density tiles for a handful of tile
#' downloads, regardless of how many records exist worldwide. This is
#' deliberately the ONLY thing a bare density tile can answer -- a pixel
#' carries no per-record fields, so no eDNA-keyword/coordinate-quality/
#' institution-proximity screening is possible at this stage (the same
#' "raw/unfiltered" caveat already documented on that function itself). Most
#' taxa are expected to come back \code{beyond_buffer = TRUE} even after
#' escalation; that IS the answer for them -- no further cost, no evidence
#' row, the species stays at the ordinary dark-diversity floor.
#'
#' @section Stage 2 -- real, filtered fetch, only for taxa Stage 1 found something for:
#' A real \code{TaxaFetch::get_gbif_occurrences()} call, scoped to a buffer
#' around the study site sized from Stage 1's own reported distance (not a
#' global fetch), run through \code{TaxaFetch::filter_gbif_quality()} -- the
#' same eDNA-exclusion/coordinate-quality/\pkg{CoordinateCleaner} checks
#' every other GBIF pull in this ecosystem gets, closing the exact gap Stage
#' 1 structurally cannot. A bad single record can trigger a wasted Stage 2
#' fetch, but can never move a prior on its own, since only the filtered
#' survivors ever produce an evidence row. \code{\link[TaxaFlag]{compute_local_occurrence_distance}}
#' (extended this session with \code{date_col}) then gives the real distance
#' AND the matched record's age from the filtered data.
#'
#' @section From distance/age to weight/p_conc -- deliberately NOT a connectivity check:
#' An earlier design explored a watershed/basin-connectivity gate (is the
#' nearby record even in a hydrologically connected water body) before being
#' explicitly dropped: this package needs to stay simple and generalize
#' across a wide range of taxa and geographic settings, and hydrological
#' connectivity is a specific-study solve, not a generalizable primitive.
#' Raw distance is the only generic signal used. The geographic-plausibility
#' judgment (is a record 100km away actually reachable, given basin/
#' dispersal-barrier structure) is left to a human or LLM reviewer with real
#' domain knowledge, not computed here -- see
#' \code{TaxaFlag::review_assignments()}'s existing GBIF-tile-context
#' annotation pattern for the established way to surface facts like this for
#' that judgment, rather than encoding a rule.
#'
#' Weight (how far toward the singleton ceiling this pulls the prior's MEAN)
#' is a saturating decay in distance: \code{weight = exp(-distance_km /
#' d_half)} -- read as P(locally present | nearest record at this distance)
#' under the 2026-08-26 presence-mixture redesign. Presence-claim confidence
#' (\code{p_conc}, how much weight the claim carries against future
#' evidence -- NOT the static prior's concentration, which is now
#' moment-matched by \code{\link{apply_undetected_evidence}}) is a
#' saturating decay in record age: \code{p_conc = exp(-age_years /
#' age_half)} -- a fresh record counts as one pseudo-observation about
#' presence, an old record as less than one. These are deliberately two independent
#' knobs, not one composite score -- an old record doesn't mean the species
#' is systematically LESS likely to be present (it could reflect a real,
#' still-extant population never resurveyed, or a range that has since
#' contracted; occurrence data alone can't tell these apart), so age widens
#' uncertainty around the same distance-driven mean rather than discounting
#' the mean itself. A record with no usable \code{year} value gets
#' \code{p_conc = 1} (no extra discount, not a value in between) --
#' absence of age information is not evidence of great age.
#'
#' \code{d_half}/\code{age_half} ship with a default
#' but are fully overridable -- there is no universally defensible distance
#' or age scale across taxa (a sedentary benthic invertebrate and a highly
#' vagile bird do not share a dispersal-distance order of magnitude), so the
#' defaults are a starting point to adjust for your own study system, not a
#' claim of correctness. See \verb{Choosing d_half/age_half} below for how
#' each one shapes the output.
#'
#' @section Choosing d_half/age_half:
#' \code{weight = exp(-distance_km / d_half)} -- \code{d_half} is the
#' distance at which the pull toward the singleton-mirror ceiling has
#' decayed to half its maximum. At the default \code{d_half = 150}: a record
#' 100km away gives \code{weight ~= 0.51} (a real, substantial pull); a
#' record 3000km away gives \code{weight ~= 4e-9} (indistinguishable from no
#' evidence at all). Halving \code{d_half} halves how far a given weight
#' reaches; doubling it reaches twice as far for the same weight.
#' \code{age_half} works the same way on \code{age_years} instead of
#' \code{distance_km}, controlling \code{p_conc} instead of the mean -- at the
#' default \code{age_half = 15}, a 15-year-old record's presence claim is held
#' with half the effective confidence of a fresh one.
#'
#' @param zero_bbox_taxa Character vector of taxon names with no in-bbox
#'   occurrence record this run -- typically every named candidate absent
#'   from \code{taxaexpect_priors} entirely. Required, no default.
#' @param lat,lng Numeric scalars. The study site's own coordinates (Stage 1
#'   and Stage 2 both search around this point).
#' @param d_half Numeric > 0. Distance (km) at which \code{weight} decays to
#'   half its maximum -- see \verb{Choosing d_half/age_half}. Default
#'   \code{150}.
#' @param age_half Numeric > 0. Record age (years) at which \code{p_conc}
#'   decays to half its fresh-record value of 1 -- see
#'   \verb{Choosing d_half/age_half}.
#'   Default \code{15}.
#' @param tile_zoom Integer. Forwarded to
#'   \code{TaxaFlag::check_gbif_tile_range(zoom = )} for Stage 1. Default
#'   \code{6L} (roughly continental scale).
#' @param buffer_margin Numeric > 1. Stage 2's fetch radius is Stage 1's own
#'   \code{dist_nearest_occupied_km} times this margin (tile-pixel distance
#'   is coarse, so the real nearest record may sit a bit further than the
#'   tile-resolution estimate) -- clamped to
#'   \verb{[min_buffer_km, max_buffer_km]}. Default \code{1.5}.
#' @param min_buffer_km,max_buffer_km Numeric. Floor/ceiling on Stage 2's
#'   fetch radius, regardless of what Stage 1 reported. Defaults \code{50}/
#'   \code{1000}.
#' @param near_lat_tolerance_deg Numeric > 0. A second, complementary test to
#'   the nearest-point distance above: at least \code{near_occurrence_min_n}
#'   of a taxon's Stage-2-filtered records must fall within this many degrees
#'   of latitude of \code{lat} (proportional fallback when a taxon has fewer
#'   total filtered records than that -- see \code{near_occurrence_min_n}).
#'   Ported from \code{build_invasive_candidates.R}'s own identically-named
#'   safeguard (\code{ecosystem_docs/REENTRY_PROMPT_invasive_species_watch_list_priors.md}),
#'   built after a real GLANSIS benchmark comparison found the plain nearest-
#'   point test alone is precision-poor: several species passed it purely on
#'   the strength of ONE isolated occurrence record (a stray record, or a
#'   real but climatically-artificial thermal-discharge refugium) while the
#'   bulk of that species' real range sat many latitude degrees away --
#'   climate-implausible warm-water species were the dominant real pattern.
#'   Latitude (not full geodesic distance) is used deliberately as a cheap
#'   climate-tolerance proxy -- thermal/seasonal regime tracks latitude far
#'   more than longitude for a fixed distance budget. Default \code{6}
#'   (~660km, matching \code{build_invasive_candidates()}'s own tuned value --
#'   a tighter 3-degree pass there cost a real, well-documented invader whose
#'   established population sat ~5 degrees of latitude from the study site
#'   despite being part of one connected system).
#' @param near_occurrence_min_n Integer >= 0. A taxon must have at least this
#'   many Stage-2-filtered records within \code{near_lat_tolerance_deg} of
#'   \code{lat}, IN ADDITION TO clearing the nearest-point/buffer test above.
#'   Default \code{3L} (an absolute count, not a fraction of a taxon's total
#'   filtered records -- a fraction would unfairly penalize a taxon with a
#'   large occurrence footprint and reward one with only a handful of
#'   records). Taxa with FEWER total Stage-2-filtered records than this
#'   threshold get a proportional fallback instead of an impossible bar: ALL
#'   of their (few) records must fall within \code{near_lat_tolerance_deg},
#'   rather than requiring an absolute count they structurally cannot reach --
#'   the real motivating case (\code{build_invasive_candidates()}'s own) is a
#'   species with exactly 1 occurrence record, genuinely close, that a flat
#'   count-of-3 test would otherwise always reject regardless of proximity.
#'   Set to \code{0} or \code{1} to disable this test and fall back to the
#'   original nearest-point-only behavior.
#' @param max_coord_uncertainty Numeric. Forwarded to
#'   \code{TaxaFetch::filter_gbif_quality()}. Default \code{500} (meters,
#'   matching that function's own default).
#' @param year_range Character or \code{NULL}. Forwarded to
#'   \code{TaxaFetch::get_gbif_occurrences()}'s underlying fetch. Default
#'   \code{NULL} (that function's own all-time default) -- deliberately not
#'   narrowed, since record age is exactly the signal this function reads
#'   out, not something to pre-filter away.
#' @param cache_dir Character or \code{NULL}. Forwarded to the Stage 2 fetch
#'   for checkpointing. Default \code{tools::R_user_dir("TaxaFetch", "cache")}.
#' @param verbose Logical. Print per-taxon Stage 1/Stage 2 progress. Default
#'   \code{FALSE}.
#'
#' @return A tibble with one row per taxon that cleared both stages:
#'   \code{taxon_name}, \code{weight}, \code{p_conc}, \code{source} (always
#'   \code{"regional_proximity"}) -- matches the evidence-table schema
#'   \code{\link{apply_undetected_evidence}} expects -- plus audit columns
#'   \code{distance_km}, \code{record_year}, \code{age_years} (\code{NA} when
#'   the matched record had no usable year), \code{tile_zoom_used}. Empty
#'   tibble (correct schema, zero rows) when nothing in \code{zero_bbox_taxa}
#'   clears Stage 1, Stage 2's quality filter, or GBIF key resolution.
#'
#' @seealso \code{\link{apply_undetected_evidence}},
#'   \code{TaxaFlag::check_gbif_tile_range()},
#'   \code{TaxaFlag::compute_local_occurrence_distance()},
#'   \code{TaxaFetch::get_gbif_occurrences()},
#'   \code{TaxaFetch::filter_gbif_quality()}
#'
#' @examples
#' \dontrun{
#' regional_evidence <- generate_regional_proximity_evidence(
#'   zero_bbox_taxa = c("Etheostoma chlorosomum", "Ictalurus furcatus"),
#'   lat = 41.67, lng = -87.15
#' )
#' elevated <- apply_undetected_evidence(
#'   taxaexpect_priors, model_fit,
#'   evidence = regional_evidence,
#'   grid_id = "Grid_41p6_m87p3", main_habitat = "Lentic"
#' )
#' }
#'
#' @importFrom tibble tibble
#' @export
generate_regional_proximity_evidence <- function(
    zero_bbox_taxa,
    lat, lng,
    d_half                = 150,
    age_half              = 15,
    tile_zoom             = 6L,
    buffer_margin         = 1.5,
    min_buffer_km         = 50,
    max_buffer_km         = 1000,
    near_lat_tolerance_deg = 6,
    near_occurrence_min_n  = 3L,
    max_coord_uncertainty = 500,
    year_range            = NULL,
    cache_dir             = tools::R_user_dir("TaxaFetch", "cache"),
    verbose               = FALSE
) {
  if (!is.character(zero_bbox_taxa) || length(zero_bbox_taxa) == 0L) {
    stop("generate_regional_proximity_evidence: `zero_bbox_taxa` must be a non-empty character vector.")
  }
  if (!is.numeric(lat) || length(lat) != 1L || is.na(lat) ||
      !is.numeric(lng) || length(lng) != 1L || is.na(lng)) {
    stop("generate_regional_proximity_evidence: `lat`/`lng` must be single non-NA numeric values.")
  }
  for (nm in c("d_half", "age_half", "near_lat_tolerance_deg")) {
    val <- get(nm)
    if (!is.numeric(val) || length(val) != 1L || is.na(val) || val <= 0) {
      stop(sprintf("generate_regional_proximity_evidence: `%s` must be a single positive numeric value.", nm))
    }
  }
  if (!is.numeric(near_occurrence_min_n) || length(near_occurrence_min_n) != 1L ||
      is.na(near_occurrence_min_n) || near_occurrence_min_n < 0) {
    stop("generate_regional_proximity_evidence: `near_occurrence_min_n` must be a single non-negative integer.")
  }
  for (pkg in c("TaxaFlag", "TaxaFetch", "rgbif")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf(
        "generate_regional_proximity_evidence: package '%s' is required. Install with: install.packages('%s')",
        pkg, pkg
      ))
    }
  }

  taxa <- unique(zero_bbox_taxa)

  # ---------------------------------------------------------------------
  # Batch-resolve every taxon name to a GBIF key in ONE name_backbone_
  # checklist() call, instead of one rgbif::name_backbone() call per taxon
  # (2026-08-22). Verified against real GBIF (not assumed) before adopting:
  # a batched checklist call and a loop of individual calls returned
  # IDENTICAL usageKey/rank for every one of 11 real test names, including
  # the pathological "Ictalurus" case (a bare genus resolving to Chordata
  # at PHYLUM rank -- the exact reason .resolve_gbif_taxon_key()'s own
  # explicit rank check exists) -- so the same per-name "is this actually
  # SPECIES rank" validation applies unchanged regardless of which call
  # shape resolved it. 11 individual calls took 3.51s; 1 batched call took
  # 1.17s (a real API-level batching win, unlike Stage 2's occurrence
  # fetch, where rgbif's own multi-key `occ_data()` convenience is just a
  # client-side loop of one request per key -- confirmed separately and
  # deliberately NOT changed, see this function's own git history/session
  # notes for that comparison).
  # ---------------------------------------------------------------------
  if (verbose) message(sprintf("Resolving %d taxon name(s) to GBIF keys (1 batched call)...", length(taxa)))
  key_lookup <- .resolve_gbif_taxon_keys_batch(taxa)

  rows <- vector("list", length(taxa))

  for (i in seq_along(taxa)) {
    nm <- taxa[i]

    taxon_key    <- key_lookup$usage_key[i]
    gbif_species <- key_lookup$gbif_species[i]
    if (is.na(taxon_key)) {
      if (verbose) message(sprintf("[%d/%d] %s: no GBIF backbone match -- skipped.", i, length(taxa), nm))
      next
    }
    # A resolved key with no gbif_species value at all (should not happen for a
    # real SPECIES-rank match, but degrade safely rather than pass NA
    # downstream) falls back to the original query name.
    if (is.na(gbif_species)) gbif_species <- nm
    if (verbose) message(sprintf("[%d/%d] %s: key resolved -- running Stage 1...", i, length(taxa), nm))

    tile <- tryCatch(
      TaxaFlag::check_gbif_tile_range(
        taxon_key = taxon_key, query_lat = lat, query_lon = lng, zoom = tile_zoom
      ),
      error = function(e) {
        warning(sprintf(
          "generate_regional_proximity_evidence: Stage 1 tile check failed for '%s': %s",
          nm, conditionMessage(e)
        ), call. = FALSE)
        NULL
      }
    )
    if (is.null(tile) || isTRUE(tile$beyond_buffer)) {
      if (verbose) message("  Stage 1: nothing found -- skipped.")
      next
    }
    if (verbose) message(sprintf("  Stage 1: found ~%.0fkm away -- running Stage 2.", tile$dist_nearest_occupied_km))

    buffer_km <- min(max_buffer_km, max(min_buffer_km, tile$dist_nearest_occupied_km * buffer_margin))
    wkt <- TaxaFetch::make_bbox_wkt(lat = lat, lon = lng, radius_deg = buffer_km / 111)

    occ <- tryCatch(
      TaxaFetch::get_gbif_occurrences(
        keys = taxon_key, geometry = wkt, year_range = year_range,
        columns = "standard", cache_dir = cache_dir
      ),
      error = function(e) {
        warning(sprintf(
          "generate_regional_proximity_evidence: Stage 2 fetch failed for '%s': %s",
          nm, conditionMessage(e)
        ), call. = FALSE)
        NULL
      }
    )
    if (is.null(occ) || nrow(occ) == 0L) {
      if (verbose) message("  Stage 2: no occurrence records returned -- skipped.")
      next
    }

    occ_clean <- TaxaFetch::filter_gbif_quality(occ, max_coord_uncertainty = max_coord_uncertainty)
    if (nrow(occ_clean) == 0L) {
      if (verbose) message("  Stage 2: nothing survived quality filtering -- skipped.")
      next
    }

    # Match against GBIF's OWN accepted species name (gbif_species), not the
    # original query string `nm` -- GBIF occurrence records fetched under a
    # resolved usageKey always report the CURRENTLY ACCEPTED name in their
    # own `species` field, regardless of what spelling/synonym the query
    # itself used to reach that key. See this function's own git history/
    # session notes: a real production run against a full, NCBI-native
    # taxon list found several real GreatLakes fish names resolve to a GBIF
    # SYNONYM's usageKey (e.g. "Erimonax monachus" -> key 2367386, status
    # SYNONYM, accepted species "Cyprinella monacha") -- fetching by that
    # key correctly returns real, quality-filterable occurrence records
    # (GBIF's occurrence search transparently expands a synonym key to its
    # accepted-key's records), but matching those records' `species` column
    # against the ORIGINAL query name always failed, silently zeroing every
    # such taxon's evidence despite real surviving data. `nm` (not
    # `gbif_species`) is still what's reported in the returned `taxon_name`
    # column below -- the caller's own priors table is keyed by whatever
    # naming convention `zero_bbox_taxa` itself used, and this internal
    # GBIF-name substitution must not leak into that join key.
    dist_out <- TaxaFlag::compute_local_occurrence_distance(
      taxon_names     = gbif_species, query_lat = lat, query_lon = lng,
      occurrence_data = occ_clean, taxon_col = "species", date_col = "year"
    )
    if (is.na(dist_out$dist_nearest_km) || dist_out$n_local_records == 0L) {
      if (verbose) message("  Stage 2: no matching filtered record for this exact name -- skipped.")
      next
    }

    # near_lat_tolerance_deg/near_occurrence_min_n: a second, complementary
    # test to the nearest-point check above -- requires a real CLUSTER of
    # filtered records near the study site's latitude, not just one nearest
    # point. Guards against exactly the failure mode a real GLANSIS benchmark
    # comparison found in the sibling build_invasive_candidates() tool: a
    # single isolated/outlier record (a stray point, or a real but
    # climatically-artificial thermal-discharge refugium) passing the
    # nearest-point test alone while the bulk of that species' real range
    # sits many latitude degrees away. Same proportional fallback as that
    # tool: a taxon with fewer filtered records than near_occurrence_min_n
    # must have ALL of them nearby rather than face an impossible bar.
    occ_species <- occ_clean[!is.na(occ_clean$species) & occ_clean$species == gbif_species &
                                !is.na(occ_clean$decimalLatitude), , drop = FALSE]
    near_count <- sum(abs(occ_species$decimalLatitude - lat) <= near_lat_tolerance_deg)
    lat_ok <- if (nrow(occ_species) < near_occurrence_min_n) {
      near_count >= 1L && near_count == nrow(occ_species)
    } else {
      near_count >= near_occurrence_min_n
    }
    if (!lat_ok) {
      if (verbose) message(sprintf(
        "  Stage 2: %d/%d filtered record(s) within %g deg latitude (need %d) -- skipped as an isolated-record artifact.",
        near_count, nrow(occ_species), near_lat_tolerance_deg, near_occurrence_min_n
      ))
      next
    }

    record_year <- suppressWarnings(as.numeric(dist_out$nearest_date))
    age_years   <- if (is.na(record_year)) NA_real_ else max(0, as.numeric(format(Sys.Date(), "%Y")) - record_year)

    weight <- exp(-dist_out$dist_nearest_km / d_half)
    p_conc <- if (is.na(age_years)) 1 else exp(-age_years / age_half)

    rows[[i]] <- tibble::tibble(
      taxon_name     = nm,
      weight         = weight,
      p_conc         = p_conc,
      source         = "regional_proximity",
      distance_km    = dist_out$dist_nearest_km,
      record_year    = record_year,
      age_years      = age_years,
      tile_zoom_used = tile$zoom_used
    )
    if (verbose) message(sprintf("  applied: weight=%.3f, p_conc=%.2f (distance=%.0fkm, age=%s)",
                                  weight, p_conc, dist_out$dist_nearest_km,
                                  if (is.na(age_years)) "unknown" else sprintf("%.0fy", age_years)))
  }

  result <- dplyr::bind_rows(Filter(Negate(is.null), rows))
  if (nrow(result) == 0L) {
    result <- tibble::tibble(
      taxon_name = character(0), weight = numeric(0), p_conc = numeric(0),
      source = character(0), distance_km = numeric(0), record_year = numeric(0),
      age_years = numeric(0), tile_zoom_used = integer(0)
    )
  }

  message(sprintf(
    "--- Regional-proximity evidence complete: %d of %d taxon/taxa elevated ---",
    nrow(result), length(taxa)
  ))

  result
}

#' Resolve a taxon name to a GBIF backbone usageKey via a species-rank name_backbone() lookup
#' Returns NA_real_ (not an error) when no match is found -- callers skip
#' the taxon rather than fail the whole run for one unresolvable name.
#'
#' rgbif::name_backbone()'s own `rank` argument is a matching HINT, not an
#' enforced constraint -- confirmed live (a bare genus name, e.g. "Ictalurus",
#' still resolves successfully with `rank = "species"` requested, returning
#' that genus's own usageKey rather than failing). The RESOLVED rank
#' (`res$rank`, GBIF's own field -- same one `TaxaFetch::get_keys_from_context()`
#' reads as `gbif_rank`) must therefore be checked explicitly; a non-species
#' resolution is treated the same as no match at all, not silently accepted
#' at the wrong taxonomic level.
#'
#' Kept as a single-name helper alongside `.resolve_gbif_taxon_keys_batch()`
#' (below, what `generate_regional_proximity_evidence()` actually calls as of
#' 2026-08-22) -- not currently called by this file, but left in place as a
#' documented, tested single-name primitive in case a future caller needs to
#' resolve just one name without paying for a whole-batch call.
#' @noRd
.resolve_gbif_taxon_key <- function(taxon_name) {
  res <- tryCatch(
    rgbif::name_backbone(name = taxon_name, rank = "species"),
    error = function(e) NULL
  )
  if (is.null(res) || !"usageKey" %in% names(res) || length(res$usageKey) == 0L) {
    return(NA_real_)
  }
  resolved_rank <- if ("rank" %in% names(res)) toupper(as.character(res$rank[[1]])) else NA_character_
  if (is.na(resolved_rank) || resolved_rank != "SPECIES") {
    return(NA_real_)
  }
  as.numeric(res$usageKey[[1]])
}

#' Batch-resolve taxon names to GBIF backbone usageKeys, one name_backbone_checklist() call
#'
#' The batched equivalent of \code{.resolve_gbif_taxon_key()} -- same
#' hint-not-constraint rank validation, applied per row instead of per call.
#' Live-verified (2026-08-22) against 11 real taxon names (9 real species, 1
#' bare genus, 1 fictional name) that this returns IDENTICAL usageKey/rank
#' results to a loop of individual \code{name_backbone()} calls, including
#' the pathological bare-genus case -- so no correctness is traded for the
#' real ~3x wall-clock win (1 batched call vs. N individual ones; the win
#' grows with \code{length(taxon_names)}, since a batched checklist call is
#' one HTTP round trip regardless of how many names it carries, chunked
#' internally by \code{rgbif} only above its own \code{bucket_size}).
#'
#' Also returns \code{gbif_species} -- GBIF's own CURRENTLY ACCEPTED species
#' name for the resolved key, which can differ from the query name itself
#' when the query matches a SYNONYM's own scientific name rather than the
#' accepted one (a real, common case for freshwater fish specifically, found
#' via a full real-scale production run: e.g. \code{"Erimonax monachus"}
#' resolves to usageKey 2367386, GBIF status \code{SYNONYM}, accepted species
#' \code{"Cyprinella monacha"}). This matters because GBIF's occurrence
#' search transparently expands a synonym key to its accepted key's real
#' records (so Stage 2's fetch genuinely succeeds), but every one of those
#' records reports the ACCEPTED name in its own \code{species} field --
#' matching them back against the original query name would silently find
#' nothing. Callers needing to match fetched occurrence records against a
#' resolved taxon must use \code{gbif_species}, not the original query name.
#'
#' @param taxon_names Character vector, already deduplicated by the caller.
#' @return A tibble, one row per \code{taxon_names} entry, SAME ORDER (not
#'   matched/reordered) -- \code{taxon_name} (as supplied), \code{usage_key}
#'   (\code{NA_real_} for any name that fails to resolve, resolves at a
#'   non-species rank, or is absent from the response entirely -- matched
#'   back defensively by the response's own \code{verbatim_name} column,
#'   never by row position/order), \code{gbif_species} (\code{NA_character_}
#'   under the same conditions, or if the response's own \code{species}
#'   field is unexpectedly missing for an otherwise-valid species-rank row).
#' @noRd
.resolve_gbif_taxon_keys_batch <- function(taxon_names) {
  out <- tibble::tibble(
    taxon_name   = taxon_names,
    usage_key    = NA_real_,
    gbif_species = NA_character_
  )

  # A real, previously-silent failure mode (found 2026-08-24 on a real
  # 333-name production GreatLakes2023 batch): rgbif::name_backbone_checklist()
  # can fail entirely for a large `taxon_names` batch with
  # "Status: 0 - try lower bucket_size or larger sleep" -- a transient
  # GBIF-side rate-limit/batch-size rejection, not reproducible at the small
  # batch sizes (4-11 names) this function's own tests use, and not
  # deterministic (an earlier, smaller real batch from the same study
  # succeeded fine at defaults). The original single-attempt
  # tryCatch(error = function(e) NULL) swallowed this identically to "no
  # taxon in this batch resolved," silently zeroing EVERY name with no
  # warning at all -- invisible until someone checks the resolved-key count
  # against a known-good spot check, which is exactly what this function's
  # own live-verified small-scale behavior masked. Retried here with
  # progressively smaller bucket_size/larger sleep -- exactly rgbif's own
  # suggested mitigation in that error message -- and a loud warning() (not
  # silent) if every attempt still fails, so a real recurrence is visible
  # immediately in the console rather than requiring a multi-session
  # diagnostic to trace a real fix's apparent "no effect" back to this.
  attempts <- list(
    list(bucket_size = 300L, sleep = 1),
    list(bucket_size = 100L, sleep = 2),
    list(bucket_size = 50L,  sleep = 3)
  )
  res <- NULL
  last_error <- NULL
  for (att in attempts) {
    res <- tryCatch(
      rgbif::name_backbone_checklist(
        name_data   = data.frame(name = taxon_names, stringsAsFactors = FALSE),
        rank        = "species",
        bucket_size = att$bucket_size,
        sleep       = att$sleep
      ),
      error = function(e) {
        last_error <<- conditionMessage(e)
        NULL
      }
    )
    if (!is.null(res)) break
  }
  if (is.null(res)) {
    warning(sprintf(
      paste0(
        "generate_regional_proximity_evidence: GBIF name resolution failed ",
        "for all %d taxa after %d attempt(s) (last error: %s) -- returning ",
        "zero evidence rows for this ENTIRE batch. This is a real resolution ",
        "failure, not a genuine absence-of-evidence result -- re-run once ",
        "GBIF's API is responsive again."
      ),
      length(taxon_names), length(attempts),
      if (is.null(last_error)) "unknown" else last_error
    ), call. = FALSE)
    return(out)
  }
  if (nrow(res) == 0L || !"usageKey" %in% names(res)) {
    return(out)
  }

  match_col <- if ("verbatim_name" %in% names(res)) "verbatim_name" else "name"
  if (!match_col %in% names(res)) {
    return(out)
  }

  resolved_rank <- if ("rank" %in% names(res)) {
    toupper(as.character(res$rank))
  } else {
    rep(NA_character_, nrow(res))
  }
  resolved_species <- if ("species" %in% names(res)) {
    as.character(res$species)
  } else {
    rep(NA_character_, nrow(res))
  }
  is_species <- !is.na(resolved_rank) & resolved_rank == "SPECIES" & !is.na(res$usageKey)

  idx     <- match(taxon_names, res[[match_col]])
  has_idx <- !is.na(idx)
  ok      <- rep(FALSE, length(taxon_names))
  ok[has_idx] <- is_species[idx[has_idx]]

  out$usage_key[ok]    <- as.numeric(res$usageKey[idx[ok]])
  out$gbif_species[ok] <- resolved_species[idx[ok]]

  out
}
