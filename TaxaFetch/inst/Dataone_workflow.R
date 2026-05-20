# ==============================================================================
# Dataone_workflow.R
# TaxaFetch — DataONE / PASTA geographic + taxonomic screening + download workflow
#
# Run section-by-section in RStudio (Cmd+Enter or Ctrl+Enter).
# Requires: ANTHROPIC_API_KEY in .Renviron (for LLM stages)
#
# SESSION MANAGEMENT
# ──────────────────
# At the start of every session (or after editing R/ files):
#
#   rm(list = ls())        # wipe GlobalEnv — avoids stale sourced functions
#   devtools::load_all()   # reload all R/ files as a clean package
#
# Never use source("R/...") inside a package project — it leaves stale
# function copies in GlobalEnv that shadow the package versions.
#
# CHECKPOINTS
# ───────────
# Expensive stages (catalog harvest, LLM screening, EML screening) are
# saved to .rds files so they survive rm(list = ls()). Each stage checks
# for its checkpoint before re-running.
#
# Checkpoint files (all in the TaxaFetch project root):
#   pasta_catalog.rds          — Stage 1 output (also the harvest cache)
#   geo_screened.rds           — Stage 4 output: geo-screened tibble
#   taxon_screened.rds         — Stage 6 output: taxon-screened tibble
#   eml_screen.rds             — Stage 8 output: eml_screen tibble
#
# Pipeline:
#   Stage 0  — Clean session + reload
#   Stage 1  — Harvest full PASTA catalog (cached to pasta_catalog.rds)
#   Stage 2  — Build geographic screening prompt
#   Stage 3  — Submit geo prompt to LLM
#   Stage 4  — Parse geo response → save geo_screened.rds
#   Stage 5  — Inspect geo-screened candidates
#   Stage 6  — Build taxonomic screening prompt
#   Stage 7  — Submit taxon prompt to LLM → save taxon_screened.rds
#   Stage 8  — EML pre-screening → save eml_screen.rds
#   Stage 9  — Preview datasets (optional scout)
#   Stage 10 — Download occurrences
#   Stage 11 — Diagnose missed datasets
# ==============================================================================


# ==============================================================================
# STAGE 0 — Clean session + reload
# Run this block at the start of every session and after any R/ file edits.
# ==============================================================================

rm(list = ls())
devtools::load_all()

# ── Define your target area and taxonomic scope ───────────────────────────────
# bbox: c(west, east, south, north) — decimal degrees, western longitudes negative
bbox <- c(-81.2, -80.4, 25.1, 25.8) #florida everglades
bbox <- c(-120.5, -119.3, 33.8, 34.5)   # Santa Barbara Channel

# taxon_scope: plain-language description of the organisms you want

taxon_scope <- "marine fish"   # e.g. "marine invertebrates", "birds", "kelp"
taxon_scope <- "birds"
# Other bbox examples:
# bbox <- c(-119.9, -119.6, 34.3, 34.5)  # Santa Barbara city area (tighter)
# bbox <- c(-122.5, -122.3, 37.7, 37.9)  # San Francisco Bay


# ==============================================================================
# STAGE 1 — Harvest full PASTA catalog
# First run: ~2-5 min. Subsequent runs within max_age_days: instant from cache.
# ==============================================================================

catalog <- harvest_dataone_catalog(
  cache_file   = "pasta_catalog.rds",
  max_age_days = 7,
  verbose      = TRUE
)

nrow(catalog)
table(catalog$is_candidate)
dplyr::count(catalog, scope, sort = TRUE) |> print(n = 20)

candidates <- catalog[catalog$is_candidate, ]
nrow(candidates)


# ==============================================================================
# STAGE 2 — Build geographic screening prompt
# ==============================================================================

geo_prompt <- build_geo_prompt(
  catalog    = catalog,
  bbox       = bbox,
  chunk_size = 80L,
  verbose    = TRUE
)

print(geo_prompt)
geo_prompt$n_items
geo_prompt$n_chunks
cat(geo_prompt$prompts[[1]])   # inspect first chunk


# ==============================================================================
# STAGE 3 — Submit geo prompt to LLM
# ==============================================================================

# Stage 3a — Anthropic API (requires ANTHROPIC_API_KEY in .Renviron):
geo_raw <- prompt_api(geo_prompt, verbose = TRUE)
cat(geo_raw)

