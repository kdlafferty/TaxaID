test_that("rename_cols rejects non-data-frame input", {
  expect_error(rename_cols("not a df"), "`input_df` must be a data frame")
  expect_error(rename_cols(1:5),        "`input_df` must be a data frame")
  expect_error(rename_cols(NULL),       "`input_df` must be a data frame")
})

test_that("rename_cols rejects invalid strict argument", {
  df <- data.frame(x = 1)
  expect_error(rename_cols(df, strict = "yes"), "`strict` must be a single logical")
  expect_error(rename_cols(df, strict = NA),    "`strict` must be a single logical")
  expect_error(rename_cols(df, strict = c(TRUE, FALSE)), "`strict` must be a single logical")
})

test_that("rename_cols rejects unnamed col_map", {
  df <- data.frame(Latitude = 1)
  expect_error(
    rename_cols(df, col_map = c("decimalLatitude")),
    "`col_map` must be a named character vector"
  )
})

test_that("rename_cols rejects non-character col_map", {
  df <- data.frame(Latitude = 1)
  expect_error(
    rename_cols(df, col_map = 1:3),
    "`col_map` must be a named character vector"
  )
})

test_that("rename_cols rejects col_map with empty names", {
  df  <- data.frame(Latitude = 1)
  # Build the bad vector programmatically — the parser rejects "" as a literal name in c()
  bad <- c("decimalLatitude", "decimalLongitude")
  names(bad) <- c("Latitude", "")
  expect_error(rename_cols(df, col_map = bad), "`col_map` must be a named character vector")
})

# ==============================================================================
# User col_map — exact matching
# ==============================================================================

test_that("rename_cols applies a single col_map entry correctly", {
  df  <- data.frame(Latitude = 34.1, other = 1)
  out <- rename_cols(df, col_map = c("Latitude" = "decimalLatitude"))
  expect_true("decimalLatitude" %in% names(out))
  expect_false("Latitude" %in% names(out))
  expect_true("other" %in% names(out))   # untouched column preserved
})

test_that("rename_cols applies multiple col_map entries correctly", {
  df <- data.frame(Lat = 34.1, Lon = -119.1, Date = "2022-01-01")
  out <- rename_cols(df, col_map = c(
    "Lat"  = "decimalLatitude",
    "Lon"  = "decimalLongitude",
    "Date" = "eventDate"
  ))
  expect_setequal(names(out), c("decimalLatitude", "decimalLongitude", "eventDate"))
})

test_that("rename_cols preserves column values after renaming", {
  df  <- data.frame(Latitude = 34.1, Longitude = -119.1)
  out <- rename_cols(df, col_map = c("Latitude" = "decimalLatitude",
                                      "Longitude" = "decimalLongitude"))
  expect_equal(out$decimalLatitude,  34.1)
  expect_equal(out$decimalLongitude, -119.1)
})

test_that("rename_cols preserves column types after renaming", {
  df  <- data.frame(Lat = 34.1, Flag = TRUE, Count = 5L, Label = "A",
                    stringsAsFactors = FALSE)
  out <- rename_cols(df, col_map = c("Lat" = "decimalLatitude"))
  expect_type(out$decimalLatitude, "double")
  expect_type(out$Flag,  "logical")
  expect_type(out$Count, "integer")
  expect_type(out$Label, "character")
})

test_that("rename_cols preserves row count and order", {
  df  <- data.frame(Lat = c(34.1, 35.2, 36.3))
  out <- rename_cols(df, col_map = c("Lat" = "decimalLatitude"))
  expect_equal(nrow(out), 3L)
  expect_equal(out$decimalLatitude, c(34.1, 35.2, 36.3))
})

test_that("rename_cols col_map: missing key warns with strict = FALSE", {
  df <- data.frame(Latitude = 34.1)
  expect_warning(
    rename_cols(df, col_map = c("NotThere" = "decimalLatitude"), strict = FALSE),
    "not found"
  )
})

test_that("rename_cols col_map: missing key stops with strict = TRUE", {
  df <- data.frame(Latitude = 34.1)
  expect_error(
    rename_cols(df, col_map = c("NotThere" = "decimalLatitude"), strict = TRUE),
    "not found"
  )
})

test_that("rename_cols col_map: renames present keys even when some are missing (strict = FALSE)", {
  df <- data.frame(Latitude = 34.1, Other = 1)
  suppressWarnings(
    out <- rename_cols(df,
                       col_map = c("Latitude" = "decimalLatitude",
                                   "Missing"  = "eventDate"),
                       strict = FALSE)
  )
  expect_true("decimalLatitude" %in% names(out))
  expect_false("Latitude" %in% names(out))
})

test_that("rename_cols col_map replaces default patterns entirely", {
  # Frame has both a pattern-matchable name AND a user-mapped name.
  # With col_map supplied, only the explicit map should apply.
  df <- data.frame(lat = 34.1, Lon = -119.1)
  out <- rename_cols(df, col_map = c("Lon" = "decimalLongitude"))
  # Lon should be renamed
  expect_true("decimalLongitude" %in% names(out))
  # lat should NOT be touched (patterns not applied when col_map supplied)
  expect_true("lat" %in% names(out))
  expect_false("decimalLatitude" %in% names(out))
})

# ==============================================================================
# Default pattern matching (col_map = NULL)
# ==============================================================================

