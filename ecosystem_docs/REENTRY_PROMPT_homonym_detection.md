# REENTRY: homonym detection and tracking in TaxaTools

**Status: BUILT AND LIVE-VERIFIED on branch `homonym-detection`, NOT merged to main,
NOT reinstalled ecosystem-wide -- see the "Resolved" section below for what shipped,
what was verified against real NCBI data, and what remains deliberately out of scope.
Opened 2026-09-22 from the California Intertidal thread, which found the defect in
production and measured it. The maintainer's call: "TaxaTools needs a way to detect
and track homonyms. It is a real weakness. And now is the time to fix it."**

Freeze note: TaxaID is in the 1.0 release freeze and a separate session owns
merge/push/reinstall. Design and measurement are welcome here; a new export needs
the maintainer's yes, and nothing ships without their word.

## The defect, stated exactly

A taxon name is not a key. NCBI (and GBIF, and WoRMS) can hold SEVERAL nodes with
the same name in different lineages, and a name-based query silently resolves to
whichever one the service prefers -- which, for an `[ORGN]` search, is any node in
the lineage, so a higher-rank homonym wins on volume.

`TaxaLikely::fetch_ncbi_reference_sequences()` queries NCBI BY NAME with no
lineage constraint. Measured live 2026-09-22:

    taxid 1261581   Vertebrata   rank=genus   division=red algae      <- wanted
    taxid 7742      Vertebrata   rank=clade   division=vertebrates    <- returned

    Vertebrata[ORGN]  AND COI AND 300:900[SLEN]  ->  519,463 records
    txid1261581[ORGN] AND COI AND 300:900[SLEN]  ->      106 records

The red alga *Vertebrata* (Rhodophyta | Florideophyceae | Ceramiales |
Rhodomelaceae; 10 species, 356 rows in the real COI match object) pulled
**306,181 vertebrate sequences** -- top species *Carollia perspicillata* (a bat),
*Rattus tanezumi*, *Artibeus lituratus*, *Prionace glauca* (blue shark),
*Sorex cinereus*, *Nanorana parkeri*.

## Two harms, and the second is worse

1. COST. 306,181 sequences = 28% of a 1,100,030-sequence COI reference set.
   `build_sequence_matrix()` then managed 2 of 5,551 genus alignments in 238
   minutes, because alignment is superlinear in sequence count. The run was killed.
2. MODEL CORRUPTION, which is worse than the cost. CORRECTED 2026-09-22 after
   testing the guard against the real cache: the query DOES return the correct
   red-algal sequences -- 68 Rhodomelaceae rows -- but they are 0.02% of the
   306,181 returned. They are not lost; they are DROWNED. That is the more
   damaging outcome, because `build_sequence_matrix()` and
   `train_likelihood_model()` then treat 306,113 bat, rat, shark and frog
   sequences as CONGENERS of a red alga, and H2/H3 model exactly that:
   between-species divergence within a genus. The fitted congener-divergence
   distribution for Vertebrata would be estimated from vertebrate mitochondria.
   So this is a statistical defect, not merely an expensive one -- and it would
   have produced numbers that looked entirely plausible.
   (An earlier draft of this document said the query returned NO Rhodophyta.
   That was wrong and is corrected here; the 68 are recoverable by a family
   filter, which is what the workflow guard now does.)

## Scale, measured -- not a one-off

A full sweep of the cached COI fetch (4,638 genera, 1,101,522 sequences), comparing
the FAMILY the match object assigns to each genus against the family NCBI returned:

    78 genera disagree, holding 314,934 sequences (28.6%)
    of which 310,628 (98.6%) belong to genera the match object calls Rhodophyta

Roughly 11 are true homonyms; the rest are benign revisions (below). **Eight of the
eleven are red algae.** Marine algal genus names collide with insect and vertebrate
names at a startling rate:

