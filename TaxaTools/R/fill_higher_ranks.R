utils::globalVariables(c(
  "taxon_name", "genus", "family", "family.local",
  "family.api", "family.fb"
))

#' Fill Higher Taxonomic Ranks from Local Data and Backbone APIs
#'
#' @description
#' Given a character vector of taxon names (typically species binomials), derives
#' `genus` (first word of the binomial) and looks up `family` using a
#' priority-ordered fallback chain:
#'
#' 1. **Local sources** -- data frames already in scope (e.g. `reference_df`,
#'    `match_obj`, `gbif_std`).  Fast, offline, covers most cases.
#' 2. **Primary backbone** -- `verify_taxon_names()` queried at genus level
#'    (`backbone_id`; default NCBI = 4).
#' 3. **Fallback backbone** -- repeated with `fallback_backbone_id` (default
#'    GBIF = 11) for any genera still unresolved.
#'
#' Queries are made at the **genus level**, so species absent from a backbone
#' (e.g. newly described species, cross-backbone synonyms) are still resolved
#' provided their genus is present.
#'
#' @param taxon_names Character vector of taxon names (an empty vector returns
#'   a zero-row table with the usual columns).  Binomial species names
#'   are expected; genus is extracted as the first word.  Single-word names
#'   (genus only) are accepted and returned as-is in the `genus` column.
#' @param local_sources List of data frames to consult before any API call.
#'   Each element must contain at least `genus` and the requested rank; elements
#'   lacking those columns are silently skipped.  Sources are consulted in
#'   order and the first non-NA value for each genus wins.  That precedence is
#'   the right policy when you have ranked your sources by authority, and it
#'   decides nothing useful when the genus name is a homonym -- *Dilophus* is a
#'   fly and a brown alga, *Porella* a bryozoan and a liverwort -- because the
#'   value it picks may then describe a different organism.  So for a genus
#'   that maps to more than one value, the lookup is keyed on the taxon's OWN
#'   row in your sources instead: a value standing beside this exact name is a
#'   statement about this taxon, where a genus-keyed one is a statement about
#'   whatever else shares the name.  Only those genera are treated this way --
#'   where the genus is unanimous the two agree anyway, and preferring one row
#'   there would import that row's own errors.  A genus with no row of its own
#'   to read keeps the precedence, and every genus that mapped to several
#'   values is REPORTED by name along with how it was settled.  Read that
#'   message: it is the only signal that a filled value was a choice rather
#'   than a lookup.  Measured on one real multi-marker study, 202 of 15,160
#'   genus names in the sources mapped to more than one family; 74 of those
#'   genera reached the 3,489 taxa being filled, affecting 137 of them.  Every
#'   one was resolved from its own row, changing 49 fills, and 63 of the 137
#'   carried competing family circumscriptions for the same organism -- two
#'   backbones disagreeing about one fish, not a homonym -- which no lineage
#'   can arbitrate and which the precedence therefore still settles.
#' @param ranks Character vector of higher ranks to resolve.  Default
#'   \code{"family"}.  Any rank label the backbone reports is accepted, e.g.
#'   \code{c("family", "class")}.  \code{"genus"} is rejected (it is derived
#'   from \code{taxon_names}, not looked up) and so is \code{"species"}.
#'   Each rank is resolved down the same chain and recorded in its own column.
#' @param record_source Logical.  \code{FALSE} (default) returns only the
#'   \code{taxon_name}, \code{genus} and rank columns.
#'   \code{TRUE} adds one \code{<rank>_source} column per entry in
#'   \code{ranks}, holding \code{"local"}, \code{"backbone_<id>"}, or
#'   \code{NA} where the rank was never resolved.  It is off by default
#'   because \code{TaxaAssign::join_priors()} joins EVERY non-\code{taxon_name}
#'   column of its \code{expansion_taxonomy} argument onto the priors table,
#'   so an unwanted source column would travel into the posteriors.  Turn it on
#'   when you want provenance, and drop the columns before passing the frame to
#'   \code{join_priors()}.
#' @param backbone_id Integer.  Primary backbone for API fallback.
#'   Default `4L` (NCBI).  Set `NULL` to skip the API entirely.
#' @param fallback_backbone_id Integer.  Secondary backbone used when
#'   `backbone_id` returns no match.  Default `11L` (GBIF).  Set `NULL` or
#'   equal to `backbone_id` to skip.
#' @param verbose Logical.  Print progress messages for API lookups.
#'   Default `TRUE`.
#' @param decisions Forwarded verbatim to [verify_taxon_names()]'s own
#'   `decisions` parameter for every genus-level lookup this function makes
#'   (primary and fallback backbone alike, whichever is `4`) -- this
#'   function grows no prompt or resolution logic of its own for an NCBI
#'   name collision.
#'
#' @param lineage Character vector or \code{NULL} (default). One lineage
#'   context per element of \code{taxon_names} (\code{NA} = none), a
#'   pipe-delimited string of ancestor names the caller already knows for the
#'   taxon (its GBIF phylum, the study's class). Forwarded, per genus, to
#'   \code{\link{verify_taxon_names}(lineage =)} on both backbones: it
#'   resolves an NCBI homonym rank alone cannot (two genus-rank nodes in
#'   different kingdoms) and rejects a fallback-backbone answer that
#'   contradicts it. The genus queries always carry \code{ranks = "genus"}.
#' @return A tibble with one row per element of `taxon_names` (preserving
#'   duplicates and order), with columns:
#'   \describe{
#'     \item{`taxon_name`}{The original input name.}
#'     \item{`genus`}{First word of `taxon_name`, EXCEPT when an API lookup
#'       resolved that genus to a backbone-flagged synonym at genus rank --
#'       in that case the backbone's own currently-accepted genus name is
#'       returned instead (see `@section Genus correction` below).
#'       Local-source-only lookups (no API call needed) always keep the
#'       locally-extracted genus unchanged.}
#'     \item{`<rank>`}{One column per entry in `ranks` (by default just
#'       `family`), holding the looked-up value or `NA` if unresolved.}
#'     \item{`<rank>_source`}{Only when `record_source = TRUE`: where that
#'       value came from -- `"local"`, `"backbone_<id>"`, or `NA`.}
#'   }
#'   A warning is issued, per rank, for any names that rank could not be
#'   resolved for after all fallbacks.
#'
#' @section Filling only where a backbone is silent:
#' A rank is filled only where the backbone above it in the chain said
#' NOTHING.  A value the primary backbone supplied is never replaced by the
#' fallback's, and a value already present is never overwritten.  Silence and
#' contradiction are different things and only the first is filled here.
#'
#' This is the opposite emphasis from
#' \code{TaxaAssign::posterior_consensus()}'s \code{cross_phylum_eps}, where
#' the backbone WINS over a disagreeing input: GBIF makes Sipuncula a phylum in
#' its own right, so a sipunculan row carrying `phylum = "Annelida",
#' class = "Sipuncula"` is treated as a genuine cross-phylum conflict rather
#' than reconciled.  The two rules are consistent because they answer different
#' questions.  There, two sources disagree and the backbone is trusted; here,
#' one source is silent and another is asked.  Nothing in this function
#' adjudicates a disagreement.
#'
#' The motivating case is GBIF's treatment of the ray-finned fishes.  GBIF
#' returns \code{kingdom|phylum|order|family|genus} for them with no class
#' entry at all -- its Actinopterygii/Actinopteri node is not an accepted
#' backbone class -- so \code{class} comes back `NA` and a consensus keyed on
#' class lands at phylum Chordata.  NCBI supplies \code{Actinopteri}, and
#' because GBIF is silent rather than contradictory, filling it is safe.
#'
#' @section Homonyms, and what the agreement check does and does not cover:
#' A bare genus name is not a key.  GBIF carries a polychaete worm genus
#' \code{"Corallina"} (\code{Animalia|Annelida|Polychaeta|...}) alongside the
#' red algal genus NCBI resolves (\code{Rhodophyta|Florideophyceae|...}), and
#' BOTH match at genus rank, so \code{matched_rank} cannot separate them.
#'
#' Before a FALLBACK value is accepted the primary must have PLACED that genus,
#' and the fallback's lineage must not contradict the primary's at
#' \code{phylum} (or \code{division}); a rejected genus raises a warning
#' naming it.  A genus the primary could not place at all is refused rather
#' than trusted -- that is not the same as the primary being silent about one
#' rank, and it is when the fallback is least safe: NCBI refuses
#' \code{"Liparis"} as ambiguous (a snailfish and an orchid), and GBIF
#' resolves the same string to an insect genus, so trusting it would put
#' \code{class = "Insecta"} on a fish.  When no primary backbone is configured
#' at all the fallback is the only source and is used as given.  Coarser ranks are deliberately
#' not compared: the backbones use different vocabulary for the same kingdom
#' ("Metazoa" against "Animalia"), and finer ranks disagree routinely for the
#' same organism (NCBI places Girella in Centrarchiformes, GBIF in
#' Perciformes), so both produced false contradictions when tried.
#'
#' The check cannot protect against a wrong PRIMARY backbone, which is
#' authoritative by construction: query with \code{backbone_id = 11}
#' (GBIF) and \code{"Corallina"} resolves to class \code{"Polychaeta"} with
#' nothing to compare it against.  Choose the primary backbone for the group
#' being resolved; the default (NCBI primary, GBIF fallback) answers all of the
#' above correctly.
#'
#' @section Genus correction:
#' `genus` reflects the backbone's currently-accepted name whenever an API
#' lookup resolves the locally-extracted genus to a taxonomic synonym at
#' genus rank -- e.g. an informally-named reference ("Inu sp. 1 sensu
#' Shibukawa et al., 2020.") extracts `genus = "Inu"`, but GBIF's own
#' backbone resolves it to the currently-accepted genus `"Luciogobius"`, so
#' `"Luciogobius"` is returned. This matters beyond cosmetics:
#' `TaxaAssign::join_priors()` joins this function's `genus`/`family` output
#' against a likelihood-side coarse-rank `taxon_name` (produced by
#' `TaxaMatch::convert_taxonomy_backbone()`, which also prefers the current
#' name over a synonym) via an EXACT STRING match. If the two functions
#' disagreed on which form to report for the same genus, that join would
#' silently fail and the observation would lose its coarse-rank species
#' expansion entirely, falling back to the dark-diversity floor instead of
#' real occurrence-based priors. `genus` is corrected to the backbone's
#' resolved name whenever an API lookup finds one cleanly at genus rank,
#' keeping this function consistent with `convert_taxonomy_backbone()`.
#' Verified backbone-general: both NCBI and GBIF resolve the "Inu" case the
#' same way.
#'
#' @details
#' **Backbone queries are at genus level.**  `verify_taxon_names()` is called
#' with the unique unresolved genera (not the full species names).  This means
#' a species absent from NCBI is still resolved provided its genus is present
#' -- which covers the vast majority of cross-backbone synonym situations.
#'
#' **Column name conflicts in local sources** (e.g. a source has both `genus`
#' and `Genus`) are handled by `tolower(names(...))` before joining.
#'
#' @seealso [verify_taxon_names()], [parse_classification_path()]
#'
#' @examples
#' \dontrun{
#' unreferenced_df <- fill_higher_ranks(
#'   coverage$unreferenced,
#'   local_sources = list(reference_df, match_obj, gbif_std)
#' )
#' # rename for expand_unreferenced_hypotheses():
#' unreferenced_df <- dplyr::rename(unreferenced_df, species = taxon_name)
#' }
#'
#' @importFrom dplyr bind_rows filter distinct left_join mutate coalesce select any_of
#' @importFrom tibble tibble
#' @export
fill_higher_ranks <- function(taxon_names,
                              local_sources = list(),
                              ranks = "family",
                              record_source = FALSE,
                              backbone_id = 4L,
                              fallback_backbone_id = 11L,
                              verbose = TRUE,
                              decisions = NULL,
                              lineage = NULL) {
  # ---- Input validation ------------------------------------------------------
  if (!is.character(taxon_names)) {
    stop("taxon_names must be a character vector")
  }
  if (!is.null(lineage)) {
    if (!is.character(lineage) || length(lineage) != length(taxon_names)) {
      stop("`lineage` must be NULL or a character vector with one lineage context per element of `taxon_names`.")
    }
    lineage <- trimws(lineage)
    lineage[!is.na(lineage) & !nzchar(lineage)] <- NA_character_
  }
  if (!is.list(local_sources)) {
    stop("local_sources must be a list of data frames")
  }
  if (!is.character(ranks) || length(ranks) == 0L || anyNA(ranks) ||
    !all(nzchar(ranks))) {
    stop("ranks must be a non-empty character vector of rank names")
  }
  ranks <- unique(ranks)
  if ("genus" %in% ranks) {
    stop("ranks must not include 'genus': genus is derived from taxon_names, not looked up")
  }
  if ("species" %in% ranks) {
    stop("ranks must not include 'species': a species is the input, not a higher rank")
  }
  if (!is.logical(record_source) || length(record_source) != 1L || is.na(record_source)) {
    stop("record_source must be TRUE or FALSE")
  }
  if (!is.null(backbone_id) && (!is.numeric(backbone_id) ||
    length(backbone_id) != 1L || is.na(backbone_id))) {
    stop("backbone_id must be a single integer or NULL")
  }
  if (!is.null(fallback_backbone_id) && (!is.numeric(fallback_backbone_id) ||
    length(fallback_backbone_id) != 1L || is.na(fallback_backbone_id))) {
    stop("fallback_backbone_id must be a single integer or NULL")
  }
  if (!is.logical(verbose) || length(verbose) != 1L || is.na(verbose)) {
    stop("verbose must be TRUE or FALSE")
  }

  # An empty input is a legitimate outcome upstream (a coverage audit that
  # finds no unreferenced species), not a caller error: return the documented
  # zero-row shape so a workflow loop does not die on its emptiest marker.
  if (length(taxon_names) == 0L) {
    if (verbose) message("fill_higher_ranks: no taxon names supplied; returning an empty table.")
    out <- tibble::tibble(taxon_name = character(0), genus = character(0))
    for (r in ranks) {
      out[[r]] <- character(0)
      if (record_source) out[[paste0(r, "_source")]] <- character(0)
    }
    return(out)
  }

  # ---- Working table: unique non-NA names + extracted genus ------------------
  all_names <- taxon_names
  valid_mask <- !is.na(taxon_names) & nzchar(trimws(taxon_names))
  uniq <- unique(taxon_names[valid_mask])

  work <- tibble::tibble(
    taxon_name = uniq,
    genus      = sub(" .*", "", uniq)
  )
  for (r in ranks) {
    work[[r]] <- NA_character_
    work[[paste0(r, "_source")]] <- NA_character_
  }

  # Local sources first, per rank: they are offline and authoritative for the
  # caller's own data.
  for (r in ranks) {
    local_lookup <- .build_genus_rank_lookup(local_sources, r)
    .amb <- attr(local_lookup, "ambiguous_genera")
    na_idx <- which(is.na(work[[r]]))
    if (nrow(local_lookup) == 0L || !length(na_idx)) {
      .report_ambiguous_genera(.amb, r, 0L, .amb, character(0))
      next
    }
    filled <- dplyr::left_join(
      work[na_idx, c("taxon_name", "genus"), drop = FALSE],
      local_lookup, by = "genus"
    )
    val <- filled[[r]]

    # A genus-keyed value is only an inference ABOUT THE SAME TAXON while the
    # genus name maps to one value. Where it maps to several, the name is doing
    # no identifying work -- Dilophus is a fly and a brown alga -- and the value
    # the precedence picks may describe a different organism entirely. So for
    # those genera only, the taxon's OWN row in the sources is preferred: a
    # value standing beside this exact name is a statement about this taxon,
    # where a genus-keyed one is a statement about whatever else shares the
    # name. Measured on one real multi-marker study, that resolved 74 of the
    # 137 affected names.
    #
    # Deliberately NOT applied where the genus is unanimous. There the two
    # agree by construction except when a source row carries the rank without
    # the genus, and on that study both such changes were WRONG (a mislabelled
    # source row placing Grateloupia in Callithamniaceae). Replacing a guess
    # with evidence is the point; replacing agreement with one row's noise is
    # not.
    n_own <- 0L
    unresolved <- .amb
    own_conflicting <- character(0)
    if (length(.amb) > 0L) {
      amb_rows <- which(filled$genus %in% .amb)
      own_lookup <- .build_name_rank_lookup(local_sources, r)
      if (length(amb_rows) > 0L && nrow(own_lookup) > 0L) {
        own_val <- own_lookup[[r]][match(filled$taxon_name[amb_rows],
                                         own_lookup$taxon_name)]
        take <- !is.na(own_val)
        val[amb_rows[take]] <- own_val[take]
        n_own <- sum(take)
        unresolved <- sort(unique(filled$genus[amb_rows[!take]]))
        # Its own name mapping to several values is a DIFFERENT disagreement:
        # two sources describing the same organism under competing family
        # circumscriptions (Cyclopsettidae against Paralichthyidae for
        # Citharichthys). No lineage can arbitrate that, so the precedence
        # still decides -- but among candidates that all describe this taxon.
        own_conflicting <- sort(intersect(filled$taxon_name[amb_rows[take]],
                                          attr(own_lookup, "ambiguous_names")))
      }
    }
    work[[r]][na_idx] <- val
    work[[paste0(r, "_source")]][na_idx[!is.na(val)]] <- "local"
    .report_ambiguous_genera(.amb, r, n_own, unresolved, own_conflicting)
  }

  # One lineage query per BACKBONE, not per rank: a single classification path
  # answers every requested rank at once, so asking for three ranks costs one
  # API round per backbone rather than three.
  # One lineage context per GENUS: the union of what the caller knows for the
  # taxa carrying it (pipe-joined). Two taxa of one genus in different lineages
  # (a fish Ulvaria and an alga Ulvaria in one table) yield a context that
  # both candidates contain, so the name stays ambiguous -- which is right for
  # a table keyed on the bare name.
  lineage_by_genus <- NULL
  if (!is.null(lineage)) {
    lineage_by_genus <- tapply(lineage, work$genus, function(v) {
      v <- unique(unlist(strsplit(v[!is.na(v)], "|", fixed = TRUE)))
      v <- trimws(v[nzchar(trimws(v))])
      if (length(v)) paste(unique(v), collapse = "|") else NA_character_
    })
    lineage_by_genus <- stats::setNames(as.character(lineage_by_genus), names(lineage_by_genus))
  }
  need <- unique(work$genus[Reduce(`|`, lapply(ranks, function(r) is.na(work[[r]])))])
  lin_primary <- NULL
  if (length(need) > 0L && !is.null(backbone_id)) {
    if (verbose) {
      message(sprintf(
        "fill_higher_ranks: %d genera unresolved in local sources; querying backbone %d for %s...",
        length(need), as.integer(backbone_id), paste(ranks, collapse = "/")
      ))
    }
    lin_primary <- .lookup_lineage_from_backbone(need, as.integer(backbone_id), decisions,
                                                 lineage_of = lineage_by_genus)
    for (r in ranks) {
      na_idx <- which(is.na(work[[r]]))
      if (!length(na_idx) || is.null(lin_primary) || nrow(lin_primary) == 0L) next
      val <- .rank_from_lineage(lin_primary, work$genus[na_idx], r)
      work[[r]][na_idx] <- val
      work[[paste0(r, "_source")]][na_idx[!is.na(val)]] <-
        paste0("backbone_", as.integer(backbone_id))
    }
    # genus correction, in lockstep with the primary lookup as before
    if (!is.null(lin_primary) && nrow(lin_primary) > 0L) {
      j <- match(work$genus, lin_primary$genus)
      work$genus <- dplyr::coalesce(lin_primary$resolved_genus[j], work$genus)
    }
  }

  # Fallback backbone, ONLY for ranks the primary left silent -- and only when
  # its lineage AGREES with the primary's on every rank the two share.
  #
  # That guard is not decoration. A bare genus name is not a key: GBIF carries
  # a polychaete worm genus "Corallina" (Animalia|Annelida|Polychaeta|...)
  # alongside the red algal genus NCBI resolves (Rhodophyta|Florideophyceae|
  # ...), and BOTH match at genus rank, so matched_rank cannot tell them apart.
  # Without the check, a genus the primary backbone could not place would take
  # a homonym's class from the fallback -- writing "Polychaeta" into a red
  # alga. Requiring agreement on the ranks both backbones DID supply catches
  # exactly that: it is the same evidence a reader would use.
  still <- unique(work$genus[Reduce(`|`, lapply(ranks, function(r) is.na(work[[r]])))])
  if (length(still) > 0L &&
    !is.null(fallback_backbone_id) &&
    !identical(as.integer(fallback_backbone_id), as.integer(backbone_id))) {
    if (verbose) {
      message(sprintf(
        "fill_higher_ranks: %d genera still unresolved; trying fallback backbone %d...",
        length(still), as.integer(fallback_backbone_id)
      ))
    }
    lin_fb <- .lookup_lineage_from_backbone(still, as.integer(fallback_backbone_id), decisions,
                                            lineage_of = lineage_by_genus)
    if (!is.null(lin_fb) && nrow(lin_fb) > 0L) {
      ok_genus <- .lineages_agree(lin_primary, lin_fb)
      rejected <- setdiff(lin_fb$genus, ok_genus)
      if (length(rejected) > 0L) {
        warning(sprintf(
          paste0("fill_higher_ranks: backbone %d's lineage contradicts backbone %d's for ",
                 "%d genus/genera, so no value was filled from it (likely a homonym):\n  %s"),
          as.integer(fallback_backbone_id), as.integer(backbone_id),
          length(rejected), paste(rejected, collapse = "\n  ")
        ), call. = FALSE)
      }
      lin_fb <- lin_fb[lin_fb$genus %in% ok_genus, , drop = FALSE]
      for (r in ranks) {
        na_idx <- which(is.na(work[[r]]))
        if (!length(na_idx) || nrow(lin_fb) == 0L) next
        val <- .rank_from_lineage(lin_fb, work$genus[na_idx], r)
        work[[r]][na_idx] <- val
        work[[paste0(r, "_source")]][na_idx[!is.na(val)]] <-
          paste0("backbone_", as.integer(fallback_backbone_id))
      }
      if (nrow(lin_fb) > 0L) {
        j <- match(work$genus, lin_fb$genus)
        work$genus <- dplyr::coalesce(lin_fb$resolved_genus[j], work$genus)
      }
    }
  }

  # ---- Warn about any remaining NAs, per rank -------------------------------
  for (r in ranks) {
    n_na <- sum(is.na(work[[r]]))
    if (n_na > 0L) {
      unresolved <- work$taxon_name[is.na(work[[r]])]
      warning(sprintf(
        "fill_higher_ranks: %d taxon(s) have no %s after all lookups:\n  %s",
        n_na, r, paste(unresolved, collapse = "\n  ")
      ), call. = FALSE)
    }
  }

  # ---- Re-expand to original length (preserve duplicates and order) ----------
  i <- match(all_names, work$taxon_name)
  out <- tibble::tibble(taxon_name = all_names)
  out$genus <- work$genus[i]
  out$genus[!valid_mask] <- NA_character_
  for (r in ranks) {
    out[[r]] <- work[[r]][i]
    out[[r]][!valid_mask] <- NA_character_
  }
  if (record_source) {
    for (r in ranks) {
      sc <- paste0(r, "_source")
      out[[sc]] <- work[[sc]][i]
      out[[sc]][!valid_mask] <- NA_character_
    }
  }

  out
}


