utils::globalVariables(c("taxid", "rank", "division", "genbankdivision", "scientificname"))

# ==============================================================================
# NCBI homonym detection
# ==============================================================================
# A taxon name is not a key: NCBI can hold several nodes with the same name in
# unrelated lineages (a genus of red algae named "Vertebrata", a genus of
# grasshoppers named "Acrotylus" beside a genus of red algae by the same
# name), and a plain name-based search resolves to whichever node the service
# prefers -- for an [ORGN] search, any node in the lineage, so a higher-rank
# or larger-volume homonym wins regardless of which one the caller meant.
# See ecosystem_docs/REENTRY_PROMPT_homonym_detection.md for the full incident
# record (measured 2026-09-22): a red-algal genus query for "Vertebrata"
# returned 306,181 vertebrate sequences alongside 68 real red-algal ones.

#' Confirmed NCBI name collisions across unrelated lineages
#'
#' Not exported. A small, hand-curated set of taxon names known to resolve
#' to more than one NCBI taxonomy node in genuinely unrelated lineages,
#' recorded as each case was found by a real sweep (see
#' ecosystem_docs/REENTRY_PROMPT_homonym_detection.md: 78 of 4,638 genera in
#' one real COI reference fetch disagreed with the match object's own
#' family, of which 11 were confirmed homonyms). Deliberately kept
#' unexported and undocumented as public API: it is a snapshot of what one
#' fetch happened to surface, not a property of NCBI, so it is incomplete on
#' day one and would go stale as NCBI's taxonomy changes -- exporting it
#' would invite a caller to guard against these twelve names specifically
#' instead of running \code{\link{resolve_ncbi_taxid}}, the actual
#' mechanism, which catches a name not on this list too. It earns its keep
#' as the fixture in \code{test-ncbi_homonyms.R} (real, verified cases) and
#' as the source for \code{\link{resolve_ncbi_taxid}}'s own worked examples.
#' @noRd
.known_ncbi_homonyms <- data.frame(
  name = c(
    "Vertebrata", "Digenea", "Grania", "Contarinia", "Acrotylus",
    "Ptilophora", "Mastophora", "Galene", "Lobophora", "Bulla",
    "Ctenophora", "Armadillo"
  ),
  lineage_a = c(
    "Rhodomelaceae (red alga)", "Rhodomelaceae (red alga)",
    "Acrochaetiaceae (red alga)", "Rhizophyllidaceae (red alga)",
    "Acrotylaceae (red alga)", "Gelidiaceae (red alga)",
    "Corallinaceae (coralline alga)", "Halymeniaceae (red alga)",
    "Dictyotaceae (brown alga)", "Bullidae (bubble snail)",
    "Tipulidae (crane fly)", "Armadillidae (isopod)"
  ),
  lineage_b = c(
    "Phyllostomidae (bats)", "Diplostomidae (trematodes)",
    "Enchytraeidae (oligochaetes)", "Cecidomyiidae (gall midges)",
    "Acrididae (grasshoppers)", "Notodontidae (moths)",
    "Araneidae (orb-weaver spiders)", "Galenidae (crabs)",
    "Geometridae (moths)", "Tetrigidae (pygmy grasshoppers)",
    "Beroidae (comb jellies)", "Dasypodidae (armadillos)"
  ),
  stringsAsFactors = FALSE
)

#' NCBI rate-limit delay: 0.34s without API key, 0.11s with key
#' @noRd
.ncbi_homonym_delay <- function() {
  has_key <- nzchar(Sys.getenv("ENTREZ_KEY", "")) ||
    nzchar(Sys.getenv("NCBI_API_KEY", ""))
  if (has_key) 0.11 else 0.34
}

