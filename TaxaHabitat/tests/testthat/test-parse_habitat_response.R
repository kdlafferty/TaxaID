test_that("parses a well-formed weighted CSV response", {
  raw_text <- paste(
    "taxon_name,Marine,Freshwater,Terrestrial,Other_weight,habitat_best_guess",
    "Sebastes mystinus,1.00,0.00,0.00,0.00,",
    "Oncorhynchus mykiss,0.50,0.50,0.00,0.00,",
    sep = "\n"
  )
  out <- parse_hierarchical_habitat_response(
    raw_text,
    taxon_list = c("Sebastes mystinus", "Oncorhynchus mykiss")
  )

  expect_equal(out$taxon_name, c("Sebastes mystinus", "Oncorhynchus mykiss"))
  expect_equal(out$Marine, c(1.00, 0.50))
  expect_equal(out$Freshwater, c(0.00, 0.50))
})

test_that("a comma embedded in habitat_best_guess does not corrupt the parse (real reported bug)", {
  # Reproduces the exact scenario a reviewer hit live-testing this function:
  # an LLM wrote habitat_best_guess text with an unquoted, embedded comma.
  # Before the fix, this silently shifted every later column by one and
  # moved the true taxon_name into read.csv()'s invisible row name instead
  # of the taxon_name column.
  raw_text <- paste0(
    "taxon_name,Shallow Kelp Forest,Deep Kelp Forest,Rocky Subtidal,",
    "Other_weight,habitat_best_guess\n",
    "Gadus morhua,0,0,0.60,0.4,",
    "Continental shelf demersal (30-200 m), including deeper muddy/sandy bottoms\n",
    "Oncorhynchus mykiss,0,0,0.20,0.80,",
    "Freshwater rivers and streams, with some coastal pelagic use"
  )

  # No warning expected: with the fix, weights parse and sum to 1.0 exactly
  # as written. Before the fix, the column shift corrupted numeric weights
  # into text and vice versa, which would either warn or error outright.
  out <- expect_warning(
    parse_hierarchical_habitat_response(
      raw_text,
      taxon_list = c("Gadus morhua", "Oncorhynchus mykiss")
    ),
    regexp = NA
  )

  # The core assertion: taxon_name must be the REAL taxon names, not the
  # first fragment of the comma-split habitat_best_guess text, and must NOT
  # have silently become row names instead of a real column.
  expect_equal(out$taxon_name, c("Gadus morhua", "Oncorhynchus mykiss"))
  # Row names must be the default sequential ones, not the taxon names --
  # confirms read.csv() never fell into its implicit-row-name inference path.
  expect_identical(rownames(out), as.character(seq_len(nrow(out))))

  # Other_weight must be the numeric value, not text.
  expect_equal(out$Other_weight, c(0.4, 0.80))

  # habitat_best_guess must contain the FULL original text, comma intact,
  # not split across two columns.
  expect_equal(
    out$habitat_best_guess,
    c(
      "Continental shelf demersal (30-200 m), including deeper muddy/sandy bottoms",
      "Freshwater rivers and streams, with some coastal pelagic use"
    )
  )
})

test_that("a comma embedded in habitat_best_guess is repaired even with ecoregion_best_guess present", {
  raw_text <- paste0(
    "taxon_name,Marine,Freshwater,Other_weight,habitat_best_guess,ecoregion_best_guess\n",
    "Gadus morhua,0.60,0.00,0.40,",
    "shelf demersal, muddy bottoms,Gulf of Maine"
  )

  out <- suppressWarnings(parse_hierarchical_habitat_response(
    raw_text,
    taxon_list = "Gadus morhua"
  ))

  expect_equal(out$taxon_name, "Gadus morhua")
  expect_equal(out$Other_weight, 0.40)
  expect_equal(out$habitat_best_guess, "shelf demersal, muddy bottoms")
  expect_equal(out$ecoregion_best_guess, "Gulf of Maine")
})

test_that("a row already correctly quoted around an embedded comma parses correctly", {
  raw_text <- paste0(
    "taxon_name,Marine,Freshwater,Other_weight,habitat_best_guess\n",
    'Gadus morhua,0.60,0.00,0.40,"shelf demersal, muddy bottoms"'
  )

  out <- suppressWarnings(parse_hierarchical_habitat_response(
    raw_text,
    taxon_list = "Gadus morhua"
  ))

  expect_equal(out$taxon_name, "Gadus morhua")
  expect_equal(out$habitat_best_guess, "shelf demersal, muddy bottoms")
})

test_that("stops on empty raw_text", {
  expect_error(
    parse_hierarchical_habitat_response("", taxon_list = "Gadus morhua"),
    "non-empty character string"
  )
})

test_that("stops on empty taxon_list", {
  expect_error(
    parse_hierarchical_habitat_response("taxon_name,Marine\nGadus morhua,1.0", taxon_list = character(0)),
    "non-empty character vector"
  )
})

