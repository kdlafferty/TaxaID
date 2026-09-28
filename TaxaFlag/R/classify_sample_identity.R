# Exports: classify_sample_identity
# Internal helpers: .sig_unit_stats, .sig_composition, .sig_appearance,
#   .sig_reason, .sig_read_decisions, .sig_apply_decisions, .sig_write_decisions,
#   .sig_top_taxa, .SIG_IDENTITY_DISPOSITIONS, .SIG_LIBRARY_DISPOSITIONS

.SIG_IDENTITY_DISPOSITIONS <- c(
  "confirm_blank", "confirm_sample", "reassign_to_blank", "reassign_to_sample",
  "exclude_tube"
)
.SIG_LIBRARY_DISPOSITIONS <- c("exclude_library", "keep_library")
.SIG_DECISION_COLS <- c("disposition", "reviewer", "decided_on", "note")

#' Gate Samples on Whether They Look Like Their Label
#'
#' Classifies every sample x marker x run (a "unit": one tube amplified with
#' one marker on one run, pooled over its replicate libraries) on two axes --
#' what it is LABELLED (blank or sample) and what it LOOKS LIKE (a valid
#' blank, a valid sample, neither, or unassessable) -- and admits it to
#' analysis only when the two agree or a person has recorded a decision.
#' Everything else is held back and listed for review. Nothing is dropped
#' silently: every unit keeps its row, its evidence and its reason.
#'
#' @section The matrix:
#' \tabular{llll}{
#'   \strong{labelled \\ looks like} \tab \strong{valid blank} \tab \strong{valid sample} \tab \strong{neither} \cr
#'   blank  \tab concordant: control \tab DISCORDANT \tab suspect \cr
#'   sample \tab DISCORDANT \tab concordant: admit \tab suspect
#' }
#' plus a fourth appearance, \code{"unassessable"}, for units the evidence
#' cannot judge. It is never merged with concordant. By default
#' (\code{unassessable_policy = "asymmetric"}) an unassessable BLANK is kept
#' out of the control set until reviewed and an unassessable SAMPLE is
#' admitted with the flag carried through. The asymmetry is about leverage:
#' a dirty blank corrupts every contaminant verdict on its run, and in the
#' permissive direction, while a sample only represents itself.
#'
#' @section Order of operations:
#' Yield is assessed first, with \code{\link{flag_failed_libraries}}. A failed
#' library looks like a sparse sample, and a failed run leaves nothing for a
#' blank to be compared with, so identity is judged only where yield held.
#' \itemize{
#'   \item A labelled SAMPLE whose libraries all failed looks like
#'     \code{"neither"} (issue type \code{"library"}).
#'   \item A labelled BLANK on a failed run is \code{"unassessable"}. Its low
#'     reads and low diversity are what a failed library would show whether
#'     or not it was clean. The one exception: a blank that still reaches
#'     sample-level diversity on a failed run is \code{"neither"}, because
#'     failure only ever lowers diversity.
#' }
#'
#' @section What "looks like a valid blank" means:
#' No single scalar works across markers. On one real three-marker study,
#' the share of reads from target-ecosystem taxa called a plankton-filled
#' blank clean in two markers, because plankton was out of analytical scope
#' but not out of the ENVIRONMENT. The axis that matters is environmental
#' versus laboratory, so this function uses two scope-free signals:
#' \itemize{
#'   \item \strong{Composition} (\code{\link{validate_controls}}, run on each
#'     run's libraries): does the blank look like the field samples it was
#'     sequenced with? A blank is sample-like when at least
#'     \code{composition_share} of its assessable replicate libraries are
#'     \code{"RESEMBLES_SAMPLE"}. This catches a blank carrying the samples'
#'     own community (a mislabel, or carry-over).
#'   \item \strong{Effective diversity} (Hill number of order 1, the
#'     exponential of Shannon entropy) relative to the marker's REFERENCE
#'     field diversity: the median, over runs, of each run's median field
#'     unit. The reference comes from outside the run, so a run whose samples
#'     all failed cannot make its blanks look rich by comparison. A blank at
#'     or above \code{diversity_blank_max} of the reference carries an
#'     environmental community. Hill N1 is used rather than richness because
#'     it is barely moved by the many one- and two-read features that index
#'     hopping spreads into blanks.
#' }
#' The second signal is what the first cannot see. A blank holding a
#' DIFFERENT environmental community -- seawater plankton in a benthic
#' study -- is compositionally disjoint from the samples, and
#' \code{validate_controls()} reads disjoint as clean. On the study above, 24
#' of 29 blanks on one run held 50 to 218 effective species of marine
#' protists that were mostly absent from that run's field samples. Every
#' one of them was \code{"consistent_with_control"} at full power.
#'
#' A blank is \code{"valid_sample"} when it is sample-like in composition,
#' \code{"neither"} when it has sample-level diversity without resembling the
#' samples, and \code{"valid_blank"} otherwise. That includes an EMPTY blank:
#' for a blank, few reads is the healthy state, and low yield never counts
#' against it. \code{confidence} is \code{"low"} when the composition test
#' had no power (\code{validate_controls()} power other than \code{"ok"}).
#' The verdict then rests on diversity alone, and the low confidence says so.
#'
#' @section What "looks like a valid sample" means:
#' A labelled sample is \code{"valid_sample"} unless:
#' \itemize{
#'   \item its libraries failed (\code{"neither"}); or
#'   \item at least \code{composition_share} of its assessable libraries
#'     \code{"RESEMBLES_CONTROL"} (\code{"valid_blank"}).
#' }
#' A sample with \code{low_yield} libraries (low in every marker, which is
#' genuine low biomass) is a valid sample. It is
#' \code{"unassessable"} only when neither yield nor composition could be
#' tested.
#'
#' @section Two kinds of decision, two scopes:
#' \describe{
#'   \item{Identity -- what is this tube?}{A property of the SAMPLE (barcode),
#'     across every marker: a tube cannot be a blank in one marker and a
#'     sample in another. Dispositions \code{"confirm_blank"},
#'     \code{"confirm_sample"}, \code{"reassign_to_blank"},
#'     \code{"reassign_to_sample"} and \code{"exclude_tube"} apply to all of
#'     the sample's units.}
#'   \item{Library validity -- did this assay work?}{A property of the
#'     UNIT. Dispositions \code{"exclude_library"} and \code{"keep_library"}
#'     apply to that unit only, so a library that failed in one marker does
#'     not take the same tube's good libraries in other markers with it.
#'     \code{"keep_library"} also lifts \code{flag_failed_libraries()}'s
#'     exclusion for that unit.}
#' }
#' Each flagged unit has an \code{issue_type} (\code{"identity"} or
#' \code{"library"}) saying which kind of disposition resolves it.
#' \itemize{
#'   \item \strong{An identity flag holds the whole tube.} A discordant or
#'     suspect identity in ANY marker holds every unit of that sample, including
#'     markers where it looked concordant (\code{tube_flagged}). A blank
#'     contaminated at the bag is contaminated in every marker, even where one
#'     marker happens to amplify little of it. An unassessable unit holds only
#'     itself: a failed library says nothing about the tube's other markers.
#'   \item \strong{Identity questions block; library failures do not.} A unit
#'     held for identity is \code{pending_review} until the tube has a
#'     disposition. A unit whose libraries failed is excluded
#'     (\code{excluded_library_issue}) but not pending: excluding it is already
#'     the conservative outcome, \code{flag_failed_libraries()} reports it
#'     loudly, and a queue that makes a person sign off every failed library
#'     invites rubber-stamping. It stays in the decision record, so
#'     \code{"keep_library"} can reverse it.
#'   \item Individually failed replicate libraries inside an admitted unit stay
#'     excluded at row level (\code{admit} is \code{FALSE} for their rows) unless
#'     the unit is kept explicitly.
#' }
#'
#' @section The decision record:
#' \code{decisions_path} names a CSV the user edits. Each call reads it and
#' applies the dispositions. It then writes it back with every unit that
#' currently needs review, preserving everything the user entered and adding
#' new rows. Rows are keyed by sample, marker and run. Each row carries the
#' \code{status} and \code{appearance} the gate reported when the row was
#' written. If the evidence has since changed, the disposition is still
#' applied, and a warning names the rows so they can be looked at again.
#' \code{\link{review_sample_identity}} adds \code{llm_} columns to the same
#' file. They are advice only: nothing is admitted on an LLM verdict. A
#' blank \code{disposition} keeps a unit held back.
#'
#' @section Cross-marker agreement:
#' The same tube assayed with independent markers is the strongest evidence
#' available. Each unit reports \code{n_markers_flagged} and
#' \code{n_markers_assessable} for its sample, counting identity flags only,
#' so a blank flagged in two markers is visibly better supported than one
#' flagged in one.
#'
#' @param input_df Long-format data frame, one row per feature x library,
#'   with every marker of the study and every control. Pass the same table
#'   used for \code{flag_failed_libraries()}.
#' @param library_col,sample_col,marker_col,run_col,count_col,taxon_col
#'   Character. Column names, as in \code{\link{flag_failed_libraries}}.
#'   \code{sample_col} must identify the physical tube shared across markers;
#'   \code{taxon_col} is the fine-grained feature (ESV/ASV) used for
#'   composition and diversity.
#' @param control_samples Character vector of \code{sample_col} (or
#'   \code{library_col}) values LABELLED as negative controls. Required.
#' @param failed_libraries Optional result of \code{flag_failed_libraries()}
#'   on \code{input_df}. When NULL it is computed here with its defaults.
#' @param taxon_label_col Character or NULL. A human-readable name column
#'   (species, or the finest rank known). When given, each unit gets a
#'   \code{top_taxa} summary, and each run gets one for its field units.
#'   Needed by \code{review_sample_identity()}. Default NULL.
#' @param diversity_blank_max Numeric. Blank effective diversity, as a
#'   fraction of the marker's reference field diversity, at or above which a
#'   blank carries an environmental community. Default 0.5. On one real
#'   study, clean blanks sat at a median of 0.18 and the worst contaminated
#'   blank at 1.43. The distribution is continuous, so the value is a
#'   judgement; units near it are for review, not for a verdict.
#' @param composition_share Numeric in (0, 1]. Share of a unit's assessable
#'   replicate libraries that must resemble the other label. Default 0.5.
#' @param unassessable_policy \code{"asymmetric"} (default) or
#'   \code{"block"}. See The matrix.
#' @param decisions_path Character or NULL. The CSV decision record. Read if
#'   it exists, then rewritten with the current review queue. Default NULL:
#'   nothing is read or written, and the queue is only returned.
#' @param on_pending \code{"warn"} (default), \code{"error"} or
#'   \code{"ignore"}: what to do when units are held back awaiting an identity
#'   decision. A production workflow should pass \code{"error"}.
#' @param verbose Logical. Print a summary. Default TRUE.
#'
#' @return \code{input_df} in its original order with these columns added:
#' \describe{
#'   \item{\code{identity_label}}{\code{"blank"} or \code{"sample"}, as labelled.}
#'   \item{\code{identity_appearance}}{\code{"valid_blank"}, \code{"valid_sample"},
#'     \code{"neither"} or \code{"unassessable"}.}
#'   \item{\code{identity_status}}{\code{"concordant"}, \code{"discordant"},
#'     \code{"suspect"} or \code{"unassessable"}.}
#'   \item{\code{admit_as}}{\code{"control"}, \code{"sample"} or \code{NA}
#'     (not admitted); reflects any reassignment.}
#'   \item{\code{admit}}{Logical. The gate. Filter on this and read
#'     \code{admit_as} for the role; the original \code{control_samples} vector
#'     is no longer the control set.}
#' }
#' Attribute \code{"units"}: one row per sample x marker x run with the
#' evidence (\code{depth}, \code{richness}, \code{diversity_n1},
#' \code{diversity_ratio}, \code{composition_share_other},
#' \code{n_libraries_assessable}, \code{composition_power},
#' \code{library_status}, \code{run_status}, \code{n_markers_flagged},
#' \code{n_markers_assessable}, \code{top_taxa}), the verdict columns,
#' \code{issue_type}, \code{tube_flagged}, \code{confidence}, \code{reason},
#' \code{disposition}, \code{pending_review}, \code{excluded_library_issue},
#' \code{admit_as} and \code{admit}. Attribute
#' \code{"review_queue"}: the units that need a person, in decision-record
#' shape. Attribute \code{"runs"}: one row per run x marker, with admitted
#' control and sample counts, \code{control_status} (\code{"ok"},
#' \code{"no_admitted_control"} or \code{"no_controls_labelled"}) and the
#' field \code{top_taxa}. Attribute \code{"failed_libraries"}: the
#' \code{flag_failed_libraries()} result used.
#'
#' @seealso \code{\link{flag_failed_libraries}} and
#'   \code{\link{validate_controls}}, which this composes;
#'   \code{\link{review_sample_identity}} for LLM advice on the queue;
#'   \code{\link{flag_contaminant}}, which should receive only admitted
#'   controls.
#'
#' @examples
#' set.seed(2)
#' # Two markers, one run each, five field samples and two blanks. Blank B2
#' # carries the field community (a mislabel or carry-over).
#' feats <- paste0("f", 1:40)
#' mk_lib <- function(s, m, pool, n) {
#'   data.frame(sample_id = s, marker = m, run = paste0("R_", m),
#'              event_id = paste0(s, ".1"), taxon_name = sample(pool, n),
#'              count = round(rlnorm(n, 5, 1)))
#' }
#' d <- do.call(rbind, c(
#'   lapply(paste0("S", 1:5), function(s) rbind(mk_lib(s, "M1", feats, 25),
#'                                               mk_lib(s, "M2", feats, 25))),
#'   list(mk_lib("B1", "M1", c("lab1", "lab2"), 2), mk_lib("B1", "M2", "lab1", 1),
#'        mk_lib("B2", "M1", feats, 25), mk_lib("B2", "M2", feats, 25))
#' ))
#' res <- classify_sample_identity(d, run_col = "run", control_samples = c("B1", "B2"),
#'                                 verbose = FALSE, on_pending = "ignore")
#' attr(res, "units")[, c("sample", "marker", "identity_label",
#'                        "identity_appearance", "identity_status", "admit")]
#' @export
classify_sample_identity <- function(input_df,
                                     library_col = "event_id",
                                     sample_col = "sample_id",
                                     marker_col = "marker",
                                     run_col = "run",
                                     count_col = "count",
                                     taxon_col = "taxon_name",
                                     control_samples,
                                     failed_libraries = NULL,
                                     taxon_label_col = NULL,
                                     diversity_blank_max = 0.5,
                                     composition_share = 0.5,
                                     unassessable_policy = c("asymmetric", "block"),
                                     decisions_path = NULL,
                                     on_pending = c("warn", "error", "ignore"),
                                     verbose = TRUE) {
  unassessable_policy <- match.arg(unassessable_policy)
  on_pending <- match.arg(on_pending)
  if (!is.data.frame(input_df)) stop("'input_df' must be a data frame.", call. = FALSE)
  for (col in c(library_col, sample_col, marker_col, run_col, count_col, taxon_col, taxon_label_col)) {
    if (!col %in% names(input_df)) {
      stop(sprintf("Column '%s' not found in input_df.", col), call. = FALSE)
    }
  }
  if (missing(control_samples) || !length(control_samples)) {
    stop("'control_samples' is required: with no labelled controls there is no ",
      "blank axis to classify.", call. = FALSE)
  }
  if (any(is.na(input_df[[sample_col]]))) {
    stop(sprintf("Column '%s' must not contain NA: identity decisions are made per sample.",
      sample_col), call. = FALSE)
  }
  if (!is.numeric(diversity_blank_max) || length(diversity_blank_max) != 1L ||
    is.na(diversity_blank_max) || diversity_blank_max <= 0) {
    stop("'diversity_blank_max' must be a single positive number.", call. = FALSE)
  }
  if (!is.numeric(composition_share) || length(composition_share) != 1L ||
    is.na(composition_share) || composition_share <= 0 || composition_share > 1) {
    stop("'composition_share' must be a single number in (0, 1].", call. = FALSE)
  }

  # --- 1. Yield first ---
  ff <- failed_libraries
  if (is.null(ff)) {
    ff <- flag_failed_libraries(input_df,
      library_col = library_col, sample_col = sample_col, marker_col = marker_col,
      run_col = run_col, count_col = count_col, taxon_col = taxon_col,
      control_samples = control_samples, verbose = verbose
    )
  } else if (is.null(attr(ff, "libraries")) || is.null(attr(ff, "runs")) ||
    nrow(ff) != nrow(input_df)) {
    stop("'failed_libraries' must be the unmodified result of flag_failed_libraries() ",
      "on this input_df (same rows, attributes intact).", call. = FALSE)
  }
  ffl_libs <- attr(ff, "libraries")
  ffl_runs <- attr(ff, "runs")

  d <- data.frame(
    marker = as.character(input_df[[marker_col]]),
    run = as.character(input_df[[run_col]]),
    library = as.character(input_df[[library_col]]),
    sample = as.character(input_df[[sample_col]]),
    feature = as.character(input_df[[taxon_col]]),
    reads = as.numeric(input_df[[count_col]]),
    excluded = ff$exclude_library %in% TRUE,
    stringsAsFactors = FALSE
  )
  d$reads[is.na(d$reads)] <- 0
  if (!is.null(taxon_label_col)) d$label_name <- as.character(input_df[[taxon_label_col]])
  d$unit <- paste(d$sample, d$marker, d$run, sep = "|")
  d$is_ctl <- d$sample %in% control_samples | d$library %in% control_samples
  if (!any(d$is_ctl)) {
    warning("None of 'control_samples' matched a sample or library in input_df.", call. = FALSE)
  }

  # --- 2. Unit evidence ---
  u <- .sig_unit_stats(d)
  ffl_libs$unit <- paste(ffl_libs$sample, ffl_libs$marker, ffl_libs$run, sep = "|")
  u$library_status <- vapply(u$unit, function(k) {
    s <- ffl_libs$library_status[ffl_libs$unit == k]
    s <- s[!is.na(s)]
    if (!length(s)) return(NA_character_)
    # the unit's best library status: one good replicate is enough to show yield
    for (lev in c("pass", "low_yield", "low_yield_undetermined", "failed")) if (lev %in% s) return(lev)
    s[1]
  }, character(1))
  rk <- paste(ffl_runs$run, ffl_runs$marker, sep = "|")
  u$run_status <- ffl_runs$run_status[match(paste(u$run, u$marker, sep = "|"), rk)]
  u$control_contrast <- ffl_runs$control_contrast[match(paste(u$run, u$marker, sep = "|"), rk)]

  # marker reference diversity: median over runs of each run's median field unit,
  # runs that failed excluded, so the reference is never set by a failure
  fld <- u$identity_label == "sample" & !(u$run_status %in% "failed") & u$n_libraries_kept > 0
  run_med <- tapply(u$diversity_n1[fld], paste(u$marker[fld], u$run[fld], sep = "\r"), stats::median)
  mk_of <- sub("\r.*$", "", names(run_med))
  ref <- tapply(run_med, mk_of, stats::median)
  u$reference_n1 <- as.numeric(ref[u$marker])
  u$diversity_ratio <- round(u$diversity_n1 / u$reference_n1, 3)

  # --- 3. Composition, per run, on the libraries that yielded ---
  comp <- .sig_composition(d, composition_share)
  u <- merge(u, comp, by = "unit", all.x = TRUE, sort = FALSE)
  u$n_libraries_assessable[is.na(u$n_libraries_assessable)] <- 0L
  u$composition_power[is.na(u$composition_power)] <- "none"

  # --- 4. Appearance and status ---
  ap <- .sig_appearance(u, diversity_blank_max)
  u$identity_appearance <- ap$appearance
  u$issue_type <- ap$issue_type
  u$confidence <- ap$confidence
  u$identity_status <- ifelse(u$identity_appearance == "unassessable", "unassessable",
    ifelse(u$identity_appearance == "neither", "suspect",
      ifelse((u$identity_label == "blank" & u$identity_appearance == "valid_blank") |
        (u$identity_label == "sample" & u$identity_appearance == "valid_sample"),
      "concordant", "discordant")
    )
  )
  u$issue_type[u$identity_status == "concordant"] <- NA_character_

  # cross-marker agreement, identity flags only
  id_flag <- u$identity_status %in% c("discordant", "suspect") & u$issue_type %in% "identity"
  assessable <- u$identity_status != "unassessable" & !(u$issue_type %in% "library")
  u$n_markers_flagged <- as.integer(tapply(u$marker[id_flag], u$sample[id_flag],
    function(x) length(unique(x)))[u$sample])
  u$n_markers_flagged[is.na(u$n_markers_flagged)] <- 0L
  u$n_markers_assessable <- as.integer(tapply(u$marker[assessable], u$sample[assessable],
    function(x) length(unique(x)))[u$sample])
  u$n_markers_assessable[is.na(u$n_markers_assessable)] <- 0L

  if (!is.null(taxon_label_col)) {
    u$top_taxa <- .sig_top_taxa(d, u$unit)
  } else {
    u$top_taxa <- NA_character_
  }
  u$reason <- .sig_reason(u, diversity_blank_max)

  # --- 5. Decisions and admission ---
  dec <- .sig_read_decisions(decisions_path)
  u <- .sig_apply_decisions(u, dec, unassessable_policy)

  # --- 6. Runs: is there still a control? ---
  runs <- unique(u[, c("marker", "run")])
  runs <- runs[order(runs$marker, runs$run), , drop = FALSE]
  rk_u <- paste(u$marker, u$run)
  rk_r <- paste(runs$marker, runs$run)
  runs$n_labelled_controls <- vapply(rk_r, function(k) sum(rk_u == k & u$identity_label == "blank"), integer(1))
  runs$n_admitted_controls <- vapply(rk_r, function(k) sum(rk_u == k & u$admit & u$admit_as %in% "control"), integer(1))
  runs$n_admitted_samples <- vapply(rk_r, function(k) sum(rk_u == k & u$admit & u$admit_as %in% "sample"), integer(1))
  runs$n_pending <- vapply(rk_r, function(k) sum(rk_u == k & u$pending_review), integer(1))
  runs$control_status <- ifelse(runs$n_labelled_controls == 0, "no_controls_labelled",
    ifelse(runs$n_admitted_controls == 0, "no_admitted_control", "ok"))
  runs$run_status <- u$run_status[match(rk_r, rk_u)]
  runs$field_top_taxa <- if (!is.null(taxon_label_col)) {
    vapply(seq_len(nrow(runs)), function(i) {
      k <- d$marker == runs$marker[i] & d$run == runs$run[i] & !d$is_ctl & !d$excluded
      if (!any(k)) return(NA_character_)
      .sig_top_taxa(d[k, ], per_unit = FALSE)
    }, character(1))
  } else {
    NA_character_
  }
  rownames(runs) <- NULL

  queue <- u[u$needs_review, , drop = FALSE]
  queue <- .sig_queue_shape(queue)
  if (!is.null(decisions_path)) .sig_write_decisions(queue, dec, decisions_path)

  # --- 7. Map back to rows ---
  m <- match(d$unit, u$unit)
  keep_lib <- u$library_disposition[m] %in% "keep_library"
  out <- input_df
  out$identity_label <- u$identity_label[m]
  out$identity_appearance <- u$identity_appearance[m]
  out$identity_status <- u$identity_status[m]
  out$admit_as <- u$admit_as[m]
  out$admit <- u$admit[m] & (!d$excluded | keep_lib)

  u <- u[order(u$marker, u$run, u$identity_label, u$sample), , drop = FALSE]
  rownames(u) <- NULL
  attr(out, "units") <- u
  attr(out, "review_queue") <- queue
  attr(out, "runs") <- runs
  attr(out, "failed_libraries") <- ff

  # --- 8. Loud reporting ---
  if (verbose) {
    message(sprintf("classify_sample_identity: %d unit(s) (sample x marker x run).", nrow(u)))
    print(table(label = u$identity_label, status = u$identity_status))
    message(sprintf(paste0("  admitted: %d as sample, %d as control; held back: %d ",
      "(%d pending identity review, %d excluded as failed libraries)."),
      sum(u$admit & u$admit_as %in% "sample"), sum(u$admit & u$admit_as %in% "control"),
      sum(!u$admit), sum(u$pending_review), sum(u$excluded_library_issue)))
  }
  nc <- runs[runs$control_status == "no_admitted_control", , drop = FALSE]
  if (nrow(nc)) {
    warning(sprintf(
      "%d run(s) x marker have labelled controls but NONE admitted: %s. Contaminant checks there have no control and must say so, not report a clean result.",
      nrow(nc), paste(nc$marker, nc$run, collapse = ", ")
    ), call. = FALSE)
  }
  stale <- attr(u, "stale_decisions")
  if (length(stale)) {
    warning(sprintf(
      "%d decision(s) were made against evidence that has since changed (status or appearance differs): %s. They are still applied; look again.",
      length(stale), paste(utils::head(stale, 8), collapse = ", ")
    ), call. = FALSE)
  }
  n_pend <- sum(u$pending_review)
  if (n_pend && on_pending != "ignore") {
    pu <- u[u$pending_review, , drop = FALSE]
    msg <- sprintf(paste0(
      "%d unit(s) from %d sample(s) do not look like their label, or cannot be assessed, ",
      "and have no recorded decision. They are NOT admitted. By status: %s. ",
      "Record a disposition%s, or see attr(, \"review_queue\")."
    ),
    n_pend, length(unique(pu$sample)),
    paste(names(table(pu$identity_status)), table(pu$identity_status), sep = " ", collapse = ", "),
    if (!is.null(decisions_path)) paste0(" in ", decisions_path) else ""
    )
    if (on_pending == "error") stop(msg, call. = FALSE)
    warning(msg, call. = FALSE)
  }
  out
}

