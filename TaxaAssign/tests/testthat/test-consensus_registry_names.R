# posterior_consensus(registry =): group_priors and species_reference are keyed by registry id, so a group or a
# reference species filed under a synonym meets the consensus the registry names. Fixtures in helper-registry.R: the
# synonym pair Embiotoca caryi (verbatim) / Hypsurus caryi (accepted), which the registry places in genus Hypsurus.

.cr_post <- function(reg, p = c(0.9, 0.1)) {
  lik <- data.frame(observation_id = "E1", taxon_name = c("Hypsurus caryi", "Embiotoca jacksoni"), taxon_name_rank = "species",
                    hypothesis_type = "specific_candidate", score_likelihood = p, stringsAsFactors = FALSE)
  lik$score_likelihood_mean <- lik$score_likelihood; lik$score_likelihood_sd <- 0.01
  lik$genus <- sub(" .*$", "", lik$taxon_name); lik$family <- "Embiotocidae"
  pri <- data.frame(taxon_name = c("Hypsurus caryi", "Embiotoca jacksoni"), taxon_name_rank = "species", grid_id = "s1",
                    main_habitat = "Rocky", alpha = c(20, 20), beta = c(80, 80), undetected_type = NA_character_,
                    stringsAsFactors = FALSE)
  jp <- suppressWarnings(suppressMessages(join_priors(.rg_stamp(lik, reg, "joined"), .rg_stamp(pri, reg, "priors"),
          site = list(grid_id = "s1", main_habitat = "Rocky"), rank_system = c("family", "genus", "species"), backbone_id = 11L,
          registry = reg)))
  set.seed(3); suppressMessages(compute_posterior(jp, n_sims = 0L))
}
.cr_cons <- function(post, reg, ...) suppressWarnings(suppressMessages(posterior_consensus(post, rank_system = c("family", "genus", "species"),
  posterior_col = "posterior_point_est", lookup_missing_taxonomy = TRUE, registry = reg, ...)))

test_that("group_priors filed under a synonym is found at the registry's accepted name (consensus_prior, has_occurrence_record)", {
  .rg_skip(); reg <- .rg_registry()
  post <- .cr_post(reg)
  gp <- data.frame(rank = c("species", "genus", "family"), taxon = c("Embiotoca caryi", "Embiotoca", "Embiotocidae"),
                   theta_sum = c(0.2, 0.3, 0.4), n_members = 1L, stringsAsFactors = FALSE)
  cons <- .cr_cons(post, reg, group_priors = gp, cumulative_threshold = 0.85)
  expect_identical(cons$consensus_taxon, "Hypsurus caryi")
  expect_identical(cons$consensus_rank, "species")
  expect_equal(cons$consensus_prior, 0.2)
  expect_true(isTRUE(cons$consensus_has_occurrence_record))
})

test_that("a group_priors or species_reference name the registry does not hold is an error, not a silent miss", {
  .rg_skip(); reg <- .rg_registry()
  post <- .cr_post(reg)
  gp <- data.frame(rank = "species", taxon = "Nonesuch nonexistens", theta_sum = 0.2, n_members = 1L, stringsAsFactors = FALSE)
  expect_error(.cr_cons(post, reg, group_priors = gp), "group_priors")
  sr <- data.frame(taxon_name = "Nonesuch nonexistens", genus = "Nonesuch", stringsAsFactors = FALSE)
  expect_error(.cr_cons(post, reg, species_reference = sr), "species_reference")
})

test_that("species_reference filed under a synonym downranks along the registry's tree", {
  .rg_skip(); reg <- .rg_registry()
  # a family-level call between the two genera; the reference holds one species, filed under its synonym and the
  # synonym's own genus. By name it narrows to genus Embiotoca, then cannot reach a species any candidate holds; by
  # id it is Hypsurus caryi in Hypsurus, a candidate.
  post <- .cr_post(reg, p = c(0.6, 0.4))
  sr <- data.frame(taxon_name = "Embiotoca caryi", genus = "Embiotoca", family = "Embiotocidae", stringsAsFactors = FALSE)
  cons <- .cr_cons(post, reg, species_reference = sr, cumulative_threshold = 0.95, min_posterior = 0)
  expect_identical(cons$consensus_taxon, "Hypsurus caryi")
  expect_true(isTRUE(cons$downranked))
})

test_that("no roxygen, Rd or code comment in TaxaAssign carries history text 'as before'", {
  root <- normalizePath(file.path(testthat::test_path(), "..", ".."), mustWork = FALSE)
  rf <- list.files(file.path(root, "R"), pattern = "[.]R$", full.names = TRUE)
  mf <- list.files(file.path(root, "man"), pattern = "[.]Rd$", full.names = TRUE)
  skip_if_not(length(rf) > 0 && length(mf) > 0, "package sources not available")
  hits <- character(0)
  for (f in rf) {
    l <- readLines(f, warn = FALSE)
    cm <- grepl("^\\s*#", l) & grepl("as before", l, fixed = TRUE)
    hits <- c(hits, sprintf("%s:%d", basename(f), which(cm)))
  }
  for (f in mf) {
    l <- readLines(f, warn = FALSE)
    hits <- c(hits, sprintf("%s:%d", basename(f), which(grepl("as before", l, fixed = TRUE))))
  }
  expect_identical(hits, character(0))
})

test_that("consensus_settings holds the frozen registry, and the roxygen says so", {
  .rg_skip(); reg <- .rg_registry()
  cons <- .cr_cons(.cr_post(reg), reg)
  st <- attr(cons, "consensus_settings")
  expect_true("registry" %in% names(st))
  expect_identical(st$registry, reg)
  root <- normalizePath(file.path(testthat::test_path(), "..", ".."), mustWork = FALSE)
  rd <- file.path(root, "man", "posterior_consensus.Rd")
  skip_if_not(file.exists(rd), "package sources not available")
  txt <- gsub("\\s+", " ", paste(readLines(rd, warn = FALSE), collapse = " "))
  expect_true(grepl("holds the whole frozen registry", txt, fixed = TRUE))
})