test_that("rename_cols default: renames 'Latitude' to decimalLatitude", {
  df  <- data.frame(Latitude = 34.1)
  out <- rename_cols(df)
  expect_true("decimalLatitude" %in% names(out))
  expect_false("Latitude" %in% names(out))
})

test_that("rename_cols default: renames 'lat' to decimalLatitude (case-insensitive)", {
  df  <- data.frame(lat = 34.1)
  out <- rename_cols(df)
  expect_true("decimalLatitude" %in% names(out))
})

test_that("rename_cols default: renames 'LAT' to decimalLatitude (case-insensitive)", {
  df  <- data.frame(LAT = 34.1)
  out <- rename_cols(df)
  expect_true("decimalLatitude" %in% names(out))
})

test_that("rename_cols default: renames 'Longitude' to decimalLongitude", {
  df  <- data.frame(Longitude = -119.1)
  out <- rename_cols(df)
  expect_true("decimalLongitude" %in% names(out))
})

test_that("rename_cols default: renames 'lon' to decimalLongitude", {
  df  <- data.frame(lon = -119.1)
  out <- rename_cols(df)
  expect_true("decimalLongitude" %in% names(out))
})

test_that("rename_cols default: renames 'long' to decimalLongitude", {
  df  <- data.frame(long = -119.1)
  out <- rename_cols(df)
  expect_true("decimalLongitude" %in% names(out))
})

test_that("rename_cols default: renames 'Date' to eventDate", {
  df  <- data.frame(Date = "2022-01-01")
  out <- rename_cols(df)
  expect_true("eventDate" %in% names(out))
})

test_that("rename_cols default: renames 'SurveyDate' to eventDate", {
  df  <- data.frame(SurveyDate = "2022-01-01")
  out <- rename_cols(df)
  expect_true("eventDate" %in% names(out))
})

test_that("rename_cols default: renames 'CollectionDate' to eventDate", {
  df  <- data.frame(CollectionDate = "2022-01-01")
  out <- rename_cols(df)
  expect_true("eventDate" %in% names(out))
})

test_that("rename_cols default: renames 'site' to verbatimLocality", {
  df  <- data.frame(site = "Carpinteria")
  out <- rename_cols(df)
  expect_true("verbatimLocality" %in% names(out))
})

test_that("rename_cols default: renames 'Location' to verbatimLocality", {
  df  <- data.frame(Location = "Carpinteria")
  out <- rename_cols(df)
  expect_true("verbatimLocality" %in% names(out))
})

test_that("rename_cols default: renames multiple pattern columns in one call", {
  df <- data.frame(Latitude = 34.1, Longitude = -119.1,
                   Date = "2022-01-01", site = "Carpinteria",
                   species = "Clevelandia ios")
  out <- rename_cols(df)
  expect_true("decimalLatitude"  %in% names(out))
  expect_true("decimalLongitude" %in% names(out))
  expect_true("eventDate"        %in% names(out))
  expect_true("verbatimLocality" %in% names(out))
  expect_true("species"          %in% names(out))   # not matched — left unchanged
})

test_that("rename_cols default: skips column already named decimalLatitude", {
  df  <- data.frame(decimalLatitude = 34.1, lat = 35.0)
  out <- rename_cols(df)
  # decimalLatitude already present — lat should NOT overwrite it
  expect_true("decimalLatitude" %in% names(out))
  expect_true("lat" %in% names(out))   # lat left unchanged because target already exists
  expect_equal(ncol(out), 2L)
})

test_that("rename_cols default: warns on ambiguous multi-column match", {
  df <- data.frame(lat = 34.1, Lat = 35.0, other = 1)
  expect_warning(rename_cols(df), "matched multiple columns")
})

test_that("rename_cols default: no match leaves df unchanged", {
  df  <- data.frame(species = "Clevelandia ios", count = 3L)
  out <- rename_cols(df)
  expect_equal(names(out), names(df))
  expect_equal(nrow(out), nrow(df))
})

test_that("rename_cols default: does NOT map any column to scientificName", {
  df <- data.frame(Species = "Clevelandia ios", species = "ios",
                   ScientificName = "Clevelandia ios", Name = "Gobiidae")
  out <- rename_cols(df)
  expect_false("scientificName" %in% names(out))
})

test_that("rename_cols default: does NOT map any column to taxon_name", {
  df  <- data.frame(taxon = "Gobiidae")
  out <- rename_cols(df)
  expect_false("taxon_name" %in% names(out))
})

# ==============================================================================
# Edge cases
# ==============================================================================

test_that("rename_cols works on a zero-row data frame", {
  df  <- data.frame(Latitude = numeric(0), Longitude = numeric(0))
  out <- rename_cols(df)
  expect_equal(nrow(out), 0L)
  expect_true("decimalLatitude"  %in% names(out))
  expect_true("decimalLongitude" %in% names(out))
})

test_that("rename_cols works on a single-column data frame", {
  df  <- data.frame(lat = 34.1)
  out <- rename_cols(df)
  expect_equal(names(out), "decimalLatitude")
})

test_that("rename_cols is pipe-friendly", {
  out <- data.frame(Latitude = 34.1) |> rename_cols()
  expect_true("decimalLatitude" %in% names(out))
})

test_that("rename_cols col_map: mapping to same name is a no-op", {
  df  <- data.frame(decimalLatitude = 34.1)
  out <- rename_cols(df, col_map = c("decimalLatitude" = "decimalLatitude"))
  expect_equal(names(out), "decimalLatitude")
  expect_equal(out$decimalLatitude, 34.1)
})
