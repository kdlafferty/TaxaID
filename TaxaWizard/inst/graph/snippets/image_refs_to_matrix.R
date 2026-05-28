# Edge: [images_meta + image_classifier_output] -> image_matrix
# Source: TaxaLikely build_image_reference()
#
# images_meta: data frame of ground-truth image labels.
#   Required columns: image_path (file path or stem), plus taxonomy columns
#   from rank_system (e.g. genus, species).
#   Optional: testid (classifier/camera type), quality (numeric 0-1).
#
# image_classifier_output: classifier output on those same reference images
#   (from read_animl_output(), read_inaturalist_cv_output(), etc.)
#   Set classifier to one of: "animl", "inaturalist_cv", "wildlife_insights"

images_meta <- {{images_meta}}   # ground-truth labels data frame

.classifier <- {{classifier}}
image_raw <- switch(.classifier,
  animl = TaxaMatch::read_animl_output(
    data = {{input_var}}, min_confidence = 0.05, top_n = 5L),
  inaturalist_cv = TaxaMatch::read_inaturalist_cv_output(
    data = {{input_var}}, min_confidence = 0.05, top_n = 5L),
  wildlife_insights = TaxaMatch::read_wildlife_insights_output(
    data = {{input_var}}, min_confidence = 0.05, top_n = 5L),
  stop("Unknown classifier '", .classifier,
       "'. Use 'animl', 'inaturalist_cv', or 'wildlife_insights'.", call. = FALSE)
)

image_matrix <- TaxaLikely::build_image_reference(
  image_df    = image_raw,
  images_meta = images_meta,
  rank_system = {{rank_system}}
)

if (nrow(image_matrix) == 0L)
  stop("build_image_reference() returned 0 pairs. Check that observation_id in ",
       "image_raw matches file stems in images_meta$image_path.", call. = FALSE)

message("Image reference matrix: ", nrow(image_matrix), " pairs, ",
        length(unique(image_matrix$species.x)), " species")
if ("testid" %in% names(image_matrix))
  message("Testids (train one model each): ",
          paste(unique(image_matrix$testid), collapse = ", "))
image_matrix
