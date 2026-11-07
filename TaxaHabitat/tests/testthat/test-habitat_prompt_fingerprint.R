# The habitat cache key holds the INPUTS, not the prompt, so a wording change
# that can move a verdict is guarded only by the version token in
# build_habitat_lookup() (currently "v2"). That token sat at "v1" while the
# prompt's compound-label wording changed under it -- "afterwards as the
# maximum over its components" became "afterwards from its components" -- which
# is the failure this file exists to stop repeating.
#
# A digest of the rendered prompt would not do: build_habitat_prompt() assembles
# per chunk and includes the compound guidelines only when the scheme declares
# parts, so the rendered text depends on the scheme and the chunking rather than
# on the wording alone.
#
# Hashing uses .habitat_cache_hash(), base-R arithmetic over code points, not
# rlang::hash(), whose value moves between rlang versions and would make this
# test fail on a dependency upgrade.

.hpf_fns <- c(
  "build_habitat_prompt",
  ".build_single_prompt",
  ".compounds_from_scheme",
  ".l1_to_realm"
)

# Fill from the failure message of one run, then commit the value. The sentinel
# must FAIL rather than skip: an un-initialised fingerprint is an absent guard.
.hpf_expected <- "0992572018-0463484266-011692"

.hpf_fingerprint <- function() {
  ns <- asNamespace("TaxaHabitat")
  src <- vapply(
    .hpf_fns,
    function(f) paste(deparse(get(f, envir = ns)), collapse = "\n"),
    character(1)
  )
  TaxaHabitat:::.habitat_cache_hash(paste(src, collapse = "\n\n"))
}

test_that("the habitat prompt's source matches the fingerprint the key token was set for", {
  for (f in .hpf_fns) {
    expect_true(
      exists(f, envir = asNamespace("TaxaHabitat"), inherits = FALSE),
      info = sprintf("%s has been renamed or removed; update .hpf_fns.", f)
    )
  }
  got <- .hpf_fingerprint()
  expect_false(
    is.na(.hpf_expected),
    info = sprintf(
      "The habitat-prompt fingerprint is un-initialised. Set .hpf_expected to \"%s\".",
      got
    )
  )
  expect_identical(
    got, .hpf_expected,
    info = paste0(
      "The habitat prompt's wording changed. A cached verdict given under the ",
      "old wording would be served as a hit, because the cache key holds the ",
      "inputs and not the prompt. BUMP the version token in ",
      "build_habitat_lookup() (\"v2\" -> \"v3\"), record what changed in the ",
      "comment above shared_key, and set .hpf_expected to \"", got, "\"."
    )
  )
})

test_that("every habitat cache entry records what answered it", {
  cache_dir <- withr::local_tempdir()
  scheme <- data.frame(l1_name = c("Lentic", "Lotic"), stringsAsFactors = FALSE)
  taxa <- c("Esox lucius", "Moxostoma macrolepidotum")

  # The column shape the parser expects for this scheme; a stray column would
  # be folded into Other_weight with a warning and this test is not about that.
  fake <- function(p, ...) {
    paste(c(
      "taxon_name,Lentic,Lotic,Other_weight,habitat_best_guess",
      "Esox lucius,0.9,0.1,0,Lentic",
      "Moxostoma macrolepidotum,0.2,0.8,0,Lotic"
    ), collapse = "\n")
  }
  out <- suppressMessages(suppressWarnings(build_habitat_lookup(
    taxa, habitat_scheme = scheme, llm_fn = fake,
    cache_dir = cache_dir, verbose = FALSE
  )))
  skip_if(nrow(out) == 0L, "the fake response did not parse; nothing was cached")

  files <- list.files(cache_dir, pattern = "_habitat\\.rds$", full.names = TRUE)
  expect_gt(length(files), 0L)
  for (f in files) {
    ent <- readRDS(f)
    # The point of the change: an entry can be traced to what produced it.
    expect_true("model" %in% names(ent))
    expect_false(is.null(ent$model))
    expect_type(ent$model, "character")
    expect_true(nzchar(ent$model))
  }

  # cache_summary names the model in force and every model behind the verdicts.
  cs <- attr(out, "cache_summary")
  expect_true(all(c("model", "models", "n_model_unknown") %in% names(cs)))
  expect_identical(cs$n_model_unknown, 0L)
  expect_length(cs$models, 1L)
})

