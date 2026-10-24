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
#' observation and "B/A" on another; joining on the label would leave one of
#' them unmatched and therefore unscored. Sets are also deduplicated
#' canonically, so each unit is reviewed exactly once regardless of which
#' ordering appears in the data. Display labels are unchanged.
#'
#' @param cache_dir Character or \code{NULL} (default). Directory for the
#'   per-taxon review cache. \code{NULL} disables caching entirely.
#'   Supplying a directory makes a re-run
#'   REPRODUCIBLE and stops it re-paying for verdicts already obtained: the
#'   review is a judgement, and two runs on identical input can disagree.
#'   One small \code{.rds} per reviewed taxon, keyed
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
#' @param consensus_provenance Logical (default \code{TRUE}). When
#'   \code{TRUE} and \code{input_df} carries
#'   \code{posterior_consensus()}'s \code{consensus_hypothesis_type}, a call
#'   that landed on an UNREFERENCED row adds a note saying so, with the scope
#'   the name came from, that scope's RANK, and whether the records offered one
#'   candidate or several. This matters because no reference sequence exists
#'   for such a taxon: the sequence settled only that an unreferenced relative
#'   beats every referenced candidate, and the NAME was supplied by the
#'   occurrence records in that scope -- sibling named rows carry identical
#'   likelihoods, so the sequence cannot choose between them. Nothing else in
#'   the context reveals this: \code{consensus_posterior} and
#'   \code{winner_prior} are both high on these calls,
#'   \code{likelihood_support} reads near 1 (truthfully about the hypothesis,
#'   silently about the name), and \code{winner_rank_expanded} is a different
#'   mechanism. The scope RANK is the load-bearing part: a scope at order or
#'   class rank is an elimination over a very wide clade. Silently skipped when
#'   the column is absent.
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
#'   the geography GUIDELINES bullets (see \code{@section Geography guidelines}
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
#'   Recognised fields: \code{geography}, \code{habitat} (or
#'   \code{main_habitat}), \code{date}. A \code{build_context()} output
#'   works directly: with no explicit \code{geography}, its
#'   \code{geographic_hint} and \code{ecoregion} are combined as
#'   \code{"hint (ecoregion)"}, so the wording you supplied is not replaced
#'   by the single ecoregion synthesised for the whole taxon list. Supply
#'   \code{geography} yourself to control the line exactly -- most useful
#'   when a study spans more than one ecoregion: the synthesised
#'   \code{ecoregion} is a single string for the whole taxon list, so on a
#'   multi-ecoregion study the parenthetical names only one of them and is
#'   narrower than the study. At minimum, supply \code{geography} and
#'   \code{habitat}.
#' @param target_group Character or \code{NULL}. Taxonomic target group
#'   (e.g., \code{"fish"}, \code{"birds"}). When supplied, the LLM
#'   populates \code{llm_scope_plausibility}. Default \code{NULL}.
#' @param marker Character or \code{NULL}. Molecular marker or detection
#'   method (e.g., \code{"12S"}, \code{"COI"}, \code{"camera trap"}).
#'   Provides contaminant context. Default \code{NULL}.
#' @param data_type Character. Detection method: one of \code{"eDNA"},
#'   \code{"acoustic"} or \code{"image"}. REQUIRED -- there is no default,
#'   because the value changes the contaminant-assessment guidance the LLM is
#'   given, and a wrong assumption there is silent. State the method explicitly.
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
#'   provider = "anthropic")}.
#'   No sampling temperature is set here: the default path calls
#'   \code{call_api()} with the provider's default. Some current models reject
#'   the \code{temperature} parameter outright (HTTP 400, "temperature is
#'   deprecated for this model"), so set one in your own \code{llm_fn} only for
#'   a model that accepts it. The \code{cache_dir} key fingerprints the
#'   deparsed SOURCE of \code{llm_fn}: a temperature, model or provider written
#'   literally into it is covered, and changing it moves the key. One supplied
#'   indirectly -- from a variable, an option or a closure over a value -- is
#'   invisible to the key; after changing such a value, use a new
#'   \code{cache_dir} or a new \code{model_label}.
#' @param model_label Character or \code{NULL}. A name for the model behind
#'   \code{llm_fn}, recorded in the cache key so a verdict obtained from one
#'   model is never served to a call asking another. \strong{Required whenever
#'   \code{cache_dir} is set and \code{llm_fn} is a function you wrote}: all
#'   that can be seen of such a closure is its source text, and a wrapper
#'   written \code{function(p, ...) call_api(p, model = MODEL, ...)} deparses
#'   to the variable NAME \code{"MODEL"}, not to the model it holds -- so
#'   switching \code{MODEL} would give a byte-identical key and serve the
#'   first model's verdicts to the second run, silently. That call now stops
#'   and asks for this argument. Default \code{NULL} is still accepted with no
#'   cache, and for an \code{llm_fn} a loaded namespace can name (such as
#'   \code{TaxaTools::call_api} itself), where the identity is derived from
#'   \code{options("TaxaID.provider")} and the function. Even then it names the
#'   FUNCTION, not the model a tier resolves to, so a cached call warns and
#'   points here.
#' @param taxa_per_call Integer. Maximum taxa (or candidate sets) per LLM call.
#'   Default \code{15L}. Candidate-set entries are longer than single taxon
#'   names; consider reducing to 8--10 when using \code{plausible_taxa_col}.
#' @param max_tokens Integer or \code{NULL}. Maximum response tokens requested
#'   from \code{llm_fn} (forwarded as \code{llm_fn(prompt, max_tokens = max_tokens)}
#'   whenever supplied). Default \code{NULL} -- does not pass \code{max_tokens}
#'   at all, so \code{llm_fn}'s own default applies (\code{16000L} for
#'   \code{TaxaTools::call_api()}). Raise this if \code{max_retries} alone
#'   isn't resolving truncation warnings for your data -- e.g. a long,
#'   multi-marker \code{marker} string can inflate per-taxon response length
#'   enough that even the smallest retry sub-batch still truncates.
#' @param max_retries Integer. The per-batch retry budget, shared by two
#'   mechanisms. (1) When a batch's LLM response is truncated, empty, or
#'   unparseable, the batch is automatically split in half and retried -- a
#'   smaller batch requests a proportionally shorter response, directly
#'   relieving token-budget pressure. (2) When a response parses cleanly and is
#'   the right shape but simply OMITS specific taxa, those taxa (and only
#'   those) are re-asked in a follow-up call. The second case is not
#'   truncation, so the halving retry never fires for it -- see
#'   \code{@section Unreviewed rows} for how omitted taxa are recovered
#'   instead. Both stop after \code{max_retries} attempts and fall back to
#'   \code{NA} defaults for whatever is still missing. Neither applies to a
#'   hard \code{llm_fn} error (e.g. network/auth failure): a smaller or
#'   narrower batch can't fix that, so it is reported immediately without
#'   retrying. \code{0L} disables both mechanisms, meaning exactly one call
#'   per batch. Default \code{2L}.
#' @param on_unreviewed Character. What to do when taxa still have no verdict
#'   after the re-asks: \code{"warn"} (default) reports them and continues,
#'   \code{"error"} stops the run, \code{"ignore"} is silent. The residue is
#'   recorded on the result either way (see \code{@section Unreviewed rows}).
#'   Production workflows pass \code{"error"}: an unreviewed row is dropped
#'   by the usual export filters, so a run with residue produces a species
#'   list that is silently short.
#' @param pause_seconds Numeric. Seconds to pause between LLM calls.
#'   Default \code{1}.
#' @param verbose Logical. Print progress messages. Default \code{TRUE}.
#'
#' @param poor_absolute_fit_col Character or \code{NULL}. Column name for
#'   \code{TaxaLikely::evaluate_likelihoods()}'s \code{poor_absolute_fit}, as
#'   passed through by \code{posterior_consensus()}: \code{TRUE} when the
#'   unit's best raw match identity reaches no rank threshold for the marker.
#'   Likelihoods are normalised to the unit maximum, so such a call can still
#'   carry a high posterior. When \code{TRUE} for any row sharing a label, one
#'   fact line (e.g. "best match identity 86.1% is below every rank threshold
#'   for this marker (poor absolute fit)") is added to that taxon's pipeline
#'   notes; \code{FALSE} or \code{NA} adds nothing. Because the note is part
#'   of what is reviewed, a change in the flag changes the cache key. Silently
#'   skipped when absent. Default \code{"poor_absolute_fit"}. Set to
#'   \code{NULL} to disable.
#' @param best_identity_col Character or \code{NULL}. Column name for the
#'   \code{best_identity} (percent) quoted in that note. Silently skipped when
#'   absent (the note then omits the number). Default \code{"best_identity"}.
#'   Set to \code{NULL} to disable.
#' @param sites \code{NULL} (default) or a data frame of study sites with
#'   columns \code{site} (unique names), \code{lat} and \code{lon} (decimal
#'   degrees; extra columns are ignored). When supplied the LLM is shown the
#'   sites (sorted south to north) and asked for each taxon's range LIMITS;
#'   the site and study verdicts are computed from them here, which adds the
#'   per-row \code{llm_geographic_plausibility_site} column; see
#'   \code{@section Site-aware geography}. With \code{NULL} nothing changes:
#'   the prompt, the cache key and the output columns are exactly those of a
#'   call without this argument.
#' @param site_col Character. Column of \code{input_df} whose values match
#'   \code{sites$site}. Only read when \code{sites} is supplied (an error if
#'   the column is absent then); non-\code{NA} values not found in
#'   \code{sites$site} are named in a warning and those rows get the
#'   study-wide verdict. Not part of the cache key, since it does not change
#'   the prompt. Default \code{"site"}.
#' @param occurrence_data \code{NULL} (default) or a data frame of occurrence
#'   records for the study region -- an occurrence table as
#'   \code{TaxaFetch} writes one, with \code{decimalLatitude},
#'   \code{decimalLongitude}, optionally \code{point_id}, and the rank columns
#'   to match on (\code{taxon_name}, \code{genus}, \code{family},
#'   \code{order}, \code{class}, \code{phylum}). When supplied, each taxon
#'   line in the prompt gains the pool's facts about that taxon -- record and
#'   location counts, the latitude extent, and per detected site the nearest
#'   record and the record locations within 50 km -- and the guidelines gain a
#'   bullet on how to read them. Requires \code{sites}: the facts are per
#'   detected site, so there is nothing for most of them to be about without a
#'   site table, and the per-taxon counts alone have not been evaluated. A
#'   missing coordinate column is an error rather than an empty bracket,
#'   because an empty bracket reads as "no records" and "we could not look"
#'   must never be served as "nothing there". Measured on the maintainer's own
#'   labels for the 34 hardest taxa: agreement 75\% -> 78\%, precision
#'   80\% -> 84\%, and the rows it newly acted on were 94\% rows he also
#'   acted on. Part of the cache key, including the pool's latitude extent.
#' @return The input data frame with the review columns appended:
#' \describe{
#'   \item{\code{llm_habitat_plausibility}}{likely / possible / unlikely,
#'     derived in code from \code{llm_p_habitat}; see \code{@section The
#'     answer is a probability}. See \code{@section Column naming} below for
#'     why this and the next three columns carry an \code{llm_} prefix.}
#'   \item{\code{llm_geographic_plausibility}}{likely / possible / unlikely.}
#'   \item{\code{llm_scope_plausibility}}{likely / possible / unlikely, or
#'     \code{NA} if \code{target_group} not supplied.}
#'   \item{\code{llm_contamination_risk}}{high / moderate / low.}
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
#'     \code{@section Geography guidelines} below for why this exists as a
#'     deterministic column rather than relying on \code{review_comment}
#'     alone.}
#'   \item{\code{llm_p_habitat}, \code{llm_p_habitat_lo},
#'     \code{llm_p_habitat_hi}}{The habitat probability the model gave and the
#'     90\% range it stated for it.}
#'   \item{\code{llm_p_transported}}{Probability that the taxon\'s DNA could
#'     plausibly reach these samples from adjacent habitats. Asked separately
#'     from residency so that "could have washed in" is not scored as "lives
#'     here". Output only: no rule reads it.}
#'   \item{\code{llm_p_scope}, \code{llm_p_scope_lo},
#'     \code{llm_p_scope_hi}}{Likewise for scope.}
#'   \item{\code{llm_p_contamination}}{The contamination probability.}
#'   \item{\code{llm_p_geographic}}{The study-wide geographic probability:
#'     with \code{sites}, the MAXIMUM over the taxon\'s detected sites.}
#' }
#' The stated 90\% ranges feed no rule either. They are kept because they were
#' measured to be 5--10 times the model\'s own run-to-run spread, so they
#' express uncertainty about the TAXON rather than noise, which is worth having
#' in front of a reviewer.
#' When \code{sites} is supplied the data frame also carries
#' \code{llm_geographic_plausibility_site} (see \code{@section Site-aware
#' geography}) and an \code{attr(result, "geographic_by_site")} data frame, one
#' row per reviewed taxon, giving the parsed range answer (\code{rule},
#' \code{range_south_lat}, \code{range_north_lat}, \code{p_inside_range},
#' \code{p_outside_range}, \code{sites_outside_range} as a
#' semicolon-separated string, \code{n_unknown_sites}, and \code{how}, which
#' records a swap, an ignored site name or a fallback). With
#' \code{occurrence_data} it also carries \code{llm_p_geographic_site},
#' \code{llm_p_inside_range}, \code{llm_p_outside_range},
#' \code{llm_range_known}, \code{llm_range_south_lat} and
#' \code{llm_range_north_lat} -- the latter five with \code{sites} alone.
#'
#' Also carries \code{"unreviewed_taxa"} (character vector, possibly empty --
#' the taxon/candidate-set labels the LLM never returned a verdict for) and
#' \code{"n_unreviewed_rows"} (integer -- input rows left with \code{NA} in
#' every \code{llm_} column) attributes; both are ALWAYS present. See
#' \code{@section Unreviewed rows}. Attributes do not survive a \code{dplyr}
#' verb, so read them immediately after the call.
#'
#' Also carries an \code{"llm_prompts"} attribute -- a named list of the
#' exact prompt string sent for each LLM call (named by batch number, with
#' an \code{"a"}/\code{"b"} suffix per retry sub-batch split, e.g.
#' \code{"2b"}). Inspect via \code{attr(reviewed, "llm_prompts")} to see
#' precisely what the LLM was asked, e.g. before trusting an unexpected
#' result or when tuning \code{context}/\code{target_group}/\code{marker}.
#'
#' @section Unreviewed rows:
#' An LLM response can parse cleanly, be the right length, and still leave
#' specific taxa out -- consistently the long compound slash labels, i.e. the
#' hardest rows, not random ones. That is not truncation, so the halving retry
#' alone would not catch it. Without a dedicated safeguard those taxa would be
#' filled with \code{NA} in all four \code{llm_} columns, and because export
#' chains filter with \code{!= "unlikely"}, which \strong{discards \code{NA}},
#' an unreviewed observation would be silently removed from the final species
#' list.
#'
#' Three mechanisms close this. (1) Omitted taxa are \strong{re-asked}, alone, up
#' to \code{max_retries} times; the cost is pay-per-failure, and the re-asking
#' stops early when a re-ask recovers nothing. (2) An unreviewed taxon is
#' \strong{never cached} -- a cached entry holding no verdict is treated as a
#' MISS, so an existing cache heals itself. (3) Whatever residue survives is
#' \strong{loud}: named in \code{attr(result, "unreviewed_taxa")}, counted in
#' \code{attr(result, "n_unreviewed_rows")}, and escalated per
#' \code{on_unreviewed}.
#'
#' The export filters themselves are deliberately UNCHANGED (still
#' \code{!= "unlikely"}, still dropping \code{NA}). Keeping an unreviewed row
#' in a species list would put an unvetted taxon in the output distinguishable
#' only by its \code{NA}s; stopping the run instead makes the decision
#' per-run and explicit.
#'
#' @section Column naming:
#' The four independent LLM judgments (\code{llm_habitat_plausibility}/
#' \code{llm_geographic_plausibility}/\code{llm_scope_plausibility}/
#' \code{llm_contamination_risk}) carry the \code{llm_} prefix because they are
#' independent LLM judgments -- by design NOT derived from or gated by any
#' pipeline-computed value (see \code{@section Pipeline context} below). An
#' unprefixed name would read as pipeline output. The LLM's own JSON response
#' schema (what \code{.build_review_prompt()} asks for and
#' \code{.parse_review_response()} parses) uses the bare names internally --
#' only the final output column names carry the prefix.
#'
#' @section Geography guidelines:
#' Three conditional GUIDELINES bullets shape the geographic rating, each
#' added only when a taxon in the batch carries the matching bracket fact:
#' \enumerate{
#'   \item{\code{"pipeline flags UNPRECEDENTED"} (no local record in the
#'     pipeline's occurrence data): absence of a citeable record is not
#'     evidence of absence. Without specific local evidence the geographic
#'     probability is intermediate, not high; a low one needs positive
#'     evidence of being out of range (a native range elsewhere with no known
#'     introduction to the region, or a habitat the taxon cannot use). This
#'     bullet exists because an earlier, harder rule ("cite a local record or
#'     rate it unlikely") rated widely introduced species out of range whenever
#'     the model could not recall a record on that draw.}
#'   \item{\code{"pipeline flags INDISTINGUISHABLE"} (a confusable relative
#'     could score as well) weakens confidence in the name only and must not by
#'     itself lower the habitat, geographic or scope probability. The same
#'     holds for a \code{"(poor absolute fit)"} note.}
#'   \item{\code{"pipeline call: <taxon> (<rank>)"}, shown when the reviewed
#'     label is not the call itself (a species label on a genus or family
#'     call): the call at its rank is the claim, and the species are candidates
#'     within it.}
#' }
#' Prompt compliance is never guaranteed, so the deterministic
#' \code{geographic_disagreement_basis} output column (see \code{@return}) still
#' marks every row whose derived geographic verdict is likely or possible
#' despite either flag; filter on it to audit those rows.
#'
#' Each taxon line carries an id (\code{[T1]}, \code{[T2]}, ...) that the
#' answer must echo; answers are matched by id first, then by name, so a long
#' candidate-set label echoed back reformatted is still matched. A response
#' matching none of several sets is treated as failed (halved and retried),
#' and an omission a re-ask cannot recover is re-asked one set per call.
#'
#' @section The answer is a probability:
#' The LLM is asked for a probability for each judgement, not a category, and
#' the \code{llm_*_plausibility} / \code{llm_contamination_risk} columns are
#' derived from those probabilities here. The cuts are
#' \code{unlikely < 0.10 <= possible < 0.70 <= likely}, and for contamination
#' \code{low < 0.20 <= moderate < 0.70 <= high}.
#'
#' Why: a category is the least reproducible part of the review. Measured on
#' 150 taxa of a real study with \code{claude-opus-5-5}, re-asking the same
#' categorical prompt changed 10\% of the decisions the verdicts drive. Asking
#' for a probability and cutting it here leaves 3\%, and agrees with the
#' maintainer's own labels on 78\% of rows against 67\%.
#'
#' The cut is applied AFTER the cache, never before it. What a cache entry
#' holds is the probability -- the model's answer -- and a cut is this
#' function's reading of it. So changing a cut takes effect for taxa already
#' cached, with no new LLM calls, and the cuts are deliberately not part of the
#' cache key.
#'
#' Four judgements are asked separately, which is the point of the format:
#' habitat is LIVING CONDITIONS only ("does it live in this kind of habitat,
#' wherever its range is"), scope is the KIND OF ORGANISM and its depth or zone
#' only, and whether the taxon occurs in the study region is geography in both
#' cases. \code{llm_p_transported} carries "its DNA could have reached these
#' samples" separately from "it lives here", so a taxon washed in from adjacent
#' water is not scored as a resident. The habitat and target-group wording in
#' the prompt comes from \code{context$habitat} and \code{target_group}, so
#' nothing about any particular study is built in; the worked examples name no
#' real taxon for the same reason.
#'
#' @section Site-aware geography:
#' A study that spans a coast or a latitude gradient has no single answer to
#' "is this taxon geographically plausible here?": a tropical reef fish is
#' plausible at the southern sites and not at the northern ones. With
#' \code{sites} supplied the prompt lists the sites (name, latitude, longitude;
#' sorted south to north), tells each taxon line which of them it was detected
#' at, and asks for the taxon's range LIMITS rather than for a verdict:
#' \itemize{
#'   \item{\code{range_known}: whether the model can state the limits at all.}
#'   \item{\code{range_south_lat}, \code{range_north_lat}: the limits in
#'     decimal degrees N, either or both \code{null} for "no limit within the
#'     study on that side".}
#'   \item{\code{sites_outside_range}: sites outside the range when latitude
#'     cannot describe it (island-only, a gap, or a study that runs east to
#'     west).}
#'   \item{\code{p_inside_range}, \code{p_outside_range}: the probability of
#'     occurrence at a site inside, and at a site outside, those limits.}
#' }
#' The site probability is then computed here: a site beyond a stated limit, or
#' named in \code{sites_outside_range}, takes \code{p_outside_range}; every
#' other site takes \code{p_inside_range}. The cuts turn that into the site
#' verdict. Asking for limits instead of a per-site verdict removes the model's
#' choice between rule shapes and gives "study-wide" a definition it did not
#' have.
#'
#' Output:
#' \itemize{
#'   \item{\code{llm_geographic_plausibility_site} and
#'     \code{llm_p_geographic_site}: the verdict and probability at the site
#'     named in each row's \code{site_col}. Rows with an \code{NA} site, or a
#'     site not in \code{sites}, get the study-wide pair. Unreviewed taxa stay
#'     \code{NA}.}
#'   \item{\code{llm_geographic_plausibility} and \code{llm_p_geographic}
#'     change meaning when \code{sites} is supplied: the probability is the
#'     MAXIMUM over the taxon's detected sites and the verdict is its level,
#'     computed here rather than asked for. Because the cut is monotone, that
#'     verdict is also the best site verdict, so \code{"unlikely"} study-wide
#'     means unlikely at every site.}
#' }
#' Guards on the answer, each recorded in the \code{how} column of
#' \code{attr(result, "geographic_by_site")}: a value that is not a latitude in
#' \code{[-90, 90]} is dropped; an INVERTED band -- a southern limit given as
#' \code{range_north_lat} -- is swapped rather than obeyed, since obeying it
#' would put every site outside the range and mark the taxon unlikely
#' everywhere; site names are matched ignoring case and surrounding spaces, and
#' names matching no site are ignored and counted in \code{n_unknown_sites}; a
#' list in which NO name is recognised is dropped whole, so it cannot appear to
#' have moved something while moving nothing; and a missing
#' \code{p_outside_range} gives \code{p_inside_range} everywhere, which never
#' manufactures an "outside" the model did not state.
#'
#' \code{range_known = FALSE} is a real answer, not a failure: it means the
#' model cannot place the taxon, so every site takes \code{p_inside_range},
#' which the guidelines tell it to make intermediate. Sites it named explicitly
#' are still honoured -- "I do not know the limits" and "not at that site" are
#' different claims. With no usable \code{p_inside_range} at all, geography is
#' \code{NA} unless the model volunteered a study-wide \code{p_geographic}; the
#' count of such taxa is reported when \code{verbose}.
#'
#' \strong{Known limitation.} Latitude limits suit a study that runs mostly
#' north to south, which is what this was evaluated on. For a study running
#' east to west, or at a single latitude, a range limit cannot be stated as a
#' latitude at all, and the prompt tells the model to use
#' \code{sites_outside_range} instead. That path works but has not been
#' measured.
#'
#' The cache key gains a digest of the sites (names and coordinates rounded to
#' 0.01 degree, order-independent) only when \code{sites} is supplied, so a
#' cached verdict obtained without sites is never served to a call with sites,
#' or the reverse. The sites a taxon was detected at are part of its own key,
#' because they are part of its prompt line. The parsed range answer is cached
#' with each taxon, so a cache hit reproduces
#' \code{llm_geographic_plausibility_site}.
#'
#' In \code{TaxaFlag::screen_assignments()}, \code{geography_col} can point at
#' \code{llm_geographic_plausibility_site} so the screen uses the verdict for
#' each row's own site.
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
#' output column. Set any of the four params to \code{NULL} to disable; all
#' four are silently skipped (not an error) when the named column is absent
#' from \code{input_df}.
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
#' iNat: in range, 1275 obs]"}). This matters because the same "unprecedented"
#' flag can have very different explanations: a genuine regional native not yet
#' recorded at this exact site, or a species thousands of km from any
#' GBIF-mapped occurrence.
#'
#' The per-taxon bracket is facts-only: no plausibility judgment is
#' pre-computed (as for \code{winner_rank_expanded}'s note above). Two caveats
#' about how to weigh these facts are added as a GUIDELINES bullet instead
#' (only when a batch has at least one such note), for the LLM to apply per
#' case: (1) GBIF's density map is raw, unfiltered global data -- an occurrence
#' found far away, especially in a small (1-2 cell) patch, may itself be a
#' single bad or mis-georeferenced GBIF record rather than a real population;
#' a small isolated patch is weaker evidence than a large one. (2) When iNat's
#' \code{matched_name} differs from the taxon under review, its \code{in_range}
#' verdict may describe a *different*, often more common, species due to a
#' fuzzy name-search match (e.g. a query for the European \emph{Gasterosteus
#' gymnurus} can resolve to \emph{Gasterosteus aculeatus}, returning a
#' misleading \code{in_range = TRUE}). \code{matched_name} is surfaced so a
#' reviewer (human or LLM) can catch this.
#'
#' Purely additive, as for "Pipeline context": never changes which rows are
#' reviewed, the dedup key, or any output column. Set any of the six params to
#' \code{NULL} to disable; all six are silently skipped when the named column
#' is absent from \code{input_df}.
#'
#' @seealso \code{\link{flag_contaminant}} for data-driven contaminant
#'   detection, \code{\link{flag_handler}} for temporal proximity flagging,
#'   \code{TaxaAssign::add_slash_taxon()} to add \code{irreducible_consensus}
#'
#' @examples
#' \dontrun{
#' # Standard review (consensus taxon only)
#' reviewed <- review_assignments(
#'   input_df = consensus_df,
#'   context = list(
#'     geography = "Palmyra Atoll, central Pacific",
#'     habitat = "coral reef"
#'   ),
#'   target_group = "fish",
#'   marker = "12S MiFish"
#' )
#'
#' # Candidate-aware review (recommended for upranked assignments)
#' consensus_df <- TaxaAssign::add_slash_taxon(consensus_df)
#' reviewed <- review_assignments(
#'   input_df = consensus_df,
#'   plausible_taxa_col = "plausible_taxa",
#'   irreducible_only = TRUE,
#'   context = ctx,
#'   target_group = "fish"
#' )
#' }
#'
#' @export
review_assignments <- function(input_df,
                               taxon_col = "consensus_taxon",
                               taxon_rank_col = NULL,
                               plausible_taxa_col = NULL,
                               irreducible_only = TRUE,
                               consensus_posterior_col = "consensus_posterior",
                               winner_prior_col = "winner_prior",
                               winner_rank_expanded_col = "winner_rank_expanded",
                               consensus_provenance = TRUE,
                               plausible_posteriors_col = "plausible_posteriors",
                               consensus_plausibility_col = "consensus_plausibility",
                               consensus_discrimination_col = "consensus_discrimination",
                               dist_nearest_occupied_km_col = "dist_nearest_occupied_km",
                               patch_diameter_km_col = "patch_diameter_km",
                               beyond_buffer_col = "beyond_buffer",
                               inat_in_range_col = "in_range",
                               inat_n_observations_col = "n_observations",
                               inat_matched_name_col = "matched_name",
                               context,
                               target_group = NULL,
                               marker = NULL,
                               data_type,
                               llm_fn = getOption("TaxaID.llm_fn", TaxaTools::call_api),
                               model_label = NULL,
                               taxa_per_call = 15L,
                               max_tokens = NULL,
                               max_retries = 2L,
                               pause_seconds = 1,
                               cache_dir = NULL,
                               on_unreviewed = c("warn", "error", "ignore"),
                               verbose = TRUE,
                               poor_absolute_fit_col = "poor_absolute_fit",
                               best_identity_col = "best_identity",
                               sites = NULL,
                               site_col = "site",
                               occurrence_data = NULL) {
  on_unreviewed <- match.arg(on_unreviewed)
  # --- Input validation ---
  # The occurrence facts are per taxon AND per detected site: the distance to
  # the nearest record and the record locations within 50 km of each site are
  # most of their measured value. With no site table there are no sites for
  # them to be about, and the per-taxon counts alone were never scored. Half
  # the data silently dropped is the worse outcome, so this is refused.
  if (!is.null(occurrence_data) && is.null(sites)) {
    stop(
      "'occurrence_data' needs 'sites' too: its facts are per detected site ",
      "(nearest record, record locations within 50 km), so there is nothing ",
      "for them to be about without a site table. Pass sites=, or leave ",
      "occurrence_data = NULL.",
      call. = FALSE
    )
  }
  if (!is.data.frame(input_df)) stop("'input_df' must be a data frame.", call. = FALSE)

  if (!taxon_col %in% names(input_df)) {
    stop(sprintf("Column '%s' not found in input_df.", taxon_col), call. = FALSE)
  }

  if (!is.null(taxon_rank_col) && !taxon_rank_col %in% names(input_df)) {
    stop(sprintf("Column '%s' not found in input_df.", taxon_rank_col), call. = FALSE)
  }

  if (!is.null(plausible_taxa_col) && !plausible_taxa_col %in% names(input_df)) {
    stop(sprintf("Column '%s' not found in input_df.", plausible_taxa_col), call. = FALSE)
  }

  # Pipeline-context column-name params are deliberately NOT validated for
  # presence in input_df -- unlike taxon_rank_col/plausible_taxa_col above, these
  # have non-NULL defaults matching TaxaAssign::posterior_consensus()'s own
  # output names, so an explicit-presence check would break every caller
  # whose input_df doesn't carry these columns (e.g. not built from
  # posterior_consensus() at all). Silently skipped instead (see
  # .summarise_pipeline_context()); only the parameter TYPE is checked here.
  if (!is.logical(consensus_provenance) || length(consensus_provenance) != 1L ||
    is.na(consensus_provenance)) {
    cli::cli_abort("{.arg consensus_provenance} must be TRUE or FALSE.")
  }
  for (col_param in list(
    consensus_posterior_col, winner_prior_col,
    winner_rank_expanded_col, plausible_posteriors_col,
    dist_nearest_occupied_km_col, patch_diameter_km_col,
    beyond_buffer_col, inat_in_range_col,
    inat_n_observations_col, inat_matched_name_col,
    consensus_plausibility_col, consensus_discrimination_col,
    poor_absolute_fit_col, best_identity_col
  )) {
    if (!is.null(col_param) && (!is.character(col_param) || length(col_param) != 1L)) {
      stop(paste(
        "'consensus_posterior_col', 'winner_prior_col',",
        "'winner_rank_expanded_col', 'plausible_posteriors_col',",
        "'dist_nearest_occupied_km_col', 'patch_diameter_km_col',",
        "'beyond_buffer_col', 'inat_in_range_col',",
        "'inat_n_observations_col', 'inat_matched_name_col',",
        "'consensus_plausibility_col', 'consensus_discrimination_col',",
        "'poor_absolute_fit_col', and 'best_identity_col' must",
        "each be a single character string or NULL."
      ), call. = FALSE)
    }
  }

  if (missing(context) || is.null(context)) {
    stop("'context' is required. Supply a named list or build_context() output.",
      call. = FALSE
    )
  }

  valid_types <- c("eDNA", "acoustic", "image")
  if (!is.character(data_type) || length(data_type) != 1L ||
    !data_type %in% valid_types) {
    stop(sprintf("'data_type' must be one of: %s", paste(valid_types, collapse = ", ")),
      call. = FALSE
    )
  }

  # --- Site-aware geography: validate the sites table (sites path only) ---
  if (!is.null(sites)) {
    sites <- .validate_review_sites(sites, input_df, site_col)
    if (!is.null(occurrence_data)) {
      occurrence_data <- .validate_occurrence_data(occurrence_data)
    }
  }

  # --- Normalise context ---
  ctx <- .normalise_context(context)

  # --- Build taxa_info: candidate-set path or consensus-taxon path ---
  use_candidates <- !is.null(plausible_taxa_col)

  # Maps each reviewed row's DISPLAY label back to its canonical (sorted-set)
  # join key; NULL on the non-candidate path, where the taxon name is the key.
  label_canon_map <- NULL

  if (use_candidates) {
    raw_sets <- input_df[[plausible_taxa_col]]
    taxa_sets <- lapply(raw_sets, function(x) sort(unique(x[!is.na(x) & nzchar(x)])))
    n_cands <- lengths(taxa_sets)

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
        if (n_cands[i] == 0L) {
          return(NA_character_)
        }
        if (n_cands[i] == 1L) {
          return(taxa_sets[[i]])
        }
        .build_candidate_label(taxa_sets[[i]])
      }, character(1L))
    }

    # Determine which rows to review
    if (irreducible_only) {
      if ("irreducible_consensus" %in% names(input_df)) {
        include_rows <- input_df[["irreducible_consensus"]] %in% TRUE
        if (verbose) {
          message(sprintf(
            "  irreducible_only = TRUE: %d of %d rows selected for review.",
            sum(include_rows & n_cands > 0L), nrow(input_df)
          ))
        }
      } else {
        if (verbose) {
          message(paste0(
            "  irreducible_only = TRUE but 'irreducible_consensus' column not found. ",
            "Run TaxaAssign::add_slash_taxon() to enable filtering. ",
            "Reviewing all non-empty candidate sets."
          ))
        }
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
    inc_ranks <- if (!is.null(taxon_rank_col)) {
      input_df[[taxon_rank_col]][include_rows]
    } else {
      rep(NA_character_, sum(include_rows))
    }

    taxa_info <- data.frame(
      taxon_name = inc_labels,
      taxon_rank = inc_ranks,
      .canon = canon_key[include_rows],
      stringsAsFactors = FALSE
    )
    # Dedup on the canonical set, not the label: one review per biological
    # unit. Where a unit appears under two orderings, deduping on the label
    # alone would review it twice, so this also removes a redundant LLM call
    # rather than adding one.
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

    if (nrow(taxa_info) == 0L) {
      stop("No candidate sets to review after filtering. ",
        "Check 'irreducible_only' and 'plausible_taxa_col'.",
        call. = FALSE
      )
    }
  } else {
    # --- Current path: dedup on consensus_taxon ---
    input_df$.join_key <- input_df[[taxon_col]]

    taxa <- unique(input_df[[taxon_col]])
    taxa <- taxa[!is.na(taxa) & nchar(trimws(taxa)) > 0]

    if (length(taxa) == 0L) {
      stop(sprintf("No non-NA taxa found in column '%s'.", taxon_col), call. = FALSE)
    }

    if (!is.null(taxon_rank_col)) {
      taxa_info <- unique(input_df[, c(taxon_col, taxon_rank_col), drop = FALSE])
      names(taxa_info) <- c("taxon_name", "taxon_rank")
      taxa_info <- taxa_info[!is.na(taxa_info$taxon_name) &
        nchar(trimws(taxa_info$taxon_name)) > 0, , drop = FALSE]
      taxa_info <- taxa_info[!duplicated(taxa_info$taxon_name), , drop = FALSE]
    } else {
      taxa_info <- data.frame(
        taxon_name = taxa, taxon_rank = NA_character_,
        stringsAsFactors = FALSE
      )
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
    winner_rank_expanded_col, consensus_plausibility_col, consensus_discrimination_col,
    consensus_provenance = consensus_provenance,
    poor_absolute_fit_col = poor_absolute_fit_col,
    best_identity_col = best_identity_col
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
    pn <- if (!is.null(pipeline_ctx)) {
      pipeline_ctx$pipeline_note[match(taxa_info$taxon_name, pipeline_ctx$taxon_name)]
    } else {
      rep(NA_character_, nrow(taxa_info))
    }
    wn <- if (!is.null(weight_ctx)) {
      weight_ctx$weight_note[match(taxa_info$taxon_name, weight_ctx$taxon_name)]
    } else {
      rep(NA_character_, nrow(taxa_info))
    }
    wn <- ifelse(is.na(wn), NA_character_, paste0("candidate weights: ", wn))
    sn <- if (!is.null(spatial_ctx)) {
      spatial_ctx$spatial_note[match(taxa_info$taxon_name, spatial_ctx$taxon_name)]
    } else {
      rep(NA_character_, nrow(taxa_info))
    }
    # spatial_note is kept as its own column (not just folded into
    # pipeline_note) so .build_review_prompt() can tell, per batch, whether
    # to include the GBIF/iNat interpretation caveats -- see "Spatial
    # context" in this function's own roxygen for why those caveats live in
    # fixed GUIDELINES text rather than being pre-judged per taxon here.
    taxa_info$spatial_note <- sn
    taxa_info$pipeline_note <- .combine_notes(.combine_notes(pn, wn), sn)
  }

  # has_unprecedented/has_indistinguishable: carried as their own LOGICAL
  # columns on taxa_info (not just folded into pipeline_note's text),
  # for two reasons. (1) .build_review_prompt() needs a real boolean to decide
  # whether to add the skepticism GUIDELINES bullet at all (matching
  # has_spatial_note's exact pattern) -- text alone can't be tested cheaply.
  # (2) the deterministic geographic_disagreement_basis column computed after
  # the LLM call (see the final assembly below) needs the RAW flags, not a
  # rendered sentence, and must survive independent of whatever the LLM
  # actually wrote in review_comment. Also folds into the cache key for free,
  # via the same "vapply(taxa_info, ...)" loop every other taxa_info column
  # already participates in.
  taxa_info$has_unprecedented <- if (!is.null(pipeline_ctx)) {
    pipeline_ctx$has_unprecedented[match(taxa_info$taxon_name, pipeline_ctx$taxon_name)]
  } else {
    rep(FALSE, nrow(taxa_info))
  }
  taxa_info$has_indistinguishable <- if (!is.null(pipeline_ctx)) {
    pipeline_ctx$has_indistinguishable[match(taxa_info$taxon_name, pipeline_ctx$taxon_name)]
  } else {
    rep(FALSE, nrow(taxa_info))
  }
  taxa_info$has_unprecedented[is.na(taxa_info$has_unprecedented)] <- FALSE
  taxa_info$has_indistinguishable[is.na(taxa_info$has_indistinguishable)] <- FALSE

  # --- Per-taxon prompt brackets (sites path) -------------------------------
  # Attached as columns of taxa_info, which is where the cache key is built
  # from: every column of it already enters the key, so the sites a taxon was
  # detected at and the occurrence facts shown alongside them key themselves.
  # They change the question asked, so a verdict obtained without them must
  # not be served as a hit for a call that includes them.
  occurrence_guideline <- NULL
  if (!is.null(sites)) {
    det <- .review_detected_sites(
      taxa_info$taxon_name, input_df, site_col, sites, label_canon_map
    )
    taxa_info$detected_note <- vapply(
      det, .detected_sites_bracket, character(1L), sites = sites
    )
    if (!is.null(occurrence_data)) {
      occurrence_guideline <- .occurrence_guideline_text(occurrence_data)
      taxa_info$occurrence_note <- vapply(seq_len(nrow(taxa_info)), function(i) {
        .occurrence_bracket(
          taxa_info$taxon_name[i], taxa_info$taxon_rank[i], det[[i]],
          occurrence_data, sites
        )
      }, character(1L))
      if (verbose) {
        n_none <- sum(grepl("no records of this taxon", taxa_info$occurrence_note,
          fixed = TRUE
        ))
        n_rank <- sum(grepl("rank not available", taxa_info$occurrence_note,
          fixed = TRUE
        ))
        message(sprintf(
          paste0(
            "  occurrence facts: %d of %d taxa matched the pool; %d had no ",
            "records and %d a rank the pool does not carry."
          ),
          nrow(taxa_info) - n_none - n_rank, nrow(taxa_info), n_none, n_rank
        ))
      }
    }
  }

  if (verbose) {
    message(sprintf(
      "review_assignments: %d unique %s to review.",
      nrow(taxa_info),
      if (use_candidates) "candidate sets" else "taxa"
    ))
  }

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
  # target_group, marker, data_type, whether this is the candidate-set path,
  # and WHO ANSWERED (see .review_reviewer_id()). Change any of them and the
  # entry is correctly a miss.
  #
  # The reviewer was missing from the key until the version prefix below went
  # to v2, so a verdict obtained from one model was served to a call asking
  # another. Raising the prefix orphans every entry written before the fix:
  # they are a miss once, re-asked, and re-written under a key that says who
  # answered. The message below says so when the directory already holds
  # entries.
  cache_hits <- NULL
  cache_paths <- NULL
  cache_keys <- NULL
  call_rows <- seq_len(nrow(taxa_info))
  if (!is.null(cache_dir)) {
    if (!is.character(cache_dir) || length(cache_dir) != 1L || is.na(cache_dir)) {
      stop("'cache_dir' must be a single non-NA character string, or NULL.",
        call. = FALSE
      )
    }
    if (!dir.exists(cache_dir)) {
      dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
    }

    reviewer_id <- .review_reviewer_id(llm_fn, model_label, caching = TRUE)
    if (verbose && length(list.files(cache_dir, pattern = "_review\\.rds$"))) {
      message(
        "review_assignments: the cache key now records which model answered, ",
        "so verdicts cached before this change are a miss once and will be ",
        "re-asked. Set model_label= to distinguish two models from one ",
        "provider."
      )
    }

    # Bump the version whenever the prompt text changes in a way that can
    # move a verdict: the key holds the inputs, not the prompt, so a cached
    # verdict from the old wording would otherwise be served as a hit.
    # v3: the poor-absolute-fit guideline. v4: the no-reference line is
    # keyed on the reviewed label's own row type, not the call's. v5: the
    # geography guidelines (a)/(b)/(f), ids on taxa lines. v6: the answer is a
    # probability under the guardrail definitions, so EVERY cached verdict --
    # on every path, sites or not -- is a miss once and is re-asked.
    shared_parts <- c(
      "v6", target_group %||% "", marker %||% "", data_type,
      as.character(use_candidates), reviewer_id,
      paste(names(ctx), vapply(
        ctx, function(z) paste(as.character(z), collapse = "~"),
        character(1)
      ), sep = "=", collapse = "|")
    )
    # The sites change the prompt and the parsed output, so they are part of
    # the key -- but ONLY when supplied, which leaves the sites = NULL key
    # byte-identical to a key written before this argument existed. Bump
    # "geo_sites_v5" whenever the sites wording in the prompt changes.
    # The occurrence guideline is keyed here too, because the pool's latitude
    # extent is quoted in it: a different pool asks a different question even
    # when the per-taxon facts happen to match.
    if (!is.null(sites)) {
      shared_parts <- c(shared_parts, "geo_sites_v5", .review_sites_digest(sites))
      if (!is.null(occurrence_guideline)) {
        shared_parts <- c(shared_parts, occurrence_guideline)
      }
    }
    .shared <- paste(shared_parts, collapse = "\u0001")

    cache_keys <- vapply(seq_len(nrow(taxa_info)), function(i) {
      paste(
        c(.shared, vapply(taxa_info, function(col) {
          paste(as.character(col[i]), collapse = "~")
        }, character(1))),
        collapse = "\u0001"
      )
    }, character(1))
    cache_paths <- file.path(
      cache_dir, paste0(
        vapply(cache_keys, .review_cache_hash, character(1)),
        "_review.rds"
      )
    )

    hit_rows <- integer(0)
    hit_list <- list()
    n_stale_na <- 0L
    for (i in seq_along(cache_paths)) {
      ent <- .review_cache_read(cache_paths[i], cache_keys[i])
      # A cached entry with no verdict at all is a cached NON-ANSWER -- it
      # should never be written now (see @section Unreviewed rows), but if
      # one exists in the cache directory, treat it as a MISS so the taxon is
      # asked again, rather than serving the omission forever.
      if (!is.null(ent) && .is_unreviewed_row(ent)) {
        n_stale_na <- n_stale_na + 1L
        ent <- NULL
      }
      if (!is.null(ent)) {
        hit_rows <- c(hit_rows, i)
        hit_list[[length(hit_list) + 1L]] <- ent
      }
    }
    if (n_stale_na > 0L && verbose) {
      message(sprintf(
        "  cache: %d entr%s held no verdict (unreviewed) and will be re-asked.",
        n_stale_na, if (n_stale_na == 1L) "y" else "ies"
      ))
    }
    if (length(hit_rows) > 0L) {
      cache_hits <- do.call(rbind, hit_list)
      call_rows <- setdiff(call_rows, hit_rows)
    }
    if (verbose) {
      message(sprintf(
        "  cache: %d of %d taxa already reviewed; %d to call.",
        length(hit_rows), nrow(taxa_info), length(call_rows)
      ))
    }
  }

  # Which taxa share a call is a measured source of irreproducibility: reshuffling
  # the batches, with nothing else changed, moved 7% of the decisions the verdicts
  # drive. Input order is whatever the upstream table happened to be in, so the
  # batches are built from a sort of the labels instead. Two runs that have the
  # same taxa left to ask therefore ask the same batches.
  #
  # It cannot be made fully order-free: batching happens on the taxa still to
  # ask, so a run whose cache covers a different subset will group the remainder
  # differently. What this removes is the part that moved for no reason at all.
  taxa_to_call <- taxa_info[call_rows, , drop = FALSE]
  taxa_to_call <- taxa_to_call[
    order(taxa_to_call$taxon_name, method = "radix"), ,
    drop = FALSE
  ]

  # --- Batch and call LLM ---
  n_taxa <- nrow(taxa_to_call)
  tpc <- if (n_taxa > 0L) min(taxa_per_call, n_taxa) else 1L
  batch_idx <- if (n_taxa > 0L) {
    split(seq_len(n_taxa), ceiling(seq_len(n_taxa) / tpc))
  } else {
    list()
  }
  n_batches <- length(batch_idx)

  if (verbose) {
    message(sprintf(
      "  %d LLM call(s) needed (taxa_per_call = %d).",
      n_batches, taxa_per_call
    ))
  }

  batch_results <- vector("list", n_batches)
  prompt_log <- new.env(parent = emptyenv())

  for (b in seq_along(batch_idx)) {
    taxa_batch <- taxa_to_call[batch_idx[[b]], , drop = FALSE]

    if (verbose) {
      message(sprintf(
        "  Calling LLM (batch %d/%d, %d %s)...",
        b, n_batches, nrow(taxa_batch),
        if (use_candidates) "candidate sets" else "taxa"
      ))
    }

    batch_results[[b]] <- .review_batch_with_retry(
      taxa_batch, ctx, target_group, marker, data_type, use_candidates,
      llm_fn, max_tokens, taxon_rank_col, verbose, pause_seconds,
      batch_label = as.character(b), max_retries = max_retries,
      prompt_log = prompt_log, sites = sites,
      occurrence_guideline = occurrence_guideline
    )

    if (b < n_batches) Sys.sleep(pause_seconds)
  }

  review_df <- do.call(rbind, batch_results)

  # Labels the LLM never returned a verdict for, even after re-asking. Collected
  # from the batch attributes rather than re-derived, so a label that IS present
  # but legitimately all-NA for another reason is not conflated with one that
  # was never answered.
  unreviewed_taxa <- unique(unlist(
    lapply(batch_results, function(b) attr(b, "missing_taxa")),
    use.names = FALSE
  ))
  unreviewed_taxa <- as.character(unreviewed_taxa %||% character(0))

  # Persist the freshly obtained verdicts, then fold the cached ones back in.
  # An unreviewed row is NEVER cached: caching a non-answer makes the omission
  # permanent, since every later run is then a cache HIT on a row of NAs and
  # the re-ask above never gets a chance to fire.
  if (!is.null(cache_dir) && !is.null(review_df) && nrow(review_df) > 0L) {
    pos <- match(review_df$taxon_name, taxa_info$taxon_name)
    for (k in which(!is.na(pos))) {
      if (review_df$taxon_name[k] %in% unreviewed_taxa) next
      .review_cache_write(
        cache_paths[pos[k]], cache_keys[pos[k]],
        review_df[k, , drop = FALSE]
      )
    }
  }
  if (!is.null(cache_hits)) {
    review_df <- if (is.null(review_df) || nrow(review_df) == 0L) {
      cache_hits
    } else {
      rbind(review_df, cache_hits[, names(review_df), drop = FALSE])
    }
  }
  rownames(review_df) <- NULL
  # Read every row -- freshly asked and cached alike -- through THIS run's
  # cuts. A cached row stores the probabilities the model gave, so a changed
  # cut applies to it without re-asking; deriving only in the parser would
  # have frozen each cached row at the cut in force when it was written.
  review_df <- .derive_levels(review_df)

  # The parsed range rule per reviewed taxon (sites path only).
  geo_attr <- if (!is.null(sites)) .geo_rules_table(review_df) else NULL
  if (!is.null(geo_attr) && verbose) {
    n_fb <- sum(geo_attr$rule == "fallback")
    n_unk <- sum(geo_attr$n_unknown_sites)
    if (n_fb > 0L) {
      message(sprintf(
        "  sites: %d of %d taxa gave no usable range answer; the study-wide verdict is used at every site.",
        n_fb, nrow(geo_attr)
      ))
    }
    if (n_unk > 0L) {
      message(sprintf(
        "  sites: %d sites_outside_range name(s) matched no site and were ignored.", n_unk
      ))
    }
  }

  if (verbose) {
    message(sprintf(
      "  Review complete. %d %s reviewed.",
      nrow(review_df),
      if (use_candidates) "candidate sets" else "taxa"
    ))
  }

  # --- Join back to input by .join_key ---
  # The four purely-LLM-sourced columns are named with an llm_ prefix
  # (llm_habitat_plausibility/llm_geographic_plausibility/
  # llm_scope_plausibility/llm_contamination_risk) so the SOURCE of a
  # "likely"/"unlikely" verdict is legible from the column name alone, not
  # just documentation. An unprefixed name would read as pipeline-derived: a
  # real case had a user trace a surprising "geographic_plausibility =
  # likely" (despite a near-zero pipeline occurrence prior) all the way to
  # this function before realising it was an independent LLM judgment, not a
  # pipeline-derived value. The LLM's own JSON schema keys (habitat_plausibility,
  # etc., in .build_review_prompt()/.parse_review_response()) use the bare
  # names internally -- only the final output column names carry the prefix.
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
    as.character(unlist(keys, use.names = FALSE)) # NULL -> character(0), keeps the column
  }

  merge_key <- data.frame(
    .join_key = join_keys,
    llm_habitat_plausibility = review_df$habitat_plausibility,
    llm_geographic_plausibility = review_df$geographic_plausibility,
    llm_scope_plausibility = review_df$scope_plausibility,
    llm_contamination_risk = review_df$contamination_risk,
    review_alternatives = review_df$review_alternatives,
    review_lower_hypotheses = review_df$review_lower_hypotheses,
    review_confidence = review_df$review_confidence,
    review_comment = review_df$review_comment,
    llm_p_habitat = review_df$p_habitat,
    llm_p_habitat_lo = review_df$p_habitat_lo,
    llm_p_habitat_hi = review_df$p_habitat_hi,
    llm_p_transported = review_df$p_transported,
    llm_p_scope = review_df$p_scope,
    llm_p_scope_lo = review_df$p_scope_lo,
    llm_p_scope_hi = review_df$p_scope_hi,
    llm_p_contamination = review_df$p_contamination,
    llm_p_geographic = review_df$p_geographic,
    .has_unprecedented = review_df$has_unprecedented,
    .has_indistinguishable = review_df$has_indistinguishable,
    stringsAsFactors = FALSE
  )
  if (!is.null(sites)) {
    merge_key$llm_p_inside_range <- review_df$p_inside_range
    merge_key$llm_p_outside_range <- review_df$p_outside_range
    merge_key$llm_range_known <- review_df$range_known
    merge_key$llm_range_south_lat <- review_df$range_south_lat
    merge_key$llm_range_north_lat <- review_df$range_north_lat
    merge_key$.geo_json <- review_df$review_geo_json
  }

  input_df$.row_id <- seq_len(nrow(input_df))
  result <- merge(input_df, merge_key, by = ".join_key", all.x = TRUE, sort = FALSE)
  result <- result[order(result$.row_id), , drop = FALSE]
  result$.row_id <- NULL
  result$.join_key <- NULL
  rownames(result) <- NULL

  # --- Per-site verdicts (sites path only) -----------------------------------
  if (!is.null(sites)) {
    result <- .apply_site_verdicts(result, sites, site_col)
  }

  # --- Deterministic disagreement flag --------------------------------------
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
  hu <- result$.has_unprecedented
  hu[is.na(hu)] <- FALSE
  hi <- result$.has_indistinguishable
  hi[is.na(hi)] <- FALSE
  llm_geo <- result$llm_geographic_plausibility
  disagrees <- !is.na(llm_geo) & llm_geo %in% c("likely", "possible")

  basis <- rep(NA_character_, nrow(result))
  basis[disagrees & hu & hi] <- "unprecedented+indistinguishable"
  basis[disagrees & hu & !hi] <- "unprecedented"
  basis[disagrees & !hu & hi] <- "indistinguishable"
  result$geographic_disagreement_basis <- basis
  result$.has_unprecedented <- NULL
  result$.has_indistinguishable <- NULL
  if (!is.null(sites)) {
    result$.geo_json <- NULL
    attr(result, "geographic_by_site") <- geo_attr
  }

  # Named by batch label (including any "a"/"b" retry sub-batch splits) --
  # see @return below.
  attr(result, "llm_prompts") <- as.list(prompt_log)

  # --- Unreviewed residue ----------------------------------------------------
  # A row the model never answered about carries NA in all four llm_ columns,
  # and every production workflow's export chain filters with != "unlikely",
  # which DISCARDS NA -- so the observation leaves the final species list
  # without a word. The count is returned as an attribute (always present, possibly empty),
  # modelled on fetch_ncbi_reference_sequences()'s count_failures, so a
  # workflow can check it programmatically instead of hand-writing a
  # diagnostic. NOTE: attributes do not survive a dplyr verb -- check this
  # immediately after the call, before any join/mutate.
  n_unreviewed_rows <- sum(is.na(result$llm_habitat_plausibility) &
    is.na(result$llm_geographic_plausibility) &
    is.na(result$llm_contamination_risk) &
    is.na(result$review_confidence))
  attr(result, "unreviewed_taxa") <- unreviewed_taxa
  attr(result, "n_unreviewed_rows") <- n_unreviewed_rows

  if (length(unreviewed_taxa) > 0L && !identical(on_unreviewed, "ignore")) {
    what_happened <- sprintf(paste0(
      "%d %s have NO LLM verdict, after re-asking (max_retries = %d):\n  %s\n",
      "%d input row(s) carry NA in every llm_ column as a result."
    ),
    length(unreviewed_taxa),
    if (use_candidates) "candidate set(s)" else "taxon/taxa",
    max_retries,
    paste(utils::head(unreviewed_taxa, 10L), collapse = "\n  "),
    n_unreviewed_rows
    )
    if (length(unreviewed_taxa) > 10L) {
      what_happened <- paste0(
        what_happened,
        sprintf("\n  ... and %d more", length(unreviewed_taxa) - 10L)
      )
    }
    what_to_do <- paste0(
      "\nThese rows are DROPPED by the usual export filters, which test\n",
      "  llm_* != \"unlikely\" and so discard NA. Re-running normally recovers\n",
      "  them (an unreviewed taxon is never cached). To continue anyway and\n",
      "  accept the loss, set on_unreviewed = \"warn\"; the affected taxa are\n",
      "  then named here and in attr(result, \"unreviewed_taxa\")."
    )
    if (identical(on_unreviewed, "error")) {
      stop(paste0(what_happened, what_to_do), call. = FALSE)
    }
    warning(paste0(what_happened, what_to_do), call. = FALSE)
    message("\n!! ", what_happened, "\n")
  }

  result
}


