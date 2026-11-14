utils::globalVariables(c("taxon_id", "verbatim_name", "source_table", "name_clean", "status", "n_names"))

# ==============================================================================
# One taxon registry per run: every name from every table resolved ONCE, to a
# record identifier under ONE key authority, and every join made on that
# identifier. A name is not a key.
#
# Layout of a registry (class "taxon_registry"):
#   $taxa   one row per taxon used in the run, accepted taxa and every ancestor:
#           taxon_id, name, rank, parent_id, authority, snapshot, local
#   $names  one row per (verbatim name, source table, context): what arrived,
#           what it resolved to, and how (status, backend record, match type)
#   $meta   run_id, key backbone, authority label, snapshot(s), frozen, digest
#
# Reuses verify_taxon_names(return_ids = TRUE) for every lookup and
# clean_taxon_names() for every name; new code here is only the table, the
# freeze/stamp, the join helper and the guard.
# ==============================================================================

.REGISTRY_PREFIX <- c(`1` = "col", `4` = "ncbi", `9` = "worms", `11` = "gbif")
.REGISTRY_STAMP <- "taxon_registry"
# Columns that hold a NAME or a name-derived lineage string. A join on any of
# them is a join on a name, which is what the registry exists to remove.
.NAME_COLUMNS <- c("taxon_name", "species", "genus", "family", "order", "class", "phylum",
                   "kingdom", "scientificName", "scientific_name", "verbatim_name", "name",
                   "name_clean", "accepted_name", "matched_name", "consensus_taxon")
# Latin gender endings: a name differing from a resolved congener ONLY here is
# the same species spelled for another gender (Platybelone argala / argalus).
.GENDER_ENDINGS <- "(us|um|a|is|e|er|ra|rum|os|on)$"
# Ranks at which an answer to a binomial is an answer about THAT species.
.SPECIES_LEVEL <- c("species", "subspecies", "variety", "form", "forma", "infraspecies", "infraspecific")
# Rank ladder for "was the name answered at a coarser rank than it was asked at?". Below species everything is one
# step (infraspecific). A rank not on the ladder cannot be compared: an ANSWER at such a rank counts as coarser
# (refused, not accepted); a name ASKED at such a rank falls back to the shape rule.
.RANK_LADDER <- c(kingdom = 1L, phylum = 2L, class = 3L, order = 4L, family = 5L, genus = 6L, species = 7L,
                  subspecies = 8L, variety = 8L, form = 8L, forma = 8L, infraspecies = 8L, infraspecific = 8L)

#' The rank a name was asked at: the rank given, else genus (one word), species (two), infraspecific (three or more)
#' @noRd
.asked_rank_level <- function(name_clean, rank_given) {
  given <- unname(.RANK_LADDER[tolower(rank_given)])
  nw <- lengths(strsplit(trimws(name_clean), "\\s+"))
  shape <- ifelse(nw <= 1L, 6L, ifelse(nw == 2L, 7L, 8L))
  ifelse(is.na(given), shape, given)
}

#' @noRd
.registry_prefix <- function(backbone_id) {
  p <- .REGISTRY_PREFIX[as.character(as.integer(backbone_id))]
  if (is.na(p)) paste0("ds", as.integer(backbone_id)) else unname(p)
}

#' @noRd
.split_pipe <- function(x) if (is.na(x) || !nzchar(x)) character(0L) else trimws(strsplit(x, "|", fixed = TRUE)[[1L]])

#' @noRd
.epithet_stem <- function(epithet) sub(.GENDER_ENDINGS, "", tolower(epithet))

#' Default lookup: verify_taxon_names() with identifiers, context and rank
#' @noRd
.registry_default_lookup <- function(backbone_id, cache_dir) {
  force(backbone_id); force(cache_dir)
  function(names, rank, context) {
    verify_taxon_names(names, backbone_id = backbone_id, cache_dir = cache_dir,
                       input_rank = rank, lineage = context, return_ids = TRUE)
  }
}

#' Ancestor rows (taxa table) of one resolved lookup row
#' @noRd
.ancestor_rows <- function(path, ranks, ids, prefix, snapshot) {
  p <- .split_pipe(path); r <- .split_pipe(ranks); i <- .split_pipe(ids)
  n <- min(length(p), length(r), length(i))
  if (n == 0L) return(NULL)
  p <- p[seq_len(n)]; r <- r[seq_len(n)]; i <- paste0(prefix, ":", i[seq_len(n)])
  data.frame(taxon_id = i, name = p, rank = tolower(r), parent_id = c(NA_character_, utils::head(i, -1L)),
             snapshot = snapshot, local = FALSE, stringsAsFactors = FALSE)
}

# Columns a lookup must return. Every one is read below; a missing one is refused, never defaulted (a defaulted
# match_type gave every row row 1's synonym status; a missing verified turned failed lookups into local ids).
.LOOKUP_COLUMNS <- c("matched_name", "matched_rank", "is_synonym", "classification_path", "classification_ranks",
                     "verified", "matched", "current_record_id", "classification_ids", "match_type")

#' Refuse a lookup answer that is not one row per name with every column the registry reads
#' @noRd
.check_lookup_shape <- function(res, n, what) {
  miss <- if (is.data.frame(res)) setdiff(.LOOKUP_COLUMNS, names(res)) else .LOOKUP_COLUMNS
  rows_ok <- is.data.frame(res) && nrow(res) == n
  if (length(miss) || !rows_ok) {
    msg <- sprintf("`lookup` (%s) must return one row per name with the verify_taxon_names(return_ids = TRUE) columns%s%s.", what,
                   if (!rows_ok) sprintf("; it returned %s row(s) for %d name(s)", if (is.data.frame(res)) nrow(res) else "no data frame /", n) else "",
                   if (length(miss)) paste0("; missing column(s): ", paste(miss, collapse = ", ")) else "")
    stop(structure(class = c("taxon_registry_bad_lookup", "error", "condition"), list(message = msg, call = NULL)))
  }
  invisible(TRUE)
}

# Ranks a candidate's lineage is compared on in the tie-break (the name itself is the same on every candidate).
.TB_RANKS <- c("kingdom", "phylum", "class", "order", "family", "genus")

#' A classification path's terms at the tie-break ranks, kingdom first, NAMED by rank
#' @noRd
.tb_terms_of_path <- function(path, ranks) {
  p <- .split_pipe(path); r <- tolower(.split_pipe(ranks))
  n <- min(length(p), length(r)); if (n == 0L) return(character(0L))
  keep <- r[seq_len(n)] %in% .TB_RANKS
  stats::setNames(p[seq_len(n)][keep], r[seq_len(n)][keep])
}

#' Tie-break between 2+ GBIF candidate ids for one name (GBIF's own match first, then each authority in order)
#'
#' Step 0 (\code{gbif_first}): GBIF's own match for the name, when it is exactly one of the candidates.
#' Then each authority in order. Candidate lineages are compared RANK BY RANK (\code{cand_terms} are named by
#' rank): a rank distinguishes only where EVERY candidate has a value there and the values differ. A rank one
#' candidate lacks is missing data, not evidence (a fuller lineage must not win on it). For each distinguishing
#' rank, a candidate scores 1 if the authority's lineage holds its term; strictly the highest score wins. No
#' answer, a tie, no distinguishing rank, or a candidate with no lineage: the next authority, then undecided
#' (\code{id = NA}), and the caller keeps the error-class finding.
#' @return list(id, by, detail)
#' @noRd
.registry_tiebreak <- function(name, cand_ids, cand_terms, lookup_id, tiebreak) {
  notes <- character(0L)
  if (isTRUE(tiebreak$gbif_first)) {
    if (!is.na(lookup_id) && sum(cand_ids == lookup_id) == 1L) {
      return(list(id = lookup_id, by = "gbif", detail = "GBIF's own match is one of the candidates"))
    }
    notes <- c(notes, "gbif: its match is not one of the candidates")
  }
  if (any(lengths(cand_terms) == 0L)) {
    return(list(id = NA_character_, by = NA_character_,
                detail = paste(c(notes, "a candidate has no lineage to compare"), collapse = "; ")))
  }
  if (any(vapply(cand_terms, function(tt) is.null(names(tt)) || any(!nzchar(names(tt))), TRUE))) {
    stop(".registry_tiebreak: candidate terms must be named by rank.")
  }
  ranks_all <- Reduce(intersect, lapply(cand_terms, names))
  dist <- ranks_all[vapply(ranks_all, function(rk) length(unique(tolower(vapply(cand_terms, function(tt) tt[[rk]], "")))) > 1L, TRUE)]
  if (!length(dist)) {
    return(list(id = NA_character_, by = NA_character_,
                detail = paste(c(notes, "no rank that every candidate has differs between them"), collapse = "; ")))
  }
  for (a in names(tiebreak$authorities)) {
    L <- tryCatch(as.character(tiebreak$authorities[[a]](name))[1L], error = function(e) NA_character_)
    if (is.na(L) || !nzchar(L)) { notes <- c(notes, paste0(a, ": no answer")); next }
    score <- vapply(cand_terms, function(tt)
      sum(check_lineage_agreement(rep(L, length(dist)), unname(tt[dist]), ignore = character(0L)) == "agrees"), 0L)
    if (max(score) > 0L && sum(score == max(score)) == 1L) {
      w <- which.max(score)
      return(list(id = cand_ids[w], by = a, detail = paste(c(notes, sprintf("%s lineage holds %s of %s's terms at the distinguishing rank(s) %s (scores %s)",
                                                             a, max(score), cand_ids[w], paste(dist, collapse = ","), paste(score, collapse = "/"))), collapse = "; ")))
    }
    notes <- c(notes, sprintf("%s: not decided (scores %s)", a, paste(score, collapse = "/")))
  }
  list(id = NA_character_, by = NA_character_, detail = paste(notes, collapse = "; "))
}

