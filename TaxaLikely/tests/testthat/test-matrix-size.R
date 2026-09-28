# Predicting the sequence-matrix memory cost: the structural pair count, the
# deterministic caps shared by the fetch and the estimator, the available-
# memory readers, the estimator itself, the guard in build_sequence_matrix(),
# and the fetch's dry run. All offline: NCBI and the operating system are
# mocked.

# --- Structure ----------------------------------------------------------------

test_that(".matrix_structure counts ordered pairs, foreign reps and rep-vs-rep", {
  # Genera of 3, 1 and 2 sequences; f = min(20, G - 1) = 2.
  st <- TaxaLikely:::.matrix_structure(c(3, 1, 2), by_genus = TRUE, max_foreign_reps_per_genus = 20L)
  expect_equal(st$S_w, 3 * 2 + 0 + 2 * 1)
  # Each non-representative sequence against 2 foreign reps, both directions
  # (3 non-reps), plus the 3 x 2 ordered rep-vs-rep pairs.
  expect_equal(st$S_x, 2 * 2 * (2 + 0 + 1) + 3 * 2)
  expect_equal(st$G, 3L)
  expect_equal(st$N, 6)

  # The foreign-rep cap binds when there are more genera than it allows.
  st <- TaxaLikely:::.matrix_structure(rep(5, 30), by_genus = TRUE, max_foreign_reps_per_genus = 20L)
  expect_equal(st$f, 20)
  expect_equal(st$S_x, 2 * 20 * 30 * 4 + 30 * 29)

  # Whole-set: every ordered pair.
  st <- TaxaLikely:::.matrix_structure(c(3, 1, 2), by_genus = FALSE)
  expect_equal(st$S_w + st$S_x, 6 * 5)
})

test_that("the structure matches a real build when nothing is filtered out", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  set.seed(1)
  base <- paste(sample(c("A", "C", "G", "T"), 120, replace = TRUE), collapse = "")
  mutate <- function(s, k) {
    ch <- strsplit(s, "")[[1]]
    pos <- sample(length(ch), k)
    ch[pos] <- sample(c("A", "C", "G", "T"), k, replace = TRUE)
    paste(ch, collapse = "")
  }
  ref <- data.frame(
    composite_id = sprintf("X%02d", 1:9),
    sequence = vapply(1:9, function(i) mutate(base, 3), character(1)),
    genus = c("Ga", "Ga", "Ga", "Gb", "Gc", "Gc", "Gd", "Gd", "Gd"),
    species = c("Ga a", "Ga a", "Ga b", "Gb a", "Gc a", "Gc b", "Gd a", "Gd a", "Gd b"),
    stringsAsFactors = FALSE
  )
  m <- suppressMessages(build_sequence_matrix(
    ref, rank_system = c("genus", "species"), min_seq_len = 50L, max_seq_len = 500L,
    max_dist = 2, by_genus = TRUE, verbose = FALSE, memory_budget_fraction = NULL
  ))
  st <- TaxaLikely:::.matrix_structure(c(3, 1, 2, 3), by_genus = TRUE)
  expect_equal(nrow(m), st$S_w + st$S_x)
  cal <- attr(m, "size_calibration")
  expect_equal(cal$r_w, 1)
  expect_equal(cal$r_x, 1)
  expect_equal(cal$S_w + cal$S_x, nrow(m))
})


# --- Deterministic caps -------------------------------------------------------

make_meta <- function() {
  data.frame(
    acc = sprintf("MK%06d", 1:60),
    genus = rep(c("Delia", "Sebastes"), c(50, 10)),
    species = c(rep("Delia platura", 40), rep("Delia radicum", 6), rep("Delia antiqua", 4),
                rep("Sebastes mystinus", 10)),
    in_barcode_range = TRUE,
    stringsAsFactors = FALSE
  )
}

test_that(".stable_key is deterministic, ignores the version, and scatters runs", {
  a <- TaxaLikely:::.stable_key(c("KY492600.1", "KY492600.2", "KY492600"))
  expect_equal(a[1], a[2])
  expect_equal(a[1], a[3])
  expect_identical(TaxaLikely:::.stable_key("AB000001"), TaxaLikely:::.stable_key("AB000001"))
  # A run of consecutive accessions (one study) must not come out in order.
  k <- TaxaLikely:::.stable_key(sprintf("MK%06d", 1:2000))
  expect_lt(abs(stats::cor(seq_along(k), rank(k), method = "spearman")), 0.1)
})