test_that("warns and removes NA/duplicate values from taxon_list", {
  raw_text <- "taxon_name,Marine,Other_weight,habitat_best_guess\nGadus morhua,1.0,0.0,"
  expect_warning(
    expect_warning(
      parse_hierarchical_habitat_response(
        raw_text,
        taxon_list = c("Gadus morhua", NA, "Gadus morhua")
      ),
      "duplicate"
    ),
    "NA value"
  )
})

test_that("warns when a taxon in taxon_list is missing from the response", {
  raw_text <- "taxon_name,Marine,Other_weight,habitat_best_guess\nGadus morhua,1.0,0.0,"
  expect_warning(
    parse_hierarchical_habitat_response(
      raw_text,
      taxon_list = c("Gadus morhua", "Oncorhynchus mykiss")
    ),
    "missing from response"
  )
})

test_that("warns when weights for a row do not sum to 1.0", {
  raw_text <- "taxon_name,Marine,Freshwater,Other_weight,habitat_best_guess\nGadus morhua,0.90,0.00,0.00,"
  expect_warning(
    parse_hierarchical_habitat_response(raw_text, taxon_list = "Gadus morhua"),
    "not summing to 1.0"
  )
})

test_that("strips markdown fences and preamble/postamble text", {
  raw_text <- paste(
    "Here is the habitat assignment:",
    "```csv",
    "taxon_name,Marine,Other_weight,habitat_best_guess",
    "Gadus morhua,1.00,0.00,",
    "```",
    "Let me know if you need anything else.",
    sep = "\n"
  )
  out <- parse_hierarchical_habitat_response(raw_text, taxon_list = "Gadus morhua")
  expect_equal(out$taxon_name, "Gadus morhua")
  expect_equal(out$Marine, 1.00)
})

test_that("strips duplicate header rows from concatenated multi-chunk responses", {
  raw_text <- paste(
    "taxon_name,Marine,Other_weight,habitat_best_guess",
    "Gadus morhua,1.00,0.00,",
    "taxon_name,Marine,Other_weight,habitat_best_guess",
    "Oncorhynchus mykiss,1.00,0.00,",
    sep = "\n"
  )
  out <- parse_hierarchical_habitat_response(
    raw_text,
    taxon_list = c("Gadus morhua", "Oncorhynchus mykiss")
  )
  expect_equal(nrow(out), 2L)
  expect_equal(out$taxon_name, c("Gadus morhua", "Oncorhynchus mykiss"))
})

test_that("unrecognised habitat columns fold into Other_weight with a warning", {
  scheme <- structure(
    list(habitat_cols = c("Marine", "Freshwater"), scheme = NULL),
    class = "habitat_prompt"
  )
  raw_text <- paste0(
    "taxon_name,Marine,Freshwater,Unexpected,Other_weight,habitat_best_guess\n",
    "Gadus morhua,0.50,0.00,0.30,0.20,x"
  )
  expect_warning(
    out <- parse_hierarchical_habitat_response(
      raw_text,
      taxon_list = "Gadus morhua",
      habitat_scheme = scheme
    ),
    "unrecognised"
  )
  expect_false("Unexpected" %in% names(out))
  expect_equal(out$Other_weight, 0.50) # 0.20 original + 0.30 folded in
})

test_that("missing expected habitat columns are added with weight 0 and a warning", {
  scheme <- structure(
    list(habitat_cols = c("Marine", "Freshwater", "Terrestrial"), scheme = NULL),
    class = "habitat_prompt"
  )
  raw_text <- "taxon_name,Marine,Other_weight,habitat_best_guess\nGadus morhua,1.00,0.00,"
  expect_warning(
    out <- parse_hierarchical_habitat_response(
      raw_text,
      taxon_list = "Gadus morhua",
      habitat_scheme = scheme
    ),
    "absent from LLM response"
  )
  expect_true(all(c("Freshwater", "Terrestrial") %in% names(out)))
  expect_equal(out$Freshwater, 0)
  expect_equal(out$Terrestrial, 0)
})

test_that("Habitat convenience column is the argmax of the weight columns", {
  raw_text <- "taxon_name,Marine,Freshwater,Other_weight,habitat_best_guess\nGadus morhua,0.20,0.80,0.00,"
  out <- parse_hierarchical_habitat_response(raw_text, taxon_list = "Gadus morhua")
  expect_equal(out$Habitat, "Freshwater")
})

test_that("ecoregion_best_guess is retained and protected from numeric detection", {
  raw_text <- paste0(
    "taxon_name,Marine,Other_weight,habitat_best_guess,ecoregion_best_guess\n",
    "Gadus morhua,1.00,0.00,,Gulf of Maine"
  )
  out <- parse_hierarchical_habitat_response(raw_text, taxon_list = "Gadus morhua")
  expect_equal(out$ecoregion_best_guess, "Gulf of Maine")
})