| genus | input lineage says | NCBI returned |
|---|---|---|
| Vertebrata | Rhodomelaceae (red alga) | Phyllostomidae (bats) |
| Digenea | Rhodomelaceae (red alga) | Diplostomidae (trematodes) |
| Grania | Acrochaetiaceae (red alga) | Enchytraeidae (oligochaetes) |
| Contarinia | Rhizophyllidaceae (red alga) | Cecidomyiidae (gall midges) |
| Acrotylus | Acrotylaceae (red alga) | Acrididae (grasshoppers) |
| Ptilophora | Gelidiaceae (red alga) | Notodontidae (moths) |
| Mastophora | Corallinaceae (coralline alga) | Araneidae (orb-weaver spiders) |
| Galene | Halymeniaceae (red alga) | Galenidae (crabs) |
| Lobophora | Dictyotaceae (brown alga) | Geometridae (moths) |
| Bulla | Bullidae (bubble snail) | Tetrigidae (pygmy grasshoppers) |
| Ctenophora | Tipulidae (crane fly) | Beroidae (comb jellies) |
| Armadillo | Armadillidae (isopod) | Dasypodidae (armadillos) |

This compounds a known weakness: 18S is currently blocked in that workflow, so
macroalgae are already thin. The bug removes algal LIKELIHOOD evidence at the same
time the same session was recovering algal PRIORS.

Prior art in this ecosystem, all the same defect wearing different clothes: the
tachinid fly genus *Polychaeta* corrupting a class-level lineage (2026-09-15, 7 taxa
silently dropped); GBIF cross-lineage homonyms for Ctenophora / Ciliophora /
Appendicularia / Pilidiophora; GBIF's genus *Spionidae* inside family Spionidae.

## HOMONYM vs BENIGN REVISION -- the distinction the fix turns on

Both present identically as "the returned lineage disagrees with mine". They must
not be treated alike: a revision should be ACCEPTED (and ideally adopted), a
homonym REJECTED.

* **Benign revision** -- same organism, reclassified. The disagreement stays
  INSIDE the same higher taxon. Real examples from the sweep:
  `Modiolus` Mytilidae -> Modiolidae; `Pseudanthias` Serranidae -> Anthiadidae;
  `Knodus` Characidae -> Stevardiidae; `Mesophyllum`/`Clathromorphum`/
  `Leptophytum`/`Melyvonnea` Mesophyllumaceae -> Hapalidiaceae; `Hydrolithon`
  Corallinaceae -> Hydrolithaceae; `Wolbachia` Rickettsiaceae -> Anaplasmataceae;
  `Xylophagus` Xylophagaidae -> Xylophagidae (spelling).
* **Homonym** -- different organism sharing a name. The disagreement CROSSES
  kingdom/phylum. Every row in the table above.

So the operative test is not "do the families match" but **"is the disagreement
contained within a shared higher rank"**. A family-level check alone produces 78
hits where only ~11 are real; adding the containment test is what separates them.

## Proposed solutions (the maintainer proposed 1 and 2; 3 and 4 came out of measuring)

**1. A known-homonym lookup table.** Viable as a stopgap and cheap to ship.
   Caveat from the data: one dataset in one region surfaced 11, eight of them red
   algae, so the universe is not small and a hand-list will always lag. Good as a
   fast guard and a place to record confirmed cases; not sufficient alone.

**2. Use the input's RANK.** Correct, and it catches the expensive cases -- but it
   is provably insufficient on its own. VERIFIED 2026-09-22:
   - *Vertebrata*: genus (alga) vs **clade** (vertebrates) -> rank DISAMBIGUATES.
     Same for *Digenea*, *Ctenophora*, *Diplura*.
   - *Lobophora*: taxid 214189 rank=**genus** division=moths & butterflies vs
     taxid 157000 rank=**genus** division=brown algae -> rank CANNOT disambiguate.
   Most of the eleven are genus-vs-genus. Rank is a necessary filter, not a
   sufficient one. Note the ecosystem ALREADY has a rank-agreement gate
   (`TaxaTools::assign_sampling_group(harmonise=TRUE)`, `verify_taxon_names()`'s
   `matched_rank`/`is_synonym`); it was simply never wired into the NCBI fetch path.

**3. Resolve to a TAXID using the caller's own lineage, then query by taxid.**
   The actual fix, and proven above: `txid1261581[ORGN]` returns 106 records where
   `Vertebrata[ORGN]` returns 519,463. NCBI's summary carries `rank` AND `division`
   ("red algae", "brown algae", "moths & butterflies", "vertebrates"), and
   `division` is what separates the genus-vs-genus cases rank cannot. The caller
   always has a lineage to disambiguate with -- the match object carries
   kingdom/phylum/class/order/family beside every genus. Cost: one extra taxonomy
   lookup per name, cacheable, and it REPLACES the name-based search rather than
   adding to it.

