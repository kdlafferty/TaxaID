utils::globalVariables(character(0))

#' Load the Workflow Graph
#'
#' Reads \code{inst/graph/workflow_graph.json} and returns a parsed list with
#' \code{nodes} and \code{edges}. The result is cached in the package
#' namespace after first load.
#'
#' @return A list with \code{$nodes} (list of input/intermediate/output node
#'   definitions) and \code{$edges} (list of edge definitions).
#' @noRd
.load_graph <- function() {
  # Check namespace cache
  cache <- .graph_cache()
  if (!is.null(cache)) return(cache)

  path <- system.file("graph", "workflow_graph.json", package = "TaxaWizard")
  if (!nzchar(path)) {
    stop("workflow_graph.json not found. Is TaxaWizard installed?",
         call. = FALSE)
  }
  graph <- jsonlite::fromJSON(path, simplifyVector = FALSE)

  # Build adjacency list for fast traversal
  graph$adj <- .build_adjacency(graph$edges)

  # Index nodes by id
  all_nodes <- c(graph$nodes$inputs, graph$nodes$intermediates, graph$nodes$outputs)
  graph$node_index <- stats::setNames(all_nodes, vapply(all_nodes, `[[`, "", "id"))

  .graph_cache(graph)
  graph
}


#' Adjacency List Cache
#'
#' Simple mutable cache using a local environment.
#' @noRd
.graph_env <- new.env(parent = emptyenv())

.graph_cache <- function(value = NULL) {
  if (!is.null(value)) {
    .graph_env$graph <- value
    return(invisible(NULL))
  }
  .graph_env$graph
}


#' Build Adjacency List from Edges
#'
#' Creates a named list where each key is a node id and each value is a list
#' of edges leaving that node. Multi-input edges (e.g. match_df + model_params
#' -> likelihoods) appear under EACH of their \code{from} nodes.
#'
#' @param edges List of edge definitions from the graph JSON.
#' @return Named list of lists of edges.
#' @noRd
.build_adjacency <- function(edges) {
  adj <- list()
  for (edge in edges) {
    for (src in edge$from) {
      adj[[src]] <- c(adj[[src]], list(edge))
    }
  }
  adj
}


#' Compute All Valid Paths Between Two Node Types
#'
#' Uses backward recursive search to find all sets of edges that can
#' produce \code{output_type} starting from \code{input_type}. Properly
#' handles multi-input edges (e.g. \code{match_to_consensus_bayes} requires
#' \code{match_df + model_params + priors}) by recursively finding plans
#' to produce each required input and combining them.
#'
#' @param input_type Character. ID of the starting node (e.g. \code{"sequences"}).
#' @param output_type Character. ID of the target node (e.g. \code{"consensus"}).
#' @param graph Optional graph object from \code{.load_graph()}.
#'
#' @return A list of paths. Each path is a list with:
#' \describe{
#'   \item{\code{edges}}{Character vector of edge IDs in dependency order.}
#'   \item{\code{uses_wrapper}}{Logical: TRUE if any edge in the path is a wrapper.}
#'   \item{\code{time_estimate}}{Character: combined time estimate.}
#' }
#' Returns an empty list if no valid path exists.
#'
#' @noRd
.compute_paths <- function(input_type, output_type, graph = NULL) {
  if (is.null(graph)) graph <- .load_graph()

  # Validate node IDs
  all_ids <- vapply(
    c(graph$nodes$inputs, graph$nodes$intermediates, graph$nodes$outputs),
    `[[`, "", "id"
  )
  if (!input_type %in% all_ids) {
    stop("Unknown input_type: ", input_type, call. = FALSE)
  }
  if (!output_type %in% all_ids) {
    stop("Unknown output_type: ", output_type, call. = FALSE)
  }

  # Build reverse adjacency: for each node, which edges produce it?
  rev_adj <- list()
  for (edge in graph$edges) {
    rev_adj[[edge$to]] <- c(rev_adj[[edge$to]], list(edge))
  }

  # Recursive backward search: find all edge-sets that produce `target`
  # starting from `input_type`. Returns list of character vectors (edge IDs).
  find_plans <- function(target, visited_targets = character(0)) {
    # Base case: target is already available
    if (target == input_type) return(list(character(0)))
    # Cycle prevention
    if (target %in% visited_targets) return(list())

    producers <- rev_adj[[target]]
    if (is.null(producers)) return(list())

    visited_targets <- c(visited_targets, target)
    results <- list()

    for (edge in producers) {
      # For each input of this edge, find all ways to produce it
      input_plans_list <- list()
      feasible <- TRUE

      for (inp in edge$from) {
        sub_plans <- find_plans(inp, visited_targets)
        if (length(sub_plans) == 0L) {
          feasible <- FALSE
          break
        }
        input_plans_list <- c(input_plans_list, list(sub_plans))
      }

      if (!feasible) next

      # Cartesian product of input plans, then append this edge
      combos <- .cartesian_plans(input_plans_list)
      for (combo in combos) {
        merged <- unique(c(combo, edge$id))
        results <- c(results, list(merged))
      }
    }

    results
  }

  raw_plans <- find_plans(output_type)
  if (length(raw_plans) == 0L) return(list())

  # Deduplicate (same edge set in different order = same plan)
  plan_keys <- vapply(raw_plans, function(p) paste(sort(p), collapse = "|"), "")
  raw_plans <- raw_plans[!duplicated(plan_keys)]

  # Build edge index for annotation and topological sorting
  edge_index <- stats::setNames(graph$edges, vapply(graph$edges, `[[`, "", "id"))

  lapply(raw_plans, function(edge_ids) {
    sorted_ids <- .topo_sort_edges(edge_ids, edge_index, input_type)
    edges <- edge_index[sorted_ids]
    list(
      edges         = sorted_ids,
      uses_wrapper  = any(vapply(edges, function(e) isTRUE(e$wrapper), FALSE)),
      time_estimate = .combine_time_estimates(edges)
    )
  })
}


