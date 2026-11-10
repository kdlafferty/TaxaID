test_that("search_literature: input validation -- empty taxon_scope", {
  expect_error(
    search_literature(taxon_scope = "", bbox = NULL, api_key = "fake"),
    "'taxon_scope' must be a non-empty character string"
  )
})

test_that("search_literature: input validation -- NA taxon_scope", {
  expect_error(
    search_literature(taxon_scope = NA_character_, bbox = NULL, api_key = "fake"),
    "'taxon_scope' must be a non-empty character string"
  )
})

test_that("search_literature: input validation -- bad bbox", {
  expect_error(
    search_literature("gobies", bbox = c(-120, -117), api_key = "fake"),
    "'bbox' must be a numeric vector of length 4"
  )
  expect_error(
    search_literature("gobies", bbox = c("a", "b", "c", "d"), api_key = "fake"),
    "'bbox' must be a numeric vector of length 4"
  )
})

test_that("search_literature: input validation -- missing API key", {
  # Only fires when api_key is empty string (env var not set)
  expect_error(
    search_literature("gobies", api_key = ""),
    "OpenAlex API key not found"
  )
})

test_that(".decode_openalex_abstract: handles NULL and empty input", {
  expect_identical(TaxaFetch:::.decode_openalex_abstract(NULL), NA_character_)
  expect_identical(TaxaFetch:::.decode_openalex_abstract(list()), NA_character_)
})

test_that(".decode_openalex_abstract: decodes simple inverted index correctly", {
  # Simulated inverted index: "hello world" at positions 0, 1
  inv <- list(hello = list(0L), world = list(1L))
  result <- TaxaFetch:::.decode_openalex_abstract(inv)
  expect_equal(result, "hello world")
})

test_that(".decode_openalex_abstract: handles numeric (non-list) positions", {
  # OpenAlex sometimes returns positions as plain integers not nested lists
  inv <- list(hello = 0L, world = 1L)
  result <- TaxaFetch:::.decode_openalex_abstract(inv)
  expect_equal(result, "hello world")
})

test_that("search_literature: geo_scope validation -- empty string rejected", {
  expect_error(
    search_literature("gobies", geo_scope = "", api_key = "fake"),
    "geo_scope.*non-empty character string"
  )
})

test_that("search_literature: geo_scope validation -- NA rejected", {
  expect_error(
    search_literature("gobies", geo_scope = NA_character_, api_key = "fake"),
    "geo_scope.*non-empty character string"
  )
})

test_that(".query_hash: returns consistent string for same inputs", {
  h1 <- TaxaFetch:::.query_hash("gobies", "California", "200", "2000", "TRUE")
  h2 <- TaxaFetch:::.query_hash("gobies", "California", "200", "2000", "TRUE")
  expect_identical(h1, h2)
})

test_that(".query_hash: returns different strings for different inputs", {
  h1 <- TaxaFetch:::.query_hash("gobies", "California")
  h2 <- TaxaFetch:::.query_hash("rockfish", "California")
  expect_false(identical(h1, h2))
})

test_that("download_literature_pdfs: input validation -- not a data frame", {
  expect_error(
    download_literature_pdfs("not_a_df", output_dir = tempdir()),
    "'catalog' must be a data frame"
  )
})

test_that("download_literature_pdfs: input validation -- missing columns", {
  bad_catalog <- data.frame(title = "Test", stringsAsFactors = FALSE)
  expect_error(
    download_literature_pdfs(bad_catalog, output_dir = tempdir()),
    "missing required columns"
  )
})

test_that("download_literature_pdfs: returns catalog with local_pdf_path column", {
  catalog <- data.frame(
    id = "W123",
    pdf_url = NA_character_,
    stringsAsFactors = FALSE
  )
  result <- download_literature_pdfs(
    catalog    = catalog,
    output_dir = file.path(tempdir(), "test_dl"),
    verbose    = FALSE
  )
  expect_true("local_pdf_path" %in% names(result))
  expect_equal(nrow(result), 1L)
  expect_true(is.na(result$local_pdf_path[1L]))
})

test_that("download_literature_pdfs: creates output_dir if absent", {
  new_dir <- file.path(tempdir(), paste0("dl_test_", sample(1e6, 1L)))
  expect_false(dir.exists(new_dir))
  catalog <- data.frame(
    id = "W1", pdf_url = NA_character_,
    stringsAsFactors = FALSE
  )
  download_literature_pdfs(catalog, output_dir = new_dir, verbose = FALSE)
  expect_true(dir.exists(new_dir))
  unlink(new_dir, recursive = TRUE)
})


# --- the OpenAlex key must not reach a failure message -----------------------
# OpenAlex takes its key as a URL query parameter, so a connection error raised
# by curl or httr2 can carry the whole request URL -- key included -- into its
# condition message, and .openalex_fetch_page() re-raises that message to the
# caller. The redaction is the only thing between the key and anything that
# captures those messages. Mutation-checked: with the gsub() removed from
# literature_search.R, the second expectation below fails, which is the one that
# matters.

