# TaxaLikely workflow example
# Run this script interactively to test all functions end-to-end.
# Requires TaxaLikely to be installed: devtools::install() from the package dir.
#
# This script has three stages:
#   A. Build a toy dataset (no real data needed) to verify functions run
#   B. Apply to a real match object (swap in your data)
#   C. Downstream: apply coverage constraints (optional, needs internet)

library(TaxaLikely)
library(DECIPHER)

# ==============================================================================
# STAGE A: TOY DATA -- verify everything runs without real sequences
# ==============================================================================
# We skip build_sequence_matrix() (needs DECIPHER) and instead hand-craft
# a minimal pairwise distance matrix of the kind it would produce.
# p_match is on 0-1 scale (= 1 - DECIPHER distance).

# 4 sequences: 3 Leuciscus cephalus (Lc1, Lc2, Lc3) + 1 Cyprinus carpio (Cc1)
# Full symmetric 4x4 matrix (all pairs, including self-matches).
# Built as expand.grid to avoid index misalignment errors.
.seqs <- c("Lc1", "Lc2", "Lc3", "Cc1")
.sp   <- c("Leuciscus cephalus", "Leuciscus cephalus",
           "Leuciscus cephalus", "Cyprinus carpio")
.gen  <- c("Leuciscus", "Leuciscus", "Leuciscus", "Cyprinus")

# Pairwise p_match (0-1 scale); symmetric
.pm <- matrix(
  c(1.00, 0.97, 0.96, 0.72,
    0.97, 1.00, 0.98, 0.71,
    0.96, 0.98, 1.00, 0.72,
    0.72, 0.71, 0.72, 1.00),
  nrow = 4, dimnames = list(.seqs, .seqs)
)

idx <- expand.grid(i = seq_along(.seqs), j = seq_along(.seqs))
toy_matrix <- data.frame(
  id_x      = .seqs[idx$i],
  id_y      = .seqs[idx$j],
  species.x = .sp[idx$i],
  species.y = .sp[idx$j],
  genus.x   = .gen[idx$i],
  genus.y   = .gen[idx$j],
  p_match   = .pm[cbind(idx$i, idx$j)],
  stringsAsFactors = FALSE
)
rm(.seqs, .sp, .gen, .pm, idx)

# ---- A1. Flag reference errors -----------------------------------------------
message("\n--- A1. flag_reference_errors ---")
errors <- flag_reference_errors(toy_matrix, return_all = TRUE)
print(errors)
# Expect: all "clean" -- no mislabeling in toy data

# ---- A2. Train model ---------------------------------------------------------
message("\n--- A2. train_likelihood_model ---")
model <- train_likelihood_model(
  raw_df         = toy_matrix,
  rank_system    = c("genus", "species"),
  use_hierarchy  = FALSE          # too few ranks for lme4 with 2 levels
)
str(model, max.level = 1)

# ---- A3. Interpret model -----------------------------------------------------
message("\n--- A3. interpret_model ---")
interp <- interpret_model(model)
# Read the report: H1 expected match %, H2/H3 baselines, per-species thresholds

# ---- A4. Build a toy match object --------------------------------------------
# One ESV with hits to three taxa
toy_match <- data.frame(
  observation_id       = "ESV_001",
  score           = c(96.5, 83.2, 72.1, 96.3, 95.8),
  taxon_name      = c("Leuciscus cephalus", "Alburnus alburnus",
                      "Rutilus rutilus", "Leuciscus cephalus",
                      "Leuciscus cephalus"),
  taxon_name_rank = "species",
  genus           = c("Leuciscus", "Alburnus", "Rutilus",
                      "Leuciscus", "Leuciscus"),
  species         = c("Leuciscus cephalus", "Alburnus alburnus",
                      "Rutilus rutilus", "Leuciscus cephalus",
                      "Leuciscus cephalus"),
  accession       = c("NC_001","NC_002","NC_003","NC_004","NC_005"),
  stringsAsFactors = FALSE
)

# ---- A5. Evaluate likelihoods ------------------------------------------------
message("\n--- A5. evaluate_likelihoods ---")
lik_result <- evaluate_likelihoods(
  match_df    = toy_match,
  model_params = model,
  rank_system  = c("genus", "species"),
  n_sims       = 100L    # Monte Carlo for credible intervals
)
print(lik_result$likelihoods)
# Expect: Leuciscus cephalus with high likelihood_point_est

# Check for unresolved queries (family-level-only matches)
if (nrow(lik_result$unresolved) > 0L) {
  cat("Unresolved observation_ids:", unique(lik_result$unresolved$observation_id), "\n")
}

