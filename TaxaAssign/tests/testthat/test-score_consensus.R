# test-score_consensus.R

# ==============================================================================
# Helpers
# ==============================================================================

make_match <- function(observation_id, taxon_name, taxon_name_rank, score,
                       genus = NULL, family = NULL, species = NULL) {
  df <- data.frame(
    observation_id = observation_id,
    taxon_name = taxon_name,
    taxon_name_rank = taxon_name_rank,
    score_original = score,
    stringsAsFactors = FALSE
  )
  if (!is.null(genus)) df$genus <- genus
  if (!is.null(family)) df$family <- family
  if (!is.null(species)) df$species <- species
  df
}

# ==============================================================================
# Basic score filtering
# ==============================================================================

test_that("single species above min_score resolves", {
  df <- make_match("s1", "Cottus bairdii", "species", 99,
    genus = "Cottus", family = "Cottidae"
  )
  out <- score_consensus(df,
    min_score = 97, rank_thresholds = NULL,
    rank_system = c("family", "genus", "species")
  )
  expect_equal(out$consensus_taxon, "Cottus bairdii")
  expect_equal(out$consensus_rank, "species")
  expect_true(out$is_resolved)
  expect_equal(out$top_score, 99)
  expect_equal(out$n_retained, 1L)
})

test_that("all hits below min_score returns NA", {
  df <- make_match("s1", "Cottus bairdii", "species", 90,
    genus = "Cottus", family = "Cottidae"
  )
  out <- score_consensus(df,
    min_score = 97, rank_thresholds = NULL,
    rank_system = c("family", "genus", "species")
  )
  expect_true(is.na(out$consensus_taxon))
  expect_equal(out$n_retained, 0L)
})

# ==============================================================================
# Gap filtering
# ==============================================================================

test_that("max_gap keeps only hits within gap of top score", {
  df <- rbind(
    make_match("s1", "Cottus bairdii", "species", 99,
      genus = "Cottus", family = "Cottidae"
    ),
    make_match("s1", "Cottus asper", "species", 98.5,
      genus = "Cottus", family = "Cottidae"
    ),
    make_match("s1", "Leptocottus armatus", "species", 95,
      genus = "Leptocottus", family = "Cottidae"
    )
  )
  out <- score_consensus(df,
    max_gap = 1, rank_thresholds = NULL,
    rank_system = c("family", "genus", "species")
  )
  # Top two within 1% gap -> genus-level LCA (both Cottus)
  expect_equal(out$consensus_taxon, "Cottus")
  expect_equal(out$consensus_rank, "genus")
  expect_equal(out$n_retained, 2L)
  expect_equal(out$n_taxa, 2L)
})

test_that("max_gap = 0 keeps only exact top score", {
  df <- rbind(
    make_match("s1", "Cottus bairdii", "species", 99,
      genus = "Cottus", family = "Cottidae"
    ),
    make_match("s1", "Cottus asper", "species", 98.9,
      genus = "Cottus", family = "Cottidae"
    )
  )
  out <- score_consensus(df,
    max_gap = 0, rank_thresholds = NULL,
    rank_system = c("family", "genus", "species")
  )
  expect_equal(out$consensus_taxon, "Cottus bairdii")
  expect_true(out$is_resolved)
  expect_equal(out$n_retained, 1L)
})

# ==============================================================================
# LCA across genera
# ==============================================================================

test_that("hits from different genera resolve to family", {
  df <- rbind(
    make_match("s1", "Cottus bairdii", "species", 99,
      genus = "Cottus", family = "Cottidae"
    ),
    make_match("s1", "Leptocottus armatus", "species", 99,
      genus = "Leptocottus", family = "Cottidae"
    )
  )
  out <- score_consensus(df,
    rank_thresholds = NULL,
    rank_system = c("family", "genus", "species")
  )
  expect_equal(out$consensus_taxon, "Cottidae")
  expect_equal(out$consensus_rank, "family")
  expect_false(out$is_resolved)
})

