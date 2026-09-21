# ==============================================================================
# fetch_worms_attributes() -- WoRMS taxon attributes by name
# ==============================================================================
#
# WHY THIS EXISTS. The ecosystem's habitat signal is
# TaxaHabitat::build_habitat_lookup(), an LLM verdict over four EXCLUSIVE
# categories (Marine / Estuarine / Freshwater / Terrestrial). Forcing one
# choice breaks on animals that use two realms: the black oystercatcher,
# sanderling, black turnstone and whimbrel all come back "Terrestrial"
# because they stand on rock, and 381 of 578 PtConception birds go the same
# way. WoRMS is MULTI-LABEL -- the oystercatcher is marine = TRUE AND
# terrestrial = TRUE -- which is the representation the four-category
# scheme cannot express and the reason the LLM picks wrong.
#
# It lives in TaxaTools, not TaxaFetch, because it is a by-NAME taxonomic
# attribute lookup (the same shape as verify_taxon_names() / change_backbone())
# and not an occurrence fetch. GBIF remains the single occurrence source for
# every workflow; OBIS integration was considered and declined.
#
# Internal helpers are deliberately placed ABOVE the exported function's roxygen
# block: a helper inserted BETWEEN a roxygen block and its function definition
# silently steals the @export, and devtools::document() reports nothing wrong.

.WORMS_REST <- "https://www.marinespecies.org/rest"

# WoRMS returns these as 1 / 0 / null. Null means "not assessed", which is NOT
# the same claim as 0 ("assessed, not present"), so it becomes NA rather than
# FALSE. Callers that need a never-NA logical read `marine_scope`.
#' @noRd
.worms_flag <- function(x) {
  if (is.null(x) || length(x) == 0L) {
    return(NA)
  }
  x <- suppressWarnings(as.integer(x[[1L]]))
  if (is.na(x)) NA else x == 1L
}

#' @noRd
.worms_chr <- function(x) {
  if (is.null(x) || length(x) == 0L) NA_character_ else as.character(x[[1L]])
}

#' @noRd
.worms_int <- function(x) {
  if (is.null(x) || length(x) == 0L) NA_integer_ else suppressWarnings(as.integer(x[[1L]]))
}

# One empty row. Every assembly path starts here so the returned schema is
# identical whether a name matched, was absent, or was rejected as fuzzy.
#' @noRd
.worms_empty_row <- function(name) {
  list(
    taxon_name         = name,
    in_worms           = FALSE,
    aphia_id           = NA_integer_,
    accepted_name      = NA_character_,
    accepted_aphia_id  = NA_integer_,
    taxonomic_status   = NA_character_,
    worms_rank         = NA_character_,
    match_type         = NA_character_,
    n_matches          = 0L,
    fuzzy_rejected     = FALSE,
    is_marine          = NA,
    is_brackish        = NA,
    is_freshwater      = NA,
    is_terrestrial     = NA,
    marine_scope       = FALSE,
    habitat_unassessed = FALSE,
    worms_ambiguous    = FALSE,
    habitat_conflict   = FALSE,
    ncbi_id            = NA_character_,
    wrims              = NA,
    kingdom            = NA_character_,
    phylum             = NA_character_,
    class              = NA_character_,
    order              = NA_character_,
    family             = NA_character_,
    genus              = NA_character_
  )
}

