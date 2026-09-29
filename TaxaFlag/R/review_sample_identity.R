# Exports: review_sample_identity
# Internal helpers: .sir_tube_items, .sir_build_prompt, .sir_parse, .SIR_VERDICTS

.SIR_ROLES <- c("blank", "sample", "positive_control", "exclude", "unknown")
# the role a verdict implies, when the model gives a verdict but no role
.SIR_VERDICT_ROLE <- c(
  clean_blank = "blank", contaminated_blank = "blank",
  sample_labelled_as_blank = "sample", positive_control_labelled_as_blank = "positive_control",
  blank_labelled_as_sample = "blank", valid_sample = "sample", uncertain = "unknown"
)
.SIR_VERDICTS <- c(
  "clean_blank", "contaminated_blank", "sample_labelled_as_blank",
  "positive_control_labelled_as_blank", "blank_labelled_as_sample",
  "valid_sample", "uncertain"
)

#' LLM Advice on Samples That Do Not Look Like Their Label
#'
#' Sends each tube held back by \code{\link{classify_sample_identity}} for an
#' identity question to an LLM, with its taxa in every marker and the
#' community of the field samples it was sequenced with, and asks for a
#' plausibility judgement: is this a clean blank, a contaminated blank, a field
#' sample carrying a blank's label, or the reverse? It also gives a ROLE: how the
#' tube should be used (blank, sample, positive control, exclude, unknown). The
#' answer is written to \code{llm_} columns beside the decision record.
#' Admission is the workflow's choice: by default a person still records the
#' \code{disposition}, and \code{classify_sample_identity(accept_llm_roles =
#' TRUE)} admits on \code{llm_role} wherever no person has decided.
#'
#' @section Why an LLM here:
#' The judgement that settles these cases is a plausibility argument over a
#' taxon list, which the statistics cannot make. "A field blank containing
#' three bloom-forming dinoflagellates and a copepod community is implausible"
#' needs knowledge of what those taxa are and where they live. So does its
#' counterpart: a blank holding a human, a few soil fungi and one hopped read
#' is a clean blank however many features it has. The deterministic evidence
#' (composition, diversity, cross-marker agreement) is given to the model as
#' well, so that a disagreement between the two is visible.
#'
#' @section One question per tube:
#' Identity is a property of the tube, not of a library, so the model is asked
#' once per sample and shown every marker together, including markers where
#' the tube looked concordant. Library failures
#' (\code{issue_type == "library"}) are not sent: they are a yield question,
#' and \code{\link{flag_failed_libraries}} has already answered it.
#'
#' @section Unreviewed tubes:
#' A tube the model does not answer is re-asked, alone, up to
#' \code{max_retries} times. Omissions come mostly from a batch that ran out of
#' output tokens: a reasoning model can spend a whole \code{max_tokens} budget
#' thinking about four tubes and return no text. On one real study, 13 of 44
#' tubes went unanswered at 4 tubes per call and 4000 tokens; asked singly,
#' all but two were answered. Raise \code{max_tokens} before raising
#' \code{tubes_per_call}. It is never cached, and it is listed in
#' \code{attr(, "unreviewed_samples")}. Because an LLM verdict never admits
#' anything, an unreviewed tube is not lost: it simply has no advice. The
#' \code{on_unreviewed} argument controls how loudly that is reported.
#'
#' @param identity The result of \code{classify_sample_identity()}, with its
#'   attributes intact (read it immediately; a dplyr verb drops them).
#' @param blank_medium Character or NULL. What a blank is filled with, e.g.
#'   "tap water". A blank is judged acceptable when its contents are
#'   consistent with its medium or with handling, so this decides many
#'   verdicts. Either one string for every tube, or a NAMED character vector
#'   giving each tube its own medium (names are sample ids; tubes not named
#'   read "not stated"). Use the per-tube form whenever media differ: a
#'   reverse-osmosis blank should be near-empty, so a tap-water community in
#'   it is anomalous, and judging it against "tap water" would explain away
#'   exactly what should be flagged. NULL tells the model the medium is not
#'   stated. Default NULL.
#' @param target_groups Character or NULL. The groups the study's samples are
#'   meant to measure, e.g. "macroalgae, macroinvertebrates, intertidal
#'   fishes". A blank holding these at more than a trace is judged
#'   contaminated even when a plausible medium community is also present: a
#'   medium explains its own community, never the target signal, and a control
#'   carrying the target signal makes contamination checks permissive in
#'   exactly the direction nobody checks. NULL tells the model the groups are
#'   not stated. Default NULL.
#' @param context Character. What a blank is in this study and where the
#'   samples came from, e.g. "Field blanks are distilled water poured through
#'   a filter at the site. Samples are rocky-intertidal swabs, southern
#'   California." Required: the verdict depends on it, and a wrong assumption
#'   is silent.
#' @param llm_fn Function taking a prompt string (and optionally
#'   \code{max_tokens}) and returning the model's text. Default
#'   \code{getOption("TaxaID.llm_fn", TaxaTools::call_api)}. Under fully
#'   namespaced calls pass it explicitly; see \code{\link{review_assignments}}
#'   for why.
#' @param model_label Character or \code{NULL}. A name for the model behind
#'   \code{llm_fn}, recorded in the cache key so one model's disposition is
#'   never served to a call asking another. Default \code{NULL} derives an
#'   identity from \code{options("TaxaID.provider")} and from \code{llm_fn}.
#'   See \code{\link{review_assignments}} for what that cannot separate.
#' @param tubes_per_call Integer. Tubes per LLM call. Default 4.
#' @param max_tokens Integer or NULL. Forwarded to \code{llm_fn}. Default NULL.
#' @param max_retries Integer. Re-asks for tubes the model omitted. Default 2.
#' @param cache_dir Character or NULL. One file per tube, keyed on the full
#'   prompt item and \code{context}, so changed evidence is a miss. Pruned by
#'   \code{\link{taxaflag_clear_cache}}. Default NULL (no cache).
#' @param decisions_path Character or NULL. If given, the \code{llm_} columns
#'   are merged into this decision record without touching anything the user
#'   entered. Default NULL.
#' @param on_unreviewed \code{"warn"} (default), \code{"error"} or
#'   \code{"ignore"}.
#' @param verbose Logical. Default TRUE.
#'
#' @return The review queue (\code{attr(identity, "review_queue")}) with
#'   \code{llm_verdict} (one of \code{"clean_blank"},
#'   \code{"contaminated_blank"}, \code{"sample_labelled_as_blank"},
#'   \code{"positive_control_labelled_as_blank"},
#'   \code{"blank_labelled_as_sample"}, \code{"valid_sample"},
#'   \code{"uncertain"}), \code{llm_role} (\code{"blank"}, \code{"sample"},
#'   \code{"positive_control"}, \code{"exclude"} or \code{"unknown"}: how the
#'   tube should be used; \code{classify_sample_identity(accept_llm_roles = TRUE)}
#'   admits on it; a contaminated blank is still role \code{"blank"}),
#'   \code{llm_suggested_disposition}, \code{llm_confidence}
#'   (high/moderate/low) and \code{llm_rationale} added per sample, and
#'   \code{llm_marker_unusable} per unit: \code{TRUE} where the model judged
#'   this marker's result contaminated. Identity is per tube, usability per
#'   marker. With \code{accept_llm_roles = TRUE} it can only EXCLUDE a marker,
#'   never keep one the gate excluded. Attributes \code{"unreviewed_samples"} (always present) and
#'   \code{"llm_prompts"}.
#'
#' @seealso \code{\link{classify_sample_identity}}.
#'
#' @examples
#' \dontrun{
#' gate <- classify_sample_identity(reads, control_samples = blanks,
#'                                  taxon_label_col = "species",
#'                                  decisions_path = "identity_decisions.csv")
#' advice <- review_sample_identity(gate,
#'   context = "Field blanks are distilled water filtered on site.",
#'   decisions_path = "identity_decisions.csv")
#' }
#' @export
review_sample_identity <- function(identity,
                                   context,
                                   blank_medium = NULL,
                                   target_groups = NULL,
                                   llm_fn = getOption("TaxaID.llm_fn", TaxaTools::call_api),
                                   model_label = NULL,
                                   tubes_per_call = 4L,
                                   max_tokens = NULL,
                                   max_retries = 2L,
                                   cache_dir = NULL,
                                   decisions_path = NULL,
                                   on_unreviewed = c("warn", "error", "ignore"),
                                   verbose = TRUE) {
  on_unreviewed <- match.arg(on_unreviewed)
  u <- attr(identity, "units")
  q <- attr(identity, "review_queue")
  runs <- attr(identity, "runs")
  if (is.null(u) || is.null(q) || is.null(runs)) {
    stop("'identity' must be the unmodified result of classify_sample_identity() ",
      "(its attributes are missing; read them before any dplyr verb).", call. = FALSE)
  }
  if (missing(context) || !is.character(context) || length(context) != 1L ||
    is.na(context) || !nzchar(trimws(context))) {
    stop("'context' is required: say what a blank is in this study and where the ",
      "samples came from. The verdict depends on it.", call. = FALSE)
  }
  if (!is.null(blank_medium)) {
    nm <- names(blank_medium)
    one <- length(blank_medium) == 1L && is.null(nm)
    per <- !is.null(nm) && all(!is.na(nm) & nzchar(nm)) && !anyDuplicated(nm)
    if (!is.character(blank_medium) || !(one || per) || anyNA(blank_medium) ||
      !all(nzchar(trimws(blank_medium)))) {
      stop("'blank_medium' must be one non-empty string (e.g. \"tap water\"), a named ",
        "character vector giving each tube's medium (names = sample ids), or NULL.",
        call. = FALSE)
    }
  }
  if (!is.null(target_groups) && (!is.character(target_groups) || length(target_groups) != 1L ||
    is.na(target_groups) || !nzchar(trimws(target_groups)))) {
    stop("'target_groups' must be a single non-empty string, e.g. ",
      "\"macroalgae, macroinvertebrates, intertidal fishes\", or NULL.", call. = FALSE)
  }
  if (!is.function(llm_fn)) stop("'llm_fn' must be a function.", call. = FALSE)
  if (all(is.na(u$top_taxa))) {
    stop("classify_sample_identity() was run without 'taxon_label_col', so there are ",
      "no taxa to review. Re-run it with a name column.", call. = FALSE)
  }

  items <- .sir_tube_items(u, runs, blank_medium)
  q$llm_verdict <- NA_character_
  q$llm_role <- NA_character_
  q$llm_suggested_disposition <- NA_character_
  q$llm_confidence <- NA_character_
  q$llm_rationale <- NA_character_
  q$llm_marker_unusable <- NA
  if (!length(items)) {
    if (verbose) message("review_sample_identity: no tube awaits an identity decision.")
    attr(q, "unreviewed_samples") <- character(0)
    attr(q, "llm_prompts") <- list()
    return(q)
  }

  # The reviewer belongs in the key: a disposition is one model's judgement,
  # and the prefix went to v2 when it was added, so entries written before the
  # fix are a miss once. See .review_reviewer_id().
  # the medium is in each tube's own text (it can differ by tube), so the item
  # carries it into the key
  ctx_key <- paste("sir-v5", .review_reviewer_id(llm_fn, model_label),
    trimws(context), trimws(target_groups %||% ""),
    sep = "\u0001"
  )
  keys <- vapply(items, function(it) paste(ctx_key, it, sep = "\u0001"), character(1))
  answers <- list()
  if (!is.null(cache_dir)) {
    if (verbose && length(list.files(cache_dir, pattern = "_identity_review\\.rds$"))) {
      message(
        "review_sample_identity: the cache key now records which model ",
        "answered, so dispositions cached before this change are a miss once ",
        "and will be re-asked."
      )
    }
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
    paths <- file.path(cache_dir, paste0(vapply(keys, .review_cache_hash, character(1)),
      "_identity_review.rds"))
    names(paths) <- names(items)
    for (s in names(items)) {
      ent <- .review_cache_read(paths[[s]], keys[[s]])
      if (!is.null(ent)) answers[[s]] <- ent
    }
  }
  todo <- setdiff(names(items), names(answers))
  if (verbose) {
    message(sprintf("review_sample_identity: %d tube(s); %d cached, %d to ask.",
      length(items), length(items) - length(todo), length(todo)))
  }

  prompts <- list()
  attempt <- 0L
  while (length(todo) && attempt <= max_retries) {
    # re-asks go one tube per call: an omission is most often a batch that ran
    # out of output tokens (a thinking model can spend them all before answering)
    per <- if (attempt == 0L) max(1L, as.integer(tubes_per_call)) else 1L
    batches <- split(todo, ceiling(seq_along(todo) / per))
    for (b in seq_along(batches)) {
      ids <- batches[[b]]
      prompt <- .sir_build_prompt(items[ids], context, blank_medium, target_groups)
      label <- sprintf("%d.%d", attempt, b)
      prompts[[label]] <- prompt
      resp <- tryCatch(
        if (is.null(max_tokens)) llm_fn(prompt) else llm_fn(prompt, max_tokens = max_tokens),
        error = function(e) {
          if (verbose) message("  LLM call failed: ", conditionMessage(e))
          NULL
        }
      )
      got <- .sir_parse(resp, ids)
      for (s in names(got)) {
        answers[[s]] <- got[[s]]
        if (!is.null(cache_dir)) .review_cache_write(paths[[s]], keys[[s]], got[[s]])
      }
    }
    todo <- setdiff(names(items), names(answers))
    attempt <- attempt + 1L
    if (length(todo) && verbose && attempt <= max_retries) {
      message(sprintf("  %d tube(s) unanswered; re-asking.", length(todo)))
    }
  }

  for (s in names(answers)) {
    k <- q$sample == s
    a <- answers[[s]]
    q$llm_verdict[k] <- a$verdict
    q$llm_role[k] <- if (!is.null(a$role)) a$role else unname(.SIR_VERDICT_ROLE[a$verdict])
    q$llm_suggested_disposition[k] <- a$disposition
    q$llm_confidence[k] <- a$confidence
    q$llm_rationale[k] <- a$rationale
    um <- a$unusable_markers[[1]]
    q$llm_marker_unusable[k] <- q$marker[k] %in% um
  }
  attr(q, "unreviewed_samples") <- todo
  attr(q, "llm_prompts") <- prompts

  if (!is.null(decisions_path)) {
    dec <- .sig_read_decisions(decisions_path)
    .sig_write_decisions(q, dec, decisions_path)
  }
  if (length(todo) && on_unreviewed != "ignore") {
    msg <- sprintf("%d tube(s) have no LLM advice after %d re-ask(s): %s. They still need a disposition; the advice is optional.",
      length(todo), max_retries, paste(utils::head(todo, 10), collapse = ", "))
    if (on_unreviewed == "error") stop(msg, call. = FALSE)
    warning(msg, call. = FALSE)
  }
  if (verbose) {
    v <- vapply(answers, function(a) a$verdict, character(1))
    if (length(v)) print(table(llm_verdict = v))
  }
  q
}

