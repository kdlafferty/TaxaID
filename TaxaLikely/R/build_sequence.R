utils::globalVariables(c(
  "composite_id", "sequence", "distance", "p_match", "species"
))

# ==============================================================================
# MODULE B: REFERENCE MATRIX CONSTRUCTION
# ==============================================================================

#' Build a pairwise match-score matrix from reference sequences
#'
#' Aligns DNA sequences using `DECIPHER::AlignSeqs()`, computes pairwise
#' distances with `DECIPHER::DistanceMatrix()`, converts distances to match
#' scores (`p_match = 1 - distance`), and joins taxonomy metadata.  The
#' resulting data frame is the input to [train_likelihood_model()].
#'
#' @section Requirements:
#' Packages `DECIPHER` and `Biostrings` must be installed
#' (`BiocManager::install("DECIPHER")`).  They are listed in `Suggests` because
#' they are only needed for this one function.
#'
#' @param reference_df Data frame with one row per reference sequence.  Must
#'   contain:
#'   \describe{
#'     \item{`composite_id`}{Unique sequence identifier (character).}
#'     \item{`sequence`}{DNA string (character, IUPAC alphabet accepted).}
#'     \item{rank columns}{One column per rank in `rank_system`
#'       (e.g., `genus`, `species`).}
#'   }
#' @param rank_system Character vector of rank names **coarse to fine**
#'   (e.g., `c("family", "genus", "species")`). Default `NULL`
#'   auto-detects from columns in `reference_df`.
#' @param max_dist Numeric (default `0.25`).  Pairs with distance above this
#'   threshold are dropped to save memory.  Roughly, 0.25 ~= 75% identity.
#'   The 75% identity threshold is a standard floor for retaining distantly
#'   related taxa in barcode reference databases.
#' @param min_seq_len Integer (default `100`).  Sequences shorter than this
#'   are discarded before alignment.  Ignored if `barcode_term` is supplied
#'   and this argument is left at its default -- see `barcode_term` below.
#' @param max_seq_len Integer (default `2000`).  Sequences longer than this
#'   are discarded before alignment.  Ignored if `barcode_term` is supplied
#'   and this argument is left at its default -- see `barcode_term` below.
#' @param barcode_term Character or `NULL` (default `NULL`).  When supplied
#'   AND `min_seq_len`/`max_seq_len` are both left at their defaults, resolves
#'   the length window via `TaxaTools::resolve_barcode_lengths(barcode_term)`
#'   instead of using the generic `[100, 2000]` default.  Explicit
#'   `min_seq_len`/`max_seq_len` always override this, matching
#'   `resolve_barcode_lengths()`'s own override convention.
#'
#'   This exists because the generic default length window does NOT
#'   guarantee every retained sequence covers the same amplicon window --
#'   only that it is a plausible barcode-length fragment of *some* kind. A
#'   broad NCBI free-text search (e.g. `barcode_term = "12S"` at fetch time)
#'   can return sequences describing a genomically different stretch of the
#'   same gene (older primer sets, broader mitochondrial fragments) that
#'   still happen to pass a length filter -- silently mixing two different
#'   genomic windows into what looks like one self-consistent H1/H2 training
#'   set (the documented "Paralabrax footgun": a real 0% MiFish-primer-site
#'   hit rate on sequences that had already passed the generic length
#'   filter). Passing a *specific, registered primer variant* here (e.g.
#'   `"MiFishU"`, not just `"12S"`) gives the strongest guarantee, since that
#'   resolves to the literature-verified real PCR amplicon length rather than
#'   a broader per-gene range; a bare marker name (e.g. `"12S"`) only
#'   guarantees "roughly the right marker," not amplicon-window
#'   comparability, and does not by itself close this gap. See
#'   the `sebastes_chromis_confirmation.R` diagnostic (TaxaID_dev repository) for the case this was
#'   found in.
#' @param filter_unnamed Logical (default `TRUE`).  If `TRUE`, sequences whose
#'   finest-rank taxonomy column (the last element of `rank_system`, typically
#'   `species`) is blank (`""`) or `NA` are removed before alignment.  Blank
#'   names produce spurious within-species pairs -- two unidentified sequences
#'   both labelled `""` are classified as conspecific even though they may
#'   represent entirely different taxa.  In a broad 18S reference database this
#'   can account for the majority of apparent within-species pairs.  Set to
#'   `FALSE` only if blank finest-rank values are intentional.
#' @param max_seqs_per_taxon Integer or `NULL` (default `NULL`).  If supplied,
#'   at most this many sequences are retained per finest-rank taxon before
#'   alignment, chosen by random sampling using the current RNG state (set
#'   `set.seed()` before calling for reproducibility).  This prevents
#'   heavily-sequenced model organisms or domestic species from dominating
#'   the within-species distribution and thereby distorting model training.
#'   For typical vertebrate barcode databases a value of `10L`-`20L` is
#'   sufficient; the resulting within-species pair counts per taxon are at most
#'   `max_seqs_per_taxon * (max_seqs_per_taxon - 1) / 2`.  `NULL` disables
#'   the cap (current behaviour).
#' @param verbose Logical (default `TRUE`).  Passed straight through to
#'   `DECIPHER::AlignSeqs()`/`DECIPHER::DistanceMatrix()`'s own native
#'   progress reporting (percent-complete, ETA) for the two
#'   steps that dominate wall time on a large reference set (alignment cost
#'   grows worse than linearly in sequence count, so a large reference
#'   database can run for hours with no visible signal of progress without
#'   it). This function's OWN `message()` calls
#'   (length-filter counts, rank-system auto-detection, timing summaries) are
#'   unaffected either way -- only DECIPHER's own in-progress display is
#'   controlled by this parameter. `FALSE` gives a fully-silent run (e.g. for
#'   a non-interactive/logged batch run where a live progress bar is
#'   meaningless).
#' @param by_genus Logical (default `FALSE`; see `@section Per-genus
#'   alignment` below). `TRUE` replaces the single whole-set
#'   `DECIPHER::AlignSeqs()` call with many small per-genus alignments (each
#'   augmented with up to `max_foreign_reps_per_genus` other genera's chosen
#'   representatives) plus one small cross-genus-representative alignment --
#'   same output shape, much better scaling on a reference set with many
#'   genera. Requires `"genus"` in `rank_system` (errors if absent); a
#'   sequence with a blank/NA `genus` value is dropped with a message rather
#'   than aborting the run (a real broad fetch legitimately has some
#'   genus-unresolved accessions -- e.g. environmental samples).
#' @param max_foreign_reps_per_genus Integer or `NULL` (default `20L`). Only
#'   relevant when `by_genus = TRUE` -- caps how many OTHER genera's
#'   representative sequences get added to each genus's own augmented
#'   alignment (see `@section Per-genus alignment` below). `NULL` means no
#'   cap (every other genus's representative is added, regardless of how
#'   many genera exist) -- real-data validation found this costs MORE than
#'   whole-set alignment, and gets worse as genus count grows (a real
#'   221-genus reference set took ~40 minutes uncapped vs ~10 minutes for
#'   whole-set), since the added cost scales with the SQUARE of genus count.
#'   A finite cap keeps the added cost linear in genus count instead
#'   (`genera x cap`, not `genera x (genera - 1)`) -- each genus draws an
#'   INDEPENDENT random subset of `cap` other genera's representatives (not
#'   one subset shared across every genus, which would starve whichever
#'   genera never happen to fall inside it), so coverage stays roughly even
#'   across genera even though it is no longer exhaustive. `0L` disables the
#'   augmentation entirely (representative-only alignment -- see the
#'   `@section` below for why that understates `gap_logit`).
#' @param pair_retention `"all"` (default), `"best_per_partner"` or
#'   `"best_per_class"`. Which pairs within `max_dist` are returned. `"all"`
#'   returns every pair. The other two return every within-species pair
#'   plus, for each sequence and each stratum of its cross-species partners,
#'   at most two pairs: the best-scoring one whose `coverage` clears
#'   `min_pair_coverage`, and the best-scoring one regardless of coverage.
#'   Under `"best_per_partner"` the stratum is the partner species inside the
#'   sequence's own genus and the partner family (or genus when no family
#'   rank is given) outside it; under `"best_per_class"` it is the pair type
#'   itself -- congeneric, confamilial or cross-family -- so a sequence keeps
#'   at most six cross-species pairs in total. See `@section Pair retention`
#'   for why both are exact for [train_likelihood_model()] and what each
#'   changes elsewhere.
#' @param min_pair_coverage Numeric in (0, 1] or `NULL` (default `0.8`). Only
#'   used when `pair_retention` is not `"all"`: the coverage floor the
#'   retained best-clearing pair is chosen under. Must equal the
#'   `min_pair_coverage` later passed to [train_likelihood_model()] (whose
#'   default is also `0.8`), or be `NULL` if training will use `NULL`; the
#'   value is recorded in the result's `"pair_retention"` attribute and
#'   [train_likelihood_model()] warns on a mismatch it can still see.
#'
#' @section Pair retention (`pair_retention` other than `"all"`):
#' The pair table's size is dominated by same-genus cross-species pairs,
#' which grow with the square of a genus's sequence count, so a species-rich
#' genus with many sequences per species sets the memory ceiling for the
#' whole build. Yet nothing downstream consumes those pairs as a
#' distribution. [train_likelihood_model()] reads, per reference sequence,
#' its best within-species match, its best same-genus cross-species match and
#' its best cross-species match of any kind (each as the best pair clearing
#' its coverage floor, with the unfloored best as fallback); the
#' confusion-risk curves read the best match per pair type (within-species,
#' congeneric, confamilial, cross-family); a singleton takes its single best
#' partner. Every one of those is a maximum, and the maximum over a union of
#' strata is the maximum of the per-stratum maxima -- so keeping the two
#' best pairs per (sequence, partner stratum) reproduces each of them exactly
#' and the trained model is identical to the one trained on `"all"`.
#' Within-species pairs are always kept in full: they are a few percent of
#' the table, and `TaxaMatch::corroborate_references_locally()` counts
#' distinct conspecific partners and their submission independence, which
#' needs every one of them.
#'
#' What changes: under `"best_per_partner"` the table is smaller by roughly
#' the mean number of sequences per partner species inside a genus (bounded
#' above by `max_seqs_per_taxon`), so same-genus rows grow as sequences
#' times species per genus instead of sequences squared; under
#' `"best_per_class"` they grow as sequences alone, and within-species pairs
#' (quadratic per species, bounded by `max_seqs_per_taxon`) become the
#' largest term. Alignment cost is unchanged either way. The row count
#' `N_Obs` in the training data is unchanged (within-species pairs are
#' complete). `restore_suppressed_candidates()` looks pairs up by accession:
#' a query's direct pair with a specific candidate accession is present only
#' when that accession is the query's best for its species, so restoration
#' resolves more often at its species-pair and genus-model levels than at
#' the direct-accession level, and its species-pair median is a median of
#' per-query bests rather than of all pairs. Removing accessions from the
#' table after the build (an accession screen) removes some queries' best
#' partner for a stratum with no runner-up to fall back on (under
#' `"best_per_class"` the direct-accession and species-pair levels of
#' restoration are reached only when a candidate happens to hold a query's
#' best congeneric pair, so restoration mostly resolves from the genus
#' model); screen
#' `reference_df` before building, which is also what
#' [train_likelihood_model()] recommends. [check_cross_genus_sampling_noise()]
#' always builds with `"all"`.
#'
#' @section Per-genus alignment (`by_genus = TRUE`):
#' Whole-set alignment cost grows worse than linearly in sequence count, but
#' `train_likelihood_model()` only ever consumes within-species pairs (H1),
#' same-genus cross-species pairs (H2), and a pooled cross-genus sample (H3,
#' already coarse/pooled, never species-specific) -- none of which strictly
#' need one shared whole-set alignment, only same-scale genomic coordinates
#' *within* whatever comparison they're drawn from.
#'
#' `by_genus = TRUE` does many smaller alignments instead of one huge one:
#' each genus's own sequences are aligned together (giving every H1/H2 pair
#' unchanged), but that alignment ALSO includes a copy of up to
#' `max_foreign_reps_per_genus` OTHER genera's chosen representative
#' sequences -- so every sequence, not just the genus's own representative,
#' gets a real comparison against a real member of some (or, uncapped, every)
#' other genus. A separate, small dedicated alignment of just the
#' representatives (one per genus) supplies the representative-vs-
#' representative pairs (excluded from the per-genus step to avoid computing
#' them twice). Together these give H3 (and H2's pooled fallback for a genus
#' with no real congener) a real cross-genus sample, at a fraction of the
#' whole-set cost -- see `.align_pairs_by_genus()`'s own `@section Why every
#' sequence, not just the representative` for the real-data finding that
#' motivated this design (a representative-only version measurably inflated
#' the `gap_logit` feature for every non-representative sequence), and its
#' `@section Capping the foreign-representative count` for why the fix's
#' first, uncapped version was itself found to cost more than whole-set
#' alignment on real data. Both pieces are combined into one table with the
#' identical column shape this function always returns --
#' `train_likelihood_model()` needs no changes either way.
#'
#' Each genus's own representative is chosen at RANDOM, not "first" -- see
#' `.align_pairs_by_genus()`'s own header for why (nothing guarantees
#' `reference_df`'s row order is itself unbiased). Use
#' [check_cross_genus_sampling_noise()] to see how much that one random draw
#' actually moves the cross-genus pair distribution before trusting a single
#' run's H3 estimate on a new marker.
#'
#' A pair between two NON-representative sequences from two DIFFERENT genera
#' is still never compared (recovering that would mean going back to
#' whole-set cost) -- this design fixes "some sequences get zero cross-genus
#' visibility at all," not the coarser representative-sampling approximation
#' itself. Validate against a marker with an existing, already-trusted
#' whole-set-trained model before relying on this for a new one; do not
#' assume the two approaches give numerically identical H1/H2/H3 parameters
#' just because they consume conceptually the same pairs.
#'
#' @return A data frame with one row per sequence pair within `max_dist`:
#'   \describe{
#'     \item{`id_x`, `id_y`}{`composite_id` values for each pair member.}
#'     \item{`p_match`}{Match score (1 - distance), range (0, 1].}
#'     \item{`coverage`}{Alignment coverage: number of positions where both
#'       sequences contribute a non-gap character, divided by the shorter
#'       unaligned sequence length.  Range (0, 1].  Values near 1.0 indicate
#'       nearly complete overlap; values near 0.0 indicate highly gappy or
#'       partial alignments that produce unreliable match scores.  A minimum
#'       coverage threshold can be applied directly (e.g.
#'       `ref_matrix[ref_matrix$coverage >= threshold, ]`) before calling
#'       [train_likelihood_model()]; this package does not provide a
#'       dedicated threshold-calibration helper for it.}
#'     \item{`{rank}.x`, `{rank}.y`}{Taxonomy columns for each pair member.}
#'   }
#'
#' @seealso [train_likelihood_model()]
#'
#' @examples
#' \dontrun{
#' # Requires DECIPHER + Biostrings (Bioconductor)
#' ref_matrix <- build_sequence_matrix(
#'   reference_df,
#'   rank_system = c("family", "genus", "species"),
#'   filter_unnamed = TRUE, # drop blank/NA species (default)
#'   max_seqs_per_taxon = 20L # cap per-species sequences before alignment
#' )
#' head(ref_matrix)
#' }
#'
#' @importFrom dplyr all_of distinct filter left_join mutate rename_with select
#' @export
build_sequence_matrix <- function(reference_df,
                                  rank_system = NULL,
                                  max_dist = 0.25,
                                  min_seq_len = 100L,
                                  max_seq_len = 2000L,
                                  filter_unnamed = TRUE,
                                  max_seqs_per_taxon = NULL,
                                  barcode_term = NULL,
                                  verbose = TRUE,
                                  by_genus = FALSE,
                                  max_foreign_reps_per_genus = 20L,
                                  pair_retention = c("all", "best_per_partner", "best_per_class"),
                                  min_pair_coverage = 0.8) {
  if (!is.logical(verbose) || length(verbose) != 1L || is.na(verbose)) {
    stop("verbose must be TRUE or FALSE")
  }
  pair_retention <- match.arg(pair_retention)
  if (!is.null(min_pair_coverage) &&
    (!is.numeric(min_pair_coverage) || length(min_pair_coverage) != 1L ||
      is.na(min_pair_coverage) || min_pair_coverage <= 0 || min_pair_coverage > 1)) {
    stop("min_pair_coverage must be NULL or a single number in (0, 1]")
  }
  if (!is.logical(by_genus) || length(by_genus) != 1L || is.na(by_genus)) {
    stop("by_genus must be TRUE or FALSE")
  }
  if (!is.null(max_foreign_reps_per_genus)) {
    if (!is.numeric(max_foreign_reps_per_genus) || length(max_foreign_reps_per_genus) != 1L ||
      is.na(max_foreign_reps_per_genus) || max_foreign_reps_per_genus < 0L) {
      stop("max_foreign_reps_per_genus must be NULL or a single non-negative integer")
    }
    max_foreign_reps_per_genus <- as.integer(max_foreign_reps_per_genus)
  }
  if (!is.null(barcode_term)) {
    if (missing(min_seq_len) && missing(max_seq_len)) {
      len_bounds <- TaxaTools::resolve_barcode_lengths(barcode_term)
      min_seq_len <- len_bounds[["min_bp"]]
      max_seq_len <- len_bounds[["max_bp"]]
      message(sprintf(
        paste0(
          "build_sequence_matrix: barcode_term '%s' resolved to length range [%d, %d] bp ",
          "(TaxaTools::resolve_barcode_lengths()); pass min_seq_len/max_seq_len explicitly ",
          "to override."
        ),
        paste(barcode_term, collapse = "/"), min_seq_len, max_seq_len
      ))
    } else {
      message(sprintf(
        paste0(
          "build_sequence_matrix: barcode_term supplied but min_seq_len/max_seq_len were ",
          "also set explicitly -- using [%d, %d] as given, NOT barcode_term's resolved ",
          "range. This does not guarantee every retained sequence covers the same amplicon ",
          "window."
        ),
        min_seq_len, max_seq_len
      ))
    }
  }

  if (!is.data.frame(reference_df)) {
    stop("reference_df must be a data frame")
  }

  needed <- c("composite_id", "sequence")
  missing_cols <- setdiff(needed, names(reference_df))
  if (length(missing_cols) > 0L) {
    stop(sprintf(
      "reference_df is missing required columns: %s",
      paste(missing_cols, collapse = ", ")
    ))
  }

  if (!is.logical(filter_unnamed) || length(filter_unnamed) != 1L || is.na(filter_unnamed)) {
    stop("filter_unnamed must be TRUE or FALSE")
  }

  if (!is.null(max_seqs_per_taxon)) {
    if (!is.numeric(max_seqs_per_taxon) || length(max_seqs_per_taxon) != 1L ||
      is.na(max_seqs_per_taxon) || max_seqs_per_taxon < 2L) {
      stop("max_seqs_per_taxon must be NULL or an integer >= 2")
    }
    max_seqs_per_taxon <- as.integer(max_seqs_per_taxon)
  }

  if (!requireNamespace("DECIPHER", quietly = TRUE)) {
    stop("Package 'DECIPHER' is required. Install it with: BiocManager::install('DECIPHER')")
  }
  if (!requireNamespace("Biostrings", quietly = TRUE)) {
    stop("Package 'Biostrings' is required. Install it with: BiocManager::install('Biostrings')")
  }

  names(reference_df) <- tolower(names(reference_df))

  # Auto-detect rank_system from reference_df columns
  if (is.null(rank_system) || length(rank_system) == 0L) {
    rank_system <- TaxaTools::detect_ranks(reference_df, warn = FALSE)
    if (length(rank_system) == 0L) {
      # Fallback to standard trio
      fallback <- c("family", "genus", "species")
      rank_system <- fallback[fallback %in% names(reference_df)]
    }
    if (length(rank_system) == 0L) {
      stop("rank_system could not be auto-detected. reference_df has no recognized taxonomy columns.")
    }
    message(
      "build_sequence_matrix: auto-detected rank_system: ",
      paste(rank_system, collapse = ", ")
    )
  }

  rank_cols <- tolower(rank_system)
  missing_ranks <- setdiff(rank_cols, names(reference_df))
  if (length(missing_ranks) > 0L) {
    stop(sprintf(
      "rank_system columns not found in reference_df (after lowercasing): %s",
      paste(missing_ranks, collapse = ", ")
    ))
  }

  # ---- 1. CLEAN & DEDUPLICATE -----------------------------------------------
  ref_seqs <- reference_df |>
    dplyr::filter(!is.na(sequence), nchar(sequence) > 0L) |>
    dplyr::distinct(composite_id, .keep_all = TRUE)

  if (nrow(ref_seqs) < 2L) {
    stop("Fewer than 2 valid sequences in reference_df after deduplication")
  }

  # ---- 1b. IUPAC DNA FILTER --------------------------------------------------
  # Biostrings::DNAStringSet() throws a cryptic lookup-table error if a sequence
  # contains non-IUPAC-DNA characters (e.g., 'E', 'F', 'I', 'L' -- amino acid
  # codes returned when an accession resolves to a protein record or a corrupt
  # NCBI entry).  Filter these out with a clear message before hitting Biostrings.
  valid_iupac <- "^[ACGTRYSWKMBDHVNacgtryswkmbdhvn-]+$"
  is_valid <- grepl(valid_iupac, ref_seqs$sequence)
  n_invalid <- sum(!is_valid)
  if (n_invalid > 0L) {
    bad_ids <- head(ref_seqs$composite_id[!is_valid], 5L)
    warning(sprintf(
      paste0(
        "build_sequence_matrix: removed %d sequence(s) with non-IUPAC DNA characters %s",
        "(likely protein accessions or corrupt records)."
      ),
      n_invalid,
      sprintf("(e.g. %s) ", paste(bad_ids, collapse = ", "))
    ), call. = FALSE)
    ref_seqs <- ref_seqs[is_valid, , drop = FALSE]
  }

  if (nrow(ref_seqs) < 2L) {
    stop("Fewer than 2 valid DNA sequences in reference_df after IUPAC filter")
  }

  # ---- 1c. FILTER UNNAMED FINEST-RANK TAXA ------------------------------------
  # Pairs where the finest-rank label is blank or NA are not valid within-species
  # training pairs.  In broad 18S reference databases, blank species names can
  # account for the majority of apparent within-species pairs.
  finest_rank <- rank_cols[length(rank_cols)]
  if (filter_unnamed && finest_rank %in% names(ref_seqs)) {
    finest_vals <- ref_seqs[[finest_rank]]
    is_named <- !is.na(finest_vals) & nchar(trimws(finest_vals)) > 0L
    n_unnamed <- sum(!is_named)
    if (n_unnamed > 0L) {
      message(sprintf(
        "build_sequence_matrix: removed %d sequence(s) with blank/NA '%s' (filter_unnamed = TRUE).",
        n_unnamed, finest_rank
      ))
      ref_seqs <- ref_seqs[is_named, , drop = FALSE]
    }
    if (nrow(ref_seqs) < 2L) {
      stop("Fewer than 2 sequences remained after filtering unnamed sequences")
    }
  }

  # ---- 1d. THIN TO max_seqs_per_taxon -----------------------------------------
  # Randomly subsample sequences per finest-rank taxon before alignment to
  # prevent heavily-sequenced species from dominating the within-species
  # distribution.  Uses the caller's RNG state; call set.seed() beforehand for
  # reproducibility.
  if (!is.null(max_seqs_per_taxon) && finest_rank %in% names(ref_seqs)) {
    finest_vals <- ref_seqs[[finest_rank]]
    # NA finest-rank values are reachable whenever filter_unnamed = FALSE, and
    # they must be excluded from the taxon list rather than treated as a taxon:
    # `sum(finest_vals == tx)` is NA for EVERY taxon once a single NA is
    # present, so `over_cap` became all-NA (firing the branch unconditionally
    # and reporting a nonsense cap count), and `which(finest_vals == NA)` is
    # integer(0), so every unnamed sequence was silently dropped from training.
    # A sequence with no finest-rank label belongs to no taxon and so cannot be
    # capped by a per-taxon limit -- it is retained unchanged, which is what
    # filter_unnamed = FALSE asked for.
    na_rows <- which(is.na(finest_vals))
    unique_taxa <- unique(finest_vals[!is.na(finest_vals)])
    taxon_counts <- vapply(
      unique_taxa,
      function(tx) sum(finest_vals == tx, na.rm = TRUE),
      integer(1L)
    )
    over_cap <- unique_taxa[taxon_counts > max_seqs_per_taxon]
    if (length(over_cap) > 0L) {
      keep_rows <- c(na_rows, unlist(lapply(unique_taxa, function(tx) {
        rows <- which(finest_vals == tx)
        if (length(rows) > max_seqs_per_taxon) sample(rows, max_seqs_per_taxon) else rows
      }), use.names = FALSE))
      ref_seqs <- ref_seqs[sort(keep_rows), , drop = FALSE]
      message(sprintf(
        "build_sequence_matrix: capped %d taxon/taxa to <= %d sequences per '%s'.",
        length(over_cap), max_seqs_per_taxon, finest_rank
      ))
    }
    if (nrow(ref_seqs) < 2L) {
      stop("Fewer than 2 sequences remained after thinning to max_seqs_per_taxon")
    }
  }

  # ---- 2. LENGTH FILTER -------------------------------------------------------
  dna <- Biostrings::DNAStringSet(ref_seqs$sequence)
  names(dna) <- ref_seqs$composite_id

  widths <- Biostrings::width(dna)
  valid_idx <- widths >= min_seq_len & widths <= max_seq_len
  n_dropped <- sum(!valid_idx)

  if (n_dropped > 0L) {
    message(sprintf(
      "Dropped %d sequence(s) outside length range [%d, %d]",
      n_dropped, min_seq_len, max_seq_len
    ))
  }

  dna <- dna[valid_idx]
  ref_seqs <- ref_seqs[valid_idx, , drop = FALSE]

  if (length(dna) < 2L) {
    stop(sprintf(
      "Fewer than 2 sequences remained after length filtering [%d, %d]",
      min_seq_len, max_seq_len
    ))
  }

  # ---- 3. ALIGNMENT & DISTANCE MATRIX ----------------------------------------
  # The retention context carries each sequence's taxonomy into every
  # alignment so that pairs can be thinned as each alignment is extracted --
  # the full pair table is never accumulated (see @section Pair retention).
  retain <- if (pair_retention != "all") {
    .retention_context(ref_seqs, rank_cols, min_pair_coverage, pair_retention)
  } else {
    NULL
  }
  if (isTRUE(by_genus)) {
    dist_tbl <- .align_pairs_by_genus(
      dna, ref_seqs, rank_cols, max_dist, verbose, max_foreign_reps_per_genus,
      retain = retain
    )
  } else {
    t0 <- proc.time()[["elapsed"]]
    message("Aligning sequences with DECIPHER...")
    dist_tbl <- .decipher_align_pairs(dna, max_dist, verbose, retain = retain)
    message(sprintf("Alignment complete (%.1fs)", proc.time()[["elapsed"]] - t0))
  }

  # A (sequence, stratum) group can be fed by more than one alignment under
  # by_genus = TRUE (a foreign representative meets a family's members in
  # each of that family's genus alignments, and its representatives in the
  # representative alignment). Each alignment kept its own two best, so the
  # union is exact but can exceed two per group; one final pass over the
  # already-thinned table restores the documented "at most two" shape.
  if (!is.null(retain) && nrow(dist_tbl) > 0L) {
    .lab <- function(v, k) if (is.null(v)) NULL else unname(v[k])
    keep <- .best_per_partner_keep(
      x = dist_tbl$id_x,
      sp_x = .lab(retain$species, dist_tbl$id_x), sp_y = .lab(retain$species, dist_tbl$id_y),
      gn_x = .lab(retain$genus, dist_tbl$id_x), gn_y = .lab(retain$genus, dist_tbl$id_y),
      fam_x = .lab(retain$family, dist_tbl$id_x), fam_y = .lab(retain$family, dist_tbl$id_y),
      p_match = dist_tbl$p_match, coverage = dist_tbl$coverage, tie = dist_tbl$id_y,
      min_pair_coverage = retain$min_pair_coverage, by = retain$by
    )
    dist_tbl <- dist_tbl[keep, , drop = FALSE]
  }

  # ---- 4. MERGE TAXONOMY METADATA --------------------------------------------
  present_rank_cols <- intersect(rank_cols, names(ref_seqs))
  lookup <- dplyr::select(ref_seqs, composite_id, dplyr::all_of(present_rank_cols))

  out <- dist_tbl |>
    dplyr::left_join(lookup, by = c("id_x" = "composite_id")) |>
    dplyr::rename_with(~ paste0(., ".x"), dplyr::all_of(present_rank_cols)) |>
    dplyr::left_join(lookup, by = c("id_y" = "composite_id")) |>
    dplyr::rename_with(~ paste0(., ".y"), dplyr::all_of(present_rank_cols))

  # Recorded so train_likelihood_model() can tell that a thinned table was
  # built under a different coverage floor than the one it is about to apply
  # (see @section Pair retention). Base-R row subsetting drops this attribute,
  # so it is a courtesy check, not a guarantee.
  attr(out, "pair_retention") <- list(
    policy = pair_retention,
    min_pair_coverage = if (pair_retention != "all") min_pair_coverage else NULL
  )

  message(sprintf(
    "Matrix built: %d pairs within distance < %.2f%s",
    nrow(out), max_dist,
    if (pair_retention != "all") sprintf(" (pair_retention = \"%s\")", pair_retention) else ""
  ))
  out
}

