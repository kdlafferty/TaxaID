# Edge: taxa -> acoustic_matrix
# Source: TaxaLikely fetch_reference_recordings() + TaxaMatch read_birdnet_output()
#         + TaxaLikely build_acoustic_reference()
#
# This edge has THREE stages. Stage 2 requires an external Python step.
# Re-run from Stage 3 after BirdNET completes.
# =============================================================================

# ---- STAGE 1: Fetch reference recordings from Xeno-canto -------------------
message("Stage 1: Fetching reference recordings from Xeno-canto...")

# {{input_var}} is a character vector of species names
recordings_meta <- TaxaLikely::fetch_reference_recordings(
  species         = unique({{input_var}}),
  quality         = {{xc_quality}},
  max_per_species = {{max_per_species}},
  download        = TRUE,
  download_dir    = {{audio_dir}},
  api_key         = {{xc_api_key}}
)

if (nrow(recordings_meta) == 0L)
  stop("fetch_reference_recordings() returned 0 recordings. Check XC_API_KEY and species names.",
       call. = FALSE)
message("Fetched ", nrow(recordings_meta), " recordings to ", {{audio_dir}})

# ---- STAGE 2: Run BirdNET on downloaded audio (external Python step) -------
# Complete this step before running Stage 3.
#
#   From the shell:
#     python -m birdnetanalyzer.analyze \
#       --i "{{audio_dir}}" \
#       --o "{{birdnet_refs_dir}}" \
#       --min_conf 0.1 \
#       --rtype csv
#
#   From R (using TaxaMatch helper script):
#     system(paste("python", system.file("run_birdnet.py", package = "TaxaMatch"),
#                  "--input", {{audio_dir}}, "--output", {{birdnet_refs_dir}}))

if (!dir.exists({{birdnet_refs_dir}}) ||
    length(list.files({{birdnet_refs_dir}}, pattern = "\\.csv$")) == 0L)
  stop("BirdNET output directory '", {{birdnet_refs_dir}}, "' is empty or missing.\n",
       "Complete Stage 2 (run BirdNET) before proceeding.", call. = FALSE)

# ---- STAGE 3: Build acoustic reference matrix ------------------------------
message("Stage 3: Reading BirdNET output and building acoustic reference matrix...")

birdnet_on_refs <- TaxaMatch::read_birdnet_output(
  data           = {{birdnet_refs_dir}},
  min_confidence = 0.1   # keep liberal for reference building; model learns the distribution
)

acoustic_matrix <- TaxaLikely::build_acoustic_reference(
  recordings_meta  = recordings_meta,
  birdnet_df       = birdnet_on_refs,
  rank_system      = {{rank_system}},
  exclude_background = TRUE
)

message("Acoustic reference matrix: ", nrow(acoustic_matrix), " pairs, ",
        length(unique(acoustic_matrix$species.x)), " species, ",
        length(unique(recordings_meta$type)), " recording type(s): ",
        paste(unique(recordings_meta$type), collapse = ", "))
message("Train one model per recording type: train_likelihood_model(acoustic_matrix[type == 'song', ])")
acoustic_matrix
