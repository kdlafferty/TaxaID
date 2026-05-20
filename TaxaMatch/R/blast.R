utils::globalVariables(c("qseqid", "pident", "slen", "staxids", "max_pident"))

# ==============================================================================
# blast_sequences() -- Query NCBI BLAST (remote or local) for top matches
# ==============================================================================

#' BLAST Sequences Against NCBI or a Local Database
#'
#' Searches query sequences against NCBI nucleotide (remote) or a local BLAST
#' database, then filters hits using a score window approach: retain all hits
#' within \code{score_range} percent identity of each query's top hit, up to
#' \code{max_hits} per query.
#'
#' @param seq_df Data frame with at least \code{asv_id} and \code{sequence}
#'   columns (e.g., output of \code{\link{read_sequence_table}} or
#'   \code{\link{filter_sequences}}).
#' @param method Character: \code{"remote"} (default) to use the NCBI BLAST URL
#'   API, or \code{"local"} to use a local BLAST+ database via the \pkg{rBLAST}
#'   package.
#' @param database For remote: NCBI database name (default \code{"nt"}). For
#'   local: path to a local BLAST database.
#' @param program BLAST program. Default \code{"blastn"}.
#' @param score_range Numeric. Keep all hits within this many percent identity
#'   points of each query's top hit (default \code{2}). For example, if the
#'   top hit is 99% identity, all hits at 97% or above are retained. Wider
#'   ranges capture more taxonomic alternatives; narrower ranges (e.g., 1)
#'   focus on the closest matches only.
#' @param max_hits Integer. Safety cap: maximum hits to retain per query after
#'   score window filtering (default \code{20L}). Increase for queries
#'   expected to match many closely related species.
#' @param min_score Numeric. Discard hits below this percent identity
#'   (default \code{70}). The 70% threshold is a conventional cross-genus
#'   floor for DNA barcoding; most true species-level matches exceed 95%.
#' @param min_query_coverage Numeric. Discard hits where less than this
#'   percentage of the query sequence aligned (default \code{80}). Standard
#'   BLAST quality filter; ensures hits span most of the barcode region.
#' @param barcode_term Character. Barcode marker name for auto-detecting
#'   subject length bounds (e.g., \code{"12S"}, \code{"COI"}). Default
#'   \code{NULL}.
#' @param min_subject_length Integer. Minimum subject (reference) sequence
#'   length in bp. Overrides \code{barcode_term}. Default \code{NULL}.
#' @param max_subject_length Integer. Maximum subject (reference) sequence
#'   length in bp. Overrides \code{barcode_term}. Default \code{NULL}.
#' @param max_target_seqs Integer. Number of hits to request from BLAST before
#'   client-side filtering (default \code{100L}). Should be generous (larger
#'   than \code{max_hits}) since NCBI's default is 500. Set higher (e.g., 500)
#'   for comprehensive searches; lower for speed.
#' @param batch_size Integer. For remote BLAST, number of sequences per
#'   submission (default \code{20L}). Larger batches reduce API overhead but
#'   risk timeout on NCBI's server. NCBI handles multi-FASTA queries.
#' @param email Character. Email address sent to NCBI (required by their usage
#'   policy for remote BLAST). Default \code{NULL}.
#' @param ncbi_api_key Character. Optional NCBI API key for higher rate limits.
#'   Default \code{NULL}.
#' @param resolve_taxonomy Logical. If \code{TRUE} (default), resolve NCBI
#'   taxonomy IDs to full lineage (kingdom through species) and append taxonomy
#'   columns to the output.
#' @param verbose Logical. Print progress messages. Default \code{TRUE}.
#'
#' @return A data frame with one row per query x hit, containing:
#'   \describe{
#'     \item{observation_id}{Query identifier (from \code{asv_id})}
#'     \item{accession}{Subject accession}
#'     \item{score}{Percent identity (0-100 scale)}
#'     \item{evalue}{E-value}
#'     \item{bitscore}{Bit score}
#'     \item{alignment_length}{Alignment length}
#'     \item{query_coverage}{Percent of query aligned}
#'     \item{subject_length}{Subject sequence length}
#'   }
#'   If \code{resolve_taxonomy = TRUE}, taxonomy columns (\code{kingdom},
#'   \code{phylum}, \code{class}, \code{order}, \code{family}, \code{genus},
#'   \code{species}) are appended.
#'
#'   This output is ready for \code{\link{standardize_match_data}}.
#'
#' @details
#' ## Score window algorithm
#'
#' Rather than a flat top-N cutoff, hits are filtered per query:
#' \enumerate{
#'   \item All hits below \code{min_score} are removed
#'   \item Hits with query coverage below \code{min_query_coverage} are removed
#'   \item Hits with subject length outside the barcode range are removed
#'   \item For each query, the top hit's percent identity is found
#'   \item All hits within \code{score_range} of the top hit are retained
#'   \item A \code{max_hits} safety cap is applied per query
#' }
#'
#' This means a clear top match may return only 1-3 hits (the rest are too
#' distant), while an ambiguous query retains all plausible candidates.
#'
#' ## Remote BLAST
#'
#' Uses the NCBI BLAST URL API with proper rate limiting (minimum 10 seconds
#' between submissions). Sequences are submitted in batches of
#' \code{batch_size}. The function polls for results with exponential backoff.
#' An \code{email} is required by NCBI usage policy.
#'
#' ## Local BLAST
#'
#' Requires BLAST+ installed on the system and the \pkg{rBLAST} package
#' (Bioconductor). Point \code{database} to a local BLAST database path.
#' Much faster for large numbers of queries.
#'
#' @examples
#' \dontrun{
#' hits <- blast_sequences(seq_df, method = "remote", database = "nt")
#' }
#'
#' @export
blast_sequences <- function(seq_df,
                            method = "remote",
                            database = "nt",
                            program = "blastn",
                            score_range = 2,
                            max_hits = 20L,
                            min_score = 70,
                            min_query_coverage = 80,
                            barcode_term = NULL,
                            min_subject_length = NULL,
                            max_subject_length = NULL,
                            max_target_seqs = 100L,
                            batch_size = 20L,
                            email = NULL,
                            ncbi_api_key = NULL,
                            resolve_taxonomy = TRUE,
                            verbose = TRUE) {

  # --- Input validation -------------------------------------------------------
  if (!is.data.frame(seq_df))
    stop("seq_df must be a data frame")
  if (!"asv_id" %in% names(seq_df) || !"sequence" %in% names(seq_df))
    stop("seq_df must contain 'asv_id' and 'sequence' columns")
  if (nrow(seq_df) == 0L)
    stop("seq_df has no rows")
  na_asv <- is.na(seq_df$asv_id) | !nzchar(seq_df$asv_id)
  na_seq <- is.na(seq_df$sequence) | !nzchar(seq_df$sequence)
  if (any(na_asv))
    stop(sprintf("seq_df has %d row(s) with empty or NA asv_id. All sequences must have identifiers.", sum(na_asv)))
  if (any(na_seq))
    stop(sprintf("seq_df has %d row(s) with empty or NA sequence. Remove these rows before calling blast_sequences().", sum(na_seq)))

  # Sanitize asv_id: '>' or newlines would corrupt FASTA formatting
  bad_ids <- grepl("[>\n\r]", seq_df$asv_id)
  if (any(bad_ids)) {
    warning(sprintf("blast_sequences: %d asv_id(s) contain '>' or newline characters; sanitizing.", sum(bad_ids)))
    seq_df$asv_id <- gsub("[>\n\r]", "_", seq_df$asv_id)
  }

  method <- match.arg(method, c("remote", "local"))

  if (!is.numeric(score_range) || length(score_range) != 1L || is.na(score_range) ||
      score_range < 0)
    stop("score_range must be a non-negative numeric value")
  if (!is.numeric(max_hits) || length(max_hits) != 1L || is.na(max_hits) ||
      max_hits < 1L)
    stop("max_hits must be a positive integer")
  if (!is.numeric(min_score) || length(min_score) != 1L || is.na(min_score))
    stop("min_score must be a single numeric value")
  if (!is.numeric(min_query_coverage) || length(min_query_coverage) != 1L ||
      is.na(min_query_coverage))
    stop("min_query_coverage must be a single numeric value")
  if (!is.logical(resolve_taxonomy) || length(resolve_taxonomy) != 1L ||
      is.na(resolve_taxonomy))
    stop("resolve_taxonomy must be TRUE or FALSE")

  max_hits <- as.integer(max_hits)
  max_target_seqs <- as.integer(max_target_seqs)
  batch_size <- as.integer(batch_size)

  # --- Resolve subject length bounds ------------------------------------------
  subject_len_range <- NULL
  if (!is.null(barcode_term) || !is.null(min_subject_length) ||
      !is.null(max_subject_length)) {
    subject_len_range <- TaxaTools::resolve_barcode_lengths(
      barcode_term, min_subject_length, max_subject_length
    )
    if (verbose)
      message(sprintf("Subject length filter: %d-%d bp",
                      subject_len_range[1L], subject_len_range[2L]))
  }

  # --- Run BLAST --------------------------------------------------------------
  if (method == "remote") {
    if (is.null(email))
      warning(
        "NCBI requires an email address for remote BLAST. ",
        "Set email = 'you@example.com' to comply with their usage policy."
      )
    raw_hits <- .blast_remote(
      seq_df, database, program, max_target_seqs, batch_size,
      email, ncbi_api_key, verbose
    )
  } else {
    raw_hits <- .blast_local(
      seq_df, database, program, max_target_seqs, verbose
    )
  }

  if (nrow(raw_hits) == 0L) {
    warning("BLAST returned no hits")
    return(.empty_blast_result(resolve_taxonomy))
  }

  if (verbose)
    message(sprintf("Raw BLAST hits: %d across %d queries",
                    nrow(raw_hits), length(unique(raw_hits$qseqid))))

  # --- Filter hits ------------------------------------------------------------
  filtered <- .filter_blast_hits(
    raw_hits, min_score, min_query_coverage,
    subject_len_range, score_range, max_hits, verbose
  )

  if (nrow(filtered) == 0L) {
    warning("All hits removed by filtering")
    return(.empty_blast_result(resolve_taxonomy))
  }

  # --- Resolve taxonomy -------------------------------------------------------
  if (resolve_taxonomy) {
    # Try taxid-based resolution first; fall back to accession-based lookup
    taxids <- character(0L)
    if ("staxids" %in% names(filtered)) {
      taxids <- unique(stats::na.omit(filtered$staxids))
      taxids <- unique(vapply(
        strsplit(as.character(taxids), ";"),
        `[`, character(1L), 1L
      ))
      taxids <- taxids[nchar(taxids) > 0L & taxids != "N/A"]
    }

    if (length(taxids) > 0L) {
      # Direct taxid resolution
      if (verbose) message(sprintf("Resolving taxonomy for %d unique taxids...", length(taxids)))
      tax_map <- .resolve_taxonomy(taxids, ncbi_api_key, verbose)
      filtered$taxid_join <- vapply(
        strsplit(as.character(filtered$staxids), ";"),
        `[`, character(1L), 1L
      )
      filtered <- merge(filtered, tax_map, by.x = "taxid_join", by.y = "taxid",
                        all.x = TRUE, sort = FALSE)
      filtered$taxid_join <- NULL
    } else {
      # No taxids available (e.g., from XML output) -- look up from accessions
      accessions <- unique(filtered$sacc)
      accessions <- accessions[!is.na(accessions) & nchar(accessions) > 0L]
      if (length(accessions) > 0L && verbose)
        message(sprintf("Looking up taxids for %d unique accessions...", length(accessions)))
      if (length(accessions) > 0L) {
        tax_map <- .resolve_taxonomy_from_accessions(accessions, ncbi_api_key, verbose)
        if (is.data.frame(tax_map) && nrow(tax_map) > 0L) {
          filtered <- merge(filtered, tax_map, by.x = "sacc", by.y = "accession",
                            all.x = TRUE, sort = FALSE)
        }
      }
    }
  }

  # --- Rename to TaxaMatch convention -----------------------------------------
  out <- data.frame(
    observation_id        = filtered$qseqid,
    accession        = if ("sacc" %in% names(filtered)) filtered$sacc else filtered$sseqid,
    score            = filtered$pident,
    evalue           = if ("evalue" %in% names(filtered)) filtered$evalue else NA_real_,
    bitscore         = if ("bitscore" %in% names(filtered)) filtered$bitscore else NA_real_,
    alignment_length = if ("length" %in% names(filtered)) filtered$length else NA_integer_,
    query_coverage   = if ("qcovs" %in% names(filtered)) filtered$qcovs else NA_real_,
    subject_length   = if ("slen" %in% names(filtered)) filtered$slen else NA_integer_,
    stringsAsFactors = FALSE
  )

  # Append taxonomy columns if present
  tax_cols <- TaxaTools::standard_ranks
  for (tc in tax_cols) {
    if (tc %in% names(filtered)) {
      out[[tc]] <- filtered[[tc]]
    }
  }

  rownames(out) <- NULL
  if (verbose)
    message(sprintf(
      "Final: %d hits across %d queries (%d unique taxa)",
      nrow(out), length(unique(out$observation_id)),
      length(unique(stats::na.omit(out$species)))
    ))

  # --- Attach report_params for report_match() --------------------------------
  attr(out, "report_params") <- list(
    method    = if (method == "remote") "remote BLAST" else "local BLAST",
    database  = database,
    min_score = min_score,
    n_samples = length(unique(out$observation_id))
  )

  out
}


