utils::globalVariables(c("posterior_mean", "posterior_point_est", "posterior_sd",
                          "confidence_score", "hypothesis_type", "is_resolved",
                          "consensus_taxon", "consensus_rank", "prior_updated"))

# generate_report.R
# TaxaAssign package
#
# Generates publication-ready Methods and Results text from TaxaAssign output
# objects. Methods section is template-based; Results section is LLM-generated
# (with a template fallback when llm_fn = NULL).
#
# Exported functions:
#   generate_report()         Orchestrator: Methods + Results -> markdown string
#
# Internal helpers:
#   .detect_workflow()        Detect "llm" or "bayesian" from column presence
#   .extract_report_stats()   Compute summary statistics from result + consensus
#   .extract_unreferenced_stats()  Unreferenced species stats from S3 object
#   .build_methods_text()     Template-based methods section
#   .build_results_prompt()   LLM prompt for results narrative
#   .build_results_template() Bullet-point fallback for results


#' Generate Publication-Ready Report from TaxaAssign Output
#'
#' Produces a Methods and Results text suitable for inclusion in a scientific
#' paper. The Methods section is assembled from templates that adapt to the
#' workflow used (LLM-shortcut or Bayesian). The Results section summarises
#' assignment outcomes, either as LLM-composed prose or as a structured
#' bullet-point summary when \code{llm_fn = NULL}.
#'
#' Parameters used during the analysis (e.g. \code{n_sims},
#' \code{score_sharpness}, \code{cumulative_threshold}) are read from
#' \code{report_params} attributes attached to the input objects by upstream
#' functions. If these attributes are absent, sensible defaults are assumed.
#'
#' @param result Data frame or \code{NULL}. Posterior output from
#'   \code{\link{compute_posterior}} or \code{\link{assign_taxa_llm}}. Required
#'   when \code{consensus} comes from \code{\link{posterior_consensus}}.
#'   Pass \code{NULL} when \code{consensus} comes from
#'   \code{\link{score_consensus}} (no posterior data exists).
#' @param consensus Data frame. Output from \code{\link{posterior_consensus}}
#'   or \code{\link{score_consensus}}. The consensus type is detected
#'   automatically from column presence (\code{top_score} for score-based;
#'   \code{consensus_posterior} for posterior-based) and the report adapts
#'   accordingly.
#' @param unreferenced_result Optional. An \code{unreferenced_species_result}
#'   S3 object from \code{\link{suggest_unreferenced_species}}. When provided,
#'   the report includes reference database completeness statistics and
#'   unreferenced species findings.
#' @param data_type Character. One of \code{"eDNA"}, \code{"image"},
#'   \code{"acoustic"}, or \code{NULL}. Used to tailor methods language.
#' @param marker Character. Molecular marker name (e.g. \code{"12S MiFish"}).
#'   Used only when \code{data_type = "eDNA"}.
#' @param context_source Character. One of \code{"user"} (user provided
#'   geographic context manually) or \code{"llm"} (context was inferred by
#'   \code{\link{build_context}}). Affects the methods description of how
#'   geographic context was determined. Default \code{"user"}.
#' @param study_description Character. One or two sentences describing the study
#'   context, passed to the LLM to ground the results narrative.
#' @param llm_fn Function or \code{NULL}. LLM provider function following the
#'   TaxaTools \code{llm_fn} pattern. When \code{NULL}, the Results section
#'   uses a template-based bullet-point summary instead of LLM prose.
#' @param verbose Logical. Print progress messages. Default \code{FALSE}.
#'
#' @return A single character string containing markdown-formatted Methods and
#'   Results text. Printed to the console via \code{cat()} and returned
#'   invisibly.
#'
#' @examples
#' \dontrun{
#' report <- generate_report(
#'   result    = result_updated,
#'   consensus = consensus_final,
#'   data_type = "eDNA",
#'   marker    = "12S MiFish"
#' )
#' }
#'
#' @export
generate_report <- function(result,
                            consensus,
                            unreferenced_result = NULL,
                            data_type           = NULL,
                            marker              = NULL,
                            context_source      = "user",
                            study_description   = NULL,
                            llm_fn              = NULL,
                            verbose             = FALSE) {

  # --- Input validation -------------------------------------------------------
  if (!is.data.frame(consensus))
    cli::cli_abort("{.arg consensus} must be a data frame.")

  required_consensus <- c("observation_id", "consensus_taxon", "consensus_rank",
                          "is_resolved")
  missing_c <- setdiff(required_consensus, names(consensus))
  if (length(missing_c) > 0)
    cli::cli_abort("{.arg consensus} is missing column(s): {.field {missing_c}}")

  # Detect consensus type: score-based (has top_score) vs posterior-based
  consensus_type <- if ("top_score" %in% names(consensus)) "score" else "posterior"

  if (consensus_type == "posterior") {
    if (is.null(result) || !is.data.frame(result))
      cli::cli_abort("{.arg result} must be a data frame when consensus is from posterior_consensus().")
    required_result <- c("observation_id", "taxon_name", "posterior_mean")
    missing_r <- setdiff(required_result, names(result))
    if (length(missing_r) > 0)
      cli::cli_abort("{.arg result} is missing column(s): {.field {missing_r}}")
  }

  if (!is.null(unreferenced_result) &&
      !inherits(unreferenced_result, "unreferenced_species_result"))
    cli::cli_abort(
      "{.arg unreferenced_result} must be an {.cls unreferenced_species_result} object."
    )

  if (!is.null(data_type))
    data_type <- match.arg(data_type, c("eDNA", "image", "acoustic"))

  context_source <- match.arg(context_source, c("user", "llm"))

  if (!is.null(llm_fn) && !is.function(llm_fn))
    cli::cli_abort("{.arg llm_fn} must be a function or NULL.")

  # --- Detect workflow and gather parameters ----------------------------------
  if (consensus_type == "posterior") {
    workflow <- .detect_workflow(result)
  } else {
    workflow <- "score"
  }
  if (verbose) cli::cli_inform("Detected workflow: {.val {workflow}}")

  params <- .gather_report_params(result, consensus)

  # --- Detect LLM model name from llm_fn formals ---
  llm_model_name <- .detect_llm_model(llm_fn)

  # --- Extract statistics -----------------------------------------------------
  stats <- .extract_report_stats(result, consensus, consensus_type)

  unref_stats <- NULL
  if (!is.null(unreferenced_result))
    unref_stats <- .extract_unreferenced_stats(unreferenced_result, result,
                                                consensus)

  # --- Build Methods ----------------------------------------------------------
  methods_text <- .build_methods_text(workflow, params, data_type, marker,
                                      context_source,
                                      !is.null(unreferenced_result),
                                      !is.null(unref_stats) &&
                                        unref_stats$has_family_expansion,
                                      stats$has_empirical_bayes,
                                      llm_model_name)

  # --- Build Results ----------------------------------------------------------
  if (!is.null(llm_fn)) {
    if (verbose) cli::cli_inform("Generating results narrative via LLM...")
    results_text <- .build_results_llm(stats, unref_stats,
                                        study_description, llm_fn)
  } else {
    results_text <- .build_results_template(stats, unref_stats)
  }

  # --- Assemble ---------------------------------------------------------------
  report <- paste0(
    "## Methods\n\n", methods_text, "\n\n",
    "## Results\n\n", results_text
  )

  cat(report)
  invisible(report)
}


