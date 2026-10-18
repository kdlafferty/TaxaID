# Prompt version v5: id-matched answers (R1), whole-batch mismatch is a failed
# call (R2), one-set-per-call re-ask (R3), geography GUIDELINES bullets
# (a)/(b)/(f), default temperature 0.2 (e). Every test uses a mock llm_fn.

.v5_obj <- function(name, id = NULL, comment = "ok") {
  id_part <- if (is.null(id)) "" else if (is.na(id)) '"id": null, ' else sprintf('"id": "%s", ', id)
  sprintf(
    '{%s"taxon_name": "%s", "habitat_plausibility": "likely", "geographic_plausibility": "likely", "scope_plausibility": "likely", "contamination_risk": "low", "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": "%s"}',
    id_part, name, comment
  )
}

.v5_json <- function(objs) paste0("[", paste(objs, collapse = ","), "]")

# The taxon lines of a prompt: list(id = "T<i>", label = <text after the id>).
.v5_asked <- function(prompt) {
  part <- sub("(?s).*TAXA TO REVIEW:\n", "", prompt, perl = TRUE)
  lines <- grep("^- \\[T[0-9]+\\] ", strsplit(part, "\n", fixed = TRUE)[[1]], value = TRUE)
  list(
    id = sub("^- \\[(T[0-9]+)\\] .*$", "\\1", lines),
    label = sub("^- \\[T[0-9]+\\] ", "", lines)
  )
}

.v5_long <- paste(
  "Ctenopharyngodon idella + Squaliobarbus curriculus + Hypophthalmichthys nobilis +",
  "Opsariichthys + Zacco + Metzia + Xenocyprididae + Anabarilius + Xenocypris +",
  "Hypophthalmichthys + Opsariichthys jishuiensis + Zacco acanthogenys +",
  "Metzia longinasus + Anabarilius brevianalis + Xenocypris davidi +",
  "Ctenopharyngodon + Squaliobarbus"
)

# Same number of objects as sets asked, but the sets matching `omit` come back
# under an unmatchable name and no id (a count-preserving omission; a SHORT
# reply is "truncated" and halved instead).
.v5_answer_except <- function(a, omit) {
  drop <- grepl(omit, a$label)
  .v5_json(vapply(seq_along(a$id), function(i) {
    if (drop[i]) .v5_obj(paste0("unmatched ", i)) else .v5_obj(a$label[i], a$id[i])
  }, character(1)))
}

.v5_ctx <- list(geography = "Lake Michigan", habitat = "harbor")

.v5_review <- function(labels, llm_fn, ..., extra = NULL) {
  df <- data.frame(
    observation_id = paste0("o", seq_along(labels)),
    primary_taxon = labels, stringsAsFactors = FALSE
  )
  if (!is.null(extra)) df <- cbind(df, extra)
  review_assignments(
    data_type = "eDNA", input_df = df, taxon_col = "primary_taxon",
    context = .v5_ctx, llm_fn = llm_fn, pause_seconds = 0, ...
  )
}

# --- 1. Batch-4 shape: long "+" label echoed back reformatted ----------------

test_that("a reformatted 17-name label is matched by id: one call, no NA rows", {
  expect_equal(lengths(strsplit(.v5_long, " + ", fixed = TRUE)), 17L)
  n <- 0L
  seen <- NULL
  fn <- function(prompt_str, ...) {
    n <<- n + 1L
    a <- .v5_asked(prompt_str)
    seen <<- a
    # reformatted names (", " joined, truncated), correct ids
    nm <- gsub(" + ", ", ", a$label, fixed = TRUE)
    nm[2L] <- substr(nm[2L], 1L, 20L)
    .v5_json(mapply(.v5_obj, nm, a$id, USE.NAMES = FALSE))
  }
  labels <- c("Lepomis macrochirus + Perca flavescens", .v5_long, "Cottus bairdii/cognatus")
  out <- .v5_review(labels, fn, verbose = FALSE)
  expect_equal(n, 1L)
  expect_equal(seen$id, c("T1", "T2", "T3"))
  expect_false(any(is.na(out$llm_habitat_plausibility)))
  expect_equal(nrow(out), 3L)
  expect_equal(out$llm_habitat_plausibility, rep("likely", 3L))
})