# ==============================================================================
# Internal: Remote NCBI BLAST via URL API
# ==============================================================================

.blast_remote <- function(seq_df, database, program, max_target_seqs,
                          batch_size, email, ncbi_api_key, verbose) {
  if (!requireNamespace("httr2", quietly = TRUE))
    stop("Package 'httr2' is required for remote BLAST. Install with: install.packages('httr2')")

  base_url <- "https://blast.ncbi.nlm.nih.gov/blast/Blast.cgi"

  # Split sequences into batches
  n <- nrow(seq_df)
  batches <- split(seq_len(n), ceiling(seq_len(n) / batch_size))

  all_hits <- vector("list", length(batches))
  failed_batches <- integer(0)

  for (i in seq_along(batches)) {
    idx <- batches[[i]]
    batch_df <- seq_df[idx, ]

    # Build multi-FASTA query string
    fasta_lines <- paste0(">", batch_df$asv_id, "\n", batch_df$sequence)
    query_str <- paste(fasta_lines, collapse = "\n")

    if (verbose)
      message(sprintf("Submitting batch %d/%d (%d sequences)...",
                      i, length(batches), length(idx)))

    # --- Submit (PUT) ---------------------------------------------------------
    rid <- .blast_submit(base_url, query_str, database, program,
                         max_target_seqs, email, ncbi_api_key)

    if (is.null(rid)) {
      warning(sprintf("Batch %d/%d: BLAST submission failed. Skipping.", i, length(batches)))
      failed_batches <- c(failed_batches, i)
      next
    }

    if (verbose) message(sprintf("  RID: %s -- polling for results...", rid))

    # --- Poll (GET) -----------------------------------------------------------
    result_text <- .blast_poll(base_url, rid, verbose)

    if (is.null(result_text)) {
      warning(sprintf("Batch %d/%d: No results retrieved (RID: %s). Skipping.", i, length(batches), rid))
      failed_batches <- c(failed_batches, i)
      next
    }

    # --- Parse XML output -----------------------------------------------------
    hits <- .parse_blast_xml(result_text)
    if (!is.null(hits) && nrow(hits) > 0L) {
      all_hits[[i]] <- hits
    }

    # Rate limiting between batches
    if (i < length(batches)) {
      if (verbose) message("  Waiting 11 seconds (NCBI rate limit)...")
      Sys.sleep(11)
    }
  }

  if (length(failed_batches) > 0L) {
    warning(sprintf(
      "%d of %d BLAST batch(es) failed: %s. Results are incomplete.",
      length(failed_batches), length(batches),
      paste(failed_batches, collapse = ", ")
    ))
  }

  all_hits <- Filter(Negate(is.null), all_hits)
  if (length(all_hits) == 0L) return(.empty_raw_hits())
  result <- do.call(rbind, all_hits)
  attr(result, "failed_batches") <- if (length(failed_batches) > 0L) failed_batches else NULL
  result
}


