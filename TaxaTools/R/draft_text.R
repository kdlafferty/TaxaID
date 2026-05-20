# ==============================================================================
# draft_text.R
# TaxaTools -- LLM-based methods and results text generation
#
# Exported functions:
#   build_report_context() Structured fact sheet for grounding LLM output
#   draft_methods_text()   Read R code and describe what was done
#   draft_results_text()   Read R objects and summarize findings
#
# These are general-purpose functions for any analysis workflow.
# For TaxaAssign-specific report generation, see generate_report() in TaxaAssign.
# ==============================================================================


# ==============================================================================
# build_report_context()
# ==============================================================================

#' Build a Report Context Object
#'
#' Creates a structured context object containing grounded facts about an
#' analysis. When passed to \code{\link{draft_methods_text}} or
#' \code{\link{draft_results_text}}, these facts are injected into the LLM
#' prompt so the model uses verified information rather than inferring from
#' code comments or data summaries.
#'
#' This function is domain-agnostic. It works for any analysis workflow --
#' ecological surveys, clinical trials, economic models, etc. Domain-specific
#' details (e.g., molecular markers, study sites, model types) belong in the
#' \code{facts} parameter as named key-value pairs.
#'
#' @param study_description Character. One or two sentences describing the
#'   study (e.g., \code{"eDNA metabarcoding of coral reef fish at Palmyra
#'   Atoll"}, or \code{"Phase III clinical trial of drug X in 500
#'   patients"}). Default \code{NULL}.
#' @param data_type Character. Type of data (e.g., \code{"eDNA"},
#'   \code{"survey"}, \code{"time series"}, \code{"spatial"},
#'   \code{"experimental"}). Default \code{NULL}.
#' @param workflow Character. Analysis pipeline or approach
#'   (e.g., \code{"Bayesian likelihood model"}, \code{"mixed-effects
#'   regression"}, \code{"machine learning classification"}).
#'   Default \code{NULL}.
#' @param packages Character vector. Software packages used, with optional
#'   version info (e.g., \code{c("lme4 1.1-35", "ggplot2", "dplyr")}).
#'   Default \code{NULL}.
#' @param parameters Named list. Key analysis parameters and their values
#'   (e.g., \code{list(alpha = 0.05, n_iterations = 1000,
#'   min_score = 70)}). Default \code{NULL}.
#' @param statistics Named list. Summary statistics to report as verified
#'   facts (e.g., \code{list(n_samples = 70, n_resolved = 65,
#'   resolution_rate = 92.9, mean_effect_size = 0.45)}). Default
#'   \code{NULL}.
#' @param citations Character vector. References to incorporate into the
#'   text (e.g., \code{c("Callahan et al. (2016) DADA2",
#'   "R Core Team (2025)")}). Default \code{NULL}.
#' @param facts Named list. Domain-specific grounding facts as key-value
#'   pairs. Use this for any information that does not fit the other
#'   fields (e.g., \code{list(location = "Palmyra Atoll",
#'   marker = "12S MiFish", sampling_year = 2017,
#'   model_type = "VAR(2)")}). Default \code{NULL}.
#'
#' @return An S3 object of class \code{"report_context"} (a named list).
#'
#' @details
#' The context object is intentionally simple -- a named list with a class
#' attribute and a print method. All fields are optional. The LLM prompt
#' is built only from fields that are non-NULL, so a minimal context with
#' just \code{study_description} is valid.
#'
#' \strong{Why use a context?} Without a context, the LLM infers facts from
#' code comments and data summaries, which may be incomplete or ambiguous.
#' The context lets you provide verified numbers and details that the LLM
#' must use as ground truth, reducing hallucination and ensuring consistency
#' between the methods and results text.
#'
#' \strong{statistics vs. facts:} Use \code{statistics} for numeric results
#' (sample sizes, rates, counts) and \code{facts} for non-numeric
#' domain knowledge (study location, equipment, species groups).
#' \code{statistics} are presented to the LLM under a "Statistics" heading
#' and are restricted to the results text. \code{facts} appear under
#' "Additional facts" and may appear in either methods or results.
#'
#' \strong{Reuse:} Build one context object and pass it to both
#' \code{draft_methods_text()} and \code{draft_results_text()} for
#' consistent grounding across sections.
#'
#' Pipeline-specific packages can provide helper functions that extract
#' facts from their output objects and pass them here (e.g., a TaxaAssign
#' helper that reads \code{report_params} attributes from posterior
#' output and consensus objects).
#'
#' @examples
#' # Ecology example
#' ctx <- build_report_context(
#'   study_description = "eDNA survey of reef fish",
#'   data_type = "eDNA",
#'   parameters = list(min_score = 70, score_range = 2),
#'   statistics = list(n_samples = 70, n_esvs = 89),
#'   facts = list(marker = "12S MiFish", location = "Palmyra Atoll")
#' )
#'
#' # Clinical example
#' ctx2 <- build_report_context(
#'   study_description = "Phase III RCT of treatment X",
#'   data_type = "experimental",
#'   workflow = "intention-to-treat analysis with Cox regression",
#'   statistics = list(n_patients = 500, median_followup_months = 24),
#'   facts = list(primary_endpoint = "overall survival")
#' )
#'
#' @export
build_report_context <- function(study_description = NULL,
                                  data_type         = NULL,
                                  workflow          = NULL,
                                  packages          = NULL,
                                  parameters        = NULL,
                                  statistics        = NULL,
                                  citations         = NULL,
                                  facts             = NULL) {

  # Validate types
  if (!is.null(study_description) &&
      (!is.character(study_description) || length(study_description) != 1L))
    stop("study_description must be a single character string or NULL")
  if (!is.null(data_type) && (!is.character(data_type) || length(data_type) != 1L))
    stop("data_type must be a single character string or NULL")
  if (!is.null(workflow) && (!is.character(workflow) || length(workflow) != 1L))
    stop("workflow must be a single character string or NULL")
  if (!is.null(packages) && !is.character(packages))
    stop("packages must be a character vector or NULL")
  if (!is.null(parameters) && !is.list(parameters))
    stop("parameters must be a named list or NULL")
  if (!is.null(statistics) && !is.list(statistics))
    stop("statistics must be a named list or NULL")
  if (!is.null(citations) && !is.character(citations))
    stop("citations must be a character vector or NULL")
  if (!is.null(facts) && !is.list(facts))
    stop("facts must be a named list or NULL")

  ctx <- list(
    study_description = study_description,
    data_type         = data_type,
    workflow          = workflow,
    packages          = packages,
    parameters        = parameters,
    statistics        = statistics,
    citations         = citations,
    facts             = facts
  )

  # Remove NULL entries for clean printing
  ctx <- Filter(Negate(is.null), ctx)

  structure(ctx, class = "report_context")
}


