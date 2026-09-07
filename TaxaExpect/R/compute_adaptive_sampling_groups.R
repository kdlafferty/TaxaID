# compute_adaptive_sampling_groups.R
# TaxaExpect package
#
# Computes a taxon_name -> sampling_group assignment for
# prepare_model_dataframe(sampling_group_col = ...) / train_biodiversity_model_by_group()
# by greedily merging taxa up a taxonomic rank hierarchy until each group's
# typical per-site record count clears a minimum viable sample size --
# analogous to "stratum collapsing" in survey methodology, and structurally
# similar to TaxaAssign::join_priors()'s hierarchical dark-diversity group
# construction (phylum -> genus recursive descent), but merging bottom-up on
# a sample-size criterion rather than descending top-down on singleton
# presence. Added Session 149, design worked through with the user: the
# distinction is between two different questions -- "do I have enough data
# to trust an estimate at this level" (a sample-size question, answerable
# from the data, what this function solves) vs. "were these taxa even
# measured by a comparable detection process" (a domain-knowledge question a
# taxonomic-rank ceiling can only approximate, never fully answer -- hence
# the rank_system ceiling and the always-available custom-group override).

#' Compute an Adaptive Taxonomic Grouping for the Shared-Effort Denominator
#'
#' Greedily merges taxa up a taxonomic rank hierarchy (finest rank first) so
#' that every resulting \code{sampling_group} clears a minimum viable typical
#' per-site record count, without ever merging across the coarsest rank in
#' \code{rank_system} (the "ceiling" -- taxa in different phyla, by default,
#' are never pooled together regardless of how sparse either one is). Groups
#' that already clear the minimum at the finest rank are left there;
#' shortfall groups are merged with their taxonomic siblings (sharing the
#' same parent at the next rank up) and re-checked, escalating only as far
#' as needed.
#'
#' This is the automated alternative to hand-classifying detection-process
#' groups (as the real PtConception 18S workflow originally did with an
#' 11-way manual \code{case_when()}) -- pass the result to
#' \code{\link{prepare_model_dataframe}(sampling_group_col = "sampling_group")}
#' or \code{\link{train_biodiversity_model_by_group}} the same way you would
#' a manually-supplied grouping column. It answers a narrower question than a
#' human classifier would: taxonomic rank is only a proxy for "these taxa
#' share a detection process," never a guarantee of it (two taxa in the same
#' order could still be measured completely differently; two in different
#' orders of the same class usually are not) -- if you know your study
#' system needs a different or additional split (e.g. a genuinely
#' methodological distinction that doesn't line up with taxonomy at all),
#' build \code{sampling_group} yourself and skip this function entirely.
#'
#' @param data Data frame of raw occurrence records (e.g. the output of
#'   \code{\link{create_sites_from_grid}}). Must contain \code{grid_col} and
#'   every rank named in \code{rank_system}.
#' @param rank_system Character vector of taxonomy column names, ordered
#'   finest to coarsest. The last element is the ceiling rank -- groups are
#'   never merged across it. Default \code{c("order", "class", "phylum")}.
#' @param min_n Numeric. Minimum viable typical per-site record count for a
#'   group (see Details for exactly how this is computed). No default --
#'   there is no universal viable effort scale across study systems (a
#'   camera-trap survey and a broad eDNA marker have wildly different typical
#'   per-site counts), matching this ecosystem's convention of requiring an
#'   explicit value rather than shipping a threshold that would be silently
#'   wrong for most callers (see e.g. \code{TaxaAssign::join_priors(
#'   backbone_id = )}).
#' @param grid_col Character. Column identifying spatial sites. Default
#'   \code{"grid_id"}.
#' @param habitat_col Character or \code{NULL}. If supplied, the per-site
#'   record count used to evaluate \code{min_n} is computed per
#'   \code{(grid_col, habitat_col)} combination instead of per \code{grid_col}
#'   alone, matching \code{\link{prepare_model_dataframe}}'s own
#'   \code{n_total_at_site} granularity exactly. Default \code{NULL} (grid
#'   cell only -- a simplification; still directly usable as
#'   \code{sampling_group_col} either way).
#'
#' @details
#' \strong{Effort metric:} for a candidate group (rows sharing a value at the
#' rank currently being evaluated), the metric is the mean record count
#' across the distinct sites (or site x habitat combinations, if
#' \code{habitat_col} is supplied) where that group has at least one record
#' -- i.e. what that group's own \code{n_total_at_site} would typically look
#' like in \code{\link{prepare_model_dataframe}}'s output. Sites where the
#' group has zero records don't enter the average, matching how
#' \code{n_total_at_site} is itself computed only over site-habitat cells
#' present in the raw data.
#'
#' \strong{Algorithm:} starting at \code{rank_system[1]} (finest), every
#' distinct value at that rank is checked against \code{min_n}. Groups that
#' clear it are finalized immediately (labelled e.g. \code{"order:Perciformes"}).
#' Groups that don't are left unresolved and re-evaluated at the next rank up
#' -- since unresolved rows are grouped by their shared value at that coarser
#' rank, this automatically pools exactly the taxonomically-adjacent
#' shortfall groups (e.g. multiple sparse orders sharing one class), while
#' already-resolved finer groups are excluded and stay untouched. This
#' repeats up to the ceiling rank. Rows still below \code{min_n} even at the
#' ceiling are finalized anyway (there is nowhere left to escalate to without
#' violating the ceiling) with \code{sampling_group_below_min_n = TRUE} so
#' downstream code/reports can see the denominator is weaker than intended
#' for that group -- it is never silently treated as if the floor were met,
#' and never merged across the ceiling rank regardless.
#'
#' \strong{Missing taxonomy:} rows with \code{NA} at the rank currently being
#' evaluated are held back (grouped separately from named values) rather
#' than merged into a same-rank NA bucket; if still \code{NA} at the ceiling
#' rank, they are finalized into a single \code{"unknown"} group of their own
#' (never merged with any named ceiling-rank group), flagged
#' \code{sampling_group_below_min_n} the same way.
#'
#' @section Partition guarantee:
#' Every row of \code{data} is assigned to exactly one \code{sampling_group}
#' -- never zero, never more than one. This follows from the algorithm's
#' structure, not from the specific \code{min_n} rule: at every rank,
#' \code{split()} partitions the current set of not-yet-finalized rows (each
#' row goes to exactly one bucket); a row is removed from that
#' not-yet-finalized set the moment it is finalized and is never
#' re-examined afterward; and at the ceiling rank, every remaining row is
#' finalized unconditionally (the code's own gating condition is
#' \code{cleared || is_ceiling}, which is always true once
#' \code{is_ceiling} is true) -- so nothing can be left over unassigned.
#' Verified directly (not just argued) in
#' \code{test-compute_adaptive_sampling_groups.R} via a stress fixture mixing
#' common/rare taxa and missing taxonomy at every rank: row count and row
#' identity are preserved exactly, and every group's membership is checked
#' against its own label (e.g. every row in an \code{"order:X"} group
#' actually has \code{order == "X"}). This guarantee would hold equally for
#' a different \code{min_n} rule (e.g. a relative/proportional criterion
#' instead of an absolute count) as long as it is implemented within this
#' same split-then-defer-with-guaranteed-ceiling-finalization structure.
#'
#' @return \code{data} with two columns added: \code{sampling_group}
#'   (character, e.g. \code{"order:Perciformes"}, \code{"class:Actinopteri"},
#'   \code{"phylum:Chordata"}, or \code{"unknown"}) and
#'   \code{sampling_group_below_min_n} (logical).
#'
#' @seealso \code{\link{prepare_model_dataframe}},
#'   \code{\link{train_biodiversity_model_by_group}}
#'
#' @examples
#' obs <- data.frame(
#'   grid_id = rep(c("Grid_1", "Grid_2", "Grid_3"), each = 4),
#'   order = c(
#'     "Perciformes", "Perciformes", "Perciformes", "Perciformes",
#'     "Diatomea", "Diatomea", "Rotifera", "Rotifera",
#'     "Perciformes", "Diatomea", "Rotifera", "Perciformes"
#'   ),
#'   class = c(
#'     rep("Actinopteri", 4), rep("Bacillariophyceae", 2),
#'     rep("Rotifera", 2), "Actinopteri", "Bacillariophyceae",
#'     "Rotifera", "Actinopteri"
#'   ),
#'   phylum = c(
#'     rep("Chordata", 4), rep("Ochrophyta", 2), rep("Rotifera", 2),
#'     "Chordata", "Ochrophyta", "Rotifera", "Chordata"
#'   )
#' )
#' grouped <- compute_adaptive_sampling_groups(obs, min_n = 3)
#' table(grouped$sampling_group)
#'
#' \dontrun{
#' occurrences_gridded <- compute_adaptive_sampling_groups(
#'   occurrences_gridded,
#'   rank_system = c("order", "class", "phylum"),
#'   min_n       = 100
#' )
#' model_data <- prepare_model_dataframe(
#'   occurrences_gridded,
#'   sampling_group_col = "sampling_group"
#' )
#' }
#'
#' @export
compute_adaptive_sampling_groups <- function(data,
                                             rank_system = c("order", "class", "phylum"),
                                             min_n,
                                             grid_col = "grid_id",
                                             habitat_col = NULL) {
  if (length(rank_system) < 1L) {
    stop("compute_adaptive_sampling_groups: 'rank_system' must have at least one rank.")
  }
  if (missing(min_n)) {
    stop("compute_adaptive_sampling_groups: 'min_n' is required -- there is no ",
      "safe universal default across study systems. Supply the minimum ",
      "viable typical per-site record count for YOUR effort scale (see ",
      "the Details section of ?compute_adaptive_sampling_groups).",
      call. = FALSE
    )
  }
  missing_cols <- setdiff(c(grid_col, rank_system, habitat_col), names(data))
  if (length(missing_cols) > 0L) {
    stop(
      "compute_adaptive_sampling_groups: missing required columns: ",
      paste(missing_cols, collapse = ", ")
    )
  }
  if (!is.numeric(min_n) || length(min_n) != 1L || is.na(min_n) || min_n <= 0) {
    stop("compute_adaptive_sampling_groups: 'min_n' must be a single positive number.")
  }

  # Real GBIF-derived taxonomy sometimes stores "unclassified at this rank"
  # as an empty string rather than NA (confirmed on real PtConception 18S
  # data, not a hypothetical) -- normalize to NA so it is handled by the same
  # NA-holdback/escalation logic as a true missing value, rather than being
  # treated as its own literal "" taxon group. Matches the existing
  # convention in TaxaAssign::join_priors()'s dark-diversity code.
  for (rank in rank_system) {
    data[[rank]] <- dplyr::na_if(data[[rank]], "")
  }

  n <- nrow(data)
  site_key <- if (is.null(habitat_col)) {
    data[[grid_col]]
  } else {
    paste(data[[grid_col]], data[[habitat_col]], sep = "\r")
  }

  group_label <- rep(NA_character_, n)
  below_min_flag <- rep(NA, n)
  unresolved <- seq_len(n)

  .effort_metric <- function(idx) {
    mean(table(site_key[idx]))
  }

  for (depth in seq_along(rank_system)) {
    if (length(unresolved) == 0L) break
    rank <- rank_system[depth]
    is_ceiling <- depth == length(rank_system)

    vals <- data[[rank]][unresolved]
    # Keep NA as its own explicit split key (rather than silently dropped by
    # split()) so unnamed-taxonomy rows are held back for a chance to resolve
    # at a coarser rank, exactly like named values.
    f <- factor(vals, exclude = NULL)
    idx_by_val <- split(unresolved, f)

    # Iterate by position, not by name: list[[NA_name]] returns NULL rather
    # than the actual element, since the NA level's name is a literal NA --
    # positional [[i]] indexing is unaffected by that and always retrieves
    # the right group.
    for (i in seq_along(idx_by_val)) {
      idx <- idx_by_val[[i]]
      val_chr <- names(idx_by_val)[i]
      # All rows in idx share one factor level (including the explicit NA
      # level), so checking the first element's rank value is sufficient.
      is_na_val <- is.na(data[[rank]][idx[1L]])

      if (is_na_val && !is_ceiling) {
        # Hold back -- try again one rank up.
        next
      }

      effort <- .effort_metric(idx)
      cleared <- effort >= min_n

      if (cleared || is_ceiling) {
        label <- if (is_na_val) {
          "unknown"
        } else {
          paste0(rank, ":", val_chr)
        }
        group_label[idx] <- label
        below_min_flag[idx] <- !cleared
        unresolved <- setdiff(unresolved, idx)
      }
      # else: leave unresolved for the next (coarser) rank's grouping, which
      # will naturally pool this group with its taxonomic siblings sharing
      # the same value at that coarser rank.
    }
  }

  data$sampling_group <- group_label
  data$sampling_group_below_min_n <- below_min_flag
  data
}
