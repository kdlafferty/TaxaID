# ==============================================================================
# WORKFLOW 3b: TRAIN AN ACOUSTIC LIKELIHOOD MODEL
# ==============================================================================
# Purpose: Build an acoustic reference dataset from Xeno-canto recordings +
#   BirdNET-Analyzer output, then train a likelihood model for converting
#   BirdNET confidence scores into calibrated likelihoods.
#
# This is the acoustic analog of Workflow 3 (DNA sequences). The core idea
# is the same: compare within-species scores to cross-species scores to
# learn what a "correct match" looks like vs. a "wrong match" or an
# "absent species."
#
# --- HOW ACOUSTIC TRAINING DIFFERS FROM SEQUENCE TRAINING ---
#
# DNA sequences:    build_sequence_matrix()    -- pairwise DECIPHER alignment
# Acoustic:         build_acoustic_reference() -- BirdNET detections vs.
#                     Xeno-canto ground truth labels
#
# DNA reference:    NCBI (fetch_reference_sequences)
# Acoustic ref:     Xeno-canto (fetch_reference_recordings)
#
# DNA match unit:   ESV/ASV sequence  -->  reference accession
# Acoustic match:   time window (3s)  -->  BirdNET detection
#
# DNA barcode type: testid column (12S, COI, MiFish, etc.)
# Acoustic type:    testid column (song, call, flight call, etc.)
#
# --- THE RECORDING TYPE PROBLEM ---
#
# This is the most important design decision in acoustic likelihood modelling.
# A species' song and its call are acoustically very different signals.
# BirdNET confidence scores for a correct match are not the same for songs
# vs. calls. If you mix types and train one model, the within-species
# distribution is artificially broadened and the model loses discrimination.
#
# The solution mirrors eDNA practice exactly:
#   - eDNA: train one model per barcode marker (12S, 16S, COI)
#   - Acoustics: train one model per recording type (song, call, etc.)
#
# Xeno-canto recording types are often multi-valued (e.g., "call, song",
# "song, growl song"). At Step 6, filter to exact matches (testid == "song")
# to keep only pure recordings of each type.
#
# --- H1, H2, H3 IN ACOUSTIC CONTEXT ---
#
#   H1: BirdNET detected the correct species. High confidence, clear gap
#       between the top candidate and the runner-up.
#
#   H2: BirdNET detected a wrong species from the same genus. Low-to-moderate
#       confidence, small gap.
#
#   H3: BirdNET detected a species from a different genus entirely.
#       Very low confidence, negligible gap.
#
# --- COMPLETE PIPELINE ---
#
#   STEP 1  Fetch reference recordings from Xeno-canto
#   STEP 2  Download audio files
#   STEP 3  Run BirdNET-Analyzer (Python, in Terminal)
#   STEP 4  Read BirdNET results into R
#   STEP 5  Build acoustic reference dataset
#   STEP 6  Train one model per recording type
#   STEP 7  Inspect and save models
#
# --- WORKING DIRECTORY ---
#
# All paths below are relative to TaxaID/ (the monorepo root).
# The script auto-detects whether you are running from TaxaID/ or from
# TaxaLikely/ and sets .taxa_root accordingly. You do not need to change
# your working directory manually.
#
# --- PYTHON SETUP (one-time) ---
#
# BirdNET-Analyzer requires Python 3.9+. Install dependencies once:
#   pip3 install birdnetlib librosa resampy tensorflow
#   brew install ffmpeg
#
# Verify the install worked:
#   python3 -c "import birdnetlib; print('ok')"
#
# ==============================================================================

library(TaxaLikely)
library(TaxaMatch)

# Auto-detect TaxaID root (works whether wd is TaxaID/ or TaxaLikely/)
.taxa_root <- normalizePath(
  if (basename(getwd()) == "TaxaLikely") ".." else ".",
  mustWork = FALSE
)

# ---- STEP 1: Fetch reference recordings from Xeno-canto ---------------------
# Requires a free API key from xeno-canto.org/account.
# Set it once in ~/.Renviron:   XC_API_KEY=your_key_here
# Then restart R.
#
# First run with download = FALSE to confirm counts before downloading.

