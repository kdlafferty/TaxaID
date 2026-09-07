# --- Mock LLM function ---
# Returns canned JSON for known taxa; simulates real LLM behavior

mock_llm_fn <- function(prompt_str, ...) {
  # Return a realistic JSON response for Palmyra Atoll reef taxa
  '[
    {"taxon_name": "Carcharhinus melanopterus", "habitat_plausibility": "likely", "geographic_plausibility": "likely", "scope_plausibility": "likely", "contamination_risk": "low", "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": "Blacktip reef shark, common on Pacific coral reefs"},
    {"taxon_name": "Homo sapiens", "habitat_plausibility": "unlikely", "geographic_plausibility": "likely", "scope_plausibility": "unlikely", "contamination_risk": "high", "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": "Common lab contaminant in eDNA studies"},
    {"taxon_name": "Gobiidae", "habitat_plausibility": "likely", "geographic_plausibility": "likely", "scope_plausibility": "likely", "contamination_risk": "low", "review_alternatives": null, "review_lower_hypotheses": "Eviota sp., Trimma sp.", "review_confidence": "moderate", "review_comment": "Diverse family on coral reefs; many cryptic species"},
    {"taxon_name": "Salmo salar", "habitat_plausibility": "unlikely", "geographic_plausibility": "unlikely", "scope_plausibility": "likely", "contamination_risk": "moderate", "review_alternatives": "Lutjanus bohar, Lutjanus kasmira", "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": "Atlantic salmon; not found in central Pacific. Possible food-source contaminant"},
    {"taxon_name": "Bos taurus", "habitat_plausibility": "unlikely", "geographic_plausibility": "unlikely", "scope_plausibility": "unlikely", "contamination_risk": "high", "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": "Domestic cattle; common food-source contaminant"}
  ]'
}


# --- Mock consensus data ---
mock_consensus <- data.frame(
  observation_id       = c("S1", "S1", "S2", "S2", "S3"),
  consensus_taxon = c("Carcharhinus melanopterus", "Homo sapiens",
                      "Gobiidae", "Salmo salar", "Bos taurus"),
  consensus_rank  = c("species", "species", "family", "species", "species"),
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
    input_df           = mock_consensus,
    taxon_col    = "consensus_taxon",
    context      = mock_context,
    target_group = "fish",
    llm_fn       = mock_llm_fn,
    verbose      = FALSE
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
    input_df           = mock_consensus,
    taxon_col    = "consensus_taxon",
    context      = mock_context,
    target_group = "fish",
    llm_fn       = mock_llm_fn,
    verbose      = FALSE
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
    input_df           = mock_consensus,
    taxon_col    = "consensus_taxon",
    context      = mock_context,
    target_group = "fish",
    llm_fn       = mock_llm_fn,
    verbose      = FALSE
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
    input_df             = mock_consensus,
    taxon_col      = "consensus_taxon",
    taxon_rank_col = "consensus_rank",
    context        = mock_context,
    target_group   = "fish",
    llm_fn         = mock_llm_fn,
    verbose        = FALSE
  )

  gov <- result[result$consensus_taxon == "Gobiidae", ]
  expect_true(!is.na(gov$review_lower_hypotheses))
})

test_that("review_lower_hypotheses is NA when taxon_rank_col not supplied", {
  result <- review_assignments(
    input_df           = mock_consensus,
    taxon_col    = "consensus_taxon",
    context      = mock_context,
    target_group = "fish",
    llm_fn       = mock_llm_fn,
    verbose      = FALSE
  )

  # All lower_hypotheses should be NA when no rank column
  expect_true(all(is.na(result$review_lower_hypotheses)))
})


# ===========================================================================
# target_group controls scope_plausibility
# ===========================================================================

test_that("scope_plausibility is NA when target_group not supplied", {
  result <- review_assignments(
    input_df       = mock_consensus,
    taxon_col = "consensus_taxon",
    context  = mock_context,
    llm_fn   = mock_llm_fn,
    verbose  = FALSE
  )

  expect_true(all(is.na(result$llm_scope_plausibility)))
})


