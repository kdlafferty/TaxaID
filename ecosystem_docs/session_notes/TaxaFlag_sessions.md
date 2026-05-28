# TaxaFlag Session Notes Archive
# Sessions 60–74. Current sessions live in TaxaFlag/CLAUDE.md.

**Session 60 (2026-04-28)**
- Package scaffold created (DESCRIPTION, NAMESPACE, CLAUDE.md, CITATION, tests, etc.)
- Design plan finalized: 6 exported functions + 2 internal helpers
- Key decisions: single `flag_contaminant()` with `contaminant_type` param;
  consensus_df must have `n_reads` pre-joined; `flag_allochthonous()` reuses
  TaxaAssign `build_context()` output

**Session 62 (2026-04-30)**
- `review_assignments()` designed: LLM expert review producing 8 structured columns
- `flag_allochthonous()` and `flag_taxonomic_scope()` dropped -- absorbed into
  `review_assignments()` for efficiency (one LLM call covers all dimensions)
- `review_alternatives` vs `review_lower_hypotheses` distinction clarified:
  alternatives = wrong taxon, plausible relative; lower = right group, finer resolution
- Implementation order: data-driven flaggers first (baseline for LLM validation),
  then `review_assignments()`, then wrapper

**Session 63 (2026-04-30)**
- `flag_contaminant()` + `.compute_contaminant_scores()` implemented and tested (17 tests)
  - `blank_samples` renamed to `control_samples` (supports positive controls)
  - Returns per-taxon summary, not joined to input
- `flag_handler()` + `.parse_datetimes()` implemented and tested (16 tests)
  - Placeholder function for camera trap handler artifacts
  - Auto-parses datetime formats; per-group min/max; linear scoring
- `review_assignments()` + `.build_review_prompt()` + `.parse_review_response()` +
  `.normalise_context()` implemented and tested (14 tests)
  - Accepts build_context() or named list for context
  - Batched LLM calls; graceful fallback on failure
  - Tested against real Palmyra Atoll data via workflow script
- `combine_flags()` dropped -- users should weight flags themselves
- `flag_detections()` dropped -- wrapper that guesses parameters is unhelpful
- Quality audit: removed unused `rlang` import; replaced `%||%` with inline
  null check; removed `VignetteBuilder` (no vignette yet); updated DESCRIPTION
  text; fixed non-ASCII em-dashes in prompt text
- devtools::check(): 0 errors, 0 warnings, 1 note (timestamp)

**Session 66 (2026-05-03)**
- `stop()` missing `sprintf()` in `review_assignments()` fixed
- TaxaTools moved from Suggests to Imports (used unconditionally)
- Vignette parameter names corrected (`data→df`, `count_col→reads_col`, `window_minutes→interval_minutes`)

**Session 74 (2026-05-15)**
- `review_assignments()` truncation fix: `taxa_per_call` default reduced from 30 to 15.
  With 8 JSON fields per taxon, 30 taxa generate ~10K char responses that exceed
  `call_anthropic_api()`'s 3000 `max_tokens` default, causing mid-JSON truncation.
  15 taxa stays well within limits (~1500-2250 tokens).
- `.recover_truncated_json()` added: when truncation occurs, walks backward through
  `}` positions to find the last complete JSON object, closes the array, and parses
  the recoverable portion. Recovered taxa get real reviews; only omitted taxa get NA defaults.
- `.parse_review_response()` multi-strategy parser: (1) strip markdown fences (lazy `.*?`
  regex), (2) direct parse, (3) bracket extraction, (4) truncated recovery.
- Fence-stripping regex fixed: greedy `(?s).*``` ` matched the LAST triple-backtick
  (consuming the entire response); corrected to lazy `(?s).*?``` ` to match the FIRST.
  Same PCRE footgun documented in ecosystem CLAUDE.md Session 33.
- TaxaWizard script continuation mode: `.find_existing_script()` scoped to today's date
  only; `.append_to_script()` inserts new steps before footer; handles both `total_steps`
  variable and hardcoded step counts. `is_continuation` flag propagated to parameterize prompt.
- TaxaWizard UI: CSS flex layout anchors messages near input box; Enter-to-send via JS keydown handler.
- 3 match-input snippets (`match_to_consensus_score/llm/bayes`) gain `sample_id`/`score` column rename block.
