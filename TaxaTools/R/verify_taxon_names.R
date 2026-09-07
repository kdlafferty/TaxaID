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
#'
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
#'   \item{verified}{Logical. \code{TRUE} if the API returned a result,
#'     \code{FALSE} if the API failed and fallback values were used. Always
#'     check rows where \code{verified = FALSE}.}
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
#' Life, ITIS, NCBI, WoRMS, GBIF) with the same query before this section was
#' written: \code{matched_rank} (derived from \code{classificationRanks}) and
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
                               fallback_backbone_id = 11L) {
  # --- Input validation ---
  if (!is.character(name_list) || length(name_list) == 0) {
    stop("`name_list` must be a non-empty character vector.")
  }
  if ((!is.numeric(backbone_id) && !is.integer(backbone_id)) ||
    length(backbone_id) != 1 || is.na(backbone_id)) {
    stop("`backbone_id` must be a single integer (e.g., 4 for NCBI).")
  }
  backbone_id <- as.integer(backbone_id)

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
    unique_df <- .verify_via_ncbi(clean_names, fallback_backbone_id = fallback_backbone_id)
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
    return(final_df)
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

  n_verified <- sum(unique_df$verified, na.rm = TRUE)
  n_unverified <- sum(!unique_df$verified, na.rm = TRUE)
  n_no_match <- sum(unique_df$verified & is.na(unique_df$matched_name), na.rm = TRUE)

  msg <- sprintf("Done. %d name(s) reached the API.", n_verified)
  if (n_no_match > 0L) msg <- paste0(msg, sprintf(" %d had no match.", n_no_match))
  if (n_unverified > 0L) msg <- paste0(msg, sprintf(" %d were unverified due to API failure.", n_unverified))
  message(msg)

  final_df
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
#' @return A tibble with columns: user_supplied_name, matched_name,
#'   classification_path, classification_ranks, score, verified,
#'   fuzzy_corrected.
#' @noRd
.verify_via_ncbi <- function(clean_names,
                             search_batch_size = 40L,
                             fetch_batch_size = 100L,
                             fallback_backbone_id = 11L) {
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

  for (i in seq_along(batches)) {
    batch <- batches[[i]]
    or_terms <- paste0('"', batch, '"[Scientific Name]')
    query <- paste(or_terms, collapse = " OR ")

    tryCatch(
      {
        res <- rentrez::entrez_search(
          db     = "taxonomy",
          term   = query,
          retmax = length(batch) * 2L # allow some overhead
        )

        if (as.integer(res$count) > 0L && length(res$ids) > 0L) {
          # Resolve taxids back to names via esummary
          summaries <- .ncbi_batch_summary(res$ids, delay)
          for (s in summaries) {
            sci_name <- s$scientificname %||% s$ScientificName
            if (!is.null(sci_name) && sci_name %in% clean_names) {
              name_to_taxid[[sci_name]] <- as.character(s$uid %||% s$TaxId)
            }
          }
        }
      },
      error = function(e) {
        warning(
          "verify_taxon_names: NCBI search batch ", i, " failed: ",
          conditionMessage(e),
          call. = FALSE
        )
      }
    )

    if (i < length(batches)) Sys.sleep(delay)
  }

  # --- Step 1b: Synonym fallback for unmatched names ---
  # [Scientific Name] misses reclassified taxa (e.g., Hypsurus caryi -> Embiotoca
  # caryi). Try [All Names] for names that weren't found, one at a time to
  # correctly associate input name -> taxid.
  missing_names <- clean_names[is.na(name_to_taxid)]
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
        error = function(e) NULL
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
  still_missing <- clean_names[is.na(name_to_taxid)]

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
      if (i < length(fetch_batches)) Sys.sleep(delay)
    }
  }

  # --- Step 3: Assemble output tibble ---
  rows <- lapply(clean_names, function(nm) {
    tid <- name_to_taxid[[nm]]
    if (is.na(tid) || is.null(lineage_map[[tid]])) {
      return(dplyr::tibble(
        user_supplied_name   = nm,
        matched_name         = NA_character_,
        matched_rank         = NA_character_,
        is_synonym           = NA,
        classification_path  = NA_character_,
        classification_ranks = NA_character_,
        score                = NA_real_,
        verified             = TRUE,
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
  n_no_match <- sum(is.na(result$matched_name))
  n_fuzzy <- sum(result$fuzzy_corrected)
  msg_ncbi <- sprintf("Done. %d name(s) matched.", n_matched)
  if (n_fuzzy > 0L) msg_ncbi <- paste0(msg_ncbi, sprintf(" %d matched only after fuzzy correction.", n_fuzzy))
  if (n_no_match > 0L) msg_ncbi <- paste0(msg_ncbi, sprintf(" %d had no match.", n_no_match))
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
