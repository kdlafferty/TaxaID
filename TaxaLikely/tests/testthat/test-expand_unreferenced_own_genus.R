# A species is named ONLY from its own genus's ring (an "unreferenced_species"
# row whose taxon_name is that genus). A family ring ("unreferenced_genus") never
# yields a named species copy, even for a genus with no references at all; the
# species it would have named are listed in attr(, "unreferenced_withheld").
# Fixtures are offline and mirror real shapes (numbers simplified).

.og_lik <- function(obs, name, rank, type, score) {
  data.frame(
    observation_id = obs, taxon_name = name, taxon_name_rank = rank,
    hypothesis_type = type, score_likelihood = score,
    score_likelihood_mean = score, score_likelihood_sd = 0.01,
    stringsAsFactors = FALSE
  )
}

.og_unref <- function(species, genus, family) {
  data.frame(species = species, genus = genus, family = family,
             stringsAsFactors = FALSE)
}

.og_run <- function(lik, unref) {
  suppressMessages(expand_unreferenced_hypotheses(lik, unref))
}

named_rows <- function(out) {
  out[out$taxon_name_rank == "species" & out$hypothesis_type != "specific_candidate", ]
}

test_that("Taonia shape: no Taonia ring, so Taonia is withheld; generic Dictyotaceae row kept", {
  lik <- rbind(
    .og_lik("ASV_T", "Dictyota dichotoma", "species", "specific_candidate", 0.05),
    .og_lik("ASV_T", "Dictyotaceae", "family", "unreferenced_genus", 0.40)
  )
  unref <- .og_unref("Taonia lennebackerae", "Taonia", "Dictyotaceae")
  expect_no_warning(out <- .og_run(lik, unref))
  expect_false("Taonia lennebackerae" %in% out$taxon_name)
  expect_equal(nrow(named_rows(out)), 0L)
  fam <- out[out$taxon_name == "Dictyotaceae", ]
  expect_equal(nrow(fam), 1L)
  expect_equal(fam$hypothesis_type, "unreferenced_genus")
  expect_equal(fam$taxon_name_rank, "family")
  expect_equal(fam$score_likelihood, 0.40)
  w <- attr(out, "unreferenced_withheld")
  expect_identical(names(w), c("observation_id", "taxon_name", "genus", "family", "reason"))
  expect_equal(nrow(w), 1L)
  expect_equal(w$observation_id, "ASV_T")
  expect_equal(w$taxon_name, "Taonia lennebackerae")
  expect_equal(w$genus, "Taonia")
  expect_equal(w$family, "Dictyotaceae")
  expect_equal(w$reason, "no_own_genus_ring")
  # H1 passes through
  expect_equal(nrow(out), 2L)
})

test_that("Hypsoblennius shape (Mugu ASV_606): named from its own genus ring with that ring's score", {
  lik <- rbind(
    .og_lik("ASV_606", "Hypsoblennius gilberti", "species", "specific_candidate", 0.20),
    .og_lik("ASV_606", "Hypsoblennius hentz", "species", "specific_candidate", 0.14),
    .og_lik("ASV_606", "Hypsoblennius", "genus", "unreferenced_species", 0.37),
    .og_lik("ASV_606", "Blenniidae", "family", "unreferenced_genus", 0.91)
  )
  unref <- .og_unref("Hypsoblennius jenkinsi", "Hypsoblennius", "Blenniidae")
  out <- .og_run(lik, unref)
  j <- out[out$taxon_name == "Hypsoblennius jenkinsi", ]
  expect_equal(nrow(j), 1L)
  expect_equal(j$hypothesis_type, "unreferenced_species")
  expect_equal(j$taxon_name_rank, "species")
  expect_equal(j$score_likelihood, 0.37)
  expect_equal(j$score_likelihood_mean, 0.37)
  expect_equal(j$score_likelihood_sd, 0.01)
  expect_equal(j$observation_id, "ASV_606")
  # not the family ring's score, and not withheld
  expect_false(isTRUE(all.equal(j$score_likelihood, 0.91)))
  expect_equal(nrow(attr(out, "unreferenced_withheld")), 0L)
  # both generic rows are kept
  expect_equal(out$score_likelihood[out$taxon_name == "Hypsoblennius" & out$taxon_name_rank == "genus"], 0.37)
  expect_equal(out$score_likelihood[out$taxon_name == "Blenniidae"], 0.91)
  expect_equal(sum(out$hypothesis_type == "unreferenced_genus" & out$taxon_name_rank == "species"), 0L)
})