#' Print a Report Context Object
#'
#' Displays a human-readable summary of a \code{report_context} object,
#' showing each field and its value(s).
#'
#' @param x A \code{report_context} object (from \code{\link{build_report_context}}).
#' @param ... Additional arguments (ignored).
#' @return \code{x}, invisibly.
#' @export
print.report_context <- function(x, ...) {
  cat("Report Context\n")
  cat(strrep("-", 40), "\n")
  for (nm in names(x)) {
    val <- x[[nm]]
    if (is.list(val)) {
      cat(sprintf("  %s:\n", nm))
      for (k in names(val)) {
        cat(sprintf("    %s = %s\n", k, paste(val[[k]], collapse = ", ")))
      }
    } else if (length(val) > 1L) {
      cat(sprintf("  %s: %s\n", nm, paste(val, collapse = "; ")))
    } else {
      cat(sprintf("  %s: %s\n", nm, val))
    }
  }
  invisible(x)
}


# ==============================================================================
# draft_methods_text()
# ==============================================================================

#' Draft Methods Text from R Code
#'
#' Reads R code (a script, file path, or character vector of code lines) and
#' uses an LLM to draft a methods section describing the analysis in
#' scientific prose.
#'
#' @param code Character. One of:
#'   \itemize{
#'     \item A file path to an R script (must exist)
#'     \item A character vector of code lines (e.g., from \code{readLines()})
#'     \item A single string of R code
#'   }
#' @param description Character. Brief study context to guide the LLM
#'   (e.g., \code{"eDNA metabarcoding of coral reef fish at Palmyra Atoll
#'   using MiFish 12S primers"}). Default \code{NULL}. Ignored when
#'   \code{context} is provided (uses \code{context$study_description}).
#' @param context A \code{report_context} object from
#'   \code{\link{build_report_context}}. Provides structured facts (study
#'   description, parameters, statistics, citations) that the LLM must use
#'   as ground truth. When provided, overrides \code{description}. Default
#'   \code{NULL}.
#' @param audience Character. Target audience: \code{"journal"} (default)
#'   for peer-reviewed publication style, \code{"technical"} for a methods
#'   appendix with parameter details, or \code{"brief"} for a short summary.
#' @param llm_fn Function. LLM provider function with signature
#'   \code{function(prompt_str, ...) -> character(1)}. Default
#'   \code{call_anthropic_api}.
#' @param max_code_lines Integer. Maximum number of code lines to include
#'   in the prompt. Long scripts are truncated with a note. Default
#'   \code{300L}.
#' @param verbose Logical. Print progress messages. Default \code{FALSE}.
#'
#' @return A character string containing the drafted methods text.
#'   Printed to the console via \code{cat()} and returned invisibly.
#'
#' @details
#' The function sends the R code to the LLM with instructions to:
#' \itemize{
#'   \item Describe the analysis workflow in past tense
#'   \item Note key parameters and their values
#'   \item Use appropriate scientific language for the audience
#'   \item Avoid reproducing code; describe what was done conceptually
#'   \item \strong{Not report findings or summary statistics} -- these
#'     belong in the Results section (use \code{\link{draft_results_text}})
#'   \item Flag any analysis steps that used LLM-generated data, with a
#'     caveat about stochastic output
#' }
#'
#' \strong{Code comments are treated as facts.} If the code contains
#' comments like \code{"# 70 paired-end MiSeq samples"} or
#' \code{"# DADA2 denoised with default parameters"}, the LLM will
#' incorporate this information into the methods text. Make sure code
#' comments are accurate before passing the script. To provide verified
#' facts that override inferences from code comments, use the
#' \code{context} parameter.
#'
#' \strong{Statistics bleed guard.} When a \code{context} is provided,
#' its \code{statistics} field (sample sizes, resolution rates, etc.) is
#' shown to the LLM for accuracy checking only. The LLM is explicitly
#' instructed not to report these numbers in the methods text. If you
#' find statistics appearing in the methods output, they likely came from
#' code comments rather than the context; review and clean the code
#' comments, or use a more targeted code excerpt.
#'
#' \strong{LLM stochasticity.} Because the output is generated by an LLM,
#' it will vary slightly between runs. The output is a starting point for
#' editing, not a final manuscript. Always review for accuracy.
#'
#' @examples
#' \dontrun{
#' methods <- draft_methods_text(
#'   code = readLines("inst/workflows/my_workflow.R"),
#'   description = "eDNA metabarcoding of tidewater goby habitat"
#' )
#' cat(methods)
#' }
#'
#' @export
draft_methods_text <- function(code,
                               description    = NULL,
                               context        = NULL,
                               audience       = "journal",
                               llm_fn         = call_anthropic_api,
                               max_code_lines = 300L,
                               verbose        = FALSE) {

  # --- Input validation -------------------------------------------------------
  if (!is.character(code) || length(code) == 0L)
    stop("code must be a non-empty character vector (code lines, file path, or single string)")
  if (!is.null(context) && !inherits(context, "report_context"))
    stop("context must be a report_context object from build_report_context()")
  if (!is.null(description) && (!is.character(description) || length(description) != 1L))
    stop("description must be a single character string or NULL")
  audience <- match.arg(audience, c("journal", "technical", "brief"))
  if (!is.function(llm_fn))
    stop("llm_fn must be a function")

  # Context overrides description
  if (!is.null(context) && !is.null(context$study_description))
    description <- context$study_description

  # --- Resolve code input -----------------------------------------------------
  code_lines <- .resolve_code_input(code)

  if (length(code_lines) > max_code_lines) {
    code_lines <- c(
      code_lines[seq_len(max_code_lines)],
      sprintf("# ... [truncated: %d additional lines not shown]",
              length(code_lines) - max_code_lines)
    )
  }

  code_block <- paste(code_lines, collapse = "\n")

  # --- Build prompt -----------------------------------------------------------
  context_block <- if (!is.null(context)) .format_context(context) else NULL
  prompt <- .build_methods_prompt(code_block, description, audience, context_block)

  if (verbose) message("Sending code to LLM for methods drafting...")

  # --- Call LLM ---------------------------------------------------------------
  response <- llm_fn(prompt)

  if (verbose) message("Methods text received.")
  cat(response, "\n")
  invisible(response)
}


