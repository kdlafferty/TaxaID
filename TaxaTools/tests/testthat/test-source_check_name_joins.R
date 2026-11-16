# SOURCE CHECK (design section 7, phase 4): no match / %in% / join / merge on a taxon-name or lineage column anywhere in
# the nine packages' R/ code unless it is listed, with its verdict and reason, in fixtures/name_join_review.json. A NEW
# name join fails here until it is converted to taxon ids or reviewed and listed; a listed line that no longer exists
# fails too, so the list cannot go stale. Runs only in a source checkout of the repository (it reads the sibling
# packages' R/ files); skipped in an installed package.

.sc_root <- function() {
  r <- normalizePath(file.path(testthat::test_path(), "..", "..", ".."), mustWork = FALSE)
  if (dir.exists(file.path(r, "TaxaAssign", "R")) && dir.exists(file.path(r, "TaxaTools", "R"))) r else NA_character_
}
.sc_hits <- function(root) {
  pk <- c("TaxaTools", "TaxaFetch", "TaxaHabitat", "TaxaExpect", "TaxaMatch", "TaxaLikely", "TaxaAssign", "TaxaFlag", "TaxaWizard")
  cols <- "(taxon_name|species|genus|family|[a-z_]*_ncbi|matched_name|consensus_taxon|scientificName)"
  pat <- paste0("(match\\(|%in%|_join\\(|merge\\().*\\b", cols, "\\b|by *= *[^\\n]*\"", cols, "\"")
  out <- list()
  for (p in pk) for (f in list.files(file.path(root, p, "R"), "\\.R$", full.names = TRUE)) {
    l <- readLines(f, warn = FALSE); i <- grep(pat, l, perl = TRUE); i <- i[!grepl("^\\s*#", l[i])]
    if (length(i)) out[[length(out) + 1L]] <- data.frame(file = paste0(p, "/R/", basename(f)), code = trimws(l[i]), stringsAsFactors = FALSE)
  }
  do.call(rbind, out)
}

test_that("every name join in the nine packages is converted or reviewed, and the review list is current", {
  root <- .sc_root(); skip_if(is.na(root), "not a source checkout of the TaxaID repository")
  rv <- jsonlite::fromJSON(testthat::test_path("fixtures", "name_join_review.json"))
  expect_true(all(nzchar(rv$verdict) & !is.na(rv$verdict) & nzchar(rv$reason) & !is.na(rv$reason)))
  expect_true(all(rv$verdict %in% c("converted", "converted_upstream", "registry_internal", "resolver", "reviewed", "model",
                                    "display_filler", "fp", "within")))
  h <- .sc_hits(root)
  kh <- paste(h$file, h$code, sep = "\r"); kr <- paste(rv$file, rv$code, sep = "\r")
  new <- h[!kh %in% kr, , drop = FALSE]
  expect(nrow(new) == 0L, paste0("name join(s) not converted and not reviewed (add to fixtures/name_join_review.json with a verdict, or join on taxon_id):\n",
                                 paste(utils::head(sprintf("%s: %s", new$file, new$code), 20), collapse = "\n")))
  stale <- rv[!kr %in% kh, , drop = FALSE]
  expect(nrow(stale) == 0L, paste0("review list entries that no longer exist in the code:\n",
                                   paste(utils::head(sprintf("%s: %s", stale$file, stale$code), 20), collapse = "\n")))
})

test_that("GUARD CAN FAIL: the source check flags a planted name join", {
  root <- .sc_root(); skip_if(is.na(root), "not a source checkout of the TaxaID repository")
  tmp <- tempfile("sc_"); dir.create(file.path(tmp, "TaxaAssign", "R"), recursive = TRUE)
  writeLines("x <- dplyr::left_join(a, b, by = \"taxon_name\")", file.path(tmp, "TaxaAssign", "R", "planted.R"))
  h <- .sc_hits(tmp)
  expect_identical(nrow(h), 1L)
  rv <- jsonlite::fromJSON(testthat::test_path("fixtures", "name_join_review.json"))
  expect_false(paste(h$file, h$code, sep = "\r") %in% paste(rv$file, rv$code, sep = "\r"))
})