# Turn the records WoRMS returned for ONE input name into one row.
#
# TWO RULES CARRY THE SAFETY ARGUMENT HERE, because this function's failure mode
# is silent loss of a real detection:
#
#   1. A fuzzy match is NOT a match. "Mytilus edulus" resolves to Mytilus edulis
#      with match_type = "phonetic"; harmless there, but the same machinery will
#      happily hand a terrestrial homonym's habitat flags to a marine name, and
#      a filter built on that cuts a real taxon on another taxon's status.
#      Rejected fuzzy matches are RECORDED (`fuzzy_rejected`), never hidden.
#   2. Homonyms are ORed, not resolved. "Ficus" is BOTH a marine gastropod genus
#      (AphiaID 205605, isMarine = 1) and the fig genus (447837, isMarine = 0).
#      Picking one would be a coin flip whose wrong face deletes data, so
#      marine_scope is TRUE if ANY retained match is marine or brackish, and
#      `worms_ambiguous` / `habitat_conflict` make the case auditable.
#' @noRd
.worms_row_from_records <- function(name, recs, accept_fuzzy) {
  row <- .worms_empty_row(name)
  if (is.null(recs) || length(recs) == 0L) {
    return(row)
  }

  mt <- vapply(recs, function(r) .worms_chr(r$match_type), character(1))
  keep <- if (accept_fuzzy) rep(TRUE, length(recs)) else !is.na(mt) & mt == "exact"

  if (!any(keep)) {
    # Something came back, but nothing we are willing to trust. Say so.
    row$match_type     <- paste(sort(unique(mt[!is.na(mt)])), collapse = "/")
    row$fuzzy_rejected <- TRUE
    row$n_matches      <- length(recs)
    return(row)
  }

  recs <- recs[keep]
  mt <- mt[keep]

  # --- representative record: first accepted, else first ----------------------
  status <- vapply(recs, function(r) .worms_chr(r$status), character(1))
  rep_i <- which(!is.na(status) & status == "accepted")[1L]
  if (is.na(rep_i)) rep_i <- 1L
  rep <- recs[[rep_i]]

  flags <- function(field) vapply(recs, function(r) .worms_flag(r[[field]]), logical(1))
  f_mar <- flags("isMarine")
  f_bra <- flags("isBrackish")
  f_fre <- flags("isFreshwater")
  f_ter <- flags("isTerrestrial")

  # `%in% TRUE` rather than `|`: NA | FALSE is NA, and an NA keep-vector handed
  # to an ESV filter neither keeps nor drops -- it errors or silently subsets.
  scope_per_rec <- (f_mar %in% TRUE) | (f_bra %in% TRUE)

  row$in_worms          <- TRUE
  row$aphia_id          <- .worms_int(rep$AphiaID)
  row$accepted_name     <- .worms_chr(rep$valid_name)
  row$accepted_aphia_id <- .worms_int(rep$valid_AphiaID)
  row$taxonomic_status  <- .worms_chr(rep$status)
  row$worms_rank        <- .worms_chr(rep$rank)
  row$match_type        <- .worms_chr(rep$match_type)
  row$n_matches         <- length(recs)
  row$fuzzy_rejected    <- FALSE

  row$is_marine      <- .worms_flag(rep$isMarine)
  row$is_brackish    <- .worms_flag(rep$isBrackish)
  row$is_freshwater  <- .worms_flag(rep$isFreshwater)
  row$is_terrestrial <- .worms_flag(rep$isTerrestrial)

  row$marine_scope <- any(scope_per_rec)
  # In the register but with all four flags unset. These are the taxa a
  # marine filter would drop for lack of evidence rather than on evidence,
  # so they are counted separately and reported, never folded into "absent".
  row$habitat_unassessed <- all(is.na(c(
    row$is_marine, row$is_brackish, row$is_freshwater, row$is_terrestrial
  )))
  row$worms_ambiguous  <- length(recs) > 1L
  row$habitat_conflict <- length(recs) > 1L && length(unique(scope_per_rec)) > 1L

  for (rk in c("kingdom", "phylum", "class", "order", "family", "genus")) {
    row[[rk]] <- .worms_chr(rep[[rk]])
  }

  row
}

#' @noRd
.worms_get <- function(url, timeout = 60) {
  resp <- tryCatch(
    httr2::request(url) |>
      httr2::req_timeout(timeout) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_perform(),
    error = function(e) e
  )
  if (inherits(resp, "error")) {
    return(list(ok = FALSE, status = NA_integer_, body = NULL))
  }
  status <- httr2::resp_status(resp)
  # 204 = "no content", i.e. a genuine answer of "nothing here", not a failure.
  if (status == 204L) {
    return(list(ok = TRUE, status = 204L, body = NULL))
  }
  if (status != 200L) {
    return(list(ok = FALSE, status = status, body = NULL))
  }
  body <- tryCatch(httr2::resp_body_json(resp), error = function(e) NULL)
  list(ok = !is.null(body), status = status, body = body)
}

# Batch the name-match call. Chunks respect BOTH a name count and a URL-length
# budget: the endpoint takes repeated scientificnames[] parameters, so a batch
# of long names can blow the server's URL limit while sitting well under
# batch_size. Returns a named list: name -> list of records (or NULL on a
# failed request, which the caller must not cache).
#' @noRd
.worms_match_names <- function(names_vec, batch_size, delay, verbose,
                               url_budget = 6000L) {
  out <- stats::setNames(vector("list", length(names_vec)), names_vec)
  failed <- character(0)

  # --- chunk on count AND encoded length --------------------------------------
  costs <- nchar(vapply(names_vec, utils::URLencode, character(1), reserved = TRUE)) + 20L
  chunks <- list()
  cur <- integer(0)
  cur_cost <- 0L
  for (i in seq_along(names_vec)) {
    if (length(cur) > 0L &&
      (length(cur) >= batch_size || cur_cost + costs[[i]] > url_budget)) {
      chunks[[length(chunks) + 1L]] <- cur
      cur <- integer(0)
      cur_cost <- 0L
    }
    cur <- c(cur, i)
    cur_cost <- cur_cost + costs[[i]]
  }
  if (length(cur) > 0L) chunks[[length(chunks) + 1L]] <- cur

  for (ci in seq_along(chunks)) {
    idx <- chunks[[ci]]
    nms <- names_vec[idx]
    req <- httr2::request(file.path(.WORMS_REST, "AphiaRecordsByMatchNames")) |>
      httr2::req_url_query(
        `scientificnames[]` = nms,
        marine_only = "false",
        .multi = "explode"
      )

    res <- .worms_get(req$url)

    if (!res$ok) {
      # A failed request is NOT an answer. Leave these NULL so the caller
      # neither reports them as absent nor writes them to the cache.
      failed <- c(failed, nms)
    } else if (is.null(res$body)) {
      for (k in seq_along(nms)) out[[idx[[k]]]] <- list()
    } else {
      body <- res$body
      if (length(body) != length(nms)) {
        # Positional alignment is the endpoint's only contract. If it is not
        # honoured we cannot tell which answer belongs to which name.
        failed <- c(failed, nms)
      } else {
        for (k in seq_along(nms)) out[[idx[[k]]]] <- body[[k]]
      }
    }

    if (verbose && length(chunks) > 1L) {
      message(sprintf(
        "  fetch_worms_attributes(): name batch %d of %d (%d names).",
        ci, length(chunks), length(nms)
      ))
    }
    if (ci < length(chunks)) Sys.sleep(delay)
  }

  attr(out, "failed") <- unique(failed)
  out
}

