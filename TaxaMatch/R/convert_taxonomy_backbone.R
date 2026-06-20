# ==============================================================================
# convert_taxonomy_backbone.R
# TaxaMatch — Convert match object taxonomy to a target backbone
# NOTE: This is a generic utility that should eventually move to TaxaTools.
#       Written here first because TaxaTools is under manuscript review.
# ==============================================================================


#' Convert Match Object Taxonomy to a Target Backbone
#'
#' Looks up each unique taxon name in `df[[taxon_col]]` against a target
#' taxonomic backbone (e.g. GBIF, NCBI), then replaces rank columns with
#' the target backbone's hierarchy wherever the target provides a non-NA
#' value (*per-column fallback*: ranks the target omits are left unchanged).
#'
#' A `taxonomy_collision` column records what happened for each row:
#' \describe{
#'   \item{`"consistent"`}{Taxon found in target backbone; all supplied rank columns agree with the original.}
#'   \item{`"backbone_N[col1,col2]"`}{Taxon found; listed columns were changed to target backbone N values.}
#'   \item{`"backbone_N"` or `"original"`}{Taxon not found in target backbone; hierarchy unchanged. Label is `"backbone_N"` when `source_backbone_id` is supplied, otherwise `"original"`.}
#' }
#'
#' A `taxonomy_backbone` column records which backbone the row's hierarchy
#' was drawn from (`"backbone_N"` for found rows, source label for not-found rows).
#'
#' An R attribute `backbone_cols` is set on the returned data frame recording
#' which rank columns were subject to backbone conversion. A summary message
#' is also printed.
#'
#' @param df A data frame containing a taxon name column and rank columns.
#' @param target_backbone_id Integer. The target backbone identifier.
#'   Standard IDs: 1 = Catalogue of Life, 3 = ITIS, 4 = NCBI, 9 = WoRMS,
#'   11 = GBIF. See <https://verifier.globalnames.org/> for the full list.
#' @param source_backbone_id Integer or `NULL`. The backbone that produced
#'   `df`'s current hierarchy. Used only to label the `taxonomy_collision`
#'   column for rows not found in the target backbone. When `NULL` (default),
#'   not-found rows are labelled `"original"`.
#' @param rank_system Character vector of rank column names to compare and
#'   potentially update, listed broadest to finest (e.g.
#'   `c("order", "family", "genus", "species")`). Columns absent from `df`
#'   are silently skipped.
#' @param taxon_col Character. Name of the column containing the taxon name
#'   used as the lookup key (default `"taxon_name"`).
#' @param update_taxon_name Logical. When `TRUE` (default), `df[[taxon_col]]`
#'   is updated to the target backbone's accepted name (authority strings
#'   stripped via [TaxaTools::clean_taxon_names()]). The original value is
#'   preserved in `df[[original_col]]`.
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
#'   `verified`. Default: [TaxaTools::verify_taxon_names]. Override for
#'   offline testing via dependency injection.
#'
#' @return `df` with rank columns potentially updated, plus `backbone_col`,
#'   `collision_col`, and (when `update_taxon_name = TRUE`) `original_col`
#'   columns added. The attribute `backbone_cols` is set: a named list
#'   mapping `"backbone_N_cols"` to the rank column names that were subject
#'   to conversion.
#'
#' @note
#' This function issues one API call to `verify_fn` covering all unique
#' non-NA taxon names in `df`. Rank updates and collision detection are
#' performed with vectorised operations (no row-by-row loop).
#'
#' Taxonomic backbones assign different family/order hierarchies to the same
#' species (e.g. NCBI places *Girella nigricans* in Girellidae; GBIF places
#' it in Kyphosidae). Call `convert_taxonomy_backbone()` on your match object
#' before passing it to [TaxaMatch::filter_redundant_hypotheses()] or to
#' [TaxaAssign::join_priors()] when the prior expansion taxonomy was built
#' from a different backbone.
#'
#' @seealso [TaxaTools::verify_taxon_names()], [TaxaTools::clean_taxon_names()]
#'
#' @examples
#' \dontrun{
#' # Convert a BLAST match object (NCBI backbone, backbone_id = 4) to GBIF (11)
#' match_obj_gbif <- convert_taxonomy_backbone(
#'   df                = match_obj,
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
  df,
  target_backbone_id,
  source_backbone_id = NULL,
  rank_system        = c("order", "family", "genus", "species"),
  taxon_col          = "taxon_name",
  update_taxon_name  = TRUE,
  original_col       = "taxon_name_original",
  backbone_col       = "taxonomy_backbone",
  collision_col      = "taxonomy_collision",
  verify_fn          = TaxaTools::verify_taxon_names
) {

  # ---------------------------------------------------------------------------
  # Input validation
  # ---------------------------------------------------------------------------
  if (!is.data.frame(df))
    stop("`df` must be a data frame.")
  if (!taxon_col %in% names(df))
    stop(sprintf("Column '%s' not found in `df`.", taxon_col))
  if (!is.numeric(target_backbone_id) || length(target_backbone_id) != 1L ||
      is.na(target_backbone_id))
    stop("`target_backbone_id` must be a single non-NA numeric value.")
  if (!is.null(source_backbone_id) &&
      (!is.numeric(source_backbone_id) || length(source_backbone_id) != 1L ||
       is.na(source_backbone_id)))
    stop("`source_backbone_id` must be a single non-NA numeric value, or NULL.")

  rank_cols_present <- intersect(rank_system, names(df))
  if (length(rank_cols_present) == 0L)
    stop(
      "None of the `rank_system` columns (",
      paste0("'", rank_system, "'", collapse = ", "),
      ") are present in `df`."
    )

  # ---------------------------------------------------------------------------
  # Unique taxon names to query
  # ---------------------------------------------------------------------------
  unique_names <- unique(df[[taxon_col]])
  unique_names <- unique_names[!is.na(unique_names) & nzchar(unique_names)]

  if (length(unique_names) == 0L) {
    warning("All values in `taxon_col` are NA or empty; nothing to convert.")
    return(df)
  }

  # ---------------------------------------------------------------------------
  # Query target backbone (single batched API call on unique names)
  # ---------------------------------------------------------------------------
  verified <- verify_fn(unique_names, backbone_id = target_backbone_id)

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

  for (rk in rank_system) {
    verified[[paste0("target_", rk)]] <- mapply(function(path, ranks) {
      if (length(ranks) == 1L && is.na(ranks)) return(NA_character_)
      idx <- match(rk, ranks)
      if (is.na(idx) || idx > length(path)) NA_character_ else path[[idx]]
    }, path_list, ranks_list, USE.NAMES = FALSE)
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
  # lookup_idx[i] = row in `verified` for df row i; NA when name not found
  # or when df[[taxon_col]][i] is NA / empty.
  # ---------------------------------------------------------------------------
  lookup_idx <- match(df[[taxon_col]], verified$user_supplied_name)

  # A row is "found" when the API was reached (verified = TRUE).
  # verified$verified[NA] returns NA; !is.na(NA) = FALSE → found_mask = FALSE
  # for rows with NA/empty taxon_name, as required.
  found_mask <- !is.na(lookup_idx) & verified$verified[lookup_idx]

  # ---------------------------------------------------------------------------
  # Prepare output columns
  # ---------------------------------------------------------------------------
  if (!backbone_col  %in% names(df)) df[[backbone_col]]  <- NA_character_
  if (!collision_col %in% names(df)) df[[collision_col]] <- NA_character_
  if (update_taxon_name && !original_col %in% names(df)) {
    df[[original_col]] <- df[[taxon_col]]
  }

  # ---------------------------------------------------------------------------
  # Save original rank values BEFORE updating (needed for collision detection)
  # ---------------------------------------------------------------------------
  original_ranks <- df[, rank_cols_present, drop = FALSE]

  # ---------------------------------------------------------------------------
  # Vectorised collision detection
  # changed_matrix[i, j] = TRUE when rank j was different in the target backbone
  # (target not NA, original not NA, and values differ)
  # ---------------------------------------------------------------------------
  changed_matrix <- matrix(FALSE,
                            nrow     = nrow(df),
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
  changed_labels <- character(nrow(df))
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
  has_name <- !is.na(df[[taxon_col]]) & nzchar(df[[taxon_col]])

  df[[backbone_col]] <- ifelse(found_mask, target_label,
                               ifelse(has_name, source_label, NA_character_))

  collision_vec <- ifelse(has_name, source_label, NA_character_)
  collision_vec[found_mask & n_changed_per_row == 0L] <- "consistent"
  if (length(rows_with_changes) > 0L) {
    collision_vec[rows_with_changes] <- sprintf(
      "%s[%s]", target_label, changed_labels[rows_with_changes]
    )
  }
  df[[collision_col]] <- collision_vec

  # ---------------------------------------------------------------------------
  # Vectorised rank column updates
  # Replace each rank column where the target backbone provides a non-NA value.
  # ---------------------------------------------------------------------------
  for (rk in rank_cols_present) {
    target_vals <- verified[[paste0("target_", rk)]][lookup_idx]
    has_target  <- found_mask & !is.na(target_vals)
    df[[rk]]    <- ifelse(has_target, target_vals, df[[rk]])
  }

  # ---------------------------------------------------------------------------
  # Vectorised taxon_name update
  # ---------------------------------------------------------------------------
  if (update_taxon_name) {
    if ("taxon_name_rank" %in% names(df)) {
      # Build a matrix of target values: rows = verified rows, cols = rank_system.
      # Matrix indexing then extracts the right value per row using the row's own
      # taxon_name_rank, without any element-wise loop.
      target_mat <- do.call(cbind, lapply(rank_system, function(rk) {
        col <- paste0("target_", rk)
        if (col %in% names(verified)) verified[[col]]
        else rep(NA_character_, nrow(verified))
      }))

      rank_col_idx <- match(df$taxon_name_rank, rank_system)
      rank_vals    <- rep(NA_character_, nrow(df))
      valid        <- !is.na(lookup_idx) & !is.na(rank_col_idx)
      if (any(valid)) {
        rank_vals[valid] <- target_mat[cbind(lookup_idx[valid], rank_col_idx[valid])]
      }

      # Prefer rank-specific value (authority-free from classification_path);
      # fall back to matched_name_clean for ranks not in rank_system.
      new_names <- ifelse(
        found_mask & !is.na(rank_vals) & nzchar(rank_vals),
        rank_vals,
        ifelse(found_mask, verified$matched_name_clean[lookup_idx], df[[taxon_col]])
      )
    } else {
      new_names <- ifelse(
        found_mask,
        verified$matched_name_clean[lookup_idx],
        df[[taxon_col]]
      )
    }

    # Only update where we have a valid non-empty new name
    update_mask      <- found_mask & !is.na(new_names) & nzchar(new_names)
    df[[taxon_col]]  <- ifelse(update_mask, new_names, df[[taxon_col]])
  }

  # ---------------------------------------------------------------------------
  # Warning if any inconsistencies
  # ---------------------------------------------------------------------------
  name_ref_col <- if (update_taxon_name && original_col %in% names(df)) original_col else taxon_col
  has_name     <- !is.na(df[[name_ref_col]]) & nzchar(df[[name_ref_col]])
  n_changed   <- sum(n_changed_per_row > 0L)
  n_not_found <- sum(!found_mask & has_name)
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

  all_rank_cols    <- intersect(names(df),
                       c("kingdom", "phylum", "class", "order", "family",
                         "genus", "species", "subspecies"))
  source_only_cols <- setdiff(all_rank_cols, rank_cols_present)
  if (length(source_only_cols) > 0L) {
    bbone_attr[[paste0(source_label, "_cols")]] <- source_only_cols
  }

  attr(df, "backbone_cols") <- bbone_attr

  msg_lines <- vapply(names(bbone_attr), function(nm) {
    sprintf("  %s: %s", nm, paste(bbone_attr[[nm]], collapse = ", "))
  }, character(1L))
  message("Backbone column mapping:\n", paste(msg_lines, collapse = "\n"))

  df
}
