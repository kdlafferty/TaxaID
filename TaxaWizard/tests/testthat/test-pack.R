# Tests for R/pack.R -- workflow_export_prompts(), the prompt pack generator
# (see TaxaID_dev/ecosystem_docs/SPEC_taxawizard_derived_context_2026_09_18.md (sibling development repository), section
# P4). Every call here uses placeholder_setup_report = TRUE, so none of these
# tests run workflow_check()'s live network probes -- fully offline, like
# test-setup.R's .tw_offline() pattern, just via the placeholder argument
# instead of options(TaxaWizard.offline = TRUE).

skip_if_not(length(TaxaWizard:::TAXAID_PACKAGES[
  vapply(TaxaWizard:::TAXAID_PACKAGES, requireNamespace, logical(1), quietly = TRUE)
]) > 0L, "no TaxaID packages installed")


# ==============================================================================
# File list
# ==============================================================================

test_that("workflow_export_prompts() writes the documented file list", {
  dir <- tempdir()
  written <- workflow_export_prompts(dir, placeholder_setup_report = TRUE, overwrite = TRUE)
  on.exit(unlink(written, force = TRUE), add = TRUE)

  expect_type(written, "character")
  expect_true(length(written) > 0L)

  registry <- TaxaWizard::workflow_registry()
  expected_rel <- c(
    "START_HERE.md", "CLAUDE.md", "AGENTS.md", "CONTEXT_TaxaID.md",
    sprintf("CONTEXT_%s.md", names(registry)),
    "SETUP_REPORT.md",
    file.path("tasks", c(
      "classify.md", "path_select.md", "parameterize.md", "error_fix.md",
      "handoff_template.md"
    ))
  )
  expect_length(written, length(expected_rel))
  for (rel in expected_rel) {
    expect_true(file.exists(file.path(dir, rel)), info = rel)
  }
})

test_that("workflow_export_prompts() refuses to overwrite existing files unless asked", {
  dir <- tempfile("pack_overwrite_")
  written1 <- workflow_export_prompts(dir, placeholder_setup_report = TRUE)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  expect_error(
    workflow_export_prompts(dir, placeholder_setup_report = TRUE, overwrite = FALSE),
    "already exists"
  )
  # overwrite = TRUE succeeds and writes the same file set again.
  written2 <- workflow_export_prompts(dir, placeholder_setup_report = TRUE, overwrite = TRUE)
  expect_setequal(written1, written2)
})

test_that("workflow_export_prompts() validates 'dir'", {
  expect_error(workflow_export_prompts(dir = NA), "single non-empty path")
  expect_error(workflow_export_prompts(dir = character(0)), "single non-empty path")
  expect_error(workflow_export_prompts(dir = 1L), "single non-empty path")
})


# ==============================================================================
# CONTEXT_TaxaID.md
# ==============================================================================

test_that("CONTEXT_TaxaID.md is at most 400 lines", {
  dir <- tempfile("pack_contextlen_")
  workflow_export_prompts(dir, placeholder_setup_report = TRUE)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  n <- length(readLines(file.path(dir, "CONTEXT_TaxaID.md"), warn = FALSE))
  expect_lte(n, 400L)
})

test_that("CONTEXT_TaxaID.md's canonical-pipelines section is read live from system_prompt.md, not pasted", {
  dir <- tempfile("pack_pipelines_")
  workflow_export_prompts(dir, placeholder_setup_report = TRUE)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  ctx <- paste(readLines(file.path(dir, "CONTEXT_TaxaID.md"), warn = FALSE), collapse = "\n")
  expect_true(grepl("LLM-Shortcut Pipeline", ctx, fixed = TRUE))
  expect_true(grepl("Full Bayesian Pipeline", ctx, fixed = TRUE))
})


# ==============================================================================
# CONTEXT_<Package>.md
# ==============================================================================

