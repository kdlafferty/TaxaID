# Edge: reference_df -> reference_matrix
# Source: TaxaLikely build_sequence_matrix()

# These are the production choices, not the defaults. Each one changes the
# fitted model, so a run that omits them is fitting something different:
#   by_genus = TRUE          align WITHIN genus. The default (FALSE) aligns the
#                            whole set at once, which is where large reference
#                            sets become unrunnable.
#   pair_retention           keeps every within-species pair and, per sequence,
#     = "best_per_partner"   only its best match to each partner taxon. The
#                            default "all" leaves the between-species pair count
#                            quadratic in genus size.
#   max_seqs_per_taxon = 20L species-stratified cap. Prefer this to a genus cap:
#                            a genus cap drops WHOLE SPECIES, and H2/H3 estimate
#                            BETWEEN-species divergence, so it would bias exactly
#                            the quantity being fitted.
#   min_pair_coverage        must equal train_likelihood_model(min_pair_coverage).
#   seed                     the build draws at random; set it or the matrix is
#                            not reproducible.
ref_matrix <- TaxaLikely::build_sequence_matrix(
  reference_df               = {{input_var}},
  by_genus                   = TRUE,
  max_seqs_per_taxon         = 20L,
  max_foreign_reps_per_genus = 20L,
  pair_retention             = "best_per_partner",
  min_pair_coverage          = 0.8,
  seed                       = 1L
)
message("Built reference matrix: ", nrow(ref_matrix), " pairwise comparisons")
ref_matrix
