# test-report_habitat.R
# Tests for report_habitat()

test_that("report_habitat returns valid report_section", {
  df <- data.frame(
    scientificName = c("Sp A", "Sp B", "Sp C"),
    Marine = c(0.9, 0.8, 1.0),
    Freshwater = c(0.1, 0.2, 0.0),
    stringsAsFactors = FALSE
  )

  sec <- report_habitat(df)
  expect_s3_class(sec, "report_section")
  expect_equal(sec$package, "TaxaHabitat")
  expect_equal(sec$section, "habitat")
  expect_equal(sec$statistics$n_taxa, 3L)
})

test_that("report_habitat detects 3-category scheme", {
  df <- data.frame(
    scientificName = c("Sp A", "Sp B"),
    Marine = c(0.9, 1.0),
    Freshwater = c(0.1, 0.0),
    Terrestrial = c(0.0, 0.0),
    stringsAsFactors = FALSE
  )

  sec <- report_habitat(df)
  expect_equal(sec$params$habitat_scheme, "3-category")
  expect_true(grepl("3-category", sec$methods))
})

test_that("report_habitat identifies dominant habitat", {
  df <- data.frame(
    scientificName = c("Sp A", "Sp B"),
    Marine = c(0.9, 1.0),
    Freshwater = c(0.1, 0.0),
    stringsAsFactors = FALSE
  )

  sec <- report_habitat(df)
  expect_equal(sec$statistics$dominant_habitat, "Marine")
  expect_true(grepl("Marine", sec$results))
})

test_that("report_habitat respects custom taxon_col", {
  df <- data.frame(
    taxon_name = c("Sp A", "Sp B", "Sp C"),
    Marine = c(0.9, 0.8, 1.0),
    Freshwater = c(0.1, 0.2, 0.0),
    stringsAsFactors = FALSE
  )

  sec <- report_habitat(df, taxon_col = "taxon_name")
  expect_equal(sec$statistics$n_taxa, 3L)
})

test_that("report_habitat excludes known non-habitat columns", {
  df <- data.frame(
    scientificName = c("Sp A", "Sp B"),
    Marine = c(0.9, 1.0),
    Freshwater = c(0.1, 0.0),
    habitat_best_guess = c("Marine", "Marine"),
    main_habitat = c("Marine", "Marine"),
    stringsAsFactors = FALSE
  )

  sec <- report_habitat(df)
  # Should only have 2 habitat columns (Marine, Freshwater), not 4
  expect_equal(sec$statistics$n_habitat_cols, 2L)
})

test_that("report_habitat reads report_params attribute", {
  df <- data.frame(
    scientificName = "Sp A",
    Marine = 1.0,
    stringsAsFactors = FALSE
  )
  attr(df, "report_params") <- list(geographic_context = "tropical Pacific")

  sec <- report_habitat(df)
  expect_equal(sec$params$geographic_context, "tropical Pacific")
})

test_that("report_habitat errors on empty data", {
  expect_error(report_habitat(data.frame()))
  expect_error(report_habitat(NULL))
})

test_that("dominant pct survives an all-NA habitat column (2026-09-01 real crash)", {
  df <- data.frame(
    scientificName = c("Sp A", "Sp B"),
    Marine = c(0.9, 1.0),
    Freshwater = c(NA_real_, NA_real_),
    stringsAsFactors = FALSE
  )
  sec <- report_habitat(df)
  expect_equal(sec$statistics$dominant_habitat, "Marine")
  expect_equal(sec$statistics$dominant_pct, 95)
  expect_true(grepl("mean weight 95%", sec$results, fixed = TRUE))
})

test_that("no crash when EVERY habitat column is entirely NA (2026-09-07 code review)", {
  df <- data.frame(
    scientificName = c("Sp A", "Sp B"),
    Marine = c(NA_real_, NA_real_),
    Freshwater = c(NA_real_, NA_real_),
    stringsAsFactors = FALSE
  )
  sec <- report_habitat(df)
  expect_null(sec$statistics$dominant_habitat)
  expect_null(sec$statistics$dominant_pct)
  expect_false(grepl("Dominant habitat", sec$results, fixed = TRUE))
})

