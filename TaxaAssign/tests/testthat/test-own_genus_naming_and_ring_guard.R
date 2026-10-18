# tests/testthat/test-own_genus_naming_and_ring_guard.R
#
# Two rules, from real CalIntertidal shapes, fully offline:
#  (A) add_unreferenced_prior_mass(named_rows = TRUE) names a local unreferenced
#      species only from its OWN genus ring; a family (or coarser) ring takes
#      its prior mass unnamed.
#  (B) posterior_consensus() never downranks a call held by an unreferenced
#      ring onto a species; a coarser narrowing (family -> genus) is kept.

.og_joined <- function(rows) {
  d <- data.frame(
    observation_id = "E1", grid_id = "site1", main_habitat = "Marine",
    score_likelihood_sd = 0, stringsAsFactors = FALSE
  )
  do.call(rbind, lapply(rows, function(r) cbind(d, as.data.frame(r, stringsAsFactors = FALSE))))
}
.og_priors <- function(taxon_name, theta_mean) {
  data.frame(taxon_name = taxon_name, taxon_name_rank = "species", grid_id = "site1",
    main_habitat = "Marine", theta_mean = theta_mean,
    alpha = theta_mean * 1000, beta = (1 - theta_mean) * 1000, stringsAsFactors = FALSE)
}
.og_add <- function(...) suppressMessages(add_unreferenced_prior_mass(...))

# ---- (a) Taonia shape: a family ring does not name ---------------------------

test_that("Taonia: a family ring takes the local species' prior unnamed", {
  j <- .og_joined(list(
    list(taxon_name = "Dictyotaceae", taxon_name_rank = "family",
      hypothesis_type = "unreferenced_genus", score_likelihood = 0.8, score_likelihood_mean = 0.8,
      prior_mean = 2e-6, prior_alpha = 0.002, prior_beta = 999.998)
  ))
  pr <- .og_priors("Taonia lennebackerae", 0.03)
  tax <- data.frame(taxon_name = "Taonia lennebackerae", genus = "Taonia",
    family = "Dictyotaceae", stringsAsFactors = FALSE)
  out <- .og_add(j, pr, tax, referenced_names = "Dictyota dichotoma", named_rows = TRUE)
  expect_equal(nrow(out), 1L)
  expect_false("Taonia lennebackerae" %in% out$taxon_name)
  expect_identical(out$taxon_name, "Dictyotaceae")
  expect_equal(out$prior_mean, 2e-6 + 0.03)
  expect_equal(out$unreferenced_mass, 0.03)
  expect_equal(out$unreferenced_n_species, 1L)
  expect_equal(nrow(attr(out, "unreferenced_withheld")), 0L)
  mem <- attr(out, "unreferenced_scope_members")
  expect_identical(mem$taxon_name, "Taonia lennebackerae")
  expect_identical(mem$scope, "Dictyotaceae")
  expect_identical(mem$scope_rank, "family")
  # exactly the named_rows = FALSE treatment
  off <- .og_add(j, pr, tax, referenced_names = "Dictyota dichotoma", named_rows = FALSE)
  expect_equal(out$prior_mean, off$prior_mean)
  expect_equal(out$prior_alpha, off$prior_alpha)
  expect_equal(out$prior_beta, off$prior_beta)
})

# ---- (b) Hypsoblennius shape: the own genus ring names ------------------------

test_that("Hypsoblennius: the own genus ring names the local species, with its own prior", {
  j <- .og_joined(list(
    list(taxon_name = "Hypsoblennius", taxon_name_rank = "genus",
      hypothesis_type = "unreferenced_species", score_likelihood = 0.6, score_likelihood_mean = 0.6,
      prior_mean = 4e-6, prior_alpha = 0.004, prior_beta = 999.996)
  ))
  pr <- .og_priors("Hypsoblennius jenkinsi", 0.012)
  tax <- data.frame(taxon_name = "Hypsoblennius jenkinsi", genus = "Hypsoblennius",
    family = "Blenniidae", stringsAsFactors = FALSE)
  out <- .og_add(j, pr, tax, referenced_names = "Hypsoblennius gilberti", named_rows = TRUE)
  expect_equal(nrow(out), 2L)
  nr <- out[out$taxon_name == "Hypsoblennius jenkinsi", ]
  expect_equal(nrow(nr), 1L)
  expect_identical(nr$taxon_name_rank, "species")
  expect_equal(nr$score_likelihood, 0.6)  # the ring's likelihood
  expect_equal(nr$prior_mean, 0.012)      # its own prior
  expect_identical(nr$unreferenced_scope, "Hypsoblennius")
  expect_identical(nr$unreferenced_scope_rank, "genus")
  ring <- out[out$taxon_name == "Hypsoblennius", ]
  expect_equal(ring$prior_mean, 4e-6)  # the ring keeps its floor prior
})

