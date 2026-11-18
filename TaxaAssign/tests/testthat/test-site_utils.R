# tests/testthat/test-site_utils.R
# Dedicated coverage for these internal helpers.

# ---- .parse_grid_ids() -------------------------------------------------------

test_that(".parse_grid_ids parses lat/lon out of the Grid_{lat}_{lon} encoding", {
  out <- .parse_grid_ids(c("Grid_34p1_m119p1", "Grid_0p0_0p0"))
  expect_equal(out$grid_lat, c(34.1, 0.0))
  expect_equal(out$grid_lon, c(-119.1, 0.0))
})

# ---- .find_nearest_grid() -----------------------------------------------------

test_that(".find_nearest_grid returns the closest cell and a distance", {
  grid_coords <- .parse_grid_ids(c("Grid_34p0_m119p0", "Grid_40p0_m119p0"))
  out <- .find_nearest_grid(34.1, -119.0, grid_coords)
  expect_equal(out$grid_id, "Grid_34p0_m119p0")
  expect_true(out$dist_deg < 1)
})

test_that(".find_nearest_grid's cosine-latitude correction picks the geographically nearer cell at high latitude", {
  # At 60N, 1 degree of longitude is much shorter in real distance than
  # 1 degree of latitude (~cos(60) = 0.5x) -- a naive Euclidean degree
  # distance would treat a 2-degree lat gap and a 4-degree lon gap as
  # equally far (4^2 == 2^2 + ~3.46^2 in real terms), but the real nearer
  # cell is the one with the SMALLER latitude gap once longitude is
  # correctly down-weighted.
  grid_coords <- .parse_grid_ids(c("Grid_60p0_m10p0", "Grid_62p0_m4p0"))
  query_lat <- 60.0
  query_lon <- -8.0
  out <- .find_nearest_grid(query_lat, query_lon, grid_coords)
  expect_equal(out$grid_id, "Grid_60p0_m10p0")
})

test_that(".find_nearest_grid reduces to the closer cell in a simple equatorial case", {
  grid_coords <- .parse_grid_ids(c("Grid_0p0_0p0", "Grid_0p0_5p0"))
  out <- .find_nearest_grid(0, 1, grid_coords)
  expect_equal(out$grid_id, "Grid_0p0_0p0")
})

# ---- .build_context_block() ---------------------------------------------------

test_that(".build_context_block returns empty string for NULL/empty context", {
  expect_equal(.build_context_block(NULL), "")
  expect_equal(.build_context_block(list()), "")
})

test_that(".build_context_block formats populated fields and skips empty ones", {
  ctx <- list(ecoregion = "California Coast", main_habitat = "Estuarine", lat = NA)
  out <- .build_context_block(ctx)
  expect_true(grepl("Ecoregion: California Coast", out, fixed = TRUE))
  expect_true(grepl("Habitat: Estuarine", out, fixed = TRUE))
  expect_false(grepl("Latitude", out, fixed = TRUE))
})

test_that(".build_context_block respects a custom habitat_field name", {
  ctx <- list(habitat = "Marine")
  out <- .build_context_block(ctx, habitat_field = "habitat")
  expect_true(grepl("Habitat: Marine", out, fixed = TRUE))
})

# ---- .check_rank_system_order() -----------------------------------------------

test_that(".check_rank_system_order is silent for a correctly-ordered rank_system", {
  expect_no_warning(.check_rank_system_order(c("family", "genus", "species"), "test"))
})

test_that(".check_rank_system_order warns for a reversed rank_system", {
  expect_warning(
    .check_rank_system_order(c("species", "genus", "family"), "test"),
    "disagrees in.*relative order"
  )
})

test_that(".check_rank_system_order is silent when fewer than 2 ranks overlap with standard_ranks", {
  expect_no_warning(.check_rank_system_order(c("custom_rank_a", "custom_rank_b"), "test"))
  expect_no_warning(.check_rank_system_order(NULL, "test"))
  expect_no_warning(.check_rank_system_order("species", "test"))
})

# ---- .beta_mean() --------------------------------------------------------------

test_that(".beta_mean computes alpha / (alpha + beta)", {
  expect_equal(.beta_mean(3, 7), 0.3)
  expect_equal(.beta_mean(c(1, 9), c(1, 1)), c(0.5, 0.9))
})

