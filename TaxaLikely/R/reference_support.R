# ==============================================================================
# reference_support.R
# TaxaLikely -- How much reference data stood behind a call
#
# Exported functions:
#   annotate_reference_support()   -- post-hoc annotation from a trained model
# ==============================================================================


#' Annotate Calls With How Much Reference Data Stood Behind Them
#'
#' @description
#' Appends four information-only columns reporting how much per-species
#' reference data the trained likelihood model had for each row's taxon:
#' the number of training observations behind that species' fitted mean, the
#' empirical-Bayes weight those observations earned, which of six situations
#' the row is in, and whether the count is at the model's ceiling. The
#' annotation is a lookup into the model that already scored the data, so it
#' needs no re-evaluation and can be applied to results produced earlier.
#'
#' Nothing in TaxaID reads these columns. They do not gate, filter, re-rank
#' or alter a call, there is no threshold on them anywhere, and
#' \code{\link{evaluate_likelihoods}} has already accounted for a thin
#' reference set by shrinking that species' mean toward the global mean --
#' which is what \code{<prefix>_reference_weight} reports. The columns say
#' what the model had to work with, not how good the answer is.
#'
#' \strong{A low count does not imply the call is wrong.} Thin and correct is
#' an ordinary combination: a species may be genuinely under-sequenced in
#' public databases and still be the only plausible match for a query that
#' hits it at full identity. Nor does a high count imply a call is right -- a
#' well-sequenced species can be the wrong answer when the true source is a
#' congener nobody has sequenced at all. Use these columns to ask "how much
#' did the model know here?", never as evidence for or against a particular
#' call.
#'
#' \strong{\code{NA} is not one situation but five, and one of them means
#' thinner, not better.} Always read \code{<prefix>_reference_basis} rather
#' than treating missingness as a single state. In particular
#' \code{"no_model_row"} means the taxon has no per-species row in the model
#' at all, which happens when it contributed fewer training observations than
#' the model's minimum -- typically a single reference sequence. Those taxa
#' have \emph{less} reference support than any row carrying a number, so
#' reading their \code{NA} as "not thin" inverts the truth.
#'
#' @param x Data frame of calls or hypotheses, one row per thing to annotate.
#'   Anything with a taxon-name column works, including a
#'   \code{TaxaAssign::posterior_consensus()} output, a per-observation
#'   posterior table, or an \code{\link{evaluate_likelihoods}}
#'   \code{$likelihoods} frame.
#' @param model A \code{taxa_model_params} object from
#'   \code{\link{train_likelihood_model}} -- the model that actually scored
#'   \code{x} -- or, when \code{platform_col} is given, a named list of such
#'   models whose names are the platform values appearing in that column.
#'   Any list carrying a conforming \code{H1_Lookup} is accepted, so a model
#'   restored from a cache that lost its class attribute still works.
#' @param taxon_col Character. Column in \code{x} holding the taxon name to
#'   look up (default \code{"consensus_taxon"}). For a consensus table this
#'   is the published call; for a hypothesis table, the hypothesis.
#' @param rank_col Character or \code{NULL}. Column holding that taxon's rank
#'   (default \code{"consensus_rank"}). Rows whose rank is not one the model
#'   fits per-species rows at get \code{"rank_not_in_model"} without a name
#'   lookup, which is what separates a genus-level or rank-ring call from a
#'   species the model simply never saw. \code{NULL}, or a column absent from
#'   \code{x}, skips the rank check and relies on the name lookup alone.
#' @param hypothesis_type_col Character or \code{NULL} (default). Column
#'   holding \code{hypothesis_type}. Any value beginning
#'   \code{"unreferenced_"} -- \code{"unreferenced_species"} and its
#'   genus, family, order and class counterparts -- is a hypothesis about
#'   something that is \strong{not} in the reference set, so it has no
#'   reference sequences by construction and gets
#'   \code{"unreferenced_hypothesis"}. Every other value, including
#'   \code{"suppressed_candidate"}, is looked up normally. \strong{Supply
#'   this whenever the data has it.} Most unreferenced-species hypotheses
#'   carry a real binomial at species rank, and without this column they
#'   match no lookup key and are reported as \code{"no_model_row"} -- which
#'   says "too thin for its own row" about a taxon that was never expected to
#'   have one. For a consensus table, which has no \code{hypothesis_type} of
#'   its own, join it from the hypothesis the consensus node came from.
#' @param platform_col Character or \code{NULL} (default). Column naming
#'   which sequencing platform's model scored each row. Supply it with a
#'   named list of models whenever a marker was trained per platform;
#'   omitting it when the models differ silently reports one platform's
#'   numbers for all of them.
#' @param lineage_cols Character vector or \code{NULL} (default). Lineage
#'   columns in \code{x}, \strong{finest rank first}, used to reproduce the
#'   ancestor fallback \code{\link{evaluate_likelihoods}} applies when a
#'   candidate name is not itself a lookup key: the first ancestor name that
#'   is a key supplies the parameters, and the row is marked
#'   \code{"model_row_via_lineage"} so it is never mistaken for a direct
#'   species match. \code{NULL} disables the fallback, which under-reports
#'   support for exactly those rows.
#' @param prefix Character. Prefix for the four new column names (default
#'   \code{"winner"}). Annotate two taxon columns of the same table by
#'   calling twice with different prefixes.
#'
#' @return \code{x} with four columns added, named for \code{prefix}:
#' \describe{
#'   \item{\code{<prefix>_n_references}}{Integer. The number of per-species
#'     training observations the model fitted this taxon's mean from
#'     (\code{H1_Lookup$n_obs_species}), or \code{NA} when no per-species row
#'     applies. What one observation counts depends on the
#'     \code{pair_retention} policy used by
#'     \code{\link{build_sequence_matrix}}: one per reference sequence under
#'     \code{"best_per_partner"} or \code{"best_per_class"}, one per
#'     reference PAIR under \code{"all"}. A trained model does not record
#'     which policy built its matrix, so this function cannot state the unit
#'     and neither should a reader who does not know the build.}
#'   \item{\code{<prefix>_reference_weight}}{Numeric in (0, 1). The
#'     empirical-Bayes weight the model gave this species' own mean
#'     (\code{H1_Lookup$shrink_w_score}); the remainder went to the global
#'     mean. Within one model this is a monotone function of the count and
#'     carries no extra per-row information -- its value is that it is
#'     comparable ACROSS markers and models, which a raw count is not,
#'     because it measures the count against that model's own fitted
#'     between-species and within-species variance.}
#'   \item{\code{<prefix>_reference_basis}}{Character, one of
#'     \code{"model_species_row"} (a direct name match: the count is this
#'     taxon's own), \code{"model_row_via_lineage"} (an ancestor's row
#'     supplied the parameters, so the count is the ANCESTOR's, not this
#'     taxon's), \code{"no_model_row"} (the rank is one the model fits but
#'     this name has no row: fewer observations than the model's minimum,
#'     typically one reference sequence, scored against the global mean --
#'     thinner than any reported count), \code{"rank_not_in_model"} (the row
#'     is coarser than the model's per-species rank, as a genus-level call or
#'     a rank-ring hypothesis is, so no per-species count applies),
#'     \code{"unreferenced_hypothesis"} (a hypothesis about a taxon absent
#'     from the reference set, which has no reference sequences by
#'     construction -- distinct from \code{"no_model_row"}, which is about a
#'     taxon that IS in the reference set but too thinly for its own row), or
#'     \code{"no_taxon"} (the taxon name is \code{NA}).}
#'   \item{\code{<prefix>_at_model_max}}{Logical. \code{TRUE} when the count
#'     equals the largest count anywhere in this model's \code{H1_Lookup}.
#'     When the matrix was built with \code{build_sequence_matrix(}
#'     \code{max_seqs_per_taxon = )}, that maximum IS the cap and these rows
#'     are censored: the count means "this many or more", the true totals are
#'     unknown, and the difference between two such rows is not evidence
#'     about either. The share at the maximum can be large, so this is not a
#'     corner case. With no cap in the build, the column instead just marks
#'     the best-referenced species, and nothing is censored -- which of the
#'     two applies is a fact about the caller's build that a trained model
#'     does not record. \code{NA} where the count is \code{NA}.}
#' }
#'
#' @seealso \code{\link{train_likelihood_model}} for where
#'   \code{n_obs_species} and the shrinkage weight come from,
#'   \code{\link{evaluate_likelihoods}} for the lookup and ancestor fallback
#'   this function reproduces, and \code{\link{interpret_model}} for the same
#'   quantities summarised over a whole model rather than per call.
#'
#' @examples
#' model <- structure(
#'   list(H1_Lookup = data.frame(
#'     lookup_key = c("Girella nigricans", "Sarda chiliensis"),
#'     rank = "species",
#'     n_obs_species = c(3L, 12L),
#'     shrink_w_score = c(0.72, 0.91),
#'     stringsAsFactors = FALSE
#'   )),
#'   class = "taxa_model_params"
#' )
#' calls <- data.frame(
#'   consensus_taxon = c("Girella nigricans", "Sarda chiliensis", "Mytilus"),
#'   consensus_rank  = c("species", "species", "genus"),
#'   stringsAsFactors = FALSE
#' )
#' annotate_reference_support(calls, model)
#'
#' @export
annotate_reference_support <- function(x,
                                       model,
                                       taxon_col = "consensus_taxon",
                                       rank_col = "consensus_rank",
                                       hypothesis_type_col = NULL,
                                       platform_col = NULL,
                                       lineage_cols = NULL,
                                       prefix = "winner") {
  if (!is.data.frame(x)) {
    stop("annotate_reference_support: 'x' must be a data frame.", call. = FALSE)
  }
  .ars_check_chr1(taxon_col, "taxon_col")
  .ars_check_chr1(prefix, "prefix")
  if (!is.null(rank_col)) .ars_check_chr1(rank_col, "rank_col")
  if (!is.null(hypothesis_type_col)) {
    .ars_check_chr1(hypothesis_type_col, "hypothesis_type_col")
  }
  if (!is.null(platform_col)) .ars_check_chr1(platform_col, "platform_col")
  if (!(taxon_col %in% names(x))) {
    stop(sprintf(
      "annotate_reference_support: 'x' has no column '%s' (taxon_col).",
      taxon_col
    ), call. = FALSE)
  }
  # rank_col and hypothesis_type_col are allowed to be absent: both are
  # refinements of the lookup, not requirements for it, and a caller
  # annotating an arbitrary table should not have to manufacture either.
  # taxon_col IS required -- without it there is nothing to look up.
  if (!is.null(hypothesis_type_col) && !(hypothesis_type_col %in% names(x))) {
    hypothesis_type_col <- NULL
  }
  if (!is.null(rank_col) && !(rank_col %in% names(x))) rank_col <- NULL
  if (!is.null(lineage_cols)) {
    if (!is.character(lineage_cols)) {
      stop("annotate_reference_support: 'lineage_cols' must be character or NULL.",
        call. = FALSE
      )
    }
    missing_lin <- setdiff(lineage_cols, names(x))
    if (length(missing_lin) > 0L) {
      stop(sprintf(
        "annotate_reference_support: lineage_cols not in 'x': %s.",
        paste(missing_lin, collapse = ", ")
      ), call. = FALSE)
    }
  }

  out_cols <- paste0(prefix, c(
    "_n_references", "_reference_weight", "_reference_basis",
    "_at_model_max"
  ))
  clash <- intersect(out_cols, names(x))
  if (length(clash) > 0L) {
    stop(sprintf(paste0(
      "annotate_reference_support: 'x' already has %s. Pass a different ",
      "'prefix' rather than overwriting an existing column."
    ), paste(clash, collapse = ", ")), call. = FALSE)
  }

  models <- .ars_resolve_models(model, x, platform_col)

  n <- nrow(x)
  n_ref <- rep(NA_integer_, n)
  w_ref <- rep(NA_real_, n)
  basis <- rep(NA_character_, n)
  at_cap <- rep(NA, n)

  if (n > 0L) {
    row_groups <- if (is.null(platform_col)) {
      list(`1` = seq_len(n))
    } else {
      split(seq_len(n), as.character(x[[platform_col]]))
    }
    for (grp in names(row_groups)) {
      idx <- row_groups[[grp]]
      if (length(idx) == 0L) next
      mdl <- if (is.null(platform_col)) models[[1L]] else models[[grp]]
      res <- .ars_annotate_one(
        taxa = as.character(x[[taxon_col]][idx]),
        ranks = if (is.null(rank_col)) NULL else as.character(x[[rank_col]][idx]),
        htypes = if (is.null(hypothesis_type_col)) {
          NULL
        } else {
          as.character(x[[hypothesis_type_col]][idx])
        },
        lineage = if (is.null(lineage_cols)) {
          NULL
        } else {
          lapply(lineage_cols, function(cc) as.character(x[[cc]][idx]))
        },
        lookup = mdl$H1_Lookup
      )
      n_ref[idx] <- res$n_ref
      w_ref[idx] <- res$w_ref
      basis[idx] <- res$basis
      at_cap[idx] <- res$at_cap
    }
  }

  x[[out_cols[1L]]] <- n_ref
  x[[out_cols[2L]]] <- w_ref
  x[[out_cols[3L]]] <- basis
  x[[out_cols[4L]]] <- at_cap
  x
}