# ---- (c) a referenced specific_candidate passes through -----------------------

test_that("a referenced specific_candidate row passes through unchanged", {
  j <- .og_joined(list(
    list(taxon_name = "Hypsoblennius gilberti", taxon_name_rank = "species",
      hypothesis_type = "specific_candidate", score_likelihood = 1, score_likelihood_mean = 1,
      prior_mean = 5e-3, prior_alpha = 5, prior_beta = 995),
    list(taxon_name = "Hypsoblennius", taxon_name_rank = "genus",
      hypothesis_type = "unreferenced_species", score_likelihood = 0.6, score_likelihood_mean = 0.6,
      prior_mean = 4e-6, prior_alpha = 0.004, prior_beta = 999.996),
    list(taxon_name = "Dictyotaceae", taxon_name_rank = "family",
      hypothesis_type = "unreferenced_genus", score_likelihood = 0.2, score_likelihood_mean = 0.2,
      prior_mean = 2e-6, prior_alpha = 0.002, prior_beta = 999.998)
  ))
  pr <- .og_priors(c("Hypsoblennius gilberti", "Hypsoblennius jenkinsi", "Taonia lennebackerae"),
    c(5e-3, 0.012, 0.03))
  tax <- data.frame(taxon_name = pr$taxon_name,
    genus = c("Hypsoblennius", "Hypsoblennius", "Taonia"),
    family = c("Blenniidae", "Blenniidae", "Dictyotaceae"), stringsAsFactors = FALSE)
  out <- .og_add(j, pr, tax, referenced_names = "Hypsoblennius gilberti", named_rows = TRUE)
  g <- out[out$taxon_name == "Hypsoblennius gilberti", ]
  expect_equal(nrow(g), 1L)
  expect_identical(g$hypothesis_type, "specific_candidate")
  expect_equal(g$prior_mean, 5e-3)
  expect_equal(g$prior_alpha, 5)
  expect_equal(g$prior_beta, 995)
  expect_equal(g$score_likelihood, 1)
  expect_true(is.na(g$unreferenced_mass))
  # one named row (jenkinsi, own genus ring); Taonia stays inside the family ring
  expect_equal(nrow(out), 4L)
  expect_true("Hypsoblennius jenkinsi" %in% out$taxon_name)
  expect_false("Taonia lennebackerae" %in% out$taxon_name)
  expect_equal(out$prior_mean[out$taxon_name == "Dictyotaceae"], 2e-6 + 0.03)
})

# ---- (B) the ring guard ---------------------------------------------------------

