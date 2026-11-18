# add_unreferenced_prior_mass(registry =): taxa matched by registry id only. Fixtures in helper-registry.R. Each case is
# a defect of the NAME path that the fixture makes visible (the name-path assertion shows the defect is there to fix).

.rg_joined <- function(rows) {
  d <- data.frame(observation_id = "E1", grid_id = "s1", rows, prior_mean = 1e-4, prior_alpha = 0.01, prior_beta = 99.99,
                  stringsAsFactors = FALSE)
  d
}
.rg_priors <- function(names, theta) data.frame(taxon_name = names, taxon_name_rank = "species", grid_id = "s1", theta_mean = theta,
                                               alpha = theta * 1000, beta = (1 - theta) * 1000, stringsAsFactors = FALSE)
# the name path's taxonomy: each table's OWN lineage columns (genus from the binomial's text, as fill_higher_ranks gives)
.rg_tax_text <- function(names, family) data.frame(taxon_name = names, genus = sub(" .*$", "", names), family = family, stringsAsFactors = FALSE)
.aupm <- function(...) suppressMessages(add_unreferenced_prior_mass(...))

test_that("registry is the LAST formal and defaults to NULL", {
  f <- formals(add_unreferenced_prior_mass)
  expect_identical(utils::tail(names(f), 1L), "registry")
  expect_null(f$registry)
})

test_that("a referenced SYNONYM makes the pool species referenced (Oxyjulis / Halichoeres californicus)", {
  .rg_skip(); reg <- .rg_registry()
  j <- .rg_joined(data.frame(taxon_name = c("Halichoeres semicinctus", "Labridae"), taxon_name_rank = c("species", "family"),
                             hypothesis_type = c("specific_candidate", "unreferenced_genus"), stringsAsFactors = FALSE))
  p <- .rg_priors(c("Oxyjulis californica", "Halichoeres semicinctus"), c(0.02, 0.01))
  # the reference carries the synonym; the pool carries the accepted name
  by_name <- .aupm(j, p, .rg_tax_text(p$taxon_name, "Labridae"), referenced_names = c("Halichoeres californicus", "Halichoeres semicinctus"))
  expect_gt(by_name$unreferenced_mass[2], 0)   # the defect: Oxyjulis californica counted as unreferenced
  ids <- c(.rg_id(reg, "Halichoeres californicus"), .rg_id(reg, "Halichoeres semicinctus"))
  by_id <- .aupm(.rg_stamp(j, reg, "joined"), .rg_stamp(p, reg, "priors"), NULL, referenced_names = ids, registry = reg)
  expect_identical(by_id$unreferenced_mass[2], 0)
  expect_identical(by_id$prior_mean, j$prior_mean)
  expect_identical(attr(by_id, "unreferenced_mass_check")$n_candidates_not_referenced, 0L)
})

test_that("one taxon under two names in the pool is ONE species: the accepted name's row is kept", {
  .rg_skip(); reg <- .rg_registry()
  j <- .rg_joined(data.frame(taxon_name = c("Embiotoca jacksoni", "Labridae"), taxon_name_rank = c("species", "family"),
                             hypothesis_type = c("specific_candidate", "unreferenced_genus"), stringsAsFactors = FALSE))
  p <- .rg_priors(c("Oxyjulis californica", "Halichoeres californicus"), c(0.02, 0.05))
  by_name <- .aupm(j, p, .rg_tax_text(p$taxon_name, "Labridae"), referenced_names = "Embiotoca jacksoni")
  expect_identical(by_name$unreferenced_n_species[2], 2L)   # the defect: one taxon counted twice
  by_id <- .aupm(.rg_stamp(j, reg, "joined"), .rg_stamp(p, reg, "priors"), NULL,
                 referenced_names = .rg_id(reg, "Embiotoca jacksoni"), registry = reg)
  expect_identical(by_id$unreferenced_n_species[2], 1L)
  expect_equal(by_id$unreferenced_mass[2], 0.02)   # the ACCEPTED name's row, though the synonym's theta is larger
  mg <- attr(by_id, "unreferenced_merged_prior_rows")
  expect_setequal(mg$taxon_name, c("Oxyjulis californica", "Halichoeres californicus"))
  expect_identical(attr(by_id, "unreferenced_mass_check")$n_prior_rows_merged, 1L)
  mem <- attr(by_id, "unreferenced_scope_members")
  expect_identical(mem$taxon_name, "Oxyjulis californica"); expect_identical(mem$taxon_id, .rg_id(reg, "Oxyjulis californica"))
  expect_identical(mem$scope, "Labridae")
})