#' Cartesian Product of Plan Lists
#'
#' Given a list of plan-lists (one per edge input), returns all combinations
#' with edge IDs merged into a single vector per combination.
#' @param plan_lists List of lists of character vectors.
#' @return List of character vectors (merged edge IDs).
#' @noRd
.cartesian_plans <- function(plan_lists) {
  if (length(plan_lists) == 0L) return(list(character(0)))
  if (length(plan_lists) == 1L) return(plan_lists[[1L]])

  # Recursive: combine first list with cartesian product of rest
  first <- plan_lists[[1L]]
  rest <- .cartesian_plans(plan_lists[-1L])

  results <- list()
  for (a in first) {
    for (b in rest) {
      results <- c(results, list(unique(c(a, b))))
    }
  }
  results
}


#' Topologically Sort Edge IDs
#'
#' Orders edge IDs so that each edge's inputs are produced before it runs.
#' @param edge_ids Character vector of edge IDs.
#' @param edge_index Named list of edge definitions.
#' @param input_type The starting node (already available).
#' @return Character vector of edge IDs in dependency order.
#' @noRd
.topo_sort_edges <- function(edge_ids, edge_index, input_type) {
  if (length(edge_ids) <= 1L) return(edge_ids)

  # Track which nodes are available
  available <- input_type
  sorted <- character(0)
  remaining <- edge_ids

  max_iter <- length(edge_ids) * length(edge_ids)
  iter <- 0L
  while (length(remaining) > 0L && iter < max_iter) {
    iter <- iter + 1L
    progress <- FALSE
    for (i in seq_along(remaining)) {
      eid <- remaining[i]
      edge <- edge_index[[eid]]
      if (all(edge$from %in% available)) {
        sorted <- c(sorted, eid)
        available <- c(available, edge$to)
        remaining <- remaining[-i]
        progress <- TRUE
        break
      }
    }
    if (!progress) {
      # Remaining edges can't be satisfied --append anyway (shouldn't happen)
      sorted <- c(sorted, remaining)
      break
    }
  }

  sorted
}


#' Combine Time Estimates from Edges
#' @noRd
.combine_time_estimates <- function(edges) {
  estimates <- vapply(edges, function(e) {
    e$time_estimate %||% "unknown"
  }, "")
  paste(estimates, collapse = " + ")
}


