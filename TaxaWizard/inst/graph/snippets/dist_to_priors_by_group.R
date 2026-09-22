# Edge: std_occurrences -> priors (grouped by sampling/detection process, kernel path)
# Source: TaxaExpect kernel-priors redesign + sampling_group_col support,
#   e.g. PtConceptionWorkflow_18S_2_single_site.R
# NOTE: {{sampling_group_col}} identifies which DETECTION METHOD/PROCESS
#   each row belongs to (e.g. "fish" vs "birds" vs "phytoplankton" surveyed
#   with different effort) -- this is NOT the same thing as a physical site.
#   Pooling groups with very different sampling effort into one estimate
#   silently distorts every group's estimated composition AND its Good-Turing
#   budget (a barely-sampled group's singletons inflate f1 -- hence
#   chao_missing, quadratically -- while adding almost nothing to
#   missing_mass). Use this path only when {{input_var}} already has a column
#   identifying detection group; otherwise use the plain std_to_priors_kernel
#   path.
# Rewritten from the retired GLMM-path wrapper
#   train_biodiversity_model_by_group() to the kernel-path equivalent. A
#   single estimate_kernel_priors(sampling_group_col=) call handles every
#   group at once (no per-group model-fitting loop needed) -- this snippet
#   works directly on standardized occurrence data, no gridding step
#   (create_sites_from_grid()/the old "distributions" intermediate) needed,
#   so this edge's own `from` is "std_occurrences", not "distributions" --
#   the whole GLMM chain, including "distributions"'s only other consumer,
#   dist_to_priors, is retired.

std_occurrences <- {{input_var}}

# Step 1: calibrate the kernel bandwidth with the SAME sampling_group_col the
# estimator uses below.
#
# (lambda_km does NOT describe spatial decay independent of detection-process
# membership -- calibrating it on pooled data is a real, non-obvious trap.
# lambda_km IS spatial decay, but the quantity MINIMISED to estimate it
# is a multinomial composition log-loss, and a composition is a share WITHIN a
# detection process. Pooling therefore lets the largest group choose the
# bandwidth for all of them. It does not announce itself: the fit succeeds and
# returns a plausible number that is simply wrong for every group but the
# dominant one. On a real fixture with 4 km patches in one group and 55 km in
# another, the groups wanted 5 km and 25 km.)
#
# lambda_grid spans 1-100 km deliberately. A grid that cannot express its own
# answer reports a boundary warning pointing the wrong way: PtConception 12S
# measured its optimum at 10 km, INTERIOR, only once 1/2/5 were offered -- the
# old c(25, 50, 100, 200) could not represent 10 at all and would have invited
# widening UPWARD. Keep this in step with the canonical workflow template.
kernel_cal <- TaxaExpect::calibrate_kernel_bandwidth(
  std_occurrences,
  site_habitat       = {{site_habitat}},
  lambda_grid        = c(1, 2, 5, 10, 25, 50, 100),
  sampling_group_col = {{sampling_group_col}}
)
message(sprintf(
  "Calibrated kernel bandwidth: lambda = %g km (LOBO loss %.3f)",
  kernel_cal$best$lambda_km, kernel_cal$best$weighted_logloss
))

# Step 1b: is the kernel worth having at all? An interior optimum says only
# "best bandwidth offered", never that the kernel beats NOT having one.
# $results carries `regional` and `nearest_block` reference rows, by row name.
.k_loss   <- kernel_cal$best$weighted_logloss
.reg_loss <- kernel_cal$results["regional", "weighted_logloss"]
.nb_loss  <- kernel_cal$results["nearest_block", "weighted_logloss"]
message(sprintf(
  "LOBO log-loss: kernel %.4f | regional %.4f | nearest_block %.4f",
  .k_loss, .reg_loss, .nb_loss
))
.gain <- .reg_loss - .k_loss
.pct  <- 100 * .gain / .reg_loss
if (!is.na(.gain) && .gain <= 0) {
  warning(sprintf(
    paste0("kernel does NOT beat regional (%.4f vs %.4f). The answer is not a ",
           "different lambda but a smaller block_size_deg."),
    .k_loss, .reg_loss
  ), call. = FALSE)
} else {
  message(sprintf("kernel beats regional by %.4f (%.2f%%)", .gain, .pct))
  if (!is.na(.pct) && .pct < 1) {
    warning(sprintf(
      paste0("kernel margin over regional is only %.2f%% -- lambda may be an ",
             "artifact of the CV block geometry rather than a real length scale."),
      .pct
    ), call. = FALSE)
  }
}

