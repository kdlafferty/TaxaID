.write_speciesnet_json <- function(predictions_json_body) {
  tmp <- tempfile(fileext = ".json")
  writeLines(paste0('{"predictions":[', predictions_json_body, ']}'), tmp)
  tmp
}

test_that("read_speciesnet_output() parses a species-level label into genus/species/taxon_rank", {
  tmp <- .write_speciesnet_json(paste0(
    '{"filepath":"IMG_001.jpg",',
    '"classifications":{"classes":["04eda76f-c0e7-4e9e-85c3-5b1542db2915;amphibia;anura;bufonidae;rhinella;marina;cane toad"],"scores":[0.87]},',
    '"prediction":"04eda76f-c0e7-4e9e-85c3-5b1542db2915;amphibia;anura;bufonidae;rhinella;marina;cane toad",',
    '"prediction_score":0.87,"prediction_source":"classifier"}'
  ))
  on.exit(unlink(tmp))

  out <- read_speciesnet_output(tmp)

  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 1L)
  expect_equal(out$observation_id, "IMG_001")
  expect_equal(out$species, "Rhinella marina")
  expect_equal(out$genus, "Rhinella")
  expect_equal(out$family, "bufonidae")
  expect_equal(out$order, "anura")
  expect_equal(out$class, "amphibia")
  expect_equal(out$common_name, "cane toad")
  expect_equal(out$taxon_rank, "species")
  expect_equal(out$score, 0.87)
  expect_equal(out$ensemble_prediction, "cane toad")
  expect_equal(out$ensemble_prediction_score, 0.87)
  expect_equal(out$ensemble_prediction_source, "classifier")
})

test_that("read_speciesnet_output() rolls up correctly at genus/family/order/class ranks", {
  tmp <- .write_speciesnet_json(paste0(
    '{"filepath":"genus.jpg","classifications":{"classes":["x;amphibia;anura;bufonidae;rhinella;;rhinella species"],"scores":[0.5]}},',
    '{"filepath":"family.jpg","classifications":{"classes":["x;amphibia;anura;ranidae;;;true frogs"],"scores":[0.5]}},',
    '{"filepath":"order.jpg","classifications":{"classes":["x;aves;accipitriformes;;;;accipitriformes order"],"scores":[0.5]}},',
    '{"filepath":"class.jpg","classifications":{"classes":["x;amphibia;;;;;amphibian"],"scores":[0.5]}}'
  ))
  on.exit(unlink(tmp))

  out <- read_speciesnet_output(tmp)
  by_id <- function(id) out[out$observation_id == id, ]

  g <- by_id("genus")
  expect_equal(g$taxon_rank, "genus")
  expect_equal(g$genus, "Rhinella")
  expect_true(is.na(g$species))

  fam <- by_id("family")
  expect_equal(fam$taxon_rank, "family")
  expect_equal(fam$family, "ranidae")
  expect_true(is.na(fam$genus))

  ord <- by_id("order")
  expect_equal(ord$taxon_rank, "order")
  expect_equal(ord$order, "accipitriformes")
  expect_true(is.na(ord$family))

  cls <- by_id("class")
  expect_equal(cls$taxon_rank, "class")
  expect_equal(cls$class, "amphibia")
  expect_true(is.na(cls$order))
})

test_that("read_speciesnet_output() marks non-taxonomic labels (blank/animal/vehicle/no cv result) with taxon_rank NA", {
  tmp <- .write_speciesnet_json(paste0(
    '{"filepath":"blank.jpg","classifications":{"classes":["f1856211-cfb7-4a5b-9158-c0f72fd09ee6;;;;;;blank"],"scores":[0.99]}},',
    '{"filepath":"animal.jpg","classifications":{"classes":["1f689929-883d-4dae-958c-3d57ab5b6c16;;;;;;animal"],"scores":[0.55]}},',
    '{"filepath":"vehicle.jpg","classifications":{"classes":["e2895ed5-780b-48f6-8a11-9e27cb594511;;;;;;vehicle"],"scores":[0.90]}},',
    '{"filepath":"unknown.jpg","classifications":{"classes":["f2efdae9-efb8-48fb-8a91-eccf79ab4ffb;no cv result;no cv result;no cv result;no cv result;no cv result;no cv result"],"scores":[0.10]}}'
  ))
  on.exit(unlink(tmp))

  out <- read_speciesnet_output(tmp)
  expect_true(all(is.na(out$taxon_rank)))
  expect_true(all(is.na(out$species)))
  expect_setequal(out$common_name, c("blank", "animal", "vehicle", NA_character_))

  filtered <- out[!is.na(out$taxon_rank), ]
  expect_equal(nrow(filtered), 0L)
})

