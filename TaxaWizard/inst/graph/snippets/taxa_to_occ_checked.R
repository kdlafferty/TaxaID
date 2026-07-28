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
occurrences <- TaxaFetch::fetch_gbif_occurrences(
  keys       = keys,
  geometry   = bbox_wkt,
  year_range = {{year_range}},
  limit      = {{gbif_limit}}
)
occurrences <- TaxaFetch::filter_gbif_quality(occurrences)
occurrences <- TaxaFetch::dedupe_occurrences(occurrences)

occurrences <- TaxaFetch::check_geographic_outliers(
  local_occurrences = occurrences,
  year_range        = {{year_range}}
)
n_outliers <- sum(occurrences$outlier_status == "outlier", na.rm = TRUE)
if (n_outliers > 0L) {
  message("Removing ", n_outliers, " geographic-outlier record(s)")
  occurrences <- occurrences[occurrences$outlier_status != "outlier", , drop = FALSE]
}

message("Fetched ", nrow(occurrences), " occurrence records (geographic-outlier screened)")
occurrences