#' @noRd
.blast_submit <- function(base_url, query, database, program,
                          max_target_seqs, email, ncbi_api_key) {
  # NCBI URL API: format params are ignored at submission time.
  # Only CMD, QUERY, DATABASE, PROGRAM, and search params matter here.
  params <- list(
    CMD            = "Put",
    QUERY          = query,
    DATABASE       = database,
    PROGRAM        = program,
    HITLIST_SIZE   = as.character(max_target_seqs)
  )
  if (!is.null(email)) params$EMAIL <- email
  if (!is.null(ncbi_api_key)) params$API_KEY <- ncbi_api_key

  for (attempt in 1:3) {
    tryCatch({
      req <- httr2::request(base_url) |>
        httr2::req_body_form(!!!params) |>
        httr2::req_timeout(120)
      resp <- httr2::req_perform(req)
      body <- httr2::resp_body_string(resp)

      # Extract RID from response
      rid_match <- regmatches(body, regexpr("RID = ([A-Z0-9-]+)", body))
      if (length(rid_match) == 1L) {
        return(sub("RID = ", "", rid_match))
      }
      warning("Could not extract RID from BLAST submission response")
      return(NULL)
    }, error = function(e) {
      if (attempt < 3L) {
        Sys.sleep(attempt * 5)
      } else {
        warning(sprintf("BLAST submission failed after 3 attempts: %s", e$message))
      }
    })
  }
  NULL
}


