# Edge: consensus + context_df -> reviewed
# Source: TaxaFlag/inst/review_assignments_workflow.R
# NOTE: When data comes from posterior_consensus() or
#   score_consensus(), the taxon column is "consensus_taxon" and rank column
#   is "consensus_rank". For external data (e.g. user-supplied CSV), use the
#   actual column names from the data.

# cache_dir: a per-taxon verdict cache, keyed on everything that
# can move a verdict. Without it, the review is not reproducible -- two real
# GreatLakes runs 50 minutes apart on identical input disagreed about a
# species' geographic plausibility ("possible" then "unlikely"), so it
# appeared in one exported species list and not the other. Force fresh
# verdicts with TaxaFlag::taxaflag_clear_cache(<that directory>).
reviewed <- TaxaFlag::review_assignments(
  data_type = {{data_type}},
  input_df       = {{consensus_var}},
  taxon_col      = {{taxon_col}},
  taxon_rank_col = {{taxon_rank_col}},
  context        = {{context_var}},
  target_group   = {{target_group}},
  marker         = {{marker}},
  llm_fn         = {{llm_fn}},
  cache_dir      = {{review_cache_dir}},
  # Fit columns from evaluate_likelihoods(), carried through
  # posterior_consensus(). poor_absolute_fit is TRUE when the unit's best raw
  # match identity (best_identity, percent) reaches no rank threshold for the
  # marker: likelihoods are normalised to the unit maximum, so such a call can
  # still carry a high posterior and the raw identity is the only thing that
  # says otherwise. best_identity is quoted for EVERY taxon that has one, not
  # only for a poor fit; where poor_absolute_fit is TRUE the same number is
  # quoted inside that note instead. A column that is absent is skipped; both
  # defaults are shown so the link is visible. NULL turns either off.
  poor_absolute_fit_col = "poor_absolute_fit",
  best_identity_col     = "best_identity",
  # The review is BLIND to this pipeline's own numbers by default: the
  # posterior, the occurrence prior, the GBIF distance and the iNaturalist
  # fields are all NULL unless named, so none of them reaches the prompt. A
  # review shown the pipeline's confidence cannot contradict it independently,
  # and one shown a taxon's GBIF distance cannot catch an error in the
  # occurrence data. What it IS shown is the DNA evidence -- the two arguments
  # just above among them -- and the study's own design. See
  # ?review_assignments, "What the review is shown, and what it is not".
  # consensus_provenance (default TRUE): a call that landed on an UNREFERENCED
  # row gets one note, "named taxon has NO reference sequence". The scope the
  # name came from and how many species the records held there are NOT sent --
  # both report what the occurrence records contain. It reads
  # posterior_consensus()'s consensus_hypothesis_type.
  consensus_provenance  = TRUE,
  # model_label: names the model behind llm_fn in the cache key, so a verdict
  # from one model is never served to a call asking another. NULL derives it
  # from options("TaxaID.provider") and llm_fn; name it yourself when you
  # compare two models from ONE provider.
  model_label    = NULL,
  # Abort rather than export a silently short species list. An LLM review can
  # parse cleanly, return the right number of objects, and still OMIT specific
  # taxa -- consistently the long compound slash labels, i.e. the hardest
  # rows. Those get NA in every llm_ column, and any export filter that tests
  # `llm_* != "unlikely"` DISCARDS NA, so the observation would leave the final
  # species list without a word. Measured on a real PtConception 12S run:
  # 20 observations across 3 plausible local fishes, gone.
  #
  # Note which filter that is. This script and the template drop nothing on an
  # LLM VERDICT -- the template's only subsetting is by expert_excluded, a
  # human decision and empty by default -- so an llm_* filter is one a reader
  # may add downstream of here, not one above.
  # review_assignments() now re-asks for omitted taxa; "error" makes any
  # residue that survives the re-ask stop the run rather than reach such a
  # filter at all.
  on_unreviewed  = "error"
)
message("Reviewed ", nrow(reviewed), " assignments")

