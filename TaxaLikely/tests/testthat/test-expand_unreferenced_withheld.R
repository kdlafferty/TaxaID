# Withheld rows of expand_unreferenced_hypotheses(): a species is never named from a FAMILY ring, whether or not its genus has references
# (a specific_candidate row ANYWHERE in likelihood_df); it is named only from
# its own genus ring, and every species so withheld is listed with a reason.
# Fixtures are offline and mirror real Mugu units (numbers
# simplified, shapes exact).

.wh_lik <- function(obs, name, rank, type, score) {
  data.frame(
    observation_id = obs, taxon_name = name, taxon_name_rank = rank,
    hypothesis_type = type, score_likelihood = score,
    score_likelihood_mean = score, score_likelihood_sd = 0,
    stringsAsFactors = FALSE
  )
}

.wh_unref <- function(species, genus, family, observation_id = NULL) {
  d <- data.frame(species = species, genus = genus, family = family,
                  stringsAsFactors = FALSE)
  if (!is.null(observation_id)) d$observation_id <- observation_id
  d
}

.wh_cols <- c("observation_id", "taxon_name", "genus", "family", "reason")

.wh_run <- function(lik, unref) {
  suppressMessages(expand_unreferenced_hypotheses(lik, unref))
}

# ASV_595 shape (12S): Atherinops affinis matched, genus ring + family ring
# present; Menidia is referenced elsewhere (ASV_109).
.wh_595_lik <- function() {
  rbind(
    .wh_lik("ASV_595", "Atherinops affinis", "species", "specific_candidate", 0.20),
    .wh_lik("ASV_595", "Atherinops", "genus", "unreferenced_species", 0.48),
    .wh_lik("ASV_595", "Atherinopsidae", "family", "unreferenced_genus", 1.0),
    .wh_lik("ASV_109", "Menidia beryllina", "species", "specific_candidate", 1.0)
  )
}

test_that("ASV_595: species of referenced and unreferenced genera are both withheld from the family ring", {
  unref <- .wh_unref(
    c("Menidia audens", "Leuresthes tenuis"),
    c("Menidia", "Leuresthes"), c("Atherinopsidae", "Atherinopsidae")
  )
  expect_message(
    out <- expand_unreferenced_hypotheses(.wh_595_lik(), unref),
    "withheld"
  )
  o <- out[out$observation_id == "ASV_595", ]
  expect_false("Menidia audens" %in% o$taxon_name)
  # a genus with no references anywhere is NOT named from the family ring
  # either: it has no ring of its own in this unit
  expect_false("Leuresthes tenuis" %in% o$taxon_name)
  expect_equal(sum(o$hypothesis_type == "unreferenced_genus" & o$taxon_name_rank == "species"), 0L)
  # the generic family row is kept
  fam <- o[o$taxon_name == "Atherinopsidae", ]
  expect_equal(nrow(fam), 1L)
  expect_equal(fam$hypothesis_type, "unreferenced_genus")
  w <- attr(out, "unreferenced_withheld")
  expect_s3_class(w, "data.frame")
  expect_identical(names(w), .wh_cols)
  expect_equal(nrow(w), 2L)
  expect_equal(w$observation_id, c("ASV_595", "ASV_595"))
  expect_equal(w$taxon_name, c("Menidia audens", "Leuresthes tenuis"))
  expect_equal(w$genus, c("Menidia", "Leuresthes"))
  expect_equal(w$family, c("Atherinopsidae", "Atherinopsidae"))
  expect_equal(w$reason, c("genus_referenced_unmatched", "no_own_genus_ring"))
})

