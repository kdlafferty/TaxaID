# render_readmes.R
# Rebuild the rendered documentation for the TaxaID ecosystem:
#   * ten package README.md files -> ecosystem_docs/readmes/<Pkg>_README.pdf
#   * the root README.md          -> README.html
# so the two can never drift apart.
#
# Run once to install TinyTeX if needed; subsequent runs are fast.
#
# Each README is rendered FROM ITS OWN PACKAGE DIRECTORY, so relative figure
# paths (the `man/figures/*` convention) resolve. Each render is wrapped in
# tryCatch(), so one failure cannot abort the rest, and the script ends with a
# PASS/FAIL table of output mtimes and stop()s if anything failed.

library(tinytex)
library(rmarkdown)

project_root <- "/Users/lafferty/My Drive/Rscripts/projects/TaxaID"
out_dir      <- file.path(project_root, "ecosystem_docs", "readmes")

# Point rmarkdown at RStudio's bundled pandoc, but only if nothing else has
# already supplied one -- on machines where pandoc is on the path, or
# RSTUDIO_PANDOC is set by the session, leave that alone.
rstudio_pandoc <- "/Applications/RStudio.app/Contents/Resources/app/quarto/bin/tools/aarch64"
if (!nzchar(Sys.getenv("RSTUDIO_PANDOC")) && dir.exists(rstudio_pandoc)) {
  Sys.setenv(RSTUDIO_PANDOC = rstudio_pandoc)
}

# Install TinyTeX if not present
if (!tinytex::is_tinytex()) {
  message("Installing TinyTeX (one-time, ~5 min)...")
  tinytex::install_tinytex()
}

# Packages in dependency order; "TaxaID" is the root README.
pkgs <- c("TaxaID", "TaxaTools", "TaxaFetch", "TaxaHabitat", "TaxaMatch",
          "TaxaLikely", "TaxaExpect", "TaxaAssign", "TaxaFlag", "TaxaWizard")

pkg_dir <- function(pkg) {
  if (identical(pkg, "TaxaID")) project_root else file.path(project_root, pkg)
}

readmes <- setNames(file.path(vapply(pkgs, pkg_dir, character(1)), "README.md"),
                    pkgs)

# ---------------------------------------------------------------------------
# Result accumulator
# ---------------------------------------------------------------------------

results <- list()

record <- function(target, status, path = NA_character_, note = "") {
  results[[length(results) + 1L]] <<- data.frame(
    target = target,
    status = status,
    mtime  = if (!is.na(path) && file.exists(path)) {
      format(file.mtime(path), "%Y-%m-%d %H:%M:%S")
    } else NA_character_,
    size_kb = if (!is.na(path) && file.exists(path)) {
      round(file.size(path) / 1024)
    } else NA_real_,
    note = note,
    stringsAsFactors = FALSE
  )
}

# ---------------------------------------------------------------------------
# One README -> PDF
# ---------------------------------------------------------------------------
# The cleaned markdown is written INTO the package directory (as a render_tmp_*
# file that is removed afterwards) and the PDF is built there too, so that
# pandoc and xelatex both run with the package as the working directory and
# relative `man/figures/*` paths resolve. The finished PDF is then copied to
# out_dir. The temp names must NOT start with "." -- TeX's openout_any = p
# refuses to write dot-files, so a dot-prefixed job name fails at \begin{document}.

render_one_pdf <- function(pkg, src, out) {
  dir <- dirname(src)

  # Strip badge/image lines that LaTeX cannot fetch (shields.io etc.)
  lines <- readLines(src, warn = FALSE)
  lines <- lines[!grepl("img\\.shields\\.io|badge/ORCID|\\[!\\[", lines)]

  tmp_md  <- file.path(dir, sprintf("render_tmp_%s_README.md", pkg))
  tmp_pdf <- file.path(dir, sprintf("render_tmp_%s_README.pdf", pkg))
  on.exit(unlink(c(tmp_md, tmp_pdf,
                   sub("\\.md$", ".tex", tmp_md),
                   sub("\\.md$", ".log", tmp_md),
                   sub("\\.md$", "_files", tmp_md)),
                 recursive = TRUE), add = TRUE)

  writeLines(lines, tmp_md)

  built <- rmarkdown::render(
    input         = tmp_md,
    output_format = pdf_document(
      latex_engine    = "xelatex",
      toc             = FALSE,
      number_sections = FALSE
    ),
    output_file   = basename(tmp_pdf),
    output_dir    = dir,
    knit_root_dir = dir,
    quiet         = TRUE
  )

  if (!file.exists(built)) {
    stop("render() returned without producing ", built)
  }
  if (!file.copy(built, out, overwrite = TRUE)) {
    stop("could not copy ", built, " to ", out)
  }
  invisible(out)
}

