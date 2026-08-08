# ==============================================================================
# TaxaFlag -- run_all_functions.R
#
# Exercises every exported function in the TaxaFlag package, in dependency
# order, against small synthetic data. Intended for a code reviewer to run
# top to bottom and confirm the package installs and works end to end --
# not a substitute for `devtools::test()` (the real, exhaustive test suite).
#
# Network calls: check_gbif_tile_range() and the optional live
# TaxaFetch::check_inat_range() fallback inside review_spatial_context()
# both need internet access to GBIF/iNaturalist's public APIs (no API key
# required). Both are wrapped in tryCatch() with a clear message if offline.
#
# LLM calls: review_assignments() and review_spatial_context()'s "Run AI
# Review" button both need a real LLM call by design. This script uses a
# small canned `llm_fn` stub by default so the whole script runs without an
# API key -- see the REAL_LLM section below to swap in a real provider.
# ==============================================================================

.libPaths(c(path.expand(Sys.getenv("R_LIBS_USER")), .libPaths()))
library(TaxaFlag)

cat("\n== TaxaFlag", as.character(utils::packageVersion("TaxaFlag")), "==\n")
cat("Installed at:", dirname(find.package("TaxaFlag")), "\n\n")

# ------------------------------------------------------------------------
# 1. flag_contaminant() -- lab/field contamination screening
# ------------------------------------------------------------------------
cat("--- 1. flag_contaminant() ---\n")

reads_long <- data.frame(
  event_id   = c("s1", "s1", "s2", "s2", "blank1", "blank1", "s3", "s3"),
  taxon_name = c("Oncorhynchus mykiss", "Homo sapiens",
                 "Oncorhynchus mykiss", "Homo sapiens",
                 "Homo sapiens", "Oncorhynchus mykiss",
                 "Oncorhynchus mykiss", "Homo sapiens"),
  n_reads    = c(50000, 20, 42000, 15, 8000, 5, 61000, 30),
  stringsAsFactors = FALSE
)

contaminant_flags <- flag_contaminant(
  input_df         = reads_long,
  control_samples  = "blank1",
  contaminant_type = "lab_contaminant"
)
print(contaminant_flags)
stopifnot(all(c("observation_validity", "validity_flag", "validity_reason") %in%
                names(contaminant_flags)))

# ------------------------------------------------------------------------
# 2. flag_handler() -- temporal proximity to sampling-period edges
# ------------------------------------------------------------------------
cat("\n--- 2. flag_handler() ---\n")

camera_detections <- data.frame(
  station    = c("A", "A", "A", "A", "B", "B", "B"),
  datetime   = as.POSIXct(c(
    "2025-06-15 08:00:00", "2025-06-15 08:20:00", "2025-06-15 10:30:00",
    "2025-06-15 11:00:00",
    "2025-06-16 09:00:00", "2025-06-16 09:15:00", "2025-06-16 09:45:00"
  )),
  taxon_name = c("Homo sapiens", "Odocoileus virginianus", "Lynx rufus",
                 "Homo sapiens", "Odocoileus virginianus", "Procyon lotor",
                 "Odocoileus virginianus"),
  stringsAsFactors = FALSE
)

handler_flags <- flag_handler(
  camera_detections,
  group_col        = "station",
  interval_minutes = 30,
  handler_taxa     = "Homo sapiens"
)
print(handler_flags)
stopifnot(identical(handler_flags$station, camera_detections$station))  # row order preserved

# ------------------------------------------------------------------------
# 3. add_posthoc_assessment() -- occurrence plausibility + discrimination
# ------------------------------------------------------------------------
cat("\n--- 3. add_posthoc_assessment() ---\n")

consensus_df <- data.frame(
  observation_id    = c("obs1", "obs2", "obs3"),
  consensus_taxon   = c("Oncorhynchus mykiss", "Felis catus", "Rare sp."),
  consensus_rank    = c("species", "species", "species"),
  winner_likelihood = c(0.95, 0.90, 0.60),
  winner_theta_mean = c(0.02, 0.0002, NA),
  winner_has_occurrence_record = c(TRUE, TRUE, FALSE),
  stringsAsFactors  = FALSE
)