#' @noRd
.blast_poll <- function(base_url, rid, verbose, max_wait = 600) {
  # Polling timing follows NCBI BLAST URL API guidelines:
  # - Initial wait: 5s (NCBI recommends waiting before first status check)
  # - Backoff: multiply wait by 1.5 each cycle (exponential backoff)
  # - Max interval: 60s cap prevents excessively long pauses
  # - Max total: 600s (10 min) safety limit before declaring failure
  wait <- 5
  elapsed <- 0

  # First: check status only (no format params)
  while (elapsed < max_wait) {
    Sys.sleep(wait)
    elapsed <- elapsed + wait

    tryCatch({
      # Status check -- lightweight
      req <- httr2::request(base_url) |>
        httr2::req_url_query(
          CMD = "Get",
          RID = rid,
          FORMAT_OBJECT = "SearchInfo"
        ) |>
        httr2::req_timeout(60)
      resp <- httr2::req_perform(req)
      body <- httr2::resp_body_string(resp)

      if (grepl("Status=WAITING", body)) {
        if (verbose) message(sprintf("    Still waiting (%gs elapsed)...", elapsed))
        wait <- min(wait * 1.5, 60)
        next
      }

      if (grepl("Status=FAILED", body) || grepl("Status=UNKNOWN", body)) {
        warning(sprintf("BLAST search failed or expired (RID: %s)", rid))
        return(NULL)
      }

      if (grepl("Status=READY", body)) {
        if (verbose) message("    Results ready -- retrieving XML...")
        # Retrieve results as XML (most reliable format for URL API)
        result_req <- httr2::request(base_url) |>
          httr2::req_url_query(
            CMD = "Get",
            RID = rid,
            FORMAT_TYPE = "XML"
          ) |>
          httr2::req_timeout(300)
        result_resp <- httr2::req_perform(result_req)
        return(httr2::resp_body_string(result_resp))
      }

      # Unrecognised status -- log and continue polling
      if (verbose) message(sprintf("    Unexpected status (%gs elapsed). Retrying...", elapsed))
      wait <- min(wait * 1.5, 60)

    }, error = function(e) {
      if (verbose) message(sprintf("    Poll error: %s. Retrying...", e$message))
      wait <<- min(wait * 2, 60)
    })
  }

  warning(sprintf("BLAST search timed out after %d seconds (RID: %s)", max_wait, rid))
  NULL
}