# ==============================================================================
# Exported helper: parse_classification_path()
# ==============================================================================

#' Parse a Rank Value from a Pipe-Delimited Classification Path
#'
#' @description
#' Extracts a single rank value from the `classification_path` and
#' `classification_ranks` columns returned by [verify_taxon_names()].
#' Both columns use `|` as a delimiter and are positionally aligned.
#'
#' @param path Character scalar.  Pipe-delimited taxon names, e.g.
#'   `"Animalia|Chordata|Cottidae|Cottus"`.
#' @param ranks Character scalar.  Pipe-delimited rank labels aligned
#'   with `path`, e.g. `"kingdom|phylum|family|genus"`.
#' @param target_rank Character scalar.  The rank to extract, e.g.
#'   `"family"` or `"order"`.
#'
#' @return The matched taxon name string, or `NA_character_` if
#'   `target_rank` is not present in `ranks` or inputs are `NA`.
#'
#' @details
#' This function is vectorised over `path` and `ranks` via [mapply()].
#' To parse an entire column from [verify_taxon_names()] output use:
#'
#' ```r
#' verified <- verify_taxon_names(stringr::word(species_names, 1))
#' families <- mapply(
#'   parse_classification_path,
#'   verified$classification_path,
#'   verified$classification_ranks,
#'   MoreArgs = list(target_rank = "family")
#' )
#' ```
#'
#' @seealso [verify_taxon_names()], [fill_higher_ranks()]
#'
#' @examples
#' parse_classification_path(
#'   path        = "Animalia|Chordata|Cottidae|Cottus",
#'   ranks       = "kingdom|phylum|family|genus",
#'   target_rank = "family"
#' )
#' # [1] "Cottidae"
#'
#' parse_classification_path(
#'   path        = "Animalia|Chordata|Cottidae|Cottus",
#'   ranks       = "kingdom|phylum|family|genus",
#'   target_rank = "order"
#' )
#' # [1] NA
#'
#' @export
parse_classification_path <- function(path, ranks, target_rank) {
  .extract_classified_rank(path, ranks, target_rank)
}


