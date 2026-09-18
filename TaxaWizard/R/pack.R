# ==============================================================================
# pack.R
# TaxaWizard -- prompt pack generator (P4)
#
# workflow_export_prompts() writes a self-contained folder any LLM -- a chat
# window with no tools, or an agentic coding tool -- can be pointed at to
# design a TaxaID workflow, with no TaxaWizard install or API key needed for
# TaxaWizard's own engine. Every generated file is DERIVED from
# workflow_registry() / .load_graph() / .load_requirements() / workflow_check(),
# the SAME sources the live chat engine (engine.R/graph.R) reads, so the pack
# and the chat engine cannot disagree (see
# ecosystem_docs/SPEC_taxawizard_derived_context_2026_09_18.md, section P4,
# decision 4: the pack is generated on demand AND committed as a rendered
# copy, refreshed by the README render pipeline, with a test that the two
# agree).
#
# The four tasks/*.md files are the phase prompt templates
# (inst/prompts/phase_*.md) with every placeholder that a LIVE conversation
# would normally fill either (a) resolved statically, when the value does not
# depend on the conversation (currently only {{NODE_TYPES}}), or (b) replaced
# with a short bracketed instruction telling the LLM how to derive it itself
# from CONTEXT_TaxaID.md / a package CONTEXT file / the user's own words. This
# reads the exact template files `.build_phase_prompt()` (graph.R) reads --
# via the same `system.file("prompts", ...)` path -- rather than a second,
# hand-typed copy of the prompt prose. It does NOT call `.build_phase_prompt()`
# itself for this: that function also appends
# `.format_corrections_for_prompt()` (context.R), a per-machine log of
# previously-learned mistakes from THIS installation's own chat sessions --
# appropriate for a live engine call, but not for a static pack meant to be
# portable and byte-for-byte reproducible.
# ==============================================================================


# ==============================================================================
# Small shared helpers
# ==============================================================================

#' Read a phase prompt template's raw text (pre-substitution)
#'
#' The exact same file \code{.build_phase_prompt()} (graph.R) reads, via the
#' same \code{system.file()} lookup -- kept here rather than calling
#' \code{.build_phase_prompt()} itself so the pack's task files never pick up
#' \code{.format_corrections_for_prompt()}'s machine-local "known issues" log
#' (see file header).
#' @noRd
.pack_read_template <- function(phase) {
  template_path <- system.file("prompts", sprintf("phase_%s.md", phase), package = "TaxaWizard")
  if (!nzchar(template_path)) {
    stop("workflow_export_prompts: prompt template not found: phase_", phase, ".md", call. = FALSE)
  }
  paste(readLines(template_path, warn = FALSE), collapse = "\n")
}

#' Locate the TaxaID repo root (the directory containing TaxaWizard/DESCRIPTION)
#'
#' Used for two things that live OUTSIDE this installed package: (1) the
#' sibling packages' README.md files, to pull each CONTEXT_<Package>.md's
#' Quick Start section, and (2) the committed \code{llm_prompts/} copy the
#' byte-for-byte test compares against. Checked first via the \code{TAXAID_ROOT}
#' env var, then by walking up from \code{getwd()}. Returns \code{NULL} (never
#' errors) when not found -- expected whenever TaxaWizard is used from an
#' ordinary install with no access to the source repo, e.g. under
#' \code{R CMD check}.
#' @noRd
.pack_find_repo_root <- function() {
  has_marker <- function(dir) file.exists(file.path(dir, "TaxaWizard", "DESCRIPTION"))

  env_root <- Sys.getenv("TAXAID_ROOT", unset = "")
  if (nzchar(env_root) && has_marker(env_root)) {
    return(normalizePath(env_root, mustWork = FALSE))
  }

  dir <- getwd()
  for (i in seq_len(10L)) {
    if (has_marker(dir)) {
      return(normalizePath(dir, mustWork = FALSE))
    }
    parent <- dirname(dir)
    if (identical(parent, dir)) break
    dir <- parent
  }
  NULL
}