#' @noRd
.parse_blast_xml <- function(xml_text) {
  # Parse NCBI BLAST XML output into a data frame matching .empty_raw_hits() schema
  if (!requireNamespace("xml2", quietly = TRUE))
    stop("Package 'xml2' is required for parsing BLAST XML output.")

  # Check for HTML status page instead of XML
  if (grepl("QBlastInfoBegin", xml_text) && !grepl("<BlastOutput>", xml_text)) {
    message("BLAST response is a status page, not XML results.")
    return(.empty_raw_hits())
  }

  doc <- tryCatch(xml2::read_xml(xml_text), error = function(e) {
    warning(sprintf("Failed to parse BLAST XML: %s", e$message))
    return(NULL)
  })
  if (is.null(doc)) return(.empty_raw_hits())

  # Each query is an <Iteration>; each hit is a <Hit> inside it
  iterations <- xml2::xml_find_all(doc, ".//Iteration")
  if (length(iterations) == 0L) return(.empty_raw_hits())

  # Batch extraction: collect all iteration-level and hit-level data using

  # vectorized xml_find_all + xml_text, avoiding per-hit XPath lookups.
  result_parts <- vector("list", length(iterations))

  for (it_i in seq_along(iterations)) {
    iter <- iterations[[it_i]]
    qdef <- xml2::xml_text(xml2::xml_find_first(iter, "./Iteration_query-def"))
    qlen_node <- xml2::xml_find_first(iter, "./Iteration_query-len")
    qlen <- if (!inherits(qlen_node, "xml_missing"))
      as.integer(xml2::xml_text(qlen_node)) else NA_integer_

    hits <- xml2::xml_find_all(iter, ".//Hit")
    n_hits <- length(hits)
    if (n_hits == 0L) next

    # Batch hit-level fields
    hit_accessions <- xml2::xml_text(xml2::xml_find_all(iter, ".//Hit/Hit_accession"))
    hit_ids        <- xml2::xml_text(xml2::xml_find_all(iter, ".//Hit/Hit_id"))
    hit_lens       <- as.integer(xml2::xml_text(xml2::xml_find_all(iter, ".//Hit/Hit_len")))

    # For HSP fields, extract first HSP per hit
    # Use per-hit loop (HSP nesting prevents fully flat extraction) but
    # minimise XPath calls with a local helper
    rows <- vector("list", n_hits)
    for (j in seq_len(n_hits)) {
      hsps <- xml2::xml_find_all(hits[[j]], ".//Hsp")
      if (length(hsps) == 0L) next
      hsp <- hsps[[1L]]

      .xt <- function(tag) xml2::xml_text(xml2::xml_find_first(hsp, tag))
      identity  <- as.numeric(.xt("./Hsp_identity"))
      align_len <- as.integer(.xt("./Hsp_align-len"))
      gaps      <- as.integer(.xt("./Hsp_gaps"))
      qfrom     <- as.integer(.xt("./Hsp_query-from"))
      qto       <- as.integer(.xt("./Hsp_query-to"))
      evalue    <- as.numeric(.xt("./Hsp_evalue"))
      bitscore  <- as.numeric(.xt("./Hsp_bit-score"))

      pident <- if (!is.na(identity) && !is.na(align_len) && align_len > 0L)
        round(100 * identity / align_len, 2) else NA_real_
      qcovs <- if (!is.na(qfrom) && !is.na(qto) && !is.na(qlen) && qlen > 0L)
        round(100 * abs(qto - qfrom + 1L) / qlen, 1) else NA_real_

      rows[[j]] <- data.frame(
        qseqid   = qdef,
        sseqid   = hit_ids[j],
        sacc     = hit_accessions[j],
        staxids  = NA_character_,
        pident   = pident,
        length   = align_len,
        slen     = hit_lens[j],
        qcovs    = qcovs,
        mismatch = NA_integer_,
        gapopen  = if (!is.na(gaps)) gaps else NA_integer_,
        evalue   = evalue,
        bitscore = bitscore,
        stringsAsFactors = FALSE
      )
    }
    result_parts[[it_i]] <- do.call(rbind, rows[lengths(rows) > 0L])
  }

  out <- do.call(rbind, result_parts[lengths(result_parts) > 0L])
  if (is.null(out) || nrow(out) == 0L) return(.empty_raw_hits())
  out
}


