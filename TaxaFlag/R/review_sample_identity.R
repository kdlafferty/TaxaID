# Exports: review_sample_identity
# Internal helpers: .sir_tube_items, .sir_build_prompt, .sir_parse, .SIR_VERDICTS

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
#' sample carrying a blank's label, or the reverse? The answer is ADVICE. It
#' is written to \code{llm_} columns beside the decision record, and nothing
#' is admitted on it: a person still records the \code{disposition}.
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
#'   \code{"uncertain"}), \code{llm_suggested_disposition},
#'   \code{llm_confidence} (high/moderate/low) and \code{llm_rationale} added
#'   per sample. Attributes \code{"unreviewed_samples"} (always present) and
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
                                   llm_fn = getOption("TaxaID.llm_fn", TaxaTools::call_api),
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
  if (!is.function(llm_fn)) stop("'llm_fn' must be a function.", call. = FALSE)
  if (all(is.na(u$top_taxa))) {
    stop("classify_sample_identity() was run without 'taxon_label_col', so there are ",
      "no taxa to review. Re-run it with a name column.", call. = FALSE)
  }

  items <- .sir_tube_items(u, runs)
  q$llm_verdict <- NA_character_
  q$llm_suggested_disposition <- NA_character_
  q$llm_confidence <- NA_character_
  q$llm_rationale <- NA_character_
  if (!length(items)) {
    if (verbose) message("review_sample_identity: no tube awaits an identity decision.")
    attr(q, "unreviewed_samples") <- character(0)
    attr(q, "llm_prompts") <- list()
    return(q)
  }

  ctx_key <- paste("sir-v1", trimws(context), sep = "\u0001")
  keys <- vapply(items, function(it) paste(ctx_key, it, sep = "\u0001"), character(1))
  answers <- list()
  if (!is.null(cache_dir)) {
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
      prompt <- .sir_build_prompt(items[ids], context)
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
    q$llm_suggested_disposition[k] <- a$disposition
    q$llm_confidence[k] <- a$confidence
    q$llm_rationale[k] <- a$rationale
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
.sir_tube_items <- function(u, runs) {
  held <- u$pending_review & !(u$issue_type %in% "library")
  tubes <- unique(u$sample[held])
  if (!length(tubes)) return(list())
  out <- lapply(tubes, function(s) {
    x <- u[u$sample == s, , drop = FALSE]
    x <- x[order(x$marker, x$run), , drop = FALSE]
    lines <- vapply(seq_len(nrow(x)), function(i) {
      r <- x[i, ]
      fr <- runs$field_top_taxa[runs$marker == r$marker & runs$run == r$run]
      ub <- runs$ubiquitous_taxa[runs$marker == r$marker & runs$run == r$run]
      ub <- if (length(ub) && !is.na(ub[1])) ub[1] else "(none)"
      sprintf(paste0(
        "  [%s, run %s] gate: %s (looks like %s). %s reads, %d features, effective diversity %.2fx a typical field sample of this marker. ",
        "Composition: %s.\n    taxa in this tube: %s\n    field samples on this run: %s\n",
        "    in >=90%% of this run's field samples (probable spike-in/internal standard): %s"
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
      ifelse(is.na(r$top_taxa), "(none)", r$top_taxa),
      ifelse(length(fr) && !is.na(fr[1]), fr[1], "(none)"),
      ub
      )
    }, character(1))
    sprintf("TUBE %s -- labelled %s\n%s", s, toupper(x$identity_label[1]), paste(lines, collapse = "\n"))
  })
  names(out) <- tubes
  out
}

#' @noRd
.sir_build_prompt <- function(items, context) {
  paste0(
    "You are reviewing negative controls and field samples in a DNA metabarcoding study, ",
    "before any of them are analysed. Each tube below was held back because its contents ",
    "do not look like its label. Judge, from the taxa, what the tube most plausibly is.\n\n",
    "STUDY CONTEXT: ", trimws(context), "\n\n",
    "GUIDELINES\n",
    "- A clean blank holds few taxa, and those are laboratory or handling signals: human, ",
    "common fungi and moulds, reagent contaminants, or a scattering of low-count reads also ",
    "found in the run's field samples (index hopping). Many features alone do not make a ",
    "blank dirty if they are of this kind.\n",
    "- A blank holding a coherent ENVIRONMENTAL community is contaminated, whatever that ",
    "environment is. If the community matches the run's field samples, suspect a mislabel ",
    "or carry-over (sample_labelled_as_blank). If it is a different environment (for example ",
    "open-water plankton in a benthic study), suspect contamination from another source, such ",
    "as a rinse with unfiltered water (contaminated_blank). Being outside the study's ",
    "analytical scope does not make a taxon a lab contaminant.\n",
    "- A taxon listed as present in >=90% of the run's field samples is a spike-in or internal ",
    "standard added to every tube. A blank holding little besides it is a CLEAN blank: with no ",
    "template, the spike dominates. Never call such a blank a positive control.\n",
    "- A tube labelled as a blank that holds a mock community NOT added to every tube (a positive-control ",
    "sequence, or taxa foreign to the study region such as freshwater or domestic species in a ",
    "marine study) is a positive control carrying a blank's label ",
    "(positive_control_labelled_as_blank; suggest reassign_to_positive_control).\n",
    "- A tube labelled as a sample that holds only lab/handling signals, or almost nothing, ",
    "may be a blank carrying a sample label (blank_labelled_as_sample).\n",
    "- Use every marker shown: agreement across markers is strong evidence; disagreement ",
    "should lower your confidence.\n",
    "- If the evidence does not support a judgement, say 'uncertain'. Do not guess.\n\n",
    "Allowed verdicts: ", paste(.SIR_VERDICTS, collapse = ", "), ".\n",
    "Allowed suggested_disposition: ", paste(.SIG_IDENTITY_DISPOSITIONS, collapse = ", "), ".\n\n",
    "TUBES\n", paste(unlist(items), collapse = "\n\n"), "\n\n",
    "Respond with ONLY a JSON array, one object per tube, in this form:\n",
    "[{\"sample\": \"<tube id>\", \"verdict\": \"...\", \"suggested_disposition\": \"...\", ",
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
    if (is.na(v) || !v %in% .SIR_VERDICTS) next
    out[[s]] <- data.frame(
      verdict = v,
      disposition = if (!is.na(d) && d %in% ok_disp) d else NA_character_,
      confidence = if (!is.na(cf) && cf %in% c("high", "moderate", "low")) cf else NA_character_,
      rationale = g("rationale"),
      stringsAsFactors = FALSE
    )
  }
  out
}
