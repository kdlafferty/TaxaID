# =============================================================================
# TaxaFetch GBIF workflow
# =============================================================================
#
# INPUT:  A list of taxonomic groups (and hierarchy) in GBIF backbone,
#         a location and scale to search, and year range.
#
# OUTPUT: Filtered occurrence results from GBIF.
#
# DEPENDENCIES:
#   TaxaTools, dplyr
#
# =============================================================================

library(TaxaTools)
library(TaxaFetch)
library(dplyr)
library(rgbif)



# =============================================================================
# 0.  USER INPUTS  -- edit this section only
# =============================================================================

# --- Study area ---------------------------------------------------------------
study_lat    <- 34.5        # centre latitude  (decimal degrees)
study_lon    <- -120.5      # centre longitude (decimal degrees)
study_radius <- 2         # search radius    (decimal degrees, ~330 km)

# --- GBIF search expansion ----------------------------------------------------
# Expand the GBIF query to all species within this rank that are represented
# in the TaxaMatch output. E.g., "family" fetches all family members, not
# just the exact species in the sample. This captures co-occurring species
# that inform the occupancy model even if they were not in the sample.

# --- search settings -----------------------------------------------------------
gbif_limit    <- 10000L        # max GBIF records to fetch
year_range    <- "2020,2025"   # GBIF year filter
higher_taxa_to_search<-tibble(genus=c("Eucyclogobius", "Gillichthys")) #must be in GBIF backbone for this to work.

# =============================================================================
# 2.  RESOLVE GBIF USAGE KEYS
# =============================================================================

message("\n--- Step 2: Resolving GBIF usage keys ---")

taxa_with_keys <- TaxaFetch::get_keys_from_context(higher_taxa_to_search)

valid_keys <- taxa_with_keys$usageKey[!is.na(taxa_with_keys$usageKey)]
message(sprintf("  %d valid GBIF key(s) resolved.", length(valid_keys)))

if (length(valid_keys) == 0) stop("No GBIF keys resolved. Cannot fetch occurrences.")


# =============================================================================
# 3.  FETCH AND FILTER GBIF OCCURRENCES
# =============================================================================

message("\n--- Step 3: Fetching GBIF occurrences ---")

bbox <- make_bbox_wkt(lat = study_lat, lon = study_lon, radius_deg = study_radius)

raw_gbif_occurrences <- fetch_gbif_occurrences(
  keys       = valid_keys,
  geometry   = bbox,
  year_range = year_range,
  limit      = gbif_limit
)
gbif_occurrences<-raw_gbif_occurrences|>
  filter_gbif_quality(max_coord_decimal_places = 2,max_coord_uncertainty=30000) #exclude low quality records.

if (nrow(gbif_occurrences) == 0) {
  stop("No GBIF records returned. Try increasing study_radius or relaxing year_range.")
}