.og_rank_system <- c("family", "genus", "species")
.og_call <- function(df, ref, ...) {
  msgs <- character()
  out <- withCallingHandlers(
    suppressWarnings(posterior_consensus(df, species_reference = ref,
      rank_system = .og_rank_system, posterior_col = "posterior_point_est",
      consensus_method = "credible_node", likelihood_consensus = FALSE,
      robust_prior_s = 0, ...)),
    message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") })
  attr(out, "msgs") <- msgs
  out
}
.og_blocked_msg <- function(out, n = 1L) {
  any(grepl(sprintf("%d downranking step\\(s\\) to a species blocked because the call's winning hypothesis is an unreferenced row", n),
    attr(out, "msgs")))
}
.og_cottus_df <- function() data.frame(
  observation_id = "E1",
  taxon_name = c("Cottus", "Cottus asper", "Cottidae"),
  taxon_name_rank = c("genus", "species", "family"),
  hypothesis_type = c("unreferenced_species", "specific_candidate", "unreferenced_genus"),
  family = "Cottidae", genus = c("Cottus", "Cottus", NA),
  species = c(NA, "Cottus asper", NA),
  posterior_point_est = c(0.85, 0.10, 0.05), stringsAsFactors = FALSE)
.og_cottus_ref <- function() data.frame(taxon_name = "Cottus asper", genus = "Cottus",
  family = "Cottidae", stringsAsFactors = FALSE)

test_that("Cottus asper: a genus call held by its ring is not downranked to the one local species", {
  out <- .og_call(.og_cottus_df(), .og_cottus_ref())
  expect_identical(out$consensus_taxon, "Cottus")
  expect_identical(out$consensus_rank, "genus")
  expect_false(isTRUE(out$downranked))
  expect_identical(out$consensus_hypothesis_type, "unreferenced_species")
  expect_true(.og_blocked_msg(out))
})

test_that("Cottus asper control: the same genus call held by referenced rows still downranks", {
  df <- data.frame(
    observation_id = "E1",
    taxon_name = c("Cottus asper", "Cottus gobio", "Cottidae"),
    taxon_name_rank = c("species", "species", "family"),
    hypothesis_type = c("specific_candidate", "specific_candidate", "unreferenced_genus"),
    family = "Cottidae", genus = c("Cottus", "Cottus", NA),
    species = c("Cottus asper", "Cottus gobio", NA),
    posterior_point_est = c(0.45, 0.45, 0.10), stringsAsFactors = FALSE)
  out <- .og_call(df, .og_cottus_ref())
  expect_identical(out$consensus_taxon, "Cottus asper")
  expect_identical(out$consensus_rank, "species")
  expect_true(isTRUE(out$downranked))
  expect_false(.og_blocked_msg(out))
})

# ---- (e) Punta Baja shape --------------------------------------------------------

test_that("Punta Baja: a Ruscarius genus call held by its ring stays at genus", {
  df <- data.frame(
    observation_id = "12S_ESV_144804",
    taxon_name = c("Ruscarius", "Ruscarius creaseri", "Cottidae"),
    taxon_name_rank = c("genus", "species", "family"),
    hypothesis_type = c("unreferenced_species", "specific_candidate", "unreferenced_genus"),
    family = "Cottidae", genus = c("Ruscarius", "Ruscarius", NA),
    species = c(NA, "Ruscarius creaseri", NA),
    posterior_point_est = c(0.8, 0.15, 0.05), stringsAsFactors = FALSE)
  ref <- data.frame(taxon_name = "Ruscarius creaseri", genus = "Ruscarius",
    family = "Cottidae", stringsAsFactors = FALSE)
  out <- .og_call(df, ref)
  expect_identical(out$consensus_taxon, "Ruscarius")
  expect_identical(out$consensus_rank, "genus")
  expect_false(isTRUE(out$downranked))
  expect_true(.og_blocked_msg(out))
})

# ---- (f) family call: narrows to genus, not to species ---------------------------

test_that("a family call held by a ring narrows to the genus but not to the species", {
  df <- data.frame(
    observation_id = "E1",
    taxon_name = c("Cottidae", "Clinocottus analis"),
    taxon_name_rank = c("family", "species"),
    hypothesis_type = c("unreferenced_genus", "specific_candidate"),
    family = "Cottidae", genus = c(NA, "Clinocottus"),
    species = c(NA, "Clinocottus analis"),
    posterior_point_est = c(0.6, 0.4), stringsAsFactors = FALSE)
  ref <- data.frame(taxon_name = "Clinocottus analis", genus = "Clinocottus",
    family = "Cottidae", stringsAsFactors = FALSE)
  out <- .og_call(df, ref)
  expect_identical(out$consensus_taxon, "Clinocottus")
  expect_identical(out$consensus_rank, "genus")
  expect_true(isTRUE(out$downranked))
  expect_true(.og_blocked_msg(out))
  # control: the same rows with the family held by a referenced row go to the species
  df$hypothesis_type[1] <- "specific_candidate"
  ctl <- .og_call(df, ref)
  expect_identical(ctl$consensus_taxon, "Clinocottus analis")
  expect_identical(ctl$consensus_rank, "species")
  expect_false(.og_blocked_msg(ctl))
})

# ---- (g) input-shape grid for the guard -------------------------------------------

.og_shapes <- list(
  with_type = function(d) d,
  no_type_column = function(d) { d$hypothesis_type <- NULL; d },
  na_type = function(d) { d$hypothesis_type <- NA_character_; d },
  na_type_ring_row = function(d) { d$hypothesis_type[d$taxon_name == "Cottus"] <- NA_character_; d },
  na_consensus_taxon_row = function(d) {
    d <- rbind(d, data.frame(observation_id = "E1", taxon_name = NA_character_,
      taxon_name_rank = NA_character_, hypothesis_type = NA_character_, family = NA_character_,
      genus = NA_character_, species = NA_character_, posterior_point_est = 0.01,
      stringsAsFactors = FALSE))
    d
  },
  two_observations = function(d) {
    d2 <- d; d2$observation_id <- "E2"; d2$hypothesis_type <- "specific_candidate"
    rbind(d, d2)
  }
)
for (sh in names(.og_shapes)) {
  local({
    sh <- sh
    test_that(sprintf("ring guard input shape: %s", sh), {
      df <- .og_shapes[[sh]](.og_cottus_df())
      if (sh == "no_type_column") {
        # posterior_consensus() requires hypothesis_type up front: a clear error
        # from its own validation, never a guard failure
        expect_error(.og_call(df, .og_cottus_ref()), "missing required column.*hypothesis_type")
        return(invisible())
      }
      out <- NULL
      expect_no_error(out <- .og_call(df, .og_cottus_ref()))
      expect_s3_class(out, "data.frame")
      expect_identical(nrow(out), length(unique(df$observation_id)))
      e1 <- out[out$observation_id == "E1", ]
      if (sh %in% c("with_type", "na_consensus_taxon_row")) {
        # known ring type: blocked
        expect_identical(e1$consensus_taxon, "Cottus")
        expect_false(isTRUE(e1$downranked))
        expect_true(.og_blocked_msg(out))
      } else if (sh %in% c("na_type", "na_type_ring_row")) {
        # unknown type: no blocking, the reference downranks as before
        expect_identical(e1$consensus_taxon, "Cottus asper")
        expect_true(isTRUE(e1$downranked))
        expect_false(any(grepl("unreferenced ring", attr(out, "msgs"))))
      } else {
        # two observations: E1 held by its ring (blocked), E2 referenced (downranks)
        expect_identical(e1$consensus_taxon, "Cottus")
        expect_false(isTRUE(e1$downranked))
        expect_true(.og_blocked_msg(out))
      }
    })
  })
}

test_that("Percina shape: a genus node WON by a referenced species still downranks", {
  # GreatLakes P1_ASV_0314: the genus node "Percina" shares its name with the
  # Percina ring, but the winner is the referenced (and Lamar-corroborated)
  # P. maculata at 0.71, the ring at 0.24. Keying the guard on the row named
  # like the call blocked 8 such calls; it is keyed on the winner.
  df <- data.frame(
    observation_id = "E1",
    taxon_name = c("Percina maculata", "Percina", "Percidae"),
    taxon_name_rank = c("species", "genus", "family"),
    hypothesis_type = c("specific_candidate", "unreferenced_species", "unreferenced_genus"),
    family = "Percidae", genus = c("Percina", "Percina", NA),
    species = c("Percina maculata", NA, NA),
    posterior_point_est = c(0.71, 0.24, 0.05), stringsAsFactors = FALSE)
  ref <- data.frame(taxon_name = "Percina maculata", genus = "Percina", family = "Percidae",
    stringsAsFactors = FALSE)
  out <- .og_call(df, ref)
  expect_identical(out$consensus_taxon, "Percina maculata")
  expect_true(isTRUE(out$downranked))
  expect_false(.og_blocked_msg(out))
})