#' Per-unit depth, richness and Hill N1 on the libraries that yielded
#' @noRd
.sig_unit_stats <- function(d) {
  first <- !duplicated(d$unit)
  u <- data.frame(
    unit = d$unit[first], sample = d$sample[first], marker = d$marker[first],
    run = d$run[first], stringsAsFactors = FALSE
  )
  u$identity_label <- ifelse(as.vector(tapply(d$is_ctl, d$unit, any)[u$unit]), "blank", "sample")
  u$n_libraries <- as.integer(tapply(d$library, d$unit, function(x) length(unique(x)))[u$unit])
  kept <- !d$excluded
  nk <- tapply(d$library[kept], d$unit[kept], function(x) length(unique(x)))
  u$n_libraries_kept <- as.integer(nk[u$unit])
  u$n_libraries_kept[is.na(u$n_libraries_kept)] <- 0L
  # Evidence is computed on kept libraries when there are any; a unit whose
  # libraries were all excluded is described by all of them (its evidence is
  # then the failure itself, and the verdict says so).
  use <- kept | !(d$unit %in% names(nk))
  f <- tapply(d$reads[use], paste(d$unit[use], d$feature[use], sep = "\r"), sum)
  f <- f[!is.na(f) & f > 0]
  f_unit <- sub("\r.*$", "", names(f))
  u$depth <- as.numeric(tapply(d$reads[use], d$unit[use], sum)[u$unit])
  u$depth[is.na(u$depth)] <- 0
  u$richness <- as.integer(table(factor(f_unit, levels = u$unit)))
  n1 <- tapply(as.numeric(f), f_unit, function(x) {
    p <- x / sum(x)
    exp(-sum(p * log(p)))
  })
  u$diversity_n1 <- round(as.numeric(n1[u$unit]), 2)
  u$diversity_n1[is.na(u$diversity_n1)] <- 0
  u
}