test_that("a headerless single-taxon response is parsed when the prompt's layout is known", {
  prompt <- structure(list(habitat_cols = c("Marine", "Terrestrial"), scheme = NULL),
                      class = "habitat_prompt")
  raw <- "Gadus morhua,0.95,0.05,0,Marine"
  expect_message(
    parsed <- parse_hierarchical_habitat_response(raw, taxon_list = "Gadus morhua",
                                                  habitat_scheme = prompt),
    "no header row"
  )
  expect_equal(nrow(parsed), 1L)
  expect_equal(parsed$taxon_name, "Gadus morhua")
  expect_true(all(c("Marine", "Terrestrial") %in% names(parsed)))
  # a field count that matches no layout is left alone (and still errors clearly)
  expect_error(
    suppressMessages(parse_hierarchical_habitat_response("Gadus morhua,0.95", taxon_list = "Gadus morhua",
                                                         habitat_scheme = prompt))
  )
})

# ---- compound labels: derived as the max over the parts --------------------

test_that("a compound label's weight is the max over its parts and the scheme's labels are the habitat columns", {
  scheme <- data.frame(
    l1_name = c("Coastal-Marine-Estuary-Stream", "Coastal-Stream", "Lake"),
    stringsAsFactors = FALSE
  )
  p <- suppressMessages(build_habitat_prompt(c("Pimephales promelas", "Mugil cephalus"),
    habitat_scheme = scheme, compound_sep = "-"))
  raw <- paste(
    "taxon_name,Coastal,Marine,Estuary,Stream,Lake,Other_weight,habitat_best_guess",
    "Pimephales promelas,0.00,0.00,0.10,0.35,0.55,0.00,",
    "Mugil cephalus,0.30,0.50,0.20,0.00,0.00,0.00,",
    sep = "\n"
  )
  out <- parse_hierarchical_habitat_response(raw, taxon_list = p$taxa, habitat_scheme = p)
  # the compound is never below any part
  fm <- out[out$taxon_name == "Pimephales promelas", ]
  expect_equal(fm[["Coastal-Marine-Estuary-Stream"]], 0.45)   # sum(0, 0, 0.10, 0.35)
  expect_equal(fm[["Coastal-Stream"]], 0.35)                  # sum(0, 0.35)
  expect_equal(fm[["Lake"]], 0.55)
  mc <- out[out$taxon_name == "Mugil cephalus", ]
  expect_equal(mc[["Coastal-Marine-Estuary-Stream"]], 1.00)   # sum capped at 1
  expect_equal(mc[["Coastal-Stream"]], 0.30)
  # declared habitat columns are the scheme's labels, not the parts
  expect_identical(attr(out, "habitat_cols"), c(scheme$l1_name, "Other_weight"))
  # the parts are kept for inspection, after the scheme columns
  expect_true(all(c("Coastal", "Marine", "Estuary", "Stream") %in% names(out)))
  expect_lt(match("Lake", names(out)), match("Coastal", names(out)))
  # argmax and breadth run over the scheme's labels
  expect_identical(fm$Habitat, "Lake")
  expect_identical(mc$Habitat, "Coastal-Marine-Estuary-Stream")
  expect_equal(fm$habitat_breadth, 1 / sum((c(0.45, 0.35, 0.55) / 1.35)^2))
})

test_that("compound_rule = 'max' keeps only the largest part", {
  scheme <- data.frame(l1_name = c("Coastal-Marine-Estuary-Stream", "Lake"), stringsAsFactors = FALSE)
  p <- suppressMessages(build_habitat_prompt("Mugil cephalus", habitat_scheme = scheme,
    compound_sep = "-", compound_rule = "max"))
  raw <- "taxon_name,Coastal,Marine,Estuary,Stream,Lake,Other_weight,habitat_best_guess\nMugil cephalus,0.30,0.50,0.20,0.00,0.00,0.00,"
  out <- parse_hierarchical_habitat_response(raw, taxon_list = "Mugil cephalus", habitat_scheme = p)
  expect_equal(out[["Coastal-Marine-Estuary-Stream"]], 0.50)
})

test_that("a part absent from the response leaves the compound at the max of what was returned", {
  scheme <- data.frame(l1_name = c("A-B", "C"), stringsAsFactors = FALSE)
  p <- suppressMessages(build_habitat_prompt("x sp", habitat_scheme = scheme, compound_sep = "-"))
  raw <- "taxon_name,A,C,Other_weight,habitat_best_guess\nx sp,0.7,0.3,0,"
  out <- suppressWarnings(parse_hierarchical_habitat_response(raw, taxon_list = "x sp", habitat_scheme = p))
  expect_equal(out[["A-B"]], 0.7)
  expect_equal(out[["B"]], 0)
})
