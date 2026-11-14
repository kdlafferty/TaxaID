# ------------------------------------------------------------------------------
# Internal helpers (above the roxygen block: a helper between a block and its
# function would take the block)
# ------------------------------------------------------------------------------

.LGT_RANKS <- c("kingdom", "phylum", "class", "order", "family", "genus", "species")
.LGT_KINGDOMS <- c("Animalia", "Plantae", "Fungi", "Chromista", "Protozoa", "Bacteria", "Archaea", "Viruses")

.LGT_SYNONYM_STATUS <- c("SYNONYM", "HETEROTYPIC_SYNONYM", "HOMOTYPIC_SYNONYM", "PROPARTE_SYNONYM", "MISAPPLIED")

#' Is a GBIF backbone record a synonym? Any one of three fields says so.
#'
#' GBIF states synonymy in three places: the \code{synonym} flag, a
#' synonym-type \code{status}, and an \code{acceptedUsageKey} different from
#' the record's own \code{usageKey}. A record need not carry all three (the
#' live backbone match returns no flag at all), so reading one alone files a
#' synonym as accepted. PROVISIONALLY_ACCEPTED and DOUBTFUL are not synonyms:
#' such a record is its own taxon.
#' @noRd
.lgt_is_synonym <- function(flag, status, accepted_key, usage_key) {
  (flag %in% TRUE) |
    (!is.na(status) & toupper(status) %in% .LGT_SYNONYM_STATUS) |
    (!is.na(accepted_key) & !is.na(usage_key) & accepted_key != usage_key)
}

#' The rank each name is looked up at: the given rank where it is one of the
#' seven, else species for a name of two or more words, else genus.
#' @noRd
.lgt_target_rank <- function(names, rank) {
  inferred <- ifelse(grepl("\\s", trimws(names)), "species", "genus")
  if (is.null(rank)) return(inferred)
  r <- tolower(trimws(as.character(rank)))
  ifelse(!is.na(r) & r %in% .LGT_RANKS, r, inferred)
}

#' A kingdom from a context string, when its first element names one
#' @noRd
.lgt_context_kingdom <- function(context, n) {
  if (is.null(context)) return(rep(NA_character_, n))
  first <- trimws(sub("\\|.*$", "", as.character(context)))
  ifelse(!is.na(first) & first %in% .LGT_KINGDOMS, first, NA_character_)
}