# ==============================================================================
# Internal helpers
# ==============================================================================

#' @noRd
.detect_workflow <- function(result) {
  llm_cols <- c("range_status", "habitat_fit", "information_quality")
  if (all(llm_cols %in% names(result))) "llm" else "bayesian"
}


#' @noRd
.gather_report_params <- function(result, consensus) {
  # Merge report_params attributes from both objects
  rp <- if (!is.null(result)) attr(result, "report_params") else NULL
  cp <- attr(consensus, "report_params")
  # result params take precedence for shared keys
  params <- c(cp, rp)  # later entries override
  params
}


#' @noRd
.detect_llm_model <- function(llm_fn) {
  if (is.null(llm_fn) || !is.function(llm_fn)) return(NULL)
  default_model <- tryCatch(formals(llm_fn)$model, error = function(e) NULL)
  if (is.null(default_model)) return(NULL)
  # formals() returns an unevaluated expression; eval to get the string
  tryCatch(eval(default_model), error = function(e) as.character(default_model))
}


#' @noRd
.build_citation_text <- function(llm_model_name = NULL) {
  # Programmatic citation from inst/CITATION
  cite <- tryCatch(
    utils::citation("TaxaAssign"),
    error = function(e) NULL
  )
  if (!is.null(cite) && length(cite) >= 2L) {
    # Second entry is the ecosystem citation
    eco <- cite[[2L]]
    cite_str <- format(eco, style = "text")
    cite_str <- paste(cite_str, collapse = " ")
  } else {
    cite_str <- "Lafferty, K. (2026). TaxaID: A Modular R Ecosystem for Bayesian Taxonomic Assignment. In preparation."
  }

  software_text <- sprintf(
    "All analyses were performed using the TaxaID R ecosystem (%s).",
    cite_str
  )

  # LLM caveat when any LLM was used
  if (!is.null(llm_model_name)) {
    caveat <- sprintf(
      paste0(
        "LLM-generated outputs (model: %s) are stochastic and may vary between ",
        "runs. All LLM-derived values (priors, range assessments, habitat ",
        "classifications) should be independently verified against authoritative ",
        "sources before use in regulatory or management decisions."
      ),
      llm_model_name
    )
    paste(software_text, caveat, sep = " ")
  } else {
    software_text
  }
}


