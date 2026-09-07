
#' LLM Expert Review of Taxonomic Assignments
#'
#' Sends unique taxa from a consensus table to an LLM for structured expert
#' review. The LLM assesses each taxon for habitat fit, geographic plausibility,
#' contaminant risk, and (optionally) taxonomic scope. It also suggests
#' plausible alternative taxa where appropriate.
#'
#' When \code{plausible_taxa_col} is supplied, the function deduplicates on
#' candidate sets rather than \code{consensus_taxon}. Each unique combination
#' of plausible species becomes one LLM query, giving the LLM full species-level
#' context rather than only the upranked LCA name. This is especially useful
#' when multiple observations share the same genus-level consensus but differ in
#' which specific candidates they contain.
#'
#' Works with any data frame containing a taxon column -- not restricted to
#' TaxaAssign output. Context (geography, habitat) can be supplied as a
#' \code{build_context()} object from TaxaAssign, or as a simple named list.
#'
#' @param input_df Data frame with at minimum a column of taxon names.
#' @param taxon_col Character. Column name for consensus taxon. Default
#'   \code{"consensus_taxon"}.
#' @section Candidate-set join key:
#' On the candidate-aware path, review results are joined back to input rows by
#' the SORTED candidate set, not by the display label. The label
#' (\code{consensus_OTU}) is ordered by posterior so the most-supported taxon
#' reads first, which means one biological unit can carry "A/B" on one
#' observation and "B/A" on another; joining on the label left one of them
#' unmatched and therefore unscored. Sets are also deduplicated canonically, so
#' a unit that previously appeared under two orderings is now reviewed once
#' rather than twice. Display labels are unchanged. (2026-09-04.)
#'
#' @param cache_dir Character or \code{NULL} (default). Directory for the
#'   per-taxon review cache. \code{NULL} disables caching entirely, which is
#'   the historical behaviour. Supplying a directory makes a re-run
#'   REPRODUCIBLE and stops it re-paying for verdicts already obtained: the
#'   review is a judgement, and two GreatLakes runs 50 minutes apart on
#'   identical input disagreed about \emph{Pimephales vigilax}
#'   (\code{"possible"} then \code{"unlikely"}), putting it in one species
#'   list and not the other. One small \code{.rds} per reviewed taxon, keyed
#'   on everything that can move a verdict -- the taxon label and rank, its
#'   attached pipeline/weight/spatial notes, \code{context},
#'   \code{target_group}, \code{marker}, \code{data_type} and the
#'   candidate-set path -- so changing any of them is correctly a miss. Manage
#'   it with [taxaflag_clear_cache()], which uses the same
#'   [TaxaTools::list_cache_files()] engine as the other packages' cache
#'   helpers, so it does not accumulate unmanaged.
#'
#' @param taxon_rank_col Character or \code{NULL}. Column name for consensus
#'   rank (e.g., "species", "genus"). When supplied, the rank is included in
#'   the prompt for context. Default \code{NULL}.
#' @param plausible_taxa_col Character or \code{NULL}. Name of the list column
#'   containing per-observation plausible candidate taxa (e.g.,
#'   \code{"plausible_taxa"} from \code{TaxaAssign::posterior_consensus()}).
#'   When supplied, the LLM receives the full candidate set for each unique
#'   combination rather than just the upranked consensus taxon. Singletons are
#'   reviewed by species name as usual. Unresolved rows (empty candidate set)
#'   are skipped. Default \code{NULL} (current behaviour -- deduplicates on
#'   \code{taxon_col}).
#' @param irreducible_only Logical. When \code{plausible_taxa_col} is supplied
#'   and an \code{irreducible_consensus} column is present in \code{input_df} (added
#'   by \code{TaxaAssign::add_slash_taxon()}), only candidate sets where
#'   \code{irreducible_consensus == TRUE} are reviewed. Non-irreducible rows
#'   receive \code{NA} review columns. When \code{irreducible_consensus} is
#'   absent, all unique candidate sets are reviewed with a message. Ignored
#'   when \code{plausible_taxa_col = NULL}. Default \code{TRUE}.
#' @param consensus_posterior_col Character or \code{NULL}. Column name for
#'   \code{TaxaAssign::posterior_consensus()}'s \code{consensus_posterior} --
#'   the pipeline's own statistical confidence in the winning taxon. When
#'   present, the median value across every row sharing a taxon/candidate-set
#'   label is shown to the LLM as context (e.g. \code{"pipeline
#'   posterior=0.81"}), so a sharp disagreement between the pipeline's
#'   confidence and the LLM's ecological plausibility judgment can be
#'   surfaced in \code{review_comment}. Purely additive text -- never changes
#'   which rows are reviewed or any output column. Silently skipped when the
#'   named column is absent from \code{input_df}. Default
#'   \code{"consensus_posterior"} (matches \code{posterior_consensus()}'s own
#'   output). Set to \code{NULL} to disable.
#' @param winner_prior_col Character or \code{NULL}. Column name for
#'   \code{posterior_consensus()}'s \code{winner_prior} -- the occurrence-
#'   database prior for the winning taxon. Same treatment as
#'   \code{consensus_posterior_col}: shown as median context (e.g.
#'   \code{"occurrence prior=0.42"}), silently skipped when absent. Default
#'   \code{"winner_prior"}. Set to \code{NULL} to disable.
#' @param winner_rank_expanded_col Character or \code{NULL}. Column name for
#'   \code{posterior_consensus()}'s \code{winner_rank_expanded} -- \code{TRUE}
#'   when the winning species-level call was manufactured by
#'   \code{join_priors()}'s coarse-rank expansion from occurrence-prior mass
#'   alone, with no direct sequence/image/acoustic evidence discriminating
#'   between candidates. When \code{TRUE} for any row sharing a label, a note
#'   to that effect is added to the LLM's context, since this changes how
#'   much weight the identification itself deserves. Silently skipped when
#'   absent. Default \code{"winner_rank_expanded"}. Set to \code{NULL} to
#'   disable.
#' @param plausible_posteriors_col Character or \code{NULL}. Column name for
#'   \code{posterior_consensus()}'s \code{plausible_posteriors} list column
#'   (per-candidate posterior weights, positionally aligned with
#'   \code{plausible_taxa_col}). Only used when \code{plausible_taxa_col} is
#'   supplied. When present, each multi-candidate label's per-candidate
#'   weights are averaged across every row sharing that label and shown to
#'   the LLM (e.g. \code{"candidate weights: Bos javanicus 72\%, Bos
#'   primigenius 28\%"}), so \code{review_comment} can speak to the specific
#'   weaker member instead of the group as an undifferentiated set. Silently
#'   skipped when absent. Default \code{"plausible_posteriors"}. Set to
#'   \code{NULL} to disable.
#' @param dist_nearest_occupied_km_col Character or \code{NULL}. Column name
#'   for \code{check_gbif_tile_range()}'s \code{dist_nearest_occupied_km} --
#'   distance from the study site to the nearest GBIF-mapped occurrence of
#'   the taxon, worldwide. Shown as median context (e.g. \code{"GBIF: nearest
#'   occurrence ~41km away"}) alongside \code{patch_diameter_km_col} when
#'   both are present. Silently skipped when absent. Default
#'   \code{"dist_nearest_occupied_km"}. Set to \code{NULL} to disable.
#' @param patch_diameter_km_col Character or \code{NULL}. Column name for
#'   \code{check_gbif_tile_range()}'s \code{patch_diameter_km} -- shown
#'   alongside \code{dist_nearest_occupied_km_col} as a rough size for the
#'   occupied area found (see "Spatial context" below for why this matters
#'   to interpretation). Silently skipped when absent, or when
#'   \code{dist_nearest_occupied_km_col} is not shown. Default
#'   \code{"patch_diameter_km"}. Set to \code{NULL} to disable.
#' @param beyond_buffer_col Character or \code{NULL}. Column name for
#'   \code{check_gbif_tile_range()}'s \code{beyond_buffer} -- when
#'   \code{TRUE}, shown instead of the distance/patch note as \code{"GBIF: no
#'   occurrence found anywhere globally"}. Silently skipped when absent.
#'   Default \code{"beyond_buffer"}. Set to \code{NULL} to disable.
#' @param inat_in_range_col Character or \code{NULL}. Column name for
#'   \code{TaxaFetch::check_inat_range()}'s \code{in_range}. Shown as
#'   \code{"in range"}/\code{"outside range"} alongside
#'   \code{inat_n_observations_col}/\code{inat_matched_name_col} when
#'   present. Silently skipped when absent. Default \code{"in_range"}. Set to
#'   \code{NULL} to disable.
#' @param inat_n_observations_col Character or \code{NULL}. Column name for
#'   \code{check_inat_range()}'s \code{n_observations}. Default
#'   \code{"n_observations"}. Set to \code{NULL} to disable.
#' @param inat_matched_name_col Character or \code{NULL}. Column name for
#'   \code{check_inat_range()}'s \code{matched_name} -- the taxon iNaturalist's
#'   own name search actually resolved the query to, which is not always the
#'   query taxon itself. When it differs from the taxon under review, this is
#'   flagged in the prompt as \code{"matched to '...' (name differs from
#'   query)"} -- a plain factual annotation, not a judgment (see "Spatial
#'   context" below). Default \code{"matched_name"}. Set to \code{NULL} to
#'   disable.
#' @param consensus_plausibility_col Character or \code{NULL}. Column name for
#'   \code{add_posthoc_assessment()}'s \code{consensus_plausibility} --
#'   specifically its \code{"unprecedented"} value (no local occurrence
#'   record at all, a pipeline-computed fact, never a threshold on a prior
#'   VALUE -- see that function's own docs for why). When present, shown to
#'   the LLM as \code{"pipeline flags UNPRECEDENTED: ..."} and used to gate
#'   the skepticism GUIDELINES bullet (see \code{@section Skepticism gate}
#'   below) and the deterministic \code{geographic_disagreement_basis} output
#'   column. Silently skipped when absent. Default
#'   \code{"consensus_plausibility"}. Set to \code{NULL} to disable.
#' @param consensus_discrimination_col Character or \code{NULL}. Column name
#'   for \code{add_posthoc_assessment()}'s \code{consensus_discrimination} --
#'   specifically its \code{"indistinguishable"} value (a one-sided tail
#'   probability says a confusable relative could score just as well).
#'   Same treatment as \code{consensus_plausibility_col}. Default
#'   \code{"consensus_discrimination"}. Set to \code{NULL} to disable.
#' @param context Named list or data frame describing the study context.
#'   Recognised fields: \code{geography} (or \code{ecoregion}),
#'   \code{habitat} (or \code{main_habitat}), \code{date}. A
#'   \code{build_context()} output works directly. At minimum, supply
#'   \code{geography} and \code{habitat}.
#' @param target_group Character or \code{NULL}. Taxonomic target group
#'   (e.g., \code{"fish"}, \code{"birds"}). When supplied, the LLM
#'   populates \code{llm_scope_plausibility}. Default \code{NULL}.
#' @param marker Character or \code{NULL}. Molecular marker or detection
#'   method (e.g., \code{"12S"}, \code{"COI"}, \code{"camera trap"}).
#'   Provides contaminant context. Default \code{NULL}.
#' @param data_type Character. Detection method. One of \code{"eDNA"} (default),
#'   \code{"acoustic"}, or \code{"image"}. Controls the contaminant assessment
#'   guidance in the LLM prompt.
#' @param llm_fn Function. LLM provider function with signature
#'   \code{function(prompt_str, ...)}. Default
#'   \code{TaxaTools::call_api}. \strong{Known footgun:} \code{call_api()}'s
#'   provider auto-detection is set up by \code{TaxaTools}'s own
#'   \code{.onAttach()}, which only runs via \code{library(TaxaTools)} --
#'   calling this function from a fully-namespaced script (no
#'   \code{library()} calls at all) never triggers it, and \code{call_api()}
#'   silently falls back to degraded/uniform output rather than erroring. If
#'   every plausibility column comes back suspiciously uniform, pass
#'   \code{llm_fn} explicitly, e.g. \code{function(p) TaxaTools::call_api(p,
#'   provider = "anthropic")}. See \code{TaxaID/CLAUDE.md}'s "Known R
#'   Footguns" for the full record.
#' @param taxa_per_call Integer. Maximum taxa (or candidate sets) per LLM call.
#'   Default \code{15L}. Candidate-set entries are longer than single taxon
#'   names; consider reducing to 8--10 when using \code{plausible_taxa_col}.
#' @param max_tokens Integer or \code{NULL}. Maximum response tokens requested
#'   from \code{llm_fn} (forwarded as \code{llm_fn(prompt, max_tokens = max_tokens)}
#'   whenever supplied). Default \code{NULL} -- does not pass \code{max_tokens}
#'   at all, so \code{llm_fn}'s own default applies (\code{3000L} for
#'   \code{TaxaTools::call_api()}). Raise this if \code{max_retries} alone
#'   isn't resolving truncation warnings for your data -- e.g. a long,
#'   multi-marker \code{marker} string can inflate per-taxon response length
#'   enough that even the smallest retry sub-batch still truncates.
#' @param max_retries Integer. When a batch's LLM response is truncated,
#'   empty, or unparseable, the batch is automatically split in half and
#'   retried -- a smaller batch requests a proportionally shorter response,
#'   directly relieving token-budget pressure -- up to \code{max_retries}
#'   times before falling back to \code{NA} defaults for whatever's still
#'   missing. Does not apply to a hard \code{llm_fn} error (e.g. network/auth
#'   failure): a smaller batch can't fix that, so it is reported immediately
#'   without retrying. Default \code{2L}.
#' @param pause_seconds Numeric. Seconds to pause between LLM calls.
#'   Default \code{1}.
#' @param verbose Logical. Print progress messages. Default \code{TRUE}.
#'
#' @return The input data frame with 8 or 9 columns appended:
#' \describe{
#'   \item{\code{llm_habitat_plausibility}}{likely / possible / unlikely.
#'     Renamed from \code{habitat_plausibility} 2026-09-06 -- see
#'     \code{@section Column naming} below.}
#'   \item{\code{llm_geographic_plausibility}}{likely / possible / unlikely.
#'     Renamed from \code{geographic_plausibility}.}
#'   \item{\code{llm_scope_plausibility}}{likely / possible / unlikely, or
#'     \code{NA} if \code{target_group} not supplied. Renamed from
#'     \code{scope_plausibility}.}
#'   \item{\code{llm_contamination_risk}}{high / moderate / low. Renamed from
#'     \code{contamination_risk}.}
#'   \item{\code{review_alternatives}}{Comma-separated plausible alternatives,
#'     or \code{NA}}
#'   \item{\code{review_lower_hypotheses}}{Comma-separated finer-rank taxa, or
#'     \code{NA}. Always \code{NA} when \code{plausible_taxa_col} is supplied
#'     (candidates already known).}
#'   \item{\code{review_confidence}}{high / moderate / low}
#'   \item{\code{review_comment}}{Free-text note, or \code{NA}}
#'   \item{\code{geographic_disagreement_basis}}{\code{NA} (no disagreement,
#'     or the pipeline columns needed to check were unavailable), or one of
#'     \code{"unprecedented"}/\code{"indistinguishable"}/
#'     \code{"unprecedented+indistinguishable"} -- \strong{deterministic},
#'     code-computed, not an LLM output: fires whenever
#'     \code{llm_geographic_plausibility \%in\% c("likely","possible")} despite
#'     \code{consensus_plausibility_col == "unprecedented"} and/or
#'     \code{consensus_discrimination_col == "indistinguishable"}. See
#'     \code{@section Skepticism gate} below for why this exists as a
#'     deterministic column rather than relying on \code{review_comment}
#'     alone.}
#' }
#' Also carries an \code{"llm_prompts"} attribute -- a named list of the
#' exact prompt string sent for each LLM call (named by batch number, with
#' an \code{"a"}/\code{"b"} suffix per retry sub-batch split, e.g.
#' \code{"2b"}). Inspect via \code{attr(reviewed, "llm_prompts")} to see
#' precisely what the LLM was asked, e.g. before trusting an unexpected
#' result or when tuning \code{context}/\code{target_group}/\code{marker}.
#'
#' @section Column naming (2026-09-06):
#' \code{habitat_plausibility}/\code{geographic_plausibility}/
#' \code{scope_plausibility}/\code{contamination_risk} were renamed to
#' \code{llm_habitat_plausibility}/\code{llm_geographic_plausibility}/
#' \code{llm_scope_plausibility}/\code{llm_contamination_risk}. All four are
#' independent LLM judgments -- by design, NOT derived from or gated by any
#' pipeline-computed value (see \code{@section Pipeline context} below) -- and
#' the old, unprefixed names read as if they might be pipeline output, which
#' is exactly what confused a real user tracing a surprising
#' \code{geographic_plausibility = "likely"} back through the pipeline before
#' realising the number it appeared to contradict was never actually
#' consulted to produce it. The LLM's own JSON response schema (what
#' \code{.build_review_prompt()} asks for and \code{.parse_review_response()}
#' parses) is UNCHANGED -- only the final output column names carry the
#' prefix. Real callers (\code{report_flags()}, five external eDNA workflow
#' scripts) were all updated the same session; \code{report_flags()}'s own
#' contamination-column detection also still recognises the old bare
#' \code{contamination_risk} name, for a data frame produced by a
#' pre-2026-09-06 install.
#'
#' @section Skepticism gate (2026-09-06):
#' A real case motivated this: an LLM rated a taxon
#' \code{llm_geographic_plausibility = "likely"} despite the pipeline
#' recording ZERO local occurrence records for it AND a near-total inability
#' to discriminate it from a confusable relative on score alone -- explaining
#' itself only with a general species-level range description, no evidence
#' specific to the actual study site. Two independent responses, both real,
#' both needed (a stronger prompt instruction is not sufficient on its own --
#' see the reasoning in
#' \code{[[project_rank_trust_mechanism_removed]]}/\code{[[project_verify_purpose_before_flagging]]}-adjacent
#' precedent throughout this ecosystem: never trust an LLM alone to reliably
#' self-flag its own uncertainty):
#' \enumerate{
#'   \item{A GUIDELINES bullet (only added when at least one taxon in a
#'     batch actually carries the flag -- see
#'     \code{consensus_plausibility_col}/\code{consensus_discrimination_col})
#'     requires the LLM to default to \code{"unlikely"} for a taxon flagged
#'     \code{"unprecedented"} (no local record) and/or
#'     \code{"indistinguishable"} (a confusable relative could score equally
#'     well) UNLESS it can cite SPECIFIC evidence for a real population at or
#'     near the study site -- a general species-level range description is
#'     explicitly declared insufficient. This is stated as a HARD requirement,
#'     the one deliberate exception to this function's own "the bracket
#'     informs, never overrides your judgment" rule for every other pipeline
#'     signal.}
#'   \item{Prompt compliance is never guaranteed, so the deterministic
#'     \code{geographic_disagreement_basis} output column (see \code{@return}
#'     above) is computed in R, independent of whether the LLM actually
#'     mentioned the disagreement anywhere. It is the reliable way to FIND
#'     every such row -- filter/sort on it directly rather than reading every
#'     \code{review_comment}.}
#' }
#'
#' @section Pipeline context:
#' When \code{consensus_posterior_col}/\code{winner_prior_col}/
#' \code{winner_rank_expanded_col}/\code{plausible_posteriors_col} match real
#' columns in \code{input_df} (the defaults match \code{TaxaAssign::
#' posterior_consensus()}'s own output names), a compact \code{"[...]"}
#' annotation is appended to each taxon's line in the LLM prompt -- the
#' pipeline's own median statistical confidence/occurrence prior for that
#' taxon, a note when the winning call was resolved by occurrence-prior
#' tie-break alone (no direct sequence evidence), and, for multi-candidate
#' sets, each candidate's averaged posterior weight. This lets the LLM's
#' free-text \code{review_comment} flag a disagreement between the
#' pipeline's own confidence and its ecological judgment. It is purely
#' additive: it never changes which rows are reviewed, the dedup key, or any
#' output column, and adds only a few tokens per taxon to the prompt. Set any
#' of the four params to \code{NULL} to disable; all four are silently
#' skipped (not an error) when the named column is absent from \code{input_df}.
#'
#' @section Spatial context:
#' When \code{dist_nearest_occupied_km_col}/\code{patch_diameter_km_col}/
#' \code{beyond_buffer_col} (matching \code{check_gbif_tile_range()}'s own
#' output) and/or \code{inat_in_range_col}/\code{inat_n_observations_col}/
#' \code{inat_matched_name_col} (matching \code{TaxaFetch::check_inat_range()}'s
#' own output) match real columns in \code{input_df} -- typically joined onto it by
#' taxon name before calling this function, since both source functions
#' operate per-taxon at a query point, not per-row -- the same \code{"[...]"}
#' bracket used for pipeline context also carries a compact GBIF/iNat summary
#' (e.g. \code{"[GBIF: nearest occurrence ~41km away, patch ~2.1km across;
#' iNat: in range, 1275 obs]"}). Found empirically to matter, not
#' hypothetically: real GreatLakes2023 "unprecedented" taxa included both a
#' genuine Great Lakes native (a real regional species simply not yet
#' recorded at this exact site) and two European fish species ~6500km from
#' any GBIF-mapped occurrence -- the same "unprecedented" flag, two very
#' different real explanations, indistinguishable without this evidence.
#'
#' Deliberately facts-only in the per-taxon bracket -- no plausibility
#' judgment is pre-computed or baked in server-side (the same design choice
#' already made for \code{winner_rank_expanded}'s note above, and the reason
#' the \code{trusted_rank} mechanism was removed from this ecosystem
#' elsewhere -- see \code{TaxaLikely::evaluate_likelihoods()}'s history). Two
#' real caveats about how to weigh these facts are added as a GUIDELINES
#' bullet instead (only when a batch has at least one such note), for the LLM
#' to apply per case: (1) GBIF's density map is raw, unfiltered global data --
#' an occurrence found far away, especially in a small (1-2 cell) patch, may
#' itself be a single bad or mis-georeferenced GBIF record rather than a real
#' population; a small isolated patch is weaker evidence than a large one.
#' (2) When iNat's \code{matched_name} differs from the taxon under review,
#' its \code{in_range} verdict may describe a *different*, often more common,
#' species due to a fuzzy name-search match -- not the taxon actually being
#' assessed. Confirmed as a real, not hypothetical, failure mode: a query for
#' the European \emph{Gasterosteus gymnurus} resolved via iNat's own search to
#' \emph{Gasterosteus aculeatus} (a genuinely North American/circumpolar
#' species), returning a misleading \code{in_range = TRUE}. This is a known,
#' separate, not-yet-fixed limitation of \code{check_inat_range()}'s name
#' resolution -- \code{matched_name} is surfaced here specifically so a
#' reviewer (human or LLM) can catch it downstream in the meantime, not as a
#' substitute for fixing it upstream.
#'
#' Purely additive, matching "Pipeline context" above in every other respect:
#' never changes which rows are reviewed, the dedup key, or any output
#' column. Set any of the six params to \code{NULL} to disable; all six are
#' silently skipped when the named column is absent from \code{input_df}.
#'
#' @seealso \code{\link{flag_contaminant}} for data-driven contaminant
#'   detection, \code{\link{flag_handler}} for temporal proximity flagging,
#'   \code{TaxaAssign::add_slash_taxon()} to add \code{irreducible_consensus}
#'
#' @examples
#' \dontrun{
#' # Standard review (consensus taxon only)
#' reviewed <- review_assignments(
#'   input_df           = consensus_df,
#'   context      = list(geography = "Palmyra Atoll, central Pacific",
#'                       habitat   = "coral reef"),
#'   target_group = "fish",
#'   marker       = "12S MiFish"
#' )
#'
#' # Candidate-aware review (recommended for upranked assignments)
#' consensus_df <- TaxaAssign::add_slash_taxon(consensus_df)
#' reviewed <- review_assignments(
#'   input_df                 = consensus_df,
#'   plausible_taxa_col = "plausible_taxa",
#'   irreducible_only   = TRUE,
#'   context            = ctx,
#'   target_group       = "fish"
#' )
#' }
#'
#' @export
review_assignments <- function(input_df,
                               taxon_col          = "consensus_taxon",
                               taxon_rank_col     = NULL,
                               plausible_taxa_col = NULL,
                               irreducible_only   = TRUE,
                               consensus_posterior_col  = "consensus_posterior",
                               winner_prior_col         = "winner_prior",
                               winner_rank_expanded_col = "winner_rank_expanded",
                               plausible_posteriors_col = "plausible_posteriors",
                               consensus_plausibility_col   = "consensus_plausibility",
                               consensus_discrimination_col = "consensus_discrimination",
                               dist_nearest_occupied_km_col = "dist_nearest_occupied_km",
                               patch_diameter_km_col        = "patch_diameter_km",
                               beyond_buffer_col            = "beyond_buffer",
                               inat_in_range_col            = "in_range",
                               inat_n_observations_col      = "n_observations",
                               inat_matched_name_col        = "matched_name",
                               context,
                               target_group       = NULL,
                               marker             = NULL,
                               data_type          = "eDNA",
                               llm_fn             = getOption("TaxaID.llm_fn", TaxaTools::call_api),
                               taxa_per_call      = 15L,
                               max_tokens         = NULL,
                               max_retries        = 2L,
                               pause_seconds      = 1,
                               cache_dir          = NULL,
                               verbose            = TRUE) {

  # --- Input validation ---
  if (!is.data.frame(input_df)) stop("'input_df' must be a data frame.", call. = FALSE)

  if (!taxon_col %in% names(input_df))
    stop(sprintf("Column '%s' not found in input_df.", taxon_col), call. = FALSE)

  if (!is.null(taxon_rank_col) && !taxon_rank_col %in% names(input_df))
    stop(sprintf("Column '%s' not found in input_df.", taxon_rank_col), call. = FALSE)

  if (!is.null(plausible_taxa_col) && !plausible_taxa_col %in% names(input_df))
    stop(sprintf("Column '%s' not found in input_df.", plausible_taxa_col), call. = FALSE)

  # Pipeline-context column-name params are deliberately NOT validated for
  # presence in input_df -- unlike taxon_rank_col/plausible_taxa_col above, these
  # have non-NULL defaults matching TaxaAssign::posterior_consensus()'s own
  # output names, so an explicit-presence check would break every existing
  # caller whose input_df predates these columns. Silently skipped instead (see
  # .summarise_pipeline_context()); only the parameter TYPE is checked here.
  for (col_param in list(consensus_posterior_col, winner_prior_col,
                         winner_rank_expanded_col, plausible_posteriors_col,
                         dist_nearest_occupied_km_col, patch_diameter_km_col,
                         beyond_buffer_col, inat_in_range_col,
                         inat_n_observations_col, inat_matched_name_col,
                         consensus_plausibility_col, consensus_discrimination_col)) {
    if (!is.null(col_param) && (!is.character(col_param) || length(col_param) != 1L))
      stop(paste(
        "'consensus_posterior_col', 'winner_prior_col',",
        "'winner_rank_expanded_col', 'plausible_posteriors_col',",
        "'dist_nearest_occupied_km_col', 'patch_diameter_km_col',",
        "'beyond_buffer_col', 'inat_in_range_col',",
        "'inat_n_observations_col', 'inat_matched_name_col',",
        "'consensus_plausibility_col', and 'consensus_discrimination_col' must",
        "each be a single character string or NULL."
      ), call. = FALSE)
  }

  if (missing(context) || is.null(context))
    stop("'context' is required. Supply a named list or build_context() output.",
         call. = FALSE)

  valid_types <- c("eDNA", "acoustic", "image")
  if (!is.character(data_type) || length(data_type) != 1L ||
      !data_type %in% valid_types)
    stop(sprintf("'data_type' must be one of: %s", paste(valid_types, collapse = ", ")),
         call. = FALSE)

  # --- Normalise context ---
  ctx <- .normalise_context(context)

  # --- Build taxa_info: candidate-set path or consensus-taxon path ---
  use_candidates <- !is.null(plausible_taxa_col)

  # Maps each reviewed row's DISPLAY label back to its canonical (sorted-set)
  # join key; NULL on the non-candidate path, where the taxon name is the key.
  label_canon_map <- NULL

  if (use_candidates) {

    raw_sets  <- input_df[[plausible_taxa_col]]
    taxa_sets <- lapply(raw_sets, function(x) sort(unique(x[!is.na(x) & nzchar(x)])))
    n_cands   <- lengths(taxa_sets)

    # Build display labels (slash notation). Prefer a pre-computed label from
    # TaxaAssign::add_slash_taxon() when present -- its slash-name logic
    # clears the label to NA (falling back to consensus_taxon) for downranked
    # rows where the plausible-genera set no longer matches consensus_taxon,
    # a case .build_candidate_label() below cannot detect on its own (it only
    # sees plausible_taxa, not downranked/consensus_taxon). Rebuilding
    # independently risks producing a DIFFERENT label than add_slash_taxon()
    # would for the same row.
    cand_labels <- if ("consensus_OTU" %in% names(input_df)) {
      input_df[["consensus_OTU"]]
    } else {
      vapply(seq_along(taxa_sets), function(i) {
        if (n_cands[i] == 0L) return(NA_character_)
        if (n_cands[i] == 1L) return(taxa_sets[[i]])
        .build_candidate_label(taxa_sets[[i]])
      }, character(1L))
    }

    # Determine which rows to review
    if (irreducible_only) {
      if ("irreducible_consensus" %in% names(input_df)) {
        include_rows <- input_df[["irreducible_consensus"]] %in% TRUE
        if (verbose)
          message(sprintf(
            "  irreducible_only = TRUE: %d of %d rows selected for review.",
            sum(include_rows & n_cands > 0L), nrow(input_df)
          ))
      } else {
        if (verbose)
          message(paste0(
            "  irreducible_only = TRUE but 'irreducible_consensus' column not found. ",
            "Run TaxaAssign::add_slash_taxon() to enable filtering. ",
            "Reviewing all non-empty candidate sets."
          ))
        include_rows <- rep(TRUE, nrow(input_df))
      }
    } else {
      include_rows <- rep(TRUE, nrow(input_df))
    }

    # Exclude unresolved rows
    include_rows <- include_rows & n_cands > 0L

    # Join on the SORTED candidate set, never on the display label. taxa_sets
    # is already sorted above; cand_labels is not -- it comes from
    # consensus_OTU, which is ordered by posterior so the most-supported taxon
    # reads first. Two observations of one unit can therefore carry "A/B" and
    # "B/A", which as join keys never match, leaving one of them unreviewed and
    # NA. The label is left exactly as it is: still posterior-ordered, still
    # what the LLM is shown and what the caller sees.
    canon_key <- vapply(taxa_sets, paste, character(1L), collapse = "\u0001")
    input_df$.join_key <- canon_key

    # Build taxa_info from unique labels in included rows
    inc_labels <- cand_labels[include_rows]
    inc_ranks  <- if (!is.null(taxon_rank_col)) {
      input_df[[taxon_rank_col]][include_rows]
    } else {
      rep(NA_character_, sum(include_rows))
    }

    taxa_info <- data.frame(
      taxon_name = inc_labels,
      taxon_rank = inc_ranks,
      .canon     = canon_key[include_rows],
      stringsAsFactors = FALSE
    )
    # Dedup on the canonical set, not the label: one review per biological
    # unit. Where a unit previously appeared under two orderings it was
    # reviewed twice, so this also removes a redundant LLM call rather than
    # adding one.
    taxa_info <- taxa_info[!duplicated(taxa_info$.canon), , drop = FALSE]
    # ... and then once more on the LABEL, because a label is NOT guaranteed
    # unique across canonical sets in the other direction either:
    # add_slash_taxon() deliberately clears the slash name for a downranked
    # row, so consensus_OTU falls back to consensus_taxon and two genuinely
    # different candidate sets can share one display label. The LLM only ever
    # sees the label -- and everything else keyed on it (the pipeline/spatial
    # notes, the cache key) is already per-label -- so such sets cannot be
    # reviewed apart; one verdict is obtained and fanned back out to every
    # canonical set carrying that label. Left un-deduplicated, the label
    # appeared twice in one batch, the taxon_name merges below multiplied the
    # review rows, and the final join DUPLICATED input rows (2 rows in, 5
    # out, in the regression test that pins this).
    label_canon_map <- split(taxa_info$.canon, taxa_info$taxon_name)
    taxa_info <- taxa_info[!duplicated(taxa_info$taxon_name), , drop = FALSE]
    taxa_info$.canon <- NULL

    if (nrow(taxa_info) == 0L)
      stop("No candidate sets to review after filtering. ",
           "Check 'irreducible_only' and 'plausible_taxa_col'.", call. = FALSE)

  } else {

    # --- Current path: dedup on consensus_taxon ---
    input_df$.join_key <- input_df[[taxon_col]]

    taxa <- unique(input_df[[taxon_col]])
    taxa <- taxa[!is.na(taxa) & nchar(trimws(taxa)) > 0]

    if (length(taxa) == 0L)
      stop(sprintf("No non-NA taxa found in column '%s'.", taxon_col), call. = FALSE)

    if (!is.null(taxon_rank_col)) {
      taxa_info <- unique(input_df[, c(taxon_col, taxon_rank_col), drop = FALSE])
      names(taxa_info) <- c("taxon_name", "taxon_rank")
      taxa_info <- taxa_info[!is.na(taxa_info$taxon_name) &
                               nchar(trimws(taxa_info$taxon_name)) > 0, , drop = FALSE]
      taxa_info <- taxa_info[!duplicated(taxa_info$taxon_name), , drop = FALSE]
    } else {
      taxa_info <- data.frame(taxon_name = taxa, taxon_rank = NA_character_,
                              stringsAsFactors = FALSE)
    }
  }

  # --- Optional pipeline-context annotation ---------------------------------
  # Purely additive text shown to the LLM (median pipeline posterior /
  # occurrence prior / rank-expanded flag / averaged candidate weights across
  # every row sharing a label) -- never changes which rows are reviewed, the
  # dedup key, or any output column. Grouping is O(n) via split(), not a
  # per-label linear scan, to stay cheap regardless of dataset size.
  label_vec_full <- if (use_candidates) cand_labels else input_df[[taxon_col]]

  pipeline_ctx <- .summarise_pipeline_context(
    label_vec_full, input_df, consensus_posterior_col, winner_prior_col,
    winner_rank_expanded_col, consensus_plausibility_col, consensus_discrimination_col
  )
  weight_ctx <- if (use_candidates && !is.null(plausible_posteriors_col) &&
                    plausible_posteriors_col %in% names(input_df)) {
    .summarise_candidate_weights(label_vec_full, input_df[[plausible_posteriors_col]])
  } else {
    NULL
  }
  spatial_ctx <- .summarise_spatial_context(
    label_vec_full, input_df, dist_nearest_occupied_km_col, patch_diameter_km_col,
    beyond_buffer_col, inat_in_range_col, inat_n_observations_col,
    inat_matched_name_col
  )

  if (!is.null(pipeline_ctx) || !is.null(weight_ctx) || !is.null(spatial_ctx)) {
    pn <- if (!is.null(pipeline_ctx))
      pipeline_ctx$pipeline_note[match(taxa_info$taxon_name, pipeline_ctx$taxon_name)]
    else rep(NA_character_, nrow(taxa_info))
    wn <- if (!is.null(weight_ctx))
      weight_ctx$weight_note[match(taxa_info$taxon_name, weight_ctx$taxon_name)]
    else rep(NA_character_, nrow(taxa_info))
    wn <- ifelse(is.na(wn), NA_character_, paste0("candidate weights: ", wn))
    sn <- if (!is.null(spatial_ctx))
      spatial_ctx$spatial_note[match(taxa_info$taxon_name, spatial_ctx$taxon_name)]
    else rep(NA_character_, nrow(taxa_info))
    # spatial_note is kept as its own column (not just folded into
    # pipeline_note) so .build_review_prompt() can tell, per batch, whether
    # to include the GBIF/iNat interpretation caveats -- see "Spatial
    # context" in this function's own roxygen for why those caveats live in
    # fixed GUIDELINES text rather than being pre-judged per taxon here.
    taxa_info$spatial_note  <- sn
    taxa_info$pipeline_note <- .combine_notes(.combine_notes(pn, wn), sn)
  }

  # has_unprecedented/has_indistinguishable (2026-09-06): carried as their own
  # LOGICAL columns on taxa_info (not just folded into pipeline_note's text),
  # for two reasons. (1) .build_review_prompt() needs a real boolean to decide
  # whether to add the skepticism GUIDELINES bullet at all (matching
  # has_spatial_note's exact pattern) -- text alone can't be tested cheaply.
  # (2) the deterministic geographic_disagreement_basis column computed after
  # the LLM call (see the final assembly below) needs the RAW flags, not a
  # rendered sentence, and must survive independent of whatever the LLM
  # actually wrote in review_comment. Also folds into the cache key for free,
  # via the same "vapply(taxa_info, ...)" loop every other taxa_info column
  # already participates in.
  taxa_info$has_unprecedented <- if (!is.null(pipeline_ctx))
    pipeline_ctx$has_unprecedented[match(taxa_info$taxon_name, pipeline_ctx$taxon_name)]
  else rep(FALSE, nrow(taxa_info))
  taxa_info$has_indistinguishable <- if (!is.null(pipeline_ctx))
    pipeline_ctx$has_indistinguishable[match(taxa_info$taxon_name, pipeline_ctx$taxon_name)]
  else rep(FALSE, nrow(taxa_info))
  taxa_info$has_unprecedented[is.na(taxa_info$has_unprecedented)] <- FALSE
  taxa_info$has_indistinguishable[is.na(taxa_info$has_indistinguishable)] <- FALSE

  if (verbose)
    message(sprintf("review_assignments: %d unique %s to review.",
                    nrow(taxa_info),
                    if (use_candidates) "candidate sets" else "taxa"))

  # --- Cache lookup ------------------------------------------------------
  # The review is a JUDGEMENT, and an uncached one is not reproducible: two
  # GreatLakes runs 50 minutes apart on identical input disagreed about
  # Pimephales vigilax ("possible" then "unlikely"), so it appeared in one
  # species list and not the other. Caching makes a re-run reproducible and
  # stops it re-paying for verdicts already obtained.
  #
  # Shape: one small file per reviewed taxon, named by a hash of its full key
  # -- the file-per-key shape TaxaTools::list_cache_files() /
  # report_and_clear_cache() are built for, so taxaflag_clear_cache() can
  # report and prune it like every other cache in the ecosystem. The FULL key
  # is stored inside each file and verified on read, so a hash collision is a
  # miss (re-asked) rather than a wrong verdict silently returned for the
  # wrong taxon.
  #
  # The key covers everything that can move a verdict: the taxon label and
  # rank, every per-taxon note already attached to taxa_info (pipeline
  # posterior, candidate weights, spatial context), the shared review context,
  # target_group, marker, data_type, and whether this is the candidate-set
  # path. Change any of them and the entry is correctly a miss.
  cache_hits <- NULL
  cache_paths <- NULL
  cache_keys <- NULL
  call_rows  <- seq_len(nrow(taxa_info))
  if (!is.null(cache_dir)) {
    if (!is.character(cache_dir) || length(cache_dir) != 1L || is.na(cache_dir))
      stop("'cache_dir' must be a single non-NA character string, or NULL.",
           call. = FALSE)
    if (!dir.exists(cache_dir))
      dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)

    .shared <- paste(c(
      "v1", target_group %||% "", marker %||% "", data_type,
      as.character(use_candidates),
      paste(names(ctx), vapply(ctx, function(z) paste(as.character(z), collapse = "~"),
                               character(1)), sep = "=", collapse = "|")
    ), collapse = "\u0001")

    cache_keys <- vapply(seq_len(nrow(taxa_info)), function(i) {
      paste(c(.shared, vapply(taxa_info, function(col)
        paste(as.character(col[i]), collapse = "~"), character(1))),
        collapse = "\u0001")
    }, character(1))
    cache_paths <- file.path(
      cache_dir, paste0(vapply(cache_keys, .review_cache_hash, character(1)),
                        "_review.rds"))

    hit_rows <- integer(0); hit_list <- list()
    for (i in seq_along(cache_paths)) {
      ent <- .review_cache_read(cache_paths[i], cache_keys[i])
      if (!is.null(ent)) { hit_rows <- c(hit_rows, i); hit_list[[length(hit_list) + 1L]] <- ent }
    }
    if (length(hit_rows) > 0L) {
      cache_hits <- do.call(rbind, hit_list)
      call_rows  <- setdiff(call_rows, hit_rows)
    }
    if (verbose)
      message(sprintf("  cache: %d of %d taxa already reviewed; %d to call.",
                      length(hit_rows), nrow(taxa_info), length(call_rows)))
  }

  taxa_to_call <- taxa_info[call_rows, , drop = FALSE]

  # --- Batch and call LLM ---
  n_taxa    <- nrow(taxa_to_call)
  tpc       <- if (n_taxa > 0L) min(taxa_per_call, n_taxa) else 1L
  batch_idx <- if (n_taxa > 0L)
    split(seq_len(n_taxa), ceiling(seq_len(n_taxa) / tpc)) else list()
  n_batches <- length(batch_idx)

  if (verbose)
    message(sprintf("  %d LLM call(s) needed (taxa_per_call = %d).",
                    n_batches, taxa_per_call))

  batch_results <- vector("list", n_batches)
  prompt_log    <- new.env(parent = emptyenv())

  for (b in seq_along(batch_idx)) {
    taxa_batch <- taxa_to_call[batch_idx[[b]], , drop = FALSE]

    if (verbose)
      message(sprintf("  Calling LLM (batch %d/%d, %d %s)...",
                      b, n_batches, nrow(taxa_batch),
                      if (use_candidates) "candidate sets" else "taxa"))

    batch_results[[b]] <- .review_batch_with_retry(
      taxa_batch, ctx, target_group, marker, data_type, use_candidates,
      llm_fn, max_tokens, taxon_rank_col, verbose, pause_seconds,
      batch_label = as.character(b), max_retries = max_retries,
      prompt_log = prompt_log
    )

    if (b < n_batches) Sys.sleep(pause_seconds)
  }

  review_df <- do.call(rbind, batch_results)

  # Persist the freshly obtained verdicts, then fold the cached ones back in.
  if (!is.null(cache_dir) && !is.null(review_df) && nrow(review_df) > 0L) {
    pos <- match(review_df$taxon_name, taxa_info$taxon_name)
    for (k in which(!is.na(pos)))
      .review_cache_write(cache_paths[pos[k]], cache_keys[pos[k]],
                          review_df[k, , drop = FALSE])
  }
  if (!is.null(cache_hits))
    review_df <- if (is.null(review_df) || nrow(review_df) == 0L) cache_hits
                 else rbind(review_df, cache_hits[, names(review_df), drop = FALSE])
  rownames(review_df) <- NULL

  if (verbose)
    message(sprintf("  Review complete. %d %s reviewed.",
                    nrow(review_df),
                    if (use_candidates) "candidate sets" else "taxa"))

  # --- Join back to input by .join_key ---
  # 2026-09-06: the four purely-LLM-sourced columns are named with an
  # llm_ prefix (llm_habitat_plausibility/llm_geographic_plausibility/
  # llm_scope_plausibility/llm_contamination_risk, were
  # habitat_plausibility/geographic_plausibility/scope_plausibility/
  # contamination_risk) -- so the SOURCE of a "likely"/"unlikely" verdict is
  # legible from the column name alone, not just documentation. Prompted
  # directly by a real case where a user traced a surprising
  # "geographic_plausibility = likely" (despite a near-zero pipeline
  # occurrence prior) all the way to this function before realising it was
  # an independent LLM judgment, not a pipeline-derived value. The LLM's own
  # JSON schema keys (habitat_plausibility, etc., in .build_review_prompt()/
  # .parse_review_response()) are UNCHANGED -- only the final output column
  # names carry the new prefix.
  flag_lookup <- taxa_info[, c("taxon_name", "has_unprecedented", "has_indistinguishable")]
  review_df <- merge(review_df, flag_lookup, by = "taxon_name", all.x = TRUE, sort = FALSE)

  # One reviewed label can stand for more than one canonical candidate set
  # (see the label dedup above), so a verdict row is repeated once per set it
  # covers before the join. A label with no entry in the map contributes no
  # key and simply drops out, exactly as an unmatched key did before.
  join_keys <- if (is.null(label_canon_map)) {
    review_df$taxon_name
  } else {
    keys <- label_canon_map[review_df$taxon_name]
    review_df <- review_df[rep(seq_len(nrow(review_df)), lengths(keys)), , drop = FALSE]
    as.character(unlist(keys, use.names = FALSE))  # NULL -> character(0), keeps the column
  }

  merge_key <- data.frame(
    .join_key                   = join_keys,
    llm_habitat_plausibility    = review_df$habitat_plausibility,
    llm_geographic_plausibility = review_df$geographic_plausibility,
    llm_scope_plausibility      = review_df$scope_plausibility,
    llm_contamination_risk      = review_df$contamination_risk,
    review_alternatives         = review_df$review_alternatives,
    review_lower_hypotheses     = review_df$review_lower_hypotheses,
    review_confidence           = review_df$review_confidence,
    review_comment               = review_df$review_comment,
    .has_unprecedented           = review_df$has_unprecedented,
    .has_indistinguishable       = review_df$has_indistinguishable,
    stringsAsFactors = FALSE
  )

  input_df$.row_id <- seq_len(nrow(input_df))
  result <- merge(input_df, merge_key, by = ".join_key", all.x = TRUE, sort = FALSE)
  result <- result[order(result$.row_id), , drop = FALSE]
  result$.row_id  <- NULL
  result$.join_key <- NULL
  rownames(result) <- NULL

  # --- Deterministic disagreement flag (2026-09-06) --------------------------
  # NOT computed from review_comment -- an LLM is not guaranteed to mention a
  # disagreement even when instructed to (see the skepticism GUIDELINES bullet
  # in .build_review_prompt()), so a reviewer who wants to reliably FIND every
  # such row needs a code-computed signal, independent of prompt compliance.
  # NA means "no disagreement, or the pipeline columns needed to check
  # weren't supplied" (never FALSE -- FALSE would wrongly imply "checked, and
  # no disagreement" when the inputs to check were simply absent). A non-NA
  # value names WHICH pipeline signal(s) the LLM's "likely"/"possible" rating
  # disagrees with, so a reviewer sees why at a glance rather than having to
  # cross-reference other columns.
  hu <- result$.has_unprecedented;     hu[is.na(hu)] <- FALSE
  hi <- result$.has_indistinguishable; hi[is.na(hi)] <- FALSE
  llm_geo <- result$llm_geographic_plausibility
  disagrees <- !is.na(llm_geo) & llm_geo %in% c("likely", "possible")

  basis <- rep(NA_character_, nrow(result))
  basis[disagrees & hu  & hi]  <- "unprecedented+indistinguishable"
  basis[disagrees & hu  & !hi] <- "unprecedented"
  basis[disagrees & !hu & hi]  <- "indistinguishable"
  result$geographic_disagreement_basis <- basis
  result$.has_unprecedented     <- NULL
  result$.has_indistinguishable <- NULL

  # Named by batch label (including any "a"/"b" retry sub-batch splits) --
  # see @return below.
  attr(result, "llm_prompts") <- as.list(prompt_log)

  result
}


