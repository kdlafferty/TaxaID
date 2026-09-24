# ==============================================================================
# PREDICTING THE MEMORY COST OF A SEQUENCE MATRIX
# ==============================================================================
#
# build_sequence_matrix() returns one row per ordered sequence pair within
# max_dist, and train_likelihood_model() holds several working copies of that
# table at once. On a broad reference set the table, not the alignment, is what
# exhausts memory. The pair count is predictable from the genus and species
# composition of the reference set before anything is aligned, so it is
# predicted here, once, and used by three callers: the exported estimator, the
# fetch's dry run, and build_sequence_matrix()'s own guard.

# --- The model ----------------------------------------------------------------
#
# Structure (exact, before the distance filter). .decipher_align_pairs() emits
# every pair in both directions, so with n_g sequences in genus g, G genera and
# f = min(max_foreign_reps_per_genus, G - 1) foreign representatives added to
# each genus's alignment:
#   within-genus   S_w = sum_g n_g (n_g - 1)
#   cross-genus    S_x = 2 f sum_g (n_g - 1)  +  G (G - 1)
# The first cross-genus term is every non-representative sequence against its
# genus's foreign representatives; the second is the dedicated
# representative-vs-representative alignment. A whole-set alignment
# (by_genus = FALSE) has S_w as above and S_x = N (N - 1) - S_w.
#
# Retention. The distance filter keeps a fraction r_w of within-genus pairs and
# r_x of cross-genus pairs. Neither can exceed 1, so S_w + S_x is a hard
# ceiling. r_w is near 1 on every marker measured; r_x depends on how broad the
# reference set is (a random pair of genera from across the animal kingdom is
# rarely within 0.25 on COI; two fish genera on 12S usually are).
#
# Bytes. Each retained pair is one row of 4 + 2 * n_ranks eight-byte columns
# (id_x, id_y, p_match, coverage, and each rank twice).
#
# Peak. train_likelihood_model() holds working copies of the table; the peak
# is expressed as a multiple of the table's own size.
#
# The constants below are measured, not assumed; see
# .matrix_size_constants() for what each was measured on.

#' Measured constants for the sequence-matrix memory model
#'
#' Each value was measured on real reference sets; none is fitted to make a
#' prediction come out right.
#'
#' \describe{
#'   \item{r_w}{Within-genus retention at `max_dist = 0.25`, pooled over four
#'     independent random samples of 300, 300, 900 and 3,000 genera from a
#'     broad metazoan COI (Leray) reference (0.944, 0.894, 0.950 and 0.945
#'     separately). A 378-genus 12S set fetched under the bare "12S" window
#'     kept only 0.551, plausibly because congeners' sequences there cover
#'     different stretches of the gene; the COI value is the high,
#'     conservative one.}
#'   \item{r_x_broad}{Cross-genus retention from the same COI samples (0.308,
#'     0.269, 0.305 and 0.317); the 12S set kept 0.348. A reference set
#'     spanning the animal kingdom is about as broad as they come; one drawn
#'     from a single class or family should keep more.}
#'   \item{bytes_overhead}{Bytes per pair above the 8-byte columns: 80.6 to
#'     82.8 measured on seven matrices against 80 for ten columns.}
#'   \item{peak, peak_fixed_gb}{The R heap at its peak through
#'     `train_likelihood_model()`, matrix included, measured with `gc()` on
#'     COI matrices of 138 MB, 476 MB and 1.6 GB: 4.0 times the matrix plus
#'     0.3 GB (least squares; the working copies on top of the matrix were
#'     3.1x, 2.8x and 3.0x the matrix beyond the fixed part). A 35 MB 12S
#'     matrix, not used in the fit, peaked at 0.42 GB against 0.44 GB
#'     predicted. Process memory as the operating system reports it can be
#'     lower, since macOS compresses idle pages: a full-scale 8.3 GB COI
#'     matrix peaked at 20.7 GB resident where this predicts a 33.5 GB heap.
#'     The heap is what R's own vector limit counts.}
#'   \item{align_bytes_per_cell}{Transient bytes per cell of one dense
#'     distance matrix during alignment: the double matrix plus the integer
#'     `row()`/`col()` indices and the logical masks built to extract the
#'     sparse pairs.}
#' }
#' @noRd
.matrix_size_constants <- function() {
  list(
    r_w = 0.942,
    r_x_broad = 0.313,
    bytes_overhead = 1.5,
    peak = 4.0,
    peak_fixed_gb = 0.3,
    align_bytes_per_cell = 28
  )
}