test_that("ASV_494: the genus-ring copy of a referenced-genus species stays", {
  lik <- rbind(
    .wh_lik("ASV_494", "Menidia beryllina", "species", "specific_candidate", 1.0),
    .wh_lik("ASV_494", "Menidia peninsulae", "species", "specific_candidate", 1.0),
    .wh_lik("ASV_494", "Menidia", "genus", "unreferenced_species", 0.96),
    .wh_lik("ASV_494", "Atherinopsidae", "family", "unreferenced_genus", 0.18)
  )
  unref <- .wh_unref("Menidia audens", "Menidia", "Atherinopsidae")
  out <- .wh_run(lik, unref)
  a <- out[out$taxon_name == "Menidia audens", ]
  expect_equal(nrow(a), 1L)
  expect_equal(a$hypothesis_type, "unreferenced_species")
  expect_equal(a$score_likelihood, 0.96)
  w <- attr(out, "unreferenced_withheld")
  expect_equal(nrow(w), 0L)
  expect_false("Menidia audens" %in% w$taxon_name)
})

test_that("ASV_109: a species that is itself a specific_candidate is untouched", {
  lik <- rbind(
    .wh_lik("ASV_109", "Menidia beryllina", "species", "specific_candidate", 1.0),
    .wh_lik("ASV_109", "Menidia audens", "species", "specific_candidate", 0.72),
    .wh_lik("ASV_109", "Atherinopsidae", "family", "unreferenced_genus", 0.30)
  )
  unref <- .wh_unref("Menidia audens", "Menidia", "Atherinopsidae")
  out <- .wh_run(lik, unref)
  a <- out[out$taxon_name == "Menidia audens", ]
  expect_equal(nrow(a), 1L)
  expect_equal(a$hypothesis_type, "specific_candidate")
  expect_equal(a$score_likelihood, 0.72)
  w <- attr(out, "unreferenced_withheld")
  expect_equal(sum(w$observation_id == "ASV_109"), 0L)
  expect_equal(nrow(w), 0L)
})

test_that("ASV_606: three referenced-genus species withheld; generic and genus rings stay", {
  lik <- rbind(
    .wh_lik("ASV_606", "Hypsoblennius hentz", "species", "specific_candidate", 0.20),
    .wh_lik("ASV_606", "Hypsoblennius sordidus", "species", "specific_candidate", 0.14),
    .wh_lik("ASV_606", "Parablennius incognitus", "species", "specific_candidate", 0.23),
    .wh_lik("ASV_606", "Parablennius", "genus", "unreferenced_species", 0.59),
    .wh_lik("ASV_606", "Blenniidae", "family", "unreferenced_genus", 1.0)
  )
  sp <- c("Hypsoblennius jenkinsi", "Hypsoblennius gilberti", "Hypsoblennius gentilis")
  unref <- .wh_unref(sp, "Hypsoblennius", "Blenniidae")
  out <- .wh_run(lik, unref)
  expect_false(any(sp %in% out$taxon_name))
  w <- attr(out, "unreferenced_withheld")
  expect_setequal(w$taxon_name, sp)
  expect_equal(nrow(w), 3L)
  expect_true(all(w$observation_id == "ASV_606"))
  expect_true(all(w$reason == "genus_referenced_unmatched"))
  expect_true(all(w$family == "Blenniidae"))
  expect_equal(sum(out$taxon_name == "Blenniidae" & out$hypothesis_type == "unreferenced_genus"), 1L)
  pb <- out[out$taxon_name == "Parablennius", ]
  expect_equal(nrow(pb), 1L)
  expect_equal(pb$hypothesis_type, "unreferenced_species")
  expect_equal(pb$score_likelihood, 0.59)
})