.make_taxaexpect_priors_for_site <- function() {
  data.frame(
    taxon_name = "Gadus morhua",
    grid_id = "Grid_34p1_m119p1",
    main_habitat = "Estuarine Bay",
    stringsAsFactors = FALSE
  )
}

# ---- .latlon_to_grid() ----------------------------------------------------------

test_that(".latlon_to_grid resolves to the nearest grid with the requested habitat", {
  out <- .latlon_to_grid(34.1, -119.1, "Estuarine Bay", .make_taxaexpect_priors_for_site())
  expect_equal(out$grid_id, "Grid_34p1_m119p1")
  expect_equal(out$main_habitat, "Estuarine Bay")
})

test_that(".latlon_to_grid errors with an informative message when main_habitat is NULL", {
  expect_error(
    .latlon_to_grid(34.1, -119.1, NULL, .make_taxaexpect_priors_for_site()),
    "main_habitat.*required"
  )
})

test_that(".latlon_to_grid errors when main_habitat isn't available at the resolved grid", {
  expect_error(
    .latlon_to_grid(34.1, -119.1, "Freshwater", .make_taxaexpect_priors_for_site()),
    "not found at"
  )
})

test_that(".latlon_to_grid gives a clear error when the nearest grid has no non-NA main_habitat rows at all", {
  priors <- data.frame(
    taxon_name = "Gadus morhua",
    grid_id = "Grid_34p1_m119p1",
    main_habitat = NA_character_,
    stringsAsFactors = FALSE
  )
  expect_error(
    .latlon_to_grid(34.1, -119.1, "Estuarine Bay", priors),
    "No prior rows"
  )
})

test_that(".latlon_to_grid warns when the nearest grid is far from the provided coordinates", {
  expect_warning(
    .latlon_to_grid(0, 0, "Estuarine Bay", .make_taxaexpect_priors_for_site()),
    "degrees from provided coordinates"
  )
})

# ---- .resolve_llm_fn() ---------------------------------------------------------

test_that(".resolve_llm_fn: returns user-supplied function unchanged", {
  my_fn <- function(x) paste("echo:", x)
  result <- TaxaAssign:::.resolve_llm_fn(my_fn, "test")
  expect_identical(result, my_fn)
})

test_that(".resolve_llm_fn: NULL resolves to TaxaTools provider when available", {
  set.seed(1) # may simulate (n_sims defaults to 1000): seeded so other tests cannot shift its stream
  skip_if_not_installed("TaxaTools")
  result <- TaxaAssign:::.resolve_llm_fn(NULL, "test")
  expect_true(is.function(result))
})

test_that(".is_complement_type covers the rings and unresolved_species, and nothing else", {
  # One predicate instead of an exemption list restated at each filter: the
  # generic complement was lost at three separate places because the list was
  # rewritten by hand every time it was needed.
  rings <- paste0("unreferenced_", c("phylum", "class", "order", "family", "genus", "species"))
  expect_true(all(.is_complement_type(rings)))
  expect_true(.is_complement_type("unresolved_species"))
  expect_false(.is_complement_type("specific_candidate"))
  expect_false(.is_complement_type("unreferenced_kingdom")) # not a ring rank
  expect_false(.is_complement_type(NA_character_))
  expect_equal(.is_complement_type(character(0)), logical(0))
  # vectorised, element-wise, and never NA
  mixed <- c("specific_candidate", "unreferenced_genus", NA, "unresolved_species")
  expect_identical(.is_complement_type(mixed), c(FALSE, TRUE, FALSE, TRUE))
})

# ---- ring types and ring ranks under a user rank system -----------------------
# A rank system with intermediate ranks, as TaxaLikely types its rings: each ring is typed by the next-finer rank IN
# the rank system (a ring at infraorder is unreferenced_family; at order, unreferenced_infraorder; at subclass,
# unreferenced_order; at class, unreferenced_subclass).
.rk_RS <- c("phylum", "class", "subclass", "order", "infraorder", "family", "genus", "species")
.rk_lin <- function() data.frame(species = c("Embiotoca jacksoni", "Hypsurus caryi", "Halichoeres semicinctus"),
  genus = c("Embiotoca", "Hypsurus", "Halichoeres"), family = c("Embiotocidae", "Embiotocidae", "Labridae"),
  infraorder = c("Ovalentaria", "Ovalentaria", "Eupercaria"), order = "Perciformes", subclass = "Neopterygii",
  class = "Actinopteri", phylum = "Chordata", stringsAsFactors = FALSE)