test_that("ring scope comes from the registry's tree, not the binomial's text (Embiotoca caryi is a Hypsurus)", {
  .rg_skip(); reg <- .rg_registry()
  j <- .rg_joined(data.frame(taxon_name = c("Embiotoca jacksoni", "Hypsurus"), taxon_name_rank = c("species", "genus"),
                             hypothesis_type = c("specific_candidate", "unreferenced_species"), stringsAsFactors = FALSE))
  p <- .rg_priors("Embiotoca caryi", 0.03)
  by_name <- .aupm(j, p, .rg_tax_text(p$taxon_name, "Embiotocidae"), referenced_names = "Embiotoca jacksoni")
  expect_identical(by_name$unreferenced_mass[2], 0)   # the defect: filed under genus Embiotoca by its text
  by_id <- .aupm(.rg_stamp(j, reg, "joined"), .rg_stamp(p, reg, "priors"), NULL,
                 referenced_names = .rg_id(reg, "Embiotoca jacksoni"), registry = reg)
  expect_equal(by_id$unreferenced_mass[2], 0.03)
  expect_identical(by_id$unreferenced_scope[2], "Hypsurus")
})

test_that("named_rows: the new species row carries its own taxon_id and its display name; joined rows keep theirs", {
  .rg_skip(); reg <- .rg_registry()
  j <- .rg_joined(data.frame(taxon_name = c("Embiotoca jacksoni", "Hypsurus"), taxon_name_rank = c("species", "genus"),
                             hypothesis_type = c("specific_candidate", "unreferenced_species"), genus = c("Embiotoca", "Hypsurus"),
                             family = "Embiotocidae", stringsAsFactors = FALSE))
  p <- .rg_priors("Embiotoca caryi", 0.03)
  js <- .rg_stamp(j, reg, "joined")
  out <- .aupm(js, .rg_stamp(p, reg, "priors"), NULL, referenced_names = .rg_id(reg, "Embiotoca jacksoni"), named_rows = TRUE, registry = reg)
  expect_identical(nrow(out), 3L)
  expect_identical(out$taxon_name[1:2], j$taxon_name); expect_identical(out$genus[1:2], j$genus)
  expect_identical(out$taxon_name[3], "Hypsurus caryi")              # the registry's accepted name, not the pool's
  expect_identical(out$taxon_id[3], .rg_id(reg, "Hypsurus caryi"))   # its own id, not the ring's
  expect_identical(out$genus[3], "Hypsurus"); expect_identical(out$family[3], "Embiotocidae")   # lineage from the tree
  expect_identical(out$taxon_id[1:2], js$taxon_id)
  expect_false(is.null(attr(out, "taxon_registry")))
})

test_that("floor rule by id: withholding scope is the name path's (local + candidates); the wider scope is internal only", {
  .rg_skip(); reg <- .rg_registry()
  # the read has only an order ring; Halichoeres semicinctus is referenced but not a candidate here, so Labridae is a
  # referenced family and Oxyjulis californica (unreferenced, same family) must not be claimed by the order ring
  j <- .rg_joined(data.frame(taxon_name = c("Embiotoca jacksoni", "Perciformes"), taxon_name_rank = c("species", "order"),
                             hypothesis_type = c("specific_candidate", "unreferenced_family"), stringsAsFactors = FALSE))
  p <- .rg_priors("Oxyjulis californica", 0.02)
  pj <- .rg_stamp(p, reg, "priors")
  js <- .rg_stamp(j[1, , drop = FALSE], reg, "joined")
  ring <- j[2, , drop = FALSE]; ring$taxon_id <- "gbif:587"
  jj <- rbind(js, ring); attr(jj, "taxon_registry") <- attr(js, "taxon_registry")
  refs <- c(.rg_id(reg, "Embiotoca jacksoni"), .rg_id(reg, "Halichoeres semicinctus"))
  # default: Halichoeres semicinctus is referenced but neither local nor a candidate, so (as on the name path) its
  # family is not known to be referenced and the order ring claims Oxyjulis californica
  out0 <- .aupm(jj, pj, NULL, referenced_names = refs, registry = reg)
  expect_equal(out0$unreferenced_mass[2], 0.02)
  # the wider scope (every referenced species' lineage), reachable only internally, withholds it
  orig <- .unref_registry_inputs
  local_mocked_bindings(.unref_registry_inputs = function(...) orig(..., ref_lineage_scope = "all"))
  out <- .aupm(jj, pj, NULL, referenced_names = refs, registry = reg)
  expect_identical(out$unreferenced_mass[2], 0)
  wh <- attr(out, "unreferenced_withheld")
  expect_identical(wh$taxon_name, "Oxyjulis californica"); expect_identical(wh$reason, "finer_rank_referenced_unmatched")
  expect_identical(wh$scope, "Perciformes")
})

