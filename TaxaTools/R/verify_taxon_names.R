#' Verify Taxon Names Against a Taxonomic Backbone
#'
#' Checks a vector of taxon names against a target taxonomic backbone using
#' the Global Names Verifier API (v1). Returns the best match for each name
#' along with classification path, ranks, a match score, and a flag indicating
#' whether verification succeeded.
#'
#' Because this function queries the internet, it can be slow for large name
#' lists. It is recommended to run it once on a deduplicated list, save the
#' result, and load that saved file in downstream scripts rather than calling
#' this function repeatedly.
#'
#' @param name_list A character vector of taxon names to verify. Duplicates
#'   are removed automatically.
#' @param backbone_id Integer. The numeric ID of the target taxonomic backbone.
#'   Common options: 1 = Catalogue of Life, 3 = ITIS, 4 = NCBI, 9 = WoRMS,
#'   11 = GBIF. See \url{https://verifier.globalnames.org/} for the full list.
#' @param batch_size Integer. Maximum number of names per API request. The
#'   Global Names Verifier API supports up to 1000 names per batch. Default
#'   is 500 to stay safely within limits.
#' @param timeout_sec Integer. Seconds to wait before the API request times
#'   out. Default is 30.
#' @param fallback_backbone_id Integer. Only used when \code{backbone_id = 4}
#'   (NCBI). NCBI's direct lookup is an exact string search with no typo
#'   tolerance -- a single misspelled letter
#'   returns zero hits even via its own synonym fallback. When that happens,
#'   this backbone's Global Names Verifier API is queried instead purely to
#'   suggest a corrected spelling, which is then re-resolved through NCBI
#'   itself (the correction is never accepted from this backbone directly, so
#'   NCBI's own classification -- the reason the direct bypass exists at all --
#'   is preserved). Default \code{11} (GBIF). Must not be \code{4}.
#' @param decisions Only used when \code{backbone_id = 4} (NCBI); a supplied
#'   value is ignored, with a warning, for any other backbone. A name is not
#'   a key -- NCBI can hold several nodes sharing one name in unrelated
#'   lineages (a genus of red algae named "Vertebrata" beside the vertebrate
#'   clade of the same name; see \code{\link{resolve_ncbi_taxid}}), and this
#'   direct bypass's own batched search used to pick whichever candidate its
#'   summary happened to process last, silently. Such a name is now reported
#'   as an unresolved AMBIGUITY, never guessed -- \code{decisions} is how a
#'   caller states which candidate is meant. \code{NULL} (default): no prior
#'   decisions. A data frame with \code{name}/\code{taxid} columns: use these
#'   decisions directly (a row with \code{taxid = NA} is an explicit
#'   \emph{skip} -- that name resolves to \code{NA}, not "not yet decided").
#'   A character scalar: the path to an \code{.rds} file holding such a data
#'   frame (read if it exists; new decisions made this call -- interactively,
#'   see below -- are merged into it, a newer decision for a name replacing
#'   an older one). A name that comes back ambiguous and has no covering
#'   decision (in \code{decisions} or, for a path, already saved in that
#'   file) is handled by session type, never by a silent default: in an
#'   interactive session, one prompt covers every such name in this call
#'   (never a dialogue per name), tabulating each candidate's rank, division,
#'   and a short lineage string; in a non-interactive session (the ordinary
#'   \code{Rscript} workflow case), the call stops, printing that same table
#'   plus a ready-to-paste \code{decisions = data.frame(...)} skeleton. No
#'   file is ever written unless \code{decisions} itself named one. That stop
#'   applies only when \code{decisions} was supplied and does not cover the
#'   name: a non-interactive call with \code{decisions = NULL} (the shape of a
#'   batch issued from inside another function, which has no way to pass a
#'   decision) instead reports the still-ambiguous name alone as
#'   \code{verified = FALSE} -- never cached, asked again next call, with the
#'   candidate table in a warning -- and the rest of the batch proceeds.
#'
#' @param ranks Character vector or \code{NULL} (default). One rank per
#'   element of \code{name_list} (\code{"genus"}, \code{"species"}, ...; \code{NA}
#'   where unknown): the rank the CALLER means each name at. Only used by the
#'   NCBI path (\code{backbone_id = 4}) and only for a name that resolves to
#'   more than one NCBI node: when exactly one candidate carries the given
#'   rank, that node is taken, with no further request and before
#'   \code{decisions} is consulted. "Etheostoma" is both a genus and a
#'   subgenus; a consensus table knows which it means. Silently unused by the
#'   Global Names path. On the NCBI path a rank that is given enters the
#'   cache key (see \code{cache_dir}); elsewhere the key is unchanged.
#' @param lineage Character vector or \code{NULL} (default). One lineage
#'   context per element of \code{name_list} (\code{NA} = none): a
#'   pipe-delimited string of ancestor names the caller already knows for that
#'   name, e.g. \code{"Chordata"} or \code{"Metazoa|Chordata|Actinopteri"}.
#'   Used twice. On the NCBI path (\code{backbone_id = 4}) a homonym is
#'   resolved, after \code{ranks} and before \code{decisions}, to the one
#'   candidate whose own lineage contains any of the context's names (the
#'   candidates' lineages are already fetched for the ambiguity report, so
#'   this adds no request); zero or several containing candidates leave it
#'   ambiguous. On EVERY backbone a returned classification that contradicts
#'   the context -- both carry comparable names (kingdoms are ignored, see
#'   [check_lineage_agreement()]) and share none -- is reported as
#'   unverified, never accepted: the Global Names path returns one best match
#'   per name with no way to prefer a lineage, and for a homonym that match can
#'   be the other taxon. A name is not a key; this is the caller's way of
#'   saying which one it means. Part of the cache key when given.
#' @param cache_dir Character or \code{NULL} (default). A directory for a
#'   per-name on-disk cache, so a re-run on the same names reproduces instead
#'   of depending on whether the service answered this time. Only names the
#'   service actually answered are cached -- matched or genuinely unmatched
#'   (\code{verified = TRUE}); a name whose lookup FAILED (\code{verified =
#'   FALSE}) is never written and is asked again next call, because a cached
#'   non-answer would be served as an answer indefinitely. Every entry
#'   written carries an \code{answered} marker; an entry from before the
#'   marker existed is served only if it holds a matched name (a failed
#'   lookup never produces one) and is otherwise asked once more and
#'   rewritten. The key is the
#'   name plus everything that can change what it resolves to:
#'   \code{backbone_id}, \code{fallback_backbone_id}, \code{decisions}
#'   (by content, including a decisions file's contents) and, on the NCBI
#'   path when one is given, the name's \code{rank}. \code{batch_size}
#'   and \code{timeout_sec} are not in the key; they cannot change a correct
#'   answer. Managed by \code{\link{taxatools_clear_cache}}. \code{NULL} keeps
#'   the uncached behaviour exactly.
#' @param cache_ttl_days Numeric (default \code{365}). A cached answer older
#'   than this is asked again, so backbone updates (renames, new synonymy)
#'   eventually reach a long-lived cache. \code{Inf} never expires.
#' @return A tibble with one row per input name and the following columns:
#' \describe{
#'   \item{user_supplied_name}{The original name as supplied.}
#'   \item{matched_name}{The best-matched name at whatever rank the backbone
#'     actually resolved it to (authorship strings stripped; a genus-only
#'     match returns a bare genus, a subspecies-level match returns the full
#'     trinomial), or \code{NA} if no match was found. When the backbone
#'     itself flags the match as a taxonomic synonym (\code{is_synonym =
#'     TRUE}), this is the backbone's OWN currently-accepted name, not the
#'     (possibly outdated) synonym form that was actually queried -- see
#'     \code{is_synonym} below. Sourced from the Global Names Verifier API's
#'     own canonical-name fields, not a local regex, so it is not vulnerable
#'     to truncating a trinomial to a binomial the way a naive
#'     genus-plus-one-epithet parse would.}
#'   \item{matched_rank}{Character. The taxonomic rank \code{matched_name}
#'     itself was actually resolved at (e.g. \code{"species"},
#'     \code{"genus"}, \code{"subspecies"}) -- the last rank present in
#'     \code{classification_ranks}. Use this, not an assumption carried over
#'     from whatever rank the input name was expected to be, to decide how to
#'     use \code{matched_name} downstream: a query submitted as a species
#'     binomial can genuinely resolve only to genus (e.g. an informally-named
#'     taxon with no species-level backbone entry), and treating the returned
#'     name as still species-level in that case silently corrupts a
#'     genus-only name into a fabricated pseudo-binomial. \code{NA} when no
#'     match was found.}
#'   \item{is_synonym}{Logical. \code{TRUE} when the backbone's own best match
#'     for this name is a taxonomic synonym of a currently-accepted name (in
#'     which case \code{matched_name} already reports the accepted form, not
#'     the synonym). \code{NA} when unknown (no match, an API failure, or --
#'     for \code{backbone_id = 4} specifically -- always, since NCBI's direct
#'     lookup path does not expose synonym relationships the way the Global
#'     Names Verifier path does). Synonymy is a property of the SPECIFIC
#'     backbone queried, not a universal fact -- the same name can be a
#'     synonym under one backbone's own taxonomic opinion and not another's
#'     (confirmed directly: GBIF/Catalogue of Life/WoRMS all flag \code{"Inu"}
#'     Snyder 1909 as a synonym of \code{"Luciogobius"} Gill 1859, while NCBI's
#'     own taxonomy does not consider it one at all). This column always
#'     reflects whichever single \code{backbone_id} was actually queried.}
#'   \item{classification_path}{Pipe-delimited classification path from the
#'     backbone (e.g., \code{"Animalia|Chordata|..."}). Already reflects the
#'     currently-accepted lineage even when the query matched a synonym.}
#'   \item{classification_ranks}{Pipe-delimited rank labels corresponding to
#'     \code{classification_path}.}
#'   \item{score}{Backbone match confidence score between 0 and 1. Higher is
#'     better. This measures name-matching quality against the backbone and is
#'     unrelated to the sequence match scores used elsewhere in the TaxaID
#'     ecosystem (e.g., percent identity from BLAST).}
#'   \item{verified}{Logical. \code{TRUE} if the lookup ran and the API
#'     answered, \code{FALSE} if the API failed and fallback values were used
#'     -- or, when \code{lineage} was given, if the API answered and the
#'     answer contradicted the caller's lineage (see \code{lineage}). The
#'     second case is deterministic: the same name with the same context is
#'     rejected every time, so retrying it is pointless; the message that
#'     names each rejected name tells the two cases apart.
#'     It does not say whether the name was found: a name the backbone does
#'     not hold returns \code{verified = TRUE} with \code{matched_name = NA}.
#'     Always check rows where \code{verified = FALSE}.}
#'   \item{matched}{Logical. \code{TRUE} only when the lookup ran and
#'     returned a name (\code{verified & !is.na(matched_name)}). Filter on
#'     this, not on \code{verified}, to keep resolved names.}
#'   \item{fuzzy_corrected}{Logical. Only present when \code{backbone_id = 4}.
#'     \code{TRUE} if this name was not found by NCBI's own exact search and
#'     was instead matched after a fuzzy-spelling correction suggested by
#'     \code{fallback_backbone_id} (see that parameter). Always review these
#'     rows before trusting them -- a fuzzy match confirms a plausible
#'     correction, not a certain one.}
#' }
#'
#' @section Synonym resolution and rank correctness (backbone-general, not GBIF-specific):
#' Verified directly against the live API across five backbones (Catalogue of
#' Life, ITIS, NCBI, WoRMS, GBIF) with the same query:
#' \code{matched_rank} (derived from \code{classificationRanks}) and
#' \code{isSynonym}/\code{currentName} (used to prefer the accepted name over
#' a synonym) are fields the Global Names Verifier API itself normalises
#' identically across every backbone it aggregates -- nothing here is
#' GBIF-specific code. What genuinely varies by backbone is the underlying
#' taxonomic *opinion* (whether a given name counts as a synonym at all), not
#' the mechanism for reading it. Because \code{dataSources} scopes every call
#' to exactly one backbone, this always reports that one backbone's own
#' answer -- it never blends or overrides one backbone's judgment with
#' another's. \code{backbone_id = 4} (NCBI) does not go through this API path
#' at all (see \code{.verify_via_ncbi()}) and so never gets synonym
#' resolution, but its own \code{matched_rank} is populated identically from
#' its own classification lineage.
#'
#' @note If the API is unreachable, the function issues a warning and returns
#'   the original names with \code{verified = FALSE} and \code{score = NA}
#'   rather than stopping, so that partial results from earlier batches are
#'   not lost. Review all \code{verified = FALSE} rows before using results
#'   downstream.
#'
#' @note Name changes suggested by the backbone should always be manually
#'   confirmed before accepting them -- automated synonym resolution can be
#'   incorrect. This applies doubly to \code{fuzzy_corrected = TRUE} rows: a
#'   fuzzy match can also (rarely) land on a different, genuinely distinct
#'   taxon rather than fixing a typo.
#'
#' @seealso \code{\link{change_backbone}} to parse and label the output of
#'   this function into wide-format taxonomy columns.
#'   \url{https://verifier.globalnames.org/api/v1}
#'
#' @importFrom httr POST content status_code timeout
#' @importFrom jsonlite toJSON
#' @importFrom dplyr tibble bind_rows
#'
#' @export
#'
#' @examples
#' \dontrun{
#' names <- c("Homo sapiens", "Mus musculus", "Tyranosaurus rex")
#' result <- verify_taxon_names(names, backbone_id = 4) # NCBI
#' result
#'
#' # Check which names failed verification or had no match
#' result[!result$verified | is.na(result$matched_name), ]
#' }
verify_taxon_names <- function(name_list,
                               backbone_id,
                               batch_size = 500,
                               timeout_sec = 30,
                               fallback_backbone_id = 11L,
                               decisions = NULL,
                               cache_dir = NULL,
                               cache_ttl_days = 365,
                               ranks = NULL,
                               lineage = NULL) {
  ranks <- .check_verify_ranks(ranks, name_list)
  lineage <- .check_verify_lineage(lineage, name_list)
  if (!is.null(cache_dir)) {
    return(.verify_taxon_names_cached(
      name_list, backbone_id, batch_size, timeout_sec, fallback_backbone_id,
      decisions, cache_dir, cache_ttl_days, ranks = ranks, lineage = lineage
    ))
  }
  # --- Input validation ---
  if (!is.character(name_list) || length(name_list) == 0) {
    stop("`name_list` must be a non-empty character vector.")
  }
  if ((!is.numeric(backbone_id) && !is.integer(backbone_id)) ||
    length(backbone_id) != 1 || is.na(backbone_id)) {
    stop("`backbone_id` must be a single integer (e.g., 4 for NCBI).")
  }
  backbone_id <- as.integer(backbone_id)
  if (!is.null(decisions) && !identical(backbone_id, 4L)) {
    warning(
      "verify_taxon_names: `decisions` is only used for backbone_id = 4 ",
      "(NCBI) and is unused for backbone_id = ", backbone_id, ".",
      call. = FALSE
    )
  }

  # --- Clean and deduplicate ---
  trimmed_names <- trimws(name_list)
  # Remove NA and empty strings before deduplication
  clean_names <- unique(trimmed_names)
  clean_names <- clean_names[!is.na(clean_names) & nzchar(clean_names)]
  n_total <- length(clean_names)

  if (n_total == 0L) {
    stop("verify_taxon_names: no valid (non-NA, non-empty) names in `name_list`.")
  }

  # --- NCBI direct bypass (backbone_id = 4) ---
  # GlobalNames has an incomplete NCBI snapshot that demotes valid species

  # to genus (~30% loss). Query NCBI taxonomy directly instead.
  if (identical(as.integer(backbone_id), 4L)) {
    unique_df <- .verify_via_ncbi(
      clean_names, fallback_backbone_id = fallback_backbone_id,
      decisions = decisions,
      ranks = .ranks_for_names(ranks, trimmed_names, clean_names),
      lineage = .ranks_for_names(lineage, trimmed_names, clean_names)
    )
    idx <- match(trimmed_names, unique_df$user_supplied_name)
    final_df <- unique_df[idx, , drop = FALSE]
    # NA/empty input names get a placeholder row with verified = FALSE
    na_rows <- which(is.na(idx))
    if (length(na_rows) > 0L) {
      final_df$user_supplied_name[na_rows] <- trimmed_names[na_rows]
      final_df$verified[na_rows] <- FALSE
      final_df$fuzzy_corrected[na_rows] <- FALSE
    }
    rownames(final_df) <- NULL
  # `verified` says the lookup ran; `matched` says it found the name. A
  # filter on `verified` alone keeps every unmatched row, which reads as
  # success downstream.
  final_df$matched <- final_df$verified & !is.na(final_df$matched_name)
    return(.apply_lineage_gate(final_df, lineage))
  }

  message("Verifying ", n_total, " unique name(s) against backbone ", backbone_id, "...")

  api_url <- "https://verifier.globalnames.org/api/v1/verifications"

  # --- Split into batches ---
  batches <- split(clean_names, ceiling(seq_along(clean_names) / batch_size))
  n_batches <- length(batches)
  if (n_batches > 1) {
    message("Processing in ", n_batches, " batches of up to ", batch_size, "...")
  }

  all_results <- vector("list", n_batches)

  for (i in seq_along(batches)) {
    batch <- batches[[i]]
    if (n_batches > 1) {
      message("  Batch ", i, " of ", n_batches, " (", length(batch), " names)...")
    }

    body <- list(
      nameStrings    = as.list(batch), # as.list() ensures JSON array even for single names
      dataSources    = list(as.integer(backbone_id)),
      withAllMatches = FALSE
    )

    batch_result <- tryCatch(
      {
        resp <- httr::POST(
          url    = api_url,
          body   = body,
          encode = "json",
          httr::timeout(timeout_sec)
        )

        if (httr::status_code(resp) != 200) {
          stop("API returned status ", httr::status_code(resp))
        }

        data <- httr::content(resp, as = "parsed", type = "application/json")

        if (is.null(data$names) || length(data$names) == 0L) {
          warning(sprintf(
            paste0(
              "verify_taxon_names: batch %d returned no 'names' field. API response ",
              "may be malformed. Treating %d names as unverified."
            ),
            i, length(batch)
          ))
          # This tibble is the tryCatch expression's value, so it becomes this
          # batch's result directly -- assigning to the accumulator here (or
          # calling next) would either skip the assignment at the bottom of the
          # loop or return early out of the whole function.
          dplyr::tibble(
            user_supplied_name   = batch,
            matched_name         = NA_character_,
            matched_rank         = NA_character_,
            is_synonym           = NA,
            classification_path  = NA_character_,
            classification_ranks = NA_character_,
            score                = NA_real_,
            verified             = FALSE
          )
        } else {
          # httr::content(as = "parsed") can return single-element lists instead of
          # plain scalars for some fields. These helpers safely extract a scalar value.
          safe_chr <- function(x) {
            if (is.null(x)) {
              return(NA_character_)
            }
            if (is.list(x)) x <- x[[1]]
            as.character(x)
          }
          safe_dbl <- function(x) {
            if (is.null(x)) {
              return(NA_real_)
            }
            if (is.list(x)) x <- x[[1]]
            as.double(x)
          }

          # --- Parse each name's result ---
          parsed <- lapply(data$names, function(item) {
            best <- item$bestResult

            if (is.null(best)) {
              # API responded but found no match for this name
              return(dplyr::tibble(
                user_supplied_name   = safe_chr(item$name),
                matched_name         = NA_character_,
                matched_rank         = NA_character_,
                is_synonym           = NA,
                classification_path  = NA_character_,
                classification_ranks = NA_character_,
                score                = NA_real_,
                verified             = TRUE # API worked; it just found nothing
              ))
            }

            # Prefer GNVerifier's own authority-free canonical fields over a local
            # regex -- matchedCanonicalSimple/currentCanonicalSimple are already
            # stripped of authorship AND correctly preserve a full trinomial
            # (e.g. a subspecies), unlike the previous strip_authority() regex
            # (genus + at most one lowercase word), which silently truncated any
            # subspecies-rank match to a binomial.
            is_syn <- isTRUE(best$isSynonym)
            current_simple <- safe_chr(best$currentCanonicalSimple)
            matched_simple <- safe_chr(best$matchedCanonicalSimple)
            use_current <- is_syn && !is.na(current_simple) && nzchar(current_simple)
            resolved_name <- if (use_current) current_simple else matched_simple

            dplyr::tibble(
              user_supplied_name   = safe_chr(item$name),
              matched_name         = resolved_name,
              matched_rank         = .last_classification_rank(safe_chr(best$classificationRanks)),
              is_synonym           = is_syn,
              classification_path  = safe_chr(best$classificationPath),
              classification_ranks = safe_chr(best$classificationRanks),
              score                = safe_dbl(best$score),
              verified             = TRUE
            )
          })

          dplyr::bind_rows(parsed)
        }
      },
      error = function(e) {
        warning(
          "API request failed for batch ", i, ". ",
          "Returning unverified passthrough for these names.\n",
          "Error: ", e$message,
          call. = FALSE
        )

        # Fallback: return names as-is, clearly flagged as unverified
        dplyr::tibble(
          user_supplied_name   = batch,
          matched_name         = NA_character_,
          matched_rank         = NA_character_,
          is_synonym           = NA,
          classification_path  = NA_character_,
          classification_ranks = NA_character_,
          score                = NA_real_,
          verified             = FALSE
        )
      }
    )

    all_results[[i]] <- batch_result
  }

  unique_df <- dplyr::bind_rows(all_results)

  # Map results back to original input positions (preserving duplicates)
  idx <- match(trimmed_names, unique_df$user_supplied_name)
  final_df <- unique_df[idx, , drop = FALSE]
  # NA/empty input names get a placeholder row with verified = FALSE
  na_rows <- which(is.na(idx))
  if (length(na_rows) > 0L) {
    final_df$user_supplied_name[na_rows] <- trimmed_names[na_rows]
    final_df$verified[na_rows] <- FALSE
  }
  rownames(final_df) <- NULL
  # `verified` says the lookup ran; `matched` says it found the name. A
  # filter on `verified` alone keeps every unmatched row, which reads as
  # success downstream.
  final_df$matched <- final_df$verified & !is.na(final_df$matched_name)

  n_verified <- sum(unique_df$verified, na.rm = TRUE)
  n_unverified <- sum(!unique_df$verified, na.rm = TRUE)
  n_no_match <- sum(unique_df$verified & is.na(unique_df$matched_name), na.rm = TRUE)

  msg <- sprintf("Done. %d name(s) reached the API.", n_verified)
  if (n_no_match > 0L) msg <- paste0(msg, sprintf(" %d had no match.", n_no_match))
  if (n_unverified > 0L) msg <- paste0(msg, sprintf(" %d were unverified due to API failure.", n_unverified))
  message(msg)

  # The gate prints its own line naming every rejected name, so the count
  # above is the API-failure count only; the gate's rejections are reported
  # separately, not folded into "API failure".
  .apply_lineage_gate(final_df, lineage)
}