# --- 2. Whole-batch mismatch without ids: halving ------------------------------

test_that("a batch answered under wrong names and no ids is halved and fully reviewed", {
  sizes <- integer(0)
  fn <- function(prompt_str, ...) {
    a <- .v5_asked(prompt_str)
    sizes <<- c(sizes, length(a$id))
    nm <- if (length(a$id) > 2L) paste0("Wrong name ", seq_along(a$id)) else a$label
    .v5_json(vapply(nm, .v5_obj, character(1), USE.NAMES = FALSE))
  }
  out <- .v5_review(
    c("Lepomis gibbosus", "Perca flavescens", "Cottus bairdii", "Esox lucius"),
    fn, verbose = FALSE
  )
  expect_equal(sizes, c(4L, 2L, 2L))
  expect_false(any(is.na(out$llm_habitat_plausibility)))
})

test_that(".parse_review_response: no set matched out of several is 'failed'; one of one is not", {
  b <- data.frame(taxon_name = c("A x", "B y"), stringsAsFactors = FALSE)
  r <- .parse_review_response(.v5_json(c(.v5_obj("zz"), .v5_obj("yy"))), b, NULL, NULL)
  expect_equal(attr(r, "status"), "failed")
  expect_setequal(attr(r, "missing_taxa"), c("A x", "B y"))
  # one set, one object, any name: accepted
  b1 <- data.frame(taxon_name = "A x", stringsAsFactors = FALSE)
  r1 <- .parse_review_response(.v5_json(.v5_obj("whatever")), b1, NULL, NULL)
  expect_equal(attr(r1, "status"), "complete")
  expect_equal(r1$taxon_name, "A x")
  expect_length(attr(r1, "missing_taxa"), 0L)
})

# --- 3. No-progress singleton: one set per call ---------------------------------

test_that("sets omitted from every multi-set ask are recovered one set per call", {
  n <- 0L
  fn <- function(prompt_str, ...) {
    n <<- n + 1L
    a <- .v5_asked(prompt_str)
    if (length(a$id) == 1L) {
      return(.v5_json(.v5_obj("some other name")))
    }
    .v5_answer_except(a, "Perca|Esox")
  }
  msgs <- character(0)
  out <- suppressWarnings(withCallingHandlers(
    .v5_review(c("Lepomis gibbosus", "Perca flavescens", "Esox lucius"), fn, verbose = TRUE),
    message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  ))
  expect_true(any(grepl("one set per call", msgs, fixed = TRUE)))
  # 1 full ask, 1 grouped re-ask (no progress), then Perca and Esox alone
  expect_equal(n, 4L)
  expect_false(any(is.na(out$llm_habitat_plausibility)))
  expect_equal(out$primary_taxon, c("Lepomis gibbosus", "Perca flavescens", "Esox lucius"))
})

test_that("a re-ask that makes progress does not switch to one set per call", {
  n <- 0L
  fn <- function(prompt_str, ...) {
    n <<- n + 1L
    a <- .v5_asked(prompt_str)
    .v5_answer_except(a, if (n == 1L) "Perca|Esox" else "^$")
  }
  msgs <- character(0)
  out <- suppressWarnings(withCallingHandlers(
    .v5_review(c("Lepomis gibbosus", "Perca flavescens", "Esox lucius"), fn, verbose = TRUE),
    message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  ))
  expect_equal(n, 2L)
  expect_false(any(grepl("one set per call", msgs, fixed = TRUE)))
  expect_false(any(is.na(out$llm_habitat_plausibility)))
})

