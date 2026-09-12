# jv_bracket_consensus_validation.R
# ------------------------------------------------------------------------------
# Validate TaxaAssign::score_consensus(consensus_mode = "bracket") against Jonah
# Ventures' OWN delivered consensus taxonomy for the Pt Conception MiFish runs.
#
# Why this is a real test and not a circular one
# ----------------------------------------------
# JV ship two files per run:
#   *-esv-data.csv   the "detailed hits" table: one row per (ESV, accession)
#                    with PercMatch and the accession's Kingdom..Species.
#   *-read-data.csv  one row per ESV carrying JV's OWN consensus Kingdom..Species.
# The second is derived from the first by the rule we are reproducing, so
# feeding the first through score_consensus(consensus_mode = "bracket") and
# comparing to the second tests the ALGORITHM in isolation: both sides see the
# identical hit table, so any disagreement is the decision rule (or an
# undocumented detail of it), not a reference-database difference. Running
# TaxaID's own BLAST output through it instead would confound the two.
#
# NOT a tuning target: we cannot see JV's reference library, their taxonomic
# backbone, or their tie-breaking, so exact reproduction is not expected and
# chasing it would be overfitting. The useful output is the number plus a
# characterisation of the residual.
#
# Run:  Rscript diagnostics/jv_bracket_consensus_validation.R
# ------------------------------------------------------------------------------

suppressMessages(library(TaxaAssign))

DATA_DIR <- file.path(
  "/Users/lafferty/My Drive/Stats and Data/PtConceptionEDNA",
  "Schulte_PtConception_DataScript_20260526/Data"
)

RUNS <- list(
  JVB3105 = list(
    hits      = "JVB3105-MiFishU-esv-data.csv",
    delivered = "JVB3105-MiFishU-read-data.csv"
  ),
  JVB3506 = list(
    hits      = "JVB3506-MiFishU-esv-data_JV270.csv",
    delivered = "JVB3506-MiFishU-read-data_JV270.csv"
  )
)

RANKS <- c("kingdom", "phylum", "class", "order", "family", "genus", "species")
JV_COLS <- c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")

# JV write "" for "no name at this rank" and "unk_<rank>" (e.g. "unk_order")
# for "rank not resolved". Both are absent labels and are normalised to NA on
# BOTH sides, so the comparison never scores a placeholder against a real name.
.blank_to_na <- function(x) {
  x <- trimws(as.character(x))
  x[x == "" | grepl("^unk_", x) | x %in% c("NA", "N/A")] <- NA_character_
  x
}

# ------------------------------------------------------------------------------
# Build a TaxaID match_df from JV's detailed-hits table
# ------------------------------------------------------------------------------
read_hits <- function(path) {
  raw <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  tax <- as.data.frame(lapply(raw[JV_COLS], .blank_to_na), stringsAsFactors = FALSE)
  names(tax) <- RANKS

  # taxon_name / taxon_name_rank are the finest non-missing rank for the hit.
  finest_name <- rep(NA_character_, nrow(tax))
  finest_rank <- rep(NA_character_, nrow(tax))
  for (rk in RANKS) { # coarse -> fine, so the last non-NA wins
    hit <- !is.na(tax[[rk]])
    finest_name[hit] <- tax[[rk]][hit]
    finest_rank[hit] <- rk
  }

  out <- data.frame(
    observation_id = raw$ESVId,
    taxon_name = finest_name,
    taxon_name_rank = finest_rank,
    score_original = as.numeric(raw$PercMatch),
    accession = raw$Accession,
    stringsAsFactors = FALSE
  )
  out <- cbind(out, tax)
  out[!is.na(out$taxon_name) & !is.na(out$score_original), ]
}

read_delivered <- function(path) {
  raw <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE)
  tax <- as.data.frame(lapply(raw[JV_COLS], .blank_to_na), stringsAsFactors = FALSE)
  names(tax) <- paste0("jv_", RANKS)
  jv_name <- rep(NA_character_, nrow(tax))
  jv_rank <- rep(NA_character_, nrow(tax))
  for (rk in RANKS) {
    hit <- !is.na(tax[[paste0("jv_", rk)]])
    jv_name[hit] <- tax[[paste0("jv_", rk)]][hit]
    jv_rank[hit] <- rk
  }
  cbind(
    data.frame(
      observation_id = raw$ESVId,
      jv_taxon = jv_name,
      jv_rank = jv_rank,
      jv_pct = suppressWarnings(as.numeric(raw[["% match"]])),
      jv_n_species = suppressWarnings(as.numeric(raw[["# species"]])),
      stringsAsFactors = FALSE
    ),
    tax
  )
}