# ==============================================================================
# Internal helpers
# ==============================================================================

#' Build slash-style candidate label
#'
#' Constructs a compact slash-species string from a sorted, deduplicated
#' character vector of binomial names (length >= 2). Same-genus candidates
#' are abbreviated; mixed-genus groups are joined with " + ".
#' Mirrors TaxaAssign::.make_slash_name() — duplicated here to avoid a
#' dependency on TaxaAssign internals.
#'
#' @noRd
.build_candidate_label <- function(taxa_vec) {
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


#' Format a pipeline confidence value for the LLM prompt, without masking near-zero
#'
#' \code{sprintf("%.2f", v)} renders anything below 0.005 as the literal string
#' "0.00" -- indistinguishable from a genuinely floor-level occurrence prior
#' (e.g. 6.5e-6, "never recorded locally") to the LLM reading the prompt. Found
#' 2026-09-06 on a real case where a user traced exactly this masking after
#' noticing the LLM's own \code{review_comment} quoted "0.00" back verbatim.
#' Below 0.01, switches to 2-significant-figure scientific notation (e.g.
#' "6.50e-06") so the LLM sees the real order of magnitude; \code{0} itself
#' prints as the literal "0" (scientific notation for an exact zero reads
#' oddly, e.g. "0.00e+00").
#' @noRd
.fmt_pipeline_value <- function(v) {
  if (is.na(v)) return(NA_character_)
  if (v == 0) return("0")
  if (abs(v) < 0.01) sprintf("%.2e", v) else sprintf("%.2f", v)
}


#' Summarise Pipeline Confidence Context per Unique Taxon/Candidate-Set Label
#'
#' Aggregates \code{TaxaAssign::posterior_consensus()}'s confidence columns
#' (when present) across every \code{input_df} row sharing a taxon/candidate-set
#' label into one compact annotation string per unique label, so the LLM
#' reviewing a taxon sees the pipeline's OWN statistical confidence alongside
#' its ecological judgment -- without inflating the prompt with one value per
#' observation. Median is used (not mean) for robustness against a handful of
#' outlier observations sharing a common label. Grouping is done once via
#' \code{split()} (O(n)), not a per-label linear scan (O(n * unique labels)).
#'
#' \code{consensus_plausibility_col}/\code{consensus_discrimination_col}
#' (2026-09-06) surface \code{TaxaFlag::add_posthoc_assessment()}'s own Axis 1
#' ("unprecedented" = no local occurrence record at all) and Axis 2
#' ("indistinguishable" = a confusable relative could score just as well)
#' verdicts as plain-text prompt context, AND as two logical columns
#' (\code{has_unprecedented}/\code{has_indistinguishable}) the caller uses
#' post-hoc to compute a deterministic disagreement flag against whatever the
#' LLM actually returned -- unlike the text note, these can't be faithfully
#' recovered from \code{review_comment} alone (an LLM is not guaranteed to
#' mention them, which is exactly the real case that prompted this: an LLM
#' rated a taxon "likely" despite the pipeline recording zero local records
#' for it, and the ecosystem's own house rule is to never trust an LLM to
#' reliably self-flag its own disagreement -- see
#' \code{[[project_rank_trust_mechanism_removed]]} for the same lesson learned
#' elsewhere). \code{isTRUE(any(...))} per group, matching
#' \code{winner_rank_expanded}'s own existing any-row-flags-it convention just
#' below -- if ANY observation sharing this label was found unprecedented/
#' indistinguishable, the whole reviewed group is treated as warranting
#' skepticism (a caution signal should over-include, not under-include).
#' @noRd
.summarise_pipeline_context <- function(label_vec, input_df, consensus_posterior_col,
                                        winner_prior_col, winner_rank_expanded_col,
                                        consensus_plausibility_col = NULL,
                                        consensus_discrimination_col = NULL) {
  has_post  <- !is.null(consensus_posterior_col)  && consensus_posterior_col  %in% names(input_df)
  has_prior <- !is.null(winner_prior_col)         && winner_prior_col         %in% names(input_df)
  has_rexp  <- !is.null(winner_rank_expanded_col) && winner_rank_expanded_col %in% names(input_df)
  has_plaus <- !is.null(consensus_plausibility_col)   && consensus_plausibility_col   %in% names(input_df)
  has_disc  <- !is.null(consensus_discrimination_col) && consensus_discrimination_col %in% names(input_df)
  if (!has_post && !has_prior && !has_rexp && !has_plaus && !has_disc) return(NULL)

  keep <- !is.na(label_vec)
  if (!any(keep)) return(NULL)

  groups <- split(which(keep), label_vec[keep])

  rows_list <- vector("list", length(groups))
  notes <- vapply(seq_along(groups), function(gi) {
    rows <- groups[[gi]]
    parts <- character(0)
    if (has_post) {
      v <- stats::median(input_df[[consensus_posterior_col]][rows], na.rm = TRUE)
      if (!is.na(v)) parts <- c(parts, sprintf("pipeline posterior=%s", .fmt_pipeline_value(v)))
    }
    if (has_prior) {
      v <- stats::median(input_df[[winner_prior_col]][rows], na.rm = TRUE)
      if (!is.na(v)) parts <- c(parts, sprintf("occurrence prior=%s", .fmt_pipeline_value(v)))
    }
    if (has_rexp && isTRUE(any(input_df[[winner_rank_expanded_col]][rows], na.rm = TRUE))) {
      parts <- c(parts, paste0(
        "species-level ID from occurrence-prior tie-break, ",
        "no direct sequence discrimination"
      ))
    }
    is_unprec <- has_plaus && isTRUE(any(input_df[[consensus_plausibility_col]][rows] == "unprecedented", na.rm = TRUE))
    is_indist <- has_disc  && isTRUE(any(input_df[[consensus_discrimination_col]][rows] == "indistinguishable", na.rm = TRUE))
    if (is_unprec) parts <- c(parts, "pipeline flags UNPRECEDENTED: no local occurrence record at all")
    if (is_indist) parts <- c(parts, "pipeline flags INDISTINGUISHABLE: a confusable relative could score equally well")
    rows_list[[gi]] <<- c(unprecedented = is_unprec, indistinguishable = is_indist)
    if (length(parts) == 0L) NA_character_ else paste(parts, collapse = "; ")
  }, character(1L))

  flags <- do.call(rbind, rows_list)
  data.frame(taxon_name = names(groups), pipeline_note = unname(notes),
             has_unprecedented   = unname(flags[, "unprecedented"]),
             has_indistinguishable = unname(flags[, "indistinguishable"]),
             stringsAsFactors = FALSE)
}


#' Summarise Per-Candidate Posterior Weights for Multi-Candidate Labels
#'
#' For each unique multi-candidate label (contains \code{"/"} or \code{"+"}),
#' averages the per-candidate posterior weight (from
#' \code{posterior_consensus()}'s \code{plausible_posteriors} list column)
#' across every \code{input_df} row sharing that label, so the LLM sees which
#' specific member of the slash/plus group carries the most evidence rather
#' than assessing an unweighted set. Singleton labels are skipped -- there is
#' nothing to weight. Grouping via \code{split()} (O(n)), matching
#' \code{.summarise_pipeline_context()}.
#' @noRd
.summarise_candidate_weights <- function(label_vec, post_list) {
  is_multi <- !is.na(label_vec) & grepl("[/+]", label_vec)
  if (!any(is_multi)) return(NULL)

  groups <- split(which(is_multi), label_vec[is_multi])

  notes <- vapply(groups, function(rows) {
    vecs <- post_list[rows]
    vecs <- vecs[lengths(vecs) > 0L]
    if (length(vecs) == 0L) return(NA_character_)
    all_vals <- unlist(vecs, use.names = TRUE)
    agg <- sort(tapply(all_vals, names(all_vals), mean, na.rm = TRUE), decreasing = TRUE)
    paste(sprintf("%s %.0f%%", names(agg), agg * 100), collapse = ", ")
  }, character(1L))

  data.frame(taxon_name = names(groups), weight_note = unname(notes),
             stringsAsFactors = FALSE)
}


#' Summarise Spatial-Occurrence Context (GBIF Density Tile + iNat Range) per
#' Unique Taxon/Candidate-Set Label
#'
#' Aggregates \code{check_gbif_tile_range()}/\code{compute_local_occurrence_distance()}
#' and \code{TaxaFetch::check_inat_range()} output columns (when present in
#' \code{input_df}, typically already joined onto it by taxon name before calling
#' \code{review_assignments()} -- both source functions operate per-taxon at
#' a query point, not per-observation) into one compact annotation string per
#' unique label. Mirrors \code{.summarise_pipeline_context()}'s exact shape
#' and O(n) \code{split()}-based grouping. Unlike that function's per-
#' observation confidence values, these spatial columns are per-TAXON
#' (constant across every row sharing a label) -- \code{median()}/\code{any()}
#' here are defensive against a caller's join producing minor row-level
#' variation, not doing real aggregation work.
#'
#' Facts only, no judgment baked in here -- see \code{review_assignments()}'s
#' own "Spatial context" roxygen section for why the interpretive caveats
#' (a small isolated GBIF patch may be a bad record, not real presence; an
#' iNat \code{matched_name} that differs from the taxon under review may
#' describe a different species entirely) live in
#' \code{.build_review_prompt()}'s GUIDELINES text instead of being
#' pre-decided per taxon here.
#' @noRd
.summarise_spatial_context <- function(label_vec, input_df,
                                       dist_nearest_occupied_km_col,
                                       patch_diameter_km_col,
                                       beyond_buffer_col,
                                       inat_in_range_col,
                                       inat_n_observations_col,
                                       inat_matched_name_col) {
  has_dist    <- !is.null(dist_nearest_occupied_km_col) && dist_nearest_occupied_km_col %in% names(input_df)
  has_patch   <- !is.null(patch_diameter_km_col)         && patch_diameter_km_col         %in% names(input_df)
  has_beyond  <- !is.null(beyond_buffer_col)              && beyond_buffer_col              %in% names(input_df)
  has_inrange <- !is.null(inat_in_range_col)              && inat_in_range_col              %in% names(input_df)
  has_nobs    <- !is.null(inat_n_observations_col)        && inat_n_observations_col        %in% names(input_df)
  has_match   <- !is.null(inat_matched_name_col)          && inat_matched_name_col          %in% names(input_df)
  if (!has_dist && !has_beyond && !has_inrange && !has_nobs && !has_match) return(NULL)

  keep <- !is.na(label_vec)
  if (!any(keep)) return(NULL)

  groups <- split(which(keep), label_vec[keep])

  notes <- vapply(names(groups), function(lbl) {
    rows <- groups[[lbl]]
    parts <- character(0)

    beyond <- has_beyond && isTRUE(any(input_df[[beyond_buffer_col]][rows] %in% TRUE))
    if (beyond) {
      parts <- c(parts, "GBIF: no occurrence found anywhere globally")
    } else if (has_dist) {
      d <- suppressWarnings(stats::median(input_df[[dist_nearest_occupied_km_col]][rows], na.rm = TRUE))
      if (is.finite(d)) {
        patch_str <- ""
        if (has_patch) {
          p <- suppressWarnings(stats::median(input_df[[patch_diameter_km_col]][rows], na.rm = TRUE))
          if (is.finite(p)) patch_str <- sprintf(", patch ~%.1fkm across", p)
        }
        parts <- c(parts, sprintf("GBIF: nearest occurrence ~%.0fkm away%s", d, patch_str))
      }
    }

    if (has_inrange || has_nobs || has_match) {
      in_range <- if (has_inrange) {
        v <- input_df[[inat_in_range_col]][rows]
        if (all(is.na(v))) NA else any(v %in% TRUE)
      } else NA
      nobs <- if (has_nobs)
        suppressWarnings(stats::median(input_df[[inat_n_observations_col]][rows], na.rm = TRUE))
      else NA_real_
      matched <- if (has_match) {
        m <- input_df[[inat_matched_name_col]][rows]
        m <- m[!is.na(m)]
        if (length(m) > 0L) m[[1L]] else NA_character_
      } else NA_character_

      if (!is.na(in_range) || is.finite(nobs) || !is.na(matched)) {
        inat_parts <- character(0)
        if (!is.na(matched) && !is.na(lbl) &&
            tolower(trimws(matched)) != tolower(trimws(lbl))) {
          inat_parts <- c(inat_parts, sprintf("matched to '%s' (name differs from query)", matched))
        }
        if (!is.na(in_range)) inat_parts <- c(inat_parts, if (in_range) "in range" else "outside range")
        if (is.finite(nobs))  inat_parts <- c(inat_parts, sprintf("%.0f obs", nobs))
        if (length(inat_parts) > 0L)
          parts <- c(parts, paste0("iNat: ", paste(inat_parts, collapse = ", ")))
      }
    }

    if (length(parts) == 0L) NA_character_ else paste(parts, collapse = "; ")
  }, character(1L))

  data.frame(taxon_name = names(groups), spatial_note = unname(notes), stringsAsFactors = FALSE)
}


#' Combine Two Optional Note Strings
#' @noRd
.combine_notes <- function(a, b) {
  ifelse(is.na(a) & is.na(b), NA_character_,
  ifelse(is.na(a), b,
  ifelse(is.na(b), a, paste0(a, "; ", b))))
}


#' Normalise Context to Standard Fields
#'
#' A \code{context} data frame is expected to describe ONE study (a single
#' geography/habitat/date shared by every taxon in this call) -- there is no
#' per-row context in \code{review_assignments()}'s design, so only the first
#' row is ever read. A multi-row \code{context} most likely means the caller
#' passed a per-observation table by mistake; warned explicitly rather than
#' silently taking row 1 and discarding the rest.
#' @noRd
.normalise_context <- function(context) {
  if (is.data.frame(context)) {
    if (nrow(context) > 1L)
      warning(sprintf(
        "review_assignments: 'context' has %d rows; only the first is used (context describes one study, not one row per observation).",
        nrow(context)
      ), call. = FALSE)
    ctx <- as.list(context[1, , drop = TRUE])
  } else if (is.list(context)) {
    ctx <- context
  } else {
    stop("'context' must be a named list or data frame.", call. = FALSE)
  }

  if (is.null(ctx$geography) && !is.null(ctx$ecoregion))
    ctx$geography <- ctx$ecoregion
  if (is.null(ctx$habitat) && !is.null(ctx$main_habitat))
    ctx$habitat <- ctx$main_habitat

  if (is.null(ctx$geography) || is.na(ctx$geography))
    warning("'context$geography' is missing. LLM review will lack geographic context.",
            call. = FALSE)
  if (is.null(ctx$habitat) || is.na(ctx$habitat))
    warning("'context$habitat' is missing. LLM review will lack habitat context.",
            call. = FALSE)

  ctx
}


#' Build Review Prompt for LLM
#' @noRd
.build_review_prompt <- function(taxa_batch, ctx, target_group, marker,
                                 data_type = "eDNA", use_candidates = FALSE) {

  # --- Context block ---
  context_lines <- character(0)
  if (!is.null(ctx$geography) && !is.na(ctx$geography))
    context_lines <- c(context_lines, sprintf("GEOGRAPHY: %s", ctx$geography))
  if (!is.null(ctx$habitat) && !is.na(ctx$habitat))
    context_lines <- c(context_lines, sprintf("HABITAT: %s", ctx$habitat))
  if (!is.null(ctx$date) && !is.na(ctx$date))
    context_lines <- c(context_lines, sprintf("DATE: %s", ctx$date))
  if (!is.null(target_group))
    context_lines <- c(context_lines, sprintf("TARGET GROUP: %s", target_group))
  if (!is.null(marker))
    context_lines <- c(context_lines, sprintf("MARKER / METHOD: %s", marker))

  context_block <- paste(context_lines, collapse = "\n")

  # --- Candidate notation definition (only when reviewing sets) ---
  notation_block <- if (use_candidates) {
    paste0(
      "CANDIDATE NOTATION:\n",
      'When a taxon entry contains "/" or "+", it represents an unresolved ',
      "assignment with multiple equally plausible candidate species:\n",
      '  "/" separates species epithets within the same genus ',
      '(e.g., "Bos javanicus/primigenius" = Bos javanicus or Bos primigenius).\n',
      '  "+" separates candidate groups from different genera ',
      '(e.g., "Bos javanicus/primigenius + Bison bonasus" = one of those three species).\n',
      "Assess the candidate group as a whole. Use review_comment to note if a ",
      "specific member is implausible."
    )
  } else {
    NULL
  }

  # --- Taxa list ---
  taxa_lines <- vapply(seq_len(nrow(taxa_batch)), function(i) {
    tn <- taxa_batch$taxon_name[i]
    tr <- taxa_batch$taxon_rank[i]
    rank_str <- if (!is.na(tr) && nchar(tr) > 0) tr else NULL

    base <- if (use_candidates && grepl("[/+]", tn)) {
      # Multi-candidate entry
      if (!is.null(rank_str)) {
        sprintf("- %s (unresolved candidates; consensus rank: %s)", tn, rank_str)
      } else {
        sprintf("- %s (unresolved candidates)", tn)
      }
    } else {
      # Singleton or consensus-taxon entry
      if (!is.null(rank_str)) {
        sprintf("- %s (rank: %s)", tn, rank_str)
      } else {
        sprintf("- %s", tn)
      }
    }

    # Optional pipeline-context annotation (see .summarise_pipeline_context()/
    # .summarise_candidate_weights()) -- absent/NA for any batch built
    # without it, so this is a no-op unless review_assignments()'s *_col
    # params found a matching column.
    note <- if ("pipeline_note" %in% names(taxa_batch)) taxa_batch$pipeline_note[i] else NA_character_
    if (!is.na(note)) base <- paste0(base, " [", note, "]")
    base
  }, character(1))

  taxa_block <- paste(taxa_lines, collapse = "\n")

  # --- Scope instructions ---
  scope_instruction <- if (!is.null(target_group)) {
    sprintf(
      '  "scope_plausibility": one of "likely", "possible", "unlikely" (does this taxon belong to the target group: %s?),',
      target_group
    )
  } else {
    '  "scope_plausibility": null (no target group specified),'
  }

  # --- Lower hypotheses instructions ---
  # Suppressed when reviewing candidate sets (species already known to pipeline)
  lower_instruction <- if (use_candidates) {
    '  "review_lower_hypotheses": null (candidate species already provided by the pipeline),'
  } else {
    has_ranks <- any(!is.na(taxa_batch$taxon_rank))
    if (has_ranks) {
      '  "review_lower_hypotheses": comma-separated string of finer-rank taxa expected at this location and habitat, or null if taxon is already at species level or you cannot suggest any,'
    } else {
      '  "review_lower_hypotheses": null (no rank information provided),'
    }
  }

  # --- Contaminant guidance ---
  contaminant_guideline <- switch(data_type,
    eDNA     = paste0(
      "For contaminant assessment, consider: Homo sapiens and domestic animals are common ",
      "contaminants in molecular studies. Common lab contaminants include Bos taurus, ",
      "Sus scrofa, Gallus gallus, and other food-source species."
    ),
    acoustic = paste0(
      "For contaminant assessment, consider: human vocalizations and handler noise near ",
      "recording equipment are common false positives. Domestic animals (dogs, livestock) ",
      "and vehicles can produce false species matches."
    ),
    image    = paste0(
      "For contaminant assessment, consider: handler presence during camera setup/teardown ",
      "events and domestic animals are common false positives in camera trap data."
    ),
    paste0(
      "For contaminant assessment, consider taxon-specific false positive sources ",
      "appropriate for the detection method used."
    )
  )

  # --- Skepticism guidance (2026-09-06; only when this batch has a real
  # unprecedented/indistinguishable case) --------------------------------------
  # Real motivation, not hypothetical: an LLM rated a taxon "likely"
  # geographically plausible despite the pipeline recording ZERO local
  # occurrence records (unprecedented) and near-total confusability with a
  # relative (indistinguishable), explaining itself only with general
  # species-level range knowledge ("found in the North Pacific") -- no
  # specific evidence for THIS site. That's a real disagreement with no
  # indication of why a user should trust it. This bullet only fires when at
  # least one taxon in this batch actually carries one of these flags (see
  # has_unprecedented/has_indistinguishable, built by
  # .summarise_pipeline_context()) -- most batches won't.
  has_skepticism_note <- ("has_unprecedented" %in% names(taxa_batch) &&
                           any(taxa_batch$has_unprecedented, na.rm = TRUE)) ||
    ("has_indistinguishable" %in% names(taxa_batch) &&
     any(taxa_batch$has_indistinguishable, na.rm = TRUE))
  skepticism_guideline <- if (has_skepticism_note) paste0(
    '- For a taxon whose bracket says "pipeline flags UNPRECEDENTED" (no ',
    "local occurrence record at all) and/or \"pipeline flags ",
    'INDISTINGUISHABLE" (a confusable relative could score equally well), do ',
    'NOT rate geographic_plausibility "likely" or "possible" unless you can ',
    "cite SPECIFIC evidence for a real population at or near THIS site (a ",
    "documented occurrence, a verified range extension, a specific source) -- ",
    "a general species-level range description (e.g. \"found broadly in the ",
    'Pacific/Atlantic/tropics\") is NOT sufficient justification on its own. ',
    "If you do rate it likely/possible anyway, review_comment MUST state the ",
    "specific evidence; otherwise rate it \"unlikely\" and say so.\n"
  ) else NULL

  # --- Spatial-context guidance (only when this batch actually has a note) ---
  has_spatial_note <- "spatial_note" %in% names(taxa_batch) &&
    any(!is.na(taxa_batch$spatial_note))
  spatial_guideline <- if (has_spatial_note) paste0(
    '- When a taxon line ends with a "GBIF:"/"iNat:" note, that is real ',
    "occurrence-database evidence -- two caveats on how to weigh it: (1) ",
    "GBIF's density map is RAW, unfiltered global data. An occurrence found ",
    "far away, especially in a small (1-2 cell) patch, may itself be a ",
    "single bad or mis-georeferenced record rather than a real population -- ",
    "weight a small isolated patch as weaker evidence than a large one. (2) ",
    "If iNat's matched name differs from the taxon under review, its range ",
    "verdict may describe a DIFFERENT (often more common) species due to a ",
    "fuzzy name match, not the taxon actually being assessed -- treat that ",
    "verdict with real suspicion rather than as confirmation. Use both to ",
    "inform geographic_plausibility, and note any inconsistency you notice ",
    "in review_comment.\n"
  ) else NULL

  example_comment <- switch(data_type,
    eDNA     = "Common lab contaminant in eDNA studies",
    acoustic = "Human vocalization detected near recording equipment",
    image    = "Handler detected during camera setup event",
    "Common false positive for this detection method"
  )

  # --- Assemble prompt ---
  header_sections <- c(
    'You are an expert wildlife biologist, biogeographer, and taxonomist.\n',
    'STUDY CONTEXT:\n', context_block, '\n'
  )
  if (!is.null(notation_block))
    header_sections <- c(header_sections, '\n', notation_block, '\n')

  prompt <- paste0(
    paste(header_sections, collapse = ""), '\n',
    'TASK: Review each taxon below and assess whether it is a plausible detection ',
    'given the study context. Return your assessment as a valid JSON array with one ',
    'object per taxon. Return ONLY the JSON array -- no markdown fences, no explanation ',
    'before or after.\n\n',
    'Each object must have these fields:\n',
    '  "taxon_name": the exact taxon name as provided,\n',
    '  "habitat_plausibility": one of "likely", "possible", "unlikely",\n',
    '  "geographic_plausibility": one of "likely", "possible", "unlikely",\n',
    scope_instruction, '\n',
    '  "contamination_risk": one of "low", "moderate", "high",\n',
    '  "review_alternatives": comma-separated string of plausible alternative taxa ',
    'that better fit the geography and habitat, or null if the taxon is plausible,\n',
    lower_instruction, '\n',
    '  "review_confidence": one of "high", "moderate", "low",\n',
    '  "review_comment": a brief free-text note, or null\n\n',
    'GUIDELINES:\n',
    '- "review_alternatives" means "you might have the wrong taxon" -- suggest ',
    'relatives that better fit the context.\n',
    '- ', contaminant_guideline, '\n',
    '- Be conservative with "unlikely" -- only use it when reasonably confident.\n',
    '- If uncertain, use "possible" or "moderate" rather than making a strong claim.\n',
    if (!is.null(skepticism_guideline)) skepticism_guideline else '',
    if (!is.null(spatial_guideline)) spatial_guideline else '',
    '- When a taxon line ends with a "[...]" bracket, that is the statistical ',
    'pipeline\'s OWN confidence for this call (posterior/occurrence prior/candidate ',
    'weights), not your input. Use it to flag disagreement between the pipeline\'s ',
    'confidence and your own ecological judgment in review_comment -- e.g. a low ',
    'pipeline posterior alongside your own "likely" rating is worth a note -- but do ',
    'not let it override your independent plausibility assessment itself, EXCEPT for ',
    'the UNPRECEDENTED/INDISTINGUISHABLE bar above, which is a hard requirement, ',
    'not a soft consideration.\n\n',
    'EXAMPLE OUTPUT FORMAT:\n',
    '[\n',
    '  {"taxon_name": "Gobiidae", "habitat_plausibility": "likely", ',
    '"geographic_plausibility": "likely", "scope_plausibility": "likely", ',
    '"contamination_risk": "low", "review_alternatives": null, ',
    '"review_lower_hypotheses": null, "review_confidence": "high", ',
    '"review_comment": null},\n',
    '  {"taxon_name": "Homo sapiens", "habitat_plausibility": "unlikely", ',
    '"geographic_plausibility": "likely", "scope_plausibility": "unlikely", ',
    '"contamination_risk": "high", "review_alternatives": null, ',
    '"review_lower_hypotheses": null, "review_confidence": "high", ',
    '"review_comment": "', example_comment, '"}\n',
    ']\n\n',
    'TAXA TO REVIEW:\n',
    taxa_block
  )

  prompt
}


#' Call LLM for a Batch, Retrying with Smaller Sub-batches on Truncation/Failure
#'
#' A truncated, empty, or unparseable response is very often caused by the
#' requested batch overflowing \code{llm_fn}'s response token budget --
#' \code{taxa_per_call} is a single global knob, so the safest per-batch fix
#' is to halve just the batch that actually failed and retry (a smaller batch
#' asks for a proportionally shorter response, directly relieving the token
#' pressure) rather than lowering \code{taxa_per_call} for the whole run.
#' A hard \code{llm_fn} error (network/auth/etc.) is deliberately NOT retried
#' this way -- a smaller batch can't fix a broken call, so that error is
#' surfaced once, immediately, exactly as before this mechanism existed.
#' @noRd
.review_batch_with_retry <- function(taxa_batch, ctx, target_group, marker,
                                     data_type, use_candidates, llm_fn,
                                     max_tokens, taxon_rank_col, verbose,
                                     pause_seconds, batch_label, max_retries,
                                     depth = 0L, prompt_log = NULL) {

  prompt <- .build_review_prompt(taxa_batch, ctx, target_group, marker,
                                 data_type, use_candidates)

  # Recorded by reference (an environment, not a data-frame attribute) so it
  # survives every rbind()/retry-recursion untouched -- lets a caller inspect
  # exactly what was sent to the LLM via attr(result, "llm_prompts") without
  # threading a second return value through every call site.
  if (!is.null(prompt_log)) assign(batch_label, prompt, envir = prompt_log)

  call_error <- NULL
  raw <- tryCatch(
    if (is.null(max_tokens)) llm_fn(prompt) else llm_fn(prompt, max_tokens = max_tokens),
    error = function(e) {
      call_error <<- conditionMessage(e)
      NULL
    }
  )

  if (!is.null(call_error)) {
    warning(sprintf("LLM call failed for batch %s: %s. Using NA defaults.",
                    batch_label, call_error), call. = FALSE)
    result <- .parse_review_response(NULL, taxa_batch, target_group,
                                     taxon_rank_col, use_candidates)
    attr(result, "status")           <- NULL
    attr(result, "pending_warnings") <- NULL
    return(result)
  }

  parsed  <- .parse_review_response(raw, taxa_batch, target_group,
                                    taxon_rank_col, use_candidates)
  status  <- attr(parsed, "status")
  pending <- attr(parsed, "pending_warnings")

  can_retry <- status %in% c("truncated", "failed") &&
    depth < max_retries && nrow(taxa_batch) > 1L

  if (can_retry) {
    if (verbose)
      message(sprintf(
        "  Batch %s %s (%d taxa) -- retrying as smaller sub-batches...",
        batch_label,
        if (status == "failed") "returned no usable content" else "was truncated",
        nrow(taxa_batch)
      ))
    mid   <- ceiling(nrow(taxa_batch) / 2)
    left  <- taxa_batch[seq_len(mid), , drop = FALSE]
    right <- taxa_batch[(mid + 1L):nrow(taxa_batch), , drop = FALSE]

    left_result <- .review_batch_with_retry(
      left, ctx, target_group, marker, data_type, use_candidates, llm_fn,
      max_tokens, taxon_rank_col, verbose, pause_seconds,
      paste0(batch_label, "a"), max_retries, depth + 1L, prompt_log
    )
    Sys.sleep(pause_seconds)
    right_result <- .review_batch_with_retry(
      right, ctx, target_group, marker, data_type, use_candidates, llm_fn,
      max_tokens, taxon_rank_col, verbose, pause_seconds,
      paste0(batch_label, "b"), max_retries, depth + 1L, prompt_log
    )
    return(rbind(left_result, right_result))
  }

  for (w in pending) warning(w, call. = FALSE)
  attr(parsed, "status")           <- NULL
  attr(parsed, "pending_warnings") <- NULL
  parsed
}


#' Parse LLM Review Response
#'
#' Never calls \code{warning()} directly. Returns the parsed result with two
#' attributes -- \code{status} (\code{"complete"}, \code{"truncated"}, or
#' \code{"failed"}) and \code{pending_warnings} (character vector of
#' not-yet-emitted warning messages) -- so \code{.review_batch_with_retry()}
#' can decide whether to retry with a smaller batch before emitting anything.
#' @noRd
.parse_review_response <- function(response, taxa_batch, target_group,
                                   taxon_rank_col, use_candidates = FALSE) {

  expected_taxa <- taxa_batch$taxon_name
  # names = expected_taxa by default (the whole-batch NA-fill case); also
  # reused below for the narrower "LLM omitted these specific taxa" case, so
  # both NA-filled shapes are built from one place.
  make_default <- function(names = expected_taxa) {
    data.frame(
      taxon_name              = names,
      habitat_plausibility    = NA_character_,
      geographic_plausibility = NA_character_,
      scope_plausibility      = NA_character_,
      contamination_risk      = NA_character_,
      review_alternatives     = NA_character_,
      review_lower_hypotheses = NA_character_,
      review_confidence       = NA_character_,
      review_comment          = NA_character_,
      stringsAsFactors = FALSE
    )
  }

  .with_status <- function(result, status, pending_warnings = character(0)) {
    attr(result, "status")           <- status
    attr(result, "pending_warnings") <- pending_warnings
    result
  }

  if (is.null(response) || !nzchar(trimws(response))) {
    return(.with_status(make_default(), "failed",
                        "Empty LLM response. Returning NA defaults."))
  }

  cleaned <- trimws(response)

  # Strategy 1: Strip markdown fences
  if (grepl("```", cleaned)) {
    fenced <- sub("(?s).*?```(?:json)?\\s*", "", cleaned, perl = TRUE)
    fenced <- sub("(?s)\\s*```.*", "", fenced, perl = TRUE)
    fenced <- trimws(fenced)
  } else {
    fenced <- cleaned
  }

  # Strategy 2: Parse directly
  parsed <- .parse_json_text(fenced)

  # Strategy 3: Extract [...] array
  if (is.null(parsed) || !is.data.frame(parsed)) {
    # sub() returns its input UNCHANGED when the pattern doesn't match, so
    # arr_str is whatever the model actually said whenever no JSON array was
    # found -- hence .parse_json_text()'s guard matters here too.
    arr_str <- sub("(?s).*?(\\[\\s*\\{[\\s\\S]*\\}\\s*\\]).*", "\\1",
                   cleaned, perl = TRUE)
    parsed <- .parse_json_text(arr_str)
  }

  # Strategy 4: Truncated JSON recovery
  if (is.null(parsed) || !is.data.frame(parsed))
    parsed <- .recover_truncated_json(fenced)

  if (is.null(parsed) || !is.data.frame(parsed) || nrow(parsed) == 0L) {
    n <- nchar(trimws(response))
    tail_str <- if (n > 200L) substr(trimws(response), max(1L, n - 200L), n) else trimws(response)
    return(.with_status(make_default(), "failed", sprintf(
      "Could not parse LLM response as JSON. Returning NA defaults.\n  Response length: %d chars; ends with: ...%s",
      n, tail_str
    )))
  }

  pending <- character(0)
  status  <- "complete"

  n_recovered <- nrow(parsed)
  n_expected  <- length(expected_taxa)
  if (n_recovered < n_expected) {
    status  <- "truncated"
    pending <- c(pending, sprintf(
      "LLM response was truncated. Recovered %d of %d taxa from partial JSON.",
      n_recovered, n_expected
    ))
  }

  if (!"taxon_name" %in% names(parsed)) {
    return(.with_status(make_default(), "failed",
                        "LLM response missing 'taxon_name' field. Returning NA defaults."))
  }

  # Reads col_name out of `df` explicitly (not `parsed` via lexical scope) --
  # a single-use helper local to this function; not duplicated elsewhere in
  # the package or ecosystem (checked), so kept inline rather than factored
  # into a shared utility, but taking `df` as an argument makes the
  # dependency visible at each call site instead of implicit.
  .safe_col <- function(input_df, col_name) {
    if (col_name %in% names(input_df)) {
      vals <- as.character(input_df[[col_name]])
      vals[vals %in% c("null", "NULL", "NA")] <- NA_character_
      vals
    } else {
      rep(NA_character_, nrow(input_df))
    }
  }

  result <- data.frame(
    taxon_name              = as.character(parsed$taxon_name),
    habitat_plausibility    = .safe_col(parsed, "habitat_plausibility"),
    geographic_plausibility = .safe_col(parsed, "geographic_plausibility"),
    scope_plausibility      = .safe_col(parsed, "scope_plausibility"),
    contamination_risk      = .safe_col(parsed, "contamination_risk"),
    review_alternatives     = .safe_col(parsed, "review_alternatives"),
    review_lower_hypotheses = .safe_col(parsed, "review_lower_hypotheses"),
    review_confidence       = .safe_col(parsed, "review_confidence"),
    review_comment          = .safe_col(parsed, "review_comment"),
    stringsAsFactors = FALSE
  )

  if (is.null(target_group))
    result$scope_plausibility <- NA_character_

  # Suppress lower hypotheses when candidates were supplied (already known)
  if (use_candidates || is.null(taxon_rank_col))
    result$review_lower_hypotheses <- NA_character_

  # Normalize taxon names: strip trailing punctuation + case-fold for matching.
  # LLMs sometimes append periods, commas, or authority strings to names they
  # return. Exact-string join would silently drop those rows. Attempt a
  # normalised fallback: if a result name doesn't match any expected name
  # exactly but matches one after normalisation, remap it to the canonical
  # expected name and warn so the caller can inspect.
  # Also strips a trailing "(rank: ...)" annotation -- taxa_batch's own prompt
  # rendering shows each taxon as "- Cottus (rank: Cottus aleuticus)" when
  # taxon_rank_col is supplied, and "taxon_name: the exact taxon name as
  # provided" can lead the LLM to echo the whole displayed string back,
  # including the parenthetical, rather than just the bare name. Confirmed as
  # a real failure mode 2026-07-14: an entire batch's taxon_name values came
  # back as "Cottus (rank: Cottus aleuticus)" etc., which the previous
  # punctuation-only normalisation couldn't recover -- every taxon in the
  # batch was wrongly treated as omitted and filled with NA, regardless of how
  # easy the taxon itself was to assess.
  # 2026-09-04: widened to the "(unresolved candidates; consensus rank: X)"
  # form as well. .build_taxa_block() renders an UNRESOLVED candidate set as
  # "- <label> (unresolved candidates; consensus rank: <rank>)", and the model
  # echoes that whole decorated string back just as it does for "(rank: ...)".
  # The old pattern required the parenthetical to begin with "rank:", so the
  # unresolved form never normalised, every slash taxon was treated as omitted
  # and filled with NA, and the workflows' export filters then dropped those
  # rows without a word -- 113 of 885 on GreatLakes 2026-09-04, every one of
  # them a multi-candidate set. Singletons were unaffected because their
  # "(rank: ...)" annotation WAS handled, which is exactly why the loss looked
  # like "coarse ranks are excluded on purpose".
  .norm <- function(x) {
    x <- sub("(?i)\\s*\\(\\s*(?:unresolved candidates|rank\\s*:)[^)]*\\)\\s*$",
             "", trimws(x), perl = TRUE)
    tolower(trimws(gsub("[.,;:]+$", "", trimws(x))))
  }
  expected_norm <- .norm(expected_taxa)

  unmatched_idx <- which(!result$taxon_name %in% expected_taxa)
  if (length(unmatched_idx) > 0L) {
    result_norm <- .norm(result$taxon_name)
    remapped <- character(0)
    for (i in unmatched_idx) {
      hit <- which(expected_norm == result_norm[i])
      if (length(hit) == 1L) {
        remapped <- c(remapped,
                      sprintf("'%s' -> '%s'", result$taxon_name[i], expected_taxa[hit]))
        result$taxon_name[i] <- expected_taxa[hit]
      }
    }
    if (length(remapped) > 0L)
      pending <- c(pending, sprintf(
        "LLM returned %d name(s) that required normalised matching: %s",
        length(remapped), paste(remapped, collapse = "; ")
      ))
  }

  # Fill any remaining missing taxa (truly absent from LLM response) with NAs
  missing_taxa <- setdiff(expected_taxa, result$taxon_name)
  if (length(missing_taxa) > 0L) {
    pending <- c(pending, sprintf("LLM omitted %d taxa. Filling with NA defaults: %s",
                    length(missing_taxa),
                    paste(missing_taxa, collapse = ", ")))
    result <- rbind(result, make_default(missing_taxa))
  }

  result <- result[result$taxon_name %in% expected_taxa, , drop = FALSE]

  .with_status(result, status, pending)
}


#' Parse a JSON string that came back from the LLM, and ONLY a JSON string
#'
#' \code{jsonlite::fromJSON()} accepts a JSON string, a URL, or a file path in
#' the same argument: when a short input does not validate as JSON it is
#' retried as \code{url()} (if it starts with http:// or https://) or as
#' \code{file()} (if such a file exists). Every string reaching the parser here
#' is LLM-generated, and none of the three call sites guarantees valid JSON --
#' \code{sub()} returns its input unchanged when the pattern doesn't match --
#' so a model reply consisting of a bare URL or path would be FETCHED or READ
#' rather than simply failing to parse. Requiring a JSON opening bracket is
#' enough to rule that out and changes nothing for real responses: every
#' string the three call sites intend to parse begins with \code{[} or
#' \code{\{}, and anything else already failed to parse before.
#' @noRd
.parse_json_text <- function(text) {
  if (!is.character(text) || length(text) != 1L || is.na(text)) return(NULL)
  if (!grepl("^\\s*[\\[{]", text, perl = TRUE)) return(NULL)
  tryCatch(jsonlite::fromJSON(text, simplifyDataFrame = TRUE),
           error = function(e) NULL)
}


#' Recover Parseable Objects from Truncated JSON Array
#' @noRd
.recover_truncated_json <- function(text) {
  if (is.null(text) || !nzchar(trimws(text))) return(NULL)

  arr_start <- regexpr("\\[", text)
  if (arr_start < 0L) return(NULL)

  text_from_arr    <- substring(text, arr_start)
  brace_positions  <- gregexpr("\\}", text_from_arr)[[1]]
  if (brace_positions[1] < 0L) return(NULL)

  for (i in rev(seq_along(brace_positions))) {
    candidate <- paste0(substring(text_from_arr, 1L, brace_positions[i]), "\n]")
    parsed <- .parse_json_text(candidate)
    if (is.data.frame(parsed) && nrow(parsed) > 0L) return(parsed)
  }

  NULL
}
