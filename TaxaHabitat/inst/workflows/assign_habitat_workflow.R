# ==============================================================================
# WORKFLOW: ASSIGN HABITAT (TaxaHabitat)
# ==============================================================================
# Purpose: Classify each taxon in an occurrence table into a habitat scheme via
#   an LLM, join those weighted habitat calls onto occurrence points, then run
#   spatial QAQC to flag points whose location is implausible given their
#   assigned habitat.
#
# Audience: someone learning TaxaHabitat step by step, continuing directly from
#   TaxaFetch's fetch_occurrences_workflow.R. With DEBUG_MODE = TRUE (the
#   default) this script tries to load that script's all_occurrences checkpoint
#   (genus Gadus, North Atlantic tutorial run); if the checkpoint file is not
#   found, it falls back to a tiny built-in all_occurrences-shaped tibble so
#   this script is still fully self-contained. Just source() the whole file.
#
#   NOTE: build_habitat_prompt() -> TaxaTools::prompt_api() is a REAL LLM call.
#   This script is not designed to run to completion without ANTHROPIC_API_KEY
#   (or another provider wired via getOption("TaxaID.llm_fn")) set. Its job is
#   to be syntactically correct and pedagogically clear -- see Section 2 below.
#
# TWO CLASSIFICATION STEPS, SAME MECHANISM:
#   STEP A (always runs) -- standard HABITAT classification using the
#     package's default 3-category scheme (Marine/Freshwater/Terrestrial).
#     Applies to both narrow-marker (12S) and broad-marker (18S/COI) workflows.
#   STEP B (OPTIONAL, NEEDS_SAMPLING_GROUP toggle, default FALSE) -- the EXACT
#     SAME three functions (build_habitat_prompt -> prompt_api ->
#     parse_hierarchical_habitat_response -> assign_habitat_biological)
#     classify taxa into an arbitrary scheme instead -- here, coarse sampling
#     groups (Fishes/Macroalgae/Phytoplankton/Zooplankton) for per-group
#     modelling downstream in TaxaExpect. Only relevant for broad-marker
#     workflows; narrow markers (12S) skip Step B entirely.
#
# Output: occurrences_clean -- a tibble; see "Output" block at the end of this
#   file for the full column contract consumed by TaxaExpect.
# ==============================================================================

# --- Namespaces used in this script (loaded, never attached) ----------------
# TaxaHabitat::, TaxaTools::, dplyr::, tibble::

# ==============================================================================
# CONFIG
# ==============================================================================
# Parameters are grouped here so this script's body can become a wrapper
# function's implementation with minimal changes -- each CONFIG value maps
# to a future function argument.

# DEBUG_MODE = TRUE  -> load the TaxaFetch tutorial checkpoint if present,
#                       else fall back to a tiny built-in example
# DEBUG_MODE = FALSE -> plug in your own all_occurrences object (see the
#                       "SWAP IN YOUR OWN DATA" block below Section 1)
DEBUG_MODE <- TRUE

# STEP B is OPTIONAL and only relevant for broad-marker (18S/COI) workflows
# that need per-sampling-group modelling downstream in TaxaExpect. Narrow
# markers (12S) leave this FALSE and skip Step B entirely.
NEEDS_SAMPLING_GROUP <- FALSE

# Habitat consensus threshold passed to assign_habitat_biological() -- see
# Section 3. Lower values include more marginal/generalist habitat calls.
HABITAT_THRESHOLD <- 0.5