#' validate_controls() run by run on kept libraries, summarised to units
#' @noRd
.sig_composition <- function(d, composition_share) {
  k <- !d$excluded & d$reads > 0
  if (!any(k)) {
    return(data.frame(unit = character(), n_libraries_assessable = integer(),
      composition_share_other = numeric(), composition_power = character(),
      composition_other = logical(), stringsAsFactors = FALSE))
  }
  x <- d[k, c("marker", "run", "library", "unit", "feature", "reads", "is_ctl")]
  x$lib_id <- paste(x$marker, x$run, x$library, sep = "|")
  x$site <- paste(x$marker, x$run, sep = "|")
  ctl_ids <- unique(x$lib_id[x$is_ctl])
  vc <- if (length(ctl_ids)) {
    suppressWarnings(validate_controls(x,
      event_col = "lib_id", taxon_col = "feature", count_col = "reads",
      control_samples = ctl_ids, site_col = "site", verbose = FALSE
    ))
  } else {
    NULL
  }
  if (is.null(vc)) {
    return(data.frame(unit = character(), n_libraries_assessable = integer(),
      composition_share_other = numeric(), composition_power = character(),
      composition_other = logical(), stringsAsFactors = FALSE))
  }
  vc$unit <- x$unit[match(vc$column_id, x$lib_id)]
  ok <- vc$verdict %in% c("consistent_with_control", "RESEMBLES_SAMPLE",
    "consistent_with_sample", "RESEMBLES_CONTROL")
  other <- vc$verdict %in% c("RESEMBLES_SAMPLE", "RESEMBLES_CONTROL")
  units <- unique(vc$unit)
  n_ok <- vapply(units, function(z) sum(ok[vc$unit == z]), integer(1))
  n_other <- vapply(units, function(z) sum(other[vc$unit == z]), integer(1))
  pw <- vapply(units, function(z) {
    p <- vc$power[vc$unit == z & ok]
    if (!length(p)) "none" else if (all(p == "ok")) "ok" else "low"
  }, character(1))
  sh <- ifelse(n_ok > 0, n_other / pmax(n_ok, 1), NA_real_)
  data.frame(
    unit = units, n_libraries_assessable = as.integer(n_ok),
    composition_share_other = round(sh, 3), composition_power = pw,
    composition_other = !is.na(sh) & sh >= composition_share,
    stringsAsFactors = FALSE
  )
}

