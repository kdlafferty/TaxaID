# CONTEXT: TaxaFlag

**Flag Anomalous Detections in Taxonomic Assignments**

Identifies and flags anomalous detections in taxonomic assignment results from biological surveys. Detects laboratory and field contamination by comparing read proportions against control samples, flags handler-related artifacts near equipment setup or collection events, and provides LLM-based expert review of habitat fit, geographic plausibility, contaminant risk, and taxonomic scope. Operates on consensus data frames and appends categorical flag columns for user-driven filtering. Part of the TaxaID ecosystem.

Version 1.0.0. 17 exported function(s).

## Functions

### add_posthoc_assessment(consensus_df, winner_likelihood_col = "winner_likelihood", consensus_taxon_col = "consensus_taxon", consensus_rank_col = "consensus_rank", likelihood_threshold = 0.5, domestic_taxa = NULL, domestic_prior_source = c("wild", "augmented"), primary_confusion_risk_col = "winner_own_rank_confusion_risk", consensus_confusion_risk_col = "consensus_confusion_risk", discriminating_threshold = 0.05, indistinguishable_threshold = 0.5, winner_theta_col = "winner_theta_mean", winner_record_col = "winner_has_occurrence_record", consensus_prior_col = "consensus_prior", consensus_record_col = "consensus_has_occurrence_record", expected_theta_threshold)

Add post-hoc plausibility and discrimination assessments to a consensus data frame

Appends two independent, orthogonal diagnostic axes to a 'TaxaAssign::posterior_consensus()' output, reported for 'primary_taxon' and 'consensus_taxon' separately: occurrence plausibility (Axis 1 - 'primary_plausibility'/ 'consensus_plausibility', "how expected is this taxon here?") and discrimination (Axis 2 - 'primary_discrimination'/ 'consensus_discrimination', "could the evidence tell this taxon apart from a plausible relative?"). Neither axis gates or overrides the other, and neither is folded into a single combined categorical - see '@section' below for both, and *Why no rank-based ...