# ---- per-name on-disk cache --------------------------------------------------
# One .rds per (name, backbone_id, fallback_backbone_id, decisions), the same
# file-per-key shape as scientific_to_common(cache_dir =), so
# taxatools_clear_cache() manages it. The full key is stored in the file and
# verified on read: a hash collision costs one re-asked name, never another
# name's answer. Bump .VERIFY_CACHE_VERSION if the returned columns change.
.VERIFY_CACHE_VERSION <- "v1"

#' @noRd
.verify_decisions_fingerprint <- function(decisions) {
  if (is.null(decisions)) return(NA_character_)
  if (is.character(decisions) && length(decisions) == 1L) {
    return(if (file.exists(decisions)) unname(tools::md5sum(decisions)) else "absent-file")
  }
  rlang::hash(decisions)
}

#' @noRd
.verify_cache_key <- function(name, backbone_id, fallback_backbone_id, decisions_fp,
                              rank = NA_character_, lineage = NA_character_) {
  key <- list(
    name = name, backbone_id = as.integer(backbone_id),
    fallback_backbone_id = if (is.null(fallback_backbone_id)) NA_integer_ else as.integer(fallback_backbone_id),
    decisions = decisions_fp, version = .VERIFY_CACHE_VERSION
  )
  # A rank is part of the question only where it can change the answer: the
  # NCBI path's homonym resolution (Etheostoma the genus and Etheostoma the
  # subgenus are different answers). The Global Names path never reads it,
  # so its entries keep the key they always had; so does any call that gives
  # no rank. Existing entries therefore still hit except NCBI ones now asked
  # with a rank, which re-ask once.
  if (!is.na(rank) && identical(as.integer(backbone_id), 4L)) key$rank <- rank
  # A lineage context can change the answer on EVERY backbone (it resolves an
  # NCBI homonym and gates a contradicting Global Names match), so it is
  # always part of the question when given.
  if (!is.na(lineage)) key$lineage <- lineage
  key
}