#' Is This Review Row an Unreviewed Non-Answer?
#'
#' TRUE when every field the LLM is asked to fill is \code{NA} -- the shape
#' \code{.parse_review_response()}'s \code{make_default()} produces for a
#' taxon the model omitted. Deliberately ignores \code{scope_plausibility}
#' (legitimately \code{NA} for every taxon when \code{target_group} is not
#' supplied) and \code{review_lower_hypotheses} (legitimately \code{NA} on
#' the whole candidate-set path), so a real verdict is never mistaken for a
#' non-answer.
#' @noRd
.is_unreviewed_row <- function(ent) {
  cols <- c(
    "habitat_plausibility", "geographic_plausibility",
    "contamination_risk", "review_confidence",
    "review_alternatives", "review_comment"
  )
  cols <- cols[cols %in% names(ent)]
  if (length(cols) == 0L) {
    return(FALSE)
  }
  all(vapply(cols, function(cl) all(is.na(ent[[cl]])), logical(1L)))
}


# ==============================================================================
# Internal helpers
# ==============================================================================

#' Build slash-style candidate label
#'
#' Constructs a compact slash-species string from a sorted, deduplicated
#' character vector of binomial names (length >= 2). Same-genus candidates
#' are abbreviated; mixed-genus groups are joined with " + ".
#' Mirrors TaxaAssign::.make_slash_name() -- duplicated here to avoid a
#' dependency on TaxaAssign internals.
#'
#' @noRd
.build_candidate_label <- function(taxa_vec) {
  first_space <- regexpr(" ", taxa_vec, fixed = TRUE)
  has_space <- first_space > 0L
  genera <- ifelse(has_space, substr(taxa_vec, 1L, first_space - 1L), taxa_vec)
  epithets <- ifelse(has_space,
    substr(taxa_vec, first_space + 1L, nchar(taxa_vec)),
    taxa_vec
  )
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
#' on a real case where a user traced exactly this masking after
#' noticing the LLM's own \code{review_comment} quoted "0.00" back verbatim.
#' Below 0.01, switches to 2-significant-figure scientific notation (e.g.
#' "6.50e-06") so the LLM sees the real order of magnitude; \code{0} itself
#' prints as the literal "0" (scientific notation for an exact zero reads
#' oddly, e.g. "0.00e+00").
#' @noRd
.fmt_pipeline_value <- function(v) {
  if (is.na(v)) {
    return(NA_character_)
  }
  if (v == 0) {
    return("0")
  }
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
#' surface \code{TaxaFlag::add_posthoc_assessment()}'s own Axis 1
#' ("unprecedented" = no local occurrence record at all) and Axis 2
#' ("indistinguishable" = a confusable relative could score just as well)
#' verdicts as plain-text prompt context, AND as two logical columns
#' (\code{has_unprecedented}/\code{has_indistinguishable}) the caller uses
#' post-hoc to compute a deterministic disagreement flag against whatever the
#' LLM actually returned -- unlike the text note, these can't be faithfully
#' recovered from \code{review_comment} alone (an LLM is not guaranteed to
#' mention them, which is exactly the real case that prompted this: an LLM
#' rated a taxon "likely" despite the pipeline recording zero local records
#' for it, and an LLM cannot be trusted to reliably self-flag its own
#' disagreement). \code{isTRUE(any(...))} per group, matching
#' \code{winner_rank_expanded}'s own existing any-row-flags-it convention just
#' below -- if ANY observation sharing this label was found unprecedented/
#' indistinguishable, the whole reviewed group is treated as warranting
#' skepticism (a caution signal should over-include, not under-include).
#' @noRd
.summarise_pipeline_context <- function(label_vec, input_df, consensus_posterior_col,
                                        winner_prior_col, winner_rank_expanded_col,
                                        consensus_plausibility_col = NULL,
                                        consensus_discrimination_col = NULL,
                                        consensus_provenance = TRUE,
                                        poor_absolute_fit_col = NULL,
                                        best_identity_col = NULL) {
  has_post <- !is.null(consensus_posterior_col) && consensus_posterior_col %in% names(input_df)
  has_prior <- !is.null(winner_prior_col) && winner_prior_col %in% names(input_df)
  has_rexp <- !is.null(winner_rank_expanded_col) && winner_rank_expanded_col %in% names(input_df)
  has_plaus <- !is.null(consensus_plausibility_col) && consensus_plausibility_col %in% names(input_df)
  has_disc <- !is.null(consensus_discrimination_col) && consensus_discrimination_col %in% names(input_df)
  has_poorfit <- !is.null(poor_absolute_fit_col) && poor_absolute_fit_col %in% names(input_df)
  has_ident <- !is.null(best_identity_col) && best_identity_col %in% names(input_df)
  # The four provenance columns are emitted together by
  # posterior_consensus(), so they are read by their canonical names rather
  # than through four separate `_col` arguments.
  has_prov <- isTRUE(consensus_provenance) &&
    "consensus_hypothesis_type" %in% names(input_df)
  has_scope <- has_prov &&
    all(c("consensus_unreferenced_scope", "consensus_unreferenced_scope_rank") %in%
      names(input_df))
  has_call <- all(c("consensus_taxon", "consensus_rank") %in% names(input_df))
  if (!has_post && !has_prior && !has_rexp && !has_plaus && !has_disc && !has_prov &&
    !has_poorfit && !has_call) {
    return(NULL)
  }

  keep <- !is.na(label_vec)
  if (!any(keep)) {
    return(NULL)
  }

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
    # Absolute fit: the likelihood is normalised to the unit maximum, so the
    # best of a poor set reads as a confident call. Only a TRUE flag adds a
    # line; FALSE and NA add nothing. Any row sharing the label flagging it
    # counts, as for winner_rank_expanded.
    if (has_poorfit) {
      pf <- input_df[[poor_absolute_fit_col]][rows]
      if (isTRUE(any(pf, na.rm = TRUE))) {
        idv <- if (has_ident) {
          suppressWarnings(stats::median(
            as.numeric(input_df[[best_identity_col]][rows][pf %in% TRUE]),
            na.rm = TRUE
          ))
        } else {
          NA_real_
        }
        parts <- c(parts, if (is.finite(idv)) {
          sprintf(
            "best match identity %.1f%% is below every rank threshold for this marker (poor absolute fit)",
            idv
          )
        } else {
          "best match identity is below every rank threshold for this marker (poor absolute fit)"
        })
      }
    }
    # "No reference sequence" is a claim about the NAMED taxon the reviewer
    # sees -- the label -- not about the row the call landed on. The two
    # differ: a unit called at a family ring can carry a referenced species as
    # its label (the first plausible taxon), and units sharing one label are
    # reviewed together. Keying the line on consensus_hypothesis_type alone
    # told the reviewer a referenced species had no reference (Mugu: Carassius
    # auratus, 76 12S references, rated geographically "unlikely" on it).
    #
    # So the label's own row type is read where it is known: from
    # consensus_hypothesis_type when the label IS consensus_taxon, from
    # winner_hypothesis_type when the label is the first plausible taxon (the
    # winner row). Only a NAMED unreferenced species qualifies: a generic ring
    # ("Salmo", "Cottus") carries a clade's name, and the clade may well have
    # references that the read simply did not match. A label shown as
    # referenced in any unit of the group gets no line; a label whose type
    # cannot be read gets none either.
    if (has_prov) {
      lab <- label_vec[rows]
      ct <- if ("consensus_taxon" %in% names(input_df)) as.character(input_df[["consensus_taxon"]][rows]) else rep(NA_character_, length(rows))
      cht <- as.character(input_df[["consensus_hypothesis_type"]][rows])
      wht <- if ("winner_hypothesis_type" %in% names(input_df)) as.character(input_df[["winner_hypothesis_type"]][rows]) else rep(NA_character_, length(rows))
      first_pl <- if ("plausible_taxa" %in% names(input_df) && is.list(input_df[["plausible_taxa"]])) {
        vapply(input_df[["plausible_taxa"]][rows], function(v) if (length(v)) as.character(v[[1L]]) else NA_character_, character(1))
      } else {
        rep(NA_character_, length(rows))
      }
      sc_all <- if (has_scope) as.character(input_df[["consensus_unreferenced_scope"]][rows]) else rep(NA_character_, length(rows))
      # Without a consensus_taxon column the label is taken to be the call.
      is_call <- if ("consensus_taxon" %in% names(input_df)) !is.na(ct) & lab == ct else rep(TRUE, length(rows))
      is_first <- !is_call & !is.na(first_pl) & lab == first_pl
      lab_type <- ifelse(is_call, cht, ifelse(is_first, wht, NA_character_))
      binomial <- grepl(" ", lab, fixed = TRUE)
      named_unref <- !is.na(lab_type) & lab_type == "unreferenced_species" & binomial &
        (!is_call | is.na(sc_all) | sc_all != lab)
      shown_referenced <- !is.na(lab_type) & !startsWith(lab_type, "unreferenced_")
      if (any(named_unref) && !any(shown_referenced)) {
        msg <- "named taxon has NO reference sequence"
        k <- which(named_unref & is_call & !is.na(sc_all))[1L]
        if (has_scope && !is.na(k)) {
          scr <- as.character(input_df[["consensus_unreferenced_scope_rank"]][rows])
          nn <- if ("consensus_scope_n_named" %in% names(input_df)) {
            suppressWarnings(max(
              input_df[["consensus_scope_n_named"]][rows][named_unref & is_call], na.rm = TRUE
            ))
          } else {
            NA_real_
          }
          how <- if (!is.finite(nn) || is.na(nn)) {
            ""
          } else if (nn <= 1) {
            "; the only such species recorded in that scope"
          } else {
            sprintf("; chosen by occurrence records among %d recorded there", as.integer(nn))
          }
          msg <- sprintf(
            "%s -- name supplied by the occurrence records for %s (%s)%s",
            msg, sc_all[k], scr[k], how
          )
        }
        parts <- c(parts, msg)
      }
    }
    # (f) When the label is not the call itself (a species label on a genus
    # or family call), say what the call is, so it is judged at its own rank.
    if (all(c("consensus_taxon", "consensus_rank") %in% names(input_df))) {
      ct_r <- as.character(input_df[["consensus_taxon"]][rows])
      cr_r <- as.character(input_df[["consensus_rank"]][rows])
      lab_r <- label_vec[rows]
      off <- !is.na(ct_r) & !is.na(lab_r) & ct_r != lab_r
      if (any(off)) {
        calls <- unique(sprintf("%s (%s)", ct_r[off], ifelse(is.na(cr_r[off]), "rank unknown", cr_r[off])))
        more <- if (length(calls) > 3L) sprintf(" and %d more", length(calls) - 3L) else ""
        parts <- c(parts, sprintf("pipeline call: %s%s", paste(utils::head(calls, 3L), collapse = "; "), more))
      }
    }
    is_unprec <- has_plaus && isTRUE(any(input_df[[consensus_plausibility_col]][rows] == "unprecedented", na.rm = TRUE))
    is_indist <- has_disc && isTRUE(any(input_df[[consensus_discrimination_col]][rows] == "indistinguishable", na.rm = TRUE))
    if (is_unprec) parts <- c(parts, "pipeline flags UNPRECEDENTED: no local occurrence record at all")
    if (is_indist) parts <- c(parts, "pipeline flags INDISTINGUISHABLE: a confusable relative could score equally well")
    rows_list[[gi]] <<- c(unprecedented = is_unprec, indistinguishable = is_indist)
    if (length(parts) == 0L) NA_character_ else paste(parts, collapse = "; ")
  }, character(1L))

  flags <- do.call(rbind, rows_list)
  data.frame(
    taxon_name = names(groups), pipeline_note = unname(notes),
    has_unprecedented = unname(flags[, "unprecedented"]),
    has_indistinguishable = unname(flags[, "indistinguishable"]),
    stringsAsFactors = FALSE
  )
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
  if (!any(is_multi)) {
    return(NULL)
  }

  groups <- split(which(is_multi), label_vec[is_multi])

  notes <- vapply(groups, function(rows) {
    vecs <- post_list[rows]
    vecs <- vecs[lengths(vecs) > 0L]
    if (length(vecs) == 0L) {
      return(NA_character_)
    }
    all_vals <- unlist(vecs, use.names = TRUE)
    agg <- sort(tapply(all_vals, names(all_vals), mean, na.rm = TRUE), decreasing = TRUE)
    paste(sprintf("%s %.0f%%", names(agg), agg * 100), collapse = ", ")
  }, character(1L))

  data.frame(
    taxon_name = names(groups), weight_note = unname(notes),
    stringsAsFactors = FALSE
  )
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
  has_dist <- !is.null(dist_nearest_occupied_km_col) && dist_nearest_occupied_km_col %in% names(input_df)
  has_patch <- !is.null(patch_diameter_km_col) && patch_diameter_km_col %in% names(input_df)
  has_beyond <- !is.null(beyond_buffer_col) && beyond_buffer_col %in% names(input_df)
  has_inrange <- !is.null(inat_in_range_col) && inat_in_range_col %in% names(input_df)
  has_nobs <- !is.null(inat_n_observations_col) && inat_n_observations_col %in% names(input_df)
  has_match <- !is.null(inat_matched_name_col) && inat_matched_name_col %in% names(input_df)
  if (!has_dist && !has_beyond && !has_inrange && !has_nobs && !has_match) {
    return(NULL)
  }

  keep <- !is.na(label_vec)
  if (!any(keep)) {
    return(NULL)
  }

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
      } else {
        NA
      }
      nobs <- if (has_nobs) {
        suppressWarnings(stats::median(input_df[[inat_n_observations_col]][rows], na.rm = TRUE))
      } else {
        NA_real_
      }
      matched <- if (has_match) {
        m <- input_df[[inat_matched_name_col]][rows]
        m <- m[!is.na(m)]
        if (length(m) > 0L) m[[1L]] else NA_character_
      } else {
        NA_character_
      }

      if (!is.na(in_range) || is.finite(nobs) || !is.na(matched)) {
        inat_parts <- character(0)
        if (!is.na(matched) && !is.na(lbl) &&
          tolower(trimws(matched)) != tolower(trimws(lbl))) {
          inat_parts <- c(inat_parts, sprintf("matched to '%s' (name differs from query)", matched))
        }
        if (!is.na(in_range)) inat_parts <- c(inat_parts, if (in_range) "in range" else "outside range")
        if (is.finite(nobs)) inat_parts <- c(inat_parts, sprintf("%.0f obs", nobs))
        if (length(inat_parts) > 0L) {
          parts <- c(parts, paste0("iNat: ", paste(inat_parts, collapse = ", ")))
        }
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
      ifelse(is.na(b), a, paste0(a, "; ", b))
    )
  )
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
    if (nrow(context) > 1L) {
      warning(sprintf(
        "review_assignments: 'context' has %d rows; only the first is used (context describes one study, not one row per observation).",
        nrow(context)
      ), call. = FALSE)
    }
    ctx <- as.list(context[1, , drop = TRUE])
  } else if (is.list(context)) {
    ctx <- context
  } else {
    stop("'context' must be a named list or data frame.", call. = FALSE)
  }

  # geography from a build_context() output: COMBINE the analyst's own wording
  # with the synthesised ecoregion, do not choose between them.
  # build_context() keeps geographic_hint verbatim precisely so the analyst's
  # phrasing survives ("otherwise only the synthesised ecoregion reaches that
  # prompt"), but ecoregion is ONE string synthesised for the whole taxon list.
  # For a study spanning more than one ecoregion that single string is narrower
  # than the study, and reading it alone would hand the LLM a geography the
  # analyst never wrote. An explicit ctx$geography is always left untouched, so
  # a hand-written context produces a byte-identical prompt.
  if (is.null(ctx$geography)) {
    .chr1 <- function(x) {
      if (is.null(x)) return(NULL)
      x <- as.character(x)[1L]
      if (is.na(x) || !nzchar(trimws(x))) NULL else trimws(x)
    }
    .hint <- .chr1(ctx$geographic_hint)
    .eco <- .chr1(ctx$ecoregion)
    if (!is.null(.hint) && !is.null(.eco) && !identical(.hint, .eco)) {
      ctx$geography <- paste0(.hint, " (", .eco, ")")
    } else if (!is.null(.hint)) {
      ctx$geography <- .hint
    } else if (!is.null(.eco)) {
      ctx$geography <- .eco
    }
  }
  if (is.null(ctx$habitat) && !is.null(ctx$main_habitat)) {
    ctx$habitat <- ctx$main_habitat
  }

  if (is.null(ctx$geography) || is.na(ctx$geography)) {
    warning("'context$geography' is missing. LLM review will lack geographic context.",
      call. = FALSE
    )
  }
  if (is.null(ctx$habitat) || is.na(ctx$habitat)) {
    warning("'context$habitat' is missing. LLM review will lack habitat context.",
      call. = FALSE
    )
  }

  ctx
}


