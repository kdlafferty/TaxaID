# The tables_to_registry snippet, run as the template runs it (placeholders filled from the generator's own
# CONFIG/DATAFLOW), with GBIF answers mocked. The registry must hold every name the posterior step stamps: the FINAL
# prior table's names, which convert_taxonomy_backbone() may have renamed and domestic/food rows may have added.

.rs_gen_env <- function(root) {
  gen <- file.path(root, "TaxaWizard", "inst", "tools", "build_workflow_template.R")
  env <- new.env()
  for (e in as.list(parse(gen, keep.source = FALSE))) {
    if (is.call(e) && identical(e[[1]], as.name("<-")) && is.name(e[[2]]) &&
        as.character(e[[2]]) %in% c("CONFIG", "DATAFLOW", "CANONICAL_PATH")) eval(e, envir = env)
  }
  env
}
.rs_fill <- function(txt, env, over = list()) {
  ph <- unique(gsub("[{}]", "", unlist(regmatches(txt, gregexpr("\\{\\{[a-zA-Z_0-9]+\\}\\}", txt)))))
  for (k in ph) {
    v <- over[[k]] %||% (if (k %in% names(env$DATAFLOW)) env$DATAFLOW[[k]] else env$CONFIG[[k]][[1]])
    txt <- gsub(paste0("{{", k, "}}"), v, txt, fixed = TRUE)
  }
  txt
}
# every name its own GBIF taxon under Animalia; ids stable within a test
.rs_lookup <- function() {
  ids <- new.env()
  function(names, rank, context, cache_dir = NULL) {
    id <- vapply(names, function(n) { if (is.null(ids[[n]])) assign(n, as.character(1000L + length(ls(ids))), envir = ids); ids[[n]] }, "")
    rk <- ifelse(!is.na(rank), rank, ifelse(grepl(" ", names), "species", "genus"))
    data.frame(user_supplied_name = names, matched_name = names, matched_rank = rk, is_synonym = FALSE,
               classification_path = paste("Animalia", names, sep = "|"), classification_ranks = paste("kingdom", rk, sep = "|"),
               score = NA_real_, verified = TRUE, matched = TRUE, record_id = id, current_record_id = id,
               classification_ids = paste("1", id, sep = "|"), data_source_id = 11L, entry_date = "2024-01-11",
               match_type = "Exact", stringsAsFactors = FALSE, row.names = NULL)
  }
}

test_that("the canonical path builds the registry AFTER the priors", {
  root <- TaxaWizard:::.pack_find_repo_root(); skip_if(is.null(root), "repo root not found")
  cp <- .rs_gen_env(root)$CANONICAL_PATH
  expect_gt(match("tables_to_registry", cp), match("dist_to_priors_by_group", cp))
  expect_lt(match("tables_to_registry", cp), match("lik_prior_to_post", cp))
})

test_that("tables_to_registry registers the final prior table's names, so the posterior step can stamp it", {
  root <- TaxaWizard:::.pack_find_repo_root(); skip_if(is.null(root), "repo root not found")
  skip_if_not(requireNamespace("TaxaTools", quietly = TRUE) && "attach_taxon_ids" %in% getNamespaceExports("TaxaTools"), "TaxaTools without the registry")
  skip_if_not(requireNamespace("TaxaFetch", quietly = TRUE) && "lookup_gbif_taxa" %in% getNamespaceExports("TaxaFetch"), "TaxaFetch without lookup_gbif_taxa")
  env <- .rs_gen_env(root)
  snip <- paste(readLines(file.path(root, "TaxaWizard", "inst", "graph", "snippets", "tables_to_registry.R"), warn = FALSE), collapse = "\n")
  code <- .rs_fill(snip, env, list(taxonomy_cache_dir = "NULL", use_taxon_registry = "TRUE"))
  run <- new.env(parent = globalenv())
  run$match_df <- data.frame(taxon_name = c("Embiotoca caryi", "Embiotoca jacksoni"), family = "Embiotocidae", genus = "Embiotoca")
  run$likelihoods <- data.frame(taxon_name = c("Embiotoca caryi", "Embiotoca jacksoni"), taxon_name_rank = "species")
  run$reference_df <- data.frame(species = c("Embiotoca caryi", "Embiotoca jacksoni"))
  run$std_occurrences <- data.frame(taxon_name = c("Embiotoca caryi", "Embiotoca jacksoni"))
  # the priors as the prior step leaves them: one name renamed by convert_taxonomy_backbone(), one domestic row added
  run$priors <- data.frame(taxon_name = c("Hypsurus caryi", "Embiotoca jacksoni", "Bos taurus", NA), taxon_name_rank = "species")
  testthat::local_mocked_bindings(lookup_gbif_taxa = .rs_lookup(), .package = "TaxaFetch")
  suppressMessages(eval(parse(text = code), envir = run))
  expect_s3_class(run$taxon_registry, "taxon_registry")
  expect_no_error(st <- TaxaTools::attach_taxon_ids(run$priors, run$taxon_registry, "taxon_name", "priors"))
  expect_false(anyNA(st$taxon_id[!is.na(st$taxon_name)]))
})