# --- Multi-site studies: per-site geography ----------------------------------
# This path reviews one site, so it leaves review_assignments(sites=) unset.
# A study with several sites passes sites = <site table> and site_col =, and
# gets a per-taxon, per-site verdict in llm_geographic_plausibility_site plus
# the parsed rules in attr(reviewed, "geographic_by_site").
#
# Read `how` in that attribute before trusting a per-site verdict. One case
# needs handling outside the package: a rule can name a single latitude bound
# on the wrong side, so a southern range limit written as lat_max puts every
# northern site outside the band. The taxon's study-wide verdict then says
# "likely" while its per-site verdict says "unlikely" everywhere it was
# actually detected. TaxaFlag holds no occurrence data and cannot tell that
# from a correct exclusion, so the check belongs here, where the records and
# the site table already are: count distinct record locations near the site,
# and where there are enough, screen on the study-wide verdict instead.
# Keep the reviewer's own column untouched and write the adjusted verdict to
# its own column, so a report can still say what it did. The worked pattern,
# with the NA-versus-0 rule and the row-count assertion, is in TaxaFlag's
# README under "Overriding a per-site verdict with local records".

# Always check: attributes do NOT survive a dplyr verb, so read this before
# any join or mutate.
if (length(attr(reviewed, "unreviewed_taxa"))) {
  message("  !! unreviewed: ",
          paste(attr(reviewed, "unreviewed_taxa"), collapse = ", "))
}
# --- FLAG, do not drop -------------------------------------------------------
# The review is a judgement: its verdicts can differ between runs on identical
# input, so it must not remove rows from the products. It only FLAGS. The four
# ratings stay as columns, and llm_review_flag is TRUE where any of them reads
# "unlikely" (contamination risk "high"). Every row stays in `reviewed`.
reviewed$llm_review_flag <-
  reviewed$llm_habitat_plausibility    %in% "unlikely" |
  reviewed$llm_geographic_plausibility %in% "unlikely" |
  reviewed$llm_scope_plausibility      %in% "unlikely" |
  reviewed$llm_contamination_risk      %in% "high"

# Expert decisions are DATA, not code: lists of observation_id values that a
# human reviewer decided. Leave both empty until someone has looked at the
# flagged rows (print them with the call below).
#   EXPERT_KEEP_IDS     -- flagged by the LLM, but the reviewer keeps the call.
#   EXPERT_EXCLUDE_IDS  -- withheld from the products, whatever the LLM said.
# Record the reason for each decision beside the list, in a file the run reads.
EXPERT_KEEP_IDS    <- character(0)
EXPERT_EXCLUDE_IDS <- character(0)
unknown_ids <- setdiff(c(EXPERT_KEEP_IDS, EXPERT_EXCLUDE_IDS), reviewed$observation_id)
if (length(unknown_ids)) {
  stop("Expert decision(s) name observation_id(s) not in this run: ",
       paste(unknown_ids, collapse = ", "), call. = FALSE)
}
reviewed$expert_keep      <- reviewed$observation_id %in% EXPERT_KEEP_IDS
reviewed$expert_excluded  <- reviewed$observation_id %in% EXPERT_EXCLUDE_IDS
# An LLM flag stands unless the reviewer keeps the call.
reviewed$review_flag_stands <- reviewed$llm_review_flag & !reviewed$expert_keep
message("LLM-flagged: ", sum(reviewed$llm_review_flag, na.rm = TRUE),
        " (", sum(reviewed$review_flag_stands, na.rm = TRUE), " stand after expert keeps); ",
        "expert-excluded: ", sum(reviewed$expert_excluded))
# To inspect: reviewed[reviewed$review_flag_stands,
#   c("observation_id", "consensus_taxon", "llm_habitat_plausibility",
#     "llm_geographic_plausibility", "llm_scope_plausibility",
#     "llm_contamination_risk", "review_comment")]

# Products carry the flag columns; only expert exclusions leave them.
reviewed_products <- reviewed[!reviewed$expert_excluded, , drop = FALSE]
reviewed
