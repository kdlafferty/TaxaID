# Fixtures use invented names throughout: the detector must find whatever the
# data carries, never a list of taxa.

bc_tax <- function() data.frame(
  observation_id = c("O1","O1","O1","O2","O2","O3","O3"),
  taxon_name     = c("Aa aa","Pb thing","Pa","Qq one","Qq two","Zz a","Zz b"),
  phylum         = c("Pa","Pb","Pa",          "Ph1","Ph2",      "Pz","Pz"),
  class          = c("Ca","Pa","Ca",          "Cc","Cc",        "Cz","Cz"),
  order          = c("Oa","Ob","Oa",          "Oc","Oc",        "Oz","Oz"),
  posterior_point_est = c(0.6, 0.09, 0.31,    0.5, 0.5,         0.9, 0.1),
  stringsAsFactors = FALSE
)
bc_cons <- function() data.frame(
  observation_id  = c("O1","O2","O3"),
  consensus_taxon = c("Pa","Cc","Oz"),
  consensus_rank  = c("phylum","class","order"),
  consensus_limit = c("cross_phylum","cross_phylum","threshold"),
  stringsAsFactors = FALSE
)

test_that("a name carried at two ranks is flagged as cross_rank", {
  out <- flag_backbone_conflicts(bc_cons(), bc_tax())
  # "Pa" is a phylum on two rows and a class on one
  expect_true(out$backbone_conflict[out$observation_id == "O1"])
  expect_equal(out$backbone_conflict_kind[out$observation_id == "O1"], "cross_rank")
  expect_true(grepl("Pa", out$backbone_conflict_names[out$observation_id == "O1"], fixed = TRUE))
  tb <- attr(out, "backbone_conflicts")
  expect_true("Pa" %in% tb$name)
  expect_equal(tb$n_ranks[tb$name == "Pa"], 2L)
  expect_equal(tb$ranks[tb$name == "Pa"], "class+phylum")
})

test_that("an observation with no conflicted name is not flagged", {
  out <- flag_backbone_conflicts(bc_cons(), bc_tax())
  i <- out$observation_id == "O3"
  expect_false(out$backbone_conflict[i])
  expect_true(is.na(out$backbone_conflict_kind[i]))
  expect_true(is.na(out$backbone_conflict_names[i]))
})

test_that("the same-rank multi-parent case is detected (delegated to TaxaTools)", {
  skip_if_not_installed("TaxaTools")
  tax <- bc_tax()
  # Cc sits under two phyla already (Ph1, Ph2) in the fixture
  out <- flag_backbone_conflicts(bc_cons(), tax)
  tb <- attr(out, "backbone_conflicts")
  expect_true("Cc" %in% tb$name)
  expect_true(any(tb$kind[tb$name == "Cc"] %in% c("multi_parent", "both")))
  expect_true(out$backbone_conflict[out$observation_id == "O2"])
})

test_that("a name at many ranks is categorised as a placeholder, without changing the flag", {
  tax <- bc_tax()
  tax$phylum[1] <- "CTRL"; tax$class[1] <- "CTRL"; tax$order[1] <- "CTRL"
  out <- flag_backbone_conflicts(bc_cons(), tax)
  tb <- attr(out, "backbone_conflicts")
  expect_equal(tb$category[tb$name == "CTRL"], "placeholder")
  expect_equal(tb$kind[tb$name == "CTRL"], "cross_rank")   # kind is the structure
  expect_true(tb$n_ranks[tb$name == "CTRL"] >= 3L)
  # raising the label threshold above its rank count relabels it, flag unchanged
  hi <- flag_backbone_conflicts(bc_cons(), tax, placeholder_rank_count = 9)
  expect_equal(attr(hi, "backbone_conflicts")$category[attr(hi, "backbone_conflicts")$name == "CTRL"], "cross_rank")
  expect_identical(hi$backbone_conflict, out$backbone_conflict)
})