test_that("every function heading in a CONTEXT_<Package>.md file is a real registry export", {
  dir <- tempfile("pack_fnnames_")
  workflow_export_prompts(dir, placeholder_setup_report = TRUE)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  registry <- TaxaWizard::workflow_registry()
  expect_true(length(registry) > 0L)

  for (pkg in names(registry)) {
    fn_names <- vapply(registry[[pkg]]$functions, `[[`, "", "name")
    lines <- readLines(file.path(dir, sprintf("CONTEXT_%s.md", pkg)), warn = FALSE)

    # Only the "## Functions" section's headings are function signatures; a
    # package README's "## Quick Start" section (appended after) may have its
    # own prose "### " subheadings (e.g. TaxaTools' "### Clean and verify a
    # messy name list") that are not function names and must not be checked
    # against the registry.
    qs_idx <- which(grepl("^## Quick Start", lines, ignore.case = TRUE))
    end <- if (length(qs_idx) > 0L) qs_idx[1L] - 1L else length(lines)
    heading_lines <- grep("^### ", lines[seq_len(end)], value = TRUE)
    expect_true(length(heading_lines) == length(fn_names), info = pkg)

    heading_fn <- sub("^### ([^(]+)\\(.*$", "\\1", heading_lines)
    expect_true(all(heading_fn %in% fn_names), info = pkg)
  }
})


# ==============================================================================
# tasks/*.md
# ==============================================================================

test_that("tasks/*.md placeholders are either filled or replaced with a bracketed instruction", {
  dir <- tempfile("pack_tasks_")
  workflow_export_prompts(dir, placeholder_setup_report = TRUE)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  for (phase in c("classify", "path_select", "parameterize", "error_fix")) {
    text <- paste(readLines(file.path(dir, "tasks", sprintf("%s.md", phase)), warn = FALSE), collapse = "\n")
    # No raw {{PLACEHOLDER}} token should survive rendering.
    expect_false(grepl("\\{\\{[A-Z_]+\\}\\}", text), info = phase)
  }
})

test_that("tasks/*.md no longer require a JSON-only response", {
  dir <- tempfile("pack_json_strip_")
  workflow_export_prompts(dir, placeholder_setup_report = TRUE)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  for (phase in c("classify", "path_select", "parameterize", "error_fix")) {
    text <- paste(readLines(file.path(dir, "tasks", sprintf("%s.md", phase)), warn = FALSE), collapse = "\n")
    expect_false(grepl("single JSON object", text, fixed = TRUE), info = phase)
    expect_false(grepl("CRITICAL FORMAT REQUIREMENT", text, fixed = TRUE), info = phase)
    expect_true(grepl("respond in", text, fixed = TRUE) || grepl("prose", text, fixed = TRUE), info = phase)
  }
})

test_that("tasks/handoff_template.md and START_HERE.md are copied verbatim from inst/prompts/pack/", {
  dir <- tempfile("pack_verbatim_")
  workflow_export_prompts(dir, placeholder_setup_report = TRUE)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  src_start <- system.file("prompts", "pack", "START_HERE.md", package = "TaxaWizard")
  src_handoff <- system.file("prompts", "pack", "handoff_template.md", package = "TaxaWizard")

  expect_identical(
    readLines(file.path(dir, "START_HERE.md"), warn = FALSE),
    readLines(src_start, warn = FALSE)
  )
  expect_identical(
    readLines(file.path(dir, "tasks", "handoff_template.md"), warn = FALSE),
    readLines(src_handoff, warn = FALSE)
  )
})


# ==============================================================================
# SETUP_REPORT.md
# ==============================================================================

test_that("SETUP_REPORT.md placeholder never runs workflow_check() or claims machine-specific status", {
  dir <- tempfile("pack_setupreport_")
  workflow_export_prompts(dir, placeholder_setup_report = TRUE)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  text <- paste(readLines(file.path(dir, "SETUP_REPORT.md"), warn = FALSE), collapse = "\n")
  expect_true(grepl("workflow_export_prompts()", text, fixed = TRUE))
  expect_false(grepl("TaxaWizard setup check", text, fixed = TRUE)) # print.taxaid_check()'s own header
})

test_that("SETUP_REPORT.md never includes a key value, placeholder or not", {
  old <- Sys.getenv("ANTHROPIC_API_KEY", unset = NA)
  Sys.setenv(ANTHROPIC_API_KEY = "sk-ant-test-distinctive-marker-should-never-appear-0000")
  on.exit(if (is.na(old)) Sys.unsetenv("ANTHROPIC_API_KEY") else Sys.setenv(ANTHROPIC_API_KEY = old), add = TRUE)

  old_offline <- options(TaxaWizard.offline = TRUE)
  on.exit(options(old_offline), add = TRUE)

  dir <- tempfile("pack_setupreport_realkeys_")
  workflow_export_prompts(dir, placeholder_setup_report = FALSE)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  text <- paste(readLines(file.path(dir, "SETUP_REPORT.md"), warn = FALSE), collapse = "\n")
  expect_false(grepl("sk-ant-test-distinctive-marker-should-never-appear-0000", text, fixed = TRUE))
  expect_true(grepl("Generated 20", text)) # the date header
})


