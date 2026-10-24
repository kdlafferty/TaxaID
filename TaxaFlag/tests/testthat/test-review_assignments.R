# --- Mock LLM function ---
# Returns canned JSON for known taxa; simulates real LLM behavior

mock_llm_fn <- function(prompt_str, ...) {
  # Return a realistic JSON response for Palmyra Atoll reef taxa
  '[
    {"taxon_name": "Carcharhinus melanopterus", "p_habitat": 0.95, "p_geographic": 0.95, "p_scope": 0.95, "p_contamination": 0.02, "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": "Blacktip reef shark, common on Pacific coral reefs"},
    {"taxon_name": "Homo sapiens", "p_habitat": 0.03, "p_geographic": 0.95, "p_scope": 0.03, "p_contamination": 0.95, "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": "Common lab contaminant in eDNA studies"},
    {"taxon_name": "Gobiidae", "p_habitat": 0.95, "p_geographic": 0.95, "p_scope": 0.95, "p_contamination": 0.02, "review_alternatives": null, "review_lower_hypotheses": "Eviota sp., Trimma sp.", "review_confidence": "moderate", "review_comment": "Diverse family on coral reefs; many cryptic species"},
    {"taxon_name": "Salmo salar", "p_habitat": 0.03, "p_geographic": 0.03, "p_scope": 0.95, "p_contamination": 0.35, "review_alternatives": "Lutjanus bohar, Lutjanus kasmira", "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": "Atlantic salmon; not found in central Pacific. Possible food-source contaminant"},
    {"taxon_name": "Bos taurus", "p_habitat": 0.03, "p_geographic": 0.03, "p_scope": 0.03, "p_contamination": 0.95, "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": "Domestic cattle; common food-source contaminant"}
  ]'
}


# --- Mock consensus data ---
mock_consensus <- data.frame(
  observation_id = c("S1", "S1", "S2", "S2", "S3"),
  consensus_taxon = c(
    "Carcharhinus melanopterus", "Homo sapiens",
    "Gobiidae", "Salmo salar", "Bos taurus"
  ),
  consensus_rank = c("species", "species", "family", "species", "species"),
  stringsAsFactors = FALSE
)

mock_context <- list(
  geography = "Palmyra Atoll, central Pacific",
  habitat   = "coral reef"
)


# ===========================================================================
# Basic functionality
# ===========================================================================

test_that("review_assignments adds 8 columns", {
  result <- review_assignments(
    data_type = "eDNA",
    input_df = mock_consensus,
    taxon_col = "consensus_taxon",
    context = mock_context,
    target_group = "fish",
    llm_fn = mock_llm_fn,
    verbose = FALSE
  )

  expect_true("llm_habitat_plausibility" %in% names(result))
  expect_true("llm_geographic_plausibility" %in% names(result))
  expect_true("llm_scope_plausibility" %in% names(result))
  expect_true("llm_contamination_risk" %in% names(result))
  expect_true("review_alternatives" %in% names(result))
  expect_true("review_lower_hypotheses" %in% names(result))
  expect_true("review_confidence" %in% names(result))
  expect_true("review_comment" %in% names(result))
  expect_equal(nrow(result), nrow(mock_consensus))
})

test_that("review values are correct for known taxa", {
  result <- review_assignments(
    data_type = "eDNA",
    input_df = mock_consensus,
    taxon_col = "consensus_taxon",
    context = mock_context,
    target_group = "fish",
    llm_fn = mock_llm_fn,
    verbose = FALSE
  )

  # Homo sapiens should be flagged as contaminant
  hs <- result[result$consensus_taxon == "Homo sapiens", ]
  expect_equal(hs$llm_contamination_risk, "high")
  expect_equal(hs$llm_scope_plausibility, "unlikely")

  # Carcharhinus melanopterus should be expected
  cm <- result[result$consensus_taxon == "Carcharhinus melanopterus", ]
  expect_equal(cm$llm_habitat_plausibility, "likely")
  expect_equal(cm$llm_geographic_plausibility, "likely")
  expect_equal(cm$llm_contamination_risk, "low")
})

test_that("alternatives populated for implausible taxa", {
  result <- review_assignments(
    data_type = "eDNA",
    input_df = mock_consensus,
    taxon_col = "consensus_taxon",
    context = mock_context,
    target_group = "fish",
    llm_fn = mock_llm_fn,
    verbose = FALSE
  )

  ss <- result[result$consensus_taxon == "Salmo salar", ]
  expect_true(!is.na(ss$review_alternatives))
  expect_true(grepl("Lutjanus", ss$review_alternatives))
})


# ===========================================================================
# taxon_rank_col and lower hypotheses
# ===========================================================================

test_that("review_lower_hypotheses populated when taxon_rank_col supplied", {
  result <- review_assignments(
    data_type = "eDNA",
    input_df = mock_consensus,
    taxon_col = "consensus_taxon",
    taxon_rank_col = "consensus_rank",
    context = mock_context,
    target_group = "fish",
    llm_fn = mock_llm_fn,
    verbose = FALSE
  )

  gov <- result[result$consensus_taxon == "Gobiidae", ]
  expect_true(!is.na(gov$review_lower_hypotheses))
})

test_that("review_lower_hypotheses is NA when taxon_rank_col not supplied", {
  result <- review_assignments(
    data_type = "eDNA",
    input_df = mock_consensus,
    taxon_col = "consensus_taxon",
    context = mock_context,
    target_group = "fish",
    llm_fn = mock_llm_fn,
    verbose = FALSE
  )

  # All lower_hypotheses should be NA when no rank column
  expect_true(all(is.na(result$review_lower_hypotheses)))
})


# ===========================================================================
# target_group controls scope_plausibility
# ===========================================================================

test_that("scope_plausibility is NA when target_group not supplied", {
  result <- review_assignments(
    data_type = "eDNA",
    input_df = mock_consensus,
    taxon_col = "consensus_taxon",
    context = mock_context,
    llm_fn = mock_llm_fn,
    verbose = FALSE
  )

  expect_true(all(is.na(result$llm_scope_plausibility)))
})


# ===========================================================================
# Context normalisation
# ===========================================================================

test_that("build_context() style data frame works as context", {
  ctx_df <- data.frame(
    ecoregion = "Central Pacific",
    main_habitat = "coral reef",
    date = "2025",
    stringsAsFactors = FALSE
  )

  result <- review_assignments(
    data_type = "eDNA",
    input_df = mock_consensus,
    taxon_col = "consensus_taxon",
    context = ctx_df,
    llm_fn = mock_llm_fn,
    verbose = FALSE
  )

  expect_equal(nrow(result), nrow(mock_consensus))
})


# ===========================================================================
# Error handling
# ===========================================================================

test_that("graceful handling of LLM failure", {
  fail_fn <- function(prompt_str, ...) stop("API error")

  expect_warning(
    result <- review_assignments(
      data_type = "eDNA",
      input_df = mock_consensus,
      taxon_col = "consensus_taxon",
      context = mock_context,
      llm_fn = fail_fn,
      verbose = FALSE
    ),
    "LLM call failed"
  )

  # Should still return all rows with NA review columns
  expect_equal(nrow(result), nrow(mock_consensus))
  expect_true(all(is.na(result$llm_habitat_plausibility)))
})

test_that("graceful handling of invalid JSON response", {
  bad_fn <- function(prompt_str, ...) "This is not JSON at all"

  expect_warning(
    result <- review_assignments(
      data_type = "eDNA",
      input_df = mock_consensus,
      taxon_col = "consensus_taxon",
      context = mock_context,
      llm_fn = bad_fn,
      verbose = FALSE
    ),
    "Could not parse"
  )

  expect_equal(nrow(result), nrow(mock_consensus))
  expect_true(all(is.na(result$llm_habitat_plausibility)))
})