#' Validate a length-1 character argument
#' @noRd
.ars_check_chr1 <- function(value, what) {
  if (!is.character(value) || length(value) != 1L || is.na(value) ||
    !nzchar(value)) {
    stop(sprintf(
      "annotate_reference_support: '%s' must be a single non-empty string.",
      what
    ), call. = FALSE)
  }
  invisible(TRUE)
}


#' Normalise `model` to a named list of models, one per platform group
#'
#' Returns a list of length 1 when `platform_col` is NULL (the single-model
#' case), otherwise a list whose names cover every platform value present in
#' `x`. A platform value with no model is an error rather than an NA column:
#' silently reporting nothing for a whole platform is the failure mode this
#' argument exists to prevent.
#' @noRd
.ars_resolve_models <- function(model, x, platform_col) {
  if (is.null(platform_col)) {
    .ars_check_lookup(model, "model")
    return(list(model))
  }
  if (!(platform_col %in% names(x))) {
    stop(sprintf(
      "annotate_reference_support: 'x' has no column '%s' (platform_col).",
      platform_col
    ), call. = FALSE)
  }
  present <- unique(as.character(x[[platform_col]]))
  present <- present[!is.na(present)]
  if (any(is.na(x[[platform_col]]))) {
    stop(sprintf(paste0(
      "annotate_reference_support: '%s' (platform_col) has %d NA value(s). ",
      "Every row must say which platform's model scored it."
    ), platform_col, sum(is.na(x[[platform_col]]))), call. = FALSE)
  }
  # A single model with a platform column is accepted only when one platform
  # is present: that is an unambiguous pairing. Two platforms and one model
  # is the mistake worth catching.
  single <- !is.null(model$H1_Lookup)
  if (single) {
    if (length(present) > 1L) {
      stop(sprintf(paste0(
        "annotate_reference_support: 'x' spans %d platforms (%s) but 'model' ",
        "is a single model. Pass a named list of models, one per platform, ",
        "so each row is annotated from the model that scored it."
      ), length(present), paste(sort(present), collapse = ", ")), call. = FALSE)
    }
    .ars_check_lookup(model, "model")
    out <- list(model)
    names(out) <- present
    return(out)
  }
  if (!is.list(model) || is.null(names(model))) {
    stop(paste0(
      "annotate_reference_support: with 'platform_col', 'model' must be a ",
      "NAMED list of models keyed by platform."
    ), call. = FALSE)
  }
  missing_pf <- setdiff(present, names(model))
  if (length(missing_pf) > 0L) {
    stop(sprintf(paste0(
      "annotate_reference_support: no model supplied for platform(s) %s. ",
      "'model' has: %s."
    ), paste(sort(missing_pf), collapse = ", "),
    paste(sort(names(model)), collapse = ", ")), call. = FALSE)
  }
  for (pf in present) .ars_check_lookup(model[[pf]], sprintf("model[[\"%s\"]]", pf))
  model
}


