# Extracted from test-fetch-cache-before-count.R:193

# setup ------------------------------------------------------------------------
library(testthat)
test_env <- simulate_test_env(package = "TaxaLikely", path = "..")
attach(test_env, warn.conflicts = FALSE)

# prequel ----------------------------------------------------------------------
write_cached_taxon <- function(cache_dir, taxon, accs,
                               sel_params = TaxaLikely:::.sel_params(
                                 NULL, NULL,
                                 paste0(
                                   "uncultured|environmental|predicted|",
                                   "vector|synthetic|unverified"
                                 )
                               )) {
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  # acc_version = accs (not left absent): these tests are about the
  # cache-before-count short-circuit and the per-accession FASTA store, not
  # about .fasta_cache_keys()'s unversioned-row handling -- a meta object
  # with no acc_version column at all would make every FASTA key
  # uncacheable (see test-fetch-fasta-versioned-key.R for that behavior on
  # its own terms) and silently break the "not re-downloaded" assertions
  # below.
  meta <- data.frame(
    taxid = seq_along(accs), acc = accs, acc_version = accs,
    title = paste(taxon, "12S ribosomal RNA gene"),
    slen = 400L, organism = paste(taxon, "sp."),
    create_date = "2026/08/29", in_barcode_range = TRUE,
    family = paste0(taxon, "idae"), genus = taxon,
    species = paste(taxon, "sp."), stringsAsFactors = FALSE
  )
  if (!is.null(sel_params)) attr(meta, "sel_params") <- sel_params
  f <- file.path(cache_dir, sprintf(
    "%s_12S_l100_5000_d_rk-family-genus-species_meta.rds", taxon
  ))
  saveRDS(meta, f)
  f
}
fake_fasta <- function(accs) {
  paste(sprintf(">%s Fake\nACGTACGTACGTACGTACGT", accs), collapse = "\n")
}

# test -------------------------------------------------------------------------
skip_if_not_installed("rentrez")
cache_dir <- tempfile("tl_p2_")
write_cached_taxon(cache_dir, "Sebastes", c("AB000001.1", "AB000002.1"))
fetched <- list()
testthat::local_mocked_bindings(
    entrez_search = function(db, term, retmax, ...) list(count = "0"),
    entrez_fetch = function(db, id, rettype, retmode, ...) {
      fetched[[length(fetched) + 1L]] <<- id
      fake_fasta(id)
    },
    .package = "rentrez"
  )
args <- list(
    taxa = "Sebastes", barcode_term = "12S",
    min_len = 100L, max_len = 5000L, cache_dir = cache_dir
  )
first <- suppressMessages(do.call(fetch_ncbi_reference_sequences, args))
n_after_first <- length(fetched)
second <- suppressMessages(do.call(fetch_ncbi_reference_sequences, args))
expect_gt(n_after_first, 0L)