#' Extract a package README's "## Quick Start" section, verbatim
#'
#' Reads \code{<repo root>/<pkg>/README.md}. Matches the heading regardless of
#' a trailing pandoc anchor (\code{## Quick Start \{#quick-start\}}, as in
#' TaxaMatch's README) and stops at the next \code{##}-level heading.
#' \code{NULL} when the repo root can't be found, the README doesn't exist, or
#' it has no Quick Start heading -- never an error.
#' @noRd
.pack_read_quick_start <- function(pkg) {
  root <- .pack_find_repo_root()
  if (is.null(root)) {
    return(NULL)
  }
  readme <- file.path(root, pkg, "README.md")
  if (!file.exists(readme)) {
    return(NULL)
  }

  lines <- readLines(readme, warn = FALSE)
  start <- which(grepl("^##\\s+Quick Start\\b", lines, ignore.case = TRUE))
  if (length(start) == 0L) {
    return(NULL)
  }
  start <- start[1L]

  after_idx <- which(grepl("^##\\s", lines))
  after_idx <- after_idx[after_idx > start]
  end <- if (length(after_idx) > 0L) after_idx[1L] - 1L else length(lines)

  body <- lines[start:end]
  while (length(body) > 0L && !nzchar(trimws(body[length(body)]))) {
    body <- body[-length(body)]
  }
  if (length(body) == 0L) {
    return(NULL)
  }
  paste(body, collapse = "\n")
}

#' Extract the system prompt's "## Pipeline Awareness" section, verbatim
#'
#' Read at render time from \code{inst/prompts/system_prompt.md} -- the
#' spec's own instruction ("do not paste it") -- so the pack's canonical-
#' pipelines text can never drift from the live engine's.
#' @noRd
.pack_pipeline_awareness_text <- function() {
  path <- system.file("prompts", "system_prompt.md", package = "TaxaWizard")
  if (!nzchar(path)) {
    return("(system_prompt.md not found)")
  }
  lines <- readLines(path, warn = FALSE)

  start <- which(grepl("^##\\s+Pipeline Awareness\\s*$", lines))
  if (length(start) == 0L) {
    return("(Pipeline Awareness section not found in system_prompt.md)")
  }
  start <- start[1L]

  after_idx <- which(grepl("^##\\s", lines))
  after_idx <- after_idx[after_idx > start]
  end <- if (length(after_idx) > 0L) after_idx[1L] - 1L else length(lines)

  body <- lines[(start + 1L):end]
  while (length(body) > 0L && !nzchar(trimws(body[1L]))) body <- body[-1L]
  while (length(body) > 0L && !nzchar(trimws(body[length(body)]))) body <- body[-length(body)]
  paste(body, collapse = "\n")
}


# ==============================================================================
# CONTEXT_TaxaID.md
# ==============================================================================

#' @noRd
.pack_packages_table <- function(registry) {
  lines <- c("| Package | Purpose | Version | Built |", "|---|---|---|---|")
  for (pkg in names(registry)) {
    desc <- tryCatch(utils::packageDescription(pkg), error = function(e) NULL)
    title <- if (!is.null(desc) && !is.na(desc$Title %||% NA)) {
      gsub("\\s+", " ", trimws(desc$Title))
    } else {
      ""
    }
    lines <- c(lines, sprintf(
      "| %s | %s | %s | %s |",
      pkg, gsub("\\|", "\\\\|", title),
      registry[[pkg]]$version %||% "?", registry[[pkg]]$built %||% "?"
    ))
  }
  paste(lines, collapse = "\n")
}