# ---- A6. Filter top hypotheses -----------------------------------------------
message("\n--- A6. filter_top_hypotheses ---")
filtered <- filter_top_hypotheses(lik_result$likelihoods, rank_system = c("genus", "species"))
print(filtered)

# ==============================================================================
# STAGE B: REAL DATA -- build reference matrix from match_obj NCBI accessions
# ==============================================================================
# Requires: rentrez (NCBI fetch), DECIPHER (alignment), internet access.
# Run interactively; the matrix step can take several minutes for large datasets.
# The result is cached to inst/real_matrix.rds so you only build it once.

match_obj <- readRDS("~/My Drive/Rscripts/projects/TaxaID/TaxaMatch/inst/match_obj.rds")

# Confirm columns
stopifnot(all(c("observation_id", "score", "taxon_name", "taxon_name_rank") %in% names(match_obj)))
cat("match_obj rows:", nrow(match_obj), "| unique accessions:", dplyr::n_distinct(match_obj$accession), "\n")

# ---- B1. Build real_matrix (or load cached copy) ----------------------------
real_matrix_path <- file.path(
  system.file("", package = "TaxaLikely"), "real_matrix.rds"
)

if (file.exists(real_matrix_path)) {
  message("Loading cached real_matrix from ", real_matrix_path)
  real_matrix <- readRDS(real_matrix_path)

} else {
  if (!requireNamespace("rentrez", quietly = TRUE))
    stop("Package 'rentrez' is required to fetch sequences. Install with: install.packages('rentrez')")

  # Extract unique NCBI accessions (exclude local vouchers: JV_voucher_*)
  ncbi_rows <- match_obj[!grepl("^JV_voucher", match_obj$accession, ignore.case = TRUE), ]
  acc_unique <- unique(ncbi_rows$accession)
  acc_unique <- acc_unique[!is.na(acc_unique) & nchar(trimws(acc_unique)) > 0L]
  cat("Fetching", length(acc_unique), "NCBI sequences via rentrez...\n")

  # Fetch in batches of 50 (NCBI rate limit)
  batch_size <- 50L
  fasta_chunks <- vector("list", ceiling(length(acc_unique) / batch_size))
  for (i in seq_along(fasta_chunks)) {
    idx_start <- (i - 1L) * batch_size + 1L
    idx_end   <- min(i * batch_size, length(acc_unique))
    batch     <- acc_unique[idx_start:idx_end]
    fasta_chunks[[i]] <- rentrez::entrez_fetch(
      db      = "nuccore",
      id      = batch,
      rettype = "fasta",
      retmode = "text"
    )
    Sys.sleep(0.4)   # stay within 3 requests/second
  }
  fasta_text <- paste(fasta_chunks, collapse = "")

  # Parse FASTA into data frame: header + sequence
  lines       <- strsplit(fasta_text, "\n")[[1L]]
  header_idx  <- which(startsWith(lines, ">"))
  seq_end_idx <- c(header_idx[-1L] - 1L, length(lines))

  composite_ids <- character(length(header_idx))
  sequences     <- character(length(header_idx))
  for (k in seq_along(header_idx)) {
    hdr <- sub("^>", "", lines[header_idx[k]])
    # accession = first whitespace-delimited token; strip version suffix (.1 etc.)
    composite_ids[k] <- sub("\\.[0-9]+$", "", strsplit(trimws(hdr), "\\s+")[[1L]][1L])
    sequences[k]     <- paste(lines[(header_idx[k] + 1L):seq_end_idx[k]], collapse = "")
  }

  fasta_df <- data.frame(
    composite_id = composite_ids,
    sequence     = sequences,
    stringsAsFactors = FALSE
  )
  # Remove any empty sequences
  fasta_df <- fasta_df[nchar(fasta_df$sequence) > 0L, ]
  cat("Parsed", nrow(fasta_df), "sequences from FASTA.\n")

  # Build taxonomy lookup from match_obj (one row per accession)
  tax_lookup <- ncbi_rows[!duplicated(ncbi_rows$accession), ]
  tax_lookup$composite_id <- sub("\\.[0-9]+$", "", tax_lookup$accession)

  # Join sequences to taxonomy
  reference_df <- merge(fasta_df, tax_lookup[, c("composite_id", "family", "genus", "species")],
                        by = "composite_id", all.x = TRUE)
  reference_df <- reference_df[!is.na(reference_df$species), ]
  cat("reference_df rows after taxonomy join:", nrow(reference_df), "\n")

  # Build pairwise distance matrix (requires DECIPHER; ~minutes for 100+ seqs)
  message("Building reference matrix with DECIPHER alignment...")
  real_matrix <- build_sequence_matrix(
    reference_df = reference_df,
    rank_system  = c("family", "genus", "species")
  )

  # Cache for future runs
  saveRDS(real_matrix, real_matrix_path)
  message("Saved real_matrix to ", real_matrix_path)
}