test_that("graceful handling of partial LLM response", {
  # Returns only 2 of 5 taxa
  partial_fn <- function(prompt_str, ...) {
    '[
      {"taxon_name": "Carcharhinus melanopterus", "p_habitat": 0.95, "p_geographic": 0.95, "p_scope": null, "p_contamination": 0.02, "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": null},
      {"taxon_name": "Homo sapiens", "p_habitat": 0.03, "p_geographic": 0.95, "p_scope": null, "p_contamination": 0.95, "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": null}
    ]'
  }

  expect_warning(
    result <- review_assignments(
      data_type = "eDNA",
      input_df = mock_consensus,
      taxon_col = "consensus_taxon",
      context = mock_context,
      llm_fn = partial_fn,
      verbose = FALSE
    ),
    "omitted"
  )

  # All rows should be present
  expect_equal(nrow(result), nrow(mock_consensus))
  # The two returned taxa should have values
  cm <- result[result$consensus_taxon == "Carcharhinus melanopterus", ]
  expect_equal(cm$llm_habitat_plausibility, "likely")
  # The missing taxa should have NA
  bt <- result[result$consensus_taxon == "Bos taurus", ]
  expect_true(is.na(bt$llm_habitat_plausibility))
})


# ===========================================================================
# Retry-on-truncation and max_tokens
# ===========================================================================

test_that("truncated batch is recovered via automatic retry with smaller sub-batches", {
  call_sizes <- integer(0)

  retry_fn <- function(prompt_str, ...) {
    # Only the "TAXA TO REVIEW:" block uses "- " lines for taxa; GUIDELINES
    # above it also has "- " bullet lines, so slice those out first.
    taxa_section <- sub("(?s).*TAXA TO REVIEW:\\n", "", prompt_str, perl = TRUE)
    taxa_lines <- regmatches(taxa_section, gregexpr("(?m)^- (.+)$", taxa_section, perl = TRUE))[[1]]
    n <- length(taxa_lines)
    call_sizes <<- c(call_sizes, n)

    build_obj <- function(line) {
      name <- sub("^- ", "", line)
      name <- sub("\\s*\\(.*\\)$", "", name)
      sprintf(
        '{"taxon_name": "%s", "p_habitat": 0.95, "p_geographic": 0.95, "p_scope": null, "p_contamination": 0.02, "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": null}',
        name
      )
    }
    objs <- vapply(taxa_lines, build_obj, character(1))

    if (n > 2L) {
      # Simulate a response cut off by max_tokens: only the first 2 objects,
      # no closing bracket.
      paste0("[\n", paste(objs[seq_len(2L)], collapse = ",\n"))
    } else {
      paste0("[\n", paste(objs, collapse = ",\n"), "\n]")
    }
  }

  expect_silent(
    result <- review_assignments(
      data_type = "eDNA",
      input_df = mock_consensus,
      taxon_col = "consensus_taxon",
      context = mock_context,
      llm_fn = retry_fn,
      max_retries = 3L,
      pause_seconds = 0,
      verbose = FALSE
    )
  )

  # 5 unique taxa truncate at batch size 5; retry-splitting keeps halving
  # until every leaf batch is small enough (<=2) to return a complete response.
  expect_false(any(is.na(result$llm_habitat_plausibility)))
  expect_true(any(call_sizes > 2L))
  expect_true(any(call_sizes <= 2L))
})

test_that("hard llm_fn errors are not retried -- a smaller batch can't fix a broken call", {
  call_count <- 0L
  fail_fn <- function(prompt_str, ...) {
    call_count <<- call_count + 1L
    stop("API error")
  }

  expect_warning(
    result <- review_assignments(
      data_type = "eDNA",
      input_df = mock_consensus,
      taxon_col = "consensus_taxon",
      context = mock_context,
      llm_fn = fail_fn,
      max_retries = 3L,
      pause_seconds = 0,
      verbose = FALSE
    ),
    "LLM call failed"
  )

  expect_equal(call_count, 1L)
  expect_true(all(is.na(result$llm_habitat_plausibility)))
})

test_that("max_retries = 0 disables retry, matching pre-retry behavior", {
  call_count <- 0L
  partial_fn <- function(prompt_str, ...) {
    call_count <<- call_count + 1L
    '[
      {"taxon_name": "Carcharhinus melanopterus", "p_habitat": 0.95, "p_geographic": 0.95, "p_scope": null, "p_contamination": 0.02, "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": null}
    ]'
  }

  expect_warning(
    result <- review_assignments(
      data_type = "eDNA",
      input_df = mock_consensus,
      taxon_col = "consensus_taxon",
      context = mock_context,
      llm_fn = partial_fn,
      max_retries = 0L,
      pause_seconds = 0,
      verbose = FALSE
    ),
    "omitted"
  )

  expect_equal(call_count, 1L)
  bt <- result[result$consensus_taxon == "Bos taurus", ]
  expect_true(is.na(bt$llm_habitat_plausibility))
})

test_that("max_tokens is forwarded to llm_fn when supplied", {
  captured <- NULL
  capture_fn <- function(prompt_str, ...) {
    captured <<- list(...)
    mock_llm_fn(prompt_str)
  }

  review_assignments(
    data_type = "eDNA",
    input_df = mock_consensus,
    taxon_col = "consensus_taxon",
    context = mock_context,
    llm_fn = capture_fn,
    max_tokens = 6000L,
    verbose = FALSE
  )

  expect_equal(captured$max_tokens, 6000L)
})

test_that("max_tokens defaults to NULL and is not forwarded to llm_fn", {
  captured <- list(untouched = TRUE)
  capture_fn <- function(prompt_str, ...) {
    captured <<- list(...)
    mock_llm_fn(prompt_str)
  }

  review_assignments(
    data_type = "eDNA",
    input_df = mock_consensus,
    taxon_col = "consensus_taxon",
    context = mock_context,
    llm_fn = capture_fn,
    verbose = FALSE
  )

  expect_equal(length(captured), 0L)
})


# ===========================================================================
# Input validation
# ===========================================================================

test_that("error when taxon column missing", {
  expect_error(
    review_assignments(data_type = "eDNA", mock_consensus,
      taxon_col = "nonexistent",
      context = mock_context, llm_fn = mock_llm_fn,
      verbose = FALSE
    ),
    "not found"
  )
})

test_that("error when context missing", {
  expect_error(
    review_assignments(data_type = "eDNA", mock_consensus,
      taxon_col = "consensus_taxon",
      llm_fn = mock_llm_fn, verbose = FALSE
    ),
    "context.*required"
  )
})

test_that("error when taxon_rank_col not in input_df", {
  expect_error(
    review_assignments(data_type = "eDNA", mock_consensus,
      taxon_col = "consensus_taxon",
      taxon_rank_col = "nonexistent",
      context = mock_context, llm_fn = mock_llm_fn,
      verbose = FALSE
    ),
    "not found"
  )
})


# ===========================================================================
# Row order preservation
# ===========================================================================

test_that("output row order matches input", {
  result <- review_assignments(
    data_type = "eDNA",
    input_df = mock_consensus,
    taxon_col = "consensus_taxon",
    context = mock_context,
    llm_fn = mock_llm_fn,
    verbose = FALSE
  )

  expect_equal(result$consensus_taxon, mock_consensus$consensus_taxon)
  expect_equal(result$observation_id, mock_consensus$observation_id)
})

# ---------------------------------------------------------------------------
# Echoed-annotation recovery (2026-09-04). The prompt decorates an unresolved
# candidate set as "<label> (unresolved candidates; consensus rank: <rank>)"
# and the model frequently echoes the decorated string back as taxon_name.
# Singletons carry no annotation, so they always matched while every
# multi-candidate row silently returned NA and was then dropped by the
# workflows' export filters. GreatLakes 2026-09-04: 113 of 885 rows.
# ---------------------------------------------------------------------------