# Step 1c: estimate_kernel_priors() takes a SCALAR lambda_km, so it can only
# REPORT a per-group disagreement, never act on one. Read $by_group before
# trusting $best -- calibrate_kernel_bandwidth() warns at >= 2x disagreement.
if (!is.null(kernel_cal$by_group)) {
  message("Per-group optimal lambda (the scalar above is a compromise across these):")
  print(kernel_cal$by_group[
    , intersect(c("sampling_group", "n_records", "n_blocks_scored",
                  "lambda_km", "weighted_logloss"),
                names(kernel_cal$by_group))
  ])
}

# Step 2: estimate site priors, computing composition AND the Good-Turing
# budget WITHIN each sampling_group_col value rather than pooled. With more
# than one group the pooled f1/f2/chao_missing/theta_present scalars are NA
# by design (no single budget exists across detection processes) -- $budget
# is the authoritative per-group table.
kernel_priors_fit <- TaxaExpect::estimate_kernel_priors(
  std_occurrences,
  site_lat           = {{lat}},
  site_lon           = {{lon}},
  site_habitat       = {{site_habitat}},
  lambda_km          = kernel_cal$best$lambda_km,
  site_id            = sprintf("Site_%.2f_%.2f", {{lat}}, {{lon}}),
  sampling_group_col = {{sampling_group_col}}
)
print(kernel_priors_fit)
message("Per-group budget:")
print(kernel_priors_fit$budget)

# Step 3: unseen-taxa floor (Good-Turing/Chao-based dark-diversity mirrors,
# stamped with this site's own id). Each singleton mirror is scaled by its
# OWN group's n_eff (not the pooled total), so this single call correctly
# handles every group at once -- no per-group loop needed.
priors_undetected <- TaxaExpect::generate_undetected_diversity(
  model_obj = kernel_priors_fit,
  taxonomy  = std_occurrences
)

priors <- dplyr::bind_rows(kernel_priors_fit$priors, priors_undetected) |>
  dplyr::mutate(taxon_name_rank = "species")

message(sprintf(
  "Generated priors for %d resident taxa + %d undetected/dark-diversity row(s) across %d sampling group(s)",
  sum(priors$prior_branch %in% c("kernel_estimated"), na.rm = TRUE),
  sum(priors$prior_branch == "resident_undetected", na.rm = TRUE),
  dplyr::n_distinct(std_occurrences[[{{sampling_group_col}}]])
))

# Optional: add named domestic/commensal-animal and food-species priors --
# these are a contamination-risk claim, not an occurrence-plausibility one,
# and are deliberately priced on a POOLED fit, not per-group: a domestic/food
# species isn't scoped to one detection process. Set
# {{include_domestic_priors}} to FALSE to skip this step entirely.
if (isTRUE({{include_domestic_priors}})) {
  kernel_priors_pooled <- TaxaExpect::estimate_kernel_priors(
    std_occurrences,
    site_lat     = {{lat}},
    site_lon     = {{lon}},
    site_habitat = {{site_habitat}},
    lambda_km    = kernel_cal$best$lambda_km,
    site_id      = kernel_priors_fit$params$site_id
  )
  domestic_priors <- TaxaExpect::generate_domestic_food_priors(
    model_obj = kernel_priors_pooled,
    lat       = {{lat}},
    lng       = {{lon}},
    grid_id   = kernel_priors_fit$params$site_id
  )
  priors <- dplyr::bind_rows(priors, domestic_priors)
  message("Added ", nrow(domestic_priors), " domestic/food-species prior row(s)")
}

# verify_taxon_names()'s real formals are
# (name_list, backbone_id, batch_size, timeout_sec, fallback_backbone_id) --
# passing the whole `priors` data frame positionally as
# `name_list` (wrong type: a character vector is expected) and a `taxon_col`
# argument that does not exist, then discarding `priors` by reassigning it
# to the verification result, is a real trap. Verify the taxon names
# informationally without clobbering `priors`.
taxon_verification <- TaxaTools::verify_taxon_names(
  name_list   = unique(priors$taxon_name),
  backbone_id = {{target_backbone_id}}
)
message(sprintf(
  "Taxon-name verification: %d of %d unique taxon name(s) did not verify against backbone %s",
  sum(!taxon_verification$verified, na.rm = TRUE), nrow(taxon_verification),
  {{target_backbone_id}}
))
priors <- TaxaMatch::convert_taxonomy_backbone(
  priors,
  target_backbone_id = {{target_backbone_id}},
  taxon_col           = "taxon_name"
)
message("Generated priors for ", length(unique(priors$taxon_name)), " taxa across ",
        dplyr::n_distinct(std_occurrences[[{{sampling_group_col}}]]), " sampling group(s)")
priors
