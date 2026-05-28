#read_birdnet_output() — no data needed, synthetic test:
  library(TaxaMatch)

tmp <- tempfile(fileext = ".BirdNET.results.csv")
write.csv(data.frame(
  "Start (s)"       = c(0.0, 0.0, 3.0),
  "End (s)"         = c(3.0, 3.0, 6.0),
  "Scientific name" = c("Turdus migratorius", "Setophaga petechia",
                        "Turdus migratorius"),
  "Common name"     = c("American Robin", "Yellow Warbler", "American Robin"),
  "Confidence"      = c(0.92, 0.45, 0.87),
  check.names = FALSE
), tmp, row.names = FALSE)

out <- read_birdnet_output(tmp, min_confidence = 0.5)
out
unlink(tmp)

library(TaxaLikely)

#  You can test it now with:
recs <- fetch_reference_recordings(
  species         = c("Turdus migratorius", "Setophaga petechia"),
  quality         = c("A", "B"),
  max_per_species = 5L
)
nrow(recs)  # should be up to 10

# After running BirdNET-Analyzer on reference_audio/:
birdnet_out <- read_birdnet_output("birdnet_results/")

# Join BirdNET detections back to ground-truth species via source_file → local_path
# Label H1 (correct species), H2 (wrong species same genus), H3 (wrong genus)
# Then: train_likelihood_model(labeled_df, rank_system = c("genus", "species"))
#

dir.create("birdnet_results", showWarnings = FALSE)
writeLines(
  c('Start (s),End (s),Scientific name,Common name,Confidence',
    '0.0,3.0,Turdus migratorius,American Robin,0.92',
    '3.0,6.0,Turdus migratorius,American Robin,0.87',
    '9.0,12.0,Melospiza melodia,Song Sparrow,0.61'),
  "birdnet_results/my_recording.BirdNET.results.csv"   # <-- correct name
)
out <- read_birdnet_output("birdnet_results/")
out


recs_dl <- fetch_reference_recordings(
  species         = "Turdus migratorius",
  quality         = "A",
  max_per_species = 3L,
  download        = TRUE,
  download_dir    = "reference_audio/"
)
# 2. Run BirdNET-Analyzer on reference_audio/ (outside R)
# 3. Then:
birdnet_out <- read_birdnet_output("birdnet_results/")