#' Build Review Prompt for LLM
#' @noRd
.build_review_prompt <- function(taxa_batch, ctx, target_group, marker,
                                 data_type, use_candidates = FALSE,
                                 sites = NULL, occurrence_guideline = NULL) {
  # --- Context block ---
  context_lines <- character(0)
  if (!is.null(ctx$geography) && !is.na(ctx$geography)) {
    context_lines <- c(context_lines, sprintf("GEOGRAPHY: %s", ctx$geography))
  }
  if (!is.null(ctx$habitat) && !is.na(ctx$habitat)) {
    context_lines <- c(context_lines, sprintf("HABITAT: %s", ctx$habitat))
  }
  if (!is.null(ctx$date) && !is.na(ctx$date)) {
    context_lines <- c(context_lines, sprintf("DATE: %s", ctx$date))
  }
  if (!is.null(target_group)) {
    context_lines <- c(context_lines, sprintf("TARGET GROUP: %s", target_group))
  }
  if (!is.null(marker)) {
    context_lines <- c(context_lines, sprintf("MARKER / METHOD: %s", marker))
  }

  context_block <- paste(context_lines, collapse = "\n")

  # --- Study sites (sites path only) ---
  sites_block <- if (!is.null(sites)) .sites_prompt_block(sites) else NULL

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
    # The run's own facts, in the order the guidelines introduce them: where
    # this taxon was actually detected, then what the occurrence pool holds
    # about it near those sites.
    for (fact in c("detected_note", "occurrence_note")) {
      v <- if (fact %in% names(taxa_batch)) taxa_batch[[fact]][i] else NA_character_
      if (!is.na(v)) base <- paste0(base, " ", v)
    }
    # The id is how the answer is matched back (see .parse_review_response()):
    # a long candidate-set label echoed back reformatted cannot be matched by
    # name, and one such label could unmatch a whole batch.
    sub("^- ", sprintf("- [T%d] ", i), base)
  }, character(1))

  taxa_block <- paste(taxa_lines, collapse = "\n")

  # --- Scope instructions ---
  scope_instruction <- .p_scope_field_text(target_group)

  # Which field the geography guidelines below should name. With a site table
  # the model states range limits and a probability inside/outside them; with
  # no sites it gives the study-wide probability directly.
  geo_p_name <- if (!is.null(sites)) "p_inside_range" else "p_geographic"

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
    eDNA = paste0(
      "For contaminant assessment, consider: Homo sapiens and domestic animals are common ",
      "contaminants in molecular studies. Common lab contaminants include Bos taurus, ",
      "Sus scrofa, Gallus gallus, and other food-source species."
    ),
    acoustic = paste0(
      "For contaminant assessment, consider: human vocalizations and handler noise near ",
      "recording equipment are common false positives. Domestic animals (dogs, livestock) ",
      "and vehicles can produce false species matches."
    ),
    image = paste0(
      "For contaminant assessment, consider: handler presence during camera setup/teardown ",
      "events and domestic animals are common false positives in camera trap data."
    ),
    paste0(
      "For contaminant assessment, consider taxon-specific false positive sources ",
      "appropriate for the detection method used."
    )
  )

  # --- Geography guidance (each bullet only when a taxon in this batch
  # carries the matching bracket fact; see @section Geography guidelines) ---
  # (b) UNPRECEDENTED: no local record in the pipeline's occurrence data.
  # Absence of a citeable record is not evidence of absence, so the flag caps
  # the rating at "possible" and never inverts it: "unlikely" needs POSITIVE
  # evidence of being out of range. An earlier hard rule ("cite a specific
  # local record or rate it unlikely") rated widely introduced species out of
  # range whenever the model could not recall a record on that draw (Mugu:
  # common carp flipped possible -> unlikely on a byte-identical prompt).
  has_unprec_note <- "has_unprecedented" %in% names(taxa_batch) &&
    any(taxa_batch$has_unprecedented, na.rm = TRUE)
  unprecedented_guideline <- if (has_unprec_note) {
    paste0(
      '- For a taxon whose bracket says "pipeline flags UNPRECEDENTED" (no ',
      "local occurrence record in the pipeline's occurrence data): absence of ",
      "a citeable record is NOT evidence of absence. Without specific evidence ",
      "of a population at or near this site, give an intermediate geographic ",
      "probability (", geo_p_name, " about 0.3-0.6), not a high one, and say ",
      "in review_comment that the evidence is thin. Give a low probability ",
      "(under 0.1) only with POSITIVE evidence that it is out of range here ",
      "-- for example a native range on another continent with no known ",
      "introduction to this region, or a habitat it cannot use. A widely ",
      "introduced species, or one known from the region, is at least ",
      "intermediate.\n"
    )
  } else {
    NULL
  }
  # (a) INDISTINGUISHABLE is a sequence fact (a relative could score as well):
  # it bears on the NAME, never on range or habitat.
  has_indist_note <- "has_indistinguishable" %in% names(taxa_batch) &&
    any(taxa_batch$has_indistinguishable, na.rm = TRUE)
  indistinguishable_guideline <- if (has_indist_note) {
    paste0(
      '- "pipeline flags INDISTINGUISHABLE" means a confusable relative could ',
      "match the sequence equally well. It weakens confidence in the NAME, not ",
      "the ecology: it must not by itself lower your habitat, geography or ",
      "scope probabilities.\n"
    )
  } else {
    NULL
  }
  # (f) The claim is the CALL, at its rank. A reviewer shown a species label
  # for a family call judged the species (Mugu: Gobiidae dropped because the
  # bay goby could not be placed, while the comment called Gobiidae "almost
  # certainly present").
  has_call_note <- "pipeline_note" %in% names(taxa_batch) &&
    any(grepl("pipeline call: ", taxa_batch$pipeline_note, fixed = TRUE))
  call_rank_guideline <- if (has_call_note) {
    paste0(
      '- When a bracket gives "pipeline call: <taxon> (<rank>)", that taxon at that ',
      "rank is the claim: rate habitat and geography for it. The species names shown ",
      "are candidates within it, not the claim, so a candidate you cannot place ",
      "locally does not lower a genus or family call's probabilities.\n"
    )
  } else {
    NULL
  }

  # --- Spatial-context guidance (only when this batch actually has a note) ---
  has_spatial_note <- "spatial_note" %in% names(taxa_batch) &&
    any(!is.na(taxa_batch$spatial_note))
  spatial_guideline <- if (has_spatial_note) {
    paste0(
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
      "inform your geographic probability, and note any inconsistency you ",
      "notice in review_comment.\n"
    )
  } else {
    NULL
  }

  # --- Absolute-fit guidance (only when a taxon line carries the note) ---
  # The fact line says the best reference match is weak. That is evidence
  # about the NAME, not the ecology: one real review rated three Gobiidae
  # family rows geographically "unlikely" citing an 89.6% match alone.
  has_poorfit_note <- "pipeline_note" %in% names(taxa_batch) &&
    any(grepl("(poor absolute fit)", taxa_batch$pipeline_note, fixed = TRUE))
  poorfit_guideline <- if (has_poorfit_note) {
    paste0(
      '- A "(poor absolute fit)" note means the best reference match is weak, ',
      "so the NAME at the called rank is uncertain. It says nothing about ",
      "whether that group is ecologically or geographically plausible here: ",
      "it must not by itself lower your habitat, geography or scope ",
      "probabilities.\n"
    )
  } else {
    NULL
  }

  example_comment <- switch(data_type,
    eDNA     = "Common lab contaminant in eDNA studies",
    acoustic = "Human vocalization detected near recording equipment",
    image    = "Handler detected during camera setup event",
    "Common false positive for this detection method"
  )

  # --- Assemble prompt ---
  header_sections <- c(
    "You are an expert wildlife biologist, biogeographer, and taxonomist.\n",
    "STUDY CONTEXT:\n", context_block, "\n"
  )
  if (!is.null(sites_block)) {
    header_sections <- c(header_sections, "\n", sites_block)
  }
  if (!is.null(notation_block)) {
    header_sections <- c(header_sections, "\n", notation_block, "\n")
  }

  prompt <- paste0(
    paste(header_sections, collapse = ""), "\n",
    "TASK: Review each taxon below and assess whether it is a plausible detection ",
    "given the study context. Return your assessment as a valid JSON array with one ",
    "object per taxon. Return ONLY the JSON array -- no markdown fences, no explanation ",
    "before or after.\n\n",
    "Each object must have these fields. Every probability is a number from 0 ",
    "to 1 with two decimals:\n",
    '  "id": the bracketed id given before the taxon, e.g. "T1",\n',
    '  "taxon_name": the exact taxon name as provided,\n',
    .p_habitat_field_text(ctx$habitat), "\n",
    '  "p_habitat_range": [low, high], your 90% range,\n',
    .p_transported_field_text, "\n",
    scope_instruction, "\n",
    '  "p_scope_range": [low, high],\n',
    if (!is.null(sites)) .p_range_field_text else .p_study_geo_field_text,
    .p_contamination_field_text, "\n",
    '  "review_alternatives": comma-separated string of plausible alternative ',
    "taxa that better fit the geography and habitat, or null,\n",
    lower_instruction, "\n",
    '  "review_confidence": one of "high", "moderate", "low",\n',
    '  "review_comment": a brief free-text note, or null\n\n',
    "GUIDELINES:\n",
    .p_guideline_text,
    '- "review_alternatives" means "you might have the wrong taxon" -- suggest ',
    "relatives that better fit the context.\n",
    "- ", contaminant_guideline, "\n",
    "- Give a low probability only when reasonably confident. If uncertain, ",
    "give an intermediate probability with a wide 90% range rather than making ",
    "a strong claim.\n",
    if (!is.null(sites)) .p_range_guideline_text else .p_study_geo_guideline_text,
    if (!is.null(unprecedented_guideline)) unprecedented_guideline else "",
    if (!is.null(indistinguishable_guideline)) indistinguishable_guideline else "",
    if (!is.null(call_rank_guideline)) call_rank_guideline else "",
    if (!is.null(spatial_guideline)) spatial_guideline else "",
    if (!is.null(poorfit_guideline)) poorfit_guideline else "",
    '- When a taxon line ends with a "[...]" bracket, that is the statistical ',
    "pipeline's OWN confidence for this call (posterior/occurrence prior/candidate ",
    "weights), not your input. Use it to flag disagreement between the pipeline's ",
    "confidence and your own ecological judgment in review_comment -- e.g. a low ",
    "pipeline posterior alongside your own high probabilities is worth a note -- ",
    "but do not let it override your independent assessment itself.\n",
    if (!is.null(sites)) .p_detected_guideline_text else "",
    occurrence_guideline %||% "",
    "\n",
    .p_worked_examples_text,
    "EXAMPLE OUTPUT FORMAT:\n",
    .p_example_output(sites, use_candidates, example_comment),
    "TAXA TO REVIEW:\n",
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
                                     depth = 0L, prompt_log = NULL,
                                     sites = NULL, occurrence_guideline = NULL) {
  prompt <- .build_review_prompt(
    taxa_batch, ctx, target_group, marker,
    data_type, use_candidates,
    sites = sites, occurrence_guideline = occurrence_guideline
  )

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
    warning(sprintf(
      "LLM call failed for batch %s: %s. Using NA defaults.",
      batch_label, call_error
    ), call. = FALSE)
    result <- .parse_review_response(
      NULL, taxa_batch, target_group,
      taxon_rank_col, use_candidates,
      site_names = sites$site
    )
    attr(result, "status") <- NULL
    attr(result, "pending_warnings") <- NULL
    return(result)
  }

  parsed <- .parse_review_response(
    raw, taxa_batch, target_group,
    taxon_rank_col, use_candidates,
    site_names = sites$site
  )
  status <- attr(parsed, "status")
  pending <- attr(parsed, "pending_warnings")

  can_retry <- status %in% c("truncated", "failed") &&
    depth < max_retries && nrow(taxa_batch) > 1L

  if (can_retry) {
    if (verbose) {
      message(sprintf(
        "  Batch %s %s (%d taxa) -- retrying as smaller sub-batches...",
        batch_label,
        if (status == "failed") "returned no usable content" else "was truncated",
        nrow(taxa_batch)
      ))
    }
    mid <- ceiling(nrow(taxa_batch) / 2)
    left <- taxa_batch[seq_len(mid), , drop = FALSE]
    right <- taxa_batch[(mid + 1L):nrow(taxa_batch), , drop = FALSE]

    left_result <- .review_batch_with_retry(
      left, ctx, target_group, marker, data_type, use_candidates, llm_fn,
      max_tokens, taxon_rank_col, verbose, pause_seconds,
      paste0(batch_label, "a"), max_retries, depth + 1L, prompt_log,
      sites = sites, occurrence_guideline = occurrence_guideline
    )
    Sys.sleep(pause_seconds)
    right_result <- .review_batch_with_retry(
      right, ctx, target_group, marker, data_type, use_candidates, llm_fn,
      max_tokens, taxon_rank_col, verbose, pause_seconds,
      paste0(batch_label, "b"), max_retries, depth + 1L, prompt_log,
      sites = sites, occurrence_guideline = occurrence_guideline
    )
    # Each half has already re-asked for its own omissions at its leaf, so
    # the residue attributes just need unioning -- rbind() would drop them.
    return(.rbind_reviews(left_result, right_result))
  }

  for (w in pending) warning(w, call. = FALSE)

  # --- Re-ask for taxa the model simply omitted -----------------------------
  # A batch can come back well-formed, the right length, and parse cleanly
  # while still leaving out specific taxa -- consistently the long compound
  # slash labels, i.e. the hardest rows, not random ones. That is NOT
  # truncation, so `status` is "complete" and the halving retry above never
  # fires for it; without this re-ask, those taxa would be filled NA and the
  # workflows' `!= "unlikely"` export filters (which discard NA) would remove
  # those observations from the final species list without a word.
  #
  # Cost is bounded and pay-per-failure: this fires only when the model
  # omits, asks for the omitted taxa ONLY, and shares the `max_retries`
  # budget with the halving retry (so max_retries = 0 still means exactly one
  # call per batch).
  missing <- attr(parsed, "missing_taxa")
  attempt <- 0L
  # R3: a re-ask that recovers nothing resends the same sets, so it would fail
  # the same way again. Then the remaining budget asks ONE set per call, where
  # a lone answer is accepted whatever name it carries.
  singletons <- FALSE
  hard_stop <- FALSE
  while (length(missing) > 0L && attempt < max_retries && !hard_stop) {
    attempt <- attempt + 1L
    groups <- if (singletons) as.list(missing) else list(missing)

    if (verbose) {
      message(sprintf(
        "  Batch %s: LLM omitted %d %s -- re-asking (attempt %d/%d%s)...",
        batch_label, length(missing),
        if (use_candidates) "candidate set(s)" else "taxon/taxa",
        attempt, max_retries, if (singletons) ", one set per call" else ""
      ))
    }

    recovered_all <- character(0)
    for (g in seq_along(groups)) {
      sub_batch <- taxa_batch[taxa_batch$taxon_name %in% groups[[g]], , drop = FALSE]
      if (nrow(sub_batch) == 0L) next

      Sys.sleep(pause_seconds)
      reask_label <- paste0(batch_label, "r", attempt, if (singletons) paste0("s", g) else "")
      reask_prompt <- .build_review_prompt(
        sub_batch, ctx, target_group, marker, data_type, use_candidates,
        sites = sites, occurrence_guideline = occurrence_guideline
      )
      if (!is.null(prompt_log)) assign(reask_label, reask_prompt, envir = prompt_log)

      reask_error <- NULL
      reask_raw <- tryCatch(
        if (is.null(max_tokens)) {
          llm_fn(reask_prompt)
        } else {
          llm_fn(reask_prompt, max_tokens = max_tokens)
        },
        error = function(e) {
          reask_error <<- conditionMessage(e)
          NULL
        }
      )
      # A hard llm_fn error (network/auth) will not be fixed by asking again --
      # stop re-asking and let the residue be reported, exactly as the halving
      # retry declines to retry a broken call.
      if (!is.null(reask_error)) {
        warning(sprintf(
          "Re-ask for omitted taxa failed for batch %s: %s. Leaving %d unreviewed.",
          batch_label, reask_error, length(setdiff(missing, recovered_all))
        ), call. = FALSE)
        hard_stop <- TRUE
        break
      }

      reask <- .parse_review_response(
        reask_raw, sub_batch, target_group, taxon_rank_col, use_candidates,
        site_names = sites$site
      )
      rec <- setdiff(sub_batch$taxon_name, attr(reask, "missing_taxa"))
      if (length(rec) > 0L) {
        keep <- reask$taxon_name %in% rec
        parsed <- rbind(
          parsed[!parsed$taxon_name %in% rec, , drop = FALSE],
          reask[keep, , drop = FALSE]
        )
        recovered_all <- c(recovered_all, rec)
      }
    }
    still_missing <- setdiff(missing, recovered_all)
    if (verbose && length(recovered_all) > 0L) {
      message(sprintf(
        "    recovered %d of %d on re-ask.", length(recovered_all), length(missing)
      ))
    }
    if (length(still_missing) == length(missing)) {
      if (!singletons && length(missing) > 1L) {
        singletons <- TRUE
      } else {
        missing <- still_missing
        break
      }
    }
    missing <- still_missing
  }

  if (length(missing) > 0L && verbose) {
    # A message, not a warning: .parse_review_response() has already warned
    # per batch and review_assignments() summarises the whole run's residue
    # at the end -- three warnings for one omission is noise, not signal.
    message(sprintf(
      "  Batch %s: %d still unreviewed after %d re-ask attempt(s): %s",
      batch_label, length(missing), attempt, paste(missing, collapse = ", ")
    ))
  }

  # Restore the batch's original taxon order so the result is deterministic
  # regardless of how many rows the re-ask moved to the bottom.
  parsed <- parsed[order(match(parsed$taxon_name, taxa_batch$taxon_name)), ,
    drop = FALSE
  ]
  rownames(parsed) <- NULL

  attr(parsed, "status") <- NULL
  attr(parsed, "pending_warnings") <- NULL
  attr(parsed, "missing_taxa") <- as.character(missing)
  parsed
}


