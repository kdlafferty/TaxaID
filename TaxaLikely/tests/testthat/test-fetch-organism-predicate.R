# The "different organisms" predicate, and the vote built on top of it.
#
# The predicate is PAIRWISE and context-free: it answers "do these two rows
# describe different organisms?" and nothing else. The fetch-wide dominance vote
# lives outside it, in .resolve_cross_lineage_contamination(), because the
# homonym call site wants the pairwise answer with no vote at all.
#
# Rank choice is measured, not preferred: class discriminates 18 of 18 genuine
# genus homonyms in the JV oracle; kingdom only 8 of 18. Every group NCBI denies
# a kingdom (Rhodophyta, Ochrophyta, Bacillariophyta, Ciliophora, Chrysophyceae)
# has a class.

row_of <- function(...) as.list(c(...))

# ---- the predicate -----------------------------------------------------------

test_that("two rows in the same class are NOT different organisms", {
  # THE control that separates this from a family-disjointness rule: a split
  # between Mytilidae and Modiolidae is a taxonomic revision, not a homonym.
  a <- row_of(kingdom = "Metazoa", phylum = "Mollusca", class = "Bivalvia")
  b <- row_of(kingdom = "Metazoa", phylum = "Mollusca", class = "Bivalvia")
  expect_false(TaxaLikely:::.different_organisms(a, b))
})

test_that("a kingdom-blind split IS caught at class (Eisenia)", {
  # The brown alga Eisenia (Phaeophyceae) and the earthworm Eisenia (Clitellata).
  # NCBI gives Ochrophyta no kingdom, so the algal row's kingdom is NA and the
  # shipped kingdom rule cannot see this at all.
  alga <- row_of(kingdom = NA_character_, phylum = "Ochrophyta", class = "Phaeophyceae")
  worm <- row_of(kingdom = "Metazoa", phylum = "Annelida", class = "Clitellata")
  expect_true(TaxaLikely:::.different_organisms(alga, worm))
})

test_that("an animal-vs-animal homonym is caught, which no kingdom test can do", {
  # Ctenophora: a genus of crane flies (Insecta) and the comb-jelly phylum.
  fly   <- row_of(kingdom = "Metazoa", phylum = "Arthropoda", class = "Insecta")
  jelly <- row_of(kingdom = "Metazoa", phylum = "Ctenophora", class = "Tentaculata")
  expect_true(TaxaLikely:::.different_organisms(fly, jelly))
  # Same kingdom: a kingdom-only comparison is blind to this pair, which is
  # the whole reason the predicate reaches down to class.
  expect_false(TaxaLikely:::.different_organisms(
    row_of(kingdom = "Metazoa"), row_of(kingdom = "Metazoa")
  ))
})

test_that("the fish/alga Ulvaria split is caught", {
  fish <- row_of(kingdom = "Metazoa", phylum = "Chordata", class = "Actinopteri")
  alga <- row_of(kingdom = "Viridiplantae", phylum = "Chlorophyta", class = "Ulvophyceae")
  expect_true(TaxaLikely:::.different_organisms(fish, alga))
})

test_that("the FINEST rank both rows declare decides, not the coarsest", {
  # Share kingdom and phylum, differ at class. Decided (Kevin, reading B): this
  # IS a difference. A cross-class split is a homonym candidate to
  # jv_genus_lineage_check.R, and judging at the coarsest shared rank instead
  # could never separate two animals, since every animal is Metazoa.
  a <- row_of(kingdom = "Metazoa", phylum = "Chordata", class = "Actinopteri")
  b <- row_of(kingdom = "Metazoa", phylum = "Chordata", class = "Chondrichthyes")
  expect_true(TaxaLikely:::.different_organisms(a, b))

  # And the converse: agreement at the finest declared rank settles it even when
  # a coarser rank disagrees. This pins that the finest rank DECIDES rather than
  # merely contributing.
  expect_false(TaxaLikely:::.different_organisms(
    row_of(kingdom = "Metazoa", phylum = "Chordata", class = "Shared"),
    row_of(kingdom = "Viridiplantae", phylum = "Chlorophyta", class = "Shared")
  ))
})

test_that("the comparison ranks are ordered coarsest to finest", {
  # Load-bearing: .different_organisms() takes the LAST comparable entry as the
  # finest declared rank, so reordering .ORGANISM_RANKS would change verdicts
  # silently rather than erroring. This is the guard against that.
  expect_identical(TaxaLikely:::.ORGANISM_RANKS,
    c("kingdom", "phylum", "class"))

  # Demonstrate the dependency rather than only assert the constant: handed the
  # same ranks finest-first, the predicate reaches the OPPOSITE verdict on a
  # pair that differs at class and agrees at kingdom.
  a <- row_of(kingdom = "Metazoa", phylum = "Arthropoda", class = "Insecta")
  b <- row_of(kingdom = "Metazoa", phylum = "Ctenophora", class = "Tentaculata")
  expect_true(TaxaLikely:::.different_organisms(a, b))
  expect_false(TaxaLikely:::.different_organisms(a, b,
    ranks = rev(TaxaLikely:::.ORGANISM_RANKS)))
})

test_that("an unknown value never establishes a difference", {
  a <- row_of(kingdom = "Metazoa", phylum = NA_character_, class = NA_character_)
  b <- row_of(kingdom = NA_character_, phylum = "Chlorophyta", class = "Ulvophyceae")
  # No rank has both values known -> not separated, by design: the fetch is not
  # split on no evidence.
  expect_false(TaxaLikely:::.different_organisms(a, b))
  # An empty string is as unknown as NA.
  expect_false(TaxaLikely:::.different_organisms(
    row_of(kingdom = "", phylum = "", class = ""),
    row_of(kingdom = "Metazoa", phylum = "Chordata", class = "Actinopteri")
  ))
})

test_that("the predicate is symmetric", {
  a <- row_of(kingdom = "Metazoa", phylum = "Chordata", class = "Actinopteri")
  b <- row_of(kingdom = NA_character_, phylum = "Ochrophyta", class = "Phaeophyceae")
  expect_identical(
    TaxaLikely:::.different_organisms(a, b),
    TaxaLikely:::.different_organisms(b, a)
  )
})

test_that("a rank absent from both rows is simply not compared", {
  a <- row_of(class = "Actinopteri")
  b <- row_of(class = "Ulvophyceae")
  expect_true(TaxaLikely:::.different_organisms(a, b))
  # And with no comparison rank present at all, nothing is claimed.
  expect_false(TaxaLikely:::.different_organisms(
    row_of(family = "Stichaeidae"), row_of(family = "Monostromataceae")
  ))
})