test_that("a model that echoes the annotated label still joins back to its rows", {
  df <- data.frame(
    observation_id = c("o1", "o2", "o3"),
    consensus_taxon = c("Lepomis", "Lepomis", "Perca flavescens"),
    consensus_rank = c("genus", "genus", "species"),
    consensus_OTU = c(
      "Lepomis macrochirus/gibbosus",
      "Lepomis gibbosus/macrochirus", # reversed display order
      "Perca flavescens"
    ),
    plausible_taxa = I(list(
      c("Lepomis macrochirus", "Lepomis gibbosus"),
      c("Lepomis gibbosus", "Lepomis macrochirus"),
      "Perca flavescens"
    )),
    stringsAsFactors = FALSE
  )
  # Model echoes the decorated label for the unresolved set, plain for the singleton
  fake_llm <- function(prompt, ...) {
    labs <- regmatches(prompt, gregexpr("(?m)^- .*$", prompt, perl = TRUE))[[1]]
    labs <- sub("^- ", "", labs)
    # only the taxon lines, not the instruction bullets
    labs <- grep("\\((unresolved candidates|rank: )", labs, value = TRUE)
    # echo the DECORATED string verbatim for unresolved sets (the real failure
    # mode); strip the plain "(rank: x)" annotation for singletons, as the
    # model does in practice
    labs <- ifelse(grepl("unresolved candidates", labs), labs,
      sub("\\s*\\(rank: [^()]*\\)$", "", labs)
    )
    paste0("[", paste(sprintf(
      '{"taxon_name":"%s","p_habitat": 0.95,"p_geographic": 0.95,
        "p_scope": 0.95,"p_contamination": 0.02,"review_alternatives":null,
        "review_lower_hypotheses":null,"review_confidence":"high","review_comment":"ok"}',
      labs
    ), collapse = ","), "]")
  }
  out <- review_assignments(data_type = "eDNA", df,
    taxon_col = "consensus_taxon",
    taxon_rank_col = "consensus_rank",
    context = list(
      geography = "Lake Michigan",
      habitat = "harbor"
    ),
    plausible_taxa_col = "plausible_taxa",
    irreducible_only = FALSE, taxa_per_call = 10L,
    llm_fn = fake_llm, verbose = FALSE
  )
  # every row scored -- no silent NA on the multi-candidate rows
  expect_false(any(is.na(out$llm_habitat_plausibility)))
  expect_equal(unique(out$llm_habitat_plausibility), "likely")
})

# ---------------------------------------------------------------------------
# review cache (2026-09-04). The review is a JUDGEMENT and an uncached one is
# not reproducible: two GreatLakes runs 50 minutes apart on identical input
# disagreed about Pimephales vigilax ("possible" then "unlikely"), so it was in
# one species list and not the other.
# ---------------------------------------------------------------------------

.cache_fixture <- function() {
  data.frame(
    observation_id = c("o1", "o2", "o3"),
    consensus_taxon = c("Lepomis", "Lepomis", "Perca flavescens"),
    consensus_rank = c("genus", "genus", "species"),
    consensus_OTU = c(
      "Lepomis macrochirus/gibbosus",
      "Lepomis gibbosus/macrochirus", "Perca flavescens"
    ),
    plausible_taxa = I(list(
      c("Lepomis macrochirus", "Lepomis gibbosus"),
      c("Lepomis gibbosus", "Lepomis macrochirus"),
      "Perca flavescens"
    )),
    stringsAsFactors = FALSE
  )
}

.counting_llm <- function(counter) {
  function(prompt, ...) {
    assign("n", get("n", counter) + 1L, counter)
    labs <- sub("^- ", "", regmatches(prompt, gregexpr("(?m)^- .*$", prompt, perl = TRUE))[[1]])
    labs <- grep("\\((unresolved candidates|rank: )", labs, value = TRUE)
    labs <- ifelse(grepl("unresolved candidates", labs), labs,
      sub("\\s*\\(rank: [^()]*\\)$", "", labs)
    )
    paste0("[", paste(sprintf(
      '{"taxon_name":"%s","p_habitat": 0.95,"p_geographic": 0.95,"p_scope": 0.95,"p_contamination": 0.02,"review_alternatives":null,"review_lower_hypotheses":null,"review_confidence":"high","review_comment":"ok"}',
      labs
    ), collapse = ","), "]")
  }
}

test_that("a cached review is reproducible and makes no second LLM call", {
  cd <- file.path(tempdir(), paste0("flagcache_", as.integer(runif(1, 1, 1e8))))
  on.exit(unlink(cd, recursive = TRUE), add = TRUE)
  ctr <- new.env()
  assign("n", 0L, ctr)
  args <- list(.cache_fixture(),
    taxon_col = "consensus_taxon",
    taxon_rank_col = "consensus_rank",
    context = list(geography = "Lake Michigan", habitat = "harbor"),
    plausible_taxa_col = "plausible_taxa", irreducible_only = FALSE,
    taxa_per_call = 10L, llm_fn = .counting_llm(ctr), data_type = "eDNA",
    model_label = "test-model", cache_dir = cd, verbose = FALSE
  )
  a <- do.call(review_assignments, args)
  first <- get("n", ctr)
  expect_gt(first, 0L)
  b <- do.call(review_assignments, args)
  expect_equal(get("n", ctr), first) # no further calls
  expect_equal(a$llm_habitat_plausibility, b$llm_habitat_plausibility)
  expect_false(any(is.na(b$llm_habitat_plausibility)))
})

test_that("changing the review context is a cache MISS, not a stale hit", {
  cd <- file.path(tempdir(), paste0("flagcache_", as.integer(runif(1, 1, 1e8))))
  on.exit(unlink(cd, recursive = TRUE), add = TRUE)
  ctr <- new.env()
  assign("n", 0L, ctr)
  base <- list(.cache_fixture(),
    taxon_col = "consensus_taxon",
    taxon_rank_col = "consensus_rank",
    context = list(geography = "Lake Michigan", habitat = "harbor"),
    plausible_taxa_col = "plausible_taxa", irreducible_only = FALSE,
    taxa_per_call = 10L, llm_fn = .counting_llm(ctr), data_type = "eDNA",
    model_label = "test-model", cache_dir = cd, verbose = FALSE
  )
  invisible(do.call(review_assignments, base))
  n1 <- get("n", ctr)
  moved <- base
  moved$context <- list(geography = "Chesapeake Bay", habitat = "harbor")
  invisible(do.call(review_assignments, moved))
  expect_gt(get("n", ctr), n1)
})

test_that("cache files are the file-per-key shape taxaflag_clear_cache() manages", {
  cd <- file.path(tempdir(), paste0("flagcache_", as.integer(runif(1, 1, 1e8))))
  on.exit(unlink(cd, recursive = TRUE), add = TRUE)
  ctr <- new.env()
  assign("n", 0L, ctr)
  invisible(review_assignments(.cache_fixture(),
    taxon_col = "consensus_taxon",
    taxon_rank_col = "consensus_rank",
    context = list(geography = "Lake Michigan", habitat = "harbor"),
    plausible_taxa_col = "plausible_taxa", irreducible_only = FALSE,
    taxa_per_call = 10L, llm_fn = .counting_llm(ctr), data_type = "eDNA", model_label = "test-model", cache_dir = cd, verbose = FALSE
  ))
  inv <- taxaflag_clear_cache(cache_dir = cd, dry_run = TRUE)
  expect_gt(nrow(inv), 0L)
  expect_true(all(grepl("_review\\.rds$", basename(inv$path))))
  expect_true(all(file.exists(inv$path))) # dry_run kept them
  taxaflag_clear_cache(cache_dir = cd)
  expect_equal(nrow(TaxaTools::list_cache_files(cd, .taxaflag_cache_patterns)), 0L)
})

test_that("a hash collision is a miss, never another taxon's verdict", {
  cd <- file.path(tempdir(), paste0("flagcache_", as.integer(runif(1, 1, 1e8))))
  dir.create(cd, recursive = TRUE)
  on.exit(unlink(cd, recursive = TRUE), add = TRUE)
  f <- file.path(cd, "collide_review.rds")
  saveRDS(list(
    key = "SOME OTHER KEY",
    row = data.frame(taxon_name = "Wrong taxon", stringsAsFactors = FALSE)
  ), f)
  expect_null(TaxaFlag:::.review_cache_read(f, "the key we actually want"))
  expect_null(TaxaFlag:::.review_cache_read(file.path(cd, "absent.rds"), "k"))
})