# ==============================================================================
# Internal helpers
# ==============================================================================

# Build a genus->family lookup from a list of data frames.
# Each source must have genus + family columns (case-insensitive check).
# Returns a tibble(genus, family) with no NAs and first-source-wins dedup.
#' @noRd
.build_genus_rank_lookup <- function(sources, rank) {
  parts <- lapply(sources, function(df) {
    if (!is.data.frame(df)) {
      return(NULL)
    }
    names(df) <- tolower(names(df))
    if (!all(c("genus", rank) %in% names(df))) {
      return(NULL)
    }
    df[, c("genus", rank), drop = FALSE]
  })
  parts <- Filter(Negate(is.null), parts)
  if (length(parts) == 0L) {
    out <- tibble::tibble(genus = character(), x = character())
    names(out)[2L] <- rank
    return(out)
  }

  all <- dplyr::bind_rows(parts)
  keep <- !is.na(all$genus) & !is.na(all[[rank]]) &
    nzchar(all$genus) & nzchar(all[[rank]])
  all <- all[keep, , drop = FALSE]

  # Which genera map to MORE THAN ONE value at this rank across the supplied
  # sources. Not an error and not refused: `local_sources` is a
  # priority-ordered chain and first-source-wins is its contract, which is the
  # right policy when the caller ranked its sources by authority. But the same
  # shape also arises when two PEER sources disagree because the genus name is
  # a homonym -- Dilophus is a fly and a brown alga, Porella a bryozoan and a
  # liverwort -- and there the winner is an artefact of binding order. This
  # list is what tells the caller apart from the first case: for the genera on
  # it the fill prefers the taxon's own row (see `.build_name_rank_lookup()`),
  # and whatever is still settled by precedence is reported by name.
  #
  # The rule names no taxon and no rank: ambiguity is computed from the
  # caller's own sources, so which genera are reported is learned from the data
  # supplied, not from any list held here.
  pairs <- unique(all[, c("genus", rank), drop = FALSE])
  per_genus <- table(pairs$genus)
  ambiguous <- sort(names(per_genus)[per_genus > 1L])

  out <- all[!duplicated(all$genus), , drop = FALSE]
  attr(out, "ambiguous_genera") <- ambiguous
  out
}