# NCBI taxon id for one AphiaID. WoRMS curates this crosswalk; the ecosystem
# otherwise recomputes it live through verify_taxon_names(backbone_id = 4),
# which costs API calls and does not always resolve (higher-rank names
# sometimes get no GBIF match at all).
# Returns list(ok, value). ok = FALSE means the request failed and must not
# be cached; ok = TRUE with value = NA means "WoRMS has no NCBI id for this".
#' @noRd
.worms_ncbi_id <- function(aphia_id) {
  res <- .worms_get(sprintf("%s/AphiaExternalIDByAphiaID/%d?type=ncbi", .WORMS_REST, aphia_id))
  if (!res$ok) {
    return(list(ok = FALSE, value = NA_character_))
  }
  if (is.null(res$body) || length(res$body) == 0L) {
    return(list(ok = TRUE, value = NA_character_))
  }
  list(ok = TRUE, value = as.character(res$body[[1L]]))
}

# Introduced-species flag, DERIVED, and named `wrims` after the WRiMS
# (World Register of Introduced Marine Species) list. WoRMS exposes no
# equivalent single field (the 42 public AphiaAttributeKeys contain no
# introduced/alien key, and Carcinus maenas -- a flagship WRiMS species --
# carries none). What WoRMS does expose is per-locality distributions with an
# `establishmentMeans` of "Alien" / "Native" / "Native - Non-endemic", and
# WRiMS is built from exactly those alien records. So: TRUE when any
# distribution record is Alien. This is the expensive extra -- one call per
# taxon, ~70 KB for a well-recorded species -- which is why it is opt-in.
#' @noRd
.worms_wrims <- function(aphia_id) {
  res <- .worms_get(sprintf("%s/AphiaDistributionsByAphiaID/%d", .WORMS_REST, aphia_id))
  if (!res$ok) {
    return(list(ok = FALSE, value = NA))
  }
  if (is.null(res$body) || length(res$body) == 0L) {
    return(list(ok = TRUE, value = FALSE))
  }
  em <- vapply(res$body, function(d) .worms_chr(d$establishmentMeans), character(1))
  list(ok = TRUE, value = any(!is.na(em) & grepl("alien", em, ignore.case = TRUE)))
}


# ---- per-name on-disk cache --------------------------------------------------
# One small .rds per (name, accept_fuzzy), the same file-per-key shape
# scientific_to_common(cache_dir=), TaxaFlag::review_assignments(cache_dir=) and
# TaxaHabitat::build_habitat_lookup(cache_dir=) use, so
# list_cache_files()/report_and_clear_cache() manage it. The full key is stored
# inside the file and verified on read, so a hash collision costs one re-asked
# name and can never return another name's answer.
#
# No TTL. Unlike an LLM verdict these are curated attributes that do not drift
# between runs; the staleness axis is WoRMS itself being revised, which is a
# manual taxatools_clear_cache() decision, not something to guess at per run.
#
# THE `resolved` FIELD IS LOAD-BEARING. A run with extras = character(0) writes
# a row whose ncbi_id is NA because it was never asked for -- not because WoRMS
# has none. Keying the file on `extras` instead would re-fetch the flags too;
# caching the NA would make the omission permanent, silently treating "never
# asked" as "asked and absent" on every future read. So the file records
# WHICH extras have actually been answered, and a request for an unrecorded
# extra is a partial hit: the flags are reused, only the missing extra is
# fetched, and the file is rewritten. Existing caches heal themselves.

#' @noRd
.worms_cache_key <- function(name, accept_fuzzy) {
  list(
    name         = tolower(trimws(name)),
    accept_fuzzy = isTRUE(accept_fuzzy),
    source       = "worms_attributes_v1"
  )
}