#' The appearance rules; see the roxygen of classify_sample_identity()
#' @noRd
.sig_appearance <- function(u, diversity_blank_max) {
  n <- nrow(u)
  ap <- character(n)
  it <- character(n)
  cf <- ifelse(u$composition_power == "ok", "ok", "low")
  run_failed <- u$run_status %in% "failed"
  collapsed <- u$n_libraries_kept == 0 & u$n_libraries > 0
  rich <- !is.na(u$diversity_ratio) & u$diversity_ratio >= diversity_blank_max
  other <- u$composition_other %in% TRUE
  for (i in seq_len(n)) {
    if (u$identity_label[i] == "blank") {
      it[i] <- "identity"
      if (run_failed[i] || collapsed[i]) {
        ap[i] <- if (rich[i]) "neither" else "unassessable"
        cf[i] <- "low"
      } else if (other[i]) {
        ap[i] <- "valid_sample"
      } else if (rich[i]) {
        ap[i] <- "neither"
      } else {
        ap[i] <- "valid_blank"
      }
    } else {
      if (collapsed[i]) {
        ap[i] <- "neither"
        it[i] <- "library"
      } else if (other[i]) {
        ap[i] <- "valid_blank"
        it[i] <- "identity"
      } else if (u$n_libraries_assessable[i] == 0 &&
        u$library_status[i] %in% c("low_yield_undetermined", NA) &&
        !u$run_status[i] %in% c("pass", "low_yield")) {
        ap[i] <- "unassessable"
        it[i] <- "identity"
        cf[i] <- "low"
      } else {
        ap[i] <- "valid_sample"
        it[i] <- "identity"
      }
    }
  }
  list(appearance = ap, issue_type = it, confidence = cf)
}

