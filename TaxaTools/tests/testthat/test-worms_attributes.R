# ==============================================================================
# fetch_worms_attributes()
# ==============================================================================
# The network-free tests exercise the logic that makes this function safe to
# build a filter on; the live tests pin the real WoRMS verdicts quoted in the
# function's own documentation, so a WoRMS revision that would change the
# filter's behaviour shows up as a test failure rather than as a quiet shift in
# a species list.

# ---- flag decoding -----------------------------------------------------------

test_that(".worms_flag distinguishes 'not assessed' from 'absent'", {
  expect_identical(TaxaTools:::.worms_flag(1), TRUE)
  expect_identical(TaxaTools:::.worms_flag("1"), TRUE)
  expect_identical(TaxaTools:::.worms_flag(0), FALSE)
  # WoRMS sends null for a realm it has not assessed. That is NOT the same
  # claim as 0, and collapsing the two would silently manufacture evidence.
  expect_identical(TaxaTools:::.worms_flag(NULL), NA)
  expect_identical(TaxaTools:::.worms_flag(list()), NA)
})


# ---- the scope rule ----------------------------------------------------------

test_that("marine_scope keeps a marine+terrestrial shorebird", {
  # The measured failure this function exists for: the LLM habitat scheme must
  # pick ONE category and calls the black oystercatcher Terrestrial.
  row <- TaxaTools:::.worms_row_from_records(
    "Haematopus bachmani", list(worms_rec(marine = 1, terrestrial = 1)), FALSE
  )
  expect_true(row$is_marine)
  expect_true(row$is_terrestrial)
  expect_true(row$marine_scope)
})

test_that("marine_scope keeps a diadromous fish with no special case", {
  row <- TaxaTools:::.worms_row_from_records(
    "Oncorhynchus mykiss",
    list(worms_rec(marine = 1, brackish = 1, freshwater = 1, terrestrial = 0)),
    FALSE
  )
  expect_true(row$marine_scope)
})

test_that("brackish alone is in scope and freshwater/terrestrial alone is not", {
  expect_true(TaxaTools:::.worms_row_from_records(
    "X", list(worms_rec(marine = 0, brackish = 1, freshwater = 1)), FALSE
  )$marine_scope)
  expect_false(TaxaTools:::.worms_row_from_records(
    "Cornu aspersum", list(worms_rec(marine = 0, terrestrial = 1)), FALSE
  )$marine_scope)
})

test_that("marine_scope is never NA, whatever the flags are", {
  # An NA in the keep-vector neither keeps nor drops -- it errors or silently
  # subsets whatever consumes it. Every combination must resolve to TRUE/FALSE.
  combos <- expand.grid(
    m = list(1, 0, NULL), b = list(1, 0, NULL),
    f = list(1, 0, NULL), t = list(1, 0, NULL)
  )
  scopes <- vapply(seq_len(nrow(combos)), function(i) {
    TaxaTools:::.worms_row_from_records("X", list(worms_rec(
      marine = combos$m[[i]], brackish = combos$b[[i]],
      freshwater = combos$f[[i]], terrestrial = combos$t[[i]]
    )), FALSE)$marine_scope
  }, logical(1))
  expect_false(anyNA(scopes))
  expect_length(scopes, 81L)
})

test_that("a record with no flags set at all is reported, not guessed at", {
  row <- TaxaTools:::.worms_row_from_records(
    "X", list(worms_rec(marine = NULL, brackish = NULL,
                        freshwater = NULL, terrestrial = NULL)), FALSE
  )
  expect_true(row$in_worms)
  expect_true(row$habitat_unassessed)
  expect_false(row$marine_scope) # dropped for want of evidence -- and counted
})


# ---- homonyms ----------------------------------------------------------------