#' Build the per-sequence taxonomy lookup that pair retention needs
#'
#' Named character vectors (by `composite_id`) for the finest rank, the genus
#' (when present) and the family (when present), plus the coverage floor.
#' `NULL` entries mean that rank is absent from `rank_cols`; the retention
#' rule adapts (see `.best_per_partner_keep()`).
#' @noRd
.retention_context <- function(ref_seqs, rank_cols, min_pair_coverage, policy) {
  ids <- ref_seqs$composite_id
  finest <- rank_cols[length(rank_cols)]
  .col <- function(nm) {
    if (nm %in% names(ref_seqs)) stats::setNames(as.character(ref_seqs[[nm]]), ids) else NULL
  }
  list(
    species = .col(finest),
    genus = if (!identical(finest, "genus")) .col("genus") else NULL,
    family = if (!identical(finest, "family")) .col("family") else NULL,
    min_pair_coverage = min_pair_coverage,
    by = if (identical(policy, "best_per_class")) "class" else "partner"
  )
}

#' Which directed pairs survive `pair_retention = "best_per_partner"`
#'
#' Works on parallel vectors describing directed pairs (`x` is the query side).
#' A pair whose two sides share the finest-rank label is always kept. Every
#' other pair is assigned to a stratum -- the partner's species when the two
#' sides share a genus, otherwise the partner's family (or genus, or species,
#' whichever coarsest of those ranks is available) -- and within each
#' `(x, stratum)` group at most two rows survive: the highest-scoring pair
#' whose `coverage` clears `min_pair_coverage`, and the highest-scoring pair
#' regardless of coverage (the same row when they coincide). Ties break on
#' higher coverage, then on `tie` (any orderable vector, e.g. the partner's
#' index or id) so the result is deterministic.
#'
#' Why this is lossless for the consumers of the pair table: every quantity
#' `train_likelihood_model()` reads from a cross-species pair is a per-query
#' maximum (best foreign match, best congener match, best match per
#' pair-type for the confusion-risk curves, a singleton's best partner), each
#' taken either over pairs clearing the coverage floor or over all pairs.
#' Both maxima of a union are maxima of the per-stratum maxima, so keeping the
#' two per stratum reproduces them exactly. Within-species pairs are kept in
#' full because `TaxaMatch::corroborate_references_locally()` counts distinct
#' conspecific partners and needs submission-batch metadata this function
#' never sees.
#'
#' @param x Query-side identifiers (any atomic vector; equal values = same
#'   query).
#' @param sp_x,sp_y,gn_x,gn_y,fam_x,fam_y Finest-rank, genus and family labels
#'   for each side; `gn_*`/`fam_*` may be `NULL` when that rank is absent.
#' @param p_match,coverage Numeric, per pair.
#' @param tie Orderable vector, per pair, for deterministic tie-breaking.
#' @param min_pair_coverage Coverage floor, or `NULL` (then only the
#'   highest-scoring pair per stratum is kept).
#' @return Logical vector, `TRUE` for rows to keep.
#' @noRd
.best_per_partner_keep <- function(x, sp_x, sp_y, gn_x, gn_y, fam_x, fam_y,
                                   p_match, coverage, tie, min_pair_coverage,
                                   by = c("partner", "class")) {
  by <- match.arg(by)
  n <- length(x)
  if (n == 0L) {
    return(logical(0L))
  }
  same_sp <- !is.na(sp_x) & !is.na(sp_y) & sp_x == sp_y
  has_gn <- !is.null(gn_x) && !is.null(gn_y)
  same_gn <- if (has_gn) !is.na(gn_x) & !is.na(gn_y) & gn_x == gn_y else rep(FALSE, n)
  # Stratum for a cross-species pair: partner species inside the genus,
  # partner family (coarsest available) outside it. The prefix keeps a
  # species-stratum key from ever colliding with a family/genus-stratum key.
  stratum <- if (by == "partner") {
    cross_stratum <- if (!is.null(fam_y)) {
      paste0("f:", fam_y)
    } else if (has_gn) {
      paste0("g:", gn_y)
    } else {
      paste0("s:", sp_y)
    }
    ifelse(same_gn & !same_sp, paste0("s:", sp_y), cross_stratum)
  } else {
    # Pair-type classes, exactly the ones the confusion-risk curves collapse
    # on: congeneric, confamilial (same family, different genus), cross-family.
    same_fam <- if (!is.null(fam_x) && !is.null(fam_y)) {
      !is.na(fam_x) & !is.na(fam_y) & fam_x == fam_y
    } else {
      rep(FALSE, n)
    }
    ifelse(same_gn, "congeneric", ifelse(same_fam, "confamilial", "crossfamily"))
  }
  key <- paste(as.character(x), stratum, sep = "\r")
  cand <- which(!same_sp)
  if (length(cand) == 0L) {
    return(rep(TRUE, n))
  }
  cov_ord <- coverage
  cov_ord[is.na(cov_ord)] <- -Inf
  ord <- cand[order(key[cand], -p_match[cand], -cov_ord[cand], tie[cand])]
  keep <- same_sp
  # Best overall per stratum: first row of each key in score order.
  keep[ord[!duplicated(key[ord])]] <- TRUE
  # Best per stratum among pairs clearing the floor.
  if (!is.null(min_pair_coverage)) {
    ok <- ord[cov_ord[ord] >= min_pair_coverage]
    keep[ok[!duplicated(key[ok])]] <- TRUE
  }
  keep
}