test_that("caps are deterministic and a smaller cap keeps a subset", {
  meta <- make_meta()
  a <- TaxaLikely:::.apply_reference_caps(meta, NULL, 20)
  b <- TaxaLikely:::.apply_reference_caps(meta, NULL, 20)
  expect_identical(a$acc, b$acc)
  small <- TaxaLikely:::.apply_reference_caps(meta, NULL, 10)
  expect_true(all(small$acc %in% a$acc))
  expect_equal(sum(a$genus == "Delia"), 20)
  expect_equal(sum(a$genus == "Sebastes"), 10)

  sp <- TaxaLikely:::.apply_reference_caps(meta, 5, NULL)
  expect_equal(as.integer(table(sp$species)[["Delia platura"]]), 5L)
  expect_equal(as.integer(table(sp$species)[["Delia antiqua"]]), 4L)
  # Species cap first, then genus cap on what remains: 5 + 5 + 4 = 14 Delia.
  both <- TaxaLikely:::.apply_reference_caps(meta, 5, 12)
  expect_equal(sum(both$genus == "Delia"), 12)
  expect_true(all(both$acc %in% sp$acc))
})

test_that("out-of-range and exempt rows are neither capped nor counted", {
  meta <- make_meta()
  meta$in_barcode_range[1:3] <- FALSE
  exempt <- seq_len(nrow(meta)) %in% 4:8
  out <- TaxaLikely:::.apply_reference_caps(meta, NULL, 2, exempt = exempt)
  expect_true(all(meta$acc[1:8] %in% out$acc))
  # Two capped Delia rows beyond the 8 kept unconditionally.
  expect_equal(sum(out$genus == "Delia"), 8 + 2)
})


# --- Available memory ---------------------------------------------------------

test_that("vm_stat is read as free + inactive + speculative + purgeable", {
  lines <- c(
    "Mach Virtual Memory Statistics: (page size of 16384 bytes)",
    "Pages free:                                5000.",
    "Pages active:                            900000.",
    "Pages inactive:                          600000.",
    "Pages speculative:                        20000.",
    "Pages throttled:                              0.",
    "Pages wired down:                        200000.",
    "Pages purgeable:                          10000."
  )
  expect_equal(
    TaxaLikely:::.parse_vm_stat(lines),
    (5000 + 600000 + 20000 + 10000) * 16384 / 2^30
  )
  expect_true(is.na(TaxaLikely:::.parse_vm_stat(character(0))))
})

test_that("meminfo is read as MemAvailable", {
  lines <- c("MemTotal:       32000000 kB", "MemFree:         1000000 kB",
             "MemAvailable:   12000000 kB")
  expect_equal(TaxaLikely:::.parse_meminfo(lines), 12000000 * 1024 / 2^30)
  expect_true(is.na(TaxaLikely:::.parse_meminfo("MemTotal: 1 kB")))
})


# --- The estimator ------------------------------------------------------------

test_that("the estimator evaluates every cap combination and names lost species", {
  meta <- make_meta()
  est <- estimate_sequence_matrix_size(
    meta, max_per_species = c(NA, 5), max_per_genus = c(NA, 3), available_gb = 16
  )
  expect_equal(nrow(est$grid), 4L)
  expect_equal(length(est$species_dropped), 4L)
  row <- which(is.na(est$grid$max_per_species) & is.na(est$grid$max_per_genus))
  expect_equal(est$grid$n_sequences[row], 60)
  expect_length(est$species_dropped[[row]], 0L)
  # A genus cap of 3 across three Delia species can drop whole species; the
  # species cap never does.
  row_sp <- which(est$grid$max_per_species %in% 5 & is.na(est$grid$max_per_genus))
  expect_length(est$species_dropped[[row_sp]], 0L)
  row_g <- which(is.na(est$grid$max_per_species) & est$grid$max_per_genus %in% 3)
  expect_equal(est$grid$n_sequences[row_g], 6)
  expect_equal(est$grid$n_species_dropped[row_g], length(est$species_dropped[[row_g]]))
  expect_true(all(est$grid$pairs_predicted <= est$grid$pairs_ceiling))
  expect_true(all(est$grid$fits))
  expect_equal(est$budget_gb, 16 * 0.7)
})

