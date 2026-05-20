#' Assign Habitat to Points Using Biological Consensus
#'
#' Infers the habitat of each sampling point from the weighted habitat
#' affinities of the species present there. Each species contributes its
#' habitat weight vector (produced by \code{\link{parse_hierarchical_habitat_response}})
#' to a per-point sum; the habitat with the highest summed weight is assigned,
#' provided it meets a minimum consensus threshold.
#'
#' This is a fallback method for when spatial polygon layers are unavailable.
#' If you have a habitat shapefile, use \code{assign_habitat_to_points()}
#' instead.
#'
#' @param data A dataframe of occurrence records. Must contain columns named
#'   by \code{point_id_col} and \code{taxon_col}.
#' @param habitats_df A dataframe giving habitat weights for each species.
#'   Must contain a column named by \code{taxon_col}, one numeric column per
#'   habitat in the scheme, and optionally \code{Other_weight} and
#'   \code{habitat_best_guess}. Produced by
#'   \code{\link{parse_hierarchical_habitat_response}}.
#' @param habitat_cols Character vector naming the habitat weight columns in
#'   \code{habitats_df}. If \code{NULL} (default), all numeric columns other
#'   than \code{taxon_col} are used. Supply explicitly when the dataframe
#'   contains non-habitat numeric columns. \code{"Other_weight"} is always
#'   treated as a valid habitat column and propagated to \code{main_habitat}
#'   when it wins the consensus vote.
#' @param point_id_col Character. Name of the point identifier column in
#'   \code{data}. Default \code{"point_id"}.
#' @param taxon_col Character. Name of the taxon name column in both
#'   \code{data} and \code{habitats_df}. Default \code{"taxon_name"}.
#' @param weight_by_abundance Logical. If \code{FALSE} (default), each species
#'   contributes equally to the point score regardless of how many occurrence
#'   records it has at that point. If \code{TRUE}, species are weighted by
#'   their record count at the point, so abundant species have more influence.
#'   Default \code{FALSE} is recommended because record abundance in occurrence
#'   datasets is strongly influenced by sampling effort rather than true
#'   ecological dominance.
#' @param threshold Numeric in (0, 1]. Minimum habitat weight fraction for
#'   a habitat to be classified as biologically relevant at a point. At 0.3,
#'   a habitat must receive at least 30\% of the species-weighted votes to
#'   be assigned. Lower values include more marginal habitats; higher values
#'   restrict assignment to clearly dominant habitats. For transitional areas
#'   (e.g., estuaries), a lower threshold (0.2) may better capture mixed
#'   habitats. Default \code{0.3}. Points where no habitat reaches the
#'   threshold receive \code{main_habitat = NA}. Note: the default is lower
#'   than in the single-habitat version because weight is now spread across
#'   multiple habitats per species; a threshold of 0.5 may be too strict
#'   for generalist communities.
#' @param min_species_weight Numeric in \code{[0, 1)}. Per-species weight floor.
#'   Any weight assigned to a habitat column by a species that is greater than
#'   zero but less than this value is set to zero before the consensus
#'   calculation. Default \code{0.0} (no floor, all weights used). Set to e.g.
#'   \code{0.1} to suppress LLM hedging weights -- small non-zero values the
#'   LLM assigns to vaguely plausible habitats that dilute the signal from
#'   the species' actual primary habitat(s). Has no effect when using the
#'   two-stage IUCN pipeline with the commit-at-confident-level prompt, which
#'   already discourages sub-0.1 weights by instruction.
#'
#' @return The input \code{data} with two additional columns:
#' \describe{
#'   \item{main_habitat}{Character. The winning habitat label at each point,
#'     or \code{NA} if no habitat reached \code{threshold}.
#'     \code{"Other"} appears here when the \code{Other_weight} column wins,
#'     signalling that the community at this point does not fit the scheme.}
#'   \item{habitat_best_guess}{Character. Non-empty only when
#'     \code{main_habitat = "Other"} (or when the leading habitat is listed
#'     but Other_weight is substantial). Concatenates the unique
#'     \code{habitat_best_guess} values from all species at the point that
#'     contributed weight to \code{Other_weight}, separated by \code{"; "}.
#'     Use this to decide whether the habitat scheme needs extending.}
#' }
#'
#' @details
#' \strong{How weighted consensus works:}
#' For each point, the function joins occurrence records to the habitat weight
#' table. Each matched species contributes its full weight vector (one value
#' per habitat column). If \code{weight_by_abundance = FALSE}, each species
#' counts once; if \code{TRUE}, its weights are multiplied by its record count
#' at the point. Column sums are normalised to proportions. The habitat with
#' the largest proportion is assigned if it meets \code{threshold}.
#'
#' \strong{Other_weight:} Treated as a regular habitat column named
#' \code{"Other"} throughout the computation. When it wins, \code{main_habitat}
#' is set to \code{"Other"} and \code{habitat_best_guess} is populated from the
#' \code{habitat_best_guess} column in \code{habitats_df}.
#'
#' \strong{Species not in lookup table:} Silently ignored -- they reduce the
#' effective species count, making consensus harder to reach. Check coverage
#' before running:
#' \preformatted{
#' mean(unique(data$taxon_name) \%in\% habitats_df$taxon_name)
#' }
#'
#' @seealso \code{assign_habitat_to_points()} (spatial polygon method),
#'   \code{\link{parse_hierarchical_habitat_response}},
#'   \code{\link{build_habitat_prompt}}, \code{prepare_model_dataframe()}
#'
#' @importFrom dplyr left_join group_by summarise mutate filter arrange
#'   slice select ungroup n distinct n_distinct
#' @importFrom rlang sym !!
#' @export
#'
#' @examples
#' \dontrun{
#' # hab_weights produced by parse_hierarchical_habitat_response()
#' result <- assign_habitat_biological(
#'   data              = occurrence_data,
#'   habitats_df       = hab_weights,
#'   threshold         = 0.3,
#'   weight_by_abundance = FALSE
#' )
#'
#' # Points with no consensus
#' result |> dplyr::filter(is.na(main_habitat)) |> dplyr::distinct(point_id)
#'
#' # Points where the scheme did not fit
#' result |> dplyr::filter(main_habitat == "Other") |>
#'   dplyr::distinct(point_id, habitat_best_guess)
#' }