test_that("homonyms are ORed, not resolved, and are flagged", {
  # "Ficus" is both a marine gastropod genus and the fig genus. Picking one
  # would be a coin flip whose wrong face deletes a real detection.
  row <- TaxaTools:::.worms_row_from_records("Ficus", list(
    worms_rec(marine = 1, aphia_id = 205605L, kingdom = "Animalia"),
    worms_rec(marine = 0, aphia_id = 447837L, kingdom = "Plantae")
  ), FALSE)
  expect_true(row$marine_scope)
  expect_true(row$worms_ambiguous)
  expect_true(row$habitat_conflict)
  expect_identical(row$n_matches, 2L)
})

test_that("agreeing homonyms are ambiguous but not in conflict", {
  row <- TaxaTools:::.worms_row_from_records("X", list(
    worms_rec(marine = 1, aphia_id = 1L), worms_rec(marine = 1, aphia_id = 2L)
  ), FALSE)
  expect_true(row$worms_ambiguous)
  expect_false(row$habitat_conflict)
})

test_that("the representative record is the first accepted match", {
  row <- TaxaTools:::.worms_row_from_records("X", list(
    worms_rec(aphia_id = 7L, status = "unaccepted"),
    worms_rec(aphia_id = 8L, status = "accepted")
  ), FALSE)
  expect_identical(row$aphia_id, 8L)
  # ... and the first record when none is accepted, rather than nothing.
  row2 <- TaxaTools:::.worms_row_from_records("X", list(
    worms_rec(aphia_id = 7L, status = "unaccepted")
  ), FALSE)
  expect_identical(row2$aphia_id, 7L)
  expect_identical(row2$taxonomic_status, "unaccepted")
})


# ---- fuzzy matching ----------------------------------------------------------

test_that("a fuzzy match is not a match unless asked for, and is reported", {
  recs <- list(worms_rec(marine = 1, match_type = "phonetic"))
  strict <- TaxaTools:::.worms_row_from_records("Mytilus edulus", recs, FALSE)
  expect_false(strict$in_worms)
  expect_true(strict$fuzzy_rejected)
  expect_identical(strict$match_type, "phonetic") # recorded, not hidden
  expect_false(strict$marine_scope)

  loose <- TaxaTools:::.worms_row_from_records("Mytilus edulus", recs, TRUE)
  expect_true(loose$in_worms)
  expect_false(loose$fuzzy_rejected)
  expect_true(loose$marine_scope)
})

test_that("an exact match is kept when it arrives alongside fuzzy ones", {
  row <- TaxaTools:::.worms_row_from_records("X", list(
    worms_rec(marine = 0, aphia_id = 1L, match_type = "near_1"),
    worms_rec(marine = 1, aphia_id = 2L, match_type = "exact")
  ), FALSE)
  expect_identical(row$n_matches, 1L)
  expect_identical(row$aphia_id, 2L)
  expect_true(row$marine_scope)
})


# ---- input handling ----------------------------------------------------------

test_that("degenerate input returns the full schema, not an empty object", {
  e <- fetch_worms_attributes(character(0), verbose = FALSE)
  expect_s3_class(e, "tbl_df")
  expect_identical(nrow(e), 0L)
  expect_true(all(c(
    "taxon_name", "in_worms", "aphia_id", "marine_scope", "is_marine",
    "is_brackish", "is_freshwater", "is_terrestrial", "ncbi_id", "wrims"
  ) %in% names(e)))
  # The residue attributes are always present, so a caller that reads them
  # unconditionally does not need a special case for an empty run.
  expect_identical(attr(e, "n_not_in_worms"), 0L)
  expect_identical(attr(e, "n_request_failed"), 0L)

  expect_identical(nrow(fetch_worms_attributes(c(NA_character_, "", "  "),
    verbose = FALSE
  )), 0L)
})