#' Validate `lineage`: NULL, or one context per name_list element (NA allowed)
#' @noRd
.check_verify_lineage <- function(lineage, name_list) {
  if (is.null(lineage)) return(NULL)
  # A logical all-NA vector is "no context for any name", not a type error.
  if (is.logical(lineage) && all(is.na(lineage))) lineage <- as.character(lineage)
  if (!is.character(lineage) || length(lineage) != length(name_list)) {
    stop("`lineage` must be NULL or a character vector with one lineage context per element of `name_list`.")
  }
  l <- trimws(lineage)
  l[!is.na(l) & !nzchar(l)] <- NA_character_
  l
}

#' Does each candidate lineage contain ANY of the context's terms?
#'
#' `lineages` are pipe-delimited (or " > "-delimited) ancestor strings, one per
#' candidate; `context` is one pipe-delimited string of known ancestor names.
#' Term match is exact and case-insensitive on whole names.
#' @noRd
.lineage_contains <- function(lineages, context) {
  terms <- tolower(trimws(strsplit(as.character(context), "|", fixed = TRUE)[[1L]]))
  terms <- terms[nzchar(terms)]
  if (length(terms) == 0L) return(rep(FALSE, length(lineages)))
  vapply(lineages, function(l) {
    if (is.na(l)) return(FALSE)
    nodes <- tolower(trimws(unlist(strsplit(l, "\\||>"))))
    any(terms %in% nodes)
  }, logical(1L), USE.NAMES = FALSE)
}