# Stage 3b — Manual submission (alternative to 3a):
# info    <- prompt_manual(geo_prompt, out_dir = "geo_screening", prefix = "geo")
# geo_raw <- read_llm_response(info$response_files)


# ==============================================================================
# STAGE 4 — Parse geo response → checkpoint
# ==============================================================================

geo_screened <- parse_geo_screening_response(geo_raw, geo_prompt)
saveRDS(geo_screened, "geo_screened.rds")   # ← checkpoint

table(geo_screened$geo_match)
table(geo_screened$geo_source)

accepted_geo <- geo_screened[geo_screened$geo_match, ]
nrow(accepted_geo)

# Spot-check rejections
geo_screened[!geo_screened$geo_match, ] |>
  dplyr::filter(geo_source == "llm_no") |>
  dplyr::select(id, title, geographicdescription) |>
  dplyr::slice_sample(n = 10)

# ── Resume here after rm(list=ls()) if Stage 4 already ran ───────────────────
# geo_screened <- readRDS("geo_screened.rds")
# accepted_geo <- geo_screened[geo_screened$geo_match, ]


# ==============================================================================
# STAGE 5 — Inspect geo-screened candidates
# ==============================================================================

message(sprintf(
  "\nGeo screening: %d accepted of %d candidates (%d shortcut, %d LLM).",
  nrow(accepted_geo), nrow(geo_screened),
  sum(accepted_geo$geo_source == "shortcut_accepted"),
  sum(accepted_geo$geo_source == "llm_yes")
))

accepted_geo |>
  dplyr::select(id, scope, title, geo_source, geographicdescription) |>
  dplyr::arrange(geo_source, scope) |>
  print(n = 50)


# ==============================================================================
# STAGE 6 — Build taxonomic screening prompt
# Input:  accepted_geo (geo_match == TRUE subset of geo_screened)
# Output: taxon_prompt object ready for LLM submission
# ==============================================================================

taxon_prompt <- build_taxon_screen_prompt(
  catalog     = accepted_geo,
  taxon_scope = taxon_scope,
  chunk_size  = 50L,
  verbose     = TRUE
)

print(taxon_prompt)
cat(taxon_prompt$prompts[[1]])   # inspect first chunk — check framing looks right


# ==============================================================================
# STAGE 7 — Submit taxon prompt to LLM → checkpoint
# ==============================================================================

# Stage 7a — Anthropic API:
taxon_raw <- prompt_api(taxon_prompt, verbose = TRUE)
cat(taxon_raw)

# Stage 7b — Manual submission (alternative to 7a):
# info      <- prompt_manual(taxon_prompt, out_dir = "taxon_screening",
#                             prefix = "taxon")
# taxon_raw <- read_llm_response(info$response_files)

taxon_screened <- parse_taxon_screening_response(taxon_raw, taxon_prompt)
saveRDS(taxon_screened, "taxon_screened.rds")   # ← checkpoint

table(taxon_screened$taxon_match)
table(taxon_screened$taxon_source)

accepted <- taxon_screened[taxon_screened$taxon_match, ]
nrow(accepted)

# Spot-check rejections — verify the LLM is applying the right logic
taxon_screened[!taxon_screened$taxon_match, ] |>
  dplyr::filter(taxon_source == "llm_no") |>
  dplyr::select(id, title) |>
  dplyr::slice_sample(n = 10)

# ── Resume here after rm(list=ls()) if Stage 7 already ran ───────────────────
# geo_screened   <- readRDS("geo_screened.rds")
# accepted_geo   <- geo_screened[geo_screened$geo_match, ]
# taxon_screened <- readRDS("taxon_screened.rds")
# accepted       <- taxon_screened[taxon_screened$taxon_match, ]


# ==============================================================================
# STAGE 8 — EML pre-screening → checkpoint
# Input:  accepted (passed both geo and taxon screens)
# ~0.5s per dataset
# ==============================================================================

eml_screen <- screen_eml_columns(accepted$id, bbox, verbose = TRUE)
saveRDS(eml_screen, "eml_screen.rds")   # ← checkpoint

table(eml_screen$eml_status)
table(eml_screen$eml_pass)

