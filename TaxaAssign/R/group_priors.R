#' Aggregate occurrence-model shares to genus/family level
#'
#' Builds the lookup `posterior_consensus(group_priors = ...)` uses to compute
#' a genuinely group-level `consensus_prior` -- the SUM of `theta_mean`
#' across every locally modelled member of a genus or family, not just the
#' few candidates one observation's evidence happened to surface.
#'
#' @section Why sum, and why this needs a separate pass:
#' `theta_mean` (`TaxaExpect::prepare_model_dataframe()`'s
#' `n_species / n_total_at_site`) is a **compositional share of local
#' records** -- one record belongs to exactly one taxon, so shares are
#' mutually exclusive across taxa. That makes the group's true share the
#' *exact* sum of its members' shares, by finite additivity, with no
#' independence assumption required -- unlike a noisy-OR combination
#' (`1 - prod(1 - p_i)`), which assumes independent Bernoulli presence
#' events per taxon and is the wrong model for a compositional share.
#'
#' `posterior_consensus()` only ever sees the candidate rows hypothesized for
#' ONE observation, so it cannot compute a true group sum on its own -- a
#' genus with 13 locally modelled species might have only 2-3 of them appear
#' as candidates for any single BLAST hit. This function does the
#' aggregation once, up front, over the full `taxaexpect_priors` table, so
#' `posterior_consensus()` only needs a cheap lookup per observation.
#'
#' @section Why `"species"` is in the default `rank_cols`:
#' `posterior_consensus()`'s `group_priors` lookup is keyed on
#' `(lca$rank, lca$taxon)`, and most real consensus calls resolve at
#' \strong{species} rank -- but a species has no "group" to sum over in the
#' usual genus/family sense, it IS the row. Without a `rank == "species"`
#' entry, every species-level `consensus_taxon` finds nothing in
#' `group_priors`, and `consensus_has_occurrence_record` reads `FALSE` (not
#' `NA` -- `group_priors` was genuinely supplied, just missing this rank) for
#' the vast majority of real observations, purely from this gap -- confirmed
#' on real production data (504 of 616 real Mugu observations misread
#' "unprecedented"). `rank_cols` therefore defaults to
#' `c("species", "genus", "family", "order", "class")`; when `taxonomy_map` has no explicit
#' `"species"` column, one is auto-derived as `taxon_col`'s own values
#' (identity: a species' "group sum" is just its own `theta_col`, `n_members`
#' = 1). Supply an explicit `"species"` column in `taxonomy_map` to override
#' this (e.g. a backbone-resolved name differing from `taxon_col`), or omit
#' `"species"` from `rank_cols` to disable it entirely.
#'
#' \strong{The same gap exists at every rank the map does not cover}
#' (2026-09-14). The default stopped at `"family"`, so a consensus resolving
#' at ORDER rank found nothing, read `consensus_has_occurrence_record = FALSE`
#' and was reported `"unprecedented"` -- identically to the species-rank bug
#' above, just coarser, and for the same reason. Found on the real
#' PtConception 12S run: the `Scorpaenichthys marmoratus + Hexagrammos
#' lagocephalus/decagrammus` unit (20 observations) resolves at order rank as
#' `Perciformes`, was auto-flagged unprecedented, and
#' `TaxaFlag::review_assignments()`'s consensus-scope skepticism gate then
#' required the reviewer to rate it geographically `"unlikely"` -- which it
#' did, while its own `review_comment` called the candidates "very common at
#' Pt. Conception". The export filters then dropped all 20 rows. Cabezon and
#' kelp greenling are Point Conception natives; nothing about the science was
#' in doubt, only the rank coverage of this lookup.
#'
#' The default now reaches `"order"` and `"class"`. Ranks in the DEFAULT that
#' `taxonomy_map` does not carry are skipped with a message rather than an
#' error, so existing callers whose maps stop at family are unaffected;
#' ranks you name EXPLICITLY are still an error when absent, because you
#' asked for them.
#'
#' @param taxaexpect_priors Data frame. The full local occurrence-prior
#'   table (e.g. `TaxaExpect::generate_full_priors()`'s output, or the
#'   `taxaexpect_priors` object already used elsewhere in this ecosystem's
#'   workflows). Must contain `taxon_col` and `theta_col`.
#' @param taxonomy_map Data frame supplying genus/family for each taxon in
#'   `taxaexpect_priors` (e.g. `occurrences_clean`, which typically has real
#'   `genus`/`family` columns even when `taxaexpect_priors` itself does not).
#'   Must contain `taxon_col` and every column named in `rank_cols`.
#' @param taxon_col Character. Shared join key between the two inputs
#'   (default `"taxon_name"`).
#' @param theta_col Character. Column in `taxaexpect_priors` holding the
#'   occurrence-model share (default `"theta_mean"`).
#' @param rank_cols Character vector. Which columns in `taxonomy_map` to
#'   aggregate by (default `c("species", "genus", "family")`). See
#'   "Why `"species"` is in the default `rank_cols`" below -- `"species"` is
#'   auto-derived as `taxon_col`'s own identity when `taxonomy_map` has no
#'   explicit `"species"` column.
#'
#' @param exclude_named_evidence Logical, default `TRUE`. Drop rows that make a
#'   presence claim about a NAMED species with no local occurrence record --
#'   i.e. rows carrying a real `evidence_sources` value (`distance_clamp`,
#'   `regional_proximity`, `invasive_watch`, `inat_range`). Since curve pricing
#'   every zero-record BLAST candidate has a clamp row, so "has a row in the
#'   priors table" stopped meaning "known locally" on 2026-08-31. Measured on
#'   the PtCon 12S run of 2026-09-13: without this filter, 256 of 264
#'   winner-scope `unprecedented` rows read `expected` or `unexpected` at
#'   consensus scope, 75 of them on nothing but a clamp or evidence row (a neon
#'   tetra, a plains minnow, a red deer at a marine site), so
#'   `TaxaFlag::review_assignments()`'s skepticism gate never saw them.
#'
#'   Deliberately keyed on `evidence_sources`, NOT on `prior_branch`. The
#'   `resident_undetected` branch holds two different things: those named
#'   evidence rows (258 of 295 at PtCon 12S), and the ANONYMOUS
#'   dark-diversity mirrors (`undetected_type` `singleton_mirror`/
#'   `global_floor`, `taxon_name` `NA`, keyed by genus -- 37 rows there). A
#'   mirror exists precisely BECAUSE the group has local records, via
#'   Good-Turing on its own singletons, so it is legitimate group support and
#'   is kept. Filtering by branch would discard it: at PtCon 18S the resident
#'   rows carry no genus/family at all, so the mirrors are the dominant source
#'   of genus- and family-level group mass.
#'
#'   `FALSE` restores the pre-2026-09-13 behaviour. Ignored, with that same
#'   behaviour, when `taxaexpect_priors` has no `evidence_sources` column
#'   (GLMM-era tables, and sites that predate curve pricing).
#' @return A data frame with one row per (rank, taxon) group actually
#'   present in the data: `rank` (the `rank_cols` value, e.g. `"genus"`),
#'   `taxon` (the group's name at that rank), `theta_sum` (sum of `theta_col`
#'   across every member with a non-NA value, capped at 1 as a defensive
#'   guard against model-fit overshoot -- see `posterior_consensus()`'s
#'   `consensus_prior` docs), `n_members` (count of members contributing to
#'   the sum, i.e. locally modelled members only -- a taxon with no
#'   occurrence record does not contribute and is not counted). A group with
#'   zero locally modelled members is simply absent, not a zero row.
#'
#' @seealso [posterior_consensus()]
#'
#' @examples
#' priors <- data.frame(
#'   taxon_name = c("Aa one", "Aa two", "Bb one"),
#'   theta_mean = c(0.02, 0.05, 0.10)
#' )
#' taxonomy <- data.frame(
#'   taxon_name = c("Aa one", "Aa two", "Bb one"),
#'   genus      = c("Aa", "Aa", "Bb"),
#'   family     = c("Fam1", "Fam1", "Fam2")
#' )
#' compute_group_priors(priors, taxonomy)
#'
#' @importFrom stats aggregate
#' @importFrom dplyr bind_rows
#' @export
compute_group_priors <- function(taxaexpect_priors,
                                 taxonomy_map,
                                 taxon_col = "taxon_name",
                                 theta_col = "theta_mean",
                                 rank_cols = c(
                                   "species", "genus", "family", "order", "class"
                                 ),
                                 exclude_named_evidence = TRUE) {
  if (!is.data.frame(taxaexpect_priors)) {
    cli::cli_abort("{.arg taxaexpect_priors} must be a data frame.")
  }
  if (!is.data.frame(taxonomy_map)) {
    cli::cli_abort("{.arg taxonomy_map} must be a data frame.")
  }
  for (col in c(taxon_col, theta_col)) {
    if (!col %in% names(taxaexpect_priors)) {
      cli::cli_abort("Column {.field {col}} not found in {.arg taxaexpect_priors}.")
    }
  }
  if (!taxon_col %in% names(taxonomy_map)) {
    cli::cli_abort("Column {.field {taxon_col}} not found in {.arg taxonomy_map}.")
  }

  # "species" is a group of one: auto-derive it as taxon_col's own identity
  # when taxonomy_map has no explicit "species" column, rather than requiring
  # every caller to add that column by hand (see @section above).
  if ("species" %in% rank_cols && !"species" %in% names(taxonomy_map)) {
    taxonomy_map$species <- taxonomy_map[[taxon_col]]
  }

  # A rank the caller ASKED for and cannot be served is an error; a rank that
  # is merely part of the default and happens to be absent from this
  # taxonomy_map is not. Without this split, widening the default (2026-09-14,
  # to cover order/class) would break every existing caller whose
  # taxonomy_map stops at family -- which is most of them.
  missing_rank_cols <- setdiff(rank_cols, names(taxonomy_map))
  if (length(missing_rank_cols) > 0) {
    if (missing(rank_cols)) {
      rank_cols <- intersect(rank_cols, names(taxonomy_map))
      if (length(rank_cols) == 0L) {
        cli::cli_abort(c(
          "None of the default {.arg rank_cols} are present in {.arg taxonomy_map}.",
          "i" = "Supply {.arg rank_cols} naming columns it does have."
        ))
      }
      cli::cli_inform(c(
        "i" = "Default {.arg rank_cols} not in {.arg taxonomy_map}, skipped: \\
        {.field {missing_rank_cols}}.",
        "!" = "A consensus resolving at a skipped rank reads \\
        {.code consensus_has_occurrence_record = FALSE} and is reported \\
        {.val unprecedented}, from this gap alone -- add the column to \\
        {.arg taxonomy_map} if that rank occurs in your consensus."
      ))
    } else {
      cli::cli_abort(
        "{.arg rank_cols} not found in {.arg taxonomy_map}: {.field {missing_rank_cols}}."
      )
    }
  }

  # Named-evidence filter (2026-09-13). A row that names a species with no
  # local record must not support that species' genus/family; an anonymous
  # dark-diversity mirror, derived from the group's OWN local records, must.
  # Both sit on prior_branch == "resident_undetected", which is why this keys
  # on evidence_sources instead -- see the @param note.
  if (isTRUE(exclude_named_evidence) && "evidence_sources" %in% names(taxaexpect_priors)) {
    drop_named <- !is.na(taxaexpect_priors$evidence_sources) &
      nzchar(as.character(taxaexpect_priors$evidence_sources))
    taxaexpect_priors <- taxaexpect_priors[!drop_named, , drop = FALSE]
  } else if (!is.logical(exclude_named_evidence) || length(exclude_named_evidence) != 1L) {
    cli::cli_abort("{.arg exclude_named_evidence} must be a single TRUE or FALSE.")
  }

  priors_slim <- taxaexpect_priors[, c(taxon_col, theta_col), drop = FALSE]
  names(priors_slim) <- c("taxon_name_", "theta_")
  tax_slim <- taxonomy_map[, c(taxon_col, rank_cols), drop = FALSE]
  names(tax_slim)[1] <- "taxon_name_"

  merged <- merge(priors_slim, tax_slim, by = "taxon_name_", all.x = TRUE)
  # Only taxa with an actual occurrence-model value contribute -- a taxon
  # absent from theta_col has no local record and cannot support a group.
  merged <- merged[!is.na(merged$theta_), , drop = FALSE]

  out_list <- lapply(rank_cols, function(rc) {
    vals <- merged[[rc]]
    ok <- !is.na(vals) & nzchar(as.character(vals))
    if (!any(ok)) {
      return(data.frame(
        rank = character(0), taxon = character(0),
        theta_sum = numeric(0), n_members = integer(0)
      ))
    }
    theta_ok <- merged$theta_[ok]
    taxon_ok <- vals[ok]
    theta_sum <- stats::aggregate(theta_ok, by = list(taxon = taxon_ok), FUN = sum)
    n_members <- stats::aggregate(theta_ok, by = list(taxon = taxon_ok), FUN = length)
    data.frame(
      rank = rc,
      taxon = theta_sum$taxon,
      theta_sum = pmin(theta_sum$x, 1), # defensive cap; see @return
      n_members = n_members$x,
      stringsAsFactors = FALSE
    )
  })

  dplyr::bind_rows(out_list)
}