if (DEBUG_MODE) {

  # ---- Tutorial example: continue from TaxaFetch's Gadus / North Atlantic run
  # This is the exact readRDS() line documented in fetch_occurrences_workflow.R's
  # Output block. If that script was never run (or tempdir() was cleared since),
  # the file will not exist and we fall back to a tiny inline example below.
  .gadus_checkpoint <- file.path(tempdir(), "tutorial_gadus_all_occurrences.rds")

  if (file.exists(.gadus_checkpoint)) {
    all_occurrences <- readRDS(.gadus_checkpoint)
    message("DEBUG_MODE = TRUE -- loaded TaxaFetch's Gadus checkpoint: ",
            .gadus_checkpoint)

    # KNOWN GAP: fetch_occurrences_workflow.R's Variant A output (unmodified
    # GBIF columns -- species/genus/family/... -- plus point_id) does NOT
    # include a taxon_name column; only its commented-out Variant B does, via
    # TaxaTools::create_taxon_names(). Every step below needs taxon_name, so
    # derive it here if the checkpoint doesn't already have one, rather than
    # assuming TaxaFetch's output shape.
    if (!"taxon_name" %in% names(all_occurrences)) {
      all_occurrences <- TaxaTools::create_taxon_names(all_occurrences)
      message("  taxon_name not present in checkpoint -- derived via ",
              "TaxaTools::create_taxon_names() from GBIF's raw rank columns.")
    }
  } else {
    # ---- Fallback: tiny inline all_occurrences-shaped tibble ----------------
    # Kept small (3 rows) but spans all three default-scheme categories
    # (marine, freshwater, terrestrial) so Step A's demo is meaningful even
    # without TaxaFetch's checkpoint on disk.
    all_occurrences <- tibble::tibble(
      point_id         = c("pt_1", "pt_2", "pt_3"),
      decimalLatitude  = c(60.0, 44.5, 46.8),
      decimalLongitude = c(2.0, -73.2, -121.7),
      taxon_name       = c("Gadus morhua",        # marine (cod)
                           "Salmo trutta",         # freshwater (brown trout)
                           "Odocoileus hemionus")  # terrestrial (mule deer)
    )
    message("DEBUG_MODE = TRUE -- TaxaFetch checkpoint not found at ",
            .gadus_checkpoint, "; using tiny built-in fallback (3 rows, ",
            "one marine/freshwater/terrestrial taxon each).")
  }

} else {

  # ==========================================================================
  # >>> SWAP IN YOUR OWN DATA <<<
  # ==========================================================================
  # Replace the block above with your real all_occurrences object:
  #
  #   all_occurrences <- readRDS("path/to/your_all_occurrences.rds")
  #     (the object produced by TaxaFetch::stack_occurrences(), or any
  #     dataframe/tibble with point_id, decimalLatitude, decimalLongitude,
  #     and taxon_name columns)
  #
  # Set DEBUG_MODE <- FALSE above and fill in the value here.
  # ==========================================================================
  stop("DEBUG_MODE is FALSE but no real all_occurrences object has been ",
       "supplied. Edit the 'SWAP IN YOUR OWN DATA' block in this script.")
}

# Output location for checkpoint files (see explicit-checkpoint pattern below)
OUT_DIR    <- tempdir()
OUT_PREFIX <- "tutorial_gadus"

message(sprintf("NEEDS_SAMPLING_GROUP = %s -- %s", NEEDS_SAMPLING_GROUP,
                if (NEEDS_SAMPLING_GROUP)
                  "Step B (sampling-group classification) WILL run"
                else
                  "Step B (sampling-group classification) will be skipped"))

# ==============================================================================
# 1.  STEP A -- STANDARD HABITAT CLASSIFICATION (default 3-category scheme)
# ==============================================================================
# Always runs, for both narrow- and broad-marker workflows.
# Mechanism: build_habitat_prompt() -> TaxaTools::prompt_api() ->
#            parse_hierarchical_habitat_response() -> assign_habitat_biological()

message("\n--- Step 1: Building habitat prompt (Step A -- default scheme) ---")

taxa_in_data <- unique(all_occurrences$taxon_name)
message(sprintf("  %d unique taxa to classify.", length(taxa_in_data)))

# habitat_scheme = NULL -> package default: Marine / Freshwater / Terrestrial.
# Always a valid starting point and always interpretable in a model. For finer
# resolution, build a custom scheme dataframe (see example_habitat_scheme) or
# use TaxaHabitat::build_iucn_scheme().
habitat_prompt_a <- TaxaHabitat::build_habitat_prompt(
  taxon_list     = taxa_in_data,
  habitat_scheme = NULL
)
print(habitat_prompt_a)

# ---- Submit to an LLM ------------------------------------------------------
# TaxaTools::prompt_api() dispatches habitat_prompt_a's chunk(s) to whichever
# provider function is passed as llm_fn. getOption("TaxaID.llm_fn") is set
# automatically by TaxaTools::.onAttach() to the first available provider
# (Anthropic > Gemini > OpenAI, by API-key presence); TaxaTools::call_anthropic_api
# is used here as an explicit fallback so this script's intent is unambiguous
# without relying on session state.
#
# This IS a real network call -- it requires ANTHROPIC_API_KEY (or another
# provider key) set in ~/.Renviron. It is not mocked here: faking an LLM
# response inline would misrepresent what the pipeline actually does. If no
# key is available, this line will error; that is expected in a sandbox with
# no credentials. The rest of the script is written so it is still syntactically
# correct and readable end to end.
message("\n--- Step 2: Submitting Step A prompt via TaxaTools::prompt_api() ---")
message("  Requires ANTHROPIC_API_KEY (or getOption(\"TaxaID.llm_fn\")) to actually run.")