test_that("the estimator accepts a count table and unknown memory", {
  counts <- data.frame(
    genus = c("Delia", "Delia", "Sebastes"),
    species = c("Delia platura", "Delia radicum", "Sebastes mystinus"),
    n = c(13116L, 900L, 60L)
  )
  est <- estimate_sequence_matrix_size(counts, max_per_species = NA, max_per_genus = NA,
                                       available_gb = NA)
  expect_equal(est$grid$n_sequences, 13116 + 900 + 60)
  expect_true(is.na(est$grid$fits))
  # Memory scales with the square of the largest genus: capping it is what matters.
  capped <- estimate_sequence_matrix_size(counts, max_per_species = 20, max_per_genus = NA,
                                          available_gb = NA)
  expect_lt(capped$grid$pairs_ceiling, est$grid$pairs_ceiling / 100)
})

test_that("calibration replaces the default retention rates", {
  meta <- make_meta()
  cal <- list(S_w = 100, S_x = 1000, within_pairs = 50, cross_pairs = 900)
  est <- estimate_sequence_matrix_size(meta, max_per_species = NA, max_per_genus = NA,
                                       calibration = cal, available_gb = 16)
  expect_equal(est$rates$r_w, 0.5)
  expect_equal(est$rates$r_x, 0.9)
  expect_match(est$rates$source, "1 earlier build")
  expect_error(
    estimate_sequence_matrix_size(meta, calibration = list(a = 1), available_gb = 1),
    "calibration must be"
  )
})

test_that("the estimator validates its inputs", {
  expect_error(estimate_sequence_matrix_size(data.frame(a = 1)), "genus")
  expect_error(estimate_sequence_matrix_size(make_meta(), max_per_genus = 0, available_gb = 1),
               "positive")
  expect_error(estimate_sequence_matrix_size(make_meta(), memory_budget_fraction = 2,
                                             available_gb = 1), "memory_budget_fraction")
})


# --- The guard in build_sequence_matrix() -------------------------------------

guard_ref <- function() {
  data.frame(
    composite_id = sprintf("G%03d", 1:40),
    sequence = strrep("ACGTACGTAC", 12),
    genus = rep(c("Ga", "Gb", "Gc", "Gd"), each = 10),
    species = rep(sprintf("S%02d", 1:8), each = 5),
    stringsAsFactors = FALSE
  )
}

test_that("the guard stops before aligning and names settings when memory is short", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  local_mocked_bindings(
    .available_memory_gb = function() 1e-5,
    .pilot_cross_genus_retention = function(...) 0.3,
    .decipher_align_pairs = function(...) stop("aligned despite the guard")
  )
  expect_error(
    suppressMessages(build_sequence_matrix(
      guard_ref(), rank_system = c("genus", "species"),
      min_seq_len = 50L, max_seq_len = 500L, by_genus = TRUE
    )),
    "Stopped before aligning"
  )
})

test_that("the guard lists caps that fit when some do", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  # One large genus (Ga: 400 sequences in two species) that a genus cap of
  # 250 or 100 brings within budget.
  ref <- data.frame(
    composite_id = sprintf("G%04d", 1:430),
    sequence = strrep("ACGTACGTAC", 12),
    genus = rep(c("Ga", "Gb", "Gc", "Gd"), c(400, 10, 10, 10)),
    species = c(rep("Ga a", 300), rep("Ga b", 100), rep(c("Gb a", "Gc a", "Gd a"), each = 10)),
    stringsAsFactors = FALSE
  )
  st <- TaxaLikely:::.matrix_structure(c(400, 10, 10, 10), TRUE, 20L)
  full <- TaxaLikely:::.matrix_memory_gb(st, 1, 0.35, 2, TaxaLikely:::.matrix_size_constants()$peak)
  # Just too little for the full set.
  local_mocked_bindings(
    .available_memory_gb = function() full$gb_peak / 0.7 * 0.9,
    .pilot_cross_genus_retention = function(...) 0.3,
    .decipher_align_pairs = function(...) stop("aligned despite the guard")
  )
  expect_error(
    suppressMessages(build_sequence_matrix(
      ref, rank_system = c("genus", "species"),
      min_seq_len = 50L, max_seq_len = 500L, by_genus = TRUE
    )),
    "max_per_species = .*, max_per_genus = [0-9]+: "
  )
})

