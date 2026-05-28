# TaxaFetch Session Notes Archive
# Sessions 26–80. Current sessions live in TaxaFetch/CLAUDE.md.

**Session 26 (2026-03-24)**
- Added `call_gemini_api()`, `call_openai_api()`, `call_ollama_api()`
- `prompt_anthropic_api` renamed to `prompt_api`; `llm_fn` param added

**Session 27 (2026-03-26)**
- CLAUDE.md restructured: ecosystem context in `TaxaID/CLAUDE.md`; this file is package-specific
- pdf_characterize_v2.R → pdf_characterize.R; pdf_text_v2.R → pdf_text.R (old v1 deleted)

**Session 28 (2026-03-26)**
- LLM provider functions (`call_*_api`, `prompt_api`, `prompt_manual`, `read_llm_response`)
  moved to TaxaTools/R/llm_api_utils.R
- Habitat functions moved to TaxaHabitat (new package)
- `parse_hierarchical_habitat_response` moved to TaxaHabitat/R/parse_habitat_response.R
- DESCRIPTION: removed sf, terra, leaflet, shiny, miniUI, rnaturalearth, rnaturalearthdata;
  added note these are now in TaxaHabitat
- `screen_pdf_structure()` in pdf_characterize.R: added `@importFrom TaxaTools call_anthropic_api`

**Session 65 (2026-05-02)**
- `report_fetch()` added to `R/report_fetch.R`: summarizes data acquisition (sources, bbox,
  year range, citations from `bibliographicCitation` column). Returns `report_section` S3
  object for `TaxaTools::assemble_report()`.
- `report_params` attribute added to `stack_occurrences()` output: attaches `citations`
  (unique `bibliographicCitation`), `n_records`, `n_sources`.
- `report_params` attribute added to `fetch_gbif_occurrences()` output: attaches `source`,
  `n_keys`, `n_records`, `geometry` (WKT), `year_range`.

**Session 66 (2026-05-03)**
- LaTeX `\$` fix in `search_literature.Rd` (escaped dollar in roxygen source).
- Dead code removed; stale `@seealso` refs updated.

**Session 67 (2026-05-04)**
- `llm_fn` default in `screen_pdf_structure()` updated to
  `getOption("TaxaID.llm_fn", call_anthropic_api)`.

**Session 72 (2026-05-11)**
- `.recover_higherrank()` internal function added: when `name_backbone()` returns HIGHERRANK
  with rank jump >1 level, falls back to `name_lookup()` with rank constraint. Rank-agnostic.

**Session 79 (2026-05-20)**
- `sample_id` → `observation_id` ecosystem rename: TaxaFetch does not use this column;
  no source changes required.

**Session 80 (2026-05-20)**
- GitHub public monorepo created at github.com/kdlafferty/TaxaID; no package-specific changes.