llm_response_a <- TaxaTools::prompt_api(
  habitat_prompt_a,
  llm_fn = getOption("TaxaID.llm_fn", TaxaTools::call_anthropic_api)
)

# ---- Parse the LLM's response into a species x habitat weight table -------
message("\n--- Step 3: Parsing Step A response ---")

habitat_weights_a <- TaxaHabitat::parse_hierarchical_habitat_response(
  raw_text       = llm_response_a,
  taxon_list     = habitat_prompt_a$taxa,
  habitat_scheme = habitat_prompt_a
)

# ---- Explicit checkpoint (not automatic) ------------------------------------
# Save now so a future session can skip Steps 1-3 by pasting the readRDS()
# line below -- no file.exists()-gated auto-reload; you decide when to reuse.
habitat_weights_a_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_habitat_weights_a.rds"))
saveRDS(habitat_weights_a, habitat_weights_a_path)
message(sprintf("  Saved: %s", habitat_weights_a_path))
message(sprintf("  To reuse without re-querying the LLM, paste:\n    habitat_weights_a <- readRDS(\"%s\")",
                habitat_weights_a_path))

# ---- Join habitat weights onto occurrence points (per-point consensus) ----
message("\n--- Step 4: Assigning habitat to occurrence points (Step A) ---")

occurrences_with_habitat <- TaxaHabitat::assign_habitat_biological(
  data         = all_occurrences,
  habitats_df  = habitat_weights_a,
  point_id_col = "point_id",
  taxon_col    = "taxon_name",
  threshold    = HABITAT_THRESHOLD
)

n_habitats_assigned <- occurrences_with_habitat |>
  dplyr::filter(!is.na(main_habitat)) |>
  dplyr::distinct(point_id) |>
  nrow()
message(sprintf("  %d point(s) assigned a habitat (threshold = %.2f).",
                n_habitats_assigned, HABITAT_THRESHOLD))

# ---- Explicit checkpoint ----------------------------------------------------
occurrences_with_habitat_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_occurrences_with_habitat.rds"))
saveRDS(occurrences_with_habitat, occurrences_with_habitat_path)
message(sprintf("  Saved: %s", occurrences_with_habitat_path))
message(sprintf("  To reuse without re-running Step A, paste:\n    occurrences_with_habitat <- readRDS(\"%s\")",
                occurrences_with_habitat_path))


# ==============================================================================
# 2.  STEP B (OPTIONAL) -- SAMPLING-GROUP CLASSIFICATION, SAME MECHANISM
# ==============================================================================
# Guarded by NEEDS_SAMPLING_GROUP (default FALSE). Demonstrates that the exact
# same three functions used for Step A -- build_habitat_prompt(),
# TaxaTools::prompt_api(), parse_hierarchical_habitat_response() -- classify
# taxa into ANY scheme, not just habitats. No package changes were needed to
# support this: the underlying mechanism is scheme-agnostic weight-matrix math
# (assign_habitat_biological() sums per-species weight vectors and takes the
# argmax against a threshold, regardless of what the columns are named). The
# LLM prompt's habitat-flavored prose does not meaningfully affect
# classification -- what actually drives the LLM's answer is the category
# list itself (here, sampling-group names instead of habitat names).
#
# Only relevant for broad-marker workflows (18S/COI) that need per-group
# modelling downstream in TaxaExpect. Narrow markers (12S) skip this entirely.
# ==============================================================================