#' Align one DNAStringSet and extract its sparse pair table
#'
#' Shared by the whole-set path and each per-genus/cross-genus call in the
#' `by_genus = TRUE` path -- the exact same alignment,
#' distance-matrix, and coverage-extraction logic, just
#' callable on a subset instead of hardcoded to the whole input.
#'
#' `retain` is `NULL` (keep every pair within `max_dist`) or the list from
#' `.retention_context()`, in which case `pair_retention = "best_per_partner"`
#' is applied here, to this alignment's pairs, before any character id column
#' is formed -- so a thinned build never holds one alignment's full pair
#' table in data-frame form, let alone the accumulated one.
#' @noRd
.decipher_align_pairs <- function(dna, max_dist, verbose, retain = NULL,
                                  pair_filter = NULL) {
  aligned <- DECIPHER::AlignSeqs(dna, processors = NULL, verbose = verbose)
  dist_m <- DECIPHER::DistanceMatrix(
    aligned,
    type                 = "matrix",
    includeTerminalGaps  = FALSE,
    processors           = NULL,
    verbose              = verbose
  )

  empty <- data.frame(
    id_x = character(0L), id_y = character(0L),
    p_match = numeric(0L), coverage = numeric(0L),
    stringsAsFactors = FALSE
  )

  # Sparse extraction: only materialise pairs within max_dist (avoids an N^2 intermediate)
  idx <- which(dist_m < max_dist & row(dist_m) != col(dist_m), arr.ind = TRUE)
  if (nrow(idx) == 0L) {
    return(empty)
  }
  i <- idx[, 1L]
  j <- idx[, 2L]
  p_match <- 1 - dist_m[idx]
  rm(idx)

  # Coverage = number of positions where both sequences contribute a non-gap
  # character, divided by the shorter unaligned sequence length. The overlap
  # count for every pair is one 0/1 matrix product (rows = sequences, columns
  # = alignment positions), taken in row blocks so the transient block never
  # exceeds a few hundred MB regardless of alignment size; the count is an
  # exact integer, so this is the same number a per-pair mask intersection
  # gives, at a small fraction of the cost.
  aln_str <- as.character(aligned)
  seq_names <- names(aligned)
  n_seq <- length(aln_str)
  gap_mat <- matrix(
    as.double(unlist(strsplit(aln_str, "", fixed = TRUE), use.names = FALSE) != "-"),
    nrow = n_seq, byrow = TRUE
  )
  orig_widths <- as.integer(rowSums(gap_mat))

  overlap <- numeric(length(i))
  block <- max(1L, as.integer(floor(3.2e7 / n_seq))) # ~256 MB of doubles per block
  ord_i <- order(i)
  i_sorted <- i[ord_i]
  starts <- seq.int(1L, n_seq, by = block)
  for (s in starts) {
    e <- min(s + block - 1L, n_seq)
    sel <- ord_i[i_sorted >= s & i_sorted <= e]
    if (length(sel) == 0L) next
    ov_block <- tcrossprod(gap_mat[s:e, , drop = FALSE], gap_mat)
    overlap[sel] <- ov_block[cbind(i[sel] - s + 1L, j[sel])]
  }
  rm(gap_mat, ord_i, i_sorted)
  min_len <- pmin(orig_widths[i], orig_widths[j])
  coverage <- ifelse(min_len == 0L, NA_real_, overlap / min_len)

  # A caller-supplied eligibility rule (the per-genus path drops pairs that
  # another alignment is responsible for) must run BEFORE retention, so that
  # retention never spends a stratum's two slots on rows that are about to be
  # discarded.
  if (!is.null(pair_filter)) {
    elig <- pair_filter(seq_names[i], seq_names[j])
    if (!any(elig)) {
      return(empty)
    }
    i <- i[elig]
    j <- j[elig]
    p_match <- p_match[elig]
    coverage <- coverage[elig]
  }

  if (!is.null(retain)) {
    .lab <- function(v, k) if (is.null(v)) NULL else unname(v[seq_names[k]])
    keep <- .best_per_partner_keep(
      x = i,
      sp_x = .lab(retain$species, i), sp_y = .lab(retain$species, j),
      gn_x = .lab(retain$genus, i), gn_y = .lab(retain$genus, j),
      fam_x = .lab(retain$family, i), fam_y = .lab(retain$family, j),
      p_match = p_match, coverage = coverage, tie = j,
      min_pair_coverage = retain$min_pair_coverage, by = retain$by
    )
    if (!any(keep)) {
      return(empty)
    }
    i <- i[keep]
    j <- j[keep]
    p_match <- p_match[keep]
    coverage <- coverage[keep]
  }

  data.frame(
    id_x = seq_names[i],
    id_y = seq_names[j],
    p_match = p_match,
    coverage = coverage,
    stringsAsFactors = FALSE
  )
}

