# Tests for review_assignments(llm_batch_fn =): the batch route must be a
# TRANSPORT only. The same prompts go out, the same verdicts come back, the
# same cache files are written, and anything the batch leaves unanswered is
# asked through llm_fn exactly as the synchronous path would ask it.

# Answers every taxon listed in a review prompt "likely" (taxa_per_call-style
# prompts list each label on a "- " line); counts its calls and keeps prompts.
.bt_answering_llm <- function(log) {
  function(prompt, ...) {
    log$n <- log$n + 1L
    log$prompts <- c(log$prompts, prompt)
    labs <- sub("^- ", "", regmatches(prompt, gregexpr("(?m)^- .*$", prompt, perl = TRUE))[[1]])
    labs <- grep("\\((unresolved candidates|rank: )", labs, value = TRUE)
    labs <- ifelse(grepl("unresolved candidates", labs), labs,
      sub("\\s*\\(rank: [^()]*\\)$", "", labs)
    )
    paste0("[", paste(sprintf(
      '{"taxon_name":"%s","habitat_plausibility":"likely","geographic_plausibility":"likely","scope_plausibility":"likely","contamination_risk":"low","review_alternatives":null,"review_lower_hypotheses":null,"review_confidence":"high","review_comment":"ok"}',
      labs
    ), collapse = ","), "]")
  }
}
.bt_log <- function() {
  e <- new.env()
  e$n <- 0L
  e$prompts <- character(0)
  e
}
.bt_input <- function() {
  data.frame(
    observation_id = paste0("o", 1:5),
    consensus_taxon = c("Perca flavescens", "Lepomis gibbosus", "Esox lucius",
                        "Micropterus dolomieu", "Ambloplites rupestris"),
    consensus_rank = "species",
    stringsAsFactors = FALSE
  )
}
.bt_args <- function(llm_fn, ...) {
  c(list(.bt_input(),
    taxon_col = "consensus_taxon", taxon_rank_col = "consensus_rank",
    context = list(geography = "Lake Michigan", habitat = "harbor"),
    data_type = "eDNA", taxa_per_call = 2L, llm_fn = llm_fn,
    pause_seconds = 0, verbose = FALSE
  ), list(...))
}
.bt_batch_from <- function(answer, log) {
  function(prompts, ...) {
    log$n <- log$n + 1L
    log$prompts <- c(log$prompts, prompts)
    vapply(prompts, answer, character(1), USE.NAMES = FALSE)
  }
}

test_that("the batch route sends the same prompts and returns the same result as llm_fn", {
  sync_log <- .bt_log()
  sync <- do.call(review_assignments, .bt_args(.bt_answering_llm(sync_log)))

  batch_log <- .bt_log()
  fallback_log <- .bt_log()
  answer <- .bt_answering_llm(.bt_log())
  via_batch <- do.call(review_assignments, .bt_args(
    .bt_answering_llm(fallback_log),
    llm_batch_fn = .bt_batch_from(answer, batch_log)
  ))

  expect_identical(via_batch, sync)
  expect_equal(batch_log$n, 1L)                  # ONE call for every batch
  expect_identical(batch_log$prompts, sync_log$prompts)
  expect_equal(fallback_log$n, 0L)               # nothing left for llm_fn
})

test_that("a batch answered NA is asked again through llm_fn, and only that batch", {
  answer <- .bt_answering_llm(.bt_log())
  fallback_log <- .bt_log()
  holey <- function(prompts, ...) {
    out <- vapply(prompts, answer, character(1), USE.NAMES = FALSE)
    out[2] <- NA_character_
    out
  }
  res <- do.call(review_assignments, .bt_args(.bt_answering_llm(fallback_log), llm_batch_fn = holey))
  expect_equal(fallback_log$n, 1L)
  expect_false(anyNA(res$llm_habitat_plausibility))
})

test_that("a failing or wrong-shaped batch call falls back to llm_fn for every batch, with a warning", {
  sync_log <- .bt_log()
  sync <- do.call(review_assignments, .bt_args(.bt_answering_llm(sync_log)))

  log1 <- .bt_log()
  expect_warning(
    res1 <- do.call(review_assignments, .bt_args(
      .bt_answering_llm(log1),
      llm_batch_fn = function(prompts, ...) stop("network down")
    )),
    "llm_batch_fn failed \\(network down\\)"
  )
  expect_equal(log1$n, sync_log$n)
  expect_identical(res1, sync)

  log2 <- .bt_log()
  expect_warning(
    res2 <- do.call(review_assignments, .bt_args(
      .bt_answering_llm(log2),
      llm_batch_fn = function(prompts, ...) "only one"
    )),
    "returned 1 answer"
  )
  expect_equal(log2$n, sync_log$n)
  expect_identical(res2, sync)
})

test_that("an unparseable batch answer goes through the synchronous retry", {
  fallback_log <- .bt_log()
  junk <- function(prompts, ...) rep("this is not JSON", length(prompts))
  res <- suppressWarnings(do.call(review_assignments, .bt_args(
    .bt_answering_llm(fallback_log), llm_batch_fn = junk
  )))
  expect_gt(fallback_log$n, 0L)
  expect_false(anyNA(res$llm_habitat_plausibility))
})

test_that("max_tokens is forwarded to llm_batch_fn when set, and nothing else is", {
  seen <- new.env()
  answer <- .bt_answering_llm(.bt_log())
  spy <- function(prompts, ...) {
    seen$dots <- list(...)
    vapply(prompts, answer, character(1), USE.NAMES = FALSE)
  }
  do.call(review_assignments, .bt_args(.bt_answering_llm(.bt_log()), llm_batch_fn = spy))
  expect_identical(seen$dots, list())
  do.call(review_assignments, .bt_args(.bt_answering_llm(.bt_log()),
    llm_batch_fn = spy, max_tokens = 4000L
  ))
  expect_identical(seen$dots, list(max_tokens = 4000L))
})

test_that("verdicts cached by the batch route are served to the synchronous route", {
  cd <- file.path(tempdir(), paste0("flagbatch_", as.integer(runif(1, 1, 1e8))))
  on.exit(unlink(cd, recursive = TRUE), add = TRUE)
  answer <- .bt_answering_llm(.bt_log())
  do.call(review_assignments, .bt_args(.bt_answering_llm(.bt_log()),
    llm_batch_fn = .bt_batch_from(answer, .bt_log()), cache_dir = cd
  ))
  files_after_batch <- sort(list.files(cd))
  sync_log <- .bt_log()
  do.call(review_assignments, .bt_args(.bt_answering_llm(sync_log), cache_dir = cd))
  expect_equal(sync_log$n, 0L)                   # every verdict a cache hit
  expect_identical(sort(list.files(cd)), files_after_batch)
})

test_that("llm_batch_fn is the last formal, so main's formals stay a prefix", {
  f <- names(formals(review_assignments))
  expect_identical(f[length(f)], "llm_batch_fn")
  expect_null(formals(review_assignments)$llm_batch_fn)
})
