# Tests for R/validate.R -- the snippet validator (P2). Offline: reads only
# the installed TaxaID packages and the package's own snippet files; no
# network, no LLM calls. See ecosystem_docs/SPEC_taxawizard_derived_context_
# 2026_09_18.md, "P2 Snippet validator + Tier-B fallback".

test_that(".validate_snippets() returns the documented shape", {
  result <- TaxaWizard:::.validate_snippets()
  expect_true(is.data.frame(result))
  expect_true(all(c("edge_id", "function", "problem", "detail") %in% names(result)))
})

test_that(".validate_snippets() returns zero rows for an empty graph", {
  result <- TaxaWizard:::.validate_snippets(graph = list(edges = list()))
  expect_equal(nrow(result), 0L)
})

# ---------------------------------------------------------------------------
# The in-package drift test: this is what P2's spec calls "the in-package
# drift test". If this ever fails on a real snippet, the fix belongs in the
# SNIPPET (a named-argument fix against the real installed formals), never
# in loosening this assertion.
# ---------------------------------------------------------------------------
test_that("every real snippet is clean: zero not_exported/stale_argument/parse_error", {
  pkgs <- TaxaWizard:::TAXAID_PACKAGES
  installed <- pkgs[vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  skip_if(length(installed) == 0L, "no TaxaID packages installed")

  result <- TaxaWizard:::.validate_snippets(registry = workflow_registry(packages = installed))
  failing <- result[result$problem %in% c("not_exported", "stale_argument", "parse_error"), ]

  expect_equal(
    nrow(failing), 0L,
    info = paste(utils::capture.output(print(failing)), collapse = "\n")
  )
})

# ---------------------------------------------------------------------------
# Injected-graph tests: a bogus edge is constructed in-memory pointing at a
# real, temp-file-backed snippet so these never touch a real snippet under
# inst/graph/snippets/.
# ---------------------------------------------------------------------------

.tw_bogus_snippet_edge <- function(code, edge_id = "bogus_edge", packages = "TaxaAssign",
                                   functions = character(0)) {
  snippet_path <- tempfile(fileext = ".R")
  writeLines(code, snippet_path)
  list(
    id = edge_id, from = list("match_df"), to = "consensus",
    label = "Bogus test edge", description = "A deliberately broken edge for testing.",
    packages = as.list(packages), functions = as.list(functions),
    snippet = snippet_path, time_estimate = "unknown", requires = list()
  )
}

test_that(".validate_snippets() flags a not_exported Pkg::fn call", {
  edge <- .tw_bogus_snippet_edge(
    'x <- TaxaAssign::this_function_does_not_exist(y = 1)\nx',
    packages = "TaxaAssign", functions = "this_function_does_not_exist"
  )
  skip_if_not(requireNamespace("TaxaAssign", quietly = TRUE))
  graph <- list(edges = list(edge))
  result <- TaxaWizard:::.validate_snippets(graph = graph)

  expect_equal(nrow(result), 1L)
  expect_equal(result$problem, "not_exported")
  expect_equal(result$edge_id, "bogus_edge")
  expect_true(grepl("this_function_does_not_exist", result$detail))
})

test_that(".validate_snippets() flags a stale named argument", {
  skip_if_not(requireNamespace("TaxaAssign", quietly = TRUE))
  reg <- workflow_registry(packages = "TaxaAssign")
  skip_if(is.null(reg$TaxaAssign), "TaxaAssign not in registry")

  edge <- .tw_bogus_snippet_edge(
    'x <- TaxaAssign::score_consensus(match_df = {{match_df}}, this_arg_does_not_exist = 1)\nx',
    packages = "TaxaAssign", functions = "score_consensus"
  )
  graph <- list(edges = list(edge))
  result <- TaxaWizard:::.validate_snippets(graph = graph, registry = list(TaxaAssign = reg$TaxaAssign))

  expect_equal(nrow(result), 1L)
  expect_equal(result$problem, "stale_argument")
  expect_true(grepl("this_arg_does_not_exist", result$detail))
})

test_that(".validate_snippets() reports parse_error on unparseable code", {
  edge <- .tw_bogus_snippet_edge("x <- (1 + \n")
  graph <- list(edges = list(edge))
  result <- TaxaWizard:::.validate_snippets(graph = graph, registry = list())

  expect_equal(nrow(result), 1L)
  expect_equal(result$problem, "parse_error")
})

test_that(".validate_snippets() reports unknown_bare_call for an unresolvable bare name, without failing the drift test", {
  edge <- .tw_bogus_snippet_edge("x <- this_bare_name_resolves_nowhere(1)\nx")
  graph <- list(edges = list(edge))
  result <- TaxaWizard:::.validate_snippets(graph = graph, registry = list())

  expect_equal(nrow(result), 1L)
  expect_equal(result$problem, "unknown_bare_call")
  # unknown_bare_call is a warn-severity report, not one of the three
  # problems the drift test (above) asserts zero of.
  expect_false(result$problem[1] %in% c("not_exported", "stale_argument", "parse_error"))
})

test_that(".validate_snippets() does not flag a snippet's own local helper function", {
  edge <- .tw_bogus_snippet_edge(paste(
    ".my_helper <- function(x) x + 1",
    "result <- .my_helper(41)",
    "result",
    sep = "\n"
  ))
  graph <- list(edges = list(edge))
  result <- TaxaWizard:::.validate_snippets(graph = graph, registry = list())

  expect_equal(nrow(result), 0L)
})

test_that(".validate_snippets() ignores stale-argument checks for functions with `...` in formals", {
  skip_if_not(requireNamespace("TaxaTools", quietly = TRUE))
  reg <- workflow_registry(packages = "TaxaTools")
  dotdotdot_fn <- Find(function(f) "..." %in% vapply(f$params, `[[`, "", "name"), reg$TaxaTools$functions)
  skip_if(is.null(dotdotdot_fn), "no TaxaTools export with ... in formals to test against")

  edge <- .tw_bogus_snippet_edge(
    sprintf(
      'x <- TaxaTools::%s(definitely_not_a_real_param_xyz = 1)\nx',
      dotdotdot_fn$name
    ),
    packages = "TaxaTools", functions = dotdotdot_fn$name
  )
  graph <- list(edges = list(edge))
  result <- TaxaWizard:::.validate_snippets(graph = graph, registry = list(TaxaTools = reg$TaxaTools))

  expect_equal(nrow(result), 0L)
})

test_that(".validate_snippets() placeholder substitution lets {{tokens}} parse cleanly", {
  edge <- .tw_bogus_snippet_edge('x <- data.frame(a = {{some_value}})\nx')
  graph <- list(edges = list(edge))
  result <- TaxaWizard:::.validate_snippets(graph = graph, registry = list())

  expect_equal(nrow(result), 0L)
})

test_that(".validate_snippets() edge_ids= restricts validation to the requested edges", {
  skip_if_not(requireNamespace("TaxaAssign", quietly = TRUE))
  bad_edge <- .tw_bogus_snippet_edge(
    "x <- TaxaAssign::this_function_does_not_exist(y = 1)\nx",
    edge_id = "bad_edge", packages = "TaxaAssign", functions = "this_function_does_not_exist"
  )
  good_edge <- .tw_bogus_snippet_edge("x <- 1\nx", edge_id = "good_edge")
  graph <- list(edges = list(bad_edge, good_edge))
  reg <- workflow_registry(packages = "TaxaAssign")

  result_all <- TaxaWizard:::.validate_snippets(graph = graph, registry = reg)
  expect_equal(sort(unique(result_all$edge_id)), "bad_edge")

  result_restricted <- TaxaWizard:::.validate_snippets(
    graph = graph, registry = reg, edge_ids = "good_edge"
  )
  expect_equal(nrow(result_restricted), 0L)
})