# ==============================================================================
# draft_results_text()
# ==============================================================================

#' Draft Results Text from R Objects
#'
#' Summarizes R objects (data frames, model outputs, summaries) using an LLM
#' to produce a results section in scientific prose.
#'
#' @param ... Named R objects to summarize. Names become labels in the prompt
#'   (e.g., \code{blast_hits = blast_hits, consensus = consensus_final}).
#'   Each object is serialized to a text summary suitable for the LLM.
#' @param description Character. Brief study context. Default \code{NULL}.
#'   Ignored when \code{context} is provided.
#' @param context A \code{report_context} object from
#'   \code{\link{build_report_context}}. Provides structured facts the LLM
#'   must use as ground truth. Default \code{NULL}.
#' @param audience Character. Target audience: \code{"journal"} (default),
#'   \code{"technical"}, or \code{"brief"}.
#' @param code Character. Optional R code (file path or lines) that produced
#'   the objects. When provided, the LLM can reference specific analysis
#'   steps. Default \code{NULL}.
#' @param llm_fn Function. LLM provider function. Default
#'   \code{call_anthropic_api}.
#' @param max_rows Integer. Maximum rows to show per data frame in the
#'   prompt. Default \code{20L}.
#' @param verbose Logical. Print progress messages. Default \code{FALSE}.
#'
#' @return A character string containing the drafted results text.
#'   Printed to the console via \code{cat()} and returned invisibly.
#'
#' @details
#' For each named object, the function extracts:
#' \itemize{
#'   \item Data frames: dimensions, column names and types, \code{summary()},
#'     and the first few rows
#'   \item Lists: \code{str()} output (truncated)
#'   \item Numeric vectors: \code{summary()} and length
#'   \item Other objects: \code{print()} output (truncated)
#' }
#'
#' These summaries are sent to the LLM with instructions to write a
#' results section highlighting key findings, sample sizes, and
#' summary statistics.
#'
#' When a \code{context} object is provided, its statistics and facts
#' are included as verified ground truth. The LLM is instructed to use
#' these numbers exactly rather than computing its own from the data
#' summaries.
#'
#' \strong{LLM-derived data caveat.} If the data objects contain values
#' that were generated by an LLM (e.g., habitat classifications, range
#' assessments), the LLM is instructed to note this and include a brief
#' caveat about stochastic output. You can also add an explicit note in
#' \code{context$facts} (e.g., \code{facts = list(llm_role = "habitat
#' classification via Claude")}).
#'
#' \strong{LLM stochasticity.} The output is generated by an LLM and
#' will vary between runs. Always review for accuracy. The output is a
#' starting point for editing, not a final manuscript.
#'
#' @examples
#' \dontrun{
#' results <- draft_results_text(
#'   consensus = consensus_final,
#'   description = "Taxonomic assignments for tidewater goby eDNA samples"
#' )
#' cat(results)
#' }
#'
#' @export
draft_results_text <- function(...,
                               description = NULL,
                               context     = NULL,
                               audience    = "journal",
                               code        = NULL,
                               llm_fn      = call_anthropic_api,
                               max_rows    = 20L,
                               verbose     = FALSE) {

  # --- Capture named objects --------------------------------------------------
  dots <- list(...)
  obj_names <- names(dots)

  if (length(dots) == 0L)
    stop("At least one named R object must be provided")
  if (is.null(obj_names) || any(obj_names == ""))
    stop("All objects passed to ... must be named (e.g., results = my_df)")
  if (all(vapply(dots, is.null, logical(1L))))
    stop("All objects passed via ... are NULL; provide at least one non-NULL object")

  if (!is.null(context) && !inherits(context, "report_context"))
    stop("context must be a report_context object from build_report_context()")
  if (!is.null(description) && (!is.character(description) || length(description) != 1L))
    stop("description must be a single character string or NULL")
  audience <- match.arg(audience, c("journal", "technical", "brief"))
  if (!is.function(llm_fn))
    stop("llm_fn must be a function")

  # Context overrides description
  if (!is.null(context) && !is.null(context$study_description))
    description <- context$study_description

  # --- Serialize objects to text summaries ------------------------------------
  obj_summaries <- vapply(obj_names, function(nm) {
    .summarize_object(dots[[nm]], nm, max_rows)
  }, character(1L))

  data_block <- paste(obj_summaries, collapse = "\n\n")

  # --- Optional code context --------------------------------------------------
  code_block <- NULL
  if (!is.null(code)) {
    code_lines <- .resolve_code_input(code)
    if (length(code_lines) > 200L) {
      code_lines <- c(code_lines[seq_len(200L)],
                      "# ... [truncated]")
    }
    code_block <- paste(code_lines, collapse = "\n")
  }

  # --- Build prompt -----------------------------------------------------------
  context_block <- if (!is.null(context)) .format_context(context) else NULL
  prompt <- .build_results_prompt(data_block, description, audience,
                                  code_block, context_block)

  if (verbose) message("Sending object summaries to LLM for results drafting...")

  # --- Call LLM ---------------------------------------------------------------
  response <- llm_fn(prompt)

  if (verbose) message("Results text received.")
  cat(response, "\n")
  invisible(response)
}