message("Rendering ", length(readmes), " README PDFs...")

for (pkg in names(readmes)) {
  src <- readmes[[pkg]]
  out <- file.path(out_dir, paste0(pkg, "_README.pdf"))

  if (!file.exists(src)) {
    message("  ", pkg, ": SKIP (README.md not found)")
    record(paste0(pkg, "_README.pdf"), "FAIL", out, "README.md not found")
    next
  }

  message("  ", pkg, " ...")
  ok <- tryCatch({
    render_one_pdf(pkg, src, out)
    TRUE
  }, error = function(e) {
    message("    FAILED: ", conditionMessage(e))
    record(paste0(pkg, "_README.pdf"), "FAIL", out,
           gsub("[\r\n]+", " ", conditionMessage(e)))
    FALSE
  })

  if (isTRUE(ok)) record(paste0(pkg, "_README.pdf"), "PASS", out)
}

# ---------------------------------------------------------------------------
# Root README.md -> README.html
# ---------------------------------------------------------------------------
# README.html is untracked by git (.gitignore), so a bad overwrite is not
# recoverable -- back it up first, then sanity-check the rebuild against the
# backup so a silent drop of the mermaid blocks or the tables is caught here.

# Local (non-URL) images the source references, from both markdown and raw-HTML
# image syntax. Used to confirm each one actually got embedded in the output.
.local_images <- function(md_path) {
  txt  <- paste(readLines(md_path, warn = FALSE), collapse = "\n")
  hits <- c(
    regmatches(txt, gregexpr('(?<=<img src=")[^"]+', txt, perl = TRUE))[[1]],
    regmatches(txt, gregexpr('(?<=!\\[)[^]]*\\]\\([^)]+', txt, perl = TRUE))[[1]]
  )
  hits <- sub(".*\\(", "", hits)
  hits <- trimws(sub(" +\"[^\"]*\"$", "", hits))       # strip a markdown title
  unique(hits[nzchar(hits) & !grepl("^(https?:|data:|//)", hits)])
}

count_in_file <- function(path, pattern) {
  if (!file.exists(path)) return(NA_integer_)
  sum(vapply(readLines(path, warn = FALSE),
             function(l) lengths(regmatches(l, gregexpr(pattern, l, perl = TRUE))),
             integer(1)))
}

html_src <- file.path(project_root, "README.md")
html_out <- file.path(project_root, "README.html")

message("Rendering README.html ...")

backup <- NULL

ok <- tryCatch({
  if (!file.exists(html_src)) stop("root README.md not found")

  before <- c(mermaid = count_in_file(html_out, 'class="mermaid"'),
              table   = count_in_file(html_out, "<table"))

  if (file.exists(html_out)) {
    backup <- paste0(html_out, ".bak_pre_render_", format(Sys.time(), "%Y%m%d_%H%M%S"))
    if (!file.copy(html_out, backup, overwrite = FALSE)) {
      stop("could not back up README.html to ", basename(backup))
    }
    message("  backed up existing README.html -> ", basename(backup))
  }

  rmarkdown::render(
    input         = html_src,
    output_format = "html_document",
    output_file   = basename(html_out),
    output_dir    = dirname(html_out),
    knit_root_dir = dirname(html_out),
    quiet         = TRUE
  )

  after <- c(mermaid = count_in_file(html_out, 'class="mermaid"'),
             table   = count_in_file(html_out, "<table"))
  html_txt <- paste(readLines(html_out, warn = FALSE), collapse = "\n")

  # Expected mermaid blocks come from the source, not from a magic number.
  src_mermaid <- count_in_file(html_src, "^``` *\\{?mermaid")

  problems <- character(0)
  # A local image pandoc cannot find is only a WARNING -- printed by the pandoc
  # subprocess, so it never reaches R and the render still "succeeds" with the
  # asset missing. The signal in the file itself is exact: html_document is
  # self-contained, so an embedded image becomes src="data:image/...", while one
  # that failed to load keeps its original relative path.
  unembedded <- .local_images(html_src)
  unembedded <- unembedded[vapply(
    unembedded,
    function(p) grepl(sprintf('src="%s"', p), html_txt, fixed = TRUE),
    logical(1))]
  if (length(unembedded)) {
    problems <- c(problems, sprintf("%d local image(s) failed to embed: %s",
                                    length(unembedded),
                                    paste(unembedded, collapse = ", ")))
  }
  if (!is.na(src_mermaid) && after[["mermaid"]] != src_mermaid) {
    problems <- c(problems, sprintf("mermaid blocks %d in HTML vs %d in README.md",
                                    after[["mermaid"]], src_mermaid))
  }
  for (what in c("mermaid", "table")) {
    if (!is.na(before[[what]]) && after[[what]] < before[[what]]) {
      problems <- c(problems, sprintf("%s count dropped %d -> %d vs previous build",
                                      what, before[[what]], after[[what]]))
    }
  }

  # html_document is self-contained, so the embedded images dominate the file
  # size -- a large shrink means an asset silently failed to embed (pandoc only
  # WARNS on "Could not fetch resource"), which the element counts cannot see.
  if (!is.null(backup) && file.exists(backup)) {
    shrink <- 1 - file.size(html_out) / file.size(backup)
    if (shrink > 0.2) {
      problems <- c(problems, sprintf("output shrank %.0f%% vs previous build (%.0f -> %.0f KB) -- an embedded asset may have failed to load",
                                      100 * shrink,
                                      file.size(backup) / 1024,
                                      file.size(html_out) / 1024))
    }
  }
  if (length(problems)) {
    # Put the good file back rather than leaving a suspect one in place.
    restored <- ""
    if (!is.null(backup) && file.exists(backup)) {
      file.copy(backup, html_out, overwrite = TRUE)
      message("  restored the previous README.html from ", basename(backup))
      restored <- "PREVIOUS RESTORED; "
    }
    stop(restored, paste(problems, collapse = "; "))
  }

  record("README.html", "PASS", html_out,
         sprintf("%d mermaid, %d tables", after[["mermaid"]], after[["table"]]))
  TRUE
}, error = function(e) {
  message("    FAILED: ", conditionMessage(e))
  record("README.html", "FAIL", html_out, gsub("[\r\n]+", " ", conditionMessage(e)))
  FALSE
})