#' Exact pre-filter pair structure of a sequence matrix
#'
#' @param n_g Integer vector: sequences per genus, as they will be aligned.
#' @param by_genus,max_foreign_reps_per_genus As in [build_sequence_matrix()].
#' @return Named list: `S_w`, `S_x`, `G`, `f`, `N`, `max_cells` (the largest
#'   dense distance matrix any single alignment builds).
#' @noRd
.matrix_structure <- function(n_g, by_genus = TRUE, max_foreign_reps_per_genus = 20L) {
  n_g <- as.numeric(n_g[n_g > 0])
  G <- length(n_g)
  N <- sum(n_g)
  S_w <- sum(n_g * (n_g - 1))
  if (G == 0L) {
    return(list(S_w = 0, S_x = 0, G = 0L, f = 0L, N = 0, max_cells = 0))
  }
  if (isTRUE(by_genus)) {
    f <- if (is.null(max_foreign_reps_per_genus)) G - 1 else min(max_foreign_reps_per_genus, G - 1)
    S_x <- 2 * f * sum(n_g - 1) + G * (G - 1)
    max_cells <- max((max(n_g) + f)^2, G^2)
  } else {
    f <- 0
    S_x <- N * (N - 1) - S_w
    max_cells <- N^2
  }
  list(S_w = S_w, S_x = S_x, G = G, f = f, N = N, max_cells = max_cells)
}


#' Predicted memory, in GB, from a pair structure and retention rates
#' @noRd
.matrix_memory_gb <- function(st, r_w, r_x, n_ranks, peak,
                              k = .matrix_size_constants()) {
  pairs <- r_w * st$S_w + r_x * st$S_x
  bpp <- 8 * (4 + 2 * n_ranks) + k$bytes_overhead
  gb_matrix <- pairs * bpp / 2^30
  gb_align <- st$max_cells * k$align_bytes_per_cell / 2^30
  list(
    pairs = pairs,
    gb_matrix = gb_matrix,
    gb_peak = max(gb_matrix * peak + k$peak_fixed_gb, gb_align)
  )
}


# --- Available memory ---------------------------------------------------------

#' Memory available to a new allocation, in GB, or NA when unknown
#'
#' "Available" is not "free". On macOS the pages the kernel will hand to a new
#' allocation are free + inactive + speculative + purgeable; "Pages free" alone
#' understated it by 10 GB on a real run and stopped a job that would have
#' fitted. Linux reports the same quantity directly as `MemAvailable`. Windows
#' reports free physical memory. Anything else returns `NA`, and callers treat
#' `NA` as "cannot check", never as "no memory".
#' @noRd
.available_memory_gb <- function() {
  sys <- Sys.info()[["sysname"]]
  out <- tryCatch(
    switch(sys,
      Darwin = .parse_vm_stat(system2("vm_stat", stdout = TRUE, stderr = FALSE)),
      Linux = .parse_meminfo(readLines("/proc/meminfo", warn = FALSE)),
      Windows = {
        kb <- system2("powershell", c(
          "-NoProfile", "-Command",
          shQuote("(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory")
        ), stdout = TRUE, stderr = FALSE)
        kb <- suppressWarnings(as.numeric(trimws(kb[nzchar(trimws(kb))][1L])))
        kb * 1024 / 2^30
      },
      NA_real_
    ),
    error = function(e) NA_real_,
    warning = function(w) NA_real_
  )
  if (length(out) != 1L || !is.finite(out) || out <= 0) NA_real_ else out
}

#' @noRd
.parse_vm_stat <- function(lines) {
  if (length(lines) == 0L) {
    return(NA_real_)
  }
  page <- suppressWarnings(as.numeric(
    sub(".*page size of ([0-9]+) bytes.*", "\\1", lines[1L])
  ))
  if (is.na(page)) {
    return(NA_real_)
  }
  pages <- function(label) {
    l <- grep(paste0("^", label, ":"), lines, value = TRUE)[1L]
    if (is.na(l)) 0 else as.numeric(gsub("[^0-9]", "", sub("^[^:]*:", "", l)))
  }
  (pages("Pages free") + pages("Pages inactive") +
    pages("Pages speculative") + pages("Pages purgeable")) * page / 2^30
}

#' @noRd
.parse_meminfo <- function(lines) {
  l <- grep("^MemAvailable:", lines, value = TRUE)[1L]
  if (is.na(l)) {
    return(NA_real_)
  }
  as.numeric(gsub("[^0-9]", "", l)) * 1024 / 2^30
}


# --- Deterministic capping ----------------------------------------------------

