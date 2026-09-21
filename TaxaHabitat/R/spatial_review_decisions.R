# ==============================================================================
# spatial_review_decisions.R
# TaxaHabitat -- persist and re-apply a reviewer's spatial-flag decisions
#
# Exported:
#   save_spatial_review_decisions
#   apply_spatial_review_decisions
#
# review_spatial_flags() is an interactive gadget whose output -- which flagged
# points a reviewer confirmed, dismissed, or moved to another habitat -- is a
# human decision, not a computed intermediate. Without persistence, every
# production workflow run would re-open the gadget and overwrite the previous
# decisions. These two helpers keep one small table per site, keyed on
# point_id (TaxaFetch::stack_occurrences() builds point_id from the
# coordinates, so it is stable across runs), and let a workflow open the
# gadget only for flagged points that carry no decision yet.
# ==============================================================================

# A decisions file is not user-facing data -- it is only ever written by
# save_spatial_review_decisions() and read back by itself and by
# apply_spatial_review_decisions(). A file that is not a data frame, or is
# missing a column either function relies on, is either corrupt, from an
# incompatible package version, or accidentally overwritten by something
# else writing to the same path. Reading it with a bare readRDS() degrades
# to a cryptic base-R error (or, for a data frame missing just `point_id`,
# no error at all -- every point silently reads as undecided). Route both
# functions through this validator instead, so a bad file fails loudly and
# names what is wrong.
#
# `taxon_name` is intentionally NOT required: every decisions file saved
# before this validator existed lacks it (it keyed decisions on `point_id`
# alone). Its presence is how the two functions tell an old-format file
# from a new one -- see the (point_id, taxon_name) key discussion in
# apply_spatial_review_decisions().
.decisions_required_cols <- c(
  point_id           = "character",
  spatial_flag       = "character",
  main_habitat       = "character",
  decided_at         = "character",
  habitat_reassigned = "logical"
)

# Strips a leading "reviewer decision (TIMESTAMP); auto: " marker (possibly
# several, if a file written before this fix already compounded them) so a
# fresh marker can be prepended without ever growing without bound.
# apply_spatial_review_decisions() calls this before every rewrite, which is
# what makes calling it twice on the same data idempotent -- see D3.
.strip_decision_marker <- function(x) {
  pat <- "^reviewer decision \\([^()]*\\); auto: "
  for (i in seq_len(50L)) {
    y <- sub(pat, "", x)
    if (identical(y, x)) break
    x <- y
  }
  x
}

.read_decisions_file <- function(path, caller) {
  if (!file.exists(path)) return(NULL)
  dec <- readRDS(path)
  if (!is.data.frame(dec)) {
    stop(sprintf(
      paste0("%s: decisions file '%s' is not a data frame (found class %s). ",
             "It may be corrupt, from an incompatible source, or overwritten ",
             "by something else writing to this path."),
      caller, path, paste(class(dec), collapse = "/")
    ), call. = FALSE)
  }
  missing_cols <- setdiff(names(.decisions_required_cols), names(dec))
  if (length(missing_cols) > 0L) {
    stop(sprintf(
      "%s: decisions file '%s' is missing required column(s): %s.",
      caller, path, paste(missing_cols, collapse = ", ")
    ), call. = FALSE)
  }
  bad_type <- character(0)
  for (cc in names(.decisions_required_cols)) {
    want <- .decisions_required_cols[[cc]]
    ok <- switch(want,
      character = is.character(dec[[cc]]) || is.factor(dec[[cc]]),
      logical   = is.logical(dec[[cc]]),
      TRUE
    )
    if (!ok) {
      bad_type <- c(bad_type, sprintf("'%s' (expected %s, found %s)", cc, want, class(dec[[cc]])[1]))
    }
  }
  if ("taxon_name" %in% names(dec) && !(is.character(dec$taxon_name) || is.factor(dec$taxon_name))) {
    bad_type <- c(bad_type, sprintf("'taxon_name' (expected character, found %s)", class(dec$taxon_name)[1]))
  }
  if (length(bad_type) > 0L) {
    stop(sprintf(
      "%s: decisions file '%s' has column(s) with the wrong type: %s.",
      caller, path, paste(bad_type, collapse = "; ")
    ), call. = FALSE)
  }
  dec
}