#' rbind Two Review Results, Preserving the Unreviewed Residue
#'
#' \code{rbind()} on data frames drops attributes, so the retry recursion's
#' \code{missing_taxa} residue has to be unioned explicitly or the top-level
#' count silently reports zero unreviewed taxa for a run that had some.
#' @noRd
.rbind_reviews <- function(a, b) {
  out <- rbind(a, b)
  attr(out, "missing_taxa") <- union(
    attr(a, "missing_taxa") %||% character(0),
    attr(b, "missing_taxa") %||% character(0)
  )
  out
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
                                   taxon_rank_col, use_candidates = FALSE,
                                   site_names = NULL) {
  expected_taxa <- taxa_batch$taxon_name
  with_geo <- !is.null(site_names)
  # names = expected_taxa by default (the whole-batch NA-fill case); also
  # reused below for the narrower "LLM omitted these specific taxa" case, so
  # both NA-filled shapes are built from one place.
  make_default <- function(names = expected_taxa) {
    out <- data.frame(
      taxon_name = names,
      habitat_plausibility = NA_character_,
      geographic_plausibility = NA_character_,
      scope_plausibility = NA_character_,
      contamination_risk = NA_character_,
      review_alternatives = NA_character_,
      review_lower_hypotheses = NA_character_,
      review_confidence = NA_character_,
      review_comment = NA_character_,
      p_habitat = NA_real_,
      p_habitat_lo = NA_real_,
      p_habitat_hi = NA_real_,
      p_transported = NA_real_,
      p_scope = NA_real_,
      p_scope_lo = NA_real_,
      p_scope_hi = NA_real_,
      p_contamination = NA_real_,
      p_geographic = NA_real_,
      stringsAsFactors = FALSE
    )
    if (with_geo) {
      out$p_inside_range <- NA_real_
      out$p_outside_range <- NA_real_
      out$range_known <- NA
      out$range_south_lat <- NA_real_
      out$range_north_lat <- NA_real_
      out$review_geo_json <- NA_character_
    }
    out
  }

  .with_status <- function(result, status, pending_warnings = character(0),
                           missing_taxa = character(0)) {
    attr(result, "status") <- status
    attr(result, "pending_warnings") <- pending_warnings
    # Which expected taxa carry NA-filled defaults rather than a real verdict.
    # Exposed (rather than only warned about) so .review_batch_with_retry()
    # can RE-ASK for exactly these, and so review_assignments() can report the
    # residue that survives -- without this, the omission would only be
    # warned about and then forgotten, and the workflows' `!= "unlikely"`
    # export filters would drop the NA rows without a word.
    attr(result, "missing_taxa") <- as.character(missing_taxa)
    result
  }

  if (is.null(response) || !nzchar(trimws(response))) {
    return(.with_status(
      make_default(), "failed",
      "Empty LLM response. Returning NA defaults.",
      missing_taxa = expected_taxa
    ))
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
      cleaned,
      perl = TRUE
    )
    parsed <- .parse_json_text(arr_str)
  }

  # Strategy 4: Truncated JSON recovery
  if (is.null(parsed) || !is.data.frame(parsed)) {
    parsed <- .recover_truncated_json(fenced)
  }

  if (is.null(parsed) || !is.data.frame(parsed) || nrow(parsed) == 0L) {
    n <- nchar(trimws(response))
    tail_str <- if (n > 200L) substr(trimws(response), max(1L, n - 200L), n) else trimws(response)
    return(.with_status(make_default(), "failed", sprintf(
      "Could not parse LLM response as JSON. Returning NA defaults.\n  Response length: %d chars; ends with: ...%s",
      n, tail_str
    ), missing_taxa = expected_taxa))
  }

  pending <- character(0)
  status <- "complete"

  n_recovered <- nrow(parsed)
  n_expected <- length(expected_taxa)
  if (n_recovered < n_expected) {
    status <- "truncated"
    pending <- c(pending, sprintf(
      "LLM response was truncated. Recovered %d of %d taxa from partial JSON.",
      n_recovered, n_expected
    ))
  }

  if (!"taxon_name" %in% names(parsed)) {
    return(.with_status(
      make_default(), "failed",
      "LLM response missing 'taxon_name' field. Returning NA defaults.",
      missing_taxa = expected_taxa
    ))
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

  # A probability field, as numbers. jsonlite hands back an atomic column when
  # every object had the field and a list column when any was null or an array,
  # so both shapes are read here; anything that is not a single number in
  # [0, 1] becomes NA rather than a silent 0 or a recycled neighbour.
  .safe_num <- function(input_df, col_name, lo = 0, hi = 1) {
    if (!col_name %in% names(input_df)) {
      return(rep(NA_real_, nrow(input_df)))
    }
    v <- input_df[[col_name]]
    out <- if (is.list(v)) {
      vapply(v, function(z) {
        if (is.null(z) || length(z) != 1L) {
          NA_real_
        } else {
          suppressWarnings(as.numeric(z[[1L]]))
        }
      }, numeric(1L))
    } else {
      suppressWarnings(as.numeric(v))
    }
    out[!is.na(out) & (out < lo | out > hi)] <- NA_real_
    out
  }
  # One end of a stated 90% range. Output only -- nothing downstream reads it
  # -- but measured to be informative: the ranges the model states are 5-10x
  # its own run-to-run spread, so they express uncertainty about the TAXON.
  .safe_bound <- function(input_df, col_name, which_end) {
    if (!col_name %in% names(input_df)) {
      return(rep(NA_real_, nrow(input_df)))
    }
    v <- input_df[[col_name]]
    if (is.matrix(v)) {
      return(suppressWarnings(as.numeric(v[, which_end])))
    }
    if (!is.list(v)) {
      return(rep(NA_real_, length(v)))
    }
    vapply(v, function(z) {
      z <- suppressWarnings(as.numeric(unlist(z, use.names = FALSE)))
      if (length(z) < which_end) NA_real_ else z[[which_end]]
    }, numeric(1L))
  }

  result <- data.frame(
    taxon_name = as.character(parsed$taxon_name),
    habitat_plausibility = NA_character_,
    geographic_plausibility = NA_character_,
    scope_plausibility = NA_character_,
    contamination_risk = NA_character_,
    review_alternatives = .safe_col(parsed, "review_alternatives"),
    review_lower_hypotheses = .safe_col(parsed, "review_lower_hypotheses"),
    review_confidence = .safe_col(parsed, "review_confidence"),
    review_comment = .safe_col(parsed, "review_comment"),
    p_habitat = .safe_num(parsed, "p_habitat"),
    p_habitat_lo = .safe_bound(parsed, "p_habitat_range", 1L),
    p_habitat_hi = .safe_bound(parsed, "p_habitat_range", 2L),
    p_transported = .safe_num(parsed, "p_transported"),
    p_scope = .safe_num(parsed, "p_scope"),
    p_scope_lo = .safe_bound(parsed, "p_scope_range", 1L),
    p_scope_hi = .safe_bound(parsed, "p_scope_range", 2L),
    p_contamination = .safe_num(parsed, "p_contamination"),
    p_geographic = .safe_num(parsed, "p_geographic"),
    stringsAsFactors = FALSE
  )
  if (with_geo) {
    result$p_inside_range <- .safe_num(parsed, "p_inside_range")
    result$p_outside_range <- .safe_num(parsed, "p_outside_range")
    # The range fields are per-taxon columns of the answer now, not a nested
    # rule object, so each row's range answer is assembled from them here.
    .cell <- function(col, i) {
      if (!col %in% names(parsed)) {
        return(NA)
      }
      v <- parsed[[col]]
      if (is.list(v)) (if (i <= length(v)) v[[i]] else NA) else v[[i]]
    }
    result$range_known <- vapply(seq_len(nrow(result)), function(i) {
      k <- .cell("range_known", i)
      if (is.character(k)) k <- tolower(trimws(k)) %in% c("true", "yes", "t")
      isTRUE(as.logical(k[1L]))
    }, logical(1L))
    result$range_south_lat <- .safe_num(parsed, "range_south_lat", -90, 90)
    result$range_north_lat <- .safe_num(parsed, "range_north_lat", -90, 90)
    result$review_geo_json <- vapply(seq_len(nrow(result)), function(i) {
      .geo_spec_to_json(.normalise_range_answer(list(
        range_known = result$range_known[i],
        range_south_lat = result$range_south_lat[i],
        range_north_lat = result$range_north_lat[i],
        sites_outside_range = .cell("sites_outside_range", i),
        p_inside_range = result$p_inside_range[i],
        p_outside_range = result$p_outside_range[i]
      ), site_names))
    }, character(1L))
  }
  result <- .derive_levels(result)

  # An echoed id prefix ("[T3] Cottus") is part of the prompt's own notation,
  # not a different name: drop it before any matching, silently.
  result$taxon_name <- sub("^\\s*\\[T[0-9]+\\]\\s*", "", result$taxon_name)
  # Match by id first (R1). Ids are local to this prompt: T<i> is row i of
  # taxa_batch. An id overrides the echoed name, which the model may have
  # reformatted; an unknown or repeated id is ignored and the name decides.
  if ("id" %in% names(parsed)) {
    ids <- toupper(trimws(as.character(parsed$id)))
    idx <- match(ids, paste0("T", seq_along(expected_taxa)))
    idx[duplicated(idx) & !is.na(idx)] <- NA_integer_
    ok <- !is.na(idx)
    result$taxon_name[ok] <- expected_taxa[idx[ok]]
  }
  # One set asked, one object back: it is that set's answer, whatever name
  # the model gave it (the singleton re-ask relies on this).
  if (length(expected_taxa) == 1L && nrow(result) == 1L &&
    !result$taxon_name[1L] %in% expected_taxa) {
    result$taxon_name[1L] <- expected_taxa[1L]
  }

  # No target group means no scope question was asked, so a scope answer the
  # model volunteered anyway is dropped at the SOURCE -- the probability --
  # not just at the verdict. Clearing only the verdict would leave
  # .derive_levels() free to recompute it from a probability we never asked
  # for, and llm_p_scope would report a judgement against no target group.
  if (is.null(target_group)) {
    result$p_scope <- NA_real_
    result$p_scope_lo <- NA_real_
    result$p_scope_hi <- NA_real_
    result$scope_plausibility <- NA_character_
  }

  # Suppress lower hypotheses when candidates were supplied (already known)
  if (use_candidates || is.null(taxon_rank_col)) {
    result$review_lower_hypotheses <- NA_character_
  }

  # Normalize taxon names: strip trailing punctuation + case-fold for matching.
  # LLMs sometimes append periods, commas, or authority strings to names they
  # return. Exact-string join would silently drop those rows. Attempt a
  # normalised fallback: if a result name doesn't match any expected name
  # exactly but matches one after normalisation, remap it to the canonical
  # expected name and warn so the caller can inspect.
  # Also strips a trailing "(rank: ...)" or "(unresolved candidates;
  # consensus rank: ...)" annotation. taxa_batch's own prompt rendering shows
  # each taxon as "- Cottus (rank: Cottus aleuticus)" when taxon_rank_col is
  # supplied, and an UNRESOLVED candidate set as "- <label> (unresolved
  # candidates; consensus rank: <rank>)" (see .build_taxa_block());
  # "taxon_name: the exact taxon name as provided" can lead the LLM to echo
  # the whole displayed string back, including the parenthetical, rather
  # than just the bare name.
  #
  # Both forms must be stripped: a normalisation that recognised only a
  # parenthetical beginning with "rank:" would leave every multi-candidate
  # slash taxon unrecognised, wrongly treated as omitted, filled with NA, and
  # then dropped by the workflows' export filters without a word --
  # confirmed on real data at 113 of 885 rows on GreatLakes, every one of
  # them a multi-candidate set; singletons were unaffected because their
  # "(rank: ...)" annotation WAS handled, which is exactly why the loss
  # would look like "coarse ranks are excluded on purpose".
  .norm <- function(x) {
    x <- sub("^\\s*\\[T[0-9]+\\]\\s*", "", x) # an echoed id prefix
    x <- sub("(?i)\\s*\\(\\s*(?:unresolved candidates|rank\\s*:)[^)]*\\)\\s*$",
      "", trimws(x),
      perl = TRUE
    )
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
        remapped <- c(
          remapped,
          sprintf("'%s' -> '%s'", result$taxon_name[i], expected_taxa[hit])
        )
        result$taxon_name[i] <- expected_taxa[hit]
      }
    }
    if (length(remapped) > 0L) {
      pending <- c(pending, sprintf(
        "LLM returned %d name(s) that required normalised matching: %s",
        length(remapped), paste(remapped, collapse = "; ")
      ))
    }
  }

  # Fill any remaining missing taxa (truly absent from LLM response) with NAs
  missing_taxa <- setdiff(expected_taxa, result$taxon_name)
  if (length(missing_taxa) > 0L) {
    pending <- c(pending, sprintf(
      "LLM omitted %d taxa. Filling with NA defaults: %s",
      length(missing_taxa),
      paste(missing_taxa, collapse = ", ")
    ))
    result <- rbind(result, make_default(missing_taxa))
  }

  result <- result[result$taxon_name %in% expected_taxa, , drop = FALSE]

  # A response that answered for NONE of several expected sets is a failed
  # call, not a complete one with every set omitted (R2): reporting it as
  # complete skipped the halving retry (GreatLakes batch 4: 10 objects back,
  # 0 names matched, every re-ask repeating the mismatch).
  if (length(expected_taxa) > 1L && length(missing_taxa) == length(expected_taxa) &&
    identical(status, "complete")) {
    status <- "failed"
  }

  .with_status(result, status, pending, missing_taxa)
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
  if (!is.character(text) || length(text) != 1L || is.na(text)) {
    return(NULL)
  }
  if (!grepl("^\\s*[\\[{]", text, perl = TRUE)) {
    return(NULL)
  }
  tryCatch(jsonlite::fromJSON(text, simplifyDataFrame = TRUE),
    error = function(e) NULL
  )
}


