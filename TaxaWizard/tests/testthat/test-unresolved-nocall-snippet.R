# An observation whose matches all name a reference only above the rank system (only "Eukaryota") gets no likelihood
# row; evaluate_likelihoods() returns it in $unresolved. The consensus snippets must still give it one consensus row,
# a no-call with consensus_reason "no_usable_likelihood" and the lineage its references share, so no observation leaves
# the consensus table without a row. Run as the template runs them (placeholders filled), with the TaxaLikely and
# TaxaAssign steps mocked.

.nu_snippet <- function(root, name, over) {
  txt <- paste(readLines(file.path(root, "TaxaWizard", "inst", "graph", "snippets", paste0(name, ".R")), warn = FALSE),
               collapse = "\n")
  for (k in names(over)) txt <- gsub(paste0("{{", k, "}}"), over[[k]], txt, fixed = TRUE)
  left <- regmatches(txt, gregexpr("\\{\\{[a-zA-Z_0-9]+\\}\\}", txt))[[1]]
  if (length(left) > 0L) stop("unfilled placeholder(s) in ", name, ": ", paste(unique(left), collapse = ", "))
  txt
}
.nu_skip <- function() {
  root <- TaxaWizard:::.pack_find_repo_root()
  testthat::skip_if(is.null(root), "repo root not found")
  for (p in c("TaxaTools", "TaxaLikely", "TaxaAssign")) testthat::skip_if_not_installed(p)
  root
}
# esv_euk: two matches, both to references named only "Eukaryota". esv_mix: references that disagree at the first
# rank they name, so no lineage is shared. Every column below kingdom is NA, as in a kingdom-only reference.
.nu_unresolved <- function() {
  data.frame(observation_id = c("esv_euk", "esv_euk", "esv_mix", "esv_mix"),
             kingdom = c("Eukaryota", "Eukaryota", "Eukaryota", "Metazoa"),
             phylum = NA_character_, class = NA_character_, order = NA_character_, family = NA_character_,
             genus = NA_character_, species = NA_character_, taxon_name = NA_character_,
             score_original = c(91, 88, 85, 80), stringsAsFactors = FALSE)
}
.nu_consensus_mock <- function(posterior_df, ...) {
  out <- data.frame(observation_id = unique(as.character(posterior_df$observation_id)),
                    consensus_taxon = "Embiotoca jacksoni", consensus_rank = "species",
                    consensus_reason = "credible_node", is_resolved = TRUE, stringsAsFactors = FALSE)
  attr(out, "consensus_settings") <- list(consensus_method = "credible_node")
  out
}
.nu_check <- function(cons) {
  expect_setequal(as.character(cons$observation_id), c("esv_ok", "esv_euk", "esv_mix"))
  expect_false(anyDuplicated(as.character(cons$observation_id)) > 0L)
  euk <- cons[cons$observation_id == "esv_euk", ]
  expect_identical(euk$consensus_reason, "no_usable_likelihood")
  expect_identical(euk$is_resolved, FALSE)
  expect_true(is.na(euk$consensus_taxon) && is.na(euk$consensus_rank))
  expect_identical(euk$coarsest_reference_lineage, "Eukaryota")
  expect_true(is.na(cons$coarsest_reference_lineage[cons$observation_id == "esv_mix"]))
  ok <- cons[cons$observation_id == "esv_ok", ]
  expect_identical(ok$consensus_reason, "credible_node")
  expect_true(is.na(ok$coarsest_reference_lineage))
  expect_identical(attr(cons, "consensus_settings"), list(consensus_method = "credible_node"))
}

test_that("model_match_to_lik keeps evaluate_likelihoods()'s $unresolved for the consensus step", {
  root <- .nu_skip()
  code <- .nu_snippet(root, "model_match_to_lik", list(match_var = "match_df", model_var = "model_params"))
  run <- new.env(parent = globalenv())
  run$match_df <- data.frame(observation_id = "esv_ok", score_original = 99, taxon_name = "Embiotoca jacksoni")
  run$model_params <- list()
  testthat::local_mocked_bindings(
    evaluate_likelihoods = function(match_df, ...) list(
      likelihoods = data.frame(observation_id = "esv_ok", taxon_name = "Embiotoca jacksoni"),
      unresolved = .nu_unresolved()),
    filter_top_hypotheses = function(x, ...) x,
    .package = "TaxaLikely")
  suppressMessages(eval(parse(text = code), envir = run))
  expect_true(exists("lik_unresolved", envir = run, inherits = FALSE))
  expect_identical(run$lik_unresolved, .nu_unresolved())
})

test_that("post_to_consensus gives an observation with no usable likelihood a no-call row", {
  root <- .nu_skip()
  code <- .nu_snippet(root, "post_to_consensus", list(
    input_var = "posteriors", taxaexpect_priors_var = "priors", taxonomy_map_var = "taxonomy_map",
    cumulative_threshold = "0.95", rank_system = 'c("kingdom", "phylum", "class", "order", "family", "genus", "species")',
    taxonomy_cache_dir = "NULL", include_group_priors = "FALSE", include_downranking = "FALSE"))
  run <- new.env(parent = globalenv())
  run$posteriors <- data.frame(observation_id = "esv_ok", taxon_name = "Embiotoca jacksoni", posterior_point_est = 1)
  run$priors <- data.frame(taxon_name = "Embiotoca jacksoni")
  run$taxonomy_map <- NULL
  run$lik_unresolved <- .nu_unresolved()
  testthat::local_mocked_bindings(
    posterior_consensus = .nu_consensus_mock,
    update_prior_from_consensus = function(posterior_df, ...) posterior_df,
    add_slash_taxon = function(consensus_df, ...) consensus_df,
    .package = "TaxaAssign")
  suppressMessages(eval(parse(text = code), envir = run))
  .nu_check(run$consensus_final)
})

test_that("match_to_consensus_bayes gives an observation with no usable likelihood a no-call row", {
  root <- .nu_skip()
  code <- .nu_snippet(root, "match_to_consensus_bayes", list(
    match_var = "match_df", model_var = "model_params", priors_var = "priors", site = "NULL",
    backbone_id = "11", taxonomy_cache_dir = "NULL", use_taxon_registry = "FALSE"))
  run <- new.env(parent = globalenv())
  run$match_df <- data.frame(observation_id = c("esv_ok", "esv_euk"), score_original = c(99, 91),
                             genus = c("Embiotoca", NA), species = c("Embiotoca jacksoni", NA),
                             taxon_name = c("Embiotoca jacksoni", NA), taxon_name_rank = c("species", NA))
  run$model_params <- list()
  run$priors <- data.frame(taxon_name = "Embiotoca jacksoni")
  testthat::local_mocked_bindings(
    evaluate_likelihoods = function(match_df, ...) list(
      likelihoods = data.frame(observation_id = "esv_ok", taxon_name = "Embiotoca jacksoni"),
      unresolved = .nu_unresolved()),
    filter_top_hypotheses = function(x, ...) x,
    .package = "TaxaLikely")
  testthat::local_mocked_bindings(
    join_priors = function(likelihoods, ...) likelihoods,
    compute_posterior = function(x, ...) x,
    posterior_consensus = .nu_consensus_mock,
    update_prior_from_consensus = function(posterior_df, ...) posterior_df,
    .package = "TaxaAssign")
  suppressMessages(eval(parse(text = code), envir = run))
  .nu_check(run$consensus)
})
