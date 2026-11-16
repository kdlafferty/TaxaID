# A small frozen taxon registry for the registry = arguments, built offline from synthetic GBIF-shaped answers
# (TaxaTools::build_taxon_registry(lookup =)). Two families, chosen from defects measured on real runs:
#   Labridae: Oxyjulis californica, whose synonym Halichoeres californicus is the name a reference or pool may carry;
#             Halichoeres semicinctus, a true Halichoeres.
#   Embiotocidae: Hypsurus caryi, whose synonym Embiotoca caryi sits in genus Embiotoca by its TEXT but in Hypsurus by
#             the tree; Embiotoca jacksoni.
.rg_skip <- function() testthat::skip_if_not("parent_at" %in% getNamespaceExports("TaxaTools"), "TaxaTools without the taxon registry")

.rg_answers <- function() {
  K <- "Animalia|Chordata|Perciformes"; KI <- "1|44|587"; KR <- "kingdom|phylum|order"
  a <- function(q, matched, rank, path, ids, ranks, cur, rec = cur, syn = FALSE) data.frame(q = q, matched = matched, rank = rank,
    path = paste(K, path, sep = "|"), ids = paste(KI, ids, sep = "|"), ranks = paste(KR, ranks, sep = "|"), cur = cur, rec = rec, syn = syn, stringsAsFactors = FALSE)
  rbind(
    a("Labridae", "Labridae", "family", "Labridae", "100", "family", "100"),
    a("Oxyjulis", "Oxyjulis", "genus", "Labridae|Oxyjulis", "100|200", "family|genus", "200"),
    a("Halichoeres", "Halichoeres", "genus", "Labridae|Halichoeres", "100|300", "family|genus", "300"),
    a("Oxyjulis californica", "Oxyjulis californica", "species", "Labridae|Oxyjulis|Oxyjulis californica", "100|200|201", "family|genus|species", "201"),
    a("Halichoeres californicus", "Oxyjulis californica", "species", "Labridae|Oxyjulis|Oxyjulis californica", "100|200|201", "family|genus|species", "201", rec = "302", syn = TRUE),
    a("Halichoeres semicinctus", "Halichoeres semicinctus", "species", "Labridae|Halichoeres|Halichoeres semicinctus", "100|300|301", "family|genus|species", "301"),
    a("Embiotocidae", "Embiotocidae", "family", "Embiotocidae", "400", "family", "400"),
    a("Hypsurus", "Hypsurus", "genus", "Embiotocidae|Hypsurus", "400|410", "family|genus", "410"),
    a("Embiotoca", "Embiotoca", "genus", "Embiotocidae|Embiotoca", "400|420", "family|genus", "420"),
    a("Hypsurus caryi", "Hypsurus caryi", "species", "Embiotocidae|Hypsurus|Hypsurus caryi", "400|410|411", "family|genus|species", "411"),
    a("Embiotoca caryi", "Hypsurus caryi", "species", "Embiotocidae|Hypsurus|Hypsurus caryi", "400|410|411", "family|genus|species", "411", rec = "412", syn = TRUE),
    a("Embiotoca jacksoni", "Embiotoca jacksoni", "species", "Embiotocidae|Embiotoca|Embiotoca jacksoni", "400|420|421", "family|genus|species", "421")
  )
}
.rg_lookup <- function(names, rank, context) {
  t <- .rg_answers(); i <- match(names, t$q); hit <- !is.na(i)
  data.frame(user_supplied_name = names, matched_name = ifelse(hit, t$matched[i], NA), matched_rank = ifelse(hit, t$rank[i], NA),
             is_synonym = ifelse(hit, t$syn[i], NA), classification_path = ifelse(hit, t$path[i], NA),
             classification_ranks = ifelse(hit, t$ranks[i], NA), score = NA_real_, verified = TRUE, matched = hit,
             record_id = ifelse(hit, t$rec[i], NA), current_record_id = ifelse(hit, t$cur[i], NA),
             classification_ids = ifelse(hit, t$ids[i], NA), data_source_id = 11L, entry_date = "2024-01-11",
             match_type = ifelse(hit, "Exact", NA), stringsAsFactors = FALSE)
}
# every answer name, registered under each table the tests stamp
.rg_registry <- function(run_id = "rg1") {
  a <- .rg_answers(); nm <- a$q
  tabs <- c("joined", "priors", "reference")
  r <- TaxaTools::build_taxon_registry(data.frame(verbatim_name = rep(nm, length(tabs)), source_table = rep(tabs, each = length(nm)),
                                                  rank_given = rep(a$rank, length(tabs)), stringsAsFactors = FALSE), run_id = run_id, lookup = .rg_lookup)
  TaxaTools::freeze_taxon_registry(r)
}
.rg_id <- function(reg, name, tab = "reference") reg$names$taxon_id[reg$names$source_table == tab & reg$names$verbatim_name == name][1]
.rg_stamp <- function(x, reg, tab) suppressMessages(TaxaTools::attach_taxon_ids(x, reg, "taxon_name", tab))