#' Save a reviewer's spatial-flag decisions
#'
#' Extracts one row per \code{(point_id, taxon_name)} from
#' \code{review_spatial_flags()}'s output -- the reviewed \code{spatial_flag}
#' and \code{main_habitat} -- and merges it into the decisions file at
#' \code{path} (a newer decision for the same point/taxon replaces the older
#' one).
#'
#' @section Why the key includes \code{taxon_name}:
#' \code{point_id} identifies a coordinate, not an occurrence record -- it is
#' routine for several taxa to share one in an eDNA occurrence table (a gull
#' and a fish detected at the same sampling point). Keying decisions on
#' \code{point_id} alone means two taxa at the same point can carry genuinely
#' different \code{spatial_flag}/\code{main_habitat} values, and a decision
#' saved for one would silently overwrite the file's only record for that
#' point -- discarding whichever taxon's row was not kept. Decisions are
#' therefore keyed on \code{(point_id, taxon_name)}. When \code{reviewed} has
#' no \code{taxon_col} column, every decision's \code{taxon_name} is recorded
#' as \code{NA} (an old-format, point-level decision); see
#' \code{\link{apply_spatial_review_decisions}} for how such a decision is
#' applied safely.
#'
#' @param reviewed Data frame returned by \code{\link{review_spatial_flags}}
#'   (must carry \code{point_id}, \code{spatial_flag}, \code{main_habitat};
#'   \code{taxon_name} is used when present, see Details).
#' @param path Character. The \code{.rds} decisions file, one per site.
#' @param before Optional data frame: the table the gadget was opened on
#'   (\code{flag_habitat_inconsistencies()}'s output). When supplied, a
#'   point's habitat is recorded as a reviewer REASSIGNMENT only where it
#'   differs from \code{before}; otherwise the habitat is treated as the
#'   automatic assignment of the day and is NOT frozen for later runs.
#'   \strong{Without \code{before}, this function cannot tell an automatic
#'   habitat from a reviewer reassignment at all}: every non-\code{NA}
#'   \code{main_habitat} in \code{reviewed} is recorded as a reassignment
#'   (the conservative reading) and will be re-applied VERBATIM by
#'   \code{\link{apply_spatial_review_decisions}} on every later run --
#'   freezing that point's habitat at whatever the automatic classifier
#'   happened to say the day it was reviewed, even if the classifier's own
#'   logic later changes for the better. Pass \code{before} whenever the
#'   pre-review table is available to avoid this. Matched on
#'   \code{(point_id, taxon_name)} when \code{before} carries \code{taxon_col}
#'   too, otherwise on \code{point_id} alone.
#' @param point_id_col,flag_col,habitat_col Column names. Defaults match
#'   \code{review_spatial_flags()}'s output.
#' @param taxon_col Character. Name of the taxon column in \code{reviewed}
#'   (and, if present, \code{before}). Default \code{"taxon_name"}. Absent
#'   from \code{reviewed}, every saved decision's \code{taxon_name} is
#'   \code{NA} -- see Details.
#' @return Invisibly, the merged decisions table (\code{point_id},
#'   \code{taxon_name}, \code{spatial_flag}, \code{main_habitat},
#'   \code{habitat_reassigned}, \code{decided_at}).
#' @seealso \code{\link{apply_spatial_review_decisions}}
#' @export
#'
#' @examples
#' before <- data.frame(
#'   point_id     = c("p1", "p2"),
#'   taxon_name   = c("Sebastes mystinus", "Larus occidentalis"),
#'   main_habitat = c("Marine", "Terrestrial"),
#'   spatial_flag = c("questionable", "likely")
#' )
#'
#' # `reviewed` is normally review_spatial_flags()'s return value; a plain
#' # data frame with the reviewer's updated columns works the same way.
#' reviewed <- before
#' reviewed$spatial_flag[1] <- "likely"
#'
#' path <- tempfile(fileext = ".rds")
#' decisions <- save_spatial_review_decisions(reviewed, path, before = before)
#' decisions
save_spatial_review_decisions <- function(reviewed, path, before = NULL,
                                          point_id_col = "point_id",
                                          flag_col = "spatial_flag",
                                          habitat_col = "main_habitat",
                                          taxon_col = "taxon_name") {
  if (!is.data.frame(reviewed)) stop("save_spatial_review_decisions: `reviewed` must be a data frame.", call. = FALSE)
  for (cc in c(point_id_col, flag_col, habitat_col)) {
    if (!cc %in% names(reviewed)) {
      stop(sprintf("save_spatial_review_decisions: `reviewed` has no column '%s'.", cc), call. = FALSE)
    }
  }
  if (!is.character(path) || length(path) != 1L || is.na(path)) {
    stop("save_spatial_review_decisions: `path` must be a single file path.", call. = FALSE)
  }
  has_taxon <- taxon_col %in% names(reviewed)
  new <- data.frame(
    point_id     = as.character(reviewed[[point_id_col]]),
    taxon_name   = if (has_taxon) as.character(reviewed[[taxon_col]]) else NA_character_,
    spatial_flag = as.character(reviewed[[flag_col]]),
    main_habitat = as.character(reviewed[[habitat_col]]),
    decided_at   = format(Sys.time(), "%Y-%m-%d %H:%M"),
    stringsAsFactors = FALSE
  )
  new <- new[!is.na(new$point_id) & !is.na(new$spatial_flag), , drop = FALSE]
  # Keyed on (point_id, taxon_name), not point_id alone -- see the "Why the
  # key includes taxon_name" section above (D2). Without taxon info every
  # row's taxon_name is NA, which still dedups to one row per point_id --
  # the only case there was ever decision-worthy information for.
  new <- new[!duplicated(paste(new$point_id, new$taxon_name, sep = "\x1f")), , drop = FALSE]
  if (!is.null(before)) {
    if (!is.data.frame(before) || !all(c(point_id_col, habitat_col) %in% names(before))) {
      stop(
        "save_spatial_review_decisions: `before` must be a data frame with the point_id and habitat columns.",
        call. = FALSE
      )
    }
    if (has_taxon && taxon_col %in% names(before)) {
      bkey <- paste(as.character(before[[point_id_col]]), as.character(before[[taxon_col]]), sep = "\x1f")
      nkey <- paste(new$point_id, new$taxon_name, sep = "\x1f")
      bh <- as.character(before[[habitat_col]])[match(nkey, bkey)]
    } else {
      bh <- as.character(before[[habitat_col]])[match(new$point_id, as.character(before[[point_id_col]]))]
    }
    # .is_habitat_unassigned(), not !is.na(): an "Uncertain" point is NOT a
    # reviewer reassignment, and testing NA alone would record every unplaceable
    # point as one.
    new$habitat_reassigned <- !.is_habitat_unassigned(new$main_habitat) &
      (.is_habitat_unassigned(bh) | bh != new$main_habitat)
  } else {
    new$habitat_reassigned <- !.is_habitat_unassigned(new$main_habitat)
    # Without `before` there is no way to tell a point whose habitat the
    # reviewer CHANGED from one they merely confirmed, so every non-NA
    # habitat is recorded as a reassignment and will be re-applied verbatim
    # on every later run -- freezing whatever the automatic classifier said
    # the day of the review. Warn rather than let a seeding script do this
    # silently.
    n_frozen <- sum(new$habitat_reassigned)
    if (n_frozen > 0L) {
      warning(sprintf(
        paste0(
          "save_spatial_review_decisions: `before` was not supplied, so %d point(s) with a ",
          "non-NA %s are recorded as habitat REASSIGNMENTS and will be re-applied verbatim on ",
          "every later run, freezing the automatic habitat for those points. Pass `before = ` ",
          "(the pre-review table) to record only genuine changes."
        ),
        n_frozen, habitat_col
      ), call. = FALSE)
    }
  }
  old <- .read_decisions_file(path, "save_spatial_review_decisions")
  if (is.null(old)) old <- new[0, ]
  # An old-format file (saved before this fix) has no taxon_name column at
  # all -- back-fill NA so it lines up with `new`'s key. Every old row at a
  # point_id being resaved is dropped below regardless of taxon (`new`, from
  # a full review_spatial_flags() table, already carries every taxon at
  # every touched point), which is also how an old-format point-level
  # decision gets superseded by taxon-specific ones the first time that
  # point is reviewed again.
  if (!"taxon_name" %in% names(old)) old$taxon_name <- NA_character_
  # A reassignment recorded earlier survives a later review that left it in place
  # (the gadget was opened on the already-applied table, so "unchanged" there
  # means "still the reassigned value", not "back to automatic").
  oi <- match(paste(new$point_id, new$taxon_name, sep = "\x1f"),
              paste(old$point_id, old$taxon_name, sep = "\x1f"))
  keep_old <- !is.na(oi) & old$habitat_reassigned[ifelse(is.na(oi), 1L, oi)] %in% TRUE &
    !.is_habitat_unassigned(new$main_habitat) &
    new$main_habitat == old$main_habitat[ifelse(is.na(oi), 1L, oi)]
  new$habitat_reassigned[keep_old] <- TRUE
  old <- old[!old$point_id %in% new$point_id, , drop = FALSE]
  out <- rbind(old[, names(new), drop = FALSE], new)
  rownames(out) <- NULL
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  saveRDS(out, path)
  message(sprintf("save_spatial_review_decisions: %d decision(s) saved (%d new or updated) to %s.",
                  nrow(out), nrow(new), basename(path)))
  invisible(out)
}