#' Describe Paths for LLM Presentation
#'
#' Takes the output of \code{.compute_paths()} and returns a human-readable
#' text block for inclusion in Phase 2 system prompts. Each path is numbered
#' with edge labels, wrapper status, and time estimates.
#'
#' @param paths List of paths from \code{.compute_paths()}.
#' @param graph Optional graph object from \code{.load_graph()}.
#'
#' @return Character string describing all paths, ready for LLM context.
#' @noRd
.describe_paths <- function(paths, graph = NULL) {
  if (is.null(graph)) graph <- .load_graph()
  if (length(paths) == 0L) return("No valid paths found.")

  edge_index <- stats::setNames(graph$edges, vapply(graph$edges, `[[`, "", "id"))

  descriptions <- vapply(seq_along(paths), function(i) {
    path <- paths[[i]]
    edges <- edge_index[path$edges]

    # Build step list with edge IDs visible
    steps <- vapply(seq_along(edges), function(j) {
      e <- edges[[j]]
      sprintf("  Step %d [edge_id: `%s`]: %s [%s]",
              j, e$id, e$label,
              paste(e$packages, collapse = ", "))
    }, "")

    header <- sprintf("Path %d%s", i,
                       if (path$uses_wrapper) " (uses wrapper -- recommended)" else "")
    time_line <- sprintf("  Time: %s", path$time_estimate)
    edge_ids_line <- sprintf("  edge_ids: %s",
                              jsonlite::toJSON(path$edges, auto_unbox = FALSE))

    paste(c(header, steps, time_line, edge_ids_line), collapse = "\n")
  }, "")

  paste(descriptions, collapse = "\n\n")
}


#' Get Context for a Selected Path
#'
#' Given a vector of edge IDs (a selected path), loads the code snippets
#' and assembles parameter documentation for each step. This is the
#' context injected into the Phase 3 (parameterize) system prompt.
#'
#' @param edge_ids Character vector of edge IDs defining the selected path.
#' @param graph Optional graph object from \code{.load_graph()}.
#' @param metadata Optional metadata from \code{.load_metadata()}.
#'
#' @return A list with:
#' \describe{
#'   \item{\code{snippets}}{Named list of code snippet strings, keyed by edge_id.}
#'   \item{\code{edge_labels}}{Named character vector of edge labels.}
#'   \item{\code{packages}}{Character vector of all packages involved.}
#'   \item{\code{functions}}{Named list of function names per edge.}
#'   \item{\code{param_docs}}{Character string: compressed parameter docs for
#'     all functions in the path.}
#' }
#' @noRd
.get_path_context <- function(edge_ids, graph = NULL, metadata = NULL) {
  if (is.null(graph)) graph <- .load_graph()
  if (is.null(metadata)) metadata <- .load_metadata()

  edge_index <- stats::setNames(graph$edges, vapply(graph$edges, `[[`, "", "id"))

  snippets <- list()
  edge_labels <- character(0)
  all_packages <- character(0)
  all_functions <- list()

  for (eid in edge_ids) {
    edge <- edge_index[[eid]]
    if (is.null(edge)) {
      stop("Unknown edge ID: ", eid, call. = FALSE)
    }

    # Load snippet
    snippet_file <- system.file("graph", "snippets", edge$snippet,
                                 package = "TaxaWizard")
    if (nzchar(snippet_file)) {
      snippets[[eid]] <- paste(readLines(snippet_file, warn = FALSE),
                                collapse = "\n")
    } else {
      snippets[[eid]] <- sprintf("# Snippet not found: %s", edge$snippet)
    }

    edge_labels[eid] <- edge$label
    all_packages <- c(all_packages, unlist(edge$packages))
    all_functions[[eid]] <- unlist(edge$functions)
  }

  all_packages <- unique(all_packages)

  # Build parameter docs from metadata for functions in this path
  param_docs <- .extract_param_docs(all_functions, all_packages, metadata)

  list(
    snippets    = snippets,
    edge_labels = edge_labels,
    packages    = all_packages,
    functions   = all_functions,
    param_docs  = param_docs
  )
}


