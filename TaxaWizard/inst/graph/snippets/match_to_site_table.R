# Edge: match_df -> site_table
# Source: TaxaMatch build_site_table() + group_observations_by_bbox()
# NOTE: build_site_table() reads embedded lat/lng columns from {{input_var}}
#   directly if present (e.g. image EXIF GPS). If your data has no embedded
#   coordinates, join a separate site metadata table first via
#   TaxaMatch::join_event_site_metadata(detections = {{input_var}},
#   site_metadata = <your site table>) and pass its output as site_df below.
# NOTE: group_observations_by_bbox() is interactive (draws polygons in a
#   Shiny gadget) -- it groups observations you haven't already assigned to
#   a site. If group membership is already known from metadata (e.g. a
#   "site_id" column), use TaxaMatch::assign_spatial_group() instead, which
#   needs no interaction.

site_table <- TaxaMatch::build_site_table(
  match_df = {{input_var}},
  site_df  = {{site_df}}
)

message(
  "Built site table: ", nrow(site_table), " observations."
)

# Interactively draw group boundaries. Cancel the gadget once every
# observation you want grouped has been assigned -- anything left ungrouped
# becomes its own single-observation spatial_group_id automatically.
site_table <- TaxaMatch::group_observations_by_bbox(site_table)

message(
  "Assigned ", length(unique(site_table$spatial_group_id)),
  " spatial group(s) across ", nrow(site_table), " observations."
)
site_table