#' One text block per tube awaiting an identity decision
#' @noRd
.sir_tube_items <- function(u, runs, blank_medium = NULL) {
  held <- u$pending_review & !(u$issue_type %in% "library")
  tubes <- unique(u$sample[held])
  if (!length(tubes)) return(list())
  out <- lapply(tubes, function(s) {
    x <- u[u$sample == s, , drop = FALSE]
    x <- x[order(x$marker, x$run), , drop = FALSE]
    lines <- vapply(seq_len(nrow(x)), function(i) {
      r <- x[i, ]
      fr <- runs$field_top_taxa[runs$marker == r$marker & runs$run == r$run]
      ub <- c(runs$run_wide_artifacts[runs$marker == r$marker & runs$run == r$run],
        runs$declared_spikes[runs$marker == r$marker & runs$run == r$run])
      ub <- ub[!is.na(ub)]
      ub <- if (length(ub)) paste(ub, collapse = "; ") else "(none)"
      sprintf(paste0(
        "  [%s, run %s] gate: %s (looks like %s). %s reads, %d features, effective diversity %.2fx a typical field sample of this marker. ",
        "Composition: %s. Dominant taxon (run-wide artifacts set aside): %s.\n    taxa in this tube: %s\n    field samples on this run: %s\n",
        "    in every tube of this run whatever the tube (run-wide artifact or declared spike): %s"
      ),
      r$marker, r$run, r$identity_status, r$identity_appearance,
      format(round(r$depth), big.mark = ",", trim = TRUE), as.integer(r$richness),
      ifelse(is.na(r$diversity_ratio), NA_real_, r$diversity_ratio),
      if (r$n_libraries_assessable > 0) {
        sprintf("%.0f%% of replicate libraries resemble the other label (test power %s)",
          100 * r$composition_share_other, r$composition_power)
      } else {
        "not testable"
      },
      if (!is.null(r$top_taxon_share) && !is.na(r$top_taxon_share)) {
        sprintf("%s %.0f%%", r$top_taxon, 100 * r$top_taxon_share)
      } else "(none)",
      ifelse(is.na(r$top_taxa), "(none)", r$top_taxa),
      ifelse(length(fr) && !is.na(fr[1]), fr[1], "(none)"),
      ub
      )
    }, character(1))
    med <- if (is.null(blank_medium)) "not stated" else if (is.null(names(blank_medium))) {
      trimws(blank_medium)
    } else if (s %in% names(blank_medium)) trimws(blank_medium[[s]]) else "not stated"
    sprintf("TUBE %s -- labelled %s; blank medium for this tube: %s\n%s", s,
      toupper(x$identity_label[1]), med, paste(lines, collapse = "\n"))
  })
  names(out) <- tubes
  out
}