test_that("two candidate sets sharing one display label are reviewed once, and no input row is duplicated", {
  # add_slash_taxon() clears the slash name on a downranked row, so
  # consensus_OTU falls back to consensus_taxon and two genuinely different
  # candidate sets can carry the identical display label. The LLM only ever
  # sees that label, so it must be reviewed once and the verdict fanned out.
  # Before the label dedup, the label went into one batch twice, the
  # taxon_name merges multiplied the review rows, and the final join returned
  # 5 rows for 2 input rows (with one of them unscored).
  df <- data.frame(
    observation_id = c("o1", "o2"),
    consensus_taxon = "Oncorhynchus mykiss",
    consensus_OTU = "Oncorhynchus mykiss",
    irreducible_consensus = TRUE,
    stringsAsFactors = FALSE
  )
  df$plausible_taxa <- list(c("Salmo salar", "Salvelinus alpinus"), "Salmo trutta")

  n_calls <- 0L
  fake_llm <- function(prompt, ...) {
    n_calls <<- n_calls + 1L
    '[{"taxon_name":"Oncorhynchus mykiss","p_habitat": 0.95,
       "p_geographic": 0.95,"p_scope": null,
       "p_contamination": 0.02,"review_alternatives":null,
       "review_lower_hypotheses":null,"review_confidence":"high",
       "review_comment":null}]'
  }
  out <- review_assignments(
    data_type = "eDNA",
    df,
    plausible_taxa_col = "plausible_taxa",
    context = list(geography = "Lake Michigan", habitat = "harbor"),
    llm_fn = fake_llm, verbose = FALSE
  )
  expect_equal(nrow(out), nrow(df))
  expect_equal(out$llm_geographic_plausibility, c("likely", "likely"))
  expect_equal(n_calls, 1L)
})

test_that(".parse_json_text() refuses to treat a model reply as a URL or file path", {
  # jsonlite::fromJSON() accepts a JSON string, a URL, or a file path in the
  # same argument -- a short non-JSON reply that looks like either would be
  # fetched/read instead of failing to parse.
  expect_null(TaxaFlag:::.parse_json_text("https://example.com/whatever.json"))
  tmp <- tempfile(fileext = ".json")
  writeLines('[{"taxon_name":"Trojan sp."}]', tmp)
  on.exit(unlink(tmp), add = TRUE)
  expect_null(TaxaFlag:::.parse_json_text(tmp))
  # ... while still parsing what the real call sites actually pass
  expect_equal(
    TaxaFlag:::.parse_json_text('[{"taxon_name":"Salmo salar"}]')$taxon_name,
    "Salmo salar"
  )
  expect_null(TaxaFlag:::.parse_json_text("This is not JSON at all"))
})



# ===========================================================================
# Omitted taxa: re-ask, residue reporting, and the cache's role
# (2026-09-14 -- see review_assignments()'s @section Unreviewed rows)
# ===========================================================================

.CANNED <- list(
  "Carcharhinus melanopterus" = '{"taxon_name": "Carcharhinus melanopterus", "p_habitat": 0.95, "p_geographic": 0.95, "p_scope": null, "p_contamination": 0.02, "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": null}',
  "Homo sapiens" = '{"taxon_name": "Homo sapiens", "p_habitat": 0.03, "p_geographic": 0.95, "p_scope": null, "p_contamination": 0.95, "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": null}',
  "Gobiidae" = '{"taxon_name": "Gobiidae", "p_habitat": 0.95, "p_geographic": 0.95, "p_scope": null, "p_contamination": 0.02, "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "moderate", "review_comment": null}',
  "Salmo salar" = '{"taxon_name": "Salmo salar", "p_habitat": 0.03, "p_geographic": 0.03, "p_scope": null, "p_contamination": 0.35, "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": null}',
  "Bos taurus" = '{"taxon_name": "Bos taurus", "p_habitat": 0.03, "p_geographic": 0.03, "p_scope": null, "p_contamination": 0.95, "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": null}'
)

# The real failure mode this whole mechanism exists for: a response that
# parses cleanly and returns the RIGHT NUMBER of objects while substituting
# something else for one expected taxon. n_recovered == n_expected keeps the
# status "complete", so the halving retry never fires -- before 2026-09-14
# nothing asked again and the taxon was NA-filled for good. (A response that
# is simply SHORT reads as truncation and does trigger halving, which is why
# the omission has to be answered separately rather than folded into it.)
.omitting_llm <- function(omit = "Bos taurus", answer_from_call = Inf) {
  calls <- 0L
  prompts <- character(0)
  fn <- function(prompt_str, ...) {
    calls <<- calls + 1L
    prompts <<- c(prompts, prompt_str)
    asked <- names(.CANNED)[vapply(
      names(.CANNED), function(nm) grepl(nm, prompt_str, fixed = TRUE),
      logical(1L)
    )]
    objs <- unlist(.CANNED[asked], use.names = FALSE)
    if (omit %in% asked && calls < answer_from_call) {
      objs[match(omit, asked)] <- sub(
        '"taxon_name": "[^"]*"',
        '"taxon_name": "Fictus imaginarius"',
        .CANNED[[omit]]
      )
    }
    paste0("[", paste(objs, collapse = ",\n"), "]")
  }
  list(
    fn = fn,
    calls = function() calls,
    prompts = function() prompts
  )
}

test_that("an omitted taxon is re-asked and recovered, not left NA", {
  m <- .omitting_llm(answer_from_call = 2L)

  result <- review_assignments(
    data_type = "eDNA",
    input_df = mock_consensus,
    taxon_col = "consensus_taxon",
    context = mock_context,
    llm_fn = m$fn,
    pause_seconds = 0,
    verbose = FALSE
  )

  bt <- result[result$consensus_taxon == "Bos taurus", ]
  expect_equal(bt$llm_habitat_plausibility, "unlikely")
  expect_length(attr(result, "unreviewed_taxa"), 0L)
  expect_equal(attr(result, "n_unreviewed_rows"), 0L)
  # One batch call plus exactly one re-ask: pay-per-failure, not a doubled run.
  expect_equal(m$calls(), 2L)
})

test_that("the re-ask asks for the omitted taxon ONLY", {
  m <- .omitting_llm(answer_from_call = 2L)
  review_assignments(
    data_type = "eDNA",
    input_df = mock_consensus, taxon_col = "consensus_taxon",
    context = mock_context, llm_fn = m$fn, pause_seconds = 0, verbose = FALSE
  )

  expect_equal(length(m$prompts()), 2L)
  block <- sub("(?s).*TAXA TO REVIEW:", "", m$prompts()[[2L]], perl = TRUE)
  expect_true(grepl("Bos taurus", block, fixed = TRUE))
  expect_false(grepl("Homo sapiens", block, fixed = TRUE))
  expect_false(grepl("Gobiidae", block, fixed = TRUE))
})

test_that("a persistently omitted taxon is reported, not silently dropped", {
  m <- .omitting_llm()

  # capture_warnings(), not expect_warning(): the parser's own per-batch
  # "LLM omitted ..." warning fires first, and the summary is the one that
  # matters here.
  warns <- testthat::capture_warnings(
    result <- review_assignments(
      data_type = "eDNA",
      input_df = mock_consensus, taxon_col = "consensus_taxon",
      context = mock_context, llm_fn = m$fn, pause_seconds = 0, verbose = FALSE
    )
  )
  expect_match(warns, "NO LLM verdict", all = FALSE)

  expect_equal(attr(result, "unreviewed_taxa"), "Bos taurus")
  expect_equal(attr(result, "n_unreviewed_rows"), 1L)
  bt <- result[result$consensus_taxon == "Bos taurus", ]
  expect_true(is.na(bt$llm_habitat_plausibility))
  # Stops once a re-ask recovers nothing, rather than burning the whole budget
  # on a model that will not answer.
  expect_equal(m$calls(), 2L)
})

test_that("a single-taxon batch is re-asked too -- halving cannot help there", {
  # With one taxon in the batch there is nothing to halve, so before the
  # re-ask this case had no retry of any kind.
  calls <- 0L
  fn <- function(prompt_str, ...) {
    calls <<- calls + 1L
    if (calls == 1L) "[]" else .CANNED[["Bos taurus"]] |> (\(x) paste0("[", x, "]"))()
  }
  df <- mock_consensus[mock_consensus$consensus_taxon == "Bos taurus", ]

  result <- suppressWarnings(review_assignments(
    data_type = "eDNA",
    input_df = df, taxon_col = "consensus_taxon", context = mock_context,
    llm_fn = fn, pause_seconds = 0, verbose = FALSE
  ))

  expect_equal(calls, 2L)
  expect_equal(result$llm_habitat_plausibility, "unlikely")
  expect_length(attr(result, "unreviewed_taxa"), 0L)
})