#' Reject a resolved name whose classification contradicts the caller's lineage
#'
#' `df` is in input order; `lineage` is the per-element context (or NULL). A
#' row with a context and a classification path that DISAGREES with it (see
#' [check_lineage_agreement()]: both sides carry comparable names and share
#' none) is turned into an unverified row -- the caller asked about a taxon
#' in one lineage and the backbone answered with another, which is a homonym,
#' not a verification. "unknown" (nothing comparable) and "agrees" pass.
#' @noRd
.apply_lineage_gate <- function(df, lineage) {
  if (is.null(lineage) || nrow(df) == 0L) return(df)
  has <- !is.na(lineage) & !is.na(df$classification_path) & nzchar(df$classification_path)
  if (!any(has)) return(df)
  verdict <- rep("unknown", nrow(df))
  verdict[has] <- check_lineage_agreement(lineage[has], df$classification_path[has])
  bad <- which(verdict == "disagrees")
  if (length(bad) == 0L) return(df)
  shown <- unique(sprintf("\"%s\" (asked for %s; backbone returned %s)",
    df$user_supplied_name[bad], lineage[bad],
    vapply(df$classification_path[bad], function(p) .short_lineage_terms(p), character(1L))))
  message(sprintf(
    "verify_taxon_names: %d name(s) resolved to a lineage that contradicts the caller's and are reported as unverified (a name is not a key; deterministic, not an API failure, so retrying will not change it): %s.",
    length(unique(df$user_supplied_name[bad])), paste(utils::head(shown, 10L), collapse = "; ")
  ))
  df$verified[bad] <- FALSE
  df$matched_name[bad] <- NA_character_
  if ("matched_rank" %in% names(df)) df$matched_rank[bad] <- NA_character_
  if ("is_synonym" %in% names(df)) df$is_synonym[bad] <- NA
  df$classification_path[bad] <- NA_character_
  df$classification_ranks[bad] <- NA_character_
  if ("score" %in% names(df)) df$score[bad] <- NA_real_
  if ("matched" %in% names(df)) df$matched[bad] <- FALSE
  df
}

#' First three comparable names of a pipe-delimited path, for messages
#' @noRd
.short_lineage_terms <- function(path) {
  nodes <- trimws(strsplit(path, "|", fixed = TRUE)[[1L]])
  nodes <- nodes[nzchar(nodes) & !tolower(nodes) %in% c("cellular organisms", "eukaryota")]
  paste(utils::head(nodes, 3L), collapse = " > ")
}

#' Validate `ranks`: NULL, or one rank per name_list element (NA allowed)
#' @noRd
.check_verify_ranks <- function(ranks, name_list) {
  if (is.null(ranks)) return(NULL)
  if (!is.character(ranks) || length(ranks) != length(name_list)) {
    stop("`ranks` must be NULL or a character vector with one rank per element of `name_list`.")
  }
  r <- tolower(trimws(ranks))
  r[!is.na(r) & !nzchar(r)] <- NA_character_
  r
}

#' One rank per unique cleaned name (the first non-NA given for it), named
#' @noRd
.ranks_for_names <- function(ranks, trimmed_names, uniq) {
  if (is.null(ranks)) return(NULL)
  out <- vapply(uniq, function(nm) {
    r <- ranks[!is.na(trimmed_names) & trimmed_names == nm]
    r <- r[!is.na(r)]
    if (length(r)) r[[1L]] else NA_character_
  }, character(1L))
  names(out) <- uniq
  out
}

#' @noRd
.verify_cache_path <- function(cache_dir, key) {
  file.path(cache_dir, paste0(rlang::hash(key), "_verified_name.rds"))
}

# The service call, as a seam tests can mock.
#' @noRd
.verify_taxon_names_uncached <- function(...) verify_taxon_names(..., cache_dir = NULL)