#' @noRd
.sir_build_prompt <- function(items, context, blank_medium = NULL, target_groups = NULL) {
  medium <- if (is.null(blank_medium)) "not stated" else if (is.null(names(blank_medium))) {
    trimws(blank_medium)
  } else "stated per tube below; media differ between tubes, so judge each tube against its own" 
  targets <- if (is.null(target_groups)) "not stated" else trimws(target_groups)
  paste0(
    "You are reviewing negative controls and field samples in a DNA metabarcoding study, ",
    "before any of them are analysed. Each tube below was held back because its contents ",
    "do not look like its label. Judge, from the taxa, what the tube most plausibly is, and ",
    "how it should be used.\n\n",
    "STUDY CONTEXT: ", trimws(context), "\n",
    "BLANK MEDIUM (what a blank is filled with): ", medium, "\n",
    "STUDY TARGET GROUPS (what the samples are meant to measure): ", targets, "\n\n",
    "GUIDELINES\n",
    "- A blank is acceptable when its contents are consistent with its MEDIUM or with ",
    "HANDLING. Handling signals: human, common fungi and moulds, reagent contaminants, a ",
    "scattering of low-count reads also found in the run's field samples. The medium can ",
    "carry a community of its own: tap water carries its source water's freshwater organisms ",
    "(fishes, invertebrates, algae, protists), and tap water varies in cleanliness. Many ",
    "features alone do not make a blank dirty if they are of these kinds (clean_blank, role ",
    "blank).\n",
    "- A PURIFIED medium (reverse-osmosis, distilled, deionised or molecular-grade water) should ",
    "be near-empty. A community in it, even a tap-water-like one, is NOT explained by the ",
    "medium: judge it as handling or contamination.\n",
    "- A medium explains its OWN community, never the study's target groups. A blank holding ",
    "taxa of the STUDY TARGET GROUPS at more than a trace (more than a few low-count reads, ",
    "for example over about 1% of its reads or across many features) is NOT acceptable, even ",
    "when a plausible medium or handling community is also present: a control carrying the ",
    "target signal hides contamination of the samples. Judge the target-group share by ",
    "itself; do not let a medium community dilute it (contaminated_blank; or ",
    "sample_labelled_as_blank if it matches the run's field samples).\n",
    "- IDENTITY IS PER TUBE, USABILITY IS PER MARKER. A contaminated blank is still a blank ",
    "(role blank): list in unusable_markers the markers whose result here is contaminated. ",
    "A marker that cannot amplify the contaminant is not biased by it (12S does not amplify ",
    "protists or algae), so it can stay usable. The inference runs one way only: a clean ",
    "result in an insensitive marker never clears a sensitive one. Use role exclude only if ",
    "the tube should not be used in ANY marker.\n",
    "- A blank is NOT acceptable when it holds a community that neither its medium nor ",
    "handling explains, in particular taxa of the SAMPLED environment. If that community ",
    "matches the run's field samples, suspect a mislabel or carry-over ",
    "(sample_labelled_as_blank, role sample). If it is from the sampled environment but not ",
    "these samples, suspect contamination (contaminated_blank, role blank, with the affected ",
    "markers in unusable_markers). Whether a taxon is inside or outside the study's analytical ",
    "scope says nothing about contamination: out-of-scope taxa (plankton in a benthic study, ",
    "say) are valid environmental signal, not lab contaminants.\n",
    "- A feature listed as being in every tube of the run is a run-wide artifact (a spike, a ",
    "provider's positive control reaching every library, or cross-contamination). It says ",
    "nothing about what the tube is; judge the tube by everything else it holds.\n",
    "- A tube labelled as a blank that holds a mock community that is NOT in every tube of the ",
    "run may be a positive control carrying a blank's label ",
    "(positive_control_labelled_as_blank, role positive_control).\n",
    "- A tube labelled as a sample that holds only medium/handling signals, or almost nothing, ",
    "may be a blank carrying a sample label (blank_labelled_as_sample, role blank).\n",
    "- Use every marker shown: agreement across markers is strong evidence; disagreement ",
    "should lower your confidence.\n",
    "- If the evidence does not support a judgement, say 'uncertain' with role 'unknown'. ",
    "Do not guess.\n\n",
    "Allowed verdicts: ", paste(.SIR_VERDICTS, collapse = ", "), ".\n",
    "Allowed roles (how the tube should be used): ", paste(.SIR_ROLES, collapse = ", "), ".\n",
    "Allowed suggested_disposition: ", paste(.SIG_IDENTITY_DISPOSITIONS, collapse = ", "), ".\n\n",
    "TUBES\n", paste(unlist(items), collapse = "\n\n"), "\n\n",
    "Respond with ONLY a JSON array, one object per tube, in this form:\n",
    "[{\"sample\": \"<tube id>\", \"verdict\": \"...\", \"role\": \"...\", \"suggested_disposition\": \"...\", ",
    "\"unusable_markers\": [\"<marker>\", ...], ",
    "\"confidence\": \"high|moderate|low\", \"rationale\": \"one or two sentences naming the taxa that decided it\"}]"
  )
}