test_that("arguments are validated", {
  expect_error(fetch_worms_attributes(1:3), "character vector")
  expect_error(fetch_worms_attributes("Sebastes", extras = "depth"), "Unsupported")
  expect_error(fetch_worms_attributes("Sebastes", accept_fuzzy = NA), "TRUE or FALSE")
  expect_error(fetch_worms_attributes("Sebastes", cache_dir = c("a", "b")), "cache_dir")
  expect_error(fetch_worms_attributes("Sebastes", batch_size = 0), "batch_size")
  expect_error(fetch_worms_attributes("Sebastes", delay = -1), "delay")
  expect_error(fetch_worms_attributes("Sebastes", verbose = "yes"), "verbose")
})


# ---- batching ----------------------------------------------------------------

test_that("requests are chunked on name count and on URL length", {
  urls <- character(0)
  fake <- function(url, timeout = 60) {
    urls <<- c(urls, url)
    list(ok = FALSE, status = NA_integer_, body = NULL)
  }

  with_fake_worms(fake, {
    suppressWarnings(fetch_worms_attributes(paste0("Gx", 1:120),
      extras = character(0), batch_size = 50, delay = 0, verbose = FALSE
    ))
  })
  expect_length(urls, 3L)

  # Long names must chunk on the URL budget even though 40 < batch_size.
  urls <- character(0)
  with_fake_worms(fake, {
    suppressWarnings(fetch_worms_attributes(
      paste0(strrep("Abcdefghij ", 30), 1:40),
      extras = character(0), batch_size = 50, delay = 0, verbose = FALSE
    ))
  })
  expect_gt(length(urls), 1L)
  expect_true(all(nchar(urls) < 8000L))
})


# ---- failure is not absence --------------------------------------------------

test_that("a failed request is neither an absence nor cached", {
  cache <- withr::local_tempdir()
  fake <- function(url, timeout = 60) list(ok = FALSE, status = 500L, body = NULL)

  # `<<-` would skip this frame, so hold the result in an explicit environment.
  out <- new.env()
  with_fake_worms(fake, {
    expect_warning(
      out$res <- fetch_worms_attributes(c("Sebastes", "Mytilus"),
        cache_dir = cache, extras = character(0), delay = 0, verbose = FALSE
      ),
      "NOT absences"
    )
  })
  res <- out$res

  expect_identical(attr(res, "n_request_failed"), 2L)
  # The dangerous confusion: a 500 must never be reported as "not in WoRMS",
  # because that reads as a real verdict to drop the taxon.
  expect_identical(attr(res, "n_not_in_worms"), 0L)
  expect_length(list.files(cache), 0L)
})

test_that("a length-mismatched response is treated as a failure, not misaligned", {
  # Positional alignment is the endpoint's only contract between names and
  # answers. Silently zipping a short response would attach one taxon's
  # habitat flags to another taxon's name.
  fake <- function(url, timeout = 60) {
    list(ok = TRUE, status = 200L, body = list(list(worms_rec(marine = 1))))
  }
  res <- with_fake_worms(fake, {
    suppressWarnings(fetch_worms_attributes(c("A", "B", "C"),
      extras = character(0), delay = 0, verbose = FALSE
    ))
  })
  expect_identical(attr(res, "n_request_failed"), 3L)
  expect_false(any(res$in_worms))
})

test_that("an empty 204 body is a genuine 'not found', and is cached", {
  cache <- withr::local_tempdir()
  fake <- function(url, timeout = 60) list(ok = TRUE, status = 204L, body = NULL)
  res <- with_fake_worms(fake, {
    fetch_worms_attributes(c("Cervus elaphus", "Zea mays"),
      cache_dir = cache, extras = character(0), delay = 0, verbose = FALSE
    )
  })
  expect_identical(attr(res, "n_not_in_worms"), 2L)
  expect_identical(attr(res, "n_request_failed"), 0L)
  expect_length(list.files(cache), 2L)
})


# ---- cache -------------------------------------------------------------------