recs_song <- fetch_reference_recordings(
  species         = c("Turdus migratorius", "Setophaga petechia",
                      "Melospiza melodia", "Zenaida macroura"),
  quality         = c("A", "B"),
  type            = "song",
  max_per_species = 30L,
  download        = FALSE,
  download_dir    = file.path(.taxa_root, "TaxaLikely/reference_audio/song/")
)

cat("Song recordings found:", nrow(recs_song), "\n")
print(table(recs_song$species, recs_song$quality))

# ---- STEP 2: Download audio files -------------------------------------------
# Re-run with download = TRUE once you are happy with the counts.
# Files (~5-15 MB each) are saved to download_dir.

recs_song <- fetch_reference_recordings(
  species         = c("Turdus migratorius", "Setophaga petechia",
                      "Melospiza melodia", "Zenaida macroura"),
  quality         = c("A", "B"),
  type            = "song",
  max_per_species = 30L,
  download        = TRUE,
  download_dir    = file.path(.taxa_root, "TaxaLikely/reference_audio/song/")
)

# Drop recordings where the download failed (NA local_path).
# These will have no audio and no BirdNET results; keeping them causes
# an error in build_acoustic_reference().
n_failed <- sum(is.na(recs_song$local_path))
if (n_failed > 0L) {
  message(sprintf("Dropping %d recording(s) with failed downloads.", n_failed))
  recs_song <- recs_song[!is.na(recs_song$local_path), ]
}

cat("Downloaded:", nrow(recs_song), "recordings\n")
saveRDS(recs_song, file.path(.taxa_root, "TaxaLikely/recs_song.rds"))

# ---- STEP 3: Run BirdNET-Analyzer (Python, in Terminal) ---------------------
# BirdNET-Analyzer processes audio files and outputs one CSV per file with
# columns: Start (s), End (s), Scientific name, Common name, Confidence.
#
# Write the Python script from R, then run it from a Terminal window.
# Do NOT use system() -- R's working directory and the terminal's working
# directory can differ, causing confusing path errors.
#
# Step 3a: Write the script
writeLines(
  c(
    "from birdnetlib import Recording",
    "from birdnetlib.analyzer import Analyzer",
    "import os, csv",
    "",
    'audio_dir  = "TaxaLikely/reference_audio/song/"',
    'result_dir = "TaxaLikely/birdnet_results/song/"',
    "os.makedirs(result_dir, exist_ok=True)",
    "",
    "analyzer = Analyzer()",
    "files = [f for f in os.listdir(audio_dir)",
    '         if f.lower().endswith((".mp3", ".wav", ".flac", ".ogg"))]',
    'print(f"Processing {len(files)} files...")',
    "for i, fname in enumerate(files, 1):",
    '    print(f"  [{i}/{len(files)}] {fname}")',
    "    rec = Recording(analyzer, os.path.join(audio_dir, fname),",
    "                    lat=37.5, lon=-122.0, min_conf=0.0)",
    "    rec.analyze()",
    "    out = os.path.join(result_dir,",
    "                       os.path.splitext(fname)[0] + '.BirdNET.results.csv')",
    '    with open(out, "w", newline="") as f:',
    "        w = csv.writer(f)",
    '        w.writerow(["Start (s)", "End (s)", "Scientific name",',
    '                    "Common name", "Confidence"])',
    "        for d in rec.detections:",
    '            w.writerow([d["start_time"], d["end_time"],',
    '                        d["scientific_name"], d["common_name"],',
    '                        d["confidence"]])',
    'print("Done.")'
  ),
  file.path(.taxa_root, "run_birdnet.py")
)
message("run_birdnet.py written to: ", .taxa_root)
message("Now open a Terminal, cd to that directory, and run:")
message("  python3 run_birdnet.py")

# Step 3b: Run in Terminal (not from R):
#   cd "/path/to/TaxaID"   # the .taxa_root path printed above
#   python3 run_birdnet.py
#
# The script prints progress ([1/120], [2/120], ...) and takes a few minutes.
# On first run it downloads the BirdNET neural network model (~100 MB).