#' @noRd
.worms_cache_path <- function(cache_dir, key) {
  file.path(cache_dir, paste0(rlang::hash(key), "_worms_attr.rds"))
}

#' @noRd
.read_worms_cache <- function(cache_dir, key) {
  path <- .worms_cache_path(cache_dir, key)
  if (!file.exists(path)) {
    return(NULL)
  }
  hit <- tryCatch(readRDS(path), error = function(e) NULL)
  if (is.null(hit) || !identical(hit$key, key) || !is.list(hit$row)) {
    return(NULL)
  }
  list(row = hit$row, resolved = as.character(hit$resolved %||% character(0)))
}

#' @noRd
.write_worms_cache <- function(cache_dir, key, row, resolved) {
  saveRDS(
    list(key = key, row = row, resolved = as.character(resolved)),
    .worms_cache_path(cache_dir, key)
  )
  invisible(TRUE)
}


#' Fetch WoRMS Taxon Attributes by Name
#'
#' Looks up taxa in the World Register of Marine Species (WoRMS) **by name** and
#' returns the curated attributes each one carries: the multi-label marine /
#' brackish / freshwater / terrestrial habitat flags, the AphiaID, accepted name
#' and taxonomic status, the WoRMS classification, and optionally the curated
#' NCBI taxon id and a derived introduced-species flag.
#'
#' @details
#' \strong{Why this is not the habitat lookup you already have.}
#' \code{TaxaHabitat::build_habitat_lookup()} asks an LLM to choose ONE of
#' Marine / Estuarine / Freshwater / Terrestrial. Intertidal foragers that stand
#' on rock come back Terrestrial -- the black oystercatcher (M 0.40 / T 0.50),
#' sanderling (0.20 / 0.50), black turnstone (0.30 / 0.60) and whimbrel all do,
#' and 381 of 578 PtConception birds go the same way.
#' WoRMS records the oystercatcher as marine \emph{and} terrestrial. The two
#' sources answer different questions and neither replaces the other.
#'
#' \strong{The filter rule is "keep if marine OR brackish", never "drop if
#' terrestrial".} Every shorebird above is terrestrial = TRUE. Diadromous fish
#' are handled by the same rule without a special case: \emph{Oncorhynchus
#' mykiss} and \emph{Alosa sapidissima} are both marine = TRUE, brackish = TRUE,
#' freshwater = TRUE, terrestrial = FALSE. The \code{marine_scope} column
#' applies this rule and is never \code{NA}.
#'
#' \strong{Apply the verdict at detection level (an ESV/ASV for sequence
#' data, a per-image or per-recording candidate ID otherwise), not taxon
#' level.} Filtering
#' candidates \emph{within} an observation strips hypotheses out of a candidate
#' set and forces the read onto whichever ones survive. Drop an observation only
#' when NO candidate is in scope; an observation with any marine candidate keeps
#' its whole candidate set, out-of-scope competitors included. See the examples.
#'
#' \strong{This is a different axis from a taxonomic scope filter, and they
#' compose.} A taxonomic filter ("is this a fish / macroinvertebrate /
#' macroalga?") keeps terrestrial snails, freshwater mussels, freshwater
#' annelids and freshwater algae, because those are \code{Gastropoda} /
#' \code{Bivalvia} / \code{Polychaeta} / \code{Ulvophyceae} wherever they live.
#' Verified here: \emph{Cornu aspersum} (garden snail) and \emph{Lumbricus
#' terrestris} are marine = FALSE, so WoRMS cuts them. Conversely WoRMS cannot
#' cut a marine copepod and a taxonomic filter can. Report the saving from both.
#'
#' \strong{What happens to non-marine taxa is the caller's decision, and it
#' should not be silent deletion.} Human / pig / cow / chicken DNA is a
#' lab-contamination signal, and out-of-scope counts are a data-quality
#' diagnostic. Cut these taxa from the prior and likelihood path but retain the
#' rows and counts -- a \code{scope_excluded} table and a line in the pipeline
#' report.
#'
#' \strong{Two rules protect against silent loss of a real detection.} A fuzzy
#' match is not treated as a match unless \code{accept_fuzzy = TRUE}: WoRMS will
#' resolve "Mytilus edulus" phonetically to \emph{Mytilus edulis}, and the same
#' machinery will hand a terrestrial homonym's flags to a marine name. Rejected
#' fuzzy matches are reported in \code{fuzzy_rejected}, not hidden. And homonyms
#' are ORed rather than resolved: "Ficus" is both a marine gastropod genus
#' (AphiaID 205605, marine) and the fig genus (447837, not marine), so
#' \code{marine_scope} is TRUE if \emph{any} retained match is marine or
#' brackish, with \code{worms_ambiguous} and \code{habitat_conflict} marking the
#' case for review.
#'
#' \strong{Absence is part of the filter, and is also its main risk.}
#' \emph{Cervus elaphus} and \emph{Zea mays} are not in WoRMS at all, so there is
#' no threshold to tune. But a genuinely marine taxon missing from the register
#' is cut the same way. Every absent name is returned in the
#' \code{"not_in_worms"} attribute -- read it before trusting a run. Absence
#' is a weaker filter than intuition suggests: \emph{Homo sapiens} (1455977),
#' \emph{Sus scrofa} (1469456), \emph{Bos taurus} (1506698), \emph{Canis
#' lupus} (1506689) and \emph{Gallus gallus} (1463738) are all in the
#' register. They are cut on their flags (marine = FALSE / NA, terrestrial =
#' TRUE), not on absence.
#'
#' \strong{Names are used as supplied}, apart from whitespace trimming. Pass
#' names that have already been through \code{\link{clean_taxon_names}} if the
#' source carries open-nomenclature or voucher labels; slash labels and
#' \code{"Genus sp."} will not match.
#'
#' @param taxon_names Character vector of scientific names, at any rank. Genera
#'   and higher ranks resolve (\emph{Sebastes} -> AphiaID 126175;
#'   \code{Teleostei} -> 293496, a working class node where GBIF's backbone has
#'   no occurrence-bearing node for ray-finned fishes at all). Duplicates and
#'   \code{NA}s are dropped; one row is returned per unique name.
#' @param cache_dir Character or \code{NULL} (default, no cache). Directory for
#'   one small \code{.rds} per looked-up name, created if needed. Attributes are
#'   curated and do not drift, so there is no TTL; clear it deliberately with
#'   \code{\link{taxatools_clear_cache}}. A cached row records which
#'   \code{extras} were actually answered, so widening \code{extras} later
#'   re-fetches only the missing ones and never re-asks for the flags.
#' @param extras Character vector, any of \code{"ncbi_id"} and \code{"wrims"};
#'   \code{character(0)} for neither. Default \code{"ncbi_id"}. The habitat
#'   flags come free with the batched name match (~50 names per request), but
#'   each extra costs \strong{one HTTP call per matched taxon}, so the fast path
#'   for a pure marine-scope filter is \code{extras = character(0)}.
#'   \code{"wrims"} is the expensive one (~70 KB per taxon) and is off by
#'   default. The schema never changes: a column not requested is \code{NA},
#'   except that a cached row already holding it returns it (free -- it is read
#'   back, never re-fetched). So an \code{NA} here means "not asked for or not
#'   held by WoRMS", which is why \code{extras} is recorded in the
#'   \code{"worms_query"} attribute.
#' @param accept_fuzzy Logical, default \code{FALSE}. When \code{FALSE} only
#'   \code{match_type == "exact"} records are used. Leave it \code{FALSE} for
#'   anything that drives a filter.
#' @param batch_size Integer, default 50. Names per name-match request. Requests
#'   are additionally split to keep the URL under ~6,000 characters, so a batch
#'   of long names is chunked further on its own.
#' @param delay Numeric seconds between requests, default 0.5. Applies between
#'   name batches and between per-taxon extra calls.
#' @param verbose Logical, default \code{TRUE}. Progress and a summary.
#'
#' @return A tibble, one row per unique non-\code{NA} input name:
#' \describe{
#'   \item{\code{taxon_name}}{The name as supplied (whitespace trimmed).}
#'   \item{\code{in_worms}}{Logical. A trusted match was found.}
#'   \item{\code{aphia_id}, \code{accepted_name}, \code{accepted_aphia_id},
#'     \code{taxonomic_status}, \code{worms_rank}}{From the representative
#'     record (the first \code{accepted} match, else the first match).}
#'   \item{\code{match_type}}{\code{"exact"}, or the rejected match type(s) when
#'     \code{fuzzy_rejected} is \code{TRUE}.}
#'   \item{\code{n_matches}}{Records retained for this name.}
#'   \item{\code{fuzzy_rejected}}{WoRMS returned only non-exact matches and
#'     \code{accept_fuzzy = FALSE}, so none were used.}
#'   \item{\code{is_marine}, \code{is_brackish}, \code{is_freshwater},
#'     \code{is_terrestrial}}{Logical, \strong{multi-label and possibly
#'     \code{NA}}. \code{NA} means WoRMS has not assessed that realm, which is
#'     not the same claim as \code{FALSE}.}
#'   \item{\code{marine_scope}}{Logical, \strong{never \code{NA}}. \code{TRUE}
#'     when any retained match is marine or brackish. This is the column to hand
#'     to a detection-level scope filter.}
#'   \item{\code{habitat_unassessed}}{In WoRMS but all four flags \code{NA} --
#'     dropped for lack of evidence rather than on evidence. Counted separately
#'     and reported.}
#'   \item{\code{worms_ambiguous}, \code{habitat_conflict}}{More than one
#'     retained match; and those matches disagreeing about
#'     \code{marine_scope}.}
#'   \item{\code{ncbi_id}}{Character NCBI taxon id, or \code{NA}. A curated
#'     crosswalk, versus the live one computed by
#'     \code{verify_taxon_names(backbone_id = 4)} / \code{\link{change_backbone}}.}
#'   \item{\code{wrims}}{Logical. Any WoRMS distribution record with
#'     \code{establishmentMeans} of "Alien". Derived, not a WoRMS field -- see
#'     Details of \code{extras}.}
#'   \item{\code{kingdom}, \code{phylum}, \code{class}, \code{order},
#'     \code{family}, \code{genus}}{WoRMS classification of the representative
#'     record.}
#' }
#' Attributes on the result, always present (the \code{count_failures} pattern),
#' so a quiet run still leaves the residue inspectable:
#' \code{"n_not_in_worms"} / \code{"not_in_worms"},
#' \code{"n_fuzzy_rejected"} / \code{"fuzzy_rejected_taxa"},
#' \code{"n_habitat_unassessed"} / \code{"habitat_unassessed_taxa"},
#' \code{"n_habitat_conflict"} / \code{"habitat_conflict_taxa"},
#' \code{"n_request_failed"} / \code{"request_failed_taxa"} (names whose request
#' errored -- these are \strong{not} cached and are \strong{not} absences), and
#' \code{"worms_query"} with the settings used.
#'
#' @seealso \code{\link{taxatools_clear_cache}} to manage the cache;
#'   \code{\link{verify_taxon_names}} and \code{\link{change_backbone}} for the
#'   live GBIF/NCBI crosswalk that \code{ncbi_id} supplements.
#'
#' @source World Register of Marine Species REST API,
#'   \url{https://www.marinespecies.org/rest/}. WoRMS Editorial Board (2026).
#'   World Register of Marine Species. \url{https://www.marinespecies.org}.
#'
#' @importFrom httr2 request req_url_query req_timeout req_error req_perform
#' @importFrom httr2 resp_status resp_body_json
#' @importFrom dplyr bind_rows
#' @importFrom rlang hash
#' @export
#'
#' @examples
#' \dontrun{
#' # --- the flags ------------------------------------------------------------
#' fetch_worms_attributes(
#'   c("Haematopus bachmani", "Oncorhynchus mykiss", "Cornu aspersum"),
#'   extras = character(0)
#' )[, c("taxon_name", "is_marine", "is_brackish", "is_terrestrial", "marine_scope")]
#' # oystercatcher  marine TRUE + terrestrial TRUE -> kept (the LLM said Terrestrial)
#' # steelhead      marine/brackish/freshwater TRUE -> kept, no diadromy special case
#' # garden snail   marine FALSE -> cut, and no taxonomic filter would have cut it
#'
#' # --- detection-level application, which is the only safe one --------------
#' att <- fetch_worms_attributes(unique(match_obj$taxon_name), extras = character(0))
#' keep <- att$marine_scope[match(match_obj$taxon_name, att$taxon_name)]
#' keep[is.na(keep)] <- FALSE # a name never sent, or absent from the register
#'
#' # Drop an observation only when NO candidate is in scope. scope_filter_esvs()
#' # takes a group vector plus keep_groups, so pass the verdict as a group:
#' filtered <- scope_filter_esvs(
#'   match_obj,
#'   group = ifelse(keep, "marine", "out_of_scope"),
#'   keep_groups = "marine"
#' )
#'
#' # Keep the excluded rows -- do not silently discard them. Lab-contaminant
#' # flags and out-of-scope counts are data-quality diagnostics.
#' scope_excluded <- match_obj[!match_obj$observation_id %in%
#'   filtered$observation_id, ]
#'
#' # --- always read the residue ----------------------------------------------
#' attr(att, "not_in_worms") # a marine taxon here is a silent loss
#' attr(att, "habitat_unassessed_taxa") # dropped for want of evidence
#' attr(att, "habitat_conflict_taxa") # homonyms disagreeing, e.g. "Ficus"
#' }
fetch_worms_attributes <- function(taxon_names,
                                   cache_dir = NULL,
                                   extras = "ncbi_id",
                                   accept_fuzzy = FALSE,
                                   batch_size = 50L,
                                   delay = 0.5,
                                   verbose = TRUE) {
  # ---- validation ------------------------------------------------------------
  if (!is.character(taxon_names)) {
    stop("`taxon_names` must be a character vector.", call. = FALSE)
  }
  if (!is.null(cache_dir) &&
    (!is.character(cache_dir) || length(cache_dir) != 1L || is.na(cache_dir))) {
    stop("`cache_dir` must be a single character string or NULL.", call. = FALSE)
  }
  if (is.null(extras)) extras <- character(0)
  if (!is.character(extras)) {
    stop("`extras` must be a character vector (any of \"ncbi_id\", \"wrims\").", call. = FALSE)
  }
  extras <- unique(extras[!is.na(extras)])
  bad <- setdiff(extras, c("ncbi_id", "wrims"))
  if (length(bad)) {
    stop(
      "Unsupported `extras`: ", paste(bad, collapse = ", "),
      ". Supported: \"ncbi_id\", \"wrims\".",
      call. = FALSE
    )
  }
  if (!is.logical(accept_fuzzy) || length(accept_fuzzy) != 1L || is.na(accept_fuzzy)) {
    stop("`accept_fuzzy` must be TRUE or FALSE.", call. = FALSE)
  }
  if (!is.numeric(batch_size) || length(batch_size) != 1L || is.na(batch_size) || batch_size < 1) {
    stop("`batch_size` must be a single positive number.", call. = FALSE)
  }
  batch_size <- as.integer(batch_size)
  if (!is.numeric(delay) || length(delay) != 1L || is.na(delay) || delay < 0) {
    stop("`delay` must be a single non-negative number.", call. = FALSE)
  }
  if (!is.logical(verbose) || length(verbose) != 1L || is.na(verbose)) {
    stop("`verbose` must be TRUE or FALSE.", call. = FALSE)
  }

  empty_cols <- .worms_empty_row(NA_character_)
  make_empty_result <- function() {
    res <- dplyr::bind_rows(lapply(character(0), function(x) empty_cols))
    if (nrow(res) == 0L && ncol(res) == 0L) {
      res <- dplyr::as_tibble(lapply(empty_cols, function(v) v[0]))
    }
    res
  }

  names_in <- trimws(taxon_names)
  names_in <- names_in[!is.na(names_in) & nzchar(names_in)]
  names_in <- unique(names_in)

  if (length(names_in) == 0L) {
    out <- make_empty_result()
    return(.worms_finalise(out, extras, accept_fuzzy, character(0), verbose,
      n_input = 0L, n_cache = 0L
    ))
  }

  # ---- cache read (partial hits allowed) -------------------------------------
  keys <- lapply(names_in, .worms_cache_key, accept_fuzzy = accept_fuzzy)
  rows <- vector("list", length(names_in))
  resolved <- vector("list", length(names_in))
  have_flags <- rep(FALSE, length(names_in))
  # Only rewrite a cache file whose CONTENT changed. A warm run that rewrote
  # every file would reset its mtime, which is the axis
  # taxatools_clear_cache(older_than_days=) prunes on -- so re-running a
  # workflow would silently make a stale cache look brand new.
  dirty <- rep(FALSE, length(names_in))

  if (!is.null(cache_dir)) {
    if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)
    for (i in seq_along(names_in)) {
      hit <- .read_worms_cache(cache_dir, keys[[i]])
      if (!is.null(hit)) {
        rows[[i]] <- hit$row
        resolved[[i]] <- hit$resolved
        have_flags[[i]] <- TRUE
      }
    }
  }
  for (i in seq_along(names_in)) {
    if (is.null(resolved[[i]])) resolved[[i]] <- character(0)
  }

  n_from_cache <- sum(have_flags)

  # ---- name match for everything not served from cache -----------------------
  request_failed <- character(0)
  to_match <- which(!have_flags)
  if (length(to_match)) {
    if (verbose) {
      message(sprintf(
        "fetch_worms_attributes(): %d name(s) -- %d from cache, %d to WoRMS.",
        length(names_in), n_from_cache, length(to_match)
      ))
    }
    matched <- .worms_match_names(names_in[to_match], batch_size, delay, verbose)
    failed_names <- attr(matched, "failed")
    for (k in seq_along(to_match)) {
      i <- to_match[[k]]
      recs <- matched[[k]]
      if (is.null(recs) && names_in[[i]] %in% failed_names) {
        # Request failed. Not an answer -- emit an empty row, do not cache it,
        # and report it separately from a genuine absence.
        rows[[i]] <- .worms_empty_row(names_in[[i]])
        request_failed <- c(request_failed, names_in[[i]])
        next
      }
      rows[[i]] <- .worms_row_from_records(names_in[[i]], recs, accept_fuzzy)
      have_flags[[i]] <- TRUE
      dirty[[i]] <- TRUE
    }
  } else if (verbose) {
    message(sprintf(
      "fetch_worms_attributes(): %d name(s) -- all %d from cache.",
      length(names_in), n_from_cache
    ))
  }

  # ---- extras, one call per matched taxon ------------------------------------
  for (ex in extras) {
    need <- which(vapply(seq_along(names_in), function(i) {
      isTRUE(rows[[i]]$in_worms) &&
        !is.na(rows[[i]]$aphia_id) &&
        !(ex %in% resolved[[i]])
    }, logical(1)))

    if (!length(need)) next
    if (verbose) {
      message(sprintf(
        "  fetch_worms_attributes(): fetching %s for %d taxa (one request each).",
        ex, length(need)
      ))
    }
    for (j in seq_along(need)) {
      i <- need[[j]]
      got <- switch(ex,
        ncbi_id = .worms_ncbi_id(rows[[i]]$aphia_id),
        wrims   = .worms_wrims(rows[[i]]$aphia_id)
      )
      if (isTRUE(got$ok)) {
        rows[[i]][[ex]] <- got$value
        resolved[[i]] <- union(resolved[[i]], ex)
        dirty[[i]] <- TRUE
      } else {
        # Unanswered. Leave NA and DO NOT record it as resolved, so the next
        # run asks again instead of caching the non-answer forever.
        request_failed <- c(request_failed, names_in[[i]])
      }
      if (j < length(need)) Sys.sleep(delay)
    }
  }

  # ---- cache write -----------------------------------------------------------
  if (!is.null(cache_dir)) {
    n_written <- 0L
    for (i in seq_along(names_in)) {
      if (!have_flags[[i]]) next # request failed; never cache a non-answer
      if (!dirty[[i]]) next # unchanged; leave the file and its mtime alone
      .write_worms_cache(cache_dir, keys[[i]], rows[[i]], resolved[[i]])
      n_written <- n_written + 1L
    }
    if (verbose && n_written > 0L) {
      message(sprintf(
        "  fetch_worms_attributes(): %d row(s) written to the cache at %s.",
        n_written, cache_dir
      ))
    }
  }

  out <- dplyr::bind_rows(lapply(rows, function(r) dplyr::as_tibble(r)))
  .worms_finalise(out, extras, accept_fuzzy, unique(request_failed), verbose,
    n_input = length(names_in), n_cache = n_from_cache
  )
}