test_that("a warm run makes no requests and returns the same rows", {
  cache <- withr::local_tempdir()
  calls <- 0L
  fake <- function(url, timeout = 60) {
    calls <<- calls + 1L
    list(ok = TRUE, status = 200L, body = list(list(worms_rec(marine = 1))))
  }

  cold <- with_fake_worms(fake, {
    fetch_worms_attributes("Sebastes",
      cache_dir = cache,
      extras = character(0), delay = 0, verbose = FALSE
    )
  })
  n_cold <- calls

  warm <- with_fake_worms(fake, {
    fetch_worms_attributes("Sebastes",
      cache_dir = cache,
      extras = character(0), delay = 0, verbose = FALSE
    )
  })
  expect_identical(calls, n_cold) # no further requests
  expect_equal(as.data.frame(warm), as.data.frame(cold), ignore_attr = TRUE)
  expect_identical(attr(warm, "worms_query")$n_from_cache, 1L)
})

test_that("widening extras reuses the cached flags and fetches only the extra", {
  # The lesson this encodes: a row whose ncbi_id is NA because it was never
  # ASKED FOR must not be cached as though WoRMS had no answer -- that is the
  # cached-non-answer failure that cost 20 PtCon 12S observations in the LLM
  # review. The cache records WHICH extras were answered.
  cache <- withr::local_tempdir()
  seen <- character(0)
  fake <- function(url, timeout = 60) {
    seen <<- c(seen, url)
    if (grepl("AphiaExternalIDByAphiaID", url)) {
      return(list(ok = TRUE, status = 200L, body = list("8022")))
    }
    list(ok = TRUE, status = 200L, body = list(list(worms_rec(marine = 1, aphia_id = 127185L))))
  }

  with_fake_worms(fake, {
    fetch_worms_attributes("Oncorhynchus mykiss",
      cache_dir = cache,
      extras = character(0), delay = 0, verbose = FALSE
    )
  })
  expect_length(seen, 1L)

  seen <- character(0)
  widened <- with_fake_worms(fake, {
    fetch_worms_attributes("Oncorhynchus mykiss",
      cache_dir = cache,
      extras = "ncbi_id", delay = 0, verbose = FALSE
    )
  })
  # Exactly one request: the extra. The name match was served from cache.
  expect_length(seen, 1L)
  expect_match(seen, "AphiaExternalIDByAphiaID")
  expect_identical(widened$ncbi_id, "8022")

  seen <- character(0)
  again <- with_fake_worms(fake, {
    fetch_worms_attributes("Oncorhynchus mykiss",
      cache_dir = cache,
      extras = "ncbi_id", delay = 0, verbose = FALSE
    )
  })
  expect_length(seen, 0L)
  expect_identical(again$ncbi_id, "8022")
})

test_that("a failed extra is not recorded as resolved, so it is re-asked", {
  cache <- withr::local_tempdir()
  extra_ok <- FALSE
  fake <- function(url, timeout = 60) {
    if (grepl("AphiaExternalIDByAphiaID", url)) {
      if (!extra_ok) return(list(ok = FALSE, status = 500L, body = NULL))
      return(list(ok = TRUE, status = 200L, body = list("8022")))
    }
    list(ok = TRUE, status = 200L, body = list(list(worms_rec(marine = 1, aphia_id = 127185L))))
  }

  first <- with_fake_worms(fake, {
    suppressWarnings(fetch_worms_attributes("Oncorhynchus mykiss",
      cache_dir = cache, extras = "ncbi_id", delay = 0, verbose = FALSE
    ))
  })
  expect_true(is.na(first$ncbi_id))

  extra_ok <- TRUE
  second <- with_fake_worms(fake, {
    fetch_worms_attributes("Oncorhynchus mykiss",
      cache_dir = cache,
      extras = "ncbi_id", delay = 0, verbose = FALSE
    )
  })
  expect_identical(second$ncbi_id, "8022") # the cache healed itself
})

