# restore_suppressed_candidates(registry =): "already a candidate?" and "in the filter?" by registry id.
# Fixtures: helper-registry.R (Hypsurus caryi, synonym Embiotoca caryi; Embiotoca jacksoni).

.rr_match <- function(genus, species) data.frame(observation_id = "obs1", score_original = 100, taxon_name = species,
  taxon_name_rank = "species", family = "Embiotocidae", genus = genus, species = species, stringsAsFactors = FALSE)
.rr_ref <- function(genus, species) data.frame(family = "Embiotocidae", genus = genus, species = species,
  composite_id = paste0("ACC_", seq_along(species)), stringsAsFactors = FALSE)
.rr_sm <- function(ref) { ids <- ref$composite_id; cb <- utils::combn(ids, 2L)
  data.frame(id_x = cb[1L, ], id_y = cb[2L, ], p_match = 0.95, coverage = 1, stringsAsFactors = FALSE) }
.rr_stamp <- function(x, reg, tab) suppressMessages(TaxaTools::attach_taxon_ids(x, reg, "species", tab))
.rr <- function(m, r, ...) restore_suppressed_candidates(m, r, rank_system = c("family", "genus", "species"),
                                                          seq_matrix = .rr_sm(r), verbose = FALSE, ...)

test_that("registry is the LAST formal of restore_suppressed_candidates and defaults to NULL", {
  f <- formals(restore_suppressed_candidates)
  expect_identical(utils::tail(names(f), 1L), "registry")
  expect_null(f$registry)
})

test_that("a reference row under a synonym of the candidate is NOT restored as a second candidate", {
  .rg_skip(); reg <- .rg_registry()
  m <- .rr_match("Hypsurus", "Hypsurus caryi")
  r <- .rr_ref("Hypsurus", c("Hypsurus caryi", "Embiotoca caryi"))   # one taxon, two labels in the references
  by_name <- .rr(m, r)
  expect_true("Embiotoca caryi" %in% by_name$species[by_name$is_restored])   # the defect: one taxon twice
  by_id <- .rr(.rr_stamp(m, reg, "joined"), .rr_stamp(r, reg, "reference"), registry = reg)
  expect_false(any(by_id$is_restored))
})

test_that("candidate_species_filter matches a reference species under any registered name", {
  .rg_skip(); reg <- .rg_registry()
  m <- .rr_match("Embiotoca", "Embiotoca jacksoni")
  r <- .rr_ref("Embiotoca", c("Embiotoca jacksoni", "Embiotoca caryi"))
  by_name <- .rr(m, r, candidate_species_filter = "Hypsurus caryi")
  expect_false(any(by_name$is_restored))   # the defect: the plausible species is filed under its accepted name
  by_id <- .rr(.rr_stamp(m, reg, "joined"), .rr_stamp(r, reg, "reference"), candidate_species_filter = "Hypsurus caryi", registry = reg)
  rr <- by_id[by_id$is_restored, ]
  expect_identical(rr$species, "Embiotoca caryi")
  expect_identical(rr$taxon_id, .rg_id(reg, "Hypsurus caryi"))   # the restored row carries its own id, not the anchor's
})

test_that("restore_suppressed_candidates(registry =) refuses an unstamped table", {
  .rg_skip(); reg <- .rg_registry()
  expect_error(.rr(.rr_match("Hypsurus", "Hypsurus caryi"), .rr_stamp(.rr_ref("Hypsurus", c("Hypsurus caryi", "Embiotoca caryi")), reg, "reference"),
                   registry = reg), "stamp")
})
