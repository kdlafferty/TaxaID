# slash_taxon.R
# TaxaAssign package
#
# Appends slash-taxon notation and irreducibility flag to a consensus dataframe.
#
# Exported functions:
#   add_slash_taxon()   Add slash_taxon_name + irreducible_consensus columns
#
# Internal helpers:
#   .make_slash_name()  Build slash string from a sorted, deduplicated taxa vector


# ==============================================================================
# Internal helper
# ==============================================================================

# .make_slash_name ---------------------------------------------------------
# Build a slash-species string from a sorted, deduplicated character vector of
# binomial names (length >= 2).
#
# Same-genus:  "Homo sapiens/heidelbergensis"
# Mixed-genus: "Bos javanicus/primigenius + Bison bonasus"
#
# Names are split on the first space; everything after the first space is
# treated as the specific epithet (handles hybrids like
# "Bos grunniens x Bos taurus" — epithet becomes "grunniens x Bos taurus").
#
# @noRd
.make_slash_name <- function(taxa_vec) {
  first_space <- regexpr(" ", taxa_vec, fixed = TRUE)
  has_space   <- first_space > 0L

  genera   <- ifelse(has_space, substr(taxa_vec, 1L, first_space - 1L), taxa_vec)
  epithets <- ifelse(has_space,
                     substr(taxa_vec, first_space + 1L, nchar(taxa_vec)),
                     taxa_vec)

  unique_genera <- unique(genera)

  if (length(unique_genera) == 1L) {
    paste0(unique_genera, " ", paste(epithets, collapse = "/"))
  } else {
    genus_strings <- vapply(unique_genera, function(g) {
      eps <- epithets[genera == g]
      if (length(eps) == 1L) paste(g, eps) else paste0(g, " ", paste(eps, collapse = "/"))
    }, character(1L))
    paste(genus_strings, collapse = " + ")
  }
}


# ==============================================================================
# Exported function
# ==============================================================================