# ==============================================================================
# Rank thresholds
# ==============================================================================

test_that("rank_thresholds caps species to genus when top score below species threshold", {
  df <- make_match("s1", "Cottus bairdii", "species", 96,
    genus = "Cottus", family = "Cottidae"
  )
  out <- score_consensus(df,
    rank_thresholds = c(species = 97, genus = 95, family = 90),
    rank_system = c("family", "genus", "species")
  )
  expect_equal(out$consensus_taxon, "Cottus")
  expect_equal(out$consensus_rank, "genus")
  expect_true(out$rank_capped)
  expect_false(out$is_resolved)
})

test_that("rank_thresholds with score meeting species threshold keeps species", {
  df <- make_match("s1", "Cottus bairdii", "species", 99,
    genus = "Cottus", family = "Cottidae"
  )
  out <- score_consensus(df,
    rank_thresholds = c(species = 97, genus = 95, family = 90),
    rank_system = c("family", "genus", "species")
  )
  expect_equal(out$consensus_taxon, "Cottus bairdii")
  expect_equal(out$consensus_rank, "species")
  expect_false(out$rank_capped)
})

test_that("rank_thresholds below all thresholds returns NA", {
  df <- make_match("s1", "Cottus bairdii", "species", 85,
    genus = "Cottus", family = "Cottidae"
  )
  out <- score_consensus(df,
    min_score = 80,
    rank_thresholds = c(species = 97, genus = 95, family = 90),
    rank_system = c("family", "genus", "species")
  )
  expect_true(is.na(out$consensus_taxon))
})

test_that("rank_thresholds caps genus LCA appropriately", {
  # Two Cottus species tie -> LCA = genus, but score only meets family threshold
  df <- rbind(
    make_match("s1", "Cottus bairdii", "species", 94,
      genus = "Cottus", family = "Cottidae"
    ),
    make_match("s1", "Cottus asper", "species", 94,
      genus = "Cottus", family = "Cottidae"
    )
  )
  out <- score_consensus(df,
    rank_thresholds = c(species = 97, genus = 95, family = 90),
    rank_system = c("family", "genus", "species")
  )
  # LCA is genus (Cottus), but 94 < 95 genus threshold -> cap to family
  expect_equal(out$consensus_taxon, "Cottidae")
  expect_equal(out$consensus_rank, "family")
  expect_true(out$rank_capped)
})

# ==============================================================================
# Whitelist upranking
# ==============================================================================

test_that("whitelist keeps consensus when taxon is in whitelist", {
  df <- make_match("s1", "Cottus bairdii", "species", 99,
    genus = "Cottus", family = "Cottidae"
  )
  out <- score_consensus(df,
    whitelist = c("Cottus bairdii", "Cottus asper"),
    rank_thresholds = NULL,
    rank_system = c("family", "genus", "species")
  )
  expect_equal(out$consensus_taxon, "Cottus bairdii")
  expect_false(out$whitelist_capped)
})

test_that("whitelist upranks to genus when species not in whitelist", {
  df <- make_match("s1", "Cottus bairdii", "species", 99,
    genus = "Cottus", family = "Cottidae"
  )
  out <- score_consensus(df,
    whitelist = c("Cottus", "Leptocottus"),
    rank_thresholds = NULL,
    rank_system = c("family", "genus", "species")
  )
  expect_equal(out$consensus_taxon, "Cottus")
  expect_equal(out$consensus_rank, "genus")
  expect_true(out$whitelist_capped)
})

test_that("whitelist returns NA when no rank matches whitelist", {
  df <- make_match("s1", "Cottus bairdii", "species", 99,
    genus = "Cottus", family = "Cottidae"
  )
  out <- score_consensus(df,
    whitelist = c("Salmo", "Oncorhynchus"),
    rank_thresholds = NULL,
    rank_system = c("family", "genus", "species")
  )
  expect_true(is.na(out$consensus_taxon))
  expect_true(out$whitelist_capped)
})