#' @noRd
.sig_reason <- function(u, diversity_blank_max) {
  vapply(seq_len(nrow(u)), function(i) {
    x <- u[i, ]
    comp <- if (x$n_libraries_assessable > 0) {
      sprintf("%d of %d replicate librar%s resemble%s the other label (composition power %s)",
        as.integer(round(x$composition_share_other * x$n_libraries_assessable)),
        as.integer(x$n_libraries_assessable),
        if (x$n_libraries_assessable == 1) "y" else "ies",
        if (x$n_libraries_assessable == 1) "s" else "",
        x$composition_power)
    } else {
      "composition not testable"
    }
    div <- sprintf("effective diversity %.1f = %.2fx the %s reference (%.1f)",
      x$diversity_n1, x$diversity_ratio, x$marker, x$reference_n1)
    base <- sprintf("%s reads, %d features; %s; %s.",
      format(round(x$depth), big.mark = ",", trim = TRUE), as.integer(x$richness), div, comp)
    lead <- switch(paste(x$identity_label, x$identity_appearance),
      "blank valid_blank" = "Looks like a clean blank.",
      "blank valid_sample" = "Blank that resembles the field samples it was sequenced with: mislabel or carry-over.",
      "blank neither" = if (x$run_status %in% "failed") {
        "Blank at sample-level diversity on a FAILED run; failure only lowers diversity, so it carries an environmental community."
      } else {
        sprintf("Blank carrying an environmental community (diversity >= %.2fx reference) that does not resemble this run's samples.", diversity_blank_max)
      },
      "blank unassessable" = "Blank on a run whose field libraries failed: nothing to compare it with, and a failure hides contamination. Not evidence of a clean blank.",
      "sample valid_sample" = "Looks like a valid sample.",
      "sample valid_blank" = "Sample that resembles the run's blanks rather than the other samples: a blank labelled as a sample, or a near-empty sample.",
      "sample neither" = sprintf("Every library of this sample failed (%s); the extract may be fine in other markers.",
        if (x$run_status %in% "failed") "whole run failed" else "library failure"),
      "sample unassessable" = "Neither yield nor composition could be tested.",
      ""
    )
    extra <- if (x$n_markers_flagged > 0) {
      sprintf(" Identity flagged in %d of %d assessable marker(s) for this sample.",
        as.integer(x$n_markers_flagged), as.integer(x$n_markers_assessable))
    } else {
      ""
    }
    paste(lead, base, extra)
  }, character(1))
}