# ---- STORAGE NOTE: delete audio files after BirdNET processing --------------
# Once BirdNET has processed the audio, the .mp3 files are no longer needed.
# Verify the CSV output is complete first:
# length(list.files(file.path(.taxa_root, "TaxaLikely/birdnet_results/song/"),
#                   pattern = "\\.csv$"))
#
# Then delete:
# audio_files <- list.files(file.path(.taxa_root, "TaxaLikely/reference_audio/song/"),
#                            full.names = TRUE,
#                            pattern = "\\.(mp3|wav|flac|ogg)$")
# file.remove(audio_files)
# message("Deleted ", length(audio_files), " audio files.")
#
# Keep recs_song.rds -- build_acoustic_reference() uses only the file stem as
# the join key, so stale local_path values are not a problem.

# ---- STEP 4: Read BirdNET detections into R ---------------------------------
# top_n >= 2 is required for gap computation in train_likelihood_model().

birdnet_song <- read_birdnet_output(
  file.path(.taxa_root, "TaxaLikely/birdnet_results/song/"),
  min_confidence = 0.0,
  top_n          = 3L
)
# Note: recordings with no detections produce an informational message and
# are skipped; this is normal for short or quiet recordings.

cat("BirdNET detections:", nrow(birdnet_song), "\n")
cat("Time windows:", length(unique(birdnet_song$observation_id)), "\n")
cat("Files processed:", length(unique(birdnet_song$source_file)), "\n")

# ---- STEP 5: Build acoustic reference dataset -------------------------------
# Joins BirdNET detections to Xeno-canto ground truth. Produces pair-format
# data frame (.x/.y suffixes) compatible with train_likelihood_model().
#
# exclude_background = TRUE drops detections of species listed in
# recs_song$also_species (background species audible in the recording).
# These are not H2/H3 errors -- they are correctly identified background birds.

ref_pairs_song <- build_acoustic_reference(
  birdnet_df         = birdnet_song,
  recordings_meta    = recs_song,
  rank_system        = c("genus", "species"),
  min_confidence     = 0.0,
  exclude_background = TRUE
)

cat("\n--- Reference pair dataset ---\n")
cat("Total pairs:", nrow(ref_pairs_song), "\n")
n_h1 <- sum(ref_pairs_song$species.x == ref_pairs_song$species.y, na.rm = TRUE)
cat("H1 (correct species):", n_h1, "\n")
cat("H2/H3 (wrong species):", nrow(ref_pairs_song) - n_h1, "\n")

# Inspect recording type breakdown.
# Xeno-canto types are often multi-valued (e.g., "call, song", "song, growl song").
# Pure "song" recordings are the cleanest training set for a song model.
cat("\nRecording type breakdown:\n")
print(sort(table(ref_pairs_song$testid), decreasing = TRUE))

saveRDS(ref_pairs_song, file.path(.taxa_root, "TaxaLikely/ref_pairs_song.rds"))

# ---- STEP 6: Train one model per recording type -----------------------------
# Filter to exact type matches before training. This keeps the within-species
# score distribution tight, giving the model maximum discrimination power.

song_pairs <- subset(ref_pairs_song, testid == "song")
cat("\nPure song training pairs:", nrow(song_pairs), "\n")
cat("H1:", sum(song_pairs$species.x == song_pairs$species.y, na.rm = TRUE), "\n")
cat("H2/H3:", sum(song_pairs$species.x != song_pairs$species.y, na.rm = TRUE), "\n")

model_song <- train_likelihood_model(
  raw_df        = song_pairs,
  rank_system   = c("genus", "species"),
  prior_weight  = 10.0,
  use_hierarchy = TRUE
)

interp_song <- interpret_model(model_song)

# ---- STEP 7: Inspect and save models ----------------------------------------
cat("\n--- Song model stats ---\n")
cat("Species in model:", model_song$Stats$n_species, "\n")
cat("Singletons:", model_song$Stats$n_singletons, "\n")
cat("Anchor rows:", model_song$Stats$n_anchors, "\n")