test_that("the guard is skipped when memory cannot be read or when disabled", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  local_mocked_bindings(
    .available_memory_gb = function() NA_real_,
    .decipher_align_pairs = function(...) stop("reached alignment")
  )
  expect_message(
    expect_error(
      build_sequence_matrix(
        guard_ref(), rank_system = c("genus", "species"),
        min_seq_len = 50L, max_seq_len = 500L, by_genus = TRUE, verbose = FALSE
      ),
      "reached alignment"
    ),
    "could not be read"
  )
  local_mocked_bindings(.available_memory_gb = function() stop("guard ran"))
  expect_error(
    suppressMessages(build_sequence_matrix(
      guard_ref(), rank_system = c("genus", "species"),
      min_seq_len = 50L, max_seq_len = 500L, by_genus = TRUE,
      memory_budget_fraction = NULL
    )),
    "reached alignment"
  )
  expect_error(
    build_sequence_matrix(guard_ref(), memory_budget_fraction = 0),
    "memory_budget_fraction"
  )
})

test_that("the guard does not touch the caller's RNG stream", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  local_mocked_bindings(
    .available_memory_gb = function() 1e-5,
    .decipher_align_pairs = function(dna, ...) {
      data.frame(id_x = character(0), id_y = character(0),
                 p_match = numeric(0), coverage = numeric(0))
    }
  )
  set.seed(42)
  try(suppressMessages(build_sequence_matrix(
    guard_ref(), rank_system = c("genus", "species"),
    min_seq_len = 50L, max_seq_len = 500L, by_genus = TRUE
  )), silent = TRUE)
  after_guard <- stats::runif(1)
  set.seed(42)
  expect_equal(after_guard, stats::runif(1))
})


# --- The fetch's dry run ------------------------------------------------------

write_uncapped_cache <- function(cache_dir, taxon, species, n_each) {
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  sp <- rep(species, n_each)
  accs <- sprintf("%s%05d.1", toupper(substr(taxon, 1, 2)), seq_along(sp))
  meta <- data.frame(
    taxid = "1", acc = sub("\\.1$", "", accs), acc_version = accs,
    title = paste(taxon, "12S ribosomal RNA gene"),
    slen = 400L, organism = sp, create_date = "2026/08/29",
    in_barcode_range = TRUE, family = paste0(taxon, "idae"),
    genus = taxon, species = sp, stringsAsFactors = FALSE
  )
  attr(meta, "sel_params") <- TaxaLikely:::.sel_params(
    NULL, NULL, "uncultured|environmental|predicted|vector|synthetic|unverified"
  )
  saveRDS(meta, file.path(cache_dir, sprintf(
    "%s_12S_l100_5000_d_rk-family-genus-species_meta.rds", taxon
  )))
  meta
}

test_that("a dry run on a warm cache makes no NCBI request and downloads nothing", {
  skip_if_not_installed("rentrez")
  cache_dir <- tempfile("tl_dry_")
  write_uncapped_cache(cache_dir, "Sebastes", c("Sebastes mystinus", "Sebastes miniatus"), c(30, 5))
  write_uncapped_cache(cache_dir, "Delia", c("Delia platura", "Delia radicum"), c(60, 4))

  calls <- character(0)
  local_mocked_bindings(
    entrez_search = function(...) { calls <<- c(calls, "search"); list(count = "0") },
    entrez_summary = function(...) { calls <<- c(calls, "summary"); stop("no") },
    entrez_fetch = function(...) { calls <<- c(calls, "fetch"); stop("no") },
    .package = "rentrez"
  )
  local_mocked_bindings(.available_memory_gb = function() 16)

  res <- suppressMessages(fetch_ncbi_reference_sequences(
    taxa = c("Sebastes", "Delia"), barcode_term = "12S",
    min_len = 100L, max_len = 5000L, cache_dir = cache_dir,
    max_per_species = NULL, max_per_genus = 20L, dry_run = TRUE
  ))
  expect_length(calls, 0L)
  expect_equal(nrow(res$sequences), 30 + 5 + 60 + 4)
  expect_true(all(res$taxa$cached))
  expect_equal(res$taxa$sequences, c(35L, 64L))
  # The call's own caps are the first row of the grid.
  expect_true(is.na(res$grid$max_per_species[1]))
  expect_equal(res$grid$max_per_genus[1], 20)
  expect_equal(res$grid$n_sequences[1], 20 + 20)
  expect_equal(res$available_gb, 16)
})