# ==============================================================================
# Internal: Local BLAST via rBLAST
# ==============================================================================

.blast_local <- function(seq_df, database, program, max_target_seqs, verbose) {
  if (!requireNamespace("rBLAST", quietly = TRUE))
    stop(
      "Package 'rBLAST' is required for local BLAST. ",
      "Install with: BiocManager::install('rBLAST')"
    )
  if (!requireNamespace("Biostrings", quietly = TRUE))
    stop(
      "Package 'Biostrings' is required for local BLAST. ",
      "Install with: BiocManager::install('Biostrings')"
    )

  # Create DNAStringSet from sequences
  dna <- Biostrings::DNAStringSet(seq_df$sequence)
  names(dna) <- seq_df$asv_id

  # Open BLAST database
  bl <- rBLAST::blast(db = database, type = program)

  # Custom output format for eDNA
  custom_format <- paste(
    "qseqid", "sseqid", "sacc", "staxids", "pident", "length",
    "qlen", "slen", "qcovs", "mismatch", "gapopen", "evalue", "bitscore",
    sep = " "
  )

  if (verbose) message(sprintf("Running local BLAST against %s...", database))

  hits <- stats::predict(bl, dna,
                  BLAST_args = sprintf(
                    "-max_target_seqs %d -outfmt '6 %s'",
                    max_target_seqs, custom_format
                  ))

  if (is.null(hits) || nrow(hits) == 0L) return(.empty_raw_hits())

  # Standardize column names (rBLAST returns named columns)
  expected_cols <- c("qseqid", "sseqid", "sacc", "staxids", "pident", "length",
                     "qlen", "slen", "qcovs", "mismatch", "gapopen", "evalue", "bitscore")

  if (ncol(hits) == length(expected_cols) && is.null(names(hits))) {
    names(hits) <- expected_cols
  }

  # Compute query coverage if not provided
  if ("qlen" %in% names(hits) && "qcovs" %in% names(hits)) {
    # qcovs from BLAST is already a percentage
  } else if ("qlen" %in% names(hits) && "length" %in% names(hits)) {
    hits$qcovs <- 100 * hits$length / hits$qlen
  }

  hits
}


# ==============================================================================
# Internal: Filter BLAST hits (score window + QC)
# ==============================================================================