#' Does a non-exact genus answer sit in the names' own lineage? Kingdom AND phylum must agree.
#'
#' A fuzzy or variant genus answer can be a different genus in another kingdom (Hypnea, a red
#' alga, answered as Hypena, a moth). It is taken only when the context (the union of the
#' lineages the tables give for the names under that genus word) names the answer's kingdom
#' and its phylum. No context, no kingdom or phylum in it, or a mismatch: not taken.
#' @noRd
.genus_answer_in_context <- function(ctx, path, ranks) {
  if (is.na(ctx) || !nzchar(ctx)) return(FALSE)
  p <- .split_pipe(path); r <- tolower(.split_pipe(ranks))
  ph <- p[r == "phylum"]
  kp <- .kingdom_of_path(path, ranks); kc <- .kingdoms_of_context(ctx)
  if (!length(ph) || is.na(kp) || !length(kc) || !(kp %in% kc)) return(FALSE)
  identical(check_lineage_agreement(ctx, ph[[1L]], ignore = character(0)), "agrees")
}

#' Does a genus answer CONTRADICT the names' context? Yes if both name a kingdom and they differ, or if the
#' context's non-kingdom terms share nothing with the answer's path from phylum to genus. No context, or nothing
#' to compare on one side: no contradiction (an EXACT answer is then taken as before).
#' @noRd
.genus_conflicts_context <- function(ctx, path, ranks) {
  if (is.na(ctx) || !nzchar(ctx)) return(FALSE)
  kp <- .kingdom_of_path(path, ranks); kc <- .kingdoms_of_context(ctx)
  if (!is.na(kp) && length(kc) && !(kp %in% kc)) return(TRUE)
  p <- .split_pipe(path); r <- tolower(.split_pipe(ranks)); n <- min(length(p), length(r))
  up <- p[seq_len(n)][r[seq_len(n)] %in% c("phylum", "class", "order", "family", "genus")]
  ct <- .split_pipe(ctx); ct <- ct[is.na(.KINGDOM_LABELS[tolower(ct)])]
  if (!length(up) || !length(ct)) return(FALSE)
  !any(tolower(ct) %in% tolower(up))
}

#' A taxa-table id's path and ranks, walked up its parent chain (kingdom first)
#' @noRd
.path_in_taxa <- function(id, taxa) {
  p <- character(0L); r <- character(0L); seen <- character(0L)
  while (length(id) == 1L && !is.na(id) && !(id %in% seen)) {
    k <- match(id, taxa$taxon_id); if (is.na(k)) break
    seen <- c(seen, id); p <- c(taxa$name[k], p); r <- c(if (is.na(taxa$rank[k])) "" else taxa$rank[k], r)
    id <- taxa$parent_id[k]
  }
  list(path = paste(p, collapse = "|"), ranks = paste(r, collapse = "|"))
}