#' Recover Parseable Objects from Truncated JSON Array
#' @noRd
.recover_truncated_json <- function(text) {
  if (is.null(text) || !nzchar(trimws(text))) {
    return(NULL)
  }

  arr_start <- regexpr("\\[", text)
  if (arr_start < 0L) {
    return(NULL)
  }

  text_from_arr <- substring(text, arr_start)
  brace_positions <- gregexpr("\\}", text_from_arr)[[1]]
  if (brace_positions[1] < 0L) {
    return(NULL)
  }

  for (i in rev(seq_along(brace_positions))) {
    candidate <- paste0(substring(text_from_arr, 1L, brace_positions[i]), "\n]")
    parsed <- .parse_json_text(candidate)
    if (is.data.frame(parsed) && nrow(parsed) > 0L) {
      return(parsed)
    }
  }

  NULL
}


# ==============================================================================
# Site-aware geography (active only when review_assignments(sites = ) is given)
# ==============================================================================

# Verdict order, best first.
# --- The probability answer format (guardrails G1-G5) -------------------------
# The review asks for probabilities, not categories, and TaxaFlag derives the
# categorical llm_* columns from them in code (see .p_to_level()). Measured on
# 150 CalIntertidal taxa with claude-opus-5-5: verdict-driven decisions repeated
# between two asks 97-99% of the time against 90% for the categorical prompt,
# and agreed with the maintainer's own labels on 78% of rows against 67%.
#
# The wording of every block below is part of the question, so any change to it
# must bump "v6" (and "geo_sites_v5" for the site blocks) in the cache key --
# the key holds the inputs, not the prompt, so a verdict obtained from older
# wording would otherwise be served as a hit.