# ==============================================================================
# Multiple samples
# ==============================================================================

test_that("multiple samples processed independently", {
  df <- rbind(
    make_match("s1", "Cottus bairdii", "species", 99,
      genus = "Cottus", family = "Cottidae"
    ),
    make_match("s2", "Cottus asper", "species", 98,
      genus = "Cottus", family = "Cottidae"
    ),
    make_match("s2", "Cottus bairdii", "species", 97,
      genus = "Cottus", family = "Cottidae"
    )
  )
  out <- score_consensus(df,
    rank_thresholds = NULL,
    rank_system = c("family", "genus", "species")
  )
  expect_equal(nrow(out), 2L)
  expect_equal(out$consensus_taxon[out$observation_id == "s1"], "Cottus bairdii")
  expect_equal(out$consensus_rank[out$observation_id == "s2"], "genus")
})

# ==============================================================================
# Interaction: rank_thresholds + whitelist
# ==============================================================================

test_that("rank_thresholds applied before whitelist", {
  # Species consensus, but top score only meets genus threshold.
  # After rank cap -> genus. Genus IS in whitelist -> no further upranking.
  df <- make_match("s1", "Cottus bairdii", "species", 96,
    genus = "Cottus", family = "Cottidae"
  )
  out <- score_consensus(df,
    rank_thresholds = c(species = 97, genus = 95),
    whitelist = c("Cottus", "Cottidae"),
    rank_system = c("family", "genus", "species")
  )
  expect_equal(out$consensus_taxon, "Cottus")
  expect_equal(out$consensus_rank, "genus")
  expect_true(out$rank_capped)
  expect_false(out$whitelist_capped)
})

# ==============================================================================
# Genus derived from binomial (no explicit genus column)
# ==============================================================================

test_that("genus derived from species binomial when genus column absent", {
  df <- rbind(
    make_match("s1", "Cottus bairdii", "species", 99, family = "Cottidae"),
    make_match("s1", "Cottus asper", "species", 98.5, family = "Cottidae")
  )
  out <- score_consensus(df,
    max_gap = 1, rank_thresholds = NULL,
    rank_system = c("family", "genus", "species")
  )
  expect_equal(out$consensus_taxon, "Cottus")
  expect_equal(out$consensus_rank, "genus")
})

# ==============================================================================
# Input validation
# ==============================================================================

test_that("missing rank_thresholds errors with guidance", {
  df <- make_match("s1", "A", "species", 99)
  expect_error(score_consensus(df), "rank_thresholds.*must be specified explicitly")
})

test_that("missing required columns errors", {
  df <- data.frame(observation_id = "s1", taxon_name = "A", stringsAsFactors = FALSE)
  expect_error(score_consensus(df, rank_thresholds = NULL), "missing required column")
})

test_that("non-numeric score errors", {
  df <- data.frame(
    observation_id = "s1", taxon_name = "A",
    taxon_name_rank = "species", score_original = "high",
    stringsAsFactors = FALSE
  )
  expect_error(score_consensus(df, rank_thresholds = NULL), "must be numeric")
})

test_that("negative max_gap errors", {
  df <- make_match("s1", "A", "species", 99)
  expect_error(score_consensus(df, max_gap = -1, rank_thresholds = NULL), "non-negative")
})

# ==============================================================================
# Edge cases
# ==============================================================================

test_that("duplicate accessions for same taxon counted once in n_taxa", {
  df <- rbind(
    make_match("s1", "Cottus bairdii", "species", 99,
      genus = "Cottus", family = "Cottidae"
    ),
    make_match("s1", "Cottus bairdii", "species", 98.5,
      genus = "Cottus", family = "Cottidae"
    )
  )
  out <- score_consensus(df,
    rank_thresholds = NULL,
    rank_system = c("family", "genus", "species")
  )
  expect_equal(out$n_retained, 2L)
  expect_equal(out$n_taxa, 1L)
  expect_equal(out$consensus_taxon, "Cottus bairdii")
})