#' @noRd
.extract_report_stats <- function(result, consensus, consensus_type = "posterior") {
  n_samples <- dplyr::n_distinct(consensus$observation_id)

  # Resolution breakdown
  n_resolved <- sum(consensus$is_resolved, na.rm = TRUE)
  resolution_rate <- round(100 * n_resolved / n_samples, 1)

  # Rank breakdown
  rank_table <- table(consensus$consensus_rank)

  # Unique taxa
  n_unique_taxa <- dplyr::n_distinct(consensus$consensus_taxon)

  # Upranked (consensus coarser than species) and downranked counts
  n_upranked <- sum(!consensus$is_resolved, na.rm = TRUE)
  n_downranked <- if ("downranked" %in% names(consensus))
    sum(consensus$downranked, na.rm = TRUE) else 0L

  # Score-based stats (only when consensus_type == "score")
  median_top_score <- NA_real_
  mean_top_score   <- NA_real_
  n_rank_capped    <- 0L
  n_whitelist_capped <- 0L
  if (consensus_type == "score" && "top_score" %in% names(consensus)) {
    scores <- consensus$top_score[!is.na(consensus$top_score)]
    if (length(scores) > 0) {
      median_top_score <- round(stats::median(scores, na.rm = TRUE), 2)
      mean_top_score   <- round(mean(scores, na.rm = TRUE), 2)
    }
    if ("rank_capped" %in% names(consensus))
      n_rank_capped <- sum(consensus$rank_capped, na.rm = TRUE)
    if ("whitelist_capped" %in% names(consensus))
      n_whitelist_capped <- sum(consensus$whitelist_capped, na.rm = TRUE)
  }

  # Posterior-based stats (only when result is available)
  median_posterior   <- NA_real_
  mean_posterior     <- NA_real_
  median_confidence  <- NA_real_
  mean_confidence    <- NA_real_
  has_mc             <- FALSE
  has_confidence     <- FALSE
  hyp_breakdown      <- NULL
  n_unreferenced_wins <- 0L
  has_empirical_bayes <- FALSE
  n_prior_updated     <- 0L
  n_consensus_unreferenced <- 0L

  if (!is.null(result) && is.data.frame(result)) {
    # Top hypothesis per observation
    top <- result |>
      dplyr::group_by(.data$observation_id) |>
      dplyr::slice_max(.data$posterior_mean, n = 1, with_ties = FALSE) |>
      dplyr::ungroup()

    median_posterior <- round(stats::median(top$posterior_mean, na.rm = TRUE), 3)
    mean_posterior   <- round(mean(top$posterior_mean, na.rm = TRUE), 3)

    has_confidence <- "confidence_score" %in% names(top) &&
      any(top$confidence_score > 0, na.rm = TRUE)
    if (has_confidence) {
      median_confidence <- round(stats::median(top$confidence_score, na.rm = TRUE), 3)
      mean_confidence   <- round(mean(top$confidence_score, na.rm = TRUE), 3)
    }

    has_mc <- "posterior_sd" %in% names(result) &&
      any(result$posterior_sd > 0, na.rm = TRUE)

    has_hyp_type <- "hypothesis_type" %in% names(top)
    if (has_hyp_type) {
      hyp_breakdown <- table(top$hypothesis_type)
      n_unreferenced_wins <- sum(
        top$hypothesis_type %in% c("unreferenced_species", "unreferenced_genus"),
        na.rm = TRUE
      )
    }

    has_empirical_bayes <- "prior_updated" %in% names(result)
    n_prior_updated <- if (has_empirical_bayes)
      sum(result$prior_updated, na.rm = TRUE) else 0L

    if ("hypothesis_type" %in% names(consensus)) {
      n_consensus_unreferenced <- sum(
        consensus$hypothesis_type %in% c("unreferenced_species", "unreferenced_genus"),
        na.rm = TRUE
      )
    }
  }

  list(
    consensus_type           = consensus_type,
    n_samples                = n_samples,
    n_resolved               = n_resolved,
    resolution_rate          = resolution_rate,
    rank_table               = rank_table,
    median_posterior          = median_posterior,
    mean_posterior            = mean_posterior,
    median_confidence         = median_confidence,
    mean_confidence           = mean_confidence,
    has_mc                    = has_mc,
    has_confidence            = has_confidence,
    n_unique_taxa             = n_unique_taxa,
    hyp_breakdown             = hyp_breakdown,
    n_unreferenced_wins       = n_unreferenced_wins,
    has_empirical_bayes       = has_empirical_bayes,
    n_prior_updated           = n_prior_updated,
    n_consensus_unreferenced  = n_consensus_unreferenced,
    n_upranked                = n_upranked,
    n_downranked              = n_downranked,
    median_top_score          = median_top_score,
    mean_top_score            = mean_top_score,
    n_rank_capped             = n_rank_capped,
    n_whitelist_capped        = n_whitelist_capped
  )
}