# Build a NAME->rank lookup from the same list of data frames, keyed on each
# source's own taxon name rather than on the genus. This is what lets an
# ambiguous genus be resolved from the row's own lineage: the value standing
# beside this exact name describes this taxon, where a genus-keyed value
# describes whatever else shares the genus name. Same precedence as the genus
# lookup (sources in order, first non-NA wins) and the same silence about
# missing columns, so a source lacking either column is skipped rather than
# erroring. `ambiguous_names` records the names that mapped to more than one
# value, which is NOT the homonym case -- it is two sources describing one
# organism under competing circumscriptions.
#' @noRd
.build_name_rank_lookup <- function(sources, rank) {
  parts <- lapply(sources, function(df) {
    if (!is.data.frame(df)) {
      return(NULL)
    }
    names(df) <- tolower(names(df))
    nm_col <- if ("taxon_name" %in% names(df)) {
      "taxon_name"
    } else if ("species" %in% names(df)) {
      "species"
    } else {
      return(NULL)
    }
    if (!rank %in% names(df)) {
      return(NULL)
    }
    out <- df[, c(nm_col, rank), drop = FALSE]
    names(out)[1L] <- "taxon_name"
    out
  })
  parts <- Filter(Negate(is.null), parts)
  if (length(parts) == 0L) {
    out <- tibble::tibble(taxon_name = character(), x = character())
    names(out)[2L] <- rank
    attr(out, "ambiguous_names") <- character(0)
    return(out)
  }

  all <- dplyr::bind_rows(lapply(parts, function(d) {
    d$taxon_name <- as.character(d$taxon_name)
    d[[rank]] <- as.character(d[[rank]])
    d
  }))
  keep <- !is.na(all$taxon_name) & !is.na(all[[rank]]) &
    nzchar(trimws(all$taxon_name)) & nzchar(trimws(all[[rank]]))
  all <- all[keep, , drop = FALSE]
  if (nrow(all) == 0L) {
    attr(all, "ambiguous_names") <- character(0)
    return(all)
  }

  pairs <- unique(all[, c("taxon_name", rank), drop = FALSE])
  per_name <- table(pairs$taxon_name)
  out <- all[!duplicated(all$taxon_name), , drop = FALSE]
  attr(out, "ambiguous_names") <- sort(names(per_name)[per_name > 1L])
  out
}