assign_habitat_biological <- function(data,
                                      habitats_df,
                                      habitat_cols        = NULL,
                                      point_id_col        = "point_id",
                                      taxon_col           = "taxon_name",
                                      weight_by_abundance = FALSE,
                                      threshold           = 0.3,
                                      min_species_weight  = 0.0) {

  # ---------------------------------------------------------------------------
  # Input checks
  # ---------------------------------------------------------------------------
  if (!is.data.frame(data)) {
    stop("assign_habitat_biological: 'data' must be a dataframe.")
  }
  if (!is.data.frame(habitats_df)) {
    stop("assign_habitat_biological: 'habitats_df' must be a dataframe.")
  }

  missing_data <- setdiff(c(point_id_col, taxon_col), names(data))
  if (length(missing_data) > 0) {
    stop(
      "assign_habitat_biological: column(s) not found in 'data': ",
      paste(missing_data, collapse = ", ")
    )
  }

  if (!taxon_col %in% names(habitats_df)) {
    stop(
      "assign_habitat_biological: taxon column '", taxon_col,
      "' not found in 'habitats_df'."
    )
  }

  if (!is.logical(weight_by_abundance) || length(weight_by_abundance) != 1L ||
      is.na(weight_by_abundance)) {
    stop("assign_habitat_biological: 'weight_by_abundance' must be TRUE or FALSE.")
  }

  if (!is.numeric(threshold) || threshold <= 0 || threshold > 1) {
    stop(
      "assign_habitat_biological: 'threshold' must be numeric in (0, 1]. ",
      "Got: ", threshold
    )
  }

  if (!is.numeric(min_species_weight) || length(min_species_weight) != 1L ||
      is.na(min_species_weight) || min_species_weight < 0 || min_species_weight >= 1) {
    stop(
      "assign_habitat_biological: 'min_species_weight' must be numeric in [0, 1). ",
      "Got: ", min_species_weight
    )
  }

  # ---------------------------------------------------------------------------
  # Identify habitat weight columns
  # ---------------------------------------------------------------------------
  det <- .detect_habitat_cols(habitats_df, habitat_cols, taxon_col,
                              caller = "assign_habitat_biological")
  habitats_df  <- det$habitats_df
  habitat_cols <- det$habitat_cols
  has_other_weight <- det$has_other_weight
  has_best_guess   <- det$has_best_guess

  # ---------------------------------------------------------------------------
  # Coverage report
  # ---------------------------------------------------------------------------
  data_taxa   <- unique(data[[taxon_col]])
  lookup_taxa <- unique(habitats_df[[taxon_col]])
  n_covered   <- sum(data_taxa %in% lookup_taxa)
  pct_covered <- 100 * n_covered / length(data_taxa)

  message(sprintf(
    "assign_habitat_biological: %d of %d species (%.0f%%) found in lookup table.",
    n_covered, length(data_taxa), pct_covered
  ))

  if (n_covered == 0) {
    warning(
      "assign_habitat_biological: no species in 'data' matched any entry in ",
      "'habitats_df'. All points will receive main_habitat = NA. ",
      "Check that 'taxon_col' refers to the same name format in both inputs.",
      call. = FALSE
    )
  }

  # ---------------------------------------------------------------------------
  # Build a clean weight matrix from habitats_df
  # Keep only: taxon_col, habitat weight cols, habitat_best_guess (if present)
  # ---------------------------------------------------------------------------
  keep_cols <- c(taxon_col, habitat_cols, if (has_best_guess) "habitat_best_guess")
  weights_clean <- habitats_df[, intersect(keep_cols, names(habitats_df)),
                               drop = FALSE]

  # Coerce weight columns to numeric; replace NA with 0
  for (hc in habitat_cols) {
    weights_clean[[hc]] <- suppressWarnings(as.numeric(weights_clean[[hc]]))
    weights_clean[[hc]][is.na(weights_clean[[hc]])] <- 0
  }

  # Apply per-species weight floor: zero out weights below min_species_weight.
  # This eliminates LLM hedging (e.g. 0.05 on a vaguely plausible habitat)
  # before weights enter the consensus calculation.
  if (min_species_weight > 0) {
    n_zeroed <- 0L
    for (hc in habitat_cols) {
      below_floor <- weights_clean[[hc]] > 0 &
                     weights_clean[[hc]] < min_species_weight
      n_zeroed <- n_zeroed + sum(below_floor, na.rm = TRUE)
      weights_clean[[hc]][below_floor] <- 0
    }
    if (n_zeroed > 0L) {
      message(sprintf(
        "assign_habitat_biological: zeroed %d per-species weight(s) below min_species_weight = %.2f.",
        n_zeroed, min_species_weight
      ))
    }
  }

  # ---------------------------------------------------------------------------
  # Compute per-species contribution weight at each point
  # ---------------------------------------------------------------------------
  # Step 1: join occurrence data to weight table on taxon_col
  joined <- merge(
    data[, unique(c(point_id_col, taxon_col)), drop = FALSE],
    weights_clean,
    by    = taxon_col,
    all.x = FALSE   # drop unmatched occurrences (taxa not in lookup)
  )

  if (nrow(joined) == 0) {
    # No matches at all -- return data with NA columns appended
    result <- data
    result[["main_habitat"]]       <- NA_character_
    result[["habitat_best_guess"]] <- NA_character_
    message("assign_habitat_biological: 0 of ", dplyr::n_distinct(data[[point_id_col]]),
            " site(s) assigned a habitat (no species matched lookup table).")
    return(result)
  }

  # Step 2: optionally scale each species' weight vector by record count
  if (weight_by_abundance) {
    # Count records per point x taxon
    rec_counts <- aggregate(
      rep(1L, nrow(joined)),
      by   = joined[, c(point_id_col, taxon_col), drop = FALSE],
      FUN  = sum
    )
    names(rec_counts)[names(rec_counts) == "x"] <- ".n_records"
    joined <- merge(joined, rec_counts, by = c(point_id_col, taxon_col))
    for (hc in habitat_cols) {
      joined[[hc]] <- joined[[hc]] * joined[[".n_records"]]
    }
    joined[[".n_records"]] <- NULL
  } else {
    # De-duplicate to one row per point x taxon (equal species weight)
    joined <- joined[!duplicated(joined[, c(point_id_col, taxon_col)]), ,
                     drop = FALSE]
  }

  # Step 3: sum weight columns across species within each point
  point_sums <- aggregate(
    joined[, habitat_cols, drop = FALSE],
    by  = joined[, point_id_col, drop = FALSE],
    FUN = sum,
    na.rm = TRUE
  )

  # Step 4: normalise rows to proportions and find the winning habitat
  weight_mat <- as.matrix(point_sums[, habitat_cols, drop = FALSE])
  row_totals <- rowSums(weight_mat, na.rm = TRUE)
  # Avoid divide-by-zero for points where all weights are 0
  row_totals[row_totals == 0] <- NA_real_
  prop_mat <- weight_mat / row_totals

  best_idx  <- max.col(prop_mat, ties.method = "first")
  best_prop <- prop_mat[cbind(seq_len(nrow(prop_mat)), best_idx)]
  best_hab  <- habitat_cols[best_idx]

  # Apply threshold
  best_hab[is.na(best_prop) | best_prop < threshold] <- NA_character_

  site_habitats <- data.frame(
    point_id_col_placeholder = point_sums[[point_id_col]],
    main_habitat             = best_hab,
    stringsAsFactors         = FALSE
  )
  names(site_habitats)[1] <- point_id_col

  # ---------------------------------------------------------------------------
  # Populate habitat_best_guess for points where Other wins or contributes
  # ---------------------------------------------------------------------------
  best_guess_col <- character(nrow(site_habitats))

  if (has_best_guess && "Other" %in% habitat_cols) {
    # For each point where Other_weight > 0 in any contributing species,
    # collect the unique non-blank habitat_best_guess strings.
    other_contributors <- joined[joined[["Other"]] > 0 &
                                   !is.na(joined[["Other"]]), ,
                                 drop = FALSE]

    if (nrow(other_contributors) > 0) {
      # Aggregate free-text guesses per point
      pt_guesses <- tapply(
        other_contributors[["habitat_best_guess"]],
        other_contributors[[point_id_col]],
        function(x) {
          vals <- unique(trimws(x[!is.na(x) & nzchar(trimws(x))]))
          if (length(vals) == 0L) "" else paste(vals, collapse = "; ")
        }
      )
      # Map into site_habitats order
      matched <- match(site_habitats[[point_id_col]], names(pt_guesses))
      best_guess_col <- ifelse(
        is.na(matched), "",
        as.character(pt_guesses[matched])
      )
      best_guess_col[is.na(best_guess_col)] <- ""
    }
  }

  site_habitats[["habitat_best_guess"]] <- best_guess_col

  # ---------------------------------------------------------------------------
  # Merge back onto original data and report
  # ---------------------------------------------------------------------------
  # Drop any pre-existing main_habitat / habitat_best_guess columns in data
  data[["main_habitat"]]       <- NULL
  data[["habitat_best_guess"]] <- NULL

  result <- merge(data, site_habitats, by = point_id_col, all.x = TRUE)

  n_sites      <- dplyr::n_distinct(data[[point_id_col]])
  n_assigned   <- dplyr::n_distinct(
    result[[point_id_col]][!is.na(result[["main_habitat"]])]
  )
  n_unassigned <- n_sites - n_assigned
  n_other      <- dplyr::n_distinct(
    result[[point_id_col]][
      !is.na(result[["main_habitat"]]) & result[["main_habitat"]] == "Other"
    ]
  )

  message(sprintf(
    paste0("assign_habitat_biological: %d of %d site(s) assigned a habitat ",
           "(threshold = %.2f). %d site(s) received NA. %d site(s) assigned 'Other' ",
           "(scheme may need extending -- check habitat_best_guess column)."),
    n_assigned, n_sites, threshold, n_unassigned, n_other
  ))

  result
}


