# Edge: taxa -> occurrences (with geographic-outlier screening)
# Source: TaxaFetch/inst/GBIF_workflow.R + check_geographic_outliers()
# NOTE: check_geographic_outliers() requires the CoordinateCleaner package.
#   For species with few LOCAL records (< min_local_n), it fetches that
#   species' GLOBAL GBIF distribution and flags local records that are
#   geographic outliers against it (e.g. one mis-georeferenced citizen-
#   science record from the wrong continent). Well-supported local species
#   are skipped -- only sparse-locally species pay the extra global-fetch
#   cost.

keys <- TaxaFetch::get_keys_from_context({{input_var}})
bbox_wkt <- TaxaFetch::make_bbox_wkt(
  lat = {{lat}}, lon = {{lon}},
  radius_deg = {{search_radius_deg}}
)
# GBIF_LIMIT WARNING. `limit` caps records PER TAXON KEY, and what survives is
# GBIF's own return order -- a non-random prefix, not a sample. Measured on real
# data: at limit = 10000, 45 of 231 Mugu taxa and 110 of 666 PtConception taxa
# sat exactly at the cap, and because each species' first 10,000 records came
# from the same few large multi-species surveys, every capped taxon emerged with
# an IDENTICAL spatial distribution (per-species median distance 104 km, IQR
# 104-104, against 81-217 for uncapped taxa). Both abundance and spatial pattern
# were then truncation artifacts. Prefer {{gbif_limit}} = NULL. Note this
# function has no on_cap guard -- TaxaFetch::get_gbif_occurrences() does, but it
# routes to the download API above 50 keys, which needs a GBIF account.
occurrences <- TaxaFetch::fetch_gbif_occurrences(
  keys       = keys,
  geometry   = bbox_wkt,
  year_range = {{year_range}},
  limit      = {{gbif_limit}},
  # Project-local cache, beside the checkpoints it feeds, rather than the
  # hidden tools::R_user_dir("TaxaFetch", "cache") default. GBIF zips are the
  # largest artefact this ecosystem produces -- 23 GB and 17 GB incidents,
  # 38 zips at 17.0 GB against 52 MB for every other cache file combined --
  # and being invisible from the project is why they went unnoticed.
  cache_dir  = {{gbif_cache_dir}}
)
occurrences <- TaxaFetch::filter_gbif_quality(occurrences)
occurrences <- TaxaFetch::dedupe_occurrences(occurrences)

occurrences <- TaxaFetch::check_geographic_outliers(
  local_occurrences = occurrences,
  year_range        = {{year_range}},
  # Caches the per-species VERDICT, not the global cloud. Without it every
  # re-run re-fetches a global distribution per sparse species -- the pass
  # that earned a GBIF rate-limit block at 360 of 829 keys on 2026-09-05.
  cache_dir         = {{gbif_cache_dir}}
)
n_outliers <- sum(occurrences$outlier_status == "outlier", na.rm = TRUE)
if (n_outliers > 0L) {
  message("Removing ", n_outliers, " geographic-outlier record(s)")
  occurrences <- occurrences[occurrences$outlier_status != "outlier", , drop = FALSE]
}

message("Fetched ", nrow(occurrences), " occurrence records (geographic-outlier screened)")
occurrences