# ------------------------------------------------------------------------------
# Per-rank labels under the same agreement rule, for a rank-by-rank comparison.
# JV deliver a full Kingdom..Species vector per ESV, not just the finest rank,
# so this is the like-for-like view; score_consensus() itself returns only the
# finest non-NA rank (the standard TaxaID consensus contract).
# ------------------------------------------------------------------------------
per_rank_labels <- function(match_df, agreement_fraction = 0.9, bracket_width = 1) {
  ids <- unique(match_df$observation_id)
  split_df <- split(match_df, match_df$observation_id)
  res <- lapply(ids, function(id) {
    chunk <- split_df[[id]]
    top <- max(chunk$score_original, na.rm = TRUE)
    kept <- chunk[chunk$score_original > (top - bracket_width), , drop = FALSE]
    n <- nrow(kept)
    vals <- vapply(RANKS, function(rk) {
      v <- kept[[rk]]
      v <- v[!is.na(v)]
      if (length(v) == 0L) {
        return(NA_character_)
      }
      tab <- table(v)
      meets <- tab[(as.numeric(tab) / n) >= (agreement_fraction - 1e-8)]
      if (length(meets) != 1L) NA_character_ else names(meets)[[1L]]
    }, character(1))
    as.data.frame(c(list(observation_id = id), as.list(vals)),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, res)
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
FALLBACK <- list(min_score = 97, rank = "family", width = 2)

all_cmp <- list()

for (run in names(RUNS)) {
  cat("\n", strrep("=", 78), "\n", run, "\n", strrep("=", 78), "\n", sep = "")

  hits <- read_hits(file.path(DATA_DIR, RUNS[[run]]$hits))
  deliv <- read_delivered(file.path(DATA_DIR, RUNS[[run]]$delivered))

  cat(
    "hit rows:", nrow(hits),
    "| ESVs with hits:", length(unique(hits$observation_id)),
    "| delivered ESV rows:", nrow(deliv), "\n"
  )

  # How wide is each ESV's delivered hit set? JV describe the detailed-hits
  # file as "all hits in the 1% bracket", so the bracket step should be close
  # to a no-op on this input -- worth confirming rather than assuming.
  rng <- tapply(hits$score_original, hits$observation_id, function(x) max(x) - min(x))
  cat(
    "per-ESV hit score range: max =", round(max(rng), 3),
    "| ESVs with range > 1:", sum(rng > 1 + 1e-9),
    "| ESVs with a hit exactly at top-1:", sum(abs(rng - 1) < 1e-9), "\n"
  )

  sc <- suppressMessages(score_consensus(
    hits,
    min_score          = 0,
    score_col          = "score_original",
    rank_system        = RANKS,
    rank_thresholds    = NULL,
    consensus_mode     = "bracket",
    agreement_fraction = 0.9,
    bracket_width      = 1,
    bracket_fallback   = FALLBACK
  ))

  cmp <- merge(sc, deliv, by = "observation_id", all = FALSE)
  cmp$run <- run
  cat("ESVs compared (present in both files):", nrow(cmp), "\n")

  # --- Headline: finest resolved rank + name -----------------------------------
  same_taxon <- (is.na(cmp$consensus_taxon) & is.na(cmp$jv_taxon)) |
    (!is.na(cmp$consensus_taxon) & !is.na(cmp$jv_taxon) &
      cmp$consensus_taxon == cmp$jv_taxon)
  same_rank <- (is.na(cmp$consensus_rank) & is.na(cmp$jv_rank)) |
    (!is.na(cmp$consensus_rank) & !is.na(cmp$jv_rank) &
      cmp$consensus_rank == cmp$jv_rank)
  cmp$exact <- same_taxon & same_rank

  cat("\n-- Finest-rank agreement --\n")
  cat(sprintf(
    "exact (same rank AND same name): %d / %d = %.4f\n",
    sum(cmp$exact), nrow(cmp), mean(cmp$exact)
  ))
  cat(sprintf("same name (any rank):            %.4f\n", mean(same_taxon)))
  cat(sprintf("same rank (any name):            %.4f\n", mean(same_rank)))

  # --- Per-rank agreement ------------------------------------------------------
  pr <- per_rank_labels(hits)
  prm <- merge(pr, deliv, by = "observation_id", all = FALSE)
  cat("\n-- Per-rank agreement (NA == NA counts as agreement) --\n")
  for (rk in RANKS) {
    ours <- prm[[rk]]
    theirs <- prm[[paste0("jv_", rk)]]
    agree <- (is.na(ours) & is.na(theirs)) |
      (!is.na(ours) & !is.na(theirs) & ours == theirs)
    cat(sprintf(
      "  %-8s %.4f   (ours NA: %5d, theirs NA: %5d, both named & differ: %4d)\n",
      rk, mean(agree), sum(is.na(ours)), sum(is.na(theirs)),
      sum(!is.na(ours) & !is.na(theirs) & ours != theirs)
    ))
  }

  # --- Characterise the residual ----------------------------------------------
  bad <- cmp[!cmp$exact, ]
  cat("\n-- Residual disagreement:", nrow(bad), "ESVs --\n")
  ridx <- function(x) match(x, RANKS)
  dir <- ifelse(is.na(bad$consensus_rank) & !is.na(bad$jv_rank), "we resolve nothing, JV does",
    ifelse(!is.na(bad$consensus_rank) & is.na(bad$jv_rank), "we resolve, JV resolves nothing",
      ifelse(ridx(bad$consensus_rank) > ridx(bad$jv_rank), "we are FINER than JV",
        ifelse(ridx(bad$consensus_rank) < ridx(bad$jv_rank), "we are COARSER than JV",
          "same rank, different name"
        )
      )
    )
  )
  print(sort(table(dir), decreasing = TRUE))

  cat("\n  by JV's own '# species' count (their ambiguity flag):\n")
  print(table(`# species` = pmin(bad$jv_n_species, 5), useNA = "ifany"))

  cat("\n  example disagreements:\n")
  show <- utils::head(bad[order(bad$observation_id), c(
    "observation_id", "top_score", "n_retained", "n_taxa",
    "consensus_rank", "consensus_taxon", "agreement_achieved",
    "jv_rank", "jv_taxon", "jv_n_species"
  )], 15)
  print(show, row.names = FALSE)

  # --- Sensitivity: how many rows would a bracket-fallback-free run change? ----
  sc_nofb <- suppressMessages(score_consensus(
    hits,
    min_score = 0, score_col = "score_original", rank_system = RANKS,
    rank_thresholds = NULL, consensus_mode = "bracket",
    agreement_fraction = 0.9, bracket_width = 1, bracket_fallback = NULL
  ))
  fb_fired <- sum(sc$consensus_reason == "bracket_widened", na.rm = TRUE) +
    sum(sc$bracket_width_used == FALLBACK$width, na.rm = TRUE) -
    sum(sc$consensus_reason == "bracket_widened" & sc$bracket_width_used == FALLBACK$width,
      na.rm = TRUE
    )
  changed_by_fb <- sum(!identical(sc$consensus_taxon, sc_nofb$consensus_taxon) &
    (sc$consensus_taxon != sc_nofb$consensus_taxon |
      xor(is.na(sc$consensus_taxon), is.na(sc_nofb$consensus_taxon))), na.rm = TRUE)
  cat("\n-- Fallback --\n")
  cat(
    "  ESVs where the 2% fallback ran:", fb_fired,
    "| ESVs whose call it changed:", changed_by_fb, "\n"
  )

  # --- Sensitivity: half-open vs closed bracket lower bound --------------------
  sc_closed <- suppressMessages(score_consensus(
    hits,
    min_score = 0, score_col = "score_original", rank_system = RANKS,
    rank_thresholds = NULL, consensus_mode = "bracket",
    agreement_fraction = 0.9, bracket_width = 1 + 1e-6, bracket_fallback = FALLBACK
  ))
  diff_bound <- sum(xor(is.na(sc$consensus_taxon), is.na(sc_closed$consensus_taxon)) |
    (!is.na(sc$consensus_taxon) & !is.na(sc_closed$consensus_taxon) &
      sc$consensus_taxon != sc_closed$consensus_taxon))
  cat("-- Bracket lower bound --\n")
  cat(
    "  ESVs whose call differs between (top-1, top] and [top-1, top]:",
    diff_bound, "\n"
  )

  # --- Sensitivity: what strict unanimity would have said ----------------------
  sc_strict <- suppressMessages(score_consensus(
    hits,
    min_score = 0, score_col = "score_original", rank_system = RANKS,
    rank_thresholds = NULL, consensus_mode = "bracket",
    agreement_fraction = 1, bracket_width = 1, bracket_fallback = FALLBACK
  ))
  strict_exact <- (is.na(sc_strict$consensus_taxon) & is.na(deliv$jv_taxon[
    match(sc_strict$observation_id, deliv$observation_id)
  ])) |
    (sc_strict$consensus_taxon == deliv$jv_taxon[
      match(sc_strict$observation_id, deliv$observation_id)
    ])
  cat("-- Agreement fraction --\n")
  cat(sprintf(
    "  same-name rate at agreement_fraction = 0.90: %.4f\n", mean(same_taxon)
  ))
  cat(sprintf(
    "  same-name rate at agreement_fraction = 1.00: %.4f  (strict unanimity)\n",
    mean(strict_exact, na.rm = TRUE)
  ))
  cat(sprintf(
    "  species-level calls, 0.90 vs 1.00: %d vs %d\n",
    sum(sc$consensus_rank == "species", na.rm = TRUE),
    sum(sc_strict$consensus_rank == "species", na.rm = TRUE)
  ))

  all_cmp[[run]] <- cmp
}

# ------------------------------------------------------------------------------
pooled <- do.call(rbind, lapply(all_cmp, function(x) x[, c("run", "exact")]))
cat("\n", strrep("=", 78), "\nPOOLED\n", strrep("=", 78), "\n", sep = "")
cat(sprintf(
  "exact finest-rank agreement across both runs: %d / %d = %.4f\n",
  sum(pooled$exact), nrow(pooled), mean(pooled$exact)
))

saveRDS(all_cmp, "diagnostics/jv_bracket_consensus_validation_result.rds")
cat("\nwrote diagnostics/jv_bracket_consensus_validation_result.rds\n")