# ---------------------------------------------------------------------------
# llm_prompts/ -- the committed copy of TaxaWizard::workflow_export_prompts()
# ---------------------------------------------------------------------------
# Per ecosystem_docs/SPEC_taxawizard_derived_context_2026_09_18.md (P4,
# decision 4): the prompt pack is BOTH generated on demand AND committed as a
# rendered copy at the repository root, refreshed by this same script, with a
# test (TaxaWizard/tests/testthat/test-pack.R) that the two agree byte-for-
# byte. Loaded from the TaxaWizard SOURCE directory (devtools::load_all()),
# never the installed package, so this always reflects the code in the repo
# being rendered -- consistent with how the README PDFs above are rendered
# from source, not from an installed copy. placeholder_setup_report = TRUE
# because the committed copy isn't any one contributor's machine; a real
# SETUP_REPORT.md is only ever meaningful for the machine that generated it.

message("Regenerating llm_prompts/ (TaxaWizard::workflow_export_prompts())...")

llm_prompts_out <- file.path(project_root, "llm_prompts")

ok <- tryCatch({
  suppressMessages(devtools::load_all(file.path(project_root, "TaxaWizard"), quiet = TRUE))
  written <- TaxaWizard::workflow_export_prompts(
    llm_prompts_out,
    overwrite = TRUE,
    placeholder_setup_report = TRUE
  )
  record("llm_prompts/", "PASS", llm_prompts_out,
         sprintf("%d file(s) written", length(written)))
  TRUE
}, error = function(e) {
  message("    FAILED: ", conditionMessage(e))
  record("llm_prompts/", "FAIL", llm_prompts_out, gsub("[\r\n]+", " ", conditionMessage(e)))
  FALSE
})

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

summary_df <- do.call(rbind, results)

message("\n", strrep("-", 78))
message("Render summary (", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), ")")
message(strrep("-", 78))

fmt <- "%-26s %-5s %-19s %8s  %s"
message(sprintf(fmt, "target", "stat", "output mtime", "size KB", "note"))
for (i in seq_len(nrow(summary_df))) {
  r <- summary_df[i, ]
  message(sprintf(fmt,
                  r$target,
                  r$status,
                  ifelse(is.na(r$mtime), "-", r$mtime),
                  ifelse(is.na(r$size_kb), "-", format(r$size_kb)),
                  substr(r$note, 1, 60)))
}
message(strrep("-", 78))

n_fail <- sum(summary_df$status != "PASS")
message(sprintf("%d of %d targets rendered; %d failed.",
                sum(summary_df$status == "PASS"), nrow(summary_df), n_fail))
message("PDFs in: ", out_dir)

if (n_fail > 0) {
  stop(sprintf("%d target(s) failed to render -- see the summary above.", n_fail),
       call. = FALSE)
}