.filter_blast_hits <- function(hits, min_score, min_query_coverage,
                               subject_len_range, score_range, max_hits,
                               verbose) {
  n_start <- nrow(hits)

  # 1. Minimum score
  hits <- hits[!is.na(hits$pident) & hits$pident >= min_score, ]

  # 2. Query coverage
  if ("qcovs" %in% names(hits) && !all(is.na(hits$qcovs))) {
    hits <- hits[is.na(hits$qcovs) | hits$qcovs >= min_query_coverage, ]
  }

  # 3. Subject length
  if (!is.null(subject_len_range) && "slen" %in% names(hits) &&
      !all(is.na(hits$slen))) {
    hits <- hits[
      is.na(hits$slen) |
        (hits$slen >= subject_len_range[1L] & hits$slen <= subject_len_range[2L]),
    ]
  }

  # 4. Score window: per query, keep hits within score_range of top hit
  if (nrow(hits) > 0L) {
    # Compute max pident per query
    max_scores <- stats::aggregate(pident ~ qseqid, data = hits, FUN = max)
    names(max_scores)[2L] <- "max_pident"
    hits <- merge(hits, max_scores, by = "qseqid", sort = FALSE)
    hits <- hits[hits$pident >= hits$max_pident - score_range, ]
    hits$max_pident <- NULL
  }

  # 5. Safety cap
  if (nrow(hits) > 0L) {
    hits <- do.call(rbind, lapply(split(hits, hits$qseqid), function(qhits) {
      qhits <- qhits[order(-qhits$pident), ]
      utils::head(qhits, max_hits)
    }))
    rownames(hits) <- NULL
  }

  if (verbose) {
    n_end <- nrow(hits)
    message(sprintf("Hit filtering: %d -> %d (removed %d)",
                    n_start, n_end, n_start - n_end))
  }

  hits
}


# ==============================================================================
# Internal: Resolve NCBI taxonomy IDs to full lineage
# ==============================================================================

#' @noRd
.resolve_taxonomy <- function(taxids, ncbi_api_key = NULL, verbose = TRUE) {
  if (!requireNamespace("rentrez", quietly = TRUE))
    stop("Package 'rentrez' is required for taxonomy resolution. ",
         "Install with: install.packages('rentrez')")
  if (!requireNamespace("xml2", quietly = TRUE))
    stop("Package 'xml2' is required for taxonomy resolution. ",
         "Install with: install.packages('xml2')")

  if (!is.null(ncbi_api_key))
    rentrez::set_entrez_key(ncbi_api_key)

  # Batch fetch taxonomy records
  batch_size <- 200L
  batches <- split(taxids, ceiling(seq_along(taxids) / batch_size))

  all_records <- vector("list", length(batches))

  for (i in seq_along(batches)) {
    batch <- batches[[i]]

    for (attempt in 1:3) {
      tryCatch({
        xml_text <- rentrez::entrez_fetch(
          db = "taxonomy",
          id = batch,
          rettype = "xml"
        )
        all_records[[i]] <- .parse_taxonomy_xml(xml_text)
        break
      }, error = function(e) {
        if (attempt < 3L) {
          Sys.sleep(attempt * 2)
        } else {
          warning(sprintf("Taxonomy fetch failed for batch %d: %s", i, e$message))
          all_records[[i]] <<- NULL
        }
      })
    }

    if (i < length(batches)) Sys.sleep(0.4)
  }

  all_records <- Filter(Negate(is.null), all_records)
  if (length(all_records) == 0L) {
    # Build empty data frame dynamically from standard ranks
    empty <- data.frame(taxid = character(), stringsAsFactors = FALSE)
    for (r in TaxaTools::standard_ranks) empty[[r]] <- character()
    return(empty)
  }

  do.call(rbind, all_records)
}


#' @noRd
.parse_taxonomy_xml <- function(xml_text) {
  doc <- xml2::read_xml(xml_text)
  taxa <- xml2::xml_find_all(doc, "/TaxaSet/Taxon")

  records <- lapply(taxa, function(taxon) {
    taxid <- xml2::xml_text(xml2::xml_find_first(taxon, "./TaxId"))
    sci_name <- xml2::xml_text(xml2::xml_find_first(taxon, "./ScientificName"))
    rank <- tolower(xml2::xml_text(xml2::xml_find_first(taxon, "./Rank")))

    # Get lineage from LineageEx
    lineage_nodes <- xml2::xml_find_all(taxon, ".//LineageEx/Taxon")
    lineage <- list()
    for (ln in lineage_nodes) {
      ln_rank <- tolower(xml2::xml_text(xml2::xml_find_first(ln, "./Rank")))
      ln_name <- xml2::xml_text(xml2::xml_find_first(ln, "./ScientificName"))
      lineage[[ln_rank]] <- ln_name
    }

    # The taxon itself may be at a rank we want
    if (rank %in% TaxaTools::standard_ranks) {
      lineage[[rank]] <- sci_name
    }

    # Build taxonomy row dynamically from standard ranks
    row <- data.frame(taxid = taxid, stringsAsFactors = FALSE)
    for (r in TaxaTools::standard_ranks) {
      if (r == "species" && is.null(lineage[["species"]]) && rank == "species") {
        row[[r]] <- sci_name
      } else {
        row[[r]] <- lineage[[r]] %||% NA_character_
      }
    }
    row
  })

  do.call(rbind, records)
}


