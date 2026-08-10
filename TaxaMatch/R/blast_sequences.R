# NSE column names referenced via non-standard evaluation below (the
# `pident ~ qseqid` formula interface to stats::aggregate() in
# .filter_blast_hits(), plus bare `$`-free references elsewhere in this
# file) would otherwise trip an R CMD CHECK "no visible binding" note.
utils::globalVariables(c("qseqid", "pident", "slen", "staxids", "max_pident"))

#' @importFrom TaxaTools %||%
NULL

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
#' @param megablast Logical. Default \code{FALSE}. Both the NCBI BLAST URL API
#'   (remote) and the standalone \code{blastn} binary (local, via \pkg{rBLAST})
#'   default an unqualified \code{program = "blastn"} search to MEGABLAST mode
#'   when this isn't set explicitly -- a fast, greedy algorithm tuned to find
#'   \emph{a} highly-similar hit quickly, not to exhaustively return every
#'   equally-good one. Confirmed on real data: a query with five reference
#'   sequences from one species and five from a second, genuinely tied at
#'   100\% identity over the full alignment, returned only a single hit from
#'   one species and none from the other under the implicit (megablast)
#'   default -- silently dropping a real, exactly-tied congener before
#'   \code{score_range} filtering ever had a chance to keep it. Set
#'   \code{TRUE} to restore the old implicit (unspecified/megablast) behavior
#'   for speed on very large batches; \code{FALSE} (classic blastn) is slower
#'   but the only mode confirmed to return every near-identical reference,
#'   which is what \code{score_range}'s own tie-detection depends on.
#' @param score_range Numeric. Keep all hits within this many percent identity
#'   points of each query's top hit (default \code{8}, widened from an
#'   earlier default of \code{2} -- see "Score window validation" below).
#'   For example, if the top hit is 99% identity, all hits at 91% or above
#'   are retained. Wider ranges capture more taxonomic alternatives; narrower
#'   ranges (e.g., 2) focus on the closest matches only but risk silently
#'   dropping the true species when a congener happens to score higher (see
#'   Details).
#' @param max_hits Integer. Safety cap: maximum hits to retain per query after
#'   score window filtering (default \code{20L}). Increase for queries
#'   expected to match many closely related species.
#' @param max_hits_per_taxon Integer or \code{NULL} (default). When set, caps
#'   the number of hits retained per taxon \emph{before} \code{max_hits} is
#'   applied. Without this, one heavily-resequenced species -- e.g. a genus
#'   with many independently deposited mitogenomes of the same well-studied
#'   species -- can consume the entire \code{max_hits} budget with redundant
#'   near-duplicate hits, silently crowding out a real, different congener
#'   that would otherwise have survived \code{score_range} filtering. Each
#'   taxon's own best-scoring hit is always kept, so this never changes which
#'   taxon has the top score. Set to e.g. \code{3L} to keep at most 3
#'   representative hits per species.
#'
#'   \strong{Requires \code{resolve_taxonomy = TRUE} to have any effect on
#'   remote BLAST results.} Remote BLAST's XML output never populates a real
#'   per-hit taxid (\code{staxids} is always \code{NA} there), so grouping
#'   would otherwise be a silent no-op -- every hit would land in its own
#'   singleton group. When both are set, taxonomy is resolved once, early
#'   (on the min_score/coverage/length survivors, before this cap and
#'   \code{max_hits} run) specifically so grouping can use the real resolved
#'   species/genus name; the normal end-of-pipeline taxonomy resolution step
#'   is skipped since it's already done. This does mean more NCBI taxonomy
#'   lookups than the \code{resolve_taxonomy = TRUE} default alone (resolved
#'   on the larger pre-\code{max_hits} set, not the smaller final one) -- a
#'   real cost, only incurred when \code{max_hits_per_taxon} is actually
#'   requested. With \code{resolve_taxonomy = FALSE}, this falls back to
#'   grouping by \code{staxids} (a no-op for remote results, same as before
#'   this parameter existed) -- local BLAST via \pkg{rBLAST} does supply
#'   real \code{staxids} directly from its own database's taxonomy mapping,
#'   so this fallback is only inert for the remote path.
#' @param min_score Numeric. Discard hits below this percent identity
#'   (default \code{70}). The 70% threshold is a conventional cross-genus
#'   floor for DNA barcoding; most true species-level matches exceed 95%.
#' @param min_query_coverage Numeric. Discard hits where less than this
#'   percentage of the query sequence aligned (default \code{80}). Standard
#'   BLAST quality filter; ensures hits span most of the barcode region.
#' @param barcode_term Character. Barcode marker name for auto-detecting the
#'   expected amplicon length bounds (e.g., \code{"12S"}, \code{"COI"}).
#'   Default \code{NULL}.
#' @param min_subject_length Integer. Minimum length, in bp, of the
#'   \emph{aligned region} against the reference (not the reference
#'   accession's own total sequence length -- see Details). Overrides
#'   \code{barcode_term}. Default \code{NULL}.
#' @param max_subject_length Integer. Maximum length, in bp, of the aligned
#'   region against the reference. Overrides \code{barcode_term}. Default
#'   \code{NULL}.
#' @param max_target_seqs Integer. Number of hits to request from BLAST before
#'   client-side filtering (default \code{100L}). Should be generous (larger
#'   than \code{max_hits}) since NCBI's default is 500. Set higher (e.g., 500)
#'   for comprehensive searches; lower for speed.
#' @param batch_size Integer. For remote BLAST, number of sequences per
#'   submission (default \code{20L}). Larger batches reduce API overhead but
#'   risk timeout on NCBI's server. NCBI handles multi-FASTA queries.
#' @param email Character. Email address sent to NCBI (required by their usage
#'   policy for remote BLAST). Defaults to the \code{NCBI_EMAIL} environment
#'   variable (unset by default); a \code{warning()} is issued for remote
#'   BLAST when neither is available.
#' @param ncbi_api_key Character. Optional NCBI API key for higher rate
#'   limits. Defaults to the \code{NCBI_API_KEY} environment variable (unset
#'   by default).
#' @param resolve_taxonomy Logical. If \code{TRUE} (default), resolve NCBI
#'   taxonomy IDs to full lineage (kingdom through species) and append taxonomy
#'   columns to the output.
#' @param resolve_location Logical. Default \code{FALSE}. If \code{TRUE},
#'   fetch each unique hit accession's full GenBank record (a real, separate
#'   NCBI round trip -- not free) and append \code{lat}/\code{lon}/
#'   \code{country} columns parsed from the record's \code{source} feature
#'   \code{lat_lon}/\code{country} qualifiers. \code{NA} where the record has
#'   no collection-location metadata. Independent of \code{resolve_taxonomy}
#'   -- taxonomy comes from the NCBI taxonomy database, location from the
#'   full nucleotide record; neither fetch gives you the other.
#' @param poll_max_wait Numeric. Remote BLAST only. Seconds to keep polling
#'   NCBI for a submitted batch's results before giving up on it (default
#'   \code{1800}, i.e. 30 minutes). Raised from an earlier hardcoded
#'   \code{600} (2026-08-09) after a real, large (1,183-accession) remote-
#'   BLAST run observed sustained per-batch queue waits exceeding 600s.
#'   A batch that still exceeds this window (even after the existing
#'   halved-batch-size retry), OR that NCBI reports \code{Status=READY} for
#'   but has actually aborted server-side for exceeding a CPU-time fair-use
#'   budget (see \code{.blast_server_rejected()}'s own documentation for the
#'   real captured case that found this -- a real, distinct failure mode
#'   from a poll timeout, since NCBI returns a genuine, successfully-
#'   retrieved XML document, just one recording a rejection instead of real
#'   search results), is recorded in \code{attr(result, "failed_query_ids")}
#'   -- the affected \code{asv_id}s, so a caller can tell "search never
#'   completed or was rejected" apart from "search completed and found
#'   nothing," which \code{evaluate_reference_accessions()} uses to avoid
#'   caching a failed batch's accessions as if they were a real verdict.
#'   Neither failure mode is fixable by raising this parameter alone --
#'   a CPU-budget rejection means NCBI is actively throttling this IP
#'   address's remote-BLAST usage; the real remedy is fewer/smaller/less
#'   frequent real calls (or \code{method = "local"} for a large batch job),
#'   not a longer wait.
#' @param verbose Logical. Print progress messages. Default \code{TRUE}.
#'
#' @return A data frame with one row per query x hit, containing:
#'   \describe{
#'     \item{observation_id}{Query identifier (from \code{asv_id})}
#'     \item{accession}{Subject accession}
#'     \item{score}{Percent identity (0-100 scale), computed as
#'       \code{round(100 * identity / align_len, 2)} from HSP fields (the
#'       standard NCBI definition). This is \emph{alignment} identity over
#'       the aligned region, not sequence identity over the full query
#'       length. For multi-HSP alignments only the highest-scoring HSP is
#'       used, which may under- or over-estimate true coverage for
#'       fragmented/chimeric reads.}
#'     \item{evalue}{E-value}
#'     \item{bitscore}{Bit score}
#'     \item{alignment_length}{Alignment length}
#'     \item{query_coverage}{Percent of query aligned}
#'     \item{subject_length}{Subject sequence length}
#'     \item{subject_start, subject_end}{Where within the subject/reference
#'       sequence this hit's alignment falls (1-based, BLAST tabular
#'       convention -- \code{subject_start > subject_end} on the minus
#'       strand; use \code{pmin()}/\code{pmax()} for a directionless span).
#'       Distinct from \code{subject_length} (the reference's TOTAL length):
#'       lets a downstream consumer tell whether two hits against the SAME
#'       long subject (e.g. a complete mitogenome) actually cover the same
#'       genomic region or two unrelated ones -- see
#'       \code{TaxaLikely::restore_suppressed_candidates(check_regional_overlap
#'       = TRUE)}.}
#'   }
#'   If \code{resolve_taxonomy = TRUE}, taxonomy columns (\code{kingdom},
#'   \code{phylum}, \code{class}, \code{order}, \code{family}, \code{genus},
#'   \code{species}) are appended. If \code{resolve_location = TRUE},
#'   \code{lat}, \code{lon}, and \code{country} columns are appended.
#'
#'   This output is ready for \code{\link{standardize_match_data}}.
#'
#'   An \code{attr(out, "report_params")} list (\code{method}, \code{database},
#'   \code{min_score}, \code{n_samples}) is also attached, consumed by
#'   \code{\link{report_match}}.
#'
#'   \code{attr(out, "failed_query_ids")} (character vector, \code{NULL} if
#'   none) -- remote BLAST only, added 2026-08-09: \code{asv_id}s whose
#'   search never completed (submission or poll failure, even after the
#'   automatic halved-batch-size retry) -- distinct from a query that
#'   completed and genuinely found nothing, which simply has no rows in
#'   \code{out} at all. Present regardless of which return path this
#'   function takes, including every early-return-on-empty-result branch.
#'   See \code{poll_max_wait}'s own documentation.
#'
#' @details
#' ## Score window algorithm
#'
#' Rather than a flat top-N cutoff, hits are filtered per query:
#' \enumerate{
#'   \item All hits below \code{min_score} are removed
#'   \item Hits with query coverage below \code{min_query_coverage} are removed
#'   \item Hits whose \emph{aligned region} falls outside the barcode length
#'     range are removed (see "Subject length filter" below)
#'   \item For each query, the top hit's percent identity is found
#'   \item All hits within \code{score_range} of the top hit are retained
#'   \item A \code{max_hits} safety cap is applied per query
#' }
#'
#' This means a clear top match may return only 1-3 hits (the rest are too
#' distant), while an ambiguous query retains all plausible candidates.
#'
#' ## Subject length filter
#'
#' This step checks the length of the \strong{aligned region} (the BLAST
#' \code{length} field), not the reference accession's own total sequence
#' length. Confirmed as a real, not cosmetic, distinction on real Great Lakes
#' Ameiurus (bullhead catfish) data: a query's raw BLAST hits included two
#' \emph{Ameiurus melas} references at 100\% identity and 100\% query
#' coverage over the full amplicon -- a genuine, exactly-tied congener match
#' -- but both were deposited as long mitogenome/partial-genome records
#' (672bp and 960bp), so checking the \emph{subject's own length} against a
#' ~130-210bp MiFish window discarded them entirely, leaving only a single
#' \emph{A. nebulosus} hit (a short, standalone 172bp barcode submission)
#' that happened to be the only reference short enough to survive -- not
#' because it was the best match, but because it was the only
#' correctly-sized \emph{record}. The aligned region itself, in every one of
#' these mitogenome-embedded hits, was the correct barcode window (full
#' query length, 100\% coverage) -- exactly the case this filter should
#' retain, not the "wrong genomic region of the same gene" case
#' (\code{TaxaLikely}'s documented "Paralabrax footgun") it exists to catch.
#' Checking aligned length rather than raw subject length fixes this while
#' still catching genuinely off-target hits (a poor, partial, non-amplicon
#' overlap is already excluded by \code{min_query_coverage} before this step
#' ever runs).
#'
#' ## Score window validation
#'
#' This filter decides which candidates ever reach TaxaLikely/TaxaAssign --
#' a true species dropped here cannot be recovered downstream, no matter how
#' good the likelihood model is. The original \code{score_range = 2} default
#' was field-tested only on 5 easy PtConception queries with clear top hits
#' at 98% identity or above; it was never stress-tested against a
#' taxonomically dense genus where real congeneric divergence can be tight.
#'
#' A leave-one-out check (\code{diagnostics/score_window_leave_one_out.R} at
#' the TaxaID root) against three independent real reference-vs-reference
#' distance matrices found this risk is real, not hypothetical: treating each
#' reference sequence as a query against every other sequence in the same
#' matrix, and asking how often a congener outscores the sequence's own true
#' species, and by how much --
#' \itemize{
#'   \item \strong{Sebastes} (54 species, real MiFish-window 12S data):
#'     3/113 (2.7\%) queries had a congener score higher than the true
#'     species, but only by 0.6 points each -- none would have been dropped
#'     even at the old \code{score_range = 2} default.
#'   \item \strong{Chromis} (26 species): 3/33 (9.1\%) queries had this
#'     happen, by 4.7-7.1 points -- \emph{all three} would have been
#'     silently dropped at \code{score_range = 2}.
#'   \item \strong{A real 6-genus PtConception 12S set} (Clinocottus,
#'     Gibbonsia, Oligocottus, Embiotoca, Phanerodon): 1/11 (9.1\%) queries,
#'     by 2.5 points -- would also have been dropped at the old default.
#' }
#' Pooling all three: 4 of 7 real congener-outscoring events (57\%) exceeded
#' the old \code{score_range = 2} default and would have silently excluded
#' the true species from every downstream step. The new default (\code{8})
#' comfortably covers every gap actually observed in this check (worst case
#' 7.1 points); it is an evidence-backed starting point given what has
#' been measured so far, not a guarantee no real dataset will ever exceed it
#' -- \code{max_hits} (default 20) bounds the resulting candidate count
#' regardless of how wide \code{score_range} is set, and a wider window is
#' precisely what preserves the "gap" feature
#' (\code{TaxaLikely::train_likelihood_model()}'s own key discriminator
#' between H1/H2/H3) for the bivariate-normal model to actually use --
#' dropping the true congener here removes the one signal that model needs
#' to correctly flag a genuinely ambiguous call instead of confidently
#' returning the wrong species.
#'
#' ## Remote BLAST
#'
#' Uses the NCBI BLAST URL API with proper rate limiting (minimum 10 seconds
#' between submissions). Sequences are submitted in batches of
#' \code{batch_size}. The function polls for results with exponential backoff.
#' An \code{email} is required by NCBI usage policy. Remote BLAST results can
#' vary over time as the NCBI \code{nt} database is updated; for
#' reproducibility, consider recording the query date (or a specific database
#' version, retrievable via NCBI Entrez) alongside results used in scientific
#' workflows.
#'
#' \code{max_target_seqs} does not guarantee the best-scoring hits are
#' returned first -- NCBI's BLAST truncates its internal hit list before
#' scoring is complete (Shah et al. 2018, \emph{Bioinformatics}), so a low
#' value can cause the true top hit to be missed. The default (\code{100L})
#' is reasonable for most barcode-length queries; raise it for taxonomically
#' dense searches.
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
                            megablast = FALSE,
                            score_range = 8,
                            max_hits = 20L,
                            max_hits_per_taxon = NULL,
                            min_score = 70,
                            min_query_coverage = 80,
                            barcode_term = NULL,
                            min_subject_length = NULL,
                            max_subject_length = NULL,
                            max_target_seqs = 100L,
                            batch_size = 20L,
                            email = Sys.getenv("NCBI_EMAIL", unset = ""),
                            ncbi_api_key = Sys.getenv("NCBI_API_KEY", unset = ""),
                            resolve_taxonomy = TRUE,
                            resolve_location = FALSE,
                            poll_max_wait = 1800,
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
    stop(sprintf(
      "seq_df has %d row(s) with empty or NA sequence. Remove before calling blast_sequences().",
      sum(na_seq)))

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
  if (!is.null(max_hits_per_taxon) &&
      (!is.numeric(max_hits_per_taxon) || length(max_hits_per_taxon) != 1L ||
       is.na(max_hits_per_taxon) || max_hits_per_taxon < 1L))
    stop("max_hits_per_taxon must be NULL or a positive integer")
  if (!is.numeric(min_score) || length(min_score) != 1L || is.na(min_score))
    stop("min_score must be a single numeric value")
  if (!is.numeric(min_query_coverage) || length(min_query_coverage) != 1L ||
      is.na(min_query_coverage))
    stop("min_query_coverage must be a single numeric value")
  if (!is.logical(megablast) || length(megablast) != 1L || is.na(megablast))
    stop("megablast must be TRUE or FALSE")
  if (!is.logical(resolve_taxonomy) || length(resolve_taxonomy) != 1L ||
      is.na(resolve_taxonomy))
    stop("resolve_taxonomy must be TRUE or FALSE")
  if (!is.logical(resolve_location) || length(resolve_location) != 1L ||
      is.na(resolve_location))
    stop("resolve_location must be TRUE or FALSE")
  if (!is.numeric(max_target_seqs) || length(max_target_seqs) != 1L ||
      is.na(max_target_seqs) || max_target_seqs < 1L)
    stop("max_target_seqs must be a positive integer")
  if (!is.numeric(batch_size) || length(batch_size) != 1L ||
      is.na(batch_size) || batch_size < 1L)
    stop("batch_size must be a positive integer")

  # Empty-string env-var defaults (email/ncbi_api_key) mean "not supplied".
  if (identical(email, "")) email <- NULL
  if (identical(ncbi_api_key, "")) ncbi_api_key <- NULL

  max_hits <- as.integer(max_hits)
  if (!is.null(max_hits_per_taxon)) max_hits_per_taxon <- as.integer(max_hits_per_taxon)
  max_target_seqs <- as.integer(max_target_seqs)
  batch_size <- as.integer(batch_size)

  if (max_target_seqs < max_hits)
    warning(sprintf(
      paste0(
        "max_target_seqs (%d) is smaller than max_hits (%d); BLAST will ",
        "never return enough hits per query to reach the max_hits cap. ",
        "Consider raising max_target_seqs."
      ),
      max_target_seqs, max_hits
    ))

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
      seq_df, database, program, megablast, max_target_seqs, batch_size,
      email, ncbi_api_key, verbose, max_wait = poll_max_wait
    )
  } else {
    raw_hits <- .blast_local(
      seq_df, database, program, megablast, max_target_seqs, verbose
    )
  }

  # Captured here, before raw_hits is filtered/rebuilt into an entirely new
  # data frame below (attr() does not survive that reconstruction) --
  # re-attached to whatever this function ultimately returns, including
  # every early-return branch, so a caller can always tell "these specific
  # queries' BLAST search never completed" apart from "completed and found
  # nothing" -- see poll_max_wait's own documentation for why this matters.
  failed_query_ids <- attr(raw_hits, "failed_query_ids")

  if (nrow(raw_hits) == 0L) {
    warning("BLAST returned no hits")
    empty <- .empty_blast_result(resolve_taxonomy)
    attr(empty, "failed_query_ids") <- failed_query_ids
    return(empty)
  }

  if (verbose)
    message(sprintf("Raw BLAST hits: %d across %d queries",
                    nrow(raw_hits), length(unique(raw_hits$qseqid))))

  # --- Filter hits ------------------------------------------------------------
  taxonomy_already_attached <- FALSE

  if (!is.null(max_hits_per_taxon) && isTRUE(resolve_taxonomy)) {
    # max_hits_per_taxon needs real species/genus names to group hits by --
    # remote BLAST's XML output never populates a real per-hit taxid
    # (staxids is always NA_character_ there; see .parse_blast_xml()), so
    # grouping by staxids alone would silently be a no-op for the remote
    # path (the one this ecosystem actually uses). Resolve taxonomy on the
    # min_score/coverage/length survivors BEFORE the per-taxon cap and
    # max_hits truncation run, so capping groups by a real resolved name
    # instead. Only done when resolve_taxonomy = TRUE -- with it FALSE,
    # max_hits_per_taxon falls back to grouping by staxids (a no-op for
    # remote results), same as before this feature existed.
    basic <- .filter_blast_hits(
      raw_hits, min_score, min_query_coverage, subject_len_range,
      score_range, max_hits, verbose = verbose, stage = "basic"
    )

    if (nrow(basic) == 0L) {
      warning("All hits removed by filtering")
      empty <- .empty_blast_result(resolve_taxonomy)
      attr(empty, "failed_query_ids") <- failed_query_ids
      return(empty)
    }

    basic <- .attach_taxonomy(basic, ncbi_api_key, verbose)

    sp <- if ("species" %in% names(basic)) basic$species else rep(NA_character_, nrow(basic))
    ge <- if ("genus"   %in% names(basic)) basic$genus   else rep(NA_character_, nrow(basic))
    st <- if ("staxids" %in% names(basic)) basic$staxids else rep(NA_character_, nrow(basic))
    basic$.taxon_group <- ifelse(
      !is.na(sp) & nzchar(sp), sp,
      ifelse(!is.na(ge) & nzchar(ge), ge,
             ifelse(!is.na(st) & nzchar(st), st,
                    paste0("__unresolved_", seq_len(nrow(basic))))))

    filtered <- .filter_blast_hits(
      basic, min_score, min_query_coverage, subject_len_range,
      score_range, max_hits, max_hits_per_taxon,
      taxon_group_col = ".taxon_group", stage = "rest", verbose = verbose
    )
    if (".taxon_group" %in% names(filtered)) filtered$.taxon_group <- NULL
    taxonomy_already_attached <- TRUE
  } else {
    filtered <- .filter_blast_hits(
      raw_hits, min_score, min_query_coverage,
      subject_len_range, score_range, max_hits, max_hits_per_taxon,
      verbose = verbose
    )
  }

  if (nrow(filtered) == 0L) {
    warning("All hits removed by filtering")
    empty <- .empty_blast_result(resolve_taxonomy)
    attr(empty, "failed_query_ids") <- failed_query_ids
    return(empty)
  }

  # --- Resolve taxonomy -------------------------------------------------------
  if (resolve_taxonomy && !taxonomy_already_attached) {
    filtered <- .attach_taxonomy(filtered, ncbi_api_key, verbose)
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
    # Where within the subject/reference sequence this hit's alignment
    # actually falls -- distinct from subject_length (the reference's TOTAL
    # length). Needed to tell whether two hits against the same long subject
    # (e.g. a complete mitogenome) cover the same region or two unrelated
    # ones. subject_start/subject_end are not normalized for strand
    # (subject_start > subject_end on the minus strand, matching raw BLAST
    # tabular convention) -- a consumer needing a directionless span should
    # use pmin()/pmax() on them.
    subject_start    = if ("sstart" %in% names(filtered)) filtered$sstart else NA_integer_,
    subject_end      = if ("send" %in% names(filtered)) filtered$send else NA_integer_,
    stringsAsFactors = FALSE
  )

  # Append taxonomy columns if present
  tax_cols <- TaxaTools::standard_ranks
  for (tc in tax_cols) {
    if (tc %in% names(filtered)) {
      out[[tc]] <- filtered[[tc]]
    }
  }

  # --- Resolve collection location (lat/lon/country) if requested ------------
  if (resolve_location) {
    accessions <- unique(out$accession)
    accessions <- accessions[!is.na(accessions) & nchar(accessions) > 0L]
    if (length(accessions) > 0L) {
      if (verbose)
        message(sprintf("Resolving location metadata for %d unique accessions...",
                        length(accessions)))
      loc_map <- .resolve_locations_by_acc(accessions, ncbi_api_key, verbose)
      # Version-suffix-stripped join key on both sides -- GBSeq_primary-accession
      # is already version-free, but out$accession/BLAST's sacc is not guaranteed
      # to be, so this is defensive rather than load-bearing.
      if (is.data.frame(loc_map) && nrow(loc_map) > 0L) {
        out$.join_acc <- sub("\\.[0-9]+$", "", out$accession)
        loc_map$.join_acc <- sub("\\.[0-9]+$", "", loc_map$accession)
        loc_map$accession <- NULL
        out <- merge(out, loc_map, by = ".join_acc", all.x = TRUE, sort = FALSE)
        out$.join_acc <- NULL
      } else {
        out$lat     <- NA_real_
        out$lon     <- NA_real_
        out$country <- NA_character_
      }
    } else {
      out$lat     <- NA_real_
      out$lon     <- NA_real_
      out$country <- NA_character_
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
  attr(out, "failed_query_ids") <- failed_query_ids

  out
}


# ==============================================================================
# Internal: Remote NCBI BLAST via URL API
# ==============================================================================

.blast_remote <- function(seq_df, database, program, megablast, max_target_seqs,
                          batch_size, email, ncbi_api_key, verbose, entrez_query = NULL,
                          max_wait = 1800) {
  .check_pkg("httr2")

  base_url <- "https://blast.ncbi.nlm.nih.gov/blast/Blast.cgi"

  # Split sequences into batches
  n <- nrow(seq_df)
  batches <- split(seq_len(n), ceiling(seq_len(n) / batch_size))

  all_hits <- vector("list", length(batches))
  failed_batches <- integer(0)
  failed_query_ids <- character(0)

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
    rid <- .blast_submit(base_url, query_str, database, program, megablast,
                         max_target_seqs, email, ncbi_api_key, entrez_query)

    if (is.null(rid)) {
      warning(sprintf("Batch %d/%d: BLAST submission failed. Skipping.", i, length(batches)))
      failed_batches <- c(failed_batches, i)
      next
    }

    if (verbose) message(sprintf("  RID: %s -- polling for results...", rid))

    # --- Poll (GET) -----------------------------------------------------------
    result_text <- .blast_poll(base_url, rid, verbose, max_wait = max_wait)

    if (is.null(result_text)) {
      warning(sprintf("Batch %d/%d: No results retrieved (RID: %s). Skipping.", i, length(batches), rid))
      failed_batches <- c(failed_batches, i)
      next
    }

    # NCBI can report Status=READY (a real, successfully-retrieved XML
    # document) while having aborted the actual computation server-side for
    # exceeding a CPU-time fair-use budget -- see .blast_server_rejected()'s
    # own documentation for the real case that found this. Treated as a
    # batch failure (same as a poll timeout), not "searched, found nothing".
    if (.blast_server_rejected(result_text)) {
      warning(sprintf(
        "Batch %d/%d: NCBI rejected this search for exceeding its server CPU budget (RID: %s). Skipping.",
        i, length(batches), rid
      ))
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

  # --- Retry failed batches with halved batch size ----------------------------
  # NCBI poll timeouts are the most common failure mode for large batches.
  # Re-submitting with fewer sequences per batch reduces the server-side
  # processing time and avoids the 10-minute poll ceiling.
  if (length(failed_batches) > 0L) {
    retry_batch_size <- max(1L, batch_size %/% 2L)
    if (verbose)
      message(sprintf(
        "  Retrying %d failed batch(es) with batch_size = %d...",
        length(failed_batches), retry_batch_size
      ))

    still_failed <- integer(0)
    still_failed_ids <- character(0)

    for (fi in failed_batches) {
      retry_rows <- seq_df[batches[[fi]], ]
      retry_batches <- split(
        seq_len(nrow(retry_rows)),
        ceiling(seq_len(nrow(retry_rows)) / retry_batch_size)
      )

      for (ri in seq_along(retry_batches)) {
        rb_df <- retry_rows[retry_batches[[ri]], ]
        fasta_lines <- paste0(">", rb_df$asv_id, "\n", rb_df$sequence)
        query_str <- paste(fasta_lines, collapse = "\n")

        if (verbose)
          message(sprintf(
            "  Retry batch %d.%d (%d sequences)...",
            fi, ri, nrow(rb_df)
          ))

        Sys.sleep(11)  # rate-limit before retry submission
        rid <- .blast_submit(base_url, query_str, database, program, megablast,
                             max_target_seqs, email, ncbi_api_key, entrez_query)

        if (is.null(rid)) {
          if (verbose)
            message(sprintf("    Retry batch %d.%d: submission failed.", fi, ri))
          still_failed <- c(still_failed, fi)
          still_failed_ids <- c(still_failed_ids, rb_df$asv_id)
          next
        }

        if (verbose) message(sprintf("    RID: %s -- polling...", rid))
        result_text <- .blast_poll(base_url, rid, verbose, max_wait = max_wait)

        if (is.null(result_text)) {
          if (verbose)
            message(sprintf("    Retry batch %d.%d: poll timed out.", fi, ri))
          still_failed <- c(still_failed, fi)
          still_failed_ids <- c(still_failed_ids, rb_df$asv_id)
          next
        }

        if (.blast_server_rejected(result_text)) {
          if (verbose)
            message(sprintf("    Retry batch %d.%d: NCBI rejected this search (server CPU budget).", fi, ri))
          still_failed <- c(still_failed, fi)
          still_failed_ids <- c(still_failed_ids, rb_df$asv_id)
          next
        }

        hits <- .parse_blast_xml(result_text)
        if (!is.null(hits) && nrow(hits) > 0L)
          all_hits <- c(all_hits, list(hits))
      }
    }

    failed_batches <- unique(still_failed)
    failed_query_ids <- unique(still_failed_ids)
  }

  if (length(failed_batches) > 0L) {
    warning(sprintf(
      "%d of %d original BLAST batch(es) could not be recovered: batches %s. ",
      length(failed_batches), length(batches),
      paste(failed_batches, collapse = ", ")
    ))
  }

  all_hits <- Filter(Negate(is.null), all_hits)
  result <- if (length(all_hits) == 0L) .empty_raw_hits() else do.call(rbind, all_hits)
  attr(result, "failed_batches") <- if (length(failed_batches) > 0L) failed_batches else NULL
  attr(result, "failed_query_ids") <- if (length(failed_query_ids) > 0L) failed_query_ids else NULL
  result
}


#' @noRd
.blast_submit <- function(base_url, query, database, program, megablast,
                          max_target_seqs, email, ncbi_api_key, entrez_query = NULL) {
  # NCBI URL API: format params are ignored at submission time.
  # Only CMD, QUERY, DATABASE, PROGRAM, and search params matter here.
  # MEGABLAST is set explicitly (on/off) rather than left unspecified -- an
  # unqualified PROGRAM = "blastn" submission defaults to megablast mode,
  # which can silently return only one of several genuinely tied top hits
  # (see blast_sequences()'s own `megablast` param documentation).
  # ENTREZ_QUERY (when supplied) restricts the search SPACE itself to
  # records matching that Entrez query (e.g. a small, specific accession
  # OR-list, `"ACC1[ACCN] OR ACC2[ACCN]"`) -- BLAST then computes a real
  # alignment against every matching record, not just whatever happens to
  # rank among the top hits of an otherwise-unrestricted search. See
  # `.blast_against_comparison_set()` (`R/investigate_flagged_accession.R`)
  # for why this matters: a post-hoc top-N-then-filter approach was tried
  # first and found live (2026-08-08, real MZ605481 case) to return ZERO
  # matches even for accessions independently confirmed to exist, because
  # the candidate accessions simply never appeared in the unrestricted
  # top-max_target_seqs hit list.
  params <- list(
    CMD            = "Put",
    QUERY          = query,
    DATABASE       = database,
    PROGRAM        = program,
    MEGABLAST      = if (isTRUE(megablast)) "on" else "off",
    HITLIST_SIZE   = as.character(max_target_seqs)
  )
  if (!is.null(entrez_query) && nzchar(entrez_query)) params$ENTREZ_QUERY <- entrez_query
  if (!is.null(email)) params$EMAIL <- email
  if (!is.null(ncbi_api_key)) params$API_KEY <- ncbi_api_key

  for (attempt in 1:3) {
    tryCatch({
      req <- do.call(
        httr2::req_body_form,
        c(list(httr2::request(base_url)), params)
      ) |>
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

#' Detect NCBI's server-side CPU-usage-limit rejection
#'
#' Found 2026-08-09 on a real, large (1,183-accession) remote-BLAST run:
#' NCBI's remote BLAST service can report a batch's search as
#' \code{Status=READY} (a real, successfully-retrieved XML document, not a
#' poll timeout) while having actually ABORTED the computation server-side
#' for exceeding a CPU-time fair-use budget -- confirmed via a real captured
#' response for a 20-query batch of mostly full-mitogenome-length sequences
#' (16.5kb each) against \code{nt}, every \code{<Iteration>} carrying two
#' \code{<Iteration_message>} entries: \code{"Searches from this IP address
#' have consumed a large amount of server CPU time..."} and
#' \code{"[blastsrv4.REAL]: Error: CPU usage limit was exceeded, resulting
#' in SIGXCPU (24)."}. \code{.parse_blast_xml()} never checked
#' \code{Iteration_message} at all -- a rejected batch silently parsed to
#' zero hit rows, indistinguishable from a real "searched everything,
#' found nothing" result, and (before this fix) would have been cached by
#' \code{evaluate_reference_accessions()} as a false
#' \code{"insufficient_independent_evidence"} verdict for every accession
#' in the batch, exactly like an undetected poll timeout.
#'
#' Matched on the raw XML text (cheap, before parsing) rather than
#' per-\code{<Iteration>} -- confirmed on the real captured case that a
#' server-side CPU rejection applies to the WHOLE batch at once (every
#' iteration carried the identical message pair), not select queries within
#' it, so there's nothing to gain from a finer-grained per-iteration check.
#'
#' @return Logical scalar.
#' @noRd
.blast_server_rejected <- function(xml_text) {
  grepl("CPU usage limit was exceeded", xml_text, fixed = TRUE) ||
    grepl("consumed a large amount of server CPU time", xml_text, fixed = TRUE)
}

#' @noRd
.parse_blast_xml <- function(xml_text) {
  # Parse NCBI BLAST XML output into a data frame matching .empty_raw_hits() schema
  .check_pkg("xml2")

  # Check for HTML status page instead of XML
  if (grepl("QBlastInfoBegin", xml_text) && !grepl("<BlastOutput>", xml_text)) {
    message("BLAST response is a status page, not XML results.")
    return(.empty_raw_hits())
  }

  doc <- tryCatch(xml2::read_xml(xml_text), error = function(e) {
    warning(sprintf("Failed to parse BLAST XML: %s", e$message))
    NULL
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
      # Subject/hit-side alignment coordinates (Hsp_hit-from/-to) -- WHERE
      # within the subject sequence this HSP actually aligns. Previously
      # parsed nowhere in this function (only the query-side qfrom/qto were
      # kept), even though BLAST already computes them -- needed so a
      # downstream consumer can tell whether two different queries' hits
      # against the SAME long subject (e.g. a complete mitogenome) actually
      # cover the same genomic region or two unrelated ones (see TaxaLikely's
      # restore_suppressed_candidates(check_regional_overlap = TRUE)).
      sfrom     <- as.integer(.xt("./Hsp_hit-from"))
      sto       <- as.integer(.xt("./Hsp_hit-to"))
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
        sstart   = sfrom,
        send     = sto,
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

.blast_local <- function(seq_df, database, program, megablast, max_target_seqs, verbose) {
  .check_pkg("rBLAST", "BiocManager::install('rBLAST')")
  .check_pkg("Biostrings", "BiocManager::install('Biostrings')")

  # Create DNAStringSet from sequences
  dna <- Biostrings::DNAStringSet(seq_df$sequence)
  names(dna) <- seq_df$asv_id

  # Open BLAST database
  bl <- rBLAST::blast(db = database, type = program)

  # Custom output format for eDNA. sstart/send (subject-side alignment
  # coordinates) added so a downstream consumer can tell whether two
  # different queries' hits against the SAME long subject (e.g. a complete
  # mitogenome) actually cover the same genomic region -- see
  # .parse_blast_xml()'s identical addition for the remote path.
  custom_format <- paste(
    "qseqid", "sseqid", "sacc", "staxids", "pident", "length",
    "qlen", "slen", "qcovs", "mismatch", "gapopen", "evalue", "bitscore",
    "sstart", "send",
    sep = " "
  )

  if (verbose) message(sprintf("Running local BLAST against %s...", database))

  # The standalone blastn binary defaults to "-task megablast" when -task is
  # left unspecified for program = "blastn" -- the same fast-but-not-
  # exhaustive behavior as the remote URL API's implicit default (see
  # blast_sequences()'s `megablast` param doc). "-task blastn" forces the
  # classic, more sensitive algorithm.
  task_flag <- if (identical(program, "blastn"))
    sprintf("-task %s", if (isTRUE(megablast)) "megablast" else "blastn") else ""

  hits <- stats::predict(bl, dna,
                  BLAST_args = sprintf(
                    "-max_target_seqs %d %s -outfmt '6 %s'",
                    max_target_seqs, task_flag, custom_format
                  ))

  if (is.null(hits) || nrow(hits) == 0L) return(.empty_raw_hits())

  # Standardize column names (rBLAST returns named columns)
  expected_cols <- c("qseqid", "sseqid", "sacc", "staxids", "pident", "length",
                     "qlen", "slen", "qcovs", "mismatch", "gapopen", "evalue", "bitscore",
                     "sstart", "send")

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
# Internal: Resolve taxonomy onto a (partially or fully) filtered hits table
# ==============================================================================

#' Attach genus/species/etc. columns to a hits data frame, in place.
#'
#' Tries taxid-based resolution first (via \code{staxids}); falls back to
#' accession-based lookup (via \code{sacc}) when no usable taxid is present
#' -- which is always the case for remote BLAST XML output, since
#' \code{.parse_blast_xml()} never populates a real per-hit taxid. Extracted
#' from \code{blast_sequences()}'s main body so it can run either at its
#' original point (after all filtering, the default) or earlier (right
#' after the cheap min_score/coverage/length filters, when
#' \code{max_hits_per_taxon} needs real names to group hits by before the
#' per-taxon cap and \code{max_hits} truncation run).
#' @noRd
.attach_taxonomy <- function(filtered, ncbi_api_key, verbose) {
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
      tax_map <- .resolve_taxonomy_by_acc(accessions, ncbi_api_key, verbose)
      if (is.data.frame(tax_map) && nrow(tax_map) > 0L) {
        filtered <- merge(filtered, tax_map, by.x = "sacc", by.y = "accession",
                          all.x = TRUE, sort = FALSE)
      }
    }
  }

  filtered
}


# ==============================================================================
# Internal: Filter BLAST hits (score window + QC)
# ==============================================================================

.filter_blast_hits <- function(hits, min_score, min_query_coverage,
                               subject_len_range, score_range, max_hits,
                               max_hits_per_taxon = NULL,
                               taxon_group_col = "staxids",
                               stage = "all",
                               verbose) {
  n_start <- nrow(hits)

  if (stage %in% c("all", "basic")) {
    # 1. Minimum score
    hits <- hits[!is.na(hits$pident) & hits$pident >= min_score, ]

    # 2. Query coverage
    if ("qcovs" %in% names(hits) && !all(is.na(hits$qcovs))) {
      hits <- hits[is.na(hits$qcovs) | hits$qcovs >= min_query_coverage, ]
    }

    # 3. Aligned-region length (NOT the subject accession's own total length
    # -- a long mitogenome/partial-genome record can still contain a
    # perfectly valid, correctly-sized amplicon-window alignment; checking
    # the whole subject's length instead of the alignment itself discards
    # those hits for no real reason. See "Subject length filter" in
    # @details.
    if (!is.null(subject_len_range) && "length" %in% names(hits) &&
        !all(is.na(hits$length))) {
      hits <- hits[
        is.na(hits$length) |
          (hits$length >= subject_len_range[1L] & hits$length <= subject_len_range[2L]),
      ]
    }
  }

  if (stage == "basic") return(hits)

  # 3b. Per-taxon cap (optional): within each query, keep at most
  # max_hits_per_taxon hits per taxon (grouped by `taxon_group_col`, default
  # "staxids" -- but note remote BLAST's XML output never populates a real
  # per-hit taxid, so blast_sequences() resolves real species/genus names
  # FIRST via .attach_taxonomy() and passes their column name here instead
  # whenever max_hits_per_taxon + resolve_taxonomy are both requested; see
  # that function's own logic). Prevents one heavily-resequenced species
  # (e.g. many independently deposited mitogenomes of the same well-studied
  # species) from consuming the whole max_hits budget with redundant
  # near-duplicates and crowding out a real, different congener. Each
  # taxon's own best hit is always kept (sorted by pident before
  # truncating), so this never changes which taxon holds the top score for
  # step 4 below.
  if (!is.null(max_hits_per_taxon) && nrow(hits) > 0L &&
      taxon_group_col %in% names(hits)) {
    group_val <- hits[[taxon_group_col]]
    taxon_key <- ifelse(
      is.na(group_val) | !nzchar(group_val),
      paste0("__unresolved_", seq_len(nrow(hits))),  # never group unresolved hits together
      group_val
    )
    hits <- do.call(rbind, lapply(
      split(hits, list(hits$qseqid, taxon_key), drop = TRUE),
      function(g) utils::head(g[order(-g$pident), ], max_hits_per_taxon)
    ))
    rownames(hits) <- NULL
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
  .check_pkg("rentrez")
  .check_pkg("xml2")

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
.empty_acc_taxonomy_result <- function() {
  data.frame(accession = character(), kingdom = character(),
             phylum = character(), class = character(),
             order = character(), family = character(),
             genus = character(), species = character(),
             stringsAsFactors = FALSE)
}

#' @noRd
.resolve_taxonomy_by_acc <- function(accessions, ncbi_api_key = NULL,
                                               verbose = TRUE) {
  .check_pkg("rentrez")
  .check_pkg("xml2")

  if (!is.null(ncbi_api_key))
    rentrez::set_entrez_key(ncbi_api_key)

  # Step 1: Look up taxids from accessions via nucleotide summary.
  # 100 accessions/batch keeps the "[ACCN]" OR-query comfortably under
  # NCBI's request-size limits; entrez_search() posts the query rather than
  # appending it to the URL, so the classic GET-URL-length ceiling does not
  # apply, but very long individual accession strings could still add up --
  # not observed in production use of this batch size to date.
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
    return(.empty_acc_taxonomy_result())
  }

  # Step 2: Resolve taxids to full taxonomy
  taxids <- unique(unlist(acc_taxid_map, use.names = FALSE))
  if (verbose) message(sprintf("Resolving taxonomy for %d unique taxids...", length(taxids)))
  tax_map <- .resolve_taxonomy(taxids, ncbi_api_key, verbose)

  if (is.null(tax_map) || nrow(tax_map) == 0L) {
    return(.empty_acc_taxonomy_result())
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
# Internal: Resolve collection location (lat_lon/country) from accessions
# ==============================================================================

#' Parse an INSDC lat_lon qualifier string into signed decimal degrees
#'
#' GenBank's \code{/lat_lon} qualifier uses the format
#' \code{"36.789 N 121.947 W"} (degrees, hemisphere letter, repeated for
#' longitude). Returns \code{c(lat = NA_real_, lon = NA_real_)} on any
#' missing/unparseable input. Deliberately duplicated from TaxaLikely's
#' identical internal helper rather than shared across packages -- matches
#' this ecosystem's existing pre-manuscript stance on NCBI-fetcher overlap
#' (see `ecosystem_docs` / TaxaLikely's Session 115 note: the only real
#' cross-package overlap is small taxid/qualifier parsing, not worth
#' abstracting before manuscript review).
#' @noRd
.parse_lat_lon <- function(x) {
  empty <- c(lat = NA_real_, lon = NA_real_)
  if (is.null(x) || length(x) != 1L || is.na(x) || !nzchar(trimws(x))) return(empty)

  m <- regmatches(x, regexec(
    "^\\s*([0-9.]+)\\s*([NSns])\\s+([0-9.]+)\\s*([EWew])\\s*$", x
  ))[[1L]]
  if (length(m) != 5L) return(empty)

  lat_val <- suppressWarnings(as.numeric(m[2L]))
  lon_val <- suppressWarnings(as.numeric(m[4L]))
  if (is.na(lat_val) || is.na(lon_val)) return(empty)

  lat <- if (toupper(m[3L]) == "S") -lat_val else lat_val
  lon <- if (toupper(m[5L]) == "W") -lon_val else lon_val
  c(lat = lat, lon = lon)
}


#' Resolve GenBank collection location (lat_lon/country) from accessions
#'
#' Fetches full GBSeq XML records (\code{rettype = "gb", retmode = "xml"})
#' directly by accession -- neither \code{.resolve_taxonomy()} nor
#' \code{.resolve_taxonomy_by_acc()} ever touch this record type (both only
#' reach the NCBI taxonomy database), so BLAST hit accessions' collection
#' coordinates are otherwise never in scope. Accessions are passed directly
#' as \code{id} (the same convention used elsewhere in this file), avoiding
#' a separate search/summary round trip.
#' @noRd
.resolve_locations_by_acc <- function(accessions, ncbi_api_key = NULL,
                                      verbose = TRUE) {
  empty <- data.frame(accession = character(0L), lat = numeric(0L),
                      lon = numeric(0L), country = character(0L),
                      stringsAsFactors = FALSE)

  .check_pkg("rentrez")
  .check_pkg("xml2")

  if (!is.null(ncbi_api_key))
    rentrez::set_entrez_key(ncbi_api_key)

  accessions <- unique(accessions[!is.na(accessions) & nzchar(accessions)])
  if (length(accessions) == 0L) return(empty)

  batch_size <- 100L
  batches    <- split(accessions, ceiling(seq_along(accessions) / batch_size))
  res        <- vector("list", length(batches))

  for (i in seq_along(batches)) {
    batch <- batches[[i]]
    for (attempt in 1:3) {
      tryCatch({
        xml_raw <- rentrez::entrez_fetch(
          db = "nucleotide", id = batch, rettype = "gb", retmode = "xml"
        )
        xml_doc <- xml2::read_xml(xml_raw)
        nodes   <- xml2::xml_find_all(xml_doc, "//GBSeq")

        res[[i]] <- do.call(rbind, lapply(nodes, function(node) {
          acc   <- xml2::xml_text(xml2::xml_find_first(node, "./GBSeq_primary-accession"))
          quals <- xml2::xml_find_all(
            node, ".//GBFeature[GBFeature_key='source']/GBFeature_quals/GBQualifier"
          )
          qnames <- xml2::xml_text(xml2::xml_find_all(quals, "./GBQualifier_name"))
          qvals  <- xml2::xml_text(xml2::xml_find_all(quals, "./GBQualifier_value"))

          lat_lon_raw <- qvals[qnames == "lat_lon"]
          country_raw <- qvals[qnames == "country"]
          ll <- .parse_lat_lon(if (length(lat_lon_raw) > 0L) lat_lon_raw[1L] else NA_character_)

          data.frame(
            accession = acc,
            lat       = ll[["lat"]],
            lon       = ll[["lon"]],
            country   = if (length(country_raw) > 0L) country_raw[1L] else NA_character_,
            stringsAsFactors = FALSE
          )
        }))
        break
      }, error = function(e) {
        if (attempt < 3L) {
          Sys.sleep(attempt * 2)
        } else if (verbose) {
          warning(sprintf("Location fetch failed for batch %d: %s", i, e$message))
        }
      })
    }
    if (i < length(batches)) Sys.sleep(0.4)
  }

  out <- do.call(rbind, Filter(Negate(is.null), res))
  if (is.null(out)) empty else out
}


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
    sstart = integer(), send = integer(),
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