#' Apply saved spatial-flag decisions before (or instead of) the gadget
#'
#' Overwrites \code{spatial_flag} on every row whose \code{(point_id,
#' taxon_name)} has a saved decision (and \code{main_habitat} where the
#' decision was a reviewer reassignment), marks the reason, and reports how
#' many flagged points still need a reviewer. Call it on
#' \code{\link{flag_habitat_inconsistencies}}'s output; open
#' \code{\link{review_spatial_flags}} only when
#' \code{attr(result, "n_pending_review") > 0} (or when you deliberately want
#' to re-review). A missing decisions file is not an error: nothing is
#' applied and every flagged point is pending.
#'
#' @details
#' A saved \code{spatial_flag} and a saved reassigned \code{main_habitat} are
#' both re-applied AS-IS -- neither is re-validated against the current run's
#' own automatic classification. If the automatic classifier's logic changes
#' between the run that produced a decision and a later run, the saved
#' decision still overwrites whatever the newer automatic classification
#' would have said, silently.
#'
#' @section Old-format decisions files (no \code{taxon_name}):
#' A decisions file saved before \code{\link{save_spatial_review_decisions}}
#' started recording \code{taxon_name} has no way to say which taxon a
#' decision was for. Applying it verbatim by \code{point_id} alone would risk
#' handing one taxon's reviewer fix to a different taxon sharing the same
#' coordinates -- so instead, a decision with no recorded taxon is applied
#' \strong{only} where \code{point_id_col} identifies exactly one distinct
#' \code{taxon_col} value in \code{occurrence_data}. Where the current data
#' has more than one taxon at that point_id, \strong{nothing is applied}: the
#' point is left pending (it will reappear in \code{pending_point_ids} and in
#' \code{\link{review_spatial_flags}}), a single \code{warning()} reports how
#' many such points there are (first 20 ids), and a \code{message()} explains
#' that re-reviewing and re-saving those points writes the newer
#' \code{(point_id, taxon_name)} key, after which this function applies them
#' normally. The same rule applies to any individual decision row saved
#' without taxon information, even inside an otherwise new-format file.
#'
#' @param occurrence_data Data frame from
#'   \code{\link{flag_habitat_inconsistencies}} (carries \code{point_id},
#'   \code{spatial_flag}, \code{spatial_flag_reason}, \code{main_habitat}, and
#'   ideally \code{taxon_col} -- see Details).
#' @param path Character. The decisions file written by
#'   \code{\link{save_spatial_review_decisions}}.
#' @param point_id_col,flag_col,reason_col,habitat_col Column names.
#' @param taxon_col Character. Name of the taxon column in
#'   \code{occurrence_data}. Default \code{"taxon_name"}. Used to match a
#'   decision's saved \code{taxon_name} against the correct rows, and to
#'   detect an ambiguous point for an old-format decision (see Details).
#' @return \code{occurrence_data} with decisions applied and attributes
#'   \code{n_applied} (rows changed), \code{n_pending_review} (distinct
#'   points with at least one row whose flag is not \code{"likely"} and that
#'   was not resolved by a decision this call -- including a point left
#'   ambiguous, see Details) and \code{pending_point_ids}.
#' @seealso \code{\link{save_spatial_review_decisions}}
#' @export
#'
#' @examples
#' before <- data.frame(
#'   point_id            = c("p1", "p2"),
#'   taxon_name          = c("Sebastes mystinus", "Larus occidentalis"),
#'   main_habitat         = c("Marine", "Terrestrial"),
#'   spatial_flag         = c("questionable", "likely"),
#'   spatial_flag_reason  = c("inland marine detection", "ok")
#' )
#'
#' path <- tempfile(fileext = ".rds")
#' reviewed <- before
#' reviewed$spatial_flag[1] <- "likely"
#' save_spatial_review_decisions(reviewed, path, before = before)
#'
#' # A later run re-applies the saved decision automatically.
#' out <- apply_spatial_review_decisions(before, path)
#' out$spatial_flag
#' attr(out, "n_applied")
apply_spatial_review_decisions <- function(occurrence_data, path,
                                           point_id_col = "point_id",
                                           flag_col = "spatial_flag",
                                           reason_col = "spatial_flag_reason",
                                           habitat_col = "main_habitat",
                                           taxon_col = "taxon_name") {
  if (!is.data.frame(occurrence_data)) {
    stop("apply_spatial_review_decisions: `occurrence_data` must be a data frame.", call. = FALSE)
  }
  for (cc in c(point_id_col, flag_col, habitat_col)) {
    if (!cc %in% names(occurrence_data)) {
      stop(sprintf("apply_spatial_review_decisions: `occurrence_data` has no column '%s'.", cc), call. = FALSE)
    }
  }
  if (!is.character(path) || length(path) != 1L || is.na(path)) {
    stop("apply_spatial_review_decisions: `path` must be a single file path.", call. = FALSE)
  }
  pid <- as.character(occurrence_data[[point_id_col]])
  n_rows <- length(pid)
  dec <- .read_decisions_file(path, "apply_spatial_review_decisions")
  n_applied <- 0L
  hit <- rep(FALSE, n_rows)
  ambiguous_pids <- character(0)
  if (!is.null(dec) && nrow(dec) > 0L) {
    has_taxon_data <- taxon_col %in% names(occurrence_data)
    taxon_vals <- if (has_taxon_data) as.character(occurrence_data[[taxon_col]]) else rep(NA_character_, n_rows)
    dec_taxon <- if ("taxon_name" %in% names(dec)) as.character(dec$taxon_name) else rep(NA_character_, nrow(dec))
    known <- !is.na(dec_taxon)
    idx <- rep(NA_integer_, n_rows)

    # 1) Decisions that know their taxon: exact (point_id, taxon_name) match.
    #    A named taxon is matched precisely regardless of how many other
    #    taxa share the point -- knowing WHICH taxon removes the ambiguity.
    if (any(known) && has_taxon_data) {
      key_data <- paste(pid, taxon_vals, sep = "\x1f")
      key_dec  <- paste(dec$point_id[known], dec_taxon[known], sep = "\x1f")
      m <- match(key_data, key_dec)
      ok <- !is.na(m)
      idx[ok] <- which(known)[m[ok]]
    }

    # 2) Decisions with no recorded taxon -- an old-format file, or an
    #    individual row saved without taxon information. These can only be
    #    applied where occurrence_data has exactly ONE distinct taxon at
    #    that point_id; otherwise there is no way to tell which taxon the
    #    decision was actually about, and guessing would risk silently
    #    reassigning the wrong one's flag/habitat (D2). Ambiguous points are
    #    left pending and reported instead of guessed.
    unk <- which(!known)
    if (length(unk) > 0L) {
      dec_pid_unk <- dec$point_id[unk]
      if (has_taxon_data) {
        n_taxa_at_point <- tapply(taxon_vals, pid, function(v) length(unique(v[!is.na(v)])))
        unambiguous_pid <- names(n_taxa_at_point)[n_taxa_at_point == 1L]
      } else {
        # occurrence_data itself has no taxon column: ambiguity cannot be
        # ruled out for any point, so none of these decisions are applied.
        unambiguous_pid <- character(0)
      }
      free <- is.na(idx)
      apply_pid <- intersect(dec_pid_unk, unambiguous_pid)
      hit_unk <- free & pid %in% apply_pid
      if (any(hit_unk)) {
        m2 <- match(pid[hit_unk], dec_pid_unk)
        idx[hit_unk] <- unk[m2]
      }
      ambiguous_pids <- unique(intersect(setdiff(dec_pid_unk, unambiguous_pid), pid))
    }

    hit <- !is.na(idx)
    if (any(hit)) {
      reassign <- hit & dec$habitat_reassigned[ifelse(is.na(idx), 1L, idx)] %in% TRUE
      .ne <- function(a, b) (is.na(a) != is.na(b)) | (!is.na(a) & !is.na(b) & a != b)
      changed <- (hit & .ne(occurrence_data[[flag_col]], dec$spatial_flag[idx])) |
        (reassign & .ne(occurrence_data[[habitat_col]], dec$main_habitat[idx]))
      occurrence_data[[flag_col]][hit] <- dec$spatial_flag[idx[hit]]
      occurrence_data[[habitat_col]][reassign] <- dec$main_habitat[idx[reassign]]
      if (reason_col %in% names(occurrence_data)) {
        # Strip any marker this function already wrote before re-prepending,
        # so re-applying the SAME saved decision to output that already
        # carries it reproduces the identical string rather than compounding
        # "reviewer decision (...); auto: reviewer decision (...); auto: ..."
        # forever. n_applied (below) is unaffected by this -- it only counts
        # a genuine flag/habitat change, not a reason-string rewrite.
        occurrence_data[[reason_col]][hit] <- paste0(
          "reviewer decision (", dec$decided_at[idx[hit]], "); auto: ",
          .strip_decision_marker(occurrence_data[[reason_col]][hit]))
      }
      n_applied <- sum(changed, na.rm = TRUE)
    }

    if (length(ambiguous_pids) > 0L) {
      warning(sprintf(
        paste0(
          "apply_spatial_review_decisions: %d point_id(s) in the decisions file carry no ",
          "recorded taxon_name (an old-format file, or a decision saved without taxon ",
          "information) and are shared by more than one taxon in the data being processed, ",
          "so no decision was applied at these point(s) -- they remain pending review: %s%s"
        ),
        length(ambiguous_pids),
        paste(utils::head(ambiguous_pids, 20L), collapse = ", "),
        if (length(ambiguous_pids) > 20L) sprintf(" (and %d more)", length(ambiguous_pids) - 20L) else ""
      ), call. = FALSE)
      message(sprintf(
        paste0(
          "apply_spatial_review_decisions: %d point(s) need re-review because their saved ",
          "decision does not record which taxon it was for. Re-open review_spatial_flags() ",
          "for them and re-save with save_spatial_review_decisions() -- the new save writes ",
          "the (point_id, taxon_name) key, and the next apply_spatial_review_decisions() call ",
          "will then apply them correctly."
        ), length(ambiguous_pids)
      ))
    }
  }
  pending <- unique(pid[!is.na(occurrence_data[[flag_col]]) &
    occurrence_data[[flag_col]] != "likely" & !hit])
  attr(occurrence_data, "n_applied") <- n_applied
  attr(occurrence_data, "n_pending_review") <- length(pending)
  attr(occurrence_data, "pending_point_ids") <- pending
  message(sprintf(
    paste0(
      "apply_spatial_review_decisions: %d saved decision(s) on file; %d row(s) changed by them; ",
      "%d flagged point(s) still need review."
    ),
    if (is.null(dec)) 0L else nrow(dec), n_applied, length(pending)))
  occurrence_data
}