if (NEEDS_SAMPLING_GROUP) {

  message("\n--- Step B: Sampling-group classification (same mechanism as Step A) ---")

  # Custom scheme: l1_name is required; l2_name/l2_code/realm are optional and
  # NA-pad automatically. realm = NA is explicitly valid (see
  # .validate_habitat_scheme()'s accepted values: "marine","freshwater",
  # "terrestrial", NA) -- a non-habitat scheme like this one uses NA throughout
  # because "realm" has no meaning for a sampling-group label.
  sampling_group_scheme <- data.frame(
    l1_name = c("Fishes", "Macroalgae", "Phytoplankton", "Zooplankton"),
    l2_name = NA_character_,
    l2_code = NA_character_,
    realm   = NA_character_,
    stringsAsFactors = FALSE
  )

  habitat_prompt_b <- TaxaHabitat::build_habitat_prompt(
    taxon_list     = taxa_in_data,
    habitat_scheme = sampling_group_scheme
  )
  print(habitat_prompt_b)

  message("  Requires ANTHROPIC_API_KEY (or getOption(\"TaxaID.llm_fn\")) to actually run.")
  llm_response_b <- TaxaTools::prompt_api(
    habitat_prompt_b,
    llm_fn = getOption("TaxaID.llm_fn", TaxaTools::call_anthropic_api)
  )

  sampling_group_weights <- TaxaHabitat::parse_hierarchical_habitat_response(
    raw_text       = llm_response_b,
    taxon_list     = habitat_prompt_b$taxa,
    habitat_scheme = habitat_prompt_b
  )

  # ---- Explicit checkpoint --------------------------------------------------
  sampling_group_weights_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_sampling_group_weights.rds"))
  saveRDS(sampling_group_weights, sampling_group_weights_path)
  message(sprintf("  Saved: %s", sampling_group_weights_path))
  message(sprintf("  To reuse without re-querying the LLM, paste:\n    sampling_group_weights <- readRDS(\"%s\")",
                  sampling_group_weights_path))

  # IMPORTANT: run this against all_occurrences (the ORIGINAL raw table), NOT
  # against occurrences_with_habitat. assign_habitat_biological() unconditionally
  # drops any pre-existing main_habitat/habitat_best_guess columns from its
  # `data` argument before joining in its own result (see its source:
  # "Drop any pre-existing main_habitat / habitat_best_guess columns in data",
  # R/assign_habitat_biological.R). Calling it directly on
  # occurrences_with_habitat would silently destroy Step A's habitat
  # classification, not just its habitat_best_guess column. Instead, compute
  # Step B's result as an independent object and explicitly join just its
  # renamed output columns onto occurrences_with_habitat -- Step A's
  # main_habitat is never at risk of being overwritten.
  sampling_group_result <- TaxaHabitat::assign_habitat_biological(
    data         = all_occurrences,
    habitats_df  = sampling_group_weights,
    point_id_col = "point_id",
    taxon_col    = "taxon_name",
    threshold    = HABITAT_THRESHOLD
  ) |>
    dplyr::distinct(point_id, sampling_group = main_habitat,
                    sampling_group_best_guess = habitat_best_guess)

  occurrences_with_habitat <- occurrences_with_habitat |>
    dplyr::left_join(sampling_group_result, by = "point_id")

  n_groups_assigned <- occurrences_with_habitat |>
    dplyr::filter(!is.na(sampling_group)) |>
    dplyr::distinct(point_id) |>
    nrow()
  message(sprintf("  %d point(s) assigned a sampling_group (threshold = %.2f).",
                  n_groups_assigned, HABITAT_THRESHOLD))

  # ---- Explicit checkpoint --------------------------------------------------
  occurrences_with_habitat_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_occurrences_with_habitat_and_group.rds"))
  saveRDS(occurrences_with_habitat, occurrences_with_habitat_path)
  message(sprintf("  Saved: %s", occurrences_with_habitat_path))
  message(sprintf("  To reuse without re-running Step B, paste:\n    occurrences_with_habitat <- readRDS(\"%s\")",
                  occurrences_with_habitat_path))

} else {
  message("\n--- Step B skipped (NEEDS_SAMPLING_GROUP = FALSE) ---")
}


# ==============================================================================
# 3.  SPATIAL QAQC -- FLAG AND REVIEW HABITAT/LOCATION INCONSISTENCIES
# ==============================================================================
# flag_habitat_inconsistencies() derives each point's physical zone (inland,
# coastal, marine shallow/deep/abyssal) from land polygons + bathymetry and
# compares it against main_habitat. review_spatial_flags() is an INTERACTIVE
# Shiny gadget for correcting flagged points -- it CANNOT run inside a
# non-interactive source() of this script. Run it by hand in an interactive
# R session after sourcing everything above; the commented call below shows
# how. For the tutorial run, we take the DEBUG_MODE shortcut described below
# instead so the script completes unattended.
# ==============================================================================

message("\n--- Step 5: Flagging spatial inconsistencies ---")

occurrences_flagged <- TaxaHabitat::flag_habitat_inconsistencies(
  occurrences_with_habitat,
  habitat_col = "main_habitat"
)