#' @noRd
.verify_taxon_names_cached <- function(name_list, backbone_id, batch_size, timeout_sec,
                                       fallback_backbone_id, decisions, cache_dir,
                                       cache_ttl_days, ranks = NULL, lineage = NULL) {
  if (!is.character(cache_dir) || length(cache_dir) != 1L || is.na(cache_dir)) {
    stop("`cache_dir` must be NULL or a single directory path.")
  }
  if (!is.numeric(cache_ttl_days) || length(cache_ttl_days) != 1L ||
    is.na(cache_ttl_days) || cache_ttl_days <= 0) {
    stop("`cache_ttl_days` must be a single positive number (Inf never expires).")
  }
  if (!is.character(name_list) || length(name_list) == 0) {
    stop("`name_list` must be a non-empty character vector.")
  }
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  trimmed <- trimws(name_list)
  uniq <- unique(trimmed[!is.na(trimmed) & nzchar(trimmed)])
  if (length(uniq) == 0L) {
    stop("verify_taxon_names: no valid (non-NA, non-empty) names in `name_list`.")
  }
  fp <- .verify_decisions_fingerprint(decisions)
  rank_of <- .ranks_for_names(ranks, trimmed, uniq)
  lin_of <- .ranks_for_names(lineage, trimmed, uniq)
  keys <- lapply(uniq, function(nm) .verify_cache_key(
    nm, backbone_id, fallback_backbone_id, fp,
    rank = if (is.null(rank_of)) NA_character_ else rank_of[[nm]],
    lineage = if (is.null(lin_of)) NA_character_ else lin_of[[nm]]
  ))
  now <- Sys.time()
  cached <- lapply(keys, function(k) {
    path <- .verify_cache_path(cache_dir, k)
    if (!file.exists(path)) return(NULL)
    hit <- tryCatch(readRDS(path), error = function(e) NULL)
    if (is.null(hit) || !identical(hit$key, k) || !is.data.frame(hit$row)) return(NULL)
    # Entries written before the `answered` marker existed cannot prove the
    # service answered: the NCBI path once reported a failed lookup as
    # verified = TRUE / matched_name = NA, byte-identical to a genuine
    # non-match. An unmarked entry that carries a NAME is a real answer (a
    # failure never produces one) and is kept; an unmarked entry with no
    # name is treated as a miss, asked once more, and rewritten with the
    # marker. Same pattern as assign_sampling_group()'s matched_rank check.
    if (!isTRUE(hit$answered) && all(is.na(hit$row$matched_name))) return(NULL)
    age <- as.numeric(difftime(now, hit$written_at, units = "days"))
    if (!is.finite(cache_ttl_days) || age <= cache_ttl_days) hit$row else NULL
  })
  is_hit <- !vapply(cached, is.null, logical(1L))
  miss <- uniq[!is_hit]
  fresh <- NULL
  if (length(miss) > 0L) {
    fresh <- .verify_taxon_names_uncached(miss, backbone_id,
      batch_size = batch_size, timeout_sec = timeout_sec,
      fallback_backbone_id = fallback_backbone_id, decisions = decisions,
      ranks = if (is.null(rank_of)) NULL else unname(rank_of[miss]),
      lineage = if (is.null(lin_of)) NULL else unname(lin_of[miss])
    )
    fresh <- fresh[!duplicated(fresh$user_supplied_name), , drop = FALSE]
    # Write only names the service answered. A failed lookup (verified FALSE)
    # is a non-answer and must be asked again, not served as one.
    for (i in seq_len(nrow(fresh))) {
      if (!isTRUE(fresh$verified[i])) next
      k <- keys[[match(fresh$user_supplied_name[i], uniq)]]
      saveRDS(list(key = k, row = fresh[i, , drop = FALSE], written_at = now, answered = TRUE),
        .verify_cache_path(cache_dir, k))
    }
  }
  if (any(is_hit)) {
    message(sprintf("verify_taxon_names: %d of %d name(s) served from cache.",
      sum(is_hit), length(uniq)))
  }
  all_rows <- dplyr::bind_rows(c(cached[is_hit], list(fresh)))
  idx <- match(trimmed, all_rows$user_supplied_name)
  out <- all_rows[idx, , drop = FALSE]
  na_rows <- which(is.na(idx))
  if (length(na_rows) > 0L) {
    out$user_supplied_name[na_rows] <- trimmed[na_rows]
    out$verified[na_rows] <- FALSE
    if ("matched" %in% names(out)) out$matched[na_rows] <- FALSE
  }
  rownames(out) <- NULL
  out
}


#' Last (finest) rank present in a pipe-delimited classification_ranks string
#'
#' The last element of \code{classification_ranks} is, by construction (both
#' the Global Names Verifier API and NCBI's own lineage XML build the path as
#' "ancestor ranks, finest last"), the rank the match itself was actually
#' resolved at -- reading it directly is more reliable than a caller assuming
#' the match resolved at whatever rank the ORIGINAL query name implied (the
#' exact assumption that let a genus-only match silently masquerade as a
#' species-level one; see this file's Synonym resolution section above).
#' @noRd
.last_classification_rank <- function(ranks_str) {
  if (is.na(ranks_str) || !nzchar(ranks_str)) {
    return(NA_character_)
  }
  ranks <- strsplit(ranks_str, "|", fixed = TRUE)[[1]]
  ranks <- ranks[nzchar(ranks)]
  if (length(ranks) == 0L) {
    return(NA_character_)
  }
  ranks[[length(ranks)]]
}


# ==============================================================================
# Internal: Direct NCBI taxonomy lookup (backbone_id = 4 bypass)
# ==============================================================================

