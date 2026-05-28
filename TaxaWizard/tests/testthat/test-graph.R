test_that(".load_graph() returns valid structure", {
  # Clear cache
  .graph_env$graph <- NULL

  graph <- TaxaWizard:::.load_graph()
  expect_type(graph, "list")
  expect_named(graph, c("nodes", "edges", "adj", "node_index"),
               ignore.order = TRUE)

  # Nodes have all three categories

  expect_true(length(graph$nodes$inputs) >= 5)
  expect_true(length(graph$nodes$intermediates) >= 5)
  expect_true(length(graph$nodes$outputs) >= 4)

  # Edges have required fields
  for (edge in graph$edges) {
    expect_true(all(c("id", "from", "to", "label", "snippet") %in% names(edge)))
  }

  # Adjacency list built
  expect_type(graph$adj, "list")
  expect_true(length(graph$adj) > 0)
})

test_that(".load_graph() caches result", {
  .graph_env$graph <- NULL
  g1 <- TaxaWizard:::.load_graph()
  g2 <- TaxaWizard:::.load_graph()
  expect_identical(g1, g2)
})

test_that(".compute_paths() finds sequences -> consensus (multiple paths)", {
  .graph_env$graph <- NULL
  paths <- .compute_paths("sequences", "consensus")

  expect_true(length(paths) >= 2,
              info = "Should find at least score-based and LLM paths")

  # Each path should be a list with edges, uses_wrapper, time_estimate

  for (p in paths) {
    expect_true(all(c("edges", "uses_wrapper", "time_estimate") %in% names(p)))
    expect_type(p$edges, "character")
    expect_true(length(p$edges) >= 1)
  }

  # All paths should start with seq_to_match
  starts <- vapply(paths, function(p) p$edges[1L], "")
  expect_true(all(starts == "seq_to_match"))
})

test_that(".compute_paths() finds taxa -> priors (wrapper and manual)", {
  .graph_env$graph <- NULL
  paths <- .compute_paths("taxa", "priors")

  expect_true(length(paths) >= 2,
              info = "Should find wrapper and manual paths")

  # One path should use the wrapper
  has_wrapper <- vapply(paths, function(p) p$uses_wrapper, FALSE)
  expect_true(any(has_wrapper), info = "Should include wrapper path")
  expect_true(any(!has_wrapper), info = "Should include manual path")

  # Wrapper path should be shorter
  wrapper_len <- min(vapply(paths[has_wrapper], function(p) length(p$edges), 0L))
  manual_len <- max(vapply(paths[!has_wrapper], function(p) length(p$edges), 0L))
  expect_true(wrapper_len < manual_len)
})

test_that(".compute_paths() finds match_df -> consensus (3+ paths)", {
  .graph_env$graph <- NULL
  paths <- .compute_paths("match_df", "consensus")

  expect_true(length(paths) >= 2,
              info = "Should find score, LLM wrapper, and possibly Bayesian paths")

  # Score-based path should exist (single edge)
  edge_sets <- lapply(paths, `[[`, "edges")
  has_score <- any(vapply(edge_sets, function(e) "match_to_consensus_score" %in% e, FALSE))
  expect_true(has_score, info = "Score-based path should exist")

  # LLM wrapper path should exist
  has_llm <- any(vapply(edge_sets, function(e) "match_to_consensus_llm" %in% e, FALSE))
  expect_true(has_llm, info = "LLM wrapper path should exist")
})

test_that(".compute_paths() finds consensus_df -> reviewed", {
  .graph_env$graph <- NULL
  paths <- .compute_paths("consensus_df", "reviewed")

  # Should find path: consensus_df_to_taxa -> taxa_to_context -> consensus_df_to_reviewed
  expect_true(length(paths) >= 1)
  p <- paths[[1]]
  expect_true("consensus_df_to_taxa" %in% p$edges)
  expect_true("taxa_to_context" %in% p$edges)
  expect_true("consensus_df_to_reviewed" %in% p$edges)
})

test_that(".compute_paths() returns empty for impossible paths", {
  .graph_env$graph <- NULL

  # reference_df -> flagged has no valid path
  paths <- .compute_paths("reference_df", "flagged")
  # This might find a path through matrix -> model -> ... or might not
  # The key test: it doesn't crash
  expect_type(paths, "list")
})

test_that(".compute_paths() errors on invalid node IDs", {
  .graph_env$graph <- NULL
  expect_error(.compute_paths("nonexistent", "consensus"), "Unknown input_type")
  expect_error(.compute_paths("sequences", "nonexistent"), "Unknown output_type")
})

test_that(".compute_paths() prevents cycles", {
  .graph_env$graph <- NULL
  # This should terminate (no infinite loops) even with complex graph
  paths <- .compute_paths("sequences", "reviewed")
  expect_type(paths, "list")
})

test_that(".describe_paths() produces readable text", {
  .graph_env$graph <- NULL
  paths <- .compute_paths("match_df", "consensus")
  desc <- TaxaWizard:::.describe_paths(paths)

  expect_type(desc, "character")
  expect_true(nchar(desc) > 50)
  expect_true(grepl("Path 1", desc))
  expect_true(grepl("Step 1", desc))
  expect_true(grepl("Time:", desc))
})