#' Extract Parameter Documentation for Path Functions
#'
#' Pulls parameter signatures and descriptions from metadata JSON for
#' all functions used in a path. Returns a compact text block.
#'
#' @param functions_by_edge Named list of function name vectors.
#' @param packages Character vector of package names.
#' @param metadata Named list of package metadata.
#' @return Character string of formatted parameter docs.
#' @noRd
.extract_param_docs <- function(functions_by_edge, packages, metadata) {
  lines <- character(0)
  seen_fns <- character(0)

  for (eid in names(functions_by_edge)) {
    fn_names <- functions_by_edge[[eid]]
    for (fn_name in fn_names) {
      if (fn_name %in% seen_fns) next
      seen_fns <- c(seen_fns, fn_name)

      # Search across relevant packages
      doc <- NULL
      for (pkg in packages) {
        pkg_meta <- metadata[[pkg]]
        if (is.null(pkg_meta)) next
        fns <- pkg_meta$functions
        if (is.null(fns)) next
        # Find matching function
        for (fn_def in fns) {
          if (identical(fn_def$name, fn_name)) {
            doc <- fn_def
            break
          }
        }
        if (!is.null(doc)) break
      }

      if (is.null(doc)) {
        lines <- c(lines, sprintf("## %s\n(no metadata available)\n", fn_name))
        next
      }

      # Format parameter list
      param_lines <- character(0)
      params <- doc$params %||% doc$parameters
      if (!is.null(params)) {
        for (p in params) {
          req <- if (isTRUE(p$required)) " (REQUIRED)" else ""
          def <- if (!is.null(p$default)) sprintf(" [default: %s]", p$default) else ""
          desc <- p$description %||% ""
          param_lines <- c(param_lines,
                            sprintf("  - %s: %s%s%s", p$name, desc, req, def))
        }
      }

      lines <- c(lines,
                  sprintf("## %s::%s", doc$package %||% "?", fn_name),
                  if (length(param_lines) > 0) param_lines else "  (no params)",
                  "")
    }
  }

  paste(lines, collapse = "\n")
}


