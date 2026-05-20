utils::globalVariables(c("observation_id", "score", "taxon_name", "taxon_name_rank",
                          "prior_mean", "prior_alpha", "prior_beta",
                          "range_status", "habitat_fit", "information_quality",
                          "hypothesis_type", "likelihood_point_est", "likelihood_mean",
                          "likelihood_sd"))

# assign_taxa_llm.R
# TaxaAssign package
#
# Approximate the full TaxaLikely -> TaxaExpect -> TaxaAssign pipeline in one LLM call.
# Score-based likelihood proxies replace TaxaLikely model; LLM-assigned weights replace
# TaxaExpect occurrence-based priors. Posteriors computed via compute_posterior().
#
# Key design: geographic plausibility is taxon-level, not observation-level.
# The LLM receives ONE flat list of unique taxa per group and returns ONE array
# of prior weights. R code handles all observation-level bookkeeping.
#
# Exported functions:
#   assign_taxa_llm()         Full LLM-shortcut pipeline: match_df + context -> posteriors
#
# Internal helpers:
#   .score_to_likelihood()    Exponential-weight scores -> normalized likelihood proxy
#   .build_group_map()        Map observation_ids to group labels via context_group columns
#   .collect_unique_taxa()    Unique taxon data frame from a set of lik_dfs
#   .get_group_context()      Context list for a representative observation in a group
#   .build_taxa_prompt()      Flat prompt: taxon list + context -> LLM input string
#   .parse_taxa_response()    Parse flat JSON array -> prior_df (one row per taxon)


# ==============================================================================
# Main exported function
# ==============================================================================