test_that("degenerate input: no specific_candidate anywhere raises no warning; family species are withheld as no_own_genus_ring", {
  lik <- rbind(
    .wh_lik("U1", "Fundulus", "genus", "unreferenced_species", 0.31),
    .wh_lik("U1", "Fundulidae", "family", "unreferenced_genus", 0.04)
  )
  unref <- .wh_unref(
    c("Fundulus parvipinnis", "Lucania parva"),
    c("Fundulus", "Lucania"), c("Fundulidae", "Fundulidae")
  )
  w_seen <- character(0)
  out <- withCallingHandlers(
    suppressMessages(expand_unreferenced_hypotheses(lik, unref)),
    warning = function(w) {
      w_seen <<- c(w_seen, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  expect_length(w_seen, 0L)
  expect_no_warning(suppressMessages(expand_unreferenced_hypotheses(lik, unref)))
  # Lucania has no ring of its own: never named from the family ring
  expect_false("Lucania parva" %in% out$taxon_name)
  expect_equal(sum(out$hypothesis_type == "unreferenced_genus" & out$taxon_name_rank == "species"), 0L)
  # Fundulus has its own genus ring and is still named from it
  expect_equal(out$score_likelihood[out$taxon_name == "Fundulus parvipinnis"], 0.31)
  expect_equal(out$hypothesis_type[out$taxon_name == "Fundulus parvipinnis"], "unreferenced_species")
  w <- attr(out, "unreferenced_withheld")
  expect_equal(nrow(w), 1L)
  expect_equal(w$taxon_name, "Lucania parva")
  expect_equal(w$genus, "Lucania")
  expect_equal(w$family, "Fundulidae")
  expect_equal(w$observation_id, "U1")
  expect_equal(w$reason, "no_own_genus_ring")
  # the generic rows are kept
  expect_equal(sum(out$taxon_name == "Fundulidae" & out$hypothesis_type == "unreferenced_genus"), 1L)
  expect_equal(sum(out$taxon_name == "Fundulus" & out$hypothesis_type == "unreferenced_species"), 1L)
})

test_that("observation-scoped unreferenced row is withheld there and does not touch another unit", {
  lik <- rbind(
    .wh_lik("U1", "Menidia beryllina", "species", "specific_candidate", 1.0),
    .wh_lik("U1", "Atherinopsidae", "family", "unreferenced_genus", 0.40),
    .wh_lik("U2", "Atherinops affinis", "species", "specific_candidate", 0.50),
    .wh_lik("U2", "Atherinopsidae", "family", "unreferenced_genus", 0.60)
  )
  unref <- .wh_unref("Menidia audens", "Menidia", "Atherinopsidae", observation_id = "U1")
  out <- .wh_run(lik, unref)
  expect_false("Menidia audens" %in% out$taxon_name)
  w <- attr(out, "unreferenced_withheld")
  expect_equal(nrow(w), 1L)
  expect_equal(w$observation_id, "U1")
  expect_equal(sum(out$observation_id == "U2"), 2L)
  expect_equal(sum(out$observation_id == "U1"), 2L)
})

test_that("the withheld attribute has its five columns; a species of an unreferenced genus is withheld, not named", {
  lik <- rbind(
    .wh_lik("ESV_001", "Atherinops affinis", "species", "specific_candidate", 0.95),
    .wh_lik("ESV_001", "Fundulus", "genus", "unreferenced_species", 0.31),
    .wh_lik("ESV_001", "Fundulidae", "family", "unreferenced_genus", 0.04)
  )
  unref <- .wh_unref("Lucania parva", "Lucania", "Fundulidae")
  out <- .wh_run(lik, unref)
  w <- attr(out, "unreferenced_withheld")
  expect_s3_class(w, "data.frame")
  expect_identical(names(w), .wh_cols)
  expect_equal(nrow(w), 1L)
  expect_equal(w$taxon_name, "Lucania parva")
  expect_equal(w$reason, "no_own_genus_ring")
  expect_equal(sum(out$hypothesis_type == "unreferenced_genus" &
    out$taxon_name_rank == "species"), 0L)
})

test_that("the withheld attribute is present and empty, with its five columns, when no family ring holds a local species", {
  lik <- rbind(
    .wh_lik("ESV_001", "Atherinops affinis", "species", "specific_candidate", 0.95),
    .wh_lik("ESV_001", "Fundulidae", "family", "unreferenced_genus", 0.04)
  )
  out <- .wh_run(lik, .wh_unref("Cottus bairdii", "Cottus", "Cottidae"))
  w <- attr(out, "unreferenced_withheld")
  expect_s3_class(w, "data.frame")
  expect_identical(names(w), .wh_cols)
  expect_equal(nrow(w), 0L)
})

# ---- input-shape grid --------------------------------------------------------

.wh_grid_lik <- function(shape) {
  cand <- .wh_lik("O1", "Atherinops affinis", "species", "specific_candidate", 0.95)
  gen <- .wh_lik("O1", "Fundulus", "genus", "unreferenced_species", 0.31)
  fam <- .wh_lik("O1", "Fundulidae", "family", "unreferenced_genus", 0.04)
  switch(shape,
    with_genus_ring = rbind(cand, gen, fam),
    without_genus_ring = rbind(cand, fam),
    without_family_ring = rbind(cand, gen),
    no_candidates = rbind(gen, fam)
  )
}

.wh_grid_unref <- function(shape) {
  base <- .wh_unref(
    c("Fundulus parvipinnis", "Fundulus zebrinus", "Lucania parva"),
    c("Fundulus", "Fundulus", "Lucania"), rep("Fundulidae", 3L)
  )
  extra <- switch(shape,
    plain = NULL,
    duplicate_species = .wh_unref("Lucania parva", "Lucania", "Fundulidae"),
    na_genus = .wh_unref("Gambusia affinis", NA_character_, "Fundulidae"),
    na_species = .wh_unref(NA_character_, "Lucania", "Fundulidae"),
    empty_family = .wh_unref("Cyprinodon variegatus", "Cyprinodon", "")
  )
  rbind(base, extra)
}

# Expected rows, by hand. Fundulus is never referenced here (the only candidate
# is Atherinops). A species is named only from its own genus ring (Fundulus,
# when present); no family-ring species is ever named. Every species the family
# ring would have named is withheld as no_own_genus_ring. NA names are never
# emitted; duplicates collapse.
.wh_grid_expect <- function(u, l) {
  has_genus <- l %in% c("with_genus_ring", "without_family_ring", "no_candidates")
  has_fam <- l %in% c("with_genus_ring", "without_genus_ring", "no_candidates")
  h2 <- if (has_genus) c("Fundulus parvipinnis", "Fundulus zebrinus") else character(0)
  fam_sp <- c("Lucania parva", if (u == "na_genus") "Gambusia affinis")
  fam_sp <- c(fam_sp, if (!has_genus) c("Fundulus parvipinnis", "Fundulus zebrinus"))
  withheld <- if (has_fam) fam_sp else character(0)
  list(h2 = sort(h2), h3 = character(0), withheld = sort(withheld))
}

for (u in c("plain", "duplicate_species", "na_genus", "na_species", "empty_family")) {
  for (l in c("with_genus_ring", "without_genus_ring", "without_family_ring", "no_candidates")) {
    local({
      u <- u
      l <- l
      test_that(sprintf("input shape grid: unreferenced_df=%s x likelihood_df=%s", u, l), {
        lik <- .wh_grid_lik(l)
        unref <- .wh_grid_unref(u)
        run <- function() suppressWarnings(suppressMessages(
          expand_unreferenced_hypotheses(lik, unref)
        ))
        expect_no_error(out <- run())
        key <- paste(out$observation_id, out$taxon_name, sep = "\r")
        expect_false(anyDuplicated(key) > 0L)
        exp <- .wh_grid_expect(u, l)
        named <- out[out$taxon_name_rank == "species" &
          out$hypothesis_type != "specific_candidate", ]
        expect_equal(sort(named$taxon_name[named$hypothesis_type == "unreferenced_species"]), exp$h2)
        expect_equal(sort(named$taxon_name[named$hypothesis_type == "unreferenced_genus"]), exp$h3)
        expect_false(anyNA(named$taxon_name))
        w <- attr(out, "unreferenced_withheld")
        expect_s3_class(w, "data.frame")
        expect_identical(names(w), .wh_cols)
        expect_equal(sort(w$taxon_name), exp$withheld)
        expect_true(all(w$reason == "no_own_genus_ring"))
        expect_false(any(w$taxon_name %in% named$taxon_name))
      })
    })
  }
}