test_that("a hard llm_fn error in a re-ask stops re-asking", {
  n <- 0L
  fn <- function(prompt_str, ...) {
    n <<- n + 1L
    a <- .v5_asked(prompt_str)
    if (n > 1L) stop("network down")
    .v5_answer_except(a, "Perca|Esox")
  }
  warns <- character(0)
  out <- withCallingHandlers(
    .v5_review(c("Lepomis gibbosus", "Perca flavescens", "Esox lucius"), fn,
      verbose = FALSE, max_retries = 3L
    ),
    warning = function(w) {
      warns <<- c(warns, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  expect_true(any(grepl("network down", warns, fixed = TRUE)))
  expect_equal(n, 2L)
  expect_equal(sum(is.na(out$llm_habitat_plausibility)), 2L)
})

# --- 4. Echoed id prefix ----------------------------------------------------------

test_that("an echoed '[T<i>] ' prefix is stripped silently", {
  fn <- function(prompt_str, ...) {
    a <- .v5_asked(prompt_str)
    .v5_json(mapply(function(l, i) .v5_obj(paste0("[", i, "] ", l)), a$label, a$id, USE.NAMES = FALSE))
  }
  expect_silent(
    out <- .v5_review(c("Cottus", "Perca flavescens"), fn, verbose = FALSE)
  )
  expect_false(any(is.na(out$llm_habitat_plausibility)))
  b <- data.frame(taxon_name = "Cottus", stringsAsFactors = FALSE)
  r <- .parse_review_response(.v5_json(.v5_obj("[T1] Cottus")), b, NULL, NULL)
  expect_equal(r$taxon_name, "Cottus")
  expect_length(attr(r, "pending_warnings"), 0L)
})

# --- 5/6. GUIDELINES bullets --------------------------------------------------------

.v5_prompt <- function(labels, extra = NULL, taxon_col = "primary_taxon") {
  got <- NULL
  fn <- function(prompt_str, ...) {
    got <<- prompt_str
    a <- .v5_asked(prompt_str)
    .v5_json(mapply(.v5_obj, a$label, a$id, USE.NAMES = FALSE))
  }
  suppressWarnings(.v5_review(labels, fn, verbose = FALSE, extra = extra))
  got
}
.v5_guidelines <- function(p) {
  sub("(?s)^.*GUIDELINES:\n(.*)EXAMPLE OUTPUT FORMAT:.*$", "\\1", p, perl = TRUE)
}

test_that("UNPRECEDENTED and INDISTINGUISHABLE bullets appear only with their flags", {
  with_flags <- .v5_prompt(c("Cyprinus carpio", "Perca flavescens"), extra = data.frame(
    consensus_plausibility = c("unprecedented", "plausible"),
    consensus_discrimination = c("resolved", "indistinguishable"),
    stringsAsFactors = FALSE
  ))
  g <- .v5_guidelines(with_flags)
  expect_match(g, "absence of a citeable record is NOT evidence of absence", fixed = TRUE)
  expect_match(g, 'most "possible", never "likely"', fixed = TRUE)
  expect_match(g, 'Rate it "unlikely" only with POSITIVE evidence', fixed = TRUE)
  expect_match(g, "weakens confidence in the NAME, not the ecology", fixed = TRUE)
  expect_false(grepl('otherwise rate it "unlikely"', with_flags, fixed = TRUE))
  expect_false(grepl("hard requirement", with_flags, fixed = TRUE))
  expect_match(with_flags, "pipeline flags UNPRECEDENTED", fixed = TRUE)

  # only the unprecedented flag: no indistinguishable bullet, and vice versa
  only_u <- .v5_guidelines(.v5_prompt(c("Cyprinus carpio", "Perca flavescens"),
    extra = data.frame(consensus_plausibility = c("unprecedented", "plausible"))
  ))
  expect_match(only_u, "NOT evidence of absence", fixed = TRUE)
  expect_false(grepl("weakens confidence in the NAME", only_u, fixed = TRUE))
  only_i <- .v5_guidelines(.v5_prompt(c("Cyprinus carpio", "Perca flavescens"),
    extra = data.frame(consensus_discrimination = c("indistinguishable", "resolved"))
  ))
  expect_match(only_i, "weakens confidence in the NAME", fixed = TRUE)
  expect_false(grepl("NOT evidence of absence", only_i, fixed = TRUE))

  none <- .v5_prompt(c("Cyprinus carpio", "Perca flavescens"), extra = data.frame(
    consensus_plausibility = c("plausible", "plausible"),
    consensus_discrimination = c("resolved", "resolved"),
    stringsAsFactors = FALSE
  ))
  expect_false(grepl("NOT evidence of absence", none, fixed = TRUE))
  expect_false(grepl("weakens confidence in the NAME", none, fixed = TRUE))
  expect_false(grepl("UNPRECEDENTED", none, fixed = TRUE))
  expect_false(grepl('otherwise rate it "unlikely"', none, fixed = TRUE))
  expect_false(grepl("hard requirement", none, fixed = TRUE))
  # and with no pipeline columns at all
  bare <- .v5_prompt(c("Cyprinus carpio", "Perca flavescens"))
  expect_false(grepl("NOT evidence of absence", bare, fixed = TRUE))
  expect_false(grepl("hard requirement", bare, fixed = TRUE))
})

test_that("a label that differs from the call gets 'pipeline call: X (rank)' and the call-rank bullet", {
  p <- .v5_prompt("Lepidogobius lepidus", extra = data.frame(
    consensus_taxon = "Gobiidae", consensus_rank = "family",
    consensus_posterior = 0.9, stringsAsFactors = FALSE
  ))
  expect_match(p, "pipeline call: Gobiidae (family)", fixed = TRUE)
  g <- .v5_guidelines(p)
  expect_match(g, 'When a bracket gives "pipeline call: <taxon> (<rank>)"', fixed = TRUE)
  expect_match(g, "is the claim", fixed = TRUE)
  expect_false(grepl("hard requirement", p, fixed = TRUE))
  # the line itself: id, label, then the bracket
  expect_match(p, "- [T1] Lepidogobius lepidus [", fixed = TRUE)
  expect_match(p, "\\[[^]]*pipeline call: Gobiidae \\(family\\)[^]]*\\]")
})

test_that("label == call: no 'pipeline call:' note and no call-rank bullet", {
  p <- .v5_prompt("Gobiidae", extra = data.frame(
    consensus_taxon = "Gobiidae", consensus_rank = "family",
    consensus_posterior = 0.9, stringsAsFactors = FALSE
  ))
  expect_false(grepl("pipeline call: Gobiidae", p, fixed = TRUE))
  expect_false(grepl('pipeline call: <taxon> (<rank>)', p, fixed = TRUE))
  # without a consensus_rank column the note cannot be built either
  p2 <- .v5_prompt("Lepidogobius lepidus", extra = data.frame(
    consensus_taxon = "Gobiidae", consensus_posterior = 0.9, stringsAsFactors = FALSE
  ))
  expect_false(grepl("pipeline call:", p2, fixed = TRUE))
})

# --- 7. v4 -> v5 cache miss ---------------------------------------------------------

test_that("verdicts cached under prompt version v4 are a miss", {
  cd <- tempfile("v5cache")
  on.exit(unlink(cd, recursive = TRUE), add = TRUE)
  n <- 0L
  fn <- function(prompt_str, ...) {
    n <<- n + 1L
    a <- .v5_asked(prompt_str)
    .v5_json(mapply(.v5_obj, a$label, a$id, USE.NAMES = FALSE))
  }
  run <- function() .v5_review(c("Cottus bairdii", "Perca flavescens"), fn, cache_dir = cd, verbose = FALSE)
  run()
  expect_equal(n, 1L)
  run()
  expect_equal(n, 1L) # a hit under v5
  files <- list.files(cd, full.names = TRUE)
  expect_gt(length(files), 0L)
  rekeyed <- 0L
  for (f in files) {
    e <- readRDS(f)
    if (is.list(e) && !is.null(e$key)) {
      e$key <- sub("v5", "v4", e$key, fixed = TRUE)
      saveRDS(e, f)
      rekeyed <- rekeyed + 1L
    }
  }
  expect_gt(rekeyed, 0L)
  run()
  expect_equal(n, 2L)
})

# --- 8. Default temperature -----------------------------------------------------------

.v5_temp_df <- data.frame(observation_id = c("o1", "o2"), primary_taxon = c("Cottus", "Perca flavescens"))
.v5_valid_reply <- function(prompt_str) {
  a <- .v5_asked(prompt_str)
  .v5_json(mapply(.v5_obj, a$label, a$id, USE.NAMES = FALSE))
}
.v5_run_default <- function() {
  review_assignments(
    data_type = "eDNA", input_df = .v5_temp_df, taxon_col = "primary_taxon",
    context = .v5_ctx, pause_seconds = 0, verbose = FALSE
  )
}

test_that("temperature, shape 1: llm_fn not supplied and option NULL -> call_api at 0.2", {
  withr::local_options(list(TaxaID.llm_fn = NULL))
  temps <- list()
  testthat::local_mocked_bindings(
    call_api = function(prompt_str, ..., temperature = NULL) {
      temps[[length(temps) + 1L]] <<- temperature
      .v5_valid_reply(prompt_str)
    },
    .package = "TaxaTools"
  )
  out <- .v5_run_default()
  expect_length(temps, 1L)
  expect_equal(temps[[1L]], 0.2)
  expect_false(any(is.na(out$llm_habitat_plausibility)))
})

test_that("temperature, shape 2: option explicitly set to TaxaTools::call_api -> still 0.2", {
  temps <- list()
  testthat::local_mocked_bindings(
    call_api = function(prompt_str, ..., temperature = NULL) {
      temps[[length(temps) + 1L]] <<- temperature
      .v5_valid_reply(prompt_str)
    },
    .package = "TaxaTools"
  )
  withr::local_options(list(TaxaID.llm_fn = TaxaTools::call_api))
  out <- .v5_run_default()
  expect_length(temps, 1L)
  expect_equal(temps[[1L]], 0.2)
  expect_false(any(is.na(out$llm_habitat_plausibility)))
})

test_that("temperature, shape 3: option naming call_anthropic_api (Mugu batch shape) is used AS GIVEN", {
  api_args <- list()
  api_n <- 0L
  testthat::local_mocked_bindings(
    call_api = function(prompt_str, ..., temperature = NULL) {
      stop("call_api must not be reached")
    },
    call_anthropic_api = function(prompt_str, ...) {
      api_n <<- api_n + 1L
      api_args[[api_n]] <<- c(list(...), if (FALSE) NULL)
      .v5_valid_reply(prompt_str)
    },
    .package = "TaxaTools"
  )
  withr::local_options(list(TaxaID.llm_fn = function(p, ...) TaxaTools::call_anthropic_api(p)))
  out <- .v5_run_default()
  expect_equal(api_n, 1L)
  expect_false("temperature" %in% names(api_args[[1L]]))
  expect_length(api_args[[1L]], 0L)
  expect_false(any(is.na(out$llm_habitat_plausibility)))
})

test_that("temperature: a supplied llm_fn is called exactly as given, no temperature argument", {
  withr::local_options(list(TaxaID.llm_fn = NULL))
  called_api <- FALSE
  testthat::local_mocked_bindings(
    call_api = function(prompt_str, ..., temperature = NULL) {
      called_api <<- TRUE
      stop("not expected")
    },
    .package = "TaxaTools"
  )
  got <- NULL
  mine <- function(prompt_str, ...) {
    got <<- names(list(...))
    .v5_valid_reply(prompt_str)
  }
  review_assignments(
    data_type = "eDNA", input_df = .v5_temp_df, taxon_col = "primary_taxon",
    context = .v5_ctx, llm_fn = mine, pause_seconds = 0, verbose = FALSE
  )
  expect_false("temperature" %in% got)
  expect_false(called_api)
})

# --- 9. Shape grid for the id parser -------------------------------------------------

test_that("id parsing: T1 / t1 / ' T1 ' all match; names are overridden by the id", {
  b <- data.frame(taxon_name = c("A x", "B y", "C z"), stringsAsFactors = FALSE)
  resp <- .v5_json(c(.v5_obj("n1", "T1"), .v5_obj("n2", "t2"), .v5_obj("n3", " T3 ")))
  r <- .parse_review_response(resp, b, NULL, NULL)
  expect_equal(attr(r, "status"), "complete")
  expect_setequal(r$taxon_name, b$taxon_name)
  expect_length(attr(r, "missing_taxa"), 0L)
  # a conflicting name loses to the id
  r2 <- .parse_review_response(.v5_json(c(
    .v5_obj("B y", "T1"), .v5_obj("B y", "T2"), .v5_obj("C z", "T3")
  )), b, NULL, NULL)
  expect_setequal(r2$taxon_name, b$taxon_name)
})

test_that("id parsing: a duplicated id keeps the first object; the repeat falls back to its name", {
  b <- data.frame(taxon_name = c("A x", "B y", "C z"), stringsAsFactors = FALSE)
  # repeat has an unmatchable name -> that set is missing
  r <- .parse_review_response(.v5_json(c(
    .v5_obj("n1", "T1", "first"), .v5_obj("n2", "T1", "repeat"), .v5_obj("n3", "T3")
  )), b, NULL, NULL)
  expect_equal(attr(r, "missing_taxa"), "B y")
  expect_equal(r$review_comment[r$taxon_name == "A x"], "first")
  # repeat whose own name is right: the name decides, so nothing is lost
  r2 <- .parse_review_response(.v5_json(c(
    .v5_obj("n1", "T1"), .v5_obj("B y", "T1"), .v5_obj("n3", "T3")
  )), b, NULL, NULL)
  expect_length(attr(r2, "missing_taxa"), 0L)
  expect_setequal(r2$taxon_name, b$taxon_name)
})

test_that("id parsing: an id beyond the batch or NA is ignored and the name decides", {
  b <- data.frame(taxon_name = c("A x", "B y"), stringsAsFactors = FALSE)
  r <- .parse_review_response(.v5_json(c(.v5_obj("A x", "T1"), .v5_obj("B y", "T9"))), b, NULL, NULL)
  expect_length(attr(r, "missing_taxa"), 0L)
  r <- .parse_review_response(.v5_json(c(.v5_obj("A x", "T1"), .v5_obj("zzz", "T9"))), b, NULL, NULL)
  expect_equal(attr(r, "missing_taxa"), "B y")
  r <- .parse_review_response(.v5_json(c(.v5_obj("A x", "T1"), .v5_obj("B y", NA))), b, NULL, NULL)
  expect_length(attr(r, "missing_taxa"), 0L)
  r <- .parse_review_response(.v5_json(c(.v5_obj("A x", "T1"), .v5_obj("zzz", NA))), b, NULL, NULL)
  expect_equal(attr(r, "missing_taxa"), "B y")
  # T0 and a non-id string are unknown ids too
  r <- .parse_review_response(.v5_json(c(.v5_obj("A x", "T0"), .v5_obj("B y", "banana"))), b, NULL, NULL)
  expect_length(attr(r, "missing_taxa"), 0L)
})

test_that("id parsing: no id column falls back to exact then normalised name", {
  b <- data.frame(taxon_name = c("A x", "B y", "C z"), stringsAsFactors = FALSE)
  r <- .parse_review_response(.v5_json(c(.v5_obj("A x"), .v5_obj("b y."), .v5_obj("C z"))), b, NULL, NULL)
  expect_equal(attr(r, "status"), "complete")
  expect_length(attr(r, "missing_taxa"), 0L)
  expect_true(any(grepl("normalised matching", attr(r, "pending_warnings"))))
  # exact names: no normalisation warning
  r <- .parse_review_response(.v5_json(c(.v5_obj("A x"), .v5_obj("B y"), .v5_obj("C z"))), b, NULL, NULL)
  expect_false(any(grepl("normalised matching", attr(r, "pending_warnings"))))
  # id column present but exact name still works when the id is junk
  r <- .parse_review_response(.v5_json(c(.v5_obj("A x", "?"), .v5_obj("B y", "?"), .v5_obj("C z", "?"))), b, NULL, NULL)
  expect_length(attr(r, "missing_taxa"), 0L)
})