#' Assign Taxa Using an LLM-Approximated Bayesian Pipeline
#'
#' A fast approximation of the full TaxaLikely -> TaxaExpect -> TaxaAssign pipeline.
#' Replaces the Bayesian likelihood model with exponentially-weighted match scores,
#' and replaces occurrence-based priors with LLM-estimated prior weights. Posteriors
#' are computed by `compute_posterior()` as normal.
#'
#' ## Key design
#' Geographic plausibility is a taxon-level property, not an observation-level one.
#' The LLM receives a single flat list of unique taxa per group and returns a
#' single JSON array of prior weights. All observation-level bookkeeping (joining,
#' normalization, posterior computation) is handled in R.
#'
#' ## Grouping
#' When `context_group` is supplied, observations are divided into groups defined by
#' unique combinations of the named `context` columns (e.g., `"ecoregion"` or
#' `c("ecoregion", "habitat")`). Each group receives a separate LLM call with
#' the taxon list and context specific to that group. This ensures geographically
#' or ecologically distinct subsets of observations are assessed independently.
#'
#' ## Likelihood proxy
#' Within each observation, candidate scores are exponentially weighted and
#' normalized so named candidates share `(1 - unknown_lik_weight)` of the total:
#' ```
#' lik_i = (1 - unknown_lik_weight) * exp(sharpness * score_i) /
#'         sum(exp(sharpness * score_j))
#' ```
#'
#' ## Unreferenced taxa
#' Species absent from the reference database (from
#' `TaxaLikely::audit_reference_coverage()$unreferenced`) that share a genus with any
#' scored candidate are inserted as additional hypotheses. Their likelihood equals
#' the median of their referenced congeners so unreferenced taxa start on equal
#' footing. They appear in the prompt labelled `[no reference sequence]`.
#'
#' @param match_df Data frame. Canonical match object from TaxaMatch (or equivalent).
#'   Required columns: `observation_id`, `score`, `taxon_name`, `taxon_name_rank`.
#'   Optional but recommended: `testid` (marker type).
#' @param context Optional data frame with location/habitat context. Either a
#'   single row (broadcast to all observations) or one row per `observation_id`. Recognised
#'   columns: `observation_id`, `ecoregion`, `lat`, `lon`, `date`, `main_habitat`.
#'   In the full pipeline, populate `main_habitat` from the `main_habitat` column
#'   produced by TaxaHabitat and passed through TaxaExpect.
#' @param context_group Optional character vector of column names in `context` to
#'   group observations by (e.g., `"ecoregion"` or `c("ecoregion", "habitat")`).
#'   Each unique combination of values becomes a separate LLM call with its own
#'   taxon list. Requires `context` to have an `observation_id` column.
#'   `NULL` (default) puts all observations in one group.
#' @param llm_fn Function or NULL. Provider function following the TaxaTools
#'   `llm_fn` pattern: accepts a single character string prompt and returns a
#'   single character string response. Default NULL resolves to
#'   `TaxaTools::call_anthropic_api` (requires TaxaTools installed).
#' @param score_threshold Numeric. Minimum score to include a candidate (0-100).
#'   Default 80.
#' @param top_n Integer. Maximum candidates per observation included in the unique
#'   taxon list sent to the LLM. Default 10.
#' @param rank_system Optional character vector of taxonomy column names in
#'   `match_df`, coarse-to-fine (e.g. `c("family", "genus", "species")`).
#'   When `NULL` (default), standard taxonomy columns present in `match_df`
#'   are detected automatically from `kingdom, phylum, class, order, family,
#'   genus, species`. Detected columns are carried through to the posterior
#'   dataframe, enabling `posterior_consensus()` to resolve LCA above genus level.
#' @param score_sharpness Numeric >= 0. Controls how strongly match score
#'   differences translate to likelihood differences via
#'   `exp(score_sharpness * score)`. At 0.1, a 10-point score difference
#'   produces a ~2.7x likelihood difference. Higher values (e.g., 0.5) make
#'   top-scoring candidates dominate sharply; lower values (e.g., 0.01) make
#'   likelihoods nearly uniform regardless of score. Default 0.1.
#'   Set to 0 for uniform likelihood across all candidates (prior-driven).
#'   In the LLM workflow, likelihoods are intentionally a weak function of
#'   scores (sharpness = 0.1) because the LLM prior provides the main
#'   discriminating information. In the Bayesian workflow, TaxaLikely provides
#'   properly calibrated likelihoods and this parameter is not used.
#' @param unknown_lik_weight Numeric in (0, 1). Baseline likelihood for the
#'   catch-all "unknown species" hypothesis (species not in any candidate
#'   list). At 0.05, the unknown hypothesis competes at 5% likelihood against
#'   named candidates. Higher values make "unknown" more competitive
#'   (conservative); lower values favor named candidates. Also used as the
#'   unknown hypothesis prior weight. Default 0.05.
#' @param unreferenced_taxa Optional character vector of species names absent from the
#'   reference database (e.g., `TaxaLikely::audit_barcode_coverage()$unreferenced`).
#'   Only congeners of scored candidates are inserted per observation. `NULL` (default)
#'   disables unreferenced species insertion.
#' @param known_present Optional character vector of species confirmed present at
#'   the site by independent survey (visual, net, prior eDNA, etc.). Passed to
#'   the LLM as ecological context to sharpen habitat assessment and co-occurrence
#'   reasoning. Not used in the mathematical update step.
#' @param known_absent Optional species list of taxa surveyed for but not detected
#'   at the site, supplied as either:
#'   \itemize{
#'     \item A character vector — all species assigned `absent_detection_prob`.
#'     \item A data frame with columns `taxon_name` (character) and optionally
#'           `detection_prob` (numeric 0–1). Missing `detection_prob` values
#'           fall back to `absent_detection_prob`.
#'   }
#'   The LLM sees the list as context. In addition, each absent species' prior
#'   is multiplied by `(1 - detection_prob)` after the LLM call, then the full
#'   prior vector is renormalized. This is a principled Bayesian update:
#'   `P(present | not detected) ∝ P(not detected | present) × P(present) =
#'   (1 - p_det) × prior_LLM`. Only applies to species that appear as
#'   hypotheses (scored candidates or inserted unreferenced taxa); species not in the
#'   candidate set already have near-zero prior by construction.
#' @param absent_detection_prob Numeric in (0, 1). Probability of detecting a
#'   species known to be absent from the study area. Applied as
#'   `prior * (1 - absent_detection_prob)` suppression. At 0.80, a
#'   known-absent species has its prior reduced by 80%. Represents the field
#'   survey's power to have detected the species if it were present. Used as
#'   the default when `known_absent` is a character vector or when a row in a
#'   `known_absent` data frame is missing `detection_prob`. Default 0.80.
#' @param taxa_per_call Integer >= 1. Maximum number of unique taxa sent to the
#'   LLM in a single call. When the unique taxon list for a group exceeds this
#'   limit it is split into sequential batches; results are combined before
#'   joining to observations. Default 30. Reduce if the LLM truncates responses;
#'   increase if taxa are few and you prefer fewer API calls.
#' @param pause_seconds Numeric. Seconds to pause between LLM calls (both
#'   between groups and between taxon batches within a group). Default 1.
#' @param prior_phi Named numeric vector mapping `information_quality` levels
#'   to Beta distribution concentration parameter (phi = alpha + beta).
#'   Phi controls how tightly the prior is centered on the LLM's point
#'   estimate: phi = 50 ("high") is equivalent to 50 observations of data,
#'   giving a tight prior; phi = 10 ("moderate") allows substantial
#'   uncertainty; phi = 3 ("low") produces a diffuse prior that the
#'   likelihood can easily override.
#'   `information_quality` is the LLM's self-assessment of how much published
#'   data exists about each taxon at the study location -- it reflects data
#'   availability, not confidence in the taxonomic assignment itself.
#'   Default `c(high = 50, moderate = 10, low = 3)`.
#'   A single unnamed scalar applies uniformly to all taxa (overrides LLM-returned
#'   quality levels). Set to `NULL` to disable Beta prior uncertainty entirely
#'   (priors treated as fixed, no Monte Carlo on prior side). Adjust based on
#'   how much you trust the LLM's ecological knowledge for your study system:
#'   decrease phi values for poorly documented regions or understudied taxa.
#' @param prior_weight_guide Named list of prior weight ranges guiding LLM
#'   assignments. Each element is a length-2 numeric vector `c(min, max)`.
#'   The LLM uses these ranges when assigning prior probabilities based on
#'   range status and habitat fit. Names indicate the ecological scenario:
#'   `native_expected`, `native_occasional`, `native_unlikely`,
#'   `nearby_expected`, `nearby_occasional_unlikely`, `not_documented`,
#'   `taxonomically_impossible`. Default ranges are derived from expert
#'   ecological judgment (see package documentation). Modifying these ranges
#'   directly affects how strongly geographic and habitat information
#'   influence posterior probabilities.
#' @param n_sims Integer. Monte Carlo simulations for `compute_posterior()`.
#'   Default 1000. Set to 0 to skip simulation and return point estimates only.
#' @param verbose Logical. If `TRUE`, prints the prompt and raw LLM response for
#'   each group call. Default `FALSE`.
#'
#' @return A data frame (the output of `compute_posterior()`) with columns:
#'   `observation_id`, `taxon_name`, `taxon_name_rank`, `hypothesis_type`, `range_status`,
#'   `habitat_fit`, `information_quality`, `likelihood_point_est`, `likelihood_mean`,
#'   `likelihood_sd`, `prior_mean`, `prior_alpha`, `prior_beta`,
#'   `posterior_point_est`, `posterior_mean`, `posterior_sd`, `confidence_score`.
#'   `prior_alpha`/`prior_beta` are present when `prior_phi` is non-NULL;
#'   `compute_posterior()` uses them for Beta-distributed prior sampling.
#'   `hypothesis_type` values: `"specific_candidate"` (has reference sequence),
#'   `"unreferenced_species"` (congener without reference sequence),
#'   `"unreferenced_genus"` (family-level unreferenced taxon or uncharacterised diversity).
#'   Taxonomy columns from `match_df` (e.g. `family`, `genus`, `species`) are
#'   preserved; unreferenced and unknown rows have `NA` in these columns.
#'   `habitat_fit` values: `"expected"` (primary habitat match),
#'   `"occasional"` (uses this habitat type peripherally), `"unlikely"`
#'   (native to region but habitat unsuitable), or `NA` when not assessed.
#'   Sorted by `observation_id`, then descending `posterior_mean`.
#'
#' @seealso [compute_posterior()] for the Bayesian update step.
#'
#' @importFrom dplyr filter arrange desc group_by ungroup left_join bind_rows
#'   slice_max n_distinct summarise
#' @importFrom rlang .data
#' @importFrom stats median setNames
#' @importFrom cli cli_inform cli_warn cli_abort cli_progress_bar
#'   cli_progress_update cli_progress_done
#'
#' @export
#'
#' @examples
#' \dontrun{
#' match_df <- readRDS(system.file("match_obj.rds", package = "TaxaMatch"))
#'
#' # Minimal call -- no context
#' result <- assign_taxa_llm(match_df)
#'
#' # With shared context
#' ctx <- data.frame(ecoregion = "California Coast", habitat = "estuarine")
#' result <- assign_taxa_llm(match_df, context = ctx,
#'                            llm_fn = TaxaTools::call_anthropic_api)
#'
#' # With per-observation context grouped by ecoregion (one LLM call per region)
#' ctx <- data.frame(observation_id = match_df$observation_id,
#'                   ecoregion = ...,
#'                   stringsAsFactors = FALSE)
#' result <- assign_taxa_llm(match_df, context = ctx,
#'                            context_group = "ecoregion")
#' }
assign_taxa_llm <- function(match_df,
                             context               = NULL,
                             context_group         = NULL,
                             llm_fn                = NULL,
                             score_threshold       = 80,
                             top_n                 = 10L,
                             rank_system           = NULL,
                             score_sharpness       = 0.1,
                             unknown_lik_weight    = 0.05,
                             unreferenced_taxa            = NULL,
                             known_present         = NULL,
                             known_absent          = NULL,
                             absent_detection_prob = 0.80,
                             taxa_per_call         = 30L,
                             pause_seconds         = 1,
                             prior_phi             = c(high = 50, moderate = 10, low = 3),
                             prior_weight_guide    = list(
                               native_expected           = c(0.5, 1.0),
                               native_occasional         = c(0.03, 0.15),
                               native_unlikely           = c(0.003, 0.03),
                               nearby_expected           = c(0.05, 0.3),
                               nearby_occasional_unlikely = c(0.002, 0.05),
                               not_documented            = c(0.001, 0.02),
                               taxonomically_impossible  = c(0.0001, 0.002)
                             ),
                             n_sims                = 1000L,
                             verbose               = FALSE) {

  # --- Resolve llm_fn default --------------------------------------------------
  llm_fn <- .resolve_llm_fn(llm_fn, "assign_taxa_llm")

  # --- Input validation -------------------------------------------------------
  required_cols <- c("observation_id", "score", "taxon_name", "taxon_name_rank")
  missing_cols  <- setdiff(required_cols, names(match_df))
  if (length(missing_cols) > 0)
    cli::cli_abort("match_df is missing required column(s): {.field {missing_cols}}")
  if (!is.numeric(score_threshold) || score_threshold < 0 || score_threshold > 100)
    cli::cli_abort("{.arg score_threshold} must be a number between 0 and 100.")
  if (!is.numeric(score_sharpness) || score_sharpness < 0)
    cli::cli_abort("{.arg score_sharpness} must be a non-negative number.")
  if (!is.numeric(unknown_lik_weight) || unknown_lik_weight <= 0 || unknown_lik_weight >= 1)
    cli::cli_abort("{.arg unknown_lik_weight} must be strictly between 0 and 1.")
  if (!is.function(llm_fn))
    cli::cli_abort("{.arg llm_fn} must be a function.")
  if (!is.null(context_group) && !is.character(context_group))
    cli::cli_abort("{.arg context_group} must be a character vector or NULL.")
  if (!is.numeric(taxa_per_call) || taxa_per_call < 1)
    cli::cli_abort("{.arg taxa_per_call} must be a positive number.")
  if (!is.null(known_present) && !is.character(known_present))
    cli::cli_abort("{.arg known_present} must be a character vector or NULL.")
  if (!is.numeric(absent_detection_prob) || length(absent_detection_prob) != 1L ||
      absent_detection_prob <= 0 || absent_detection_prob >= 1)
    cli::cli_abort("{.arg absent_detection_prob} must be a single number strictly between 0 and 1.")

  # Validate prior_weight_guide
  if (!is.list(prior_weight_guide) || length(prior_weight_guide) == 0L)
    cli::cli_abort("{.arg prior_weight_guide} must be a non-empty named list.")
  expected_pwg <- c("native_expected", "native_occasional", "native_unlikely",
                     "nearby_expected", "nearby_occasional_unlikely",
                     "not_documented", "taxonomically_impossible")
  missing_pwg <- setdiff(expected_pwg, names(prior_weight_guide))
  if (length(missing_pwg) > 0)
    cli::cli_abort("{.arg prior_weight_guide} missing required element(s): {.field {missing_pwg}}")
  for (nm in expected_pwg) {
    v <- prior_weight_guide[[nm]]
    if (!is.numeric(v) || length(v) != 2L || any(is.na(v)) || v[1] > v[2])
      cli::cli_abort("{.arg prior_weight_guide${nm}} must be a length-2 numeric vector c(min, max) with min <= max.")
  }

  # Validate prior_phi
  use_beta_prior <- !is.null(prior_phi)
  if (use_beta_prior) {
    if (!is.numeric(prior_phi) || any(prior_phi <= 0))
      cli::cli_abort("{.arg prior_phi} must be a positive numeric vector (or NULL to disable).")
    if (length(prior_phi) == 1L && is.null(names(prior_phi))) {
      # Scalar: apply uniformly (override LLM quality levels)
      phi_scalar <- prior_phi
      prior_phi  <- NULL
    } else {
      phi_scalar <- NULL
      valid_levels <- c("high", "moderate", "low")
      if (!all(names(prior_phi) %in% valid_levels))
        cli::cli_abort("{.arg prior_phi} names must be a subset of {.val {valid_levels}}.")
      # Fill any missing levels with the median of supplied values
      for (lev in setdiff(valid_levels, names(prior_phi))) {
        prior_phi[[lev]] <- stats::median(prior_phi)
        cli::cli_inform("Filling missing {.field prior_phi} level {.val {lev}} with median = {prior_phi[[lev]]}.")
      }
    }
  } else {
    phi_scalar <- NULL
  }

  # Normalise known_absent -> data frame with taxon_name + detection_prob
  if (is.null(known_absent)) {
    known_absent_df <- data.frame(taxon_name     = character(0),
                                  detection_prob = numeric(0),
                                  stringsAsFactors = FALSE)
  } else if (is.character(known_absent)) {
    known_absent_df <- data.frame(taxon_name     = known_absent,
                                  detection_prob = absent_detection_prob,
                                  stringsAsFactors = FALSE)
  } else if (is.data.frame(known_absent)) {
    if (!"taxon_name" %in% names(known_absent))
      cli::cli_abort("{.arg known_absent} data frame must have a {.field taxon_name} column.")
    known_absent_df <- known_absent
    if (!"detection_prob" %in% names(known_absent_df))
      known_absent_df$detection_prob <- absent_detection_prob
    dp <- suppressWarnings(as.numeric(known_absent_df$detection_prob))
    if (any(is.na(dp)) || any(dp <= 0) || any(dp >= 1))
      cli::cli_abort(
        "{.field detection_prob} in {.arg known_absent} must be numeric values strictly in (0, 1)."
      )
    known_absent_df$detection_prob <- dp
  } else {
    cli::cli_abort("{.arg known_absent} must be a character vector, data frame, or NULL.")
  }

  # --- Filter candidates and compute likelihoods ------------------------------
  candidates <- match_df |>
    dplyr::filter(.data$score >= score_threshold) |>
    dplyr::arrange(.data$observation_id, dplyr::desc(.data$score)) |>
    dplyr::group_by(.data$observation_id) |>
    dplyr::slice_max(order_by = .data$score, n = top_n, with_ties = FALSE) |>
    dplyr::ungroup()

  n_dropped <- dplyr::n_distinct(match_df$observation_id) -
    dplyr::n_distinct(candidates$observation_id)
  if (n_dropped > 0)
    cli::cli_warn("{n_dropped} observation_id(s) had no candidates above score_threshold = \\
                  {score_threshold} and will be absent from results.")
  if (nrow(candidates) == 0)
    cli::cli_abort("No candidates remain after applying score_threshold = {score_threshold}.")

  unref_vec        <- if (is.null(unreferenced_taxa)) character(0) else as.character(unreferenced_taxa)
  unreferenced_family_map <- if (is.null(unreferenced_taxa)) NULL else attr(unreferenced_taxa, "unreferenced_family")
  observation_ids       <- unique(candidates$observation_id)

  # Detect taxonomy columns to carry through to the posterior dataframe
  tax_cols <- intersect(
    if (is.null(rank_system)) TaxaTools::standard_ranks else rank_system,
    names(candidates)
  )

  lik_list <- stats::setNames(
    lapply(observation_ids, function(sid) {
      .score_to_likelihood(candidates[candidates$observation_id == sid, ],
                           score_sharpness, unknown_lik_weight, unref_vec,
                           unreferenced_family_map, tax_cols)
    }),
    observation_ids
  )

  # --- Build group map --------------------------------------------------------
  group_map     <- .build_group_map(context, observation_ids, context_group)
  unique_groups <- unique(group_map$group_label)
  n_groups      <- length(unique_groups)
  n_total       <- length(observation_ids)

  # Total API calls = sum of taxon batches across all groups
  n_calls_total <- sum(vapply(unique_groups, function(grp) {
    grp_sids <- group_map$observation_id[group_map$group_label == grp]
    n_taxa   <- nrow(.collect_unique_taxa(lik_list[grp_sids]))
    ceiling(n_taxa / taxa_per_call)
  }, numeric(1)))

  cli::cli_inform(
    "Assigning LLM priors: {n_total} observation(s), {n_groups} group(s), \\
    {n_calls_total} API call(s) ({taxa_per_call} taxa/call max)."
  )

  # --- LLM calls: one or more per group (batched by taxa_per_call) ------------
  prior_tables <- vector("list", n_groups)
  names(prior_tables) <- unique_groups

  pb <- cli::cli_progress_bar(
    total  = n_calls_total,
    format = "  {cli::pb_bar} {cli::pb_current}/{cli::pb_total} calls"
  )

  call_idx <- 0L

  for (g_idx in seq_along(unique_groups)) {
    grp      <- unique_groups[[g_idx]]
    grp_sids <- group_map$observation_id[group_map$group_label == grp]
    taxa_df  <- .collect_unique_taxa(lik_list[grp_sids])
    grp_ctx  <- .get_group_context(context, grp_sids[[1]])

    # Split taxon list into batches
    n_taxa     <- nrow(taxa_df)
    tpc        <- min(taxa_per_call, n_taxa)
    batch_idx  <- split(seq_len(n_taxa), ceiling(seq_len(n_taxa) / tpc))
    batch_results <- vector("list", length(batch_idx))

    for (b in seq_along(batch_idx)) {
      call_idx     <- call_idx + 1L
      taxa_batch   <- taxa_df[batch_idx[[b]], , drop = FALSE]
      batch_label  <- if (length(batch_idx) > 1)
        paste0(grp, " [batch ", b, "/", length(batch_idx), "]")
      else grp
      prompt <- .build_taxa_prompt(taxa_batch, grp_ctx,
                                   known_present, known_absent_df,
                                   prior_weight_guide)

      if (verbose) {
        cli::cli_inform(
          "--- Call {call_idx}/{n_calls_total}: {batch_label} ({nrow(taxa_batch)} taxa) ---"
        )
        cat(prompt, "\n")
      }

      raw <- tryCatch(
        llm_fn(prompt),
        error = function(e) {
          cli::cli_warn(
            "LLM call failed for {.val {batch_label}}: {conditionMessage(e)}. \\
            Using uniform priors for {nrow(taxa_batch)} taxa."
          )
          NULL
        }
      )

      if (verbose && !is.null(raw)) {
        cli::cli_inform("--- Response ---")
        cat(raw, "\n")
      }

      batch_results[[b]] <- .parse_taxa_response(raw, taxa_batch, batch_label)

      cli::cli_progress_update(id = pb)
      if (call_idx < n_calls_total) Sys.sleep(pause_seconds)
    }

    # Combine taxon batches for this group
    prior_tables[[grp]] <- dplyr::bind_rows(batch_results)
  }

  cli::cli_progress_done(id = pb)

  # --- Merge likelihoods + priors for each observation -------------------------
  merged_list <- vector("list", n_total)
  names(merged_list) <- observation_ids

  for (sid in observation_ids) {
    grp      <- group_map$group_label[group_map$observation_id == sid]
    lik_df   <- lik_list[[sid]]
    prior_df <- prior_tables[[grp]]

    merged <- dplyr::left_join(lik_df, prior_df, by = "taxon_name")

    # unknown_species prior: fixed at unknown_lik_weight (not LLM-assigned)
    unk_idx <- merged$taxon_name == "unknown_species"
    merged$prior_mean[unk_idx]            <- 0   # placeholder; set after rescaling
    merged$range_status[unk_idx]          <- "unknown"
    merged$habitat_fit[unk_idx]           <- NA_character_
    merged$information_quality[unk_idx]   <- NA_character_

    # Fill NA priors for taxa the LLM omitted:
    # - unreferenced taxa: median prior of their referenced congeners in this response
    # - other taxa: global minimum non-NA prior
    if (any(is.na(merged$prior_mean))) {
      non_na_priors <- merged$prior_mean[!is.na(merged$prior_mean)]
      global_min <- if (length(non_na_priors) > 0L) min(non_na_priors) else 0.01
      if (!is.finite(global_min)) global_min <- 0.01
      for (i in which(is.na(merged$prior_mean))) {
        if (merged$hypothesis_type[[i]] == "unreferenced_species") {
          g_genus   <- sub(" .*", "", merged$taxon_name[[i]])
          congeners <- merged[!is.na(merged$prior_mean) &
                                merged$hypothesis_type == "specific_candidate" &
                                sub(" .*", "", merged$taxon_name) == g_genus, ]
          merged$prior_mean[[i]] <- if (nrow(congeners) > 0)
            stats::median(congeners$prior_mean) else global_min
        } else {
          merged$prior_mean[[i]] <- global_min
        }
        # Omitted taxa get "low" information_quality (LLM couldn't assess them)
        if (is.na(merged$information_quality[[i]]))
          merged$information_quality[[i]] <- "low"
        if (is.na(merged$prior_source[[i]]))
          merged$prior_source[[i]] <- "na_fill_fallback"
      }
    }

    # Mathematical absence suppression: P(present | not detected) ∝ (1 - p_det) × prior
    # Applied after NA-fill so unreferenced taxon fallback priors are also suppressed where appropriate.
    # Skips unknown_species row (prior is set as a fixed weight, not LLM-assigned).
    if (nrow(known_absent_df) > 0) {
      for (ka_i in seq_len(nrow(known_absent_df))) {
        sp  <- known_absent_df$taxon_name[[ka_i]]
        pd  <- known_absent_df$detection_prob[[ka_i]]
        idx <- !unk_idx & merged$taxon_name == sp
        if (any(idx))
          merged$prior_mean[idx] <- merged$prior_mean[idx] * (1 - pd)
      }
    }

    # Rescale named taxa priors to (1 - unknown_lik_weight); set unknown_species
    named_sum <- sum(merged$prior_mean[!unk_idx], na.rm = TRUE)
    if (named_sum > 0) {
      merged$prior_mean[!unk_idx] <-
        merged$prior_mean[!unk_idx] / named_sum * (1 - unknown_lik_weight)
    }
    merged$prior_mean[unk_idx] <- unknown_lik_weight

    # --- Compute Beta prior parameters (alpha, beta) from phi ---
    if (use_beta_prior) {
      phi_vec <- if (!is.null(phi_scalar)) {
        rep(phi_scalar, nrow(merged))
      } else {
        # Map information_quality -> phi; NA -> "low" (most diffuse)
        iq <- merged$information_quality
        iq[is.na(iq)] <- "low"
        unname(prior_phi[iq])
      }
      merged$prior_alpha <- merged$prior_mean * phi_vec
      merged$prior_beta  <- (1 - merged$prior_mean) * phi_vec
    }

    merged_list[[sid]] <- merged
  }

  # --- Compute posteriors -----------------------------------------------------
  out <- compute_posterior(dplyr::bind_rows(merged_list), n_sims = n_sims)

  attr(out, "report_params") <- list(
    score_sharpness       = score_sharpness,
    unknown_lik_weight    = unknown_lik_weight,
    prior_phi             = prior_phi,
    score_threshold       = score_threshold,
    top_n                 = top_n,
    n_sims                = n_sims,
    absent_detection_prob = absent_detection_prob,
    prior_weight_guide    = prior_weight_guide
  )
  out
}


# ==============================================================================
# Internal helpers
# ==============================================================================

#' Exponential-weight scores to likelihood proxy, with optional unreferenced species insertion
#' @noRd
.score_to_likelihood <- function(chunk, sharpness, unknown_lik_weight,
                                  unreferenced_taxa = character(0),
                                  unreferenced_family_map = NULL,
                                  tax_cols = character(0)) {
  sid <- chunk$observation_id[[1]]

  # Build taxonomy lookup before aggregation (one row per taxon_name)
  present_tax_cols <- intersect(tax_cols, names(chunk))
  if (length(present_tax_cols) > 0) {
    tax_lookup <- chunk[!duplicated(chunk$taxon_name),
                        c("taxon_name", present_tax_cols), drop = FALSE]
    rownames(tax_lookup) <- NULL
  }

  agg <- chunk |>
    dplyr::group_by(.data$taxon_name, .data$taxon_name_rank) |>
    dplyr::summarise(score = stats::median(.data$score), .groups = "drop")

  exp_scores <- exp(sharpness * agg$score)
  ref_genera <- sub(" .*", "", agg$taxon_name)

  # Unreferenced taxa: congeners not already in candidates
  if (length(unreferenced_taxa) > 0) {
    unref_genera   <- sub(" .*", "", unreferenced_taxa)
    unref_eligible <- unreferenced_taxa[unref_genera %in% ref_genera &
                                   !unreferenced_taxa %in% agg$taxon_name]
  } else {
    unref_eligible <- character(0)
  }

  if (length(unref_eligible) > 0) {
    unref_exp <- vapply(unref_eligible, function(g) {
      g_genus      <- sub(" .*", "", g)
      congener_exp <- exp_scores[ref_genera == g_genus]
      if (length(congener_exp) > 0) stats::median(congener_exp) else stats::median(exp_scores)
    }, numeric(1))
  } else {
    unref_exp <- numeric(0)
  }

  # Family-level unreferenced taxa: genera NOT in candidates but family IS represented
  # Build genus -> family lookup from the chunk's taxonomy columns
  if (!is.null(unreferenced_family_map) && length(unreferenced_family_map) > 0L &&
      "family" %in% names(chunk) && "genus" %in% names(chunk)) {
    gf_df <- chunk[!is.na(chunk$genus) & !is.na(chunk$family),
                   c("genus", "family"), drop = FALSE]
    gf_df <- gf_df[!duplicated(gf_df$genus), ]
    genus_to_family <- stats::setNames(gf_df$family, gf_df$genus)

    ref_families      <- unique(unname(genus_to_family[ref_genera]))
    ref_families      <- ref_families[!is.na(ref_families)]
    fam_unref_names   <- names(unreferenced_family_map)
    fam_unref_genera  <- sub(" .*", "", fam_unref_names)
    fam_unref_families <- as.character(unreferenced_family_map)

    fam_eligible <- fam_unref_names[
      !fam_unref_names %in% agg$taxon_name &
      !fam_unref_genera %in% ref_genera &
      fam_unref_families %in% ref_families
    ]
  } else {
    genus_to_family <- character(0L)
    fam_eligible    <- character(0L)
  }

  if (length(fam_eligible) > 0L) {
    fam_exp <- vapply(fam_eligible, function(g) {
      g_fam      <- unreferenced_family_map[[g]]
      fam_genera <- names(genus_to_family)[genus_to_family == g_fam]
      fam_idx    <- ref_genera %in% fam_genera
      fam_vals   <- exp_scores[fam_idx]
      if (length(fam_vals) > 0L) stats::median(fam_vals) else stats::median(exp_scores)
    }, numeric(1))
  } else {
    fam_exp <- numeric(0L)
  }

  if (length(unref_eligible) > 0 || length(fam_eligible) > 0L) {
    all_names     <- c(agg$taxon_name, unref_eligible, fam_eligible)
    all_ranks     <- c(agg$taxon_name_rank,
                       rep("species", length(unref_eligible)),
                       rep("species", length(fam_eligible)))
    all_exp       <- c(exp_scores, unref_exp, fam_exp)
    all_hyp_type  <- c(rep("specific_candidate", nrow(agg)),
                       rep("unreferenced_species",    length(unref_eligible)),
                       rep("unreferenced_genus",      length(fam_eligible)))
  } else {
    all_names     <- agg$taxon_name
    all_ranks     <- agg$taxon_name_rank
    all_exp       <- exp_scores
    all_hyp_type  <- rep("specific_candidate", nrow(agg))
  }

  lik <- (1 - unknown_lik_weight) * all_exp / sum(all_exp)

  out <- rbind(
    data.frame(
      observation_id            = sid,
      taxon_name           = all_names,
      taxon_name_rank      = all_ranks,
      hypothesis_type      = all_hyp_type,
      likelihood_point_est = lik,
      likelihood_mean      = lik,
      likelihood_sd        = 0,
      stringsAsFactors     = FALSE
    ),
    data.frame(
      observation_id            = sid,
      taxon_name           = "unknown_species",
      taxon_name_rank      = "unknown",
      hypothesis_type      = "unreferenced_genus",
      likelihood_point_est = unknown_lik_weight,
      likelihood_mean      = unknown_lik_weight,
      likelihood_sd        = 0,
      stringsAsFactors     = FALSE
    )
  )

  # Carry through taxonomy columns; unreferenced and unknown rows receive NA
  if (length(present_tax_cols) > 0) {
    idx <- match(out$taxon_name, tax_lookup$taxon_name)
    for (tc in present_tax_cols) {
      out[[tc]] <- tax_lookup[[tc]][idx]
    }
  }

  out
}


#' Map observation_ids to group labels via context grouping columns
#' @noRd
.build_group_map <- function(context, observation_ids, context_group) {
  if (is.null(context_group) || is.null(context) ||
      !"observation_id" %in% names(context)) {
    return(data.frame(observation_id   = observation_ids,
                      group_label = "all",
                      stringsAsFactors = FALSE))
  }
  missing_cols <- setdiff(context_group, names(context))
  if (length(missing_cols) > 0)
    cli::cli_abort(
      "context_group column(s) not found in context: {.field {missing_cols}}"
    )

  ctx_sub <- context[context$observation_id %in% observation_ids,
                     c("observation_id", context_group), drop = FALSE]

  ctx_sub$group_label <- if (length(context_group) == 1L) {
    as.character(ctx_sub[[context_group]])
  } else {
    apply(ctx_sub[, context_group, drop = FALSE], 1, paste, collapse = " | ")
  }

  missing_sids <- setdiff(observation_ids, ctx_sub$observation_id)
  if (length(missing_sids) > 0) {
    ctx_sub <- rbind(
      ctx_sub[, c("observation_id", "group_label"), drop = FALSE],
      data.frame(observation_id = missing_sids, group_label = "all",
                 stringsAsFactors = FALSE)
    )
  }
  ctx_sub[, c("observation_id", "group_label"), drop = FALSE]
}


#' Collect unique taxa data frame from a named list of lik_dfs
#' @noRd
.collect_unique_taxa <- function(lik_list) {
  all_rows <- dplyr::bind_rows(lik_list)
  all_rows <- all_rows[all_rows$taxon_name != "unknown_species", ]
  dedup    <- !duplicated(all_rows$taxon_name)
  out      <- all_rows[dedup, c("taxon_name", "taxon_name_rank", "hypothesis_type"),
                       drop = FALSE]
  out[order(out$taxon_name), ]
}


#' Get context list for a representative observation in a group
#' @noRd
.get_group_context <- function(context, observation_id) {
  if (is.null(context)) return(list())
  if (!"observation_id" %in% names(context))
    return(as.list(context[1, , drop = FALSE]))
  idx <- which(context$observation_id == observation_id)
  if (length(idx) == 0) return(list())
  as.list(context[idx[[1]], setdiff(names(context), "observation_id"), drop = FALSE])
}


#' Build a flat taxon-list prompt for one group
#' @noRd
.build_taxa_prompt <- function(taxa_df, ctx,
                                known_present      = NULL,
                                known_absent_df    = NULL,
                                prior_weight_guide = NULL) {
  # Context block
  ctx_fields <- c("ecoregion", "lat", "lon", "date", "main_habitat")
  header_parts <- character(0)
  for (fld in ctx_fields) {
    v <- ctx[[fld]]
    if (!is.null(v) && length(v) == 1 && !is.na(v) && nzchar(trimws(as.character(v)))) {
      label <- switch(fld,
        ecoregion    = "Ecoregion", lat = "Latitude", lon = "Longitude",
        date         = "Date/season", main_habitat = "Habitat", fld
      )
      header_parts <- c(header_parts, paste0(label, ": ", as.character(v)))
    }
  }
  ctx_block <- if (length(header_parts) > 0)
    paste0("Context:\n", paste0("  ", header_parts, collapse = "\n"), "\n\n")
  else
    ""

  # Survey context block (independent species observations at the site)
  survey_parts <- character(0)
  if (!is.null(known_present) && length(known_present) > 0)
    survey_parts <- c(survey_parts, paste0(
      "  Confirmed present (use to infer habitat type and co-occurrence patterns):\n",
      "    ", paste(known_present, collapse = ", ")
    ))
  if (!is.null(known_absent_df) && nrow(known_absent_df) > 0)
    survey_parts <- c(survey_parts, paste0(
      "  Confirmed absent (not detected despite adequate survey effort):\n",
      "    ", paste(known_absent_df$taxon_name, collapse = ", "), "\n",
      "  Note: assign prior_weight based on ecology; detection-probability\n",
      "  correction for absent species is applied separately in post-processing."
    ))
  survey_block <- if (length(survey_parts) > 0)
    paste0("Survey context (independent of DNA):\n",
           paste(survey_parts, collapse = "\n"), "\n\n")
  else
    ""

  # Format example
  ex1 <- taxa_df$taxon_name[[1]]
  if (nrow(taxa_df) >= 2) {
    ex2 <- taxa_df$taxon_name[[2]]
    format_example <- paste0(
      "[\n",
      "  {\"taxon_name\": \"", ex1, "\", \"range_status\": \"native\",",
      " \"habitat_fit\": \"expected\",",
      " \"information_quality\": \"high\", \"prior_weight\": 0.90},\n",
      "  {\"taxon_name\": \"", ex2, "\", \"range_status\": \"native\",",
      " \"habitat_fit\": \"unlikely\",",
      " \"information_quality\": \"moderate\", \"prior_weight\": 0.05},\n",
      "  ...\n",
      "]"
    )
  } else {
    format_example <- paste0(
      "[\n",
      "  {\"taxon_name\": \"", ex1, "\", \"range_status\": \"native\",",
      " \"habitat_fit\": \"expected\",",
      " \"information_quality\": \"high\", \"prior_weight\": 0.90}\n",
      "]"
    )
  }

  # Taxa list
  taxa_lines <- sprintf("- %s (%s)%s",
    taxa_df$taxon_name,
    taxa_df$taxon_name_rank,
    ifelse(taxa_df$hypothesis_type != "specific_candidate", " [no reference sequence]", ""))

  paste0(
    "OUTPUT REQUIREMENT: Your ENTIRE response must be ONE valid JSON array.\n",
    "Do not include any text before or after the JSON array.\n",
    "You MUST include EVERY taxon listed below -- no exceptions.\n\n",
    "Act as an expert wildlife biologist, biogeographer, and taxonomist.\n\n",
    ctx_block,
    survey_block,
    "PRIOR WEIGHT RULES:\n",
    "1. Assign a weight proportional to the probability that a random observation\n",
    "   from this site belongs to this species.\n",
    "2. Commit to range_status (geographic presence in this region):\n",
    "   \"native\"                 -- breeds/resides in this region\n",
    "   \"introduced_established\" -- non-native but established here\n",
    "   \"documented_nearby\"      -- recorded in broader region; occasional here\n",
    "   \"not_documented\"         -- no records from this region\n",
    "   \"taxonomically_impossible\" -- wrong continent/realm/major environment\n",
    "   \"uncertain\"              -- insufficient data\n",
    "3. Commit to habitat_fit for the habitat stated in the context:\n",
    "   \"expected\"   -- this IS the taxon's primary or strongly preferred habitat\n",
    "   \"occasional\" -- taxon uses this habitat type peripherally or occasionally\n",
    "   \"unlikely\"   -- taxon is native to region but this habitat type is unsuitable\n",
    "4. Assign prior_weight integrating BOTH range and habitat:\n",
    sprintf("   native + expected habitat:               %g - %g\n",
            prior_weight_guide$native_expected[1], prior_weight_guide$native_expected[2]),
    sprintf("   native + occasional habitat:             %g - %g\n",
            prior_weight_guide$native_occasional[1], prior_weight_guide$native_occasional[2]),
    sprintf("   native + unlikely habitat:               %g - %g\n",
            prior_weight_guide$native_unlikely[1], prior_weight_guide$native_unlikely[2]),
    sprintf("   documented_nearby + expected habitat:    %g - %g\n",
            prior_weight_guide$nearby_expected[1], prior_weight_guide$nearby_expected[2]),
    sprintf("   documented_nearby + occasional/unlikely: %g - %g\n",
            prior_weight_guide$nearby_occasional_unlikely[1], prior_weight_guide$nearby_occasional_unlikely[2]),
    sprintf("   not_documented:                          %g - %g\n",
            prior_weight_guide$not_documented[1], prior_weight_guide$not_documented[2]),
    sprintf("   taxonomically_impossible:                %g - %g\n",
            prior_weight_guide$taxonomically_impossible[1], prior_weight_guide$taxonomically_impossible[2]),
    "5. If no habitat is given in context, base prior_weight on range only.\n",
    "6. If uncertain, reason from genus or family.\n",
    "7. Commit to information_quality -- how much published data exists about\n",
    "   this taxon's distribution in THIS region:\n",
    "   \"high\"     -- well-studied taxon; range, habitat, and occurrence are\n",
    "                  thoroughly documented in the scientific literature\n",
    "   \"moderate\" -- some records exist but distribution is incompletely known\n",
    "                  (e.g. few surveys, taxonomic revision pending)\n",
    "   \"low\"      -- data-deficient taxon, cryptic species complex, or region\n",
    "                  with minimal survey effort\n\n",
    "Required output format:\n",
    format_example, "\n\n",
    "Taxa to assess:\n",
    paste(taxa_lines, collapse = "\n")
  )
}


#' Parse flat JSON array response into a prior_df (one row per taxon)
#' @noRd
.parse_taxa_response <- function(response, taxa_df, group_label = "all") {
  expected <- taxa_df$taxon_name
  n        <- length(expected)

  make_uniform <- function() {
    data.frame(taxon_name          = expected,
               range_status        = NA_character_,
               habitat_fit         = NA_character_,
               information_quality = NA_character_,
               prior_mean          = rep(1 / n, n),
               prior_source        = rep("uniform_fallback", n),
               stringsAsFactors    = FALSE)
  }

  if (is.null(response) || !nzchar(trimws(response))) {
    cli::cli_warn(
      "Empty LLM response for group {.val {group_label}}. Using uniform priors."
    )
    return(make_uniform())
  }

  # Extract JSON array -- handles markdown fences and leading/trailing text
  # (?s) enables PCRE dotall mode so .* matches across newlines
  arr_str <- sub("(?s).*?(\\[[\\s\\S]*\\]).*", "\\1", response, perl = TRUE)
  parsed  <- tryCatch(
    jsonlite::fromJSON(arr_str, simplifyDataFrame = TRUE),
    error = function(e) NULL
  )

  if (is.null(parsed) || !is.data.frame(parsed) ||
      !all(c("taxon_name", "prior_weight") %in% names(parsed))) {
    cli::cli_warn(
      "Failed to parse taxon prior response for group {.val {group_label}}. \\
      Using uniform priors."
    )
    return(make_uniform())
  }

  parsed$prior_weight <- suppressWarnings(as.numeric(parsed$prior_weight))
  if (any(is.na(parsed$prior_weight)) || any(parsed$prior_weight < 0)) {
    cli::cli_warn(
      "Invalid prior weights for group {.val {group_label}}. Using uniform priors."
    )
    return(make_uniform())
  }

  rs <- if ("range_status" %in% names(parsed)) as.character(parsed$range_status)
        else rep(NA_character_, nrow(parsed))

  hf <- if ("habitat_fit" %in% names(parsed)) as.character(parsed$habitat_fit)
        else rep(NA_character_, nrow(parsed))

  iq <- if ("information_quality" %in% names(parsed)) as.character(parsed$information_quality)
        else rep(NA_character_, nrow(parsed))

  total <- sum(parsed$prior_weight)
  if (total == 0) total <- 1

  result <- data.frame(
    taxon_name          = parsed$taxon_name,
    range_status        = rs,
    habitat_fit         = hf,
    information_quality = iq,
    prior_mean          = parsed$prior_weight / total,
    prior_source        = rep("llm", nrow(parsed)),
    stringsAsFactors    = FALSE
  )

  # Warn about omitted taxa (fallback handled in main loop)
  omitted <- setdiff(expected, result$taxon_name)
  if (length(omitted) > 0)
    cli::cli_warn(
      "{length(omitted)} taxon/taxa omitted from LLM response for group \\
      {.val {group_label}}: {.val {omitted}}"
    )

  result
}
