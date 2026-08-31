# ==============================================================================
# convert_taxonomy_backbone.R
# TaxaMatch — Convert match object taxonomy to a target backbone
# NOTE: This is a generic utility that should eventually move to TaxaTools.
#       Written here first because TaxaTools is under manuscript review.
# ==============================================================================


#' Convert Match Object Taxonomy to a Target Backbone
#'
#' Looks up each unique taxon name in `match_df[[taxon_col]]` against a target
#' taxonomic backbone (e.g. GBIF, NCBI), then replaces rank columns with
#' the target backbone's hierarchy wherever the target provides a non-NA
#' value (*per-column fallback*: ranks the target omits are left unchanged).
#'
#' A `taxonomy_collision` column records what happened for each row:
#' \describe{
#'   \item{`"consistent"`}{Taxon found in target backbone; all supplied rank columns agree with the original.}
#'   \item{`"backbone_N[col1,col2]"`}{Taxon found; listed columns were changed to target backbone N values.}
#'   \item{`"backbone_N"` or `"original"`}{Taxon not found in target backbone; hierarchy
#'     unchanged. Label is `"backbone_N"` when `source_backbone_id` is supplied, otherwise
#'     `"original"`.}
#' }
#'
#' A `taxonomy_backbone` column records which backbone the row's hierarchy
#' was drawn from (`"backbone_N"` for found rows, source label for not-found rows).
#'
#' @section Rank correction on fallback (2026-07-25):
#' When a row's own `taxon_name_rank` has no matching target-backbone value
#' at that same rank (e.g. a row claims `"species"` but the target only
#' resolved this name to genus), `match_df[[taxon_col]]` falls back to the
#' coarser resolved name -- and `taxon_name_rank` is now corrected to match
#' it, using `verify_fn`'s `matched_rank` column when present (silently
#' skipped for a `verify_fn` that predates it, e.g. injected for offline
#' testing). Real motivating case: an informally-named NCBI reference
#' ("Inu sp. 1 sensu Shibukawa et al., 2020.") resolves against GBIF to the
#' genus `Luciogobius` (a synonym relationship -- GBIF's own backbone
#' considers `"Inu"` Snyder 1909 a synonym of `Luciogobius` Gill 1859; NCBI's
#' own taxonomy does not) with no species-level entry to fill. Before this
#' fix, `taxon_name` was correctly demoted to the genus but
#' `taxon_name_rank` silently stayed `"species"` -- a downstream slash-name
#' builder then treated the bare genus as if it were a complete binomial and
#' manufactured a fabricated pseudo-binomial (`"Inu Inu"`) from it. Confirmed
#' backbone-general, not GBIF-specific, before shipping -- see
#' `TaxaTools::verify_taxon_names()`'s own `@section Synonym resolution and
#' rank correctness`.
#'
#' **Finer rank columns are also cleared on the same rows** (e.g. `species`
#' set to `NA` when the row is demoted to genus), not just
#' `taxon_name`/`taxon_name_rank`. Found necessary by testing against a real
#' production workflow, not by inspection alone: the per-column fallback
#' (documented above) deliberately keeps each rank column's own cleaned
#' original value when the target backbone has no replacement for it --
#' correct for a column that genuinely didn't change, but it left a stale,
#' semantically-invalid value (`species = "Inu"`) in place even after
#' `taxon_name`/`taxon_name_rank` were correctly demoted. Any code that
#' re-derives a name from rank columns after calling this function (e.g. a
#' second `TaxaTools::create_taxon_names()` call, a real step some
#' production workflows already run "to re-derive taxon_name after backbone
#' conversion") would otherwise see `species` still populated, apply
#' "most specific non-NA rank wins", and silently undo the correction.
#'
#' @section Rank correction on a genus-collapsing name, any source (2026-08-21):
#' The `matched_rank`-driven correction above only fires when the target
#' backbone's own reported rank disagrees with the row's claimed rank. A
#' second, independent mechanism corrects `taxon_name_rank` whenever the
#' value that actually ended up in `taxon_name` was produced by
#' [TaxaTools::clean_taxon_names()] COLLAPSING a real second token to
#' genus-only -- regardless of which of the three possible sources produced
#' it (a not-found row's fallback cleaning; a found row's `matched_name_clean`
#' fallback when its own rank had no target value; or a found row's own
#' `target_<rank>` value at its claimed rank). This closes two real,
#' independently-discovered cases from GreatLakes2023 production data:
#' (1) an open-nomenclature, specimen-voucher-tagged reference label (e.g.
#' `"Ictalurus cf. pricei USON-01120-1"`) that never resolves in the target
#' backbone at all (`found_mask = FALSE`); and (2), found only after
#' verifying (1)'s original fix against a real re-run and still finding
#' stale rows: NCBI's own taxonomy DB genuinely contains leaf-level nodes
#' for informally-named specimens (e.g. a real node literally named
#' `"Ictalurus sp. UM 105-1789"`, ranked `"species"` by NCBI itself) -- here
#' `found_mask = TRUE` and `matched_rank` genuinely IS `"species"`
#' (backbone-consistent, so the `matched_rank`-driven correction correctly
#' does nothing), but the classification path's own species-rank VALUE is
#' that same informal label, which collapses to genus-only when cleaned.
#' No rank-MISMATCH-based correction can ever catch case (2) -- the
#' backbone's own rank claim is genuinely self-consistent; only the collapse
#' signal itself reveals the problem. Before this fix, `taxon_name_rank`
#' stayed stale at whatever rank the row claimed before conversion,
#' mislabeling a bare genus as if it were still species-level.
#'
#' Deliberately tracks the actual collapse event through the pipeline (via
#' `collapsed_to_genus`) rather than re-deriving the signal from the final
#' value's shape (e.g. via [TaxaTools::is_plausible_binomial()]) -- that
#' function's binomial regex requires a literal space immediately after the
#' genus token, which a real hyphenated genus (e.g. *Pseudo-nitzschia*,
#' already a real fixture elsewhere in this ecosystem's own test suite)
#' fails, which would have wrongly demoted every hyphenated-genus species
#' row. Requires `"genus"` to be present in `rank_system`; a no-op
#' otherwise. Gracefully absent (no-op) for a `clean_taxon_names()`-alike
#' that predates the `collapsed_to_genus` attribute. Rank columns finer than
#' the demoted rank are cleared, same as the `matched_rank`-driven
#' correction above.
#'
#' An R attribute `backbone_cols` is set on the returned data frame recording
#' which rank columns were subject to backbone conversion. A summary message
#' is also printed.
#'
#' @param match_df A data frame containing a taxon name column and rank columns.
#' @param target_backbone_id Integer. The target backbone identifier.
#'   Standard IDs: 1 = Catalogue of Life, 3 = ITIS, 4 = NCBI, 9 = WoRMS,
#'   11 = GBIF. See <https://verifier.globalnames.org/> for the full list.
#' @param source_backbone_id Integer or `NULL`. The backbone that produced
#'   `match_df`'s current hierarchy. Used only to label the `taxonomy_collision`
#'   column for rows not found in the target backbone. When `NULL` (default),
#'   not-found rows are labelled `"original"`.
#' @param rank_system Character vector of rank column names to compare and
#'   potentially update, listed broadest to finest (e.g.
#'   `c("order", "family", "genus", "species")`). Columns absent from `match_df`
#'   are silently skipped.
#' @param taxon_col Character. Name of the column containing the taxon name
#'   used as the lookup key (default `"taxon_name"`).
#' @param update_taxon_name Logical. When `TRUE` (default), `match_df[[taxon_col]]`
#'   is updated to the target backbone's accepted name (authority strings
#'   stripped via [TaxaTools::clean_taxon_names()]). The original value is
#'   preserved in `match_df[[original_col]]`.
#' @param original_col Character. Name of the column to receive the original
#'   taxon name when `update_taxon_name = TRUE` (default `"taxon_name_original"`).
#'   Created if absent; unchanged if already present.
#' @param backbone_col Character. Name of the column recording which backbone
#'   each row's hierarchy came from (default `"taxonomy_backbone"`). Created if absent.
#' @param collision_col Character. Name of the column recording the per-row
#'   conversion outcome (default `"taxonomy_collision"`). Created if absent.
#' @param verify_fn Function. The name verification function to call. Must
#'   accept a character vector as its first argument and a `backbone_id`
#'   argument; must return a data frame with columns `user_supplied_name`,
#'   `matched_name`, `classification_path`, `classification_ranks`, and
#'   `verified` (logical: `TRUE` when the name resolved in the target
#'   backbone, `FALSE`/`NA` otherwise). An optional `matched_rank` column
#'   (the rank `matched_name` actually resolved at) enables the rank
#'   correction described below; a `verify_fn` without it is still fully
#'   supported, just without that correction. Default:
#'   [TaxaTools::verify_taxon_names].
#'   Override for offline testing via dependency injection. The call is
#'   wrapped in `tryCatch()`; a failure (e.g. network unavailable, API
#'   rate-limited) raises a clear error naming the likely cause rather than
#'   propagating whatever uninformative error the API layer produced.
#' @param verbose Logical. Print the backbone column mapping summary message
#'   at the end. Default `TRUE`. `warning()`s for inconsistent taxonomy are
#'   always issued regardless of this setting.
#'
#' @return `match_df` with rank columns potentially updated, plus `backbone_col`,
#'   `collision_col`, and (when `update_taxon_name = TRUE`) `original_col`
#'   columns added -- `backbone_col`/`collision_col` are created if absent
#'   and left unchanged (not overwritten) if already present, which matters
#'   for iterative/multi-pass pipeline use. The attribute `backbone_cols` is
#'   set: a named list mapping `"backbone_N_cols"` to the rank column names
#'   that were subject to conversion, e.g.
#'   `list(backbone_11_cols = c("order", "family"), backbone_4_cols = c("kingdom", "phylum"))`.
#'   Because R uses copy-on-modify semantics, the caller's original
#'   `match_df` object is untouched; the return value must be (re)assigned.
#'
#' @note
#' This function issues one API call to `verify_fn` covering all unique
#' non-NA taxon names in `match_df`. Rank updates and collision detection are
#' performed with vectorised operations (no row-by-row loop).
#'
#' Taxonomic backbones assign different family/order hierarchies to the same
#' species (e.g. NCBI places *Girella nigricans* in Girellidae; GBIF places
#' it in Kyphosidae). Call `convert_taxonomy_backbone()` on your match object
#' before passing it to [TaxaMatch::filter_redundant_hypotheses()] or to
#' [TaxaAssign::join_priors()] when the prior expansion taxonomy was built
#' from a different backbone. For eDNA metabarcoding specifically, WoRMS
#' (backbone 9) is the authoritative backbone for marine species; GBIF (11)
#' is the more general default for terrestrial/mixed studies.
#'
#' Lookup is by taxon *name*, not ID (the correct approach for cross-backbone
#' conversion, since IDs are backbone-specific), which means homonyms --
#' the same name used for unrelated taxa in different kingdoms, e.g. *Morus*
#' (a plant genus, mulberry, and a bird genus, gannets) -- can resolve to the
#' more common usage rather than the intended one. Filter to a single kingdom
#' before conversion, or verify results for known homonymous genera. Each
#' unique `taxon_col` value is also resolved independently (no genus-up
#' cascade): if a species name is not found in the target backbone, that
#' row's hierarchy is left unchanged even when the genus or family *is*
#' present in the target -- whether that is the desired behavior depends on
#' the use case.
#'
#' Whitespace-only taxon names (e.g. `" "`) are treated as present, not
#' blank, by the `nzchar()` checks used throughout (`nzchar(" ")` is `TRUE`);
#' if this is a realistic data-quality issue for your input, `trimws()` your
#' `taxon_col` before calling.
#'
#' @section Not-found rows are cleaned too:
#' When a taxon is not found in the target backbone, its original rank
#' columns and `taxon_col` value are still run through
#' [TaxaTools::clean_taxon_names()] before being used as the output value --
#' previously only target-backbone-matched values were cleaned, so an exotic
#' name that failed to resolve (e.g. a compound hybrid-formula name straight
#' from a raw reference-database accession label,
#' `"((Citrus unshiu x Citrus sinensis) x Citrus reticulata) x Citrus reticulata"`)
#' passed through completely unmodified. This does NOT change which names are
#' sent to `verify_fn` or which rows count as "found" -- only the fallback
#' value's formatting.
#'
#' @seealso [TaxaTools::verify_taxon_names()], [TaxaTools::clean_taxon_names()]
#'
#' @examples
#' \dontrun{
#' # Convert a BLAST match object (NCBI backbone, backbone_id = 4) to GBIF (11)
#' match_obj_gbif <- convert_taxonomy_backbone(
#'   match_df           = match_obj,
#'   target_backbone_id = 11,
#'   source_backbone_id = 4,
#'   rank_system        = c("order", "family", "genus", "species")
#' )
#' attr(match_obj_gbif, "backbone_cols")
#' }
#'
#' @importFrom TaxaTools clean_taxon_names
#'
#' @export
convert_taxonomy_backbone <- function(
  match_df,
  target_backbone_id,
  source_backbone_id = NULL,
  rank_system        = c("order", "family", "genus", "species"),
  taxon_col          = "taxon_name",
  update_taxon_name  = TRUE,
  original_col       = "taxon_name_original",
  backbone_col       = "taxonomy_backbone",
  collision_col      = "taxonomy_collision",
  verify_fn          = TaxaTools::verify_taxon_names,
  verbose            = TRUE
) {

  # ---------------------------------------------------------------------------
  # Input validation
  # ---------------------------------------------------------------------------
  if (!is.data.frame(match_df)) {
    stop("`match_df` must be a data frame.")
  }
  if (!taxon_col %in% names(match_df)) {
    stop(sprintf("Column '%s' not found in `match_df`.", taxon_col))
  }
  if (!is.numeric(target_backbone_id) || length(target_backbone_id) != 1L ||
      is.na(target_backbone_id)) {
    stop("`target_backbone_id` must be a single non-NA numeric value.")
  }
  if (!is.null(source_backbone_id) &&
      (!is.numeric(source_backbone_id) || length(source_backbone_id) != 1L ||
       is.na(source_backbone_id))) {
    stop("`source_backbone_id` must be a single non-NA numeric value, or NULL.")
  }

  rank_cols_present <- intersect(rank_system, names(match_df))
  if (length(rank_cols_present) == 0L) {
    stop(
      "None of the `rank_system` columns (",
      paste0("'", rank_system, "'", collapse = ", "),
      ") are present in `match_df`."
    )
  }

  # ---------------------------------------------------------------------------
  # Unique taxon names to query
  # ---------------------------------------------------------------------------
  unique_names <- unique(match_df[[taxon_col]])
  unique_names <- unique_names[!is.na(unique_names) & nzchar(unique_names)]

  if (length(unique_names) == 0L) {
    warning("All values in `taxon_col` are NA or empty; nothing to convert.")
    return(match_df)
  }

  # classification_path/classification_ranks are parsed on "|" below; a
  # taxon name that itself contains "|" would corrupt that parse.
  pipe_names <- unique_names[grepl("|", unique_names, fixed = TRUE)]
  if (length(pipe_names) > 0L) {
    warning(sprintf(
      paste0(
        "convert_taxonomy_backbone: %d taxon name(s) contain '|' (the ",
        "classification_path delimiter), which may corrupt rank parsing: %s"
      ),
      length(pipe_names), paste(utils::head(pipe_names, 5L), collapse = ", ")
    ))
  }

  # ---------------------------------------------------------------------------
  # Query target backbone (single batched API call on unique names)
  # ---------------------------------------------------------------------------
  verified <- tryCatch(
    verify_fn(unique_names, backbone_id = target_backbone_id),
    error = function(e) {
      stop(
        "convert_taxonomy_backbone: verify_fn call failed -- check network ",
        "access, the target_backbone_id, or provide a local verify_fn. ",
        "Original error: ", conditionMessage(e),
        call. = FALSE
      )
    }
  )

  if (anyDuplicated(verified$user_supplied_name) > 0L) {
    stop(
      "convert_taxonomy_backbone: verify_fn returned duplicate ",
      "user_supplied_name values; cannot uniquely match rows back to ",
      "`match_df`. This indicates a verify_fn contract violation."
    )
  }

  # A quick sanity check on the delimiter assumption: if rank_system has
  # more than one entry but not a single non-NA classification_path/
  # classification_ranks value contains the "|" delimiter, verify_fn's
  # response format has likely changed (or a custom verify_fn doesn't
  # follow the documented contract).
  non_na_path  <- stats::na.omit(verified$classification_path)
  non_na_ranks <- stats::na.omit(verified$classification_ranks)
  if (length(rank_system) > 1L && length(non_na_path) > 0L &&
      !any(grepl("|", non_na_path, fixed = TRUE)) &&
      !any(grepl("|", non_na_ranks, fixed = TRUE))) {
    warning(
      "convert_taxonomy_backbone: none of verify_fn's classification_path/",
      "classification_ranks values contain the expected '|' delimiter; ",
      "rank extraction below will likely return all-NA. Confirm verify_fn's ",
      "output format matches the documented contract."
    )
  }

  # Strip authority strings from matched names
  verified$matched_name_clean <- TaxaTools::clean_taxon_names(verified$matched_name)

  # ---------------------------------------------------------------------------
  # Parse rank values from classification_path
  # Split once per unique name; extract each rank by position — avoids
  # repeated strsplit calls that the previous mapply(parse_classification_path)
  # approach incurred (one split per rank × per unique name).
  # ---------------------------------------------------------------------------
  path_list  <- strsplit(verified$classification_path,  "|", fixed = TRUE)
  ranks_list <- strsplit(verified$classification_ranks, "|", fixed = TRUE)

  # target_collapsed_list[[rk]]: parallel to target_<rk>, TRUE where
  # clean_taxon_names() collapsed that rank's raw classification_path value
  # to genus-only (see the unified collapse-correction block below -- this is
  # what lets a row whose BACKBONE-reported rank is genuinely "species", but
  # whose species-rank NAME is an informal/open-nomenclature placeholder, be
  # caught -- a case the matched_rank-driven correction cannot see, since
  # matched_rank itself is correct/consistent in that scenario).
  target_collapsed_list <- list()
  for (rk in rank_system) {
    raw_vals <- mapply(function(path, ranks) {
      if (length(ranks) == 1L && is.na(ranks)) return(NA_character_)
      idx <- match(rk, ranks)
      if (is.na(idx) || idx > length(path)) NA_character_ else path[[idx]]
    }, path_list, ranks_list, USE.NAMES = FALSE)
    # Strip authority strings here too (not just from matched_name) --
    # otherwise a classification_path entry carrying an authority string
    # can register a false "changed" collision against an already-clean
    # original rank value that names the same taxon.
    cleaned_rk <- TaxaTools::clean_taxon_names(raw_vals)
    verified[[paste0("target_", rk)]] <- cleaned_rk
    collapsed_rk <- attr(cleaned_rk, "collapsed_to_genus")
    target_collapsed_list[[rk]] <- if (is.null(collapsed_rk)) {
      rep(FALSE, length(raw_vals))
    } else {
      collapsed_rk
    }
  }

  # ---------------------------------------------------------------------------
  # Labels
  # ---------------------------------------------------------------------------
  target_label <- paste0("backbone_", target_backbone_id)
  source_label <- if (!is.null(source_backbone_id)) {
    paste0("backbone_", source_backbone_id)
  } else {
    "original"
  }

  # ---------------------------------------------------------------------------
  # Per-row index into verified table
  # lookup_idx[i] = row in `verified` for match_df row i; NA when name not found
  # or when match_df[[taxon_col]][i] is NA / empty.
  # ---------------------------------------------------------------------------
  lookup_idx <- match(match_df[[taxon_col]], verified$user_supplied_name)

  # A row is "found" when the API was reached (verified = TRUE).
  # verified$verified[NA] returns NA; !is.na(NA) = FALSE → found_mask = FALSE
  # for rows with NA/empty taxon_name, as required.
  found_mask <- !is.na(lookup_idx) & verified$verified[lookup_idx]

  # ---------------------------------------------------------------------------
  # Prepare output columns
  # ---------------------------------------------------------------------------
  if (!backbone_col  %in% names(match_df)) match_df[[backbone_col]]  <- NA_character_
  if (!collision_col %in% names(match_df)) match_df[[collision_col]] <- NA_character_
  if (update_taxon_name && !original_col %in% names(match_df)) {
    match_df[[original_col]] <- match_df[[taxon_col]]
  }

  # ---------------------------------------------------------------------------
  # Save original rank values BEFORE updating (needed for collision detection)
  # ---------------------------------------------------------------------------
  original_ranks <- match_df[, rank_cols_present, drop = FALSE]

  # ---------------------------------------------------------------------------
  # Cleaned fallback values -- used whenever a row's taxon was NOT found in the
  # target backbone (found_mask FALSE). Only the target-backbone-matched values
  # (matched_name_clean, target_<rank>, above) were ever run through
  # clean_taxon_names() before this fix -- a taxon that failed to resolve in the
  # target backbone (e.g. a compound hybrid-formula name straight from a raw
  # reference-database accession label, such as
  # "((Citrus unshiu x Citrus sinensis) x Citrus reticulata) x Citrus reticulata")
  # fell through with its messy original value untouched, purely because the
  # target backbone had nothing to offer for it. clean_taxon_names() is a no-op
  # on already-clean values, so this is safe for the common case too.
  # Deliberately does NOT change unique_names/verify_fn's input above -- the set
  # of names looked up, and which rows count as "found", is unaffected; only the
  # not-found fallback value itself is cleaned.
  # ---------------------------------------------------------------------------
  taxon_col_clean_fallback <- TaxaTools::clean_taxon_names(match_df[[taxon_col]])
  rank_clean_fallback <- lapply(original_ranks, TaxaTools::clean_taxon_names)

  # ---------------------------------------------------------------------------
  # Vectorised collision detection
  # changed_matrix[i, j] = TRUE when rank j was different in the target backbone
  # (target not NA, original not NA, and values differ)
  # ---------------------------------------------------------------------------
  changed_matrix <- matrix(FALSE,
                            nrow     = nrow(match_df),
                            ncol     = length(rank_cols_present),
                            dimnames = list(NULL, rank_cols_present))

  for (j in seq_along(rank_cols_present)) {
    rk          <- rank_cols_present[j]
    target_vals <- verified[[paste0("target_", rk)]][lookup_idx]
    orig_vals   <- original_ranks[[rk]]
    changed_matrix[, j] <- found_mask       &
                            !is.na(target_vals) &
                            !is.na(orig_vals)   &
                            (orig_vals != target_vals)
  }

  n_changed_per_row <- rowSums(changed_matrix)

  # Build changed-column label strings for rows where something changed.
  # apply() operates on a logical matrix (fast) and only on the changed subset.
  changed_labels <- character(nrow(match_df))
  rows_with_changes <- which(n_changed_per_row > 0L)
  if (length(rows_with_changes) > 0L) {
    changed_labels[rows_with_changes] <- apply(
      changed_matrix[rows_with_changes, , drop = FALSE], 1L,
      function(row) paste(sort(rank_cols_present[row]), collapse = ",")
    )
  }

  # ---------------------------------------------------------------------------
  # Vectorised backbone and collision columns
  # Rows with NA / empty taxon_name were never looked up; leave their
  # diagnostic columns NA (matching the original row-loop `next` behaviour).
  # ---------------------------------------------------------------------------
  has_name <- !is.na(match_df[[taxon_col]]) & nzchar(match_df[[taxon_col]])

  match_df[[backbone_col]] <- ifelse(found_mask, target_label,
                                     ifelse(has_name, source_label, NA_character_))

  collision_vec <- ifelse(has_name, source_label, NA_character_)
  collision_vec[found_mask & n_changed_per_row == 0L] <- "consistent"
  if (length(rows_with_changes) > 0L) {
    collision_vec[rows_with_changes] <- sprintf(
      "%s[%s]", target_label, changed_labels[rows_with_changes]
    )
  }
  match_df[[collision_col]] <- collision_vec

  # ---------------------------------------------------------------------------
  # Vectorised rank column updates
  # Replace each rank column where the target backbone provides a non-NA value.
  # ---------------------------------------------------------------------------
  for (rk in rank_cols_present) {
    target_vals      <- verified[[paste0("target_", rk)]][lookup_idx]
    has_target       <- found_mask & !is.na(target_vals)
    match_df[[rk]]   <- ifelse(has_target, target_vals, rank_clean_fallback[[rk]])
  }

  # ---------------------------------------------------------------------------
  # Vectorised taxon_name update
  # ---------------------------------------------------------------------------
  if (update_taxon_name) {
    if ("taxon_name_rank" %in% names(match_df)) {
      # Build a matrix of target values: rows = verified rows, cols = rank_system.
      # Matrix indexing then extracts the right value per row using the row's own
      # taxon_name_rank, without any element-wise loop.
      target_mat <- do.call(cbind, lapply(rank_system, function(rk) {
        col <- paste0("target_", rk)
        if (col %in% names(verified)) verified[[col]]
        else rep(NA_character_, nrow(verified))
      }))
      target_collapsed_mat <- do.call(cbind, lapply(rank_system, function(rk) {
        if (!is.null(target_collapsed_list[[rk]])) target_collapsed_list[[rk]]
        else rep(FALSE, nrow(verified))
      }))

      rank_col_idx <- match(match_df$taxon_name_rank, rank_system)
      rank_vals    <- rep(NA_character_, nrow(match_df))
      rank_vals_collapsed <- rep(FALSE, nrow(match_df))
      valid        <- !is.na(lookup_idx) & !is.na(rank_col_idx)
      if (any(valid)) {
        rank_vals[valid] <- target_mat[cbind(lookup_idx[valid], rank_col_idx[valid])]
        rank_vals_collapsed[valid] <- target_collapsed_mat[cbind(lookup_idx[valid], rank_col_idx[valid])]
      }

      # A row's own taxon_name_rank has no target value at that SAME rank --
      # e.g. the row claims "species" but the target backbone only resolved
      # this name to genus (a real case: an informally-named reference
      # sequence like "Inu sp. 1 sensu Shibukawa et al., 2020." matches
      # GBIF's genus "Luciogobius", a synonym relationship, with no
      # species-level entry to fill target_species). used_fallback marks
      # these rows so taxon_name_rank can be corrected below, alongside the
      # name itself.
      used_fallback <- found_mask & (is.na(rank_vals) | !nzchar(rank_vals))

      # Prefer rank-specific value (authority-free from classification_path);
      # fall back to matched_name_clean for ranks not in rank_system.
      new_names <- ifelse(
        found_mask & !is.na(rank_vals) & nzchar(rank_vals),
        rank_vals,
        ifelse(found_mask, verified$matched_name_clean[lookup_idx], taxon_col_clean_fallback)
      )
    } else {
      used_fallback <- found_mask
      new_names <- ifelse(
        found_mask,
        verified$matched_name_clean[lookup_idx],
        taxon_col_clean_fallback
      )
    }

    # Only update where we have a valid non-empty new name
    update_mask          <- found_mask & !is.na(new_names) & nzchar(new_names)
    match_df[[taxon_col]] <- ifelse(update_mask, new_names, taxon_col_clean_fallback)

    # ---------------------------------------------------------------------
    # Correct taxon_name_rank for fallback rows, AND clear rank columns
    # finer than the corrected rank.
    #
    # Without the taxon_name_rank correction, a row whose name just got
    # replaced by a coarser-rank fallback value (matched_name_clean) keeps
    # its OLD, now-stale rank label -- e.g. taxon_name = "Luciogobius" (a
    # genus) reported with taxon_name_rank still "species", the exact
    # mislabeling that let a downstream slash-name builder manufacture a
    # fabricated pseudo-binomial ("Inu Inu") from a bare genus name.
    #
    # The finer-column clearing is a SEPARATE, necessary second half, found
    # only by testing this against a real production workflow: the
    # per-column rank fallback above (rank_clean_fallback) deliberately
    # keeps each individual rank column's own cleaned original value when
    # the target backbone has no replacement for it -- correct for a column
    # that genuinely didn't change, but for THIS row it left
    # match_df$species = "Inu" in place even after taxon_name/
    # taxon_name_rank were correctly demoted to the genus "Luciogobius".
    # Anything that re-derives a name from rank columns after this point
    # (e.g. a second TaxaTools::create_taxon_names() call -- a real,
    # existing step in production Mugu-workflow scripts, not a
    # hypothetical) sees species still populated, "most specific non-NA
    # rank wins", and silently reverts the correction. Clearing every rank
    # column finer than matched_rank closes this regardless of what any
    # downstream code does with the result.
    #
    # matched_rank (verify_taxon_names(), 2026-07-25) is the authoritative
    # rank the match actually resolved at -- only used where the fallback
    # fired and a corrected rank is available, so a row whose own rank's
    # target value WAS found is left completely untouched by either half of
    # this block. Silently skipped (not an error) when verified lacks
    # matched_rank -- e.g. a custom verify_fn supplied for offline testing
    # that predates it.
    # ---------------------------------------------------------------------
    if ("matched_rank" %in% names(verified)) {
      matched_ranks     <- verified$matched_rank[lookup_idx]
      update_rank_mask  <- update_mask & used_fallback &
                            !is.na(matched_ranks) & nzchar(matched_ranks)
      if (any(update_rank_mask)) {
        match_df$taxon_name_rank[update_rank_mask] <- matched_ranks[update_rank_mask]

        matched_rank_pos <- match(matched_ranks, rank_system)
        for (j in seq_along(rank_system)) {
          rk <- rank_system[j]
          if (!rk %in% rank_cols_present) next
          clear_mask <- update_rank_mask & !is.na(matched_rank_pos) & (j > matched_rank_pos)
          if (any(clear_mask)) match_df[[rk]][clear_mask] <- NA_character_
        }
      }
    }

    # -------------------------------------------------------------------
    # Correct taxon_name_rank whenever the value that ended up populating
    # taxon_name was produced by clean_taxon_names() COLLAPSING a real
    # second token to genus-only -- regardless of WHICH of the three
    # possible sources produced it (2026-08-21). This is a genuinely
    # different, unified successor to a narrower same-day fix that only
    # covered the not-found path (see git history) -- kept as ONE
    # mechanism, not three, specifically because a second real case was
    # found the same day that the narrower fix could not catch:
    #
    # Real motivating cases, both from GreatLakes2023 production data.
    # (1) Not-found path: TaxaLikely::restore_suppressed_candidates()
    # copies a reference row's raw, open-nomenclature species value
    # ("Ictalurus cf. pricei USON-01120-1", a specimen-voucher-tagged NCBI
    # label) into a restored candidate; TaxaTools::create_taxon_names()
    # sets taxon_name_rank = "species" purely because the species column
    # is populated. This name fails an exact-name lookup entirely
    # (found_mask = FALSE); the not-found fallback's own
    # clean_taxon_names() call correctly collapses taxon_name to
    # "Ictalurus" (case C below).
    # (2) Found path, discovered when case (1)'s original fix was verified
    # against real re-run output and still found 33 stale rows: NCBI's own
    # taxonomy DB genuinely contains leaf-level nodes for informally-named
    # specimens (e.g. a real node literally named
    # "Ictalurus sp. UM 105-1789", ranked "species" by NCBI itself, not a
    # rank mismatch at all) -- found_mask = TRUE, matched_rank IS "species"
    # (backbone-consistent, so the matched_rank-driven correction above
    # correctly does nothing), but the classification_path's own
    # species-rank VALUE is that same informal label, which
    # clean_taxon_names() correctly collapses to "Ictalurus" when building
    # target_species (case A below). No rank-mismatch-based correction can
    # ever catch this -- the backbone's own rank claim is genuinely
    # self-consistent; only the collapse signal reveals the problem.
    #
    # Three possible sources for the final taxon_name value, matching the
    # three branches above that build new_names / taxon_col_clean_fallback:
    #   A. found_mask & the row's own claimed rank has a target value
    #      (rank_vals, from target_<rank> -- collapse tracked per rank via
    #      target_collapsed_mat/rank_vals_collapsed).
    #   B. found_mask & no target value at that rank (used_fallback) ->
    #      matched_name_clean.
    #   C. !found_mask -> taxon_col_clean_fallback (the original
    #      not-found-only fix, now folded in as one case of this one).
    # Whichever source actually produced the value is the one whose own
    # collapsed_to_genus flag is consulted -- never mixed across cases.
    #
    # Uses clean_taxon_names()'s own collapsed_to_genus attribute
    # throughout rather than re-deriving the signal from the final value's
    # shape (e.g. via TaxaTools::is_plausible_binomial()) -- deliberately
    # rejected: that function's binomial regex requires a literal space
    # right after the genus token, which a real hyphenated genus (e.g.
    # Pseudo-nitzschia, already a real fixture case elsewhere in this
    # ecosystem's own test suite) fails, which would have wrongly demoted
    # every hyphenated-genus species row. Tracking the actual collapse
    # event through the pipeline avoids this false-positive class entirely.
    # -------------------------------------------------------------------
    if ("taxon_name_rank" %in% names(match_df)) {
      genus_pos <- match("genus", rank_system)
      if (!is.na(genus_pos)) {
        case_a_mask <- found_mask & !used_fallback
        case_b_mask <- used_fallback
        case_c_mask <- !found_mask

        mnc <- attr(verified$matched_name_clean, "collapsed_to_genus")
        matched_name_collapsed <- rep(FALSE, nrow(match_df))
        if (!is.null(mnc)) {
          idx_ok <- !is.na(lookup_idx)
          matched_name_collapsed[idx_ok] <- mnc[lookup_idx[idx_ok]]
        }

        fallback_collapsed <- attr(taxon_col_clean_fallback, "collapsed_to_genus")
        if (is.null(fallback_collapsed)) fallback_collapsed <- rep(FALSE, nrow(match_df))

        final_collapsed <- rep(FALSE, nrow(match_df))
        final_collapsed[case_a_mask] <- rank_vals_collapsed[case_a_mask]
        final_collapsed[case_b_mask] <- matched_name_collapsed[case_b_mask]
        final_collapsed[case_c_mask] <- fallback_collapsed[case_c_mask]

        # taxon_name_rank AS IT STANDS NOW (i.e. after the matched_rank
        # correction above may already have run) -- so a row that block
        # already correctly demoted is left alone here.
        current_rank_pos <- match(match_df$taxon_name_rank, rank_system)
        demote_mask <- has_name & !is.na(current_rank_pos) &
                        current_rank_pos > genus_pos & final_collapsed

        if (any(demote_mask)) {
          match_df$taxon_name_rank[demote_mask] <- "genus"
          for (j in seq_along(rank_system)) {
            rk <- rank_system[j]
            if (!rk %in% rank_cols_present) next
            clear_mask <- demote_mask & (j > genus_pos)
            if (any(clear_mask)) match_df[[rk]][clear_mask] <- NA_character_
          }
        }
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Warning if any inconsistencies
  # ---------------------------------------------------------------------------
  name_ref_col <- if (update_taxon_name && original_col %in% names(match_df)) {
    original_col
  } else {
    taxon_col
  }
  has_orig_name <- !is.na(match_df[[name_ref_col]]) & nzchar(match_df[[name_ref_col]])
  n_changed   <- sum(n_changed_per_row > 0L)
  n_not_found <- sum(!found_mask & has_orig_name)
  n_issues    <- n_changed + n_not_found
  if (n_issues > 0L) {
    warning(sprintf(
      "%d row(s) have inconsistent taxonomy; see '%s' column.",
      n_issues, collision_col
    ))
  }

  # ---------------------------------------------------------------------------
  # backbone_cols attribute + summary message
  # ---------------------------------------------------------------------------
  bbone_attr <- list()
  bbone_attr[[paste0(target_label, "_cols")]] <- rank_cols_present

  all_rank_cols    <- intersect(names(match_df),
                       c("kingdom", "phylum", "class", "order", "family",
                         "genus", "species", "subspecies"))
  source_only_cols <- setdiff(all_rank_cols, rank_cols_present)
  if (length(source_only_cols) > 0L) {
    bbone_attr[[paste0(source_label, "_cols")]] <- source_only_cols
  }

  attr(match_df, "backbone_cols") <- bbone_attr

  msg_lines <- vapply(names(bbone_attr), function(nm) {
    sprintf("  %s: %s", nm, paste(bbone_attr[[nm]], collapse = ", "))
  }, character(1L))
  if (verbose)
    message("Backbone column mapping:\n", paste(msg_lines, collapse = "\n"))

  match_df
}