#' Top taxa by read share, as "Name 34%; Name 12%; ..."
#' @noRd
.sig_top_taxa <- function(d, units = NULL, n = 12L, per_unit = TRUE) {
  nm <- d$label_name
  nm[is.na(nm) | !nzchar(nm)] <- "(unassigned)"
  one <- function(z) {
    s <- sort(tapply(z$reads, nm[z$.row], sum), decreasing = TRUE)
    s <- s[s > 0]
    if (!length(s)) return(NA_character_)
    tot <- sum(s)
    s <- utils::head(s, n)
    paste(sprintf("%s %s%%", names(s), formatC(100 * s / tot, format = "f", digits = 1)), collapse = "; ")
  }
  d$.row <- seq_len(nrow(d))
  if (!per_unit) return(one(d))
  sp <- split(d, d$unit)
  vapply(units, function(k) if (is.null(sp[[k]])) NA_character_ else one(sp[[k]]), character(1))
}

#' Read the user-edited decision CSV (NULL when absent)
#' @noRd
.sig_read_decisions <- function(path) {
  if (is.null(path) || !file.exists(path)) return(NULL)
  dec <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character", na.strings = c("", "NA"))
  need <- c("sample", "marker", "run", "disposition")
  miss <- setdiff(need, names(dec))
  if (length(miss)) {
    stop(sprintf("Decision record %s is missing column(s): %s.", path, paste(miss, collapse = ", ")),
      call. = FALSE)
  }
  dec$disposition <- trimws(dec$disposition)
  bad <- setdiff(stats::na.omit(dec$disposition), c(.SIG_IDENTITY_DISPOSITIONS, .SIG_LIBRARY_DISPOSITIONS))
  if (length(bad)) {
    stop(sprintf("Decision record %s has unknown disposition(s): %s. Allowed: %s.",
      path, paste(bad, collapse = ", "),
      paste(c(.SIG_IDENTITY_DISPOSITIONS, .SIG_LIBRARY_DISPOSITIONS), collapse = ", ")),
    call. = FALSE)
  }
  dec
}