#' Per-genus + cross-genus-representative alignment (`by_genus = TRUE`)
#'
#' Replaces one whole-set `DECIPHER::AlignSeqs()` call (cost grows worse than
#' linearly in sequence count) with many small per-genus alignments -- giving
#' every within-species and same-genus pair `train_likelihood_model()` actually
#' uses for H1/H2 unchanged -- plus real cross-genus comparisons for EVERY
#' sequence (not just one representative), at a fraction of the whole-set
#' cost. See `build_sequence_matrix()`'s own `@param by_genus` for the full
#' rationale and the real numbers this was built against.
#'
#' @section Why every sequence, not just the representative:
#' Aligning exactly one representative
#' sequence per genus against every other genus's representative, in a single
#' small pass, is cheap, but real-data validation on two independent datasets
#' (GreatLakes-adjacent Mugu and PtConception 12S) found this understates
#' `gap_logit` (score minus best FOREIGN score) for every sequence that ISN'T
#' its genus's chosen representative: `train_likelihood_model()`'s
#' `max_foreign_score` is computed from whichever cross-species matches
#' actually exist in the output table, and a non-representative sequence had
#' none at all unless a real congener happened to exist in its OWN genus --
#' falling back to a same-genus congener match (if any) or the noise floor
#' (if the genus is monotypic), both of which understate how close the
#' sequence's TRUE nearest cross-genus relative really is. Measured effect:
#' trained `mu_gap` inflated ~0.09-0.14 (median) even for polytypic-genus
#' species, ~0.19-0.23 (median) for monotypic ones -- real, not cosmetic,
#' since gap is documented elsewhere in this package as H1's "key
#' discriminator" dimension. (The DIRECTION is toward caution, not false
#' confidence: an inflated trained gap makes a genuinely close/ambiguous real
#' query read as more atypical than it should, which biases against
#' confusable-congener false positives -- but it is still a real shift, not a
#' rounding difference.)
#'
#' Fixed by giving every genus's OWN alignment a copy of every OTHER genus's
#' chosen representative, not just aligning the representatives against each
#' other in isolation. Every sequence in genus X is therefore compared
#' directly against a real member of every other genus (that genus's
#' representative), giving `max_foreign_score` a genuine cross-genus value to
#' read for every sequence, not only the one that happened to be drawn. The
#' one exception is representative-vs-representative pairs themselves --
#' EXCLUDED from this per-genus step (a rep-vs-rep pair would otherwise be
#' computed twice, once from each of the two genera's own augmented
#' alignment, in two different alignment contexts with two different
#' resulting `p_match` values) -- those pairs are, as before, the sole
#' responsibility of the small dedicated cross-genus-representative
#' alignment below.
#'
#' This does NOT recover full whole-set fidelity: a pair between two
#' NON-representative sequences from two DIFFERENT genera is still never
#' compared (that would be back to O(sequences^2)) -- only
#' representative-vs-anything and non-representative-vs-representative pairs
#' are captured. What it fixes is specifically the "some sequences get zero
#' cross-genus visibility at all" gap, not the coarser
#' representative-sampling approximation itself (still governed by
#' [check_cross_genus_sampling_noise()]).
#'
#' @section Capping the foreign-representative count:
#' The fix above works statistically when UNCAPPED (every genus's alignment
#' gets a copy of literally every other genus's representative) -- but
#' real-data timing on two independent datasets found it costs MORE than
#' whole-set alignment, and the gap WIDENS (not
#' narrows) as genus count grows: a real 88-genus reference set went from
#' 14.1s (uncapped) to 82.1s (whole-set) -- already a real regression -- and
#' a real 221-genus reference set went from 2370.1s (uncapped) to 602.9s
#' (whole-set), a much worse one. The reason: padding every genus's own
#' alignment with `n_genera - 1` extra sequences means the total extra
#' "sequence slots" added across every genus's alignment grows with
#' `n_genera * (n_genera - 1)` -- quadratic in genus count -- which swamps
#' the savings once a marker has hundreds of genera, exactly the case this
#' whole `by_genus` feature exists to help with.
#'
#' `max_foreign_reps_per_genus` bounds this: instead of adding every other
#' genus's representative, each genus adds at most `max_foreign_reps_per_genus`
#' of them, drawn independently at random per genus (own `sample()` call,
#' consuming the caller's RNG state right after that genus's own
#' representative is chosen). Independent per-genus draws, not one shared
#' subset reused across every genus, matter here: a single shared subset
#' would mean every genus NOT in that subset gets zero foreign context at
#' all under the cap, recreating exactly the "some sequences get zero
#' cross-genus visibility" problem this whole mechanism exists to prevent, just
#' shifted from "one sequence per genus" to "whole genera." Independent
#' per-genus draws instead give every genus roughly the same expected share
#' of appearances across all other genera's subsets (`cap / (n_genera - 1)`
#' each), so no genus's representative goes systematically unseen.
#'
#' With a cap, the added cost per genus is bounded at `cap` extra sequences
#' regardless of how many genera exist, so the total added cost grows
#' linearly in genus count (`n_genera * cap`) instead of quadratically. This
#' trades away some of the fix's fidelity (a capped genus's non-representative
#' sequences see only a random SAMPLE of other genera, not all of them) for
#' cost that stays bounded as genus count grows -- see
#' `build_sequence_matrix()`'s own `@param max_foreign_reps_per_genus` for the
#' default and how to disable the cap (or the augmentation itself) entirely.
#'
#' Representative selection is RANDOM, one per genus, via `sample()` on the
#' caller's current RNG state -- matching this same file's existing
#' `max_seqs_per_taxon` convention exactly (`set.seed()` beforehand for
#' reproducibility), chosen over a deterministic "first row" rule because nothing
#' guarantees `reference_df`'s row order is itself unbiased (e.g. NCBI's own
#' return order, or a submission-date sort), and a systematic same-position
#' pick could quietly bias which sequence represents every genus in the
#' cross-genus sample. See [check_cross_genus_sampling_noise()] for a way to
#' measure how much that random draw actually moves the cross-genus estimate.
#' Representative selection happens in its own pass, BEFORE any alignment
#' runs, so every genus's augmented alignment knows every other genus's
#' chosen representative in advance -- the RNG draw sequence (one `sample()`
#' call per multi-sequence genus, in genus order) is unchanged from the
#' original single-pass design, so `set.seed()`-driven reproducibility is
#' identical to before this revision.
#'
#' Per-genus DECIPHER `verbose` output is always suppressed regardless of the
#' caller's own `verbose` (thousands of individual progress bars would be
#' worse noise than the whole-set call this replaces) -- an aggregate
#' progress message is printed instead, at a fixed cadence, when `verbose`.
#' The one cross-genus alignment (size = number of genera, not number of
#' sequences) DOES get DECIPHER's own real progress display when `verbose`,
#' since that call's cost is not negligible on a marker with many genera.
#' @noRd
.align_pairs_by_genus <- function(dna, ref_seqs, rank_cols, max_dist, verbose,
                                  max_foreign_reps_per_genus = NULL,
                                  retain = NULL) {
  if (!"genus" %in% rank_cols) {
    stop("by_genus = TRUE requires 'genus' in rank_system (found: ",
      paste(rank_cols, collapse = ", "), ").",
      call. = FALSE
    )
  }

  # A sequence with a blank/NA genus cannot be grouped by genus at all -- on a
  # real, broad fetch (e.g. 18S spanning many eukaryotic lineages) this is
  # normal, expected attrition (environmental samples, unclassified/
  # incompletely-resolved lineages), not a data error, so it is dropped with a
  # message rather than aborting the whole run -- the same "drop and report,
  # don't hard-fail" convention `filter_unnamed` already uses for a blank
  # finest-rank value. (Confirmed against a real production run: a real
  # 1,412-genus/21,896-sequence 18S fetch legitimately has some
  # genus-unresolved accessions.)
  genus_vals <- ref_seqs[["genus"]]
  has_genus <- !is.na(genus_vals) & nzchar(trimws(genus_vals))
  n_no_genus <- sum(!has_genus)
  if (n_no_genus > 0L) {
    message(sprintf(
      paste0(
        "build_sequence_matrix: by_genus = TRUE -- dropped %d sequence(s) with ",
        "blank/NA 'genus' (cannot be grouped by genus)."
      ),
      n_no_genus
    ))
    dna <- dna[has_genus]
    ref_seqs <- ref_seqs[has_genus, , drop = FALSE]
    genus_vals <- genus_vals[has_genus]
  }
  if (length(dna) < 2L) {
    stop("Fewer than 2 sequences remained after dropping blank/NA 'genus' values for by_genus = TRUE.",
      call. = FALSE
    )
  }

  genus_groups <- split(seq_along(genus_vals), genus_vals)
  n_genera <- length(genus_groups)
  if (verbose) {
    message(sprintf(
      "build_sequence_matrix: aligning %d genus group(s) (mean %.1f sequence(s)/genus)...",
      n_genera, length(genus_vals) / n_genera
    ))
  }

  # Phase 1: pick one representative per genus, BEFORE any alignment runs --
  # every genus's own augmented alignment (Phase 2) needs to know every OTHER
  # genus's already-chosen representative. RNG draw order (one sample() call
  # per multi-sequence genus, in genus order) is unchanged from the original
  # single-pass design.
  rep_idx <- integer(n_genera)
  for (i in seq_len(n_genera)) {
    rows <- genus_groups[[i]]
    rep_idx[i] <- if (length(rows) == 1L) rows else sample(rows, 1L)
  }
  rep_ids <- names(dna)[rep_idx]

  # Phase 2: each genus's own alignment includes its own sequences PLUS every
  # OTHER genus's representative -- giving every one of ITS sequences (not
  # just its own chosen representative) a genuine cross-genus comparison. See
  # this function's own @section above for why the old representative-only
  # design understated gap_logit for non-representative sequences.
  t0 <- proc.time()[["elapsed"]]
  report_every <- max(1L, round(n_genera / 10))
  augmented <- vector("list", n_genera)
  for (i in seq_len(n_genera)) {
    own_rows <- genus_groups[[i]]
    own_ids <- names(dna)[own_rows]
    other_reps_all <- rep_idx[-i]
    other_rep_rows <- if (!is.null(max_foreign_reps_per_genus) &&
      length(other_reps_all) > max_foreign_reps_per_genus) {
      if (max_foreign_reps_per_genus == 0L) {
        integer(0)
      } else {
        sample(other_reps_all, max_foreign_reps_per_genus)
      }
    } else {
      other_reps_all
    }
    combo_rows <- c(own_rows, other_rep_rows)
    # A monotypic genus (own_rows length 1) with zero foreign reps added
    # (max_foreign_reps_per_genus = 0, or a degenerate single-genus input)
    # has nothing to align -- DECIPHER::AlignSeqs() requires >= 2 sequences.
    # Such a genus's only member IS its representative, so it already gets
    # full cross-genus visibility from the dedicated alignment below; it
    # needs no augmented-step contribution at all (same as this genus's
    # treatment in the original, pre-augmentation design).
    if (length(combo_rows) >= 2L) {
      combo_pairs <- .decipher_align_pairs(dna[combo_rows], max_dist,
        verbose = FALSE, retain = retain,
        pair_filter = function(x, y) {
          (x %in% own_ids | y %in% own_ids) & !(x %in% rep_ids & y %in% rep_ids)
        }
      )
      if (nrow(combo_pairs) > 0L) {
        # Keep: within-genus pairs (both sides in own_ids), and cross-genus
        # pairs touching this genus's sequences -- EXCEPT rep-vs-rep pairs
        # (both sides are representatives of different genera), which are the
        # dedicated cross_genus_tbl alignment's sole responsibility below, to
        # avoid computing the same pair twice from two different contexts.
        keep <- (combo_pairs$id_x %in% own_ids | combo_pairs$id_y %in% own_ids) &
          !(combo_pairs$id_x %in% rep_ids & combo_pairs$id_y %in% rep_ids)
        augmented[[i]] <- combo_pairs[keep, , drop = FALSE]
      }
    }
    if (verbose && (i %% report_every == 0L || i == n_genera)) {
      message(sprintf(
        "  ...%d/%d genus group(s) aligned (%.0fs elapsed)",
        i, n_genera, proc.time()[["elapsed"]] - t0
      ))
    }
  }
  augmented_tbl <- dplyr::bind_rows(augmented)

  # Cross-genus representative sample: one representative sequence per genus,
  # aligned together in a single small pass -- the sole source of
  # representative-vs-representative pairs (excluded from Phase 2 above to
  # avoid double-counting); every pair here is cross-genus by construction.
  #
  # A single-genus reference set has no cross-genus pairs to sample at all,
  # and DECIPHER::AlignSeqs() hard-errors on a 1-sequence input ("At least two
  # sequences are required in myXStringSet") -- an opaque message for what is
  # a legitimate call (auditing one genus). The augmented step above has
  # already produced every within-genus pair in that case, so simply skip.
  cross_genus_tbl <- if (n_genera >= 2L) {
    if (verbose) {
      message(sprintf(
        "build_sequence_matrix: aligning %d cross-genus representative(s)...",
        n_genera
      ))
    }
    .decipher_align_pairs(dna[rep_idx], max_dist, verbose, retain = retain)
  } else {
    message(paste0(
      "build_sequence_matrix: only 1 genus present -- no cross-genus ",
      "representative sample is possible (H3/H2's pooled fallback will ",
      "have no local cross-genus pairs to learn from)."
    ))
    data.frame(
      id_x = character(0L), id_y = character(0L),
      p_match = numeric(0L), coverage = numeric(0L),
      stringsAsFactors = FALSE
    )
  }

  dplyr::bind_rows(augmented_tbl, cross_genus_tbl)
}

