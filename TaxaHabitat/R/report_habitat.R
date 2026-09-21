# ==============================================================================
# report_habitat.R
# TaxaHabitat -- Summarize habitat assignment for Methods/Results reporting
#
# Exported functions:
#   report_habitat()   -- generate report_section from habitat data
# ==============================================================================


#' Generate a Report Section for Habitat Assignment
#'
#' Summarizes the habitat assignment produced by TaxaHabitat into a structured
#' \code{report_section} object (from TaxaTools). Works standalone or feeds
#' into \code{TaxaTools::assemble_report()} for a unified pipeline report.
#'
#' @param habitat_data Data frame. Output of
#'   \code{\link{assign_habitat_biological}} or the raw habitat weights from
#'   \code{\link{parse_hierarchical_habitat_response}}. Must contain at least
#'   one numeric habitat weight column.
#' @param taxon_col Character. Column name containing taxon names.
#'   Default \code{"scientificName"}.
#' @param verbose Logical. Print summary messages. Default \code{FALSE}.
#'
#' @return A \code{report_section} object with:
#' \describe{
#'   \item{methods}{Template text describing habitat assignment approach.}
#'   \item{results}{Template text summarizing habitat assignments.}
#'   \item{params}{Named list of habitat parameters.}
#'   \item{statistics}{Named list of summary counts.}
#' }
#'
#' @seealso \code{\link{assign_habitat_biological}},
#'   \code{\link{parse_hierarchical_habitat_response}}
#'
#' @examples
#' \dontrun{
#' hab <- parse_hierarchical_habitat_response(llm_output)
#' sec <- report_habitat(hab)
#' print(sec)
#' }
#'
#' @export
report_habitat <- function(habitat_data,
                           taxon_col = "scientificName",
                           verbose = FALSE) {
  if (!is.data.frame(habitat_data) || nrow(habitat_data) == 0L) {
    stop("report_habitat: 'habitat_data' must be a non-empty data frame.",
      call. = FALSE
    )
  }

  # This function is documented to accept either assign_habitat_biological()'s
  # output (occurrence-level data with a categorical main_habitat winner per
  # row) or the raw per-species weight table from
  # parse_hierarchical_habitat_response(). The two shapes need genuinely
  # different summarisation -- assign_habitat_biological()'s real @return
  # adds only main_habitat/habitat_best_guess (both character) to whatever
  # occurrence_data it was given, so it carries NO numeric habitat-weight
  # columns at all. Treating "any numeric column not on a small exclude
  # list" as a habitat weight column would pick up the occurrence data's own
  # incidental numeric columns instead (decimalLatitude/decimalLongitude in
  # every real production caller): on a real 18S and a real GreatLakes
  # report, that renders "under the decimalLatitude/decimalLongitude scheme"
  # and "Dominant habitat: decimalLatitude (mean weight 3519%)" (mean
  # latitude times 100).
  #
  # main_habitat's mere presence isn't a safe dispatch signal on its own --
  # a data frame can legitimately carry both a real main_habitat column AND
  # real per-category weight columns together (this file's own "excludes
  # known non-habitat columns" test does exactly that). Positively identify
  # real weight columns instead -- see .looks_like_habitat_weights() for the
  # exact signals and why a bare [0, 1] range check on ANY one column is not
  # enough. Only fall back to tallying the categorical main_habitat column
  # when the numeric columns do not positively look like a weight table.
  # Resolve the taxon column ONCE, here, and hand the resolved name to both
  # branches: if only .summarise_main_habitat() consulted
  # .resolve_taxon_col() while .summarise_habitat_weights() tested the raw
  # taxon_col, the documented Shape A call -- report_habitat() on
  # parse_hierarchical_habitat_response()'s output, which always names its
  # taxon column taxon_name, against this function's default of
  # "scientificName" -- would silently fall through to nrow() and report
  # ROWS as n_taxa. Same class of bug .resolve_taxon_col() exists to
  # prevent, just on the other branch.
  taxon_col <- .resolve_taxon_col(habitat_data, taxon_col)

  candidate_cols <- .candidate_habitat_cols(habitat_data, taxon_col)
  has_weight_cols <- .looks_like_habitat_weights(habitat_data, candidate_cols)

  if (!has_weight_cols && "main_habitat" %in% names(habitat_data)) {
    hab <- .summarise_main_habitat(habitat_data, taxon_col)
  } else {
    hab <- .summarise_habitat_weights(habitat_data, taxon_col, candidate_cols)
  }

  statistics <- list(
    n_taxa         = hab$n_taxa,
    n_habitat_cols = length(hab$habitat_cols)
  )
  if (!is.null(hab$dominant_habitat)) {
    statistics$dominant_habitat <- hab$dominant_habitat
    statistics$dominant_pct <- hab$dominant_pct
  }

  # --- Params -----------------------------------------------------------------
  params <- list(method = "LLM-based biological consensus")
  if (!is.null(hab$scheme)) params$habitat_scheme <- hab$scheme

  # Read report_params if available
  rp <- attr(habitat_data, "report_params")
  if (!is.null(rp)) params <- c(params, rp[!names(rp) %in% names(params)])

  # --- Methods text -----------------------------------------------------------
  methods_text <- sprintf(
    "Habitat classifications were assigned to %d taxa using LLM-based biological consensus",
    hab$n_taxa
  )
  if (!is.null(hab$scheme)) {
    methods_text <- paste0(methods_text, sprintf(" under the %s scheme", hab$scheme))
  }
  methods_text <- paste0(methods_text, ".")

  # --- Results text -----------------------------------------------------------
  results_text <- paste(hab$results_parts, collapse = " ")

  # --- Construct report_section -----------------------------------------------
  TaxaTools::new_report_section(
    package    = "TaxaHabitat",
    section    = "habitat",
    methods    = methods_text,
    results    = results_text,
    citations  = NULL,
    params     = params,
    statistics = statistics
  )
}