test_that("custom score_col works", {
  df <- data.frame(
    observation_id = "s1",
    taxon_name = "Cottus bairdii",
    taxon_name_rank = "species",
    pct_identity = 99,
    genus = "Cottus",
    stringsAsFactors = FALSE
  )
  out <- score_consensus(df,
    score_col = "pct_identity", rank_thresholds = NULL,
    rank_system = c("genus", "species")
  )
  expect_equal(out$consensus_taxon, "Cottus bairdii")
})

# ==============================================================================
# consensus_mode = "bracket" (Jonah Ventures rule)  [2026-09-12]
# ==============================================================================

# Helper: n hits for one observation, given per-hit species labels.
# Scores default to a single tight bracket so the bracket step is a no-op and
# only the agreement rule is under test.
make_hits <- function(species, score = 99, observation_id = "s1",
                      genus = NULL, family = NULL) {
  if (is.null(genus)) {
    genus <- ifelse(is.na(species), NA_character_, sub(" .*", "", species))
  }
  data.frame(
    observation_id = observation_id,
    taxon_name = species,
    taxon_name_rank = "species",
    score_original = score,
    genus = genus,
    family = family %||% "Cottidae",
    stringsAsFactors = FALSE
  )
}
`%||%` <- function(x, y) if (is.null(x)) y else x

RS <- c("family", "genus", "species")

test_that("bracket mode with agreement_fraction = 1 and a wide bracket equals gap mode", {
  df <- rbind(
    make_match("s1", "Cottus bairdii", "species", 99,
      genus = "Cottus", family = "Cottidae"
    ),
    make_match("s1", "Cottus asper", "species", 98.5,
      genus = "Cottus", family = "Cottidae"
    ),
    make_match("s1", "Leptocottus armatus", "species", 98.2,
      genus = "Leptocottus", family = "Cottidae"
    )
  )
  gap <- score_consensus(df,
    max_gap = 3, rank_thresholds = NULL, rank_system = RS
  )
  brk <- score_consensus(df,
    consensus_mode = "bracket", agreement_fraction = 1, bracket_width = 3,
    rank_thresholds = NULL, rank_system = RS
  )
  expect_equal(brk$consensus_taxon, gap$consensus_taxon)
  expect_equal(brk$consensus_rank, gap$consensus_rank)
  expect_equal(brk$is_resolved, gap$is_resolved)
  expect_equal(brk$n_retained, gap$n_retained)

  # ... and the same holds when the whole bracket agrees at species level
  df2 <- rbind(
    make_match("s1", "Cottus bairdii", "species", 99,
      genus = "Cottus", family = "Cottidae"
    ),
    make_match("s1", "Cottus bairdii", "species", 98.4,
      genus = "Cottus", family = "Cottidae"
    )
  )
  gap2 <- score_consensus(df2,
    max_gap = 2, rank_thresholds = NULL, rank_system = RS
  )
  brk2 <- score_consensus(df2,
    consensus_mode = "bracket", agreement_fraction = 1, bracket_width = 2,
    rank_thresholds = NULL, rank_system = RS
  )
  expect_equal(brk2$consensus_taxon, gap2$consensus_taxon)
  expect_equal(brk2$consensus_rank, gap2$consensus_rank)
})

test_that("90% rule: 9 of 10 hits agreeing at species resolves to species", {
  df <- make_hits(c(rep("Cottus bairdii", 9), "Cottus asper"))
  out <- score_consensus(df,
    consensus_mode = "bracket", agreement_fraction = 0.9,
    rank_thresholds = NULL, rank_system = RS
  )
  expect_equal(out$consensus_taxon, "Cottus bairdii")
  expect_equal(out$consensus_rank, "species")
  expect_true(out$is_resolved)
  expect_equal(out$consensus_reason, "bracket")
  expect_equal(out$agreement_achieved, 0.9)
  expect_equal(out$n_retained, 10L)
  expect_equal(out$n_taxa, 2L)
})