#' How Much Does the Random Cross-Genus Draw Move the Estimate?
#'
#' `build_sequence_matrix(by_genus = TRUE)` represents each genus by ONE
#' randomly-drawn sequence when building the cross-genus sample that feeds H3
#' (and H2's pooled fallback). This re-runs that whole draw-and-align step
#' `n_replicates` times and reports how much the resulting cross-genus pair
#' distribution moves across replicates -- a transparency report, like
#' `TaxaExpect::kernel_budget_sensitivity()`'s own per-group budget table, not a
#' pass/fail gate. There is no universal "good enough" spread to check
#' against; the point is to make the spread visible so you can judge whether
#' it is small relative to what H3 actually does (a coarse, already-pooled
#' fallback likelihood shift for genuinely unreferenced species -- not a
#' species-specific parameter).
#'
#' @section Cost:
#' Each replicate re-runs the FULL `by_genus = TRUE` pipeline (including the
#' within-genus alignments, not just the cheap cross-genus step) -- simpler
#' and safer than threading a special reduced-recompute path through
#' `build_sequence_matrix()`'s internals, at the cost of some real redundant
#' work. Because `by_genus = TRUE` already made the whole pipeline
#' substantially cheaper than one whole-set alignment (see
#' `build_sequence_matrix()`'s own `@section Per-genus alignment`),
#' `n_replicates` repeats of it can still cost meaningfully LESS than a single
#' whole-set run would have -- but this is still real, additive NCBI-free
#' compute cost, not free; run it once when adopting `by_genus = TRUE` for a
#' new marker, not on every training run.
#'
#' @param reference_df,rank_system,max_dist,min_seq_len,max_seq_len,filter_unnamed,max_seqs_per_taxon,barcode_term,max_foreign_reps_per_genus
#'   Forwarded to `build_sequence_matrix(by_genus = TRUE, ...)`, identically
#'   for every replicate.
#' @param n_replicates Integer (default `5L`). How many independent random
#'   representative draws to compare. Each draw consumes the caller's RNG
#'   state (`sample()`, same convention as `max_seqs_per_taxon`) -- do NOT
#'   call `set.seed()` between replicates, or every "replicate" would be
#'   identical.
#'
#' @return A list:
#'   \describe{
#'     \item{`replicates`}{Data frame, one row per replicate:
#'       `replicate`, `n_cross_genus_pairs` (the count of DISTINCT unordered
#'       cross-genus sequence pairs -- `.decipher_align_pairs()`'s underlying
#'       pair table carries both `(i, j)` and `(j, i)` for every pair, and
#'       this count de-duplicates that before reporting), `mean_p_match`,
#'       `median_p_match`, `sd_p_match`.}
#'     \item{`summary`}{Named list: the range (min, max) and coefficient of
#'       variation (sd/mean) of `mean_p_match` across replicates -- the
#'       single number worth looking at first.}
#'   }
#'
#' @seealso [build_sequence_matrix()], `TaxaExpect::kernel_budget_sensitivity()`
#'
#' @examples
#' \dontrun{
#' # Requires DECIPHER + Biostrings (Bioconductor); re-runs the full
#' # by_genus = TRUE pipeline n_replicates times, so this is real compute.
#' noise <- check_cross_genus_sampling_noise(
#'   reference_df,
#'   rank_system = c("family", "genus", "species"),
#'   n_replicates = 5L
#' )
#' noise$summary
#' }
#'
#' @export
check_cross_genus_sampling_noise <- function(reference_df,
                                             rank_system = NULL,
                                             max_dist = 0.25,
                                             min_seq_len = 100L,
                                             max_seq_len = 2000L,
                                             filter_unnamed = TRUE,
                                             max_seqs_per_taxon = NULL,
                                             barcode_term = NULL,
                                             max_foreign_reps_per_genus = 20L,
                                             n_replicates = 5L) {
  if (!is.numeric(n_replicates) || length(n_replicates) != 1L ||
    is.na(n_replicates) || n_replicates < 2L) {
    stop("n_replicates must be a single integer >= 2.", call. = FALSE)
  }
  n_replicates <- as.integer(n_replicates)

  # build_sequence_matrix() only resolves barcode_term into a length window
  # when BOTH min_seq_len and max_seq_len are missing() at its own call. This
  # function forwarding its own defaults unconditionally therefore defeated
  # that gate entirely: barcode_term was accepted, then silently ignored, and
  # the diagnostic ran on a wider, unfiltered sequence set than the production
  # build_sequence_matrix(barcode_term = ...) call it exists to characterise --
  # the "Paralabrax footgun" re-entering through the diagnostic. Forward the
  # length arguments only when the caller actually supplied them.
  len_supplied <- !missing(min_seq_len) || !missing(max_seq_len)
  bs_args <- list(
    reference_df,
    rank_system = rank_system, max_dist = max_dist,
    filter_unnamed = filter_unnamed, max_seqs_per_taxon = max_seqs_per_taxon,
    barcode_term = barcode_term, by_genus = TRUE, verbose = FALSE,
    max_foreign_reps_per_genus = max_foreign_reps_per_genus
  )
  if (len_supplied) {
    bs_args$min_seq_len <- min_seq_len
    bs_args$max_seq_len <- max_seq_len
  }

  reps <- vector("list", n_replicates)
  warned_single_genus <- FALSE
  for (i in seq_len(n_replicates)) {
    message(sprintf("check_cross_genus_sampling_noise: replicate %d/%d...", i, n_replicates))
    mat <- suppressMessages(do.call(build_sequence_matrix, bs_args))
    if (!all(c("genus.x", "genus.y") %in% names(mat))) {
      stop("check_cross_genus_sampling_noise: rank_system must include 'genus' ",
        "(build_sequence_matrix(by_genus = TRUE) requires it).",
        call. = FALSE
      )
    }
    cross <- mat[mat$genus.x != mat$genus.y, , drop = FALSE]

    # .decipher_align_pairs() (the shared alignment/distance-extraction
    # helper) reports each unordered pair twice, once as (i, j) and once as
    # (j, i), from the symmetric distance matrix. That duplication does not
    # bias mean/median/sd_p_match (every value is duplicated exactly once,
    # so the distribution's shape is unchanged), but it would double-count
    # n_cross_genus_pairs. De-duplicate on an order-independent pair key
    # before counting, rather than assuming a fixed 2x factor.
    pair_key <- ifelse(
      cross$id_x < cross$id_y,
      paste(cross$id_x, cross$id_y, sep = "\r"),
      paste(cross$id_y, cross$id_x, sep = "\r")
    )
    n_pairs <- length(unique(pair_key))

    if (nrow(cross) == 0L && !warned_single_genus) {
      warning(
        "check_cross_genus_sampling_noise: no cross-genus pairs exist in this ",
        "reference set (only 1 genus present) -- mean_p_match/median_p_match/",
        "sd_p_match are NaN/NA/NA by design, not a computation error.",
        call. = FALSE
      )
      warned_single_genus <- TRUE
    }

    reps[[i]] <- data.frame(
      replicate = i,
      n_cross_genus_pairs = n_pairs,
      mean_p_match = mean(cross$p_match),
      median_p_match = stats::median(cross$p_match),
      sd_p_match = stats::sd(cross$p_match)
    )
  }
  replicates <- do.call(rbind, reps)

  mean_range <- range(replicates$mean_p_match)
  summary_list <- list(
    mean_p_match_range = mean_range,
    mean_p_match_cv = stats::sd(replicates$mean_p_match) / mean(replicates$mean_p_match)
  )
  message(sprintf(
    paste0(
      "check_cross_genus_sampling_noise: mean_p_match ranged %.4f-%.4f across %d ",
      "replicates (CV = %.4f). No pass/fail threshold -- judge this against what H3 ",
      "actually does (a coarse, pooled fallback), not against an invented cutoff."
    ),
    mean_range[1L], mean_range[2L], n_replicates, summary_list$mean_p_match_cv
  ))

  list(replicates = replicates, summary = summary_list)
}
