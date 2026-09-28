.sir_gate <- function(...) {
  d <- .sig_fixture()
  suppressWarnings(classify_sample_identity(d, control_samples = c("CLEAN", "MISLABEL", "PLANKTON"),
    taxon_label_col = "species", verbose = FALSE, on_pending = "ignore", ...))
}

.fake_llm <- function(skip = character(0)) {
  calls <- 0L
  f <- function(prompt, ...) {
    calls <<- calls + 1L
    ids <- regmatches(prompt, gregexpr("TUBE [A-Za-z0-9_]+", prompt))[[1]]
    ids <- setdiff(sub("TUBE ", "", ids), skip)
    objs <- vapply(ids, function(s) sprintf(
      '{"sample": "%s", "verdict": "%s", "suggested_disposition": "%s", "confidence": "high", "rationale": "because"}',
      s, if (s == "MISLABEL") "sample_labelled_as_blank" else "contaminated_blank",
      if (s == "MISLABEL") "reassign_to_sample" else "exclude_tube"), character(1))
    paste0("```json\n[", paste(objs, collapse = ","), "]\n```")
  }
  list(fn = f, calls = function() calls)
}

test_that("advice is attached per tube and never admits anything", {
  gate <- .sir_gate()
  llm <- .fake_llm()
  q <- review_sample_identity(gate, context = "Field blanks are distilled water.",
    llm_fn = llm$fn, verbose = FALSE)
  expect_equal(unique(q$llm_verdict[q$sample == "MISLABEL"]), "sample_labelled_as_blank")
  expect_equal(unique(q$llm_suggested_disposition[q$sample == "PLANKTON"]), "exclude_tube")
  expect_length(attr(q, "unreviewed_samples"), 0)
  # the gate itself is unchanged
  expect_false(any(attr(gate, "units")$admit[attr(gate, "units")$sample == "MISLABEL"]))
  # the prompt carries the tube's taxa and the run's field community
  p <- attr(q, "llm_prompts")[[1]]
  expect_match(p, "TUBE MISLABEL")
  expect_match(p, "field samples on this run")
  expect_match(p, "Field blanks are distilled water")
  expect_match(p, "run-wide artifact")
  expect_match(p, "BLANK MEDIUM \\(what a blank is filled with\\): not stated")
  expect_equal(unique(q$llm_role[q$sample == "MISLABEL"]), "sample")
  expect_equal(unique(q$llm_role[q$sample == "PLANKTON"]), "exclude")
})

test_that("omitted tubes are re-asked and reported if still missing", {
  gate <- .sir_gate()
  llm <- .fake_llm(skip = "PLANKTON")
  expect_warning(
    q <- review_sample_identity(gate, context = "x", llm_fn = llm$fn, max_retries = 2L,
      verbose = FALSE),
    "no LLM advice"
  )
  expect_equal(attr(q, "unreviewed_samples"), "PLANKTON")
  expect_equal(llm$calls(), 3L)
  # the re-asks carry the omitted tube alone
  pr <- attr(q, "llm_prompts")
  expect_false(grepl("TUBE MISLABEL", pr[[length(pr)]]))
  expect_match(pr[[length(pr)]], "TUBE PLANKTON")
  expect_true(all(is.na(q$llm_verdict[q$sample == "PLANKTON"])))
})

test_that("the cache serves repeat calls and never stores a non-answer", {
  dir <- tempfile()
  on.exit(unlink(dir, recursive = TRUE))
  gate <- .sir_gate()
  a <- .fake_llm(skip = "PLANKTON")
  suppressWarnings(review_sample_identity(gate, context = "x", llm_fn = a$fn,
    cache_dir = dir, max_retries = 0L, verbose = FALSE))
  expect_length(list.files(dir, pattern = "_identity_review\\.rds$"), 1)
  b <- .fake_llm()
  q <- review_sample_identity(gate, context = "x", llm_fn = b$fn, cache_dir = dir, verbose = FALSE)
  expect_equal(b$calls(), 1L)
  expect_false(grepl("TUBE MISLABEL", attr(q, "llm_prompts")[[1]]))
  # a changed context is a miss
  cc <- .fake_llm()
  review_sample_identity(gate, context = "y", llm_fn = cc$fn, cache_dir = dir, verbose = FALSE)
  expect_equal(cc$calls(), 1L)
})

