# Tests for common_to_scientific()
# LLM-dependent tests are skipped unless a provider is configured.
# All input-validation tests run without LLM access.

# ---- input validation (no LLM needed) ---------------------------------------

test_that("non-character common_names raises error", {
  expect_error(
    common_to_scientific(123),
    "non-empty character vector"
  )
})

test_that("empty common_names raises error", {
  expect_error(
    common_to_scientific(character(0)),
    "non-empty character vector"
  )
})

test_that("non-scalar taxon_group raises error", {
  expect_error(
    common_to_scientific("Robin",
      taxon_group = c("birds", "mammals"),
      llm_fn = identity
    ),
    "single character string"
  )
})

test_that("non-scalar location raises error", {
  expect_error(
    common_to_scientific("Robin",
      location = c("USA", "UK"),
      llm_fn = identity
    ),
    "single character string"
  )
})

test_that("NULL llm_fn raises informative error", {
  expect_error(
    common_to_scientific("Robin", llm_fn = NULL),
    "No LLM function configured"
  )
})

test_that("non-function llm_fn raises error", {
  expect_error(
    common_to_scientific("Robin", llm_fn = "not_a_function"),
    "must be a function"
  )
})

test_that("non-logical verify raises error", {
  expect_error(
    common_to_scientific("Robin", verify = "yes", llm_fn = identity),
    "TRUE or FALSE"
  )
})


# ---- output structure (mock LLM) --------------------------------------------

.mock_llm <- function(prompt, ...) {
  '[{"common_name":"Robin","scientific_name":"Turdus migratorius","notes":""},
    {"common_name":"Song Sparrow","scientific_name":"Melospiza melodia","notes":""}]'
}

test_that("output is a data frame with expected columns", {
  result <- common_to_scientific(
    c("Robin", "Song Sparrow"),
    verify = FALSE,
    llm_fn = .mock_llm
  )
  expect_s3_class(result, "data.frame")
  expected_cols <- c(
    "common_name", "scientific_name_llm",
    "scientific_name_verified", "backbone_id",
    "verified", "notes"
  )
  expect_true(all(expected_cols %in% names(result)))
})

test_that("output has one row per input name", {
  result <- common_to_scientific(
    c("Robin", "Song Sparrow"),
    verify = FALSE,
    llm_fn = .mock_llm
  )
  expect_equal(nrow(result), 2L)
})

test_that("scientific_name_llm populated from mock LLM response", {
  result <- common_to_scientific(
    c("Robin", "Song Sparrow"),
    verify = FALSE,
    llm_fn = .mock_llm
  )
  expect_equal(
    result$scientific_name_llm,
    c("Turdus migratorius", "Melospiza melodia")
  )
})

test_that("verify = FALSE leaves scientific_name_verified as NA", {
  result <- common_to_scientific(
    c("Robin", "Song Sparrow"),
    verify = FALSE,
    llm_fn = .mock_llm
  )
  expect_true(all(is.na(result$scientific_name_verified)))
  expect_true(all(result$verified == FALSE))
})

test_that("malformed LLM response triggers warning and returns NA names", {
  bad_llm <- function(prompt, ...) "this is not json"
  result <- suppressWarnings(
    common_to_scientific("Robin", verify = FALSE, llm_fn = bad_llm)
  )
  expect_true(is.na(result$scientific_name_llm[[1]]))
})

test_that("LLM response wrapped in markdown fences is parsed correctly", {
  fenced_llm <- function(prompt, ...) {
    '```json\n[{"common_name":"Robin","scientific_name":"Turdus migratorius","notes":""}]\n```'
  }
  result <- suppressWarnings(
    common_to_scientific("Robin", verify = FALSE, llm_fn = fenced_llm)
  )
  expect_equal(result$scientific_name_llm, "Turdus migratorius")
})

test_that("null scientific_name in LLM response becomes NA", {
  null_llm <- function(prompt, ...) {
    '[{"common_name":"Hawk","scientific_name":null,"notes":"Too coarse"}]'
  }
  result <- common_to_scientific("Hawk", verify = FALSE, llm_fn = null_llm)
  expect_true(is.na(result$scientific_name_llm))
  expect_equal(result$notes, "Too coarse")
})

test_that("backbone_id is integer in output", {
  result <- common_to_scientific(
    "Robin",
    verify = FALSE, llm_fn = .mock_llm, backbone_id = 11L
  )
  expect_type(result$backbone_id, "integer")
  expect_equal(result$backbone_id, 11L)
})


# ==============================================================================
# Tests for scientific_to_common()
# ==============================================================================

# ---- input validation --------------------------------------------------------

test_that("non-character scientific_names raises error", {
  expect_error(
    scientific_to_common(123, use_llm = FALSE),
    "non-empty character vector"
  )
})