cat("\n--- Song model: hypothesis baselines ---\n")
print(interp_song$hypothesis_baselines)

# Interpretation notes:
#
# expected_match_pct is on a logit-transformed scale, not raw BirdNET
# confidence. The key diagnostic is the GAP metric:
#
#   - H1 gap >> H2 gap: the model can reliably distinguish a correct
#     detection (large gap between top and runner-up) from a wrong detection
#     (small gap). This is good even if the absolute confidence values are low.
#
#   - If H1 expected_gap_pct is near zero, BirdNET rarely produces a clear
#     winner for this species -- consider more training recordings.
#
# mu_score on the logit scale: values below 0 correspond to raw confidence
# below 50%, which indicates BirdNET struggles with this species' song.
# The gap (mu_gap) compensates: a species with modest absolute confidence
# but a consistently large gap is still reliably identified.

low_quality <- model_song$H1_Lookup[
  model_song$H1_Lookup$rank == "species" &
    model_song$H1_Lookup$mu_score < 0.0, ]
if (nrow(low_quality) > 0L) {
  cat("\nSpecies with low expected H1 logit score (<0); consider more recordings:\n")
  print(low_quality[, c("lookup_key", "mu_score", "mu_gap")])
}

saveRDS(model_song, file.path(.taxa_root, "TaxaLikely/model_song.rds"))
message("Saved ", file.path(.taxa_root, "TaxaLikely/model_song.rds"))

# ---- (Optional) Additional type models --------------------------------------
# Repeat Steps 6-7 for other types if needed. For example, to train a
# model on "call, song" recordings (mixed but common in Xeno-canto):
#
# mixed_pairs <- subset(ref_pairs_song, testid == "call, song")
# model_mixed <- train_likelihood_model(
#   raw_df        = mixed_pairs,
#   rank_system   = c("genus", "species"),
#   prior_weight  = 10.0
# )
# saveRDS(model_mixed, file.path(.taxa_root, "TaxaLikely/model_mixed.rds"))

# ---- STEP 8: Validate model on reference detections -------------------------
# Apply the trained model back to the same recordings used for training.
# This is an optimistic (in-sample) sanity check, not a held-out test. Its
# purpose is to confirm that the model has learned a sensible score-likelihood
# mapping before applying it to field data.
#
# What good results look like:
#   - Blue points (correct detections) rise steeply with BirdNET confidence
#     and cluster above the 0.90 likelihood threshold.
#   - Red points (wrong detections) stay below 0.50 or at most scatter in the
#     0.50-0.90 band. A few red points above 0.90 are expected for acoustically
#     similar species that BirdNET cannot reliably separate.
#   - Point size (1 - CV) should be largest for blue high-likelihood points,
#     indicating confident assignments. Small points anywhere indicate that the
#     Monte Carlo simulations disagreed -- usually near decision thresholds.
#
# The confusion heatmap (Plot 2) reveals which species pairs drive errors.
# Columns are ordered by total confusion frequency, so the worst offenders
# appear on the left. A cell value of 0.30 means 30% of true-species detections
# were misidentified as the column species.
#
# This is NOT the field-data workflow -- see Workflow 4 for that.
# For field recordings: run BirdNET on your audio, feed the output through
# read_birdnet_output() + standardize_match_data(), then use Workflow 4.

library(TaxaMatch)
library(ggplot2)

match_df <- standardize_match_data(
  birdnet_song,
  observation_id_col = "observation_id",
  score_col          = "score",
  rank_system        = c("genus", "species")
)

model <- readRDS(file.path(.taxa_root, "TaxaLikely/model_song.rds"))

lik_result <- evaluate_likelihoods(
  match_df     = match_df,
  model_params = model,
  rank_system  = c("genus", "species"),
  n_sims       = 200L
)

likelihoods <- lik_result$likelihoods
cat("Likelihood rows:", nrow(likelihoods), "\n")
cat("Hypothesis types:\n")
print(table(likelihoods$hypothesis_type))

# Score-vs-likelihood plot: H1 likelihoods should rise with BirdNET score.
# Points are coloured by whether BirdNET detected the correct species (blue)
# or a wrong species for that recording (red). Red points with high score AND
# high likelihood indicate species pairs BirdNET routinely confuses.