# ===========================================================================
# Context normalisation
# ===========================================================================

test_that("build_context() style data frame works as context", {
  ctx_df <- data.frame(
    ecoregion    = "Central Pacific",
    main_habitat = "coral reef",
    date         = "2025",
    stringsAsFactors = FALSE
  )

  result <- review_assignments(
    input_df        = mock_consensus,
    taxon_col = "consensus_taxon",
    context   = ctx_df,
    llm_fn    = mock_llm_fn,
    verbose   = FALSE
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
      input_df        = mock_consensus,
      taxon_col = "consensus_taxon",
      context   = mock_context,
      llm_fn    = fail_fn,
      verbose   = FALSE
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
      input_df        = mock_consensus,
      taxon_col = "consensus_taxon",
      context   = mock_context,
      llm_fn    = bad_fn,
      verbose   = FALSE
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
      {"taxon_name": "Carcharhinus melanopterus", "habitat_plausibility": "likely", "geographic_plausibility": "likely", "scope_plausibility": null, "contamination_risk": "low", "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": null},
      {"taxon_name": "Homo sapiens", "habitat_plausibility": "unlikely", "geographic_plausibility": "likely", "scope_plausibility": null, "contamination_risk": "high", "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": null}
    ]'
  }

  expect_warning(
    result <- review_assignments(
      input_df        = mock_consensus,
      taxon_col = "consensus_taxon",
      context   = mock_context,
      llm_fn    = partial_fn,
      verbose   = FALSE
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
        '{"taxon_name": "%s", "habitat_plausibility": "likely", "geographic_plausibility": "likely", "scope_plausibility": null, "contamination_risk": "low", "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": null}',
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
      input_df            = mock_consensus,
      taxon_col     = "consensus_taxon",
      context       = mock_context,
      llm_fn        = retry_fn,
      max_retries   = 3L,
      pause_seconds = 0,
      verbose       = FALSE
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
      input_df            = mock_consensus,
      taxon_col     = "consensus_taxon",
      context       = mock_context,
      llm_fn        = fail_fn,
      max_retries   = 3L,
      pause_seconds = 0,
      verbose       = FALSE
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
      {"taxon_name": "Carcharhinus melanopterus", "habitat_plausibility": "likely", "geographic_plausibility": "likely", "scope_plausibility": null, "contamination_risk": "low", "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": null}
    ]'
  }

  expect_warning(
    result <- review_assignments(
      input_df            = mock_consensus,
      taxon_col     = "consensus_taxon",
      context       = mock_context,
      llm_fn        = partial_fn,
      max_retries   = 0L,
      pause_seconds = 0,
      verbose       = FALSE
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
    input_df         = mock_consensus,
    taxon_col  = "consensus_taxon",
    context    = mock_context,
    llm_fn     = capture_fn,
    max_tokens = 6000L,
    verbose    = FALSE
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
    input_df        = mock_consensus,
    taxon_col = "consensus_taxon",
    context   = mock_context,
    llm_fn    = capture_fn,
    verbose   = FALSE
  )

  expect_equal(length(captured), 0L)
})


# ===========================================================================
# Input validation
# ===========================================================================

test_that("error when taxon column missing", {
  expect_error(
    review_assignments(mock_consensus, taxon_col = "nonexistent",
                       context = mock_context, llm_fn = mock_llm_fn,
                       verbose = FALSE),
    "not found"
  )
})

test_that("error when context missing", {
  expect_error(
    review_assignments(mock_consensus, taxon_col = "consensus_taxon",
                       llm_fn = mock_llm_fn, verbose = FALSE),
    "context.*required"
  )
})

test_that("error when taxon_rank_col not in input_df", {
  expect_error(
    review_assignments(mock_consensus, taxon_col = "consensus_taxon",
                       taxon_rank_col = "nonexistent",
                       context = mock_context, llm_fn = mock_llm_fn,
                       verbose = FALSE),
    "not found"
  )
})


# ===========================================================================
# Row order preservation
# ===========================================================================