test_that("empty scientific_names raises error", {
  expect_error(
    scientific_to_common(character(0), use_llm = FALSE),
    "non-empty character vector"
  )
})

test_that("unsupported backbone_id warns and falls through to LLM", {
  mock_llm <- function(prompt, ...) {
    '[{"scientific_name":"Homo sapiens","common_name":"human","common_name_alternatives":null}]'
  }
  expect_warning(
    scientific_to_common("Homo sapiens", backbone_id = 9L, llm_fn = mock_llm),
    "not supported"
  )
})

test_that("NULL llm_fn with use_llm = TRUE raises error", {
  expect_error(
    scientific_to_common("Homo sapiens",
      backbone_id = NULL,
      use_llm = TRUE, llm_fn = NULL
    ),
    "No LLM function configured"
  )
})

test_that("non-logical use_llm raises error", {
  expect_error(
    scientific_to_common("Homo sapiens", use_llm = "yes", llm_fn = NULL),
    "TRUE or FALSE"
  )
})

test_that("non-function llm_fn raises error", {
  expect_error(
    scientific_to_common("Homo sapiens",
      backbone_id = NULL,
      llm_fn = "not_a_function"
    ),
    "must be a function"
  )
})


# ---- output structure (mocked backbone + LLM) --------------------------------

.mock_gbif <- function(name) {
  list(primary = "rainbow trout", alternatives = "steelhead; redband trout")
}

.mock_llm_s2c <- function(prompt, ...) {
  '[{"scientific_name":"Salmo salar","common_name":"Atlantic salmon","common_name_alternatives":"salmon"}]'
}

test_that("output is a data frame with expected columns", {
  local_mocked_bindings(.gbif_common_names = .mock_gbif, .package = "TaxaTools")
  result <- scientific_to_common("Oncorhynchus mykiss",
    backbone_id = 11L,
    use_llm = FALSE, llm_fn = NULL
  )
  expect_s3_class(result, "data.frame")
  expect_true(all(c(
    "scientific_name", "common_name",
    "common_name_alternatives", "source",
    "backbone_id"
  ) %in% names(result)))
})

test_that("output has one row per input name", {
  local_mocked_bindings(.gbif_common_names = .mock_gbif, .package = "TaxaTools")
  result <- scientific_to_common(c("Oncorhynchus mykiss", "Oncorhynchus nerka"),
    backbone_id = 11L, use_llm = FALSE, llm_fn = NULL
  )
  expect_equal(nrow(result), 2L)
})

test_that("backbone hit sets source to 'gbif' and backbone_id to 11", {
  local_mocked_bindings(.gbif_common_names = .mock_gbif, .package = "TaxaTools")
  result <- scientific_to_common("Oncorhynchus mykiss",
    backbone_id = 11L,
    use_llm = FALSE, llm_fn = NULL
  )
  expect_equal(result$source, "gbif")
  expect_equal(result$backbone_id, 11L)
  expect_equal(result$common_name, "rainbow trout")
  expect_equal(result$common_name_alternatives, "steelhead; redband trout")
})

test_that("backbone hit sets source to 'itis' and backbone_id to 3", {
  local_mocked_bindings(.itis_common_names = .mock_gbif, .package = "TaxaTools")
  result <- scientific_to_common("Oncorhynchus mykiss",
    backbone_id = 3L,
    use_llm = FALSE, llm_fn = NULL
  )
  expect_equal(result$source, "itis")
  expect_equal(result$backbone_id, 3L)
})

test_that("backbone miss with use_llm = TRUE falls back to LLM", {
  local_mocked_bindings(
    .gbif_common_names = function(name) NULL,
    .package = "TaxaTools"
  )
  result <- scientific_to_common("Salmo salar",
    backbone_id = 11L,
    use_llm = TRUE, llm_fn = .mock_llm_s2c
  )
  expect_equal(result$source, "llm")
  expect_equal(result$common_name, "Atlantic salmon")
})

test_that("backbone miss with use_llm = FALSE returns source 'none' and NA common_name", {
  local_mocked_bindings(
    .gbif_common_names = function(name) NULL,
    .package = "TaxaTools"
  )
  result <- scientific_to_common("Rare taxon sp.",
    backbone_id = 11L,
    use_llm = FALSE, llm_fn = NULL
  )
  expect_equal(result$source, "none")
  expect_true(is.na(result$common_name))
})

test_that("backbone_id = NULL goes straight to LLM for all names", {
  result <- scientific_to_common("Salmo salar",
    backbone_id = NULL,
    llm_fn = .mock_llm_s2c
  )
  expect_equal(result$source, "llm")
  expect_equal(result$common_name, "Atlantic salmon")
  expect_true(is.na(result$backbone_id))
})

