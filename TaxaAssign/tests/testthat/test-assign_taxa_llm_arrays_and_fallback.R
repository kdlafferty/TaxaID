# tests/testthat/test-assign_taxa_llm_arrays_and_fallback.R
#
# Two ways a partial run used to look complete:
#   * the array extractor ran from the first "[" to the last "]", so a reply
#     that corrected itself with a second array captured both arrays and the
#     prose between them, failed to parse, and the whole batch became uniform
#     priors (2 of 327 answers in a measured run took that form);
#   * nothing counted those rows at the end of the call, so the only trace was
#     a per-call warning and a column nobody read.

taxa_df <- data.frame(
  taxon_name = c("Eucyclogobius newberryi", "Quietula y-cauda"),
  taxon_name_rank = rep("species", 2),
  hypothesis_type = rep("specific_candidate", 2),
  stringsAsFactors = FALSE
)

row_for <- function(name, w) {
  sprintf(
    '{"taxon_name":"%s","range_status":"native","prior_weight":%s}',
    name, format(w)
  )
}
arr <- function(...) {
  paste0("[\n  ", paste(c(...), collapse = ",\n  "), "\n]")
}
weight_of <- function(out, name) out$prior_mean[out$taxon_name == name]

# ---- the scanner -----------------------------------------------------------

test_that(".top_level_json_arrays finds each top-level span, in order", {
  expect_equal(.top_level_json_arrays("[1]"), "[1]")
  expect_equal(.top_level_json_arrays("noise [1] middle [2] tail"), c("[1]", "[2]"))
  # A nested array belongs to its parent span; it is not a span of its own.
  expect_equal(.top_level_json_arrays("[[1],[2]]"), "[[1],[2]]")
  expect_equal(.top_level_json_arrays("no brackets here"), character(0))
  expect_equal(.top_level_json_arrays(NA_character_), character(0))
  # An unclosed span is not returned: there is nothing to parse.
  expect_equal(.top_level_json_arrays('[{"taxon_name":"X"'), character(0))
})

test_that("a bracket inside a JSON string neither opens nor closes a span", {
  s <- '[{"taxon_name":"Genus [sp]","prior_weight":1}]'
  expect_equal(.top_level_json_arrays(s), s)
  # A backslash-escaped quote must not end the string early, or the "]" that
  # follows would be read as structure.
  s2 <- paste0('[{"taxon_name":"Genus \\" ] still inside","prior_weight":1}]')
  expect_equal(.top_level_json_arrays(s2), s2)
})

# ---- which array the parser believes --------------------------------------

test_that("a corrected second array wins over the first", {
  resp <- paste0(
    arr(
      row_for("Eucyclogobius newberryi", 0.2),
      row_for("Quietula y-cauda", 0.2)
    ),
    "\n\nCorrection: the weights above were on the wrong scale.\n\n",
    arr(
      row_for("Eucyclogobius newberryi", 0.9),
      row_for("Quietula y-cauda", 0.1)
    )
  )
  out <- .parse_taxa_response(resp, taxa_df)
  expect_equal(out$prior_source, rep("llm", 2))
  expect_equal(weight_of(out, "Eucyclogobius newberryi"), 0.9)
  expect_equal(weight_of(out, "Quietula y-cauda"), 0.1)
})

test_that("a single array parses exactly as it did before", {
  resp <- arr(
    row_for("Eucyclogobius newberryi", 0.7),
    row_for("Quietula y-cauda", 0.3)
  )
  out <- .parse_taxa_response(resp, taxa_df)
  expect_equal(out$prior_source, rep("llm", 2))
  expect_equal(weight_of(out, "Eucyclogobius newberryi"), 0.7)
})

test_that("markdown fences and surrounding prose are still tolerated", {
  resp <- paste0(
    "Here you go:\n```json\n",
    arr(row_for("Eucyclogobius newberryi", 0.6), row_for("Quietula y-cauda", 0.4)),
    "\n```\nHope that helps."
  )
  out <- .parse_taxa_response(resp, taxa_df)
  expect_equal(out$prior_source, rep("llm", 2))
  expect_equal(weight_of(out, "Quietula y-cauda"), 0.4)
})