#' Build a run's taxon registry
#'
#' Resolves every verbatim name the run will use, from every table, ONCE, to a
#' record identifier under one key authority, and records how each name got
#' there. Lookups go through \code{\link{verify_taxon_names}} with
#' \code{return_ids = TRUE}, so the identifier of the accepted record and of
#' every ancestor come back in one answer; names are cleaned first with
#' \code{\link{clean_taxon_names}}. The registry is then frozen with
#' \code{\link{freeze_taxon_registry}} before any table is joined.
#'
#' \strong{Pool keys first.} Where \code{pool_keys} gives an accepted key for a
#' name (the occurrence pool's own GBIF \code{speciesKey}), that key IS the
#' taxon identifier; the lookup still supplies the ancestor chain, and a lookup
#' whose accepted record differs from the pool's key is recorded as
#' \code{status = "pool_key_conflict"} for the guard, never silently resolved.
#' A name the pool holds under two or more different keys is not keyed from
#' the pool at all (its identifier comes from the lookup alone); it is listed in
#' \code{meta$pool_key_ambiguous} and reported by
#' \code{\link{check_taxon_registry}} as an error-class
#' \code{pool_key_ambiguous} finding.
#'
#' \strong{Tie-break} (off by default, \code{tiebreak}). Where a name has two
#' or more candidate ids (\code{pool_key_ambiguous}, or a
#' \code{pool_key_conflict} between the pool's key and the lookup's), the
#' candidates are decided by, in order: for \code{pool_key_ambiguous} only,
#' the lookup's own answer when it is exactly one of the pool's keys
#' (\code{gbif_first}); then each of \code{authorities} in turn. The
#' candidates' lineages are compared rank by rank: a rank distinguishes only
#' where every candidate has a value there and the values differ (a rank one
#' candidate lacks is missing data, not evidence). Per distinguishing rank, a
#' candidate scores 1 if the authority's lineage holds its term; strictly the
#' highest score wins. A decided name gets
#' \code{status = "pool_key_tiebreak"}; an undecided one keeps its
#' error-class finding. Candidates with identical lineages are never decided.
#' Step 0 never applies to a \code{pool_key_conflict}: there the lookup's key
#' is one of the two candidates by construction, so it would always win and
#' undo pool-keys-first; a conflict is decided by the authorities or not at all.
#'
#' \strong{Coarser answers.} Every name is checked for an answer at a coarser
#' rank than it was asked at (\code{rank_given}, else genus for one word,
#' species for two, infraspecific for three or more): such a name gets
#' \code{status = "rank_fallback"} and a run-local identifier under the
#' answered ancestor, never that ancestor's identifier.
#'
#' \strong{Unresolved names} get a run-local identifier under their resolved
#' genus (\code{local:<genus id>:<epithet>}), or \code{local:<name>} when even
#' the genus is unknown. The genus is resolved per genus word AND \code{context}:
#' genus rows already in the registry are used only where they do not
#' contradict the context, and a word naming two or more such genera is refused
#' (\code{meta$genus_homonym_unresolved}); otherwise the genus is looked up
#' with the names' context. A genus answered only by a fuzzy or variant match
#' is taken only where the context names the answer's kingdom and phylum; an
#' exact answer is refused where it contradicts the context. Refusals are listed
#' in \code{meta$genus_variant_rejected} (a genus word can name a genus in
#' another kingdom). One narrow exception: a binomial whose epithet differs
#' from a resolved congener's only in its Latin gender ending (\emph{Platybelone
#' argala} / \emph{argalus}) takes that congener's identifier with
#' \code{status = "gender_variant"}, only from a congener with the same context
#' (or, with a context, the same kingdom), and never for a name the lineage
#' gate rejected. A second: a binomial the lookup answers
#' as a GBIF \code{VARIANT} of its genus, with the epithet unchanged
#' (\emph{Pyrogophorus platyrachis} / \emph{Pyrgophorus platyrachis}), takes
#' that species' identifier with \code{status = "genus_variant"}, under the same
#' gate: the name's own \code{context} must name the answer's kingdom and
#' phylum, or it is refused and listed in \code{meta$genus_variant_rejected}.
#' This needs the lookup's \code{gbif_matchType} column. Every use is listed by
#' \code{\link{check_taxon_registry}}. No other fuzzy matching is accepted:
#' any other fuzzy answer gets \code{status = "fuzzy_rejected"} and no
#' identifier from the answer; the name takes the unresolved path above.
#' A \code{lookup} must return every column the registry reads (see
#' \code{lookup}); a missing one is refused with an error of class
#' \code{taxon_registry_bad_lookup}, never defaulted.
#'
#' @param names A data frame of the names to register, one row per name per
#'   source: \code{verbatim_name} and \code{source_table} (required);
#'   \code{source_naming} (e.g. \code{"ncbi"}, \code{"gbif"}, \code{"user"}),
#'   \code{rank_given} and \code{context} (a pipe-delimited higher-taxon string,
#'   the homonym gate) optional.
#' @param run_id Character scalar identifying the run; part of every stamp.
#' @param key_backbone_id Integer: the key authority's Global Names Verifier
#'   data source (11 = GBIF Backbone, 1 = Catalogue of Life, 9 = WoRMS). Default
#'   \code{11L}.
#' @param pool_keys \code{NULL} or a data frame with \code{verbatim_name} and
#'   \code{species_key}: the occurrence pool's accepted key per name, used as the
#'   identifier ahead of any lookup. Optional \code{kingdom} ... \code{genus}
#'   columns give each key's lineage for the tie-break.
#' @param lookup \code{NULL} (default: \code{verify_taxon_names()} against
#'   \code{key_backbone_id} with \code{cache_dir}) or a function
#'   \code{function(names, rank, context)} returning a table shaped like
#'   \code{verify_taxon_names(return_ids = TRUE)}, one row per name, with at
#'   least \code{matched_name}, \code{matched_rank}, \code{is_synonym},
#'   \code{classification_path}, \code{classification_ranks}, \code{verified},
#'   \code{matched}, \code{current_record_id}, \code{classification_ids} and
#'   \code{match_type}; supply one to resolve from recorded answers offline.
#' @param cache_dir Passed to \code{verify_taxon_names()} by the default lookup.
#' @param tiebreak \code{NULL} (default: no tie-break; 2+ candidate ids stay
#'   error-class findings) or a list: \code{gbif_first} (logical, default
#'   \code{TRUE}: for a name the pool holds under 2+ keys, take the lookup's
#'   own answer when it is exactly one of them; never used for a
#'   \code{pool_key_conflict}) and \code{authorities}, a named, ordered list of functions
#'   \code{function(name)} returning that authority's pipe-delimited lineage
#'   for the name, or \code{NA} (e.g. \code{list(ncbi = ..., worms = ...)}).
#'   Candidate lineages come from the lookup's classification and from optional
#'   \code{kingdom} ... \code{genus} columns of \code{pool_keys}.
#' @return An object of class \code{taxon_registry}: a list with \code{taxa},
#'   \code{names} and \code{meta}, unfrozen.
#' @seealso \code{\link{freeze_taxon_registry}}, \code{\link{attach_taxon_ids}},
#'   \code{\link{join_by_taxon}}, \code{\link{check_taxon_registry}}
#' @export
build_taxon_registry <- function(names, run_id, key_backbone_id = 11L, pool_keys = NULL,
                                 lookup = NULL, cache_dir = NULL, tiebreak = NULL) {
  if (!is.data.frame(names) || !all(c("verbatim_name", "source_table") %in% names(names))) {
    stop("`names` must be a data frame with columns verbatim_name and source_table.")
  }
  if (!is.character(run_id) || length(run_id) != 1L || is.na(run_id) || !nzchar(run_id)) {
    stop("`run_id` must be a non-empty character scalar.")
  }
  key_backbone_id <- as.integer(key_backbone_id)
  prefix <- .registry_prefix(key_backbone_id)
  if (is.null(lookup)) lookup <- .registry_default_lookup(key_backbone_id, cache_dir)
  if (!is.function(lookup)) stop("`lookup` must be NULL or a function(names, rank, context).")
  if (!is.null(tiebreak)) {
    if (!is.list(tiebreak)) stop("`tiebreak` must be NULL or a list(gbif_first =, authorities =).")
    tiebreak$gbif_first <- if (is.null(tiebreak$gbif_first)) TRUE else isTRUE(tiebreak$gbif_first)
    au <- tiebreak$authorities %||% list()
    if (!is.list(au) || (length(au) && (is.null(names(au)) || any(!nzchar(names(au))) || !all(vapply(au, is.function, TRUE))))) {
      stop("`tiebreak$authorities` must be a named list of functions(name).")
    }
    tiebreak$authorities <- au
  }

  nm <- data.frame(verbatim_name = as.character(names$verbatim_name),
                   source_table = as.character(names$source_table), stringsAsFactors = FALSE)
  for (cc in c("source_naming", "rank_given", "context")) {
    nm[[cc]] <- if (cc %in% names(names)) as.character(names[[cc]]) else NA_character_
  }
  nm$rank_given <- tolower(nm$rank_given)
  nm <- nm[!is.na(nm$verbatim_name) & nzchar(trimws(nm$verbatim_name)), , drop = FALSE]
  nm <- unique(nm)
  if (nrow(nm) == 0L) stop("`names` holds no non-empty verbatim_name.")
  nm$name_clean <- as.character(suppressMessages(clean_taxon_names(nm$verbatim_name)))
  nm$name_clean[is.na(nm$name_clean) | !nzchar(nm$name_clean)] <- trimws(nm$verbatim_name[is.na(nm$name_clean) | !nzchar(nm$name_clean)])

  # --- one lookup per distinct (clean name, rank, context) ----------------------
  q <- unique(nm[, c("name_clean", "rank_given", "context")])
  res <- lookup(q$name_clean, q$rank_given, q$context)
  .check_lookup_shape(res, nrow(q), "name lookup")
  qk <- paste(q$name_clean, q$rank_given, q$context, sep = "\r")
  nk <- paste(nm$name_clean, nm$rank_given, nm$context, sep = "\r")
  r <- res[match(nk, qk), , drop = FALSE]
  ok <- r$matched %in% TRUE & !is.na(r$current_record_id) & nzchar(r$current_record_id)

  nm$taxon_id <- ifelse(ok, paste0(prefix, ":", r$current_record_id), NA_character_)
  # the lookup's ACCEPTED name for that id: what names a taxon the lookup gave no path for
  nm$accepted_lookup <- ifelse(ok, as.character(r$matched_name), NA_character_)
  nm$matched_rank <- tolower(r$matched_rank)
  nm$status <- ifelse(!ok, NA_character_,
                ifelse(tolower(r$match_type) %in% c("fuzzy", "partialfuzzy", "partialfuzzyspecies"), "fuzzy",
                ifelse(r$is_synonym %in% TRUE, "synonym", "accepted")))
  # A fuzzy answer that differs from the query ONLY in the epithet's gender
  # ending is the gender rule, declared and listed; any other fuzzy answer stays
  # "fuzzy" and is an undeclared merge if it lands on another name's taxon.
  fz <- which(nm$status %in% "fuzzy" & grepl("^\\S+ \\S+$", nm$name_clean) & grepl("^\\S+ \\S+$", r$matched_name))
  if (length(fz)) {
    same_g <- sub(" .*$", "", nm$name_clean[fz]) == sub(" .*$", "", r$matched_name[fz])
    same_s <- .epithet_stem(sub("^\\S+ ", "", nm$name_clean[fz])) == .epithet_stem(sub("^\\S+ ", "", r$matched_name[fz]))
    nm$status[fz[same_g & same_s]] <- "gender_variant"
  }
  # A binomial GBIF answered as an orthographic VARIANT of its GENUS, with the epithet exact
  # (Pyrogophorus platyrachis -> Pyrgophorus platyrachis), takes GBIF's species, status
  # genus_variant -- but only where the name's own context names the answer's kingdom and phylum,
  # the genus-pass gate: Hypnea nigrescens, a red alga, answered as Hypena nigrescens, a moth, is
  # refused (fuzzy_rejected) and listed. Needs the lookup's gbif_matchType; without it, never fires.
  bin_variant_rejected <- list()
  gmt <- if ("gbif_matchType" %in% names(r)) as.character(r$gbif_matchType) else rep(NA_character_, nrow(r))
  gvb <- which(nm$status %in% "fuzzy" & gmt %in% "VARIANT" & nm$matched_rank %in% "species" &
                 grepl("^\\S+ \\S+$", nm$name_clean) & grepl("^\\S+ \\S+$", r$matched_name))
  gvb <- gvb[sub(" .*$", "", nm$name_clean[gvb]) != sub(" .*$", "", r$matched_name[gvb]) &
               sub("^\\S+ ", "", nm$name_clean[gvb]) == sub("^\\S+ ", "", r$matched_name[gvb])]
  for (i in gvb) {
    ctx_i <- nm$context[i]
    if (.genus_answer_in_context(ctx_i, r$classification_path[i], r$classification_ranks[i])) {
      nm$status[i] <- "genus_variant"
    } else {
      has_ctx <- !is.na(ctx_i) && nzchar(ctx_i)
      bin_variant_rejected[[length(bin_variant_rejected) + 1L]] <- data.frame(
        genus_word = sub(" .*$", "", nm$name_clean[i]), answer = r$matched_name[i], answer_id = paste0(prefix, ":", r$current_record_id[i]),
        answer_path = r$classification_path[i], context = if (has_ctx) ctx_i else NA_character_,
        reason = if (has_ctx) "lineage does not agree at kingdom and phylum" else "no lineage context",
        pass = "binomial", query = nm$name_clean[i], stringsAsFactors = FALSE)
    }
  }
  # Three answers that must NOT resolve a name to the id they carry:
  #  - a lookup that FAILED (verified FALSE): status lookup_failed, no id, never a local id --
  #    a failed request is not an answer, and attach_taxon_ids() refuses the name;
  #  - a name answered at a COARSER rank than it was asked at (a binomial answered at its genus, a genus at its
  #    family, a trinomial at its species): taking that id would merge the name into its ancestor; status
  #    rank_fallback, then a run-local id under the answered ancestor (below). Every row is checked, not only
  #    binomials;
  #  - a fuzzy answer that is not a gender variant: a different string, so a different taxon
  #    until shown otherwise; status fuzzy_rejected, then the unresolved path.
  # A row the lineage gate refused is an ANSWER (the service named a taxon in another
  # lineage: a homonym), not a failure: it takes the unresolved path, status homonym_rejected.
  gated <- !(r$verified %in% TRUE) & r$match_type %in% "LineageRejected"
  failed <- !(r$verified %in% TRUE) & !gated
  nm$status[gated] <- "homonym_rejected"
  nm$status[failed] <- "lookup_failed"; nm$taxon_id[failed] <- NA_character_
  ans_lvl <- unname(.RANK_LADDER[nm$matched_rank])
  above <- ok & (is.na(ans_lvl) | ans_lvl < .asked_rank_level(nm$name_clean, nm$rank_given))
  nm$fallback_parent <- ifelse(above, nm$taxon_id, NA_character_)   # the answered ancestor: parent of the local id
  nm$status[above] <- "rank_fallback"; nm$taxon_id[above] <- NA_character_
  fzr <- nm$status %in% "fuzzy"
  nm$status[fzr] <- "fuzzy_rejected"; nm$taxon_id[fzr] <- NA_character_
  nm$accepted_lookup[failed | above | fzr] <- NA_character_
  nm$backend <- ifelse(!is.na(nm$taxon_id), paste0("gnverifier:", key_backbone_id), NA_character_)
  nm$backend_record_id <- ifelse(ok, r$record_id, NA_character_)
  nm$match_type <- r$match_type
  nm$hop <- ifelse(nm$source_naming %in% "ncbi", "ncbi_name_in_key_authority", "direct")

  taxa <- list()
  for (i in which(!duplicated(qk) & seq_along(qk) > 0L)) {
    if (!(res$matched[i] %in% TRUE) || is.na(res$current_record_id[i])) next
    a <- .ancestor_rows(res$classification_path[i], res$classification_ranks[i], res$classification_ids[i],
                        prefix, res$entry_date[i] %||% NA_character_)
    if (!is.null(a)) taxa[[length(taxa) + 1L]] <- a
  }

  # --- pool keys first --------------------------------------------------------
  pool_key_ambiguous <- NULL; pool_key_tiebreaks <- NULL
  if (!is.null(pool_keys)) {
    if (!is.data.frame(pool_keys) || !all(c("verbatim_name", "species_key") %in% names(pool_keys))) {
      stop("`pool_keys` must be NULL or a data frame with verbatim_name and species_key.")
    }
    # A name the pool holds under 2+ different keys has no one pool key: it is not keyed from the pool
    # (match() would silently take the first) and is listed in meta$pool_key_ambiguous for the guard.
    pkv <- pool_keys[!is.na(pool_keys$verbatim_name) & !is.na(pool_keys$species_key), c("verbatim_name", "species_key"), drop = FALSE]
    pkv <- unique(data.frame(verbatim_name = as.character(pkv$verbatim_name), species_key = as.character(pkv$species_key),
                             stringsAsFactors = FALSE))
    amb_names <- unique(pkv$verbatim_name[duplicated(pkv$verbatim_name)])
    amb_all <- amb_names                                     # never keyed by match(), decided or not
    lk_id <- nm$taxon_id; acc0 <- nm$accepted_lookup        # the lookup's own answer, before any pool key
    lin_cols <- intersect(.TB_RANKS, names(pool_keys))
    pool_terms <- function(v, k) {
      if (!length(lin_cols)) return(character(0L))
      w <- pool_keys[as.character(pool_keys$verbatim_name) %in% v & as.character(pool_keys$species_key) %in% k, lin_cols, drop = FALSE]
      if (!nrow(w)) return(character(0L))
      x <- stats::setNames(as.character(unlist(w[1L, ], use.names = FALSE)), lin_cols); x[!is.na(x) & nzchar(x)]
    }
    tb_rows <- list(); tb_pick <- character(0L); tb_by <- character(0L)
    if (!is.null(tiebreak)) {
      for (v in intersect(amb_names, nm$verbatim_name)) {
        keys <- sort(unique(pkv$species_key[pkv$verbatim_name == v])); ids <- paste0(prefix, ":", keys)
        lid <- unique(stats::na.omit(lk_id[nm$verbatim_name == v]))
        tb <- .registry_tiebreak(v, ids, lapply(keys, function(k) pool_terms(v, k)), if (length(lid) == 1L) lid else NA_character_, tiebreak)
        tb_rows[[length(tb_rows) + 1L]] <- data.frame(verbatim_name = v, kind = "pool_key_ambiguous", candidates = paste(ids, collapse = " | "),
                                                      chosen = tb$id, by = tb$by, detail = tb$detail, stringsAsFactors = FALSE)
        if (!is.na(tb$id)) { tb_pick[v] <- tb$id; tb_by[v] <- tb$by }
      }
      amb_names <- setdiff(amb_names, names(tb_pick))
    }
    pool_key_ambiguous <- if (length(amb_names)) data.frame(verbatim_name = amb_names,
      species_keys = vapply(amb_names, function(v) paste(sort(pkv$species_key[pkv$verbatim_name == v]), collapse = " | "), ""),
      in_names = amb_names %in% nm$verbatim_name, stringsAsFactors = FALSE, row.names = NULL) else NULL
    pkv <- pkv[!pkv$verbatim_name %in% amb_all, , drop = FALSE]   # a decided ambiguous name takes its id below, not a first pick
    pk <- paste0(prefix, ":", pkv$species_key)[match(nm$verbatim_name, pkv$verbatim_name)]
    has <- !is.na(match(nm$verbatim_name, pkv$verbatim_name))
    clash <- has & !is.na(nm$taxon_id) & nm$taxon_id != pk
    if (!is.null(tiebreak) && any(clash)) {
      for (v in unique(nm$verbatim_name[clash])) {
        i <- which(clash & nm$verbatim_name == v)[1L]
        ids <- c(pk[i], lk_id[i])
        # no step 0 here: the lookup's key is one of the two candidates by construction, so "GBIF's own match
        # decides" would always side with the lookup and silently reverse pool-keys-first. Authorities only.
        tb <- .registry_tiebreak(v, ids, list(pool_terms(v, sub("^[^:]+:", "", pk[i])),
                                              .tb_terms_of_path(r$classification_path[i], r$classification_ranks[i])), lk_id[i],
                                 utils::modifyList(tiebreak, list(gbif_first = FALSE)))
        tb_rows[[length(tb_rows) + 1L]] <- data.frame(verbatim_name = v, kind = "pool_key_conflict", candidates = paste(ids, collapse = " | "),
                                                      chosen = tb$id, by = tb$by, detail = tb$detail, stringsAsFactors = FALSE)
        if (!is.na(tb$id)) { tb_pick[v] <- tb$id; tb_by[v] <- tb$by }
      }
    }
    nm$status[clash] <- "pool_key_conflict"
    nm$accepted_lookup[clash] <- NA_character_   # the lookup's accepted name is ANOTHER taxon's
    nm$taxon_id[has] <- pk[has]
    nm$backend[has & !clash & is.na(nm$backend)] <- "pool_keys"
    nm$status[has & (is.na(nm$status) | nm$status %in% c("lookup_failed", "rank_fallback", "fuzzy_rejected", "homonym_rejected"))] <- "pool_key_only"
    if (length(tb_pick)) {
      w <- which(nm$verbatim_name %in% names(tb_pick))
      newid <- unname(tb_pick[nm$verbatim_name[w]])
      same <- !is.na(lk_id[w]) & newid == lk_id[w]
      nm$accepted_lookup[w] <- ifelse(same, acc0[w], NA_character_)   # the lookup's name only where it named the chosen id
      nm$taxon_id[w] <- newid; nm$status[w] <- "pool_key_tiebreak"
      nm$backend[w] <- paste0("tiebreak:", unname(tb_by[nm$verbatim_name[w]]))
    }
    pool_key_tiebreaks <- if (length(tb_rows)) do.call(rbind, tb_rows) else NULL
  }

  taxa <- if (length(taxa)) do.call(rbind, taxa) else
    data.frame(taxon_id = character(0), name = character(0), rank = character(0), parent_id = character(0),
               snapshot = character(0), local = logical(0), stringsAsFactors = FALSE)

  # --- unresolved: gender variant of a resolved congener, else a local id ---------
  # A genus id is resolved per (genus WORD, CONTEXT), never by the word alone: one word can name genera in two
  # kingdoms (Vertebrata the red alga; Agathis the conifer and the wasp).
  #  - genus rows already in taxa: those not contradicting the context are candidates; exactly one is taken;
  #    two or more (or two with no context to choose) are refused and listed (genus_homonym_unresolved);
  #  - otherwise one lookup per (word, context), WITH the context: a non-exact answer needs the kingdom+phylum
  #    gate; an EXACT one is refused where it contradicts the context (.genus_conflicts_context);
  #  - the gender rule takes a congener only from the same context (or, with a context, the same kingdom), and
  #    never for a homonym_rejected name.
  genus_variant_rejected <- list(); genus_homonym_unresolved <- list()
  un <- which(is.na(nm$taxon_id) & !nm$status %in% "lookup_failed")
  if (length(un)) {
    gen_of <- function(x) sub(" .*$", "", x)
    ep_of <- function(x) sub("^\\S+ ", "", x)
    ctx_of <- function(v) ifelse(is.na(v) | !nzchar(v), NA_character_, v)
    gkey <- function(w, c) paste(w, ifelse(is.na(c), "", c), sep = "\r")
    resolved <- unique(nm[!is.na(nm$taxon_id) & grepl("^\\S+ \\S+$", nm$name_clean), c("name_clean", "taxon_id", "context"), drop = FALSE])
    resolved$context <- ctx_of(resolved$context)
    kingdom_of_id <- function(id) { pp <- .path_in_taxa(id, taxa); .kingdom_of_path(pp$path, pp$ranks) }
    bu <- un[grepl("^\\S+ \\S+$", nm$name_clean[un])]
    grp <- unique(data.frame(word = gen_of(nm$name_clean[bu]), ctx = ctx_of(nm$context[bu]), stringsAsFactors = FALSE))
    gid <- stats::setNames(rep(NA_character_, nrow(grp)), gkey(grp$word, grp$ctx))
    gt <- unique(taxa[taxa$rank %in% "genus", c("taxon_id", "name"), drop = FALSE])
    ask <- integer(0L)
    for (k in seq_len(nrow(grp))) {
      cand <- unique(gt$taxon_id[gt$name == grp$word[k]])
      if (!length(cand)) { ask <- c(ask, k); next }
      keep <- cand[!vapply(cand, function(id) { pp <- .path_in_taxa(id, taxa); .genus_conflicts_context(grp$ctx[k], pp$path, pp$ranks) }, TRUE)]
      if (length(keep) == 1L) { gid[k] <- keep; next }
      if (length(keep) >= 2L) {
        genus_homonym_unresolved[[length(genus_homonym_unresolved) + 1L]] <- data.frame(genus_word = grp$word[k], context = grp$ctx[k],
          candidates = paste(sort(keep), collapse = " | "), stringsAsFactors = FALSE)
        next
      }
      ask <- c(ask, k)                                   # every row in taxa contradicts the context: ask, with it
    }
    if (length(ask)) {
      g <- lookup(grp$word[ask], rep("genus", length(ask)), grp$ctx[ask])
      .check_lookup_shape(g, length(ask), "genus lookup")
      okg <- g$matched %in% TRUE & tolower(g$matched_rank) %in% "genus" & !is.na(g$current_record_id)
      nonexact <- tolower(g$match_type) %in% c("fuzzy", "partialfuzzy", "partialfuzzyspecies")
      for (j in which(okg)) {
        k <- ask[j]; has_ctx <- !is.na(grp$ctx[k])
        reason <- if (nonexact[j] && !.genus_answer_in_context(grp$ctx[k], g$classification_path[j], g$classification_ranks[j])) {
          if (has_ctx) "lineage does not agree at kingdom and phylum" else "no lineage context"
        } else if (!nonexact[j] && .genus_conflicts_context(grp$ctx[k], g$classification_path[j], g$classification_ranks[j])) {
          "exact genus answer outside the names' kingdom/phylum"
        } else NA_character_
        if (!is.na(reason)) {
          okg[j] <- FALSE
          genus_variant_rejected[[length(genus_variant_rejected) + 1L]] <- data.frame(
            genus_word = grp$word[k], answer = g$matched_name[j], answer_id = paste0(prefix, ":", g$current_record_id[j]),
            answer_path = g$classification_path[j], context = grp$ctx[k], reason = reason,
            pass = "genus", query = grp$word[k], stringsAsFactors = FALSE)
        }
      }
      gid[ask[okg]] <- paste0(prefix, ":", g$current_record_id[okg])
      for (j in which(okg)) {
        a <- .ancestor_rows(g$classification_path[j], g$classification_ranks[j], g$classification_ids[j],
                            prefix, g$entry_date[j] %||% NA_character_)
        if (!is.null(a)) taxa <- rbind(taxa, a)
      }
    }
    for (i in un) {
      x <- nm$name_clean[i]; cx <- ctx_of(nm$context[i])
      if (grepl("^\\S+ \\S+$", x)) {
        if (!nm$status[i] %in% "homonym_rejected") {
          cong <- resolved[gen_of(resolved$name_clean) == gen_of(x) & resolved$name_clean != x &
                             .epithet_stem(ep_of(resolved$name_clean)) == .epithet_stem(ep_of(x)), , drop = FALSE]
          same <- if (is.na(cx)) is.na(cong$context) else
            (cong$context %in% cx) | vapply(cong$taxon_id, function(id) isTRUE(kingdom_of_id(id) %in% .kingdoms_of_context(cx)), TRUE)
          hit <- unique(cong$taxon_id[same])
          if (length(hit) == 1L) {
            nm$taxon_id[i] <- hit; nm$status[i] <- "gender_variant"; nm$backend[i] <- "gender_rule"
            next
          }
        }
        g <- gid[gkey(gen_of(x), cx)]
        if (!is.na(g)) {
          nm$taxon_id[i] <- paste0("local:", sub("^[^:]+:", "", g), ":", tolower(ep_of(x)))
          taxa <- rbind(taxa, data.frame(taxon_id = nm$taxon_id[i], name = x, rank = "species", parent_id = unname(g),
                                         snapshot = NA_character_, local = TRUE, stringsAsFactors = FALSE))
          if (is.na(nm$status[i])) nm$status[i] <- "unresolved_local"
          next
        }
      }
      nm$taxon_id[i] <- paste0("local:", x)
      taxa <- rbind(taxa, data.frame(taxon_id = nm$taxon_id[i], name = x, rank = nm$rank_given[i] %||% NA_character_,
                                     parent_id = nm$fallback_parent[i], snapshot = NA_character_, local = TRUE, stringsAsFactors = FALSE))
      if (is.na(nm$status[i])) nm$status[i] <- "unresolved_local"
    }
  }

  # --- taxa: one row per id; a second, DIFFERENT description of an id is a conflict ---
  key <- paste(taxa$taxon_id, taxa$name, taxa$rank, taxa$parent_id, sep = "\r")
  taxa <- taxa[!duplicated(key), , drop = FALSE]
  conflicts <- taxa[taxa$taxon_id %in% taxa$taxon_id[duplicated(taxa$taxon_id)], , drop = FALSE]
  taxa <- taxa[!duplicated(taxa$taxon_id), , drop = FALSE]
  # an id the lookup gave no path for (or a pool key it never described) still needs a row,
  # named by the lookup's ACCEPTED name for that id -- never by whichever verbatim name
  # happened to arrive first, which may be a synonym and would make the accepted name
  # look like an undeclared second name. The verbatim name only when there is none.
  miss <- setdiff(stats::na.omit(nm$taxon_id), taxa$taxon_id)
  if (length(miss)) {
    acc <- nm[!is.na(nm$accepted_lookup), c("taxon_id", "accepted_lookup"), drop = FALSE]
    nm_miss <- acc$accepted_lookup[match(miss, acc$taxon_id)]
    nm_miss[is.na(nm_miss)] <- nm$name_clean[match(miss[is.na(nm_miss)], nm$taxon_id)]
    taxa <- rbind(taxa, data.frame(taxon_id = miss, name = nm_miss, rank = NA_character_,
                                   parent_id = NA_character_, snapshot = NA_character_, local = FALSE, stringsAsFactors = FALSE))
  }
  taxa$authority <- ifelse(taxa$local, "run-local", prefix)
  rownames(taxa) <- NULL; rownames(nm) <- NULL

  snaps <- sort(unique(stats::na.omit(taxa$snapshot)))
  structure(list(
    taxa = taxa, names = nm,
    meta = list(run_id = run_id, key_backbone_id = key_backbone_id, authority = prefix,
                snapshot = if (length(snaps)) paste(snaps, collapse = ",") else NA_character_,
                frozen = FALSE, digest = NA_character_, built_at = Sys.time(),
                taxa_conflicts = conflicts, pool_key_ambiguous = pool_key_ambiguous, pool_key_tiebreaks = pool_key_tiebreaks,
                genus_variant_rejected = if (length(gvr_all <- c(bin_variant_rejected, genus_variant_rejected))) unique(do.call(rbind, gvr_all)) else NULL,
                genus_homonym_unresolved = if (length(genus_homonym_unresolved)) unique(do.call(rbind, genus_homonym_unresolved)) else NULL)
  ), class = "taxon_registry")
}