| Param | Required | Default | Doc |
|---|---|---|---|
| consensus_df | yes |  | Data frame. Output of TaxaAssign::posterior_consensus(), containing at minimum winner_likelihood_col, consensus_taxon_col, and consensus_rank_col. |
| winner_likelihood_col | no | "winner_likelihood" | Character. Column in consensus_df holding the winner's ratio-normalised likelihood (default "winner_likelihood"). Used only by the domestic-species caveat (see below) -- a strong value here means the ID itself is trustworthy, independent of whether the occurrence prior underrepresents the taxon. |
| consensus_taxon_col | no | "consensus_taxon" | Character. Column holding the consensus taxon name (default "consensus_taxon"). Used only by the domestic-species caveat, to match against domestic_taxa. |
| consensus_rank_col | no | "consensus_rank" | Character. Column holding the consensus rank (default "consensus_rank"). Drives which expected_theta_threshold entry consensus_plausibility compares against. |
| likelihood_threshold | no | 0.5 | Numeric in (0, 1). Likelihood cutoff the domestic-species caveat uses for "the ID itself is trustworthy" (default 0.5). Below this, the winner had less than half the sequence-match density of the best-matching hypothesis. Unused when domestic_taxa is NULL. |
| domestic_taxa | no | NULL | Character vector or NULL (default). Taxon names (matched against consensus_taxon_col) that are domestic or synanthropic for your study system (e.g. "Felis catus", "Canis familiaris", "Bos taurus") -- there is no built-in default list, since what counts as "domestic" is study-system-specific. NULL disables this feature entirely (matches flag_handler's handler_taxa convention). See the Domestic/synanthropic species caveat section above. |
| domestic_prior_source | no | c("wild", "augmented") | Character. One of "wild" (default) or "augmented". "wild" assumes the underlying occurrence prior came from a raw occurrence database (GBIF/iNaturalist) with no domestic-species augmentation, so a strong-likelihood + low-plausibility domestic-species row is flagged via domestic_prior_caveat. "augmented" means the prior pipeline already incorporated known local domestic/synanthropic presence, so low occurrence plausibility is treated as informative and the flag never fires. Ignored when domestic_taxa is NULL. |
| primary_confusion_risk_col | no | "winner_own_rank_confusion_risk" | Character. Column in consensus_df holding TaxaAssign::posterior_consensus()'s winner_own_rank_confusion_risk -- the confusion-risk value rank-matched to primary_taxon's own resolved rank (default "winner_own_rank_confusion_risk"). Drives primary_discrimination. See @section Discrimination (Axis 2) below. |
| consensus_confusion_risk_col | no | "consensus_confusion_risk" | Character. Column holding the confusion-risk value rank-matched to consensus_taxon (default "consensus_confusion_risk"). Drives consensus_discrimination. |
| discriminating_threshold | no | 0.05 | Numeric in [0, 1] (default 0.05). Below this, the resolved rank is "discriminating". |
| indistinguishable_threshold | no | 0.5 | Numeric in [0, 1], >= discriminating_threshold (default 0.5). At or above this, the resolved rank is "indistinguishable"; between the two thresholds, "weak". |
| winner_theta_col | no | "winner_theta_mean" | Character. Column in consensus_df holding the winning hypothesis's own raw occurrence-model share (default "winner_theta_mean", from TaxaAssign::posterior_consensus()). Drives primary_plausibility. Deliberately reads theta_mean, NOT winner_prior/prior_mean -- see @section Occurrence plausibility below for why the two are not interchangeable. |
| winner_record_col | no | "winner_has_occurrence_record" | Character. Column indicating whether the winning hypothesis's taxon carries a real occurrence record at all (default "winner_has_occurrence_record"). This, NOT a low theta value, is what makes a call "unprecedented". |
| consensus_prior_col | no | "consensus_prior" | Character. Column holding the occurrence-model share (theta_mean-based group sum, see TaxaAssign::posterior_consensus()'s own docs) for the consensus taxon (default "consensus_prior"). |
| consensus_record_col | no | "consensus_has_occurrence_record" | Character. Column indicating whether the consensus taxon's group carries a real occurrence record at all (default "consensus_has_occurrence_record"). This, NOT consensus_prior_col's NA-ness, is what makes a call "unprecedented" at consensus scope -- consensus_prior is NA for two different reasons (no local member found, OR group_priors was never supplied to posterior_consensus() at all) that this column alone cannot distinguish; a taxon with NA here is "not_modeled", not "unprecedented". |
| expected_theta_threshold | yes |  | Named numeric vector, no default -- this genuinely depends on the taxon assemblage being scored and there is no universal safe value (mirrors TaxaAssign::join_priors()'s backbone_id / TaxaAssign::score_consensus()'s rank_thresholds, both required for the same reason). Names must be rank labels (e.g. c(species = ..., genus = ..., family = ...)); "species" is required, since primary_plausibility always compares against it (see @section Occurrence plausibility). A recorded taxon at or above the threshold for ITS OWN rank is "expected"; below it, "unexpected"; a rank with no entry in this vector gets "not_modeled" rather than an unsafe cross-rank comparison. Recommended: the median theta_sum at each rank from TaxaAssign::compute_group_priors() (species from median(taxaexpect_priors$theta_mean, na.rm = TRUE) directly, since compute_group_priors() is only built for genus/family) -- an "at least as expected as a typical local taxon at this rank" reading, avoiding a fitted or absolute cutoff. See @section Occurrence plausibility. If you derive it that way, the boundary FLOATS with the data. The recommendation above computes the threshold from the very table being classified, so it is a within-run RELATIVE judgement, not a fixed criterion, and two runs of the same site can classify differently with no code change and nothing wrong. Measured at GreatLakes: re-running only the prior side four days later refreshed 346 resident_undetected evidence rows (the priors were otherwise structurally identical -- same 483 rows, same 467 taxa, same branch counts), which moved median(theta_mean) from 1.72e-07 to 1.48e-08, an 11.7x shift in the species threshold, and unexpected went from 1 row to 18. The pipeline itself is deterministic: two runs on identical inputs produced byte-identical consensus rows. This is a property to REPORT, not a defect to patch. Wherever these categories are published, say what the threshold was and that it is assemblage-relative; a reader comparing unexpected counts across runs or sites is otherwise comparing two different questions. Pass a fixed vector instead if you need a criterion stable across runs -- at the cost of the "typical local taxon" reading that makes the data-derived version meaningful in the first place. |

**Value:** 'consensus_df' with five columns appended: 'primary_plausibility', 'consensus_plausibility' Character. Occurrence plausibility (Axis 1) of 'primary_taxon' and of 'consensus_taxon': '"expected"', '"unexpected"', '"unprecedented"', or '"not_modeled"' when nothing is computable - including when 'consensus_rank' has no matching entry in 'expected_theta_threshold'. 'NA' when the required source columns are absent from 'consensus_df'. 'primary_discrimination', 'consensus_discrimination' Character. Discrimination (Axis 2) of 'primary_taxon' and of 'consensus_taxon': '"discriminating"', '"weak"', '"indistinguishable"', or '"not_modeled"' when the source confusion-risk column is absent or 'NA'. See '@section Discrimination (Axis 2)' above. 'domestic_prior_caveat' Logical. 'TRUE' when the winning taxon is in 'domestic_taxa', 'domestic_prior_source = "wild"', the ID itself is trustworthy ('winner_likelihood_col' '>= likelihood_threshold'), and 'primary_plausibility' is '"unexpected"' or '"unprecedented"' - i.e. the occurrence plausibility flag for this row is a likely database-coverage artifact, not a genuine surprise. 'FALSE' otherwise, including when 'domestic_taxa' is 'NULL' (the feature is disabled). See @section Domestic/synanthropic species caveat above. 'domestic_caveat_type' Character. 'NA' unless 'domestic_prior_caveat' is 'TRUE', then one of: '"no_local_records"' ('primary_plausibility' was '"unprecedented"' - the species has never been reported locally, so the classic food/domestic-contamination reading is the leading hypothesis) or '"local_records"' ('primary_plausibility' was '"unexpected"' - the species HAS real local occurrence records, just at an implausibly low modelled rate, typically because those records sit in a different habitat than the survey's. For that case a genuine allochthonous detection - DNA transported across habitats, e.g. terrestrial pigs or coyotes reaching beach eDNA samples via runoff and tides - is at least as plausible as food contamination, and a reviewer should not read the row as a plain food label.)

#### Why no rank-based short-circuit

A single combined design that cross-tabulates sequence-match evidence against a taxon-tier lookup into one 9-category column would need a fallback for any row whose consensus_rank is coarser than species -- and a short-circuit value such as "vague_rank", returned for EVERY such row, stops classification entirely rather than reporting a coarser-but-still-informative answer. Axis 1 and Axis 2 avoid this because both are computed at whatever rank the data actually resolved to, reported alongside each other, with no rank at which classification simply stops.

#### Domestic/synanthropic species caveat

GBIF- and iNaturalist-derived occurrence priors structurally under-index captive/domestic organisms (pets, livestock) -- a data-curation property of those sources, not a modelling choice. A domestic species can therefore show primary_plausibility = "unexpected"/"unprecedented" (an artificially low occurrence share) even when the sequence-match or image/acoustic evidence for it is strong, looking like a suspicious call when it is really just a database gap. Passing domestic_taxa flags exactly this combination (strong likelihood + low occurrence plausibility) via the domestic_prior_caveat column, so a reviewer sees "trust the ID, question the rarity" rather than treating the occurrence-implausibility flag at face value. This is deliberately conservative: it only fires when the prior is expected to be an under-count (see domestic_prior_source), never invents or elevates a prior itself, and is its own small additive column. If your prior pipeline already augments occurrence data with known local domestic/synanthropic presence (rather than relying on raw GBIF/iNat), set domestic_prior_source = "augmented" to disable this flag, since primary_plausibility is then informative on its own.

#### Discrimination (Axis 2) (primary_discrimination/consensus_discrimination)

A confusion-risk value (TaxaLikely::evaluate_likelihoods()'s species_confusion_risk/genus_confusion_risk/ family_confusion_risk, passed through by posterior_consensus()) is a model-independent, score-ONLY diagnostic: given the winning candidate's own raw match score, how often would a REAL congener/confamilial/cross-family pair score this high or higher? HIGHER values mean MORE confusable, i.e. WEAKER evidence for the resolved rank -- a genuine risk-style metric (high=concern), unlike score_likelihood/posterior_mean/confidence_score elsewhere in this ecosystem, which are all high=good -- see evaluate_likelihoods()'s own @section Confusion risk for the full interpretation.

primary_discrimination/consensus_discrimination tier that raw value into three ordinal bands (plus "not_modeled" when the source column is absent or NA): "discriminating" (< 0.05), "weak" (0.05-0.5), "indistinguishable" (>= 0.5). Both breaks are interpretable statements about a genuine one-sided tail probability rather than fitted cutoffs.

These are reported alongside primary_plausibility/ consensus_plausibility (Axis 1) rather than combined with them -- Axis 1 asks whether the taxon is expected to be here at all; Axis 2 asks whether the evidence could discriminate it from a plausible relative. Neither substitutes for the other, and neither recomputes or overrides any other column.

#### Occurrence plausibility (primary_plausibility/consensus_plausibility)

An ordinal answer to "how expected is this taxon here?", reported for primary_taxon and consensus_taxon separately and computed at whatever rank the data actually resolved to -- never short-circuited for a coarser rank; see Why no rank-based short-circuit above for the failure mode this avoids.

"unprecedented" is driven by RECORD PRESENCE, never by a low value. A never-reported taxon and a genuine singleton can carry the same numeric value -- both land on the dark-diversity floor -- while meaning opposite things, so no threshold on the value can separate them.

Reads theta_mean, not prior_mean. prior_mean can be substantially inflated by TaxaAssign::update_prior_from_consensus()'s cross-observation confirmation boost, which has no gate on occurrence-record presence -- so an expected call built on prior_mean would mean "confirmed elsewhere in this dataset", not "expected here on occurrence grounds". theta_mean (TaxaExpect::prepare_model_dataframe()'s raw occurrence-model share, a compositional share of local records -- see TaxaAssign::update_prior_from_consensus()'s own "Rescaling onto the occurrence scale" section) is immune to that boost by construction, since the boost only ever modifies prior_mean.

A single absolute threshold, such as 0.5 on the prior_mean scale, is also a unit mismatch on the theta_mean scale: theta_mean is a share of local records, not a presence probability, so comparing it to "50/50 odds" is not a meaningful comparison. Beyond that, a SINGLE threshold applied at every rank is itself biased: a genus/family-level consensus_prior (the SUM of theta_mean across every locally modelled group member, from TaxaAssign::posterior_consensus(group_priors = ...)) is mechanically larger than any one species' own share just from summing more terms, not because it is more locally expected. expected_theta_threshold is therefore a RANK-MATCHED vector: primary_plausibility (always the winning candidate's own species-level share) is compared against the "species" entry; consensus_plausibility is compared against whichever entry matches that row's own consensus_rank_col value. A consensus_rank with no matching entry (e.g. a coarser rank the caller didn't supply a threshold for) gets "not_modeled" rather than being compared against the wrong rank's threshold.

### check_gbif_tile_range(taxon_key, query_lat, query_lon, zoom = 6L, buffer_px = 512L, escalate = TRUE, min_zoom = 0L, base_url = "https://api.gbif.org/v2/map/occurrence/density", cache_dir = NULL)

Spatial-isolation signal for a taxon from GBIF's occurrence-density map tiles

Downloads the GBIF occurrence-density PNG tile(s) covering a query point and a surrounding buffer, and reports how isolated that point is from the taxon's known range: whether the point itself falls in an occupied cell, the real-world distance to the nearest occupied cell, and the size of the occupied blob nearest the point (a weak proxy for "one lone report" vs. "a small cluster of independent reports").

| Param | Required | Default | Doc |
|---|---|---|---|
| taxon_key | yes |  | Integer. GBIF backbone usageKey for the taxon. Resolve via TaxaFetch::get_keys_from_context() or rgbif::name_backbone(). |
| query_lat | yes |  | Numeric scalars. The point to check. query_lat must be within Web Mercator's valid range (approximately -85.05 to 85.05 -- the projection is undefined at the poles). |
| query_lon | yes |  | Numeric scalars. The point to check. query_lat must be within Web Mercator's valid range (approximately -85.05 to 85.05 -- the projection is undefined at the poles). |
| zoom | no | 6L | Integer in [0, 12]. Starting tile zoom level. Controls both the real-world size of each density cell and how much ground a fixed buffer_px covers -- a coarser (smaller) zoom gives a wider, coarser view for the same download cost; a finer (larger) zoom gives tighter precision over a smaller area. Default 6L is roughly continental scale (tens to low hundreds of km per pixel, depending on latitude). |
| buffer_px | no | 512L | Integer. How far around the query point to scan for the nearest occupied cell, in tile pixels. Tiles are fetched in whole 512x512 blocks, so this is rounded up to the nearest multiple of 512. |
| escalate | no | TRUE | Logical. Widen the search to coarser zoom levels when nothing is found at zoom -- see "Zoom escalation" above. Default TRUE. |
| min_zoom | no | 0L | Integer in [0, zoom]. Coarsest zoom level escalation is allowed to reach. Default 0L (the whole world, one tile). Ignored when escalate = FALSE. |
| base_url | no | "https://api.gbif.org/v2/map/occurrence/density" | Character. GBIF map tile base URL. Exposed for testing. |
| cache_dir | no | NULL | Character or NULL (default). Directory for a persistent, per-key on-disk cache -- see Caching below. NULL disables caching entirely. |

**Value:** A one-row data frame: taxon_key, query_lat, query_lon As supplied. zoom_requested The 'zoom' argument, as supplied. zoom_used The zoom level the reported values were actually computed at - 'zoom_requested' unless escalation stepped down to find something. 'NA' when 'escalate = TRUE' (the default) and nothing was found anywhere from 'zoom' down to 'min_zoom' (nothing was ever "used"). When 'escalate = FALSE', this is always 'zoom_requested', even if nothing was found there - the single attempted zoom is still reported, for reference. escalated Logical. 'TRUE' when 'zoom_used != zoom_requested' - the answer came from a coarser search than requested. tile_size Pixel width/height of one fetched tile (512, GBIF's @1x.png size). n_tiles_fetched Total tiles downloaded across every zoom level attempted - transparency on the real cost of the call, including any escalation. resolution_km_per_px Real-world ground distance per pixel at 'query_lat'/'zoom_used' (Web Mercator distorts by latitude and zoom) - the unit 'patch_size_px'/'patch_area_km2' are derived from. point_occupied Logical. Does the query point's own cell (at 'zoom_used') have at least one occurrence? dist_nearest_occupied_km Distance from the query point to the nearest occupied cell found. '0' when 'point_occupied'. 'NA' when 'beyond_buffer'. patch_size_px Size (in cells, at 'zoom_used') of the occupied blob nearest the point (8-connected), grown from that nearest cell. Growth is capped at a small fixed number of iterations for bounded latency (see 'patch_size_capped'), so this is exact for a small/isolated patch (the case this function is for) but only a lower bound once a patch is large enough to hit the cap. 'NA' when 'beyond_buffer'. patch_size_capped Logical. 'TRUE' when patch growth hit the iteration cap before converging - 'patch_size_px'/'patch_area_km2' are then a lower bound, not exact. In practice this itself is informative: a capped patch is, by construction, one that already covers a wide area at 'zoom_used', i.e. clearly not an isolated report. 'NA' when 'beyond_buffer'. patch_area_km2 'patch_size_px * resolution_km_per_px^2' - the pixel count converted to real-world area, since a raw pixel count is only interpretable alongside the zoom it was measured at. A lower bound when 'patch_size_capped'. 'NA' when 'beyond_buffer'. patch_diameter_km 'sqrt(patch_size_px) * resolution_km_per_px' - a rough linear length scale for the same patch, in the same units as 'dist_nearest_occupied_km', meant for eyeballing the two against each other (e.g. "the isolated point is 340 km from a patch about 15 km across"). A lower bound when 'patch_size_capped'. 'NA' when 'beyond_buffer'. beyond_buffer Logical. With 'escalate = TRUE' (default): 'TRUE' only when no occupied cell was found anywhere from 'zoom' down to 'min_zoom' - with the default 'min_zoom = 0', this means the species has no occurrence anywhere in GBIF's density map at all (a real, decisive finding, not just "outside this window"). With 'escalate = FALSE': 'TRUE' when nothing was found within the single requested 'zoom'/'buffer_px' window.

#### Details

This is the cheap, global, approximate complement to compute_local_occurrence_distance()'s free, local, exact view: the local function can only speak to whatever bounding box a study's own GBIF fetch covered, while this one gives the missing global context (is a species that is novel to this study also far from its known range everywhere, or is it novel here simply because no one sampled here before) for the cost of a handful of small tile downloads, regardless of how many occurrence records exist worldwide.

#### What the PNG can and can't tell you

GBIF's density tiles encode density as a colour ramp, which is not a reliable source for exact counts. This function only ever reads the alpha channel (transparent = zero occurrences in that cell, any non-zero alpha = at least one) -- a presence/absence signal, not a decoded density value. patch_size_px/patch_area_km2 are weak, resolution-limited proxies for how much local support an isolated detection has (a bigger blob suggests more than one independent nearby report), not an exact record count; for that, follow up with a targeted GBIF occurrence query at just the flagged point.

#### What isolation does and doesn't mean

A point far from the nearest occupied cell is equally consistent with a genuine rarity/vagrancy report and with a misidentified or mis-georeferenced record -- this function cannot distinguish the two on geometry alone. Error screening against implausible occurrences belongs to TaxaFetch::check_geographic_outliers(); this function is for a downstream, different question -- for a detection already judged plausible, how far outside the species' main range does it sit.

#### Zoom escalation

A fixed zoom/buffer_px only ever covers a bounded window (e.g. the default is roughly continental scale) -- a species genuinely absent from that window could be just outside it, or on another continent, and a flat "not found" (NA distance) can't tell those apart. When escalate = TRUE (the default) and nothing is found at zoom, the same buffer_px window is re-tried one zoom level coarser (each step downward roughly doubles the real-world ground the same pixel buffer covers), continuing down to min_zoom (default 0L -- the whole world in a single tile) until an occupied cell is found or min_zoom is exhausted. This is cheap in the common case: escalation only fires for calls that would otherwise return NA, each step costs the same handful of tiles as the original call, and it terminates as soon as anything is found. Set escalate = FALSE to restore the original single-zoom, bounded-latency behaviour, where beyond_buffer means only "not within this one window." resolution_km_per_px/dist_nearest_occupied_km/patch_size_px etc. are always reported at zoom_used (whichever level actually found something, or the originally requested zoom if nothing was found at any level) -- compare against zoom_used, not zoom, when judging precision.

#### Caching

check_gbif_tile_range() is called once per zero-record taxon by TaxaExpect::generate_regional_proximity_evidence()'s Stage 1 gate -- cheap per call, but re-paid in full on every re-run of a workflow against otherwise-unchanged data. When cache_dir is supplied, a hit is read from disk with no HTTP request at all and a miss is fetched normally and then written.

Cache key (order shown; joined into one string and hashed for the filename): taxon_key, query_lat/query_lon each rounded to 4 decimal places (about 11m of ground resolution at the equator, so rounding only collapses floating-point noise), buffer_px, zoom, escalate, min_zoom, base_url. The full, unhashed key is stored inside the cache file and re-checked on every read -- a filename hash collision therefore costs one extra re-fetch, and can never hand back a different taxon/location's verdict. Each file also stores fetched_at (a POSIXct), which is how staleness is surfaced (see below) without a TTL.

No expiry, by design. A hit is always used, however old -- there is no automatic re-fetch. If you want fresher verdicts (GBIF's density map is refreshed with new occurrence submissions over time), you must deliberately clear the cache with taxaflag_clear_cache(); this function will never do it for you.

No year dimension in the key. GBIF's density tile API has no year filter at all -- a tile request always reflects GBIF's current full-history density map for that taxon, so the tiles cannot answer a time-scoped question.

What is and isn't cached. Every value this function can return once the fetch itself succeeds -- including beyond_buffer = TRUE -- is a real, decisive verdict (see @return below) and is cached. Nothing here is ever cached on a thrown error (a missing httr2/png package, a malformed GBIF tile, or any other condition that stops this function before it can construct a result) -- an error always propagates to the caller with no cache read or write, so a transient failure is retried plainly on the next call rather than being frozen as "unknown."

A verdict built on a tile GBIF did not return (HTTP status other than 200 or 204, e.g. a 5xx under load) is reported for the call with attr(out, "tile_fetch_failed") = TRUE and is never cached, because its "no occurrences" reading is what a server error looks like, not what it means. The returned data frame carries attr(out, "cache_age_days"): the age in days of the cached verdict on a hit, or NA on a miss/uncached call -- lets a caller report how stale the tile checks behind a run were, rather than that staleness being silent.

### classify_sample_identity(input_df, library_col = "event_id", sample_col = "sample_id", marker_col = "marker", run_col = "run", count_col = "count", taxon_col = "taxon_name", control_samples = NULL, failed_libraries = NULL, taxon_label_col = NULL, diversity_blank_max = 0.5, composition_share = 0.5, artifact_fraction = 0.9, spike_taxa = NULL, untested_policy = c("admit", "hold_blanks", "block"), accept_llm_roles = FALSE, decisions_path = NULL, on_pending = c("warn", "error", "ignore"), verbose = TRUE)

Gate Samples on Whether They Look Like Their Label

Classifies every sample x marker x run (a "unit": one tube amplified with one marker on one run, pooled over its replicate libraries) on two axes - what it is LABELLED (blank or sample) and what it LOOKS LIKE (a valid blank, a valid sample, or neither) - and suggests admitting it when the two agree or a decision has been recorded. Admission is the workflow's choice: 'admit' is a default the workflow may follow or replace. Everything else is held back and listed for review. Nothing is dropped silently: every unit keeps its row, its evidence and its reason.

| Param | Required | Default | Doc |
|---|---|---|---|
| input_df | yes |  | Long-format data frame, one row per feature x library, with every marker of the study and every control. Pass the same table used for flag_failed_libraries(). |
| library_col | no | "event_id" | Character. Column names, as in flag_failed_libraries. sample_col must identify the physical tube shared across markers; taxon_col is the fine-grained feature (ESV/ASV) used for composition and diversity. |
| sample_col | no | "sample_id" | Character. Column names, as in flag_failed_libraries. sample_col must identify the physical tube shared across markers; taxon_col is the fine-grained feature (ESV/ASV) used for composition and diversity. |
| marker_col | no | "marker" | Character. Column names, as in flag_failed_libraries. sample_col must identify the physical tube shared across markers; taxon_col is the fine-grained feature (ESV/ASV) used for composition and diversity. |
| run_col | no | "run" | Character. Column names, as in flag_failed_libraries. sample_col must identify the physical tube shared across markers; taxon_col is the fine-grained feature (ESV/ASV) used for composition and diversity. |
| count_col | no | "count" | Character. Column names, as in flag_failed_libraries. sample_col must identify the physical tube shared across markers; taxon_col is the fine-grained feature (ESV/ASV) used for composition and diversity. |
| taxon_col | no | "taxon_name" | Character. Column names, as in flag_failed_libraries. sample_col must identify the physical tube shared across markers; taxon_col is the fine-grained feature (ESV/ASV) used for composition and diversity. |
| control_samples | no | NULL | Character vector of sample_col (or library_col) values LABELLED as negative controls. NULL or empty is allowed: every unit is then "untested" ("no_blanks"). |
| failed_libraries | no | NULL | Optional result of flag_failed_libraries() on input_df. When NULL it is computed here with its defaults. |
| taxon_label_col | no | NULL | Character or NULL. A human-readable name column (species, or the finest rank known). When given, each unit gets a top_taxa summary, and each run gets one for its field units. Needed by review_sample_identity(). Default NULL. |
| diversity_blank_max | no | 0.5 | Numeric. Blank effective diversity, as a fraction of the marker's reference field diversity, at or above which a blank carries an environmental community. Default 0.5. On one real study, clean blanks sat at a median of 0.18 and the worst contaminated blank at 1.43. The distribution is continuous, so the value is a judgement; units near it are for review, not for a verdict. |
| composition_share | no | 0.5 | Numeric in (0, 1]. Share of a unit's assessable replicate libraries that must resemble the other label. Default 0.5. |
| artifact_fraction | no | 0.9 | Numeric in (0, 1] or NULL. Field-library prevalence at which a feature that also dominates the run's blanks is a run-wide artifact (see Run-wide artifacts). NULL disables detection. Default 0.9. |
| spike_taxa | no | NULL | Character or NULL. Features (taxon_col or taxon_label_col values) the user deliberately added to every tube. Set aside like an artifact, without a warning, and listed in attr(, "runs")$declared_spikes. Default NULL. |
| untested_policy | no | c("admit", "hold_blanks", "block") | "admit" (default), "hold_blanks" or "block": what the suggested admit does with untested and inconclusive units. See Status. |
| accept_llm_roles | no | FALSE | Logical. Let llm_role from the decision record stand in for an identity disposition where no person has recorded one, and llm_marker_unusable exclude that marker where no person has recorded a library disposition (it can only exclude, never keep). Default FALSE. |
| decisions_path | no | NULL | Character or NULL. The CSV decision record. Read if it exists, then rewritten with the current review queue. Default NULL: nothing is read or written, and the queue is only returned. |
| on_pending | no | c("warn", "error", "ignore") | "warn" (default), "error" or "ignore": what to do when units are held back awaiting an identity decision. A production workflow should pass "error". |
| verbose | no | TRUE | Logical. Print a summary. Default TRUE. |

**Value:** 'input_df' in its original order with these columns added: 'identity_label' '"blank"' or '"sample"', as labelled. 'identity_appearance' '"valid_blank"', '"valid_sample"', '"neither"' or '"not_assessed"'. 'identity_status' '"concordant"', '"discordant"', '"suspect"', '"inconclusive"' or '"untested"'. 'identity_status_reason' See Status. 'admit_as' '"control"', '"sample"', '"positive_control"' or 'NA' (not admitted); reflects any reassignment. 'control_usability', 'sample_viability' Per marker; see Decision scopes. 'admit' Logical. The gate. Filter on this and read 'admit_as' for the role; the original 'control_samples' vector is no longer the control set. Attribute '"units"': one row per sample x marker x run with the evidence ('depth', 'richness', 'diversity_n1', 'diversity_ratio', 'composition_share_other', 'n_libraries_assessable', 'composition_power', 'library_status', 'run_status', 'n_markers_flagged', 'n_markers_assessable', 'top_taxa', and 'top_taxon' with 'top_taxon_share': the single most abundant feature and its share of the unit's reads, with run-wide artifacts and declared spikes set aside. Dominance is reported as evidence for a reviewer and never acted on: a blank that is 96\ verdict columns, 'identity_status_reason', 'issue_type', 'tube_flagged', 'hold_reason', 'confidence', 'reason', 'disposition', 'disposition_source', 'pending_review', 'excluded_library_issue', 'control_usability' (for units whose role is control: '"usable"', '"contaminated_in_marker"', '"kept_by_decision"' or '"excluded_by_decision"'), 'sample_viability' (for units whose role is sample: '"viable"', '"thin"' or '"non_viable"'), 'admit_as' and 'admit'. Attribute '"review_queue"': the units that need a person, in decision-record shape. Attribute '"runs"': one row per run x marker, with admitted control and sample counts, 'control_status' ('"ok"', '"no_admitted_control"' or '"no_controls_labelled"') and the field 'top_taxa', 'run_wide_artifacts' and 'declared_spikes' (see Run-wide artifacts). Attribute '"failed_libraries"': the 'flag_failed_libraries()' result used.

#### The matrix

llll labelled \ looks like valid blank valid sample neither blank concordant: control DISCORDANT suspect sample DISCORDANT concordant: admit suspect

#### Status

what was found, and why nothing could be: identity_status separates a finding from the absence of one, and identity_status_reason names the evidence or the reason:

- concordant, discordant, suspect: A test ran and answered (reason: "composition", "diversity", "library_failed", ...).

- inconclusive: A test ran but could not discriminate ("no_power": validate_controls() reported a null too wide to separate anything, or no headroom).

- untested: No test ran: "no_blanks" (nothing to compare a sample with), "unreplicated" (too few field units on the run), or "uncomparable" (the run's field libraries failed, so a blank has nothing valid to be compared with).

An untested or inconclusive unit shows no evidence of a problem, which is not evidence of its absence. Many studies are thin, and they should still be analysed, cautiously: by default (untested_policy = "admit") such units are admitted with their status carried through. "hold_blanks" keeps untested/inconclusive blanks out of the control set (a dirty blank corrupts contaminant verdicts in the permissive direction); "block" holds every such unit for review.

#### Order of operations

Yield is assessed first, with flag_failed_libraries. A failed library looks like a sparse sample, and a failed run leaves nothing for a blank to be compared with, so identity is judged only where yield held.

- A labelled SAMPLE whose libraries all failed looks like "neither" (issue type "library").

- A labelled BLANK on a failed run is "untested" ("uncomparable"). Its low reads and low diversity are what a failed library would show whether or not it was clean. The one exception: a blank that still reaches sample-level diversity on a failed run is "neither", because failure only ever lowers diversity.

#### What "looks like a valid blank" means

No single scalar works across markers (a plankton-filled blank can be out of analytical scope but not out of the ENVIRONMENT). The axis that matters is environmental versus laboratory, so this function uses two scope-free signals:

- Composition (validate_controls, run on each run's libraries): does the blank look like the field samples it was sequenced with? A blank is sample-like when at least composition_share of its assessable replicate libraries are "RESEMBLES_SAMPLE". This catches a blank carrying the samples' own community (a mislabel, or carry-over).

- Effective diversity (Hill number of order 1, the exponential of Shannon entropy) relative to the marker's REFERENCE field diversity: the median, over runs, of each run's median field unit. The reference comes from outside the run, so a run whose samples all failed cannot make its blanks look rich by comparison. A blank at or above diversity_blank_max of the reference carries an environmental community. Hill N1 is barely moved by the many one- and two-read features that index hopping spreads into blanks.

The second signal is what the first cannot see. A blank holding a DIFFERENT environmental community -- seawater plankton in a benthic study -- is compositionally disjoint from the samples, and validate_controls() reads disjoint as clean.

A blank is "valid_sample" when it is sample-like in composition, "neither" when it has sample-level diversity without resembling the samples, and "valid_blank" otherwise. That includes an EMPTY blank: for a blank, few reads is the healthy state, and low yield never counts against it. confidence is "low" when the composition test had no power (validate_controls() power other than "ok"). The verdict then rests on diversity alone, and the low confidence says so.

A diverse blank is flagged "suspect", not condemned: a blank's own medium can carry a community (tap water carries its source water's freshwater organisms). Whether the community is consistent with the blank medium or with handling is a judgement about what the taxa are, which review_sample_identity makes when told the medium.

#### What "looks like a valid sample" means

A labelled sample is "valid_sample" unless:

- its libraries failed ("neither"); or

- at least composition_share of its assessable libraries "RESEMBLES_CONTROL" ("valid_blank").

A sample with low_yield libraries (low in every marker, which is genuine low biomass) is a valid sample. The identity test for a sample is whether it resembles the run's blanks; when that test cannot run or cannot discriminate the sample is "untested" or "inconclusive", not concordant.

#### Run-wide artifacts and declared spikes

A feature in at least artifact_fraction of a run's field libraries that also holds the majority of reads in at least half of the run's blanks is in every tube whatever the tube is: a spike the user added, a provider's positive control reaching every library, or cross-contamination. It carries no identity information, so it is set aside from composition and diversity. Both conditions are needed: common environmental taxa can be in nearly every field library, but they do not dominate the blanks. Unless declared in spike_taxa, such a feature is REPORTED as a run-wide artifact with a warning, because its cause is a question for the user or the provider. It stays visible in top_taxa. Judged per run, since one archive can mix runs with and without it.

#### Two kinds of decision, two scopes

- Identity -- what is this tube?: A property of the SAMPLE (barcode), across every marker: a tube cannot be a blank in one marker and a sample in another. Dispositions "confirm_blank", "confirm_sample", "reassign_to_blank", "reassign_to_sample", "reassign_to_positive_control" and "exclude_tube" apply to all of the sample's units. A positive control recorded as a field blank must not stay in the negative control set: it inflates the control rate of every spiked taxon, which makes flag_contaminant() more permissive. Re-roled, it is admitted with admit_as = "positive_control".

- Library validity -- did this assay work?: A property of the UNIT. Dispositions "exclude_library" and "keep_library" apply to that unit only, so a library that failed in one marker does not take the same tube's good libraries in other markers with it. "keep_library" also lifts flag_failed_libraries()'s exclusion for that unit.

Each flagged unit has an issue_type ("identity" or "library") saying which kind of disposition resolves it.

- An identity flag holds the whole tube. A discordant or suspect identity in ANY marker holds every unit of that sample, including markers where it looked concordant (tube_flagged). Such a unit keeps its own identity_status (it is not itself evidence of anything), and hold_reason says why it is held: "own_evidence", "tube", "untested" or "inconclusive". An untested unit holds only itself: a failed library says nothing about the tube's other markers.

- Identity is per tube; usability is per marker. A blank whose own evidence in one marker looks contaminated (discordant or suspect in that marker) is not admitted as a control IN THAT MARKER, even after the tube is confirmed as a blank: control_usability reads "contaminated_in_marker", and "keep_library" on that unit overrides it. Its other markers are judged on their own evidence: contamination a marker cannot amplify cannot bias that marker. The inference runs one way only. A clean result in an insensitive marker (12S cannot amplify protists or algae) never clears a sensitive one.

- Sample viability is per marker. sample_viability combines yield with appearance: "viable" (libraries passed), "thin" (low yield but a normal-looking composition: a genuinely small sample, not a broken one) or "non_viable" (no library yielded). Depth alone cannot tell thin from broken. Below some depth the composition test has nothing to compare, so only depth speaks; that is the inconclusive/no_power state.

- Identity questions block; library failures do not. A unit held for identity is pending_review until the tube has a disposition. A unit whose libraries failed is excluded (excluded_library_issue) but not pending: excluding it is already the conservative outcome, flag_failed_libraries() reports it loudly, and a queue that makes a person sign off every failed library invites rubber-stamping. It stays in the decision record, so "keep_library" can reverse it.

- Individually failed replicate libraries inside an admitted unit stay excluded at row level (admit is FALSE for their rows) unless the unit is kept explicitly.

#### The decision record

decisions_path names a CSV the user edits. Each call reads it and applies the dispositions. It then writes it back with every unit that currently needs review, preserving everything the user entered and adding new rows. Rows are keyed by sample, marker and run. Each row carries the status and appearance the gate reported when the row was written. If the evidence has since changed, the disposition is still applied, and a warning names the rows so they can be looked at again. review_sample_identity adds llm_ columns to the same file, including llm_role (blank, sample, positive_control, exclude or unknown). By default these are advice. With accept_llm_roles = TRUE, llm_role stands in for an identity disposition wherever no person has recorded one, and disposition_source says which it was ("user" or "llm"). A person's disposition always wins.

#### Cross-marker agreement

Each unit reports n_markers_flagged and n_markers_assessable for its sample, counting identity flags only: a blank flagged in two independent markers is better supported than one flagged in one.

### compute_local_occurrence_distance(taxon_names, query_lat, query_lon, occurrence_data, taxon_col = "taxon_name", lat_col = "decimalLatitude", lon_col = "decimalLongitude", date_col = NULL)

Distance from a query point to the nearest already-fetched GBIF occurrence

For each taxon in 'taxon_names', finds the nearest record of that taxon already present in 'occurrence_data' and reports the geodesic distance from 'query_lat'/'query_lon' to it. 'occurrence_data' is meant to be data a workflow already fetched for its own purposes (e.g. the 'all_occurrences'/'occurrences_clean' objects 'TaxaFetch' produces during the normal pipeline) - this function costs nothing beyond arithmetic, no new GBIF call, since that regional data is already in hand.

| Param | Required | Default | Doc |
|---|---|---|---|
| taxon_names | yes |  | Character vector. One or more taxon names to check (e.g. every consensus_taxon flagged "unexpected"/"unprecedented" in one review session). Matched exactly against occurrence_data[[taxon_col]]. |
| query_lat | yes |  | Numeric scalars. The point to measure distance from -- typically the study site's own centroid. |
| query_lon | yes |  | Numeric scalars. The point to measure distance from -- typically the study site's own centroid. |
| occurrence_data | yes |  | Data frame of already-fetched occurrence records (e.g. all_occurrences, occurrences_clean). Must contain taxon_col, lat_col, lon_col. |
| taxon_col | no | "taxon_name" | Character scalars. Column names in occurrence_data. Defaults match TaxaFetch's DarwinCore-aligned convention. |
| lat_col | no | "decimalLatitude" | Character scalars. Column names in occurrence_data. Defaults match TaxaFetch's DarwinCore-aligned convention. |
| lon_col | no | "decimalLongitude" | Character scalars. Column names in occurrence_data. Defaults match TaxaFetch's DarwinCore-aligned convention. |
| date_col | no | NULL | Character or NULL. Optional column in occurrence_data giving the nearest record's collection date/year (e.g. GBIF's own "year" standard column). When supplied and present, the matched nearest record's raw value is surfaced as nearest_date -- lets a caller weigh a fresh vs. a decades-old nearest record differently without a second lookup. Default NULL (no age column requested; nearest_date is simply absent from the output). No parsing/normalization is done on the raw value; a "year" column comes back as whatever numeric/character type it already was. |

**Value:** A data frame, one row per unique entry in 'taxon_names': taxon_name As supplied. n_local_records Count of 'occurrence_data' rows for this taxon with non-missing coordinates. '0' for a taxon with no local record at all - for a genuinely unprecedented taxon this IS the answer, not a failure to find one. dist_nearest_km Geodesic (great-circle) distance in km from the query point to the nearest such record. 'NA' when 'n_local_records == 0'. nearest_lat, nearest_lon Coordinates of that nearest record. 'NA' when 'n_local_records == 0'. nearest_date The nearest record's raw 'date_col' value. Only present when 'date_col' is supplied and found in 'occurrence_data'. 'NA' when 'n_local_records == 0' or the nearest record's own 'date_col' value is missing.

#### Details

Designed as the free, local, exact complement to check_gbif_tile_range()'s cheap, global, approximate view: a taxon with n_local_records = 0 here is, by construction, exactly the situation that produces TaxaAssign::compute_group_priors()'s consensus_has_occurrence_record = FALSE (an "unprecedented" call from add_posthoc_assessment()), so this answers why that flag fired using data the pipeline already paid for, rather than re-querying GBIF. Because occurrence_data is whatever bounding box a study's own GBIF fetch used, this function can only speak to that regional extent -- a taxon absent here may still occur well outside it; check_gbif_tile_range() is the tool for that wider question.

### flag_backbone_conflicts(consensus, taxonomy, rank_system = NULL, observation_col = "observation_id", posterior_col = NULL, placeholder_rank_count = 3L)

Flag Taxa Whose Backbone Placement Disagrees With Itself

Asks whether a name in the taxonomy actually denotes one place in the tree. Two failures are detected, both learned from the backbone present in the data rather than from any list of taxa: a name carried at MORE THAN ONE RANK (a clade treated as a phylum on some rows and as a lower rank inside another phylum on others, or a true homonym such as a phylum name reused as a genus), and a name carried under MORE THAN ONE PARENT at the same rank.

| Param | Required | Default | Doc |
|---|---|---|---|
| consensus | yes |  | Data frame of consensus calls, one row per observation, as returned by TaxaAssign::posterior_consensus() or TaxaAssign::score_consensus(). Only observation_col is required; consensus_limit and consensus_rank are used when present. |
| taxonomy | yes |  | Data frame of the candidate rows the consensus was computed from (the posterior or match table), carrying observation_col and the rank columns. This is where placement is learned: the consensus alone cannot show a disagreement. |
| rank_system | no | NULL | Character vector of rank column names, coarse to fine. NULL (default) auto-detects via TaxaTools::detect_ranks(), falling back to the standard ladder intersected with the columns present. |
| observation_col | no | "observation_id" | Character. Observation identifier shared by consensus and taxonomy. Default "observation_id". |
| posterior_col | no | NULL | Character or NULL. Posterior/weight column in taxonomy used for backbone_conflict_mass. NULL (default) auto-detects "posterior_point_est" then "posterior_mean"; when neither is present the mass column is NA and the flag is unaffected. |
| placeholder_rank_count | no | 3L | Integer >= 2. Number of distinct ranks at which a name is labelled "placeholder" rather than "cross_rank". Default 3: a real homonym occupies two ranks, while a control or placeholder string occupies as many as it is written into. Presentation only -- it changes category, never the flag. |

**Value:** 'consensus' with these columns added (existing columns of the same name are overwritten, with a warning): 'backbone_conflict' Logical. 'TRUE' when any candidate row of the observation carries a conflicted name at any rank. 'backbone_conflict_kind' '"cross_rank"', '"multi_parent"', '"both"', '"placeholder"', or 'NA' when not flagged. '"placeholder"' wins over the others. 'backbone_conflict_names' Semicolon-separated conflicted names found in the observation, or 'NA'. 'backbone_conflict_mass' Share of the observation's candidate mass sitting on rows that carry a conflicted name, or 'NA' when no posterior column is available. A small share is a weaker concern than a large one. 'cross_phylum_conflicted' Logical or 'NA'. For rows whose 'consensus_limit' is '"cross_phylum"', whether the withholding involves a name that is ALSO used as a phylum elsewhere in 'taxonomy' - i.e. whether the phyla the rule compared may be two names for one lineage. 'NA' where 'consensus_limit' is absent or not '"cross_phylum"'. The conflict table itself is attached as attribute '"backbone_conflicts"': one row per conflicted name with 'name', 'kind', 'category', 'n_ranks', 'ranks', 'parents', 'candidate_rows' and 'observations'. Attribute '"backbone_conflict_params"' records the arguments used. Both survive row subsetting and are dropped by column subsetting ('d[, cols]'), 'merge()' and 'dplyr::summarise()'.

#### What this CANNOT see

Both detected failures are ONE NAME in more than one place. The inverse -- MANY NAMES for one organism, i.e. synonymy -- is invisible here, and not as an implementation gap: a synonym pair sits consistently at one rank under one parent on each of its two names, so there is no conflict to find. Where a reference database holds Eisenia arborea and an occurrence pool lists Ecklonia arborea, this function reports nothing, by construction. It therefore cannot be used as evidence that a name set is free of duplicate organisms, and a report of zero conflicts says nothing about synonymy.

That matters because a name absent from a reference set becomes an unreferenced local species downstream, and TaxaAssign::add_unreferenced_prior_mass(named_rows = TRUE) can then name it in a call -- so a synonym of a referenced taxon could be reported as having no reference sequence. The designed defence is the NCBI-to-GBIF crosswalk, not this function.

Measured on one real multi-marker study, in two independent ways, and it found no instance of that failure. First, the 35 record-named taxa behind its 410 such calls produced 97 shared-epithet pairs against the reference sets and EVERY one was in a different family -- homonymous epithets across unrelated groups (Fucus / Pleurophycus / Pyropia gardneri) rather than synonyms. Second, all 34 distinct names among them resolve at species rank to THEMSELVES on the backbone the priors use, none flagged as a synonym, and none of their accepted names appears in the same marker's reference set; the reverse direction, resolving all 318 reference species sharing a family with any of the 35, likewise returned nothing. So the limitation is a measured absence there rather than an untested assumption -- but it IS only that backbone's taxonomic opinion. A pair that another authority treats as synonymous while this backbone keeps it separate would not show, and a synonym the backbone places in a DIFFERENT family would escape the reverse check (though that would itself be a conflict of the kind this function does detect). The limitation stands regardless of the result.

#### Why this is not a data-cleaning nicety

Any rule that compares taxonomy by NAME is wrong wherever a name is not a key. TaxaAssign::posterior_consensus()'s cross_phylum_eps rule withholds a call that rests on a choice between phyla, and it compares the phylum column by name; where one lineage carries two names at different ranks, that comparison sees two phyla where biology has one, and no value of the tolerance distinguishes the two cases. The same applies to anything that groups, pools or counts by a rank column. This function does not fix the taxonomy -- the fix is upstream, in making the backbone placement consistent -- it tells the reader which calls stand on a name that cannot be trusted as a key.

#### What the two kinds look like

On one real multi-marker study (CalIntertidal, 6.13M candidate rows, 49,346 observations) 18 of 28,610 distinct names were carried at more than one rank. Four of them were used as a phylum somewhere, and those four touched 1,054 of the 24,739 observations whose calls the cross-phylum rule can reach. The largest was a chromist class also carried as a phylum (606 observations), not the case that prompted the check (37). One name was a textbook homonym: a phylum of comb jellies reused as a crane-fly genus. Separately, 33 or more name/rank combinations sat under two parents, and three of those were ONE inconsistent placement showing up at three consecutive ranks, which is the argument for fixing the backbone rather than each rank.

#### Placeholders are found by the same rule, and kept visible

Control and placeholder names ("PositiveControl", "None" and the like) are genuinely carried at many ranks, so a detector learned from the data finds them. They are reported in their own category, never silently dropped: a control name occupying a phylum column is itself worth a reader's attention. In the study above the placeholders sat at four and six ranks while every genuine homonym sat at exactly two, which is what placeholder_rank_count is set from. The FLAG does not depend on that argument; only the label does.

### flag_contaminant(input_df, event_col = "event_id", taxon_col = "taxon_name", count_col = "count", control_samples = NULL, sample_type_col = NULL, control_types = NULL, exclude_samples = NULL, contaminant_type = "lab_contaminant", score_thresholds = c(0.5, 0.9), prior_weight = 20, require_control_evidence = FALSE, site_col = NULL, min_sites_systemic = 2L, min_control_obs = 2L, verbose = TRUE)

Flag Potential Contaminants by Comparison to Control Samples

Compares detection proportions between field samples and control samples (negative controls or positive controls) to identify taxa that may be contaminants. Supports any labelled control samples (extraction, PCR, or field blanks; for non-sequence data, a blank photo/recording or a negative-control site) plus positive controls.

| Param | Required | Default | Doc |
|---|---|---|---|
| input_df | yes |  | Data frame in long format with at minimum columns for sample identification, taxon identification, and count data (e.g. read counts, detection counts). |
| event_col | no | "event_id" | Character. Column name identifying collection events (e.g., individual filters, bottles, or deployments). Default "event_id". |
| taxon_col | no | "taxon_name" | Character. Column name identifying taxa (species, ESV, ASV, etc.). Default "taxon_name". |
| count_col | no | "count" | Character. Column name with integer count data. Default "count". |
| control_samples | no | NULL | Character vector of sample IDs that are controls (negative controls or positive controls). Mutually exclusive with sample_type_col; at least one must be supplied. |
| sample_type_col | no | NULL | Character. Column name containing sample type labels. When supplied, control_types identifies which values are controls. Mutually exclusive with control_samples. |
| control_types | no | NULL | Character vector of values in sample_type_col that identify control samples. Required when sample_type_col is used. Default NULL. |
| exclude_samples | no | NULL | Character vector of sample IDs to exclude from both control and field calculations. Use to remove e.g. extraction controls when analysing PCR controls, or vice versa. Default NULL. |
| contaminant_type | no | "lab_contaminant" | Character. Label for the type of contamination being assessed, embedded in validity_flag's values (e.g. "invalid_lab_contaminant") -- see @return below. Does NOT change output column NAMES (see Details); those are fixed (observation_validity/validity_flag/ validity_reason) so every TaxaFlag flag_*() mechanism shares one schema. Common values: "lab_contaminant", "field_contaminant", "positive_control". Default "lab_contaminant". |
| score_thresholds | no | c(0.5, 0.9) | Numeric vector of length 2. Thresholds for converting observation_validity to validity_flag. Values at or below the first are "invalid_{contaminant_type}" (probable contaminant); at or below the second, "questionable_{contaminant_type}"; higher values are "valid" (likely a genuine detection). Default c(0.5, 0.9). |
| prior_weight | no | 20 | Numeric (default 20). Empirical Bayes shrinkage strength, in units of "equivalent reads" (see .compute_contaminant_scores()'s own documentation for why reads, not samples). Controls how strongly the final field-vs-control ratio is pulled toward 0.5 (maximally uncertain) when a taxon has little total read support overall. Higher values shrink harder (more conservative, less willing to call a thinly-supported taxon confidently clean or contaminated); 0 disables shrinkage entirely, restoring the raw depth-weighted ratio. |
| require_control_evidence | no | FALSE | Logical. When TRUE, an ESV that was never detected in ANY control is labelled "no_control_evidence" instead of being scored, and ESVs that ARE seen in a control are split by DIRECTION. Default FALSE, which emits a warning when it bites (see below); TRUE is the defensible setting for new work. Why: the shrunken score is driven by READ DEPTH when control detections are rare, so it assigns a contamination verdict to ESVs with no contamination evidence at all. Measured on a real 12S run: of 13,597 ESVs only 43 were ever detected in a single control, yet 10,300 were labelled questionable_lab_contaminant -- the whole middle tier had ZERO blank evidence, and the rate was 75-81% in every marker and workflow checked because it reflects the read-depth distribution rather than contamination. DIRECTION IS THE POINT. Contamination flows control -> sample; CARRYOVER flows sample -> control, which is what happens when a blank picks up a little of an abundant local taxon. The first must be filtered and the second must not, and a symmetric score cannot tell them apart. |
| site_col | no | NULL | Character or NULL. Column giving each event's site. When supplied, site breadth is computed per taxon and used as a DISCRIMINANT, not merely as extra power: a systemic contaminant (reagent, water supply) appears in controls at MANY sites regardless of which sites' samples carry it, whereas a local source appears in controls at the ONE site whose samples are full of it. This is what dissolves the pooling-versus-pairing dilemma -- pooling controls buys power but lets one trip's contamination speak for another's, while pairing by event buys specificity at the cost of power (on real data, event-paired controls emptied the invalid tier completely: 0 ESVs, against 43 and 323 in pooled runs). Using the cross-site PATTERN keeps both. |
| min_sites_systemic | no | 2L | Integer. How many distinct sites must show a control detection before it counts as systemic rather than local. Default 2. Only used when site_col is supplied. |
| min_control_obs | no | 2L | Integer. Minimum number of distinct controls a taxon must appear in before the rate comparison is allowed to condemn it. Default 2. Only used when require_control_evidence = TRUE. This exists because the direction test is a BARE RATE INEQUALITY, and rates built on one observation are not comparable to rates built on hundreds: with 91 controls against 1,052 samples, one stray read in one blank scores 1/91 = 0.011 and outvotes two genuine detections at 2/1052 = 0.0019. On real data 55-63 per cent of everything the gate condemned rested on a single control observation, and the tail contained genuine organisms. Setting this to 1 restores the unfloored behaviour; a proper one-sided significance test with a multiple-testing correction would be the principled replacement and is NOT implemented. |
| verbose | no | TRUE | Logical. Print summary messages. Default TRUE. |

**Value:** A data frame with one row per taxon, sorted by 'observation_validity' (most likely contaminants first). Columns: '{taxon_col}' Taxon identifier (from input). 'observation_validity' Numeric 0-1. Empirical Bayes-shrunk ratio of the depth-weighted field rate to the total (field + control) rate. Higher = more likely a real, genuine detection; lower = more likely a contaminant. Approaches, but does not reach, 1.0 for taxa absent from controls - see Details. A ranked screening statistic, not a calibrated probability. 'validity_flag' Character. '"invalid_{contaminant_type}"' (probable contaminant), '"questionable_{contaminant_type}"' (uncertain), or '"valid"' (likely genuine detection) - see '@section Unified validity schema' above. Fixed column name across every TaxaFlag flag_*() mechanism; the specific type of concern lives in the value, not the column name. 'validity_reason' Character. Plain-English explanation including depth-weighted rates and control detection counts. 'mean_prop_field' Informational only, does not drive the score: unweighted mean of within-sample proportions in field samples. 'mean_prop_control' Informational only, does not drive the score: unweighted mean of within-sample proportions in control samples. 'field_rate' Depth-weighted detection rate in field samples (taxon reads / total field sequencing depth), before shrinkage. 'control_rate' Depth-weighted detection rate in control samples, before shrinkage. 'n_field_present' Number of field samples in which the taxon was detected. Informational only - does not drive the shrinkage weight (see 'n_reads_total'). 'n_controls_present' Number of controls in which the taxon was detected. Informational only. 'n_controls_total' Total number of controls. 'n_reads_total' Total reads for this taxon across field + control samples combined. This, not sample count, is what the shrinkage weight ('prior_weight') is measured against - see '.compute_contaminant_scores()' for why.

#### Details

The algorithm computes a depth-weighted detection rate per taxon in field samples vs. controls, then an Empirical Bayes-shrunk score comparing them (.compute_contaminant_scores()'s own internal documentation has the full mechanism and the real-data motivation for it). Taxa with a higher rate in controls than field samples receive low scores (likely contaminants); taxa strongly favoring field samples receive scores approaching, but not reaching, 1.0 -- shrinkage means no taxon gets an absolute 0 or 1 score purely from having little total read support (shrinkage strength is measured in reads, not samples; see .compute_contaminant_scores()'s documentation).

This score is a ranked screening statistic, not a calibrated probability: no generative model of contamination is fit, and the score is not validated against known-true contamination status. Use it to rank taxa for review against score_thresholds, not as a literal posterior probability.

For positive controls, the interpretation is inverted: taxa from the positive control appearing in field samples indicate cross-contamination.

#### Unified validity schema

Output column NAMES are fixed (observation_validity/ validity_flag/validity_reason) rather than parameterized by contaminant_type -- every TaxaFlag flag_*() mechanism (see also flag_handler) shares this one schema, matching the "one column, type-qualified values" pattern. The contaminant_type string appears in validity_flag's VALUES ("invalid_{contaminant_type}"/"questionable_ {contaminant_type}") instead of in a column name. report_flags() auto-detects this schema by inspecting validity_flag's values, since the column name alone does not identify which check produced it.

#### DO NOT FILTER ON validity_flag != "valid"

This was always a fragile idiom and require_control_evidence = TRUE makes it catastrophic. Under the gate the honest-unknown state "no_control_evidence" is not "valid", and it is normally the overwhelming majority (often more than nine in ten taxa). A downstream validity_flag != "valid" filter would therefore delete nearly the whole dataset.

"not_control_enriched" and "single_site_enriched" are also not "valid", and they are the states that exist precisely to say DO NOT REMOVE THIS. Neither is "insufficient_control_evidence", which means the question was not answerable on the evidence available.

The removal predicate is the invalid_ prefix, never the negation of "valid":


```

# correct to_remove <- startsWith(flagged$validity_flag, "invalid_") # also correct, if you want one named type to_remove <- flagged$validity_flag == "invalid_lab_contaminant" # WRONG, and much worse under require_control_evidence = TRUE to_remove <- flagged$validity_flag != "valid" ```

Anything filtering on the negation of "valid" sweeps the whole middle tier in.

#### Evidence-gated states (require_control_evidence = TRUE)

validity_flag takes these values instead of the score bands:

- "no_control_evidence" -- never detected in any control, so no assessment is possible. An honest unknown, and expected to be the large majority.

- "invalid_{contaminant_type}" -- control rate above sample rate. The name is kept so existing downstream filters on invalid_* keep working.

- "not_control_enriched" -- present in a control but at or below its sample rate. Signal leaking sample -> control, the OPPOSITE direction of travel. Must not be filtered; this is the state the score-band design could not express, and it is what made abundant local taxa look like contaminants. Named for what was measured rather than for a mechanism: a rate comparison alone cannot establish a direction of travel, so the label states only that the taxon is not enriched in controls.

- "insufficient_control_evidence" -- seen in at least one control but fewer than min_control_obs. Not assessable, because a rate built on one observation is not comparable to a rate built on hundreds.

- "single_site_enriched" -- control-enriched, but confined to one site whose samples also carry it. Local, not a systemic source. Distinct from "not_control_enriched": this taxon IS enriched in controls, so the two labels make opposite claims and must not share a name.

- "questionable_{contaminant_type}" -- present in a control with rates that do not separate.

With site_col, three columns are added -- site_breadth_control, site_breadth_sample, control_sites_shared -- and a control-enriched taxon confined to ONE site whose samples also carry it is downgraded to "single_site_enriched".

### flag_failed_libraries(input_df, library_col = "event_id", sample_col = "sample_id", marker_col = "marker", run_col = "run", count_col = "count", taxon_col = "taxon_name", control_samples = NULL, expected_libraries = NULL, fold_threshold = 10, run_fail_fraction = 0.5, min_reference_runs = 3L, reference_depth = NULL, control_contrast_max = 0.5, cleared_runs = NULL, verbose = TRUE)

Flag Sequencing Libraries and Runs That Failed

Asks, before anything else is computed from a run, whether each library actually sequenced. A library is one sample amplified with one marker; a run is the set of libraries of one marker sequenced together. A failed library looks like a sample with few species, and nothing downstream can tell the difference: richness, occupancy and read shares all shrink, and control checks such as 'validate_controls' lose the power to fail anything, which they report as a pass.

| Param | Required | Default | Doc |
|---|---|---|---|
| input_df | yes |  | Long-format data frame, one row per feature x library. |
| library_col | no | "event_id" | Character. Column identifying the sequenced library (a sample-replicate column). Default "event_id". |
| sample_col | no | "sample_id" | Character. Column identifying the physical sample or extract shared across markers. Default "sample_id". |
| marker_col | no | "marker" | Character. Column identifying the marker or assay. Default "marker". |
| run_col | no | "run" | Character. Column identifying the sequencing run (the pool sequenced together); runs are always taken within a marker. Default "run". |
| count_col | no | "count" | Character. Numeric count column. Default "count". |
| taxon_col | no | "taxon_name" | Character or NULL. Feature column, used for richness (features with a positive count). NULL skips richness and the control contrast. Default "taxon_name". |
| control_samples | no | NULL | Character vector of library_col or sample_col values that are negative controls. Controls are not given a library verdict; they feed the control contrast. Default NULL. |
| expected_libraries | no | NULL | Optional data frame with the columns named by library_col, sample_col, marker_col and run_col: libraries known to have been sequenced. Any with no rows in input_df enter at depth 0. Default NULL. |
| fold_threshold | no | 10 | Numeric > 1. How many times below expectation a library must be on BOTH deviations to fail. Default 10. On one real three-marker study the within-sample, cross-marker scatter of healthy libraries had a median absolute deviation of about 2.1-fold, so 10-fold sits about three of those out; two whole-run failures there sat 100-fold low. |
| run_fail_fraction | no | 0.5 | Numeric in (0, 1]. Share of a run's assessed field libraries that must fail (or be low, for "low_yield") for the run verdict. Default 0.5. |
| min_reference_runs | no | 3L | Integer. Runs a marker needs before its reference can expose a whole-run failure. Default 3. |
| reference_depth | no | NULL | Optional named numeric vector, one typical field-library depth per marker (names = marker values). Overrides the data-derived reference for those markers; use it for a marker sequenced in fewer than min_reference_runs runs. |
| control_contrast_max | no | 0.5 | Numeric. Control-over-field richness ratio at or above which the control contrast is reported "collapsed". Default 0.5. |
| cleared_runs | no | NULL | Character vector of "<run>\|<marker>" keys a person has reviewed and chosen to analyse despite a "failed" verdict. The verdict is kept; only exclude_library changes, and the clearance is recorded in attr(, "runs"). Default NULL. |
| verbose | no | TRUE | Logical. Print a per-run summary. Default TRUE. |

**Value:** 'input_df' in its original row order with these columns added: 'library_status' '"failed"', '"low_yield"', '"low_yield_undetermined"', '"pass"' or 'NA' (control, not assessed); see The test. 'library_reason' Plain-English explanation with the numbers. 'run_status' The run verdict; see Two granularities. 'exclude_library' Logical. TRUE for a failed library and for every library of a failed, uncleared run. The workflow should drop these rows from richness, occupancy and read-share summaries and say so in its output. Attribute '"libraries"': one row per library with 'depth', 'richness', 'role', 'own_dev' and 'cross_resid' (log10), 'n_other_markers', 'library_status', 'failure_scope' ('"run"' or '"library"') and 'exclude_library'. Attribute '"runs"': one row per run x marker with library counts by status, 'median_depth', 'reference_depth', 'fold_below_reference', 'median_cross_resid', 'reference_basis' ('"runs"', '"supplied"' or '"too_few_runs"'), 'n_runs_marker', 'failure_basis' ('"cross_marker"', '"single_marker"' or 'NA' when the run did not fail), the control contrast columns, 'n_absent', 'run_status', 'cleared' and 'reason'. Attribute '"libraries_absent"': sample x marker x run combinations with no library although the sample has libraries in another marker of that run. A warning names every failed run and library that is excluded and not cleared: those rows should not be analysed until a person has looked.

#### Why failure is not "few reads"

A genuinely low-biomass sample can yield few reads, so a read-count floor cannot tell a failed library from a sparse but valid sample. The evidence that separates them is the SAME extract sequenced with OTHER markers. If a sample yields 59,000 reads for one marker and 580 for another, the extract was fine and the second library failed. If it is low in every marker, the sample itself is sparse, which is a result, not a failure.

#### Taxonomically narrow markers

Cross-marker evidence shows that the EXTRACT was fine, not that the marker's target taxa were present in it. For a marker that amplifies a narrow group (12S for vertebrates, say), a sample with no such DNA looks exactly like a failed library: low for its marker, fine in the others. On such a marker read "failed" as "failed, or target absent". Agreement among a sample's replicate libraries of the same marker is the evidence that separates the two; this function does not use it, so check it before acting on a scattered failure in a narrow marker.

#### The test

Depths are compared on a log10 scale. For each marker, the reference depth is the median, over runs, of each run's median field-library depth; a median of run medians, so one failed or unusually deep run does not define normal. Each field library then gets two deviations:

- own-marker deviation: its depth relative to its marker's reference.

- cross-marker residual: its own-marker deviation minus the median own-marker deviation of the same sample's libraries in the OTHER markers. It is how far below this sample's other markers the library fell. Libraries judged failed in a first pass are left out of the second pass as predictors for the sample's other markers.

With T = \log_{10}(fold_threshold), a field library is:

- "failed" when BOTH deviations are at or below -T: it is low for its marker AND low relative to its own sample's other markers. Requiring both guards against a run on which the other markers were simply sequenced unusually deep.

- "low_yield" when it is low for its marker but the sample's other markers are comparably low: a sample-level cause (low biomass, poor extraction), not a library failure. Not excluded.

- "low_yield_undetermined" when it is low for its marker and the sample has no other marker to compare with. A single-marker rule cannot tell failure from low biomass, and this says so rather than guess. Not excluded, but reported.

- "pass" otherwise.

- NA (not assessed) for control libraries.

#### Two granularities

A run fails as a whole when a fault hits the library pool (chemistry, loading, a demultiplexing error): every library on it is low. Reporting that as dozens of individual failures would hide the single cause, so each run (run x marker) also gets a verdict, in attr(, "runs"):

- "failed": at least run_fail_fraction of its field libraries failed (failure_basis = "cross_marker"), OR, in a single-marker study or for samples with no other marker, at least run_fail_fraction are low for the marker with no cross-marker evidence against it (failure_basis = "single_marker"): those libraries outnumber any whose other markers are comparably low. A whole run this far below the marker's other runs is taken as a run fault. Needs min_reference_runs runs of the marker or a reference_depth. Every library on the run, controls included, is excluded, and failure_scope is "run".

- "low_yield": at least run_fail_fraction of its field libraries are low for the marker, but the samples' other markers are comparably low. The whole run is weak and the data cannot say whether the libraries or the samples are the cause. Not excluded; read it.

- "pass": neither. Individual failed libraries may still be present (n_failed); they are excluded one by one.

- "not_testable": the marker has fewer than min_reference_runs runs and no reference_depth, so its reference IS this run and a whole-run failure cannot be seen. Individual libraries are still tested against the run. This is a distinct outcome from "pass".

#### Controls

Blanks on a failed run are usually as depth-starved as the field libraries and can be as rich or richer, and control-based tests then have no contrast to work with. Each run reports control_depth_ratio and control_richness_ratio (median control over median field library) and control_contrast: "collapsed" when the richness ratio is at least control_contrast_max, "informative" below it, "no_controls" when the run has none. Richness, not depth, is the informative ratio: sequencing providers often pool libraries to equal depth, so a clean blank can carry as many reads as a field sample while holding a fraction of its features. A collapsed contrast can also occur on a run that sequenced normally, when its blanks carry field-like reads; it is reported, never used to exclude anything.

#### What to pass in

Pass every marker of the study in one table: the cross-marker comparison is the point, and it cannot be made one marker at a time. Include control libraries and samples you do not intend to analyse. sample_col must identify the physical extract that every marker was amplified from, so that the same value appears under each marker.

A library that sequenced nothing has no rows in a long table that keeps only positive counts. Give it one zero-count row, or list it in expected_libraries; otherwise it is invisible. Samples that have libraries in some markers of a run but none at all in another marker of the same run are listed in attr(, "libraries_absent"); they are not given a verdict because the table cannot say whether the library was ever made.

### flag_handler(input_df, datetime_col = "datetime", taxon_col = "taxon_name", group_col = NULL, interval_minutes = 30, handler_taxa = NULL, station_metadata = NULL, deploy_col = "deploy_time", retrieve_col = "retrieve_time", verbose = TRUE)

Flag Detections Near Start or End of a Sampling Period

Identifies detections that occur within a user-specified time interval of the earliest or latest timestamp in each group (e.g., camera station, sampling event). Detections near these edges are likely handler artifacts (researcher setting up or retrieving equipment).

| Param | Required | Default | Doc |
|---|---|---|---|
| input_df | yes |  | Data frame with at minimum a datetime column, a taxon column, and optionally a grouping column (e.g., station or site). |
| datetime_col | no | "datetime" | Character. Column name containing timestamps. The function attempts to parse with several common formats. Default "datetime". |
| taxon_col | no | "taxon_name" | Character. Column name identifying taxa. Default "taxon_name". |
| group_col | no | NULL | Character or NULL. Column name for grouping (e.g., camera station). Min/max times are computed within each group. If NULL, all rows are treated as one group. Default NULL. |
| interval_minutes | no | 30 | Numeric. Minutes from the earliest or latest timestamp within each group to flag. Default 30. |
| handler_taxa | no | NULL | Character vector or NULL. If supplied, only these taxa are flagged (e.g., "Homo sapiens"). Other taxa within the interval receive a score but are flagged "valid". Besides the researcher themselves, this can include any species plausibly present specifically because of handling activity rather than the wildlife the camera is meant to detect -- e.g. a domestic dog accompanying a field crew (c("Homo sapiens", "Canis familiaris")). If NULL, all taxa within the interval are flagged. Default NULL. |
| station_metadata | no | NULL | Data frame or NULL (default). One row per group_col value with real deploy/retrieve timestamps -- see "Edge anchoring" above. Requires group_col to be non-NULL (a single implicit "all" group has no per-station metadata to key on). Must contain group_col plus deploy_col/retrieve_col. |
| deploy_col | no | "deploy_time" | Character. Column name in station_metadata for the true equipment-setup timestamp. Default "deploy_time". |
| retrieve_col | no | "retrieve_time" | Character. Column name in station_metadata for the true equipment-retrieval timestamp. Default "retrieve_time". |
| verbose | no | TRUE | Logical. Print summary messages. Default TRUE. |

**Value:** The input data frame with four columns appended: 'validity_flag' Character. '"valid"' (genuine detection), '"questionable_handling"', or '"invalid_handling"' (probable handler artifact). Fixed column name across every TaxaFlag flag_*() mechanism - see '@section Unified validity schema' above. 'observation_validity' Numeric 0-1. 1.0 for detections outside the interval; decreasing toward 0 as the detection approaches the min/max timestamp. Higher = more likely genuine, lower = more likely a handler artifact. 'validity_reason' Character. Plain-English explanation. 'edge_anchor_source' Character. '"station_metadata"' (real deploy/retrieve times used) or '"detection_data_fallback"' (data-derived min/max used - see "Edge anchoring" above).

#### Details

This is a placeholder implementation for camera trap and similar time-stamped detection data. The datetime column is auto-parsed using as.POSIXct with common format guessing.

#### Edge anchoring

By default (station_metadata = NULL), "deployment edges" are the detection data's own per-group minimum and maximum timestamps -- NOT true setup/pickup times. This means the very first and last GENUINE wildlife detection at a station is always exactly at the edge (minutes_to_edge = 0) and scores maximally suspect, purely as an artifact of how the edge is defined, regardless of whether a handler was ever actually present. Supply station_metadata (one row per group_col value, with real deploy/retrieve timestamps -- the same "external attribute lookup table keyed by a sample/event identifier" pattern already used elsewhere in this ecosystem, e.g. TaxaMatch::join_event_site_metadata()) to anchor edges on the actual deployment window instead. A group present in input_df but absent from station_metadata (or with an unparseable timestamp) falls back to the data-derived min/max for that group only, with a warning() naming it -- this is a real weakening of that group's flag, not a silent one. The output edge_anchor_source column records, per row, whether "station_metadata" or "detection_data_fallback" was used, so a caller can filter or discount rows accordingly. When station_metadata is not supplied at all, every row is fallback -- handler_taxa remains the primary real protection in that case, since it already restricts flagging to a caller-nominated taxon list regardless of edge-anchor quality.

#### Unified validity schema

Output column NAMES are fixed (observation_validity/ validity_flag/validity_reason), matching flag_contaminant's own schema, so every TaxaFlag flag_*() mechanism shares one schema (the "one column, type-qualified values" pattern add_posthoc_assessment uses). report_flags() auto-detects this schema by inspecting validity_flag's values, not just the column's presence, since the column name alone does not identify which check produced it.

### flag_hopped_detections(input_df, event_col = "event_id", taxon_col = "taxon_name", count_col = "count", run_col = NULL, control_samples = NULL, spike_taxa = NULL, spike_samples = NULL, receiver_share = c("equal", "depth"), alpha = 0.01, max_rate = 0.05, verbose = TRUE)

Flag Detections Explained by Read Spillover Between Samples on a Run

Flags individual detections (one feature in one sample) whose read count is no larger than what spillover from the SAME feature elsewhere on the same sequencing run would be expected to deposit there. Spillover covers Illumina index hopping, tag jumps and Nanopore barcode misassignment: every mechanism in which a small fraction of a feature's reads are credited to other samples in the same pool.

| Param | Required | Default | Doc |
|---|---|---|---|
| input_df | yes |  | Long-format data frame, one row per feature x sample. |
| event_col | no | "event_id" | Character. Column identifying the sequenced sample (library, replicate or recording unit). Default "event_id". |
| taxon_col | no | "taxon_name" | Character. Column identifying the feature. A fine-grained feature id (ESV/ASV, or a call/image id for non-sequence data) is preferable to a taxon name, because spillover acts on the feature and does not depend on assignment succeeding. Default "taxon_name". |
| count_col | no | "count" | Character. Numeric count column. Default "count". |
| run_col | no | NULL | Character or NULL. Column identifying the run (the pool in which spillover can occur). When NULL the whole table is treated as one run and a warning says so. |
| control_samples | no | NULL | Character vector of event_col values that are negative controls (field, extraction or PCR blanks). May be NULL when spike_taxa is supplied. |
| spike_taxa | no | NULL | Character vector of taxon_col values that are a NON-NATIVE positive-control spike: a feature that cannot genuinely occur in any field sample. Do not list a native spike here; its field detections would all be flagged. Default NULL. |
| spike_samples | no | NULL | Character vector of event_col values holding the spike (positive controls). Required with spike_taxa. |
| receiver_share | no | c("equal", "depth") | Character. "equal" (default) or "depth"; see The model. "depth" requires a spike on every assessed run. |
| alpha | no | 0.01 | Numeric in (0, 1). Tail probability used three ways: a detection more improbable than this under spillover is "valid"; a control feature more improbable than this is excluded as contamination; and 1 - alpha is the confidence level of the rate's upper bound. Default 0.01. |
| max_rate | no | 0.05 | Numeric. The largest spillover rate treated as physically possible. A run whose evidence implies more is reported as "implausible_rate" and NOT assessed: its detections carry NA. Default 0.05. Published figures: Illumina index hopping on patterned flow cells is typically 0.1-2%, up to ~6% in a PCR-free workflow (Costello et al. 2018, BMC Genomics 19:332); metabarcoding tag jumps ~2.1-2.6% of sequences (Schnell et al. 2015, Mol. Ecol. Resour. 15:1289). On one real three-marker study, blanks on three large runs implied 7-57%: that is abundance-correlated contamination OF THE BLANKS, which blanks overstate (an empty library is amplified until a few molecules fill it), and projecting it onto field samples would have flagged 16% of all 18S detections. |
| verbose | no | TRUE | Logical. Print a per-run summary. Default TRUE. |

**Value:** 'input_df' in its original row order with these columns added: 'observation_validity' Numeric 0-1, x / (x + E): the share of the detection's reads that expected spillover does not account for. Higher = more likely genuine. A ranked screening statistic, not a probability. 'NA' where not assessed. 'validity_flag' '"invalid_index_hop"', '"questionable_index_hop"', '"valid"' or 'NA' - see Verdicts. Shares TaxaFlag's unified validity schema, so 'report_flags' picks it up. 'validity_reason' Plain-English explanation, including why a row was not assessed. 'hop_source_reads' S_{ij}. 'hop_receiver_share' w_j. 'hop_expected', 'hop_expected_upper' E at \hat r and at r_{up}. 'hop_p_spill' P(X >= x) at \hat r. 'hop_basis' '"spike"' or '"controls"'. Attribute '"run_rates"': one row per run with 'n_samples', 'n_controls', 'n_spike_samples', 'control_reads', the evidence used ('basis'), k ('spill_reads'), M ('exposure'), 'rate', 'rate_upper', the separate 'rate_controls'/'rate_spike' estimates, 'n_control_excess', 'hop_signature' (Spearman correlation, across features, between control reads and source reads after exclusion: positive is the spillover signature, near zero means the control reads look like something else) and 'evidence': '"estimated"', '"bound_only"' (no spilled reads observed), '"implausible_rate"' (above 'max_rate'; not assessed) or '"none"' (nothing to estimate from). Also 'dispersion' (the negative-binomial size of the spillover counts; 'Inf' = Poisson) and 'rate_untrimmed' (the naive control-read rate before contamination was excluded, for comparison). Attribute '"control_excess"': the run x feature pairs excluded as contamination, with their control reads, source reads and implied rate. Attribute '"controls_absent"': 'control_samples' with no rows in 'input_df'.

#### Why a flat read threshold does not work

Spilled reads scale with how abundant a feature is ELSEWHERE on the run, not with a constant. A floor of, say, 100 reads is simultaneously too lax for a feature carrying millions of reads on the run (it can spill hundreds into every sample) and too strict for a genuinely rare feature (which spills essentially nothing, so its 30-read detection is real). This function therefore compares each detection with its OWN expected spillover.

#### The model

For feature i and receiving sample j on one run, E_{ij} = r \times S_{ij} \times w_j where S_{ij} is the feature's reads in every OTHER sample on the run (the source), w_j is sample j's share of what spills, and r is the run's spillover rate: the fraction of a feature's reads that end up credited to some other sample. A sample that holds all of a feature's reads on the run has no source and can never be flagged.

receiver_share = "equal" (the default) gives every other sample on the run the same share, 1/(n-1). "depth" makes the share proportional to the sample's reads. "depth" CANNOT be estimated from negative controls: a blank holding nothing but spilled reads has a depth made of those same reads, so its share is caused by the spillover it is meant to measure and the estimated rate comes out near 1 whatever the truth. It is only meaningful with a spike, whose receivers are field samples with their own DNA; with a spike, fit both and compare.

r is ESTIMATED PER RUN from the data, never assumed, from one of two kinds of evidence:

- A non-native spike (spike_taxa in spike_samples). Every spike read outside its positive control is spillover, with nothing else that can explain it, and every other sample on the run is a receiver. This is the better estimator and is used whenever a run has one.

- Negative controls (control_samples). A control's reads of a feature are spillover or contamination, and the two are separated by shape: spillover is proportional to the feature's source, so all spilling features share one rate, whereas a contaminant carries far more control reads than its source can explain. The rate is fitted, every feature whose control reads are improbably high under it (one-sided Poisson, alpha) is excluded, and the rate is refitted until no further feature is excluded. Excluded features are reported in attr(, "control_excess") as reagent contamination candidates -- a different problem, for flag_contaminant. Low-level contamination by a feature that is also common in the field cannot be told apart from spillover and inflates r, which errs toward flagging more.

The estimate is \hat r = k / M, with k the spilled reads observed and M their expected count at r = 1 (the exposure): the Poisson maximum likelihood estimate. The upper bound r_{up} is the exact one-sided Poisson upper confidence limit on k at level 1 - alpha, divided by M.

#### Verdicts

A detection with x reads is compared with a Poisson count of mean E. It is:

- "invalid_index_hop" when P(X \ge x) > alpha at \hat r: the estimated rate alone explains it. Requires k > 0, i.e. spillover was actually observed on that run.

- "questionable_index_hop" when it is explained only at the upper bound r_{up}. On a run whose controls held NO spilled reads (k = 0) this is the only tier available, and how much it flags depends on how much the controls could have caught: a clean run with many controls and abundant sources bounds r tightly and flags little. The reason string says which case applies.

- "valid" otherwise.

- NA (not assessed) for control and spike samples, zero-count rows, and every row of a run with no usable evidence. A run without evidence is reported, never given a verdict: see attr(, "run_rates").

Any read of a spike feature outside spike_samples is "invalid_index_hop" regardless of the test, because a non-native spike cannot be genuinely present in a field sample.

Spillover counts are over-dispersed relative to a Poisson; this under-flags at the invalid tier, which the questionable tier partly offsets. The flags are a screening statistic; the workflow decides what to drop.

#### What to pass in

Pass the WHOLE run table, including controls, every feature and samples you do not intend to analyse: sources S_{ij} and sample counts are computed from it, and a pre-filtered table understates both. Pass one marker/assay at a time. run_col must identify the physical pool that was sequenced together, which is not necessarily a field trip or collection event.

A clean control must still be present. A long table that keeps only positive counts has no row at all for a control that sequenced nothing, and that control then counts for nothing: its run can read as having no evidence when it in fact has the best evidence there is. Give each such control one zero-count row carrying its run_col. A control listed in control_samples but absent from input_df is reported in attr(, "controls_absent").

#### Before trusting a negative result

"Nothing flagged" on a run whose evidence is "bound_only" means the test had limited power, not that there was no spillover. Read rate_upper: it is the largest rate the controls cannot exclude.

#### What "not spillover" does not mean

This function answers one question: is this detection no larger than what the SAME feature's abundance elsewhere on the run would spill into this sample? A clean verdict is therefore evidence about spillover and about nothing else. In particular it does not mean the detection is real.

A detection far ABOVE the run's spillover bound is correctly left unflagged, and that is exactly the shape of the artefacts this test cannot see: well-to-well or reagent carry-over, which does not scale with a feature's run-wide abundance; a mislabelled reference sequence; a genuinely sequenced but non-local organism, such as food, bait or wastewater DNA. A feature can be correctly judged "not spillover" and still not be plausible biology.

So read a clean verdict as narrowing the explanations, not as clearing the detection, and pair it with flag_contaminant for control-based contamination and with range or habitat evidence for whether the organism belongs where it was found.

### flag_watch_candidates(consensus_df, match_df, watch_taxa, observation_col = "observation_id", taxon_col = "taxon_name", score_col = "score_original", winner_col = "primary_taxon", score_margin = 0)

Flag observations where a watch-list species outscores the consensus winner

This function implements the likelihood-side half of the watch-list surveillance guarantee: since a watch-list species' occurrence prior stays low by design, the posterior alone cannot guarantee it surfaces, so raw match scores are compared directly instead (see *Why this exists*, below).

| Param | Required | Default | Doc |
|---|---|---|---|
| consensus_df | yes |  | Data frame, one row per observation -- TaxaAssign::posterior_consensus() output (or anything carrying observation_col and winner_col). |
| match_df | yes |  | Data frame of raw match candidates (e.g. the workflow's match_obj_restored) carrying observation_col, taxon_col, and score_col. |
| watch_taxa | yes |  | Character vector of watch-list species names (e.g. the workflow's INVASIVE_TAXA). Required, no default. |
| observation_col | no | "observation_id" | Character. Observation identifier column shared by both inputs. Default "observation_id". |
| taxon_col | no | "taxon_name" | Character. Candidate taxon-name column in match_df. Default "taxon_name". |
| score_col | no | "score_original" | Character. Raw match-score column in match_df (higher = better). Default "score_original". |
| winner_col | no | "primary_taxon" | Character. Winner column in consensus_df. Default "primary_taxon" (the top-posterior candidate -- present even when the final consensus upranked to a coarser rank). |
| score_margin | no | 0 | Numeric >= 0. Flag when the best watch score is within this many score units of the reference score (0 = must tie or exceed). Default 0. |

**Value:** 'consensus_df' with four added columns: watch_flag Logical. TRUE when a watch-list species scored within 'score_margin' of the winner's own best score. watch_taxon The best-scoring watch-list species for this observation (NA when no watch candidate exists). watch_score That species' best raw score (NA likewise). watch_reference_score The reference score the comparison used (winner's own best match, or best non-watch score).

#### Why this exists

A watch-list species' occurrence prior should be a small, honest probability of local presence (the GreatLakes2023 calibration adopted w = 0.05) -- which correctly stops such species from vetoing the species- level resolution of genuinely observed natives, but also means a watch species will rarely surface in the posterior-driven consensus at all. The surveillance requirement ("if a watch species matches this observation well, a reviewer must see that, every time") cannot be honored through the posterior without breaking the prior's honesty -- Bayes correctly down-weights an unobserved species against an abundant native at any likelihood ratio short of overwhelming. So the guarantee is honored on the LIKELIHOOD side instead: this function compares raw match scores only -- no priors, no likelihood model -- and flags every observation where a watch-list species scored at least as well as (within score_margin of) the consensus winner's own best match. The flag is purely informational: it never changes consensus_taxon/consensus_rank, matching this package's additive-column convention.

#### How the comparison works

Per observation: the best raw score among watch-list candidates is compared against a reference score -- the winner's (winner_col, default primary_taxon) own best match score in match_df, or, when the winner has no match row of its own (an unreferenced or rank-expanded winner), the best score among non-watch candidates. The observation is flagged when watch_score >= reference_score - score_margin. An observation whose winner IS itself a watch-list species is never flagged (surveillance already succeeded through the front door). Observations with no watch-list candidate rows at all get watch_flag = FALSE with NA detail columns.

### report_flags(flagged_data, verbose = FALSE)

Generate a Report Section for Quality Flagging

Summarizes the quality flags applied by TaxaFlag into a structured 'report_section' object (from TaxaTools). Auto-detects which flag types are present in the data. Works standalone or feeds into 'TaxaTools::assemble_report()' for a unified pipeline report. Any reference-support columns from 'TaxaLikely::annotate_reference_support()' are reported next to the flags and kept out of every flag count: they are information, not a flag, and *a low reference count does not mean a call is wrong*.

| Param | Required | Default | Doc |
|---|---|---|---|
| flagged_data | yes |  | Data frame. Assignment data with flag columns from flag_contaminant, flag_handler, and/or review_assignments, optionally also carrying reference-support columns from TaxaLikely::annotate_reference_support(). Those columns are additive and order-independent, so annotating before or after any flag_*() call or add_posthoc_assessment gives the same result. |
| verbose | no | FALSE | Logical. Print summary messages. Default FALSE. |

**Value:** A 'report_section' object with: methods Template text describing which flags were applied. results Template text summarizing flag counts. params Named list of flagging parameters. statistics Named list of flag counts. When reference-support columns are present, also 'reference_support': one entry per column prefix giving 'n_rows', 'n_with_count', the 'min'/'median'/'max' count, 'n_at_model_max' (censored rows), and 'basis' (how many rows fall in each situation, including the '"no_model_row"' rows that have the least reference support of all). None of it is added to 'n_flagged'.

### review_assignments(input_df, taxon_col = "consensus_taxon", taxon_rank_col = NULL, plausible_taxa_col = NULL, irreducible_only = TRUE, consensus_posterior_col = NULL, winner_prior_col = NULL, winner_rank_expanded_col = "winner_rank_expanded", consensus_provenance = TRUE, plausible_posteriors_col = NULL, consensus_plausibility_col = "consensus_plausibility", consensus_discrimination_col = "consensus_discrimination", dist_nearest_occupied_km_col = NULL, patch_diameter_km_col = NULL, beyond_buffer_col = NULL, inat_in_range_col = NULL, inat_n_observations_col = NULL, inat_matched_name_col = NULL, context, target_group = NULL, marker = NULL, data_type, llm_fn = getOption("TaxaID.llm_fn", TaxaTools::call_api), model_label = NULL, taxa_per_call = 15L, max_tokens = NULL, max_retries = 2L, pause_seconds = 1, cache_dir = NULL, on_unreviewed = c("warn", "error", "ignore"), verbose = TRUE, poor_absolute_fit_col = "poor_absolute_fit", best_identity_col = "best_identity", sites = NULL, site_col = "site")

LLM Expert Review of Taxonomic Assignments

Sends unique taxa from a consensus table to an LLM for structured expert review. The LLM assesses each taxon for habitat fit, geographic plausibility, contaminant risk, and (optionally) taxonomic scope. It also suggests plausible alternative taxa where appropriate.

| Param | Required | Default | Doc |
|---|---|---|---|
| input_df | yes |  | Data frame with at minimum a column of taxon names. |
| taxon_col | no | "consensus_taxon" | Character. Column name for consensus taxon. Default "consensus_taxon". |
| taxon_rank_col | no | NULL | Character or NULL. Column name for consensus rank (e.g., "species", "genus"). When supplied, the rank is included in the prompt for context. Default NULL. |
| plausible_taxa_col | no | NULL | Character or NULL. Name of the list column containing per-observation plausible candidate taxa (e.g., "plausible_taxa" from TaxaAssign::posterior_consensus()). When supplied, the LLM receives the full candidate set for each unique combination rather than just the upranked consensus taxon. Singletons are reviewed by species name as usual. Unresolved rows (empty candidate set) are skipped. Default NULL (current behaviour -- deduplicates on taxon_col). |
| irreducible_only | no | TRUE | Logical. When plausible_taxa_col is supplied and an irreducible_consensus column is present in input_df (added by TaxaAssign::add_slash_taxon()), only candidate sets where irreducible_consensus == TRUE are reviewed. Non-irreducible rows receive NA review columns. When irreducible_consensus is absent, all unique candidate sets are reviewed with a message. Ignored when plausible_taxa_col = NULL. Default TRUE. |
| consensus_posterior_col | no | NULL | Character or NULL. Column name for TaxaAssign::posterior_consensus()'s consensus_posterior -- the pipeline's own statistical confidence in the winning taxon. When present, the median value across every row sharing a taxon/candidate-set label is shown to the LLM as context (e.g. "pipeline posterior=0.81"), so a sharp disagreement between the pipeline's confidence and the LLM's ecological plausibility judgment can be surfaced in review_comment. Purely additive text -- never changes which rows are reviewed or any output column. Silently skipped when the named column is absent from input_df. Default NULL: the review is not shown this, see What the review is shown, and what it is not. Pass "consensus_posterior" to show it. That name is posterior_consensus()'s own output column. |
| winner_prior_col | no | NULL | Character or NULL. Column name for posterior_consensus()'s winner_prior -- the occurrence- database prior for the winning taxon. Same treatment as consensus_posterior_col: shown as median context (e.g. "occurrence prior=0.42"), silently skipped when absent. Default NULL: the review is not shown this, see What the review is shown, and what it is not. Pass "winner_prior" to show it. |
| winner_rank_expanded_col | no | "winner_rank_expanded" | Character or NULL. Column name for ANY logical column meaning the sequence does not resolve this call to species. It is read PER ROW while the note is per taxon, so the wording follows the taxon's own detections: flagged on all of them, the bracket says "the sequence does not resolve this call to species"; flagged on some, "... on some of its detections"; flagged on none, there is no note. NA counts as unflagged, so a column that is NA where it was never computed manufactures nothing. Nothing is said about what supplied the name instead, and the argument's own name is not part of the contract. Two columns that mean it, as examples rather than as the definition: posterior_consensus()'s winner_rank_expanded, TRUE when a species-level call was manufactured by join_priors()'s coarse-rank expansion with nothing in the sequence discriminating between candidates; and a column a caller derives itself, such as "the consensus is at species while the likelihood's own consensus rank is coarser". Either is correct input. Silently skipped when the named column is absent. Default "winner_rank_expanded"; NULL to suppress the note. See What the review is shown, and what it is not. |
| consensus_provenance | no | TRUE | Logical (default TRUE). When TRUE and input_df carries posterior_consensus()'s consensus_hypothesis_type, a call that landed on an UNREFERENCED row adds one note: "named taxon has NO reference sequence". That is the whole of it. The note once continued with the scope the name came from, that scope's rank, and how many species the records held in it; all three report what the occurrence records CONTAIN, so they are gone -- see What the review is shown, and what it is not. What is left matters because no reference sequence exists for such a taxon: the sequence settled only that an unreferenced relative beats every referenced candidate, and the name came from somewhere other than the sequence -- sibling named rows carry identical likelihoods, so the sequence cannot choose between them. Nothing else the review is shown reveals this, which is why the note is on by default: consensus_posterior and winner_prior are not sent at all, and winner_rank_expanded is a different mechanism. Silently skipped when the column is absent. |
| plausible_posteriors_col | no | NULL | Character or NULL. Column name for posterior_consensus()'s plausible_posteriors list column (per-candidate posterior weights, positionally aligned with plausible_taxa_col). Only used when plausible_taxa_col is supplied. When present, each multi-candidate label's per-candidate weights are averaged across every row sharing that label and shown to the LLM (e.g. "candidate weights: Bos javanicus 72%, Bos primigenius 28%"), so review_comment can speak to the specific weaker member instead of the group as an undifferentiated set. Silently skipped when absent. Default NULL: the review is not shown this, see What the review is shown, and what it is not. Pass "plausible_posteriors" to show it. |
| consensus_plausibility_col | no | "consensus_plausibility" | Character or NULL. Column name for add_posthoc_assessment()'s consensus_plausibility -- specifically its "unprecedented" value (no local occurrence record at all, a pipeline-computed fact, never a threshold on a prior VALUE -- see that function's own docs for why). When present, shown to READ but never shown: it says "no local occurrence record at all", which is a statement about the occurrence data, so it does not enter the prompt -- see What the review is shown, and what it is not. It populates the deterministic geographic_disagreement_basis output column, and that is the whole of what it does. Silently skipped when absent. Default "consensus_plausibility"; NULL gives up that column. |
| consensus_discrimination_col | no | "consensus_discrimination" | Character or NULL. Column name for add_posthoc_assessment()'s consensus_discrimination -- specifically its "indistinguishable" value (a one-sided tail probability says a confusable relative could score just as well). That is a statement about the match scores, so unlike consensus_plausibility_col it IS shown, as "pipeline flags INDISTINGUISHABLE: ...", as well as populating geographic_disagreement_basis. Default "consensus_discrimination". Set to NULL to disable. |
| dist_nearest_occupied_km_col | no | NULL | Character or NULL. Column name for check_gbif_tile_range()'s dist_nearest_occupied_km -- distance from the study site to the nearest GBIF-mapped occurrence of the taxon, worldwide. Shown as median context (e.g. "GBIF: nearest occurrence ~41km away") alongside patch_diameter_km_col when both are present. Silently skipped when absent. Default NULL: the review is not shown this, see What the review is shown, and what it is not. Pass "dist_nearest_occupied_km" to show it. |
| patch_diameter_km_col | no | NULL | Character or NULL. Column name for check_gbif_tile_range()'s patch_diameter_km -- shown alongside dist_nearest_occupied_km_col as a rough size for the occupied area found (see "Spatial context" below for why this matters to interpretation). Silently skipped when absent, or when dist_nearest_occupied_km_col is not shown. Default NULL: the review is not shown this, see What the review is shown, and what it is not. Pass "patch_diameter_km" to show it. |
| beyond_buffer_col | no | NULL | Character or NULL. Column name for check_gbif_tile_range()'s beyond_buffer -- when TRUE, shown instead of the distance/patch note as "GBIF: no occurrence found anywhere globally". Silently skipped when absent. Default NULL: the review is not shown this, see What the review is shown, and what it is not. Pass "beyond_buffer" to show it. |
| inat_in_range_col | no | NULL | Character or NULL. Column name for TaxaFetch::check_inat_range()'s in_range. Shown as "in range"/"outside range" alongside inat_n_observations_col/inat_matched_name_col when present. Silently skipped when absent. Default NULL: the review is not shown this, see What the review is shown, and what it is not. Pass "in_range" to show it. |
| inat_n_observations_col | no | NULL | Character or NULL. Column name for check_inat_range()'s n_observations. Default NULL: the review is not shown this, see What the review is shown, and what it is not. Pass "n_observations" to show it. |
| inat_matched_name_col | no | NULL | Character or NULL. Column name for check_inat_range()'s matched_name -- the taxon iNaturalist's own name search actually resolved the query to, which is not always the query taxon itself. When it differs from the taxon under review, this is flagged in the prompt as "matched to '...' (name differs from query)" -- a plain factual annotation, not a judgment (see "Spatial context" below). Default NULL: the review is not shown this, see What the review is shown, and what it is not. Pass "matched_name" to show it. |
| context | yes |  | Named list or data frame describing the study context. Recognised fields: geography, habitat (or main_habitat), date. A build_context() output works directly: with no explicit geography, its geographic_hint and ecoregion are combined as "hint (ecoregion)", so the wording you supplied is not replaced by the single ecoregion synthesised for the whole taxon list. Supply geography yourself to control the line exactly -- most useful when a study spans more than one ecoregion: the synthesised ecoregion is a single string for the whole taxon list, so on a multi-ecoregion study the parenthetical names only one of them and is narrower than the study. At minimum, supply geography and habitat. |
| target_group | no | NULL | Character or NULL. Taxonomic target group (e.g., "fish", "birds"). When supplied, the LLM populates llm_scope_plausibility. Default NULL. |
| marker | no | NULL | Character or NULL. Molecular marker or detection method (e.g., "12S", "COI", "camera trap"). Provides contaminant context. Default NULL. |
| data_type | yes |  | Character. Detection method: one of "eDNA", "acoustic" or "image". REQUIRED -- there is no default, because the value changes the contaminant-assessment guidance the LLM is given, and a wrong assumption there is silent. State the method explicitly. |
| llm_fn | no | getOption("TaxaID.llm_fn", TaxaTools::call_api) | Function. LLM provider function with signature function(prompt_str, ...). Default TaxaTools::call_api. Known footgun: call_api()'s provider auto-detection is set up by TaxaTools's own .onAttach(), which only runs via library(TaxaTools) -- calling this function from a fully-namespaced script (no library() calls at all) never triggers it, and call_api() silently falls back to degraded/uniform output rather than erroring. If every plausibility column comes back suspiciously uniform, pass llm_fn explicitly, e.g. function(p) TaxaTools::call_api(p, provider = "anthropic"). No sampling temperature is set here: the default path calls call_api() with the provider's default. Some current models reject the temperature parameter outright (HTTP 400, "temperature is deprecated for this model"), so set one in your own llm_fn only for a model that accepts it. The cache_dir key fingerprints the deparsed SOURCE of llm_fn: a temperature, model or provider written literally into it is covered, and changing it moves the key. One supplied indirectly -- from a variable, an option or a closure over a value -- is invisible to the key; after changing such a value, use a new cache_dir or a new model_label. |
| model_label | no | NULL | Character or NULL. A name for the model behind llm_fn, recorded in the cache key so a verdict obtained from one model is never served to a call asking another. Required whenever cache_dir is set and llm_fn is a function you wrote: all that can be seen of such a closure is its source text, and a wrapper written function(p, ...) call_api(p, model = MODEL, ...) deparses to the variable NAME "MODEL", not to the model it holds -- so switching MODEL would give a byte-identical key and serve the first model's verdicts to the second run, silently. That call now stops and asks for this argument. Default NULL is still accepted with no cache, and for an llm_fn a loaded namespace can name (such as TaxaTools::call_api itself), where the identity is derived from options("TaxaID.provider") and the function. Even then it names the FUNCTION, not the model a tier resolves to, so a cached call warns and points here. What it does NOT capture is anything else your wrapper pins -- temperature, max_tokens, a system prompt, a reasoning effort. Two runs that differ only in one of those share a key, so give them different model_labels when you compare them. |
| taxa_per_call | no | 15L | Integer. Maximum taxa (or candidate sets) per LLM call. Default 15L. Candidate-set entries are longer than single taxon names; consider reducing to 8--10 when using plausible_taxa_col. |
| max_tokens | no | NULL | Integer or NULL. Maximum response tokens requested from llm_fn (forwarded as llm_fn(prompt, max_tokens = max_tokens) whenever supplied). Default NULL -- does not pass max_tokens at all, so llm_fn's own default applies (16000L for TaxaTools::call_api()). Raise this if max_retries alone isn't resolving truncation warnings for your data -- e.g. a long, multi-marker marker string can inflate per-taxon response length enough that even the smallest retry sub-batch still truncates. |
| max_retries | no | 2L | Integer. The per-batch retry budget, shared by two mechanisms. (1) When a batch's LLM response is truncated, empty, or unparseable, the batch is automatically split in half and retried -- a smaller batch requests a proportionally shorter response, directly relieving token-budget pressure. (2) When a response parses cleanly and is the right shape but simply OMITS specific taxa, those taxa (and only those) are re-asked in a follow-up call. The second case is not truncation, so the halving retry never fires for it -- see @section Unreviewed rows for how omitted taxa are recovered instead. Both stop after max_retries attempts and fall back to NA defaults for whatever is still missing. Neither applies to a hard llm_fn error (e.g. network/auth failure): a smaller or narrower batch can't fix that, so it is reported immediately without retrying. 0L disables both mechanisms, meaning exactly one call per batch. Default 2L. |
| pause_seconds | no | 1 | Numeric. Seconds to pause between LLM calls. Default 1. |
| cache_dir | no | NULL | Character or NULL (default). Directory for the per-taxon review cache. NULL disables caching entirely. Supplying a directory makes a re-run REPRODUCIBLE and stops it re-paying for verdicts already obtained: the review is a judgement, and two runs on identical input can disagree. One small .rds per reviewed taxon, keyed on everything that can move a verdict -- the taxon label and rank, its attached pipeline/weight/spatial notes, context, target_group, marker, data_type and the candidate-set path -- so changing any of them is correctly a miss. Manage it with taxaflag_clear_cache(), which uses the same TaxaTools::list_cache_files() engine as the other packages' cache helpers, so it does not accumulate unmanaged. |
| on_unreviewed | no | c("warn", "error", "ignore") | Character. What to do when taxa still have no verdict after the re-asks: "warn" (default) reports them and continues, "error" stops the run, "ignore" is silent. The residue is recorded on the result either way (see @section Unreviewed rows). Production workflows pass "error": an unreviewed row is dropped by any export filter that tests llm_* != "unlikely", so under one of those a run with residue produces a species list that is silently short. |
| verbose | no | TRUE | Logical. Print progress messages. Default TRUE. |
| poor_absolute_fit_col | no | "poor_absolute_fit" | Character or NULL. Column name for TaxaLikely::evaluate_likelihoods()'s poor_absolute_fit, as passed through by posterior_consensus(): TRUE when the unit's best raw match identity reaches no rank threshold for the marker. Likelihoods are normalised to the unit maximum, so such a call can still carry a high posterior. When TRUE for any row sharing a label, one fact line (e.g. "best match identity 86.1% is below every rank threshold for this marker (poor absolute fit)") is added to that taxon's pipeline notes; FALSE or NA adds nothing. Because the note is part of what is reviewed, a change in the flag changes the cache key. Silently skipped when absent. Default "poor_absolute_fit". Set to NULL to disable. |
| best_identity_col | no | "best_identity" | Character or NULL. Column name for the best_identity (percent). Shown for EVERY taxon that has one, as "best match identity 99.4%" -- it is the most direct sequence evidence there is about the name, and likelihoods are normalised to the unit maximum, so the best of a poor set reads as a confident call and the raw identity is the only thing that says otherwise. Where poor_absolute_fit_col flags the row the same number is quoted inside that note instead. Silently skipped when absent. Default "best_identity"; NULL to suppress the number. |
| sites | no | NULL | NULL (default) or a data frame of study sites with columns site (unique names), lat and lon (decimal degrees; extra columns are ignored). When supplied the LLM is shown the sites (sorted south to north) and asked for each taxon's range LIMITS; the site and study verdicts are computed from them here, which adds the per-row llm_geographic_plausibility_site column; see @section Site-aware geography. With NULL nothing changes: the prompt, the cache key and the output columns are exactly those of a call without this argument. |
| site_col | no | "site" | Character. Column of input_df whose values match sites$site. Only read when sites is supplied (an error if the column is absent then); non-NA values not found in sites$site are named in a warning and those rows get the study-wide verdict. Not part of the cache key, since it does not change the prompt. Default "site". |

**Value:** The input data frame with the review columns appended: 'llm_habitat_plausibility' likely / possible / unlikely, derived in code from 'llm_p_habitat'; see '@section The answer is a probability'. See '@section Column naming' below for why this and the next three columns carry an 'llm_' prefix. 'llm_geographic_plausibility' likely / possible / unlikely. 'llm_scope_plausibility' likely / possible / unlikely, or 'NA' if 'target_group' not supplied. 'llm_contamination_risk' high / moderate / low. 'review_alternatives' Comma-separated plausible alternatives, or 'NA' 'review_lower_hypotheses' Comma-separated finer-rank taxa, or 'NA'. Always 'NA' when 'plausible_taxa_col' is supplied (candidates already known). 'review_confidence' high / moderate / low 'review_comment' Free-text note, or 'NA' 'geographic_disagreement_basis' 'NA' (no disagreement, or the pipeline columns needed to check were unavailable), or one of '"unprecedented"'/'"indistinguishable"'/ '"unprecedented+indistinguishable"' - *deterministic*, code-computed, not an LLM output: fires whenever 'llm_geographic_plausibility %in% c("likely","possible")' despite 'consensus_plausibility_col == "unprecedented"' and/or 'consensus_discrimination_col == "indistinguishable"'. See '@section Geography guidelines' below for why this exists as a deterministic column rather than relying on 'review_comment' alone. 'llm_p_habitat', 'llm_p_habitat_lo', 'llm_p_habitat_hi' The habitat probability the model gave and the 90% range it stated for it. 'llm_p_transported' Probability that the taxon's DNA could plausibly reach these samples from adjacent habitats. Asked separately from residency so that "could have washed in" is not scored as "lives here". Output only: no rule reads it. 'llm_p_scope', 'llm_p_scope_lo', 'llm_p_scope_hi' Likewise for scope. 'llm_p_contamination' The contamination probability. 'llm_p_geographic' The study-wide geographic probability: with 'sites', the MAXIMUM over the taxon's detected sites. The stated 90% ranges feed no rule either. They are kept because they were measured to be 5-10 times the model's own run-to-run spread, so they express uncertainty about the TAXON rather than noise, which is worth having in front of a reviewer. When 'sites' is supplied the data frame also carries 'llm_geographic_plausibility_site' (see '@section Site-aware geography') and an 'attr(result, "geographic_by_site")' data frame, one row per reviewed taxon, giving the parsed range answer ('rule', 'range_south_lat', 'range_north_lat', 'p_inside_range', 'p_outside_range', 'sites_outside_range' as a semicolon-separated string, 'n_unknown_sites', and 'how', which records a swap, an ignored site name or a fallback). 'sites' alone also adds 'llm_p_geographic_site', 'llm_p_inside_range', 'llm_p_outside_range', 'llm_range_known', 'llm_range_south_lat' and 'llm_range_north_lat'. Also carries a '"review_cuts"' attribute naming the four cut points the verdicts were derived with. The cuts are code rather than part of the cache key, so a saved result would otherwise carry verdicts with no record of how they were read off the probabilities. Also carries '"unreviewed_taxa"' (character vector, possibly empty - the taxon/candidate-set labels the LLM never returned a verdict for) and '"n_unreviewed_rows"' (integer - input rows left with 'NA' in every 'llm_' column) attributes; both are ALWAYS present. See '@section Unreviewed rows'. Attributes do not survive a 'dplyr' verb, so read them immediately after the call. Also carries an '"llm_prompts"' attribute - a named list of the exact prompt string sent for each LLM call (named by batch number, with an '"a"'/'"b"' suffix per retry sub-batch split, e.g. '"2b"'). Inspect via 'attr(reviewed, "llm_prompts")' to see precisely what the LLM was asked, e.g. before trusting an unexpected result or when tuning 'context'/'target_group'/'marker'.

#### Details

When plausible_taxa_col is supplied, the function deduplicates on candidate sets rather than consensus_taxon. Each unique combination of plausible species becomes one LLM query, giving the LLM full species-level context rather than only the upranked LCA name. This is especially useful when multiple observations share the same genus-level consensus but differ in which specific candidates they contain.

Works with any data frame containing a taxon column -- not restricted to TaxaAssign output. Context (geography, habitat) can be supplied as a build_context() object from TaxaAssign, or as a simple named list.

#### Candidate-set join key

On the candidate-aware path, review results are joined back to input rows by the SORTED candidate set, not by the display label. The label (consensus_OTU) is ordered by posterior so the most-supported taxon reads first, which means one biological unit can carry "A/B" on one observation and "B/A" on another; joining on the label would leave one of them unmatched and therefore unscored. Sets are also deduplicated canonically, so each unit is reviewed exactly once regardless of which ordering appears in the data. Display labels are unchanged.

#### Unreviewed rows

An LLM response can parse cleanly, be the right length, and still leave specific taxa out -- consistently the long compound slash labels, i.e. the hardest rows, not random ones. That is not truncation, so the halving retry alone would not catch it. Without a dedicated safeguard those taxa would be filled with NA in all four llm_ columns. The workflow template and the DAG snippet FLAG on those columns and drop nothing, but an export chain written != "unlikely" discards NA, so under one of those an unreviewed observation would be silently removed from the final species list.

A taxon the model answered for but whose answer is unusable counts as omitted too, and for the same reason. The probabilities are the answer, so a value outside 0--1, or one that is not a number at all -- 85 for a percentage, "high" for a category -- leaves that verdict NA while review_confidence and review_comment arrive intact. Such a row is treated as omitted: it is re-asked and it is never cached.

The test is ANY of the probabilities that drive a decision, not all of them: p_habitat, p_contamination, geography, and p_scope when target_group is supplied. A row that answered three questions and fumbled the fourth still carries one NA that the export filters discard without a word. p_outside_range is deliberately NOT in that set: its absence gives the inside probability at every site, which never manufactures an "outside" the model did not state. Each unusable answer is named, with its failing fields, in a warning() -- not only when verbose -- and a row still failing after every re-ask is counted in attr(result, "n_unreviewed_rows") like any other omission.

Three mechanisms close this. (1) Omitted taxa are re-asked, alone, up to max_retries times; the cost is pay-per-failure, and the re-asking stops early when a re-ask recovers nothing. (2) An unreviewed taxon is never cached -- a cached entry holding no verdict is treated as a MISS, so an existing cache heals itself. (3) Whatever residue survives is loud: named in attr(result, "unreviewed_taxa"), counted in attr(result, "n_unreviewed_rows"), and escalated per on_unreviewed.

A downstream filter is deliberately not second-guessed here: a chain written != "unlikely" drops NA whatever this function does about it. Keeping an unreviewed row in a species list would put an unvetted taxon in the output distinguishable only by its NAs; stopping the run instead makes the decision per-run and explicit.

#### Column naming

The four independent LLM judgments (llm_habitat_plausibility/ llm_geographic_plausibility/llm_scope_plausibility/ llm_contamination_risk) carry the llm_ prefix because they are independent LLM judgments -- by design NOT derived from or gated by any pipeline-computed value (see @section Pipeline context below). An unprefixed name would read as pipeline output. The LLM's own JSON response schema (what .build_review_prompt() asks for and .parse_review_response() parses) uses the bare names internally -- only the final output column names carry the prefix.

#### Geography guidelines

Two conditional GUIDELINES bullets shape the geographic rating, each added only when a taxon in the batch carries the matching bracket fact:

- "pipeline flags INDISTINGUISHABLE" (a confusable relative could score as well) weakens confidence in the name only and must not by itself lower the habitat, geographic or scope probability. The same holds for a "(poor absolute fit)" note, and for the note saying the sequence did not resolve the call to species.

- "pipeline call: <taxon> (<rank>)", shown when the reviewed label is not the call itself (a species label on a genus or family call): the call at its rank is the claim, and the species are candidates within it.

There is no UNPRECEDENTED bullet, because there is no UNPRECEDENTED note: "no local occurrence record at all" is a statement about the occurrence data and the flag is read without being shown (see What the review is shown, and what it is not). What that bullet used to say -- that absence of a citeable record is not evidence of absence, and that an unrecalled range deserves an intermediate probability rather than a low one -- is in the UNCONDITIONAL geography text, which is the right place for it: it is true of every rare taxon, not only of the ones the pipeline flagged. The harder earlier form of that rule ("cite a local record or rate it unlikely") rated widely introduced species out of range whenever the model could not recall a record on that draw, which is why it is guidance and not a rule.

Prompt compliance is never guaranteed, and the model is not shown the UNPRECEDENTED flag at all, so the deterministic geographic_disagreement_basis output column (see @return) marks every row whose derived geographic verdict is likely or possible despite that flag or the INDISTINGUISHABLE one; filter on it to audit those rows. For UNPRECEDENTED it is the ONLY signal, by design: the review reaches its geographic verdict without knowing the records are empty, and this column is where the two are compared afterwards.

Each taxon line carries an id ([T1], [T2], ...) that the answer must echo; answers are matched by id first, then by name, so a long candidate-set label echoed back reformatted is still matched. A response matching none of several sets is treated as failed (halved and retried), and an omission a re-ask cannot recover is re-asked one set per call.

#### The answer is a probability

The LLM is asked for a probability for each judgement, not a category, and the llm_*_plausibility / llm_contamination_risk columns are derived from those probabilities here. The cuts are unlikely < 0.10 <= possible < 0.70 <= likely, and for contamination low < 0.20 <= moderate < 0.70 <= high.

Why: asking for a probability and cutting it in code repeated more of its decisions between two asks than asking for the category did. That pair was measured on habitat and scope wording written for one study; on the wording this package ships the review repeats fewer of its decisions, and not enough more than the categorical figure for the two to be told apart on the taxa measured. Neither is there any measured difference between the two formats in agreement with the maintainer's own labels. What the probability does buy outright is below: a cut becomes this code's reading of a stored answer, so it can change without re-asking anything. The figures, and what they were and were not measured on, are in What was measured below, which is the only place in this package that states them.

The cut is applied AFTER the cache, never before it. What a cache entry holds is the probability -- the model's answer -- and a cut is this function's reading of it. So changing a cut takes effect for taxa already cached, with no new LLM calls, and the cuts are deliberately not part of the cache key.

Four judgements are asked separately, which is the point of the format: habitat is LIVING CONDITIONS only ("does it live in this kind of habitat, wherever its range is"), scope is the KIND OF ORGANISM and its depth or zone only, and whether the taxon occurs in the study region is geography in both cases. llm_p_transported carries "its DNA could have reached these samples" separately from "it lives here", so a taxon washed in from adjacent water is not scored as a resident. The habitat and target-group wording in the prompt comes from context$habitat and target_group, so nothing about any particular study is built in; the worked examples name no real taxon for the same reason.

#### What was measured

Every accuracy figure this package states is here, and nowhere else: one copy, so that a later measurement is one edit. All of it is claude-opus-5-5 on one real multi-marker study: the maintainer's labels are 12S taxa, and the taxa behind the repeat figures include COI and 18S as well. Every interval given is a 95% bootstrap interval over taxa, and they are wide -- 34 labelled taxa and 90 repeated ones is what all of this rests on. Two figures separated by less than their intervals are not two figures, and the text below says so wherever that is the case rather than reporting an ordering.

Against the maintainer's own labels, over the 34 hardest taxa of that study, with sites supplied, as same-decision / precision / recall:

- this prompt carrying every pipeline note it can: 73% (60-85) / 70% (51-89) / 73% (54-90).

- the same prompt with NO pipeline-derived text at all -- no numbers and no notes, so not the DNA evidence the defaults do send: 74% (60-86) / 70% (50-89) / 65% (45-85).

- the same guardrails and site block, asked with habitat and scope wording written for that one study rather than taken from context$habitat and target_group: 75% (61-89) / 80% (60-99) / 66% (43-88). That difference is the only measurement of what generalising the wording cost.

- a plain probability prompt with neither the site block nor the guardrail definitions, study-specific wording again: 67% (52-81) / 75% (50-100) / 44% (22-66). It differs from the others in BOTH the guardrails and the site block, so its difference belongs to that pair and is not an isolated effect of sites.

Every difference among those four sits inside the intervals.

No arm was asked exactly what the defaults now send, and this section states that rather than claim a figure for it. The two nearest are the first two above. The first was told everything, the pipeline's own numbers included. The second was told nothing the pipeline produced -- not even the match identity or the INDISTINGUISHABLE flag, both of which the defaults DO send. What ships differs from the second by the DNA evidence it adds back, and from the first by every occurrence-derived number it drops. Those two agreed with the maintainer within the intervals on all three statistics, so they bracket the shipped configuration without measuring it, and that is the most that can be said until an arm is scored on this prompt.

Repeat stability, as the share of the decisions the verdicts drive that a second ask repeats: with the pipeline notes, 90.0% (82.5-96.1) over 356 verdict-driven rows in 90 taxa, four asks of each taxon and six pairs; with none of them, 85.8% (69.4-98.4) over 345 rows in 88 taxa, which rests on a single pair per taxon and is correspondingly weak; the study-specific wording, 96.9% (93.8-98.9) over 346 rows in 87 taxa. Leaving out the one taxon described below takes the first to 93.0% and the second to 92.5%. All three intervals overlap, so none of these orderings is measured. Repeat pairs are correlated within a taxon, so it is those taxon counts and not the pair counts that set the intervals.

Why the answer is a probability: re-asking the same CATEGORICAL prompt repeated 90% of those decisions, against 97% for asking a probability and cutting it in code. Both of those arms were asked without the site block and without the guardrail definitions, so the pair isolates the answer format and nothing else, and neither figure is this prompt's own stability -- that is the paragraph above. Stability is the whole of the reason: scored against the maintainer's labels under one common rule, the two formats agree with him 71% and 74% of the time, are within 3 points of each other on each of the four judgements, and differ on precision and recall by less than their intervals. There is no measured difference in accuracy between asking for a category and asking for a probability.

The cuts: the question measured was not margin against hard directly. It was, of the rows this prompt acts on that a plain probability prompt keeps, how many did the maintainer act on too -- scored once with the verdicts read off by the margin cuts and once by hard cuts (0.20/0.70, contamination 0.50). Under this prompt's wording, 51% with the margin cuts against 31% with hard; under the study-specific wording, 54% against 32%. So the margin cuts make the guardrails' extra actions about half right where hard cuts leave them about a third right, and that holds on both wordings. No alternative to the 0.10 cut improves repeat stability; the instability that is left sits at the 0.70 cut, which is the paragraph below.

A known instability, not fixed in this release: a site-geography probability that lands near 0.70 can cross it between two asks, because the answer to whether the model can state the taxon's range at all moves with it. On the taxon that drives the repeat figure above, Eucheilota bakeri on COI, the site probability is 0.80 when the model says it knows the range and 0.50 to 0.70 when it says it does not; another taxon, Spheciospongia, moves 0.85 against 0.60 the same way. One such taxon is the whole of the leave-one-out difference above. Nothing in this release special-cases it: a fix is deferred to 1.1, because every candidate fix changes what the cut means for every other taxon.

What the pipeline's own numbers add: nothing that was measured. The first two arms above differ only in whether the taxon lines carried the posterior, the occurrence prior and the rest of it, and they agree on all three statistics well inside the intervals. That is the reason the defaults leave them off -- independence at no measured cost, not an improvement.

#### Site-aware geography

Supply a site table when you have one: of the two configurations scored against the maintainer's labels, the one with it has the higher point estimates -- same-decision 73% against 67%, recall 73% against 44%, with intervals that overlap. See What was measured.

A study that spans a coast or a latitude gradient has no single answer to "is this taxon geographically plausible here?": a tropical reef fish is plausible at the southern sites and not at the northern ones. With sites supplied the prompt lists the sites (name, latitude, longitude; sorted south to north), tells each taxon line which of them it was detected at, and asks for the taxon's range LIMITS rather than for a verdict:

- range_known: whether the model can state the limits at all.

- range_south_lat, range_north_lat: the limits in decimal degrees N, either or both null for "no limit within the study on that side".

- sites_outside_range: sites outside the range when latitude cannot describe it (island-only, a gap, or a study that runs east to west).

- p_inside_range, p_outside_range: the probability of occurrence at a site inside, and at a site outside, those limits.

The site probability is then computed here: a site beyond a stated limit, or named in sites_outside_range, takes p_outside_range; every other site takes p_inside_range. The cuts turn that into the site verdict. Asking for limits instead of a per-site verdict removes the model's choice between rule shapes and gives "study-wide" a definition it did not have.

Output:

- llm_geographic_plausibility_site and llm_p_geographic_site: the verdict and probability at the site named in each row's site_col. Rows with an NA site, or a site not in sites, get the study-wide pair. Unreviewed taxa stay NA.

- llm_geographic_plausibility and llm_p_geographic change meaning when sites is supplied: the probability is the MAXIMUM over the taxon's detected sites and the verdict is its level, computed here rather than asked for. Because the cut is monotone, that verdict is also the best site verdict, so "unlikely" study-wide means unlikely at every site.

Guards on the answer, each recorded in the how column of attr(result, "geographic_by_site"): a value that is not a latitude in [-90, 90] is dropped; an INVERTED band -- a southern limit given as range_north_lat -- is swapped rather than obeyed, since obeying it would put every site outside the range and mark the taxon unlikely everywhere; site names are matched ignoring case and surrounding spaces, and names matching no site are ignored and counted in n_unknown_sites; a list in which NO name is recognised is dropped whole, so it cannot appear to have moved something while moving nothing; and a missing p_outside_range gives p_inside_range everywhere, which never manufactures an "outside" the model did not state.

range_known = FALSE is a real answer, not a failure: it means the model cannot place the taxon, so every site takes p_inside_range, which the guidelines tell it to make intermediate. Sites it named explicitly are still honoured -- "I do not know the limits" and "not at that site" are different claims. With no usable p_inside_range at all, geography is NA unless the model volunteered a study-wide p_geographic; the count of such taxa is reported when verbose.

Known limitation. Latitude limits suit a study that runs mostly north to south, which is what this was evaluated on. For a study running east to west, or at a single latitude, a range limit cannot be stated as a latitude at all, and the prompt tells the model to use sites_outside_range instead. That path works but has not been measured.

The cache key gains a digest of the sites (names and coordinates rounded to 0.01 degree, order-independent) only when sites is supplied, so a cached verdict obtained without sites is never served to a call with sites, or the reverse. The sites a taxon was detected at are part of its own key, because they are part of its prompt line. The parsed range answer is cached with each taxon, so a cache hit reproduces llm_geographic_plausibility_site.

In TaxaFlag::screen_assignments(), geography_col can point at llm_geographic_plausibility_site so the screen uses the verdict for each row's own site.

#### What the review is shown, and what it is not

The rule, by default: the prompt carries DNA evidence and the study's own design, and no text derived from occurrence records.

Shown. What the sequence could and could not settle about the name -- the best match identity for the taxon, whether that match clears any rank threshold for the marker (poor_absolute_fit_col), whether a confusable relative could match as well (consensus_discrimination_col), whether any reference sequence exists for the name at all (consensus_provenance), and, where it did not, that the sequence did not resolve the call to species -- on all of a taxon's detections or only some (winner_rank_expanded_col). The guideline that explains the bracket is assembled from the notes the batch actually carries, and says that a missing note means nothing: naming a note that is absent would turn its absence into a claim. And the study's own design, which is not evidence about the taxon: the context (geography, habitat, dates, target group, marker), the site table when sites is supplied, and which of those sites each taxon was detected at.

Not shown. Everything the occurrence records produced. The occurrence prior, the GBIF distance and patch size, the beyond_buffer flag and the three iNaturalist fields are all NULL by default, and the guideline that explains them is not assembled. The pipeline's posterior and its candidate weights are also NULL, both being a likelihood combined with that prior.

The rank-expansion flag is the awkward case, and it is SHOWN. The flag is set because the occurrence prior supplied a species name where the sequence could not, so its existence is occurrence-derived -- but what the prompt says about it is only what the sequence did, and a reviewer judging that name needs to know the sequence did not reach it. Set winner_rank_expanded_col = NULL to take the other view.

The UNPRECEDENTED flag is the one that is READ but never SHOWN: it means "no local occurrence record at all", so it stays out of the prompt, while geographic_disagreement_basis is still computed from it -- that column is how a reviewer deterministically finds a taxon the model called plausible where the records hold nothing, and it would be silently empty if the flag were simply switched off.

Pass any of those column names and the value reaches the prompt again, one at a time or all of them.

Why. A review shown the pipeline's own confidence cannot contradict it independently, and a review shown a taxon's GBIF distance cannot catch an error IN the occurrence data -- which is one of the things it is for. The DNA evidence is in a different position: it is what the identification rests on, so a reviewer judging whether the NAME is right needs it. Scored against the maintainer's labels, a review told the pipeline's numbers and a review told none of them came out the same within the intervals, so the independence costs nothing measurable. See What was measured.

For a prompt with no pipeline-derived text at all, set consensus_provenance = FALSE and consensus_discrimination_col, poor_absolute_fit_col and best_identity_col to NULL. consensus_plausibility_col can stay as it is, since nothing it produces is in the prompt; setting it to NULL as well costs geographic_disagreement_basis, which is then NA throughout.

#### Pipeline context

A compact "[...]" annotation is appended to each taxon's line in the LLM prompt. What goes in it depends on the four params below, and they do not default alike -- see What the review is shown, and what it is not for the rule:

- consensus_posterior_col and winner_prior_col are NULL by default. Passed, they add the pipeline's own median statistical confidence and the occurrence prior for the taxon, which lets review_comment flag a disagreement between the pipeline's confidence and the model's ecological judgment.

- plausible_posteriors_col is NULL by default. Passed, it adds each candidate's averaged posterior weight, for multi-candidate sets only.

- winner_rank_expanded_col defaults to "winner_rank_expanded" and IS sent, as one sequence fact: that the sequence did not resolve the call to species. It says nothing about what supplied the name instead, and takes any logical column that means it, not only join_priors()'s own flag.

The annotation is purely additive: it never changes which rows are reviewed, the dedup key, or any output column. Set any of the four to NULL to disable; all four are silently skipped (not an error) when the named column is absent from input_df.

#### Spatial context

All six of these are NULL by default and nothing below happens unless they are passed -- see What the review is shown, and what it is not. When dist_nearest_occupied_km_col/patch_diameter_km_col/ beyond_buffer_col (check_gbif_tile_range()'s own output names) and/or inat_in_range_col/inat_n_observations_col/ inat_matched_name_col (TaxaFetch::check_inat_range()'s own names) are passed and match real columns in input_df -- typically joined onto it by taxon name before calling this function, since both source functions operate per-taxon at a query point, not per-row -- the same "[...]" bracket used for pipeline context also carries a compact GBIF/iNat summary (e.g. "[GBIF: nearest occurrence ~41km away, patch ~2.1km across; iNat: in range, 1275 obs]"). This matters because the same "unprecedented" flag can have very different explanations: a genuine regional native not yet recorded at this exact site, or a species thousands of km from any GBIF-mapped occurrence.

The per-taxon bracket is facts-only: no plausibility judgment is pre-computed (as for winner_rank_expanded's note above). Two caveats about how to weigh these facts are added as a GUIDELINES bullet instead (only when a batch has at least one such note), for the LLM to apply per case: (1) GBIF's density map is raw, unfiltered global data -- an occurrence found far away, especially in a small (1-2 cell) patch, may itself be a single bad or mis-georeferenced GBIF record rather than a real population; a small isolated patch is weaker evidence than a large one. (2) When iNat's matched_name differs from the taxon under review, its in_range verdict may describe a different, often more common, species due to a fuzzy name-search match (e.g. a query for the European Gasterosteus gymnurus can resolve to Gasterosteus aculeatus, returning a misleading in_range = TRUE). matched_name is surfaced so a reviewer (human or LLM) can catch this.

Purely additive, as for "Pipeline context": never changes which rows are reviewed, the dedup key, or any output column. Set any of the six params to NULL to disable; all six are silently skipped when the named column is absent from input_df.

### review_sample_identity(identity, context, blank_medium = NULL, target_groups = NULL, llm_fn = getOption("TaxaID.llm_fn", TaxaTools::call_api), model_label = NULL, tubes_per_call = 4L, max_tokens = NULL, max_retries = 2L, cache_dir = NULL, decisions_path = NULL, on_unreviewed = c("warn", "error", "ignore"), verbose = TRUE)

LLM Advice on Samples That Do Not Look Like Their Label

Sends each tube held back by 'classify_sample_identity' for an identity question to an LLM, with its taxa in every marker and the community of the field samples it was sequenced with, and asks for a plausibility judgement: is this a clean blank, a contaminated blank, a field sample carrying a blank's label, or the reverse? It also gives a ROLE: how the tube should be used (blank, sample, positive control, exclude, unknown). The answer is written to 'llm_' columns beside the decision record. Admission is the workflow's choice: by default a person still records the 'disposition', and ...

| Param | Required | Default | Doc |
|---|---|---|---|
| identity | yes |  | The result of classify_sample_identity(), with its attributes intact (read it immediately; a dplyr verb drops them). |
| context | yes |  | Character. What a blank is in this study and where the samples came from, e.g. "Field blanks are distilled water poured through a filter at the site. Samples are rocky-intertidal swabs, southern California." Required: the verdict depends on it, and a wrong assumption is silent. |
| blank_medium | no | NULL | Character or NULL. What a blank is filled with, e.g. "tap water". A blank is judged acceptable when its contents are consistent with its medium or with handling, so this decides many verdicts. Either one string for every tube, or a NAMED character vector giving each tube its own medium (names are sample ids; tubes not named read "not stated"). Use the per-tube form whenever media differ: a reverse-osmosis blank should be near-empty, so a tap-water community in it is anomalous, and judging it against "tap water" would explain away exactly what should be flagged. NULL tells the model the medium is not stated. Default NULL. |
| target_groups | no | NULL | Character or NULL. The groups the study's samples are meant to measure, e.g. "macroalgae, macroinvertebrates, intertidal fishes". A blank holding these at more than a trace is judged contaminated even when a plausible medium community is also present: a medium explains its own community, never the target signal, and a control carrying the target signal makes contamination checks permissive in exactly the direction nobody checks. NULL tells the model the groups are not stated. Default NULL. |
| llm_fn | no | getOption("TaxaID.llm_fn", TaxaTools::call_api) | Function taking a prompt string (and optionally max_tokens) and returning the model's text. Default getOption("TaxaID.llm_fn", TaxaTools::call_api). Under fully namespaced calls pass it explicitly; see review_assignments for why. |
| model_label | no | NULL | Character or NULL. A name for the model behind llm_fn, recorded in the cache key so one model's disposition is never served to a call asking another. Required whenever cache_dir is set and llm_fn is a function you wrote: all that can be seen of such a closure is its source text, so a wrapper that picks its model from a variable would key identically for two models and serve the first one's dispositions to the second run. Default NULL is accepted with no cache, and for an llm_fn a loaded namespace can name. See review_assignments for the full reasoning. |
| tubes_per_call | no | 4L | Integer. Tubes per LLM call. Default 4. |
| max_tokens | no | NULL | Integer or NULL. Forwarded to llm_fn. Default NULL. |
| max_retries | no | 2L | Integer. Re-asks for tubes the model omitted. Default 2. |
| cache_dir | no | NULL | Character or NULL. One file per tube, keyed on the full prompt item and context, so changed evidence is a miss. Pruned by taxaflag_clear_cache. Default NULL (no cache). |
| decisions_path | no | NULL | Character or NULL. If given, the llm_ columns are merged into this decision record without touching anything the user entered. Default NULL. |
| on_unreviewed | no | c("warn", "error", "ignore") | "warn" (default), "error" or "ignore". |
| verbose | no | TRUE | Logical. Default TRUE. |

**Value:** The review queue ('attr(identity, "review_queue")') with 'llm_verdict' (one of '"clean_blank"', '"contaminated_blank"', '"sample_labelled_as_blank"', '"positive_control_labelled_as_blank"', '"blank_labelled_as_sample"', '"valid_sample"', '"uncertain"'), 'llm_role' ('"blank"', '"sample"', '"positive_control"', '"exclude"' or '"unknown"': how the tube should be used; 'classify_sample_identity(accept_llm_roles = TRUE)' admits on it; a contaminated blank is still role '"blank"'), 'llm_suggested_disposition', 'llm_confidence' (high/moderate/low) and 'llm_rationale' added per sample, and 'llm_marker_unusable' per unit: 'TRUE' where the model judged this marker's result contaminated. Identity is per tube, usability per marker. With 'accept_llm_roles = TRUE' it can only EXCLUDE a marker, never keep one the gate excluded. Attributes '"unreviewed_samples"' (always present) and '"llm_prompts"'.

#### Why an LLM here

The judgement that settles these cases is a plausibility argument over a taxon list, which the statistics cannot make. "A field blank containing three bloom-forming dinoflagellates and a copepod community is implausible" needs knowledge of what those taxa are and where they live. So does its counterpart: a blank holding a human, a few soil fungi and one hopped read is a clean blank however many features it has. The deterministic evidence (composition, diversity, cross-marker agreement) is given to the model as well, so that a disagreement between the two is visible.

#### One question per tube

Identity is a property of the tube, not of a library, so the model is asked once per sample and shown every marker together, including markers where the tube looked concordant. Library failures (issue_type == "library") are not sent: they are a yield question, and flag_failed_libraries has already answered it.

#### Unreviewed tubes

A tube the model does not answer is re-asked, alone, up to max_retries times. Omissions come mostly from a batch that ran out of output tokens: a reasoning model can spend a whole max_tokens budget thinking about four tubes and return no text. On one real study, 13 of 44 tubes went unanswered at 4 tubes per call and 4000 tokens; asked singly, all but two were answered. Raise max_tokens before raising tubes_per_call. It is never cached, and it is listed in attr(, "unreviewed_samples"). Because an LLM verdict never admits anything, an unreviewed tube is not lost: it simply has no advice. The on_unreviewed argument controls how loudly that is reported.

### review_spatial_context(input_df, query_lat, query_lon, taxon_col = "primary_taxon", plausibility_col = "primary_plausibility", occurrence_data = NULL, excluded_occurrence_data = NULL, occurrence_taxon_col = "taxon_name", occurrence_lat_col = "decimalLatitude", occurrence_lon_col = "decimalLongitude", inat_range = NULL, inat_taxon_col = "taxon_name", live_inat_check = TRUE, inat_cache_dir = NULL, inat_radius_km = 500, context = NULL, target_group = NULL, marker = NULL, data_type, llm_fn = getOption("TaxaID.llm_fn", TaxaTools::call_api), tile = "CartoDB.Positron", gbif_style = "classic.point", gbif_bin_size = 256L, gbif_year_range = NULL)

Interactive Spatial Review of Consensus Taxa

Opens a Shiny gadget for scrolling through consensus taxa - grouped by plausibility (e.g. '"expected"'/'"unexpected"'/'"unprecedented"' from 'add_posthoc_assessment()''s 'primary_plausibility') - and seeing, for whichever taxon is selected, a live GBIF occurrence-density map plus the same numeric spatial context 'check_gbif_tile_range()' and 'compute_local_occurrence_distance()' compute, so a reviewer can look at a flagged taxon's real-world distribution without leaving the pipeline.

| Param | Required | Default | Doc |
|---|---|---|---|
| input_df | yes |  | Data frame of consensus taxa (e.g. consensus_final after add_posthoc_assessment()). Must contain taxon_col; supply plausibility_col = NULL if there is no grouping column to filter by. |
| query_lat | yes |  | Numeric scalars. The study site to check distances/tiles against. |
| query_lon | yes |  | Numeric scalars. The study site to check distances/tiles against. |
| taxon_col | no | "primary_taxon" | Character. Column in input_df naming each taxon. Default "primary_taxon". |
| plausibility_col | no | "primary_plausibility" | Character or NULL. Column in input_df used to group the taxon dropdown (e.g. "primary_plausibility"). NULL shows every taxon in one unfiltered list. Default "primary_plausibility". |
| occurrence_data | no | NULL | Data frame or NULL. Already-fetched occurrence records this study kept (e.g. occurrences_clean) passed straight to compute_local_occurrence_distance() and overlaid on the map as small, semi-transparent points for the selected taxon (deliberately understated so they don't visually overwhelm the GBIF tile layer underneath). NULL (default) omits the free/local panel and the point overlay entirely. |
| excluded_occurrence_data | no | NULL | Data frame or NULL. Occurrence records this study's own GBIF quality/outlier/institution/spatial-QC filtering excluded, in the same shape as occurrence_data -- overlaid as hollow red rings, distinct from occurrence_data's solid points, for provenance ("what did we have and choose not to use") rather than as evidence of presence. Not computed here -- reconstruct it yourself, e.g. dplyr::anti_join(raw_gbif, geo_outlier_check, by = "gbifID") for the filter_gbif_quality() stage specifically (see TaxaFetch::filter_gbif_quality()'s own removed_records attribute for exact per-record reasons when that attribute is still attached). NULL (default) omits this overlay. |
| occurrence_taxon_col | no | "taxon_name" | Character. Column names shared by occurrence_data AND excluded_occurrence_data. Defaults match compute_local_occurrence_distance()'s own defaults. |
| occurrence_lat_col | no | "decimalLatitude" | Character. Column names shared by occurrence_data AND excluded_occurrence_data. Defaults match compute_local_occurrence_distance()'s own defaults. |
| occurrence_lon_col | no | "decimalLongitude" | Character. Column names shared by occurrence_data AND excluded_occurrence_data. Defaults match compute_local_occurrence_distance()'s own defaults. |
| inat_range | no | NULL | Data frame or NULL. Pre-computed TaxaFetch::check_inat_range() output (one row per taxon, with in_range/n_observations/matched_name) to look up by taxon name -- checked FIRST, for free, before any live call (see live_inat_check below). Real, confirmed limitation this param alone can't cover: check_inat_range() is typically only ever run on a pipeline's own undetected/unreferenced candidate list (e.g. Step 8c of a workflow script), not every taxon in a consensus table -- verified directly against a real dataset that taxa flagged "expected" or "unexpected" (not "unprecedented") are routinely absent from it entirely, which is why live_inat_check exists. |
| inat_taxon_col | no | "taxon_name" | Character. Taxon-name column in inat_range. Default "taxon_name". |
| live_inat_check | no | TRUE | Logical. When a taxon has no row in inat_range (including when inat_range itself is NULL), fall back to a real, live TaxaFetch::check_inat_range() call for just that one taxon. Default TRUE -- unlike review_assignments()'s "Run AI Review" button, this is free (no LLM billing) and fires automatically on selection, matching check_gbif_tile_range()'s own always-on treatment. Requires the TaxaFetch package and a real INAT_API_TOKEN; silently falls back to "no data" (not an error) when either is unavailable, or when iNat itself has no polygon for the resolved taxon (surfaced via range_status in that case, e.g. "taxon_not_found"/"no_polygon", rather than a blanket "no data" that can't be told apart from "never checked"). |
| inat_cache_dir | no | NULL | Character or NULL. Forwarded to check_inat_range()'s own cache_dir when live_inat_check fires -- caches per-taxon iNat range polygons on disk so re-selecting the same taxon (in this session or a later one) doesn't re-download it. NULL (default) disables caching, matching check_inat_range()'s own default. |
| inat_radius_km | no | 500 | Numeric. Search radius (kilometers) for the real iNaturalist observation points plotted on the map (see .fetch_inat_points(), internal) -- distinct from live_inat_check's range-polygon check, which has no radius concept. Default 500 -- confirmed live this needs to be wide, not just permissive: the individual-point map layer only shows points within this radius, unlike a full-coverage density tile (continuous world density, like GBIF's own tiles), so too small a radius can make even a well-recorded taxon look confined to "a small region." A smaller default (50km, copied unexamined from an unrelated function's own default) was confirmed live to do exactly this. A dashed circle of this exact radius is drawn on the map (grouped with the iNat points layer, so toggling one toggles both) specifically so a taxon with no visible points nearby doesn't read as "no iNat data exists" when it may just mean "none within this radius." |
| context | no | NULL | Passed straight to review_assignments() when "Run AI Review" is clicked. context defaulting to NULL (rather than being required, unlike review_assignments() itself) is what hides the button entirely -- supply it to enable on-demand AI review. |
| target_group | no | NULL | Passed straight to review_assignments() when "Run AI Review" is clicked. context defaulting to NULL (rather than being required, unlike review_assignments() itself) is what hides the button entirely -- supply it to enable on-demand AI review. |
| marker | no | NULL | Passed straight to review_assignments() when "Run AI Review" is clicked. context defaulting to NULL (rather than being required, unlike review_assignments() itself) is what hides the button entirely -- supply it to enable on-demand AI review. |
| data_type | yes |  | Character. Detection method, passed straight to review_assignments(): one of "eDNA", "acoustic" or "image". REQUIRED, and required even when the "Run AI Review" button is never clicked, because the value changes the guidance the LLM receives and defaulting it would make that choice silently. |
| llm_fn | no | getOption("TaxaID.llm_fn", TaxaTools::call_api) | Passed straight to review_assignments() when "Run AI Review" is clicked. context defaulting to NULL (rather than being required, unlike review_assignments() itself) is what hides the button entirely -- supply it to enable on-demand AI review. |
| tile | no | "CartoDB.Positron" | Character. Leaflet base-map tile provider (the reference map underneath the GBIF density overlay). Default "CartoDB.Positron" -- a muted, mostly-grayscale basemap chosen specifically so GBIF's own density colours stand out (a busier basemap like "OpenStreetMap"'s default styling visually competes with them, especially at low zoom where GBIF's own density pixels are small). Try "CartoDB.PositronNoLabels" for an even plainer background (drops place-name labels too). |
| gbif_style | no | "classic.point" | Character. GBIF map API style query parameter, controlling how GBIF itself renders density (colour ramp, point vs. area aggregation). Default "classic.point" -- GBIF's own default rendering, matching what GBIF's own map viewer shows. A bare ".point" style is automatically upgraded to its ".poly" counterpart and combined with gbif_bin_size (below) unless it's a Heat-family style, which has no .poly counterpart. Other .point styles (e.g. "purpleHeat.point") are valid and can look bolder against a light basemap; pass one to compare. |
| gbif_bin_size | no | 256L | Integer or NULL. GBIF map API's bin= square/squareSize binning parameters, aggregating raw single-pixel occurrence dots into visibly larger squares -- confirmed live before choosing this default: squareSize params are silently NO-OPS when style stays .point-suffixed (identical bytes with/without them), and only take effect once the style is switched to its .poly counterpart, which is why gbif_style is auto-upgraded above. Default 256L, chosen from real measurements against the SPARSE species this gadget is actually meant to review (this thread's own real "unprecedented" candidates, at the real zoom-7 study-site tile), not a common/ everywhere-present species -- a smaller default (64) would look like no noticeable change, which real measurement confirms: for a real, genuinely sparse GBIF record set at that exact tile, raw .point pixels covered under 0.1%; squareSize=64 only reaches ~1-2.5%, visually indistinguishable from unbinned dots on a full map pane. 256 reaches ~10-15% coverage for the same real sparse species (a ~60-140x increase over raw pixels) while a maximally common, everywhere-present species (checked separately, not this gadget's typical use case) only reaches ~26% -- visibly bigger without turning into a solid blob. NULL disables binning entirely, reverting to gbif_style exactly as supplied. ".poly"-suffixed styles combined with gbif_bin_size = NULL (unbinned) can render as a completely EMPTY tile at a real zoom/species combination that raw .point styles render correctly -- confirmed live, not a safe combination -- so this is only ever applied together with binning, never on its own. A binned square can visually sit offset from a point's true location by up to gbif_bin_size pixels, since GBIF snaps each occurrence to its containing bin before drawing it -- a real, expected consequence of aggregation, not a data or rendering bug (a single domestic-cat record appearing a few km into open water at the default 256L binning is exactly this: GBIF's real, unfiltered occurrence data plus one coarse pixel's worth of legitimate positional imprecision from binning, not a broken map layer). See also check_gbif_tile_range()'s own What the PNG can and can't tell you section -- density tiles are a display aid, not an exact-count source, in this gadget as much as there. |
| gbif_year_range | no | NULL | Character or NULL. GBIF map API year query parameter (e.g. "1995,2025"), display-only -- affects only the visual tile layer, NOT check_gbif_tile_range()'s own distance/patch numbers (which deliberately stay all-time/global, the right question for "is this plausible anywhere, ever" rather than "within our exact study window"). Worth knowing: the density map is all-time and worldwide by default, which is often a much LARGER pool of records than a study's own date- and quality-filtered GBIF fetch -- confirmed directly against the real GBIF tile API that a narrower year range genuinely reduces what's rendered (a real, working filter, not a cosmetic one). NULL (default) shows GBIF's full all-time record, matching GBIF's own default map view. |

**Value:** 'NULL' invisibly. The gadget is for interactive exploration only.

#### Details

The map itself renders GBIF's live density tiles directly (leaflet::addTiles() with the density-tile URL template) rather than a static snapshot -- the reviewer can pan and zoom the actual tile layer, at any resolution, the same way GBIF's own map viewer works. This is a genuinely different (and free) consumer of the same GBIF tile API check_gbif_tile_range() uses for its own alpha-channel analysis -- one renders raw tiles client-side for a human to look at, the other decodes pixels server-side for a number. Selecting a taxon triggers both: the visual tile layer updates, and the sidebar's numeric context (check_gbif_tile_range()/compute_local_occurrence_distance(), plus a pre-supplied inat_range lookup if given) recomputes.

#### Cost

Selecting a taxon triggers real, but free/cheap, network calls (GBIF name resolution + check_gbif_tile_range()'s tile fetches, a few seconds). The "Run AI Review" button is the one exception -- a real, BILLED LLM call via review_assignments() -- and is deliberately never triggered automatically; it only fires on an explicit click, and only appears at all when context is supplied.

### screen_assignments(reviewed_df, posterior_df = NULL, taxon_col = "consensus_taxon", rank_col = "consensus_rank", geography_col = "llm_geographic_plausibility", habitat_col = "llm_habitat_plausibility", scope_col = "llm_scope_plausibility", poor_fit_col = "poor_absolute_fit", best_identity_rank_col = "best_identity_rank", relative_score_gap = 0.25, move_up_max_rank = "genus", poor_fit_habitat_exclude_max_rank = "family", blank_flag_col = NULL)

Screen reviewed assignments for identity and presence problems

Applies a fixed set of rules to the rows of a reviewed assignment table (one row per taxon at a site, as returned by 'review_assignments()') and appends what the rules suggest. The rules combine three kinds of evidence already present on each row: whether the best reference match fits well in absolute terms, the reviewer's geographic, habitat and scope verdicts, and, optionally, the competing hypotheses in the posterior table. Nothing is dropped or changed: every input row is returned in its original order with new columns that say what the screen would do and why.

| Param | Required | Default | Doc |
|---|---|---|---|
| reviewed_df | yes |  | A data frame with one row per taxon x site unit. Required columns: observation_id, the columns named by taxon_col, rank_col, geography_col, poor_fit_col and best_identity_rank_col. scope_col and habitat_col are optional; if absent the matching rule is skipped with a message. A winner_hypothesis_type column enables the unreferenced-species exception. An n_tubes column (distinct tubes per row) enables isolated_geography_unlikely. Columns named genus, family, order, class and phylum, if present, help resolve the taxon a call moves up to. |
| posterior_df | no | NULL | Optional data frame of per-hypothesis posterior rows. Needed to find relatives for rule I2. Columns: observation_id, taxon_name, taxon_name_rank, hypothesis_type, genus, family, score_likelihood; and theta_mean and/or prior_branch to decide whether a relative is local. Also used, with its genus through phylum columns, to resolve move-up target names. NULL (default) means no relatives are found and every I2 row is "review". |
| taxon_col | no | "consensus_taxon" | Names of the consensus taxon and rank columns. |
| rank_col | no | "consensus_rank" | Names of the consensus taxon and rank columns. |
| geography_col | no | "llm_geographic_plausibility" | Names of the reviewer's geographic, habitat and scope plausibility columns, with values "likely", "possible" or "unlikely" (anything else counts as missing for geography, and as not plausible for habitat). |
| habitat_col | no | "llm_habitat_plausibility" | Names of the reviewer's geographic, habitat and scope plausibility columns, with values "likely", "possible" or "unlikely" (anything else counts as missing for geography, and as not plausible for habitat). |
| scope_col | no | "llm_scope_plausibility" | Names of the reviewer's geographic, habitat and scope plausibility columns, with values "likely", "possible" or "unlikely" (anything else counts as missing for geography, and as not plausible for habitat). |
| poor_fit_col | no | "poor_absolute_fit" | Name of the logical column that is TRUE when the best match fits poorly in absolute terms. |
| best_identity_rank_col | no | "best_identity_rank" | Name of the column giving the rank at which the best reference match is identified; used as the move-up target when it is coarser than the call. |
| relative_score_gap | no | 0.25 | Largest allowed shortfall of a relative's score_likelihood below the call's best member for the relative to qualify under I2 (inclusive). The default 0.25 is a chosen value, not calibrated; on the test data 0.10 and 0.25 gave identical results. |
| move_up_max_rank | no | "genus" | Coarsest call rank that is moved up under I3. One of "species", "genus", "family", "order", "class", "phylum", "kingdom". The default "genus" is a rank limit chosen by the maintainer and checked against expert review. |
| poor_fit_habitat_exclude_max_rank | no | "family" | Coarsest call rank at which poor fit with an unlikely habitat excludes the row. Default "family". |
| blank_flag_col | no | NULL | Optional name of a logical column marking rows with blank (contamination) evidence. Where TRUE, suggested_action becomes "exclude" and identity_reason has "blank evidence" appended; identity_action is unchanged. The default NULL ignores it, because no fixed column name exists, so the caller names the column. |

**Value:** 'reviewed_df' with these columns appended, in the same row order: identity_action "keep", "move_up", "exclude" or "review". identity_taxon_after Taxon after the identity layer: the call itself, the move-up target (NA if its lineage cannot be resolved), or NA when excluded. identity_rank_after Rank of 'identity_taxon_after'; NA when excluded. identity_reason Plain-words reason naming the rule. suggested_action "keep", "move_up" or "exclude". "review" rows and blank-flagged rows suggest "exclude". presence "resident", "off_habitat" or "out_of_scope"; NA for identity-excluded rows and where habitat is missing. poor_fit_flag TRUE for poor-fit calls kept at a rank coarser than 'move_up_max_rank'. isolated_geography_unlikely Information only; never acts. TRUE if the taxon's total tubes across the input (summed 'n_tubes') is at most 3 and geography is unlikely; FALSE otherwise; NA when 'reviewed_df' has no 'n_tubes' column or the count is missing. The result also carries 'attr(, "rule_counts")', a data frame with one row per rule (I1, I2_relative, I2_review, I3_move_up, I3_flag_coarse, I3_exception, poor_fit_habitat_exclude, I4, blank_evidence) and 'n_rows', the number of rows on which it fired (0 when none). Rules are exclusive per row except blank_evidence, which is counted in addition. A message reports the same counts, zeros included, and states how many rows the relative move (I2_relative, which depends on 'relative_score_gap') fired on. 'rule_counts' has a fixed row set and an 'evaluated' column: a rule that ran and fired on nothing has 'n_rows' 0 and 'evaluated' TRUE; a rule that could not run has 'n_rows' NA and 'evaluated' FALSE (I2_relative without 'posterior_df', I3_exception without a 'winner_hypothesis_type' column, poor_fit_habitat_exclude without the habitat column, blank_evidence with 'blank_flag_col = NULL'). Because 'rule_counts' is an attribute, dplyr verbs drop it; read it straight off the value 'screen_assignments()' returns.

#### Two layers

The screen separates two questions.

The identity layer asks whether the name on the row can be trusted. Each row follows the first rule that applies:

- I1: good fit and geography likely or possible: keep.

- I2: good fit but geography unlikely. If the posterior table holds a referenced (hypothesis_type "specific_candidate") and local (prior_branch "kernel_estimated" or "resident_observed", or a theta_mean value) congener or confamilial of the call, observed for the same observation_id, whose best score_likelihood is within relative_score_gap of the call's best member, the call moves up to the genus (congener) or family (confamilial) they share. Otherwise the row is marked "review" (range expansion or error cannot be told apart) and the suggested action is "exclude". Without posterior_df every I2 row is "review". Only species and genus calls are tested.

- I3: poor fit and geography plausible. A call at move_up_max_rank or finer moves up to best_identity_rank if that is coarser than the call, otherwise up one rank. Coarser calls are kept with poor_fit_flag TRUE. A named unreferenced species (winner_hypothesis_type "unreferenced_species") whose geography is "likely" keeps its name.

- Habitat exclusion: poor fit, geography plausible and habitat unlikely, at poor_fit_habitat_exclude_max_rank or finer: exclude (applied before the move-up, after the unreferenced exception).

- I4: poor fit and geography unlikely: exclude.

A missing poor-fit verdict counts as a good fit, and a missing geography verdict counts as plausible, so a missing verdict never triggers a rule.

The presence layer asks whether the taxon belongs in the study system, for rows the identity layer did not exclude: "out_of_scope" if the scope verdict is unlikely (scope wins), else "off_habitat" if the habitat verdict is anything other than likely or possible, else "resident". A missing habitat verdict leaves presence NA. Presence never sets suggested_action.

#### Flags, never drops

The function returns every input row in the input order. It does not remove rows, rename taxa in place, or alter any input column. The appended columns are suggestions for the caller to act on; filtering is a separate, deliberate step. The suggested action for a "review" row is "exclude", the conservative reading, but identity_action keeps the distinction.

#### Site-aware screening

geography_col may name a per-site column, such as llm_geographic_plausibility_site returned by review_assignments(sites = ...). The rules then judge each taxon at each site against that site's own geographic verdict, rather than one verdict for the taxon across the whole study.

### taxaflag_clear_cache(cache_dir = tools::R_user_dir("TaxaFlag", "cache"), older_than_days = NULL, dry_run = FALSE, force = FALSE)

Report and clear TaxaFlag's on-disk caches

Lists, and optionally deletes, the per-key files written by 'review_assignments()' and 'check_gbif_tile_range()' when either is given a 'cache_dir': 'review_assignments()''s per-reviewed-taxon LLM verdict cache, and 'check_gbif_tile_range()''s per-(taxon, location, zoom, ...) GBIF density-tile verdict cache. Entries in both have no built-in expiry - a verdict stays valid until its own key changes (e.g. the taxon's review context changes, or the query location/zoom changes), which makes it a miss anyway - so pruning is about disk usage and about deliberately forcing a fresh ...

| Param | Required | Default | Doc |
|---|---|---|---|
| cache_dir | no | tools::R_user_dir("TaxaFlag", "cache") | Character. The directory passed to review_assignments()'s or check_gbif_tile_range()'s cache_dir (each function's cache lives in its own directory, so point this at whichever one you want to inspect/clear). Defaults to tools::R_user_dir("TaxaFlag", "cache"), matching the sibling packages; workflows that pass a project-local directory should pass the same one here. |
| older_than_days | no | NULL | Optional numeric. Delete only entries older than this many days. NULL (default) considers every entry. |
| dry_run | no | FALSE | Logical. TRUE reports what would be deleted without deleting it. |
| force | no | FALSE | Logical (default FALSE). Pass TRUE to clear a cache_dir that holds file(s) matching none of the recognized cache patterns -- see TaxaTools::list_cache_files(). |

**Value:** Invisibly, the inventory data frame ('TaxaTools::list_cache_files()' output) of the files considered.

### validate_controls(input_df, event_col = "event_id", taxon_col = "taxon_name", count_col = "count", control_samples, site_col = NULL, min_samples_per_site = 3L, headroom_fraction = 0.5, headroom_limit = 0.98, max_null_pairs = 5000L, verbose = TRUE)

Validate That Control Samples Actually Look Like Controls

Tests whether each column labelled a control is compositionally consistent with being one, and - in the other direction - whether any column labelled a field sample looks like a control. Mislabelling runs both ways, and a mislabelled field sample sitting in the control set is the more damaging of the two: it makes the real community look like contamination, so 'flag_contaminant' then filters genuine signal.

| Param | Required | Default | Doc |
|---|---|---|---|
| input_df | yes |  | Long-format data frame: one row per taxon x column observation, carrying at least event_col, taxon_col and count_col. |
| event_col | no | "event_id" | Character. Column identifying the sampled/observed unit (filter, bottle, replicate, recording, or image batch). Default "event_id". |
| taxon_col | no | "taxon_name" | Character. Column identifying the feature to compare compositions on -- a fine-grained candidate/detection ID (e.g. ESV/ASV for sequence data, a call/image ID for acoustic/image data) is preferable to a taxon name, because it does not depend on assignment succeeding. Default "taxon_name". |
| count_col | no | "count" | Character. Count column. Default "count". |
| control_samples | yes |  | Character vector of event_col values that are labelled controls. |
| site_col | no | NULL | Character or NULL. Column grouping columns into sites. When NULL every column is treated as one site, which makes the null a whole-study one and weakens the test; a warning says so. |
| min_samples_per_site | no | 3L | Integer. Below this many field samples a site cannot form its own null. Default 3. |
| headroom_fraction | no | 0.5 | Numeric in (0, 1). A control is consistent with being a control when its median distance to the site's samples is at least this far along the room remaining above the sample median: threshold = median(null) + headroom_fraction * (1 - median(null)). Default 0.5, i.e. halfway between "as distant as the samples are from each other" and "completely disjoint". THIS FORM WAS ARRIVED AT BY FAILING TWICE ON REAL DATA, and both failures are worth knowing because each looked reasonable: A high QUANTILE of the null (0.90) is in-range but not robust. A control mislabelled as a sample sits inside the sample set and inflates the very null it is tested against -- with 8 samples plus one disjoint hidden control, 22% of sample-pair distances go to ~1.0 and drag the quantile into the contaminated tail. It also has no headroom at heterogeneous sites: a real site with 1,151 samples had a 0.90-quantile of exactly 1.000, so nothing could pass. An additive robust fence, median + 3 * MAD, is robust but LEAVES THE METRIC'S RANGE. Bray-Curtis is bounded at 1, and on real sites this produced thresholds of 1.54 and 1.62, after which the headroom guard fired on 59 of 84 controls. Robustness is not worth an impossible cutoff. Scaling into the remaining headroom is bounded by construction (it can never exceed 1) and depends only on the median, so it keeps the 50% breakdown point that made MAD attractive. |
| headroom_limit | no | 0.98 | Numeric. If a site's null threshold reaches this value the test has no headroom above the samples and cannot pass anything: a control would have to be MORE disjoint than the samples already are from each other. Such columns are reported "untestable_no_headroom" rather than given a confident verdict. Found on real data: a site with 1,151 samples had a null 0.90-quantile of exactly 1.000, which flagged genuine 6-taxon controls as resembling 34-taxon samples. Default 0.98. |
| max_null_pairs | no | 5000L | Integer. Cap on the number of sample-pair distances used to estimate a site's null. The null is O(n^2) in samples, and a real site here had 213 samples = 22,578 pairs, which made the first version of this function unusable (still running after 19 minutes). A few hundred pairs estimate a median and a 0.90 quantile, but a subsample makes a site whose null sits near its cut-off land on either side of it, so the default uses every pair for sites up to 100 samples (4,950 pairs) and subsamples only above that. Pairs are sampled above this cap and null_n_pairs records how many were actually used. The sample is drawn from a fixed local seed and the caller's random-number state is restored afterwards, so the same data always give the same verdicts: an unseeded draw made a real run's power flip between "ok" and "low_wide_null" from one call to the next, moving 32 units between concordant and inconclusive. A fixed seed makes such a verdict reproducible; only using every pair makes it exact. Default 5000. |
| verbose | no | TRUE | Logical. Print a summary. Default TRUE. |

**Value:** A data frame, one row per sequenced column, with the column id, its site, its label, 'n_taxa', 'n_reads', the test statistic 'd_to_samples', the site null ('null_median', 'null_threshold', 'null_n_pairs'), a 'power' verdict and a 'verdict'. Attribute '"site_power"' carries the per-site table. 'verdict' takes: '"consistent_with_control"', '"RESEMBLES_SAMPLE"' (a control that may be a mislabelled sample), '"consistent_with_sample"', '"RESEMBLES_CONTROL"' (a sample that may be a mislabelled control), '"untestable"' (no null available), '"untestable_no_headroom"' (the null reaches the metric's ceiling), or '"no_detections"' (every read for this column is 0 or NA, so it has no composition to compare against anything - 'd_to_samples'/ 'd_to_controls' are 'NA', 'power' reads '"none_no_detections"'). 'confidence' is '"low"' wherever the site's power is not '"ok"'; filter on it, because a verdict from a wide null is weak evidence and must not read like one from a tight null. A column with no positive reads at all still gets its own row here - the "one row per sequenced column" contract above holds even for it - rather than silently disappearing because there was nothing to compute a distance from. *A site with two samples and a site with twenty both return "nothing flagged".* Only one of those is evidence. 'power', 'null_n_pairs' and 'confidence' are what separate them, and the function says so on the console as well as here.

#### The principle

A control is defined by what it LACKS, not by what it contains. Whatever the medium -- tapwater, sterilised seawater, molecular-grade water, air -- a control's defining property is that its composition is not drawn from the sampled habitat. Everything here follows from that, which is why the test needs no taxonomy, no habitat model, no marker-specific tuning and no assumption about what the blank medium is.

#### Why the reference must come from the data

The test statistic is each control's median compositional distance to the FIELD SAMPLES IT SITS WITH, compared against the null distribution of sample-to-sample distance at that same site. A fixed cutoff cannot work: measured on one real COI study, the within-site sample-vs-sample median ranged from 0.145 to 0.890 ACROSS SITES IN THAT ONE DATASET. A threshold of 0.8 would have called every control at the tight site a blank and every control at the heterogeneous site a sample, on data where both were in fact fine. Drawing the null from each site's own samples self-calibrates to marker diversity, habitat and sampling design.

#### Power is reported, not assumed

Two situations both produce "nothing flagged", for opposite reasons, and this function refuses to let them look alike: a site with many samples and a tight null gives a real negative result; a site with two samples, or a null spanning most of the range, has no power to detect anything. Every site gets an explicit power verdict and the null's own spread, so a clean result can be distinguished from an untested one.

#### Before trusting a negative result

Prove both directions on your own data, as with any guard: relabel a known field sample as a control and confirm it is flagged, and confirm a clean control set stays silent. A check demonstrated only in the flagging direction is half-tested, and the untested half is the one that matters when it reports nothing.

## Quick Start

### Check that the blanks really are blanks (do this first)

``` r
library(TaxaFlag)

checked <- validate_controls(
  input_df        = reads_long,
  event_col       = "event_id",
  taxon_col       = "ESVId",     # a fine-grained candidate/detection ID beats
  count_col       = "n_reads",   # a taxon name: it does not depend on
  control_samples = blank_ids,   # assignment having succeeded
  site_col        = "Site"       # supply this if you have it; the null is per site
)

# controls that look like field samples, and samples that look like controls
checked[checked$verdict %in% c("RESEMBLES_SAMPLE", "RESEMBLES_CONTROL"), ]

# and read the power before believing a clean result
attr(checked, "site_power")
```

### Flag contamination from lab blanks

``` r
flagged <- flag_contaminant(
  input_df               = reads_long,
  taxon_col        = "taxon_name",
  count_col        = "n_reads",
  event_col        = "event_id",
  control_samples  = c("Blank_1", "Blank_2"),
  contaminant_type = "lab_contaminant"
)

# Output adds: observation_validity, validity_flag, validity_reason
# Filter to invalid taxa (probable contaminants)
flagged[flagged$validity_flag == "invalid_lab_contaminant", ]
```

For new work, gate on evidence and use site breadth:

``` r
gated <- flag_contaminant(
  input_df                 = reads_long,
  taxon_col                = "ESVId",
  count_col                = "n_reads",
  event_col                = "event_id",
  control_samples          = blank_ids,
  require_control_evidence = TRUE,   # no verdict without a control detection
  site_col                 = "Site", # systemic vs local
  min_control_obs          = 2L     # don't condemn on ONE blank observation
)

# what to actually remove
gated[gated$validity_flag == "invalid_lab_contaminant", ]
# what NOT to remove, though the ungated path would have
gated[gated$validity_flag == "not_control_enriched", ]
# and what simply cannot be assessed
table(gated$validity_flag)
```

### Flag handler artifacts (camera traps)

``` r
flagged <- flag_handler(
  input_df               = camera_detections,
  datetime_col     = "datetime",
  group_col        = "camera_id",
  interval_minutes = 30
)
```

### LLM expert review

``` r
reviewed <- review_assignments(
  input_df         = consensus_results,
  taxon_col  = "consensus_taxon",
  context    = list(geography = "Southern California", habitat = "Marine"),
  target_group = "fish"
)
# Returns 8 structured columns (llm_-prefixed: independent LLM judgments,
# never derived from the pipeline's own values):
# llm_habitat_plausibility, llm_geographic_plausibility, llm_scope_plausibility,
# llm_contamination_risk, review_alternatives, review_lower_hypotheses,
# review_confidence, review_comment

# Filter to contamination concerns
reviewed[reviewed$llm_contamination_risk %in% c("high", "moderate"), ]

# Site-aware geography: one verdict per taxon per site
reviewed <- review_assignments(
  input_df     = consensus_results,
  taxon_col    = "consensus_taxon",
  context      = list(geography = "Pacific coast", habitat = "Marine"),
  target_group = "fish",
  sites        = site_table,          # columns: site, lat, lon
  site_col     = "site"
)

# Suggested actions; nothing is dropped
screened <- screen_assignments(
  reviewed,
  posterior_df  = posteriors,
  geography_col = "llm_geographic_plausibility_site"
)
table(screened$suggested_action, screened$presence, useNA = "ifany")
```

