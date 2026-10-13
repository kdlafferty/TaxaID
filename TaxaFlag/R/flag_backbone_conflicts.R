#' Flag Taxa Whose Backbone Placement Disagrees With Itself
#'
#' Asks whether a name in the taxonomy actually denotes one place in the tree.
#' Two failures are detected, both learned from the backbone present in the
#' data rather than from any list of taxa: a name carried at MORE THAN ONE
#' RANK (a clade treated as a phylum on some rows and as a lower rank inside
#' another phylum on others, or a true homonym such as a phylum name reused as
#' a genus), and a name carried under MORE THAN ONE PARENT at the same rank.
#'
#' @section What this CANNOT see:
#' Both detected failures are ONE NAME in more than one place. The inverse --
#' MANY NAMES for one organism, i.e. synonymy -- is invisible here, and not as
#' an implementation gap: a synonym pair sits consistently at one rank under
#' one parent on each of its two names, so there is no conflict to find. Where
#' a reference database holds \emph{Eisenia arborea} and an occurrence pool
#' lists \emph{Ecklonia arborea}, this function reports nothing, by
#' construction. It therefore cannot be used as evidence that a name set is
#' free of duplicate organisms, and a report of zero conflicts says nothing
#' about synonymy.
#'
#' That matters because a name absent from a reference set becomes an
#' unreferenced local species downstream, and
#' \code{TaxaAssign::add_unreferenced_prior_mass(named_rows = TRUE)} can then
#' name it in a call -- so a synonym of a referenced taxon could be reported as
#' having no reference sequence. The designed defence is the NCBI-to-GBIF
#' crosswalk, not this function. Measured on one real multi-marker study, the
#' 35 record-named taxa behind its 410 such calls produced 97 shared-epithet
#' pairs against the reference sets and EVERY one was in a different family --
#' homonymous epithets across unrelated groups rather than synonyms -- so that
#' study showed no instance of the failure. The limitation stands regardless of
#' that result.
#'
#' @section Why this is not a data-cleaning nicety:
#' Any rule that compares taxonomy by NAME is wrong wherever a name is not a
#' key. \code{TaxaAssign::posterior_consensus()}'s \code{cross_phylum_eps}
#' rule withholds a call that rests on a choice between phyla, and it compares
#' the phylum column by name; where one lineage carries two names at different
#' ranks, that comparison sees two phyla where biology has one, and no value of
#' the tolerance distinguishes the two cases. The same applies to anything that
#' groups, pools or counts by a rank column. This function does not fix the
#' taxonomy -- the fix is upstream, in making the backbone placement consistent
#' -- it tells the reader which calls stand on a name that cannot be trusted as
#' a key.
#'
#' @section What the two kinds look like:
#' On one real multi-marker study (CalIntertidal, 6.13M candidate rows,
#' 49,346 observations) 18 of 28,610 distinct names were carried at more than
#' one rank. Four of them were used as a phylum somewhere, and those four
#' touched 1,054 of the 24,739 observations whose calls the cross-phylum rule
#' can reach. The largest was a chromist class also carried as a phylum (606
#' observations), not the case that prompted the check (37). One name was a
#' textbook homonym: a phylum of comb jellies reused as a crane-fly genus.
#' Separately, 33 or more name/rank combinations sat under two parents, and
#' three of those were ONE inconsistent placement showing up at three
#' consecutive ranks, which is the argument for fixing the backbone rather
#' than each rank.
#'
#' @section Placeholders are found by the same rule, and kept visible:
#' Control and placeholder names ("PositiveControl", "None" and the like) are
#' genuinely carried at many ranks, so a detector learned from the data finds
#' them. They are reported in their own \code{category}, never silently
#' dropped: a control name occupying a phylum column is itself worth a
#' reader's attention. In the study above the placeholders sat at four and six
#' ranks while every genuine homonym sat at exactly two, which is what
#' \code{placeholder_rank_count} is set from. The FLAG does not depend on that
#' argument; only the label does.
#'
#' @param consensus Data frame of consensus calls, one row per observation,
#'   as returned by \code{TaxaAssign::posterior_consensus()} or
#'   \code{TaxaAssign::score_consensus()}. Only \code{observation_col} is
#'   required; \code{consensus_limit} and \code{consensus_rank} are used when
#'   present.
#' @param taxonomy Data frame of the candidate rows the consensus was computed
#'   from (the posterior or match table), carrying \code{observation_col} and
#'   the rank columns. This is where placement is learned: the consensus alone
#'   cannot show a disagreement.
#' @param rank_system Character vector of rank column names, coarse to fine.
#'   \code{NULL} (default) auto-detects via \code{TaxaTools::detect_ranks()},
#'   falling back to the standard ladder intersected with the columns present.
#' @param observation_col Character. Observation identifier shared by
#'   \code{consensus} and \code{taxonomy}. Default \code{"observation_id"}.
#' @param posterior_col Character or \code{NULL}. Posterior/weight column in
#'   \code{taxonomy} used for \code{backbone_conflict_mass}. \code{NULL}
#'   (default) auto-detects \code{"posterior_point_est"} then
#'   \code{"posterior_mean"}; when neither is present the mass column is
#'   \code{NA} and the flag is unaffected.
#' @param placeholder_rank_count Integer >= 2. Number of distinct ranks at
#'   which a name is labelled \code{"placeholder"} rather than
#'   \code{"cross_rank"}. Default 3: a real homonym occupies two ranks, while
#'   a control or placeholder string occupies as many as it is written into.
#'   Presentation only -- it changes \code{category}, never the flag.
#'
#' @return \code{consensus} with these columns added (existing columns of the
#'   same name are overwritten, with a warning):
#'   \describe{
#'     \item{\code{backbone_conflict}}{Logical. \code{TRUE} when any candidate
#'       row of the observation carries a conflicted name at any rank.}
#'     \item{\code{backbone_conflict_kind}}{\code{"cross_rank"},
#'       \code{"multi_parent"}, \code{"both"}, \code{"placeholder"}, or
#'       \code{NA} when not flagged. \code{"placeholder"} wins over the others.}
#'     \item{\code{backbone_conflict_names}}{Semicolon-separated conflicted
#'       names found in the observation, or \code{NA}.}
#'     \item{\code{backbone_conflict_mass}}{Share of the observation's
#'       candidate mass sitting on rows that carry a conflicted name, or
#'       \code{NA} when no posterior column is available. A small share is a
#'       weaker concern than a large one.}
#'     \item{\code{cross_phylum_conflicted}}{Logical or \code{NA}. For rows
#'       whose \code{consensus_limit} is \code{"cross_phylum"}, whether the
#'       withholding involves a name that is ALSO used as a phylum elsewhere
#'       in \code{taxonomy} -- i.e. whether the phyla the rule compared may be
#'       two names for one lineage. \code{NA} where
#'       \code{consensus_limit} is absent or not \code{"cross_phylum"}.}
#'   }
#'   The conflict table itself is attached as attribute
#'   \code{"backbone_conflicts"}: one row per conflicted name with
#'   \code{name}, \code{kind}, \code{category}, \code{n_ranks},
#'   \code{ranks}, \code{parents}, \code{candidate_rows} and
#'   \code{observations}. Attribute \code{"backbone_conflict_params"} records
#'   the arguments used. Both survive row subsetting and are dropped by
#'   column subsetting (\code{d[, cols]}), \code{merge()} and
#'   \code{dplyr::summarise()}.
#'
#' @seealso \code{TaxaTools::find_taxonomy_conflicts()}, which this function
#'   calls for the same-rank case and does not reimplement;
#'   \code{TaxaAssign::posterior_consensus()} for \code{cross_phylum_eps} and
#'   its \code{lineage_conflict} column, which reports the same-rank case
#'   WITHIN one observation while this function learns placement across the
#'   whole table.
#' @export
flag_backbone_conflicts <- function(consensus,
                                    taxonomy,
                                    rank_system = NULL,
                                    observation_col = "observation_id",
                                    posterior_col = NULL,
                                    placeholder_rank_count = 3L) {
  if (!is.data.frame(consensus)) stop("flag_backbone_conflicts: consensus must be a data frame", call. = FALSE)
  if (!is.data.frame(taxonomy)) stop("flag_backbone_conflicts: taxonomy must be a data frame", call. = FALSE)
  if (!observation_col %in% names(consensus))
    stop("flag_backbone_conflicts: consensus has no column '", observation_col, "'", call. = FALSE)
  if (!observation_col %in% names(taxonomy))
    stop("flag_backbone_conflicts: taxonomy has no column '", observation_col, "'", call. = FALSE)
  if (!is.numeric(placeholder_rank_count) || length(placeholder_rank_count) != 1L ||
      is.na(placeholder_rank_count) || placeholder_rank_count < 2)
    stop("flag_backbone_conflicts: placeholder_rank_count must be a single number >= 2", call. = FALSE)

  ranks <- .bc_rank_system(taxonomy, rank_system)
  if (length(ranks) < 2L)
    stop("flag_backbone_conflicts: fewer than two rank columns found in taxonomy; ",
         "pass rank_system explicitly", call. = FALSE)

  # ---- (1) names carried at more than one RANK -------------------------------
  per_rank <- lapply(ranks, function(r) {
    v <- as.character(taxonomy[[r]])
    unique(v[!is.na(v) & nzchar(v)])
  })
  names(per_rank) <- ranks
  all_names <- unlist(per_rank, use.names = FALSE)
  owner <- rep(ranks, lengths(per_rank))
  n_rank_of <- table(all_names)
  cross_rank <- names(n_rank_of)[n_rank_of > 1L]
  rank_sets <- if (length(cross_rank)) {
    keep <- all_names %in% cross_rank
    vapply(split(owner[keep], all_names[keep]),
           function(x) paste(sort(unique(x)), collapse = "+"), character(1))
  } else character(0)

  # ---- (2) names under more than one PARENT at the same rank -----------------
  # Delegated: TaxaTools::find_taxonomy_conflicts() already does exactly this,
  # comparing each name against EVERY coarser rank, not just its parent.
  mp <- .bc_multi_parent(taxonomy, ranks)

  conflicted <- union(cross_rank, mp$name)
  params <- list(rank_system = ranks, observation_col = observation_col,
                 placeholder_rank_count = as.integer(placeholder_rank_count),
                 n_cross_rank = length(cross_rank), n_multi_parent = nrow(mp))

  if (!length(conflicted)) {
    out <- .bc_empty_columns(consensus)
    attr(out, "backbone_conflicts") <- .bc_empty_table()
    attr(out, "backbone_conflict_params") <- params
    return(out)
  }

  # ---- per-row hits, and per-observation rollup ------------------------------
  hit_rank <- lapply(ranks, function(r) {
    v <- as.character(taxonomy[[r]])
    !is.na(v) & v %in% conflicted
  })
  any_hit <- Reduce(`|`, hit_rank)
  # which conflicted name(s) each hit row carries
  row_names_hit <- rep(NA_character_, nrow(taxonomy))
  if (any(any_hit)) {
    idx <- which(any_hit)
    collected <- lapply(seq_along(ranks), function(i) {
      v <- as.character(taxonomy[[ranks[i]]])[idx]
      ifelse(hit_rank[[i]][idx], v, NA_character_)
    })
    m <- do.call(cbind, collected)
    # A row's label depends only on its own tuple of conflicted names, and the
    # distinct tuples are far fewer than the rows, so each is resolved once and
    # joined back. This replaces a per-row apply() over the whole frame; rows
    # that carry no conflicted name keep the NA they were initialised with,
    # which is what the per-row call returned for them.
    key <- do.call(paste, c(as.data.frame(m, stringsAsFactors = FALSE), sep = "\r"))
    uk <- unique(key)
    um <- m[match(uk, key), , drop = FALSE]
    vals <- vapply(seq_len(nrow(um)), function(j) {
      x <- unique(um[j, ][!is.na(um[j, ])])
      if (!length(x)) NA_character_ else paste(sort(x), collapse = "; ")
    }, character(1))
    row_names_hit[idx] <- vals[match(key, uk)]
  }

  obs <- as.character(taxonomy[[observation_col]])
  pcol <- .bc_posterior_col(taxonomy, posterior_col)
  w <- if (is.null(pcol)) NULL else suppressWarnings(as.numeric(taxonomy[[pcol]]))

  flagged_obs <- unique(obs[any_hit])
  names_by_obs <- if (length(flagged_obs)) {
    tapply(row_names_hit[any_hit], obs[any_hit], function(x) {
      x <- unlist(strsplit(x[!is.na(x)], "; ", fixed = TRUE))
      paste(sort(unique(x)), collapse = "; ")
    })
  } else character(0)
  mass_by_obs <- if (is.null(w)) NULL else {
    num <- tapply(ifelse(any_hit, w, 0), obs, sum, na.rm = TRUE)
    den <- tapply(w, obs, sum, na.rm = TRUE)
    ifelse(is.finite(den) & den > 0, num / den, NA_real_)
  }

  # ---- the conflict table ----------------------------------------------------
  rows_of <- vapply(conflicted, function(n) {
    sum(vapply(ranks, function(r) {
      v <- as.character(taxonomy[[r]]); sum(!is.na(v) & v == n)
    }, integer(1)))
  }, integer(1))
  obs_of <- vapply(conflicted, function(n) {
    keep <- Reduce(`|`, lapply(ranks, function(r) {
      v <- as.character(taxonomy[[r]]); !is.na(v) & v == n
    }))
    length(unique(obs[keep]))
  }, integer(1))
  n_ranks <- as.integer(ifelse(conflicted %in% names(rank_sets),
                               lengths(strsplit(rank_sets[conflicted], "+", fixed = TRUE)), 1L))
  kind <- ifelse(conflicted %in% cross_rank & conflicted %in% mp$name, "both",
          ifelse(conflicted %in% cross_rank, "cross_rank", "multi_parent"))
  category <- ifelse(n_ranks >= placeholder_rank_count, "placeholder", kind)
  tab <- data.frame(
    name = conflicted, kind = kind, category = category, n_ranks = n_ranks,
    ranks = unname(ifelse(conflicted %in% names(rank_sets), rank_sets[conflicted], NA_character_)),
    parents = vapply(conflicted, function(n) {
      p <- mp$parents[mp$name == n]
      if (!length(p)) NA_character_ else paste(unique(p), collapse = " | ")
    }, character(1)),
    candidate_rows = unname(rows_of), observations = unname(obs_of),
    stringsAsFactors = FALSE
  )
  tab <- tab[order(-tab$observations, -tab$candidate_rows, tab$name), , drop = FALSE]
  rownames(tab) <- NULL

  # ---- attach to the consensus ----------------------------------------------
  out <- .bc_empty_columns(consensus)
  cid <- as.character(out[[observation_col]])
  m <- match(cid, flagged_obs)
  out$backbone_conflict <- !is.na(m)
  out$backbone_conflict_names <- unname(ifelse(is.na(m), NA_character_, names_by_obs[cid]))
  if (!is.null(mass_by_obs)) out$backbone_conflict_mass <- unname(mass_by_obs[cid])
  # kind per observation: placeholder wins, then both, then the single kinds
  kind_of <- stats::setNames(tab$category, tab$name)
  rank_order <- c(placeholder = 1L, both = 2L, cross_rank = 3L, multi_parent = 4L)
  out$backbone_conflict_kind <- vapply(seq_len(nrow(out)), function(i) {
    if (is.na(out$backbone_conflict_names[i])) return(NA_character_)
    k <- kind_of[unlist(strsplit(out$backbone_conflict_names[i], "; ", fixed = TRUE))]
    k <- k[!is.na(k)]
    if (!length(k)) NA_character_ else names(sort(rank_order[unique(k)]))[1L]
  }, character(1))

  # ---- did a cross_phylum withholding stand on a name used as a phylum? -----
  if ("consensus_limit" %in% names(out)) {
    phylum_col <- ranks[[1L]]
    pv <- as.character(taxonomy[[phylum_col]])
    # conflicted names that are ALSO used as a phylum somewhere
    as_phylum <- intersect(conflicted, unique(pv[!is.na(pv)]))
    if (length(as_phylum)) {
      ph_obs <- unique(obs[!is.na(pv) & pv %in% as_phylum])
      is_cp <- out$consensus_limit %in% "cross_phylum"
      out$cross_phylum_conflicted <- ifelse(is_cp, cid %in% ph_obs, NA)
    }
  }

  attr(out, "backbone_conflicts") <- tab
  attr(out, "backbone_conflict_params") <- params
  out
}