eml_screen |>
  dplyr::select(id, eml_status, eml_bbox_ok,
                has_lat, has_lon, has_species,
                lat_col, lon_col, species_col, n_tables) |>
  print(n = 50)

to_download <- accepted |>
  dplyr::inner_join(eml_screen[eml_screen$eml_pass, ], by = "id")
nrow(to_download)

# ── Resume here after rm(list=ls()) if Stage 8 already ran ───────────────────
# geo_screened   <- readRDS("geo_screened.rds")
# accepted_geo   <- geo_screened[geo_screened$geo_match, ]
# taxon_screened <- readRDS("taxon_screened.rds")
# accepted       <- taxon_screened[taxon_screened$taxon_match, ]
# eml_screen     <- readRDS("eml_screen.rds")
# to_download    <- accepted |>
#   dplyr::inner_join(eml_screen[eml_screen$eml_pass, ], by = "id")


# ==============================================================================
# STAGE 9 — Preview datasets (optional but recommended)
# HEAD + stream n rows per entity; detects DwC join pairs; no full downloads.
# ==============================================================================

prev <- preview_dataone_occurrences(to_download$resolved_id, bbox)
print(prev)

# Inspect a specific dataset's sample rows:
# prev$sample[[1]]

# Cherry-pick fetch set by status:
fetch_ids <- prev |>
  dplyr::filter(status %in% c("ready", "join_ready")) |>
  dplyr::pull(dataset_id) |>
  unique()

length(fetch_ids)


# ==============================================================================
# STAGE 10 — Download and standardize occurrences
# ==============================================================================

dataone_occ <- fetch_dataone_occurrences(fetch_ids, bbox)

# ── Summary ───────────────────────────────────────────────────────────────────
dataone_occ |> dplyr::count(datasetName) |> print(n = 30)
nrow(dataone_occ)
dplyr::glimpse(dataone_occ)


# ==============================================================================
# STAGE 11 — Diagnose missed datasets
# Classifies every entity in every accepted candidate from EML alone (no
# downloads). Shows which datasets still have species data we can't reach
# and why.
# ==============================================================================

all_candidates <- accepted |>
  dplyr::left_join(dplyr::select(eml_screen, id, resolved_id), by = "id")

diagnose_dataset <- function(dataset_id) {
  meta <- TaxaFetch:::.parse_eml_metadata(dataset_id)
  if (is.null(meta)) {
    return(data.frame(dataset_id   = dataset_id,
                      title        = NA_character_,
                      entity       = "(EML failed)",
                      category     = NA_character_,
                      mapped_terms = NA_character_,
                      stringsAsFactors = FALSE))
  }
  rows <- lapply(meta$entities, function(e) {
    col_names <- e$attributes$attributeName
    if (length(col_names) == 0L || all(is.na(col_names))) col_names <- character(0)
    mapping <- if (length(col_names) > 0L)
      TaxaFetch:::.map_columns_to_dwc(col_names, TaxaFetch:::.default_dwc_map) else character(0)
    data.frame(
      dataset_id   = dataset_id,
      title        = substr(meta$title %||% "", 1, 60),
      entity       = substr(e$entity_name %||% "(unnamed)", 1, 40),
      category     = TaxaFetch:::.classify_entity(mapping),
      mapped_terms = if (length(mapping) > 0L)
        paste(sort(unique(mapping[!is.na(mapping)])), collapse = ", ") else "",
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

diag <- do.call(rbind, lapply(all_candidates$resolved_id, function(rid) {
  if (is.na(rid)) return(NULL)
  diagnose_dataset(rid)
}))

# ── Category mix per dataset ──────────────────────────────────────────────────
diag |>
  dplyr::group_by(dataset_id, title) |>
  dplyr::summarise(
    categories = paste(sort(unique(category)), collapse = " + "),
    .groups = "drop"
  ) |>
  print(n = 60)

# ── Stranded datasets: have species but no complete/spatial entity ─────────────
diag |>
  dplyr::group_by(dataset_id) |>
  dplyr::filter(
    !any(category == "complete"),
    any(category %in% c("species_only", "no_coords_no_species"))
  ) |>
  dplyr::ungroup() |>
  dplyr::filter(category %in% c("species_only", "no_coords_no_species")) |>
  dplyr::select(dataset_id, entity, category, mapped_terms) |>
  print(n = 80)