# Say what the ambiguity was and what was done about it. NOT gated on
# `verbose`: a value chosen rather than looked up is the one thing a reader
# cannot recover from the returned table, and silence here is the half of this
# defect that made it uncountable.
#' @noRd
.report_ambiguous_genera <- function(ambiguous, rank, n_own,
                                     unresolved, own_conflicting) {
  if (length(ambiguous) == 0L) {
    return(invisible(NULL))
  }
  .name_some <- function(x, n = 5L) {
    paste0(paste(utils::head(x, n), collapse = ", "),
           if (length(x) > n) ", ..." else "")
  }
  message(sprintf(
    "fill_higher_ranks: %d genus name(s) map to more than one %s across `local_sources` (%s). A genus name that maps to several values identifies nothing, so where the taxon has its own row in your sources that row's %s is used instead: %d name(s) resolved that way.",
    length(ambiguous), rank, .name_some(ambiguous), rank, n_own
  ))
  if (length(unresolved) > 0L) {
    message(sprintf(
      "fill_higher_ranks: %d of those genera had no row of their own to read, so the FIRST source's %s stands, per the documented precedence (%s). Check that your sources are ordered by authority -- for a genus that is a homonym there is no single right answer here.",
      length(unresolved), rank, .name_some(unresolved)
    ))
  }
  if (length(own_conflicting) > 0L) {
    message(sprintf(
      "fill_higher_ranks: %d resolved name(s) carry more than one %s across sources themselves, so the first source won there too -- this is competing circumscription of one organism rather than a homonym, and no lineage decides it (%s).",
      length(own_conflicting), rank, .name_some(own_conflicting)
    ))
  }
  invisible(NULL)
}