test_that("a cache mixing two models warns, and a stub that is never called does not", {
  cache_dir <- withr::local_tempdir()
  scheme <- data.frame(l1_name = c("Lentic", "Lotic"), stringsAsFactors = FALSE)

  resp <- function(name, a, b, best) {
    paste(c(
      "taxon_name,Lentic,Lotic,Other_weight,habitat_best_guess",
      sprintf("%s,%s,%s,0,%s", name, a, b, best)
    ), collapse = "\n")
  }
  m1 <- function(p, ...) resp("Esox lucius", 0.9, 0.1, "Lentic")
  out1 <- suppressMessages(suppressWarnings(build_habitat_lookup(
    "Esox lucius", habitat_scheme = scheme, llm_fn = m1,
    cache_dir = cache_dir, verbose = FALSE
  )))
  skip_if(nrow(out1) == 0L, "the fake response did not parse; nothing was cached")

  # Same taxon, same key, nothing to ask: the stub is not counted, so no warning
  # even though it is a different function from the one that wrote the entry.
  never <- function(p, ...) stop("must not be called")
  expect_warning(
    suppressMessages(build_habitat_lookup(
      "Esox lucius", habitat_scheme = scheme, llm_fn = never,
      cache_dir = cache_dir, verbose = FALSE
    )),
    NA
  )

  # A second taxon under a different function DOES mix: one verdict from the
  # cache's model, one about to come from this one.
  m2 <- function(p, ...) resp("Perca flavescens", 0.8, 0.2, "Lentic")
  expect_warning(
    suppressMessages(build_habitat_lookup(
      c("Esox lucius", "Perca flavescens"), habitat_scheme = scheme,
      llm_fn = m2, cache_dir = cache_dir, verbose = FALSE
    )),
    "draws on 2 different models"
  )
})

test_that("the recorded model is the one the provider resolved, not the wrapper", {
  cache_dir <- withr::local_tempdir()
  scheme <- data.frame(l1_name = c("Lentic", "Lotic"), stringsAsFactors = FALSE)

  # Shaped like call_api: the response carries the model that answered, which
  # prompt_api() propagates. Two wrappers can look identical and resolve to
  # different models, so the record has to come from the call, not the function.
  with_model <- function(id, name = "Esox lucius") {
    function(p, ...) {
      out <- paste(c(
        "taxon_name,Lentic,Lotic,Other_weight,habitat_best_guess",
        sprintf("%s,0.9,0.1,0,Lentic", name)
      ), collapse = "\n")
      attr(out, "model") <- id
      out
    }
  }

  out <- suppressMessages(build_habitat_lookup(
    "Esox lucius", habitat_scheme = scheme, llm_fn = with_model("claude-z-9"),
    cache_dir = cache_dir, verbose = FALSE
  ))
  skip_if(nrow(out) == 0L, "the fake response did not parse; nothing was cached")

  files <- list.files(cache_dir, pattern = "_habitat\\.rds$", full.names = TRUE)
  expect_length(files, 1L)
  expect_identical(readRDS(files[[1]])$model, "claude-z-9")
  expect_identical(attr(out, "cache_summary")$model, "claude-z-9")

  # A second wrapper that LOOKS different but resolves to the same model is not
  # a mixed result, so it must not warn -- the point of recording the resolved
  # model rather than the function.
  same_model_other_wrapper <- function(p, ...) {
    out <- paste(c(
      "taxon_name,Lentic,Lotic,Other_weight,habitat_best_guess",
      "Perca flavescens,0.8,0.2,0,Lentic"
    ), collapse = "\n")
    attr(out, "model") <- "claude-z-9"
    out
  }
  expect_warning(
    suppressMessages(build_habitat_lookup(
      c("Esox lucius", "Perca flavescens"), habitat_scheme = scheme,
      llm_fn = same_model_other_wrapper, cache_dir = cache_dir, verbose = FALSE
    )),
    NA
  )

  # A genuinely different model IS a mixed result.
  expect_warning(
    suppressMessages(build_habitat_lookup(
      c("Esox lucius", "Gasterosteus aculeatus"), habitat_scheme = scheme,
      llm_fn = with_model("grok-q-2", "Gasterosteus aculeatus"),
      cache_dir = cache_dir, verbose = FALSE
    )),
    "draws on 2 different models"
  )
})