test_that("the registry path refuses unstamped tables, another registry's stamp, and names in place of ids", {
  .rg_skip(); reg <- .rg_registry(); reg2 <- .rg_registry("rg2")
  j <- .rg_joined(data.frame(taxon_name = c("Embiotoca jacksoni", "Hypsurus"), taxon_name_rank = c("species", "genus"),
                             hypothesis_type = c("specific_candidate", "unreferenced_species"), stringsAsFactors = FALSE))
  p <- .rg_priors("Embiotoca caryi", 0.03); ref <- .rg_id(reg, "Embiotoca jacksoni")
  expect_error(.aupm(j, .rg_stamp(p, reg, "priors"), NULL, ref, registry = reg), "stamp")
  expect_error(.aupm(.rg_stamp(j, reg2, "joined"), .rg_stamp(p, reg, "priors"), NULL, ref, registry = reg), "different registry")
  expect_error(.aupm(.rg_stamp(j, reg, "joined"), .rg_stamp(p, reg, "priors"), NULL, "Embiotoca jacksoni", registry = reg), "taxon ids")
  expect_error(.aupm(.rg_stamp(j, reg, "joined"), .rg_stamp(p, reg, "priors"), NULL, ref, registry = TaxaTools::build_taxon_registry(
    data.frame(verbatim_name = "Hypsurus", source_table = "joined"), run_id = "x", lookup = .rg_lookup)), "frozen")
})

test_that("withhold = \"genus\" by id: a pool species in a referenced TREE genus is withheld, whatever its binomial's text", {
  .rg_skip()
  # one more answer: "Embiotoca nova", a synonym whose accepted species Hypsurus nova sits in genus Hypsurus by the tree
  .n3_answers <- function() {
    t <- .rg_answers(); x <- t[t$q == "Embiotoca caryi", ]
    x$q <- "Embiotoca nova"; x$matched <- "Hypsurus nova"
    x$path <- sub("Hypsurus caryi$", "Hypsurus nova", x$path); x$ids <- sub("411$", "413", x$ids); x$cur <- "413"; x$rec <- "414"
    rbind(t, x)
  }
  lk <- .rg_lookup; environment(lk) <- list2env(list(.rg_answers = .n3_answers), parent = environment(.rg_lookup))
  a <- .n3_answers(); tabs <- c("joined", "priors", "reference")
  reg <- TaxaTools::freeze_taxon_registry(TaxaTools::build_taxon_registry(
    data.frame(verbatim_name = rep(a$q, length(tabs)), source_table = rep(tabs, each = nrow(a)), rank_given = rep(a$rank, length(tabs)),
               stringsAsFactors = FALSE), run_id = "n3", lookup = lk))
  # the read: Hypsurus caryi (referenced) and a family ring; the pool holds Hypsurus nova (filed as "Embiotoca nova") and
  # Embiotoca jacksoni, neither referenced
  j <- .rg_joined(data.frame(taxon_name = c("Hypsurus caryi", "Embiotocidae"), taxon_name_rank = c("species", "family"),
                             hypothesis_type = c("specific_candidate", "unreferenced_genus"), stringsAsFactors = FALSE))
  p <- .rg_priors(c("Embiotoca nova", "Embiotoca jacksoni"), c(0.04, 0.02))
  by_name <- .aupm(j, p, .rg_tax_text(p$taxon_name, "Embiotocidae"), referenced_names = "Hypsurus caryi", withhold = "genus")
  expect_equal(by_name$unreferenced_mass[2], 0.06)   # the defect: by its text "Embiotoca nova" is no Hypsurus, so the ring claims it
  by_id <- .aupm(.rg_stamp(j, reg, "joined"), .rg_stamp(p, reg, "priors"), NULL, referenced_names = .rg_id(reg, "Hypsurus caryi"),
                 withhold = "genus", registry = reg)
  expect_equal(by_id$unreferenced_mass[2], 0.02)     # Embiotoca jacksoni only
  wh <- attr(by_id, "unreferenced_withheld")
  expect_identical(wh$taxon_id, .rg_id(reg, "Embiotoca nova"))
  expect_identical(wh$taxon_name, "Hypsurus nova")
  expect_identical(wh$reason, "genus_referenced_unmatched")
  expect_identical(wh$scope, "Embiotocidae")
  mem <- attr(by_id, "unreferenced_scope_members")
  expect_identical(mem$taxon_id, .rg_id(reg, "Embiotoca jacksoni"))
})