test_that("output row order matches input", {
  result <- review_assignments(
    input_df        = mock_consensus,
    taxon_col = "consensus_taxon",
    context   = mock_context,
    llm_fn    = mock_llm_fn,
    verbose   = FALSE
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
    observation_id  = c("o1", "o2", "o3"),
    consensus_taxon = c("Lepomis", "Lepomis", "Perca flavescens"),
    consensus_rank  = c("genus", "genus", "species"),
    consensus_OTU   = c("Lepomis macrochirus/gibbosus",
                        "Lepomis gibbosus/macrochirus",   # reversed display order
                        "Perca flavescens"),
    plausible_taxa  = I(list(c("Lepomis macrochirus", "Lepomis gibbosus"),
                             c("Lepomis gibbosus", "Lepomis macrochirus"),
                             "Perca flavescens")),
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
                   sub("\\s*\\(rank: [^()]*\\)$", "", labs))
    paste0("[", paste(sprintf(
      '{"taxon_name":"%s","habitat_plausibility":"likely","geographic_plausibility":"likely",
        "scope_plausibility":"likely","contamination_risk":"low","review_alternatives":null,
        "review_lower_hypotheses":null,"review_confidence":"high","review_comment":"ok"}',
      labs), collapse = ","), "]")
  }
  out <- review_assignments(df, taxon_col = "consensus_taxon",
                            taxon_rank_col = "consensus_rank",
                            context = list(geography = "Lake Michigan",
                                           habitat   = "harbor"),
                            plausible_taxa_col = "plausible_taxa",
                            irreducible_only = FALSE, taxa_per_call = 10L,
                            llm_fn = fake_llm, verbose = FALSE)
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
    observation_id  = c("o1", "o2", "o3"),
    consensus_taxon = c("Lepomis", "Lepomis", "Perca flavescens"),
    consensus_rank  = c("genus", "genus", "species"),
    consensus_OTU   = c("Lepomis macrochirus/gibbosus",
                        "Lepomis gibbosus/macrochirus", "Perca flavescens"),
    plausible_taxa  = I(list(c("Lepomis macrochirus", "Lepomis gibbosus"),
                             c("Lepomis gibbosus", "Lepomis macrochirus"),
                             "Perca flavescens")),
    stringsAsFactors = FALSE)
}

.counting_llm <- function(counter) {
  function(prompt, ...) {
    assign("n", get("n", counter) + 1L, counter)
    labs <- sub("^- ", "", regmatches(prompt, gregexpr("(?m)^- .*$", prompt, perl = TRUE))[[1]])
    labs <- grep("\\((unresolved candidates|rank: )", labs, value = TRUE)
    labs <- ifelse(grepl("unresolved candidates", labs), labs,
                   sub("\\s*\\(rank: [^()]*\\)$", "", labs))
    paste0("[", paste(sprintf(
      '{"taxon_name":"%s","habitat_plausibility":"likely","geographic_plausibility":"likely","scope_plausibility":"likely","contamination_risk":"low","review_alternatives":null,"review_lower_hypotheses":null,"review_confidence":"high","review_comment":"ok"}',
      labs), collapse = ","), "]")
  }
}

test_that("a cached review is reproducible and makes no second LLM call", {
  cd <- file.path(tempdir(), paste0("flagcache_", as.integer(runif(1, 1, 1e8))))
  on.exit(unlink(cd, recursive = TRUE), add = TRUE)
  ctr <- new.env(); assign("n", 0L, ctr)
  args <- list(.cache_fixture(), taxon_col = "consensus_taxon",
               taxon_rank_col = "consensus_rank",
               context = list(geography = "Lake Michigan", habitat = "harbor"),
               plausible_taxa_col = "plausible_taxa", irreducible_only = FALSE,
               taxa_per_call = 10L, llm_fn = .counting_llm(ctr),
               cache_dir = cd, verbose = FALSE)
  a <- do.call(review_assignments, args)
  first <- get("n", ctr)
  expect_gt(first, 0L)
  b <- do.call(review_assignments, args)
  expect_equal(get("n", ctr), first)                       # no further calls
  expect_equal(a$llm_habitat_plausibility, b$llm_habitat_plausibility)
  expect_false(any(is.na(b$llm_habitat_plausibility)))
})