#' Validate one model's H1_Lookup schema
#'
#' Accepts any list carrying a conforming `H1_Lookup` rather than requiring
#' the `taxa_model_params` class, so a model read back from a cache that
#' dropped its class attribute still annotates. The columns actually read are
#' required by name; a model trained before any of them existed fails here
#' with the column named rather than producing a silently empty annotation.
#' @noRd
.ars_check_lookup <- function(model, what) {
  if (!is.list(model) || is.null(model$H1_Lookup)) {
    stop(sprintf(paste0(
      "annotate_reference_support: '%s' must be a taxa_model_params object ",
      "(or a list carrying an H1_Lookup table) from train_likelihood_model()."
    ), what), call. = FALSE)
  }
  H <- model$H1_Lookup
  if (!is.data.frame(H)) {
    stop(sprintf("annotate_reference_support: '%s$H1_Lookup' is not a data frame.",
      what
    ), call. = FALSE)
  }
  if (nrow(H) > 0L) {
    need <- c("lookup_key", "rank", "n_obs_species", "shrink_w_score")
    absent <- setdiff(need, names(H))
    if (length(absent) > 0L) {
      stop(sprintf(paste0(
        "annotate_reference_support: '%s$H1_Lookup' has no %s column(s). ",
        "A model trained with shrinkage = \"fixed\" or by a version that ",
        "predates these columns cannot report reference support."
      ), what, paste(absent, collapse = ", ")), call. = FALSE)
    }
  }
  invisible(TRUE)
}