#' A stable pseudo-random key per accession
#'
#' Caps keep the lowest-keyed rows of each species or genus. A key derived from
#' the accession itself, rather than from the RNG, makes the choice identical
#' on every call and on every platform, so a dry run names exactly the species
#' the real run drops, and a smaller cap keeps a subset of what a larger one
#' kept. The version suffix is stripped first so a GenBank revision does not
#' reshuffle the sample. The final mixing steps break up runs of consecutive
#' accessions, which usually come from one study and would otherwise be kept or
#' dropped together.
#' @noRd
.stable_key <- function(x) {
  x <- sub("\\.[0-9]+$", "", as.character(x))
  x[is.na(x)] <- ""
  p <- 2147483647
  ascii <- intToUtf8(32:126, multiple = TRUE)
  nch <- nchar(x)
  h <- numeric(length(x))
  for (k in seq_len(max(0L, nch))) {
    code <- match(substr(x, k, k), ascii, nomatch = 0L)
    h <- ifelse(k <= nch, (h * 131 + code) %% p, h)
  }
  h <- (h * 48271) %% p
  h <- bitwXor(as.integer(h), as.integer(h %/% 8192))
  (as.numeric(h) * 16807) %% p
}

#' Rank of each element within its group, by key
#' @noRd
.rank_within <- function(group, key) {
  g <- match(group, unique(group))
  o <- order(g, key, method = "radix")
  r <- integer(length(g))
  r[o] <- sequence(rle(g[o])$lengths)
  r
}

#' Apply the per-species and per-genus caps to reference metadata
#'
#' Species cap first, then genus cap, each keeping the lowest-keyed rows (see
#' `.stable_key()`). Only in-barcode-range rows are capped; out-of-range rows
#' have their own separate cap and pass through. Rows flagged in `exempt`
#' (priority species) are neither capped nor counted against a genus's cap.
#' @param meta Data frame with an accession column (`acc`, `acc_version` or
#'   `composite_id`) and the rank columns.
#' @param finest_rank Name of the finest rank; the species cap applies only
#'   when it is `"species"`.
#' @param key Optional precomputed `.stable_key()` of the accession column,
#'   for callers applying several caps to the same rows.
#' @return `meta`, filtered, in its original row order.
#' @noRd
.apply_reference_caps <- function(meta, max_per_species, max_per_genus,
                                  finest_rank = "species", exempt = NULL,
                                  key = NULL) {
  if (nrow(meta) == 0L || (is.null(max_per_species) && is.null(max_per_genus))) {
    return(meta)
  }
  id_col <- intersect(c("acc", "acc_version", "composite_id"), names(meta))[1L]
  if (is.na(id_col)) stop("meta needs an acc, acc_version or composite_id column")
  if (is.null(key)) key <- .stable_key(meta[[id_col]])
  meta[.cap_mask(meta, key, exempt, max_per_species, max_per_genus, finest_rank), , drop = FALSE]
}

#' Logical keep-mask behind .apply_reference_caps()
#' @noRd
.cap_mask <- function(meta, key, exempt, max_per_species, max_per_genus,
                      finest_rank = "species") {
  keep <- rep(TRUE, nrow(meta))
  if (nrow(meta) == 0L) {
    return(keep)
  }
  in_range <- if ("in_barcode_range" %in% names(meta)) {
    !is.na(meta$in_barcode_range) & meta$in_barcode_range
  } else {
    rep(TRUE, nrow(meta))
  }
  if (is.null(exempt)) exempt <- rep(FALSE, nrow(meta))
  capped <- in_range & !exempt

  if (!is.null(max_per_species) && identical(finest_rank, "species") &&
    "species" %in% names(meta)) {
    idx <- which(capped)
    r <- .rank_within(meta$species[idx], key[idx])
    keep[idx[r > max_per_species]] <- FALSE
  }
  if (!is.null(max_per_genus) && "genus" %in% names(meta)) {
    idx <- which(capped & keep)
    r <- .rank_within(meta$genus[idx], key[idx])
    keep[idx[r > max_per_genus]] <- FALSE
  }
  keep
}


# --- Calibration --------------------------------------------------------------