cat("real_matrix rows:", nrow(real_matrix), "\n")

# ---- B2. Train model ---------------------------------------------------------
message("\n--- B2. train_likelihood_model (real data) ---")
real_model <- train_likelihood_model(
  raw_df       = real_matrix,
  rank_system  = c("family", "genus", "species"),
  prior_weight = 10.0
)
str(real_model, max.level = 1)
interpret_model(real_model)

saveRDS(real_model, file.path(system.file("", package = "TaxaLikely"), "real_model.rds"))
message("Saved real_model.")

# ---- B3. Evaluate likelihoods -----------------------------------------------
message("\n--- B3. evaluate_likelihoods (real data) ---")
real_lik_result <- evaluate_likelihoods(
  match_df     = match_obj,
  model_params = real_model,
  rank_system  = c("family", "genus", "species"),
  n_sims       = 200L
)
real_likelihoods <- real_lik_result
cat("Likelihood rows:", nrow(real_likelihoods$likelihoods), "\n")
print(head(real_likelihoods$likelihoods))

# Inspect unresolved queries (family-level-only matches)
if (nrow(real_lik_result$unresolved) > 0L) {
  cat("Unresolved observation_ids:", dplyr::n_distinct(real_lik_result$unresolved$observation_id), "\n")
  # Optionally re-run at family level:
  # real_lik_family <- evaluate_likelihoods(
  #   match_df     = real_lik_result$unresolved,
  #   model_params = real_model,
  #   rank_system  = c("order", "family"),
  #   n_sims       = 200L
  # )
}

saveRDS(real_likelihoods,
        "/Users/lafferty/My Drive/Rscripts/projects/TaxaID/TaxaLikely/inst/real_likelihoods.rds")

message("Saved real_likelihoods.")

# ==============================================================================
# STAGE C: COVERAGE CONSTRAINTS (needs internet)
# ==============================================================================
# Run after Stage B. Uses reference_df built above (genus + species columns).
#
# Unreferenced species: described taxa with NO barcode sequence for the target marker.
# TaxaMatch cannot return these as named candidates even if they are the true
# source of an observed sequence.
#
# audit_barcode_coverage() workflow per genus:
#   1. All described species from NCBI taxonomy (or user-supplied species_list).
#   2. Species in reference_df are skipped (confirmed sequenced).
#   3. Each remaining species: retmax=0 count query to NCBI nucleotide.
#      count=0 -> unreferenced; count>0 -> has sequences but missing from reference.
#
# For non-barcode libraries (images, sounds) use audit_reference_coverage()
# instead (queries NCBI taxonomy tree, no sequence check needed).
#
# Census columns:
#   total               - described species in this genus
#   in_reference        - species in reference_df (skip-list)
#   has_seqs_not_in_ref - have barcode sequences but absent from reference
#   unreferenced        - no barcode sequence found (the unreferenced species list)
#   is_complete         - TRUE when both gaps are zero

coverage <- audit_barcode_coverage(
  reference_df[!duplicated(reference_df$species), c("genus", "species")],
  barcode_term = "12S",   # adjust to your marker: "COI", "ITS2", etc.
  target_rank  = "genus"
  # max_date    = "2024/12/31",  # restrict to sequences available by this date
  # species_list = my_fishbase_spp,  # optional: more complete than NCBI taxonomy
)
print(coverage$census)
cat("Unreferenced species:\n"); print(coverage$unreferenced)

# Reshape census for apply_coverage_constraints():
census_result <- dplyr::mutate(
  coverage$census,
  taxon_name = group,
  rank       = "genus",
  status     = ifelse(is_complete, "complete", "incomplete")
)


# Check: unreferenced_species rows for complete genera now have likelihood = 0
constrained <- apply_coverage_constraints(real_likelihoods$likelihoods, census_result)
message("\nWorkflow complete.")
# Next step: obtain data for priors using TaxaFetch.
# see inst/TaxaAssign_bayesian_workflow.R in TaxaAssign for the full
# pipeline including unreferenced hypothesis expansion and compute_posterior().