test_that("accept_fuzzy is part of the cache key", {
  cache <- withr::local_tempdir()
  fake <- function(url, timeout = 60) {
    list(ok = TRUE, status = 200L, body = list(list(
      worms_rec(marine = 1, match_type = "phonetic", valid_name = "Mytilus edulis")
    )))
  }
  strict <- with_fake_worms(fake, {
    fetch_worms_attributes("Mytilus edulus",
      cache_dir = cache,
      extras = character(0), delay = 0, verbose = FALSE
    )
  })
  loose <- with_fake_worms(fake, {
    fetch_worms_attributes("Mytilus edulus",
      cache_dir = cache, accept_fuzzy = TRUE,
      extras = character(0), delay = 0, verbose = FALSE
    )
  })
  expect_false(strict$in_worms)
  expect_true(loose$in_worms)
  expect_length(list.files(cache), 2L)
})

test_that("a warm run does not rewrite cache files", {
  # Rewriting an unchanged file resets its mtime, which is the axis
  # taxatools_clear_cache(older_than_days=) prunes on -- so re-running a
  # workflow would silently make an ageing cache look brand new.
  cache <- withr::local_tempdir()
  fake <- function(url, timeout = 60) {
    list(ok = TRUE, status = 200L, body = list(list(worms_rec(marine = 1))))
  }
  with_fake_worms(fake, {
    fetch_worms_attributes("Sebastes",
      cache_dir = cache,
      extras = character(0), delay = 0, verbose = FALSE
    )
  })
  before <- file.mtime(list.files(cache, full.names = TRUE))
  Sys.sleep(1.1)
  with_fake_worms(fake, {
    fetch_worms_attributes("Sebastes",
      cache_dir = cache,
      extras = character(0), delay = 0, verbose = FALSE
    )
  })
  expect_identical(file.mtime(list.files(cache, full.names = TRUE)), before)
})

test_that("a corrupt or foreign cache file is a miss, never another taxon's answer", {
  cache <- withr::local_tempdir()
  key <- TaxaTools:::.worms_cache_key("Sebastes", FALSE)
  path <- TaxaTools:::.worms_cache_path(cache, key)

  writeLines("not an rds", path)
  expect_null(TaxaTools:::.read_worms_cache(cache, key))

  # Right file name, wrong key inside: the stored key is verified on read, so
  # a hash collision costs one re-asked name and can never cross taxa.
  saveRDS(list(
    key = TaxaTools:::.worms_cache_key("Mytilus", FALSE),
    row = TaxaTools:::.worms_empty_row("Mytilus"), resolved = character(0)
  ), path)
  expect_null(TaxaTools:::.read_worms_cache(cache, key))
})

test_that("taxatools_clear_cache() sees WoRMS cache files", {
  cache <- withr::local_tempdir()
  with_fake_worms(fake_match(), {
    fetch_worms_attributes(c("Sebastes", "Mytilus"),
      cache_dir = cache,
      extras = character(0), delay = 0, verbose = FALSE
    )
  })
  inv <- suppressMessages(taxatools_clear_cache(cache, dry_run = TRUE))
  expect_identical(nrow(inv), 2L)
  expect_length(list.files(cache), 2L) # dry run deleted nothing
})


# ---- derived columns ---------------------------------------------------------

test_that("wrims is TRUE only when a distribution record is Alien", {
  mk <- function(...) {
    list(ok = TRUE, status = 200L, body = lapply(c(...), function(x) list(establishmentMeans = x)))
  }
  fake_for <- function(dist) {
    function(url, timeout = 60) {
      if (grepl("AphiaDistributionsByAphiaID", url)) return(dist)
      list(ok = TRUE, status = 200L, body = list(list(worms_rec(marine = 1, aphia_id = 107381L))))
    }
  }
  get_wrims <- function(dist) {
    with_fake_worms(fake_for(dist), {
      fetch_worms_attributes("X", extras = "wrims", delay = 0, verbose = FALSE)$wrims
    })
  }
  expect_true(get_wrims(mk("Native", "Alien")))
  expect_false(get_wrims(mk("Native", "Native - Non-endemic")))
  # No distribution records at all is a genuine "not introduced", not unknown.
  expect_false(get_wrims(list(ok = TRUE, status = 204L, body = NULL)))
})