#' Retention rates from earlier builds' size_calibration records
#'
#' Pools the pairs, not the rates, so a large build counts for more than a
#' small one.
#' @param calibration A `build_sequence_matrix()` result, its
#'   `size_calibration` attribute, or a list of either.
#' @return Named list `r_w`, `r_x`, `n_builds`, or `NULL` when nothing usable
#'   was supplied.
#' @noRd
.pool_calibration <- function(calibration) {
  if (is.null(calibration)) {
    return(NULL)
  }
  as_rec <- function(x) {
    if (is.data.frame(x)) x <- attr(x, "size_calibration")
    if (is.list(x) && all(c("S_w", "S_x", "within_pairs", "cross_pairs") %in% names(x))) x else NULL
  }
  recs <- if (!is.null(as_rec(calibration))) list(as_rec(calibration)) else lapply(calibration, as_rec)
  recs <- Filter(Negate(is.null), recs)
  if (length(recs) == 0L) {
    stop(
      "calibration must be a build_sequence_matrix() result, its ",
      "\"size_calibration\" attribute, or a list of either.",
      call. = FALSE
    )
  }
  tot <- function(f) sum(vapply(recs, function(r) as.numeric(r[[f]]), numeric(1L)))
  list(
    r_w = if (tot("S_w") > 0) tot("within_pairs") / tot("S_w") else 1,
    r_x = if (tot("S_x") > 0) tot("cross_pairs") / tot("S_x") else 1,
    n_builds = length(recs)
  )
}


# --- The exported estimator ---------------------------------------------------

