# build_habitat_lookup() -- the cached wrapper (2026-09-10). No LLM is ever
# called: llm_fn is a fake that answers only for the taxa named in the prompt
# it receives, so the tests can see exactly which taxa reached the "LLM".

.fake_scheme <- data.frame(l1_name = c("Lentic", "Lotic"), stringsAsFactors = FALSE)

# A fake provider: returns a CSV row for every KNOWN taxon whose name appears
# in the prompt text, records each call, and can be told to answer nothing
# for a given taxon (all-zero weights -> Habitat NA -> must not be cached).
.make_fake_llm <- function(known, unresolved = character(0)) {
  calls <- new.env(parent = emptyenv())
  calls$prompts <- list()
  fn <- function(p, ...) {
    calls$prompts[[length(calls$prompts) + 1L]] <- p
    asked <- known[vapply(known, function(k) grepl(k, p, fixed = TRUE), logical(1))]
    rows <- vapply(asked, function(k) {
      if (k %in% unresolved) {
        sprintf("%s,0,0,0,", k)
      } else if (grepl("lucius", k)) {
        sprintf("%s,0.9,0.1,0,Lentic", k)
      } else {
        sprintf("%s,0.2,0.8,0,Lotic", k)
      }
    }, character(1))
    paste(c("taxon_name,Lentic,Lotic,Other_weight,habitat_best_guess", rows), collapse = "\n")
  }
  list(fn = fn, calls = calls)
}

.taxa_asked <- function(calls, known) {
  unique(unlist(lapply(calls$prompts, function(p) {
    known[vapply(known, function(k) grepl(k, p, fixed = TRUE), logical(1))]
  })))
}

test_that("build_habitat_lookup() without a cache_dir behaves like the three-step pattern", {
  taxa <- c("Esox lucius", "Moxostoma macrolepidotum")
  fake <- .make_fake_llm(taxa)
  out <- suppressMessages(build_habitat_lookup(
    taxa, habitat_scheme = .fake_scheme, llm_fn = fake$fn, verbose = FALSE
  ))
  expect_equal(out$taxon_name, taxa)
  expect_equal(out$Habitat, c("Lentic", "Lotic"))
  expect_equal(attr(out, "cache_summary")$n_from_cache, 0L)
  expect_equal(attr(out, "cache_summary")$n_called, 2L)
  expect_length(fake$calls$prompts, 1L)
})

test_that("a second identical call is served entirely from cache with zero LLM calls", {
  cache_dir <- withr::local_tempdir()
  taxa <- c("Esox lucius", "Moxostoma macrolepidotum", "Perca flavescens")
  fake <- .make_fake_llm(taxa)
  first <- suppressMessages(build_habitat_lookup(
    taxa, habitat_scheme = .fake_scheme, llm_fn = fake$fn,
    cache_dir = cache_dir, verbose = FALSE
  ))
  expect_equal(attr(first, "cache_summary")$n_cached_new, 3L)
  expect_length(list.files(cache_dir, pattern = "_habitat\\.rds$"), 3L)

  never <- function(p, ...) stop("the LLM must not be called on a full cache hit")
  second <- suppressMessages(build_habitat_lookup(
    taxa, habitat_scheme = .fake_scheme, llm_fn = never,
    cache_dir = cache_dir, verbose = FALSE
  ))
  expect_equal(attr(second, "cache_summary")$n_from_cache, 3L)
  expect_equal(attr(second, "cache_summary")$n_called, 0L)
  expect_equal(second$taxon_name, first$taxon_name)
  expect_equal(second$Habitat, first$Habitat)
  expect_equal(second$Lentic, first$Lentic)
})

test_that("only the taxa missing from the cache reach the LLM, and order follows taxon_list", {
  cache_dir <- withr::local_tempdir()
  known <- c("Esox lucius", "Moxostoma macrolepidotum", "Perca flavescens")
  fake <- .make_fake_llm(known)
  suppressMessages(build_habitat_lookup(
    known[1:2], habitat_scheme = .fake_scheme, llm_fn = fake$fn,
    cache_dir = cache_dir, verbose = FALSE
  ))
  fake2 <- .make_fake_llm(known)
  out <- suppressMessages(build_habitat_lookup(
    c("Perca flavescens", "Esox lucius", "Moxostoma macrolepidotum"),
    habitat_scheme = .fake_scheme, llm_fn = fake2$fn,
    cache_dir = cache_dir, verbose = FALSE
  ))
  expect_equal(.taxa_asked(fake2$calls, known), "Perca flavescens")
  expect_equal(out$taxon_name, c("Perca flavescens", "Esox lucius", "Moxostoma macrolepidotum"))
  expect_equal(attr(out, "cache_summary")$n_from_cache, 2L)
  expect_equal(attr(out, "cache_summary")$n_called, 1L)
})

