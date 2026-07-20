# Reentry prompt: domestic/commensal/food-species priors

**From:** the same design conversation as
`REENTRY_PROMPT_degraded_species_likelihood_thresholds.md` (2026-07-17-ish,
grown out of the real PtConception 12S "obvious errors" edge-case review —
see `[[project_edge_case_error_taxa_design]]` for the full 14-taxa list and
mechanisms). Split out at the user's request into its own chat since it's a
genuinely separate problem from the degradation/likelihood-threshold thread.

## The problem

Humans and domestic/commensal species systematically receive artificially
low ("global floor") occurrence priors from GBIF/iNat-derived pipelines, even
when genuinely common contamination sources at a site — GBIF's standard
occurrence indexing structurally excludes/under-indexes captive/cultivated/
domestic organisms. Full original write-up:
`[[project_taxaflag_domestic_species_floor_note]]` (memory), which this
prompt extends — **read that memory first**, it has the original 2026-07-03
camera-trap finding (`Felis catus`/`Canis familiaris` both getting the same
~0.00006 floor prior as a geographically-impossible candidate) and the
existing partial fix.

## What already exists (Session 149, don't rebuild)

`TaxaFlag::add_posthoc_assessment(domestic_taxa=, domestic_prior_source=)` —
opt-in, re-labels a strong-likelihood + database-floor-tier domestic call as
`"domestic_prior_caveat"`. **This is post-hoc relabeling only, not a real
prior change** — the gap this reentry prompt is about is upstream of that, in
TaxaExpect itself.

## Important corrected finding from this session — read before assuming the fix is about sequence resolution

Checked directly against real PtConception 12S data: **`Homo sapiens` is
already well-referenced and resolves essentially perfectly** — 86 of 89
primate-genus-hitting ESVs correctly resolve to `Homo sapiens` at
`consensus_posterior` = 1.0 (min=median=max=1 across all 86), despite zero
`taxaexpect_priors` rows for `Homo sapiens` (GBIF excludes human records, as
expected). **So the domestic-prior fix's value is NOT primarily about fixing
sequence-level resolution** — that already works fine when the match is
strong, prior or no prior. Its real value is:
(a) a categorical **domestic flag** for systematic downstream handling
(reporting, exclusion from biodiversity summaries, routing to review)
regardless of the numeric prior magnitude, and
(b) genuinely helps the *weaker*/degraded match cases (e.g. the one real
Hylobatidae ESV that failed to resolve to `Homo sapiens`, landing on gibbon
references at only ~81% identity instead), and
(c) does **not** help cross-genus gaps like `Bison bison`/`Bos taurus` at
all — `restore_suppressed_candidates()` only pulls same-genus congeners, and
`Bos taurus` was a real candidate genus elsewhere in this exact dataset but
never for the Bison-anchored ESV specifically. A prior fix can't repair that;
it would need a different, not-yet-designed cross-genus/related-genus
candidate-expansion mechanism.

## Design direction agreed in principle (not yet built)

A new TaxaExpect-level fix: a **non-GBIF occurrence data source** for
domestic/commensal/food species, generating genuine non-zero priors, plus a
boolean/categorical column on the priors table for downstream systematic
handling (mirrors this ecosystem's existing `habitat_col`-style NULL-able
categorical column pattern).

**Three separable input channels, user's own framing (most recent, supersedes
earlier iNat-for-everything idea):**

1. **`domestic_animal_taxa`** — a user-supplied vector, pre-populated with
   common defaults (dog, cat, cow, sheep, pig, chicken, horse, `Homo sapiens`,
   etc. — **not yet drafted**, offered and the user hadn't responded to that
   offer when this thread was split out).
2. **`domestic_plant_taxa`** — sourced via **iNaturalist "casual" grade**
   (explicitly retains captive/cultivated records that GBIF-standard
   filtering and this ecosystem's own `filter_gbif_quality()` exclude) —
   user explicitly likes this specifically for domestic plants, given the
   combinatorial diversity of cultivated/ornamental/garden species a fixed
   vector can't practically enumerate. `TaxaFetch::check_inat_range()` is the
   existing infrastructure most likely to extend for this — not yet
   confirmed as the right building block, just the obvious candidate.
3. **`food_species_taxa`** (new this session) — a separate user-supplied
   vector for human food/crop species (tomato, onion, etc.) — a genuinely
   distinct contamination category from "domestic" (food-handling/lab-bench/
   sample-processing contamination, not pet/livestock/ranch runoff). Marker
   relevance: essentially irrelevant for 12S (MiFish is vertebrate-specific,
   won't amplify plant DNA at all) but directly relevant for this
   ecosystem's 18S workflows, which are plant/algae-inclusive.

## Real data already checked

User pointed at two real files:
`/Users/lafferty/My Drive/Stats and Data/USGS/Fox Parasites/IntestinalContents/Cultivated_plants.csv`
(651 rows, bare species-name column only) and
`Food_Plants_Taxonomy.csv` (597 rows, full resolved taxonomy —
`id,submitted_name,Corrected_name,species,genus,family,order,class,phylum,kingdom,taxon_name,taxon_name_rank`,
already matching this ecosystem's own naming/rank-system conventions closely
enough that it may itself be output from a `TaxaTools`-style resolution pass).

**Checked and found: these two files are mostly the SAME underlying list at
two different processing stages**, not two genuinely distinct categories —
503/613 and 503/591 overlap; the "differences" are mostly formatting
artifacts (`"Tulipa spp."` vs `"Tulipa"`, `"Dahlia spp."` vs `"Dahlia"`), not
real content differences. **So these two files alone do not give a clean
"ornamental/cultivated (non-food) vs. food-crop" split** — if the user wants
that distinction preserved, it needs a different/additional source, not just
these two files.

## Open design question — not resolved, needs the user's call

**Separate lists per category vs. one augmented table with a `type` column.**
My (unconfirmed) lean: single augmented table with a `type`/category column —
avoids exactly the kind of accidental list drift just found between the two
CSV files above, still supports `filter(type == "domestic_animal")`-style
downstream subsetting, and matches the `habitat_col` precedent already used
elsewhere in this ecosystem. User had not yet confirmed or pushed back on
this when the thread was split.

## Not yet done — nothing has been implemented

- No default `domestic_animal_taxa` or `food_species_taxa` vector drafted.
- No decision on which TaxaExpect function gains the new non-GBIF prior
  source, or its exact signature/placement in the pipeline.
- No decision on the exact column name/type for the domestic/food flag on
  the priors table.
- The iNat-casual-grade mechanism for `domestic_plant_taxa` is a proposed
  direction only, not scoped or built.

## Where to start re-reading

1. `[[project_taxaflag_domestic_species_floor_note]]` (memory) — the original
   finding and the existing partial fix; this prompt's own "corrected
   finding" section above has been folded into that memory already.
2. `[[project_edge_case_error_taxa_design]]` (memory) — the broader 14-taxa
   review this grew out of.
3. `TaxaFlag::add_posthoc_assessment()`'s Session 149 note (`TaxaFlag/CLAUDE.md`)
   — the existing partial mechanism, don't duplicate it.
4. `TaxaFetch::check_inat_range()` — likely building block for the domestic-plant
   iNat-casual-grade source.
5. The two real CSV files above, if/when a genuine food-vs-ornamental split
   is needed beyond what they currently provide.