#' Verify taxon names directly against NCBI taxonomy via rentrez
#'
#' Replaces GlobalNames for backbone_id = 4. Batches \code{entrez_search()}
#' with OR'd \code{"Name"[Scientific Name]} terms, then fetches full lineage
#' XML for all matched taxids. Returns the same tibble format as the
#' GlobalNames path so that \code{change_backbone()} works unchanged.
#'
#' @param clean_names Character vector of unique, trimmed taxon names.
#' @param search_batch_size Integer. Names per \code{entrez_search()} call.
#'   NCBI URL length limits suggest ~40. Default 40.
#' @param fetch_batch_size Integer. Taxids per \code{entrez_fetch()} call.
#'   Default 100.
#' @param fallback_backbone_id Integer. Backbone queried via
#'   \code{\link{verify_taxon_names}}'s Global Names Verifier path for names
#'   NCBI's own exact search cannot find, purely to suggest a corrected
#'   spelling (see that function's own docs for the full rationale). Must not
#'   be \code{4}.
#' @param ranks Named character vector (names = \code{clean_names}) or NULL:
#'   the caller's rank for each name, used to resolve a homonym by rank before
#'   \code{decisions} is consulted. See \code{verify_taxon_names(ranks =)}.
#' @param decisions See \code{\link{verify_taxon_names}}'s own \code{@param
#'   decisions} -- NULL, a \code{data.frame(name, taxid)}, or a path to an
#'   \code{.rds} file holding one.
#' @param lineage Named character vector (names = \code{clean_names}) or NULL:
#'   the caller's known ancestor names for each name, pipe-delimited, used to
#'   resolve a homonym by lineage containment after \code{ranks} and before
#'   \code{decisions}. See \code{verify_taxon_names(lineage =)}.
#' @return A tibble with columns: user_supplied_name, matched_name,
#'   classification_path, classification_ranks, score, verified,
#'   fuzzy_corrected.
#' @noRd
.verify_via_ncbi <- function(clean_names,
                             search_batch_size = 40L,
                             fetch_batch_size = 100L,
                             fallback_backbone_id = 11L,
                             decisions = NULL,
                             ranks = NULL,
                             lineage = NULL) {
  if (!requireNamespace("rentrez", quietly = TRUE) ||
    !requireNamespace("xml2", quietly = TRUE)) {
    stop(
      "verify_taxon_names: packages 'rentrez' and 'xml2' are required for ",
      "direct NCBI lookup (backbone_id = 4).\n",
      "Install with: install.packages(c('rentrez', 'xml2'))"
    )
  }
  if (identical(as.integer(fallback_backbone_id), 4L)) {
    stop(
      "verify_taxon_names: `fallback_backbone_id` cannot be 4 (NCBI) -- the ",
      "fallback exists specifically to reach the Global Names Verifier API's ",
      "fuzzy matching, which the NCBI direct-lookup bypass does not have.",
      call. = FALSE
    )
  }

  n_total <- length(clean_names)
  message("Verifying ", n_total, " unique name(s) against NCBI taxonomy (direct)...")

  delay <- if (nzchar(Sys.getenv("ENTREZ_KEY", "")) ||
    nzchar(Sys.getenv("NCBI_API_KEY", ""))) {
    0.11
  } else {
    0.34
  }

  # --- Step 1: Batch entrez_search to find taxids ---
  # Build OR'd queries: "Name1"[Scientific Name] OR "Name2"[Scientific Name] ...
  batches <- split(clean_names, ceiling(seq_along(clean_names) / search_batch_size))

  # Map: name => taxid (character)
  name_to_taxid <- stats::setNames(rep(NA_character_, n_total), clean_names)
  fuzzy_corrected <- stats::setNames(rep(FALSE, n_total), clean_names)

  # A name is not a key -- NCBI can hold several nodes sharing one scientific
  # name in unrelated lineages (see resolve_ncbi_taxid()'s own header for
  # confirmed real cases: a genus of red algae named "Vertebrata" beside the
  # vertebrate clade of the same name). This used to pick whichever ESummary
  # happened to be processed last for such a name -- silently. Every ESummary
  # record for a name sharing a batch's query is grouped here instead; a name
  # with more than one is AMBIGUOUS and is resolved below (never guessed),
  # not written into name_to_taxid directly.
  ambiguous_summaries <- list()

  # Names the service could not be ASKED about, as opposed to names it
  # answered "no match" for. A failed search batch, a failed lineage fetch or
  # a failed synonym fallback lands its names here, and Step 3 reports them
  # with verified = FALSE, which the cache writer never stores and every
  # consumer already treats as "ask again". Before this set existed such a
  # name left Step 3 as verified = TRUE / matched_name = NA -- the same shape
  # as a genuine non-match -- and a cache_dir then served a network outage as
  # a definitive answer on every later run.
  failed_names <- character(0)
  failed_taxids <- character(0)

  for (i in seq_along(batches)) {
    batch <- batches[[i]]
    or_terms <- paste0('"', batch, '"[Scientific Name]')
    query <- paste(or_terms, collapse = " OR ")

    # NCBI throttles and drops requests under load; a failed search must
    # not read as "these names do not exist". Three attempts with a growing
    # pause, like the lineage fetch below, then a warning naming the batch.
    res <- NULL
    search_error <- NULL
    for (attempt in 1:3) {
      res <- tryCatch(
        rentrez::entrez_search(
          db     = "taxonomy",
          term   = query,
          retmax = length(batch) * 2L # allow some overhead
        ),
        error = function(e) {
          search_error <<- e
          NULL
        }
      )
      if (!is.null(res)) break
      if (attempt < 3L) Sys.sleep(attempt * max(delay, 1))
    }

    tryCatch(
      {
        if (is.null(res)) stop(conditionMessage(search_error))

        if (as.integer(res$count) > 0L && length(res$ids) > 0L) {
          # Resolve taxids back to names via esummary
          summaries <- .ncbi_batch_summary(res$ids, delay)
          by_name <- list()
          for (s in summaries) {
            sci_name <- s$scientificname %||% s$ScientificName
            if (!is.null(sci_name) && sci_name %in% clean_names) {
              by_name[[sci_name]] <- c(by_name[[sci_name]], list(s))
            }
          }
          for (sci_name in names(by_name)) {
            hits <- by_name[[sci_name]]
            if (length(hits) == 1L) {
              name_to_taxid[[sci_name]] <- as.character(hits[[1L]]$uid %||% hits[[1L]]$TaxId)
            } else {
              ambiguous_summaries[[sci_name]] <- hits
            }
          }
        }
      },
      error = function(e) {
        failed_names <<- c(failed_names, batch)
        warning(
          "verify_taxon_names: NCBI search batch ", i, " failed after 3 attempts: ",
          conditionMessage(e),
          "; its ", length(batch), " name(s) are reported as unverified ",
          "(verified = FALSE), not as absent, and are never cached.",
          call. = FALSE
        )
      }
    )

    if (i < length(batches)) Sys.sleep(delay)
  }

  # --- Ambiguity resolution ---------------------------------------------------
  # Never guessed: an ambiguous name is resolved against `decisions` (a
  # supplied data frame, or one saved at a supplied path); anything still
  # pending after that is handled by session type -- one batch prompt
  # (interactive) or a stop() naming exactly how to supply the missing
  # decisions (non-interactive). `skipped_names` (an explicit decision of
  # NA, "this name means nothing to me") must NOT re-enter Step 1b/1c's
  # missing-name fallback below -- that would silently override the user's
  # own choice with a different, independent resolution mechanism.
  skipped_names <- character(0L)
  if (length(ambiguous_summaries) > 0L) {
    dec_df <- if (is.data.frame(decisions)) decisions else NULL
    dec_path <- if (is.character(decisions) && length(decisions) == 1L && !is.na(decisions)) decisions else NULL

    pending_names <- names(ambiguous_summaries)

    # Rank first. The caller often knows the rank it means a name at (a
    # consensus table does), and every candidate's own rank is already in
    # hand from the ESummary that found it, so a homonym whose candidates
    # include exactly one node at that rank is resolved here with no further
    # request and before any decision is consulted -- resolve_ncbi_taxid()'s
    # resolved_by_rank, applied to the batch.
    if (!is.null(ranks) && length(pending_names) > 0L) {
      by_rank <- character(0L)
      for (nm in pending_names) {
        want <- if (nm %in% names(ranks)) ranks[[nm]] else NA_character_
        if (is.na(want)) next
        cands <- ambiguous_summaries[[nm]]
        cand_rank <- tolower(vapply(cands, function(s) as.character(s$rank %||% NA_character_), character(1L)))
        hit <- which(!is.na(cand_rank) & cand_rank == want)
        if (length(hit) == 1L) {
          name_to_taxid[[nm]] <- as.character(cands[[hit]]$uid %||% cands[[hit]]$TaxId)
          by_rank <- c(by_rank, nm)
        }
      }
      if (length(by_rank) > 0L) {
        message(sprintf(
          "verify_taxon_names: %d homonym(s) resolved by the caller's rank: %s.",
          length(by_rank), paste(by_rank, collapse = ", ")
        ))
        pending_names <- setdiff(pending_names, by_rank)
      }
    }

    # Lineage next. Rank cannot separate two genus-rank nodes in different
    # kingdoms (Argentina the fish, Argentina the plant); the caller's own
    # known ancestors can. Every candidate's lineage is fetched here, in one
    # batched request for the whole set, the same table the report below
    # prints -- so this costs nothing the unresolved case would not have paid.
    # Where the caller also gave a rank, candidates at that rank are preferred
    # when any exist. Exactly one candidate containing any context term
    # resolves; zero or several leave the name pending.
    prebuilt_ambiguous <- NULL
    if (!is.null(lineage) && length(pending_names) > 0L) {
      ctx <- vapply(pending_names, function(nm) {
        if (nm %in% names(lineage)) as.character(lineage[[nm]]) else NA_character_
      }, character(1L))
      with_ctx <- pending_names[!is.na(ctx)]
      if (length(with_ctx) > 0L) {
        prebuilt_ambiguous <- .build_ncbi_ambiguous_table(ambiguous_summaries[with_ctx], delay)
        by_lineage <- character(0L)
        for (nm in with_ctx) {
          cand <- prebuilt_ambiguous[prebuilt_ambiguous$name == nm, , drop = FALSE]
          want <- if (!is.null(ranks) && nm %in% names(ranks)) ranks[[nm]] else NA_character_
          if (!is.na(want)) {
            at <- !is.na(cand$candidate_rank) & tolower(cand$candidate_rank) == want
            if (any(at)) cand <- cand[at, , drop = FALSE]
          }
          full <- if ("candidate_lineage_full" %in% names(cand)) cand$candidate_lineage_full else cand$candidate_lineage
          hit <- which(.lineage_contains(full, ctx[[nm]]))
          if (length(hit) == 1L) {
            name_to_taxid[[nm]] <- cand$candidate_taxid[hit]
            by_lineage <- c(by_lineage, nm)
          }
        }
        if (length(by_lineage) > 0L) {
          message(sprintf(
            "verify_taxon_names: %d homonym(s) resolved by the caller's lineage: %s.",
            length(by_lineage), paste(by_lineage, collapse = ", ")
          ))
          pending_names <- setdiff(pending_names, by_lineage)
        }
      }
    }

    applied <- .apply_ncbi_homonym_decisions(pending_names, path = dec_path, decisions = dec_df)
    for (nm in pending_names[attr(applied, "decided")]) {
      if (!is.na(applied[[nm]])) {
        name_to_taxid[[nm]] <- applied[[nm]]
      } else {
        skipped_names <- c(skipped_names, nm)
      }
    }
    still_pending <- pending_names[!attr(applied, "decided")]

    if (length(still_pending) > 0L) {
      # Reuse the candidate table already fetched for the lineage step.
      need_build <- setdiff(still_pending, if (is.null(prebuilt_ambiguous)) character(0L) else unique(prebuilt_ambiguous$name))
      ambiguous_df <- dplyr::bind_rows(
        if (!is.null(prebuilt_ambiguous)) prebuilt_ambiguous[prebuilt_ambiguous$name %in% still_pending, , drop = FALSE],
        if (length(need_build) > 0L) .build_ncbi_ambiguous_table(ambiguous_summaries[need_build], delay)
      )

      if (.is_interactive_session()) {
        new_decisions <- .prompt_ncbi_homonym_decisions(ambiguous_df)
        for (j in seq_len(nrow(new_decisions))) {
          nm <- new_decisions$name[j]
          tid <- new_decisions$taxid[j]
          if (!is.na(tid)) {
            name_to_taxid[[nm]] <- tid
          } else {
            skipped_names <- c(skipped_names, nm)
          }
        }
        if (!is.null(dec_path)) {
          .save_ncbi_homonym_decisions(new_decisions, dec_path)
          message(sprintf(
            "verify_taxon_names: %d decision(s) saved to %s.",
            nrow(new_decisions), dec_path
          ))
        } else {
          message(
            "verify_taxon_names: no `decisions` path was supplied, so nothing was written to ",
            "disk. Paste this into your script to skip the prompt next time:\n\n",
            "decisions <- data.frame(\n",
            "  name = c(", paste(sprintf('"%s"', new_decisions$name), collapse = ", "), "),\n",
            "  taxid = c(",
            paste(ifelse(is.na(new_decisions$taxid), "NA_integer_", new_decisions$taxid), collapse = ", "),
            ")\n)"
          )
        }
      } else if (is.null(decisions)) {
        # No decision can reach this call (a batch issued from inside another
        # function has no `decisions` to pass), so the stop below would cost
        # the whole batch for one undecidable name: 75 of 75 unreferenced
        # taxa lost their lineage over "Etheostoma" alone. These names are
        # reported alone as verified = FALSE (never cached, asked again next
        # call) with the candidate table, and the rest of the batch proceeds.
        # They are also excluded from the synonym and fuzzy fallbacks below,
        # which would otherwise re-attempt resolution by another route.
        failed_names <- c(failed_names, still_pending)
        skipped_names <- c(skipped_names, still_pending)
        warning(
          "verify_taxon_names: ", length(still_pending), " name(s) resolved to more than one ",
          "NCBI taxonomy node and could not be told apart by rank; reported as unverified ",
          "(verified = FALSE), not cached. Supply `ranks =` or `decisions =` to resolve them:\n\n",
          .format_ncbi_ambiguous_report(ambiguous_df),
          call. = FALSE
        )
      } else {
        stop(
          "verify_taxon_names: ", length(still_pending), " name(s) resolved to more than one ",
          "NCBI taxonomy node, and `decisions` does not cover them. A name is not a key -- ",
          "decide which candidate each one means, then re-run with `decisions =` set to a ",
          "data frame like the one below (taxid = NA_integer_ means skip), or saveRDS() it ",
          "and pass the path so this only needs deciding once:\n\n",
          .format_ncbi_ambiguous_report(ambiguous_df),
          call. = FALSE
        )
      }
    }
  }

  # --- Step 1b: Synonym fallback for unmatched names ---
  # [Scientific Name] misses reclassified taxa (e.g., Hypsurus caryi -> Embiotoca
  # caryi). Try [All Names] for names that weren't found, one at a time to
  # correctly associate input name -> taxid. Excludes skipped_names: an
  # explicit skip decision must not be silently re-attempted here.
  missing_names <- clean_names[is.na(name_to_taxid) & !clean_names %in% skipped_names]
  if (length(missing_names) > 0L) {
    for (nm in missing_names) {
      tryCatch(
        {
          res <- rentrez::entrez_search(
            db     = "taxonomy",
            term   = paste0('"', nm, '"[All Names]'),
            retmax = 1L
          )
          if (as.integer(res$count) > 0L && length(res$ids) > 0L) {
            name_to_taxid[[nm]] <- as.character(res$ids[1L])
          }
        },
        # The synonym check could not be run, so "no match" is not known yet.
        error = function(e) failed_names <<- c(failed_names, nm)
      )
      Sys.sleep(delay)
    }
  }

  # --- Step 1c: Fuzzy cross-backbone fallback for names NCBI still can't find ---
  # NCBI's exact-string Entrez search has no typo tolerance -- a single
  # misspelled letter (e.g. "flavimannus" vs "flavimanus") returns zero hits
  # even via [All Names], while any other backbone_id (routed through the real
  # Global Names Verifier API) resolves it immediately via genuine fuzzy
  # matching. That fuzzy match is used only to SUGGEST a corrected spelling;
  # the correction is then re-resolved through NCBI itself (never adopting the
  # fallback backbone's own classification), so this bypass's whole reason for
  # existing -- avoiding GlobalNames' incomplete/demoting NCBI snapshot --
  # still holds for the corrected name.
  # Also excludes skipped_names -- see Step 1b's own comment above.
  still_missing <- clean_names[is.na(name_to_taxid) & !clean_names %in% skipped_names]

  if (length(still_missing) > 0L) {
    fuzzy_hits <- tryCatch(
      verify_taxon_names(still_missing, backbone_id = fallback_backbone_id),
      error = function(e) NULL
    )

    if (!is.null(fuzzy_hits) && nrow(fuzzy_hits) == length(still_missing)) {
      for (i in seq_along(still_missing)) {
        orig <- still_missing[i]
        corrected <- fuzzy_hits$matched_name[i]
        if (is.na(corrected) || identical(corrected, orig)) next

        # Reuse an already-resolved taxid for the corrected spelling if this
        # same batch already found one (e.g. another row spelled it
        # correctly); otherwise do one fresh exact NCBI lookup for it.
        tid <- if (corrected %in% names(name_to_taxid)) name_to_taxid[[corrected]] else NA_character_
        if (is.na(tid)) {
          tryCatch(
            {
              res <- rentrez::entrez_search(
                db = "taxonomy", term = paste0('"', corrected, '"[All Names]'), retmax = 1L
              )
              if (as.integer(res$count) > 0L && length(res$ids) > 0L) {
                tid <- as.character(res$ids[1L])
              }
            },
            error = function(e) NULL
          )
          Sys.sleep(delay)
        }

        if (!is.na(tid)) {
          name_to_taxid[[orig]] <- tid
          fuzzy_corrected[[orig]] <- TRUE
        }
      }
    }
  }

  if (any(fuzzy_corrected)) {
    fixed <- names(fuzzy_corrected)[fuzzy_corrected]
    warning(
      "verify_taxon_names: ", length(fixed), " name(s) not found by NCBI's exact ",
      "search were fuzzy-matched via backbone ", fallback_backbone_id, " and ",
      "corrected:\n",
      paste0('  "', fixed, '"', collapse = "\n"),
      "\nVerify these are genuine typos, not distinct taxa, before trusting them ",
      "downstream -- see the `fuzzy_corrected` column.",
      call. = FALSE
    )
  }

  found_mask <- !is.na(name_to_taxid)
  found_taxids <- name_to_taxid[found_mask]
  n_found <- sum(found_mask)

  message("  Found ", n_found, " of ", n_total, " names in NCBI taxonomy.")

  # --- Step 2: Fetch full lineage XML for found taxids ---
  lineage_map <- list() # taxid => list(classification_path, classification_ranks)

  if (n_found > 0L) {
    unique_taxids <- unique(found_taxids)
    fetch_batches <- split(
      unique_taxids,
      ceiling(seq_along(unique_taxids) / fetch_batch_size)
    )

    for (i in seq_along(fetch_batches)) {
      attempt <- 0L
      success <- FALSE
      while (attempt < 3L && !success) {
        attempt <- attempt + 1L
        tryCatch(
          {
            xml_raw <- rentrez::entrez_fetch(
              db = "taxonomy", id = fetch_batches[[i]], rettype = "xml"
            )
            parsed <- .parse_ncbi_lineage_xml(xml_raw)
            for (tid in names(parsed)) {
              lineage_map[[tid]] <- parsed[[tid]]
            }
            success <- TRUE
          },
          error = function(e) {
            if (attempt < 3L) Sys.sleep(attempt)
          }
        )
      }
      if (!success) {
        failed_taxids <- c(failed_taxids, fetch_batches[[i]])
        warning(
          "verify_taxon_names: NCBI lineage fetch batch ", i, " failed after 3 ",
          "attempts; its ", length(fetch_batches[[i]]), " taxid(s) are reported ",
          "as unverified (verified = FALSE), not as absent, and are never cached.",
          call. = FALSE
        )
      }
      if (i < length(fetch_batches)) Sys.sleep(delay)
    }
  }

  # --- Step 3: Assemble output tibble ---
  rows <- lapply(clean_names, function(nm) {
    tid <- name_to_taxid[[nm]]
    if (is.na(tid) || is.null(lineage_map[[tid]])) {
      # verified says the service ANSWERED. It did not when the name's search
      # batch, synonym fallback or (for a resolved taxid) lineage fetch failed.
      lookup_failed <- nm %in% failed_names || (!is.na(tid) && tid %in% failed_taxids)
      return(dplyr::tibble(
        user_supplied_name   = nm,
        matched_name         = NA_character_,
        matched_rank         = NA_character_,
        is_synonym           = NA,
        classification_path  = NA_character_,
        classification_ranks = NA_character_,
        score                = NA_real_,
        verified             = !lookup_failed,
        fuzzy_corrected      = fuzzy_corrected[[nm]]
      ))
    }

    lin <- lineage_map[[tid]]
    dplyr::tibble(
      user_supplied_name   = nm,
      matched_name         = lin$matched_name,
      # NA, not FALSE: this bypass reads NCBI's taxonomy XML directly and has
      # no access to synonym/current-name relationships the way the Global
      # Names Verifier path does (confirmed live: GBIF/CoL/WoRMS flag "Inu" as
      # a synonym of "Luciogobius", NCBI's own taxonomy does not consider it
      # one at all) -- "unknown" is honest here, "not a synonym" would not be.
      is_synonym           = NA,
      matched_rank         = .last_classification_rank(lin$classification_ranks),
      classification_path  = lin$classification_path,
      classification_ranks = lin$classification_ranks,
      score                = 1.0,
      verified             = TRUE,
      fuzzy_corrected      = fuzzy_corrected[[nm]]
    )
  })

  result <- dplyr::bind_rows(rows)

  n_matched <- sum(!is.na(result$matched_name))
  n_failed <- sum(!result$verified)
  n_no_match <- sum(is.na(result$matched_name) & result$verified)
  n_fuzzy <- sum(result$fuzzy_corrected)
  msg_ncbi <- sprintf("Done. %d name(s) matched.", n_matched)
  if (n_fuzzy > 0L) msg_ncbi <- paste0(msg_ncbi, sprintf(" %d matched only after fuzzy correction.", n_fuzzy))
  if (n_no_match > 0L) msg_ncbi <- paste0(msg_ncbi, sprintf(" %d had no match.", n_no_match))
  if (n_failed > 0L) msg_ncbi <- paste0(msg_ncbi, sprintf(" %d could not be looked up (verified = FALSE; not cached).", n_failed))
  message(msg_ncbi)

  result
}