test_that("a referenced specific_candidate row is passed through untouched", {
  lik <- rbind(
    .og_lik("ASV_P", "Hypsoblennius gilberti", "species", "specific_candidate", 0.2345),
    .og_lik("ASV_P", "Hypsoblennius", "genus", "unreferenced_species", 0.37),
    .og_lik("ASV_P", "Blenniidae", "family", "unreferenced_genus", 0.91)
  )
  lik$extra_col <- c("keep_me", "a", "b")
  unref <- .og_unref(
    c("Hypsoblennius jenkinsi", "Hypsoblennius gilberti"),
    "Hypsoblennius", "Blenniidae"
  )
  out <- .og_run(lik, unref)
  h1_in <- lik[lik$hypothesis_type == "specific_candidate", ]
  h1_out <- out[out$hypothesis_type == "specific_candidate", ]
  attr(h1_out, "unreferenced_withheld") <- NULL
  rownames(h1_in) <- NULL
  rownames(h1_out) <- NULL
  expect_identical(as.data.frame(h1_out), h1_in)
  # the unreferenced_df species that is already H1 is not duplicated as H2
  expect_equal(sum(out$taxon_name == "Hypsoblennius gilberti"), 1L)
  expect_equal(out$taxon_name[out$hypothesis_type == "unreferenced_species" &
    out$taxon_name_rank == "species"], "Hypsoblennius jenkinsi")
})

test_that("objectionable case: a genus with no references and its family ring present is not named", {
  # Old tier (c) let a genus with no reference at all borrow the family ring.
  lik <- rbind(
    .og_lik("ASV_N", "Atherinops affinis", "species", "specific_candidate", 0.30),
    .og_lik("ASV_N", "Atherinops", "genus", "unreferenced_species", 0.48),
    .og_lik("ASV_N", "Atherinopsidae", "family", "unreferenced_genus", 1.0)
  )
  unref <- .og_unref("Leuresthes tenuis", "Leuresthes", "Atherinopsidae")
  expect_no_warning(out <- .og_run(lik, unref))
  expect_false("Leuresthes tenuis" %in% out$taxon_name)
  expect_equal(nrow(named_rows(out)), 0L)
  expect_equal(sum(out$taxon_name == "Atherinopsidae"), 1L)
  w <- attr(out, "unreferenced_withheld")
  expect_equal(nrow(w), 1L)
  expect_equal(w$taxon_name, "Leuresthes tenuis")
  expect_equal(w$genus, "Leuresthes")
  expect_equal(w$family, "Atherinopsidae")
  expect_equal(w$reason, "no_own_genus_ring")
})

test_that("two genus rings in one unit each copy only onto their own genus", {
  lik <- rbind(
    .og_lik("ASV_2", "Hypsoblennius gilberti", "species", "specific_candidate", 0.30),
    .og_lik("ASV_2", "Parablennius incognitus", "species", "specific_candidate", 0.25),
    .og_lik("ASV_2", "Hypsoblennius", "genus", "unreferenced_species", 0.37),
    .og_lik("ASV_2", "Parablennius", "genus", "unreferenced_species", 0.59),
    .og_lik("ASV_2", "Blenniidae", "family", "unreferenced_genus", 0.91)
  )
  unref <- .og_unref(
    c("Hypsoblennius jenkinsi", "Hypsoblennius gentilis",
      "Parablennius sanguinolentus", "Entomacrodus new"),
    c("Hypsoblennius", "Hypsoblennius", "Parablennius", "Entomacrodus"),
    "Blenniidae"
  )
  out <- .og_run(lik, unref)
  nr <- named_rows(out)
  expect_equal(nrow(nr), 3L)
  sc <- setNames(nr$score_likelihood, nr$taxon_name)
  expect_equal(sc[["Hypsoblennius jenkinsi"]], 0.37)
  expect_equal(sc[["Hypsoblennius gentilis"]], 0.37)
  expect_equal(sc[["Parablennius sanguinolentus"]], 0.59)
  expect_true(all(nr$hypothesis_type == "unreferenced_species"))
  # the third genus has no ring: withheld, never given either ring's value
  expect_false("Entomacrodus new" %in% out$taxon_name)
  w <- attr(out, "unreferenced_withheld")
  expect_equal(w$taxon_name, "Entomacrodus new")
  expect_equal(w$reason, "no_own_genus_ring")
  # generic rows of both genera and the family are kept
  expect_equal(sum(out$taxon_name_rank == "genus" & out$hypothesis_type == "unreferenced_species"), 2L)
  expect_equal(sum(out$taxon_name == "Blenniidae"), 1L)
})