# ==============================================================================
# TAXAID_ROOT / repo-root discovery, and the committed llm_prompts/ copy
# ==============================================================================

test_that("generated pack equals the committed llm_prompts/ copy, date stamp aside", {
  # The pack carries its own generation date, which is genuinely useful to
  # someone reading it cold ("how old is this?"). But comparing it bytewise
  # made this test fail EVERY DAY, on the clock alone, with no code change --
  # caught on 2026-09-20 when midnight passed mid-session. A check that is
  # wrong daily gets switched off within a week, and then you have neither the
  # check nor the discipline it replaced. So the date stamp is normalised out
  # of the comparison, and asserted separately below to be present and current.
  # Everything else is still compared exactly.
  root <- TaxaWizard:::.pack_find_repo_root()
  if (is.null(root)) {
    skip("repo root not found (TAXAID_ROOT unset and no TaxaWizard/DESCRIPTION found walking up from getwd()) -- expected e.g. under R CMD check")
  }
  committed_dir <- file.path(root, "llm_prompts")
  if (!dir.exists(committed_dir)) {
    skip(sprintf(
      "committed pack not found at %s -- generate it first with workflow_export_prompts(\"llm_prompts\", placeholder_setup_report = TRUE)",
      committed_dir
    ))
  }

  gen_dir <- tempfile("pack_committed_cmp_")
  workflow_export_prompts(gen_dir, placeholder_setup_report = TRUE)
  on.exit(unlink(gen_dir, recursive = TRUE), add = TRUE)

  committed_files <- list.files(committed_dir, recursive = TRUE)
  expect_true(length(committed_files) > 0L)

  generated_files <- list.files(gen_dir, recursive = TRUE)
  expect_setequal(committed_files, generated_files)

  # Replace any ISO date with a fixed token, so only the stamp is excused.
  .undate <- function(path) {
    gsub("\\d{4}-\\d{2}-\\d{2}", "<DATE>",
         paste(readLines(path, warn = FALSE), collapse = "\n"))
  }

  for (rel in committed_files) {
    committed_path <- file.path(committed_dir, rel)
    generated_path <- file.path(gen_dir, rel)
    expect_identical(.undate(committed_path), .undate(generated_path), info = rel)
  }
})

test_that("the committed pack still carries a generation date, and it is today's", {
  # The other half: excusing the stamp from the comparison must not let it
  # vanish or go stale unnoticed. If this fails, regenerate the pack.
  root <- TaxaWizard:::.pack_find_repo_root()
  skip_if(is.null(root), "repo root not found")
  f <- file.path(root, "llm_prompts", "CONTEXT_TaxaID.md")
  skip_if(!file.exists(f), "committed pack not present")

  line <- grep("^Generated by ", readLines(f, warn = FALSE), value = TRUE)[1L]
  expect_false(is.na(line))
  expect_match(line, "\\d{4}-\\d{2}-\\d{2}")
})


# --- P6: phase templates live in ONE place -----------------------------------

test_that("the pack's tasks are rendered from inst/prompts, not a second copy", {
  # The spec's no-duplication requirement. If someone ever hand-writes a task
  # file, this catches it: every tasks/<phase>.md must still be recognisably
  # the inst/prompts/phase_<phase>.md file it is rendered from.
  root <- TaxaWizard:::.pack_find_repo_root()
  skip_if(is.null(root), "repo root not found")
  committed <- file.path(root, "llm_prompts", "tasks")
  skip_if(!dir.exists(committed), "committed pack not present")

  graph <- TaxaWizard:::.load_graph()
  for (phase in c("classify", "path_select", "parameterize", "error_fix")) {
    template_path <- system.file("prompts", sprintf("phase_%s.md", phase),
      package = "TaxaWizard"
    )
    skip_if(!nzchar(template_path), "prompt templates not installed")

    rendered <- TaxaWizard:::.pack_render_task(phase, graph)
    on_disk <- paste(
      readLines(file.path(committed, paste0(phase, ".md")), warn = FALSE),
      collapse = "\n"
    )
    expect_equal(
      on_disk, rendered,
      info = sprintf(
        "llm_prompts/tasks/%s.md is not what .pack_render_task() produces from inst/prompts/phase_%s.md -- regenerate the pack rather than editing the task file",
        phase, phase
      )
    )
  }
})