#' The habitat field: living conditions only, never region
#'
#' Habitat and geography are asked separately on purpose. A taxon that lives in
#' this kind of habitat but not in this region must score high on habitat and
#' low on geography, because the two drive different product rules; merging them
#' loses the distinction and was measured to cost accuracy.
#' @noRd
.p_habitat_field_text <- function(habitat) {
  where <- if (!is.null(habitat) && !is.na(habitat) && nzchar(trimws(habitat))) {
    sprintf(" (%s)", trimws(habitat))
  } else {
    ""
  }
  paste0(
    '  "p_habitat": probability that the taxon\'s LIVING CONDITIONS match the ',
    "study habitat", where, ": that it lives (any life stage) in this kind of ",
    "habitat, wherever its range is. Judge the habitat type only; whether it ",
    "occurs in the study region is geography (the range fields), not habitat. ",
    "High = regularly; intermediate = occasionally, marginally, or only some ",
    "life stages or places (e.g. juveniles only); low = does not live in this ",
    "kind of habitat,"
  )
}

.p_transported_field_text <- paste0(
  '  "p_transported": probability that the taxon\'s DNA could plausibly reach ',
  "these samples from adjacent habitats or waters (e.g. currents, inflowing ",
  "water, predators, nearby habitats). This is separate from residency: a ",
  "non-resident can have a high value,"
)

