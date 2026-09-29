# Exports: classify_sample_identity
# Internal helpers: .sig_unit_stats, .sig_composition, .sig_appearance,
#   .sig_reason, .sig_read_decisions, .sig_apply_decisions, .sig_write_decisions,
#   .sig_top_taxa, .SIG_IDENTITY_DISPOSITIONS, .SIG_LIBRARY_DISPOSITIONS

.SIG_IDENTITY_DISPOSITIONS <- c(
  "confirm_blank", "confirm_sample", "reassign_to_blank", "reassign_to_sample",
  "reassign_to_positive_control", "exclude_tube"
)
.SIG_LIBRARY_DISPOSITIONS <- c("exclude_library", "keep_library")
.SIG_DECISION_COLS <- c("disposition", "reviewer", "decided_on", "note")

#' Gate Samples on Whether They Look Like Their Label
#'
#' Classifies every sample x marker x run (a "unit": one tube amplified with
#' one marker on one run, pooled over its replicate libraries) on two axes --
#' what it is LABELLED (blank or sample) and what it LOOKS LIKE (a valid
#' blank, a valid sample, or neither) -- and suggests admitting it when the two
#' agree or a decision has been recorded. Admission is the workflow's choice:
#' \code{admit} is a default the workflow may follow or replace.
#' Everything else is held back and listed for review. Nothing is dropped
#' silently: every unit keeps its row, its evidence and its reason.
#'
#' @section The matrix:
#' \tabular{llll}{
#'   \strong{labelled \\ looks like} \tab \strong{valid blank} \tab \strong{valid sample} \tab \strong{neither} \cr
#'   blank  \tab concordant: control \tab DISCORDANT \tab suspect \cr
#'   sample \tab DISCORDANT \tab concordant: admit \tab suspect
#' }
#'
#' @section Status: what was found, and why nothing could be:
#' \code{identity_status} separates a finding from the absence of one, and
#' \code{identity_status_reason} names the evidence or the reason:
#' \describe{
#'   \item{\code{concordant}, \code{discordant}, \code{suspect}}{A test ran
#'     and answered (reason: \code{"composition"}, \code{"diversity"},
#'     \code{"library_failed"}, ...).}
#'   \item{\code{inconclusive}}{A test ran but could not discriminate
#'     (\code{"no_power"}: \code{validate_controls()} reported a null too wide
#'     to separate anything, or no headroom).}
#'   \item{\code{untested}}{No test ran: \code{"no_blanks"} (nothing to
#'     compare a sample with), \code{"unreplicated"} (too few field units on
#'     the run), or \code{"uncomparable"} (the run's field libraries failed, so
#'     a blank has nothing valid to be compared with).}
#' }
#' An untested or inconclusive unit shows no evidence of a problem, which is
#' not evidence of its absence. Many studies are thin, and they should still
#' be analysed, cautiously: by default (\code{untested_policy = "admit"}) such
#' units are admitted with their status carried through.
#' \code{"hold_blanks"} keeps untested/inconclusive blanks out of the control
#' set (a dirty blank corrupts contaminant verdicts in the permissive
#' direction); \code{"block"} holds every such unit for review.
#'
#' @section Order of operations:
#' Yield is assessed first, with \code{\link{flag_failed_libraries}}. A failed
#' library looks like a sparse sample, and a failed run leaves nothing for a
#' blank to be compared with, so identity is judged only where yield held.
#' \itemize{
#'   \item A labelled SAMPLE whose libraries all failed looks like
#'     \code{"neither"} (issue type \code{"library"}).
#'   \item A labelled BLANK on a failed run is \code{"untested"} (\code{"uncomparable"}). Its low
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
#' A diverse blank is flagged \code{"suspect"}, not condemned: a blank's own
#' medium can carry a community (tap water carries its source water's
#' freshwater organisms). Whether the community is consistent with the blank
#' medium or with handling is a judgement about what the taxa are, which
#' \code{\link{review_sample_identity}} makes when told the medium.
#'
#' @section What "looks like a valid sample" means:
#' A labelled sample is \code{"valid_sample"} unless:
#' \itemize{
#'   \item its libraries failed (\code{"neither"}); or
#'   \item at least \code{composition_share} of its assessable libraries
#'     \code{"RESEMBLES_CONTROL"} (\code{"valid_blank"}).
#' }
#' A sample with \code{low_yield} libraries (low in every marker, which is
#' genuine low biomass) is a valid sample. The identity test for a sample is
#' whether it resembles the run's blanks; when that test cannot run or cannot
#' discriminate the sample is \code{"untested"} or \code{"inconclusive"}, not
#' concordant.
#'
#' @section Run-wide artifacts and declared spikes:
#' A feature in at least \code{artifact_fraction} of a run's field libraries
#' that also holds the majority of reads in at least half of the run's blanks
#' is in every tube whatever the tube is: a spike the user added, a provider's
#' positive control reaching every library, or cross-contamination. It carries
#' no identity information, so it is set aside from composition and diversity.
#' Both conditions are needed: common environmental taxa can be in nearly
#' every field library, but they do not dominate the blanks. Unless declared in
#' \code{spike_taxa}, such a feature is REPORTED as a run-wide artifact with a
#' warning, because its cause is a question for the user or the provider. It
#' stays visible in \code{top_taxa}. Judged per run, since one archive can mix
#' runs with and without it.
#'
#' @section Two kinds of decision, two scopes:
#' \describe{
#'   \item{Identity -- what is this tube?}{A property of the SAMPLE (barcode),
#'     across every marker: a tube cannot be a blank in one marker and a
#'     sample in another. Dispositions \code{"confirm_blank"},
#'     \code{"confirm_sample"}, \code{"reassign_to_blank"},
#'     \code{"reassign_to_sample"}, \code{"reassign_to_positive_control"} and
#'     \code{"exclude_tube"} apply to all of the sample's units. A positive
#'     control recorded as a field blank must not stay in the negative control
#'     set: it inflates the control rate of every spiked taxon, which makes
#'     \code{flag_contaminant()} more permissive. Re-roled, it is admitted with
#'     \code{admit_as = "positive_control"}.}
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
#'     markers where it looked concordant (\code{tube_flagged}). Such a unit
#'     keeps its own \code{identity_status} (it is not itself evidence of
#'     anything), and \code{hold_reason} says why it is held:
#'     \code{"own_evidence"}, \code{"tube"}, \code{"untested"} or
#'     \code{"inconclusive"}. An untested unit holds only itself: a failed
#'     library says nothing about the tube's other markers.
#'   \item \strong{Identity is per tube; usability is per marker.} Whether a
#'     tube IS a blank is one question for all its markers. Whether a marker's
#'     result is USABLE is asked per marker, because different markers can
#'     return usable and unusable results for the same tube. A blank whose own
#'     evidence in one marker looks contaminated (discordant or suspect in that
#'     marker) is not admitted as a control IN THAT MARKER, even after the tube
#'     is confirmed as a blank: \code{control_usability} reads
#'     \code{"contaminated_in_marker"}, and \code{"keep_library"} on that unit
#'     overrides it. Its other markers are judged on their own evidence:
#'     contamination a marker cannot amplify cannot bias that marker. The
#'     inference runs one way only. A clean result in an insensitive marker
#'     (12S cannot amplify protists or algae) never clears a sensitive one,
#'     because each marker is judged only on its own evidence.
#'   \item \strong{Sample viability is per marker.} \code{sample_viability}
#'     combines yield with appearance: \code{"viable"} (libraries passed),
#'     \code{"thin"} (low yield but a normal-looking composition: a genuinely
#'     small sample, not a broken one) or \code{"non_viable"} (no library
#'     yielded). Depth alone cannot tell thin from broken. Below some depth
#'     the composition test has nothing to compare, so only depth speaks; that
#'     is the \code{inconclusive}/\code{no_power} state.
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
#' file, including \code{llm_role} (blank, sample, positive_control, exclude or
#' unknown). By default these are advice. With \code{accept_llm_roles = TRUE},
#' \code{llm_role} stands in for an identity disposition wherever no person
#' has recorded one, and \code{disposition_source} says which it was
#' (\code{"user"} or \code{"llm"}). A person's disposition always wins.
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
#'   \code{library_col}) values LABELLED as negative controls. NULL or empty is
#'   allowed: every unit is then \code{"untested"} (\code{"no_blanks"}).
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
#' @param artifact_fraction Numeric in (0, 1] or NULL. Field-library
#'   prevalence at which a feature that also dominates the run's blanks is a
#'   run-wide artifact (see Run-wide artifacts). NULL disables detection.
#'   Default 0.9.
#' @param spike_taxa Character or NULL. Features (\code{taxon_col} or
#'   \code{taxon_label_col} values) the user deliberately added to every tube.
#'   Set aside like an artifact, without a warning, and listed in
#'   \code{attr(, "runs")$declared_spikes}. Default NULL.
#' @param untested_policy \code{"admit"} (default), \code{"hold_blanks"} or
#'   \code{"block"}: what the suggested \code{admit} does with untested and
#'   inconclusive units. See Status.
#' @param accept_llm_roles Logical. Let \code{llm_role} from the decision record
#'   stand in for an identity disposition where no person has recorded one,
#'   and \code{llm_marker_unusable} exclude that marker where no person has
#'   recorded a library disposition (it can only exclude, never keep).
#'   Default FALSE.
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
#'     \code{"neither"} or \code{"not_assessed"}.}
#'   \item{\code{identity_status}}{\code{"concordant"}, \code{"discordant"},
#'     \code{"suspect"}, \code{"inconclusive"} or \code{"untested"}.}
#'   \item{\code{identity_status_reason}}{See Status.}
#'   \item{\code{admit_as}}{\code{"control"}, \code{"sample"},
#'     \code{"positive_control"} or \code{NA}
#'     (not admitted); reflects any reassignment.}
#'   \item{\code{control_usability}, \code{sample_viability}}{Per marker; see
#'     Decision scopes.}
#'   \item{\code{admit}}{Logical. The gate. Filter on this and read
#'     \code{admit_as} for the role; the original \code{control_samples} vector
#'     is no longer the control set.}
#' }
#' Attribute \code{"units"}: one row per sample x marker x run with the
#' evidence (\code{depth}, \code{richness}, \code{diversity_n1},
#' \code{diversity_ratio}, \code{composition_share_other},
#' \code{n_libraries_assessable}, \code{composition_power},
#' \code{library_status}, \code{run_status}, \code{n_markers_flagged},
#' \code{n_markers_assessable}, \code{top_taxa}, and \code{top_taxon} with
#' \code{top_taxon_share}: the single most abundant feature and its share of
#' the unit's reads, with run-wide artifacts and declared spikes set aside.
#' Dominance is reported as evidence for a reviewer and never acted on: a
#' blank that is 96\% one field fish is worth a look in any marker, and the
#' number needs no taxonomy, habitat or scope), the verdict columns,
#' \code{identity_status_reason}, \code{issue_type}, \code{tube_flagged}, \code{hold_reason},
#' \code{confidence}, \code{reason}, \code{disposition}, \code{disposition_source},
#' \code{pending_review}, \code{excluded_library_issue},
#' \code{control_usability} (for units whose role is control: \code{"usable"},
#' \code{"contaminated_in_marker"}, \code{"kept_by_decision"} or
#' \code{"excluded_by_decision"}), \code{sample_viability} (for units whose
#' role is sample: \code{"viable"}, \code{"thin"} or \code{"non_viable"}),
#' \code{admit_as} and \code{admit}. Attribute
#' \code{"review_queue"}: the units that need a person, in decision-record
#' shape. Attribute \code{"runs"}: one row per run x marker, with admitted
#' control and sample counts, \code{control_status} (\code{"ok"},
#' \code{"no_admitted_control"} or \code{"no_controls_labelled"}) and the
#' field \code{top_taxa}, \code{run_wide_artifacts} and \code{declared_spikes}
#' (see Run-wide artifacts). Attribute \code{"failed_libraries"}: the
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
                                     control_samples = NULL,
                                     failed_libraries = NULL,
                                     taxon_label_col = NULL,
                                     diversity_blank_max = 0.5,
                                     composition_share = 0.5,
                                     artifact_fraction = 0.9,
                                     spike_taxa = NULL,
                                     untested_policy = c("admit", "hold_blanks", "block"),
                                     accept_llm_roles = FALSE,
                                     decisions_path = NULL,
                                     on_pending = c("warn", "error", "ignore"),
                                     verbose = TRUE) {
  untested_policy <- match.arg(untested_policy)
  on_pending <- match.arg(on_pending)
  if (!is.data.frame(input_df)) stop("'input_df' must be a data frame.", call. = FALSE)
  for (col in c(library_col, sample_col, marker_col, run_col, count_col, taxon_col, taxon_label_col)) {
    if (!col %in% names(input_df)) {
      stop(sprintf("Column '%s' not found in input_df.", col), call. = FALSE)
    }
  }
  if (is.null(control_samples) || !length(control_samples)) {
    control_samples <- character(0)
    warning("No labelled controls: nothing can be compared with a blank, so every ",
      "unit is reported 'untested' (no_blanks). That is no evidence of a problem, ",
      "not evidence of its absence.", call. = FALSE)
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
      control_samples = if (length(control_samples)) control_samples else NULL,
      verbose = verbose
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
  if (length(control_samples) && !any(d$is_ctl)) {
    warning("None of 'control_samples' matched a sample or library in input_df.", call. = FALSE)
  }

  # --- 2. Unit evidence, without run-wide artifacts or declared spikes ---
  # A feature in nearly every field library of a run that also dominates the
  # run's blanks is in every tube whatever the tube is -- a spike the user
  # added, a provider's positive control reaching every library, or
  # cross-contamination. It carries no identity information, so it is set aside
  # from composition and diversity, and it is REPORTED: unless the user
  # declared it in spike_taxa, its cause is a question to investigate.
  rk_d <- paste(d$marker, d$run, sep = "\r")
  d$declared_spike <- FALSE
  if (length(spike_taxa)) {
    d$declared_spike <- d$feature %in% spike_taxa |
      (!is.null(taxon_label_col) & d$label_name %in% spike_taxa)
  }
  d$artifact <- FALSE
  if (!is.null(artifact_fraction)) {
    if (!is.numeric(artifact_fraction) || length(artifact_fraction) != 1L ||
      is.na(artifact_fraction) || artifact_fraction <= 0 || artifact_fraction > 1) {
      stop("'artifact_fraction' must be a single number in (0, 1], or NULL.", call. = FALSE)
    }
    fk <- !d$is_ctl & !d$excluded & d$reads > 0
    n_units <- tapply(d$unit[fk], rk_d[fk], function(z) length(unique(z)))
    prev <- tapply(d$unit[fk], paste(rk_d[fk], d$feature[fk], sep = "\r"),
      function(z) length(unique(z)))
    run_of <- sub("\r[^\r]*$", "", names(prev))
    frac <- prev / as.numeric(n_units[run_of])
    ubi <- names(frac)[frac >= artifact_fraction & as.numeric(n_units[run_of]) >= 5]
    # Common environmental taxa can also sit in nearly every field unit; what
    # marks a run-wide artifact is that it also DOMINATES the run's blanks.
    # Require both, or real community signal is removed.
    ck <- d$is_ctl & !d$excluded & d$reads > 0
    if (length(ubi) && any(ck)) {
      c_tot <- tapply(d$reads[ck], d$unit[ck], sum)
      c_key <- paste(rk_d[ck], d$feature[ck], sep = "\r")
      share <- d$reads[ck] / as.numeric(c_tot[d$unit[ck]])
      dom <- tapply(share >= 0.5, c_key, sum)
      n_ctl <- tapply(d$unit[ck], rk_d[ck], function(z) length(unique(z)))
      dom_frac <- as.numeric(dom[ubi]) / as.numeric(n_ctl[sub("\r[^\r]*$", "", ubi)])
      ubi <- ubi[!is.na(dom_frac) & dom_frac >= 0.5]
    } else {
      ubi <- character(0)
    }
    d$artifact <- paste(rk_d, d$feature, sep = "\r") %in% ubi & !d$declared_spike
  }
  d$ubiquitous <- d$artifact | d$declared_spike
  u <- .sig_unit_stats(d[!d$ubiquitous, , drop = FALSE])
  missing_u <- setdiff(unique(d$unit), u$unit)
  if (length(missing_u)) {
    # a unit holding ONLY ubiquitous features: an empty (clean) library once the spike is set aside
    z <- .sig_unit_stats(d[d$unit %in% missing_u, , drop = FALSE])
    z$depth <- 0
    z$richness <- 0L
    z$diversity_n1 <- 0
    u <- rbind(u, z[, names(u)])
  }
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
  comp <- .sig_composition(d[!d$ubiquitous, , drop = FALSE], composition_share)
  u <- merge(u, comp, by = "unit", all.x = TRUE, sort = FALSE)
  u$n_libraries_assessable[is.na(u$n_libraries_assessable)] <- 0L
  u$composition_power[is.na(u$composition_power)] <- "none"

  # --- 4. Appearance and status ---
  u$run_has_controls <- stats::ave(u$identity_label == "blank", u$marker, u$run, FUN = any)
  u$n_field_units_run <- stats::ave(u$identity_label == "sample" & u$n_libraries_kept > 0,
    u$marker, u$run, FUN = sum)
  ap <- .sig_appearance(u, diversity_blank_max)
  u$identity_appearance <- ap$appearance
  u$identity_status <- ap$status
  u$identity_status_reason <- ap$status_reason
  u$issue_type <- ap$issue_type
  u$confidence <- ap$confidence
  u$issue_type[u$identity_status %in% c("concordant", "inconclusive", "untested")] <- NA_character_

  # cross-marker agreement, identity flags only
  id_flag <- u$identity_status %in% c("discordant", "suspect") & u$issue_type %in% "identity"
  assessable <- u$identity_status %in% c("concordant", "discordant", "suspect") &
    !(u$issue_type %in% "library")
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
  # Dominance: evidence only, never acted on. Computed with run-wide artifacts
  # and declared spikes set aside, since a clean blank on a spiked run is
  # dominated by the spike.
  dom <- .sig_dominance(d[!d$ubiquitous, , drop = FALSE], u$unit)
  u$top_taxon <- dom$top_taxon
  u$top_taxon_share <- dom$top_taxon_share
  u$reason <- .sig_reason(u, diversity_blank_max)

  # --- 5. Decisions and admission ---
  dec <- .sig_read_decisions(decisions_path)
  u <- .sig_apply_decisions(u, dec, untested_policy, accept_llm_roles)

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
  .run_feats <- function(flag) vapply(seq_len(nrow(runs)), function(i) {
    k <- flag & d$marker == runs$marker[i] & d$run == runs$run[i]
    if (!any(k)) return(NA_character_)
    nm <- if (!is.null(taxon_label_col)) d$label_name[k] else d$feature[k]
    bad <- is.na(nm) | !nzchar(nm)
    nm[bad] <- d$feature[k][bad]
    paste(sort(unique(nm)), collapse = "; ")
  }, character(1))
  runs$run_wide_artifacts <- .run_feats(d$artifact)
  runs$declared_spikes <- .run_feats(d$declared_spike)
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
  out$identity_status_reason <- u$identity_status_reason[m]
  out$control_usability <- u$control_usability[m]
  out$sample_viability <- u$sample_viability[m]
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
  nx <- sum(u$control_usability %in% "contaminated_in_marker" & !u$pending_review)
  if (verbose && nx) {
    message(sprintf(paste0("  not a control in %d marker(s) of confirmed blanks: their own evidence ",
      "in that marker looks contaminated (control_usability = \"contaminated_in_marker\"); ",
      "the same tubes' other markers were judged on their own evidence."), nx))
  }
  # Admitting a unit no test could judge is a policy choice, so say how many,
  # and why, every time -- "no evidence of a problem" is not "checked clean".
  nt <- u$admit & u$identity_status %in% c("untested", "inconclusive")
  if (any(nt)) {
    why <- table(paste(u$identity_status[nt], u$identity_status_reason[nt], sep = "/"))
    message(sprintf(paste0(
      "  admitted WITHOUT a discriminating test: %d unit(s) (%s). This is no evidence ",
      "of a problem, not evidence of none; untested_policy = \"%s\"."),
      sum(nt), paste(names(why), why, sep = " ", collapse = ", "), untested_policy))
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
  art <- runs[!is.na(runs$run_wide_artifacts), , drop = FALSE]
  if (nrow(art)) {
    warning(sprintf(paste0(
      "Run-wide artifact(s) on %d run(s) x marker: a feature in >= %.0f%% of field libraries that ",
      "also dominates the blanks (%s). It is in every tube whatever the tube is -- a spike, a ",
      "provider's positive control reaching every library, or cross-contamination. It was set ",
      "aside from identity evidence. If you added it on purpose, declare it in spike_taxa; ",
      "otherwise ask the provider. See attr(, \"runs\")$run_wide_artifacts."),
      nrow(art), 100 * artifact_fraction,
      paste(utils::head(unique(paste0(art$marker, " ", art$run, ": ", art$run_wide_artifacts)), 4), collapse = "; ")
    ), call. = FALSE)
  }
  n_pend <- sum(u$pending_review)
  if (n_pend && on_pending != "ignore") {
    pu <- u[u$pending_review, , drop = FALSE]
    # Split by WHY a unit is held: a concordant unit held only because another
    # marker of its tube was flagged would otherwise read as a gate error.
    own <- pu[!pu$hold_reason %in% "tube", , drop = FALSE]
    n_tube <- sum(pu$hold_reason %in% "tube")
    msg <- sprintf(paste0(
      "%d unit(s) from %d sample(s) await an identity decision and are NOT admitted: ",
      "%d on their own evidence (%s)%s. Record a disposition%s, or see attr(, \"review_queue\")."
    ),
    n_pend, length(unique(pu$sample)), nrow(own),
    if (nrow(own)) paste(names(table(own$identity_status)), table(own$identity_status), sep = " ", collapse = ", ") else "none",
    if (n_tube) sprintf(paste0("; %d held only because another marker of the same tube was flagged ",
      "(their own status may be concordant)"), n_tube) else "",
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
  # What the composition test could say about this unit. A run with no control
  # library gives no identity test at all (validate_controls() then calls every
  # sample "consistent" by default, which is not evidence), so it is kept apart.
  run_ctl <- tapply(x$is_ctl, x$site, any)
  vc$site_has_ctl <- as.logical(run_ctl[vc$site])
  pw <- vapply(units, function(z) {
    k <- vc$unit == z
    if (!any(vc$site_has_ctl[k])) return("no_controls")
    p <- vc$power[k & ok]
    if (length(p)) return(if (all(p == "ok")) "ok" else "low")
    if (any(vc$verdict[k] == "untestable_no_headroom")) return("no_headroom")
    if (any(vc$verdict[k] == "untestable")) return("too_few_samples")
    "none"
  }, character(1))
  n_ok[pw == "no_controls"] <- 0L
  n_other[pw == "no_controls"] <- 0L
  sh <- ifelse(n_ok > 0, n_other / pmax(n_ok, 1), NA_real_)
  data.frame(
    unit = units, n_libraries_assessable = as.integer(n_ok),
    composition_share_other = round(sh, 3), composition_power = pw,
    composition_other = !is.na(sh) & sh >= composition_share,
    stringsAsFactors = FALSE
  )
}

#' The appearance and status rules; see the roxygen of classify_sample_identity()
#'
#' Status separates what a test FOUND from why a test could not be made:
#' concordant / discordant / suspect (tested, with an answer), inconclusive
#' (tested, could not discriminate), untested (no test ran). status_reason says
#' which evidence decided it, or why none could.
#' @noRd
.sig_appearance <- function(u, diversity_blank_max) {
  n <- nrow(u)
  ap <- character(n)
  st <- character(n)
  why <- character(n)
  it <- character(n)
  cf <- ifelse(u$composition_power == "ok", "ok", "low")
  run_failed <- u$run_status %in% "failed"
  collapsed <- u$n_libraries_kept == 0 & u$n_libraries > 0
  div_known <- !is.na(u$diversity_ratio)
  rich <- div_known & u$diversity_ratio >= diversity_blank_max
  other <- u$composition_other %in% TRUE
  pw <- u$composition_power
  for (i in seq_len(n)) {
    if (u$identity_label[i] == "blank") {
      it[i] <- "identity"
      if (run_failed[i] || collapsed[i]) {
        if (rich[i]) {
          ap[i] <- "neither"
          st[i] <- "suspect"
          why[i] <- "diversity_on_failed_run"
        } else {
          ap[i] <- "not_assessed"
          st[i] <- "untested"
          why[i] <- "uncomparable"
        }
        cf[i] <- "low"
      } else if (other[i]) {
        ap[i] <- "valid_sample"
        st[i] <- "discordant"
        why[i] <- "composition"
      } else if (rich[i]) {
        ap[i] <- "neither"
        st[i] <- "suspect"
        why[i] <- "diversity"
      } else if (div_known[i]) {
        # low diversity against an external reference is a real test that passed
        ap[i] <- "valid_blank"
        st[i] <- "concordant"
        why[i] <- "diversity"
      } else if (pw[i] == "ok") {
        ap[i] <- "valid_blank"
        st[i] <- "concordant"
        why[i] <- "composition"
      } else if (pw[i] %in% c("low", "no_headroom")) {
        ap[i] <- "not_assessed"
        st[i] <- "inconclusive"
        why[i] <- "no_power"
      } else {
        ap[i] <- "not_assessed"
        st[i] <- "untested"
        why[i] <- "unreplicated"
      }
    } else {
      if (collapsed[i]) {
        ap[i] <- "neither"
        st[i] <- "suspect"
        why[i] <- "library_failed"
        it[i] <- "library"
      } else if (other[i]) {
        ap[i] <- "valid_blank"
        st[i] <- "discordant"
        why[i] <- "composition"
        it[i] <- "identity"
      } else {
        # the identity test for a sample is whether it resembles the blanks;
        # yield alone says it sequenced, not what it is
        it[i] <- "identity"
        ap[i] <- "valid_sample"
        if (pw[i] == "ok") {
          st[i] <- "concordant"
          why[i] <- "composition"
        } else if (pw[i] %in% c("low", "no_headroom")) {
          st[i] <- "inconclusive"
          why[i] <- "no_power"
        } else if (pw[i] == "no_controls" || !isTRUE(u$run_has_controls[i])) {
          ap[i] <- "not_assessed"
          st[i] <- "untested"
          why[i] <- "no_blanks"
        } else {
          ap[i] <- "not_assessed"
          st[i] <- "untested"
          why[i] <- "unreplicated"
        }
      }
    }
  }
  list(appearance = ap, status = st, status_reason = why, issue_type = it, confidence = cf)
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
    lead <- switch(paste(x$identity_label, x$identity_status, x$identity_status_reason),
      "blank concordant diversity" = "Looks like a clean blank: diversity well below a typical field sample.",
      "blank concordant composition" = "Looks like a clean blank: composition unlike the run's samples.",
      "blank discordant composition" = "Blank that resembles the field samples it was sequenced with: mislabel or carry-over.",
      "blank suspect diversity" = sprintf("Blank carrying a community (diversity >= %.2fx reference) that does not resemble this run's samples; judge it against the blank medium.", diversity_blank_max),
      "blank suspect diversity_on_failed_run" = "Blank at sample-level diversity on a FAILED run; failure only lowers diversity, so it carries a community of its own.",
      "blank untested uncomparable" = "UNTESTED: the run's field libraries failed, so there is nothing valid to compare this blank with. No evidence of a problem; not evidence of a clean blank.",
      "blank untested unreplicated" = "UNTESTED: too few field units on this run, and no diversity reference. No evidence of a problem.",
      "blank inconclusive no_power" = "INCONCLUSIVE: the composition test ran but could not discriminate, and no diversity reference exists.",
      "sample concordant composition" = "Looks like a valid sample.",
      "sample discordant composition" = "Sample that resembles the run's blanks rather than the other samples: a blank labelled as a sample, or a near-empty sample.",
      "sample suspect library_failed" = sprintf("Every library of this sample failed (%s); the extract may be fine in other markers.",
        if (x$run_status %in% "failed") "whole run failed" else "library failure"),
      "sample inconclusive no_power" = "INCONCLUSIVE: the test for resembling a blank ran but could not discriminate on this run. No evidence of a problem.",
      "sample untested no_blanks" = "UNTESTED: no blank on this run to compare with. No evidence of a problem.",
      "sample untested unreplicated" = "UNTESTED: too few field units on this run to test. No evidence of a problem.",
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
#' The single most abundant feature in each unit and its share of the unit's
#' reads, on kept libraries (all libraries when none were kept)
#' @noRd
.sig_dominance <- function(d, units) {
  out <- data.frame(unit = units, top_taxon = NA_character_, top_taxon_share = NA_real_,
    stringsAsFactors = FALSE)
  if (!nrow(d)) return(out)
  has_kept <- tapply(!d$excluded, d$unit, any)
  use <- !d$excluded | !has_kept[d$unit]
  x <- d[use & d$reads > 0, , drop = FALSE]
  if (!nrow(x)) return(out)
  f <- tapply(x$reads, paste(x$unit, x$feature, sep = "\r"), sum)
  key <- names(f)
  fu <- sub("\r.*$", "", key)
  ff <- sub("^[^\r]*\r", "", key)
  tot <- tapply(as.numeric(f), fu, sum)
  o <- order(fu, -as.numeric(f))
  top <- !duplicated(fu[o])
  tu <- fu[o][top]
  tf <- ff[o][top]
  sh <- as.numeric(f)[o][top] / as.numeric(tot[tu])
  # The fallback to the feature id below must be able to fire per unit. `else NA` made `lab` a
  # length-1 vector, and ifelse() returns the length of its TEST, so `lab` collapsed to length 1
  # and top_taxon came back NA for every unit while top_taxon_share stayed populated. A share
  # without a name is worse than neither: 1.0 means "clean spike-dominated blank" or "blank that
  # is 100% one local fish" depending entirely on the name.
  lab <- if ("label_name" %in% names(x)) {
    x$label_name[match(paste(tu, tf), paste(x$unit, x$feature))]
  } else {
    rep(NA_character_, length(tf))
  }
  lab <- ifelse(is.na(lab) | !nzchar(lab), tf, lab)
  m <- match(out$unit, tu)
  out$top_taxon <- lab[m]
  out$top_taxon_share <- round(sh[m], 4)
  out
}

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
.sig_apply_decisions <- function(u, dec, untested_policy, accept_llm_roles = FALSE) {
  u$identity_disposition <- NA_character_
  u$library_disposition <- NA_character_
  u$disposition_source <- NA_character_
  stale <- character(0)
  if (!is.null(dec) && nrow(dec)) {
    all_dec <- dec
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
      u$disposition_source[!is.na(u$identity_disposition)] <- "user"
    }
    lbd <- dec[dec$disposition %in% .SIG_LIBRARY_DISPOSITIONS, , drop = FALSE]
    if (nrow(lbd)) {
      u$library_disposition <- lbd$disposition[match(u$unit, paste(lbd$sample, lbd$marker, lbd$run, sep = "|"))]
      u$disposition_source[!is.na(u$library_disposition) & is.na(u$disposition_source)] <- "user"
    }
    # the LLM's role verdict stands in for a disposition only when asked, and
    # never over a person's decision
    if (isTRUE(accept_llm_roles) && "llm_role" %in% names(all_dec)) {
      r <- all_dec[!is.na(all_dec$llm_role) & nzchar(all_dec$llm_role), c("sample", "llm_role"), drop = FALSE]
      r <- r[!duplicated(r$sample), , drop = FALSE]
      role <- r$llm_role[match(u$sample, r$sample)]
      lab_blank <- u$identity_label == "blank"
      llm_disp <- ifelse(role %in% "blank", ifelse(lab_blank, "confirm_blank", "reassign_to_blank"),
        ifelse(role %in% "sample", ifelse(lab_blank, "reassign_to_sample", "confirm_sample"),
          ifelse(role %in% "positive_control", "reassign_to_positive_control",
            ifelse(role %in% "exclude", "exclude_tube", NA_character_))))
      use <- is.na(u$identity_disposition) & !is.na(llm_disp)
      u$identity_disposition[use] <- llm_disp[use]
      u$disposition_source[use] <- "llm"
    }
    # the LLM's per-marker judgement can only EXCLUDE a marker, never keep one
    # the gate excluded: keeping is a person's call
    if (isTRUE(accept_llm_roles) && "llm_marker_unusable" %in% names(all_dec)) {
      k <- paste(all_dec$sample, all_dec$marker, all_dec$run, sep = "|")
      bad <- k[as.character(all_dec$llm_marker_unusable) %in% "TRUE"]
      use <- is.na(u$library_disposition) & u$unit %in% bad
      u$library_disposition[use] <- "exclude_library"
      u$disposition_source[use & is.na(u$disposition_source)] <- "llm"
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
  role[idd %in% "reassign_to_positive_control"] <- "positive_control"

  st <- u$identity_status
  flagged <- st %in% c("discordant", "suspect")
  id_issue <- u$issue_type %in% "identity"
  lib_issue <- u$issue_type %in% "library"
  # untested / inconclusive: no evidence of a problem. Admitted by default so a
  # thin study can still be analysed (cautiously, with the status carried);
  # "hold_blanks" keeps such blanks out of the control set, "block" holds all.
  weak <- st %in% c("untested", "inconclusive")
  weak_holds <- weak & (untested_policy == "block" |
    (untested_policy == "hold_blanks" & u$identity_label == "blank"))

  id_resolved <- !is.na(idd)
  lib_resolved <- !is.na(u$library_disposition)
  # identity is a property of the tube: an identity flag in ANY marker holds every
  # unit of that sample until the tube is dispositioned (a weak unit holds only
  # itself: an untested library says nothing about the tube's other markers)
  tube_flag <- u$sample %in% u$sample[flagged & id_issue]
  u$tube_flagged <- tube_flag
  # why a unit is held: its OWN evidence, or only its tube's. identity_status
  # always describes the unit's own evidence, so counting flags never double-counts
  u$hold_reason <- ifelse(flagged & id_issue, "own_evidence",
    ifelse(weak_holds, as.character(st),
      ifelse(tube_flag, "tube", NA_character_)))
  needs_id <- (tube_flag | weak_holds) & !id_resolved
  held_by_tube <- tube_flag & !(flagged & id_issue) & !id_resolved
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

  # Identity is per tube, usability per marker: a blank whose OWN evidence in
  # this marker looks contaminated is not a control in this marker, whatever the
  # tube's identity decision. Excluded by default (like a failed library, not
  # pending: excluding is the conservative outcome); keep_library overrides.
  is_ctl <- role == "control"
  own_bad <- is_ctl & u$identity_label == "blank" & flagged & id_issue
  kept <- u$library_disposition %in% "keep_library"
  admit[own_bad & !kept] <- FALSE
  cu <- rep(NA_character_, nrow(u))
  cu[is_ctl] <- "usable"
  cu[own_bad] <- "contaminated_in_marker"
  cu[own_bad & kept] <- "kept_by_decision"
  cu[is_ctl & u$library_disposition %in% "exclude_library"] <- "excluded_by_decision"
  u$control_usability <- cu
  ex_ctl <- own_bad & !kept & id_resolved
  u$reason[ex_ctl] <- paste(u$reason[ex_ctl],
    "NOT A CONTROL IN THIS MARKER: its own evidence here looks contaminated; the tube's other markers are judged on their own evidence. Record keep_library on this unit to override.")

  # Viability is per marker: yield and appearance together. Low yield with a
  # normal composition is a thin sample, not a broken one.
  collapsed <- u$n_libraries_kept == 0 & u$n_libraries > 0
  sv <- ifelse(collapsed | u$library_status %in% "failed", "non_viable",
    ifelse(u$library_status %in% c("low_yield", "low_yield_undetermined"), "thin",
      ifelse(u$library_status %in% "pass", "viable", NA_character_)))
  sv[role != "sample"] <- NA_character_
  u$sample_viability <- sv
  u$excluded_library_issue <- needs_lib
  u$pending_review <- needs_id
  # the queue lists every flagged unit, every weak unit that is held, and any
  # unit already decided (so the record keeps it)
  u$needs_review <- flagged | weak_holds | tube_flag | id_resolved | lib_resolved
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
    "identity_status_reason", "issue_type", "tube_flagged", "hold_reason", "control_usability", "sample_viability", "confidence", "n_markers_flagged", "n_markers_assessable", "depth",
    "richness", "diversity_n1", "diversity_ratio", "composition_share_other",
    "composition_power", "run_status", "reason", "top_taxon", "top_taxon_share", "top_taxa"
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