#' @noRd
.extract_unreferenced_stats <- function(unreferenced_result, result, consensus) {
  census   <- attr(unreferenced_result, "census")
  plausible <- attr(unreferenced_result, "plausible")
  unref_family <- attr(unreferenced_result, "unreferenced_family")

  n_unreferenced <- length(unreferenced_result)
  has_family_expansion <- !is.null(unref_family) && length(unref_family) > 0

  # --- Reference completeness from census ---
  # census is a data frame with columns like genus, in_reference, unreferenced, etc.
  ref_completeness <- NULL
  if (!is.null(census) && is.data.frame(census)) {
    # Compute per-genus % referenced and total species counts
    if (all(c("in_reference", "unreferenced") %in% names(census))) {
      total_per_genus <- census$in_reference + census$unreferenced
      # Also count has_seqs_not_in_ref if available (species with sequences
      # but not in the user's reference library)
      has_seqs <- if ("has_seqs_not_in_ref" %in% names(census))
        census$has_seqs_not_in_ref else rep(0L, nrow(census))
      total_described <- total_per_genus + has_seqs
      total_with_seqs <- census$in_reference + has_seqs

      # Avoid division by zero
      total_per_genus[total_per_genus == 0] <- NA_real_
      pct_referenced <- census$in_reference / total_per_genus * 100

      ref_completeness <- list(
        n_genera             = nrow(census),
        total_described      = sum(total_described, na.rm = TRUE),
        total_with_seqs      = sum(total_with_seqs, na.rm = TRUE),
        total_in_reference   = sum(census$in_reference, na.rm = TRUE),
        median_pct_ref       = round(stats::median(pct_referenced, na.rm = TRUE), 1),
        min_pct_ref          = round(min(pct_referenced, na.rm = TRUE), 1),
        max_pct_ref          = round(max(pct_referenced, na.rm = TRUE), 1),
        n_complete_genera    = sum(census$unreferenced == 0, na.rm = TRUE),
        n_incomplete_genera  = sum(census$unreferenced > 0, na.rm = TRUE)
      )
    }
  }

  # --- Plausible species fraction ---
  n_plausible <- if (!is.null(plausible)) length(plausible) else NA_integer_
  frac_unreferenced <- if (!is.na(n_plausible) && n_plausible > 0)
    round(n_unreferenced / n_plausible, 3) else NA_real_

  # --- Family expansion ---
  n_family_unreferenced <- if (has_family_expansion) length(unref_family) else 0L

  # --- Consensus outcomes for unreferenced taxa ---
  unreferenced_names <- as.character(unreferenced_result)
  n_consensus_to_unreferenced <- sum(
    consensus$consensus_taxon %in% unreferenced_names, na.rm = TRUE
  )

  list(
    n_unreferenced              = n_unreferenced,
    n_plausible                 = n_plausible,
    frac_unreferenced           = frac_unreferenced,
    ref_completeness            = ref_completeness,
    has_family_expansion        = has_family_expansion,
    n_family_unreferenced       = n_family_unreferenced,
    n_consensus_to_unreferenced = n_consensus_to_unreferenced
  )
}


# ==============================================================================
# Methods text (template-based)
# ==============================================================================