assessed <- add_posthoc_assessment(
  consensus_df,
  domestic_taxa             = "Felis catus",
  expected_theta_threshold  = c(species = 0.008)
)
print(assessed[, c("consensus_taxon", "primary_plausibility", "domestic_prior_caveat")])
stopifnot("primary_plausibility" %in% names(assessed))

# ------------------------------------------------------------------------
# 4. build_review_covariates() -- per-observation covariates for modelling
# ------------------------------------------------------------------------
cat("\n--- 4. build_review_covariates() ---\n")

reads_for_covariates <- data.frame(
  ESVId    = c("obs1", "obs1", "obs2", "obs2", "obs3"),
  sequence = c("ACGTACGT", "ACGTACGT", "ACGT", "ACGT", "ACGTACGTAC"),
  event_id = c("s1", "s2", "s1", "s2", "s3"),
  n_reads  = c(50000, 42000, 20, 15, 200),
  stringsAsFactors = FALSE
)
cls_for_covariates <- data.frame(
  observation_id        = assessed$observation_id,
  primary_plausibility   = assessed$primary_plausibility,
  stringsAsFactors = FALSE
)

covariates <- build_review_covariates(
  reads_for_covariates, cls_for_covariates
)
print(covariates)
stopifnot(nrow(covariates) == nrow(assessed))

# ------------------------------------------------------------------------
# 5. report_flags() -- Methods/Results section from flagged data
# ------------------------------------------------------------------------
cat("\n--- 5. report_flags() ---\n")

flag_section <- report_flags(contaminant_flags, verbose = FALSE)
print(flag_section)
stopifnot(inherits(flag_section, "report_section"))

# ------------------------------------------------------------------------
# 6. compute_local_occurrence_distance() -- free, local, exact spatial context
# ------------------------------------------------------------------------
cat("\n--- 6. compute_local_occurrence_distance() ---\n")

occurrences_clean <- data.frame(
  taxon_name       = c("Oncorhynchus mykiss", "Oncorhynchus mykiss", "Felis catus"),
  decimalLatitude  = c(41.68, 41.60, 34.40),
  decimalLongitude = c(-87.14, -87.30, -119.70),
  stringsAsFactors = FALSE
)

local_dist <- compute_local_occurrence_distance(
  taxon_names     = c("Oncorhynchus mykiss", "Rare sp."),
  query_lat       = 41.67, query_lon = -87.15,
  occurrence_data = occurrences_clean
)
print(local_dist)
stopifnot(nrow(local_dist) == 2L)

# ------------------------------------------------------------------------
# 7. check_gbif_tile_range() -- cheap, global spatial context (real network call)
# ------------------------------------------------------------------------
cat("\n--- 7. check_gbif_tile_range() ---\n")

gbif_tile_result <- tryCatch(
  check_gbif_tile_range(
    taxon_key = 5204019,  # Oncorhynchus mykiss, GBIF backbone usageKey (verified live via /v1/species/match)
    query_lat = 41.67, query_lon = -87.15
  ),
  error = function(e) {
    message("  (skipped -- needs internet access to api.gbif.org: ", conditionMessage(e), ")")
    NULL
  }
)
if (!is.null(gbif_tile_result)) print(gbif_tile_result)

# ------------------------------------------------------------------------
# 8. review_assignments() -- LLM expert review (stubbed llm_fn by default)
# ------------------------------------------------------------------------
cat("\n--- 8. review_assignments() ---\n")