# the likelihoods TaxaLikely's .evaluate_one_query() gives for these rings: E1 two embiotocids, E2 an embiotocid tied
# with a labrid (its infraorder ring named at their common order, members listed at infraorder)
.rk_lik <- function() {
  r <- function(o, t, n, k, s, m = NA, st = NA) data.frame(observation_id = o, hypothesis_type = t, taxon_name = n, taxon_name_rank = k,
    score_likelihood = s, ring_member_clades = m, ring_lca_status = st, stringsAsFactors = FALSE)
  out <- rbind(
    r("E1", "specific_candidate", "Embiotoca jacksoni", "species", 1), r("E1", "unreferenced_species", "Hypsurus", "genus", 0.03),
    r("E1", "specific_candidate", "Hypsurus caryi", "species", 0.03), r("E1", "unreferenced_species", "Embiotoca", "genus", 2e-3),
    r("E1", "unreferenced_genus", "Embiotocidae", "family", 3e-6), r("E1", "unreferenced_family", "Ovalentaria", "infraorder", 3e-8),
    r("E1", "unreferenced_infraorder", "Perciformes", "order", 2e-10), r("E1", "unreferenced_order", "Neopterygii", "subclass", 7e-13),
    r("E1", "unreferenced_subclass", "Actinopteri", "class", 1e-15), r("E1", "unreferenced_class", "Chordata", "phylum", 1e-18),
    r("E2", "specific_candidate", "Embiotoca jacksoni", "species", 1), r("E2", "specific_candidate", "Halichoeres semicinctus", "species", 1),
    r("E2", "unreferenced_species", "Embiotoca", "genus", 0.08), r("E2", "unreferenced_species", "Halichoeres", "genus", 0.08),
    r("E2", "unreferenced_genus", "Embiotocidae", "family", 2e-4), r("E2", "unreferenced_genus", "Labridae", "family", 2e-4),
    r("E2", "unreferenced_family", "Perciformes", "order", 4e-6, "Eupercaria|Ovalentaria", "lca"),
    r("E2", "unreferenced_infraorder", "Perciformes", "order", 4e-8), r("E2", "unreferenced_order", "Neopterygii", "subclass", 2e-10),
    r("E2", "unreferenced_subclass", "Actinopteri", "class", 6e-13), r("E2", "unreferenced_class", "Chordata", "phylum", 8e-16))
  out$score_likelihood_mean <- out$score_likelihood; out$score_likelihood_sd <- 0
  out
}
.rk_priors <- function() {
  p <- data.frame(taxon_name = c(.rk_lin()$species, NA), taxon_name_rank = "species", grid_id = "s1", main_habitat = "Rocky",
                  alpha = c(20, 10, 8, 1), beta = c(80, 90, 92, 999), undetected_type = c(NA, NA, NA, "global_floor"), stringsAsFactors = FALSE)
  p$theta_mean <- p$alpha / (p$alpha + p$beta)
  p
}
.rk_tl <- function() { tl <- .rk_lin(); tl$taxon_name <- tl$species; tl }
.rk_jp <- function(lik, pri, ...) suppressWarnings(suppressMessages(join_priors(lik, pri, site = list(grid_id = "s1", main_habitat = "Rocky"),
  taxonomy_lookup = .rk_tl(), rank_system = .rk_RS, backbone_id = 11, ...)))
.rk_rings <- function(x) x[grepl("^unreferenced_", x$hypothesis_type), , drop = FALSE]

test_that("a ring type at any rank the rank system names is a complement type; other unreferenced_* strings are not", {
  ty <- c("unreferenced_species", "unreferenced_family", "unreferenced_infraorder", "unreferenced_subclass",
          "unreferenced_parvorder", "unreferenced_superfamily", "unreferenced_subphylum")
  expect_true(all(.is_unreferenced_type(ty)))
  expect_true(all(.is_complement_type(ty)))
  expect_false(any(.is_unreferenced_type(c("unreferenced_hypothesis", "unreferenced_", "specific_candidate", NA))))
})