# ==============================================================================
# Internal: Format report_context as text for LLM prompt
# ==============================================================================

#' @noRd
.format_context <- function(ctx) {
  lines <- character()

  if (!is.null(ctx$data_type))
    lines <- c(lines, sprintf("Data type: %s", ctx$data_type))
  if (!is.null(ctx$workflow))
    lines <- c(lines, sprintf("Analysis workflow: %s", ctx$workflow))

  if (!is.null(ctx$packages))
    lines <- c(lines, sprintf("Software: %s", paste(ctx$packages, collapse = ", ")))

  if (!is.null(ctx$parameters) && length(ctx$parameters) > 0L) {
    param_strs <- vapply(names(ctx$parameters), function(k) {
      sprintf("  %s = %s", k, paste(ctx$parameters[[k]], collapse = ", "))
    }, character(1L))
    lines <- c(lines, "Parameters:", param_strs)
  }

  if (!is.null(ctx$statistics) && length(ctx$statistics) > 0L) {
    stat_strs <- vapply(names(ctx$statistics), function(k) {
      sprintf("  %s = %s", k, paste(ctx$statistics[[k]], collapse = ", "))
    }, character(1L))
    lines <- c(lines, "Statistics:", stat_strs)
  }

  if (!is.null(ctx$facts) && length(ctx$facts) > 0L) {
    fact_strs <- vapply(names(ctx$facts), function(k) {
      sprintf("  %s: %s", k, paste(ctx$facts[[k]], collapse = ", "))
    }, character(1L))
    lines <- c(lines, "Additional facts:", fact_strs)
  }

  if (!is.null(ctx$citations) && length(ctx$citations) > 0L) {
    lines <- c(lines, "Citations to include:",
               paste("  -", ctx$citations))
  }

  paste(lines, collapse = "\n")
}