#' @noRd
.pack_graph_adjacency_text <- function(graph) {
  node_label <- function(id) {
    n <- graph$node_index[[id]]
    if (is.null(n)) id else sprintf("%s (%s)", id, n$label)
  }

  to_ids_all <- vapply(graph$edges, `[[`, "", "to")
  by_to <- split(graph$edges, to_ids_all)

  order_ids <- vapply(
    c(graph$nodes$inputs, graph$nodes$intermediates, graph$nodes$outputs),
    `[[`, "", "id"
  )
  to_ids <- intersect(order_ids, names(by_to))

  lines <- character(0)
  for (to_id in to_ids) {
    lines <- c(lines, sprintf("### -> %s", node_label(to_id)))
    for (e in by_to[[to_id]]) {
      req <- if (length(e$requires) > 0L) paste(unlist(e$requires), collapse = ", ") else "none"
      wrap <- if (isTRUE(e$wrapper)) " [wrapper]" else ""
      lines <- c(lines, sprintf(
        "- `%s`: %s -> `%s` -- %s%s (requires: %s)",
        e$id, paste(unlist(e$from), collapse = " + "), e$to, e$label, wrap, req
      ))
    }
    lines <- c(lines, "")
  }
  paste(lines, collapse = "\n")
}

#' @param items List of requirements.json entries (keys/packages/binaries/network).
#' @param default_level Level shown when an entry has no \code{level} field.
#'   requirements.json's own convention (see its \code{_comment}): omitted
#'   means \code{"missing"} (blocking) for keys/packages/binaries -- but
#'   \code{"network"} entries never carry a \code{level} at all, because
#'   \code{workflow_check()} never reports a network row as \code{"missing"}
#'   (only \code{ok}/\code{warn}/\code{skip}; see \code{.resolve_net_token()}
#'   in setup.R), so defaulting those to \code{"missing"} would misstate them
#'   as blocking.
#' @noRd
.pack_requirements_table <- function(items, default_level = "missing") {
  if (length(items) == 0L) {
    return("(none)")
  }
  rows <- vapply(items, function(x) {
    sprintf(
      "| %s | %s | %s |",
      x$id %||% "?",
      gsub("\\|", "\\\\|", x$purpose %||% ""),
      x$level %||% default_level
    )
  }, character(1))
  paste(c("| id | purpose | level |", "|---|---|---|", rows), collapse = "\n")
}

#' @noRd
.pack_requirements_summary <- function(requirements) {
  group_items <- lapply(names(requirements$groups), function(g) {
    list(
      id = paste0("key:", g),
      purpose = requirements$groups[[g]]$purpose,
      level = requirements$groups[[g]]$level
    )
  })

  paste(c(
    "### API keys (individual)", "",
    .pack_requirements_table(requirements$keys), "",
    "### API key groups (any ONE member key satisfies the group)", "",
    .pack_requirements_table(group_items), "",
    "### Optional / Bioconductor packages", "",
    .pack_requirements_table(requirements$packages), "",
    "### Binaries", "",
    .pack_requirements_table(requirements$binaries), "",
    "### Network endpoints checked", "",
    .pack_requirements_table(requirements$network, default_level = "n/a (never blocking; ok/warn/skip only)")
  ), collapse = "\n")
}

#' @noRd
.pack_context_taxaid_md <- function(registry, graph, requirements) {
  c(
    "# CONTEXT: TaxaID ecosystem",
    "",
    sprintf(
      "Generated by `TaxaWizard::workflow_export_prompts()` on %s from the packages installed on that machine. Derived, not hand-written -- trust this over any prior knowledge of TaxaID.",
      format(Sys.Date())
    ),
    "",
    "## Packages",
    "",
    .pack_packages_table(registry),
    "",
    "## Node types (workflow graph inputs and outputs)",
    "",
    .describe_node_types(graph),
    "",
    "## Workflow graph (edges, grouped by output node)",
    "",
    "Each edge turns its `from` node(s) into its `to` node. An edge tagged",
    "`[wrapper]` is a high-level convenience function preferred over the",
    "manual multi-step equivalent when defaults are acceptable. `requires`",
    "lists the setup tokens (see \"Setup requirements summary\" below) that",
    "edge's step needs -- check them against SETUP_REPORT.md before running.",
    "",
    .pack_graph_adjacency_text(graph),
    "## Canonical pipelines",
    "",
    .pack_pipeline_awareness_text(),
    "",
    "## Setup requirements summary",
    "",
    "Key and network checks report **set/unset, or reachable/unreachable,",
    "only** -- never a value. See SETUP_REPORT.md for this machine's actual",
    "status.",
    "",
    .pack_requirements_summary(requirements)
  )
}