#' Apply dispositions and the default admission rule
#' @noRd
.sig_apply_decisions <- function(u, dec, unassessable_policy) {
  u$identity_disposition <- NA_character_
  u$library_disposition <- NA_character_
  stale <- character(0)
  if (!is.null(dec) && nrow(dec)) {
    dec <- dec[!is.na(dec$disposition), , drop = FALSE]
    key_d <- paste(dec$sample, dec$marker, dec$run, sep = "|")
    # identity: per sample, must agree across its rows
    idd <- dec[dec$disposition %in% .SIG_IDENTITY_DISPOSITIONS, , drop = FALSE]
    if (nrow(idd)) {
      per <- tapply(idd$disposition, idd$sample, function(x) unique(x))
      conflict <- names(per)[lengths(per) > 1L]
      if (length(conflict)) {
        stop(sprintf("Conflicting identity dispositions for sample(s) %s: an identity decision applies to the whole tube, across markers.",
          paste(conflict, collapse = ", ")), call. = FALSE)
      }
      per <- unlist(per)
      u$identity_disposition <- as.vector(unname(per[u$sample]))
    }
    lbd <- dec[dec$disposition %in% .SIG_LIBRARY_DISPOSITIONS, , drop = FALSE]
    if (nrow(lbd)) {
      u$library_disposition <- lbd$disposition[match(u$unit, paste(lbd$sample, lbd$marker, lbd$run, sep = "|"))]
    }
    # evidence drift: recorded status/appearance vs now
    if (all(c("identity_status", "identity_appearance") %in% names(dec))) {
      ds <- if ("status_at_decision" %in% names(dec)) dplyr::coalesce(dec$status_at_decision, dec$identity_status) else dec$identity_status
      da <- if ("appearance_at_decision" %in% names(dec)) dplyr::coalesce(dec$appearance_at_decision, dec$identity_appearance) else dec$identity_appearance
      m <- match(key_d, u$unit)
      ch <- !is.na(m) & ((!is.na(ds) & ds != u$identity_status[m]) |
        (!is.na(da) & da != u$identity_appearance[m]))
      stale <- key_d[ch]
    }
    unknown <- setdiff(key_d, u$unit)
    if (length(unknown)) {
      warning(sprintf("%d decision row(s) match no unit in input_df (e.g. %s); ignored.",
        length(unknown), unknown[1]), call. = FALSE)
    }
  }

  idd <- u$identity_disposition
  role <- ifelse(u$identity_label == "blank", "control", "sample")
  role[idd %in% c("confirm_blank", "reassign_to_blank")] <- "control"
  role[idd %in% c("confirm_sample", "reassign_to_sample")] <- "sample"

  st <- u$identity_status
  flagged <- st %in% c("discordant", "suspect")
  id_issue <- u$issue_type %in% "identity"
  lib_issue <- u$issue_type %in% "library"
  unass <- st == "unassessable"
  unass_blocks <- unass & (unassessable_policy == "block" | u$identity_label == "blank")

  id_resolved <- !is.na(idd)
  lib_resolved <- !is.na(u$library_disposition)
  # identity is a property of the tube: an identity flag in ANY marker holds every
  # unit of that sample until the tube is dispositioned
  # (an unassessable unit holds only itself: a failed library says nothing about
  # the tube's other markers)
  tube_flag <- u$sample %in% u$sample[flagged & id_issue]
  u$tube_flagged <- tube_flag
  needs_id <- (tube_flag | unass_blocks) & !id_resolved
  held_by_tube <- tube_flag & st == "concordant" & !id_resolved
  u$reason[held_by_tube] <- paste(u$reason[held_by_tube],
    "HELD: this tube's identity is flagged in another marker; an identity decision covers every marker.")
  needs_lib <- flagged & lib_issue & !lib_resolved

  # A library failure is excluded by default and does not block: excluding is the
  # conservative outcome, flag_failed_libraries() already reports it loudly, and
  # making a person sign off every failed library invites rubber-stamping. It stays
  # in the record so "keep_library" can reverse it. Identity questions block.
  admit <- !needs_id & !needs_lib
  admit[idd %in% "exclude_tube"] <- FALSE
  admit[u$library_disposition %in% "exclude_library"] <- FALSE
  u$excluded_library_issue <- needs_lib
  u$pending_review <- needs_id
  # the queue lists every flagged unit and every unassessable unit that blocks,
  # plus any unit already decided (so the record keeps it)
  u$needs_review <- flagged | unass_blocks | tube_flag | id_resolved | lib_resolved
  u$admit <- admit
  u$admit_as <- ifelse(admit, role, NA_character_)
  u$disposition <- ifelse(!is.na(u$library_disposition), u$library_disposition, idd)
  attr(u, "stale_decisions") <- stale
  u
}