test_that("strict unanimity upranks the same 9/10 case to genus", {
  df <- make_hits(c(rep("Cottus bairdii", 9), "Cottus asper"))
  out <- score_consensus(df,
    consensus_mode = "bracket", agreement_fraction = 1,
    rank_thresholds = NULL, rank_system = RS
  )
  expect_equal(out$consensus_taxon, "Cottus")
  expect_equal(out$consensus_rank, "genus")
  expect_false(out$is_resolved)
})

test_that("the agreement boundary is inclusive: exactly 9/10 at 0.9 resolves", {
  nine <- make_hits(c(rep("Cottus bairdii", 9), "Cottus asper"))
  expect_equal(
    score_consensus(nine,
      consensus_mode = "bracket", agreement_fraction = 0.9,
      rank_thresholds = NULL, rank_system = RS
    )$consensus_rank,
    "species"
  )
  # 8/10 is genuinely below the bar and must NOT resolve at species
  eight <- make_hits(c(rep("Cottus bairdii", 8), rep("Cottus asper", 2)))
  expect_equal(
    score_consensus(eight,
      consensus_mode = "bracket", agreement_fraction = 0.9,
      rank_thresholds = NULL, rank_system = RS
    )$consensus_rank,
    "genus"
  )
  # And a fraction that is not exactly representable in binary (27/30 = 0.9)
  # must still clear a 0.9 bar.
  thirty <- make_hits(c(rep("Cottus bairdii", 27), rep("Cottus asper", 3)))
  expect_equal(
    score_consensus(thirty,
      consensus_mode = "bracket", agreement_fraction = 0.9,
      rank_thresholds = NULL, rank_system = RS
    )$consensus_rank,
    "species"
  )
})

test_that("missing rank labels count toward the denominator, not toward any taxon", {
  # 9 hits labelled to species + 1 hit with NO species label. The 9 agreeing
  # hits are 9/10 = 0.9 of the retained hits, so at agreement_fraction = 0.9
  # this still resolves...
  df <- rbind(
    make_hits(rep("Cottus bairdii", 9)),
    data.frame(
      observation_id = "s1", taxon_name = "Cottidae",
      taxon_name_rank = "family", score_original = 99,
      genus = NA_character_, family = "Cottidae", stringsAsFactors = FALSE
    )
  )
  out09 <- score_consensus(df,
    consensus_mode = "bracket", agreement_fraction = 0.9,
    rank_thresholds = NULL, rank_system = RS
  )
  expect_equal(out09$consensus_rank, "species")
  expect_equal(out09$agreement_achieved, 0.9)

  # ...but at 0.95 the unlabelled hit is what blocks it: it counts against
  # species (9/10 < 0.95), so the consensus falls back to family, where all
  # 10 hits DO carry a label.
  out095 <- score_consensus(df,
    consensus_mode = "bracket", agreement_fraction = 0.95,
    rank_thresholds = NULL, rank_system = RS
  )
  expect_equal(out095$consensus_rank, "family")
  expect_equal(out095$consensus_taxon, "Cottidae")
  expect_equal(out095$agreement_achieved, 1)

  # Guard against the "drop the NAs" bug specifically: if the unlabelled hit
  # were dropped, species agreement would compute as 9/9 = 1 and resolve.
  expect_false(out095$consensus_rank == "species")
})

