# registry_keys.R
# TaxaExpect package
#
# Shared internals for the `registry =` arguments.

# A per-taxon lookup table (one row per name) reduced to one row per registry taxon id, after checking that it and
# `x` carry the same frozen registry's stamp. Of several names of one taxon, the row under the registry's accepted
# name is kept, else the first. Rows with no id are dropped (they can match nothing by id).
.registry_lookup_by_id <- function(lookup, registry, lookup_arg, x, x_arg) {
  if (!inherits(registry, "taxon_registry")) stop("`registry` must be a taxon_registry (TaxaTools::build_taxon_registry()).", call. = FALSE)
  if (!isTRUE(registry$meta$frozen)) stop("`registry` must be frozen (TaxaTools::freeze_taxon_registry()).", call. = FALSE)
  for (a in c(lookup_arg, x_arg)) {
    t <- if (a == lookup_arg) lookup else x
    s <- attr(t, "taxon_registry", exact = TRUE)
    if (!"taxon_id" %in% names(t) || is.null(s)) {
      stop(sprintf("`%s` has no taxon_id column or no registry stamp: attach ids with TaxaTools::attach_taxon_ids() before the call.", a), call. = FALSE)
    }
    if (!identical(s$digest, registry$meta$digest)) stop(sprintf("`%s` was stamped by a different registry than `registry`.", a), call. = FALSE)
  }
  lk <- as.data.frame(lookup)
  lk <- lk[!is.na(lk$taxon_id), , drop = FALSE]
  acc <- as.character(lk$taxon_name) == registry$taxa$name[match(lk$taxon_id, registry$taxa$taxon_id)]
  acc[is.na(acc)] <- FALSE
  lk <- lk[order(!acc, seq_len(nrow(lk))), , drop = FALSE]
  lk[!duplicated(lk$taxon_id), , drop = FALSE]
}