#' @noRd
.sig_queue_shape <- function(q) {
  cols <- c(
    "sample", "marker", "run", "identity_label", "identity_appearance", "identity_status",
    "issue_type", "tube_flagged", "confidence", "n_markers_flagged", "n_markers_assessable", "depth",
    "richness", "diversity_n1", "diversity_ratio", "composition_share_other",
    "composition_power", "run_status", "reason", "top_taxa"
  )
  q <- q[, cols, drop = FALSE]
  q$suggested_disposition <- ifelse(q$issue_type %in% "library", "exclude_library",
    ifelse(q$identity_label == "blank" & q$identity_appearance == "valid_blank", "confirm_blank",
      ifelse(q$identity_label == "sample" & q$identity_appearance == "valid_sample", "confirm_sample",
        NA_character_)))
  q <- q[order(-q$n_markers_flagged, q$marker, q$run, q$sample), , drop = FALSE]
  rownames(q) <- NULL
  q
}

#' Merge the current queue into the CSV, never overwriting user-entered fields
#'
#' Evidence columns come from the current run. Every other column in the old
#' record (the user's decision columns, any column they added, llm_ advice)
#' is carried forward; fresh llm_ advice replaces old advice only where it
#' exists. The evidence a person decided against is pinned in
#' status_at_decision / appearance_at_decision the first time a disposition
#' is seen, so a later change in evidence can be reported rather than
#' silently overwritten.
#' @noRd
.sig_write_decisions <- function(queue, dec, path) {
  new <- queue
  for (col in c(.SIG_DECISION_COLS, "status_at_decision", "appearance_at_decision")) {
    if (!col %in% names(new)) new[[col]] <- NA_character_
  }
  if (!is.null(dec) && nrow(dec)) {
    for (col in c("status_at_decision", "appearance_at_decision")) {
      if (!col %in% names(dec)) dec[[col]] <- NA_character_
    }
    pin <- !is.na(dec$disposition) & is.na(dec$status_at_decision)
    if ("identity_status" %in% names(dec)) dec$status_at_decision[pin] <- dec$identity_status[pin]
    if ("identity_appearance" %in% names(dec)) dec$appearance_at_decision[pin] <- dec$identity_appearance[pin]
    key_new <- paste(new$sample, new$marker, new$run, sep = "|")
    key_old <- paste(dec$sample, dec$marker, dec$run, sep = "|")
    m <- match(key_new, key_old)
    evidence <- setdiff(names(queue), grep("^llm_", names(queue), value = TRUE))
    for (col in setdiff(names(dec), evidence)) {
      if (!col %in% names(new)) new[[col]] <- NA_character_
      take <- !is.na(m)
      if (grepl("^llm_", col)) take <- take & is.na(new[[col]])
      new[[col]][take] <- dec[[col]][m[take]]
    }
    # decided rows no longer in the queue stay in the record
    gone <- dec[!key_old %in% key_new & !is.na(dec$disposition), , drop = FALSE]
    if (nrow(gone)) {
      for (col in setdiff(names(new), names(gone))) gone[[col]] <- NA
      new <- rbind(new, gone[, names(new), drop = FALSE])
    }
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp")
  utils::write.csv(new, tmp, row.names = FALSE, na = "")
  file.rename(tmp, path)
  invisible(path)
}