#' @export
print.taxon_registry <- function(x, ...) {
  cat(sprintf("<taxon_registry> run %s | key authority %s (snapshot %s) | %s\n", x$meta$run_id, x$meta$authority,
              x$meta$snapshot, if (isTRUE(x$meta$frozen)) paste("FROZEN", x$meta$digest) else "not frozen"))
  cat(sprintf("  taxa %d (run-local %d) | names %d from %d table(s)\n", nrow(x$taxa), sum(x$taxa$local),
              nrow(x$names), length(unique(x$names$source_table))))
  st <- table(x$names$status, useNA = "ifany"); cat("  status:", paste(names(st), st, sep = " ", collapse = "; "), "\n")
  u <- function(s) length(unique(x$names$verbatim_name[x$names$status %in% s]))
  cat(sprintf("  lookup FAILED (no answer; not resolved, not local): %d name(s) | answered but unresolved (local ids): %d | answered above species (rank_fallback): %d | fuzzy rejected: %d\n",
              u("lookup_failed"), u("unresolved_local"), u("rank_fallback"), u("fuzzy_rejected")))
  invisible(x)
}

#' Freeze a taxon registry before the first join
#'
#' After the freeze the registry cannot grow: a name it does not hold is an
#' error at \code{\link{attach_taxon_ids}}, never a new row. The freeze records
#' the registry's content digest, which every stamp carries, so tables stamped
#' from one frozen registry can be joined and tables from any other cannot.
#'
#' @param registry A \code{taxon_registry} from \code{\link{build_taxon_registry}}.
#' @return The registry, frozen.
#' @export
freeze_taxon_registry <- function(registry) {
  if (!inherits(registry, "taxon_registry")) stop("`registry` must be a taxon_registry.")
  if (isTRUE(registry$meta$frozen)) return(registry)
  registry$meta$frozen <- TRUE
  registry$meta$digest <- .cache_hash(list(registry$taxa, registry$names[, setdiff(names(registry$names), "built_at")],
                                           registry$meta$run_id, registry$meta$authority))
  registry
}