#' Parse the JSON reply into one list per tube; unknown values become NA
#' @noRd
.sir_parse <- function(resp, ids) {
  if (is.null(resp) || !is.character(resp) || !length(resp)) return(list())
  txt <- paste(resp, collapse = "\n")
  txt <- sub("(?s)^.*?(\\[.*\\]).*$", "\\1", txt, perl = TRUE)
  p <- .parse_json_text(txt)
  if (is.null(p)) p <- .recover_truncated_json(txt)
  if (!is.data.frame(p) || !"sample" %in% names(p)) return(list())
  ok_disp <- c(.SIG_IDENTITY_DISPOSITIONS)
  out <- list()
  for (i in seq_len(nrow(p))) {
    s <- trimws(as.character(p$sample[i]))
    if (!s %in% ids) next
    g <- function(col) if (col %in% names(p)) as.character(p[[col]][i]) else NA_character_
    v <- g("verdict")
    d <- g("suggested_disposition")
    cf <- g("confidence")
    ro <- g("role")
    if (is.na(v) || !v %in% .SIR_VERDICTS) next
    if (is.na(ro) || !ro %in% .SIR_ROLES) ro <- unname(.SIR_VERDICT_ROLE[v])
    um <- if ("unusable_markers" %in% names(p)) p$unusable_markers[[i]] else character(0)
    um <- trimws(unlist(strsplit(as.character(unlist(um)), ",")))
    um <- um[!is.na(um) & nzchar(um)]
    out[[s]] <- data.frame(
      verdict = v,
      role = ro,
      disposition = if (!is.na(d) && d %in% ok_disp) d else NA_character_,
      confidence = if (!is.na(cf) && cf %in% c("high", "moderate", "low")) cf else NA_character_,
      rationale = g("rationale"),
      stringsAsFactors = FALSE
    )
    out[[s]]$unusable_markers <- list(um)
  }
  out
}