test_that("cross_phylum_conflicted is TRUE only when the withheld phyla include a cross-rank name", {
  out <- flag_backbone_conflicts(bc_cons(), bc_tax())
  # O1: withheld, and "Pa" is used as a phylum AND as a class -> ambiguous key
  expect_true(out$cross_phylum_conflicted[out$observation_id == "O1"])
  # O2: withheld, but its phyla (Ph1/Ph2) are each used only as phyla
  expect_false(out$cross_phylum_conflicted[out$observation_id == "O2"])
  # O3: not a cross_phylum withholding at all
  expect_true(is.na(out$cross_phylum_conflicted[out$observation_id == "O3"]))
})

test_that("no consensus_limit column leaves cross_phylum_conflicted all NA", {
  cons <- bc_cons(); cons$consensus_limit <- NULL
  out <- flag_backbone_conflicts(cons, bc_tax())
  expect_true(all(is.na(out$cross_phylum_conflicted)))
})

test_that("conflict mass is a share, and is NA when there is no posterior column", {
  out <- flag_backbone_conflicts(bc_cons(), bc_tax())
  m <- out$backbone_conflict_mass[out$observation_id == "O3"]
  expect_equal(m, 0)
  expect_true(all(out$backbone_conflict_mass >= 0 & out$backbone_conflict_mass <= 1))
  tax <- bc_tax(); tax$posterior_point_est <- NULL
  nop <- flag_backbone_conflicts(bc_cons(), tax)
  expect_true(all(is.na(nop$backbone_conflict_mass)))
  expect_identical(nop$backbone_conflict, out$backbone_conflict)   # flag unaffected
})

test_that("a clean taxonomy yields no flags and an empty conflict table", {
  tax <- data.frame(observation_id = c("O1","O1","O2"),
    taxon_name = c("A a","A b","B a"),
    phylum = c("P1","P1","P2"), class = c("C1","C1","C2"), order = c("R1","R1","R2"),
    posterior_point_est = c(0.5, 0.5, 1), stringsAsFactors = FALSE)
  cons <- data.frame(observation_id = c("O1","O2"), consensus_limit = c("threshold","threshold"),
    stringsAsFactors = FALSE)
  out <- flag_backbone_conflicts(cons, tax)
  expect_false(any(out$backbone_conflict))
  expect_equal(nrow(attr(out, "backbone_conflicts")), 0L)
  expect_true(all(is.na(out$backbone_conflict_kind)))
})

test_that("the attributes follow data-frame attribute rules", {
  out <- flag_backbone_conflicts(bc_cons(), bc_tax())
  expect_false(is.null(attr(out[1:2, ], "backbone_conflicts")))            # row subset KEEPS
  expect_true(is.null(attr(out[, c("observation_id")], "backbone_conflicts")))  # column subset DROPS
  expect_false(is.null(attr(out, "backbone_conflict_params")))
  expect_equal(attr(out, "backbone_conflict_params")$observation_col, "observation_id")
})

test_that("input problems are reported, not guessed at", {
  expect_error(flag_backbone_conflicts(list(), bc_tax()), "must be a data frame")
  expect_error(flag_backbone_conflicts(bc_cons(), list()), "must be a data frame")
  expect_error(flag_backbone_conflicts(bc_cons()[, "consensus_taxon", drop = FALSE], bc_tax()),
               "no column 'observation_id'")
  expect_error(flag_backbone_conflicts(bc_cons(), bc_tax(), placeholder_rank_count = 1),
               "placeholder_rank_count")
  expect_error(flag_backbone_conflicts(bc_cons(), bc_tax(), rank_system = c("phylum", "nope")),
               "absent from taxonomy")
  one <- bc_tax()[, c("observation_id", "phylum", "posterior_point_est")]
  expect_error(flag_backbone_conflicts(bc_cons(), one, rank_system = "phylum"),
               "fewer than two rank columns")
})

test_that("existing columns of the same name are overwritten with a warning", {
  cons <- bc_cons(); cons$backbone_conflict <- "stale"
  expect_warning(flag_backbone_conflicts(cons, bc_tax()), "overwriting existing column")
})

test_that("rank_system is honoured when given explicitly", {
  out <- flag_backbone_conflicts(bc_cons(), bc_tax(), rank_system = c("phylum", "class"))
  expect_equal(attr(out, "backbone_conflict_params")$rank_system, c("phylum", "class"))
  # "Pa" is still phylum+class, so it is still found
  expect_true("Pa" %in% attr(out, "backbone_conflicts")$name)
})