# ==============================================================================
# Internal: Resolve code input to lines
# ==============================================================================

#' @noRd
.resolve_code_input <- function(code) {
  # Single string that looks like a file path
  if (length(code) == 1L && !grepl("\n", code) &&
      file.exists(code) && grepl("\\.[Rr]$", code)) {
    return(tryCatch(
      readLines(code, warn = FALSE),
      error = function(e) {
        stop(sprintf("Cannot read code file '%s': %s", code, conditionMessage(e)))
      }
    ))
  }

  # Single string with newlines -> split

  if (length(code) == 1L && grepl("\n", code)) {
    return(strsplit(code, "\n")[[1L]])
  }

  # Already a character vector of lines
  code
}


# ==============================================================================
# Internal: Build methods prompt
# ==============================================================================

#' @noRd
.build_methods_prompt <- function(code_block, description, audience,
                                  context_block = NULL) {
  audience_instruction <- switch(audience,
    journal = paste(
      "Write in the style of a peer-reviewed journal Methods section.",
      "Use past tense. Be precise about what was done but do not reproduce code.",
      "Include parameter values where they affect the analysis.",
      "Write 2-4 paragraphs."
    ),
    technical = paste(
      "Write a detailed technical methods description.",
      "Use past tense. Include all parameter values and function names.",
      "Organize by analysis stage. Write 3-6 paragraphs."
    ),
    brief = paste(
      "Write a brief methods summary in 1-2 paragraphs.",
      "Use past tense. Mention the main steps and key parameters only."
    )
  )

  context_line <- if (!is.null(description)) {
    sprintf("\n\nSTUDY CONTEXT: %s\n", description)
  } else ""

  context_section <- if (!is.null(context_block)) {
    paste0(
      "\n\nVERIFIED FACTS (use these exactly as stated; ",
      "they override any conflicting information inferred from code or comments):\n",
      context_block, "\n"
    )
  } else ""

  sprintf(
    paste0(
      "You are a scientific writer. Read the following R code from a data ",
      "analysis workflow and draft a Methods section describing what was done.",
      "%s%s",
      "\n\nINSTRUCTIONS:\n",
      "- %s\n",
      "- Describe the analysis conceptually, not the code itself.\n",
      "- Do not include R function names unless the audience is 'technical'.\n",
      "- Note software packages and their roles where appropriate.\n",
      "- Comments in the R code may be treated as factual descriptions of the ",
      "analysis. However, if the VERIFIED FACTS section is present, its ",
      "contents take precedence over code comments.\n",
      "- If the code references specific thresholds, cutoffs, or model ",
      "parameters, mention them.\n",
      "- If citations are provided, incorporate them naturally into the text.\n",
      "- Do NOT report findings, results, or summary statistics (sample sizes, ",
      "resolution rates, counts, proportions). The statistics in VERIFIED FACTS ",
      "are provided for accuracy checking only -- they belong in the Results ",
      "section, not here. Describe only what was done, not what was found.\n",
      "- If the analysis workflow includes steps where data were generated or ",
      "classified by a large language model (LLM), note this and state that LLM ",
      "outputs are stochastic and should be independently verified.\n",
      "- Output plain text (no markdown headers or formatting).\n",
      "\nR CODE:\n```r\n%s\n```"
    ),
    context_line,
    context_section,
    audience_instruction,
    code_block
  )
}