#' @noRd
.registry_stamp <- function(registry) {
  list(run_id = registry$meta$run_id, authority = registry$meta$authority, digest = registry$meta$digest)
}

#' Attach registry taxon identifiers to a table
#'
#' Adds a \code{taxon_id} column to \code{x} by looking up each row's verbatim
#' name, as registered for \code{source_table}, in a FROZEN registry, and stamps
#' the table with the registry's identity. The verbatim name column is left
#' untouched. A name the registry does not hold for that table is an error:
#' after the freeze nothing is resolved on the fly.
#'
#' @param x A data frame.
#' @param registry A frozen \code{taxon_registry}.
#' @param name_col Column of \code{x} holding the verbatim name.
#' @param source_table The \code{source_table} label the names were registered
#'   under.
#' @param context_col \code{NULL} or the column of \code{x} holding the context
#'   each name was registered with; needed only when one name was registered
#'   under several contexts for this table.
#' @return \code{x} with \code{taxon_id}, stamped.
#' @export
attach_taxon_ids <- function(x, registry, name_col, source_table, context_col = NULL) {
  if (!inherits(registry, "taxon_registry")) stop("`registry` must be a taxon_registry.")
  if (!isTRUE(registry$meta$frozen)) stop("Freeze the registry (freeze_taxon_registry()) before attaching ids: a registry that can still grow gives tables stamped from different contents.")
  if (!is.data.frame(x) || !name_col %in% names(x)) stop("`name_col` must name a column of `x`.")
  # A taxon_id column this registry did not stamp belongs to someone else (e.g. iNaturalist's numeric
  # taxon ids in check_inat_range() output): overwriting it would silently change what the column means.
  if ("taxon_id" %in% names(x) && !identical(attr(x, .REGISTRY_STAMP, exact = TRUE), .registry_stamp(registry))) {
    stop("`x` already has a taxon_id column that this registry did not stamp (another source's ids?); rename it before attaching registry ids.")
  }
  n <- registry$names[registry$names$source_table == source_table, , drop = FALSE]
  if (!nrow(n)) stop(sprintf("The registry holds no names for source_table '%s'.", source_table))
  v <- as.character(x[[name_col]])
  if (is.null(context_col)) {
    amb <- unique(n$verbatim_name[duplicated(n$verbatim_name) &
                                  vapply(n$verbatim_name, function(z) length(unique(n$taxon_id[n$verbatim_name == z])) > 1L, TRUE)])
    if (length(amb) && any(v %in% amb)) {
      stop(sprintf("Name(s) registered under several contexts with different ids for '%s' (e.g. %s); supply `context_col`.",
                   source_table, paste(utils::head(amb, 3), collapse = ", ")))
    }
    id <- n$taxon_id[match(v, n$verbatim_name)]
  } else {
    id <- n$taxon_id[match(paste(v, x[[context_col]], sep = "\r"), paste(n$verbatim_name, n$context, sep = "\r"))]
  }
  bad <- !is.na(v) & nzchar(v) & is.na(id)
  lf <- bad & v %in% n$verbatim_name[n$status %in% "lookup_failed"]
  if (any(lf)) {
    stop(sprintf("%d name(s) in '%s' had a FAILED lookup when the registry was built (e.g. %s): no id was assigned. Rebuild the registry once the service answers.",
                 length(unique(v[lf])), source_table, paste(utils::head(unique(v[lf]), 3), collapse = ", ")))
  }
  if (any(bad)) {
    stop(sprintf("%d name(s) in '%s' are not in the frozen registry (e.g. %s): register them before the freeze.",
                 length(unique(v[bad])), source_table, paste(utils::head(unique(v[bad]), 3), collapse = ", ")))
  }
  x$taxon_id <- id
  attr(x, .REGISTRY_STAMP) <- .registry_stamp(registry)
  x
}

