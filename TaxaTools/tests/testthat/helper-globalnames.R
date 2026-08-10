# skip_if_offline() only checks general internet connectivity -- it does not
# catch the case (observed repeatedly in CI, see TaxaID/CLAUDE.md's Recent
# Breaking Changes / session notes) where the runner has internet but
# verifier.globalnames.org specifically is unreachable or too slow to
# establish a TCP connection. Any test that calls verify_taxon_names() with a
# path that reaches the real Global Names Verifier API (backbone_id != 4, or
# backbone_id = 4's fuzzy-fallback path) should call this in addition to
# skip_if_offline().
skip_if_verifier_down <- function() {
  testthat::skip_if_offline()
  reachable <- tryCatch({
    resp <- httr::HEAD("https://verifier.globalnames.org/api/v1/data_sources",
                        httr::timeout(5))
    httr::status_code(resp) < 500
  }, error = function(e) FALSE)
  if (!reachable) {
    testthat::skip("verifier.globalnames.org is unreachable from this runner")
  }
}