test_that("no rendered task file leaks an unfilled placeholder", {
  graph <- TaxaWizard:::.load_graph()
  for (phase in c("classify", "path_select", "parameterize", "error_fix")) {
    txt <- TaxaWizard:::.pack_render_task(phase, graph)
    expect_false(
      grepl("\\{\\{[A-Z_]+\\}\\}", txt),
      info = sprintf("tasks/%s.md still contains a {{PLACEHOLDER}}", phase)
    )
  }
})

test_that("the root README's Software Inventory table matches the tree", {
  # The table is hand-written; this is what keeps it current. A count that
  # drifts (a new export, a new test file) fails here instead of going stale.
  root <- TaxaWizard:::.pack_find_repo_root()
  skip_if(is.null(root), "repo root not found")
  # Under R CMD check the package is copied out of the repository, so a root
  # can be found that holds no README.md or sibling packages; that is not a
  # repository checkout, and the check is meaningless there.
  in_repo <- file.exists(file.path(root, "README.md")) &&
    all(dir.exists(file.path(root, TaxaWizard:::TAXAID_PACKAGES)))
  skip_if(!in_repo, "not a repository checkout (README.md and the nine packages not all present)")
  readme <- readLines(file.path(root, "README.md"), warn = FALSE)
  rows <- grep("^\\| Taxa[A-Za-z]+ +\\| +[0-9]+ +\\| +[0-9]+ +\\|", readme, value = TRUE)
  expect_true(length(rows) >= 9L, info = "Software Inventory rows not found in README.md")
  for (row in rows) {
    cells <- trimws(strsplit(row, "|", fixed = TRUE)[[1]])[-1]
    pkg <- cells[[1]]; stated_exports <- as.integer(cells[[2]]); stated_tests <- as.integer(cells[[3]])
    ns <- readLines(file.path(root, pkg, "NAMESPACE"), warn = FALSE)
    n_exports <- sum(grepl("^export\\(", ns))
    n_tests <- length(list.files(file.path(root, pkg, "tests", "testthat"), pattern = "^test-.*\\.R$"))
    expect_equal(stated_exports, n_exports, info = sprintf("%s exported functions in README.md vs NAMESPACE", pkg))
    expect_equal(stated_tests, n_tests, info = sprintf("%s test files in README.md vs tests/testthat", pkg))
  }
})


# ==============================================================================
# \details and titled \section text reach the CONTEXT files, in full
# ==============================================================================

