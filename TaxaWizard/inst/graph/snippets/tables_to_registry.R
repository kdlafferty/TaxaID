# Edge: match_df + likelihoods + reference_df + std_occurrences + priors -> taxon_registry
# Source: TaxaTools build_taxon_registry() + freeze_taxon_registry() +
#         check_taxon_registry() + attach_taxon_ids(); TaxaFetch lookup_gbif_taxa()
#
# One taxon registry for the run. Every name the later steps join on is resolved
# ONCE to a GBIF Backbone taxon id: the match object's names and lineage columns,
# the likelihoods' names (candidates and the clades their placeholder rows name),
# the reference database's species, the standardized occurrences, and the FINISHED
# prior table. This step runs after the priors are built, so the names it registers
# for them are the names the posterior step stamps: the names
# convert_taxonomy_backbone() left, plus any domestic/food or evidence rows the prior
# step added, plus each singleton mirror's source species. Answers are cached in {{taxonomy_cache_dir}}, so a rerun asks nothing.
# The registry is then FROZEN: a name it does not hold is an error later, never a new
# row. The prior and posterior steps reuse this one registry, so a call under a
# synonym meets the prior filed under the accepted name, one taxon under two names is
# one hypothesis, family and order come from the GBIF tree, and outputs carry GBIF
# accepted names (each row keeps its own name in taxon_name_verbatim).
#
# check_taxon_registry(mode = "error") stops here if a lookup FAILED or two different
# taxa were merged with no declared synonymy, rather than guessing. Its full report
# (synonyms merged, names it could only place at genus, run-local names) is kept as
# taxon_registry_report. Set {{use_taxon_registry}} to FALSE to join on names instead.
#
# A table that reaches the posterior step without passing through here (prior rows
# added after this step) must have its names added to .reg_names before the freeze.

taxon_registry <- NULL
taxon_registry_report <- NULL
if (isTRUE({{use_taxon_registry}})) {
  .reg_rows <- function(x, col, tab, rank = NULL) {
    if (is.null(x) || !col %in% names(x)) return(NULL)
    rk <- if (!is.null(rank)) rank else if (col == "taxon_name" && "taxon_name_rank" %in% names(x)) as.character(x$taxon_name_rank) else NA_character_
    d <- unique(data.frame(verbatim_name = as.character(x[[col]]), rank_given = rk, source_table = tab, stringsAsFactors = FALSE))
    d[!is.na(d$verbatim_name) & nzchar(d$verbatim_name), , drop = FALSE]
  }
  .lineage_ranks <- c("kingdom", "phylum", "class", "order", "family", "genus")
  .reg_names <- rbind(
    .reg_rows({{match_var}}, "taxon_name", "match"),
    do.call(rbind, lapply(.lineage_ranks, function(r) .reg_rows({{match_var}}, r, "match", rank = r))),
    .reg_rows({{lik_var}}, "taxon_name", "likelihoods"),
    .reg_rows({{reference_var}}, "species", "reference", rank = "species"),
    .reg_rows({{std_var}}, "taxon_name", "occurrences"),
    # the finished prior table, under the table name the posterior step stamps it with
    .reg_rows({{priors_var}}, "taxon_name", "priors"),
    .reg_rows({{priors_var}}, "source_taxon_name", "priors", rank = "species")
  )
  .reg_names <- unique(.reg_names)
  taxon_registry <- TaxaTools::freeze_taxon_registry(TaxaTools::build_taxon_registry(
    .reg_names,
    run_id          = format(Sys.time(), "run-%Y%m%d-%H%M%S"),
    key_backbone_id = 11L,
    lookup          = function(names, rank, context) {
      TaxaFetch::lookup_gbif_taxa(names, rank, context, cache_dir = {{taxonomy_cache_dir}})
    }
  ))
  taxon_registry_report <- TaxaTools::check_taxon_registry(taxon_registry, mode = "error")
  {{std_var}} <- TaxaTools::attach_taxon_ids({{std_var}}, taxon_registry, "taxon_name", "occurrences")
  message(sprintf("Taxon registry: %d names -> %d taxa (GBIF Backbone); frozen.",
                  length(unique(.reg_names$verbatim_name)), nrow(taxon_registry$taxa)))
}
taxon_registry
