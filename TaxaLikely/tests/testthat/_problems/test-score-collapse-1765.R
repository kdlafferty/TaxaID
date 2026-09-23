# Extracted from test-score-collapse.R:1765

# setup ------------------------------------------------------------------------
library(testthat)
test_env <- simulate_test_env(package = "TaxaLikely", path = "..")
attach(test_env, warn.conflicts = FALSE)

# prequel ----------------------------------------------------------------------
make_match <- function(obs_id = "obs1", score = 100, genus = "Girella",
                       species = "simplicidens") {
  data.frame(
    observation_id = obs_id,
    score_original = score,
    taxon_name = species,
    taxon_name_rank = "species",
    family = "Kyphosidae",
    genus = genus,
    species = species,
    stringsAsFactors = FALSE
  )
}
make_ref <- function(genus = "Girella",
                     species = c("simplicidens", "nigricans", "laevifrons")) {
  data.frame(
    family = "Kyphosidae",
    genus = genus,
    species = species,
    composite_id = paste0("ACC_", species),
    stringsAsFactors = FALSE
  )
}
make_seq_matrix_for_ref <- function(ref, p_match = 0.95) {
  ids <- unique(ref$composite_id)
  if (length(ids) < 2L) {
    return(data.frame(
      id_x = character(0), id_y = character(0),
      p_match = numeric(0), coverage = numeric(0),
      stringsAsFactors = FALSE
    ))
  }
  combos <- utils::combn(ids, 2L)
  data.frame(
    id_x = combos[1L, ],
    id_y = combos[2L, ],
    p_match = p_match,
    coverage = 1.0,
    stringsAsFactors = FALSE
  )
}
.check_regional_overlap <- function(...) {
  get(".check_regional_overlap", envir = asNamespace("TaxaLikely"))(...)
}
region_A <- "ACGTTGCAATCGGATCCGTAGCTTAACGGTTCCAAGGTTCAGGCTTAACCGGATCGGTA"
region_B <- "TTGGCCAATTCCGGAACCTTGGAACCTTAAGGCCTTAAGGCCAATTGGCCTTAAGGCCA"
spacer <- "GATTACAGATTACAGATTACAGATTACAGATTACAGATTACAGATTACAGATTACAGA"
anchor_full <- paste0(region_A, spacer, region_B)
region_A_range <- c(1L, 60L)
region_B_start <- nchar(region_A) + nchar(spacer) + 1L
region_B_range <- c(region_B_start, region_B_start + 59L)
.mutate_seq <- function(s, positions, new_bases) {
  chars <- strsplit(s, "")[[1]]
  chars[positions] <- new_bases
  paste(chars, collapse = "")
}
candidate_seq <- .mutate_seq(region_A, c(5, 20, 40), c("T", "A", "G"))
make_overlap_ref_df <- function() {
  data.frame(
    composite_id = c("ANCHOR_ACC", "CANDIDATE_ACC"),
    sequence = c(anchor_full, candidate_seq),
    genus = c("Testgenus", "Testgenus"),
    species = c("Testgenus anchorus", "Testgenus candidatus"),
    stringsAsFactors = FALSE
  )
}
.simple_model_params <- function(sigma11 = 0.05) {
  list(
    H1_Sigma = matrix(c(sigma11, 0, 0, 1),
      nrow = 2,
      dimnames = list(
        c("score_logit", "gap_logit"),
        c("score_logit", "gap_logit")
      )
    ),
    H1_Lookup = NULL,
    Score_Transform = "logit"
  )
}

# test -------------------------------------------------------------------------
cache <- new.env()
many <- sprintf("ACC%09d.1", seq_len(2000L))
sm <- data.frame(id_x = many[1:10], id_y = many[11:20], stringsAsFactors = FALSE)
expect_no_error(first <- TaxaLikely:::.has_seq_matrix_presence(many, sm, cache))
expect_true(first)
keys <- ls(cache)
expect_true(all(nchar(keys) < 100L))
expect_identical(TaxaLikely:::.has_seq_matrix_presence(many, sm, cache), first)