test_that("on_unreviewed = 'error' stops the run rather than exporting short", {
  m <- .omitting_llm()
  expect_error(
    suppressWarnings(review_assignments(
      data_type = "eDNA",
      input_df = mock_consensus, taxon_col = "consensus_taxon",
      context = mock_context, llm_fn = m$fn, pause_seconds = 0,
      on_unreviewed = "error", verbose = FALSE
    )),
    "Bos taurus"
  )
})

test_that("on_unreviewed = 'ignore' is silent but still records the residue", {
  m <- .omitting_llm()
  result <- suppressWarnings(review_assignments(
    data_type = "eDNA",
    input_df = mock_consensus, taxon_col = "consensus_taxon",
    context = mock_context, llm_fn = m$fn, pause_seconds = 0,
    on_unreviewed = "ignore", verbose = FALSE
  ))
  expect_equal(attr(result, "unreviewed_taxa"), "Bos taurus")
  expect_equal(attr(result, "n_unreviewed_rows"), 1L)
})

test_that("the residue attributes are always present, even with nothing missing", {
  result <- review_assignments(
    data_type = "eDNA",
    input_df = mock_consensus, taxon_col = "consensus_taxon",
    context = mock_context, llm_fn = mock_llm_fn, verbose = FALSE
  )
  expect_identical(attr(result, "unreviewed_taxa"), character(0))
  expect_equal(attr(result, "n_unreviewed_rows"), 0L)
})

test_that("max_retries = 0 still means exactly one call per batch", {
  m <- .omitting_llm()
  warns <- testthat::capture_warnings(
    result <- review_assignments(
      data_type = "eDNA",
      input_df = mock_consensus, taxon_col = "consensus_taxon",
      context = mock_context, llm_fn = m$fn, max_retries = 0L,
      pause_seconds = 0, verbose = FALSE
    )
  )
  expect_match(warns, "NO LLM verdict", all = FALSE)
  expect_equal(m$calls(), 1L)
  expect_equal(attr(result, "unreviewed_taxa"), "Bos taurus")
})

test_that("an unreviewed taxon is never written to the cache", {
  cache_dir <- file.path(tempdir(), paste0("flagcache_", as.integer(runif(1, 1, 1e8))))
  m <- .omitting_llm()

  suppressWarnings(review_assignments(
    data_type = "eDNA",
    input_df = mock_consensus, taxon_col = "consensus_taxon",
    context = mock_context, llm_fn = m$fn, pause_seconds = 0,
    model_label = "test-model", cache_dir = cache_dir, verbose = FALSE
  ))

  # Four answered taxa cached; the omitted one is not -- caching a non-answer
  # would make the omission permanent on every later run.
  cached <- list.files(cache_dir, pattern = "_review\\.rds$", full.names = TRUE)
  expect_length(cached, 4L)
  names_cached <- vapply(cached, function(p) readRDS(p)$row$taxon_name, character(1L))
  expect_false("Bos taurus" %in% names_cached)
})

test_that("a cached non-answer from an older run is re-asked, not served", {
  cache_dir <- file.path(tempdir(), paste0("flagcache_", as.integer(runif(1, 1, 1e8))))

  # Seed the cache the way a pre-2026-09-14 run would have: every taxon
  # cached, one of them holding NA in every field.
  review_assignments(
    data_type = "eDNA",
    input_df = mock_consensus, taxon_col = "consensus_taxon",
    context = mock_context, llm_fn = mock_llm_fn, pause_seconds = 0,
    model_label = "test-model", cache_dir = cache_dir, verbose = FALSE
  )
  files <- list.files(cache_dir, pattern = "_review\\.rds$", full.names = TRUE)
  hit <- Filter(
    function(p) identical(readRDS(p)$row$taxon_name, "Bos taurus"), files
  )
  expect_length(hit, 1L)
  ent <- readRDS(hit[[1L]])
  for (cl in setdiff(names(ent$row), "taxon_name")) ent$row[[cl]] <- NA_character_
  saveRDS(ent, hit[[1L]])

  m <- .omitting_llm(answer_from_call = 1L)
  result <- review_assignments(
    data_type = "eDNA",
    input_df = mock_consensus, taxon_col = "consensus_taxon",
    context = mock_context, llm_fn = m$fn, pause_seconds = 0,
    model_label = "test-model", cache_dir = cache_dir, verbose = FALSE
  )

  # One call, for the one taxon whose cached entry held no verdict.
  expect_equal(m$calls(), 1L)
  bt <- result[result$consensus_taxon == "Bos taurus", ]
  expect_equal(bt$llm_habitat_plausibility, "unlikely")
  expect_length(attr(result, "unreviewed_taxa"), 0L)
})


# ===========================================================================
# One biological unit is reviewed once, whatever order its label renders in
# ===========================================================================

test_that("a candidate set arriving in two posterior orders is reviewed once", {
  # add_slash_taxon() orders the display label by posterior (what
  # primary_taxon reads), so one unit legitimately carries "A + B/C" on one
  # observation and "A + C/B" on another. Reviewing by label would ask twice
  # and leave one of them unmatched; the review joins on the SORTED set.
  df <- data.frame(
    observation_id = c("o1", "o2"),
    consensus_taxon = "Perciformes",
    consensus_OTU = c(
      "Scorpaenichthys marmoratus + Hexagrammos lagocephalus/decagrammus",
      "Scorpaenichthys marmoratus + Hexagrammos decagrammus/lagocephalus"
    ),
    irreducible_consensus = TRUE,
    stringsAsFactors = FALSE
  )
  df$plausible_taxa <- list(
    c(
      "Scorpaenichthys marmoratus", "Hexagrammos lagocephalus",
      "Hexagrammos decagrammus"
    ),
    c(
      "Scorpaenichthys marmoratus", "Hexagrammos decagrammus",
      "Hexagrammos lagocephalus"
    )
  )

  n_calls <- 0L
  labels_asked <- character(0)
  fn <- function(prompt_str, ...) {
    n_calls <<- n_calls + 1L
    lab <- df$consensus_OTU[vapply(
      df$consensus_OTU, function(x) grepl(x, prompt_str, fixed = TRUE),
      logical(1L)
    )]
    labels_asked <<- c(labels_asked, lab)
    paste0(
      '[{"taxon_name":"', lab[[1L]], '","p_habitat": 0.95,',
      '"p_geographic": 0.95,"p_scope": null,',
      '"p_contamination": 0.02,"review_alternatives":null,',
      '"review_lower_hypotheses":null,"review_confidence":"high",',
      '"review_comment":null}]'
    )
  }

  out <- review_assignments(
    data_type = "eDNA",
    df,
    plausible_taxa_col = "plausible_taxa",
    context = list(geography = "Point Conception", habitat = "rocky reef"),
    llm_fn = fn, pause_seconds = 0, verbose = FALSE
  )

  expect_equal(n_calls, 1L)
  expect_length(labels_asked, 1L)
  # Both orderings of the one unit get the verdict, and neither is left NA.
  expect_equal(nrow(out), 2L)
  expect_equal(out$llm_habitat_plausibility, c("likely", "likely"))
  expect_length(attr(out, "unreviewed_taxa"), 0L)
})

test_that("the review cache key records which model answered", {
  # A verdict is a judgement, so a key that omits the reviewer serves one
  # model's answer to a call asking another. These are the separations the
  # default path must make on its own.
  a <- TaxaFlag:::.review_reviewer_id(TaxaTools::call_anthropic_api)
  g <- TaxaFlag:::.review_reviewer_id(TaxaTools::call_gemini_api)
  o <- TaxaFlag:::.review_reviewer_id(TaxaTools::call_openai_api)
  expect_false(a == g)
  expect_false(a == o)
  expect_false(g == o)

  # A caller's own wrapper is identified by what it pins, not by its package.
  w1 <- TaxaFlag:::.review_reviewer_id(function(p) TaxaTools::call_api(p, model = "one"))
  w2 <- TaxaFlag:::.review_reviewer_id(function(p) TaxaTools::call_api(p, model = "two"))
  expect_false(w1 == w2)

  # The provider option is part of the identity, because call_api() reads it.
  old_opt <- options(TaxaID.provider = "anthropic")
  p1 <- TaxaFlag:::.review_reviewer_id(TaxaTools::call_api)
  options(TaxaID.provider = "openai")
  p2 <- TaxaFlag:::.review_reviewer_id(TaxaTools::call_api)
  options(old_opt)
  expect_false(p1 == p2)

  # model_label wins outright, which is the only way to separate two models
  # from one provider.
  expect_identical(
    TaxaFlag:::.review_reviewer_id(TaxaTools::call_api, model_label = "a-model"),
    "a-model"
  )
  expect_error(
    TaxaFlag:::.review_reviewer_id(TaxaTools::call_api, model_label = c("a", "b")),
    "single non-NA character"
  )

  # An api_key default must never reach the key as a VALUE. The signature
  # deparses to the Sys.getenv() call itself.
  had <- Sys.getenv("ANTHROPIC_API_KEY", unset = NA_character_)
  Sys.setenv(ANTHROPIC_API_KEY = "sk-not-a-real-key")
  id <- TaxaFlag:::.review_reviewer_id(TaxaTools::call_anthropic_api)
  if (is.na(had)) Sys.unsetenv("ANTHROPIC_API_KEY") else Sys.setenv(ANTHROPIC_API_KEY = had)
  expect_false(grepl("sk-not-a-real-key", id, fixed = TRUE))
  expect_true(grepl("Sys.getenv", id, fixed = TRUE))
})