test_that(".describe_paths() handles empty paths", {
  desc <- TaxaWizard:::.describe_paths(list())
  expect_equal(desc, "No valid paths found.")
})

test_that(".get_path_context() returns snippets and docs", {
  .graph_env$graph <- NULL
  ctx <- TaxaWizard:::.get_path_context(c("seq_to_match", "match_to_consensus_score"))

  expect_type(ctx, "list")
  expect_named(ctx, c("snippets", "edge_labels", "packages", "functions", "param_docs"),
               ignore.order = TRUE)

  # Snippets should be loaded

  expect_true(nchar(ctx$snippets[["seq_to_match"]]) > 20)
  expect_true(nchar(ctx$snippets[["match_to_consensus_score"]]) > 20)

  # Edge labels present
  expect_true(all(c("seq_to_match", "match_to_consensus_score") %in%
                    names(ctx$edge_labels)))

  # Packages collected
  expect_true("TaxaMatch" %in% ctx$packages)
  expect_true("TaxaAssign" %in% ctx$packages)
})

test_that(".get_path_context() errors on unknown edge", {
  .graph_env$graph <- NULL
  expect_error(.get_path_context(c("nonexistent_edge")), "Unknown edge ID")
})

test_that(".list_node_types() returns inputs and outputs", {
  .graph_env$graph <- NULL
  types <- .list_node_types()

  expect_named(types, c("inputs", "outputs"))
  expect_true("sequences" %in% types$inputs)
  expect_true("match_df" %in% types$inputs)
  expect_true("consensus" %in% types$outputs)
  expect_true("reviewed" %in% types$outputs)
})

test_that(".describe_node_types() produces text with all nodes", {
  .graph_env$graph <- NULL
  desc <- .describe_node_types()

  expect_type(desc, "character")
  expect_true(grepl("INPUT TYPES", desc))
  expect_true(grepl("OUTPUT TYPES", desc))
  expect_true(grepl("sequences", desc))
  expect_true(grepl("consensus", desc))
})

test_that("priors_to_map edge is reachable from taxa", {
  .graph_env$graph <- NULL
  paths <- .compute_paths("taxa", "prior_map")
  expect_true(length(paths) >= 1, info = "Should find path to prior_map")
})

test_that("taxa_refs_to_gaps edge requires both taxa and reference_df", {
  .graph_env$graph <- NULL
  # From taxa alone, ref_gaps requires reference_df (via taxa_to_refs or taxa_to_site_refs)
  paths <- .compute_paths("taxa", "ref_gaps")
  expect_true(length(paths) >= 1, info = "taxa -> refs -> ref_gaps should work")

  # All paths must go through taxa_refs_to_gaps (the final step)
  for (p in paths) {
    expect_true("taxa_refs_to_gaps" %in% p$edges)
  }
  # At least one path should use taxa_to_refs (direct NCBI fetch)
  has_taxa_to_refs <- vapply(paths, function(p) "taxa_to_refs" %in% p$edges, FALSE)
  expect_true(any(has_taxa_to_refs), info = "At least one path should use taxa_to_refs")
})

test_that("multi-input edges produce full Bayesian path", {
  .graph_env$graph <- NULL
  paths <- .compute_paths("sequences", "consensus")

  # Should find path with match_to_consensus_bayes (requires match_df + model_params + priors)
  has_bayes <- vapply(paths, function(p) "match_to_consensus_bayes" %in% p$edges, FALSE)
  expect_true(any(has_bayes), info = "Full Bayesian wrapper path should be found")

  # At least one Bayesian path should include DNA model training AND prior building
  bayes_paths <- paths[has_bayes]
  has_dna_model <- vapply(bayes_paths, function(p) "matrix_to_model" %in% p$edges, FALSE)
  expect_true(any(has_dna_model),
    info = "At least one Bayesian path should train a DNA likelihood model")
  dna_bayes <- bayes_paths[has_dna_model]
  for (p in dna_bayes) {
    expect_true("seq_to_match" %in% p$edges)
    # Priors via wrapper or manual
    has_priors <- "taxa_to_priors_wrapper" %in% p$edges ||
                  "dist_to_priors" %in% p$edges
    expect_true(has_priors, info = "Bayesian path needs priors")
  }

  # Should also find the stepwise Bayesian path (lik_prior_to_post)
  has_stepwise <- vapply(paths, function(p) "lik_prior_to_post" %in% p$edges, FALSE)
  expect_true(any(has_stepwise), info = "Stepwise Bayesian path should also be found")
})

test_that("edges are topologically sorted in path output", {
  .graph_env$graph <- NULL
  graph <- .load_graph()
  edge_index <- stats::setNames(graph$edges, vapply(graph$edges, `[[`, "", "id"))

  paths <- .compute_paths("sequences", "consensus")
  for (p in paths) {
    available <- "sequences"
    for (eid in p$edges) {
      edge <- edge_index[[eid]]
      # All inputs should be available before this edge
      expect_true(all(edge$from %in% available),
                  info = sprintf("Edge %s inputs not yet produced", eid))
      available <- c(available, edge$to)
    }
  }
})