test_that("advice merges into the decision record without touching user fields", {
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path))
  gate <- .sir_gate(decisions_path = path)
  rec <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character")
  rec$note[rec$sample == "PLANKTON"] <- "bag rinsed in the tidepool?"
  utils::write.csv(rec, path, row.names = FALSE, na = "")
  review_sample_identity(gate, context = "x", llm_fn = .fake_llm()$fn,
    decisions_path = path, verbose = FALSE)
  rec2 <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character")
  expect_equal(unique(rec2$note[rec2$sample == "PLANKTON"]), "bag rinsed in the tidepool?")
  expect_equal(unique(rec2$llm_verdict[rec2$sample == "MISLABEL"]), "sample_labelled_as_blank")
  expect_true(all(is.na(rec2$disposition) | rec2$disposition == ""))
  # a later gate run keeps the advice
  .sir_gate(decisions_path = path)
  rec3 <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character")
  expect_equal(unique(rec3$llm_verdict[rec3$sample == "MISLABEL"]), "sample_labelled_as_blank")
})

test_that("junk verdicts and dispositions are dropped, not trusted", {
  gate <- .sir_gate()
  f <- function(prompt, ...) '[{"sample": "MISLABEL", "verdict": "definitely_fine", "suggested_disposition": "x"},
    {"sample": "PLANKTON", "verdict": "contaminated_blank", "suggested_disposition": "delete_it", "confidence": "very"}]'
  q <- suppressWarnings(review_sample_identity(gate, context = "x", llm_fn = f,
    max_retries = 0L, verbose = FALSE))
  expect_equal(attr(q, "unreviewed_samples"), "MISLABEL")
  expect_true(all(is.na(q$llm_suggested_disposition[q$sample == "PLANKTON"])))
  expect_true(all(is.na(q$llm_confidence[q$sample == "PLANKTON"])))
})

test_that("input validation", {
  gate <- .sir_gate()
  expect_error(review_sample_identity(gate, llm_fn = identity), "'context' is required")
  expect_error(review_sample_identity(data.frame(), context = "x"), "unmodified result")
  nolab <- suppressWarnings(classify_sample_identity(.sig_fixture(),
    control_samples = c("CLEAN", "MISLABEL", "PLANKTON"), verbose = FALSE, on_pending = "ignore"))
  expect_error(review_sample_identity(nolab, context = "x", llm_fn = identity), "taxon_label_col")
})

test_that("blank_medium reaches the prompt and the cache key; an explicit role wins", {
  dir <- tempfile()
  on.exit(unlink(dir, recursive = TRUE))
  gate <- .sir_gate()
  f <- function(prompt, ...) {
    ids <- sub("TUBE ", "", regmatches(prompt, gregexpr("TUBE [A-Za-z0-9_]+", prompt))[[1]])
    paste0("[", paste(sprintf('{"sample": "%s", "verdict": "clean_blank", "role": "blank", "confidence": "moderate", "rationale": "tap-water taxa"}', ids), collapse = ","), "]")
  }
  q <- review_sample_identity(gate, context = "x", blank_medium = "tap water", llm_fn = f,
    cache_dir = dir, verbose = FALSE)
  expect_match(attr(q, "llm_prompts")[[1]], "BLANK MEDIUM \\(what a blank is filled with\\): tap water")
  expect_true(all(q$llm_role[!is.na(q$llm_verdict)] == "blank"))
  # a different medium is a cache miss
  n <- 0L
  g <- function(prompt, ...) { n <<- n + 1L; f(prompt) }
  review_sample_identity(gate, context = "x", blank_medium = "distilled water", llm_fn = g,
    cache_dir = dir, verbose = FALSE)
  expect_gt(n, 0L)
  expect_error(review_sample_identity(gate, context = "x", blank_medium = "", llm_fn = f), "blank_medium")
})