test_that("a different scheme is a cache miss, not a wrong verdict", {
  cache_dir <- withr::local_tempdir()
  taxa <- "Esox lucius"
  fake <- .make_fake_llm(taxa)
  suppressMessages(build_habitat_lookup(
    taxa, habitat_scheme = .fake_scheme, llm_fn = fake$fn,
    cache_dir = cache_dir, verbose = FALSE
  ))
  other_scheme <- data.frame(l1_name = c("Lentic", "Lotic", "Estuarine"), stringsAsFactors = FALSE)
  fake2 <- function(p, ...) {
    "taxon_name,Lentic,Lotic,Estuarine,Other_weight,habitat_best_guess\nEsox lucius,0.5,0.5,0,0,Lentic"
  }
  out <- suppressMessages(build_habitat_lookup(
    taxa, habitat_scheme = other_scheme, llm_fn = fake2,
    cache_dir = cache_dir, verbose = FALSE
  ))
  expect_equal(attr(out, "cache_summary")$n_from_cache, 0L)
  expect_true("Estuarine" %in% names(out))
  expect_length(list.files(cache_dir, pattern = "_habitat\\.rds$"), 2L)
})

test_that("cache_tag forces a fresh classification for the same taxon and scheme", {
  cache_dir <- withr::local_tempdir()
  taxa <- "Esox lucius"
  fake <- .make_fake_llm(taxa)
  suppressMessages(build_habitat_lookup(
    taxa, habitat_scheme = .fake_scheme, llm_fn = fake$fn,
    cache_dir = cache_dir, verbose = FALSE
  ))
  fake2 <- .make_fake_llm(taxa)
  suppressMessages(build_habitat_lookup(
    taxa, habitat_scheme = .fake_scheme, llm_fn = fake2$fn,
    cache_dir = cache_dir, cache_tag = "other-model", verbose = FALSE
  ))
  expect_length(fake2$calls$prompts, 1L)
})

test_that("an unresolved verdict (Habitat NA) is returned but NOT cached, so it is re-asked", {
  cache_dir <- withr::local_tempdir()
  taxa <- c("Esox lucius", "Perca flavescens")
  fake <- .make_fake_llm(taxa, unresolved = "Perca flavescens")
  out <- suppressMessages(suppressWarnings(build_habitat_lookup(
    taxa, habitat_scheme = .fake_scheme, llm_fn = fake$fn,
    cache_dir = cache_dir, verbose = FALSE
  )))
  expect_true(is.na(out$Habitat[out$taxon_name == "Perca flavescens"]))
  expect_equal(attr(out, "cache_summary")$n_cached_new, 1L)

  fake2 <- .make_fake_llm(taxa)
  out2 <- suppressMessages(build_habitat_lookup(
    taxa, habitat_scheme = .fake_scheme, llm_fn = fake2$fn,
    cache_dir = cache_dir, verbose = FALSE
  ))
  expect_equal(.taxa_asked(fake2$calls, taxa), "Perca flavescens")
  expect_equal(out2$Habitat[out2$taxon_name == "Perca flavescens"], "Lotic")
})

test_that("build_habitat_lookup() validates its arguments", {
  expect_error(build_habitat_lookup(character(0)), "non-empty character")
  expect_error(build_habitat_lookup("Esox lucius", cache_dir = c("a", "b")), "cache_dir")
  expect_error(build_habitat_lookup("Esox lucius", cache_tag = NA_character_), "cache_tag")
})

test_that("taxahabitat_clear_cache() reports and prunes the per-taxon files", {
  cache_dir <- withr::local_tempdir()
  taxa <- c("Esox lucius", "Perca flavescens")
  fake <- .make_fake_llm(taxa)
  suppressMessages(build_habitat_lookup(
    taxa, habitat_scheme = .fake_scheme, llm_fn = fake$fn,
    cache_dir = cache_dir, verbose = FALSE
  ))
  inv <- suppressMessages(taxahabitat_clear_cache(cache_dir, dry_run = TRUE))
  expect_equal(nrow(inv), 2L)
  expect_length(list.files(cache_dir, pattern = "_habitat\\.rds$"), 2L)
  suppressMessages(taxahabitat_clear_cache(cache_dir))
  expect_length(list.files(cache_dir, pattern = "_habitat\\.rds$"), 0L)
})