# Rank columns, coarse to fine: TaxaTools::detect_ranks() when available,
# else the standard ladder intersected with what taxonomy actually carries.
.bc_rank_system <- function(taxonomy, rank_system) {
  if (!is.null(rank_system)) {
    miss <- setdiff(rank_system, names(taxonomy))
    if (length(miss))
      stop("flag_backbone_conflicts: rank_system columns absent from taxonomy: ",
           paste(miss, collapse = ", "), call. = FALSE)
    return(rank_system)
  }
  if (requireNamespace("TaxaTools", quietly = TRUE)) {
    r <- try(TaxaTools::detect_ranks(taxonomy), silent = TRUE)
    if (!inherits(r, "try-error") && length(r) >= 2L) return(intersect(r, names(taxonomy)))
  }
  intersect(c("kingdom", "phylum", "class", "order", "family", "genus", "species"),
            names(taxonomy))
}

# The same-rank case, delegated to TaxaTools rather than reimplemented.
.bc_multi_parent <- function(taxonomy, ranks) {
  empty <- data.frame(name = character(0), rank = character(0),
                      parents = character(0), stringsAsFactors = FALSE)
  if (!requireNamespace("TaxaTools", quietly = TRUE)) {
    warning("flag_backbone_conflicts: TaxaTools is not installed, so the ",
            "same-rank (multi-parent) case is not checked; only cross-rank ",
            "names are reported.", call. = FALSE)
    return(empty)
  }
  # Deduplicated first. Whether a name sits under more than one parent is a
  # property of the SET of (name, rank, parent) tuples present, so it cannot
  # depend on how many rows carry a tuple -- and this helper keeps only
  # name/rank/parents, no counts, so nothing downstream sees multiplicity
  # either. find_taxonomy_conflicts() scales super-linearly in rows: measured
  # 1.9s at 25k, 9.2s at 100k and 54.1s at 400k, which projects to hours on a
  # real posterior frame (6.1M rows, 34k distinct tuples), where the
  # deduplicated call is ~1s. unique() itself is cheap (0.6s at 400k).
  cf <- try(TaxaTools::find_taxonomy_conflicts(unique(taxonomy[, ranks, drop = FALSE]),
                                               rank_system = ranks), silent = TRUE)
  if (inherits(cf, "try-error") || !is.data.frame(cf) || !nrow(cf)) return(empty)
  need <- c("taxon_name", "taxon_rank", "parent_values")
  if (!all(need %in% names(cf))) return(empty)
  data.frame(name = as.character(cf$taxon_name), rank = as.character(cf$taxon_rank),
             parents = as.character(cf$parent_values), stringsAsFactors = FALSE)
}