#' @noRd
.check_stamp <- function(x, arg) {
  s <- attr(x, .REGISTRY_STAMP, exact = TRUE)
  if (is.null(s)) {
    stop(sprintf("`%s` carries no taxon-registry stamp (it was never passed through attach_taxon_ids(), or an operation dropped its attributes). Re-stamp it; a join on an unstamped table is refused.", arg))
  }
  if (!"taxon_id" %in% names(x)) stop(sprintf("`%s` has no taxon_id column.", arg))
  s
}

#' Join two tables on registry taxon identifiers only
#'
#' The one join helper. Both tables must carry the stamp of the same frozen
#' registry (\code{\link{attach_taxon_ids}}); an unstamped table, or one
#' stamped from another registry, is an error. The join is on \code{taxon_id}
#' plus \code{extra_by}, and \code{extra_by} may not name a taxon-name or
#' lineage column. Every call reports the rows on each side with no partner,
#' so a lost fallback shows up as a number.
#'
#' @param x,y Stamped data frames.
#' @param type One of \code{"left"}, \code{"inner"}, \code{"anti"}, \code{"semi"}.
#' @param extra_by Further join columns (e.g. \code{"grid_id"}), never names.
#' @param verbose Print the no-partner counts. Default \code{TRUE}.
#' @return The joined table, stamped, with attribute \code{"no_partner"}
#'   (\code{x_rows}, \code{y_rows}).
#' @export
join_by_taxon <- function(x, y, type = c("left", "inner", "anti", "semi"), extra_by = NULL, verbose = TRUE) {
  type <- match.arg(type)
  sx <- .check_stamp(x, "x"); sy <- .check_stamp(y, "y")
  if (!identical(sx, sy)) {
    stop(sprintf("`x` and `y` are stamped by different registries (x: %s/%s, y: %s/%s); one run, one registry.",
                 sx$run_id, sx$digest, sy$run_id, sy$digest))
  }
  bad <- intersect(extra_by, .NAME_COLUMNS)
  bad <- c(bad, grep("_ncbi$|_name$", extra_by, value = TRUE))
  if (length(bad)) stop(sprintf("`extra_by` names taxon-name or lineage column(s) (%s): join on taxon_id only.", paste(unique(bad), collapse = ", ")))
  by <- c("taxon_id", extra_by)
  # An NA taxon_id (an unnamed or blank row) is no taxon: it never matches another NA (na_matches = "never", as
  # taxon_in() treats NA), and a row with an NA key always counts as having no partner.
  kx <- do.call(paste, c(lapply(by, function(b) x[[b]]), sep = "\r"))
  ky <- do.call(paste, c(lapply(by, function(b) y[[b]]), sep = "\r"))
  nax <- is.na(x$taxon_id); nay <- is.na(y$taxon_id)
  np <- c(x_rows = sum(nax | !kx %in% ky[!nay]), y_rows = sum(nay | !ky %in% kx[!nax]))
  out <- switch(type,
                left = dplyr::left_join(x, y, by = by, relationship = "many-to-many", na_matches = "never"),
                inner = dplyr::inner_join(x, y, by = by, relationship = "many-to-many", na_matches = "never"),
                anti = dplyr::anti_join(x, y, by = by, na_matches = "never"),
                semi = dplyr::semi_join(x, y, by = by, na_matches = "never"))
  if (verbose) message(sprintf("join_by_taxon (%s on %s): %d row(s) of x and %d row(s) of y have no partner.",
                               type, paste(by, collapse = "+"), np[["x_rows"]], np[["y_rows"]]))
  attr(out, .REGISTRY_STAMP) <- sx
  attr(out, "no_partner") <- np
  out
}