# A minimal canned llm_fn so this script runs end to end with no API key.
# To exercise a REAL LLM call instead, replace this with:
#   llm_fn = getOption("TaxaID.llm_fn", TaxaTools::call_api)
.stub_llm_fn <- function(prompt, ...) {
  taxa_in_prompt <- regmatches(prompt, gregexpr("(?<=^- )[A-Za-z. ]+(?= \\()", prompt, perl = TRUE))[[1]]
  # Fallback: pull taxon names straight out of the TAXA TO REVIEW block
  lines <- strsplit(prompt, "\n")[[1]]
  taxa_lines <- grep("^- ", lines, value = TRUE)
  taxa <- sub("^- ([^()]+?)\\s*(\\(.*\\))?$", "\\1", taxa_lines)
  taxa <- trimws(taxa)
  entries <- vapply(taxa, function(tx) {
    sprintf(paste0(
      '{"taxon_name": %s, "habitat_plausibility": "likely", ',
      '"geographic_plausibility": "likely", "scope_plausibility": null, ',
      '"contamination_risk": "low", "review_alternatives": null, ',
      '"review_lower_hypotheses": null, "review_confidence": "moderate", ',
      '"review_comment": "Stub review for demonstration purposes."}'
    ), jsonlite::toJSON(tx))
  }, character(1))
  paste0("[", paste(entries, collapse = ","), "]")
}

reviewed <- review_assignments(
  input_df     = consensus_df,
  taxon_col    = "consensus_taxon",
  context      = list(geography = "Lake Michigan, Illinois", habitat = "nearshore"),
  target_group = "fish",
  llm_fn       = .stub_llm_fn,
  verbose      = FALSE
)
print(reviewed[, c("consensus_taxon", "habitat_plausibility", "review_confidence")])
stopifnot("habitat_plausibility" %in% names(reviewed))

# ------------------------------------------------------------------------
# 9. review_spatial_context() -- interactive Shiny/leaflet gadget
# ------------------------------------------------------------------------
cat("\n--- 9. review_spatial_context() ---\n")

if (interactive()) {
  cat("  Launching interactive gadget (close its window to continue)...\n")
  review_spatial_context(
    input_df         = consensus_df,
    query_lat        = 41.67, query_lon = -87.15,
    taxon_col        = "consensus_taxon",
    plausibility_col = NULL,
    occurrence_data  = occurrences_clean,
    live_inat_check  = FALSE
  )
} else {
  # Non-interactive fallback: drives the SAME reactive server logic the
  # gadget uses via shiny::testServer() (this package's own test strategy
  # for this file -- see tests/testthat/test-review_spatial_context.R),
  # confirming the gadget's internals work without needing a live browser.
  cat("  Non-interactive session: exercising the gadget's server logic via",
      "shiny::testServer() instead of launching the UI.\n")
  server <- TaxaFlag:::.build_spatial_context_server(
    input_df = consensus_df, query_lat = 41.67, query_lon = -87.15,
    taxon_col = "consensus_taxon", plausibility_col = NULL,
    all_taxa = sort(unique(consensus_df$consensus_taxon)), plaus_choices = NULL,
    occurrence_data = occurrences_clean, excluded_occurrence_data = NULL,
    occurrence_taxon_col = "taxon_name", occurrence_lat_col = "decimalLatitude",
    occurrence_lon_col = "decimalLongitude",
    inat_range = NULL, inat_taxon_col = "taxon_name",
    live_inat_check = FALSE, inat_cache_dir = NULL, inat_radius_km = 500,
    context = NULL, target_group = NULL, marker = NULL, llm_fn = .stub_llm_fn,
    tile = "CartoDB.Positron", gbif_style = "classic.point",
    gbif_bin_size = 256L, gbif_year_range = NULL
  )
  shiny::testServer(server, {
    session$setInputs(taxon = "Oncorhynchus mykiss")
    stats_html <- output$stats_panel$html
    cat("  stats_panel rendered", nchar(stats_html), "characters of HTML -- OK\n")
    stopifnot(nchar(stats_html) > 0)
  })
}

cat("\n== All 9 TaxaFlag functions ran successfully. ==\n")