# ==============================================================================
# CONTEXT_<Package>.md
# ==============================================================================

#' @noRd
.pack_params_table <- function(params) {
  if (length(params) == 0L) {
    return("(no parameters)")
  }
  rows <- vapply(params, function(p) {
    sprintf(
      "| %s | %s | %s | %s |",
      p$name,
      if (isTRUE(p$required)) "yes" else "no",
      gsub("\\|", "\\\\|", p$default %||% ""),
      gsub("\\|", "\\\\|", p$doc %||% "")
    )
  }, character(1))
  paste(c("| Param | Required | Default | Doc |", "|---|---|---|---|", rows), collapse = "\n")
}

#' @noRd
.pack_context_package_md <- function(pkg, entry) {
  desc <- tryCatch(utils::packageDescription(pkg), error = function(e) NULL)
  title <- if (!is.null(desc) && !is.na(desc$Title %||% NA)) gsub("\\s+", " ", trimws(desc$Title)) else ""
  description <- if (!is.null(desc) && !is.na(desc$Description %||% NA)) {
    gsub("\\s+", " ", trimws(desc$Description))
  } else {
    ""
  }

  lines <- c(
    sprintf("# CONTEXT: %s", pkg),
    "",
    sprintf("**%s**", title),
    "",
    description,
    "",
    sprintf(
      "Version %s (built %s). %d exported function(s).",
      entry$version %||% "?", entry$built %||% "?", length(entry$functions)
    ),
    "",
    "## Functions",
    ""
  )

  for (fn in entry$functions) {
    lines <- c(lines, sprintf("### %s(%s)", fn$name, .format_registry_signature(fn)), "")
    if (!is.null(fn$title) && nzchar(fn$title)) lines <- c(lines, fn$title, "")
    if (!is.null(fn$description) && nzchar(fn$description)) lines <- c(lines, fn$description, "")
    lines <- c(lines, .pack_params_table(fn$params), "")
    if (!is.null(fn$value) && nzchar(fn$value)) {
      lines <- c(lines, sprintf("**Value:** %s", fn$value), "")
    }
  }

  quick_start <- .pack_read_quick_start(pkg)
  if (!is.null(quick_start)) {
    lines <- c(lines, quick_start, "")
  }

  lines
}


# ==============================================================================
# SETUP_REPORT.md
# ==============================================================================

#' @noRd
.pack_setup_report_md <- function(placeholder_setup_report) {
  header <- c(
    "# TaxaID setup report",
    "",
    sprintf(
      "Generated %s. Key checks report **set/unset only** -- a key's value is never included here, or written anywhere by TaxaWizard.",
      format(Sys.Date())
    ),
    ""
  )

  if (isTRUE(placeholder_setup_report)) {
    return(c(
      header,
      "Run `TaxaWizard::workflow_export_prompts()` (without `placeholder_setup_report = TRUE`) to generate a report for your machine."
    ))
  }

  report <- workflow_check(verbose = FALSE)
  body <- utils::capture.output(print(report))
  c(header, "```", body, "```")
}


# ==============================================================================
# tasks/*.md
# ==============================================================================

