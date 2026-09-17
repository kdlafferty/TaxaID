# WoRMS marine filter (GBIF stays the occurrence source)

**Status: DELIVERABLE 1 BUILT 2026-09-15 (Opus 5). DELIVERABLE 2 STILL OPEN.**
Scoped 2026-09-15 from real measurements made while building the PtConception
nearshore species list; NARROWED 2026-09-15 (later) — see "Scope change" below.

- **Built:** the function, as `TaxaTools::fetch_worms_attributes()` — *not*
  `TaxaFetch::`. It is a by-name attribute lookup in the shape of
  `verify_taxon_names()` / `change_backbone()`, not an occurrence fetch;
  TaxaFetch's DESCRIPTION scopes that package to occurrence data and TaxaTools'
  already names WoRMS as a backbone. `TaxaTools/R/worms_attributes.R`,
  `tests/testthat/test-worms_attributes.R` (105 tests incl. live WoRMS),
  `taxatools_clear_cache()` extended, `EXTERNAL_DATA_SOURCES.md` row added.
  devtools::test() 1097/0, check() 0/0/0. Not reinstalled, not committed.
- **Still open:** deliverable 2 — no workflow wires the filter in yet — and
  every one of the four "MUST VALIDATE BEFORE TRUSTING" steps below. Nothing has
  been run against a real match object.

**THREE CLAIMS BELOW WERE CHECKED AGAINST THE LIVE API AND ARE WRONG. Do not
build on them:**

1. *"`Cervus elaphus`, `Homo sapiens`, `Sus scrofa`, `Bos taurus`,
   `Gallus gallus` are not in the register at all. Absence is the filter."*
   FALSE for four of the five, verified 2026-09-15: *Homo sapiens* (AphiaID
   1455977), *Sus scrofa* (1469456), *Bos taurus* (1506698) and *Gallus gallus*
   (1463738) are all in WoRMS. Only *Cervus elaphus* is genuinely absent. The
   `is_marine | is_brackish` rule still cuts all of them — on their FLAGS
   (marine 0 or null, terrestrial 1), not on absence. The rule is safe; the
   stated mechanism is not, and it has already moved once.
2. *`wrims` is WoRMS payload.* It is not. That column came from the OBIS
   checklist, which this document declines. WoRMS exposes no equivalent single
   field: checked 2026-09-15 against the 42 public `AphiaAttributeKeys` (no
   introduced/alien key) and against *Carcinus maenas*, a flagship WRiMS
   species, which carries none. It is now DERIVED from
   `AphiaDistributionsByAphiaID` — `establishmentMeans == "Alien"` — which
   is what WRiMS is built from. ~70 KB per taxon, so it is opt-in.
3. *"`scope_filter_esvs()` ... takes a per-taxon logical vector, so a WoRMS
   verdict drops straight in with no change."* It takes `group` (character) plus
   `keep_groups`. Adapting is one line — `group = ifelse(keep, "marine",
   "out_of_scope")`, `keep_groups = "marine"` — but it is not a no-op.

Confirmed exactly as written: every shorebird and diadromous verdict in the
table below, `ncbi_id` availability, and `Teleostei` as a working class
(AphiaID 293496).

**One behaviour this document did not anticipate:** WoRMS sends `null`, not `0`,
for a realm it has not assessed (*Macrocystis pyrifera* is marine = 1 with the
other three null). Those are different claims, so the four flags are returned as
logicals WITH `NA` and a separate never-`NA` `marine_scope` column is what a
filter reads. Relatedly, *Dreissena polymorpha* (marine 0, brackish 1,
freshwater 1) is KEPT: the brackish clause that diadromous fish need also
retains brackish-tolerant freshwater invasives.

**ONE deliverable now, not three:**

1. ~~**`TaxaFetch::fetch_worms_attributes()`**~~ — a by-name WoRMS taxon-attribute
   lookup. BUILT 2026-09-15 as **`TaxaTools::fetch_worms_attributes()`**; see the
   status block above for why the package differs.
2. A **marine scope filter** in the workflows that uses it to cut non-marine
   candidates *early*, before the occurrence fetch and prior stages.

## Scope change, 2026-09-15 (user decision, evidence below)

The original version of this document proposed three functions —
`fetch_worms_attributes()`, `fetch_obis_checklist()` and
`fetch_obis_occurrences()`. **The two OBIS functions are declined.** GBIF
remains the single occurrence source for every workflow, marine and freshwater
alike, and WoRMS becomes a taxon-attribute lookup rather than an alternative
data pipeline. See "Considered and declined" for the reasons, which are mostly
this document's own measurements.

