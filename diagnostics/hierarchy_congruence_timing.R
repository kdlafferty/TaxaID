# diagnostics/hierarchy_congruence_timing.R
#
# Real-scale timing check for TaxaLikely:::.compute_hierarchy_congruence(),
# required by the verification bar in
# ecosystem_docs/REENTRY_PROMPT_reference_database_audit_hierarchy_check.md:
# "A timing check of .compute_hierarchy_congruence() against a real-scale
# (order 10^5-10^6 row) seq_matrix, confirming the vectorised (not per-row)
# implementation."
#
# Generates a synthetic but structurally realistic seq_matrix + reference_df
# (submission batches with contiguous accession numbers + close create_dates,
# a 7-level rank hierarchy, ~10^5-10^6 pairwise rows) and times the function
# directly. Not part of the automated test suite (too slow for CI, matching
# this package's own diagnostics/ convention for real-scale checks) -- run
# manually with `Rscript diagnostics/hierarchy_congruence_timing.R`.

devtools::load_all("TaxaLikely", quiet = TRUE)

set.seed(42)

# ---- Build a synthetic taxonomy hierarchy ----------------------------------
n_species <- 300L
species_id <- seq_len(n_species)
genus_id   <- ((species_id - 1L) %/% 4L) + 1L    # ~75 genera, 4 species each
family_id  <- ((genus_id - 1L) %/% 3L) + 1L        # ~25 families
order_id   <- ((family_id - 1L) %/% 2L) + 1L         # ~13 orders
class_id   <- ((order_id - 1L) %/% 2L) + 1L            # ~7 classes
phylum_id  <- ((class_id - 1L) %/% 2L) + 1L              # ~4 phyla

taxonomy <- data.frame(
  species = sprintf("species_%03d", species_id),
  genus   = sprintf("genus_%03d", genus_id),
  family  = sprintf("family_%03d", family_id),
  order   = sprintf("order_%03d", order_id),
  class   = sprintf("class_%03d", class_id),
  phylum  = sprintf("phylum_%03d", phylum_id),
  stringsAsFactors = FALSE
)

# ---- Build accessions, grouped into submission batches ---------------------
n_accessions <- 6000L
prefixes <- c("AB", "CD", "EF", "GH", "IJ", "KL", "MN", "OP", "QR", "ST")

acc_species_idx <- sample.int(n_species, n_accessions, replace = TRUE)
batch_size      <- 8L
n_batches       <- ceiling(n_accessions / batch_size)
batch_of        <- rep(seq_len(n_batches), each = batch_size)[seq_len(n_accessions)]
batch_prefix    <- prefixes[((batch_of - 1L) %% length(prefixes)) + 1L]
batch_num_base  <- ((batch_of - 1L) %/% length(prefixes)) * 100L + 1000L
within_batch    <- ave(batch_of, batch_of, FUN = seq_along)
acc_num         <- batch_num_base + within_batch
composite_id    <- sprintf("%s%06d", batch_prefix, acc_num)

batch_base_date <- as.Date("2015-01-01") + batch_of * 11L  # widely spread across batches
create_date     <- format(batch_base_date + sample(0:1, n_accessions, replace = TRUE),
                          "%Y/%m/%d")

reference_df <- cbind(
  data.frame(composite_id = composite_id, create_date = create_date,
             stringsAsFactors = FALSE),
  taxonomy[acc_species_idx, , drop = FALSE]
)
rownames(reference_df) <- NULL

message(sprintf("Synthetic reference_df: %d accessions across %d batches, %d species.",
                nrow(reference_df), n_batches, n_species))

# ---- Build a real-scale pairwise seq_matrix ---------------------------------
# Each accession gets ~100 partners: mostly same-species (including some
# same-batch siblings), plus a spread of cross-genus/family/order/phylum
# matches at lower p_match -- a realistic mix, not an adversarial worst case.
partners_per_acc <- 100L
rank_system <- c("phylum", "class", "order", "family", "genus", "species")

idx_x <- rep(seq_len(n_accessions), each = partners_per_acc)
# Vectorised partner sampling: 60% same-species, 40% uniform random.
same_species_flag <- stats::runif(length(idx_x)) < 0.6
rand_partner       <- sample.int(n_accessions, length(idx_x), replace = TRUE)
sp_lookup           <- split(seq_len(n_accessions), acc_species_idx)
same_sp_partner      <- vapply(idx_x, function(i) {
  pool <- sp_lookup[[as.character(acc_species_idx[i])]]
  if (length(pool) <= 1L) i else sample(pool[pool != i], 1L)
}, integer(1L))
partner_idx <- ifelse(same_species_flag, same_sp_partner, rand_partner)
partner_idx <- ifelse(partner_idx == idx_x, rand_partner, partner_idx)

p_match <- ifelse(
  acc_species_idx[idx_x] == acc_species_idx[partner_idx],
  stats::runif(length(idx_x), 0.95, 1.00),
  stats::runif(length(idx_x), 0.76, 0.94)
)

seq_matrix <- data.frame(
  id_x    = composite_id[idx_x],
  id_y    = composite_id[partner_idx],
  p_match = p_match,
  stringsAsFactors = FALSE
)
for (r in rank_system) {
  seq_matrix[[paste0(r, ".x")]] <- taxonomy[[r]][acc_species_idx[idx_x]]
  seq_matrix[[paste0(r, ".y")]] <- taxonomy[[r]][acc_species_idx[partner_idx]]
}

message(sprintf("Synthetic seq_matrix: %s rows.", format(nrow(seq_matrix), big.mark = ",")))

# ---- Time it ------------------------------------------------------------
t0 <- proc.time()[["elapsed"]]
result <- TaxaLikely:::.compute_hierarchy_congruence(
  seq_matrix   = seq_matrix,
  reference_df = reference_df,
  rank_system  = rank_system,
  top_n        = 5L,
  min_congruent_rank = "family",
  submission_window  = 5L
)
elapsed <- proc.time()[["elapsed"]] - t0

message(sprintf(
  "\n.compute_hierarchy_congruence(): %s rows -> %s accessions in %.2fs",
  format(nrow(seq_matrix), big.mark = ","), format(nrow(result), big.mark = ","), elapsed
))
message(sprintf(
  "  Rate: %.0f seq_matrix rows/sec",
  nrow(seq_matrix) / elapsed
))
print(table(result$n_independent_top_matches))