**4. A post-fetch lineage-agreement guard.** Cheap, catches everything after the
   fact, needs no API call (the returned records carry their own lineage), and is
   exactly the sweep that found all of this. Should exist regardless of 3, because
   it is the check that fails LOUDLY where the current behaviour fails silently.

Recommended shape: 3 as the fix, 4 as the permanent guard, 1 as a recorded registry
of confirmed cases, 2 folded into 3 as one of two discriminators (rank + division).

## Where it would live

A homonym check is a naming concern, so TaxaTools is the right home, next to
`verify_taxon_names()` / `resolve_barcode_marker()`. Consumers that need it today:
`TaxaLikely::fetch_ncbi_reference_sequences()` (the site of this defect),
`audit_barcode_coverage()`, `TaxaLikely::suggest_unreferenced_species()`, and the
two backbone harmonisers that already have the rank half of the answer.

## Reproducing

    # the collision
    rentrez::entrez_search(db="taxonomy", term="Vertebrata[All Names]", retmax=10)
    # -> taxid 1261581 (genus, red algae) and 7742 (clade, vertebrates)
    rentrez::entrez_search(db="nuccore", term="Vertebrata[ORGN]", retmax=0)$count
    rentrez::entrez_search(db="nuccore", term="txid1261581[ORGN]", retmax=0)$count

    # the sweep that found all 78 (read-only, no API calls, against a warm cache)
    # scratchpad/coi_homonym_sweep_FULL.rds holds the result

## Resolved -- branch `homonym-detection`, not yet merged to main

Built and live-verified against the real defect this document opened with, using this
document's own reproduction command as the acceptance test. **Not merged to main and
not reinstalled ecosystem-wide** -- this is design/measurement work per the freeze
note above; a new export needs the maintainer's yes before it ships.

**1 and 4, TaxaTools (`R/ncbi_homonyms.R`):**
- `.known_ncbi_homonyms` -- the registry, the 12-row table above, as internal package
  data. **Screen decision, applied:** NOT exported. It is a snapshot of what one COI
  fetch over 5,551 genera happened to surface, not a property of NCBI, so it is
  incomplete on day one and goes stale as NCBI's taxonomy changes; exporting it would
  invite a caller to guard against these twelve names instead of running the actual
  resolver, which catches a name not on any list. It earns its keep as the fixture in
  `test-ncbi_homonyms.R` (real, verified cases) and as the source for
  `resolve_ncbi_taxid()`'s own worked examples (Vertebrata, Lobophora) in its roxygen.
- `resolve_ncbi_taxid(name, rank = NULL, lineage_terms = NULL)` -- the actual fix
  (proposal 3, with rank folded in as the first discriminator per proposal 2). Two
  discriminators tried in order: rank (when supplied), then lineage containment
  (fetching each surviving candidate's own NCBI lineage and testing for ANY overlap
  with `lineage_terms`, case-insensitive) when rank alone can't decide. Returns
  `status` in `"unique"`/`"resolved_by_rank"`/`"resolved_by_lineage"`/`"ambiguous"`/
  `"not_found"`, never guesses.
- `check_lineage_agreement(declared, returned)` -- the permanent guard (proposal 4).
  Pipe/semicolon-delimited lineage strings; `"agrees"` on any shared term (covers both
  an exact match and a benign revision, per the HOMONYM vs BENIGN REVISION test
  above), `"disagrees"` on zero overlap between two non-empty sides, `"unknown"` when
  either side has nothing to compare -- never a false "disagrees" from missing data.

