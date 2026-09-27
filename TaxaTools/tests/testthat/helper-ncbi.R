# Same reasoning as skip_if_verifier_down(): skip_if_offline() only checks
# general connectivity, and a runner can have internet while NCBI E-utilities
# are down, throttling, or too slow, which shows up as a name the NCBI path
# cannot find rather than as a network error. Any test that reaches NCBI
# (verify_taxon_names(backbone_id = 4), resolve_ncbi_taxid()) should call
# this in addition to skip_if_offline(). The probe is one esearch for a name
# NCBI has held for decades; anything but a 2xx with a count is "down".
skip_if_ncbi_down <- function() {
  testthat::skip_if_offline()
  reachable <- tryCatch(
    {
      resp <- httr2::request(
        "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi"
      ) |>
        httr2::req_url_query(db = "taxonomy", term = "Homo sapiens[Scientific Name]", retmode = "json") |>
        httr2::req_timeout(10) |>
        httr2::req_error(is_error = function(r) FALSE) |>
        httr2::req_perform()
      httr2::resp_status(resp) < 300 &&
        grepl("\"count\":\"[1-9]", httr2::resp_body_string(resp))
    },
    error = function(e) FALSE
  )
  if (!reachable) {
    testthat::skip("NCBI E-utilities are unreachable or not answering from this runner")
  }
}