# ==============================================================================
# consensus provenance in the reviewer's context
# ==============================================================================
# A call that landed on an unreferenced row has NO reference sequence for the
# named taxon: the sequence settled only that an unreferenced relative beats
# every referenced candidate, and the NAME came from the occurrence records in
# that row's scope. Nothing else in the context reveals it -- posterior and
# prior are both high, likelihood_support reads near 1, and
# winner_rank_expanded is a different mechanism.

.prov_input <- function(type = "unreferenced_species",
                        scope = "Erythropeltidales", scope_rank = "order",
                        n_named = 1L, with_scope = TRUE) {
  df <- data.frame(
    taxon_name = "Smithora naiadum",
    consensus_posterior = 0.98,
    winner_prior = 0.01,
    winner_rank_expanded = FALSE,
    consensus_hypothesis_type = type,
    stringsAsFactors = FALSE
  )
  if (with_scope) {
    df$consensus_unreferenced_scope <- scope
    df$consensus_unreferenced_scope_rank <- scope_rank
    df$consensus_scope_n_named <- n_named
  }
  df
}
.prov_note <- function(df, ...) {
  ctx <- .summarise_pipeline_context(
    df$taxon_name, df, "consensus_posterior", "winner_prior",
    "winner_rank_expanded", NULL, NULL, ...
  )
  if (is.null(ctx)) NA_character_ else ctx$pipeline_note[[1L]]
}

test_that("a call on an unreferenced row is reported as having no reference sequence", {
  note <- .prov_note(.prov_input())
  expect_match(note, "NO reference sequence")
})

test_that("the note says nothing about what the occurrence records contain", {
  # The scope's name and rank, and how many species the records hold in it,
  # were all once part of this note. They report the CONTENT of the occurrence
  # data, which is the one thing a review meant to judge that data
  # independently must not be handed. The sequence fact survives; the rest is
  # gone, on both the one-species and the many-species path.
  for (n in c(1L, 25L)) {
    note <- .prov_note(.prov_input(n_named = n))
    expect_match(note, "NO reference sequence")
    expect_false(grepl("Erythropeltidales", note, fixed = TRUE))
    expect_false(grepl("occurrence records", note, fixed = TRUE))
    expect_false(grepl("recorded in that scope", note, fixed = TRUE))
    expect_false(grepl("chosen by occurrence records", note, fixed = TRUE))
  }
})

test_that("a referenced call gets no provenance note", {
  note <- .prov_note(.prov_input(type = "specific_candidate"))
  expect_false(grepl("reference sequence", note))
})

test_that("consensus_provenance = FALSE suppresses the note", {
  note <- .prov_note(.prov_input(), consensus_provenance = FALSE)
  expect_false(grepl("reference sequence", note))
  # the rest of the context survives
  expect_match(note, "pipeline posterior")
})

test_that("the note degrades without the scope columns rather than failing", {
  note <- .prov_note(.prov_input(with_scope = FALSE))
  expect_match(note, "NO reference sequence")
  expect_false(grepl("occurrence records for", note))
})

test_that("a generic ring call names a clade, not an unreferenced species: no line", {
  # "Salmo" as an unreferenced_species ring: the genus may well be referenced
  # (Mugu: 90 12S references); only the read failed to match them.
  df <- .prov_input(scope = "Salmo", scope_rank = "genus")
  df$taxon_name <- "Salmo"
  expect_false(grepl("reference sequence", .prov_note(df)))
  for (ty in paste0("unreferenced_", c("genus", "family", "order", "class"))) {
    df2 <- .prov_input(type = ty)
    expect_false(grepl("reference sequence", .prov_note(df2)))
  }
})

# Goldfish shape (Mugu _final1): units sharing the label "Carassius auratus",
# a referenced species. One unit calls it outright; others call a family ring
# with Carassius auratus as the first plausible taxon. None of them may tell
# the reviewer the named taxon has no reference.
.goldfish <- function() {
  df <- data.frame(
    observation_id = c("ASV_139", "ASV_142"),
    primary_taxon = c("Carassius auratus", "Carassius auratus"),
    consensus_taxon = c("Carassius auratus", "Cyprinidae"),
    consensus_rank = c("species", "family"),
    consensus_hypothesis_type = c("specific_candidate", "unreferenced_genus"),
    winner_hypothesis_type = c("specific_candidate", "specific_candidate"),
    consensus_unreferenced_scope = c(NA, "Cyprinidae"),
    consensus_unreferenced_scope_rank = c(NA, "family"),
    consensus_scope_n_named = c(NA, 1L),
    consensus_posterior = c(0.97, 0.97),
    stringsAsFactors = FALSE
  )
  df$plausible_taxa <- I(list("Carassius auratus", c("Carassius auratus", "Cyprinus carpio")))
  df
}

test_that("a referenced label under a ring call gets no 'no reference' line (goldfish)", {
  df <- .goldfish()
  ctx <- .summarise_pipeline_context(df$primary_taxon, df, "consensus_posterior", NULL, NULL)
  expect_false(grepl("reference sequence", ctx$pipeline_note[[1L]]))
  # the ring unit alone, label = first plausible taxon, winner referenced
  one <- df[2, ]
  ctx1 <- .summarise_pipeline_context(one$primary_taxon, one, "consensus_posterior", NULL, NULL)
  expect_false(grepl("reference sequence", ctx1$pipeline_note[[1L]]))
})

test_that("a named unreferenced first-plausible label still gets the line", {
  df <- .goldfish()[2, ]
  df$primary_taxon <- "Carassius cuvieri"
  df$winner_hypothesis_type <- "unreferenced_species"
  df$plausible_taxa <- I(list(c("Carassius cuvieri", "Carassius auratus")))
  ctx <- .summarise_pipeline_context(df$primary_taxon, df, "consensus_posterior", NULL, NULL)
  expect_match(ctx$pipeline_note[[1L]], "NO reference sequence")
  # the scope detail belongs to the call row, so it is not borrowed here
  expect_false(grepl("occurrence records for", ctx$pipeline_note[[1L]]))
})

test_that("a label shown as referenced anywhere in its group gets no line", {
  df <- .goldfish()
  df$winner_hypothesis_type[2] <- "unreferenced_species"
  ctx <- .summarise_pipeline_context(df$primary_taxon, df, "consensus_posterior", NULL, NULL)
  expect_false(grepl("reference sequence", ctx$pipeline_note[[1L]]))
})

test_that("a label whose row type cannot be read gets no line", {
  df <- .goldfish()[2, ]
  df$primary_taxon <- "Cyprinus carpio" # neither the call nor the first plausible taxon
  ctx <- .summarise_pipeline_context(df$primary_taxon, df, "consensus_posterior", NULL, NULL)
  expect_false(grepl("reference sequence", ctx$pipeline_note[[1L]]))
})

test_that("provenance alone is enough context to annotate", {
  # No posterior, prior or rank-expanded columns: the note must still appear
  # rather than the summariser returning NULL.
  df <- data.frame(
    taxon_name = "Smithora naiadum",
    consensus_hypothesis_type = "unreferenced_species",
    consensus_unreferenced_scope = "Erythropeltidales",
    consensus_unreferenced_scope_rank = "order",
    consensus_scope_n_named = 1L,
    stringsAsFactors = FALSE
  )
  ctx <- .summarise_pipeline_context(df$taxon_name, df, NULL, NULL, NULL)
  expect_false(is.null(ctx))
  expect_match(ctx$pipeline_note[[1L]], "NO reference sequence")
})