# ==============================================================================
# Internal: Build results prompt
# ==============================================================================

#' @noRd
.build_results_prompt <- function(data_block, description, audience,
                                  code_block = NULL, context_block = NULL) {
  audience_instruction <- switch(audience,
    journal = paste(
      "Write in the style of a peer-reviewed journal Results section.",
      "Use past tense. Report key numbers (sample sizes, percentages,",
      "summary statistics) with appropriate precision.",
      "Write 2-4 paragraphs."
    ),
    technical = paste(
      "Write a detailed technical results description.",
      "Use past tense. Report all summary statistics, counts, and",
      "distributions. Organize by analysis output. Write 3-6 paragraphs."
    ),
    brief = paste(
      "Write a brief results summary in 1-2 paragraphs.",
      "Use past tense. Highlight the most important findings only."
    )
  )

  context_line <- if (!is.null(description)) {
    sprintf("\n\nSTUDY CONTEXT: %s\n", description)
  } else ""

  context_section <- if (!is.null(context_block)) {
    paste0(
      "\n\nVERIFIED FACTS (use these numbers exactly as stated; ",
      "they take precedence over any values computed from the data summaries):\n",
      context_block, "\n"
    )
  } else ""

  code_section <- if (!is.null(code_block)) {
    sprintf(
      "\n\nANALYSIS CODE (for reference -- describes how these results were produced):\n```r\n%s\n```\n",
      code_block
    )
  } else ""

  sprintf(
    paste0(
      "You are a scientific writer. Read the following summaries of R objects ",
      "from a data analysis and draft a Results section describing the findings.",
      "%s%s",
      "\n\nINSTRUCTIONS:\n",
      "- %s\n",
      "- Report what the data show, not how the analysis was done.\n",
      "- Use specific numbers from the summaries provided.\n",
      "- When VERIFIED FACTS are present, use those numbers exactly.\n",
      "- If citations are provided, incorporate them naturally.\n",
      "- Do not speculate beyond what the data show.\n",
      "- Do not describe methods; focus on findings.\n",
      "- If any values in the data were generated or classified by a large ",
      "language model (LLM), note this and include a brief caveat that LLM ",
      "outputs are stochastic and may vary between runs.\n",
      "- Output plain text (no markdown headers or formatting).\n",
      "%s",
      "\nDATA SUMMARIES:\n%s"
    ),
    context_line,
    context_section,
    audience_instruction,
    code_section,
    data_block
  )
}


# ==============================================================================
# Internal: Summarize an R object for the prompt
# ==============================================================================