#' Predict the memory a sequence matrix will need, for a grid of caps
#'
#' [build_sequence_matrix()] returns one row per ordered pair of reference
#' sequences within `max_dist`, and [train_likelihood_model()] holds several
#' working copies of that table. On a broad reference set this table is what
#' exhausts memory, and its size is fixed by the genus and species composition
#' of the reference set, which is known before anything is aligned. This
#' function predicts it for each combination of `max_per_species` and
#' `max_per_genus`, so a cap can be chosen from numbers rather than found by a
#' failed run.
#'
#' @section How memory scales:
#' With `by_genus = TRUE` the pairs, before the distance filter, are
#' \deqn{\sum_g n_g(n_g - 1) + 2f\sum_g (n_g - 1) + G(G - 1)}{sum_g n_g(n_g - 1) + 2 f sum_g (n_g - 1) + G(G - 1)}
#' for \eqn{n_g} sequences in genus \eqn{g}, \eqn{G} genera and
#' \eqn{f = \min(}`max_foreign_reps_per_genus`\eqn{, G - 1)}: within-genus
#' pairs, each sequence against its genus's foreign representatives, and the
#' representatives against each other, all counted in both directions. Two
#' things follow. Memory grows with the square of the sequences in the largest
#' genera, which is what `max_per_species` and `max_per_genus` control. It also
#' grows with the square of the number of genera, which no cap controls: at
#' 11,000 genera the representative term alone is 121 million pairs before
#' filtering. Only a narrower taxon list reduces that term.
#'
#' Use `max_per_species` first. It never removes a species, and a species with
#' thousands of sequences (a model organism, a pest, a fishery species) is
#' usually where the bloat is. `max_per_genus` second: it samples across the
#' whole genus, so in a genus with more species than the cap allows, whole
#' species are dropped. The `species_dropped` element of the result names them.
#'
#' @section How accurate the prediction is:
#' The pair structure above is exact. What is estimated is the fraction of
#' those pairs the distance filter keeps. Within a genus it was 0.942 on COI
#' and 0.551 on a 12S set fetched under the bare "12S" window (plausibly
#' because congeners' sequences there cover different stretches of the gene).
#' Across genera it depends on how broad the reference set is: 0.313 on a COI
#' set spanning the animal kingdom and 0.348 on the 12S set; a set drawn from
#' one family should keep more.
#' Without `calibration`, `pairs_predicted` uses the COI rates, which fit a
#' broad reference set; `pairs_ceiling` assumes every pair is kept and cannot
#' be exceeded. For a narrow reference set read the ceiling, or calibrate.
#' [build_sequence_matrix()] does not rely on these defaults: before
#' aligning, it measures the cross-genus rate on the actual sequences. Pass an
#' earlier build of a similar reference set as `calibration` to use its
#' measured rates instead; each [build_sequence_matrix()] result carries them.
#' Against a real 11,322-genus COI build of 110.3 million pairs, rates
#' measured on 4,500 genera sampled independently of it predicted 112.9
#' million (2% high); single samples of 300 genera were within 7%.
#'
#' The peak through training (the table plus the working copies
#' [train_likelihood_model()] makes, together about `peak_multiple` times the
#' table plus 0.3 GB) is R's own memory, measured with `gc()` on real COI
#' builds. The operating system can report less, because macOS compresses
#' idle memory; a run can therefore survive a `gb_peak` above the memory
#' available, slowly and on compressed memory, but not above R's own vector
#' limit. Treat `gb_peak` as a guide to the right order
#' of magnitude with a margin, not as a guarantee: other objects in the session
#' also need memory, which is why only `memory_budget_fraction` of the
#' available memory is counted as usable.
#'
#' @param x The reference set: a data frame with `genus` and `species`
#'   columns and one row per sequence (a `reference_df`, or the `sequences`
#'   element of a [fetch_ncbi_reference_sequences()] dry run), or one row per
#'   species with an integer count column `n`. With an accession column (`acc`,
#'   `acc_version` or `composite_id`) the caps choose the same rows the fetch
#'   would; without one, `species_dropped` shows what a cap of that size drops
#'   from a set of this shape, not the exact species.
#' @param max_per_species,max_per_genus Numeric vectors of the caps to
#'   compare, as in [fetch_ncbi_reference_sequences()]; `NA` means no cap.
#'   Every combination is evaluated.
#' @param max_seqs_per_taxon,by_genus,max_foreign_reps_per_genus The values
#'   that will be passed to [build_sequence_matrix()]. `max_seqs_per_taxon` is
#'   applied after the fetch caps, as the build applies it.
#' @param n_ranks Number of rank columns the matrix will carry (the length of
#'   `rank_system`); each adds 16 bytes per pair.
#' @param calibration Optional: a [build_sequence_matrix()] result, its
#'   `size_calibration` attribute, or a list of either, from a reference set
#'   of similar breadth. Its measured retention rates replace the defaults in
#'   `pairs_predicted`.
#' @param memory_budget_fraction Fraction of available memory counted as
#'   usable (default 0.7).
#' @param available_gb Available memory in GB. `NULL` (default) reads it from
#'   the operating system (macOS, Linux and Windows); `NA` when it cannot be
#'   read, and then `fits` is `NA`.
#'
#' @return A list:
#'   \describe{
#'     \item{`grid`}{One row per cap combination: `max_per_species`,
#'       `max_per_genus`, `n_sequences`, `n_genera`, `n_species`,
#'       `n_species_dropped`, `largest_genus`, `pairs_predicted`,
#'       `pairs_ceiling`, `gb_matrix`, `gb_peak`, `gb_peak_ceiling`, and
#'       `fits` (whether `gb_peak` is within the budget).}
#'     \item{`species_dropped`}{A list parallel to `grid`'s rows: the species
#'       each combination removes entirely.}
#'     \item{`available_gb`, `budget_gb`}{The memory the verdict used.}
#'     \item{`rates`}{The retention rates used, and where they came from.}
#'   }
#'
#' @seealso [fetch_ncbi_reference_sequences()] with `dry_run = TRUE` for the
#'   same table before any sequence is downloaded; [build_sequence_matrix()],
#'   which checks the same prediction before aligning.
#'
#' @examples
#' counts <- data.frame(
#'   genus = c(rep("Delia", 3), "Sebastes", "Sebastes"),
#'   species = c("Delia platura", "Delia radicum", "Delia antiqua",
#'               "Sebastes mystinus", "Sebastes miniatus"),
#'   n = c(13116L, 900L, 405L, 60L, 45L)
#' )
#' est <- estimate_sequence_matrix_size(counts, available_gb = 16)
#' est$grid[, c("max_per_species", "max_per_genus", "n_sequences",
#'              "gb_peak", "fits")]
#'
#' @export
estimate_sequence_matrix_size <- function(x,
                                          max_per_species = c(NA, 20, 10),
                                          max_per_genus = c(NA, 1000, 500, 250),
                                          max_seqs_per_taxon = NULL,
                                          by_genus = TRUE,
                                          max_foreign_reps_per_genus = 20L,
                                          n_ranks = 3L,
                                          calibration = NULL,
                                          memory_budget_fraction = 0.7,
                                          available_gb = NULL) {
  if (!is.data.frame(x) || !all(c("genus", "species") %in% names(x))) {
    stop("x must be a data frame with `genus` and `species` columns")
  }
  check_caps <- function(v, nm) {
    if (!is.numeric(v) && !all(is.na(v))) stop(nm, " must be numeric (NA for no cap)")
    if (any(!is.na(v) & v < 1)) stop(nm, " values must be positive or NA")
    unique(as.numeric(v))
  }
  max_per_species <- check_caps(max_per_species, "max_per_species")
  max_per_genus <- check_caps(max_per_genus, "max_per_genus")
  if (!is.numeric(memory_budget_fraction) || length(memory_budget_fraction) != 1L ||
    is.na(memory_budget_fraction) || memory_budget_fraction <= 0 ||
    memory_budget_fraction > 1) {
    stop("memory_budget_fraction must be a single number in (0, 1]")
  }

  # Normalise to one row per sequence.
  rows <- x
  if ("n" %in% names(x) && !any(c("acc", "acc_version", "composite_id") %in% names(x))) {
    n <- as.integer(x$n)
    n[is.na(n) | n < 0L] <- 0L
    rows <- x[rep(seq_len(nrow(x)), n), c("genus", "species"), drop = FALSE]
    rows$composite_id <- paste0(rows$species, "#", sequence(n))
  }
  if (!"in_barcode_range" %in% names(rows)) rows$in_barcode_range <- TRUE
  # What build_sequence_matrix() can align: a named species in a named genus,
  # inside the barcode window.
  ok <- !is.na(rows$genus) & nzchar(trimws(rows$genus)) &
    !is.na(rows$species) & nzchar(trimws(rows$species)) &
    !is.na(rows$in_barcode_range) & rows$in_barcode_range
  rows <- rows[ok, , drop = FALSE]
  exempt <- if ("cap_exempt" %in% names(rows)) rows$cap_exempt %in% TRUE else NULL
  id_col <- intersect(c("acc", "acc_version", "composite_id"), names(rows))[1L]
  key <- .stable_key(rows[[id_col]])
  all_species <- unique(rows$species)
  sp_code <- match(rows$species, all_species)
  # Each species belongs to one genus for counting; a species name recorded
  # under two genera is counted under the first.
  sp_genus <- match(rows$genus, unique(rows$genus))[match(seq_along(all_species), sp_code)]

  k <- .matrix_size_constants()
  cal <- .pool_calibration(calibration)
  r_w <- if (is.null(cal)) k$r_w else cal$r_w
  r_x <- if (is.null(cal)) k$r_x_broad else cal$r_x

  if (is.null(available_gb)) available_gb <- .available_memory_gb()
  budget_gb <- available_gb * memory_budget_fraction

  grid <- expand.grid(
    max_per_species = max_per_species, max_per_genus = max_per_genus,
    KEEP.OUT.ATTRS = FALSE
  )
  dropped <- vector("list", nrow(grid))
  res <- vector("list", nrow(grid))
  for (i in seq_len(nrow(grid))) {
    sp <- grid$max_per_species[i]
    gn <- grid$max_per_genus[i]
    keep <- .cap_mask(
      rows, key, exempt,
      max_per_species = if (is.na(sp)) NULL else sp,
      max_per_genus = if (is.na(gn)) NULL else gn
    )
    per_sp <- tabulate(sp_code[keep], nbins = length(all_species))
    dropped[[i]] <- sort(all_species[per_sp == 0L])
    if (!is.null(max_seqs_per_taxon)) per_sp <- pmin(per_sp, max_seqs_per_taxon)
    n_g <- as.numeric(rowsum(as.numeric(per_sp), sp_genus, reorder = FALSE))
    st <- .matrix_structure(n_g, by_genus, max_foreign_reps_per_genus)
    pred <- .matrix_memory_gb(st, r_w, r_x, n_ranks, k$peak, k)
    ceil <- .matrix_memory_gb(st, 1, 1, n_ranks, k$peak, k)
    res[[i]] <- data.frame(
      n_sequences = st$N, n_genera = st$G, n_species = sum(per_sp > 0L),
      n_species_dropped = length(dropped[[i]]),
      largest_genus = if (length(n_g)) max(n_g) else 0,
      pairs_predicted = round(pred$pairs), pairs_ceiling = st$S_w + st$S_x,
      gb_matrix = pred$gb_matrix, gb_peak = pred$gb_peak,
      gb_peak_ceiling = ceil$gb_peak
    )
  }
  grid <- cbind(grid, do.call(rbind, res))
  grid$fits <- if (is.na(budget_gb)) NA else grid$gb_peak <= budget_gb

  list(
    grid = grid,
    species_dropped = dropped,
    available_gb = available_gb,
    budget_gb = budget_gb,
    rates = list(
      r_w = r_w, r_x = r_x, peak_multiple = k$peak,
      source = if (is.null(cal)) {
        "package defaults (broad COI reference set)"
      } else {
        sprintf("calibration from %d earlier build(s)", cal$n_builds)
      }
    )
  )
}