#' Look Up Taxon Names in GBIF's Backbone, With Identifiers
#'
#' Matches each name against GBIF's backbone taxonomy (the release GBIF
#' occurrence records are keyed on) and returns the record's identifiers: its
#' own key, its accepted key, and the key of every rank in its classification.
#' The output has the columns of
#' \code{TaxaTools::verify_taxon_names(return_ids = TRUE)}, so it can be passed
#' as the \code{lookup} of \code{TaxaTools::build_taxon_registry()}.
#'
#' @param names Character vector of taxon names.
#' @param rank \code{NULL} (default) or a character vector, one per name: the
#'   rank each name is meant at. A rank outside kingdom ... species, or
#'   \code{NA}, is inferred: species for a name of two or more words, genus
#'   for one word. Give the rank for a one-word name above genus (a family),
#'   or it is asked as a genus.
#' @param context \code{NULL} (default) or a character vector, one per name: a
#'   pipe-delimited higher-taxon string. Only a leading kingdom name is used
#'   (passed to GBIF as context); the other elements carry no rank label.
#' @param cache_dir \code{NULL} (default, no cache) or a directory: the
#'   per-row cache of \code{\link{get_keys_from_context}}. Failed requests are
#'   never cached.
#'
#' @return A data frame, one row per name, in input order:
#'   \describe{
#'     \item{user_supplied_name}{The name as given.}
#'     \item{matched_name}{The ACCEPTED name GBIF gives for the match at its
#'       matched rank (a synonym's accepted name, read from the record's own
#'       classification), or \code{NA} when not matched.}
#'     \item{matched_rank}{Lower-case rank of the matched record.}
#'     \item{is_synonym}{\code{TRUE} when the record is a synonym by any of its
#'       synonym flag, a synonym-type status (SYNONYM, HETEROTYPIC_SYNONYM,
#'       HOMOTYPIC_SYNONYM, PROPARTE_SYNONYM, MISAPPLIED), or an accepted key
#'       that differs from its own key. PROVISIONALLY_ACCEPTED and DOUBTFUL
#'       records are not synonyms.}
#'     \item{classification_path, classification_ranks, classification_ids}{
#'       Pipe-delimited names, ranks and GBIF keys, kingdom to the matched
#'       rank, positionally aligned.}
#'     \item{score}{\code{NA} (GBIF's confidence is not carried).}
#'     \item{verified}{\code{FALSE} only where the request failed.}
#'     \item{matched}{\code{TRUE} for EXACT, FUZZY and HIGHERRANK answers
#'       with a key. A HIGHERRANK answer is matched at its coarser rank: read
#'       \code{matched_rank}. LOOKUP_RECOVERED is not matched (it has no
#'       lineage).}
#'     \item{record_id}{The matched record's own GBIF key.}
#'     \item{current_record_id}{Its accepted key (its own key when accepted).}
#'     \item{data_source_id}{11 (GBIF).}
#'     \item{entry_date}{\code{NA}.}
#'     \item{match_type}{\code{"Fuzzy"} for FUZZY, \code{"Exact"} for other
#'       matched rows, else \code{NA}.}
#'     \item{gbif_matchType, gbif_status}{GBIF's own match type and status.}
#'   }
#'   Attributes \code{n_requested} (names asked), \code{n_cached} (served
#'   from \code{cache_dir} without a request), \code{n_error} (requests that
#'   failed: not answered, not the same as unmatched), \code{n_fuzzy},
#'   \code{n_higherrank} and \code{n_recovered}.
#'
#' @seealso \code{\link{get_keys_from_context}}, which this calls with
#'   \code{return_keys = TRUE}.
#' @examples
#' \dontrun{
#' x <- lookup_gbif_taxa(c("Embiotoca caryi", "Hypsurus caryi"))
#' x[, c("user_supplied_name", "matched_name", "is_synonym", "current_record_id")]
#' attr(x, "n_error")
#' }
#' @export
lookup_gbif_taxa <- function(names, rank = NULL, context = NULL, cache_dir = NULL) {
  if (!is.character(names)) stop("lookup_gbif_taxa: 'names' must be a character vector.")
  n <- length(names)
  if (!is.null(rank) && length(rank) != n) stop("lookup_gbif_taxa: 'rank' must be NULL or one value per name.")
  if (!is.null(context) && length(context) != n) stop("lookup_gbif_taxa: 'context' must be NULL or one value per name.")
  cols <- c("user_supplied_name", "matched_name", "matched_rank", "is_synonym", "classification_path",
            "classification_ranks", "score", "verified", "matched", "record_id", "current_record_id",
            "classification_ids", "data_source_id", "entry_date", "match_type", "gbif_matchType", "gbif_status")
  if (n == 0L) {
    out <- as.data.frame(stats::setNames(replicate(length(cols), character(0), simplify = FALSE), cols), stringsAsFactors = FALSE)
    for (a in c("n_requested", "n_cached", "n_error", "n_fuzzy", "n_higherrank", "n_recovered")) attr(out, a) <- 0L
    return(out)
  }

  tr <- .lgt_target_rank(names, rank)
  df <- as.data.frame(stats::setNames(replicate(length(.LGT_RANKS), rep(NA_character_, n), simplify = FALSE), .LGT_RANKS),
                      stringsAsFactors = FALSE)
  for (i in seq_len(n)) df[[tr[i]]][i] <- trimws(names[i])
  kg <- .lgt_context_kingdom(context, n)
  fill_k <- !is.na(kg) & tr != "kingdom"
  df$kingdom[fill_k] <- kg[fill_k]

  .gkfc_state$cache_hits <- 0L
  g <- suppressWarnings(get_keys_from_context(df, return_keys = TRUE, cache_dir = cache_dir))
  n_cached <- .gkfc_state$cache_hits

  mt <- g$matchType
  matched <- mt %in% c("EXACT", "FUZZY", "HIGHERRANK") & !is.na(g$usageKey)
  syn <- .lgt_is_synonym(g$gbif_synonym, g$gbif_status, g$gbif_acceptedUsageKey, g$usageKey)
  cur <- ifelse(!is.na(g$gbif_acceptedUsageKey), g$gbif_acceptedUsageKey, g$usageKey)
  mr <- tolower(g$gbif_rank)

  path <- ranks <- ids <- acc <- rep(NA_character_, n)
  for (i in which(matched)) {
    k <- vapply(.LGT_RANKS, function(r) as.character(g[[paste0("gbif_", r, "Key")]][i]), "")
    nm <- vapply(.LGT_RANKS, function(r) as.character(g[[paste0("gbif_", r)]][i]), "")
    keep <- !is.na(k) & !is.na(nm)
    path[i] <- paste(nm[keep], collapse = "|"); ranks[i] <- paste(.LGT_RANKS[keep], collapse = "|")
    ids[i] <- paste(k[keep], collapse = "|")
    # a synonym's classification is its accepted taxon's: the accepted name at the matched rank is there
    own_rank_name <- if (!is.na(mr[i]) && mr[i] %in% .LGT_RANKS) nm[[mr[i]]] else NA_character_
    acc[i] <- if (isTRUE(syn[i]) && !is.na(own_rank_name)) own_rank_name else g$gbif_canonicalName[i]
  }

  out <- data.frame(
    user_supplied_name = names,
    matched_name = ifelse(matched, acc, NA_character_),
    matched_rank = ifelse(matched, mr, NA_character_),
    is_synonym = ifelse(matched, syn, NA),
    classification_path = path, classification_ranks = ranks,
    score = NA_real_,
    verified = mt != "ERROR",
    matched = matched,
    record_id = ifelse(matched, as.character(g$usageKey), NA_character_),
    current_record_id = ifelse(matched, as.character(cur), NA_character_),
    classification_ids = ids,
    data_source_id = 11L,
    entry_date = NA_character_,
    match_type = ifelse(matched, ifelse(mt == "FUZZY", "Fuzzy", "Exact"), NA_character_),
    gbif_matchType = mt,
    gbif_status = g$gbif_status,
    stringsAsFactors = FALSE
  )
  attr(out, "n_requested") <- n
  attr(out, "n_cached") <- n_cached
  attr(out, "n_error") <- sum(mt %in% "ERROR")
  attr(out, "n_fuzzy") <- sum(mt %in% "FUZZY")
  attr(out, "n_higherrank") <- sum(mt %in% "HIGHERRANK")
  attr(out, "n_recovered") <- sum(mt %in% "LOOKUP_RECOVERED")
  out
}
