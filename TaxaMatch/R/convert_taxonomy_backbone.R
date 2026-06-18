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
#' This function issues one API call to `verify_fn` per unique non-NA taxon
#' name. All lookups are batched into a single call.
#'
#' Taxonomic backbones assign different family/order hierarchies to the same
#' species (e.g. NCBI places *Girella nigricans* in Girellidae; GBIF places
#' it in Kyphosidae). Call `convert_taxonomy_backbone()` on your match object
#' before passing it to [TaxaMatch::filter_redundant_hypotheses()] or to
#' [TaxaAssign::join_priors()] when the prior expansion taxonomy was built
#' from a different backbone.
#'
#' @seealso [TaxaTools::verify_taxon_names()], [TaxaTools::clean_taxon_names()],
#'   [TaxaTools::parse_classification_path()]
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
#' @importFrom TaxaTools clean_taxon_names parse_classification_path
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
  # Query target backbone
  # ---------------------------------------------------------------------------
  verified <- verify_fn(unique_names, backbone_id = target_backbone_id)

  # Clean matched names (strip authority strings like "(Ayres, 1860)")
  verified$matched_name_clean <- TaxaTools::clean_taxon_names(verified$matched_name)

  # Parse each rank from classification_path
  for (rk in rank_system) {
    verified[[paste0("target_", rk)]] <- mapply(
      TaxaTools::parse_classification_path,
      verified$classification_path,
      verified$classification_ranks,
      MoreArgs  = list(target_rank = rk),
      USE.NAMES = FALSE
    )
  }

  # Build fast lookup: name -> row index in verified
  lookup_idx <- stats::setNames(seq_len(nrow(verified)), verified$user_supplied_name)

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
  # Prepare output columns (add if absent)
  # ---------------------------------------------------------------------------
  if (!backbone_col %in% names(df)) df[[backbone_col]] <- NA_character_
  if (!collision_col %in% names(df)) df[[collision_col]] <- NA_character_

  if (update_taxon_name && !original_col %in% names(df)) {
    df[[original_col]] <- df[[taxon_col]]
  }

  # ---------------------------------------------------------------------------
  # Per-row conversion
  # ---------------------------------------------------------------------------
  n_changed   <- 0L
  n_not_found <- 0L

  for (i in seq_len(nrow(df))) {

    name_i <- df[[taxon_col]][i]
    if (is.na(name_i) || !nzchar(name_i)) next

    vi <- lookup_idx[name_i]

    if (is.na(vi) || !isTRUE(verified$verified[vi])) {
      # Not found in target backbone — keep hierarchy as-is
      df[[backbone_col]][i] <- source_label
      df[[collision_col]][i] <- source_label
      n_not_found <- n_not_found + 1L
      next
    }

    # --- Found: apply per-column fallback ---
    changed_cols <- character(0)

    for (rk in rank_cols_present) {
      target_val   <- verified[[paste0("target_", rk)]][vi]
      original_val <- df[[rk]][i]

      if (!is.na(target_val)) {
        # Target backbone provides a value for this rank
        if (!is.na(original_val) && !identical(target_val, original_val)) {
          # Column differs from original — record change
          changed_cols <- c(changed_cols, rk)
        }
        # Update (whether original was NA or different)
        df[[rk]][i] <- target_val
      }
      # If target_val is NA: leave original value in place (per-column fallback)
    }

    # --- Update taxon_col to accepted name ---
    if (update_taxon_name) {
      # Prefer the parsed rank-column value (extracted from classification_path,
      # always authority-free) over matched_name, which GBIF returns with author
      # strings for genus-level and other uninomial entries (e.g.
      # "Atherinops Steindachner,"). Fall back to matched_name_clean when the
      # rank column cannot supply a value (rank not in rank_system, or NA).
      new_name <- NA_character_
      if ("taxon_name_rank" %in% names(df)) {
        rank_i     <- df$taxon_name_rank[i]
        target_col <- paste0("target_", rank_i)
        if (!is.null(verified[[target_col]])) {
          rank_val <- verified[[target_col]][vi]
          if (!is.na(rank_val) && nzchar(rank_val)) new_name <- rank_val
        }
      }
      if (is.na(new_name) || !nzchar(new_name)) {
        new_name <- verified$matched_name_clean[vi]
      }
      if (!is.na(new_name) && nzchar(new_name)) {
        df[[taxon_col]][i] <- new_name
      }
    }

    # --- Record outcome ---
    df[[backbone_col]][i] <- target_label

    if (length(changed_cols) > 0L) {
      df[[collision_col]][i] <- sprintf(
        "%s[%s]",
        target_label,
        paste(sort(changed_cols), collapse = ",")
      )
      n_changed <- n_changed + 1L
    } else {
      df[[collision_col]][i] <- "consistent"
    }
  }

  # ---------------------------------------------------------------------------
  # Warning if any inconsistencies
  # ---------------------------------------------------------------------------
  n_issues <- n_changed + n_not_found
  if (n_issues > 0L) {
    warning(sprintf(
      "%d row(s) have inconsistent taxonomy; see '%s' column.",
      n_issues,
      collision_col
    ))
  }

  # ---------------------------------------------------------------------------
  # backbone_cols attribute + summary message
  # ---------------------------------------------------------------------------
  bbone_attr <- list()
  bbone_attr[[paste0(target_label, "_cols")]] <- rank_cols_present

  # Rank columns present in df but not in rank_system stayed from the source
  all_rank_cols <- intersect(
    names(df),
    c("kingdom", "phylum", "class", "order", "family", "genus",
      "species", "subspecies")
  )
  source_only_cols <- setdiff(all_rank_cols, rank_cols_present)
  if (length(source_only_cols) > 0L) {
    bbone_attr[[paste0(source_label, "_cols")]] <- source_only_cols
  }

  attr(df, "backbone_cols") <- bbone_attr

  msg_lines <- vapply(names(bbone_attr), function(nm) {
    sprintf("  %s: %s", nm, paste(bbone_attr[[nm]], collapse = ", "))
  }, character(1))
  message("Backbone column mapping:\n", paste(msg_lines, collapse = "\n"))

  df
}