# Query verify_taxon_names() for a vector of genera, then parse family from
# classification_path + classification_ranks (pipe-delimited).
# Returns tibble(genus, resolved_genus, family). `genus` is always the QUERY
# genus (the join key back to the caller's own `work` table); `resolved_genus`
# is the backbone's own resolved name when the match cleanly resolved at
# genus rank, NA otherwise -- kept separate from `genus` so the caller can
# still join on the original spelling while writing the corrected value back.
#' @noRd
# Prefer the backbone's own resolved genus over the query genus when the match
# cleanly resolved at genus rank -- keeps this function consistent with
# TaxaMatch::convert_taxonomy_backbone()'s own current-name preference: a genus
# that is a taxonomic synonym under this backbone (confirmed real case: GBIF
# resolves "Inu" to "Luciogobius") is reported the same way regardless of which
# function in the ecosystem touched it, rather than being split across two
# different labels depending on whether a taxon's genus was derived here or via
# convert_taxonomy_backbone() -- exactly the mismatch that would silently break
# TaxaAssign::join_priors()'s exact-string genus/family match between the
# likelihood side and the priors side. `matched_rank` may be absent from
# `verified` depending on what `verify_taxon_names()` returns; when absent this
# is a no-op and `genus` passes through unchanged.
#' @noRd
.resolved_genus_at_rank <- function(verified) {
  if (!"matched_rank" %in% names(verified)) {
    return(rep(NA_character_, nrow(verified)))
  }
  ifelse(
    !is.na(verified$matched_rank) & verified$matched_rank == "genus" &
      !is.na(verified$matched_name) & nzchar(verified$matched_name),
    verified$matched_name,
    NA_character_
  )
}