#' Fetch rank/division/scientificname for a set of NCBI taxonomy ids
#' @noRd
.ncbi_taxid_candidates <- function(ids) {
  summ <- rentrez::entrez_summary(db = "taxonomy", id = ids)
  if (inherits(summ, "esummary")) summ <- list(summ)
  rows <- lapply(summ, function(s) {
    data.frame(
      taxid = as.character(s[["uid"]] %||% NA_character_),
      rank = as.character(s[["rank"]] %||% NA_character_),
      division = as.character(s[["division"]] %||% NA_character_),
      genbankdivision = as.character(s[["genbankdivision"]] %||% NA_character_),
      scientificname = as.character(s[["scientificname"]] %||% NA_character_),
      stringsAsFactors = FALSE
    )
  })
  dplyr::bind_rows(rows)
}

#' Resolve a taxon name to one disambiguated NCBI taxonomy id
#'
#' A taxon name is not a key -- NCBI can hold several nodes with the same
#' name in unrelated lineages (real confirmed cases include a genus of red
#' algae named "Vertebrata" beside the vertebrate clade of the same name,
#' and a genus of moths named "Lobophora" beside a genus of brown algae of
#' the same name), and a name-based sequence search silently resolves
#' to whichever node the service prefers. This function disambiguates by
#' resolving to a taxonomy id first, using the caller's OWN declared rank
#' and/or higher-rank lineage as discriminators, so a caller can then query
#' by \code{txid<id>[ORGN]} instead of \code{<name>[Organism]}.
#'
#' Two discriminators are tried, in order, whenever a name resolves to more
#' than one node:
#' \enumerate{
#'   \item \strong{Rank.} If \code{rank} is supplied, candidates whose own
#'     NCBI rank does not match are dropped. This alone resolves many real
#'     cases (e.g. a genus-rank alga vs. a clade-rank "Vertebrata"), but is
#'     NOT sufficient alone -- two candidates can share the same rank (e.g.
#'     two genus-rank "Lobophora", one a moth, one a brown alga).
#'   \item \strong{Lineage containment.} If more than one candidate survives
#'     the rank filter (or \code{rank} was not supplied at all), each
#'     surviving candidate's own full NCBI lineage is fetched and tested for
#'     ANY overlap (case-insensitive) with \code{lineage_terms} -- the
#'     caller's own known higher-rank names for this taxon (e.g. its phylum,
#'     class, order, family). A candidate with zero overlap is dropped.
#' }
#' A name resolving to exactly one surviving candidate at any stage is
#' returned as the answer; a name resolving to zero or more than one after
#' both discriminators is reported \code{"ambiguous"} rather than guessed.
#'
#' @param name Character scalar. The taxon name to resolve.
#' @param rank Character scalar or \code{NULL} (default). The caller's own
#'   declared rank for \code{name} (e.g. \code{"genus"}), used as the first
#'   discriminator. Case-insensitive.
#' @param lineage_terms Character vector or \code{NULL} (default). The
#'   caller's own known higher-rank names for \code{name} (e.g.
#'   \code{c("Rhodomelaceae", "Ceramiales", "Florideophyceae", "Rhodophyta")}),
#'   used as the second discriminator when rank alone cannot decide.
#' @return A list:
#'   \describe{
#'     \item{taxid}{Character scalar, the resolved NCBI taxonomy id, or
#'       \code{NA_character_} if not found or ambiguous.}
#'     \item{status}{One of \code{"unique"} (only one node has this name),
#'       \code{"resolved_by_rank"}, \code{"resolved_by_lineage"},
#'       \code{"ambiguous"} (more than one candidate survived both
#'       discriminators), or \code{"not_found"}.}
#'     \item{candidates}{A data frame of every NCBI node sharing this name
#'       (\code{taxid}, \code{rank}, \code{division}, \code{genbankdivision},
#'       \code{scientificname}), for logging/inspection regardless of
#'       status. Zero rows when \code{status == "not_found"}.}
#'   }
#' @examples
#' \dontrun{
#' # The Vertebrata case: a name-based "Vertebrata[ORGN]" search pulls in
#' # vertebrate sequences alongside the wanted red-algal ones. Rank alone
#' # disambiguates here, since the two candidates differ in rank (genus vs.
#' # clade) -- see ecosystem_docs/REENTRY_PROMPT_homonym_detection.md for
#' # the full measured incident.
#' resolve_ncbi_taxid("Vertebrata", rank = "genus",
#'   lineage_terms = c("Rhodomelaceae", "Ceramiales", "Rhodophyta"))
#' # -> taxid "1261581", status "resolved_by_rank"
#'
#' # The Lobophora case: rank alone is NOT enough here, because both real
#' # candidates are genus-rank (one a moth genus, one a brown alga) --
#' # lineage containment is what decides it.
#' resolve_ncbi_taxid("Lobophora", rank = "genus",
#'   lineage_terms = c("Dictyotaceae", "Phaeophyceae"))
#' # -> taxid "157000", status "resolved_by_lineage"
#' }
#' @export
resolve_ncbi_taxid <- function(name, rank = NULL, lineage_terms = NULL) {
  if (!is.character(name) || length(name) != 1L || is.na(name) || !nzchar(trimws(name))) {
    stop("resolve_ncbi_taxid: `name` must be a single non-empty character string.")
  }
  if (!requireNamespace("rentrez", quietly = TRUE)) {
    stop("resolve_ncbi_taxid requires the 'rentrez' package. Install with: install.packages('rentrez')")
  }
  if (!is.null(rank)) {
    if (!is.character(rank) || length(rank) != 1L || is.na(rank)) {
      stop("resolve_ncbi_taxid: `rank` must be a single character string or NULL.")
    }
    rank <- tolower(trimws(rank))
  }
  if (!is.null(lineage_terms)) {
    if (!is.character(lineage_terms)) {
      stop("resolve_ncbi_taxid: `lineage_terms` must be a character vector or NULL.")
    }
    lineage_terms <- tolower(trimws(lineage_terms[!is.na(lineage_terms) & nzchar(trimws(lineage_terms))]))
  }

  empty_candidates <- data.frame(
    taxid = character(0), rank = character(0), division = character(0),
    genbankdivision = character(0), scientificname = character(0),
    stringsAsFactors = FALSE
  )

  res <- tryCatch(
    rentrez::entrez_search(db = "taxonomy", term = sprintf('"%s"[All Names]', name)),
    error = function(e) NULL
  )
  if (is.null(res) || length(res$ids) == 0L) {
    return(list(taxid = NA_character_, status = "not_found", candidates = empty_candidates))
  }
  if (length(res$ids) == 1L) {
    cand <- tryCatch(.ncbi_taxid_candidates(res$ids), error = function(e) NULL)
    return(list(taxid = res$ids[[1L]], status = "unique", candidates = cand %||% empty_candidates))
  }

  Sys.sleep(.ncbi_homonym_delay())
  candidates <- tryCatch(.ncbi_taxid_candidates(res$ids), error = function(e) NULL)
  if (is.null(candidates) || nrow(candidates) == 0L) {
    return(list(taxid = NA_character_, status = "ambiguous", candidates = empty_candidates))
  }

  survivors <- candidates
  if (!is.null(rank)) {
    by_rank <- survivors[!is.na(survivors$rank) & tolower(survivors$rank) == rank, , drop = FALSE]
    if (nrow(by_rank) == 1L) {
      return(list(taxid = by_rank$taxid[[1L]], status = "resolved_by_rank", candidates = candidates))
    }
    if (nrow(by_rank) > 1L) survivors <- by_rank
    # nrow(by_rank) == 0L: rank could not discriminate at all -- fall through
    # to lineage disambiguation over the FULL candidate set, not an empty one.
  }

  if (length(lineage_terms) > 0L && nrow(survivors) > 1L) {
    Sys.sleep(.ncbi_homonym_delay())
    lineage_hits <- vapply(survivors$taxid, function(tid) {
      xml_raw <- tryCatch(
        rentrez::entrez_fetch(db = "taxonomy", id = tid, rettype = "xml"),
        error = function(e) NA_character_
      )
      if (is.na(xml_raw)) return(FALSE)
      parsed <- tryCatch(.parse_ncbi_lineage_xml(xml_raw), error = function(e) NULL)
      lin <- parsed[[as.character(tid)]]
      if (is.null(lin)) return(FALSE)
      lin_terms <- tolower(trimws(strsplit(lin$classification_path, "|", fixed = TRUE)[[1L]]))
      any(lineage_terms %in% lin_terms)
    }, logical(1L))
    by_lineage <- survivors[lineage_hits, , drop = FALSE]
    if (nrow(by_lineage) == 1L) {
      return(list(taxid = by_lineage$taxid[[1L]], status = "resolved_by_lineage", candidates = candidates))
    }
  }

  list(taxid = NA_character_, status = "ambiguous", candidates = candidates)
}