test_that("location param is accepted and passed to LLM without error", {
  captured <- NULL
  capture_llm <- function(prompt, ...) {
    captured <<- prompt
    '[{"scientific_name":"Salmo salar","common_name":"Atlantic salmon","common_name_alternatives":null}]'
  }
  result <- scientific_to_common("Salmo salar",
    backbone_id = NULL,
    location = "Pacific Northwest, USA",
    llm_fn = capture_llm
  )
  expect_equal(result$common_name, "Atlantic salmon")
  expect_true(grepl("Pacific Northwest", captured))
})

test_that("non-scalar location raises error", {
  expect_error(
    scientific_to_common("Salmo salar",
      location = c("USA", "UK"),
      backbone_id = NULL, llm_fn = .mock_llm_s2c
    ),
    "single character string"
  )
})

test_that("LLM null common_name returns NA and source 'none'", {
  null_llm <- function(prompt, ...) {
    '[{"scientific_name":"Obscura sp.","common_name":null,"common_name_alternatives":null}]'
  }
  result <- scientific_to_common("Obscura sp.",
    backbone_id = NULL,
    llm_fn = null_llm
  )
  expect_true(is.na(result$common_name))
  expect_equal(result$source, "none")
})

test_that("malformed LLM response warns and returns NA common_name", {
  bad_llm <- function(prompt, ...) "not json"
  result <- suppressWarnings(
    scientific_to_common("Salmo salar", backbone_id = NULL, llm_fn = bad_llm)
  )
  expect_true(is.na(result$common_name))
})

test_that("LLM response wrapped in markdown fences is parsed correctly", {
  fenced_llm <- function(prompt, ...) {
    '```json\n[{"scientific_name":"Salmo salar","common_name":"Atlantic salmon","common_name_alternatives":null}]\n```'
  }
  result <- scientific_to_common("Salmo salar",
    backbone_id = NULL,
    llm_fn = fenced_llm
  )
  expect_equal(result$common_name, "Atlantic salmon")
})

test_that("backbone_id is integer NA for llm-sourced rows", {
  result <- scientific_to_common("Salmo salar",
    backbone_id = NULL,
    llm_fn = .mock_llm_s2c
  )
  expect_type(result$backbone_id, "integer")
  expect_true(is.na(result$backbone_id))
})

test_that("mixed batch: backbone hit for first, LLM fallback for second", {
  local_mocked_bindings(
    .gbif_common_names = function(name) {
      if (name == "Oncorhynchus mykiss") .mock_gbif(name) else NULL
    },
    .package = "TaxaTools"
  )
  result <- scientific_to_common(c("Oncorhynchus mykiss", "Salmo salar"),
    backbone_id = 11L, use_llm = TRUE,
    llm_fn = .mock_llm_s2c
  )
  expect_equal(result$source, c("gbif", "llm"))
  expect_equal(result$common_name, c("rainbow trout", "Atlantic salmon"))
})


# ---- cache_dir + verbose (2026-09-12) ----------------------------------------

# An LLM mock that answers every name in the prompt and counts its calls.
.make_counting_llm <- function(known, null_for = character(0), garbage = FALSE) {
  calls <- new.env(parent = emptyenv()); calls$n <- 0L
  fn <- function(prompt, ...) {
    calls$n <- calls$n + 1L
    if (garbage) return("not json at all")
    asked <- known[vapply(known, function(k) grepl(k, prompt, fixed = TRUE), logical(1))]
    rows <- vapply(asked, function(k) {
      cn <- if (k %in% null_for) "null" else sprintf('"%s common"', tolower(sub(" .*", "", k)))
      sprintf('{"scientific_name":"%s","common_name":%s,"common_name_alternatives":null}', k, cn)
    }, character(1))
    paste0("[", paste(rows, collapse = ","), "]")
  }
  list(fn = fn, calls = calls)
}

test_that("cache_dir: a second identical call is served with zero LLM calls", {
  cache_dir <- withr::local_tempdir()
  taxa <- c("Salmo salar", "Oncorhynchus mykiss")
  llm <- .make_counting_llm(taxa)
  first <- suppressMessages(scientific_to_common(taxa,
    backbone_id = NULL, location = "North Pacific",
    llm_fn = llm$fn, cache_dir = cache_dir
  ))
  expect_equal(llm$calls$n, 1L)
  expect_equal(first$source, c("llm", "llm"))
  expect_length(list.files(cache_dir, pattern = "_common_name\\.rds$"), 2L)

  never <- function(prompt, ...) stop("the LLM must not be called on a full cache hit")
  second <- suppressMessages(scientific_to_common(taxa,
    backbone_id = NULL, location = "North Pacific",
    llm_fn = never, cache_dir = cache_dir
  ))
  expect_equal(second$common_name, first$common_name)
  expect_equal(second$source, first$source)
})