test_that("a ring's own rank is the rank above its type IN the rank system", {
  ty <- c("unreferenced_species", "unreferenced_genus", "unreferenced_family", "unreferenced_infraorder", "unreferenced_order",
          "unreferenced_subclass", "unreferenced_class")
  expect_identical(.unreferenced_ring_rank(ty, .rk_RS), c("genus", "family", "infraorder", "order", "subclass", "class", "phylum"))
  # without a rank system: the standard ranks
  expect_identical(.unreferenced_ring_rank(c("unreferenced_family", "unreferenced_genus"), NULL), c("order", "family"))
})

test_that("join_priors keeps every ring row of a rank system with subclass and infraorder (no registry)", {
  lik <- .rk_lik()
  out <- .rk_jp(lik, .rk_priors())
  key <- function(d) sort(paste(d$observation_id, d$hypothesis_type, d$taxon_name))
  expect_identical(nrow(.rk_rings(lik)), 17L)
  expect_identical(key(.rk_rings(out)), key(.rk_rings(lik)))
})

test_that("join_priors keeps every ring row of a rank system with subclass and infraorder (registry)", {
  .rg_skip()
  # GBIF-shaped answers: the intermediate ranks are not in the key authority's tree, so a name at subclass or
  # infraorder is a run-local node under the major-rank node its answer gives
  extra <- data.frame(q = c("Chordata", "Actinopteri", "Neopterygii", "Perciformes", "Ovalentaria", "Eupercaria"),
                      rank = c("phylum", "class", "subclass", "order", "infraorder", "infraorder"),
                      above = c("Animalia", "Animalia|Chordata", "Animalia|Chordata|Actinopteri", "Animalia|Chordata",
                                "Animalia|Chordata|Actinopteri", "Animalia|Chordata|Actinopteri"),
                      above_ids = c("1", "1|44", "1|44|204", "1|44", "1|44|204", "1|44|204"),
                      above_ranks = c("kingdom", "kingdom|phylum", "kingdom|phylum|class", "kingdom|phylum", "kingdom|phylum|class",
                                      "kingdom|phylum|class"),
                      id = c("44", "204", "9003", "587", "9001", "9002"), stringsAsFactors = FALSE)
  lk <- function(names, rank, context) {
    out <- .rg_lookup(names, rank, context)
    for (k in which(names %in% extra$q)) {
      e <- extra[match(names[k], extra$q), ]
      major <- e$rank %in% c("phylum", "class", "order")
      out$matched_name[k] <- e$q; out$matched_rank[k] <- e$rank; out$is_synonym[k] <- FALSE; out$matched[k] <- TRUE
      out$classification_path[k] <- if (major) paste(e$above, e$q, sep = "|") else e$above
      out$classification_ranks[k] <- if (major) paste(e$above_ranks, e$rank, sep = "|") else e$above_ranks
      out$classification_ids[k] <- if (major) paste(e$above_ids, e$id, sep = "|") else e$above_ids
      out$record_id[k] <- out$current_record_id[k] <- e$id; out$match_type[k] <- "Exact"
    }
    out
  }
  lik <- .rk_lik(); pri <- .rk_priors(); lin <- .rk_lin()
  nt <- unique(rbind(data.frame(verbatim_name = lik$taxon_name, rank_given = lik$taxon_name_rank, source_table = "joined"),
                     data.frame(verbatim_name = lin$species, rank_given = "species", source_table = "priors"),
                     do.call(rbind, lapply(setdiff(.rk_RS, "species"), function(r) data.frame(verbatim_name = unique(lin[[r]]), rank_given = r,
                                                                                             source_table = "joined")))))
  reg <- TaxaTools::freeze_taxon_registry(TaxaTools::build_taxon_registry(nt, run_id = "rk", lookup = lk))
  lik <- .rg_stamp(lik, reg, "joined"); pri <- .rg_stamp(pri, reg, "priors")
  out <- .rk_jp(lik, pri, registry = reg)
  vb <- if ("taxon_name_verbatim" %in% names(out)) out$taxon_name_verbatim else out$taxon_name
  ro <- .rk_rings(out)
  expect_identical(sort(paste(ro$observation_id, ro$hypothesis_type, vb[grepl("^unreferenced_", out$hypothesis_type)])),
                   sort(paste(.rk_rings(lik)$observation_id, .rk_rings(lik)$hypothesis_type, .rk_rings(lik)$taxon_name)))
})