#' @noRd
.build_methods_text <- function(workflow, params, data_type, marker,
                                 context_source,
                                 has_unreferenced, has_family_expansion,
                                 has_empirical_bayes,
                                 llm_model_name = NULL) {
  sections <- character(0)

  # --- Data type preamble ---
  data_desc <- switch(
    if (!is.null(data_type)) data_type else "generic",
    eDNA = if (!is.null(marker)) {
      sprintf("Taxonomic assignments were made from %s metabarcoding sequence data.", marker)
    } else {
      "Taxonomic assignments were made from environmental DNA (eDNA) metabarcoding sequence data."
    },
    image    = "Taxonomic assignments were made from image-based species identification data.",
    acoustic = "Taxonomic assignments were made from acoustic species identification data.",
    generic  = "Taxonomic assignments were made from species identification data."
  )

  # --- Workflow introductory sentence ---
  if (workflow == "score") {
    intro <- paste0(
      "Taxonomic consensus was determined using a conventional score-based ",
      "approach based on match quality thresholds applied to reference database ",
      "search results."
    )
  } else if (workflow == "llm") {
    llm_label <- if (!is.null(llm_model_name)) {
      sprintf("a large language model (LLM; %s)", llm_model_name)
    } else {
      "a large language model (LLM)"
    }
    intro <- sprintf(
      paste0(
        "Rather than the conventional method of basing taxonomic assignments on ",
        "likelihood scores alone, assignments were estimated using a Bayesian ",
        "framework in which both match likelihoods and occurrence priors were ",
        "approximated by %s, rather than derived from ",
        "statistical training on the reference database and species occurrence ",
        "records, respectively."
      ),
      llm_label
    )
  } else {
    intro <- paste0(
      "Assignments were estimated using a hierarchical Bayesian framework ",
      "combining statistically modeled match likelihoods with occurrence-based ",
      "priors."
    )
  }
  sections <- c(sections, paste(data_desc, intro))

  # --- Score-based consensus Methods (workflow == "score") ---
  if (workflow == "score") {
    min_sc  <- if (!is.null(params$min_score)) params$min_score else 0
    max_gp  <- if (!is.null(params$max_gap)) params$max_gap else Inf
    rt      <- params$rank_thresholds
    has_wl  <- isTRUE(params$has_whitelist)

    score_text <- sprintf(
      paste0(
        "For each observation, reference hits with match scores below %s were ",
        "discarded. Among the remaining hits, all candidates within %s of the ",
        "top score were retained."
      ),
      min_sc,
      if (is.infinite(max_gp)) "any distance" else sprintf("%s%%", max_gp)
    )

    score_text <- paste0(
      score_text,
      " A consensus taxonomic assignment was determined using a least common ",
      "ancestor (LCA) algorithm: the consensus was set to the most specific ",
      "taxonomic rank at which all retained hits agreed."
    )

    if (!is.null(rt)) {
      thresh_parts <- vapply(names(rt), function(rk) {
        sprintf("%s >= %s%%", rk, rt[[rk]])
      }, character(1))
      score_text <- paste0(
        score_text,
        sprintf(
          " The consensus rank was then capped at the finest level whose minimum score threshold was met (%s).",
          paste(thresh_parts, collapse = ", ")
        )
      )
    }

    if (has_wl) {
      score_text <- paste0(
        score_text,
        " Additionally, a plausible-taxa whitelist was applied: if the ",
        "consensus taxon was not in the whitelist, the assignment was upranked ",
        "to the coarsest rank where a whitelisted taxon agreed with the ",
        "retained candidates."
      )
    }

    sections <- c(sections, score_text)

    # Software citation and return early for score workflow
    sections <- c(sections, .build_citation_text(llm_model_name))
    return(paste(sections, collapse = "\n\n"))
  }

  # --- Likelihood estimation (posterior workflows only) ---
  if (workflow == "llm") {
    sharpness <- if (!is.null(params$score_sharpness)) params$score_sharpness else 0.1
    unk_wt    <- if (!is.null(params$unknown_lik_weight)) params$unknown_lik_weight else 0.05
    threshold <- if (!is.null(params$score_threshold)) params$score_threshold else 80
    top_n     <- if (!is.null(params$top_n)) params$top_n else 10L

    lik_text <- sprintf(
      paste0(
        "Likelihoods were derived from match scores using exponential weighting. ",
        "For each observation, candidate taxa with scores above %s were retained (up to ",
        "the top %d candidates). Match scores were transformed via an exponential ",
        "function (sharpness parameter = %s) and normalized to sum to one, producing ",
        "a likelihood estimate for each candidate taxon. A residual likelihood of %s ",
        "was reserved for the possibility that the true taxon was not among the named ",
        "candidates."
      ),
      threshold, top_n, sharpness, unk_wt
    )
  } else {
    lik_text <- paste0(
      "Likelihoods were estimated using a hierarchical statistical model trained ",
      "on the reference database (TaxaLikely package). Per-species score ",
      "distributions were modeled as bivariate normal distributions in ",
      "logit-transformed score and gap (difference between best and second-best ",
      "match) space, with empirical Bayes shrinkage toward a global mean. ",
      "Three hypothesis types were evaluated for each observation: that the true taxon ",
      "is a species present in the reference database (H1), a congener absent from ",
      "the reference (H2), or a member of a different genus entirely (H3)."
    )
  }
  sections <- c(sections, lik_text)

  # --- Prior estimation ---
  if (workflow == "llm") {
    phi <- params$prior_phi
    phi_text <- if (!is.null(phi) && length(phi) == 3) {
      sprintf(
        paste0(
          "The LLM also rated its information quality for each taxon as high, moderate, ",
          "or low; these ratings controlled the concentration of the Beta-distributed ",
          "prior (phi = %s, %s, and %s, respectively), with higher concentration ",
          "indicating greater certainty in the prior estimate."
        ),
        phi["high"], phi["moderate"], phi["low"]
      )
    } else ""

    absent_prob <- if (!is.null(params$absent_detection_prob)) params$absent_detection_prob else 0.80

    context_desc <- if (context_source == "llm") {
      paste0(
        "Geographic context (ecoregion and dominant habitat) was inferred by the ",
        "LLM from the assemblage of candidate taxa, rather than specified by the analyst. "
      )
    } else {
      paste0(
        "Geographic context (ecoregion and dominant habitat) was specified by the ",
        "analyst based on the study site. "
      )
    }

    prior_text <- paste0(
      "Prior probabilities of occurrence were estimated by a large language model ",
      "(LLM) based on geographic context and habitat information. ",
      context_desc,
      "For each unique ",
      "taxon, the LLM assessed geographic range status (native, introduced, or ",
      "unknown) and habitat fit (expected, occasional, or unlikely), returning a ",
      "relative weight reflecting the plausibility of encountering that taxon at ",
      "the study site. Weights were normalized to produce prior probabilities. ",
      phi_text,
      if (absent_prob < 1) sprintf(
        paste0(
          " Taxa presumed to be absent from the study area had their ",
          "priors reduced by a factor of %s (the estimated probability of non-detection), ",
          "accounting for the possibility of rare or transient occurrences."
        ),
        1 - absent_prob
      ) else ""
    )
  } else {
    prior_text <- paste0(
      "Prior probabilities were generated from species occurrence records and ",
      "habitat models (TaxaExpect package). Occurrence data from public ",
      "biodiversity databases were combined with habitat classifications to ",
      "estimate the probability of encountering each taxon at the study site. ",
      "Prior uncertainty was parameterized using a Beta distribution, where the ",
      "shape parameters (alpha, beta) encode both the expected probability and ",
      "the degree of confidence in that estimate."
    )
  }
  sections <- c(sections, prior_text)

  # --- Unreferenced species ---
  if (has_unreferenced) {
    unref_intro <- paste0(
      "Because reference databases are inevitably incomplete, species absent from ",
      "the reference but biogeographically plausible were included as competing ",
      "hypotheses. Plausible unreferenced species were identified per genus using ",
      "a large language model informed by the study location and habitat, then ",
      "confirmed as unreferenced by querying NCBI GenBank for the absence of ",
      "relevant barcode sequences."
    )

    if (workflow == "llm") {
      unref_lik <- paste0(
        " Each unreferenced species was assigned a ",
        "likelihood equal to the median likelihood of its referenced congeners ",
        "(or family members, for family-level unreferenced taxa), reflecting the ",
        "expectation that an unreferenced species would produce match scores ",
        "similar to those of its closest relatives in the reference."
      )
    } else {
      unref_lik <- paste0(
        " Likelihoods for unreferenced species were derived from the trained ",
        "likelihood model (TaxaLikely package), which estimates the expected score ",
        "distribution for a species absent from the reference (H2 hypothesis) based ",
        "on the distance between within-species and cross-species match score ",
        "distributions observed in the training data."
      )
    }
    unref_text <- paste0(unref_intro, unref_lik)
    if (has_family_expansion) {
      unref_text <- paste0(
        unref_text,
        " When no plausible unreferenced species were found within a genus, the ",
        "search was expanded to the family level to capture potential diversity ",
        "from related genera."
      )
    }
    sections <- c(sections, unref_text)
  }

  # --- Posterior computation ---
  n_sims <- if (!is.null(params$n_sims)) params$n_sims else 1000L
  if (n_sims > 0) {
    post_text <- sprintf(
      paste0(
        "Posterior probabilities were computed for each observation as the normalized ",
        "product of likelihood and prior (Bayes' theorem). To propagate uncertainty, ",
        "%d Monte Carlo simulations were performed: in each simulation, likelihoods ",
        "were drawn from their estimated distributions and priors were sampled from ",
        "their Beta distributions. The posterior mean and standard deviation across ",
        "simulations were recorded, along with a confidence score representing the ",
        "fraction of simulations in which each taxon had the highest posterior ",
        "probability."
      ),
      n_sims
    )
  } else {
    post_text <- paste0(
      "Posterior probabilities were computed for each observation as the normalized ",
      "product of likelihood and prior (Bayes' theorem), producing a point estimate ",
      "of the posterior probability for each candidate taxon."
    )
  }
  sections <- c(sections, post_text)

  # --- Consensus taxonomy ---
  cum_thresh <- if (!is.null(params$cumulative_threshold)) params$cumulative_threshold else 0.9
  min_post   <- if (!is.null(params$min_posterior)) params$min_posterior else 0.05

  multiplier <- params$presence_multiplier
  has_eb <- !is.null(multiplier) || has_empirical_bayes
  if (is.null(multiplier) && has_eb) multiplier <- 5L  # default

  cons_text <- sprintf(
    paste0(
      "A consensus taxonomic assignment was determined for each observation using a ",
      "lowest common ancestor (LCA) algorithm. Candidate taxa with individual ",
      "posterior probabilities below %s were excluded. Among the remaining ",
      "candidates, hypotheses were accumulated in decreasing order of posterior ",
      "probability until their cumulative sum reached %s. The consensus was set ",
      "to the most specific taxonomic rank at which all retained hypotheses agreed. ",
      "When all plausible hypotheses belonged to the same species, the assignment ",
      "was considered resolved to species level."
    ),
    min_post, cum_thresh
  )
  sections <- c(sections, cons_text)

  # --- Empirical Bayes ---
  if (has_eb) {
    eb_text <- sprintf(
      paste0(
        "Following the initial consensus, a single-pass empirical Bayes ",
        "refinement was applied: species that were confidently identified in at ",
        "least one observation had their prior probabilities multiplied by %s in all ",
        "remaining unresolved observations, reflecting the increased likelihood of ",
        "encountering a species already confirmed as present in the dataset. ",
        "Posteriors were then recomputed and the consensus algorithm was re-run ",
        "for the affected observations. This step used only cross-observation evidence ",
        "(an observation's own posterior was never used to update its own prior)."
      ),
      multiplier
    )
    sections <- c(sections, eb_text)
  }

  # --- Software citation and LLM caveat ---
  sections <- c(sections, .build_citation_text(llm_model_name))

  paste(sections, collapse = "\n\n")
}


