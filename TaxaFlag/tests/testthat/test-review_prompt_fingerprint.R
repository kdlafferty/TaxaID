# The review cache key holds the INPUTS, not the prompt. A wording change that
# can move a verdict is therefore guarded only by the hand-bumped version token
# in review_assignments() (currently "v15"), and that token has been bumped
# fifteen times -- a guard that depends on someone remembering is not a guard.
#
# Why the key cannot simply carry the prompt: .build_review_prompt() assembles
# per BATCH, and several guidelines are included only when some line in the
# batch carries a note (the v8, v9 and v10 bumps are all about exactly that).
# Batch composition depends on which taxa were cache hits, so a digest of the
# rendered prompt would make each key depend on the batching and almost nothing
# would ever hit again.
#
# So the guard lives here instead: a fingerprint over the SOURCE of the
# prompt-building functions. Change their wording and this test fails, naming
# the token to bump. It costs no LLM call and invalidates no cache.
#
# Hashing uses .review_cache_hash(), which is base-R arithmetic over code
# points -- deliberately not rlang::hash(), whose value moves between rlang
# versions and would make this test fail on a dependency upgrade.

.rpf_fns <- c(
  ".build_review_prompt",
  ".p_scope_field_text",
  ".p_habitat_field_text",
  ".p_example_output",
  ".sites_prompt_block"
)

# Fill from the failure message of one run, then commit the value. The sentinel
# must FAIL rather than skip: an un-initialised fingerprint is an absent guard,
# and a test that waits quietly for a value is the failure mode this file exists
# to close.
.rpf_expected <- NA_character_

.rpf_fingerprint <- function() {
  ns <- asNamespace("TaxaFlag")
  src <- vapply(
    .rpf_fns,
    function(f) paste(deparse(get(f, envir = ns)), collapse = "\n"),
    character(1)
  )
  TaxaFlag:::.review_cache_hash(paste(src, collapse = "\n\n"))
}

test_that("the review prompt's source matches the fingerprint the key token was set for", {
  for (f in .rpf_fns) {
    expect_true(
      exists(f, envir = asNamespace("TaxaFlag"), inherits = FALSE),
      info = sprintf("%s has been renamed or removed; update .rpf_fns.", f)
    )
  }
  got <- .rpf_fingerprint()
  expect_false(
    is.na(.rpf_expected),
    info = sprintf(
      "The review-prompt fingerprint is un-initialised. Set .rpf_expected to \"%s\".",
      got
    )
  )
  expect_identical(
    got, .rpf_expected,
    info = paste0(
      "The review prompt's wording changed. A cached verdict given under the ",
      "old wording would be served as a hit, because the cache key holds the ",
      "inputs and not the prompt. BUMP the version token in ",
      "review_assignments() (\"v15\" -> \"v16\"), record what changed in the ",
      "comment above shared_parts, and set .rpf_expected to \"", got, "\". ",
      "If the sites block changed, bump \"geo_sites_v5\" too."
    )
  )
})

# The v15 split, asserted on meaning rather than on the digest: scope is
# taxonomic, habitat is where the taxon lives. The digest above would catch any
# edit to these functions, but it cannot say WHICH property broke, and this is
# the one the maintainer's review of real calls found violated.
test_that("p_scope asks about the kind of organism only, and sends habitat to p_habitat", {
  scope <- TaxaFlag:::.p_scope_field_text("shallow-water marine fishes")

  expect_true(grepl("KIND OF ORGANISM", scope, fixed = TRUE))
  expect_true(grepl("Judge the taxonomy only", scope, fixed = TRUE))
  # The habitat words appear ONLY to be excluded, and the exclusion names the
  # field that carries them.
  expect_true(grepl("ignore that part here", scope, fixed = TRUE))
  expect_true(grepl("scored in p_habitat", scope, fixed = TRUE))
  # The v14 wording, which made scope a second habitat flag.
  expect_false(grepl("and its depth or habitat zone", scope, fixed = TRUE))
  expect_false(grepl("realm or depth the target group excludes", scope, fixed = TRUE))
  # Geography was never scope and still is not.
  expect_true(grepl("geography, not scope", scope, fixed = TRUE))

  # No target group: the field is null and asks nothing.
  expect_true(grepl("null (no target group specified)", 
                    TaxaFlag:::.p_scope_field_text(NULL), fixed = TRUE))

  # p_habitat keeps the habitat question, so the split loses nothing.
  hab <- TaxaFlag:::.p_habitat_field_text("rocky intertidal")
  expect_true(grepl("LIVING CONDITIONS", hab, fixed = TRUE))
  expect_true(grepl("any life stage", hab, fixed = TRUE))
})