#' Bracketed live-conversation placeholder text, one map per phase.
#'
#' Every key is a literal \code{\{\{PLACEHOLDER\}\}} token exactly as it
#' appears in \code{inst/prompts/phase_*.md}. \code{classify}'s
#' \code{\{\{NODE_TYPES\}\}} is filled with REAL content elsewhere (it does
#' not depend on a live conversation -- see \code{.pack_render_task()}); every
#' other phase's placeholders here depend on a live conversation and are
#' replaced with an instruction telling the LLM how to derive the value
#' itself, from CONTEXT_TaxaID.md, a package CONTEXT file, or the user's own
#' words.
#' @noRd
.pack_task_bracket_map <- function() {
  list(
    path_select = c(
      "{{INPUT_TYPE}}" = "[the input node id you and the user agreed on -- see CONTEXT_TaxaID.md's Node types]",
      "{{OUTPUT_TYPE}}" = "[the output node id you and the user agreed on -- see CONTEXT_TaxaID.md's Node types]",
      "{{INPUT_LABEL}}" = "[that input node's label, from CONTEXT_TaxaID.md]",
      "{{OUTPUT_LABEL}}" = "[that output node's label, from CONTEXT_TaxaID.md]",
      "{{PATH_OPTIONS}}" = "[derive this from CONTEXT_TaxaID.md's \"Workflow graph\" section: trace edges from the input node to the output node -- there may be more than one route. List each route as an ordered sequence of edge ids with their labels, packages, and `requires` tokens, and note whether it uses a `[wrapper]` edge.]"
    ),
    parameterize = c(
      "{{INPUT_TYPE}}" = "[the input node id, chosen in tasks/path_select.md]",
      "{{OUTPUT_TYPE}}" = "[the output node id, chosen in tasks/path_select.md]",
      "{{EDGE_DESCRIPTIONS}}" = "[the selected path's steps, one line each: step number, edge id, label -- from tasks/path_select.md's chosen route]",
      "{{SNIPPETS}}" = "[the prompt pack does not ship a pre-validated code-snippet library. Write each step's R code yourself, one function call per step, strictly from the signature and docs in the relevant CONTEXT_<Package>.md file -- named arguments only, never a parameter name that isn't in that file's params table.]",
      "{{PARAM_DOCS}}" = "[the params tables for every function used in the selected path, copied from the relevant CONTEXT_<Package>.md file(s)]",
      "{{SELECTED_PATH_JSON}}" = "[the selected edge ids, in order]"
    ),
    error_fix = c(
      "{{STEP_NUMBER}}" = "[the step number the user reports failing]",
      "{{EDGE_ID}}" = "[that step's edge id, from the script's \"Step N\" comment]",
      "{{STEP_DESCRIPTION}}" = "[that step's description, from the script's comment or the plan in tasks/parameterize.md]",
      "{{ERROR_MESSAGE}}" = "[paste the user's exact error text here]",
      "{{FAILING_STEP_DOCS}}" = "[the failing function's params table, from the relevant CONTEXT_<Package>.md file]",
      "{{FAILING_STEP_CODE}}" = "[the failing step's R code, from the script the user is running]"
    )
  )
}

#' Strip the JSON-only response-format requirement from a phase template
#'
#' The engine's phase templates require a single, schema-conformant JSON
#' object with no surrounding prose (parsed by \code{workflow_engine()}).
#' That contract makes no sense for a plain chat LLM with no parser behind
#' it, so the pack's task files replace each template's whole
#' "# RESPONSE FORMAT" section (heading through the next top-level `#`
#' heading) with a short prose instruction instead -- a documented,
#' mechanical post-processing pass, per the spec, rather than a second set
#' of hand-edited templates.
#' @noRd
.pack_strip_json_format <- function(text) {
  lines <- strsplit(text, "\n", fixed = TRUE)[[1L]]

  # phase_parameterize.md's standalone bold callout, ahead of any heading.
  lines <- lines[!grepl("^\\*\\*CRITICAL FORMAT REQUIREMENT", lines)]

  start <- which(grepl("^# RESPONSE FORMAT\\s*$", lines))
  if (length(start) == 0L) {
    return(paste(lines, collapse = "\n"))
  }
  start <- start[1L]

  after_idx <- which(grepl("^# ", lines))
  after_idx <- after_idx[after_idx > start]
  end <- if (length(after_idx) > 0L) after_idx[1L] - 1L else length(lines)

  replacement <- c(
    "# RESPONSE FORMAT",
    "",
    "This is a plain conversation, not a machine-parsed API -- respond in",
    "prose, not JSON. Ask your question, or state your recommendation, in",
    "ordinary text ending with a clear question (see MESSAGE STYLE / RULES",
    "below). When you have enough information to write code, give it",
    "directly as a fenced ```r code block, one step at a time, following the",
    "code rules below.",
    ""
  )

  tail_lines <- if (end < length(lines)) lines[(end + 1L):length(lines)] else character(0)
  paste(c(lines[seq_len(start - 1L)], replacement, tail_lines), collapse = "\n")
}