#' The scope field: kind of organism and depth or zone only, never region
#' @noRd
.p_scope_field_text <- function(target_group) {
  if (is.null(target_group)) {
    return('  "p_scope": null (no target group specified),')
  }
  paste0(
    '  "p_scope": probability that the taxon is in the target group (',
    target_group, ") by the KIND OF ORGANISM and its depth or habitat zone ",
    "only; whether it occurs in the study region is geography, not scope. ",
    "High = the kind of organism and its normal depth or zone fit the target ",
    "group; intermediate = mainly outside it but with a regular life stage ",
    "inside it, or a group containing both kinds; low = a kind of organism, ",
    "realm or depth the target group excludes,"
  )
}

# Geography with a site table: the model states range LIMITS and TaxaFlag
# computes the site and study verdicts from them (guardrail G2). Asking for the
# limits instead of a per-site verdict removes the model's choice of rule type
# and the undefined "study-wide" verdict; the study verdict is defined here as
# the maximum site probability over the sites where the taxon was detected.
.p_range_field_text <- paste0(
  '  "range_known": true if you know the taxon\'s range limits within the ',
  "study region well enough to state them, false if you do not,\n",
  '  "range_south_lat": the southern limit of its range within the study ',
  "region in decimal degrees N, or null if the range extends south beyond the ",
  "study (or range_known is false),\n",
  '  "range_north_lat": the northern limit within the study region, or null ',
  "if the range extends north beyond the study (or range_known is false),\n",
  '  "sites_outside_range": names of study sites outside the range when ',
  "latitude limits do not describe it (e.g. island-only, a gap in the range), ",
  "copied exactly, or [],\n",
  '  "p_inside_range": probability that the taxon occurs at a study site ',
  "inside its range (a rare but in-range taxon is intermediate, not low),\n",
  '  "p_outside_range": probability that it occurs at a study site outside ',
  "its range,\n"
)

# Geography with no site table: there are no site latitudes for a stated limit
# to be applied to, so the model gives the study-wide probability directly.
.p_study_geo_field_text <- paste0(
  '  "p_geographic": probability that the study area lies within this ',
  "taxon’s geographic range (overall, across the study area),\n",
  '  "p_geographic_range": [low, high],\n'
)

.p_contamination_field_text <- paste0(
  '  "p_contamination": probability that this detection is contamination ',
  "rather than DNA from the sampled environment. Anchors: high (about 0.7 or ",
  "more) = a food, lab or aquarium species with no wild population in the ",
  "region; intermediate (about 0.2-0.5) = a commercial food or bait species ",
  "that also lives wild in the region, or a human-associated taxon; low ",
  "(under 0.2) = otherwise,"
)

# Guidelines common to both paths. The four-questions line is the guardrail
# that keeps habitat, detectability, range and scope from collapsing into one
# judgement, which is what the categorical prompt was measured to do.
.p_guideline_text <- paste0(
  "- For a genus or family, judge the group: does ANY member qualify?\n",
  "- Answer the four questions separately. Residency (p_habitat) is not ",
  "detectability (p_transported); range (geography) is not habitat or scope; ",
  "rarity within the range is not absence.\n"
)

.p_range_guideline_text <- paste0(
  "- State range limits as numbers. Southern limit = the southernmost ",
  "latitude of the range within the study region, northern limit = the ",
  "northernmost. Decide which side each limit is on before answering. The ",
  "study’s site verdicts are computed from your limits, so do not ",
  "summarise geography any other way. If latitude cannot describe the range ",
  "-- for a study that runs east to west, or one at a single latitude -- ",
  "leave both limits null and name the sites outside the range instead.\n",
  "- If you cannot recall a rare or poorly known taxon’s range, say so: ",
  "range_known false, and p_inside_range = p_outside_range = an intermediate ",
  "value with low confidence. Do not reconstruct a range from the genus or ",
  "from similar species. No records is not evidence of absence.\n"
)

.p_study_geo_guideline_text <- paste0(
  "- Judge GEOGRAPHY (range) only: habitat fit and rarity are rated ",
  "separately, and a rare but in-range occurrence has an intermediate ",
  "geographic probability, not a low one.\n",
  "- If you cannot recall a rare or poorly known taxon’s range, give an ",
  "intermediate probability with low confidence rather than recalling one. ",
  "No records is not evidence of absence.\n"
)

# Worked examples (G5). Deliberately generic: a named species here would teach
# the model the answer for that species rather than the shape of the judgement,
# and the examples must suit a freshwater or terrestrial study as well as a
# marine one.
.p_worked_examples_text <- paste0(
  "WORKED EXAMPLES (invented taxa):\n",
  "- A taxon from a very different habitat (e.g. a deep-sea fish in a shore ",
  "study, or a marine species in a freshwater study): p_habitat 0.03 (not ",
  "resident), p_transported set by how its DNA could arrive (e.g. 0.6 with ",
  "currents or predators, 0.05 with no route), p_scope low if the target ",
  "group excludes its kind or depth.\n",
  "- A taxon whose habitat fits but whose range ends part-way through the ",
  "study area, detected beyond that limit: p_habitat 0.8, the limit stated as ",
  "a number on the correct side, p_inside_range 0.7, p_outside_range 0.05.\n",
  "- A commercial food species that also lives wild in the region: ",
  "p_contamination 0.3. A farmed species with no wild population in the ",
  "region: p_contamination 0.85.\n",
  "- A rare taxon you cannot place: range_known false, p_inside_range 0.5, ",
  "p_outside_range 0.5, review_confidence \"low\".\n\n"
)

.p_detected_guideline_text <- paste0(
  '- A "[detected at: ...]" bracket lists the sites where this taxon was ',
  "detected in this study.\n"
)

#' The EXAMPLE OUTPUT FORMAT block, for whichever geography fields were asked
#'
#' Two objects, as before: a plausible resident and a contaminant. The
#' contaminant's comment is the data-type-specific one, so an acoustic or image
#' study sees an example from its own method rather than an eDNA one.
#' @noRd
.p_example_output <- function(sites, use_candidates, example_comment) {
  geo_resident <- if (!is.null(sites)) {
    paste0(
      '"range_known": true, "range_south_lat": 28.0, ',
      '"range_north_lat": null, "sites_outside_range": [], ',
      '"p_inside_range": 0.9, "p_outside_range": 0.05, '
    )
  } else {
    '"p_geographic": 0.97, "p_geographic_range": [0.92, 0.99], '
  }
  geo_contam <- if (!is.null(sites)) {
    paste0(
      '"range_known": true, "range_south_lat": null, ',
      '"range_north_lat": null, "sites_outside_range": [], ',
      '"p_inside_range": 0.99, "p_outside_range": 0.99, '
    )
  } else {
    '"p_geographic": 0.99, "p_geographic_range": [0.95, 1.00], '
  }
  lower <- if (use_candidates) "" else '"review_lower_hypotheses": null, '
  paste0(
    "[\n",
    '  {"id": "T1", "taxon_name": "Example residentus", "p_habitat": 0.95, ',
    '"p_habitat_range": [0.90, 0.99], "p_transported": 0.90, "p_scope": 0.97, ',
    '"p_scope_range": [0.93, 0.99], ', geo_resident,
    '"p_contamination": 0.02, "review_alternatives": null, ', lower,
    '"review_confidence": "high", "review_comment": null},\n',
    '  {"id": "T2", "taxon_name": "Homo sapiens", "p_habitat": 0.01, ',
    '"p_habitat_range": [0.00, 0.05], "p_transported": 0.20, "p_scope": 0.01, ',
    '"p_scope_range": [0.00, 0.02], ', geo_contam,
    '"p_contamination": 0.95, "review_alternatives": null, ', lower,
    '"review_confidence": "high", "review_comment": "', example_comment, '"}\n',
    "]\n\n"
  )
}