test_that(".normalise_context() combines the analyst's wording with the synthesised ecoregion", {
  nc <- TaxaFlag:::.normalise_context

  # A build_context() output: geographic_hint is the analyst's own wording and
  # ecoregion is ONE string synthesised for the whole taxon list. Reading the
  # ecoregion alone would hand the LLM a geography narrower than the study.
  ctx <- nc(data.frame(
    ecoregion       = "Southern California Bight",
    main_habitat    = "rocky nearshore reef",
    date            = "2025",
    geographic_hint = "California coast, Point Conception to the Oregon border",
    stringsAsFactors = FALSE
  ))
  expect_equal(
    ctx$geography,
    "California coast, Point Conception to the Oregon border (Southern California Bight)"
  )
  expect_equal(ctx$habitat, "rocky nearshore reef")

  # An explicit geography is authoritative and must survive untouched, so a
  # hand-written context produces a byte-identical prompt.
  expect_equal(
    nc(list(geography = "Pt. Conception, CA Pacific Ocean",
            ecoregion = "Southern California Bight",
            habitat = "coastal marine"))$geography,
    "Pt. Conception, CA Pacific Ocean"
  )

  # Either field alone is used as-is.
  expect_equal(nc(list(ecoregion = "Lake Michigan", habitat = "x"))$geography,
               "Lake Michigan")
  expect_equal(nc(list(geographic_hint = "Burns Harbor", habitat = "x"))$geography,
               "Burns Harbor")

  # A hint identical to the ecoregion must not be duplicated into "X (X)".
  expect_equal(
    nc(list(geographic_hint = "Lake Michigan", ecoregion = "Lake Michigan",
            habitat = "x"))$geography,
    "Lake Michigan"
  )

  # NA and empty-string placeholders are not geography. build_context() writes
  # NA_character_ for an absent hint, so this is the common case, not a corner.
  expect_warning(
    g <- nc(list(geographic_hint = NA_character_, ecoregion = NA_character_,
                 habitat = "x"))$geography,
    "geography"
  )
  expect_null(g)
  expect_equal(
    nc(list(geographic_hint = "   ", ecoregion = "Lake Michigan",
            habitat = "x"))$geography,
    "Lake Michigan"
  )
})

# ===========================================================================
# The pipeline's own numbers are off by default
# ===========================================================================

# The review is asked for an independent ecological judgement, and a judgement
# that has been shown the pipeline's own posterior cannot contradict it
# independently -- nor can a review that has been shown a taxon's GBIF
# distance catch an error IN the occurrence data. The eight NULL defaults are
# the only thing keeping those numbers out of the prompt, so what they do is
# asserted here rather than left to the roxygen: a caller who hands this
# function a frame straight out of posterior_consensus() and
# check_gbif_tile_range() gets a blind review unless it asks for otherwise.
.noted_input <- data.frame(
  observation_id = "S1",
  consensus_taxon = "Bos taurus",
  consensus_rank = "species",
  consensus_posterior = 0.81,
  winner_prior = 0.42,
  dist_nearest_occupied_km = 41,
  patch_diameter_km = 2.1,
  beyond_buffer = FALSE,
  in_range = TRUE,
  n_observations = 1275L,
  matched_name = "Bos taurus",
  winner_rank_expanded = TRUE,
  # Still ON by default, so the DEFAULT prompt carries a bracket -- which is
  # the case the bracket guideline has to describe correctly.
  poor_absolute_fit = TRUE,
  best_identity = 89.6,
  stringsAsFactors = FALSE
)

# The candidate-set path, which is the only path the per-candidate weights
# reach: the label has to be a multi-candidate one for them to be summarised.
.weighted_input <- data.frame(
  observation_id = c("S1", "S1"),
  consensus_taxon = c("Bos taurus/javanicus", "Bos taurus/javanicus"),
  consensus_rank = c("species", "species"),
  plausible_taxa = I(list(
    c("Bos taurus", "Bos javanicus"), c("Bos taurus", "Bos javanicus")
  )),
  plausible_posteriors = I(list(
    c("Bos taurus" = 0.72, "Bos javanicus" = 0.28),
    c("Bos taurus" = 0.72, "Bos javanicus" = 0.28)
  )),
  stringsAsFactors = FALSE
)

# Returns the prompt that was actually sent, which is the only place the
# notes can be checked: nothing about them reaches an output column.
.prompt_sent <- function(...) {
  seen <- character(0)
  fn <- function(prompt_str, ...) {
    seen <<- c(seen, prompt_str)
    paste0("[", .CANNED[["Bos taurus"]], "]")
  }
  invisible(review_assignments(
    data_type = "eDNA", input_df = .noted_input,
    taxon_col = "consensus_taxon", context = mock_context,
    llm_fn = fn, verbose = FALSE, ...
  ))
  paste(seen, collapse = "\n")
}

.NOTE_COLS <- list(
  consensus_posterior_col = "consensus_posterior",
  winner_prior_col = "winner_prior",
  dist_nearest_occupied_km_col = "dist_nearest_occupied_km",
  patch_diameter_km_col = "patch_diameter_km",
  beyond_buffer_col = "beyond_buffer",
  inat_in_range_col = "in_range",
  inat_n_observations_col = "n_observations",
  inat_matched_name_col = "matched_name"
)

test_that("no pipeline posterior, prior, GBIF or iNat note is sent by default", {
  p <- .prompt_sent()
  for (txt in c("pipeline posterior", "occurrence prior", "GBIF", "iNat")) {
    expect_false(grepl(txt, p, fixed = TRUE), info = txt)
  }
  # The guidelines that explain those notes are conditional on them, so they
  # are not assembled either. The bracket guideline is the one that names a
  # posterior and an occurrence prior in its own text, so an ungated copy of
  # it would tell the model to look for numbers that are not there.
  expect_false(grepl("nearest occurrence", p, fixed = TRUE))
  # The bracket's NUMERIC guideline is the one that names a posterior and an
  # occurrence prior, so an ungated copy would tell the model to look for
  # numbers that are not there.
  expect_false(grepl("OWN statistical confidence", p, fixed = TRUE))
})

test_that("the rank-expansion note is sent, and says only what the sequence did", {
  # winner_rank_expanded is TRUE in the fixture. The note is sequence-only
  # wording: what the sequence did not do, with no mention of what supplied
  # the name instead. It is also deliberately NOT the INDISTINGUISHABLE
  # statement -- that is a tail probability saying a relative could score as
  # well, where this says the sequence never reached species at all.
  p <- .prompt_sent()
  expect_match(p, "the sequence does not resolve this call to species", fixed = TRUE)
  expect_false(grepl("occurrence-prior tie-break", p, fixed = TRUE))
  expect_false(grepl("could score equally well", p, fixed = TRUE))
})

test_that("winner_rank_expanded_col = NULL suppresses it", {
  p <- .prompt_sent(winner_rank_expanded_col = NULL)
  expect_false(grepl("the sequence does not resolve", p, fixed = TRUE))
})

test_that("no candidate weights are sent by default, and naming the column sends them", {
  seen <- character(0)
  fn <- function(prompt_str, ...) {
    seen <<- c(seen, prompt_str)
    paste0(
      '[{"taxon_name": "Bos taurus/javanicus", "p_habitat": 0.5,',
      ' "p_geographic": 0.5, "p_scope": 0.5, "p_contamination": 0.5,',
      ' "review_confidence": "low", "review_comment": null}]'
    )
  }
  args <- list(.weighted_input,
    data_type = "eDNA", taxon_col = "consensus_taxon",
    taxon_rank_col = "consensus_rank", plausible_taxa_col = "plausible_taxa",
    irreducible_only = FALSE, context = mock_context, llm_fn = fn,
    verbose = FALSE
  )
  invisible(do.call(review_assignments, args))
  # The NOTE is "candidate weights: ..."; the words also occur bare in the
  # bracket guideline, which this batch still gets because the candidate-set
  # path emits an ungated "pipeline call:" note. So the colon is load-bearing
  # in this assertion, and it was this test that found that residue.
  expect_false(grepl("candidate weights: ", paste(seen, collapse = "\n"), fixed = TRUE))

  seen <- character(0)
  invisible(do.call(
    review_assignments, c(args, list(plausible_posteriors_col = "plausible_posteriors"))
  ))
  expect_match(
    paste(seen, collapse = "\n"), "candidate weights: Bos taurus 72%", fixed = TRUE
  )
})

