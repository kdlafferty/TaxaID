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
#'
#' @return A tibble with one row per input name and the following columns:
#' \describe{
#'   \item{user_supplied_name}{The original name as supplied.}
#'   \item{matched_name}{The best-matched name returned by the backbone (genus
#'     and species epithet only; authorship strings are stripped), or
#'     \code{NA} if no match was found.}
#'   \item{classification_path}{Pipe-delimited classification path from the
#'     backbone (e.g., \code{"Animalia|Chordata|..."}).}
#'   \item{classification_ranks}{Pipe-delimited rank labels corresponding to
#'     \code{classification_path}.}
#'   \item{score}{Backbone match confidence score between 0 and 1. Higher is
#'     better. This measures name-matching quality against the backbone and is
#'     unrelated to the sequence match scores used elsewhere in the TaxaID
#'     ecosystem (e.g., percent identity from BLAST).}
#'   \item{verified}{Logical. \code{TRUE} if the API returned a result,
#'     \code{FALSE} if the API failed and fallback values were used. Always
#'     check rows where \code{verified = FALSE}.}
#' }
#'
#' @note If the API is unreachable, the function issues a warning and returns
#'   the original names with \code{verified = FALSE} and \code{score = NA}
#'   rather than stopping, so that partial results from earlier batches are
#'   not lost. Review all \code{verified = FALSE} rows before using results
#'   downstream.
#'
#' @note Name changes suggested by the backbone should always be manually
#'   confirmed before accepting them -- automated synonym resolution can be
#'   incorrect.
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
#' result <- verify_taxon_names(names, backbone_id = 4)  # NCBI
#' result
#'
#' # Check which names failed verification or had no match
#' result[!result$verified | is.na(result$matched_name), ]
#' }
verify_taxon_names <- function(name_list,
                               backbone_id,
                               batch_size  = 500,
                               timeout_sec = 30) {

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
  clean_names   <- unique(trimmed_names)
  clean_names   <- clean_names[!is.na(clean_names) & nzchar(clean_names)]
  n_total       <- length(clean_names)

  if (n_total == 0L) {
    stop("verify_taxon_names: no valid (non-NA, non-empty) names in `name_list`.")
  }

  # --- NCBI direct bypass (backbone_id = 4) ---
  # GlobalNames has an incomplete NCBI snapshot that demotes valid species

  # to genus (~30% loss). Query NCBI taxonomy directly instead.
  if (identical(as.integer(backbone_id), 4L)) {
    unique_df <- .verify_via_ncbi(clean_names)
    idx <- match(trimmed_names, unique_df$user_supplied_name)
    final_df <- unique_df[idx, , drop = FALSE]
    # NA/empty input names get a placeholder row with verified = FALSE
    na_rows <- which(is.na(idx))
    if (length(na_rows) > 0L) {
      final_df$user_supplied_name[na_rows] <- trimmed_names[na_rows]
      final_df$verified[na_rows] <- FALSE
    }
    rownames(final_df) <- NULL
    return(final_df)
  }

  message("Verifying ", n_total, " unique name(s) against backbone ", backbone_id, "...")

  api_url <- "https://verifier.globalnames.org/api/v1/verifications"

  # --- Split into batches ---
  batches   <- split(clean_names, ceiling(seq_along(clean_names) / batch_size))
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
      nameStrings    = as.list(batch),           # as.list() ensures JSON array even for single names
      dataSources    = list(as.integer(backbone_id)),
      withAllMatches = FALSE
    )

    batch_result <- tryCatch({

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
          "verify_taxon_names: batch %d returned no 'names' field. API response may be malformed. Treating %d names as unverified.",
          i, length(batch)
        ))
        batch_result <- dplyr::tibble(
          user_supplied_name   = batch,
          matched_name         = NA_character_,
          classification_path  = NA_character_,
          classification_ranks = NA_character_,
          score                = NA_real_,
          verified             = FALSE
        )
        results[[i]] <- batch_result
        next
      }

      # httr::content(as = "parsed") can return single-element lists instead of
      # plain scalars for some fields. These helpers safely extract a scalar value.
      safe_chr <- function(x) {
        if (is.null(x)) return(NA_character_)
        if (is.list(x)) x <- x[[1]]
        as.character(x)
      }
      safe_dbl <- function(x) {
        if (is.null(x)) return(NA_real_)
        if (is.list(x)) x <- x[[1]]
        as.double(x)
      }

      # Helper: strip authorship from a name string, keeping only the
      # genus (and optional epithet). Authority strings begin after the
      # binomial (e.g. "(Claus, 1863)" or "Hasle, 1993").
      # Pattern: uppercase-start word (genus, allows hyphens/dots) +
      # optional space + lowercase-start word (epithet).
      strip_authority <- function(x) {
        if (is.na(x)) return(NA_character_)
        m <- regmatches(trimws(x),
                        regexpr("^[A-Z][A-Za-z.-]*(?: [a-z][A-Za-z.-]*)?",
                                trimws(x), perl = TRUE))
        if (length(m) == 0L) x else m
      }

      # --- Parse each name's result ---
      parsed <- lapply(data$names, function(item) {
        best <- item$bestResult

        if (is.null(best)) {
          # API responded but found no match for this name
          return(dplyr::tibble(
            user_supplied_name   = safe_chr(item$name),
            matched_name         = NA_character_,
            classification_path  = NA_character_,
            classification_ranks = NA_character_,
            score                = NA_real_,
            verified             = TRUE   # API worked; it just found nothing
          ))
        }

        dplyr::tibble(
          user_supplied_name   = safe_chr(item$name),
          matched_name         = strip_authority(safe_chr(best$matchedName)),
          classification_path  = safe_chr(best$classificationPath),
          classification_ranks = safe_chr(best$classificationRanks),
          score                = safe_dbl(best$score),
          verified             = TRUE
        )
      })

      dplyr::bind_rows(parsed)

    }, error = function(e) {

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
        classification_path  = NA_character_,
        classification_ranks = NA_character_,
        score                = NA_real_,
        verified             = FALSE
      )
    })

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

  n_verified   <- sum( unique_df$verified, na.rm = TRUE)
  n_unverified <- sum(!unique_df$verified, na.rm = TRUE)
  n_no_match   <- sum(unique_df$verified & is.na(unique_df$matched_name), na.rm = TRUE)

  msg <- sprintf("Done. %d name(s) reached the API.", n_verified)
  if (n_no_match   > 0L) msg <- paste0(msg, sprintf(" %d had no match.", n_no_match))
  if (n_unverified > 0L) msg <- paste0(msg, sprintf(" %d were unverified due to API failure.", n_unverified))
  message(msg)

  final_df
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
#' @return A tibble with columns: user_supplied_name, matched_name,
#'   classification_path, classification_ranks, score, verified.
#' @noRd
.verify_via_ncbi <- function(clean_names,
                             search_batch_size = 40L,
                             fetch_batch_size  = 100L) {

  if (!requireNamespace("rentrez", quietly = TRUE) ||
      !requireNamespace("xml2", quietly = TRUE)) {
    stop(
      "verify_taxon_names: packages 'rentrez' and 'xml2' are required for ",
      "direct NCBI lookup (backbone_id = 4).\n",
      "Install with: install.packages(c('rentrez', 'xml2'))"
    )
  }

  n_total <- length(clean_names)
  message("Verifying ", n_total, " unique name(s) against NCBI taxonomy (direct)...")

  delay <- if (nzchar(Sys.getenv("ENTREZ_KEY", "")) ||
               nzchar(Sys.getenv("NCBI_API_KEY", ""))) 0.11 else 0.34

  # --- Step 1: Batch entrez_search to find taxids ---
  # Build OR'd queries: "Name1"[Scientific Name] OR "Name2"[Scientific Name] ...
  batches <- split(clean_names, ceiling(seq_along(clean_names) / search_batch_size))

  # Map: name -> taxid (character)
  name_to_taxid <- stats::setNames(rep(NA_character_, n_total), clean_names)

  for (i in seq_along(batches)) {
    batch <- batches[[i]]
    or_terms <- paste0('"', batch, '"[Scientific Name]')
    query <- paste(or_terms, collapse = " OR ")

    tryCatch({
      res <- rentrez::entrez_search(
        db     = "taxonomy",
        term   = query,
        retmax = length(batch) * 2L  # allow some overhead
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
    }, error = function(e) {
      warning(
        "verify_taxon_names: NCBI search batch ", i, " failed: ",
        conditionMessage(e), call. = FALSE
      )
    })

    if (i < length(batches)) Sys.sleep(delay)
  }

  # --- Step 1b: Synonym fallback for unmatched names ---
  # [Scientific Name] misses reclassified taxa (e.g., Hypsurus caryi -> Embiotoca
  # caryi). Try [All Names] for names that weren't found, one at a time to
  # correctly associate input name -> taxid.
  missing_names <- clean_names[is.na(name_to_taxid)]
  if (length(missing_names) > 0L) {
    for (nm in missing_names) {
      tryCatch({
        res <- rentrez::entrez_search(
          db     = "taxonomy",
          term   = paste0('"', nm, '"[All Names]'),
          retmax = 1L
        )
        if (as.integer(res$count) > 0L && length(res$ids) > 0L) {
          name_to_taxid[[nm]] <- as.character(res$ids[1L])
        }
      }, error = function(e) NULL)
      Sys.sleep(delay)
    }
  }

  found_mask   <- !is.na(name_to_taxid)
  found_taxids <- name_to_taxid[found_mask]
  n_found      <- sum(found_mask)

  message("  Found ", n_found, " of ", n_total, " names in NCBI taxonomy.")

  # --- Step 2: Fetch full lineage XML for found taxids ---
  lineage_map <- list()  # taxid -> list(classification_path, classification_ranks)

  if (n_found > 0L) {
    unique_taxids  <- unique(found_taxids)
    fetch_batches  <- split(unique_taxids,
                            ceiling(seq_along(unique_taxids) / fetch_batch_size))

    for (i in seq_along(fetch_batches)) {
      attempt <- 0L
      success <- FALSE
      while (attempt < 3L && !success) {
        attempt <- attempt + 1L
        tryCatch({
          xml_raw <- rentrez::entrez_fetch(
            db = "taxonomy", id = fetch_batches[[i]], rettype = "xml"
          )
          parsed <- .parse_ncbi_lineage_xml(xml_raw)
          for (tid in names(parsed)) {
            lineage_map[[tid]] <- parsed[[tid]]
          }
          success <- TRUE
        }, error = function(e) {
          if (attempt < 3L) Sys.sleep(attempt)
        })
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
        classification_path  = NA_character_,
        classification_ranks = NA_character_,
        score                = NA_real_,
        verified             = TRUE
      ))
    }

    lin <- lineage_map[[tid]]
    dplyr::tibble(
      user_supplied_name   = nm,
      matched_name         = lin$matched_name,
      classification_path  = lin$classification_path,
      classification_ranks = lin$classification_ranks,
      score                = 1.0,
      verified             = TRUE
    )
  })

  result <- dplyr::bind_rows(rows)

  n_matched  <- sum(!is.na(result$matched_name))
  n_no_match <- sum(is.na(result$matched_name))
  msg_ncbi <- sprintf("Done. %d name(s) matched.", n_matched)
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
    tryCatch({
      summ <- rentrez::entrez_summary(db = "taxonomy", id = batches[[i]])
      # entrez_summary returns a single record (not a list) when length == 1
      if (inherits(summ, "esummary")) {
        all_summaries <- c(all_summaries, list(summ))
      } else {
        all_summaries <- c(all_summaries, summ)
      }
    }, error = function(e) {
      warning("NCBI summary batch failed: ", conditionMessage(e), call. = FALSE)
    })
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
  nodes   <- xml2::xml_find_all(xml_doc, "//TaxaSet/Taxon")

  result <- list()

  for (node in nodes) {
    this_id   <- xml2::xml_text(xml2::xml_find_first(node, "./TaxId"))
    this_sci  <- xml2::xml_text(xml2::xml_find_first(node, "./ScientificName"))
    this_rank <- xml2::xml_text(xml2::xml_find_first(node, "./Rank"))

    # Parse lineage ancestors
    lineage_nodes <- xml2::xml_find_all(node, "./LineageEx/Taxon")
    l_ranks <- xml2::xml_text(xml2::xml_find_first(lineage_nodes, "./Rank"))
    l_names <- xml2::xml_text(xml2::xml_find_first(lineage_nodes, "./ScientificName"))

    # Build path: lineage ranks + the taxon's own rank
    # Keep only standard Linnaean ranks + common sub-ranks to avoid duplicate
    # "clade" entries that break change_backbone()'s unnest_wider().
    linnaean_ranks <- c("superkingdom", "kingdom", "subkingdom",
                        "superphylum", "phylum", "subphylum",
                        "superclass", "class", "subclass", "infraclass",
                        "superorder", "order", "suborder", "infraorder",
                        "superfamily", "family", "subfamily",
                        "tribe", "subtribe",
                        "genus", "subgenus",
                        "species", "subspecies", "varietas", "forma")

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