.geo_levels <- c("likely", "possible", "unlikely")

# --- Probability -> category --------------------------------------------------
# The model answers with a probability; these cuts are how TaxaFlag reads it.
# They are the "margin" cuts, chosen by measurement over hard cuts (0.20/0.70,
# contamination 0.50): on the maintainer's own labels for the 34 hardest taxa,
# the extra rows the margin rule acts on were 94% rows he also acted on,
# against about half for the hard cuts, and 97-99% of verdict-driven decisions
# repeated between two asks.
#
# The cuts are deliberately NOT part of the cache key. The cached answer is the
# probability; a cut is this code's reading of it, re-applied on every run (see
# .derive_levels()). Changing a cut therefore takes effect for already-cached
# taxa too, with no new LLM calls -- which is only true because the cut is
# applied after the cache and never before it.
.p_cut_unlikely <- 0.10
.p_cut_likely <- 0.70
.p_cut_contam_moderate <- 0.20
.p_cut_contam_high <- 0.70

#' Three-level plausibility verdict from a probability
#' @noRd
.p_to_level <- function(p) {
  p <- suppressWarnings(as.numeric(p))
  out <- rep(NA_character_, length(p))
  ok <- !is.na(p)
  out[ok] <- ifelse(p[ok] < .p_cut_unlikely, "unlikely",
    ifelse(p[ok] < .p_cut_likely, "possible", "likely")
  )
  out
}

#' Contamination risk level from a probability
#' @noRd
.p_to_risk <- function(p) {
  p <- suppressWarnings(as.numeric(p))
  out <- rep(NA_character_, length(p))
  ok <- !is.na(p)
  out[ok] <- ifelse(p[ok] < .p_cut_contam_moderate, "low",
    ifelse(p[ok] < .p_cut_contam_high, "moderate", "high")
  )
  out
}

#' A probability column of a review frame, or all-NA when the path never asked
#' @noRd
.p_col <- function(df, nm) {
  if (nm %in% names(df)) suppressWarnings(as.numeric(df[[nm]])) else rep(NA_real_, nrow(df))
}

#' Fill the categorical verdict columns from the probability columns
#'
#' Called in the parser, so a freshly asked row carries both, and again after
#' cached rows are folded back in, so every row in one run is read through the
#' same cuts even when it was cached under earlier ones.
#'
#' With a site table the study-wide geographic verdict is the best over the
#' detected sites and .apply_site_verdicts() computes it; what is set here is
#' the value it starts from, which is also the answer when no site falls
#' outside the stated range.
#' @noRd
.derive_levels <- function(df) {
  df$habitat_plausibility <- .p_to_level(.p_col(df, "p_habitat"))
  df$scope_plausibility <- .p_to_level(.p_col(df, "p_scope"))
  df$contamination_risk <- .p_to_risk(.p_col(df, "p_contamination"))
  geo <- if ("p_inside_range" %in% names(df)) {
    # With a site table p_inside_range is the geography answer. A model that
    # omitted it but volunteered the study-wide p_geographic it was not asked
    # for is taken at its word for that row rather than left with no geography
    # at all: an NA here is discarded by every downstream "!= unlikely" filter,
    # which would lose the observation without a word.
    ins <- .p_col(df, "p_inside_range")
    alt <- .p_col(df, "p_geographic")
    ifelse(is.na(ins), alt, ins)
  } else {
    .p_col(df, "p_geographic")
  }
  df$geographic_plausibility <- .p_to_level(geo)
  df$p_geographic <- geo
  df
}

#' STUDY SITES block of the prompt, sorted south to north
#' @noRd
.sites_prompt_block <- function(sites) {
  s <- sites[order(sites$lat, sites$site), , drop = FALSE]
  paste0(
    "STUDY SITES (name, latitude, longitude; sorted south to north):\n",
    paste(sprintf("  %s (%.2f, %.2f)", s$site, s$lat, s$lon), collapse = "\n"),
    "\n"
  )
}

#' Order-independent digest of the sites table, for the cache key
#' @noRd
.review_sites_digest <- function(sites) {
  lines <- sort(sprintf("%s|%.2f|%.2f", sites$site, sites$lat, sites$lon),
    method = "radix"
  )
  .review_cache_hash(paste(lines, collapse = "\n"))
}

#' Validate the sites table; return it reduced to site/lat/lon
#' @noRd
.validate_review_sites <- function(sites, input_df, site_col) {
  if (!is.data.frame(sites)) {
    stop("'sites' must be a data frame with columns site, lat, lon, or NULL.", call. = FALSE)
  }
  miss <- setdiff(c("site", "lat", "lon"), names(sites))
  if (length(miss) > 0L) {
    stop(sprintf("'sites' is missing column(s): %s.", paste(miss, collapse = ", ")), call. = FALSE)
  }
  if (nrow(sites) == 0L) stop("'sites' has no rows.", call. = FALSE)
  if (!is.numeric(sites$lat) || !is.numeric(sites$lon)) {
    stop("'sites$lat' and 'sites$lon' must be numeric.", call. = FALSE)
  }
  if (anyNA(sites$lat) || anyNA(sites$lon) ||
    any(!is.finite(sites$lat)) || any(!is.finite(sites$lon))) {
    stop("'sites$lat' and 'sites$lon' must not contain NA or non-finite values.", call. = FALSE)
  }
  if (any(abs(sites$lat) > 90) || any(abs(sites$lon) > 180)) {
    stop("'sites' has latitude outside [-90, 90] or longitude outside [-180, 180].", call. = FALSE)
  }
  nm <- as.character(sites$site)
  if (anyNA(nm) || any(!nzchar(trimws(nm)))) {
    stop("'sites$site' must not contain NA or empty names.", call. = FALSE)
  }
  if (anyDuplicated(nm)) {
    stop(sprintf(
      "'sites$site' must be unique; duplicated: %s.",
      paste(unique(nm[duplicated(nm)]), collapse = ", ")
    ), call. = FALSE)
  }
  if (!is.character(site_col) || length(site_col) != 1L || is.na(site_col)) {
    stop("'site_col' must be a single character string.", call. = FALSE)
  }
  if (!site_col %in% names(input_df)) {
    stop(sprintf("site_col '%s' not found in input_df.", site_col), call. = FALSE)
  }
  vals <- unique(as.character(input_df[[site_col]]))
  bad <- vals[!is.na(vals) & !vals %in% nm]
  if (length(bad) > 0L) {
    warning(sprintf(
      "%d value(s) of input_df$%s are not in sites$site and get the study-wide geographic verdict: %s",
      length(bad), site_col, paste(utils::head(bad, 10L), collapse = ", ")
    ), call. = FALSE)
  }
  data.frame(site = nm, lat = as.numeric(sites$lat), lon = as.numeric(sites$lon),
    stringsAsFactors = FALSE
  )
}

#' Normalise the model's range answer into a site rule spec
#'
#' Carries over every guard the earlier per-site rule object needed, because
#' the failure modes are properties of the model, not of the field names:
#' a latitude outside [-90, 90] is not a latitude; a southern limit placed in
#' range_north_lat inverts the band and would mark every site outside, so the
#' pair is swapped rather than obeyed; named sites are matched case-insensitively
#' against the site table and unknown names are counted, not silently treated as
#' outside; and a list in which NO name is recognised is dropped entirely rather
#' than allowed to move nothing while looking as though it moved something.
#'
#' range_known = FALSE is a real answer, not a failure: it means "I cannot place
#' this taxon", and every site then takes p_inside_range, which the guidelines
#' tell the model to make intermediate.
#' @noRd
.normalise_range_answer <- function(o, site_names) {
  fb <- function(how, n_unknown = 0L) {
    list(
      rule = "fallback", lat_min = NA_real_, lat_max = NA_real_,
      p_in = NA_real_, p_out = NA_real_, unlikely_sites = character(0),
      how = how, n_unknown = as.integer(n_unknown)
    )
  }
  one <- function(x) if (length(x) >= 1L) x[[1L]] else NA
  if (!is.list(o)) {
    return(fb("missing"))
  }
  prob <- function(x) {
    v <- suppressWarnings(as.numeric(one(x)))
    if (is.na(v) || v < 0 || v > 1) NA_real_ else v
  }
  lat <- function(x) {
    v <- suppressWarnings(as.numeric(one(x)))
    if (is.na(v) || abs(v) > 90) NA_real_ else v
  }
  p_in <- prob(o$p_inside_range)
  p_out <- prob(o$p_outside_range)
  if (is.na(p_in)) {
    return(fb("no_inside_probability"))
  }

  # Sites the model named as outside the range, when latitude cannot say it.
  u <- trimws(as.character(unlist(o$sites_outside_range, use.names = FALSE)))
  u <- unique(u[!is.na(u) & nzchar(u)])
  pos <- match(tolower(u), tolower(trimws(site_names)))
  n_unknown <- sum(is.na(pos))
  known <- unique(site_names[pos[!is.na(pos)]])

  known_flag <- one(o$range_known)
  if (is.character(known_flag)) {
    known_flag <- tolower(trimws(known_flag)) %in% c("true", "yes", "t")
  }
  known_flag <- isTRUE(as.logical(known_flag))

  lo <- lat(o$range_south_lat)
  hi <- lat(o$range_north_lat)
  how <- if (n_unknown > 0L) "sites_unknown_ignored" else NA_character_

  if (!known_flag) {
    spec <- fb(.combine_how("range_unknown", how), n_unknown)
    spec$rule <- "unknown"
    spec$p_in <- p_in
    spec$p_out <- p_out
    # A taxon whose range the model cannot state still has whatever sites it
    # named honoured: "I don't know the limits" and "not at that site" are
    # different claims.
    spec$unlikely_sites <- known
    return(spec)
  }

  if (!is.na(lo) && !is.na(hi) && lo > hi) {
    tmp <- lo
    lo <- hi
    hi <- tmp
    how <- .combine_how("range_swapped", how)
  }
  if (is.na(lo) && is.na(hi) && length(known) == 0L) {
    # No limit inside the study and no site named: the range covers the study.
    how <- .combine_how("no_limit_in_study", how)
  }
  list(
    rule = "range", lat_min = lo, lat_max = hi, p_in = p_in, p_out = p_out,
    unlikely_sites = known,
    how = if (is.na(how)) "range" else how,
    n_unknown = as.integer(n_unknown)
  )
}

#' Join two "how" notes, either of which may be NA
#' @noRd
.combine_how <- function(a, b) {
  if (is.na(b)) a else paste(a, b, sep = "+")
}

#' @noRd
.geo_spec_to_json <- function(spec) {
  as.character(jsonlite::toJSON(spec,
    auto_unbox = TRUE, null = "null", na = "null", digits = NA
  ))
}

#' @noRd
.geo_spec_from_json <- function(json) {
  if (is.null(json) || is.na(json)) {
    return(NULL)
  }
  x <- tryCatch(jsonlite::fromJSON(json, simplifyVector = FALSE), error = function(e) NULL)
  if (!is.list(x)) {
    return(NULL)
  }
  num <- function(v) if (is.null(v)) NA_real_ else as.numeric(v)
  list(
    rule = x$rule %||% "fallback",
    lat_min = num(x$lat_min), lat_max = num(x$lat_max),
    p_in = num(x$p_in), p_out = num(x$p_out),
    unlikely_sites = as.character(unlist(x$unlikely_sites, use.names = FALSE)),
    how = x$how %||% NA_character_,
    n_unknown = as.integer(x$n_unknown %||% 0L)
  )
}

#' Per-site probability for one range spec
#'
#' This is the whole of guardrail G2: the model states limits, and the site
#' probability is read off them here rather than asked for. A site beyond a
#' stated limit, or named in sites_outside_range, gets p_outside_range; every
#' other site gets p_inside_range. A model that gave no outside probability
#' gets p_inside_range everywhere, which is the conservative reading -- it
#' never manufactures an "outside" the model did not state.
#' @noRd
.geo_site_probs <- function(spec, sites) {
  n <- nrow(sites)
  if (is.null(spec) || is.na(spec$p_in)) {
    return(rep(NA_real_, n))
  }
  p_out <- if (is.na(spec$p_out)) spec$p_in else spec$p_out
  if (!identical(spec$rule, "range") && !identical(spec$rule, "unknown")) {
    return(rep(NA_real_, n))
  }
  v <- rep(spec$p_in, n)
  if (identical(spec$rule, "unknown")) {
    # No limits to apply; only sites the model named explicitly move.
    v[sites$site %in% spec$unlikely_sites] <- p_out
    return(v)
  }
  outside <- (!is.na(spec$lat_min) & sites$lat < spec$lat_min) |
    (!is.na(spec$lat_max) & sites$lat > spec$lat_max) |
    sites$site %in% spec$unlikely_sites
  v[outside] <- p_out
  v
}

#' Per-site verdicts for one range spec
#'
#' The cuts are applied here and nowhere earlier, so the verdict is always a
#' function of the probability this run read from the cache or the model.
#' \code{base} is used only when the spec yields no probability at all.
#' @noRd
.geo_site_verdicts <- function(spec, base, sites) {
  p <- .geo_site_probs(spec, sites)
  if (all(is.na(p))) {
    return(rep(base, nrow(sites)))
  }
  .p_to_level(p)
}

#' One row per reviewed taxon with its parsed range answer (attr "geographic_by_site")
#' @noRd
.geo_rules_table <- function(review_df) {
  ok <- which(!is.na(review_df$review_geo_json))
  specs <- lapply(review_df$review_geo_json[ok], .geo_spec_from_json)
  data.frame(
    taxon = review_df$taxon_name[ok],
    rule = vapply(specs, function(z) as.character(z$rule), character(1L)),
    range_south_lat = vapply(specs, function(z) z$lat_min, numeric(1L)),
    range_north_lat = vapply(specs, function(z) z$lat_max, numeric(1L)),
    p_inside_range = vapply(specs, function(z) z$p_in, numeric(1L)),
    p_outside_range = vapply(specs, function(z) z$p_out, numeric(1L)),
    sites_outside_range = vapply(
      specs, function(z) paste(z$unlikely_sites, collapse = "; "), character(1L)
    ),
    n_unknown_sites = vapply(specs, function(z) z$n_unknown, integer(1L)),
    how = vapply(specs, function(z) as.character(z$how), character(1L)),
    stringsAsFactors = FALSE
  )
}

#' Add the per-site geography columns to the joined result
#'
#' Each row takes its own site's probability and verdict; a row whose site is NA
#' or absent from the site table takes the study-wide pair. The study-wide
#' probability is the MAXIMUM over the sites where the taxon was detected, and
#' the study-wide verdict is that probability's level -- never the model's own
#' summary, which it is no longer asked for. Taking the maximum is why the
#' study verdict is also the best site verdict: the cuts are monotone.
#' @noRd
.apply_site_verdicts <- function(result, sites, site_col) {
  study <- result$llm_geographic_plausibility
  study_p <- result$llm_p_geographic
  per_site <- study
  per_site_p <- study_p
  gj <- result$.geo_json
  idx <- match(as.character(result[[site_col]]), sites$site)
  combo <- paste(gj, study, sep = "\u0001")
  for (u in unique(combo[!is.na(gj)])) {
    rows <- which(combo == u & !is.na(gj))
    spec <- .geo_spec_from_json(gj[rows[1L]])
    base <- study[rows[1L]]
    pvec <- .geo_site_probs(spec, sites)
    vec <- .geo_site_verdicts(spec, base, sites)
    best_p <- if (all(is.na(pvec))) NA_real_ else max(pvec, na.rm = TRUE)
    best <- if (all(is.na(vec))) {
      NA_character_
    } else {
      .geo_levels[min(match(vec, .geo_levels))]
    }
    sv <- rep(best, length(rows))
    sp <- rep(best_p, length(rows))
    ok <- !is.na(idx[rows])
    sv[ok] <- vec[idx[rows][ok]]
    sp[ok] <- pvec[idx[rows][ok]]
    per_site[rows] <- sv
    per_site_p[rows] <- sp
    study[rows] <- best
    if (!is.na(best_p)) study_p[rows] <- best_p
  }
  result$llm_geographic_plausibility <- study
  result$llm_p_geographic <- study_p
  pos <- match("llm_geographic_plausibility", names(result))
  result$llm_geographic_plausibility_site <- per_site
  result$llm_p_geographic_site <- per_site_p
  nm <- names(result)
  nm <- append(setdiff(nm, "llm_geographic_plausibility_site"),
    "llm_geographic_plausibility_site",
    after = pos
  )
  result[, nm, drop = FALSE]
}