test_that("bracket_fallback fires only when BOTH conditions hold", {
  # Built so the 1% bracket splits 1:1 at family (no family >= 90%), while
  # widening to 2% pulls in 18 more Cottidae hits -> 19/20 = 0.95 at family.
  narrow <- rbind(
    make_hits("Cottus bairdii", score = 99, family = "Cottidae"),
    make_hits("Clupea harengus", score = 98.5, family = "Clupeidae")
  )
  # 18 further Cottidae hits, each a DIFFERENT genus+species, so widening
  # cannot resolve at species or genus -- only at family (19/20 = 0.95).
  wide_extra <- make_hits(paste0("Gen", 1:18, " sp", 1:18),
    score = 97.6, family = "Cottidae"
  )
  df <- rbind(narrow, wide_extra)

  fb <- list(min_score = 97, rank = "family", width = 2)

  # No fallback: the 1% bracket gives 1 Cottidae + 1 Clupeidae -> nothing at
  # 90% anywhere.
  none <- score_consensus(df,
    consensus_mode = "bracket", agreement_fraction = 0.9, bracket_width = 1,
    rank_thresholds = NULL, rank_system = RS
  )
  expect_true(is.na(none$consensus_taxon))
  expect_equal(none$bracket_width_used, 1)

  # Fallback armed and both conditions met (top score 99 >= 97, nothing at
  # family or finer) -> widened.
  hit <- score_consensus(df,
    consensus_mode = "bracket", agreement_fraction = 0.9, bracket_width = 1,
    bracket_fallback = fb, rank_thresholds = NULL, rank_system = RS
  )
  expect_equal(hit$consensus_taxon, "Cottidae")
  expect_equal(hit$consensus_rank, "family")
  expect_equal(hit$consensus_reason, "bracket_widened")
  expect_equal(hit$bracket_width_used, 2)
  expect_equal(hit$n_retained, 20L)

  # Condition 1 fails: the same shape shifted below the 97 score floor.
  low <- df
  low$score_original <- low$score_original - 10
  low_out <- score_consensus(low,
    consensus_mode = "bracket", agreement_fraction = 0.9, bracket_width = 1,
    bracket_fallback = fb, rank_thresholds = NULL, rank_system = RS
  )
  expect_true(is.na(low_out$consensus_taxon))
  expect_equal(low_out$bracket_width_used, 1)

  # Condition 2 fails: the 1% bracket already returns a family-level name, so
  # the fallback must not fire even though the top score clears 97.
  ok <- rbind(
    make_hits(rep("Cottus bairdii", 9), score = 99, family = "Cottidae"),
    make_hits("Cottus asper", score = 98.5, family = "Cottidae"),
    make_hits(rep("Clupea harengus", 30), score = 97.6, family = "Clupeidae")
  )
  ok_out <- score_consensus(ok,
    consensus_mode = "bracket", agreement_fraction = 0.9, bracket_width = 1,
    bracket_fallback = fb, rank_thresholds = NULL, rank_system = RS
  )
  expect_equal(ok_out$consensus_taxon, "Cottus bairdii")
  expect_equal(ok_out$consensus_reason, "bracket")
  expect_equal(ok_out$bracket_width_used, 1)
})

test_that("all hits below min_score are unresolvable in both modes", {
  df <- make_hits(c(rep("Cottus bairdii", 9), "Cottus asper"), score = 90)
  for (mode in c("gap", "bracket")) {
    out <- score_consensus(df,
      consensus_mode = mode, min_score = 97, agreement_fraction = 0.9,
      rank_thresholds = NULL, rank_system = RS
    )
    expect_true(is.na(out$consensus_taxon), info = mode)
    expect_true(is.na(out$consensus_rank), info = mode)
    expect_equal(out$n_retained, 0L, info = mode)
    expect_true(is.na(out$bracket_width_used), info = mode)
    expect_true(is.na(out$agreement_achieved), info = mode)
  }
})

test_that("bracket window is anchored at the top score and excludes hits below it", {
  df <- rbind(
    make_hits(rep("Cottus bairdii", 2), score = 99),
    make_hits(rep("Clupea harengus", 20), score = 97.5, family = "Clupeidae")
  )
  out <- score_consensus(df,
    consensus_mode = "bracket", agreement_fraction = 0.9, bracket_width = 1,
    rank_thresholds = NULL, rank_system = RS
  )
  # The 20 Clupea hits are 1.5 below the top score -> outside the 1% bracket.
  expect_equal(out$n_retained, 2L)
  expect_equal(out$consensus_taxon, "Cottus bairdii")
})

