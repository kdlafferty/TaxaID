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
#' across rows do not affect the result.
#'
#' @param consensus_df Dataframe. Output of [posterior_consensus()]. Must
#'   contain a list column of character vectors giving the plausible candidate
#'   taxa per observation (see `taxa_col`).
#' @param taxa_col Character. Name of the list column containing per-observation
#'   plausible taxa vectors. Default `"plausible_taxa"`.
#'
#' @return `consensus_df` with two additional columns appended:
#'   `slash_taxon_name` (character) and `irreducible_consensus` (logical).
#'
#' @note **Invalid species names upstream:** Non-binomial entries such as
#'   `"Thunnus aff."`, `"Thunnus cf."`, or `"Canis sp. Russia/33500"` can
#'   corrupt slash names. These arise from GBIF records returned when querying
#'   at genus or family rank. Prevent them by passing
#'   `require_species = TRUE` to [TaxaFetch::filter_gbif_quality()] before
#'   occurrence data enters the pipeline. Use
#'   `TaxaTools::is_plausible_binomial()` to audit candidate sets if unexpected
#'   slash names appear.
#'
#' @examples
#' \dontrun{
#' consensus <- posterior_consensus(posterior_df)
#' consensus <- add_slash_taxon(consensus)
#'
#' # All reportable observations: singletons + irreducible slash taxa
#' reportable <- consensus[consensus$irreducible_consensus %in% TRUE, ]
#' }
#'
#' @export
add_slash_taxon <- function(consensus_df, taxa_col = "plausible_taxa") {

  if (!taxa_col %in% names(consensus_df))
    stop(sprintf("Column '%s' not found in consensus_df.", taxa_col))

  raw_sets <- consensus_df[[taxa_col]]

  # Normalise: sort + deduplicate each candidate set
  taxa_sets <- lapply(raw_sets, function(x) sort(unique(x[nzchar(x) & !is.na(x)])))
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
  nonempty_sigs  <- vapply(nonempty_sets, paste, character(1L), collapse = SEP)

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

  consensus_df
}