#' Do the candidate numeric columns positively look like a habitat weight table?
#'
#' report_habitat() accepts two documented shapes and must tell them apart from
#' the data alone. Shape A -- parse_hierarchical_habitat_response()'s per-species
#' weight table -- has one numeric column per habitat plus Other_weight,
#' documented to hold values in the interval 0 to 1 and (its own @details) to sum to ~1.0
#' across a row within a tolerance of 0.05. Shape B --
#' assign_habitat_biological()'s occurrence-level output -- adds only a
#' categorical main_habitat winner per row and NO numeric weight columns at all,
#' so its only numeric columns are the occurrence data's own incidental ones
#' (decimalLatitude/decimalLongitude in every real production caller, often also
#' elevation_m/dist_to_coast_km/depth_m).
#'
#' A dispatch that asks only whether ANY single candidate column satisfies
#' \code{all(is.na(x) | (x >= 0 & x <= 1))} has two holes:
#'
#' 1. It passes VACUOUSLY for an all-NA numeric column -- is.na(x) is then TRUE
#'    everywhere and the range half of the `|` is never reached. GBIF exports
#'    routinely carry such columns (depth, elevation, coordinatePrecision).
#' 2. It passes for any genuinely proportional non-habitat column, e.g. a
#'    coordinatePrecision of 0.001, or a dist_to_coast_km that is 0 for every
#'    retained record in a coastal-only survey.
#'
#' Either flips Shape B into the weight branch. On the real
#' PtConMifishSchulte occurrence object, adding one all-NA `depth` column
#' turns a correct "356 taxa ... Dominant habitat: Marine (89% of assigned
#' records)" into "20000 taxa ... Dominant habitat: decimalLatitude (mean
#' weight 3506%)".
#'
#' So ask for POSITIVE evidence of a weight table instead of mere absence of a
#' range violation. All of:
#'
#' 1. at least one candidate column;
#' 2. EVERY candidate column carries real data (at least one non-NA value) and
#'    lies in the interval 0 to 1.05. `all`, not `any`, because a genuine weight table has no
#'    non-weight numeric columns while an occurrence frame essentially always
#'    carries at least one out-of-range one -- this closes hole 1 by making an
#'    all-NA column a disqualifier rather than a free pass. The 0.05 upper slack
#'    is parse_hierarchical_habitat_response()'s own tolerance, since it
#'    documents that weights are NOT renormalised;
#' 3. the columns behave like a composition: over rows with any positive weight,
#'    more than half sum to 1.0 within 0.05 -- deliberately the same
#'    `abs(row_sums - 1) > 0.05 & row_sums > 0` rule that function uses to call
#'    a row's weights malformed. This closes hole 2: a lone 0.001 precision
#'    column, or an all-zero distance column, is in range but never composes.
#'
#' Chosen over the minimal `any(!is.na(x)) && all(...)` patch, which closes hole
#' 1 only; and over dispatching purely on structural markers (Other_weight /
#' Habitat present, main_habitat absent), because a hand-assembled table can
#' carry main_habitat and real weight columns together with none of Shape A's
#' other markers -- this file's own "excludes known non-habitat columns" test
#' does exactly that, and structure alone would misdispatch it.
#'
#' Being strict is cheap: report_habitat() consults this only when deciding
#' whether to PREFER the main_habitat tally, so a false negative on a frame with
#' no main_habitat column still falls through to the weight branch.
#'
#' @return Logical scalar.
#' @noRd
.looks_like_habitat_weights <- function(habitat_data, candidate_cols) {
  if (length(candidate_cols) == 0L) {
    return(FALSE)
  }

  # parse_hierarchical_habitat_response() documents weights as [0, 1] but
  # explicitly does not renormalise, and warns only beyond 0.05 of 1.0.
  weight_tol <- 0.05

  ok <- vapply(candidate_cols, function(hc) {
    x <- habitat_data[[hc]]
    nn <- x[!is.na(x)]
    # length(nn) > 0L first: this is the all-NA guard. An all-NA column is
    # not evidence of a weight table, and treating it as such is the bug.
    length(nn) > 0L && all(nn >= 0 & nn <= 1 + weight_tol)
  }, logical(1L))
  if (!all(ok)) {
    return(FALSE)
  }

  # Build the matrix by column so this works for data.frame, tibble and
  # data.table alike ([ , cols] means something else entirely for the last).
  # dim<- rather than relying on vapply's shape: with a single row vapply
  # returns a bare vector, not a 1-row matrix.
  n <- nrow(habitat_data)
  w <- vapply(
    candidate_cols,
    function(hc) as.numeric(habitat_data[[hc]]),
    numeric(n)
  )
  dim(w) <- c(n, length(candidate_cols))
  row_sums <- rowSums(w, na.rm = TRUE)

  # row_sums > 0 mirrors parse_hierarchical_habitat_response()'s own exemption
  # for all-zero rows (a taxon the LLM gave no weight anywhere). If NOTHING is
  # scored -- every candidate column is zero throughout -- there is no positive
  # evidence of a weight table, so this is FALSE rather than vacuously TRUE.
  scored <- row_sums > 0
  if (!any(scored)) {
    return(FALSE)
  }
  mean(abs(row_sums[scored] - 1) <= weight_tol) > 0.5
}