#' @noRd
.summarize_object <- function(obj, name, max_rows = 20L) {
  header <- sprintf("=== %s ===", name)

  summary_text <- if (is.data.frame(obj)) {
    .summarize_data_frame(obj, name, max_rows)
  } else if (is.matrix(obj)) {
    .summarize_data_frame(as.data.frame(obj), name, max_rows)
  } else if (is.list(obj) && !is.data.frame(obj)) {
    .summarize_list(obj, name)
  } else if (is.numeric(obj) || is.integer(obj)) {
    .summarize_numeric(obj, name)
  } else if (is.character(obj)) {
    .summarize_character(obj, name)
  } else {
    .summarize_generic(obj, name)
  }

  paste(header, summary_text, sep = "\n")
}


#' @noRd
.summarize_data_frame <- function(df, name, max_rows) {
  lines <- character()

  # Dimensions
  lines <- c(lines, sprintf("Data frame: %d rows x %d columns", nrow(df), ncol(df)))

  # Column types
  col_types <- vapply(df, function(x) class(x)[1L], character(1L))
  lines <- c(lines, sprintf("Columns: %s",
    paste(sprintf("%s (%s)", names(col_types), col_types), collapse = ", ")))

  # Summary statistics for numeric columns
  num_cols <- names(df)[vapply(df, is.numeric, logical(1L))]
  if (length(num_cols) > 0L) {
    summ <- utils::capture.output(summary(df[, num_cols, drop = FALSE]))
    lines <- c(lines, "", "Numeric summary:", summ)
  }

  # Character/factor column value counts
  char_cols <- names(df)[vapply(df, function(x) is.character(x) || is.factor(x), logical(1L))]
  for (cc in char_cols[seq_len(min(length(char_cols), 5L))]) {
    vals <- df[[cc]]
    n_unique <- length(unique(stats::na.omit(vals)))
    n_na <- sum(is.na(vals))
    top_vals <- utils::head(sort(table(vals), decreasing = TRUE), 5L)
    lines <- c(lines, sprintf("\n%s: %d unique values, %d NA", cc, n_unique, n_na))
    if (length(top_vals) > 0L) {
      lines <- c(lines, sprintf("  Top values: %s",
        paste(sprintf("%s (%d)", names(top_vals), as.integer(top_vals)), collapse = ", ")))
    }
  }

  # First few rows
  show_n <- min(nrow(df), max_rows)
  if (show_n > 0L) {
    preview <- utils::capture.output(print(utils::head(df, show_n), row.names = FALSE))
    lines <- c(lines, sprintf("\nFirst %d rows:", show_n), preview)
  }

  paste(lines, collapse = "\n")
}


#' @noRd
.summarize_list <- function(obj, name) {
  str_out <- utils::capture.output(utils::str(obj, max.level = 2L, list.len = 20L))
  if (length(str_out) > 40L) {
    str_out <- c(str_out[seq_len(40L)], "... [truncated]")
  }
  paste(c(sprintf("List with %d elements", length(obj)), str_out), collapse = "\n")
}


#' @noRd
.summarize_numeric <- function(obj, name) {
  lines <- c(
    sprintf("Numeric vector: length %d", length(obj)),
    utils::capture.output(summary(obj))
  )
  if (length(obj) <= 20L) {
    lines <- c(lines, sprintf("Values: %s", paste(obj, collapse = ", ")))
  }
  paste(lines, collapse = "\n")
}


#' @noRd
.summarize_character <- function(obj, name) {
  n_unique <- length(unique(obj))
  lines <- c(
    sprintf("Character vector: length %d, %d unique values", length(obj), n_unique)
  )
  if (n_unique <= 20L) {
    top_vals <- utils::head(sort(table(obj), decreasing = TRUE), 20L)
    lines <- c(lines, sprintf("Values: %s",
      paste(sprintf("%s (%d)", names(top_vals), as.integer(top_vals)), collapse = ", ")))
  } else {
    top_vals <- utils::head(sort(table(obj), decreasing = TRUE), 10L)
    lines <- c(lines, sprintf("Top 10 values: %s",
      paste(sprintf("%s (%d)", names(top_vals), as.integer(top_vals)), collapse = ", ")))
  }
  paste(lines, collapse = "\n")
}


#' @noRd
.summarize_generic <- function(obj, name) {
  lines <- utils::capture.output(print(obj))
  if (length(lines) > 30L) {
    lines <- c(lines[seq_len(30L)], "... [truncated]")
  }
  paste(c(sprintf("Object of class: %s", paste(class(obj), collapse = ", ")), lines),
        collapse = "\n")
}