test_that("occurrence-level habitat data is summarised from main_habitat, not coordinates (2026-09-07 bug)", {
  # Reproduces the real shape that produced "under the decimalLatitude/
  # decimalLongitude scheme" and "Dominant habitat: decimalLatitude (mean
  # weight 3519%)" in both a real 18S and a real GreatLakes generated report:
  # occurrence-level data (taxon_name, not scientificName; decimalLatitude/
  # decimalLongitude as the only other numeric columns) with a categorical
  # main_habitat winner per row, no numeric habitat-weight columns at all.
  df <- data.frame(
    taxon_name       = c("Sp A", "Sp A", "Sp B", "Sp C", "Sp C"),
    decimalLatitude  = c(34.1, 34.2, 35.0, 34.5, 34.6),
    decimalLongitude = c(-119.8, -119.7, -120.1, -119.9, -119.9),
    main_habitat     = c("Marine", "Marine", "Estuarine", "Marine", NA_character_),
    habitat_best_guess = c(NA_character_, NA_character_, NA_character_, NA_character_, "unclear"),
    stringsAsFactors = FALSE
  )

  sec <- report_habitat(df)
  # 3 unique taxa, not 5 raw rows.
  expect_equal(sec$statistics$n_taxa, 3L)
  # Real categories (Marine/Estuarine), never the coordinate column names.
  expect_equal(sec$statistics$n_habitat_cols, 2L)
  expect_equal(sec$params$habitat_scheme, "Marine/Estuarine")
  expect_false(grepl("decimalLat|decimalLon", sec$methods))
  # Dominant = most common category among ASSIGNED (non-NA) rows: Marine, 3/4.
  expect_equal(sec$statistics$dominant_habitat, "Marine")
  expect_equal(sec$statistics$dominant_pct, 75)
  expect_true(grepl("Marine \\(75% of assigned records\\)", sec$results))
})

test_that("main_habitat branch: n_habitat_cols and dominant_habitat are NULL/0 when every row is NA", {
  df <- data.frame(
    taxon_name   = c("Sp A", "Sp B"),
    main_habitat = c(NA_character_, NA_character_),
    stringsAsFactors = FALSE
  )
  sec <- report_habitat(df)
  expect_equal(sec$statistics$n_habitat_cols, 0L)
  expect_null(sec$statistics$dominant_habitat)
  expect_null(sec$params$habitat_scheme)
})

# ------------------------------------------------------------------------------
# 2026-09-10: the 2026-09-08 dispatch test --
#   any(vapply(candidate_cols, function(hc) all(is.na(x) | (x >= 0 & x <= 1))))
# -- had two holes that put occurrence-level data back down the weight branch.
# Confirmed by direct evaluation, then reproduced end-to-end on the real
# PtConMifishSchulte occurrence object. Each test below fixes one hole.
# ------------------------------------------------------------------------------

test_that("an all-NA numeric column does not vacuously look like a habitat weight (2026-09-10)", {
  # is.na(x) is TRUE everywhere for an all-NA column, so the `|` short-circuits
  # the range condition away and all() returns TRUE regardless. GBIF exports
  # routinely carry such columns. On the real Pt Conception 12S object, adding
  # a single all-NA `depth` column turned "356 taxa ... Dominant habitat:
  # Marine (89% of assigned records)" into "20000 taxa ... Dominant habitat:
  # decimalLatitude (mean weight 3506%)" -- the exact pre-fix symptom, and the
  # one printed in the 2026-08-30 generated report.
  df <- data.frame(
    taxon_name       = c("Sp A", "Sp A", "Sp B", "Sp C", "Sp C"),
    decimalLatitude  = c(34.1, 34.2, 35.0, 34.5, 34.6),
    decimalLongitude = c(-119.8, -119.7, -120.1, -119.9, -119.9),
    depth            = NA_real_,
    main_habitat     = c("Marine", "Marine", "Estuarine", "Marine", NA_character_),
    stringsAsFactors = FALSE
  )

  sec <- report_habitat(df)
  expect_equal(sec$statistics$n_taxa, 3L)
  expect_equal(sec$statistics$dominant_habitat, "Marine")
  expect_equal(sec$params$habitat_scheme, "Marine/Estuarine")
  expect_false(grepl("decimalLat|decimalLon|depth", sec$methods))
  expect_false(grepl("mean weight", sec$results, fixed = TRUE))
})