#' Annotate one platform group against one H1_Lookup
#'
#' Decision order matters and mirrors what the row actually means rather than
#' what the name lookup happens to return: an unreferenced hypothesis and a
#' coarser-than-species call both have no per-species row for reasons that
#' have nothing to do with the reference set, so they are settled before any
#' name is matched. Only then does a name miss mean what `"no_model_row"`
#' says it means.
#' @noRd
.ars_annotate_one <- function(taxa, ranks, htypes, lineage, lookup) {
  n <- length(taxa)
  n_ref <- rep(NA_integer_, n)
  w_ref <- rep(NA_real_, n)
  basis <- rep(NA_character_, n)
  at_cap <- rep(NA, n)
  if (n == 0L) {
    return(list(n_ref = n_ref, w_ref = w_ref, basis = basis, at_cap = at_cap))
  }

  todo <- rep(TRUE, n)

  # (1) No taxon to look up.
  no_taxon <- is.na(taxa) | !nzchar(taxa)
  basis[no_taxon] <- "no_taxon"
  todo[no_taxon] <- FALSE

  # (2) A hypothesis about something that is NOT in the reference set. Matched
  # on the `unreferenced_` prefix rather than a fixed list of values: the
  # hypothesis set runs as deep as the rank system does
  # (unreferenced_species/genus/family/order/class all occur in real output),
  # and a closed list silently mislabels whichever level it omits.
  if (!is.null(htypes)) {
    unref <- todo & !is.na(htypes) & grepl("^unreferenced_", htypes)
    basis[unref] <- "unreferenced_hypothesis"
    todo[unref] <- FALSE
  }

  # (3) A rank the model does not fit per-species rows at: genus-level calls
  # and rank-ring hypotheses land here.
  model_ranks <- if (nrow(lookup) > 0L) unique(as.character(lookup$rank)) else character(0L)
  if (!is.null(ranks) && length(model_ranks) > 0L) {
    off_rank <- todo & !is.na(ranks) & !(ranks %in% model_ranks)
    basis[off_rank] <- "rank_not_in_model"
    todo[off_rank] <- FALSE
  }

  if (nrow(lookup) == 0L) {
    basis[todo] <- "no_model_row"
    return(list(n_ref = n_ref, w_ref = w_ref, basis = basis, at_cap = at_cap))
  }

  keys <- as.character(lookup$lookup_key)
  cap <- suppressWarnings(max(lookup$n_obs_species, na.rm = TRUE))
  if (!is.finite(cap)) cap <- NA_integer_

  take <- function(rows, idx, label) {
    n_ref[rows] <<- as.integer(lookup$n_obs_species[idx])
    w_ref[rows] <<- as.numeric(lookup$shrink_w_score[idx])
    basis[rows] <<- label
    nn <- n_ref[rows]
    # NA, not FALSE, when either side is unknown: "FALSE" would assert the row
    # is below a ceiling nobody established.
    at_cap[rows] <<- ifelse(is.na(nn) | is.na(cap), NA, nn >= cap)
    todo[rows] <<- FALSE
  }

  # (4) Direct name match.
  hit <- match(ifelse(todo, taxa, NA_character_), keys)
  direct <- todo & !is.na(hit)
  if (any(direct)) take(which(direct), hit[direct], "model_species_row")

  # (5) Ancestor fallback, finest rank first -- the same walk
  # evaluate_likelihoods() does over its lineage matrix.
  if (!is.null(lineage)) {
    for (lin in lineage) {
      if (!any(todo)) break
      lh <- match(ifelse(todo, lin, NA_character_), keys)
      got <- todo & !is.na(lh)
      if (any(got)) take(which(got), lh[got], "model_row_via_lineage")
    }
  }

  # (6) The rank is one the model fits, but this name has no row.
  basis[todo] <- "no_model_row"
  list(n_ref = n_ref, w_ref = w_ref, basis = basis, at_cap = at_cap)
}