# ==============================================================================
# Results text
# ==============================================================================

#' @noRd
.build_results_prompt <- function(stats, unref_stats, study_description) {
  # Build a structured data block for the LLM
  lines <- c(
    "ASSIGNMENT SUMMARY:",
    sprintf("- Total observations: %d", stats$n_samples),
    sprintf("- Resolved to species: %d (%.1f%%)",
            stats$n_resolved, stats$resolution_rate),
    sprintf("- Unique taxa assigned: %d", stats$n_unique_taxa),
    "",
    "RANK BREAKDOWN:"
  )
  for (rk in names(stats$rank_table)) {
    lines <- c(lines, sprintf("- %s: %d", rk, stats$rank_table[[rk]]))
  }

  if (stats$consensus_type == "score") {
    lines <- c(lines, "",
      "TOP MATCH SCORE (per observation):",
      sprintf("- Median: %s", stats$median_top_score),
      sprintf("- Mean: %s", stats$mean_top_score)
    )
    if (stats$n_rank_capped > 0)
      lines <- c(lines,
        sprintf("- Assignments capped by rank thresholds: %d", stats$n_rank_capped))
    if (stats$n_whitelist_capped > 0)
      lines <- c(lines,
        sprintf("- Assignments upranked by whitelist: %d", stats$n_whitelist_capped))
  } else {
    lines <- c(lines, "",
      "POSTERIOR PROBABILITY (top hypothesis per observation):",
      sprintf("- Median: %s", stats$median_posterior),
      sprintf("- Mean: %s", stats$mean_posterior)
    )

    if (stats$has_confidence) {
      lines <- c(lines, "",
        "CONFIDENCE SCORE (fraction of MC simulations won by top hypothesis):",
        sprintf("- Median: %s", stats$median_confidence),
        sprintf("- Mean: %s", stats$mean_confidence)
      )
    }
  }

  # Upranked / downranked
  if (stats$n_upranked > 0 || stats$n_downranked > 0) {
    lines <- c(lines, "",
      "CONSENSUS RANK ADJUSTMENTS:",
      sprintf("- Upranked to coarser rank due to ambiguity (these were tabulated): %d", stats$n_upranked)
    )
    if (stats$n_downranked > 0) {
      lines <- c(lines,
        sprintf("- Downranked to finer rank via species reference: %d",
                stats$n_downranked)
      )
    }
  }

  if (stats$n_unreferenced_wins > 0) {
    lines <- c(lines, "",
      sprintf("UNREFERENCED SPECIES: %d observation(s) had an unreferenced species as top hypothesis.",
              stats$n_unreferenced_wins),
      sprintf("- Consensus assignments to unreferenced taxa: %d",
              stats$n_consensus_unreferenced)
    )
  }

  if (stats$has_empirical_bayes) {
    lines <- c(lines, "",
      sprintf("EMPIRICAL BAYES: %d row(s) had priors updated based on cross-observation evidence.",
              stats$n_prior_updated)
    )
  }

  # Unreferenced species detail
  if (!is.null(unref_stats)) {
    lines <- c(lines, "", "REFERENCE DATABASE COMPLETENESS:")
    rc <- unref_stats$ref_completeness
    if (!is.null(rc)) {
      lines <- c(lines,
        sprintf("- Genera investigated: %d", rc$n_genera),
        sprintf("- Total described species across these genera: %d", rc$total_described),
        sprintf("- Species with barcode sequences in NCBI: %d", rc$total_with_seqs),
        sprintf("- Species in the user's reference database: %d", rc$total_in_reference),
        sprintf("- Genera with complete reference coverage: %d", rc$n_complete_genera),
        sprintf("- Genera with incomplete coverage: %d", rc$n_incomplete_genera),
        sprintf("- Per-genus %% of species in reference: median %.1f%%, range %.1f%%--%.1f%%",
                rc$median_pct_ref, rc$min_pct_ref, rc$max_pct_ref)
      )
    }
    lines <- c(lines,
      sprintf("- Plausible species from the observation location: %s",
              if (!is.na(unref_stats$n_plausible)) unref_stats$n_plausible else "unknown"),
      sprintf("- Of those, unreferenced (no barcode sequence): %d (%.1f%%)",
              unref_stats$n_unreferenced,
              if (!is.na(unref_stats$frac_unreferenced))
                unref_stats$frac_unreferenced * 100 else 0),
      sprintf("- Consensus assignments to unreferenced taxa (by process of elimination): %d",
              unref_stats$n_consensus_to_unreferenced)
    )
    if (unref_stats$has_family_expansion) {
      lines <- c(lines,
        sprintf("- Family-level unreferenced taxa: %d",
                unref_stats$n_family_unreferenced)
      )
    }
  }

  paste(lines, collapse = "\n")
}