# One query per backbone: returns genus, the backbone's resolved genus, and the
# raw pipe-delimited path/ranks so every requested rank can be read off the
# same lineage without a second round trip.
#' @noRd
.lookup_lineage_from_backbone <- function(genera, backbone_id, decisions = NULL,
                                          lineage_of = NULL) {
  ask <- function(nm) {
    tryCatch(
      verify_taxon_names(
        nm, backbone_id = backbone_id,
        # decisions only means anything for backbone_id = 4 -- forwarding it
        # unconditionally would trip verify_taxon_names()'s own "unused"
        # warning when this call targets a non-NCBI backbone.
        decisions = if (identical(as.integer(backbone_id), 4L)) decisions else NULL,
        # Every name asked here IS a genus (the first word of taxon_names), so
        # the rank is known and free: it separates Etheostoma the genus from
        # Etheostoma the subgenus with no decision from anyone.
        ranks = rep("genus", length(nm)),
        # The caller's own lineage for the taxon (phylum/class it already
        # knows), per genus: resolves a two-kingdom homonym and gates a
        # contradicting fallback answer. NULL when the caller gave none.
        lineage = if (is.null(lineage_of)) NULL else unname(lineage_of[nm])
      ),
      error = function(e) NULL
    )
  }
  verified <- ask(genera)
  if (is.null(verified)) {
    # One name can abort the whole batch. verify_taxon_names() refuses to guess
    # between NCBI homonyms and errors out asking for a `decisions` entry, and
    # that error is raised for the CALL, not the name: measured 2026-10-08,
    # 7 ambiguous genera (Apogon, Coris, Liparis, Microstoma, Decodon,
    # Hirundichthys, Appendicularia -- fish names that are also plant or
    # tunicate genera) cost all 374 resolvable genera in the same request, and
    # every rank came back NA. Retrying name by name keeps the resolvable ones
    # and isolates the ambiguous ones, WITHOUT this function choosing between
    # homonyms: an unresolvable name is simply reported and left unfilled, as
    # the `decisions` contract requires.
    parts <- lapply(genera, ask)
    failed <- genera[vapply(parts, is.null, logical(1))]
    parts <- Filter(Negate(is.null), parts)
    if (length(failed) > 0L) {
      warning(sprintf(
        paste0("fill_higher_ranks: backbone %d could not resolve %d name(s) ",
               "unambiguously; they are left unfilled. Pass `decisions` to choose ",
               "between NCBI homonyms:\n  %s"),
        backbone_id, length(failed), paste(failed, collapse = "\n  ")
      ), call. = FALSE)
    }
    if (length(parts) == 0L) {
      return(NULL)
    }
    verified <- dplyr::bind_rows(parts)
  }
  if (is.null(verified) || nrow(verified) == 0L ||
    !all(c("classification_path", "classification_ranks") %in% names(verified))) {
    return(NULL)
  }
  out <- tibble::tibble(
    genus = as.character(verified$user_supplied_name),
    resolved_genus = .resolved_genus_at_rank(verified),
    path = as.character(verified$classification_path),
    ranks = as.character(verified$classification_ranks),
    # Did the backbone ANSWER? FALSE for an undecidable homonym, a failed
    # lookup or a lineage-gated rejection; TRUE with an NA path means the
    # name is simply absent there.
    answered = if ("verified" %in% names(verified)) as.logical(verified$verified) else TRUE
  )
  out[!duplicated(out$genus), , drop = FALSE]
}