# ==============================================================================
# Internal: detect habitat weight columns in habitats_df
# ==============================================================================

#' Detect habitat weight columns and rename Other_weight to Other
#'
#' Shared logic used by \code{assign_habitat_biological()} and
#' \code{consensus_habitat()}.
#' @param habitats_df Data frame from \code{parse_hierarchical_habitat_response()}.
#' @param habitat_cols User-supplied column names or \code{NULL} for auto-detect.
#' @param taxon_col Name of the taxon column.
#' @param caller Character string for error messages.
#' @return A list with elements \code{habitats_df} (modified),
#'   \code{habitat_cols}, \code{has_other_weight}, \code{has_best_guess}.
#' @noRd
.detect_habitat_cols <- function(habitats_df, habitat_cols, taxon_col, caller) {
  # Rename Other_weight -> Other for uniform treatment throughout.
  has_other_weight <- "Other_weight" %in% names(habitats_df)
  if (has_other_weight) {
    names(habitats_df)[names(habitats_df) == "Other_weight"] <- "Other"
  }

  has_best_guess <- "habitat_best_guess" %in% names(habitats_df)

  if (!is.null(habitat_cols)) {
    habitat_cols <- sub("^Other_weight$", "Other", habitat_cols)
    missing_hc <- setdiff(habitat_cols, names(habitats_df))
    if (length(missing_hc) > 0) {
      stop(
        caller, ": habitat_cols not found in 'habitats_df': ",
        paste(missing_hc, collapse = ", ")
      )
    }
  } else {
    exclude_cols <- c(taxon_col,
                      if (has_best_guess) "habitat_best_guess",
                      if ("ecoregion_best_guess" %in% names(habitats_df))
                        "ecoregion_best_guess",
                      "Habitat")
    numeric_cols <- names(habitats_df)[
      vapply(habitats_df, is.numeric, logical(1))
    ]
    habitat_cols <- setdiff(numeric_cols, exclude_cols)
    if (length(habitat_cols) == 0) {
      stop(
        caller, ": no numeric habitat weight columns found in ",
        "'habitats_df'. Ensure parse_hierarchical_habitat_response() produced ",
        "a weighted output, or supply 'habitat_cols' explicitly."
      )
    }
  }

  list(habitats_df       = habitats_df,
       habitat_cols      = habitat_cols,
       has_other_weight  = has_other_weight,
       has_best_guess    = has_best_guess)
}


