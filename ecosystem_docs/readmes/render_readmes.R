# render_readmes.R
# Convert all TaxaID ecosystem README.md files to PDF.
# Run once to install TinyTeX if needed; subsequent runs are fast.

library(tinytex)
library(rmarkdown)

# Point rmarkdown to RStudio's bundled pandoc
Sys.setenv(RSTUDIO_PANDOC = "/Applications/RStudio.app/Contents/Resources/app/quarto/bin/tools/aarch64")

# Install TinyTeX if not present
if (!tinytex::is_tinytex()) {
  message("Installing TinyTeX (one-time, ~5 min)...")
  tinytex::install_tinytex()
}

out_dir <- "/Users/lafferty/My Drive/Rscripts/projects/TaxaID/ecosystem_docs/readmes"

readmes <- list(
  TaxaID       = "/Users/lafferty/My Drive/Rscripts/projects/TaxaID/README.md",
  TaxaTools    = "/Users/lafferty/My Drive/Rscripts/projects/TaxaID/TaxaTools/README.md",
  TaxaFetch    = "/Users/lafferty/My Drive/Rscripts/projects/TaxaID/TaxaFetch/README.md",
  TaxaHabitat  = "/Users/lafferty/My Drive/Rscripts/projects/TaxaID/TaxaHabitat/README.md",
  TaxaMatch    = "/Users/lafferty/My Drive/Rscripts/projects/TaxaID/TaxaMatch/README.md",
  TaxaLikely   = "/Users/lafferty/My Drive/Rscripts/projects/TaxaID/TaxaLikely/README.md",
  TaxaExpect   = "/Users/lafferty/My Drive/Rscripts/projects/TaxaID/TaxaExpect/README.md",
  TaxaAssign   = "/Users/lafferty/My Drive/Rscripts/projects/TaxaID/TaxaAssign/README.md",
  TaxaFlag     = "/Users/lafferty/My Drive/Rscripts/projects/TaxaID/TaxaFlag/README.md",
  TaxaWizard   = "/Users/lafferty/My Drive/Rscripts/projects/TaxaID/TaxaWizard/README.md"
)

tmp_dir <- tempdir()

for (pkg in names(readmes)) {
  src <- readmes[[pkg]]
  out <- file.path(out_dir, paste0(pkg, "_README.pdf"))
  if (!file.exists(src)) {
    message("Skipping ", pkg, " — README.md not found")
    next
  }

  # Read and strip badge/image lines that LaTeX cannot fetch
  lines <- readLines(src, warn = FALSE)
  lines <- lines[!grepl("img\\.shields\\.io|badge/ORCID|\\[!\\[", lines)]

  # Write cleaned markdown to a temp file
  tmp_md <- file.path(tmp_dir, paste0(pkg, "_README_clean.md"))
  writeLines(lines, tmp_md)

  message("Rendering ", pkg, "...")
  rmarkdown::render(
    input         = tmp_md,
    output_format = pdf_document(
      latex_engine    = "xelatex",
      toc             = FALSE,
      number_sections = FALSE
    ),
    output_file = out,
    quiet       = TRUE
  )
  message("  -> ", basename(out))
}

message("\nDone. PDFs written to:\n  ", out_dir)