# Read one rank off a lineage table, for each genus in `genera` (NA when the
# backbone is silent on that rank, which is the case this whole function
# exists to fill).
#' @noRd
.rank_from_lineage <- function(lineage, genera, rank) {
  i <- match(genera, lineage$genus)
  out <- rep(NA_character_, length(genera))
  ok <- !is.na(i)
  if (!any(ok)) return(out)
  out[ok] <- mapply(
    .extract_classified_rank,
    lineage$path[i[ok]], lineage$ranks[i[ok]],
    MoreArgs = list(target_rank = rank),
    SIMPLIFY = TRUE, USE.NAMES = FALSE
  )
  out[!is.na(out) & !nzchar(trimws(out))] <- NA_character_
  out
}

# Which genera of `fb` may be trusted: those whose lineage does not contradict
# the primary's HIGH-LEVEL placement. Only the ranks in .LINEAGE_AGREEMENT_RANKS
# are compared, and only where both backbones supply one.
#
# Two narrowings, both forced by measurement rather than chosen:
#
# Comparing EVERY shared rank is too strict. NCBI and GBIF routinely disagree on
# intermediate ranks for the same organism -- NCBI puts Girella in
# Centrarchiformes where GBIF says Perciformes -- so an any-shared-rank test
# rejected a correct class for every fish tried. Disagreement above the filled
# rank means a different organism; disagreement below it is classification
# churn.
#
# KINGDOM is also excluded, for a different reason: the two backbones use
# different vocabulary for the same kingdom. NCBI says "Metazoa" where GBIF
# says "Animalia", which is not a contradiction at all, and including kingdom
# rejected every fish a second time. Normalising that would mean hard-coding a
# synonym list for particular taxa, which this codebase deliberately avoids.
#
# What is left is phylum (and division, its botanical equivalent) -- the
# highest rank the backbones actually name alike, and the rank immediately
# above class. It is enough to catch the case worth catching: GBIF's polychaete
# worm genus "Corallina" is phylum Annelida where NCBI's red alga of the same
# name is phylum Rhodophyta. When neither backbone names a comparable rank
# there is nothing to contradict and the fill is allowed.
#' @noRd
.LINEAGE_AGREEMENT_RANKS <- c("phylum", "division")

#' @noRd
.lineages_agree <- function(primary, fb) {
  if (is.null(fb) || nrow(fb) == 0L) return(character(0))
  if (is.null(primary) || nrow(primary) == 0L) return(fb$genus)
  split_named <- function(path, ranks) {
    if (is.na(path) || is.na(ranks)) return(character(0))
    p <- strsplit(path, "|", fixed = TRUE)[[1L]]
    r <- strsplit(ranks, "|", fixed = TRUE)[[1L]]
    n <- min(length(p), length(r))
    if (n == 0L) return(character(0))
    stats::setNames(trimws(p[seq_len(n)]), tolower(trimws(r[seq_len(n)])))
  }
  keep <- vapply(seq_len(nrow(fb)), function(k) {
    j <- match(fb$genus[k], primary$genus)
    # The primary could not place this genus AT ALL -- which is NOT the same as
    # being silent about one rank, and is exactly when the fallback is least
    # safe. Measured 2026-10-08: NCBI refuses "Liparis" as an ambiguous name
    # (a snailfish and an orchid), so it never reached the primary lineage
    # table; GBIF then resolved the same string to an INSECT genus and a
    # "nothing to contradict" allowance filled class = "Insecta" on a fish.
    # With no primary lineage there is nothing to check against, so the value
    # is refused and the rank stays NA. Same principle K. Lafferty chose for
    # cross_phylum_eps: unresolvable is not evidence of agreement.
    if (is.na(j)) return(FALSE)
    # The same refusal when the primary has a row it could not ANSWER: an
    # undecidable NCBI homonym, a failed lookup or a lineage-gated rejection
    # is "could not place", not "silent about one rank". Reading such a row's
    # empty path as "nothing to contradict" accepted a GBIF plant genus's
    # class for the larvacean Appendicularia. A row the backbone answered
    # with NO match (the name is absent there) keeps the allowance below.
    if ("answered" %in% names(primary) && !isTRUE(primary$answered[j])) return(FALSE)
    a <- split_named(primary$path[j], primary$ranks[j])
    b <- split_named(fb$path[k], fb$ranks[k])
    shared <- intersect(intersect(names(a), names(b)), .LINEAGE_AGREEMENT_RANKS)
    if (!length(shared)) return(TRUE)
    all(a[shared] == b[shared])
  }, logical(1))
  fb$genus[keep]
}


# Parse one rank value from pipe-delimited classification_path +
# classification_ranks strings.  Returns NA_character_ if rank not found.
#' @noRd
.extract_classified_rank <- function(path, ranks, target_rank) {
  if (is.na(path) || is.na(ranks) || !nzchar(path) || !nzchar(ranks)) {
    return(NA_character_)
  }
  rank_vec <- strsplit(ranks, "|", fixed = TRUE)[[1L]]
  path_vec <- strsplit(path, "|", fixed = TRUE)[[1L]]
  idx <- which(rank_vec == target_rank)
  if (length(idx) == 0L || idx[1L] > length(path_vec)) {
    return(NA_character_)
  }
  path_vec[idx[1L]]
}
