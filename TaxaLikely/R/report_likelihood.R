# ==============================================================================
# report_likelihood.R
# TaxaLikely -- Summarize likelihood model for Methods/Results reporting
#
# Exported functions:
#   report_likelihood()   -- generate report_section from trained model
#
# Session 65: initial implementation
# ==============================================================================


#' Generate a Report Section for Likelihood Estimation
#'
#' Summarizes a trained likelihood model into a structured
#' \code{report_section} object (from TaxaTools). Works standalone or feeds
#' into \code{TaxaTools::assemble_report()} for a unified pipeline report.
#'
#' @param model A \code{taxa_model_params} object from
#'   \code{\link{train_likelihood_model}}.
#' @param verbose Logical. Print summary messages. Default \code{FALSE}.
#'
#' @return A \code{report_section} object with:
#' \describe{
#'   \item{methods}{Template text describing the likelihood model.}
#'   \item{results}{Template text summarizing model diagnostics.}
#'   \item{params}{Named list of model parameters.}
#'   \item{statistics}{Named list of model diagnostics.}
#' }
#'
#' @seealso \code{\link{train_likelihood_model}}, \code{\link{interpret_model}}
#'
#' @examples
#' \dontrun{
#' model <- train_likelihood_model(ref_matrix)
#' sec <- report_likelihood(model)
#' print(sec)
#' }
#'
#' @export
report_likelihood <- function(model,
                              verbose = FALSE) {

  if (!inherits(model, "taxa_model_params"))
    stop("report_likelihood: 'model' must be a 'taxa_model_params' object.",
         call. = FALSE)

  # --- Extract statistics from model ------------------------------------------
  stats_slot <- model$Stats
  n_species    <- if (!is.null(stats_slot$n_species)) stats_slot$n_species else NA_integer_
  n_singletons <- if (!is.null(stats_slot$n_singletons)) stats_slot$n_singletons else 0L
  n_anchors    <- if (!is.null(stats_slot$n_anchors)) stats_slot$n_anchors else 0L
  aic_score    <- stats_slot$AIC_Score

  # Reference errors

  n_errors <- if (!is.null(model$reference_errors) &&
                  is.data.frame(model$reference_errors)) {
    sum(model$reference_errors$error_type == "likely_mislabeled", na.rm = TRUE)
  } else {
    0L
  }

  # H1 lookup info
  n_profiled <- if (!is.null(model$H1_Lookup) &&
                    is.data.frame(model$H1_Lookup)) {
    nrow(model$H1_Lookup)
  } else {
    NA_integer_
  }

  # --- Statistics list --------------------------------------------------------
  statistics <- list(
    n_species    = n_species,
    n_singletons = n_singletons,
    n_anchors    = n_anchors,
    n_errors     = n_errors
  )
  if (!is.null(aic_score)) statistics$aic_score <- round(aic_score, 1)
  if (!is.na(n_profiled))  statistics$n_profiled <- n_profiled

  # --- Params -----------------------------------------------------------------
  params <- list(
    method = "hierarchical likelihood model"
  )
  if (!is.null(aic_score)) params$aic <- round(aic_score, 1)

  # --- Methods text -----------------------------------------------------------
  methods_parts <- sprintf(
    "A hierarchical likelihood model was trained on reference sequences spanning %d species",
    n_species
  )

  if (n_singletons > 0L) {
    methods_parts <- paste0(methods_parts,
                            sprintf(" (%d represented by a single sequence)", n_singletons))
  }
  methods_parts <- paste0(methods_parts, ".")

  methods_parts <- paste0(methods_parts,
    " Match scores were logit-transformed and modelled as bivariate normal",
    " distributions (score + gap features) with empirical Bayes shrinkage",
    " toward a global mean.")

  if (n_anchors > 0L) {
    methods_parts <- paste0(methods_parts,
      sprintf(" Perfect-match pseudo-data anchoring was applied (n = %d).", n_anchors))
  }

  if (n_errors > 0L) {
    methods_parts <- paste0(methods_parts,
      sprintf(" %d likely mislabeled reference sequences were detected and removed.", n_errors))
  }

  # --- Results text -----------------------------------------------------------
  results_parts <- character(0L)

  if (!is.null(aic_score)) {
    results_parts <- c(results_parts,
                       sprintf("Model AIC = %.1f.", aic_score))
  }

  if (!is.na(n_profiled)) {
    results_parts <- c(results_parts,
      sprintf("Species-specific parameters were estimated for %d taxa; %d singleton species used global parameters.",
              n_profiled, n_singletons))
  }

  results_text <- if (length(results_parts) > 0L) {
    paste(results_parts, collapse = " ")
  } else {
    NULL
  }

  # --- Construct report_section -----------------------------------------------
  TaxaTools::new_report_section(
    package    = "TaxaLikely",
    section    = "likelihood",
    methods    = methods_parts,
    results    = results_text,
    citations  = NULL,
    params     = params,
    statistics = statistics
  )
}