# ==============================================================================
# consensus_habitat()
# ==============================================================================

#' Compute Assemblage-Level Consensus Habitat
#'
#' Summarises per-species habitat weights into a single consensus habitat (and
#' optionally ecoregion) for the entire assemblage. Each species contributes
#' equally. Useful for inferring site-level habitat context from a list of
#' candidate taxon names when occurrence records or spatial data are unavailable.
#'
#' @param habitats_df A dataframe of per-species habitat weights, as produced by
#'   \code{\link{parse_hierarchical_habitat_response}}. Must contain a column
#'   named by \code{taxon_col} and one or more numeric habitat weight columns.
#' @param habitat_cols Character vector naming the habitat weight columns. If
#'   \code{NULL} (default), auto-detected (all numeric columns except
#'   \code{taxon_col} and text columns).
#' @param taxon_col Character. Name of the taxon name column. Default
#'   \code{"taxon_name"}.
#' @param threshold Numeric in (0, 1]. Minimum habitat weight fraction for
#'   a habitat to be classified as biologically relevant. At 0.3, a habitat
#'   must receive at least 30\% of the species-weighted votes to be assigned.
#'   Lower values include more marginal habitats; higher values restrict
#'   assignment to clearly dominant habitats. For transitional areas (e.g.,
#'   estuaries), a lower threshold (0.2) may better capture mixed habitats.
#'   Default \code{0.3}.
#'
#' @return A one-row data frame with columns:
#' \describe{
#'   \item{main_habitat}{Character. The consensus habitat, or \code{NA} if none
#'     reached \code{threshold}.}
#'   \item{ecoregion}{Character. The modal \code{ecoregion_best_guess} value
#'     across species, or \code{NA} if the column is absent.}
#'   \item{habitat_best_guess}{Character. Concatenated free-text guesses when
#'     \code{"Other"} wins, otherwise \code{NA}.}
#' }
#' The full habitat proportion vector is attached as
#' \code{attr(result, "habitat_proportions")}.
#'
#' @seealso \code{\link{assign_habitat_biological}},
#'   \code{\link{parse_hierarchical_habitat_response}},
#'   \code{\link{build_habitat_prompt}}
#'
#' @export
#'
#' @examples
#' hab_weights <- data.frame(
#'   taxon_name = c("Sebastes mystinus", "Gadus morhua", "Oncorhynchus mykiss"),
#'   Marine     = c(1.0, 1.0, 0.5),
#'   Freshwater = c(0.0, 0.0, 0.5),
#'   Terrestrial = c(0.0, 0.0, 0.0),
#'   Other_weight = c(0.0, 0.0, 0.0),
#'   habitat_best_guess = c("", "", "")
#' )
#' consensus_habitat(hab_weights)