test_that("naming the columns puts every one of those notes back", {
  p <- do.call(.prompt_sent, .NOTE_COLS)
  expect_match(p, "pipeline posterior=0.81", fixed = TRUE)
  expect_match(p, "occurrence prior=0.42", fixed = TRUE)
  expect_match(p, "GBIF: nearest occurrence", fixed = TRUE)
  expect_match(p, "iNat: in range", fixed = TRUE)
  # ... and the guidelines that explain the bracket come back with it, which
  # is the other half of the gate: the notes and the words that tell the model
  # how to read them travel together. With a posterior in the batch that
  # includes the NUMERIC piece, which is gated separately.
  expect_match(p, "reports what the DNA evidence could and could not settle", fixed = TRUE)
  expect_match(p, "OWN statistical confidence", fixed = TRUE)
  expect_match(p, "GBIF's density map is RAW", fixed = TRUE)
})

test_that("the study's own design is still sent: it is not evidence about the taxon", {
  p <- .prompt_sent()
  expect_match(p, "Palmyra Atoll", fixed = TRUE)
  expect_match(p, "coral reef", fixed = TRUE)
  expect_match(p, "Bos taurus", fixed = TRUE)
})

test_that("a verdict cached WITH the notes is not served to a blind call", {
  cd <- file.path(tempdir(), paste0("flagblind_", as.integer(runif(1, 1, 1e8))))
  on.exit(unlink(cd, recursive = TRUE), add = TRUE)
  ctr <- new.env()
  assign("n", 0L, ctr)
  fn <- function(prompt_str, ...) {
    assign("n", get("n", ctr) + 1L, ctr)
    paste0("[", .CANNED[["Bos taurus"]], "]")
  }
  base <- list(.noted_input,
    data_type = "eDNA", taxon_col = "consensus_taxon", context = mock_context,
    llm_fn = fn, model_label = "test-model", cache_dir = cd, verbose = FALSE
  )
  invisible(do.call(review_assignments, c(base, .NOTE_COLS)))
  n1 <- get("n", ctr)
  expect_gt(n1, 0L)
  # Same taxon, same context, same model: only the notes are gone. The notes
  # are columns of taxa_info and every column of it enters the key, so this is
  # a miss with no version bump anywhere -- which is why switching the
  # defaults off needed none.
  invisible(do.call(review_assignments, base))
  expect_gt(get("n", ctr), n1)
  n2 <- get("n", ctr)
  # ... and the blind call's own verdict caches and is served back.
  invisible(do.call(review_assignments, base))
  expect_equal(get("n", ctr), n2)
})


# ===========================================================================
# The bracket guideline describes what the bracket actually carries
# ===========================================================================

# Under the shipped defaults a bracket never holds a number, only notes about
# the NAME. A single guideline calling the bracket "the pipeline's OWN
# confidence (posterior/occurrence prior/candidate weights)" therefore told
# the model to read a sequence fact as a confidence and to look for a
# posterior that was not in the prompt. Found on a live run, not by a test,
# which is why both sides are pinned here.

test_that("a bracket with no number gets the facts guideline and not the numeric one", {
  p <- .prompt_sent()
  # The fixture's poor_absolute_fit is TRUE, so a bracket IS present.
  expect_match(p, "(poor absolute fit)", fixed = TRUE)
  expect_match(p, "reports what the DNA evidence could and could not settle", fixed = TRUE)
  # ... and nothing claims that bracket is a confidence, or names a number
  # the model cannot see.
  expect_false(grepl("OWN statistical confidence", p, fixed = TRUE))
  expect_false(grepl("pipeline posterior alongside your own", p, fixed = TRUE))
})

test_that("a bracket carrying a number gets both guidelines", {
  p <- .prompt_sent(
    consensus_posterior_col = "consensus_posterior",
    winner_prior_col = "winner_prior"
  )
  expect_match(p, "pipeline posterior=0.81", fixed = TRUE)
  expect_match(p, "reports what the DNA evidence could and could not settle", fixed = TRUE)
  expect_match(p, "OWN statistical confidence", fixed = TRUE)
  expect_match(p, "pipeline posterior alongside your own", fixed = TRUE)
})

test_that("no bracket at all means neither guideline", {
  # A frame with none of the note columns: nothing to describe, so the prompt
  # says nothing about brackets.
  bare <- data.frame(
    observation_id = "S1", consensus_taxon = "Bos taurus",
    consensus_rank = "species", stringsAsFactors = FALSE
  )
  seen <- character(0)
  fn <- function(prompt_str, ...) {
    seen <<- c(seen, prompt_str)
    paste0("[", .CANNED[["Bos taurus"]], "]")
  }
  invisible(review_assignments(
    data_type = "eDNA", input_df = bare, taxon_col = "consensus_taxon",
    context = mock_context, llm_fn = fn, verbose = FALSE
  ))
  p <- paste(seen, collapse = "\n")
  expect_false(grepl("reports what the DNA evidence could and could not settle", p, fixed = TRUE))
  expect_false(grepl("OWN statistical confidence", p, fixed = TRUE))
})

# ===========================================================================
# Read without showing: UNPRECEDENTED
# ===========================================================================

test_that("an UNPRECEDENTED row still fills geographic_disagreement_basis", {
  # The point of the read-vs-show split. "No local occurrence record at all"
  # is a statement about the occurrence data, so it never reaches the prompt
  # -- but geographic_disagreement_basis is computed from it in code, and that
  # column is the deterministic way a reviewer finds a taxon the LLM called
  # plausible where the records hold nothing. Losing the column would have
  # traded a safety signal for the prompt change; this test is what says the
  # trade did not happen.
  df <- data.frame(
    observation_id = "S1",
    consensus_taxon = "Bos taurus",
    consensus_rank = "species",
    consensus_plausibility = "unprecedented",
    consensus_discrimination = "resolved",
    stringsAsFactors = FALSE
  )
  seen <- character(0)
  fn <- function(prompt_str, ...) {
    seen <<- c(seen, prompt_str)
    # geography "likely" is what makes it a disagreement.
    paste0(
      '[{"taxon_name": "Bos taurus", "p_habitat": 0.9, "p_geographic": 0.9,',
      ' "p_scope": 0.9, "p_contamination": 0.1,',
      ' "review_confidence": "high", "review_comment": null}]'
    )
  }
  out <- review_assignments(
    data_type = "eDNA", input_df = df, taxon_col = "consensus_taxon",
    context = mock_context, llm_fn = fn, verbose = FALSE
  )
  expect_equal(out$geographic_disagreement_basis, "unprecedented")
  expect_equal(out$llm_geographic_plausibility, "likely")
  # ... and the prompt said nothing about it.
  p <- paste(seen, collapse = "\n")
  expect_false(grepl("UNPRECEDENTED", p, fixed = TRUE))
  expect_false(grepl("occurrence record", p, fixed = TRUE))
})

test_that("an identity alone is enough to send the sequence-evidence guideline", {
  # The commonest default case: a frame out of the pipeline carries
  # best_identity and no flag is set, so the only bracket note is the number.
  df <- data.frame(
    observation_id = "S1", consensus_taxon = "Bos taurus",
    consensus_rank = "species", best_identity = 99.4,
    stringsAsFactors = FALSE
  )
  seen <- character(0)
  fn <- function(prompt_str, ...) {
    seen <<- c(seen, prompt_str)
    paste0("[", .CANNED[["Bos taurus"]], "]")
  }
  invisible(review_assignments(
    data_type = "eDNA", input_df = df, taxon_col = "consensus_taxon",
    context = mock_context, llm_fn = fn, verbose = FALSE
  ))
  p <- paste(seen, collapse = "\n")
  expect_match(p, "best match identity 99.4%", fixed = TRUE)
  expect_match(p, "reports what the DNA evidence could and could not settle", fixed = TRUE)
  expect_false(grepl("OWN statistical confidence", p, fixed = TRUE))
})