test_that("join_priors keeps every ring row of a rank system with subclass and infraorder (registry; a lookup that answers an intermediate rank on its own path)", {
  .rg_skip()
  # The answer shape that dropped rows before: the lookup names an intermediate-rank taxon AT its rank, on a path that
  # holds it (a run-local node under the answer, since the registry's tree keeps the major ranks). Before the ring
  # types followed the rank system, join_priors dropped both observations' unreferenced_subclass rings here (15 of 17).
  inter <- data.frame(q = c("Chordata", "Actinopteri", "Neopterygii", "Perciformes", "Ovalentaria", "Eupercaria"),
                      rank = c("phylum", "class", "subclass", "order", "infraorder", "infraorder"),
                      path = c("Animalia|Chordata", "Animalia|Chordata|Actinopteri", "Animalia|Chordata|Actinopteri|Neopterygii",
                               "Animalia|Chordata|Perciformes", "Animalia|Chordata|Actinopteri|Ovalentaria", "Animalia|Chordata|Actinopteri|Eupercaria"),
                      ranks = c("kingdom|phylum", "kingdom|phylum|class", "kingdom|phylum|class|subclass", "kingdom|phylum|order",
                                "kingdom|phylum|class|infraorder", "kingdom|phylum|class|infraorder"),
                      ids = c("1|44", "1|44|204", "1|44|204|9003", "1|44|587", "1|44|204|9001", "1|44|204|9002"),
                      id = c("44", "204", "9003", "587", "9001", "9002"), stringsAsFactors = FALSE)
  lk <- function(names, rank, context) {
    out <- .rg_lookup(names, rank, context)
    for (k in which(names %in% inter$q)) {
      e <- inter[match(names[k], inter$q), ]
      out$matched_name[k] <- e$q; out$matched_rank[k] <- e$rank; out$is_synonym[k] <- FALSE; out$matched[k] <- TRUE
      out$classification_path[k] <- e$path; out$classification_ranks[k] <- e$ranks; out$classification_ids[k] <- e$ids
      out$record_id[k] <- out$current_record_id[k] <- e$id; out$match_type[k] <- "Exact"
    }
    out
  }
  lik <- .rk_lik(); pri <- .rk_priors(); lin <- .rk_lin()
  nt <- unique(rbind(data.frame(verbatim_name = lik$taxon_name, rank_given = lik$taxon_name_rank, source_table = "joined"),
                     data.frame(verbatim_name = lin$species, rank_given = "species", source_table = "priors"),
                     do.call(rbind, lapply(setdiff(.rk_RS, "species"), function(r) data.frame(verbatim_name = unique(lin[[r]]), rank_given = r,
                                                                                             source_table = "joined")))))
  reg <- TaxaTools::freeze_taxon_registry(suppressWarnings(TaxaTools::build_taxon_registry(nt, run_id = "rk2", lookup = lk)))
  out <- .rk_jp(.rg_stamp(lik, reg, "joined"), .rg_stamp(pri, reg, "priors"), registry = reg)
  vb <- if ("taxon_name_verbatim" %in% names(out)) out$taxon_name_verbatim else out$taxon_name
  ro <- .rk_rings(out)
  expect_identical(nrow(ro), 17L)
  expect_identical(sort(paste(ro$observation_id, ro$hypothesis_type, vb[grepl("^unreferenced_", out$hypothesis_type)])),
                   sort(paste(.rk_rings(lik)$observation_id, .rk_rings(lik)$hypothesis_type, .rk_rings(lik)$taxon_name)))
})

# .is_unreferenced_type() is reached with a table's raw hypothesis_type column on the registry = NULL path
# (join_priors(), posterior_consensus(), update_prior_from_consensus()). A column read with stringsAsFactors = TRUE is a
# factor, and a column that is all NA is logical; both must classify, not stop.

test_that(".is_unreferenced_type() classifies a factor column as it does the character one", {
  v <- c("unreferenced_genus", "specific_candidate", "unreferenced_infraorder", "unreferenced_kingdom", NA)
  want <- c(TRUE, FALSE, TRUE, FALSE, FALSE)
  expect_identical(TaxaAssign:::.is_unreferenced_type(v), want)
  expect_identical(TaxaAssign:::.is_unreferenced_type(factor(v)), want)
})

test_that(".is_unreferenced_type() answers FALSE for an all-NA logical column", {
  expect_identical(TaxaAssign:::.is_unreferenced_type(c(NA, NA)), c(FALSE, FALSE))
  expect_identical(TaxaAssign:::.is_unreferenced_type(logical(0)), logical(0))
})