test_that("an incomplete later array does not beat a complete earlier one", {
  # Taking the last array unconditionally would drop a taxon here. The rule is
  # the last array that parses AND names every taxon asked for.
  resp <- paste0(
    arr(
      row_for("Eucyclogobius newberryi", 0.9),
      row_for("Quietula y-cauda", 0.1)
    ),
    "\n\nCorrection: ",
    arr(row_for("Eucyclogobius newberryi", 0.5))
  )
  out <- .parse_taxa_response(resp, taxa_df)
  expect_setequal(out$taxon_name, taxa_df$taxon_name)
  expect_equal(weight_of(out, "Eucyclogobius newberryi"), 0.9)
})

test_that("a reply with no parsable array is still a uniform fallback", {
  # A "]" present but no array to find: this must take the GENERIC message,
  # not the truncation one, which is reserved for a reply cut off before any
  # "]" arrived.
  expect_warning(
    out <- .parse_taxa_response("I cannot answer that. ]", taxa_df),
    "Failed to parse"
  )
  expect_equal(out$prior_source, rep("uniform_fallback", 2))
  expect_true(all(is.na(out$prior_mean)))
})

test_that("an array without prior_weight is a uniform fallback, not a parse", {
  resp <- '[{"taxon_name":"Eucyclogobius newberryi","range_status":"native"}]'
  expect_warning(
    out <- .parse_taxa_response(resp, taxa_df),
    "Failed to parse"
  )
  expect_equal(out$prior_source, rep("uniform_fallback", 2))
})

test_that("a truncated reply keeps its own, more useful message", {
  expect_warning(
    out <- .parse_taxa_response('[{"taxon_name":"Eucyclogobius', taxa_df),
    "TRUNCATED"
  )
  expect_equal(out$prior_source, rep("uniform_fallback", 2))
})

# ---- the end-of-call report ------------------------------------------------

test_that("the call reports its uniform-fallback rows once, at the end", {
  match_df <- data.frame(
    observation_id = c("S1", "S1", "S2", "S2"),
    score_original = c(99, 93, 100, 88),
    taxon_name = c(
      "Eucyclogobius newberryi", "Quietula y-cauda",
      "Eucyclogobius newberryi", "Gillichthys mirabilis"
    ),
    taxon_name_rank = rep("species", 4),
    stringsAsFactors = FALSE
  )
  broken_llm <- function(prompt_str) "not valid json at all!!!"

  set.seed(1) # assign_taxa_llm() simulates; seeded so other tests cannot shift it
  warnings_seen <- character(0)
  res <- withCallingHandlers(
    assign_taxa_llm(match_df, llm_fn = broken_llm, pause_seconds = 0),
    warning = function(cnd) {
      warnings_seen <<- c(warnings_seen, conditionMessage(cnd))
      invokeRestart("muffleWarning")
    }
  )
  expect_true(
    any(grepl("failed or unparsable LLM answer", warnings_seen)),
    info = paste(warnings_seen, collapse = " | ")
  )
  expect_true(any(grepl("Treat this run as partial", warnings_seen)))
})

test_that("a run with no failure says nothing about fallbacks", {
  match_df <- data.frame(
    observation_id = c("S1", "S1"),
    score_original = c(99, 93),
    taxon_name = c("Eucyclogobius newberryi", "Quietula y-cauda"),
    taxon_name_rank = rep("species", 2),
    stringsAsFactors = FALSE
  )
  good_llm <- function(prompt_str) {
    taxa <- trimws(regmatches(
      prompt_str,
      gregexpr("(?m)(?<=^- )[^\n(]+(?= \\()", prompt_str, perl = TRUE)
    )[[1]])
    arr(unlist(lapply(taxa, row_for, w = 1)))
  }

  set.seed(1)
  warnings_seen <- character(0)
  res <- withCallingHandlers(
    assign_taxa_llm(match_df, llm_fn = good_llm, pause_seconds = 0),
    warning = function(cnd) {
      warnings_seen <<- c(warnings_seen, conditionMessage(cnd))
      invokeRestart("muffleWarning")
    }
  )
  expect_false(any(grepl("failed or unparsable LLM answer", warnings_seen)))
})