#' Membership by registry taxon identifier
#'
#' The identifier form of \code{\%in\%}: "is this taxon already a candidate?",
#' asked of ids, never of names. \code{NA} is never a member.
#'
#' @param ids Character vector of taxon identifiers.
#' @param set Character vector of taxon identifiers.
#' @return Logical, one per \code{ids}.
#' @export
taxon_in <- function(ids, set) {
  if (!is.character(ids) || !is.character(set)) stop("`ids` and `set` must be character vectors of taxon ids.")
  !is.na(ids) & ids %in% set[!is.na(set)]
}

#' The ancestor of each taxon at a given rank
#'
#' Walks \code{parent_id} up the registry's own tree, so ring scope and genus
#' fallback read one tree, never a table's own genus or family column.
#'
#' @param ids Character vector of taxon identifiers.
#' @param rank Rank to return, e.g. \code{"genus"} or \code{"family"}.
#' @param registry A \code{taxon_registry}.
#' @return Character vector of taxon identifiers (\code{NA} where the walk does
#'   not reach that rank). A taxon AT \code{rank} returns itself.
#' @export
parent_at <- function(ids, rank, registry) {
  if (!inherits(registry, "taxon_registry")) stop("`registry` must be a taxon_registry.")
  t <- registry$taxa; rank <- tolower(rank)
  par <- stats::setNames(t$parent_id, t$taxon_id); rk <- stats::setNames(t$rank, t$taxon_id)
  vapply(ids, function(id) {
    seen <- 0L
    while (!is.na(id) && seen < 100L) {
      if (identical(unname(rk[id]), rank)) return(id)
      id <- unname(par[id]); seen <- seen + 1L
    }
    NA_character_
  }, character(1L), USE.NAMES = FALSE)
}