test_that(".openalex_fetch_page redacts the key from a failure message", {
  key <- "oa-SECRET-KEY-DO-NOT-LEAK-9f3a"

  # Error the way httr2/curl does: the message carries the full request URL,
  # which is where the key is.
  local_mocked_bindings(
    req_perform = function(req, ...) {
      stop(sprintf(
        "Could not resolve host: api.openalex.org (url: https://api.openalex.org/works?api_key=%s&per-page=200)",
        key
      ), call. = FALSE)
    },
    .package = "httr2"
  )

  err <- tryCatch(
    TaxaFetch:::.openalex_fetch_page("https://api.openalex.org/works", key),
    error = function(e) e
  )
  expect_s3_class(err, "error")
  msg <- conditionMessage(err)

  # The function still reports the failure, and still says it was OpenAlex.
  expect_match(msg, "OpenAlex request failed")
  expect_match(msg, "Could not resolve host")
  # The key is gone and the placeholder is there in its place.
  expect_false(grepl(key, msg, fixed = TRUE))
  expect_match(msg, "***REDACTED***", fixed = TRUE)
})

test_that(".openalex_fetch_page does not break when there is no key to redact", {
  # The redaction is guarded, so an empty, NA or NULL key must not turn a
  # connection error into a different error from inside the handler.
  local_mocked_bindings(
    req_perform = function(req, ...) stop("Timeout was reached", call. = FALSE),
    .package = "httr2"
  )
  for (k in list("", NA_character_, NULL)) {
    err <- tryCatch(
      TaxaFetch:::.openalex_fetch_page("https://api.openalex.org/works", k),
      error = function(e) e
    )
    expect_s3_class(err, "error")
    expect_match(conditionMessage(err), "Timeout was reached")
  }
})

# ---- cache keys ignore a string's encoding mark ------------------------------

test_that("a cache key ignores the encoding mark of its strings", {
  s_utf8 <- "Pt. Mugu, California — estuarine and coastal"
  s_unk <- s_utf8
  Encoding(s_unk) <- "unknown"

  # Guards first. Without these the test could pass by comparing a string with
  # itself: the fixture has to differ in the MARK and in nothing else.
  expect_identical(nchar(s_utf8, "bytes"), nchar(s_unk, "bytes"))
  expect_false(identical(Encoding(s_utf8), Encoding(s_unk)))

  # The defect the helper exists for: rlang::hash() serializes the mark, so the
  # same text hashes two ways. If this expectation ever fails, rlang has fixed
  # it upstream and the helper is no longer earning its keep.
  expect_false(identical(rlang::hash(s_utf8), rlang::hash(s_unk)))

  # The fix.
  expect_identical(.cache_hash(s_utf8), .cache_hash(s_unk))

  # Nested, because most cache keys in this ecosystem are a list() of fields and
  # a top-level normalisation would miss the strings inside.
  expect_identical(
    .cache_hash(list(name = "cymatogaster aggregata", location = s_utf8)),
    .cache_hash(list(name = "cymatogaster aggregata", location = s_unk))
  )
})

test_that("the fix leaves an ASCII or already-UTF-8 key exactly where it was", {
  # Nothing cached before this helper existed may be orphaned by it.
  expect_identical(.cache_hash("abc"), rlang::hash("abc"))
  expect_identical(
    .cache_hash(list(a = 1L, b = "plain ascii")),
    rlang::hash(list(a = 1L, b = "plain ascii"))
  )

  # A real production key, rebuilt as a fixture rather than read from anyone's
  # cache directory. Under rlang 1.3.0 it hashes to
  # 013ed883133c9461d1c3671a4b2be57a, which is the filename it is stored under
  # in a live cache -- but that VALUE is asserted against rlang::hash() rather
  # than pinned as a literal, because rlang::hash() is documented as unstable
  # across rlang versions. Pinning it would turn an rlang upgrade into a red
  # suite for a reason that has nothing to do with this property.
  k <- list(
    name = "paralabrax maculatofasciatus",
    backbone_id = NA_integer_,
    location = "Pt. Mugu, California — estuarine and coastal"
  )
  expect_identical(.cache_hash(k), rlang::hash(k))
})

test_that("the literature query hash is the same under either encoding mark", {
  # Through the call site's own .query_hash(), so a tree without the helper
  # fails here because the hashes differ, not because a function is missing.
  q_utf8 <- "Mugu — estuarine fishes"
  q_unk <- q_utf8
  Encoding(q_unk) <- "unknown"
  expect_identical(.query_hash("openalex", q_utf8), .query_hash("openalex", q_unk))
})

test_that("an attributed or classed key is not moved by the fix", {
  k_df <- data.frame(name = "other", taxid = "1", stringsAsFactors = FALSE)
  expect_identical(.cache_hash(k_df), rlang::hash(k_df))
  k_cl <- structure(list(a = "ascii", b = 2L), class = "my_key", extra = "kept")
  expect_identical(.cache_hash(k_cl), rlang::hash(k_cl))
})
