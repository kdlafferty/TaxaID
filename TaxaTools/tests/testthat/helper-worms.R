# Same reasoning as skip_if_verifier_down(): skip_if_offline() only checks
# general connectivity, and a runner can have internet while
# marinespecies.org specifically is down, throttling, or too slow. Any test
# that reaches the real WoRMS REST API should call this.
skip_if_worms_down <- function() {
  testthat::skip_on_cran()
  testthat::skip_if_offline()
  reachable <- tryCatch(
    {
      resp <- httr2::request(
        "https://www.marinespecies.org/rest/AphiaIDByName/Sebastes?marine_only=false"
      ) |>
        httr2::req_timeout(10) |>
        httr2::req_error(is_error = function(r) FALSE) |>
        httr2::req_perform()
      httr2::resp_status(resp) < 500
    },
    error = function(e) FALSE
  )
  if (!reachable) {
    testthat::skip("marinespecies.org is unreachable from this runner")
  }
}

# Build one WoRMS-shaped AphiaRecord. The flags are passed through verbatim so
# a test can hand in NULL, which is what the live API sends for "not assessed"
# and the distinction .worms_flag() must preserve.
worms_rec <- function(marine = 1, brackish = 0, freshwater = 0, terrestrial = 0,
                      aphia_id = 1L, status = "accepted", match_type = "exact",
                      valid_name = "Valid name", rank = "Species",
                      kingdom = "Animalia") {
  list(
    AphiaID = aphia_id, valid_AphiaID = aphia_id, valid_name = valid_name,
    status = status, rank = rank, match_type = match_type,
    isMarine = marine, isBrackish = brackish,
    isFreshwater = freshwater, isTerrestrial = terrestrial,
    kingdom = kingdom, phylum = "Chordata", class = "Teleostei",
    order = "Ord", family = "Fam", genus = "Gen"
  )
}

# Run `code` with TaxaTools:::.worms_get() replaced, so the batching, caching,
# failure and extras paths are testable without the network.
with_fake_worms <- function(fn, code) {
  ns <- asNamespace("TaxaTools")
  orig <- get(".worms_get", envir = ns)
  unlockBinding(".worms_get", ns)
  assign(".worms_get", fn, envir = ns)
  on.exit(
    {
      assign(".worms_get", orig, envir = ns)
      lockBinding(".worms_get", ns)
    },
    add = TRUE
  )
  force(code)
}

# A fake .worms_get() for the name-match endpoint that honours the endpoint's
# positional contract: one answer per name in the URL. Writing it any other way
# trips the length-mismatch guard (which is the point of that guard).
fake_match <- function(rec_fn = function(i) worms_rec(marine = 1), log = NULL) {
  function(url, timeout = 60) {
    if (!is.null(log)) assign(log, c(get(log, envir = parent.frame(2)), url),
                              envir = parent.frame(2))
    n <- lengths(regmatches(url, gregexpr("scientificnames(%5B%5D|\\[\\])=", url)))
    list(ok = TRUE, status = 200L,
         body = lapply(seq_len(max(n, 1L)), function(i) list(rec_fn(i))))
  }
}
