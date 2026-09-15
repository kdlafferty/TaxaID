# Edge: taxa -> occurrences
# Source: TaxaFetch/inst/GBIF_workflow.R + Define_search_workflow.R

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
message("Fetched ", nrow(occurrences), " occurrence records")
occurrences
