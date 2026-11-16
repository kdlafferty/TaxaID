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

# A name asked at two ranks whose two answers are not nested: GBIF answers "Polyarthra" at genus with the rotifer genus
# and at order with an arthropod order. The run's own lineage (the match object's) places the genus in Rotifera; with
# that context the order answer is a homonym, refused, and the one remaining candidate is taken. With no context both
# answers stand, the backbone's tree nests neither, and the name is lineage_unresolved: an error that stops the run.
.rs_lookup_polyarthra <- function() {
  base <- .rs_lookup()
  function(names, rank, context, cache_dir = NULL) {
    out <- base(names, rank, context)
    for (i in which(names == "Polyarthra vulgaris")) {
      out$classification_path[i] <- "Animalia|Rotifera|Synchaetidae|Polyarthra|Polyarthra vulgaris"
      out$classification_ranks[i] <- "kingdom|phylum|family|genus|species"; out$classification_ids[i] <- paste("1|91|7100|7101", out$record_id[i], sep = "|")
    }
    for (i in which(names == "Polyarthra")) {
      if (identical(rank[i], "order")) {
        out$matched_rank[i] <- "order"; out$classification_path[i] <- "Animalia|Arthropoda|Polyarthra"
        out$classification_ranks[i] <- "kingdom|phylum|order"; out$classification_ids[i] <- "1|54|7001"
        out$record_id[i] <- out$current_record_id[i] <- "7001"
      } else {
        out$matched_rank[i] <- "genus"; out$classification_path[i] <- "Animalia|Rotifera|Synchaetidae|Polyarthra"
        out$classification_ranks[i] <- "kingdom|phylum|family|genus"; out$classification_ids[i] <- "1|91|7100|7101"
        out$record_id[i] <- out$current_record_id[i] <- "7101"
      }
    }
    out
  }
}

test_that("tables_to_registry gives names their own lineage as context: a cross-phylum homonym asked at another rank is refused", {
  root <- TaxaWizard:::.pack_find_repo_root(); skip_if(is.null(root), "repo root not found")
  skip_if_not(requireNamespace("TaxaTools", quietly = TRUE) && "attach_taxon_ids" %in% getNamespaceExports("TaxaTools"), "TaxaTools without the registry")
  skip_if_not(requireNamespace("TaxaFetch", quietly = TRUE) && "lookup_gbif_taxa" %in% getNamespaceExports("TaxaFetch"), "TaxaFetch without lookup_gbif_taxa")
  env <- .rs_gen_env(root)
  snip <- paste(readLines(file.path(root, "TaxaWizard", "inst", "graph", "snippets", "tables_to_registry.R"), warn = FALSE), collapse = "\n")
  code <- .rs_fill(snip, env, list(taxonomy_cache_dir = "NULL", use_taxon_registry = "TRUE"))
  run <- new.env(parent = globalenv())
  run$match_df <- data.frame(taxon_name = "Polyarthra vulgaris", kingdom = "Animalia", phylum = "Rotifera", family = "Synchaetidae",
                             genus = "Polyarthra")
  # a ring row that names the clade at order (as an unreferenced-hypothesis row can)
  run$likelihoods <- data.frame(taxon_name = c("Polyarthra vulgaris", "Polyarthra"), taxon_name_rank = c("species", "order"))
  run$reference_df <- data.frame(species = "Polyarthra vulgaris")
  run$std_occurrences <- data.frame(taxon_name = "Polyarthra vulgaris")
  run$priors <- data.frame(taxon_name = "Polyarthra vulgaris", taxon_name_rank = "species")
  testthat::local_mocked_bindings(lookup_gbif_taxa = .rs_lookup_polyarthra(), .package = "TaxaFetch")
  expect_no_error(suppressMessages(eval(parse(text = code), envir = run)))
  reg <- run$taxon_registry
  expect_s3_class(reg, "taxon_registry")
  ids <- unique(reg$names$taxon_id[reg$names$verbatim_name == "Polyarthra"])
  expect_identical(ids, "gbif:7101")
  expect_false(any(reg$names$status %in% "lineage_unresolved"))
})

test_that("the posterior snippets' own registry (built when none exists) gives names the same lineage context", {
  root <- TaxaWizard:::.pack_find_repo_root(); skip_if(is.null(root), "repo root not found")
  skip_if_not(requireNamespace("TaxaTools", quietly = TRUE) && "attach_taxon_ids" %in% getNamespaceExports("TaxaTools"), "TaxaTools without the registry")
  skip_if_not(requireNamespace("TaxaFetch", quietly = TRUE) && "lookup_gbif_taxa" %in% getNamespaceExports("TaxaFetch"), "TaxaFetch without lookup_gbif_taxa")
  env <- .rs_gen_env(root)
  for (f in c("lik_prior_to_post.R", "lik_prior_to_post_multisite.R")) {
    src <- readLines(file.path(root, "TaxaWizard", "inst", "graph", "snippets", f), warn = FALSE)
    i <- grep('^if \\(!exists\\("taxon_registry"\\)\\) taxon_registry <- NULL', src); j <- grep("^if \\(isTRUE\\(\\{\\{use_taxon_registry\\}\\}\\)\\) \\{", src)
    expect_length(i, 1L); expect_length(j, 1L)
    code <- .rs_fill(paste(src[i:(j - 1L)], collapse = "\n"), env, list(taxonomy_cache_dir = "NULL", use_taxon_registry = "TRUE"))
    run <- new.env(parent = globalenv())
    run$likelihoods <- data.frame(taxon_name = c("Polyarthra vulgaris", "Polyarthra"), taxon_name_rank = c("species", "order"),
                                  kingdom = "Animalia", phylum = "Rotifera", family = c("Synchaetidae", NA), genus = c("Polyarthra", NA))
    run$priors <- data.frame(taxon_name = "Polyarthra vulgaris", taxon_name_rank = "species")
    testthat::local_mocked_bindings(lookup_gbif_taxa = .rs_lookup_polyarthra(), .package = "TaxaFetch")
    expect_no_error(suppressMessages(eval(parse(text = code), envir = run)))
    reg <- run$taxon_registry
    # asked only at order, the arthropod order is a homonym of the rotifer genus the run's own lineage names: refused
    expect_false(any(reg$names$taxon_id[reg$names$verbatim_name == "Polyarthra"] %in% "gbif:7001"), info = f)
    expect_true(all(reg$names$status[reg$names$verbatim_name == "Polyarthra"] %in% "homonym_rejected"), info = f)
  }
})