# Attach the residue attributes and report. Kept separate so the zero-row path
# and the normal path cannot drift apart.
#' @noRd
.worms_finalise <- function(out, extras, accept_fuzzy, request_failed, verbose,
                            n_input, n_cache) {
  absent <- if (nrow(out)) out$taxon_name[!out$in_worms & !out$fuzzy_rejected] else character(0)
  fuzzy <- if (nrow(out)) out$taxon_name[out$fuzzy_rejected] else character(0)
  unassessed <- if (nrow(out)) out$taxon_name[out$habitat_unassessed] else character(0)
  conflict <- if (nrow(out)) out$taxon_name[out$habitat_conflict] else character(0)

  absent <- setdiff(absent, request_failed)

  attr(out, "n_not_in_worms") <- length(absent)
  attr(out, "not_in_worms") <- absent
  attr(out, "n_fuzzy_rejected") <- length(fuzzy)
  attr(out, "fuzzy_rejected_taxa") <- fuzzy
  attr(out, "n_habitat_unassessed") <- length(unassessed)
  attr(out, "habitat_unassessed_taxa") <- unassessed
  attr(out, "n_habitat_conflict") <- length(conflict)
  attr(out, "habitat_conflict_taxa") <- conflict
  attr(out, "n_request_failed") <- length(request_failed)
  attr(out, "request_failed_taxa") <- request_failed
  attr(out, "worms_query") <- list(
    extras = extras, accept_fuzzy = accept_fuzzy,
    n_input = n_input, n_from_cache = n_cache
  )

  if (verbose && nrow(out)) {
    message(sprintf(
      "  fetch_worms_attributes(): %d in WoRMS, %d marine or brackish (marine_scope).",
      sum(out$in_worms), sum(out$marine_scope)
    ))
    if (length(absent)) {
      message(sprintf(
        "  %d name(s) NOT in WoRMS -- see attr(, \"not_in_worms\"). A marine taxon here is a silent loss.",
        length(absent)
      ))
    }
    if (length(fuzzy)) {
      message(sprintf(
        "  %d name(s) had only non-exact matches and were NOT used (accept_fuzzy = FALSE) -- attr(, \"fuzzy_rejected_taxa\").",
        length(fuzzy)
      ))
    }
    if (length(unassessed)) {
      message(sprintf(
        "  %d name(s) in WoRMS with NO habitat flags set -- attr(, \"habitat_unassessed_taxa\").",
        length(unassessed)
      ))
    }
    if (length(conflict)) {
      message(sprintf(
        "  %d name(s) matched homonyms that DISAGREE on marine status; marine_scope is the OR -- attr(, \"habitat_conflict_taxa\").",
        length(conflict)
      ))
    }
  }
  if (length(request_failed)) {
    warning(
      "fetch_worms_attributes: ", length(request_failed),
      " name(s) had a failed WoRMS request and are NOT absences -- they were not ",
      "cached and will be re-asked. See attr(, \"request_failed_taxa\").",
      call. = FALSE
    )
  }

  out
}