This removes the original's stated honest limit — *"marine-only means two
source paths forever"* — entirely. There is now one source path.

## Why the filter

The binding constraint on multi-site, multi-marker analyses is rows, sequences
and taxonomic breadth carried through the pipeline. At PtConception, **37% of
12S taxa holding priors are non-marine** (428 marine / 151 terrestrial / 87
freshwater / 15 estuarine of 681) and the 18S occurrence pool holds **63,613
terrestrial records** across 498 terrestrial taxa. For a marine study every one
of those is fetched, habitat-classified, kernel-priced and carried to consensus
in order to be down-weighted at the end. Cutting them at the *candidate* stage
removes that work entirely.

**This is a different axis from the taxonomic scope filter, and they compose.**
`CaliforniaIntertidal/scope_classifier.R` cuts on TAXONOMY (is this a fish /
macroinvertebrate / macroalga?) and deliberately does not touch habitat — its
header says so explicitly. WoRMS is the HABITAT axis done properly. Neither
substitutes for the other, and for an intertidal study the gap each leaves is
real: the taxonomic filter drops insects and birds but **keeps terrestrial
snails, freshwater mussels, freshwater annelids and freshwater algae**, because
those are taxonomically `Gastropoda` / `Bivalvia` / `Polychaeta` /
`Ulvophyceae` and land in `macroinvertebrates` or `macroalgae` regardless of
where they live. WoRMS cuts those; the taxonomic filter cannot. Conversely
WoRMS cannot cut a marine copepod, and the taxonomic filter does.

## The evidence (measured 2026-09-15, not assumed)

**WoRMS solves the failure the LLM habitat scheme cannot.** The four-category
scheme (Marine/Estuarine/Freshwater/Terrestrial) forces a single choice, so
intertidal foragers that stand on rock come back Terrestrial. Measured verdicts
from `TaxaHabitat::build_habitat_lookup()` vs WoRMS:

| taxon | LLM verdict | WoRMS |
|---|---|---|
| *Haematopus bachmani* (black oystercatcher) | Terrestrial (M 0.40 / T 0.50) | **marine=Y**, terrestrial=Y |
| *Calidris alba* (sanderling) | Terrestrial (M 0.20 / T 0.50) | **marine=Y**, terrestrial=Y |
| *Arenaria melanocephala* (black turnstone) | Terrestrial (M 0.30 / T 0.60) | **marine=Y**, terrestrial=Y |
| *Numenius phaeopus* (whimbrel) | Terrestrial | **marine=Y**, terrestrial=Y |
| *Uria aalge* (common murre) | Marine (M 0.90) | marine=Y |

WoRMS is **multi-label**, not exclusive — the oystercatcher is marine AND
terrestrial. That is the representation the scheme could not express, and it is
why the LLM had to pick wrong. 381 of 578 birds were called Terrestrial by the
LLM; only ~100 survived, against 173 in genuinely marine/shore orders.

**Diadromous species are handled explicitly.** *Oncorhynchus mykiss* and
*Alosa sapidissima* both return marine=Y, brackish=Y, freshwater=Y,
terrestrial=**FALSE**. So the filter rule is **keep if `is_marine` OR
`is_brackish`** — never "drop if terrestrial", which would cut every shorebird.

**The taxa to cut are simply absent.** *Cervus elaphus*, *Homo sapiens*,
*Sus scrofa*, *Bos taurus*, *Gallus gallus* are not in the register at all.
Absence is the filter; there is no threshold to tune.

> **CORRECTED 2026-09-15 against the live API — this paragraph is wrong for
> four of its five examples.** *Homo sapiens* (AphiaID 1455977), *Sus scrofa*
> (1469456), *Bos taurus* (1506698) and *Gallus gallus* (1463738) ARE in WoRMS;
> only *Cervus elaphus* is absent. They are cut on their flags (marine 0 or
> null, terrestrial 1), not on absence. The conclusion — no threshold to tune
> — survives; the mechanism does not, and a filter written to rely on absence
> is resting on something that has already changed once.