#' Check a taxon registry and the tables stamped from it
#'
#' The guard. It reports, per table: taxa held under two or more verbatim names
#' (expected for input tables, and the baseline a run is compared against);
#' names that map to two or more taxa; unresolved and run-local names; the
#' \strong{merge audit}: every taxon identifier reached by two or more
#' different names, each with the relationship its backend declared, and an
#' error-class finding where none was declared (a fuzzy match onto another
#' name's taxon, a pool key that disagrees with the lookup); conflicting
#' descriptions of one identifier; and, for stamped tables, a missing stamp, the
#' same taxon twice in one observation (by \code{taxon_id} and
#' \code{hypothesis_type}), and table lineage columns that disagree with the
#' registry's tree. The registry's tree is the authority: a family or order
#' column that disagrees is another classification of the same taxon, listed
#' as \code{lineage_concept_differs} (info); a genus column that disagrees is
#' \code{lineage_disagrees} (error), unless the table's genus is the genus word
#' of a name registered as a synonym of that taxon (info).
#'
#' @param registry A \code{taxon_registry}.
#' @param tables Named list of data frames to check (optional).
#' @param mode \code{"report"} (default): return the findings. \code{"error"}:
#'   stop if any error-class finding exists.
#' @param verbose Print a summary. Default \code{TRUE}.
#' @return A data frame of findings: \code{severity} (\code{"error"} or
#'   \code{"info"}), \code{kind}, \code{table}, \code{taxon_id}, \code{names},
#'   \code{detail}, \code{n}.
#' @export
check_taxon_registry <- function(registry, tables = list(), mode = c("report", "error"), verbose = TRUE) {
  mode <- match.arg(mode)
  if (!inherits(registry, "taxon_registry")) stop("`registry` must be a taxon_registry.")
  out <- list()
  add <- function(sev, kind, table, id, names, detail, n) {
    out[[length(out) + 1L]] <<- data.frame(severity = sev, kind = kind, table = table, taxon_id = id, names = names,
                                           detail = detail, n = as.integer(n), stringsAsFactors = FALSE)
  }
  nm <- registry$names
  # taxa under 2+ names, per source table (baseline)
  for (tb in sort(unique(nm$source_table))) {
    z <- nm[nm$source_table == tb & !is.na(nm$taxon_id), , drop = FALSE]
    for (id in unique(z$taxon_id[duplicated(z$taxon_id)])) {
      v <- sort(unique(z$verbatim_name[z$taxon_id == id]))
      if (length(v) > 1L) add("info", "taxon_under_2plus_names", tb, id, paste(v, collapse = " | "),
                              paste(sort(unique(z$status[z$taxon_id == id])), collapse = "/"), length(v))
    }
    # name -> 2+ taxa within a table
    for (v in unique(z$verbatim_name[duplicated(z$verbatim_name)])) {
      ids <- unique(z$taxon_id[z$verbatim_name == v])
      if (length(ids) > 1L) add("error", "name_to_2plus_taxa", tb, paste(ids, collapse = " | "), v,
                                paste("contexts:", paste(unique(z$context[z$verbatim_name == v]), collapse = " / ")), length(ids))
    }
  }
  # unresolved and gender variants
  for (s in c("unresolved_local", "gender_variant", "genus_variant", "rank_fallback", "fuzzy_rejected", "homonym_rejected", "lookup_failed")) {
    z <- nm[nm$status %in% s, , drop = FALSE]
    if (nrow(z)) add(if (s == "lookup_failed") "error" else "info", s, NA_character_, NA_character_, paste(utils::head(sort(unique(z$verbatim_name)), 200), collapse = " | "),
                     sprintf("%d name(s)", length(unique(z$verbatim_name))), length(unique(z$verbatim_name)))
  }
  # merge audit: ids reached by 2+ different CLEAN names
  z <- nm[!is.na(nm$taxon_id), , drop = FALSE]
  declared <- c("accepted", "synonym", "gender_variant", "genus_variant", "pool_key_only", "pool_key_tiebreak")
  for (id in unique(z$taxon_id)) {
    w <- z[z$taxon_id == id, , drop = FALSE]
    if (length(unique(w$name_clean)) < 2L) next
    undeclared <- w$name_clean[!w$status %in% declared]
    # an "accepted" name is declared only if it IS the taxon's own name; a second accepted
    # name on one id has no stated relationship to it
    acc <- unique(w$name_clean[w$status %in% "accepted"])
    own <- registry$taxa$name[match(id, registry$taxa$taxon_id)]
    if (length(acc) > 1L || (length(acc) == 1L && !is.na(own) && acc != own)) undeclared <- c(undeclared, acc[acc != own])
    rel <- paste(sprintf("%s=%s", w$name_clean, w$status), collapse = "; ")
    if (length(undeclared)) {
      add("error", "undeclared_merge", NA_character_, id, paste(sort(unique(w$name_clean)), collapse = " | "), rel, length(unique(w$name_clean)))
    } else {
      add("info", "declared_merge", NA_character_, id, paste(sort(unique(w$name_clean)), collapse = " | "), rel, length(unique(w$name_clean)))
    }
  }
  pkc <- nm[nm$status %in% "pool_key_conflict", , drop = FALSE]
  if (nrow(pkc)) add("error", "pool_key_conflict", NA_character_, paste(unique(pkc$taxon_id), collapse = " | "),
                     paste(unique(pkc$verbatim_name), collapse = " | "), "lookup's accepted record differs from the pool's key", nrow(pkc))
  # a name the pool holds under 2+ keys: not keyed from the pool, and not silently given one of them
  pka <- registry$meta$pool_key_ambiguous
  if (!is.null(pka) && nrow(pka)) {
    for (i in seq_len(nrow(pka))) add("error", "pool_key_ambiguous", NA_character_, pka$species_keys[i], pka$verbatim_name[i],
                                      if (isTRUE(pka$in_names[i])) "pool holds this name under 2+ keys; id from the lookup only"
                                      else "pool holds this name under 2+ keys; name not in the registered tables", 1L)
  }
  # non-exact genus answers refused by the lineage gate: the names under them kept plain local ids
  gvr <- registry$meta$genus_variant_rejected
  if (!is.null(gvr) && nrow(gvr)) {
    for (i in seq_len(nrow(gvr))) add("info", "genus_variant_rejected", NA_character_, gvr$answer_id[i], gvr$query[i] %||% gvr$genus_word[i],
                                      sprintf("%s pass; answer %s (%s): %s", gvr$pass[i] %||% "genus", gvr$answer[i], gvr$answer_path[i], gvr$reason[i]), 1L)
  }
  # a genus word naming 2+ genera in taxa, with no context to choose: the names under it kept plain local ids
  ghu <- registry$meta$genus_homonym_unresolved
  if (!is.null(ghu) && nrow(ghu)) {
    for (i in seq_len(nrow(ghu))) add("info", "genus_homonym_unresolved", NA_character_, ghu$candidates[i], ghu$genus_word[i],
                                      sprintf("genus word names 2+ genera (%s); context %s", ghu$candidates[i], if (is.na(ghu$context[i])) "none" else ghu$context[i]), 1L)
  }
  # tie-break outcomes: a decided name is listed (info) with the authority that decided; an undecided one keeps
  # its error-class pool_key_ambiguous / pool_key_conflict finding above, and the reason is listed here
  tbk <- registry$meta$pool_key_tiebreaks
  if (!is.null(tbk) && nrow(tbk)) {
    for (i in seq_len(nrow(tbk))) add("info", if (is.na(tbk$chosen[i])) "pool_key_tiebreak_undecided" else "pool_key_tiebroken",
                                      NA_character_, if (is.na(tbk$chosen[i])) tbk$candidates[i] else tbk$chosen[i], tbk$verbatim_name[i],
                                      sprintf("%s; candidates %s; %s", tbk$kind[i], tbk$candidates[i],
                                              if (is.na(tbk$by[i])) tbk$detail[i] else paste0("decided by ", tbk$by[i], ": ", tbk$detail[i])), 1L)
  }
  tc <- registry$meta$taxa_conflicts
  if (!is.null(tc) && nrow(tc)) {
    for (id in unique(tc$taxon_id)) add("error", "taxon_described_twice", NA_character_, id,
                                        paste(unique(tc$name[tc$taxon_id == id]), collapse = " | "),
                                        paste(unique(paste(tc$rank, tc$parent_id)[tc$taxon_id == id]), collapse = " / "), sum(tc$taxon_id == id))
  }
  # stamped tables
  stamp <- if (isTRUE(registry$meta$frozen)) .registry_stamp(registry) else NULL
  for (tn in names(tables)) {
    x <- tables[[tn]]
    s <- attr(x, .REGISTRY_STAMP, exact = TRUE)
    if (is.null(s) || !"taxon_id" %in% names(x)) { add("error", "missing_stamp", tn, NA_character_, NA_character_, "table not passed through attach_taxon_ids()", nrow(x)); next }
    if (!is.null(stamp) && !identical(s, stamp)) add("error", "foreign_stamp", tn, NA_character_, NA_character_, sprintf("stamped by %s/%s", s$run_id, s$digest), nrow(x))
    if ("observation_id" %in% names(x)) {
      k <- paste(x$observation_id, x$taxon_id, if ("hypothesis_type" %in% names(x)) x$hypothesis_type else "", sep = "\r")
      d <- duplicated(k) & !is.na(x$taxon_id)
      if (any(d)) add("error", "taxon_twice_in_observation", tn, paste(utils::head(unique(x$taxon_id[d]), 20), collapse = " | "), NA_character_,
                      sprintf("%d observation(s)", length(unique(x$observation_id[d]))), sum(d))
    }
    # The registry's tree is the authority. A table that files a taxon under another FAMILY or ORDER uses another
    # classification of the same taxon: listed (info, lineage_concept_differs), not flagged. A GENUS that disagrees
    # means the name may be another taxon (error, lineage_disagrees) -- unless the table's genus is the genus word of a
    # name registered as a SYNONYM of that taxon (the table carries the synonym's own genus): listed as info.
    syn <- nm[nm$status %in% c("synonym", "genus_variant") & !is.na(nm$taxon_id), , drop = FALSE]
    syn_key <- paste(syn$taxon_id, sub(" .*$", "", syn$name_clean), sep = "\r")
    for (rk in intersect(c("genus", "family", "order"), names(x))) {
      anc <- parent_at(x$taxon_id, rk, registry)
      reg_name <- registry$taxa$name[match(anc, registry$taxa$taxon_id)]
      dis <- !is.na(reg_name) & !is.na(x[[rk]]) & as.character(x[[rk]]) != reg_name
      info <- if (rk == "genus") dis & paste(x$taxon_id, as.character(x[[rk]]), sep = "\r") %in% syn_key else dis
      for (lv in c("info", "error")) {
        w <- if (lv == "info") info else dis & !info
        if (!any(w)) next
        add(lv, if (lv == "info") "lineage_concept_differs" else "lineage_disagrees", tn,
            paste(utils::head(unique(x$taxon_id[w]), 20), collapse = " | "),
            paste(utils::head(unique(sprintf("%s: table %s, registry %s", rk, x[[rk]][w], reg_name[w])), 10), collapse = "; "),
            if (rk == "genus" && lv == "info") "genus column; the table's genus is a declared synonym's or genus variant's" else sprintf("%s column", rk), sum(w))
      }
    }
  }
  res <- if (length(out)) do.call(rbind, out) else
    data.frame(severity = character(0), kind = character(0), table = character(0), taxon_id = character(0),
               names = character(0), detail = character(0), n = integer(0), stringsAsFactors = FALSE)
  if (verbose) {
    tab <- table(paste(res$severity, res$kind))
    message(sprintf("check_taxon_registry (%s): %d finding(s)%s", mode, nrow(res),
                    if (length(tab)) paste0(": ", paste(names(tab), tab, sep = " ", collapse = "; ")) else ""))
  }
  if (mode == "error" && any(res$severity == "error")) {
    stop(sprintf("check_taxon_registry: %d error-class finding(s): %s", sum(res$severity == "error"),
                 paste(unique(res$kind[res$severity == "error"]), collapse = ", ")))
  }
  res
}