#' Print a cap grid as a compact table in messages
#' @noRd
.message_size_grid <- function(est) {
  g <- est$grid
  fmt_cap <- function(v) ifelse(is.na(v), "none", format(v))
  lines <- sprintf(
    "  %-8s %-8s %11s %9s %8s %13s %9s %9s  %s",
    fmt_cap(g$max_per_species), fmt_cap(g$max_per_genus),
    format(g$n_sequences, big.mark = ","), format(g$n_genera, big.mark = ","),
    format(g$n_species_dropped, big.mark = ","),
    format(round(g$pairs_predicted), big.mark = ","),
    sprintf("%.1f", g$gb_peak), sprintf("%.1f", g$gb_peak_ceiling),
    ifelse(is.na(g$fits), "?", ifelse(g$fits, "fits", "TOO BIG"))
  )
  message(paste0(
    "Predicted sequence-matrix memory (",
    if (is.na(est$available_gb)) {
      "available memory unknown"
    } else {
      sprintf("%.1f GB available, %.1f GB budget", est$available_gb, est$budget_gb)
    },
    "; retention: ", est$rates$source, "):\n",
    sprintf(
      "  %-8s %-8s %11s %9s %8s %13s %9s %9s\n",
      "species", "genus", "sequences", "genera", "sp.lost", "pairs", "peak GB", "ceil GB"
    ),
    paste(lines, collapse = "\n")
  ))
  invisible(est)
}