.bc_posterior_col <- function(taxonomy, posterior_col) {
  if (!is.null(posterior_col)) {
    if (!posterior_col %in% names(taxonomy))
      stop("flag_backbone_conflicts: posterior_col '", posterior_col,
           "' absent from taxonomy", call. = FALSE)
    return(posterior_col)
  }
  for (cand in c("posterior_point_est", "posterior_mean")) if (cand %in% names(taxonomy)) return(cand)
  NULL
}

.bc_cols <- c("backbone_conflict", "backbone_conflict_kind", "backbone_conflict_names",
              "backbone_conflict_mass", "cross_phylum_conflicted")

.bc_empty_columns <- function(consensus) {
  clash <- intersect(.bc_cols, names(consensus))
  if (length(clash))
    warning("flag_backbone_conflicts: overwriting existing column(s): ",
            paste(clash, collapse = ", "), call. = FALSE)
  consensus$backbone_conflict <- FALSE
  consensus$backbone_conflict_kind <- NA_character_
  consensus$backbone_conflict_names <- NA_character_
  consensus$backbone_conflict_mass <- NA_real_
  consensus$cross_phylum_conflicted <- NA
  consensus
}

.bc_empty_table <- function() {
  data.frame(name = character(0), kind = character(0), category = character(0),
             n_ranks = integer(0), ranks = character(0), parents = character(0),
             candidate_rows = integer(0), observations = integer(0),
             stringsAsFactors = FALSE)
}