# Join likelihoods to BirdNET scores
top_h1 <- likelihoods[likelihoods$hypothesis_type == "specific_candidate", ]
top_h1 <- merge(top_h1, match_df[, c("observation_id", "taxon_name", "score")],
                by = c("observation_id", "taxon_name"))

# Recover ground-truth species for each observation window.
# ref_pairs_song uses id_x for the window ID and species.x for the
# Xeno-canto ground-truth label; rename to match top_h1 columns.
gt <- unique(ref_pairs_song[, c("id_x", "species.x")])
names(gt) <- c("observation_id", "true_species")
top_h1 <- merge(top_h1, gt, by = "observation_id", all.x = TRUE)

# Flag detections where BirdNET's candidate != true species
top_h1$correct <- !is.na(top_h1$true_species) &
                  (top_h1$taxon_name == top_h1$true_species)

if (nrow(top_h1) > 0L) {

  lik_hi <- 0.90    # high-confidence threshold
  lik_lo <- 0.50    # decision boundary

  # Pre-transform: asin(x) stretches both ends while keeping the middle linear.
  # Bounded at pi/2 (~1.57), so perfect matches stay on the plot.
  ticks_raw  <- c(0, 0.25, 0.50, 0.75, 0.90, 0.95, 0.99)
  ticks_tr   <- asin(ticks_raw)
  top_h1$lik_tr   <- asin(top_h1$likelihood_mean)
  top_h1$score_tr <- asin(top_h1$score)
  # Confidence = 1 - CV (coefficient of variation). High mean + low SD -> near 1.
  # Clamped to [0,1]: CV can exceed 1 when mean is near 0.
  top_h1$conf <- pmax(0, 1 - top_h1$likelihood_sd /
                           pmax(top_h1$likelihood_mean, 0.01))
  top_h1$label  <- factor(
    ifelse(is.na(top_h1$correct), "Unknown",
           ifelse(top_h1$correct, "Correct", "Wrong")),
    levels = c("Correct", "Wrong", "Unknown"))

  # ---- Plot 1: score vs H1 likelihood ----------------------------------------
  p1 <- ggplot(top_h1,
               aes(x = score_tr, y = lik_tr,
                   colour = label, size = conf)) +
    geom_point(shape = 21, fill = NA, alpha = 0.85) +
    geom_hline(yintercept = asin(lik_hi), linetype = "dashed",
               colour = "grey35", linewidth = 0.6) +
    geom_hline(yintercept = asin(lik_lo), linetype = "dotted",
               colour = "grey55") +
    annotate("text", x = Inf, y = asin(lik_hi), label = " 0.90",
             hjust = 1, vjust = -0.4, size = 3, colour = "grey35") +
    annotate("text", x = Inf, y = asin(lik_lo), label = " 0.50",
             hjust = 1, vjust = -0.4, size = 3, colour = "grey55") +
    scale_colour_manual(
      values = c("Correct" = "steelblue", "Wrong" = "red2",
                 "Unknown" = "grey70"),
      name = NULL) +
    scale_size_continuous(range = c(0.4, 4),
                          name  = "Confidence\n(1 \u2212 CV)") +
    scale_y_continuous(breaks = ticks_tr, labels = ticks_raw,
                       name = "H1 likelihood (mean)") +
    scale_x_continuous(breaks = ticks_tr, labels = ticks_raw,
                       name = "BirdNET confidence (arcsine scale)") +
    labs(title    = "Score vs H1 likelihood",
         subtitle = "Point size = confidence (1 \u2212 CV); both axes on arcsine scale") +
    theme_bw(base_size = 11) +
    theme(legend.position = "right")
  print(p1)

  # Threshold summary
  n_hi_tot   <- sum(top_h1$likelihood_mean >= lik_hi, na.rm = TRUE)
  n_hi_wrong <- sum(top_h1$label == "Wrong" &
                    top_h1$likelihood_mean >= lik_hi, na.rm = TRUE)
  cat(sprintf(
    "\nAbove %.0f%% likelihood: %d detections, %d wrong (%.1f%%)\n",
    lik_hi * 100, n_hi_tot, n_hi_wrong,
    if (n_hi_tot > 0L) 100 * n_hi_wrong / n_hi_tot else 0))
  if (n_hi_wrong > 0L)
    cat("  Red points above 0.90 are acoustically confusable pairs;\n",
        "  the model cannot distinguish them from correct H1 detections.\n")

  # ---- Confusion table -------------------------------------------------------
  n_correct <- sum(top_h1$correct,  na.rm = TRUE)
  n_wrong   <- sum(!top_h1$correct, na.rm = TRUE)
  cat(sprintf("\nDetections: %d correct, %d wrong (%.1f%% error rate)\n",
              n_correct, n_wrong,
              100 * n_wrong / max(n_correct + n_wrong, 1L)))

  if (n_wrong > 0L) {
    has_gt     <- !is.na(top_h1$true_species)
    conf_mat   <- table(true     = top_h1$true_species[has_gt],
                        detected = top_h1$taxon_name[  has_gt])
    row_totals <- rowSums(conf_mat)
    conf_prop  <- conf_mat / row_totals

    wrong <- top_h1[top_h1$label == "Wrong" & !is.na(top_h1$label), ]
    tbl   <- as.data.frame(sort(
               table(paste0(wrong$true_species, " -> ", wrong$taxon_name)),
               decreasing = TRUE))
    names(tbl) <- c("confusion_pair", "n")
    tbl$true_sp     <- sub(" -> .*", "", tbl$confusion_pair)
    tbl$n_true      <- row_totals[tbl$true_sp]
    tbl$pct_of_true <- round(100 * tbl$n / tbl$n_true, 1L)
    cat("\nConfusion summary (wrong detections only):\n")
    print(tbl[, c("confusion_pair", "n", "n_true", "pct_of_true")],
          row.names = FALSE)

    sp_both   <- intersect(rownames(conf_prop), colnames(conf_prop))
    diag_vals <- diag(conf_prop[sp_both, sp_both, drop = FALSE])

    # ---- Plot 2: off-diagonal confusion heatmap ------------------------------
    off_mat        <- conf_prop
    diag(off_mat)  <- 0
    col_ord        <- order(colSums(off_mat), decreasing = TRUE)
    off_plot       <- off_mat[, col_ord, drop = FALSE]

    if (any(off_plot > 0)) {
      off_long <- as.data.frame(as.table(off_plot))
      names(off_long) <- c("true_species", "detected", "proportion")
      off_long$proportion <- as.numeric(off_long$proportion)
      off_long$detected   <- factor(off_long$detected,
                                    levels = colnames(off_plot))

      p2 <- ggplot(off_long,
                    aes(x = detected, y = true_species, fill = proportion)) +
        geom_tile(colour = "grey85", linewidth = 0.3) +
        geom_text(data  = subset(off_long, proportion > 0.01),
                  aes(label  = sprintf("%.2f", proportion),
                      colour = proportion > 0.15),
                  size = 3, show.legend = FALSE) +
        scale_fill_gradient(low = "white", high = "#b2182b",
                            name = "Proportion", na.value = "white") +
        scale_colour_manual(values = c("TRUE"  = "white",
                                       "FALSE" = "grey25")) +
        labs(x        = "Falsely detected as",
             y        = "True species",
             title    = "Off-diagonal confusion",
             subtitle = "Columns ordered by confusion frequency") +
        theme_bw(base_size = 11) +
        theme(axis.text.x = element_text(angle = 45, hjust = 1, size = 9),
              axis.text.y = element_text(size = 9))
      print(p2)
    }
  }
}

# ---- Next step --------------------------------------------------------------
# For field recordings, run Workflow 4 directly.
# Pass match_df (built from your field BirdNET output) and model_song.
# Skip Section 2 of Workflow 4 (remove_flagged_references -- DNA only).
# Use rank_system = c("genus", "species") throughout.

message("\nWorkflow 3b complete.")
message("Next: Workflow 4 (convert BirdNET scores to likelihoods for field data)")