#' Build Phase-Specific System Prompt
#'
#' Reads the template for the given phase and fills in placeholders with
#' graph-derived context. This replaces the monolithic system prompt with
#' a minimal, phase-appropriate prompt.
#'
#' @param phase Character: \code{"classify"}, \code{"path_select"},
#'   \code{"parameterize"}, or \code{"error_fix"}.
#' @param context Named list of values to substitute into the template.
#'   Required keys depend on phase:
#'   \describe{
#'     \item{classify}{(none --node types auto-loaded)}
#'     \item{path_select}{\code{input_type}, \code{output_type}, \code{paths}}
#'     \item{parameterize}{\code{input_type}, \code{output_type},
#'       \code{selected_path} (edge ID vector)}
#'     \item{error_fix}{\code{step_number}, \code{edge_id},
#'       \code{step_description}, \code{error_message}, \code{step_code}}
#'   }
#' @param graph Optional graph object.
#' @param metadata Optional metadata (only needed for parameterize/error_fix).
#'
#' @return Character string: the assembled system prompt.
#' @noRd
.build_phase_prompt <- function(phase, context = list(), graph = NULL,
                                 metadata = NULL) {
  if (is.null(graph)) graph <- .load_graph()

  template_file <- sprintf("phase_%s.md", phase)
  template_path <- system.file("prompts", template_file,
                                package = "TaxaWizard")
  if (!nzchar(template_path)) {
    stop("Prompt template not found: ", template_file, call. = FALSE)
  }
  prompt <- paste(readLines(template_path, warn = FALSE), collapse = "\n")

  switch(phase,
    classify = {
      prompt <- sub("{{NODE_TYPES}}", .describe_node_types(graph),
                     prompt, fixed = TRUE)
      # Continuation context: when extending a completed workflow
      prior_out <- context$prior_output_type
      if (!is.null(prior_out) && nzchar(prior_out)) {
        prior_label <- graph$node_index[[prior_out]]$label %||% prior_out

        # Compute reachable outputs so the LLM knows what is possible
        all_output_ids <- vapply(graph$nodes$outputs, `[[`, "", "id")
        reachable <- character(0)
        for (oid in all_output_ids) {
          paths <- tryCatch(
            .compute_paths(prior_out, oid, graph),
            error = function(e) list()
          )
          if (length(paths) > 0L) {
            olabel <- graph$node_index[[oid]]$label %||% oid
            reachable <- c(reachable, sprintf("- `%s` (%s)", oid, olabel))
          }
        }
        reachable_text <- if (length(reachable) > 0L) {
          paste0("Reachable outputs from `", prior_out, "`:\n",
                 paste(reachable, collapse = "\n"))
        } else {
          "No further outputs are reachable from this input."
        }

        continuation <- sprintf(paste0(
          "\n\n# CONTINUATION MODE\n\n",
          "The user has ALREADY completed a workflow that produced **%s** (`%s`). ",
          "They now want to extend it. Their new input_type is `%s` (already ",
          "available from the previous script). Identify only what NEW output ",
          "they want. Do NOT re-classify the input -- set `input_type` to `\"%s\"` ",
          "immediately and focus on asking what they want to do next.\n\n",
          "%s\n\n",
          "IMPORTANT: Only offer outputs from this list. Do NOT invent package ",
          "names or functions that are not in the TaxaID ecosystem. If the user ",
          "asks for something not on this list, tell them it is not available."
        ), prior_label, prior_out, prior_out, prior_out, reachable_text)
        prompt <- paste0(prompt, continuation)
      }
    },
    path_select = {
      input_type  <- context$input_type
      output_type <- context$output_type

      # Look up labels
      input_label  <- graph$node_index[[input_type]]$label %||% input_type
      output_label <- graph$node_index[[output_type]]$label %||% output_type

      # Compute paths if not provided
      paths <- context$paths
      if (is.null(paths)) {
        paths <- .compute_paths(input_type, output_type, graph)
      }

      prompt <- sub("{{INPUT_TYPE}}", input_type, prompt, fixed = TRUE)
      prompt <- gsub("{{INPUT_TYPE}}", input_type, prompt, fixed = TRUE)
      prompt <- sub("{{OUTPUT_TYPE}}", output_type, prompt, fixed = TRUE)
      prompt <- gsub("{{OUTPUT_TYPE}}", output_type, prompt, fixed = TRUE)
      prompt <- sub("{{INPUT_LABEL}}", input_label, prompt, fixed = TRUE)
      prompt <- sub("{{OUTPUT_LABEL}}", output_label, prompt, fixed = TRUE)
      prompt <- sub("{{PATH_OPTIONS}}", .describe_paths(paths, graph),
                     prompt, fixed = TRUE)
    },
    parameterize = {
      input_type    <- context$input_type
      output_type   <- context$output_type
      selected_path <- context$selected_path

      if (is.null(metadata)) metadata <- .load_metadata()
      path_ctx <- .get_path_context(selected_path, graph, metadata)

      # Format snippets
      snippet_text <- vapply(names(path_ctx$snippets), function(eid) {
        sprintf("### %s: %s\n```r\n%s\n```",
                eid, path_ctx$edge_labels[eid], path_ctx$snippets[[eid]])
      }, "")
      snippet_block <- paste(snippet_text, collapse = "\n\n")

      # Format edge descriptions
      edge_desc <- paste(vapply(seq_along(selected_path), function(i) {
        sprintf("Step %d: %s (`%s`)", i,
                path_ctx$edge_labels[selected_path[i]], selected_path[i])
      }, ""), collapse = "\n")

      prompt <- gsub("{{INPUT_TYPE}}", input_type, prompt, fixed = TRUE)
      prompt <- gsub("{{OUTPUT_TYPE}}", output_type, prompt, fixed = TRUE)
      prompt <- sub("{{EDGE_DESCRIPTIONS}}", edge_desc, prompt, fixed = TRUE)
      prompt <- sub("{{SNIPPETS}}", snippet_block, prompt, fixed = TRUE)
      prompt <- sub("{{PARAM_DOCS}}", path_ctx$param_docs, prompt, fixed = TRUE)
      prompt <- sub("{{SELECTED_PATH_JSON}}",
                     jsonlite::toJSON(selected_path, auto_unbox = FALSE),
                     prompt, fixed = TRUE)

      # Continuation mode: tell the LLM that input variables already exist
      if (isTRUE(context$is_continuation)) {
        input_label <- graph$node_index[[input_type]]$label %||% input_type
        continuation_note <- sprintf(paste0(
          "\n\n# CONTINUATION MODE\n\n",
          "This workflow EXTENDS a previously generated script. The input data ",
          "(`%s` -- %s) is already available as a variable from the prior script. ",
          "Do NOT add a file-loading step for the input. The new steps will be ",
          "APPENDED to the existing script, so all prior variables (e.g. ",
          "`consensus_df`, `context_df`, `match_df`) are in scope.\n\n",
          "Start your DAG from the first processing step, not a data-loading step."
        ), input_type, input_label)
        prompt <- paste0(prompt, continuation_note)
      }
    },
    error_fix = {
      if (is.null(metadata)) metadata <- .load_metadata()

      step_number <- context$step_number %||% "?"
      edge_id     <- context$edge_id %||% "unknown"
      step_desc   <- context$step_description %||% ""
      error_msg   <- context$error_message %||% ""
      step_code   <- context$step_code %||% ""

      # Get full docs for the failing edge's functions
      edge_index <- stats::setNames(graph$edges,
                                     vapply(graph$edges, `[[`, "", "id"))
      edge <- edge_index[[edge_id]]
      if (!is.null(edge)) {
        fn_list <- list()
        fn_list[[edge_id]] <- unlist(edge$functions)
        docs <- .extract_param_docs(fn_list, unlist(edge$packages), metadata)
      } else {
        docs <- "(edge not found in graph)"
      }

      prompt <- sub("{{STEP_NUMBER}}", step_number, prompt, fixed = TRUE)
      prompt <- sub("{{EDGE_ID}}", edge_id, prompt, fixed = TRUE)
      prompt <- sub("{{STEP_DESCRIPTION}}", step_desc, prompt, fixed = TRUE)
      prompt <- sub("{{ERROR_MESSAGE}}", error_msg, prompt, fixed = TRUE)
      prompt <- sub("{{FAILING_STEP_DOCS}}", docs, prompt, fixed = TRUE)
      prompt <- sub("{{FAILING_STEP_CODE}}", step_code, prompt, fixed = TRUE)
    },
    stop("Unknown phase: ", phase, call. = FALSE)
  )

  # Append corrections (learned from previous errors)
  corrections_text <- .format_corrections_for_prompt()
  if (nzchar(corrections_text)) {
    prompt <- paste0(prompt, "\n\n", corrections_text)
  }

  prompt
}