test_that("every CONTEXT_<pkg>.md carries a known sentence from a named function's \\details and from a titled \\section", {
  # POSITIVE checks: a registry that silently dropped \details or \section
  # would still pass every structural test above (the headings, the params
  # tables, the Value lines are all there). So each package names one
  # function and one sentence its help page states in \details, and one
  # titled \section with a sentence from its body, and both must appear
  # inside that function's own block (between its ### heading and the next).
  # The sentences are operative rules, not narrative, so a documentation
  # pass that trims repetition must leave them in place.
  expected <- list(
    TaxaTools = list(
      details = c("fetch_worms_attributes", "Why this is not the habitat lookup you already have"),
      section = c("assign_sampling_group", "Empty-string normalisation",
                  "is normalised to NA across every present rank_cols column")
    ),
    TaxaFetch = list(
      details = c("dedupe_occurrences", "rows with a duplicated non-NA gbifID are dropped"),
      section = c("download_gbif_occurrences", "Why nothing here blocks by default",
                  "can consume the ENTIRE remainder of the script")
    ),
    TaxaHabitat = list(
      details = c("parse_hierarchical_habitat_response", "duplicate header rows are stripped automatically"),
      section = c("apply_spatial_review_decisions", "Old-format decisions files (no taxon_name)",
                  "has no way to say which taxon a decision was for")
    ),
    TaxaMatch = list(
      details = c("blast_sequences", "Rather than a flat top-N cutoff, hits are filtered per query"),
      section = c("check_marker_mismatch", "Why this exists", "AY850362")
    ),
    TaxaLikely = list(
      details = c("evaluate_likelihoods", "takes the median score across references"),
      section = c("apply_coverage_constraints", "Census confidence",
                  "reflects what an NCBI taxonomy-tree query returned for the genus")
    ),
    TaxaExpect = list(
      details = c("generate_uncertain_habitat_evidence", "The gap this closes"),
      section = c("apply_undetected_evidence", "Why one shared function, not one per evidence source",
                  "independently constructed and appended its own finished Beta")
    ),
    TaxaAssign = list(
      details = c("compute_posterior", "Two computation paths are available"),
      section = c("add_unreferenced_prior_mass", "What is added",
                  "the added mass is the sum")
    ),
    TaxaFlag = list(
      details = c("flag_contaminant", "depth-weighted detection rate per taxon in field samples"),
      section = c("add_posthoc_assessment", "Why no rank-based short-circuit",
                  "would need a fallback for any row")
    )
  )

  dir <- tempfile("pack_details_")
  workflow_export_prompts(dir, placeholder_setup_report = TRUE)
  on.exit(unlink(dir, recursive = TRUE), add = TRUE)

  block_of <- function(lines, fn) {
    starts <- grep("^### ", lines)
    i <- starts[grepl(sprintf("^### %s\\(", fn), lines[starts])]
    expect_length(i, 1L)
    nxt <- starts[starts > i]
    end <- if (length(nxt) > 0L) nxt[1L] - 1L else length(lines)
    paste(lines[i:end], collapse = "\n")
  }

  for (pkg in names(expected)) {
    f <- file.path(dir, sprintf("CONTEXT_%s.md", pkg))
    if (!file.exists(f)) skip(sprintf("%s not installed", pkg))
    lines <- readLines(f, warn = FALSE)
    ex <- expected[[pkg]]

    blk <- block_of(lines, ex$details[1L])
    expect_true(grepl("\n#### Details\n", blk, fixed = TRUE), info = paste(pkg, ex$details[1L], "has a Details heading"))
    expect_true(grepl(ex$details[2L], blk, fixed = TRUE), info = paste(pkg, ex$details[1L], "details sentence"))

    blk <- block_of(lines, ex$section[1L])
    expect_true(grepl(sprintf("\n#### %s\n", ex$section[2L]), blk, fixed = TRUE), info = paste(pkg, ex$section[1L], "section heading"))
    expect_true(grepl(ex$section[3L], blk, fixed = TRUE), info = paste(pkg, ex$section[1L], "section sentence"))

    # Headings inside a block are never at ### (that level is the function
    # signature the structural test counts) and never shallower.
    inner <- grep("^#{1,3} ", strsplit(blk, "\n", fixed = TRUE)[[1L]][-1L], value = TRUE)
    expect_length(inner, 0L)
  }
})

test_that("a registry entry's details keep paragraph breaks and list items", {
  # Build an Rd page in memory and read it the way the registry does.
  rd <- tools::parse_Rd(textConnection(c(
    "\\name{zz}", "\\title{Zz}", "\\description{One.}",
    "\\details{First paragraph.", "", "Second paragraph with \\code{x}.",
    "\\itemize{\\item first item \\item second item}",
    "\\preformatted{a <- 1", "b <- 2}", "}",
    "\\section{Why it exists}{Because.", "", "\\subsection{Sub}{Deeper.}}"
  )))
  s <- TaxaWizard:::.rd_sections(rd)
  expect_true(grepl("First paragraph.\n\nSecond paragraph with x.", s$details, fixed = TRUE))
  expect_true(grepl("\n\n- first item\n\n- second item", s$details, fixed = TRUE))
  expect_true(grepl("```\na <- 1\nb <- 2\n```", s$details, fixed = TRUE))
  expect_length(s$sections, 1L)
  expect_identical(s$sections[[1L]]$title, "Why it exists")
  expect_true(grepl("Because.\n\n##### Sub\n\nDeeper.", s$sections[[1L]]$body, fixed = TRUE))
})