test_that("changing the review context is a cache MISS, not a stale hit", {
  cd <- file.path(tempdir(), paste0("flagcache_", as.integer(runif(1, 1, 1e8))))
  on.exit(unlink(cd, recursive = TRUE), add = TRUE)
  ctr <- new.env(); assign("n", 0L, ctr)
  base <- list(.cache_fixture(), taxon_col = "consensus_taxon",
               taxon_rank_col = "consensus_rank",
               context = list(geography = "Lake Michigan", habitat = "harbor"),
               plausible_taxa_col = "plausible_taxa", irreducible_only = FALSE,
               taxa_per_call = 10L, llm_fn = .counting_llm(ctr),
               cache_dir = cd, verbose = FALSE)
  invisible(do.call(review_assignments, base))
  n1 <- get("n", ctr)
  moved <- base; moved$context <- list(geography = "Chesapeake Bay", habitat = "harbor")
  invisible(do.call(review_assignments, moved))
  expect_gt(get("n", ctr), n1)
})

test_that("cache files are the file-per-key shape taxaflag_clear_cache() manages", {
  cd <- file.path(tempdir(), paste0("flagcache_", as.integer(runif(1, 1, 1e8))))
  on.exit(unlink(cd, recursive = TRUE), add = TRUE)
  ctr <- new.env(); assign("n", 0L, ctr)
  invisible(review_assignments(.cache_fixture(), taxon_col = "consensus_taxon",
    taxon_rank_col = "consensus_rank",
    context = list(geography = "Lake Michigan", habitat = "harbor"),
    plausible_taxa_col = "plausible_taxa", irreducible_only = FALSE,
    taxa_per_call = 10L, llm_fn = .counting_llm(ctr), cache_dir = cd, verbose = FALSE))
  inv <- taxaflag_clear_cache(cache_dir = cd, dry_run = TRUE)
  expect_gt(nrow(inv), 0L)
  expect_true(all(grepl("_review\\.rds$", basename(inv$path))))
  expect_true(all(file.exists(inv$path)))                  # dry_run kept them
  taxaflag_clear_cache(cache_dir = cd)
  expect_equal(nrow(TaxaTools::list_cache_files(cd, .taxaflag_cache_patterns)), 0L)
})

test_that("a hash collision is a miss, never another taxon's verdict", {
  cd <- file.path(tempdir(), paste0("flagcache_", as.integer(runif(1, 1, 1e8))))
  dir.create(cd, recursive = TRUE)
  on.exit(unlink(cd, recursive = TRUE), add = TRUE)
  f <- file.path(cd, "collide_review.rds")
  saveRDS(list(key = "SOME OTHER KEY",
               row = data.frame(taxon_name = "Wrong taxon", stringsAsFactors = FALSE)), f)
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
    observation_id  = c("o1", "o2"),
    consensus_taxon = "Oncorhynchus mykiss",
    consensus_OTU   = "Oncorhynchus mykiss",
    irreducible_consensus = TRUE,
    stringsAsFactors = FALSE
  )
  df$plausible_taxa <- list(c("Salmo salar", "Salvelinus alpinus"), "Salmo trutta")

  n_calls <- 0L
  fake_llm <- function(prompt, ...) {
    n_calls <<- n_calls + 1L
    '[{"taxon_name":"Oncorhynchus mykiss","habitat_plausibility":"likely",
       "geographic_plausibility":"likely","scope_plausibility":null,
       "contamination_risk":"low","review_alternatives":null,
       "review_lower_hypotheses":null,"review_confidence":"high",
       "review_comment":null}]'
  }
  out <- review_assignments(
    df, plausible_taxa_col = "plausible_taxa",
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
  expect_equal(TaxaFlag:::.parse_json_text('[{"taxon_name":"Salmo salar"}]')$taxon_name,
               "Salmo salar")
  expect_null(TaxaFlag:::.parse_json_text("This is not JSON at all"))
})