# --- The guard in build_sequence_matrix() -------------------------------------

#' Sequences per genus, as build_sequence_matrix() will align them
#' @noRd
.genus_sizes <- function(ref_seqs, by_genus = TRUE) {
  if (!"genus" %in% names(ref_seqs)) {
    return(nrow(ref_seqs))
  }
  g <- ref_seqs$genus
  blank <- is.na(g) | !nzchar(trimws(g))
  # by_genus drops a sequence with no genus; a whole-set alignment keeps it,
  # with no genus to share, so it counts as a group of one.
  c(as.numeric(table(g[!blank])), if (!isTRUE(by_genus)) rep(1, sum(blank)))
}

#' Cross-genus retention measured on a pilot of genus representatives
#'
#' One sequence per genus, up to `n_pilot` genera, all chosen by
#' `.stable_key()` so the pilot consumes no random numbers and leaves the
#' caller's RNG stream -- and so the representatives the real alignment
#' draws -- exactly as they would have been without it.
#' @return The fraction of ordered pilot pairs within `max_dist`, or `NA`
#'   when fewer than two genera are available.
#' @noRd
.pilot_cross_genus_retention <- function(dna, ref_seqs, max_dist, n_pilot = 200L) {
  if (!"genus" %in% names(ref_seqs)) {
    return(NA_real_)
  }
  ok <- !is.na(ref_seqs$genus) & nzchar(trimws(ref_seqs$genus))
  idx <- which(ok)
  key <- .stable_key(ref_seqs$composite_id[idx])
  first <- idx[.rank_within(ref_seqs$genus[idx], key) == 1L]
  if (length(first) < 2L) {
    return(NA_real_)
  }
  first <- first[order(.stable_key(ref_seqs$genus[first]))][seq_len(min(n_pilot, length(first)))]
  k <- length(first)
  pairs <- .decipher_align_pairs(dna[first], max_dist, verbose = FALSE)
  nrow(pairs) / (k * (k - 1))
}

