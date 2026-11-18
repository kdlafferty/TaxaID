# registry_keys.R
# TaxaExpect package
#
# Shared internals for the `registry =` arguments.

# A per-taxon lookup table (one row per name) reduced to one row per registry taxon id, after checking that it and
# `x` carry the same frozen registry's stamp. Of several names of one taxon, the row under the registry's accepted
# name is kept, else the first. Rows with no id are dropped (they can match nothing by id).
.registry_lookup_by_id <- function(lookup, registry, lookup_arg, x, x_arg) {
  TaxaTools::registry_ids_for_names(NULL, registry, tables = stats::setNames(list(lookup, x), c(lookup_arg, x_arg)))
  lk <- as.data.frame(lookup)
  lk <- lk[!is.na(lk$taxon_id), , drop = FALSE]
  acc <- as.character(lk$taxon_name) == registry$taxa$name[match(lk$taxon_id, registry$taxa$taxon_id)]
  acc[is.na(acc)] <- FALSE
  lk <- lk[order(!acc, seq_len(nrow(lk))), , drop = FALSE]
  lk[!duplicated(lk$taxon_id), , drop = FALSE]
}

# Rank columns for a table's names read from the registry's tree: each name in `name_col` resolves through the
# registry's name table (a name registered to exactly one taxon); `id_col` receives the id and each of `cols` the
# registry's name for that taxon's ancestor at the rank. Names the registry does not hold get NA throughout. The id
# column is not `taxon_id`: that name is reserved for a table attach_taxon_ids() stamped, and these rows are bound
# into a prior table that is stamped later, which would refuse an unstamped taxon_id as another source's ids.
.registry_lineage_cols <- function(x, registry, cols, name_col = "taxon_name", id_col = "registry_taxon_id", caller = "") {
  x[[id_col]] <- as.vector(TaxaTools::registry_ids_for_names(as.character(x[[name_col]]), registry, resolve = "names",
                                                               caller = if (nzchar(caller)) caller else NULL))
  reg_name <- stats::setNames(registry$taxa$name, registry$taxa$taxon_id)
  u <- unique(stats::na.omit(x[[id_col]]))
  for (rc in cols) {
    a <- stats::setNames(TaxaTools::parent_at(u, rc, registry), u)
    x[[rc]] <- unname(reg_name[unname(a[x[[id_col]]])])
  }
  x
}