test_that("bracket mode counts hits, not distinct taxa", {
  # 1 Leptocottus hit vs 9 Cottus bairdii hits. Counting distinct taxa would
  # give 1/2 at genus and uprank to family; counting hits gives 9/10.
  df <- rbind(
    make_hits(rep("Cottus bairdii", 9)),
    make_hits("Leptocottus armatus")
  )
  out <- score_consensus(df,
    consensus_mode = "bracket", agreement_fraction = 0.9,
    rank_thresholds = NULL, rank_system = RS
  )
  expect_equal(out$consensus_taxon, "Cottus bairdii")
  expect_equal(out$consensus_rank, "species")
})

test_that("several taxa clearing the bar at one rank yields NA at that rank", {
  # At agreement_fraction = 0.4 both species hold 0.5 -> ambiguous, so the
  # rank must yield NA and the walk continue coarser (both are Cottidae).
  df <- rbind(
    make_hits(rep("Cottus bairdii", 5)),
    make_hits(rep("Leptocottus armatus", 5))
  )
  out <- score_consensus(df,
    consensus_mode = "bracket", agreement_fraction = 0.4,
    rank_thresholds = NULL, rank_system = RS
  )
  expect_equal(out$consensus_rank, "family")
  expect_equal(out$consensus_taxon, "Cottidae")
})

test_that("rank_thresholds and whitelist still apply after the bracket step", {
  df <- make_hits(c(rep("Cottus bairdii", 9), "Cottus asper"), score = 96)
  capped <- score_consensus(df,
    consensus_mode = "bracket", agreement_fraction = 0.9, min_score = 90,
    rank_thresholds = c(species = 97, genus = 95, family = 90),
    rank_system = RS
  )
  expect_equal(capped$consensus_taxon, "Cottus")
  expect_equal(capped$consensus_rank, "genus")
  expect_true(capped$rank_capped)
  expect_equal(capped$consensus_reason, "threshold")

  wl <- score_consensus(df,
    consensus_mode = "bracket", agreement_fraction = 0.9, min_score = 90,
    whitelist = c("Cottus", "Cottidae"), rank_thresholds = NULL,
    rank_system = RS
  )
  expect_equal(wl$consensus_taxon, "Cottus")
  expect_true(wl$whitelist_capped)
})

test_that("new diagnostic columns are present in gap mode too", {
  df <- make_match("s1", "Cottus bairdii", "species", 99,
    genus = "Cottus", family = "Cottidae"
  )
  out <- score_consensus(df, rank_thresholds = NULL, rank_system = RS)
  expect_true(all(c("bracket_width_used", "agreement_achieved") %in% names(out)))
  expect_true(is.na(out$bracket_width_used))
  expect_equal(out$agreement_achieved, 1)
})

# ==============================================================================
# New-argument validation
# ==============================================================================

test_that("new arguments are validated", {
  df <- make_match("s1", "A", "species", 99, genus = "A", family = "F")
  expect_error(
    score_consensus(df, rank_thresholds = NULL, agreement_fraction = 0),
    "agreement_fraction"
  )
  expect_error(
    score_consensus(df, rank_thresholds = NULL, agreement_fraction = 1.5),
    "agreement_fraction"
  )
  expect_error(
    score_consensus(df, rank_thresholds = NULL, bracket_width = 0),
    "bracket_width"
  )
  expect_error(
    score_consensus(df, rank_thresholds = NULL, consensus_mode = "jonah"),
    "should be one of"
  )
  expect_error(
    score_consensus(df,
      rank_thresholds = NULL, consensus_mode = "bracket",
      bracket_fallback = list(min_score = 97, width = 2)
    ),
    "missing element"
  )
  expect_error(
    score_consensus(df,
      rank_thresholds = NULL, consensus_mode = "bracket", rank_system = RS,
      bracket_fallback = list(min_score = 97, rank = "tribe", width = 2)
    ),
    "not in.*rank system"
  )
})