**Other WoRMS payload, measured on the PtCon polygon (2,453 spp).** These are
WoRMS *attributes*, retained in full by this narrowing — none of them came from
OBIS: `aphia_id` (joins Joe Craine's Tier 1 inventory directly), **`ncbi_id`
for 1,614 species**, `wrims` introduced-species flag on 129 species (overlaps
the GISD invasive-watch work), 902 vernacular names, and **`Teleostei` as a
working class** where GBIF's backbone has no occurrence-bearing node for
ray-finned fishes at all (see `reference_gbif_query_gotchas`).

**`ncbi_id` is a second, independent reason to build this.** It is a *curated*
GBIF↔NCBI crosswalk. The ecosystem currently computes that crosswalk live via
`verify_taxon_names(backbone_id = 4)` / `TaxaTools::change_backbone()`, which
costs API calls and does not always resolve: on the 2026-09-13 scope-classifier
run, **33 of 803 higher-rank names got no GBIF match**, each leaving rows to
fall back to source taxonomy. A curated crosswalk directly improves the
harmonisation step the taxonomic scope filter depends on.

## Deliverable — `TaxaFetch::fetch_worms_attributes()`

- **`fetch_worms_attributes(taxon_names, cache_dir =)`** — query WoRMS **by
  name** (the `worrms` package / WoRMS REST API), NOT via an OBIS polygon
  checklist. Returns `aphia_id`, `is_marine`, `is_brackish`, `is_freshwater`,
  `is_terrestrial`, `ncbi_id`, `accepted_name`, `taxonomic_status`, `wrims`.
  Content-keyed cache like `build_habitat_lookup()`; these are curated
  attributes, so unlike an LLM verdict they do not drift between runs.
  (As built: `wrims` is DERIVED, not a WoRMS field — see correction 2 above.)
  **Do not filter on occurrence presence** — that conflates marine status with
  local residency and would cut real marine taxa unrecorded near the site.

## How to apply it — ESV-LEVEL, NOT TAXON-LEVEL

The original draft wrote the cut as
`match_obj -> candidate taxa -> keep is_marine | is_brackish -> families`.
That is a **taxon-level** cut, and it is the thing its own "MUST VALIDATE"
section is afraid of: it strips candidates from inside an ESV, forcing the read
onto whichever candidates survive.

Apply the same WoRMS verdict at **ESV level** instead — drop an ESV only when
**no** candidate is marine or brackish — and that failure becomes structurally
impossible rather than something to validate against. An ESV with any marine
candidate keeps its whole candidate set, out-of-scope competitors included.

This is exactly the rule `CaliforniaIntertidal/scope_classifier.R`'s
`scope_filter_esvs()` already implements, and it takes a per-taxon logical
vector, so a WoRMS verdict drops straight in with no change. The equivalent
comparison was measured there on the real PtCon 18S match object
(2026-09-15): any-in-scope kept 1,592 ESVs; collapsing to an LCA first kept
2,103 — **worse**, because when candidates disagree the LCA climbs to the root,
and 518 of the 526 ESVs it rescued had no kingdom/phylum/class at all and fell
through the catch-all. Scope is a property of the candidate SET; summarising
first throws away the information the question needs.

```
match_obj
  -> fetch_worms_attributes(unique candidate taxa)
  -> per-candidate logical: is_marine | is_brackish
  -> scope_filter_esvs(..., keep = that logical)     <- ESV-level cut
  -> families/keys for the GBIF occurrence fetch (now much smaller)
  -> priors, likelihoods, consensus
```

**FLAG AND SET ASIDE — do not silently discard.** The 12S pipeline report
carries **10,218 `questionable_lab_contaminant` flags**; human/pig/cow/chicken
DNA is a lab-contamination signal, and the consensus-scope
unprecedented/unexpected counts are a data-quality diagnostic (the 2026-09-14
run moved unprecedented 10 → 73 and unexpected 116 → 54). Cut non-marine taxa
from the prior/likelihood path but **retain the rows and counts** so those
signals survive. A `scope_excluded` table plus a line in the pipeline report.

## MUST VALIDATE BEFORE TRUSTING

The headline risk — *an unreferenced marine species whose best BLAST match is a
terrestrial congener gets cut on the congener's status, silently losing a real
detection* — is largely defused by the ESV-level application above, since such
an ESV keeps its marine candidates. Validate anyway:

1. Run the filter against the real PtCon 12S and 18S match objects and list
   **exactly what it removes**, by taxon, with the match identity.
2. Check every removal against the final consensus from the current runs —
   nothing that reached consensus should be cut.
3. Check the unreferenced/expanded hypotheses specifically
   (`expand_unreferenced_hypotheses()`, `restore_suppressed_candidates()`),
   since those are where a marine species is represented by a referenced
   relative.
4. Quantify the saving: candidates cut, GBIF keys avoided, records not fetched.
   Report it **on top of** the taxonomic scope filter, not instead of it — the
   two cut on orthogonal axes and the combined figure is the one that matters.

## Considered and declined — the two OBIS functions

**`fetch_obis_occurrences()` — declined.** This document's own measurements make
the case: OBIS is **not independent of GBIF** (log-correlation of per-species
counts for shared algal taxa is **0.933** — largely the same records under WoRMS
names, so agreement is not replication); it is **thinner** (2,453 species vs
3,027 from GBIF on the same polygon; macroalgae 131 vs 292); and it is
pagination-bound at ~380 records/s, explicitly *"not a replacement for GBIF's
async download at bulk"*.

Its one unique contribution was **78.9% complete measured `depth`**, offered as
"a different and arguably better quantity than the ETOPO seafloor lookup the
depth covariate uses now". **That argument is much weaker than it looked:**

> **GBIF already downloads depth.** Verified 2026-09-15 against a real cached
> zip (`PtConception/cache_gbif_global/0012530-260903145123482.zip`): GBIF's
> SIMPLE_CSV has **50 columns**, including `elevation` (26),
> `elevationAccuracy` (27), **`depth` (28)** and `depthAccuracy` (29).
> `download_gbif_occurrences()` drops them because its `select_cols` default
> names ~35 columns and depth is not among them — and per that argument's own
> roxygen, `select_cols` is applied **at import time and does not affect the
> cache**. So the depth data is *already sitting in the zips on disk*. Adding
> `"depth"` to `select_cols` recovers it with no re-download and no new data
> source.

So the depth question is a one-line change plus an experiment, not a second
data pipeline. Completeness is the open part: **21.5% of a 400,000-row sample**
of the cached GBIF data carried a depth value, against OBIS's 78.9%. Treat 21.5%
as a FLOOR, not an estimate — that sample came from `cache_gbif_global`, the
global refetch of rare-in-bbox species, a mostly terrestrial/museum population
where depth is rarely recorded. A marine-scoped nearshore query should score
higher; nobody has measured it.

**Next step on depth, if wanted (small, independent of everything above):** add
`"depth"` to `select_cols`, measure real completeness on the nearshore polygon,
then test measured-depth against the current ETOPO `compute_shore_depth()`
covariate with `calibrate_kernel_bandwidth()`. The kernel treats a missing
covariate neutrally (`w_cov = 1`), so partial coverage is tolerable; the
question is whether partial measured depth beats full modelled depth. The
existing ETOPO path is validated (interior optimum at 250 m in both PtCon
markers) and is not broken.

**`fetch_obis_checklist()` — declined.** One row per taxon with a `records`
count, ~34 s for the PtCon polygon (11,826 taxa). Redundant: GBIF already
supplies this, and the marine filter now comes from WoRMS by name rather than
from a polygon checklist.

Both remain available in the working reference implementation if ever wanted:
`~/My Drive/Rscripts/eDNA/PtConception/PtCon_nearshore_OBIS_fetch.R`, methods in
`PtCon_nearshore_OBIS_METHODS.md`.

## Honest limits

- **WoRMS coverage is not total.** Absence is the filter for livestock and
  humans, which is what makes it clean — but absence is also how a genuinely
  marine taxon missing from the register would be cut. Validation step 1 exists
  to catch that.
- **Algae need a phycological flora regardless.** GBIF gave 292 macroalgal
  species on the PtCon polygon and OBIS 131; neither is a flora.
- **The OBIS list shipped with no date filter** while the GBIF list is
  1995-2026 — relevant only if the reference implementation is revisited.

## Related

`reference_gbif_query_gotchas`, `reference_ne_coastline_missing_islands`,
`project_ptcon_nearshore_species_list_2026_09_15`,
`project_scope_classifier_sampling_group_gaps`,
`project_california_intertidal_multi_marker_2026_09_13` memories;
`ecosystem_docs/EXTERNAL_DATA_SOURCES.md` (has no WoRMS row — add one; an OBIS
row is no longer needed).

Superseded draft kept as
`REENTRY_PROMPT_obis_marine_workflow.md.bak_pre_worms_narrowing_20260915`.