test_that("read_speciesnet_output() min_confidence and top_n filter per image", {
  tmp <- .write_speciesnet_json(paste0(
    '{"filepath":"IMG_001.jpg","classifications":{',
    '"classes":["x;mammalia;rodentia;sciuridae;sciurus;carolinensis;eastern gray squirrel",',
    '"x;mammalia;rodentia;sciuridae;sciurus;niger;fox squirrel",',
    '"x;mammalia;rodentia;sciuridae;;;squirrel"],',
    '"scores":[0.80,0.15,0.05]}}'
  ))
  on.exit(unlink(tmp))

  out_conf <- read_speciesnet_output(tmp, min_confidence = 0.10)
  expect_equal(nrow(out_conf), 2L)
  expect_true(all(out_conf$score >= 0.10))

  out_topn <- read_speciesnet_output(tmp, top_n = 1L)
  expect_equal(nrow(out_topn), 1L)
  expect_equal(out_topn$species, "Sciurus carolinensis")
})

test_that("read_speciesnet_output() include_coverage computes bbox area from the top animal detection", {
  tmp <- .write_speciesnet_json(paste0(
    '{"filepath":"IMG_001.jpg",',
    '"classifications":{"classes":["x;mammalia;;;;;mammal"],"scores":[0.6]},',
    '"detections":[',
    '{"category":"2","conf":0.99,"bbox":[0,0,0.9,0.9]},',
    '{"category":"1","conf":0.40,"bbox":[0.0,0.0,0.5,0.5]},',
    '{"category":"1","conf":0.85,"bbox":[0.1,0.1,0.2,0.5]}',
    ']}'
  ))
  on.exit(unlink(tmp))

  out <- read_speciesnet_output(tmp, include_coverage = TRUE)
  expect_true(all(c("coverage", "detection_conf") %in% names(out)))
  expect_equal(out$detection_conf, 0.85)
  expect_equal(out$coverage, 0.2 * 0.5)

  out_gated <- read_speciesnet_output(tmp, include_coverage = TRUE, min_detection_conf = 0.9)
  expect_true(is.na(out_gated$coverage))
  expect_true(is.na(out_gated$detection_conf))
})

test_that("read_speciesnet_output() without include_coverage has no coverage columns", {
  tmp <- .write_speciesnet_json(paste0(
    '{"filepath":"IMG_001.jpg","classifications":{"classes":["x;mammalia;;;;;mammal"],"scores":[0.6]}}'
  ))
  on.exit(unlink(tmp))

  out <- read_speciesnet_output(tmp)
  expect_false(any(c("coverage", "detection_conf") %in% names(out)))
})

test_that("read_speciesnet_output() carries lat/lon/country when present", {
  tmp <- .write_speciesnet_json(paste0(
    '{"filepath":"IMG_001.jpg","classifications":{"classes":["x;mammalia;;;;;mammal"],"scores":[0.6]},',
    '"country":"USA","latitude":34.41,"longitude":-119.86}'
  ))
  on.exit(unlink(tmp))

  out <- read_speciesnet_output(tmp)
  expect_equal(out$country, "USA")
  expect_equal(out$lat, 34.41)
  expect_equal(out$lon, -119.86)
})

test_that("read_speciesnet_output() errors on missing files", {
  expect_error(read_speciesnet_output("does_not_exist.json"), "not found")
})

test_that("read_speciesnet_output() reads all JSON files in a directory", {
  d <- tempfile()
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE))
  writeLines('{"predictions":[{"filepath":"a.jpg","classifications":{"classes":["x;mammalia;;;;;mammal"],"scores":[0.5]}}]}',
             file.path(d, "batch1.json"))
  writeLines('{"predictions":[{"filepath":"b.jpg","classifications":{"classes":["x;aves;;;;;bird"],"scores":[0.6]}}]}',
             file.path(d, "batch2.json"))

  out <- read_speciesnet_output(d)
  expect_equal(nrow(out), 2L)
  expect_setequal(out$observation_id, c("a", "b"))
})

test_that("read_speciesnet_output() warns and returns NA taxonomy for a malformed label", {
  tmp <- .write_speciesnet_json(paste0(
    '{"filepath":"IMG_001.jpg","classifications":{"classes":["not;enough;fields"],"scores":[0.5]}}'
  ))
  on.exit(unlink(tmp))

  expect_warning(out <- read_speciesnet_output(tmp), "7")
  expect_true(is.na(out$taxon_rank))
  expect_true(is.na(out$species))
})

test_that("read_speciesnet_output() returns an empty result with a message when no predictions are found", {
  tmp <- .write_speciesnet_json("")
  on.exit(unlink(tmp))

  expect_message(out <- read_speciesnet_output(tmp), "no predictions")
  expect_equal(nrow(out), 0L)
  expect_true(all(c("observation_id", "score", "species", "taxon_rank") %in% names(out)))
})