#' @noRd
.build_results_llm <- function(stats, unref_stats,
                                study_description, llm_fn) {
  data_block <- .build_results_prompt(stats, unref_stats, study_description)

  study_ctx <- if (!is.null(study_description)) {
    sprintf("\nSTUDY CONTEXT: %s\n", study_description)
  } else ""

  if (stats$consensus_type == "score") {
    para_instructions <- paste0(
      "Write 2-3 paragraphs:\n",
      "- First paragraph: Overview of assignment success (how many observations, ",
      "resolution rate, unique taxa).\n",
      "- Second paragraph: Match score quality and rank breakdown. Report median ",
      "and mean top scores, the distribution of consensus ranks, and any rank ",
      "threshold capping or whitelist upranking that occurred. Include counts of ",
      "upranked taxa if present.\n",
      if (!is.null(unref_stats)) {
        paste0(
          "- Third paragraph: Reference database completeness and unreferenced ",
          "species findings (what unreferenced means, how many, outcomes).\n"
        )
      } else ""
    )
  } else {
    para_instructions <- paste0(
      "Write 2-4 paragraphs:\n",
      "- First paragraph: Overview of assignment success (how many observations, ",
      "resolution rate, unique taxa).\n",
      "- Second paragraph: Posterior probability and confidence (what these mean, ",
      "their distributions). Include counts of upranked and downranked taxa if present.\n",
      if (!is.null(unref_stats) || stats$n_unreferenced_wins > 0) {
        paste0(
          "- Third paragraph: Reference database completeness and unreferenced ",
          "species findings (what unreferenced means, how many, outcomes).\n"
        )
      } else "",
      if (stats$has_empirical_bayes) {
        "- A paragraph on the effect of empirical Bayes refinement.\n"
      } else ""
    )
  }

  prompt <- paste0(
    "You are a scientific writer composing the Results section of a taxonomy ",
    "methods paper. Write for readers who did not perform the analysis. Avoid ",
    "jargon; define statistical terms on first use. Do not use bullet points. ",
    "Write in past tense.\n\n",
    para_instructions,
    study_ctx,
    "\nHere are the statistics to report:\n\n",
    data_block,
    "\n\nWrite the Results section now. Return ONLY the prose paragraphs, ",
    "no headings or markdown formatting."
  )

  response <- llm_fn(prompt)
  # Extract text — handle both raw string and list responses
  if (is.list(response) && !is.null(response$text)) {
    response$text
  } else if (is.character(response)) {
    response
  } else {
    cli::cli_warn("Could not parse LLM response; falling back to template.")
    .build_results_template(stats, unref_stats)
  }
}


