# Edge: taxa -> occurrences
# Source: TaxaFetch/inst/GBIF_workflow.R + Define_search_workflow.R

keys <- TaxaFetch::get_keys_from_context({{input_var}})
bbox_wkt <- TaxaFetch::make_bbox_wkt(
  lat = {{lat}}, lon = {{lon}},
  radius_deg = {{search_radius_deg}}
)
occurrences <- TaxaFetch::fetch_gbif_occurrences(
  keys       = keys,
  geometry   = bbox_wkt,
  year_range = {{year_range}},
  limit      = {{gbif_limit}}
)
occurrences <- TaxaFetch::filter_gbif_quality(occurrences)
message("Fetched ", nrow(occurrences), " occurrence records")
occurrences