test_that("an in-range but non-compositional column does not look like a habitat weight (2026-09-10)", {
  # coordinatePrecision is legitimately in [0, 1] without being a weight, so
  # the range check alone passed it too. Same symptom as the all-NA case.
  df <- data.frame(
    taxon_name          = c("Sp A", "Sp A", "Sp B", "Sp C", "Sp C"),
    decimalLatitude     = c(34.1, 34.2, 35.0, 34.5, 34.6),
    decimalLongitude    = c(-119.8, -119.7, -120.1, -119.9, -119.9),
    coordinatePrecision = c(0.001, 0.001, 0.0001, 0.01, 0.001),
    main_habitat        = c("Marine", "Marine", "Estuarine", "Marine", NA_character_),
    stringsAsFactors    = FALSE
  )

  sec <- report_habitat(df)
  expect_equal(sec$statistics$n_taxa, 3L)
  expect_equal(sec$statistics$dominant_habitat, "Marine")
  expect_false(grepl("coordinatePrecision", sec$methods, fixed = TRUE))
})

test_that("an all-zero in-range column does not look like a habitat weight (2026-09-10)", {
  # The production-shaped version of the same hole: dist_to_coast_km is 0 for
  # every retained record in a coastal-only survey, which is in [0, 1] and has
  # real (non-NA) data, so neither the range check nor a bare non-NA guard
  # would reject it.
  df <- data.frame(
    taxon_name       = c("Sp A", "Sp A", "Sp B"),
    decimalLatitude  = c(34.1, 34.2, 35.0),
    dist_to_coast_km = c(0, 0, 0),
    main_habitat     = c("Marine", "Marine", "Estuarine"),
    stringsAsFactors = FALSE
  )

  sec <- report_habitat(df)
  expect_equal(sec$statistics$n_taxa, 2L)
  expect_equal(sec$params$habitat_scheme, "Marine/Estuarine")
})

test_that("real weight columns still win over a co-occurring main_habitat (2026-09-10)", {
  # The hardened dispatch must not overshoot: a hand-assembled table carrying
  # BOTH main_habitat and real per-category weights is still Shape A, because
  # its numeric columns are all in range and do compose to 1.0 per row.
  df <- data.frame(
    scientificName = c("Sp A", "Sp B", "Sp C"),
    Marine         = c(0.9, 1.0, 0.25),
    Freshwater     = c(0.1, 0.0, 0.75),
    main_habitat   = c("Marine", "Marine", "Freshwater"),
    stringsAsFactors = FALSE
  )

  sec <- report_habitat(df)
  expect_equal(sec$statistics$n_habitat_cols, 2L)
  expect_equal(sec$statistics$dominant_habitat, "Marine")
  expect_true(grepl("mean weight", sec$results, fixed = TRUE))
})

test_that("un-renormalised weights within parse()'s own 0.05 tolerance still dispatch as weights (2026-09-10)", {
  # parse_hierarchical_habitat_response() documents that weights are NOT
  # renormalised and warns only past 0.05 of 1.0, so the composition check
  # uses that same tolerance rather than exact equality.
  df <- data.frame(
    taxon_name   = c("Sp A", "Sp B", "Sp C"),
    Marine       = c(0.96, 1.02, 0.60),
    Freshwater   = c(0.06, 0.00, 0.42),
    main_habitat = c("Marine", "Marine", "Marine"),
    stringsAsFactors = FALSE
  )

  sec <- report_habitat(df, taxon_col = "taxon_name")
  expect_equal(sec$statistics$n_habitat_cols, 2L)
  expect_equal(sec$statistics$dominant_habitat, "Marine")
})

test_that("single-row weight tables survive the composition check (2026-09-10)", {
  # vapply() returns a bare vector rather than a 1-row matrix when nrow == 1,
  # so the row-sum matrix has its dim set explicitly. Guard that here.
  df <- data.frame(
    scientificName = "Sp A",
    Marine         = 0.7,
    Freshwater     = 0.3,
    main_habitat   = "Marine",
    stringsAsFactors = FALSE
  )
  sec <- report_habitat(df)
  expect_equal(sec$statistics$n_habitat_cols, 2L)
  expect_equal(sec$statistics$dominant_habitat, "Marine")
})