#' @noRd
.build_results_template <- function(stats, unref_stats = NULL) {
  lines <- c(
    sprintf(
      "Of %d observations analyzed, %d (%.1f%%) were resolved to species level, ",
      stats$n_samples, stats$n_resolved, stats$resolution_rate
    ),
    sprintf(
      "yielding %d unique taxonomic assignments.", stats$n_unique_taxa
    )
  )
  first_para <- paste0(lines, collapse = "")

  # Rank breakdown
  rank_parts <- vapply(names(stats$rank_table), function(rk) {
    sprintf("%s: %d", rk, stats$rank_table[[rk]])
  }, character(1))
  rank_line <- sprintf(
    "Consensus assignments by rank: %s.", paste(rank_parts, collapse = "; ")
  )

  if (stats$consensus_type == "score") {
    # Score-based second paragraph
    score_line <- sprintf(
      "The median top match score across observations was %s (mean %s).",
      stats$median_top_score, stats$mean_top_score
    )

    rank_adj <- ""
    if (stats$n_rank_capped > 0) {
      rank_adj <- sprintf(
        " %d assignment(s) were capped at a coarser rank because the top score did not meet the rank-specific threshold.",
        stats$n_rank_capped
      )
    }
    if (stats$n_whitelist_capped > 0) {
      rank_adj <- paste0(rank_adj, sprintf(
        " %d assignment(s) were upranked because the consensus taxon was absent from the plausible-taxa whitelist.",
        stats$n_whitelist_capped
      ))
    }
    if (stats$n_upranked > 0) {
      rank_adj <- paste0(rank_adj, sprintf(
        " In total, %d assignment(s) were resolved to a coarser rank than species due to disagreement among retained hits or threshold constraints.",
        stats$n_upranked
      ))
    }

    second_para <- paste0(rank_line, " ", score_line, rank_adj)
  } else {
    # Posterior-based second paragraph
    post_line <- sprintf(
      "The median posterior probability of the top-ranked hypothesis was %s (mean %s).",
      stats$median_posterior, stats$mean_posterior
    )

    conf_line <- ""
    if (stats$has_confidence) {
      conf_line <- sprintf(
        " The median confidence score (fraction of Monte Carlo simulations in which the top hypothesis was favored) was %s (mean %s).",
        stats$median_confidence, stats$mean_confidence
      )
    }

    rank_adj <- ""
    if (stats$n_upranked > 0) {
      rank_adj <- sprintf(
        " %d assignment(s) were resolved to a coarser rank (e.g., genus or family) due to ambiguity among competing hypotheses (these were tabulated).",
        stats$n_upranked
      )
    }
    if (stats$n_downranked > 0) {
      rank_adj <- paste0(rank_adj, sprintf(
        " %d assignment(s) were downranked to a finer taxonomic level when only one plausible candidate existed within the consensus group.",
        stats$n_downranked
      ))
    }

    second_para <- paste0(rank_line, " ", post_line, conf_line, rank_adj)
  }

  paras <- c(first_para, second_para)

  # Unreferenced
  if (!is.null(unref_stats) || stats$n_unreferenced_wins > 0) {
    unref_lines <- character(0)
    if (!is.null(unref_stats)) {
      rc <- unref_stats$ref_completeness
      if (!is.null(rc)) {
        unref_lines <- c(unref_lines, sprintf(
          paste0(
            "Reference database completeness was assessed across %d genera ",
            "encompassing %d described species, of which %d had barcode sequences ",
            "in NCBI and %d were included in the reference database. ",
            "The median percentage of described species represented in the reference ",
            "was %.1f%% (range: %.1f%%--%.1f%%). %d genera had complete coverage ",
            "and %d had incomplete coverage."
          ),
          rc$n_genera, rc$total_described, rc$total_with_seqs,
          rc$total_in_reference,
          rc$median_pct_ref, rc$min_pct_ref, rc$max_pct_ref,
          rc$n_complete_genera, rc$n_incomplete_genera
        ))
      }
      if (!is.na(unref_stats$n_plausible)) {
        unref_lines <- c(unref_lines, sprintf(
          paste0(
            "Of %d plausible species from the observation location, %d (%.1f%%) lacked ",
            "barcode sequences in public databases and were therefore unreferenced."
          ),
          unref_stats$n_plausible, unref_stats$n_unreferenced,
          unref_stats$frac_unreferenced * 100
        ))
      }
      if (unref_stats$n_consensus_to_unreferenced > 0) {
        unref_lines <- c(unref_lines, sprintf(
          "%d consensus assignment(s) were to unreferenced taxa using the process of elimination.",
          unref_stats$n_consensus_to_unreferenced
        ))
      }
    } else if (stats$n_unreferenced_wins > 0) {
      unref_lines <- c(unref_lines, sprintf(
        "%d observation(s) had an unreferenced species as the top-ranked hypothesis.",
        stats$n_unreferenced_wins
      ))
    }
    paras <- c(paras, paste(unref_lines, collapse = " "))
  }

  # Empirical Bayes (posterior workflows only)
  if (stats$has_empirical_bayes && stats$n_prior_updated > 0) {
    paras <- c(paras, sprintf(
      "Empirical Bayes refinement updated priors for %d observation(s) based on cross-observation evidence from confidently identified species.",
      stats$n_prior_updated
    ))
  }

  paste(paras, collapse = "\n\n")
}