# ---- live WoRMS --------------------------------------------------------------
# These pin the real verdicts the function's documentation quotes. If WoRMS
# revises one, this fails loudly rather than shifting a species list quietly.

test_that("live: WoRMS keeps shorebirds the LLM habitat scheme calls Terrestrial", {
  skip_if_worms_down()
  res <- fetch_worms_attributes(
    c("Haematopus bachmani", "Calidris alba", "Arenaria melanocephala", "Numenius phaeopus"),
    extras = character(0), verbose = FALSE
  )
  expect_true(all(res$in_worms))
  expect_true(all(res$is_marine))
  expect_true(all(res$is_terrestrial))
  expect_true(all(res$marine_scope))
})

test_that("live: diadromous fish are kept by the marine-OR-brackish rule", {
  skip_if_worms_down()
  res <- fetch_worms_attributes(c("Oncorhynchus mykiss", "Alosa sapidissima"),
    extras = character(0), verbose = FALSE
  )
  expect_true(all(res$is_marine))
  expect_true(all(res$is_brackish))
  expect_true(all(res$is_freshwater))
  expect_false(any(res$is_terrestrial))
  expect_true(all(res$marine_scope))
})

test_that("live: non-marine taxa are cut, whether by flags or by absence", {
  skip_if_worms_down()
  res <- fetch_worms_attributes(
    c("Homo sapiens", "Sus scrofa", "Gallus gallus", "Cornu aspersum",
      "Lumbricus terrestris", "Cervus elaphus"),
    extras = character(0), verbose = FALSE
  )
  expect_false(any(res$marine_scope))
  # Absence is NOT the mechanism for most of these any more: verified
  # 2026-09-15, Homo sapiens / Sus scrofa / Gallus gallus ARE in the register
  # and are cut on their flags. Cervus elaphus is genuinely absent.
  expect_true(res$in_worms[res$taxon_name == "Homo sapiens"])
  expect_false(res$in_worms[res$taxon_name == "Cervus elaphus"])
  # The terrestrial snail and the earthworm are the gap a TAXONOMIC scope
  # filter cannot close -- they are Gastropoda and Clitellata wherever they live.
  expect_true(res$in_worms[res$taxon_name == "Cornu aspersum"])
  expect_false(res$marine_scope[res$taxon_name == "Cornu aspersum"])
})

test_that("live: higher ranks resolve, including Teleostei", {
  skip_if_worms_down()
  res <- fetch_worms_attributes(c("Sebastes", "Teleostei"),
    extras = character(0), verbose = FALSE
  )
  expect_true(all(res$in_worms))
  expect_true(all(res$marine_scope))
  expect_identical(
    res$worms_rank[res$taxon_name == "Teleostei"], "Class"
  )
  # GBIF's backbone has no occurrence-bearing node for ray-finned fishes;
  # WoRMS does, which is part of why this lookup is worth having.
  expect_identical(res$aphia_id[res$taxon_name == "Teleostei"], 293496L)
})

test_that("live: a synonym resolves to its accepted name", {
  skip_if_worms_down()
  res <- fetch_worms_attributes("Urolophus halleri",
    extras = character(0), verbose = FALSE
  )
  expect_identical(res$taxonomic_status, "unaccepted")
  expect_identical(res$accepted_name, "Urobatis halleri")
  expect_true(res$marine_scope)
})

test_that("live: ncbi_id returns the curated crosswalk", {
  skip_if_worms_down()
  res <- fetch_worms_attributes(c("Oncorhynchus mykiss", "Homo sapiens"),
    extras = "ncbi_id", verbose = FALSE
  )
  expect_identical(res$ncbi_id[res$taxon_name == "Oncorhynchus mykiss"], "8022")
  expect_identical(res$ncbi_id[res$taxon_name == "Homo sapiens"], "9606")
})