# ==============================================================================
# Internal: Resolve taxonomy from accession numbers (when taxids unavailable)
# ==============================================================================

#' @noRd
.resolve_taxonomy_from_accessions <- function(accessions, ncbi_api_key = NULL,
                                               verbose = TRUE) {
  if (!requireNamespace("rentrez", quietly = TRUE))
    stop("Package 'rentrez' is required for taxonomy resolution.")
  if (!requireNamespace("xml2", quietly = TRUE))
    stop("Package 'xml2' is required for taxonomy resolution.")

  if (!is.null(ncbi_api_key))
    rentrez::set_entrez_key(ncbi_api_key)

  # Step 1: Look up taxids from accessions via nucleotide summary
  batch_size <- 100L
  batches <- split(accessions, ceiling(seq_along(accessions) / batch_size))
  acc_taxid_map <- list()

  for (i in seq_along(batches)) {
    batch <- batches[[i]]
    for (attempt in 1:3) {
      tryCatch({
        # Search nucleotide for these accessions
        ids <- rentrez::entrez_search(
          db = "nucleotide",
          term = paste(batch, "[ACCN]", collapse = " OR "),
          retmax = length(batch)
        )$ids

        if (length(ids) > 0L) {
          summaries <- rentrez::entrez_summary(db = "nucleotide", id = ids)
          if (inherits(summaries, "esummary")) summaries <- list(summaries)
          for (s in summaries) {
            acc <- s$caption
            taxid <- as.character(s$taxid)
            if (!is.null(acc) && !is.null(taxid)) {
              acc_taxid_map[[acc]] <- taxid
            }
          }
        }
        break
      }, error = function(e) {
        if (attempt < 3L) Sys.sleep(attempt * 2)
        else if (verbose)
          warning(sprintf("Accession lookup failed for batch %d: %s", i, e$message))
      })
    }
    if (i < length(batches)) Sys.sleep(0.4)
  }

  if (length(acc_taxid_map) == 0L) {
    return(data.frame(accession = character(), kingdom = character(),
                      phylum = character(), class = character(),
                      order = character(), family = character(),
                      genus = character(), species = character(),
                      stringsAsFactors = FALSE))
  }

  # Step 2: Resolve taxids to full taxonomy
  taxids <- unique(unlist(acc_taxid_map, use.names = FALSE))
  if (verbose) message(sprintf("Resolving taxonomy for %d unique taxids...", length(taxids)))
  tax_map <- .resolve_taxonomy(taxids, ncbi_api_key, verbose)

  if (is.null(tax_map) || nrow(tax_map) == 0L) {
    return(data.frame(accession = character(), kingdom = character(),
                      phylum = character(), class = character(),
                      order = character(), family = character(),
                      genus = character(), species = character(),
                      stringsAsFactors = FALSE))
  }

  # Step 3: Build accession -> taxonomy mapping
  acc_df <- data.frame(
    accession = names(acc_taxid_map),
    taxid = unlist(acc_taxid_map, use.names = FALSE),
    stringsAsFactors = FALSE
  )
  result <- merge(acc_df, tax_map, by = "taxid", all.x = TRUE, sort = FALSE)
  result$taxid <- NULL
  result
}


# ==============================================================================
#' @importFrom TaxaTools %||%
NULL


# ==============================================================================
# Internal: Empty result constructors
# ==============================================================================

#' @noRd
.empty_raw_hits <- function() {
  data.frame(
    qseqid = character(), sseqid = character(), sacc = character(),
    staxids = character(), pident = numeric(), length = integer(),
    slen = integer(), qcovs = numeric(),
    mismatch = integer(), gapopen = integer(),
    evalue = numeric(), bitscore = numeric(),
    stringsAsFactors = FALSE
  )
}

#' @noRd
.empty_blast_result <- function(with_taxonomy = FALSE) {
  df <- data.frame(
    observation_id = character(), accession = character(), score = numeric(),
    evalue = numeric(), bitscore = numeric(),
    alignment_length = integer(), query_coverage = numeric(),
    subject_length = integer(),
    stringsAsFactors = FALSE
  )
  if (with_taxonomy) {
    for (tc in TaxaTools::standard_ranks)
      df[[tc]] <- character()
  }
  df
}