#' Add Slash Taxon Name and Irreducibility Flag to a Consensus Dataframe
#'
#' Appends two columns to the output of [posterior_consensus()]:
#'
#' * **`slash_taxon_name`** — a compact human-readable label for the plausible
#'   candidate set, following ornithological slash-species convention.
#'   Same-genus candidates are abbreviated (`Homo sapiens/heidelbergensis`);
#'   mixed-genus candidates are grouped by genus and joined with ` + `
#'   (`Bos javanicus/primigenius + Bison bonasus`). `NA` for singletons and
#'   unresolved observations.
#'
#' * **`irreducible_consensus`** — logical. `TRUE` when the candidate set for
#'   this observation cannot be further decomposed by reference to any other
#'   observation in the dataframe. A set is irreducible when no other
#'   (distinct) set in the data is the same size or smaller *and* shares at
#'   least one taxon. Singletons are always `TRUE` (a single species is
#'   trivially irreducible). Unresolved observations (empty candidate set) are
#'   always `FALSE`. Multi-taxon sets are `TRUE` when the marker/model cannot
#'   distinguish the candidates anywhere else in the dataset — i.e., the slash
#'   taxon is a genuine reporting unit, not a locally ambiguous observation that
#'   is resolved elsewhere.
#'
#' The irreducibility check operates on the full set of unique candidate
#' combinations present in `consensus_df`. Candidate sets are sorted and
#' deduplicated before comparison, so order differences in `plausible_taxa`
#' across rows do not affect the result. This matters because candidate order
#' is POSTERIOR order (it is what `primary_taxon` reads), so one biological
#' unit legitimately arrives in different orders on different observations.
#' Irreducibility is a property of the SET, not of the ranking within it.
#' Enforced and regression-tested since 2026-09-04; before that the signature
#' was built from the unsorted vector, so two orderings of one set each marked
#' the other reducible and every row of the unit went `FALSE`.
#'
#' @param consensus_df Dataframe. Output of [posterior_consensus()]. Must
#'   contain a list column of character vectors giving the plausible candidate
#'   taxa per observation (see `taxa_col`).
#' @param taxa_col Character. Name of the list column containing per-observation
#'   plausible taxa vectors. Default `"plausible_taxa"`.
#' @param posteriors_col Character. Name of the list column containing
#'   per-observation posterior probability vectors, positionally aligned with
#'   `taxa_col` (e.g., `"plausible_posteriors"` from [posterior_consensus()]).
#'   When present, candidates within each slash name are ordered by descending
#'   posterior (most probable first). When `NULL` or absent from `consensus_df`,
#'   candidates are ordered alphabetically. Default `"plausible_posteriors"`.
#'
#' @return `consensus_df` with additional columns appended:
#'   `slash_taxon_name` (character) and `irreducible_consensus` (logical).
#'   When `consensus_df` has a `consensus_taxon` column, two more columns are
#'   added:
#'   \describe{
#'     \item{`consensus_OTU`}{Single reporting label per observation —
#'       `slash_taxon_name` when non-`NA`, otherwise `consensus_taxon`. Use
#'       this as the one column with a non-`NA` label for every resolved
#'       observation.}
#'     \item{`primary_taxon`}{`consensus_OTU` reduced to a single taxon name
#'       by dropping everything from the first `/` or ` + ` onward — the
#'       single most-reportable name when a slash/plus label is not wanted
#'       (e.g. simple species tallies). For a slash set, this is whichever
#'       candidate `.make_slash_name()` placed first (highest posterior when
#'       `posteriors_col` is available, else alphabetical) — a convenience
#'       label, not a statistically preferred pick.}
#'   }
#'
#' @note **Non-binomial names in `plausible_taxa`:** Entries that are not a
#'   two-word binomial (e.g. `"Thunnus aff."`, a bare genus like `"Perca"`)
#'   can corrupt slash-name formatting. Two distinct, legitimate causes
#'   produce this, not just one: (1) GBIF occurrence records returned when
#'   querying at genus or family rank -- prevent by passing
#'   `require_species = TRUE` to [TaxaFetch::filter_gbif_quality()] before
#'   occurrence data enters the pipeline; and (2) genuine genus-level
#'   fallback hypotheses from the sequence/BLAST pathway (e.g.
#'   `hypothesis_type == "unreferenced_genus"`, or a
#'   `TaxaMatch::convert_taxonomy_backbone()` fallback to a bare genus when no
#'   species-level match exists) -- this is expected, intended behavior for
#'   real production data with a genuinely thin reference database, not a
#'   data-quality problem to fix upstream (found 2026-09-05 on real
#'   GreatLakes/PtConception 12S data: warnings fired on real genus-only
#'   candidates like `"Perca"`/`"Ictalurus"`/`"Fundulus"` with no GBIF
#'   involvement at all). This warning cannot distinguish the two causes --
#'   use `TaxaTools::is_plausible_binomial()` directly, cross-referenced
#'   against each flagged name's `hypothesis_type`, to tell them apart.
#'
#' @examples
#' posterior_df <- data.frame(
#'   observation_id  = c("S1", "S1", "S2"),
#'   taxon_name      = c("Homo sapiens", "Homo heidelbergensis", "Bos taurus"),
#'   taxon_name_rank = "species",
#'   hypothesis_type = "specific_candidate",
#'   genus           = c("Homo", "Homo", "Bos"),
#'   family          = c("Hominidae", "Hominidae", "Bovidae"),
#'   posterior_mean  = c(0.55, 0.45, 1.0),
#'   posterior_point_est = c(0.55, 0.45, 1.0)
#' )
#' consensus <- posterior_consensus(posterior_df, min_posterior = 0)
#' consensus <- add_slash_taxon(consensus)
#' consensus[, c("observation_id", "slash_taxon_name", "irreducible_consensus")]
#'
#' # All reportable observations: singletons + irreducible slash taxa
#' reportable <- consensus[consensus$irreducible_consensus %in% TRUE, ]
#'
#' @export
add_slash_taxon <- function(consensus_df,
                           taxa_col       = "plausible_taxa",
                           posteriors_col = "plausible_posteriors") {

  if (!taxa_col %in% names(consensus_df))
    cli::cli_abort("Column {.field {taxa_col}} not found in {.arg consensus_df}.")

  raw_sets <- consensus_df[[taxa_col]]

  # Defensive runtime check for the @note's documented failure mode:
  # non-binomial entries ("Thunnus aff.", "Canis sp. Russia/33500") corrupt
  # .make_slash_name()'s space-split logic. Prevention belongs upstream
  # (TaxaFetch::filter_gbif_quality(require_species = TRUE)); this only
  # makes the failure visible at the point it would actually corrupt output,
  # rather than relying solely on upstream discipline.
  if (requireNamespace("TaxaTools", quietly = TRUE)) {
    all_taxa <- unique(unlist(raw_sets, use.names = FALSE))
    all_taxa <- all_taxa[!is.na(all_taxa) & nzchar(all_taxa)]
    implausible <- all_taxa[!TaxaTools::is_plausible_binomial(all_taxa)]
    if (length(implausible) > 0L) {
      cli::cli_warn(c(
        "{length(implausible)} taxon name(s) in {.arg {taxa_col}} do not look \\
        like plausible species binomials and may corrupt slash-name \\
        formatting: {.val {utils::head(implausible, 5L)}}\\
        {if (length(implausible) > 5L) '...' else ''}",
        "i" = "See {.fn add_slash_taxon}'s documentation Note -- this can be a \\
        genuine GBIF data-quality artifact (filter upstream) OR an expected \\
        genus-level fallback hypothesis (no fix needed); check hypothesis_type \\
        to tell which."
      ))
    }
  }

  # Posterior vectors for ordering (NULL when unavailable)
  use_posteriors <- !is.null(posteriors_col) &&
                    posteriors_col %in% names(consensus_df)
  raw_posts <- if (use_posteriors) consensus_df[[posteriors_col]] else NULL

  # Normalise: deduplicate each candidate set; order by descending posterior
  # when available, otherwise alphabetically.
  taxa_sets <- lapply(seq_along(raw_sets), function(i) {
    x <- raw_sets[[i]]
    keep <- !is.na(x) & nzchar(x) & !duplicated(x)
    x <- x[keep]
    if (length(x) == 0L) return(character(0L))
    if (use_posteriors) {
      post_vec <- raw_posts[[i]]
      # posterior_consensus()'s plausible_posteriors is a NAMED vector keyed
      # by taxon name (not just positionally aligned with plausible_taxa) --
      # look up by name when available, so this is robust to the two list
      # columns ever losing positional sync (e.g. a hand-built consensus_df,
      # or any future reordering of one column without the other). Falls
      # back to positional indexing for older/hand-built input where
      # post_vec has no names.
      p <- if (!is.null(names(post_vec))) unname(post_vec[x]) else post_vec[keep]
      p[is.na(p)] <- 0
      x[order(-p)]
    } else {
      sort(x)
    }
  })
  n_taxa    <- lengths(taxa_sets)

  # --- slash_taxon_name (per-row, no dataset context needed) ----------------
  slash_names <- vapply(seq_along(taxa_sets), function(i) {
    if (n_taxa[i] <= 1L) return(NA_character_)
    .make_slash_name(taxa_sets[[i]])
  }, character(1L))

  # When species_reference downranking overrode the LCA (downranked = TRUE),
  # the plausible_taxa may belong to genera that differ from consensus_taxon
  # (e.g., BLAST returned Salmo/Salvelinus but reference downranked to
  # Oncorhynchus). In that case the slash name is a database artifact rather
  # than a genuine species-level ambiguity, so clear it to NA so that
  # downstream consensus_OTU logic falls back to consensus_taxon.
  # When the plausible genera are consistent with consensus_taxon (e.g.,
  # all candidates are Oncorhynchus and consensus is Oncorhynchus), the slash
  # name is informative and is kept.
  if ("downranked" %in% names(consensus_df) &&
      "consensus_taxon" %in% names(consensus_df)) {
    is_downranked <- !is.na(consensus_df[["downranked"]]) &
                     consensus_df[["downranked"]]
    ctaxa <- consensus_df[["consensus_taxon"]]
    for (i in which(is_downranked & !is.na(slash_names))) {
      slash_genera <- sub(" .*", "", trimws(
        strsplit(slash_names[[i]], "\\s*[+/]\\s*")[[1L]]
      ))
      if (!ctaxa[[i]] %in% slash_genera)
        slash_names[[i]] <- NA_character_
    }
  }

  # --- irreducible_consensus (dataset-level) --------------------------------
  # Unresolved rows (empty candidate set) are always FALSE — handle up front.
  is_empty <- n_taxa == 0L

  # Collapse non-empty sets to a signature string for fast dedup + lookup.
  # Separator is ASCII SOH (char 1) — never present in taxon names.
  SEP <- rawToChar(as.raw(1L))

  nonempty_sets  <- taxa_sets[!is_empty]
  # SORT before hashing. Candidate sets arrive ordered by POSTERIOR (the
  # ecosystem's deliberate convention -- it is what primary_taxon reads), so
  # one biological unit can arrive as {A,B} on one observation and {B,A} on
  # another. Hashing the unsorted vector made those two DISTINCT signatures of
  # equal size sharing a taxon, so each marked the other reducible and every
  # row of the unit went FALSE -- with no surviving irreducible instance, the
  # unit's label became an orphan that review_assignments() never scores and
  # the workflows' export filters then drop as NA. That is how a 7,453-read
  # Ctenopharyngodon idella detection (independently confirmed by Lamar in 8
  # 2023 samples) vanished from the GreatLakes output. Irreducibility is a
  # property of the SET, not of the ranking within it; sorting here asks the
  # set question and leaves the posterior order untouched everywhere else.
  # This is monotone: merging spurious duplicate signatures can only move rows
  # FALSE -> TRUE, never the reverse, so it cannot retract an existing call.
  nonempty_sigs  <- vapply(lapply(nonempty_sets, sort), paste,
                           character(1L), collapse = SEP)

  unique_sigs <- unique(nonempty_sigs)
  unique_sets <- strsplit(unique_sigs, SEP, fixed = TRUE)
  unique_n    <- lengths(unique_sets)

  irreducible_unique <- vapply(seq_along(unique_sets), function(i) {
    this_n    <- unique_n[i]
    this_taxa <- unique_sets[[i]]

    others <- seq_along(unique_sets)[-i]
    if (length(others) == 0L) return(TRUE)

    !any(vapply(others, function(j) {
      unique_n[j] <= this_n && any(this_taxa %in% unique_sets[[j]])
    }, logical(1L)))
  }, logical(1L))

  names(irreducible_unique) <- unique_sigs

  # Map back to all rows: empty sets → FALSE, others via lookup
  irreducible_vec           <- rep(FALSE, nrow(consensus_df))
  irreducible_vec[!is_empty] <- unname(irreducible_unique[nonempty_sigs])

  consensus_df[["slash_taxon_name"]]      <- slash_names
  consensus_df[["irreducible_consensus"]] <- irreducible_vec

  # --- consensus_OTU / primary_taxon (require consensus_taxon) --------------
  # Every real workflow that calls add_slash_taxon() re-derives these two
  # columns by hand (identical logic independently written 3x across
  # PtConceptionWorkflow_12S.R, PtConceptionWorkflow_18S_2.R, and
  # MuguFishWorkflow.R) -- promoted here so it is computed once, consistently.
  if ("consensus_taxon" %in% names(consensus_df)) {
    otu <- ifelse(
      is.na(consensus_df[["slash_taxon_name"]]),
      consensus_df[["consensus_taxon"]],
      consensus_df[["slash_taxon_name"]]
    )
    consensus_df[["consensus_OTU"]]   <- otu
    consensus_df[["primary_taxon"]]   <- sub("(\\s*\\+\\s*|/).*", "", otu)
  }

  consensus_df
}