#' Resolve the taxon-name column, falling back to this ecosystem's convention
#'
#' Every real production caller passes \code{assign_habitat_biological()}'s
#' output, which names its taxon column \code{taxon_name} (not this function's
#' historical \code{"scientificName"} default) -- without this fallback,
#' \code{n_taxa} silently counted raw ROWS instead of unique taxa whenever the
#' requested column wasn't present (the real cause of a generated report
#' claiming "1419840 taxa" for an 18S survey with 2,027 real taxa).
#'
#' @noRd
.resolve_taxon_col <- function(habitat_data, taxon_col) {
  if (taxon_col %in% names(habitat_data)) {
    return(taxon_col)
  }
  if ("taxon_name" %in% names(habitat_data)) {
    return("taxon_name")
  }
  taxon_col
}


#' Summarise assign_habitat_biological() output (categorical main_habitat)
#' @noRd
.summarise_main_habitat <- function(habitat_data, taxon_col) {
  resolved_taxon_col <- .resolve_taxon_col(habitat_data, taxon_col)
  n_taxa <- if (resolved_taxon_col %in% names(habitat_data)) {
    length(unique(habitat_data[[resolved_taxon_col]][!is.na(habitat_data[[resolved_taxon_col]])]))
  } else {
    nrow(habitat_data)
  }

  mh <- habitat_data$main_habitat[!.is_habitat_unassigned(habitat_data$main_habitat)]
  # First-appearance order, not table()'s alphabetical default -- a scheme
  # string should read in the order categories actually occur, not shuffle
  # depending on which letters the LLM's own labels happen to start with.
  habitat_cols <- unique(mh)
  counts <- vapply(habitat_cols, function(h) sum(mh == h), integer(1L))
  scheme <- if (length(habitat_cols) > 0L) paste(habitat_cols, collapse = "/") else NULL

  dominant_habitat <- NULL
  dominant_pct <- NULL
  if (length(counts) > 0L) {
    dominant_habitat <- habitat_cols[which.max(counts)]
    dominant_pct <- round(100 * max(counts) / length(mh), 0)
  }

  results_parts <- sprintf(
    "%d taxa received habitat assignments across %d categories.",
    n_taxa, length(habitat_cols)
  )
  if (!is.null(dominant_habitat)) {
    results_parts <- c(results_parts, sprintf(
      "Dominant habitat: %s (%.0f%% of assigned records).",
      dominant_habitat, dominant_pct
    ))
  }

  list(
    n_taxa = n_taxa, habitat_cols = habitat_cols, scheme = scheme,
    dominant_habitat = dominant_habitat, dominant_pct = dominant_pct,
    results_parts = results_parts
  )
}