#' Split a pipe- or semicolon-delimited lineage string into normalised terms
#' @noRd
.lineage_split <- function(x) {
  if (is.na(x) || !nzchar(trimws(x))) {
    return(character(0))
  }
  terms <- strsplit(x, "[|;]")[[1L]]
  terms <- tolower(trimws(terms))
  terms[nzchar(terms)]
}

#' Check whether a returned lineage agrees with a declared one
#'
#' A cheap, no-API-call post-fetch guard: given what a caller DECLARED about
#' a taxon's own higher-rank lineage (e.g. from their own match object) and
#' what a name-based fetch ACTUALLY RETURNED for it, decides whether the two
#' are the same organism reclassified (a benign revision -- accept) or two
#' different organisms sharing a name (a homonym -- reject). Both present
#' identically as "the returned lineage disagrees with mine"; the operative
#' test is not whether any one rank matches exactly, but whether the
#' disagreement is CONTAINED within some shared higher clade at all. See
#' \code{ecosystem_docs/REENTRY_PROMPT_homonym_detection.md}'s "HOMONYM vs
#' BENIGN REVISION" section for the full reasoning and real worked examples
#' (e.g. \code{Modiolus} Mytilidae -> Modiolidae is a revision, both molluscs;
#' \code{Polychaeta} class -> a tachinid fly genus is a homonym).
#'
#' @param declared Character vector. One element per row: the caller's own
#'   known higher-rank lineage terms for that row, pipe- or
#'   semicolon-delimited (e.g. \code{"Rhodophyta|Florideophyceae|Ceramiales"}).
#' @param returned Character vector, same length as \code{declared}. The
#'   corresponding lineage actually returned by the fetch being checked, in
#'   the same delimited form.
#' @return Character vector, same length as \code{declared}, one of
#'   \code{"agrees"} (at least one shared term -- same clade, whether an
#'   exact match or a benign revision), \code{"disagrees"} (both sides have
#'   real terms and share none -- a likely homonym), or \code{"unknown"}
#'   (one or both sides had nothing to compare).
#' @examples
#' check_lineage_agreement(
#'   declared = c("Rhodophyta|Rhodomelaceae", "Mollusca|Mytilidae"),
#'   returned = c("Chordata|Mammalia", "Mollusca|Modiolidae")
#' )
#' # -> c("disagrees", "agrees")
#' @export
check_lineage_agreement <- function(declared, returned) {
  if (!is.character(declared) || !is.character(returned)) {
    stop("check_lineage_agreement: `declared` and `returned` must be character vectors.")
  }
  if (length(declared) != length(returned)) {
    stop("check_lineage_agreement: `declared` and `returned` must be the same length.")
  }
  vapply(seq_along(declared), function(i) {
    d <- .lineage_split(declared[[i]])
    r <- .lineage_split(returned[[i]])
    if (length(d) == 0L || length(r) == 0L) {
      return("unknown")
    }
    if (any(d %in% r)) "agrees" else "disagrees"
  }, character(1L))
}