consensus_habitat <- function(habitats_df,
                              habitat_cols = NULL,
                              taxon_col    = "taxon_name",
                              threshold    = 0.3) {

  # --- Input checks ---
  if (!is.data.frame(habitats_df)) {
    stop("consensus_habitat: 'habitats_df' must be a dataframe.")
  }
  if (!taxon_col %in% names(habitats_df)) {
    stop("consensus_habitat: taxon column '", taxon_col,
         "' not found in 'habitats_df'.")
  }
  if (!is.numeric(threshold) || length(threshold) != 1L ||
      is.na(threshold) || threshold <= 0 || threshold > 1) {
    stop("consensus_habitat: 'threshold' must be numeric in (0, 1].")
  }

  # --- Detect habitat columns ---
  det <- .detect_habitat_cols(habitats_df, habitat_cols, taxon_col,
                              caller = "consensus_habitat")
  habitats_df  <- det$habitats_df
  habitat_cols <- det$habitat_cols

  # --- De-duplicate to one row per taxon ---
  habitats_df <- habitats_df[!duplicated(habitats_df[[taxon_col]]), , drop = FALSE]

  # --- Sum habitat weights across all taxa ---
  col_sums <- colSums(habitats_df[, habitat_cols, drop = FALSE], na.rm = TRUE)
  total    <- sum(col_sums)

  if (total == 0) {
    props <- rep(0, length(habitat_cols))
    names(props) <- habitat_cols
    main_habitat <- NA_character_
  } else {
    props <- col_sums / total
    best_idx <- which.max(props)
    main_habitat <- if (props[best_idx] >= threshold) {
      habitat_cols[best_idx]
    } else {
      NA_character_
    }
  }

  # --- Ecoregion: modal non-blank value ---
  ecoregion <- NA_character_
  if ("ecoregion_best_guess" %in% names(habitats_df)) {
    eco_vals <- trimws(habitats_df[["ecoregion_best_guess"]])
    eco_vals <- eco_vals[!is.na(eco_vals) & nzchar(eco_vals)]
    if (length(eco_vals) > 0) {
      eco_counts <- table(eco_vals)
      ecoregion  <- names(which.max(eco_counts))
    }
  }

  # --- habitat_best_guess when Other wins ---
  best_guess <- NA_character_
  if ("habitat_best_guess" %in% names(habitats_df) &&
      !is.na(main_habitat) && main_habitat == "Other") {
    guesses <- trimws(habitats_df[["habitat_best_guess"]])
    guesses <- unique(guesses[!is.na(guesses) & nzchar(guesses)])
    if (length(guesses) > 0) best_guess <- paste(guesses, collapse = "; ")
  }

  result <- data.frame(
    main_habitat       = main_habitat,
    ecoregion          = ecoregion,
    habitat_best_guess = best_guess,
    stringsAsFactors   = FALSE
  )
  attr(result, "habitat_proportions") <- props
  result
}