#' Stop before aligning when the matrix will not fit in memory
#'
#' @return Invisibly, the pair structure (`.matrix_structure()`), used for the
#'   result's `size_calibration` attribute. Stops, naming settings that would
#'   fit, when the prediction exceeds `memory_budget_fraction` of available
#'   memory.
#' @noRd
.matrix_memory_guard <- function(ref_seqs, dna, n_ranks, by_genus,
                                 max_foreign_reps_per_genus, max_dist,
                                 memory_budget_fraction, max_seqs_per_taxon) {
  k <- .matrix_size_constants()
  st <- .matrix_structure(.genus_sizes(ref_seqs, by_genus), by_genus, max_foreign_reps_per_genus)
  if (is.null(memory_budget_fraction)) {
    return(invisible(st))
  }
  avail <- .available_memory_gb()
  ceil <- .matrix_memory_gb(st, 1, 1, n_ranks, k$peak, k)
  if (is.na(avail)) {
    message(sprintf(
      paste0(
        "build_sequence_matrix: available memory could not be read on this ",
        "system, so the memory check was skipped (at most %s pairs; ",
        "at most %.1f GB peak through training)."
      ),
      format(st$S_w + st$S_x, big.mark = ","), ceil$gb_peak
    ))
    return(invisible(st))
  }
  budget <- avail * memory_budget_fraction
  if (ceil$gb_peak <= budget) {
    return(invisible(st))
  }

  # The ceiling does not fit, so measure this reference set's own
  # cross-genus retention rather than assume one. Within-genus retention is
  # taken as 1 (0.55-0.95 measured), and the pilot's rate gets a 0.05 margin:
  # repeat samples of 300 genera differed by 0.04.
  r_pilot <- .pilot_cross_genus_retention(dna, ref_seqs, max_dist)
  r_x <- if (is.na(r_pilot)) 1 else min(1, r_pilot + 0.05)
  pred <- .matrix_memory_gb(st, 1, r_x, n_ranks, k$peak, k)
  if (pred$gb_peak <= budget) {
    message(sprintf(
      paste0(
        "build_sequence_matrix: predicted %.1f GB peak through training ",
        "(%s pairs; cross-genus retention %.2f from a pilot) against a %.1f GB ",
        "budget (%.0f%% of %.1f GB available)."
      ),
      pred$gb_peak, format(round(pred$pairs), big.mark = ","), r_x,
      budget, 100 * memory_budget_fraction, avail
    ))
    return(invisible(st))
  }

  # Name settings that would fit: the fetch's own caps, which it applies to
  # its cached metadata without re-fetching, predicted with this reference
  # set's measured cross-genus retention.
  est <- estimate_sequence_matrix_size(
    ref_seqs,
    max_per_species = c(NA, 20, 10),
    max_per_genus = c(NA, 2000, 1000, 500, 250, 100),
    max_seqs_per_taxon = max_seqs_per_taxon,
    by_genus = by_genus,
    max_foreign_reps_per_genus = max_foreign_reps_per_genus,
    n_ranks = n_ranks,
    calibration = list(S_w = 1, S_x = 1, within_pairs = 1, cross_pairs = r_x),
    memory_budget_fraction = memory_budget_fraction,
    available_gb = avail
  )
  fit <- est$grid[est$grid$fits %in% TRUE, , drop = FALSE]
  fit <- fit[order(-fit$n_sequences), , drop = FALSE]
  fmt <- function(v) ifelse(is.na(v), "NULL", format(v))
  suggestions <- if (nrow(fit) == 0L) {
    rep_gb <- .matrix_memory_gb(
      list(S_w = 0, S_x = st$G * (st$G - 1), max_cells = st$G^2),
      1, r_x, n_ranks, k$peak, k
    )$gb_peak
    sprintf(
      paste0(
        "  No cap combination fits. The %s genera alone need about %.1f GB ",
        "(the representative-vs-representative pairs grow with the square of ",
        "the number of genera, and no cap reduces them): fetch a narrower ",
        "taxon list."
      ),
      format(st$G, big.mark = ","), rep_gb
    )
  } else {
    fit <- utils::head(fit, 5L)
    paste(sprintf(
      "  max_per_species = %s, max_per_genus = %s: %s sequences, %s species lost, %.1f GB peak",
      fmt(fit$max_per_species), fmt(fit$max_per_genus),
      format(fit$n_sequences, big.mark = ","),
      format(fit$n_species_dropped, big.mark = ","), fit$gb_peak
    ), collapse = "\n")
  }
  stop(
    sprintf(
      paste0(
        "build_sequence_matrix: this reference set would need about %.1f GB ",
        "at its peak through train_likelihood_model() (%s pairs in a %.1f GB ",
        "table), more than the %.1f GB budget (%.0f%% of %.1f GB available ",
        "now). Stopped before aligning.\n\n",
        "Caps for fetch_ncbi_reference_sequences() that fit, most sequences ",
        "first (it applies them to its cached metadata, so changing them ",
        "re-fetches nothing already downloaded):\n%s\n\n",
        "The prediction uses a cross-genus retention of %.2f measured on a ",
        "pilot of this reference set. To run anyway, pass ",
        "memory_budget_fraction = NULL. See ?estimate_sequence_matrix_size."
      ),
      pred$gb_peak, format(round(pred$pairs), big.mark = ","), pred$gb_matrix,
      budget, 100 * memory_budget_fraction, avail, suggestions, r_x
    ),
    call. = FALSE
  )
}

#' The size_calibration record attached to a build_sequence_matrix() result
#' @noRd
.size_calibration <- function(out, st, by_genus, max_foreign_reps_per_genus, max_dist) {
  within <- if (all(c("genus.x", "genus.y") %in% names(out))) {
    sum(out$genus.x == out$genus.y, na.rm = TRUE)
  } else {
    nrow(out)
  }
  list(
    n_sequences = st$N, n_genera = st$G,
    # The foreign representatives each genus actually received, not the cap
    # requested: two builds that aligned the same pairs record the same value.
    by_genus = by_genus, foreign_reps = st$f,
    max_dist = max_dist,
    S_w = st$S_w, S_x = st$S_x,
    within_pairs = within, cross_pairs = nrow(out) - within,
    r_w = if (st$S_w > 0) within / st$S_w else NA_real_,
    r_x = if (st$S_x > 0) (nrow(out) - within) / st$S_x else NA_real_,
    bytes_per_pair = 8 * ncol(out)
  )
}