test_that("the real run keeps exactly the rows the dry run predicted", {
  skip_if_not_installed("rentrez")
  cache_dir <- tempfile("tl_dry_")
  write_uncapped_cache(cache_dir, "Delia", c("Delia platura", "Delia radicum", "Delia antiqua"),
                       c(60, 4, 2))
  fetched <- character(0)
  local_mocked_bindings(
    entrez_search = function(...) list(count = "0"),
    entrez_fetch = function(db, id, rettype, retmode, ...) {
      fetched <<- c(fetched, id)
      paste(sprintf(">%s Fake\nACGTACGTACGTACGTACGT", id), collapse = "\n")
    },
    .package = "rentrez"
  )
  local_mocked_bindings(.available_memory_gb = function() 16)

  dry <- suppressMessages(fetch_ncbi_reference_sequences(
    taxa = "Delia", barcode_term = "12S", min_len = 100L, max_len = 5000L,
    cache_dir = cache_dir, max_per_genus = 5L, dry_run = TRUE
  ))
  expect_length(fetched, 0L)
  ref <- suppressMessages(fetch_ncbi_reference_sequences(
    taxa = "Delia", barcode_term = "12S", min_len = 100L, max_len = 5000L,
    cache_dir = cache_dir, max_per_genus = 5L
  ))
  expect_equal(nrow(ref), 5L)
  expect_equal(nrow(ref), dry$grid$n_sequences[1])
  expect_setequal(
    setdiff(unique(dry$sequences$species), unique(ref$species)),
    dry$species_dropped[[1]]
  )
  # Only the kept sequences were downloaded.
  expect_equal(length(unique(fetched)), 5L)
})

test_that("dry_run is validated", {
  expect_error(
    fetch_ncbi_reference_sequences("Delia", "12S", dry_run = NA),
    "dry_run"
  )
})

test_that("a retained build reports the unretained ceiling and does not refuse to run", {
  # A reference set whose ceiling cannot fit a tiny budget: with
  # pair_retention = "all" the guard stops; with a retention policy the table
  # is thinned inside the alignment loop, so the ceiling is an upper bound
  # the build will not reach and the guard reports instead of stopping.
  ref <- data.frame(
    composite_id = sprintf("ACC%04d", 1:400),
    genus = rep(sprintf("Genus%02d", 1:4), each = 100),
    species = rep(sprintf("Genus%02d sp%d", rep(1:4, each = 5), 1:5), each = 20),
    stringsAsFactors = FALSE
  )
  dna <- Biostrings::DNAStringSet(setNames(rep(strrep("ACGT", 40), 400), ref$composite_id))
  local_mocked_bindings(.available_memory_gb = function() 0.001)

  expect_error(
    TaxaLikely:::.matrix_memory_guard(
      ref, dna, n_ranks = 2L, by_genus = TRUE, max_foreign_reps_per_genus = 20L,
      max_dist = 0.25, memory_budget_fraction = 0.7, max_seqs_per_taxon = 20L,
      pair_retention = "all"
    )
  )
  expect_message(
    st <- TaxaLikely:::.matrix_memory_guard(
      ref, dna, n_ranks = 2L, by_genus = TRUE, max_foreign_reps_per_genus = 20L,
      max_dist = 0.25, memory_budget_fraction = 0.7, max_seqs_per_taxon = 20L,
      pair_retention = "best_per_partner"
    ),
    "upper bound"
  )
  expect_true(is.list(st))
})
