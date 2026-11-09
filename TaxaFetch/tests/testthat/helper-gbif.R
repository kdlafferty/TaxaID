# Why skip_if_offline() is not enough for a live GBIF test, and why this helper
# exists.
#
# skip_if_offline() calls skip_on_cran() first and then checks general
# connectivity. CI sets NOT_CRAN = "true", so skip_on_cran() does NOT fire
# there, and a GitHub runner has working internet, so the connectivity check
# passes too. A "live API" test therefore runs for real on every CI build and
# fails whenever GBIF is slow, throttling, or simply answers differently --
# a failure about someone else's service, on a build that is supposed to be
# about this code.
#
# The workflow already sets TAXAID_SKIP_LIVE = "1" for exactly this purpose,
# and TaxaTools' helpers honour it (helper-ncbi.R, helper-worms.R,
# helper-globalnames.R). TaxaFetch did not, because until its tests/testthat.R
# driver existed none of its tests ran under R CMD check at all, so nothing
# ever surfaced it.
skip_if_live_off <- function() {
  if (nzchar(Sys.getenv("TAXAID_SKIP_LIVE"))) {
    testthat::skip("live-service tests are off (TAXAID_SKIP_LIVE is set)")
  }
  testthat::skip_if_offline()
}
