# tests/testthat/test-build_context_site_guard.R
#
# `taxon_names` is build_context()'s FIRST argument, so a site description
# given positionally becomes a taxon and `geographic_hint` stays NA. The guard
# warns, and warns before any LLM call is made.
#
# False positives on genus- and family-rank calls are this guard's failure
# mode, so every name form below is asserted SILENT explicitly -- a guard that
# warned on "Mytilus sp." would be worse than no guard at all.

skip_if_not_installed("TaxaTools")

# Returns TRUE if the guard warned, without letting the warning escape, so a
# failure names the form that misbehaved instead of just the loop.
guard_warns <- function(x, geographic_hint = NULL) {
  warned <- FALSE
  withCallingHandlers(
    .warn_if_site_passed_as_taxa(x, geographic_hint),
    warning = function(cnd) {
      warned <<- TRUE
      invokeRestart("muffleWarning")
    }
  )
  warned
}

name_forms <- c(
  "Salmo salar",
  "Salmo",
  "Salmonidae",
  "Hydra",
  "Hydrozoa",
  "Eucyclogobius newberryi",
  "Mytilus sp.",
  "Mytilus spp.",
  "Salmo cf. salar",
  "Oncorhynchus mykiss x clarkii",
  "Carcharodon carcharias (great white)"
)

site_forms <- c(
  "Lake Michigan",
  "Burns/Indiana Harbor, Lake Michigan, MiFish-U 12S",
  "Burns Harbor",
  "MiFish-U 12S",
  "Mugu Lagoon",
  "Southern California",
  "Point Conception, CA",
  "uncultured bacterium",
  "ASV_1"
)

test_that("a single taxon name stays silent at every rank", {
  expect_equal(
    vapply(name_forms, guard_warns, logical(1)),
    stats::setNames(rep(FALSE, length(name_forms)), name_forms)
  )
})

test_that("a single site description warns", {
  expect_equal(
    vapply(site_forms, guard_warns, logical(1)),
    stats::setNames(rep(TRUE, length(site_forms)), site_forms)
  )
})

test_that("the warning says which argument was meant", {
  expect_warning(
    .warn_if_site_passed_as_taxa("Lake Michigan", NULL),
    "does not read like a taxon name"
  )
})

test_that("a supplied geographic_hint silences the guard", {
  # With the hint given, the positional mistake cannot have happened, so even
  # the GL string is a deliberate (if odd) taxon query.
  expect_false(guard_warns(
    "Burns/Indiana Harbor, Lake Michigan, MiFish-U 12S",
    geographic_hint = "Lake Michigan"
  ))
})

test_that("a vector of names is never judged", {
  # The guard targets the one-string positional mistake only; a real taxon list
  # is not inspected, whatever it contains.
  expect_false(guard_warns(c("Lake Michigan", "Lake Huron")))
  expect_false(guard_warns(c("Salmo salar", "Salmo trutta")))
  expect_false(guard_warns(character(0)))
})

test_that("build_context() warns before the LLM request is made", {
  skip_if_not_installed("TaxaHabitat")
  # never_llm stops on the first request, so the warning can only be seen at
  # all if it was raised before that request. The guard warns and does NOT
  # stop, so the request still follows -- which is why the call is wrapped in
  # try(): what is under test is the warning and its ordering, not the call.
  never_llm <- function(prompt) stop("llm_fn reached")
  expect_warning(
    suppressMessages(try(build_context("Lake Michigan", llm_fn = never_llm),
      silent = TRUE
    )),
    "does not read like a taxon name"
  )
})

test_that("a place name shaped like a binomial is a KNOWN miss", {
  # Not a wish -- a record. The test is one of shape, and these read exactly
  # like "Genus epithet", so no shape rule can separate them from a real name.
  # Asserted so that nobody widens the regex to catch them: that would warn on
  # genus-rank calls, which are common, to catch site strings in this form,
  # which are not. If the guard ever does catch these, this test fails and the
  # trade has to be argued again.
  known_misses <- c(
    "Gulf of Mexico", "Sea of Cortez", "Strait of Georgia",
    "Mugu lagoon", "Burns harbor", "Los angeles"
  )
  expect_equal(
    vapply(known_misses, guard_warns, logical(1)),
    stats::setNames(rep(FALSE, length(known_misses)), known_misses)
  )
})
