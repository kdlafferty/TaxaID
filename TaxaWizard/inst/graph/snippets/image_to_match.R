# Edge: image_classifier_output -> match_df
# Source: TaxaMatch read_animl_output() / read_inaturalist_cv_output() /
#         read_wildlife_insights_output()
# Set classifier to one of: "animl", "inaturalist_cv", "wildlife_insights"

.classifier <- {{classifier}}

image_raw <- switch(.classifier,
  animl = TaxaMatch::read_animl_output(
    data           = {{input_var}},
    min_confidence = {{min_confidence}},
    top_n          = {{top_n}}
  ),
  inaturalist_cv = TaxaMatch::read_inaturalist_cv_output(
    data           = {{input_var}},
    min_confidence = {{min_confidence}},
    top_n          = {{top_n}}
  ),
  wildlife_insights = TaxaMatch::read_wildlife_insights_output(
    data           = {{input_var}},
    min_confidence = {{min_confidence}},
    top_n          = {{top_n}}
  ),
  stop("Unknown classifier '", .classifier,
       "'. Use 'animl', 'inaturalist_cv', or 'wildlife_insights'.", call. = FALSE)
)

if (nrow(image_raw) == 0L) {
  stop(
    "Image reader returned 0 detections. Check:\n",
    "  - That '{{input_var}}' points to valid classifier output\n",
    "  - That min_confidence ({{min_confidence}}) is not too strict\n",
    call. = FALSE
  )
}

for (.col in TaxaTools::detect_ranks(image_raw)) {
  image_raw[[.col]] <- TaxaTools::clean_taxon_names(image_raw[[.col]])
}

match_df <- TaxaMatch::standardize_match_data(
  data               = image_raw,
  observation_id_col = "observation_id",
  score_col          = "score",
  rank_system        = {{rank_system}}
)

match_df <- TaxaMatch::filter_redundant_hypotheses(match_df)
message("Image classifier: ", length(unique(match_df$observation_id)),
        " images, ", nrow(match_df), " candidate hypotheses")
match_df