#' Numeric columns that could plausibly be habitat weight columns: not the
#' taxon column or a known non-habitat column. This is deliberately just the
#' candidate set (no value-range filtering) -- report_habitat()'s own dispatch
#' logic uses the range check to decide which shape was passed, but once
#' Shape A is confirmed every candidate is still treated as a real habitat
#' column here, same as before, so a column with a defensible out-of-range
#' value (e.g. floating-point overshoot) is never silently dropped.
#' @noRd
.candidate_habitat_cols <- function(habitat_data, taxon_col) {
  # DECLARED weight columns win, exactly as in .detect_habitat_cols().
  #
  # This is the second consumer of the same table, and it had the same defect:
  # inferring the weight set by scanning column types absorbs any numeric column
  # added later. Reproduced on the real PtConception 12S lookup once
  # habitat_breadth existed -- report_habitat() went from
  #   "across 5 categories. Dominant habitat: Marine (mean weight 58%)"
  # to
  #   "across 6 categories. Dominant habitat: habitat_breadth"
  # which is Methods/Results text headed for a manuscript.
  #
  # The denylist below is the fragile complement of type-scanning: it has to be
  # updated for every new non-habitat numeric column, forever. It stays only as
  # the fallback for hand-assembled tables that carry no declaration.
  declared <- attr(habitat_data, "habitat_cols")
  if (!is.null(declared)) {
    declared <- intersect(declared, names(habitat_data))
    if (length(declared) > 0L) {
      return(declared)
    }
  }
  exclude_cols <- c(
    taxon_col, "habitat_best_guess", "ecoregion_best_guess",
    "Habitat", "main_habitat",
    "habitat_breadth"
  )
  numeric_cols <- names(habitat_data)[
    vapply(habitat_data, is.numeric, logical(1L))
  ]
  setdiff(numeric_cols, exclude_cols)
}


#' Summarise raw per-species habitat weights (parse_hierarchical_habitat_response())
#' @noRd
.summarise_habitat_weights <- function(habitat_data, taxon_col, habitat_cols) {
  # Infer scheme from column names
  scheme <- NULL
  if (length(habitat_cols) > 0L) {
    if (all(habitat_cols %in% c("Marine", "Freshwater", "Terrestrial", "Other"))) {
      scheme <- "3-category"
    } else if (any(grepl("^\\d+\\.?\\d*", habitat_cols))) {
      scheme <- "IUCN_L1"
    } else {
      scheme <- paste(habitat_cols, collapse = "/")
    }
  }

  # taxon_col arrives already resolved by report_habitat(); .resolve_taxon_col()
  # is idempotent, so calling it again here keeps this helper correct if it is
  # ever used directly. The nrow() fallback is a last resort only -- reaching it
  # means n_taxa counts ROWS, which is exactly the wrong number to print.
  resolved_taxon_col <- .resolve_taxon_col(habitat_data, taxon_col)
  n_taxa <- if (resolved_taxon_col %in% names(habitat_data)) {
    length(unique(habitat_data[[resolved_taxon_col]][!is.na(habitat_data[[resolved_taxon_col]])]))
  } else {
    nrow(habitat_data)
  }

  # Dominant habitat (column with highest mean weight)
  dominant_habitat <- NULL
  dominant_pct <- NULL
  if (length(habitat_cols) > 0L) {
    col_means <- vapply(habitat_cols, function(hc) {
      mean(habitat_data[[hc]], na.rm = TRUE)
    }, numeric(1L))
    dominant_habitat <- names(which.max(col_means))
    # Read the pct off the SELECTED column, not max(col_means): which.max()
    # skips NA means (an all-NA habitat column) but a bare max() returns NA
    # whenever any column's mean is NA -- yielding a valid dominant_habitat
    # paired with an NA pct, which would crash the %d sprintf below.
    #
    # Guarded on dominant_habitat itself, not just habitat_cols: when EVERY
    # habitat column is entirely NA (a degraded-LLM-output case, not yet hit
    # in production but structurally possible), which.max() on an all-NA
    # col_means returns integer(0), so dominant_habitat is NULL here --
    # col_means[[NULL]] then errors ("attempt to select less than one
    # element") instead of falling through to the no-dominant-habitat path
    # the `if (!is.null(dominant_habitat))` check below already exists to
    # handle.
    if (!is.null(dominant_habitat)) {
      dominant_pct <- round(col_means[[dominant_habitat]] * 100, 0)
    }
  }

  results_parts <- sprintf(
    "%d taxa received habitat weight assignments across %d categories.",
    n_taxa, length(habitat_cols)
  )
  if (!is.null(dominant_habitat)) {
    results_parts <- c(results_parts, sprintf(
      # %.0f, not %d: round() returns a double, and sprintf's %d errors on
      # non-integer doubles.
      "Dominant habitat: %s (mean weight %.0f%%).",
      dominant_habitat, dominant_pct
    ))
  }

  list(
    n_taxa = n_taxa, habitat_cols = habitat_cols, scheme = scheme,
    dominant_habitat = dominant_habitat, dominant_pct = dominant_pct,
    results_parts = results_parts
  )
}