**Live-verified against real NCBI**, not just offline mocks: `resolve_ncbi_taxid`
correctly resolves *Vertebrata* to taxid 1261581 (division "red algae") via rank alone,
and correctly resolves *Lobophora* to taxid 157000 (division "brown algae") via lineage
containment once rank alone leaves both genus-rank candidates tied -- reproducing this
document's own worked examples exactly. A live count check reproduced the order-of-
magnitude harm directly: `Vertebrata[ORGN] AND COI AND 300:900[SLEN]` -> 351,647 records;
`txid1261581[ORGN] AND COI AND 300:900[SLEN]` -> 94 (NCBI's live count has moved since
this document's own snapshot; the ratio is the same defect).

**3, TaxaLikely (`fetch_ncbi_reference_sequences()`):** new opt-in `taxa_lineage`
parameter (a data frame: `taxon`, optional `rank`, and any of `kingdom`/`phylum`/
`class`/`order`/`family` -- the caller's own declared lineage). `NULL` (the default)
reproduces this function's exact original behaviour: every existing caller is
unaffected. When supplied: each taxon is resolved to a taxid via
`TaxaTools::resolve_ncbi_taxid()` *before* the count query, and queried by
`txid<id>[ORGN]` instead of `<name>[Organism]` -- REPLACING the name-based search, not
adding to it, per proposal 3's own recommendation. A taxon that resolves ambiguously
falls back to the name-based query with no protection, exactly as if it had never been
named in `taxa_lineage`. The reference-cache key gained a `taxid` component (a
name-scoped and a taxid-scoped query for the same taxon are different queries, and
must never serve as a cache hit for each other) -- `.ref_cache_grammar()`'s eviction
proof and its generated-argument test were both updated in the same change.

**4, wired as an always-on side effect of the same parameter:** the taxonomy bridge
already fetches each accession's full NCBI lineage XML; widened (only when
`taxa_lineage` is supplied) to also keep kingdom/phylum alongside whatever
`rank_system` already requests -- no extra API call, exactly as proposed. Every fetched
row's returned kingdom/phylum/family is checked via `check_lineage_agreement()` against
its queried taxon's declared lineage; disagreements are recorded in
`attr(reference_df, "lineage_disagreements")` and reported by count, never silently
acted on (no row is dropped by this guard -- it is diagnostic, matching this codebase's
`attr(x, "count_failures")`/`attr(x, "regional_unreferenced")` convention).

**Live-verified end to end**, this document's own reproduction case: fetching
*Vertebrata* + COI with `taxa_lineage` declaring `phylum = "Rhodophyta"`,
`family = "Rhodomelaceae"` returned **68 sequences, all family Rhodomelaceae, 0 lineage
disagreements** -- exactly the 68 real red-algal rows this document reports as
recoverable, and none of the 306,181 vertebrate sequences. `devtools::test()`: TaxaTools
1209/0 (35 new), TaxaLikely 1358/0 (34 new across two new test files).
`devtools::check()`: 0 errors/0 warnings on both (TaxaLikely's 1 note is the
pre-existing environmental timestamp note, unrelated).

**Deliberately not done, scope boundaries recorded rather than papered over:**
- `1` is a registry only, not consulted automatically by `resolve_ncbi_taxid()` -- it
  documents confirmed cases, it doesn't gate anything. A future session could wire it
  in as a fast pre-check if that proves worth the complexity.
- `audit_barcode_coverage()` and `TaxaLikely::suggest_unreferenced_species()` -- the
  doc's other two named consumers -- are NOT yet wired to `resolve_ncbi_taxid()`. Both
  query by name via their own code paths, independent of `fetch_ncbi_reference_
  sequences()`'s `.build_search_term()`; wiring them is the same shape of change but
  wasn't attempted this session.
- The two backbone harmonisers (`TaxaTools::assign_sampling_group(harmonise=TRUE)` and
  CaliforniaIntertidal's own harmonizer) already have the rank half of the answer per
  this document's own note and were NOT touched -- they operate on GBIF verification
  via `verify_taxon_names()`, a different mechanism than the NCBI-specific fix here.
- `fetch_ncbi_reference_sequences()`'s **priority_taxa path** (a separate, per-species
  code path the file's own comments say "no production workflow does") was left
  entirely unwired -- `.build_search_term()` calls there still pass no `taxid`.
- **`TaxaTools::verify_taxon_names(backbone_id = 4)`'s own internal NCBI bypass**
  (`.verify_via_ncbi()`) was found, while reading this code, to have the SAME shape of
  defect independently: it batches `entrez_search()` OR-queries and maps a returned
  `scientificname` back to a taxid via `name_to_taxid[[sci_name]] <- taxid`, which
  silently OVERWRITES on a homonym rather than erroring or disambiguating -- whichever
  candidate's ESummary is processed last in the batch wins, silently. This is a real,
  separate, more central bug (this function is what `escalate_taxonomic_rank()`,
  `fill_higher_ranks()`, and `assign_sampling_group(harmonise=TRUE)` all sit on top
  of), NOT fixed here -- fixing it means touching code with a much wider blast radius
  than this document's own scope, and deserves its own decision rather than being
  folded into this fix silently. Recorded here so it isn't lost.