#' List All Valid Input and Output Types
#'
#' Returns the node IDs that can serve as starting points (inputs) or
#' endpoints (outputs) in the workflow graph.
#'
#' @param graph Optional graph object.
#' @return A list with \code{$inputs} and \code{$outputs} character vectors.
#' @noRd
.list_node_types <- function(graph = NULL) {
  if (is.null(graph)) graph <- .load_graph()
  list(
    inputs  = vapply(graph$nodes$inputs, `[[`, "", "id"),
    outputs = vapply(graph$nodes$outputs, `[[`, "", "id")
  )
}


#' Describe All Node Types for Phase 1
#'
#' Returns a compact text block listing all input and output types with
#' descriptions, for injection into the Phase 1 (classify) system prompt.
#'
#' @param graph Optional graph object.
#' @return Character string.
#' @noRd
.describe_node_types <- function(graph = NULL) {
  if (is.null(graph)) graph <- .load_graph()

  fmt <- function(nodes, header) {
    items <- vapply(nodes, function(n) {
      sprintf("  - %s: %s --%s", n$id, n$label, n$description)
    }, "")
    paste(c(header, items), collapse = "\n")
  }

  paste(
    fmt(graph$nodes$inputs, "INPUT TYPES (what the user starts with):"),
    fmt(graph$nodes$outputs, "OUTPUT TYPES (what the user wants):"),
    sep = "\n\n"
  )
}