test_that("Shape A n_taxa resolves taxon_name against the scientificName default (2026-09-10)", {
  # parse_hierarchical_habitat_response() ALWAYS names its taxon column
  # taxon_name, but report_habitat()'s default taxon_col is "scientificName".
  # Only .summarise_main_habitat() used to consult .resolve_taxon_col(), so the
  # documented Shape A call fell through to nrow() and reported rows as taxa --
  # the same class as the "1419840 taxa" bug, on the weight branch.
  df <- data.frame(
    taxon_name   = c("Sp A", "Sp A", "Sp B"),
    Marine       = c(0.9, 0.9, 0.2),
    Other_weight = c(0.1, 0.1, 0.8),
    stringsAsFactors = FALSE
  )

  # No taxon_col given: must still count 2 unique taxa, not 3 rows.
  expect_equal(report_habitat(df)$statistics$n_taxa, 2L)
  # Explicit taxon_col agrees.
  expect_equal(report_habitat(df, taxon_col = "taxon_name")$statistics$n_taxa, 2L)
})

test_that("an explicitly named, present taxon_col still wins over taxon_name (2026-09-10)", {
  # .resolve_taxon_col() only falls back when the requested column is ABSENT,
  # so a frame carrying both must honour the caller's choice.
  df <- data.frame(
    scientificName = c("Sp A", "Sp B", "Sp C"),
    taxon_name     = c("Sp A", "Sp A", "Sp A"),
    Marine         = c(0.9, 1.0, 0.5),
    Freshwater     = c(0.1, 0.0, 0.5),
    stringsAsFactors = FALSE
  )
  expect_equal(report_habitat(df)$statistics$n_taxa, 3L)
  expect_equal(report_habitat(df, taxon_col = "taxon_name")$statistics$n_taxa, 1L)
})

# -----------------------------------------------------------------------------
# report_habitat() is the SECOND consumer of the habitat weight table, and it
# inferred the weight set by scanning column types exactly as
# .detect_habitat_cols() did. Reproduced on the real PtConception 12S lookup
# once habitat_breadth existed: "across 5 categories. Dominant habitat: Marine
# (mean weight 58%)" became "across 6 categories. Dominant habitat:
# habitat_breadth" -- Methods/Results text headed for a manuscript.
# -----------------------------------------------------------------------------

.rh_weights <- function(with_breadth, with_attr) {
  h <- data.frame(
    taxon_name = c("sp1", "sp2", "sp3"),
    Marine      = c(0.90, 0.30, 0.10),
    Estuarine   = c(0.05, 0.20, 0.10),
    Freshwater  = c(0.05, 0.30, 0.70),
    Terrestrial = c(0.00, 0.20, 0.10),
    Other_weight = 0,
    habitat_best_guess = "",
    Habitat = c("Marine", "Marine", "Freshwater"),
    stringsAsFactors = FALSE
  )
  if (with_breadth) {
    h$habitat_breadth <- .compute_habitat_breadth(
      h, c("Marine", "Estuarine", "Freshwater", "Terrestrial")
    )
  }
  if (with_attr) {
    attr(h, "habitat_cols") <- c(
      "Marine", "Estuarine", "Freshwater", "Terrestrial", "Other_weight"
    )
  }
  h
}

test_that("report_habitat() never reports habitat_breadth as a habitat", {
  for (with_attr in c(TRUE, FALSE)) {
    r <- report_habitat(.rh_weights(TRUE, with_attr), taxon_col = "taxon_name")
    txt <- paste(unlist(r), collapse = " ")
    expect_false(grepl("habitat_breadth", txt), info = paste("attr:", with_attr))
    expect_false(grepl("6 categories", txt), info = paste("attr:", with_attr))
  }
})

test_that("adding habitat_breadth does not change report_habitat()'s output", {
  # The column must be genuinely additive for the reporting path, both when the
  # table declares its weight columns and when it does not.
  for (with_attr in c(TRUE, FALSE)) {
    a <- report_habitat(.rh_weights(FALSE, with_attr), taxon_col = "taxon_name")
    b <- report_habitat(.rh_weights(TRUE, with_attr), taxon_col = "taxon_name")
    expect_equal(unlist(a), unlist(b), info = paste("attr:", with_attr))
  }
})

test_that(".candidate_habitat_cols prefers the declared columns", {
  h <- .rh_weights(TRUE, TRUE)
  cc <- .candidate_habitat_cols(h, "taxon_name")
  expect_false("habitat_breadth" %in% cc)
  expect_true(all(c("Marine", "Estuarine", "Freshwater", "Terrestrial") %in% cc))
  # A stale declaration naming no present column falls back to the scan
  attr(h, "habitat_cols") <- "NoSuchColumn"
  cc2 <- .candidate_habitat_cols(h, "taxon_name")
  expect_false("habitat_breadth" %in% cc2)
  expect_true("Marine" %in% cc2)
})