#' Render one tasks/<phase>.md file
#' @noRd
.pack_render_task <- function(phase, graph) {
  text <- .pack_read_template(phase)

  if (identical(phase, "classify")) {
    text <- sub("{{NODE_TYPES}}", .describe_node_types(graph), text, fixed = TRUE)
  } else {
    bracket_map <- .pack_task_bracket_map()[[phase]]
    for (ph in names(bracket_map)) {
      text <- gsub(ph, bracket_map[[ph]], text, fixed = TRUE)
    }
  }

  .pack_strip_json_format(text)
}


# ==============================================================================
# Agentic-tool pointer files
# ==============================================================================

#' @noRd
.pack_agent_note <- function() {
  c(
    "Read START_HERE.md first, before doing anything else in this folder.",
    "CONTEXT_TaxaID.md and every CONTEXT_<Package>.md file are generated from the TaxaID packages installed on the machine that ran `TaxaWizard::workflow_export_prompts()` -- trust them over any prior knowledge of TaxaID.",
    "Do not hand-edit files in this folder; regenerate them with `TaxaWizard::workflow_export_prompts()` instead."
  )
}


# ==============================================================================
# workflow_export_prompts()
# ==============================================================================

#' Export a Portable TaxaID Prompt Pack
#'
#' Writes a self-contained folder any LLM can be pointed at to design a
#' TaxaID workflow -- an agentic coding tool that can read files and run R
#' directly, or a plain chat window where the user pastes files and console
#' output back and forth. Every file except \code{START_HERE.md} and
#' \code{tasks/handoff_template.md} (hand-written, copied verbatim) is
#' generated from \code{\link{workflow_registry}}, the workflow graph, and
#' \code{\link{workflow_check}} -- the same sources
#' \code{\link{workflow_engine}} reads for its own prompts, so the pack and
#' the live chat engine cannot disagree.
#'
#' Layout written under \code{dir}:
#' \describe{
#'   \item{\code{START_HERE.md}}{Copied verbatim from \code{inst/prompts/pack/}.}
#'   \item{\code{CLAUDE.md}, \code{AGENTS.md}}{Three lines each, telling an
#'     agentic coding tool to read \code{START_HERE.md} first.}
#'   \item{\code{CONTEXT_TaxaID.md}}{Ecosystem digest: packages, node types,
#'     the workflow graph as a text adjacency list, the canonical pipelines
#'     (read live from \code{inst/prompts/system_prompt.md}'s "Pipeline
#'     Awareness" section), and a setup-requirements summary. At most 400
#'     lines.}
#'   \item{\code{CONTEXT_<Package>.md}}{One per TaxaID package: its
#'     DESCRIPTION Title/Description, every exported function with its
#'     signature/title/description/params table/value, and its README's
#'     Quick Start section when one exists and the source repo is reachable
#'     (see \code{TAXAID_ROOT} in Details).}
#'   \item{\code{SETUP_REPORT.md}}{\code{\link{workflow_check}}'s report for
#'     the machine that generated the pack, or a placeholder (see
#'     \code{placeholder_setup_report}).}
#'   \item{\code{tasks/classify.md}, \code{tasks/path_select.md},
#'     \code{tasks/parameterize.md}, \code{tasks/error_fix.md}}{The
#'     corresponding \code{inst/prompts/phase_*.md} template, with
#'     statically-known placeholders filled and every placeholder that
#'     depends on a live conversation replaced by a bracketed instruction.
#'     The JSON-only response-format requirement (meant for the machine-
#'     parsed engine, not a chat LLM) is stripped.}
#'   \item{\code{tasks/handoff_template.md}}{Copied verbatim from
#'     \code{inst/prompts/pack/}.}
#' }
#'
#' @param dir Character. Directory to write the pack into (created if it
#'   does not exist). Default \code{"taxaid_prompts"}.
#' @param overwrite Logical. When \code{FALSE} (default), errors if any file
#'   this function would write already exists at that path. \code{TRUE}
#'   replaces it.
#' @param placeholder_setup_report Logical. When \code{TRUE}, writes
#'   \code{SETUP_REPORT.md} as a placeholder pointing the reader at
#'   \code{workflow_check()} instead of running the check on this machine.
#'   Default \code{FALSE}. Used for the copy committed to the repository
#'   (\code{llm_prompts/}), which is not any one contributor's machine.
#'
#' @return Character vector of the full paths written, invisibly.
#'
#' @details
#' \code{CONTEXT_<Package>.md}'s Quick Start section, and the committed-copy
#' comparison in this package's own test suite, need the TaxaID source repo
#' (the sibling packages' \code{README.md} files, and \code{llm_prompts/}
#' itself) -- not something an ordinary install of TaxaWizard carries.
#' Located via the \code{TAXAID_ROOT} environment variable, or by walking up
#' from \code{getwd()} looking for \code{TaxaWizard/DESCRIPTION}. When
#' neither finds it (e.g. TaxaWizard installed standalone, or under
#' \code{R CMD check}), the Quick Start section is silently omitted -- never
#' an error.
#'
#' @seealso \code{\link{workflow_registry}}, \code{\link{workflow_check}}
#' @export
#' @examples
#' \dontrun{
#' workflow_export_prompts("taxaid_prompts")
#'
#' # The committed repository copy is regenerated with:
#' workflow_export_prompts("llm_prompts", overwrite = TRUE, placeholder_setup_report = TRUE)
#' }
workflow_export_prompts <- function(dir = "taxaid_prompts", overwrite = FALSE,
                                     placeholder_setup_report = FALSE) {
  if (!is.character(dir) || length(dir) != 1L || is.na(dir) || !nzchar(dir)) {
    stop("workflow_export_prompts: 'dir' must be a single non-empty path.", call. = FALSE)
  }

  dir.create(file.path(dir, "tasks"), recursive = TRUE, showWarnings = FALSE)

  registry <- workflow_registry()
  graph <- .load_graph()
  requirements <- .load_requirements()

  written <- character(0)
  w <- function(rel_path, text) {
    full <- file.path(dir, rel_path)
    if (file.exists(full) && !isTRUE(overwrite)) {
      stop(
        "workflow_export_prompts: '", full, "' already exists. ",
        "Pass overwrite = TRUE to replace it, or write to a different 'dir'.",
        call. = FALSE
      )
    }
    writeLines(text, full)
    written <<- c(written, full)
  }

  # --- P5 files: hand-written, copied verbatim ----------------------------
  start_here_src <- system.file("prompts", "pack", "START_HERE.md", package = "TaxaWizard")
  handoff_src <- system.file("prompts", "pack", "handoff_template.md", package = "TaxaWizard")
  if (!nzchar(start_here_src) || !nzchar(handoff_src)) {
    stop(
      "workflow_export_prompts: inst/prompts/pack/ files not found. Is TaxaWizard installed correctly?",
      call. = FALSE
    )
  }
  w("START_HERE.md", readLines(start_here_src, warn = FALSE))
  w("tasks/handoff_template.md", readLines(handoff_src, warn = FALSE))

  # --- Agentic-tool pointer files ------------------------------------------
  w("CLAUDE.md", .pack_agent_note())
  w("AGENTS.md", .pack_agent_note())

  # --- Generated ecosystem digest -------------------------------------------
  w("CONTEXT_TaxaID.md", .pack_context_taxaid_md(registry, graph, requirements))

  # --- Generated per-package digests ----------------------------------------
  for (pkg in names(registry)) {
    w(sprintf("CONTEXT_%s.md", pkg), .pack_context_package_md(pkg, registry[[pkg]]))
  }

  # --- Setup report -----------------------------------------------------------
  w("SETUP_REPORT.md", .pack_setup_report_md(placeholder_setup_report))

  # --- Phase task templates -------------------------------------------------
  for (phase in c("classify", "path_select", "parameterize", "error_fix")) {
    w(sprintf("tasks/%s.md", phase), .pack_render_task(phase, graph))
  }

  invisible(written)
}