#' Batch entrez_summary for taxonomy DB
#'
#' @param taxids Character vector of taxids.
#' @param delay Numeric. Seconds between batches.
#' @return List of summary records (each a named list with uid, scientificname).
#' @noRd
.ncbi_batch_summary <- function(taxids, delay = 0.11) {
  batch_size <- 100L
  batches <- split(taxids, ceiling(seq_along(taxids) / batch_size))
  all_summaries <- list()

  for (i in seq_along(batches)) {
    tryCatch(
      {
        summ <- rentrez::entrez_summary(db = "taxonomy", id = batches[[i]])
        # entrez_summary returns a single record (not a list) when length == 1
        if (inherits(summ, "esummary")) {
          all_summaries <- c(all_summaries, list(summ))
        } else {
          all_summaries <- c(all_summaries, summ)
        }
      },
      error = function(e) {
        message("NCBI summary batch failed: ", conditionMessage(e))
        warning("NCBI summary batch failed: ", conditionMessage(e), call. = FALSE)
      }
    )
    if (i < length(batches)) Sys.sleep(delay)
  }

  all_summaries
}


#' Parse NCBI taxonomy XML into lineage data
#'
#' @param xml_raw Character. Raw XML from entrez_fetch(db="taxonomy").
#' @return Named list: taxid -> list(matched_name, classification_path,
#'   classification_ranks). Paths and ranks are pipe-delimited strings.
#' @noRd
.parse_ncbi_lineage_xml <- function(xml_raw) {
  xml_doc <- xml2::read_xml(xml_raw)
  nodes <- xml2::xml_find_all(xml_doc, "//TaxaSet/Taxon")

  result <- list()

  for (node in nodes) {
    this_id <- xml2::xml_text(xml2::xml_find_first(node, "./TaxId"))
    this_sci <- xml2::xml_text(xml2::xml_find_first(node, "./ScientificName"))
    this_rank <- xml2::xml_text(xml2::xml_find_first(node, "./Rank"))

    # Parse lineage ancestors
    lineage_nodes <- xml2::xml_find_all(node, "./LineageEx/Taxon")
    l_ranks <- xml2::xml_text(xml2::xml_find_first(lineage_nodes, "./Rank"))
    l_names <- xml2::xml_text(xml2::xml_find_first(lineage_nodes, "./ScientificName"))

    # Build path: lineage ranks + the taxon's own rank
    # Keep only standard Linnaean ranks + common sub-ranks to avoid duplicate
    # "clade" entries that break change_backbone()'s unnest_wider().
    linnaean_ranks <- c(
      "superkingdom", "kingdom", "subkingdom",
      "superphylum", "phylum", "subphylum",
      "superclass", "class", "subclass", "infraclass",
      "superorder", "order", "suborder", "infraorder",
      "superfamily", "family", "subfamily",
      "tribe", "subtribe",
      "genus", "subgenus",
      "species", "subspecies", "varietas", "forma"
    )

    keep <- !is.na(l_ranks) & nzchar(l_ranks) & l_ranks %in% linnaean_ranks &
      !is.na(l_names) & nzchar(l_names)
    path_names <- l_names[keep]
    path_ranks <- l_ranks[keep]

    # Append the taxon itself (if it has a recognized rank)
    if (!is.na(this_rank) && nzchar(this_rank) && this_rank %in% linnaean_ranks) {
      path_names <- c(path_names, this_sci)
      path_ranks <- c(path_ranks, this_rank)
    }

    result[[this_id]] <- list(
      matched_name         = this_sci,
      classification_path  = paste(path_names, collapse = "|"),
      classification_ranks = paste(path_ranks, collapse = "|")
    )
  }

  result
}