# ---- Explicit checkpoint ----------------------------------------------------
occurrences_flagged_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_occurrences_flagged.rds"))
saveRDS(occurrences_flagged, occurrences_flagged_path)
message(sprintf("  Saved: %s", occurrences_flagged_path))
message(sprintf("  To reuse without re-flagging, paste:\n    occurrences_flagged <- readRDS(\"%s\")",
                occurrences_flagged_path))

# ---- Interactive review (run by hand -- NOT via source()) -----------------
# review_spatial_flags() opens a Shiny gadget: click points on a map to move
# them between "likely" / "questionable" / "unlikely", or reassign main_habitat
# directly. Must be run interactively; uncomment and run this line yourself
# in the R console (not by sourcing this file):
#
#   reviewed_spatial <- TaxaHabitat::review_spatial_flags(occurrences_flagged)
#   occurrences_clean <- dplyr::filter(reviewed_spatial, spatial_flag == "likely")
#
# DEBUG_MODE shortcut so the tutorial completes unattended: flag_habitat_
# inconsistencies() already classifies every point as spatial_flag %in%
# c("likely", "questionable", "unlikely") (see R/flag_habitat_inconsistencies.R).
# Here we simply take all "likely" points as-is, without the interactive
# upgrade/downgrade pass a real analysis would apply to "questionable" points.
message("\n--- Step 6: Filtering to spatial_flag == \"likely\" (DEBUG_MODE shortcut) ---")
message("  For real analyses, run TaxaHabitat::review_spatial_flags() interactively",
        " instead of this shortcut -- see the commented block above.")

occurrences_clean <- dplyr::filter(occurrences_flagged, spatial_flag == "likely")
message(sprintf("  %d of %d row(s) retained (spatial_flag == \"likely\").",
                nrow(occurrences_clean), nrow(occurrences_flagged)))

# ---- Explicit checkpoint ----------------------------------------------------
occurrences_clean_path <- file.path(OUT_DIR, paste0(OUT_PREFIX, "_occurrences_clean.rds"))
saveRDS(occurrences_clean, occurrences_clean_path)
message(sprintf("  Saved: %s", occurrences_clean_path))
message(sprintf("  To reuse without re-running this workflow, paste:\n    occurrences_clean <- readRDS(\"%s\")",
                occurrences_clean_path))

message("\nWorkflow complete.")
message("Next: pass occurrences_clean to TaxaExpect for grid optimization and prior generation.")

# ==============================================================================
# Output
# ==============================================================================
# This workflow produces one primary object: occurrences_clean (a tibble).
#
# Columns (always present):
#   point_id                -- character; from all_occurrences
#   decimalLatitude          -- numeric
#   decimalLongitude         -- numeric
#   taxon_name / other taxonomic columns -- as carried in from all_occurrences
#   main_habitat             -- character; winning habitat from Step A's
#                               3-category (or custom) scheme, or NA if no
#                               habitat reached HABITAT_THRESHOLD. "Other"
#                               indicates the assemblage at that point does
#                               not fit the scheme -- see habitat_best_guess.
#   habitat_best_guess       -- character; free-text description populated
#                               only when main_habitat == "Other".
#   elevation_m              -- numeric; GEBCO bathymetry/elevation at the
#                               point (diagnostic; added by
#                               flag_habitat_inconsistencies()).
#   dist_to_coast_km         -- numeric; distance to nearest coastline.
#   spatial_flag             -- character; "likely" for all retained rows
#                               (occurrences_clean is pre-filtered to this).
#   spatial_flag_reason      -- character; plain-English explanation.
#
# Additional columns (present only if NEEDS_SAMPLING_GROUP was TRUE):
#   sampling_group           -- character; winning sampling group from Step B
#                               (Fishes/Macroalgae/Phytoplankton/Zooplankton/
#                               Other/NA), for per-group modelling in
#                               TaxaExpect. Absent entirely for narrow-marker
#                               (12S) workflows that skip Step B. Computed
#                               independently of main_habitat -- Step B never
#                               overwrites Step A's columns (see the comment
#                               above sampling_group_result in Section 2).
#   sampling_group_best_guess -- character; Step B's free-text description,
#                               populated only when sampling_group == "Other".
#                               Distinct from habitat_best_guess (Step A's).
#
# Consumer: TaxaExpect, which uses main_habitat (and, for broad markers,
#   sampling_group) plus the coordinate columns for grid optimization,
#   spatial modelling, and prior generation.
# ==============================================================================