test_that("cache_dir: a different location is a cache miss; a case/space variant is a hit", {
  cache_dir <- withr::local_tempdir()
  llm <- .make_counting_llm("Salmo salar")
  suppressMessages(scientific_to_common("Salmo salar",
    backbone_id = NULL, location = "Atlantic", llm_fn = llm$fn, cache_dir = cache_dir
  ))
  llm2 <- .make_counting_llm("Salmo salar")
  suppressMessages(scientific_to_common("Salmo salar",
    backbone_id = NULL, location = "Pacific", llm_fn = llm2$fn, cache_dir = cache_dir
  ))
  expect_equal(llm2$calls$n, 1L)
  never <- function(prompt, ...) stop("must be a cache hit")
  out <- suppressMessages(scientific_to_common("  salmo salar ",
    backbone_id = NULL, location = "Atlantic", llm_fn = never, cache_dir = cache_dir
  ))
  expect_equal(out$source, "llm")
})

test_that("cache_dir: a parsed 'no common name' answer is cached, an unparseable batch is not", {
  cache_dir <- withr::local_tempdir()
  llm <- .make_counting_llm("Pseudo-nitzschia delicatissima", null_for = "Pseudo-nitzschia delicatissima")
  out <- suppressMessages(scientific_to_common("Pseudo-nitzschia delicatissima",
    backbone_id = NULL, llm_fn = llm$fn, cache_dir = cache_dir
  ))
  expect_true(is.na(out$common_name))
  expect_length(list.files(cache_dir, pattern = "_common_name\\.rds$"), 1L)
  never <- function(prompt, ...) stop("must be a cache hit")
  expect_no_error(suppressMessages(scientific_to_common("Pseudo-nitzschia delicatissima",
    backbone_id = NULL, llm_fn = never, cache_dir = cache_dir
  )))

  cache_dir2 <- withr::local_tempdir()
  bad <- .make_counting_llm("Salmo salar", garbage = TRUE)
  suppressWarnings(suppressMessages(scientific_to_common("Salmo salar",
    backbone_id = NULL, llm_fn = bad$fn, cache_dir = cache_dir2
  )))
  expect_length(list.files(cache_dir2, pattern = "_common_name\\.rds$"), 0L)
})

test_that("cache_dir: a backbone miss on a use_llm = FALSE call is not cached", {
  cache_dir <- withr::local_tempdir()
  local_mocked_bindings(.gbif_common_names = function(name) NULL, .package = "TaxaTools")
  suppressMessages(scientific_to_common("Rare taxon sp.",
    backbone_id = 11L, use_llm = FALSE, llm_fn = NULL, cache_dir = cache_dir
  ))
  expect_length(list.files(cache_dir, pattern = "_common_name\\.rds$"), 0L)
})

test_that("verbose = TRUE reports the summary and one line per LLM batch", {
  taxa <- sprintf("Genus%02d species", 1:25)
  llm <- .make_counting_llm(taxa)
  msgs <- character(0)
  withCallingHandlers(
    scientific_to_common(taxa, backbone_id = NULL, llm_fn = llm$fn, verbose = TRUE),
    message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") }
  )
  expect_true(any(grepl("25 name\\(s\\) -- 0 from cache, 0 resolved by backbone, 25 to the LLM in 2 batch", msgs)))
  expect_true(any(grepl("LLM batch 1/2 \\(20 name", msgs)))
  expect_true(any(grepl("LLM batch 2/2 \\(5 name", msgs)))
  expect_equal(llm$calls$n, 2L)
  expect_silent(scientific_to_common(taxa[1:2], backbone_id = NULL, llm_fn = llm$fn, verbose = FALSE))
})

test_that("taxatools_clear_cache() reports and removes the common-name cache files", {
  cache_dir <- withr::local_tempdir()
  llm <- .make_counting_llm(c("Salmo salar", "Oncorhynchus mykiss"))
  suppressMessages(scientific_to_common(c("Salmo salar", "Oncorhynchus mykiss"),
    backbone_id = NULL, llm_fn = llm$fn, cache_dir = cache_dir
  ))
  inv <- suppressMessages(taxatools_clear_cache(cache_dir, dry_run = TRUE))
  expect_equal(nrow(inv), 2L)
  expect_length(list.files(cache_dir, pattern = "_common_name\\.rds$"), 2L)
  suppressMessages(taxatools_clear_cache(cache_dir))
  expect_length(list.files(cache_dir, pattern = "_common_name\\.rds$"), 0L)
})

test_that("scientific_to_common() validates cache_dir and verbose", {
  expect_error(scientific_to_common("Salmo salar", backbone_id = NULL, llm_fn = function(p, ...) "[]", cache_dir = c("a", "b")), "cache_dir")
  expect_error(scientific_to_common("Salmo salar", backbone_id = NULL, llm_fn = function(p, ...) "[]", verbose = NA), "verbose")
})
