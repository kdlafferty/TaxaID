# CONTEXT: TaxaExpect

**Kernel Priors for Expected Species Composition from Occurrence Data**

Estimates theta priors -- each taxon's expected share of the detections at a site -- for taxonomic assignment, from occurrence records (see TaxaFetch). A site-centered kernel estimator weights occurrence points by distance, with optional depth and habitat conditioning, and evidence layers add undetected diversity, regional proximity, iNaturalist ranges, invasive watch lists and domestic or food species. Part of the TaxaID ecosystem.

Version 1.0.0. 17 exported function(s).

## Functions

### apply_undetected_evidence(taxaexpect_priors, model_obj, evidence, grid_id, main_habitat = NULL, taxonomy = NULL, pricing = c("blend", "curve"), sampling_group = NULL, group_fallback = c("pooled_qualifying", "error", "skip"), min_group_n_eff = 100, min_group_f1 = 1L)

Elevate the dark-diversity floor prior for species with external occurrence-plausibility evidence

'generate_undetected_diversity' treats every species with zero occurrence records identically - the generic global-floor 'Beta(1, N_total - 1)', regardless of whether it has never been recorded within a thousand kilometers, or has real external evidence (a documented invasion-front species, a corroborated nearby record just outside the study bbox) making it a materially more plausible detection. This function is the single, shared mechanism for elevating that floor for named species, given evidence from any number of independent sources - designed so multiple sources can be combined ...

| Param | Required | Default | Doc |
|---|---|---|---|
| taxaexpect_priors | yes |  | Data frame. Must already contain the undetected_type == "global_floor" row from generate_undetected_diversity (errors if absent). Used both as the source of the floor/singleton anchors and to determine which evidence taxa are already observed. |
| model_obj | yes |  | A taxaexpect_kernel_priors object (output of estimate_kernel_priors). Kernel estimates are always habitat-stratified, so output rows sit on the same schema as every other prior-generating function in this package. |
| evidence | yes |  | Data frame (typically the row-bound output of one or more evidence-generating functions, e.g. generate_invasive_watch_evidence). Required columns: taxon_name (character), weight (numeric, 0-1 -- the source's probability of local presence), source (character, for audit only). Optional: p_conc (numeric, > 0; default 1) -- how much weight the presence claim carries against future evidence, in pseudo-observations -- the Beta concentration itself is always moment-matched, not caller-supplied. Additional source-specific columns are ignored by this function. |
| grid_id | yes |  | Character. Single grid cell identifier this call applies to -- required, no default (mirrors generate_domestic_food_priors's single-site-per-call convention; a multi-site study calls this once per site). TaxaAssign::join_priors()'s primary join requires an exact grid_id match, so the output rows are only usable for observations at this specific site. |
| main_habitat | no | NULL | Character. Single habitat category this call applies to. Always required -- kernel estimates are always habitat-stratified. There is no habitat-agnostic option here, unlike generate_domestic_food_priors()'s main_habitat = NA rows (which join_priors() now has a dedicated fallback tier for) -- occurrence-plausibility evidence is deliberately habitat-AWARE, since a freshwater species found nearby is only locally plausible in a freshwater habitat, a real constraint that domestic/food contamination risk does not share. |
| taxonomy | no | NULL | Optional data frame with columns taxon_name and any subset of genus, family, order, class, phylum, joined onto the result the same way generate_undetected_diversity(taxonomy = ...) does. Default NULL. |
| pricing | no | c("blend", "curve") | "blend" (default, a floor-additive presence mixture: theta = floor + w*(ceiling - floor)) or "curve" (theta = w * theta_present with theta_present = missing_mass / f1 from the kernel fit -- the mean theta of the neighborhood's own observed singletons -- and theta_absent = 0). Pricing off f1 rather than chao_missing avoids chao_missing's own radius-instability (4x-21x on real data, driven by dividing by a doubleton count that sits in the single digits). chao_missing remains available on the kernel fit as a separate, reported-not-enforced budget AUDIT figure (sum(w) vs chao_missing -- an estimate of the total unseen-species count, not the price); it does not feed the price itself, and sum(w) is not expected to equal it exactly. Curve pricing removes the floor term that dominates every blended row. Requires a taxaexpect_kernel_priors model_obj with a finite theta_present (at least one neighborhood singleton), or a multi-group fit, in which case each taxon is priced by its OWN sampling group's budget (see Per-group curve pricing). |
| sampling_group | no | NULL | Which sampling group each evidence taxon belongs to. Required (and only meaningful) when model_obj was fitted with sampling_group_col and pricing = "curve". Accepts a single group name (the whole evidence list shares one detection process -- the common case, e.g. an all-fish invasive-watch list), a named character vector (taxon -> group), or a data frame with taxon_name and sampling_group columns. A sampling_group column on evidence itself takes precedence. Deliberately NEVER inferred from taxonomy: the classification that produced the occurrence pool's groups lives in the caller's workflow, and a wrong group mis-prices silently rather than failing. |
| group_fallback | no | c("pooled_qualifying", "error", "skip") | What to do with an evidence taxon whose group fails the pricing guards. "pooled_qualifying" (default) prices it at the qualifying groups' combined budget and says so, per row, in pricing_basis; "error" refuses; "skip" drops those taxa with a message. Ignored for single-group fits. |
| min_group_n_eff | no | 100 | Support a sampling group must have before its own budget is trusted: at least this many effective records (default 100) and this many neighborhood singletons (default 1). Ignored for single-group fits. |
| min_group_f1 | no | 1L | Support a sampling group must have before its own budget is trusted: at least this many effective records (default 100) and this many neighborhood singletons (default 1). Ignored for single-group fits. |

**Value:** A tibble with one row per eligible taxon named in 'evidence': taxon_name The real taxon name. taxon_name_rank Always '"species"' - required for the row to match 'TaxaAssign::join_priors()''s composite join key. grid_id, main_habitat As supplied. alpha, beta Beta(alpha, beta) prior parameters. theta_mean, theta_sd Derived from alpha/beta. model_tier Always '"tier_undetected_evidence"'. Kernel-path output uses 'prior_branch' + 'effective_records' instead; this column is kept for schema parity with every other prior-generating function in this package. undetected_type Always '"evidence_blend"' - a new value alongside '"singleton_mirror"'/'"global_floor"'. evidence_weight The combined 'w_combined' for this taxon (audit column). prior_mix_w, prior_mix_theta_present, prior_mix_theta_absent The presence mixture itself, consumed by 'TaxaAssign::compute_posterior()''s presence-draw sampler. prior_mix_p_conc Combined presence-claim confidence (pseudo-observations) - reserved for the confirmation update; does not affect the static prior's marginal moments. prior_mix_var_present, prior_mix_var_absent Within-state variance at the present/absent anchor. Both exactly 0 under 'pricing = "curve"' (point-mass states); under '"blend"', the singleton-mirror/floor Beta variances that already enter this row's own 'v_mix' above. Carried so a later re-moment-match (e.g. 'TaxaAssign::update_prior_from_consensus()''s confirmation update) can reproduce the same variance formula instead of silently dropping these two positive terms. prior_mix_veto_bound The weight above which this row could veto species-level resolution of a genuinely observed singleton-level native (the same bound printed above, at construction time). Only ever non-'NA' for 'pricing = "blend"' rows - under '"curve"' the bound is a fixed, always-unreachable constant (see The printed veto bound), so there is nothing meaningful to cap against and this column is always 'NA' there. Persisted so 'TaxaAssign::update_prior_from_consensus()''s confirmation update - which can independently push 'prior_mix_w' past this bound via correlated cross-observation support - can cap its own result against it too, not just this row's construction-time value. evidence_sources Semicolon-joined distinct 'source' values that contributed to this row (audit column). sampling_group, pricing_basis Curve pricing only: the detection process this row was priced by, and whether that price was the group's own ('"own_group"') or borrowed from the qualifying groups ('"pooled_qualifying"'). plus taxonomy rank columns when 'taxonomy' is supplied. Empty tibble (correct schema, zero rows) when no evidence taxon is eligible.

#### Why one shared function, not one per evidence source

If each evidence source (e.g. an invasive-species watch list, a regional-proximity check) independently constructed and appended its own finished Beta(alpha, beta) row to taxaexpect_priors, that would break the moment a species qualifies under more than one source at once: TaxaAssign::join_priors() joins on the composite key (taxon_name, taxon_name_rank, grid_id, main_habitat), so two independently-appended rows sharing that key would produce an ambiguous join -- silently picking one, fanning out into duplicate hypotheses, or erroring, depending on row order. This function is the single place a new evidence-elevated row is ever created, so that collision is structurally impossible: every source's opinion about a given taxon is combined before one row is written.

#### Evidence sources are decoupled from prior construction

evidence is deliberately a thin, source-agnostic table -- a source function (e.g. an invasive-watch-list generator) never touches taxaexpect_priors, never does Beta-parameter math, and knows nothing about the floor/singleton anchors. It only answers, per taxon: how probable is local presence (weight = P(present | this source's evidence)) and how much weight that presence claim should carry against future evidence (p_conc, pseudo-observations; optional, default 1)? This function is the only consumer that turns those into an actual prior.

#### How the elevation works

For each taxon in evidence that is genuinely unobserved (see Which species are eligible below), the floor's own (alpha, beta) is read directly out of taxaexpect_priors (not recomputed), and the site's own singleton-mirror mean is used as an upper anchor -- the two values generate_undetected_diversity already produces. The elevated prior is a PRESENCE MIXTURE: with probability w_combined the species is locally present (theta ~ the ceiling-anchor state), with probability 1 - w_combined absent (theta ~ the floor state). The blended mean is that mixture's exact expectation, and the Beta summary's concentration is moment-matched to the mixture's variance -- not caller-chosen:


```

theta_new = theta_floor + (theta_singleton - theta_floor) * w_combined v = w*Var_ceiling + (1-w)*Var_floor + w*(1-w)*(theta_c-theta_f)^2 n_eff_mm = theta_new*(1-theta_new)/v - 1 alpha_new = theta_new * n_eff_mm; beta_new = (1-theta_new) * n_eff_mm ```

The mixture itself is also emitted (prior_mix_w/ prior_mix_theta_present/prior_mix_theta_absent) so TaxaAssign::compute_posterior() can integrate over presence states directly (an explicit Bernoulli presence draw) instead of sampling the J-shaped Beta summary; alpha/beta remain the point-path summary. prior_mix_p_conc does NOT affect these marginal moments (for a two-point presence mixture, uncertainty about w cancels out of the marginal variance) -- it records how much weight the presence claim carries against future evidence, for the confirmation update. Blending toward theta_singleton gives a ceiling: at w_combined = 1 the elevated prior equals the singleton-mirror mean exactly, so external evidence -- however strong -- can never make an unobserved species look more plausible than one genuinely detected once.

Ceiling anchor ladder (datasets without singletons): when taxaexpect_priors carries no singleton_mirror rows at all, the upper anchor -- "the detection rate of a species present but rare enough to have plausibly escaped local detection" -- is estimated by descending a ladder instead of silently collapsing onto the floor: (1) the minimum theta among genuinely modelled rows (site-scoped rows preferred; a mild, safe-direction overestimate, since a no-singleton dataset detected every species at least twice); (2) one detection per site effort, 1 / (median(n_obs) + 1); (3) only if neither is computable, a floor-equals-ceiling fallback with a warning.

#### The printed veto bound (pricing = "blend" only)

Each blend-mode call prints the dataset-specific weight above which an unobserved species can block species-level resolution of a singleton-level observed native at likelihood parity (derived from the anchors and the consensus default min_posterior = 0.05). Choose watch-list weights BELOW this bound unless you deliberately intend elevated species to compete with observed ones.

pricing = "curve" has no analogous veto bound: theta_present is priced from mass/f1 (see estimate_kernel_priors), pinned to exactly the neighborhood's own singleton mean, which makes the curve veto bound a fixed ((1-m)/m) = 19 at the default min_posterior = 0.05 for every group -- unreachable for any admissible weight <= 1 and therefore never informative. Pricing off f1 rather than Chao keeps it unreachable. The call prints f1 (and, for a multi-group fit, the whole per-group budget) next to the price, but names no bound.

#### Per-group curve pricing

A model_obj fitted with sampling_group_col carries one Good-Turing budget PER GROUP, and those budgets are not interchangeable (on real multi-group data they can span orders of magnitude, and a single pooled price can sit below every priced group). Under pricing = "curve" each taxon is therefore priced at its own group's theta_present, resolved from sampling_group.

The guards. Per-group budgets fail in ways a pooled one does not:

- No anchor. A group with f1 = 0 has no budget at all, since theta_present = missing_mass / f1 is undefined there.

- Too thin to trust. A group with very few effective records can price a single unseen species at a large share of its own community. min_group_n_eff/min_group_f1 exclude these.

No cap at the group's singleton mean is needed: theta_present IS the singleton mean by construction (mass/f1).

A group failing the guards is priced by group_fallback. The "pooled_qualifying" price combines the qualifying groups GROUP-WISE and never by re-pooling records (which would reintroduce the f1 inflation per-group pricing exists to remove): unseen-species counts and missing masses both add across disjoint groups, giving the missing mass of the union as a share of the union's own singleton count -- the same mass/f1 formula as any single qualifying group.

Every row records sampling_group and pricing_basis ("own_group" or "pooled_qualifying"), and the call prints the whole per-group budget with the price adopted for each. A borrowed price is never silent.

Single-group fits are untouched. The guards police borrowing BETWEEN groups. With one group the caller has asserted the whole stratum is a single detection process; that assertion is not second-guessed here (its f1/f2 are printed, and kernel_budget_sensitivity() is the tool for interrogating it).

#### Combining multiple sources for one taxon

When more than one evidence row names the same taxon (e.g. a regional- proximity signal and an invasive-watch-list signal both fire for one species), the weights combine via w_combined = 1 - prod(1 - weight_i) and the presence-claim confidences combine via p_conc_combined = sum(p_conc_i) This assumes the evidence sources are independent readers of different underlying facts -- e.g. a curated invasion-biology database and raw occurrence geography are evidentially unrelated, not two noisy reads of the same signal. It is NOT safe for every pair of sources: a plain maximum or probabilistic-OR combination across CORRELATED confirmations (e.g. several observations reviewed by one classifier that cannot separate two similar species) manufactures spurious confidence that renormalization does not undo (see TaxaAssign::update_prior_from_consensus()'s confirmation-quantile design). Before combining a new evidence source with an existing one, confirm they are independent; two sources both derived from the same underlying occurrence database would need this revisited.

#### Which species are eligible

Only taxa with no row anywhere in taxaexpect_priors are eligible -- checked against both taxon_name (catches Tier 1/2 modelled rows and named rows from other prior sources, e.g. generate_domestic_food_priors) and source_taxon_name (catches singleton mirrors, whose own identity lives in that column, not taxon_name). A species detected even once is not dark diversity, regardless of what external evidence says about it, and is left untouched.

#### Deliberately out of scope

domestic/food priors: generate_domestic_food_priors is NOT a valid evidence source for this function and should never be fed into evidence. A domestic/food-list detection and an occurrence-plausibility detection (invasive-watch, regional-proximity) are opposite claims about the same zero-local-record fact: the former is plausible because the species is transported/food-handled near the site (a contamination-risk signal, unrelated to whether a wild population exists), the latter because a real wild population might be present. OR-combining them would conflate two questions into one number. A taxon flagged by both mechanisms is surfaced as two distinct reviewer-facing caveats (see TaxaFlag::add_posthoc_assessment()'s domestic_prior_caveat), not collapsed here.

### calibrate_kernel_bandwidth(occurrence_data, site_habitat, lambda_grid = c(10, 25, 50, 100, 200), m_grid = 1, covariate_col = NULL, lambda_covariate_grid = NULL, lambda_latitude_grid = NULL, block_size_deg = 0.5, min_block_records = 20L, sampling_group_col = NULL, min_group_records = NULL, smoothing = 0.5, taxon_col = "taxon_name", lat_col = "decimalLatitude", lon_col = "decimalLongitude", habitat_col = "main_habitat", habitat_levels = NULL, habitat_weights = NULL)

Calibrate kernel bandwidths by leave-one-block-out composition prediction

Chooses 'lambda_km' (and optionally the covariate bandwidth and the back-off mass 'm') for 'estimate_kernel_priors()' empirically: records are partitioned into spatial blocks; each block's species composition is predicted from all records _outside_ it, using the same kernel machinery evaluated at the block's own data centroid; predictions are scored by per-record multinomial log-loss against the block's actual records. Two reference predictors are always scored alongside for context: 'regional' (all held-out records, unweighted - "is locality worth anything?") and 'nearest_block' (the ...

| Param | Required | Default | Doc |
|---|---|---|---|
| occurrence_data | yes |  | As in estimate_kernel_priors(). |
| site_habitat | yes |  | As in estimate_kernel_priors(). |
| lambda_grid | no | c(10, 25, 50, 100, 200) | Numeric vector of candidate geographic bandwidths (km). Default c(10, 25, 50, 100, 200). |
| m_grid | no | 1 | Numeric vector of candidate back-off masses. Default 1 (calibrate lambda only). Supply several values to tune m jointly. |
| covariate_col | no | NULL | Optional: a numeric record column (e.g. depth) and candidate bandwidths for its kernel factor. When supplied, every (lambda, lambda_covariate, m) combination is scored; the block's mean covariate value stands in for the "site" value. NULL (default) disables the covariate factor. |
| lambda_covariate_grid | no | NULL | Optional: a numeric record column (e.g. depth) and candidate bandwidths for its kernel factor. When supplied, every (lambda, lambda_covariate, m) combination is scored; the block's mean covariate value stands in for the "site" value. NULL (default) disables the covariate factor. |
| lambda_latitude_grid | no | NULL | Optional numeric vector: candidate bandwidths (km) for estimate_kernel_priors()'s climate-similarity factor on the absolute-latitude difference. Inf (factor off) is always added to the sweep so the no-factor case competes on equal footing -- a best row with lambda_latitude = Inf means the data rejected the factor. NULL (default) omits the dimension entirely. |
| block_size_deg | no | 0.5 | Numeric scalar: CV block size in degrees (default 0.5). A block enters scoring only if it holds at least min_block_records records. |
| min_block_records | no | 20L | Integer, default 20L. |
| sampling_group_col | no | NULL | Optional column naming a detection-process grouping (e.g. "sampling_group") -- the same column passed to estimate_kernel_priors(). NULL (default) scores ONE pooled composition. Pass it whenever the estimator will be given it. See Why pooling the groups fits the wrong lambda. |
| min_group_records | no | NULL | Minimum records a group must contribute to a block before that (block, group) cell is scored. NULL (default) follows min_block_records, which makes this function's stratified fit agree on block eligibility with the other way of fitting per group -- subsetting to one group and calling this function on each subset. Lower it to admit sparse cells; a thin group's loss curve will flatten when you do. Ignored without sampling_group_col. |
| smoothing | no | 0.5 | Laplace pseudo-count added to every species when forming a predicted composition, so held-out species never score -Inf (default 0.5). |
| taxon_col | no | "taxon_name" | As in estimate_kernel_priors(). |
| lat_col | no | "decimalLatitude" | As in estimate_kernel_priors(). |
| lon_col | no | "decimalLongitude" | As in estimate_kernel_priors(). |
| habitat_col | no | "main_habitat" | As in estimate_kernel_priors(). |
| habitat_levels | no | NULL | Optional, supplied together, as on estimate_kernel_priors(): with both, a record whose habitat could not be placed joins the cross-validation at its taxon's site_habitat weight -- as that fraction of a record when it is a prediction target and as that fraction of its kernel weight when it is held out -- so the bandwidth is chosen on the pool the estimator will see. Pass the same two arguments to both functions. |
| habitat_weights | no | NULL | Optional, supplied together, as on estimate_kernel_priors(): with both, a record whose habitat could not be placed joins the cross-validation at its taxon's site_habitat weight -- as that fraction of a record when it is a prediction target and as that fraction of its kernel weight when it is held out -- so the bandwidth is chosen on the pool the estimator will see. Pass the same two arguments to both functions. |

**Value:** A list with results Data frame: one row per parameter combination plus the 'regional' and 'nearest_block' references; columns 'lambda_km', 'lambda_covariate', 'lambda_latitude', 'm', 'mean_logloss' (simple mean over blocks), 'weighted_logloss' (record-weighted), 'blocks_beating_nearest'. best The row minimizing 'weighted_logloss' among kernel rows. n_blocks Number of scored blocks. by_group 'NULL' without 'sampling_group_col', or with a single group. Otherwise one row per group: 'sampling_group', 'n_records', 'n_blocks_scored', that group's own optimal 'lambda_km', 'lambda_covariate', 'lambda_latitude', 'm', and its 'weighted_logloss'. Read it before trusting 'best'.

#### Details

The spatial blocks are a cross-validation device only -- they impose no structure on the estimator being calibrated (this is the one place a grid appears in the kernel estimator, and the only job it keeps).

#### Why pooling the groups fits the wrong lambda

Composition is a share WITHIN a detection process. With one pooled composition, a block's log-loss is dominated by whichever group contributed the most records, so lambda is fitted to that group and then handed to every group by estimate_kernel_priors(). It does not announce itself: the fit succeeds and returns a plausible number, just the wrong one for every group but the dominant one.

With sampling_group_col set, each (block, group) cell is scored against that group's own composition, over that group's own species universe, and the cells are combined weighting each group by the target records it contributed. A record counts once, so a group's influence is its share of the data -- not one-group-one-vote, which would let a 20-record group outvote a 200,000-record one.

Two details that are easy to get wrong and are handled here. The species universe is per group: smoothing a group's composition over the FULL species set would put smoothing mass on every species that group can never contain, shrinking its real probabilities by the ratio of the two set sizes -- an invisible, group-size-dependent penalty. And a (block, group) cell is skipped when the group has fewer than 2 target records there or no held-out records at all, since a 1-record target is a degenerate composition; the count of skipped cells is reported.

One lambda is still one lambda. estimate_kernel_priors() takes a scalar lambda_km, so this function cannot give each group its own. What it can do is say whether that is defensible: $by_group reports each group's own optimum, and a warning fires when they differ by 2x or more. On a fixture with 4 km patches in one group and 55 km patches in another, the groups chose 5 km and 25 km and the record-weighted compromise was 5 km -- correct for the dominant group, 5x too narrow for the other. Treat that warning as a prompt to fit the groups separately, not as noise.

### condition_evidence_on_habitat(evidence, habitat_lookup, site_habitat, w_floor = 0, verbose = TRUE)

Condition Presence Evidence on the Site Habitat

Multiplies each evidence row's presence weight by the taxon's own weight for the site habitat, floored at the weight a taxon with no evidence at all receives. Applied to the output of 'generate_regional_proximity_evidence', 'generate_presence_curve_evidence' and 'generate_inat_range_evidence' BEFORE 'apply_undetected_evidence' prices the rows.

| Param | Required | Default | Doc |
|---|---|---|---|
| evidence | yes |  | Data frame with taxon_name and weight columns (any evidence generator's output). |
| habitat_lookup | yes |  | Data frame from TaxaHabitat::build_habitat_lookup(): taxon_name plus one numeric weight column per habitat class. |
| site_habitat | yes |  | Character scalar naming the site's habitat column in habitat_lookup. |
| w_floor | no | 0 | Numeric in [0, 1). The weight below which no evidence row may fall -- pass the run's clamp weight (w_scale * exp(-d_cap / d_half) under curve pricing). Default 0. |
| verbose | no | TRUE | Logical. Report counts. Default TRUE. |

**Value:** 'evidence' with 'weight' replaced by the conditioned weight and three added columns: 'habitat_weight' (H_{site}, 'NA' when unknown), 'weight_unconditioned' (the generator's original weight) and 'habitat_floored' ('TRUE' where the product fell below 'w_floor').

#### Details

Why. The resident priors are stratified by habitat: a record only enters the site's pool when its point (classified by the community observed there, TaxaHabitat::assign_habitat_biological()) carries the site habitat. Evidence rows skipped that stratification, so a distant record of a species that never occupies the site habitat was priced more generously than a local population of the same species. A real case: a red deer record 54 km from Point Conception earned a prior 480 times the zero-record floor at a marine site, while the deer living on the site itself sat at that floor; a mountain whitefish record 355 km from Pt. Mugu out-competed four unrecorded congeners at an estuary.

The rule. w_{site} = \max(w \cdot H_{site}, w_{floor}) where w is the generator's own presence weight (P(present in the region | evidence)), H_{site} the taxon's weight for the site habitat from the same LLM habitat lookup that supplies the residents' point votes (P(occupies the site habitat | present in the region)), and w_{floor} the clamp weight every zero-evidence taxon receives. The product is P(present in the site habitat | evidence) under independence of distance and habitat -- the same product-kernel assumption estimate_kernel_priors makes for geography and a covariate. Because the rule is linear in H_{site}, habitat bleed survives in proportion: a steelhead with Marine 0.25 keeps a quarter of its regional weight at a marine site; a terrestrial mammal with Marine 0 drops to the floor. A taxon absent from habitat_lookup (or with an NA weight) is left unchanged and counted in a message -- no information, no change.

### estimate_kernel_priors(occurrence_data, site_lat, site_lon, site_habitat, lambda_km, m = 1, covariate_col = NULL, site_covariate = NULL, lambda_covariate = NULL, lambda_latitude = NULL, site_id = NULL, taxon_col = "taxon_name", lat_col = "decimalLatitude", lon_col = "decimalLongitude", habitat_col = "main_habitat", sampling_group_col = NULL, count_col = NULL, support_weight = exp(-3), habitat_levels = NULL, habitat_weights = NULL)

Estimate site priors by distance-kernel weighting of occurrence records

Computes each species' expected share of legitimate detections at a sampling site ('theta') directly from habitat-stratified occurrence records, weighting every record by its distance to the site:

| Param | Required | Default | Doc |
|---|---|---|---|
| occurrence_data | yes |  | Data frame of cleaned, habitat-labelled occurrence records (one row per record). |
| site_lat | yes |  | Numeric scalars. The sampling site coordinates. |
| site_lon | yes |  | Numeric scalars. The sampling site coordinates. |
| site_habitat | yes |  | Character scalar. Focal habitat; records are stratified to habitat_col == site_habitat before any weighting. |
| lambda_km | yes |  | Numeric scalar. Geographic kernel bandwidth in km. Required, no default: the defensible value is dataset-specific -- derive it with calibrate_kernel_bandwidth() (leave-one-block-out composition prediction) rather than guessing. |
| m | no | 1 | Numeric scalar >= 0. Regional pseudo-records for the Dirichlet back-off (default 1, a weakly-informative single pseudo-record; tunable via calibrate_kernel_bandwidth()). m = 0 disables shrinkage. |
| covariate_col | no | NULL | Optional character. Name of a SINGLE numeric record column (e.g. "depth_m") for the product kernel -- accepts one scalar column name only. A second covariate (e.g. time) is not supported by the product kernel as written; adding one would require a second lambda_*/site_* pair and a genuine multi-factor product, not just a longer vector here. NULL (default) disables it. |
| site_covariate | no | NULL | Numeric scalar. The site's own value of covariate_col. Required when covariate_col is supplied. |
| lambda_covariate | no | NULL | Numeric scalar. Covariate kernel bandwidth, in the covariate's own units. Required when covariate_col is supplied. Records with NA covariate values receive the neutral weight 1 for the covariate factor (distance factor still applies) rather than being dropped. |
| lambda_latitude | no | NULL | Optional numeric scalar. Bandwidth (km) for a climate-similarity factor exp(-111 * \|\|lat\| - \|site_lat\|\| / lambda_latitude) on the ABSOLUTE latitude difference -- records from the site's own climate band (same \|latitude\|, either hemisphere) keep full weight while records poleward/equatorward of it decay, making north-south kilometers cost more than east-west kilometers. NULL (default) disables the factor. Tunable via calibrate_kernel_bandwidth()'s lambda_latitude_grid. |
| site_id | no | NULL | Character scalar. Identifier stamped on the output rows' grid_id column (kept under that name for downstream join compatibility; the value is treated as opaque everywhere downstream). Default: "Site_<lat>_<lon>". |
| taxon_col | no | "taxon_name" | Column names in occurrence_data (defaults "taxon_name", "decimalLatitude", "decimalLongitude", "main_habitat"). |
| lat_col | no | "decimalLatitude" | Column names in occurrence_data (defaults "taxon_name", "decimalLatitude", "decimalLongitude", "main_habitat"). |
| lon_col | no | "decimalLongitude" | Column names in occurrence_data (defaults "taxon_name", "decimalLatitude", "decimalLongitude", "main_habitat"). |
| habitat_col | no | "main_habitat" | Column names in occurrence_data (defaults "taxon_name", "decimalLatitude", "decimalLongitude", "main_habitat"). |
| sampling_group_col | no | NULL | Optional column naming a detection-process grouping (e.g. "sampling_group"). Default NULL: all taxa share one composition and one Good-Turing budget. This default is not a safe "do nothing" choice: with no sampling_group_col, every record is pooled regardless of detection process, with no warning or error, even when that means silently mixing genuinely incompatible processes (e.g. phytoplankton cell counts with bird point counts). Grouping is never inferred automatically from taxonomy or data -- this function has no way to know which taxa were sampled by a comparable process, so it never guesses. Supplying a correct sampling_group_col is the caller's responsibility, built BY HAND from real knowledge of detection methodology -- there is no automated way to detect "comparable method" from taxonomy or data alone (an LLM guess is not a substitute for real methodological knowledge either). This is not a burdensome ask: this function does NOT require pre-merged, sample-size-adequate groups for statistical adequacy -- it degrades gracefully, producing honestly wide uncertainty for a sparse group on its own (empirically confirmed on a real 9-group expert classification down to a single-taxon group, see README.md's "Shared detection effort" section) -- so classify at whatever granularity genuinely reflects distinct detection methods, without worrying whether each resulting group individually "has enough data." When supplied, theta AND the budget (f1, f2, missing_mass, chao_missing, theta_present) are computed WITHIN each group, because both are shared-denominator quantities that assume a common detection process. Pooling across processes dilutes a detectable taxon's share with records the assay could never amplify, and lets barely-sampled groups contribute singletons that inflate f1 -- and so chao_missing, quadratically -- while adding almost nothing to missing_mass, deflating theta_present (theta_present is priced from missing_mass / f1, so a diluted missing_mass still deflates it even though chao_missing does not itself appear in it). Note this is a no-op for a taxonomically homogeneous pool (a fish assay whose occurrence pool is all fish), which is why it changes nothing at sites like GreatLakes; it matters for broad markers (18S) spanning groups with very different detection probabilities. With more than one group the pooled scalars are NA by design and $budget is authoritative -- a single number would be silently wrong. |
| count_col | no | NULL | Optional character. Name of a non-negative numeric column giving how many records each row stands for. NULL (default): every row is one record. With a count column, a row of count n is exactly equivalent to n identical one-record rows -- every sum (W, the Kish denominator, the kernel-weighted and regional compositions, the neighborhood-support counts behind f1/f2) is count-weighted -- so aggregated inputs such as gridded occurrence cubes or estimate_kernel_priors_from_counts()'s distance bands reuse this estimator unchanged. Rows with a count of zero are dropped. |
| support_weight | no | exp(-3) | Numeric in (0, 1]. A record counts toward the discrete neighborhood-support statistics (singleton detection, record counts) when its total kernel weight is at least support_weight (default exp(-3), i.e. within ~3 bandwidths). Continuous quantities (theta, n_eff) always use all records. |
| habitat_levels | no | NULL | Optional, supplied together. By default a record enters the stratum only when its habitat_col label equals site_habitat, so a point the habitat consensus could not place ("Uncertain", NA, "") is left out whatever lives there. With habitat_levels (the scheme's declared habitat names, e.g. simple_scheme$l1_name) and habitat_weights (the per-taxon table TaxaHabitat::build_habitat_lookup() returns: taxon_name plus one column per habitat holding the taxon's probability of occupying it), such an UNPLACEABLE record counts toward the stratum at its taxon's own site_habitat weight, as that fraction of a record; a record in a DIFFERENT declared habitat stays excluded, and a taxon with no weight contributes nothing (counted in the message). Unplaceable means a no-verdict label: NA, "", "Uncertain", "Unknown", "Unassigned". "Other" is a PLACED verdict (TaxaHabitat::assign_habitat_biological() emits it for a point that is none of the scheme's habitats) and stays excluded like any other habitat. Any other label not in habitat_levels is excluded too and named in a warning: a scheme that does not list a label its classifier emits is an easy trap, and exclusion is the direction that cannot add weight by mistake. (This differs from generate_uncertain_habitat_evidence(), which recovers every undeclared label as evidence.) The fraction enters W, n_eff and the regional composition; it is not a whole detection and does not count toward f1/f2. Pass the same two arguments to calibrate_kernel_bandwidth(), so the bandwidth is chosen on the pool the estimator sees; plot_theta_surface() reads them from the fit. Do not also price these records through generate_uncertain_habitat_evidence(), which would count them twice. |
| habitat_weights | no | NULL | Optional, supplied together. By default a record enters the stratum only when its habitat_col label equals site_habitat, so a point the habitat consensus could not place ("Uncertain", NA, "") is left out whatever lives there. With habitat_levels (the scheme's declared habitat names, e.g. simple_scheme$l1_name) and habitat_weights (the per-taxon table TaxaHabitat::build_habitat_lookup() returns: taxon_name plus one column per habitat holding the taxon's probability of occupying it), such an UNPLACEABLE record counts toward the stratum at its taxon's own site_habitat weight, as that fraction of a record; a record in a DIFFERENT declared habitat stays excluded, and a taxon with no weight contributes nothing (counted in the message). Unplaceable means a no-verdict label: NA, "", "Uncertain", "Unknown", "Unassigned". "Other" is a PLACED verdict (TaxaHabitat::assign_habitat_biological() emits it for a point that is none of the scheme's habitats) and stays excluded like any other habitat. Any other label not in habitat_levels is excluded too and named in a warning: a scheme that does not list a label its classifier emits is an easy trap, and exclusion is the direction that cannot add weight by mistake. (This differs from generate_uncertain_habitat_evidence(), which recovers every undeclared label as evidence.) The fraction enters W, n_eff and the regional composition; it is not a whole detection and does not count toward f1/f2. Pass the same two arguments to calibrate_kernel_bandwidth(), so the bandwidth is chosen on the pool the estimator sees; plot_theta_surface() reads them from the fit. Do not also price these records through generate_uncertain_habitat_evidence(), which would count them twice. |

**Value:** An object of class '"taxaexpect_kernel_priors"': a list with priors Data frame: 'taxon_name', 'grid_id', 'main_habitat', 'alpha', 'beta', 'theta_mean', 'theta_sd', 'prior_branch', 'effective_records'. n_eff Kish effective sample size at the site. W Total kernel weight. singletons Data frame of neighborhood singletons (species with exactly one supporting record): 'taxon_name', record 'lat'/'lon', 'weight', 'effective_records'. missing_mass Weighted Good-Turing missing mass: the summed effective share of singleton species - the budget available to the resident-undetected branch (consumed by later machinery, not here). f1, f2 Neighborhood-support singleton and doubleton species counts (records with kernel weight >= 'support_weight'). chao_missing Chao (1984) estimated number of locally-present but unrecorded species: 'f1^2/(2*f2)', with the standard 'f1*(f1-1)/2' fallback when 'f2 = 0'; '0' when 'f1 = 0'. Not part of 'theta_present''s price (see next item) - kept for the budget AUDIT ('sum(w)' vs 'chao_missing' in 'apply_undetected_evidence', reported not enforced). theta_present 'missing_mass / f1': the mean theta of the neighborhood's own observed singletons - "a species we barely detect here" - used by 'apply_undetected_evidence''s curve pricing. Deliberately NOT 'missing_mass / chao_missing': 'f1' is observed directly, while 'chao_missing' divides by the doubleton count 'f2', which sits in the single digits and is radius-unstable (measured 4x-21x across a plausible counting-radius range on real data) - instability this price avoids. 'NA' when no singleton anchor exists ('f1 = 0'). regional_composition Named numeric: the unweighted habitat-stratified composition used for back-off. params The call's tuning values, for provenance.

#### Details

A hard grid cell is the special case of a top-hat kernel: with all weights equal, theta reduces to ordinary record shares, n_eff to the record count, and the singleton set to species seen exactly once.

#### Why an estimator, not a spatial model

Several modeling strategies were considered for pricing spatial priors, including grid-cell GLMM prediction and per-species latent spatial fields (GP/SPDE/GAMM); the kernel estimator was adopted because leave-one-cell-out validation on real Great Lakes data found distance-kernel composition prediction beats both single grid-cell GLMM prediction (the worst of the options tested) and unweighted regional pooling, with an interior bandwidth optimum, and because it runs in O(records) with no optimization step (~0.1 s at 1.8 million records), so cost is independent of species count -- unlike per-species latent spatial fields, which are computationally infeasible at many-species scale.

#### Output schema

The returned $priors table's prior_branch (here always "kernel_estimated") and effective_records (the species' kernel-effective record count c_i * n_eff / W, in units of records) are its row-provenance and evidence-weight columns.

prior_branch is written as a CONSTANT on every row this function emits. It records which generator produced the row, not how much evidence stands behind it -- that is effective_records, and it spans roughly ten orders of magnitude within this one branch, continuously and with no natural break. The name "kernel_estimated" deliberately makes no evidence claim: on the real PtConception 12S priors 44.9% of labelled rows carried under one effective record (64.9% at 18S). Consumers that need an evidence claim must threshold effective_records themselves; see TaxaAssign::posterior_consensus()'s min_effective_records. Undetected/evidence/domestic rows belong to other branches and are appended by their own generators, not this function. A species whose nearby records are all classified to a habitat other than site_habitat yields NO resident row here at all and is indistinguishable, at this stage, from a species with no nearby records whatsoever -- it only re-enters via the evidence pathway (apply_undetected_evidence()), where the taxon-level habitat weight (condition_evidence_on_habitat()) applies a SECOND, continuous discount on top of whatever this function already omitted.

#### Habitat is not a kernel covariate (measured, left out)

Habitat enters this estimator as a record FILTER (the site stratum) and, with habitat_weights, as a per-record weight for unplaceable records. A third form, treating habitat as a dimension of the product kernel through a declared habitat-to-habitat similarity, was built and measured against the Great Lakes pool and deliberately left out: leave-one-block-out prediction of the in-habitat composition got WORSE at every similarity strength (loss 3.375 at strength 0, 3.426 at 0.25, 3.487 at 0.5, 3.594 at 1, against a no-space reference of 3.623), and a taxon-affinity weight on every off-habitat record performed the same as the similarity. Habitat is an unordered categorical variable with no metric, so any such kernel is a declared table rather than a measurement; the data did not support one.

### estimate_kernel_priors_from_counts(occurrence_counts, site_habitat, lambda_km, m = 1, habitat_filter = c("none", "taxon_threshold"), habitat_lookup = NULL, habitat_threshold = 0.5, extra_occurrences = NULL, sampling_group_col = NULL, site_id = NULL, support_weight = exp(-3), habitat_levels = NULL, habitat_weights = NULL)

Estimate site priors from GBIF band counts (no record download)

The fast path to the same prior object 'estimate_kernel_priors()' returns. Input is 'TaxaFetch::fetch_gbif_occurrence_counts()': per-species GBIF record counts in concentric distance bands around the site. Each band becomes one pseudo-record carrying its count, placed at the band's representative distance, and the fit is delegated to 'estimate_kernel_priors()' with 'count_col' - so 'theta', the Beta parameters, 'effective_records', the regional back-off, the per-group Good-Turing budget and every warning are computed by exactly the same code, and the result slots into ...

| Param | Required | Default | Doc |
|---|---|---|---|
| occurrence_counts | yes |  | Tibble from TaxaFetch::fetch_gbif_occurrence_counts() (columns taxon_name, band_lo_km, band_hi_km, n), optionally with a sampling-group column added by TaxaTools::assign_sampling_group(). |
| site_habitat | yes |  | Character scalar. Focal habitat. |
| lambda_km | yes |  | Numeric scalar. Kernel bandwidth, km. Required. |
| m | no | 1 | Numeric >= 0. Regional pseudo-records (as in estimate_kernel_priors()). |
| habitat_filter | no | c("none", "taxon_threshold") | How the band counts are restricted to site_habitat. "none" (default): every counted taxon enters the composition. "taxon_threshold": only taxa whose habitat_lookup weight for site_habitat is at least habitat_threshold. See "What differs from the records path" for the trade-off. Applies to the band counts only; extra_occurrences carry their own record-level habitat. What the default admits. Under "none" a taxon of ANY habitat enters a site's composition if occurrence records put it within the bands, so a freshwater species can receive a (small) prior at a marine site. That is deliberate -- it keeps the counts path comparable with the records path, which also carries whatever the records say -- but it means the prior is not a habitat filter and should not be read as one. Downstream steps that pick one species out of a genus can then select such a taxon purely because it is the only locally recorded member, so pass "taxon_threshold" with a habitat_lookup when the study wants habitat to constrain the prior. Note that main_habitat on the returned rows records the SITE's habitat, not the taxon's, in both modes. |
| habitat_lookup | no | NULL | Data frame or NULL. Required for habitat_filter = "taxon_threshold". Per-taxon habitat weights with a taxon_name column and one numeric column per habitat, named as in site_habitat (the shape TaxaHabitat::build_habitat_lookup() returns). Taxa absent from it are treated like records with no habitat in the records path: dropped, and counted in a message. |
| habitat_threshold | no | 0.5 | Numeric in (0, 1]. Minimum site_habitat weight for a taxon to enter the composition. Default 0.5, the threshold the production workflows pass to assign_habitat_biological(). |
| extra_occurrences | no | NULL | Data frame or NULL. Point records from sources other than GBIF (a local survey, a museum table), one row per record, prepared exactly as for the records path: columns taxon_name, decimalLatitude, decimalLongitude and a record-level main_habitat (e.g. from TaxaHabitat::assign_habitat_biological()), plus the sampling_group_col column when grouping. They are fitted at their true distances in the same composition as the band counts; only rows whose main_habitat is site_habitat count, as in the records path. Make sure they are not ALSO in GBIF (a dataset published to GBIF would be counted twice); exclude it from the count query if it is. |
| sampling_group_col | no | NULL | Optional column in occurrence_counts (and extra_occurrences) naming the detection-process group; passed through to estimate_kernel_priors(). |
| site_id | no | NULL | Character or NULL, as in estimate_kernel_priors(). |
| support_weight | no | exp(-3) | Numeric in (0, 1], as in estimate_kernel_priors(). The support radius -lambda_km * log(support_weight) should be one of the band edges (the default edges include 3 * lambda_km); otherwise the singleton/doubleton counts are only approximate and a warning says so. |
| habitat_levels | no | NULL | Optional, supplied together, as on estimate_kernel_priors(). They apply to extra_occurrences only (the counts carry no points to place): an extra record whose habitat could not be placed joins the fit at its taxon's site_habitat weight. |
| habitat_weights | no | NULL | Optional, supplied together, as on estimate_kernel_priors(). They apply to extra_occurrences only (the counts carry no points to place): an extra record whose habitat could not be placed joins the fit at its taxon's site_habitat weight. |

**Value:** An object of class '"taxaexpect_kernel_priors"', as from 'estimate_kernel_priors()', with 'params$source = "gbif_counts"', 'params$breaks_km', 'params$habitat_mode', 'params$habitat_threshold' and 'params$n_extra_records' added.

#### Representative distance

A band from a to b km is given the kernel weight a record would have on average if the band's records were spread uniformly over its annulus, \bar w = \frac{2}{b^2-a^2}\int_a^b e^{-r/\lambda} r\,dr, and placed at the distance with that weight, -\lambda \log \bar w. The regional remainder band (records in the polygon beyond the last break) has no outer edge and is placed at 1.5 times the last break; with the default breaks that is 13.5 bandwidths, where its weight is negligible and it matters only for the regional back-off, which uses unweighted counts.

#### Slotting into a workflow

Treat the band table like the occurrence table it replaces. Fetch it with the same taxon keys, search polygon and year range; run the same name standardisation on taxon_name (e.g. the GBIF-to-NCBI verify_taxon_names() step), because the count table's names are GBIF-backbone names and priors join to candidates by name; add sampling_group with the same TaxaTools::assign_sampling_group() call; build the habitat lookup with the same TaxaHabitat::build_habitat_lookup() call and cache if you use habitat_filter = "taxon_threshold". Records from other sources (a local survey) are read, name-checked and habitat-assigned as before and passed as extra_occurrences. The fitted object then goes wherever the kernel fit went.

#### What differs from the records path

Measured against the same kernel run on the full GBIF record set for PtConception 18S (1,715 species), the band approximation is within 10x for about 99% of species with theta >= 1e-4; it is coarser in the far tail (species whose nearest records are several bandwidths away), where priors are below 1e-6 regardless. What it cannot reproduce:

- Record-level habitat. The records path labels every point from the community recorded there (TaxaHabitat::assign_habitat_biological()) and keeps only points in site_habitat. Counts have no points. The default, habitat_filter = "none", applies no habitat restriction to the counts and leaves observed_in_habitat NA. "taxon_threshold" applies habitat per TAXON instead: a species enters the composition when its habitat_lookup weight for site_habitat is at least habitat_threshold -- numerator and denominator alike. Neither is the records path's stratum. The records path keeps a species whenever its records sit at points labelled site_habitat, so at a coastal site it keeps shoreline terrestrial plants whose own habitat weight is zero; a taxon-level filter drops them. On PtConception 18S the taxon filter lost 50 of 377 species with theta >= 1e-4 in the record-level Marine stratum, while the unfiltered fit lost none (it adds taxa the records path excludes instead, which only matters for taxa that are also match candidates). Check which error your site can better afford.

- A covariate kernel (e.g. depth) and the |latitude| factor: both need record coordinates. Not available here.

- Bandwidth calibration. calibrate_kernel_bandwidth() needs records. Reuse a lambda_km calibrated for the same region, or choose one deliberately; it is required, as in the records path.

- Singleton coordinates. $singletons carries NA lat/lon (a band has no point), except for a singleton whose one supporting record is an extra_occurrences row. Nothing downstream reads them.

### fit_regional_presence_curve(presence_df, bins = c(0, 100, 200, 400, 700, 1100))

Fit a distance-to-presence curve for regional-proximity weights

The per-dataset, self-calibrating alternative to accepting 'generate_regional_proximity_evidence''s default 'w_scale'/'d_half': estimate P(locally present | nearest external record at distance d) from a study's own data and read the two parameters off the fit.

| Param | Required | Default | Doc |
|---|---|---|---|
| presence_df | yes |  | Data frame with columns present (logical) and distance_km (numeric > 0): one row per species in the chosen recipe's population. |
| bins | no | c(0, 100, 200, 400, 700, 1100) | Numeric vector of distance-bin edges for the zero-positive bound table (and a fit-vs-binned diagnostic otherwise). Default c(0, 100, 200, 400, 700, 1100). |

**Value:** A list: w_scale, d_half Fitted parameters (NA when unidentifiable). fit The glm object (or NULL). identifiable FALSE when zero positives (or a degenerate fit). bin_table Per-bin n, positives, and Jeffreys 95 percent upper bound on P(present); plus a pooled row. n, n_present Sample sizes.

#### Building the input (two general recipes)

- Leave-the-bbox-out (GBIF only, no checklist needed): For each species in the regional pool, present = does it have any in-bbox occurrence record; distance_km = distance from the study site to its nearest record OUTSIDE the bbox. Fully generic across taxa and geography, but note the estimand caveat: presence of RECORDS understates true presence where local effort is thin.

- Checklist calibration (preferred when a site checklist exists): Restrict to the actual application population -- candidate species with NO in-bbox records -- and let present = membership on an independent expert site checklist. This matches the deployment condition exactly (the weight is only ever applied to zero-in-bbox species). The GreatLakes2023 test case used this recipe and found 0 positives in 110 candidates at 12-990 km, making the curve SHAPE unidentifiable -- only bounded -- which is exactly what this function's zero-positive path reports.

#### What is fitted

The same functional form the generator applies, P(present | d) = w_scale * exp(-d / d_half), via a binomial GLM with log link (so w_scale = exp(intercept) and d_half = -1/slope). When the log-link fit fails to converge (small samples, probabilities near 1) a logistic fit is tried and mapped to the exponential form at its small-probability limit. With ZERO positives no curve is identifiable; the function instead returns Jeffreys 95 percent upper bounds on P(present) per distance bin plus pooled -- calibrate w_scale against those bounds (choose a curve sitting inside them), as the GreatLakes2023 case did (pooled bound 0.027 -> adopted w_scale = 0.05 with the default d_half, predicted pooled prevalence 1.4 percent).

### generate_domestic_food_priors(model_obj, lat, lng, grid_id = NA_character_, domestic_animal_taxa = .default_domestic_animal_taxa, food_species_taxa = .default_food_species_taxa, known_cultivar_taxa = .default_known_cultivar_taxa, candidate_plant_taxa = NULL, match_list_taxa = NULL, taxaexpect_priors = NULL, radius_km = 50, ess = 5, max_ess = 50, taxonomy = NULL, api_token = Sys.getenv("INAT_API_TOKEN"), verbose = FALSE)

Generate priors for domestic, commensal, and food-associated species

Constructs Beta(alpha, beta) prior rows for named domestic/commensal animal species, human food/crop species, and (optionally) candidate cultivated/ornamental plants, using a three-channel design. Unlike 'generate_undetected_diversity''s anonymous Tier 3 proxies, every row here carries a real 'taxon_name' and a 'prior_source_type' category for downstream systematic handling (reporting, exclusion from biodiversity summaries, routing to review).

| Param | Required | Default | Doc |
|---|---|---|---|
| model_obj | yes |  | A taxaexpect_kernel_priors object (output of estimate_kernel_priors), used only for its Kish effective sample size (as N_total) so these rows sit on the same theta scale as generate_undetected_diversity()'s output. |
| lat | yes |  | Numeric. Query site coordinates for the iNaturalist search. |
| lng | yes |  | Numeric. Query site coordinates for the iNaturalist search. |
| grid_id | no | NA_character_ | Character. Grid cell identifier to attach to every row (for joining into taxaexpect_priors). Default NA_character_. |
| domestic_animal_taxa | no | .default_domestic_animal_taxa | Character vector of domestic/commensal animal taxon names. Default .default_domestic_animal_taxa (a starting list -- extend for your study system). Set to character(0) to disable this channel. Normalized via TaxaTools::clean_taxon_names() before use -- see @section Name normalization. |
| food_species_taxa | no | .default_food_species_taxa | Character vector of food/crop species taxon names. Default .default_food_species_taxa. Set to character(0) to disable this channel. Normalized the same way as domestic_animal_taxa. |
| known_cultivar_taxa | no | .default_known_cultivar_taxa | Character vector of known cultivated/ornamental (non-food) plant taxon names. Default .default_known_cultivar_taxa. Set to character(0) to disable this channel. Normalized the same way as domestic_animal_taxa. Patched immediately like the two fixed lists above -- see @section Four fixed-list channels. |
| candidate_plant_taxa | no | NULL | Character vector of candidate plant-kingdom taxon names to check for real local cultivated/casual-grade iNaturalist evidence. Default NULL (channel disabled -- no live iNaturalist calls are made unless you supply candidates here, or unless match_list_taxa produces open-discovery candidates). Normalized the same way as domestic_animal_taxa. |
| match_list_taxa | no | NULL | Optional character vector of taxa that actually have a likelihood in this run (e.g. from match_obj/ lik_result). Default NULL (no gating -- every fixed-list channel is checked in full, the original behavior). See @section Match-list gating. |
| taxaexpect_priors | no | NULL | Optional data frame (or just its taxon_name column) of already-modelled priors, used only to shrink the open-discovery residual pool when match_list_taxa is supplied -- a match-list taxon with a real named row here doesn't need an iNaturalist check. Default NULL (residual pool is a safe superset, not incorrect, just less minimal). |
| radius_km | no | 50 | Numeric. iNaturalist search radius, in kilometers. Default 50. |
| ess | no | 5 | Numeric. Baseline effective sample size (in the same N_total units as generate_undetected_diversity()'s singleton_ess) assumed for domestic_animal_taxa/ food_species_taxa even with zero local iNaturalist evidence -- these categories are plausible almost anywhere. Default 5. |
| max_ess | no | 50 | Numeric. Cap on the evidence-boosted effective sample size, so a very large local iNaturalist count cannot dominate N_total. Default 50. |
| taxonomy | no | NULL | Optional data frame with columns taxon_name and any subset of genus, family, order, class, phylum, joined onto the result the same way generate_undetected_diversity(taxonomy = ...) does. Default NULL. When a kingdom column is also present, it additionally enables the iNaturalist kingdom cross-check (see inat_kingdom_mismatch in @return) -- without it, a mismatched-homonym result cannot be detected and is trusted as-is. When a phylum column is present AND match_list_taxa is supplied, it additionally enables the open-discovery residual step (see @section Match-list gating) -- without it, that step is skipped with a message. |
| api_token | no | Sys.getenv("INAT_API_TOKEN") | Character. iNaturalist API token, forwarded to TaxaFetch::fetch_inat_occurrence_counts(). Defaults to the INAT_API_TOKEN environment variable. |
| verbose | no | FALSE | Logical. Print progress. Default FALSE. |

**Value:** A tibble with one row per resolved domestic/food/plant taxon: taxon_name The real taxon name (never NA, unlike 'generate_undetected_diversity()''s anonymous proxies). taxon_name_rank Always '"species"' - every candidate channel here resolves to a real species-level name. Required for 'TaxaAssign::join_priors()''s composite-key join to ever match these rows at all: an unset value here silently defeats every row's elevated prior. grid_id As supplied. alpha, beta Beta(alpha, beta) prior parameters. theta_mean, theta_sd Derived from alpha/beta. model_tier Always '"tier_domestic_food"' - deliberately distinct from '"tier3_undetected"' so downstream code can tell a named domestic/food prior apart from an anonymous dark- diversity proxy. Kernel-path output uses 'prior_branch' + 'effective_records' instead; this column is kept for schema parity with every other prior-generating function in this package. prior_source_type One of '"domestic_animal"', '"food_species"', '"domestic_plant"' - the categorical column this function exists to add. '"domestic_plant"' is shared by 'known_cultivar_taxa', 'candidate_plant_taxa', and the open-discovery channel - see 'cultivar_evidence_source' to tell them apart. cultivar_evidence_source For 'prior_source_type == "domestic_plant"' rows only ('NA' otherwise): '"known_list"' (matched 'known_cultivar_taxa', patched without needing local evidence), '"candidate_supplied"' (from 'candidate_plant_taxa', required and found real local evidence), or '"inat_confirmed"' (from the automatic open-discovery residual step, required and found real local evidence). inat_n_observations_local Raw local iNaturalist observation count backing this row (audit column, mirrors 'generate_undetected_diversity()''s 'source_taxon_name' pattern). 'NA' for a request failure OR when a kingdom mismatch (see 'inat_kingdom_mismatch') discarded the evidence. inat_kingdom iNaturalist's own resolved kingdom for the matched taxon (via 'TaxaFetch::fetch_inat_occurrence_counts()''s 'inat_kingdom'). 'NA' when the taxon wasn't found on iNaturalist. inat_kingdom_mismatch Logical. 'TRUE' when 'taxonomy' supplied a kingdom for this taxon that disagrees with 'inat_kingdom' - iNaturalist resolves names against its own curated taxonomy, not NCBI's or GBIF's, so a name can occasionally match an unrelated homonym in a different kingdom. When this fires, the local-evidence boost is discarded (treated the same as no local evidence) rather than trusted - the candidate still gets patched normally if it's on a fixed list; only the extra confidence from a (likely wrong) local match is dropped. 'FALSE' when no mismatch is detected (including when it can't be checked at all, e.g. no 'taxonomy' kingdom column supplied). plus 'main_habitat' (always 'NA' - see below) and taxonomy rank columns when 'taxonomy' is supplied.

#### Why this exists

GBIF/iNaturalist-derived occurrence data structurally under-index captive/cultivated organisms (pets, livestock, garden/crop plants), so these species get the same tiny generate_undetected_diversity() global-floor prior as a genuinely implausible candidate -- not because they are rare, but because the occurrence database under-counts them. This function is a non-GBIF prior source for exactly that gap, using TaxaFetch::fetch_inat_occurrence_counts() (which can include quality_grade = "casual"/captive = "any" records that standard occurrence indexing excludes) as evidence.

#### Four fixed-list channels, plus one open-discovery channel

- domestic_animal_taxa: A fixed, user-editable vector (pre-populated with common defaults: dog, cat, cow, sheep, pig, chicken, horse, Homo sapiens, etc.). Patched immediately -- membership alone earns a baseline prior, no live check required.

- food_species_taxa: A separate fixed vector for human food/crop species (tomato, onion, etc., plus a short list of cultivated food fungi) -- a distinct contamination category from domestic_animal_taxa (food-handling/lab-bench/sample- processing contamination, not pet/livestock/ranch runoff). Marker relevance varies: irrelevant for vertebrate-specific markers (e.g. 12S MiFish), directly relevant for plant/algae-inclusive markers (e.g. 18S). Patched immediately, same as domestic_animal_taxa.

- known_cultivar_taxa: A third fixed vector: species known to be cultivated somewhere (ornamental/dye/fiber/forage/medicinal) but not primarily as food. Patched immediately, same as the two channels above -- membership on this list is itself the evidence, no live iNaturalist confirmation needed. prior_source_type = "domestic_plant" (shared with the open-discovery channel below; see cultivar_evidence_source in @return for which mechanism actually produced a given row).

- candidate_plant_taxa: User-supplied candidates that genuinely require live confirmation -- unlike the three fixed lists above, membership here is NOT itself sufficient evidence. Each is checked against TaxaFetch::fetch_inat_occurrence_counts( captive = "any", quality_grade = "casual") and only receives a prior row if that check finds real local casual-grade (cultivated/garden) evidence. Default NULL.

- Open discovery (automatic, requires match_list_taxa): A fixed list cannot anticipate every real cultivated escapee. When match_list_taxa is supplied, any match-list taxon not already covered by a fixed list or an existing modelled prior (taxaexpect_priors), and whose taxonomy-supplied phylum is "Streptophyta" or "Tracheophyta" (land plants -- both spellings needed, since TaxaMatch::convert_taxonomy_backbone()'s per-column NCBI fallback means either can appear in one dataset), is added as an open candidate -- deliberately NOT pre-restricted to known_cultivar_taxa or any other list. See @section Match-list gating.

#### Name normalization

Every candidate name (from all three channels, including user-supplied overrides) is passed through TaxaTools::clean_taxon_names() before becoming a row's taxon_name -- the same cleaner match_obj$taxon_name values are normalized through elsewhere in this ecosystem, which truncates to genus + epithet only (e.g. a subspecies trinomial like "Sus scrofa domesticus" becomes "Sus scrofa"; a hybrid-formula name like "Fragaria x ananassa" becomes genus-only "Fragaria", since "x" is treated as an abbreviation token). TaxaAssign::join_priors() joins on an exact taxon_name string match, so an uncleaned candidate name would silently never join to a real query's (cleaned) result. A name that cannot be cleaned to a valid binomial/genus is dropped with a warning() rather than passed through as-is.

#### Match-list gating

match_list_taxa = NULL (the default): every fixed-list channel is checked in full, regardless of whether those taxa have any bearing on your data. This is simple but wasteful: most fixed-list taxa were never detected this run, and each check is a real iNaturalist API call.

Supplying match_list_taxa (the taxa that actually have a likelihood this run -- e.g. unique(match_obj$species) or unique(lik_result$likelihoods$taxon_name[taxon_name_rank == "species"])) restricts every channel (the three fixed lists AND any user-supplied candidate_plant_taxa) to the intersection with match_list_taxa, and the residual -- match-list taxa left over after that restriction and after excluding anything already carrying a named prior in taxaexpect_priors -- becomes the pool for the open-discovery channel. The result is fewer, more meaningful iNaturalist calls and a chance to catch a cultivated species nothing anticipated.

taxaexpect_priors is optional even when match_list_taxa is supplied -- omitting it just means a few more candidates get checked than strictly needed, never a correctness problem.

The open-discovery step is skipped (with a message(), not a warning()) whenever taxonomy lacks a phylum column: there is no safe way to scope an unrestricted live-check pool to plausible taxa without it.

#### What this does NOT fix

Cross-genus reference gaps (e.g. Bison bison anchored reads with Bos taurus never proposed as a candidate for that specific observation) are unaffected -- TaxaLikely::restore_suppressed_candidates() only pulls same-genus congeners. This function only changes the PRIOR for a species already under consideration; it does not expand candidate sets. Strong sequence matches (e.g. Homo sapiens) resolve correctly regardless of prior magnitude; this function's value is the categorical flag plus help for weaker or degraded matches, not sequence resolution itself.

#### Why habitat is always NA here, deliberately

A food/domestic species' plausibility is governed by human food supply and cultivation, not by local habitat suitability -- it has no single correct habitat value to assign, and a grid_id can span more than one real habitat anyway. Do not "fix" a row not joining to real observation data by stamping a real habitat value here -- the correct fix lives in TaxaAssign::join_priors(), which reads a NA main_habitat named-species prior row as applying to ANY habitat at that grid_id (its own dedicated fallback tier, ranked below a real per-habitat match but above the generic dark-diversity floor). Without that tier, or without taxon_name_rank set, join_priors()'s primary composite-key join silently defeats the row under habitat-scoped priors and the observation falls back to the ordinary dark-diversity prior.

### generate_inat_range_evidence(inat_range, weight = 0.8, p_conc = 1, n_obs_threshold = 500L, require_name_match = TRUE)

Evidence rows for species inside their iNaturalist range polygon

The third evidence generator for 'apply_undetected_evidence', alongside 'generate_invasive_watch_evidence' and 'generate_regional_proximity_evidence'. Converts 'TaxaFetch::check_inat_range()' output into presence-probability evidence, replacing 'TaxaAssign::adjust_inat_range_priors()''s post-join binary elevation for the mixture pathway - so iNat evidence shares the same anchors, moment-matched concentration, and multi-source probabilistic-OR combination as every other evidence channel, instead of jumping rows straight to the singleton level outside the framework.

| Param | Required | Default | Doc |
|---|---|---|---|
| inat_range | yes |  | Data frame from TaxaFetch::check_inat_range(). |
| weight | no | 0.8 | Numeric, 0-1. P(locally present) for an in-range, well-observed, name-verified species. Default 0.8. |
| p_conc | no | 1 | Numeric > 0. Presence-claim confidence in pseudo-observations (drives the confirmation update, not the static prior -- see apply_undetected_evidence). Default 1. |
| n_obs_threshold | no | 500L | Integer. Minimum n_observations for the range polygon to count as well-observed. Default 500L, matching TaxaAssign::adjust_inat_range_priors()'s established value. |
| require_name_match | no | TRUE | Logical. Exclude rows whose resolved iNat name differs from the query (or cannot be verified). Default TRUE; set FALSE only with a reviewed name mapping in hand. |

**Value:** Evidence tibble ('taxon_name', 'weight', 'p_conc', 'source = "inat_range"'), ready to 'dplyr::bind_rows()' with other generators' output and feed to 'apply_undetected_evidence'. Zero rows when nothing qualifies.

#### Where iNat sits, and why below the singleton

An in-range polygon with substantial observation coverage is close to observational evidence of regional presence -- much stronger than a lone distant GBIF record -- so its weight sits near the ceiling but at a deliberate "small disadvantage": the default weight = 0.8 reads as P(locally present | in range, well-observed), discounted below 1 because (a) a range polygon is regional, not site-scale, and (b) citizen-science identifications carry a real misidentification rate.

#### Calibration status

Unlike generate_regional_proximity_evidence's w_scale (checklist-calibrated against a real site species list) and generate_invasive_watch_evidence()'s weight (derived from the dataset-independent ordering bound), this function's 0.8 default is design intuition, not empirically calibrated. Under pricing = "blend" (see apply_undetected_evidence), the printed dataset-specific veto bound is often far below 0.8 (~0.05 on a Great Lakes dataset's own real anchors) -- a weight this high can block species-level resolution of a genuinely observed singleton-level native, the exact failure an uncalibrated invasive weight (0.6) caused for yellow perch. apply_undetected_evidence() already warns generically whenever any evidence source's combined weight exceeds that bound in blend mode, so a blend-mode misuse of this default will not pass silently -- but the warning fires after the row is built, not before, and no number here has been chosen to avoid triggering it. Under pricing = "curve" the bound is structurally unreachable (see that function's own docs), so 0.8 carries no such risk there -- this is the only pricing mode any real production caller currently uses this function under. Before wiring this into a blend-mode workflow, either lower weight below that call's own printed bound or calibrate it by the same checklist recipe w_scale used, rather than trusting this default's intuition-only provenance.

#### The fuzzy-match gate is mandatory by default

iNaturalist's taxon search takes the single best TEXT match, so a query can silently resolve to a DIFFERENT species (real production case: Gasterosteus gymnurus resolved to G. aculeatus, returning in_range = TRUE for the wrong organism). At near-singleton weight that error is far more consequential than at the floor, so rows whose name_match is not TRUE are excluded by default (require_name_match = TRUE) and counted in a message. Requires check_inat_range() output that carries the name_match column; cached tables lacking it are treated as unverified and excluded, with a message saying to re-run the check.

### generate_invasive_watch_evidence(invasive_taxa, weight, p_conc = 1, match_list_taxa = NULL)

Evidence rows for a user-supplied invasive/nonindigenous watch list

A thin evidence generator for 'apply_undetected_evidence': given a plain, user-supplied list of taxa (e.g. hand-pulled from the USGS Nonindigenous Aquatic Species database, or any other invasion-biology source relevant to your study), produces one evidence row per listed taxon with a flat, caller-chosen weight and confidence. Deliberately does no live querying, no geography/watershed reasoning, and no Beta-parameter math - see 'apply_undetected_evidence' for why that split exists and where the actual prior construction happens.

| Param | Required | Default | Doc |
|---|---|---|---|
| invasive_taxa | yes |  | Character vector of taxon names. Required, no default. |
| weight | yes |  | Numeric, 0-1. How strongly this list's membership should pull an unobserved taxon's prior toward the singleton-mirror ceiling -- see apply_undetected_evidence's How the elevation works section for the exact blend. Required, no default: there is no universally defensible value (an invasion risk you're highly confident about locally warrants a different weight than a precautionary watch-list entry, and this function has no way to know which is which for your study). |
| p_conc | no | 1 | Numeric, > 0. How much weight the presence claim carries against future evidence (the confirmation update), in pseudo-observations. Default 1 -- a curated listing counts as roughly one direct observation about presence. Does NOT affect the static prior's mean or concentration (both derive from weight via apply_undetected_evidence's presence-mixture moment matching, not from a caller-supplied n_eff). |
| match_list_taxa | no | NULL | Optional character vector of taxa that actually have a likelihood this run (e.g. unique(match_obj$taxon_name)). When supplied, invasive_taxa is restricted to the intersection -- avoids emitting evidence for list members that were never even candidates this run. Default NULL (no restriction). |

**Value:** A tibble with one row per taxon in scope: 'taxon_name', 'weight', 'p_conc', 'source' (always '"invasive_watch"'). Matches the evidence-table schema 'apply_undetected_evidence' expects. Empty tibble (correct schema, zero rows) when nothing is in scope.

#### Why no live query or region-scoping here

Querying the USGS NAS database live and scoping results by watershed (HUC8) would bake a narrow (aquatic-only, United-States-only) external data source and freshwater-specific watershed-connectivity logic into a package meant to stay generic across taxa and geography. Region-scoping instead happens entirely on the caller's side, in how invasive_taxa is built (e.g. filter a NAS pull to species actually relevant to your basin before calling this function) -- this function only knows "is this taxon on the list," nothing else.

#### Tiering via repeated calls, not a built-in tier system

If different taxa on your list warrant different confidence (e.g. a species with multiple confirmed regional populations vs. one with a single distant record), call this function once per tier with a different weight/p_conc and dplyr::bind_rows() the results before passing them to apply_undetected_evidence() -- evidence tables from any number of calls combine naturally, so no tiering logic needs to live inside this function itself.

### generate_presence_curve_evidence(taxon_names, w_scale, distance_km = NULL, d_half = 150, d_cap = 1000, k = 1, p_conc = 1, source = NULL)

Price unobserved candidates on the presence-distance curve

Emits an evidence frame (for 'apply_undetected_evidence()') pricing each taxon's presence probability from the shared distance curve

| Param | Required | Default | Doc |
|---|---|---|---|
| taxon_names | yes |  | Character vector of candidate species names. |
| w_scale | yes |  | Numeric scalar in (0, 1]. The curve's ceiling: presence probability for a species with a record at the site itself. Required, no default -- calibrate against a local checklist (the GreatLakes value is 0.05; see the regional-proximity generator's calibration record). |
| distance_km | no | NULL | Optional numeric vector of distances (km), either named by taxon or positionally aligned with taxon_names. Missing/NA entries -- and the NULL default -- price at d_cap (the clamp). |
| d_half | no | 150 | Numeric scalar, the curve's e-folding half-distance in km (default 150, matching generate_regional_proximity_evidence()). |
| d_cap | no | 1000 | Numeric scalar, the instrument-cap distance in km beyond which the curve is flat (default 1000, the regional generator's own fetch-buffer cap). |
| k | no | 1 | Numeric scalar >= 1, the bandwidth stretch for listed invaders (default 1, no lift). |
| p_conc | no | 1 | Numeric scalar > 0 passed through to the applier (default 1). |
| source | no | NULL | Character scalar stamped on the rows (default "distance_clamp" when no distances are supplied, "presence_curve" otherwise). |

**Value:** A data frame with columns 'taxon_name', 'weight', 'p_conc', 'source', 'distance_km', 'k' - ready for 'apply_undetected_evidence()'.

### generate_regional_proximity_evidence(zero_bbox_taxa, lat, lng, d_half = 150, w_scale = 1, age_half = 15, tile_zoom = 6L, buffer_margin = 1.5, min_buffer_km = 50, max_buffer_km = 1000, near_lat_tolerance_deg = 6, near_occurrence_min_n = 3L, max_coord_uncertainty = 500, year_range = paste0("2000,", format(Sys.Date(), "%Y")), cache_dir = tools::R_user_dir("TaxaFetch", "cache"), tile_cache_dir = NULL, verbose = FALSE)

Evidence rows for species with a real GBIF record just outside the study bbox

A thin, two-stage evidence generator for 'apply_undetected_evidence': for each taxon with no in-bbox occurrence record, cheaply checks whether GBIF has ANY record nearby at all (Stage 1), and only pays for a real, quality-screened fetch to find the actual nearest record and its age for the taxa where that cheap check finds something (Stage 2).

| Param | Required | Default | Doc |
|---|---|---|---|
| zero_bbox_taxa | yes |  | Character vector of taxon names with no in-bbox occurrence record this run -- typically every named candidate absent from taxaexpect_priors entirely. Required, no default. |
| lat | yes |  | Numeric scalars. The study site's own coordinates (Stage 1 and Stage 2 both search around this point). |
| lng | yes |  | Numeric scalars. The study site's own coordinates (Stage 1 and Stage 2 both search around this point). |
| d_half | no | 150 | Numeric > 0. Distance (km) at which weight decays to half its maximum -- see Choosing d_half/age_half. Default 150. |
| w_scale | no | 1 | Numeric in (0, 1]. Near-boundary presence probability: weight = w_scale * exp(-distance_km / d_half), so w_scale is P(locally present) for a species whose nearest record sits just outside the study bbox but that has NO records inside it. The default 1 is almost certainly too high for any real study -- a species with zero in-bbox records is usually genuinely absent even when nearby records exist. Calibrate against a local expert checklist: a Great Lakes test case found 0 of 110 zero-bbox candidates with records at 12-990 km on the site's 53-species checklist (Jeffreys 95 percent upper bounds: 0.107 for the under-100 km bin, 0.027 pooled), and adopted w_scale = 0.05 -- which also satisfies the dataset-independent ordering bound that an unobserved species should never veto a singleton-level observed native at likelihood parity (w below roughly 1/19). |
| age_half | no | 15 | Numeric > 0. Record age (years) at which p_conc decays to half its fresh-record value of 1 -- see Choosing d_half/age_half. Default 15. |
| tile_zoom | no | 6L | Integer. Forwarded to TaxaFlag::check_gbif_tile_range(zoom = ) for Stage 1. Default 6L (roughly continental scale). |
| buffer_margin | no | 1.5 | Numeric > 1. Stage 2's fetch radius is Stage 1's own dist_nearest_occupied_km times this margin (tile-pixel distance is coarse, so the real nearest record may sit a bit further than the tile-resolution estimate) -- clamped to [min_buffer_km, max_buffer_km]. Default 1.5. |
| min_buffer_km | no | 50 | Numeric. Floor/ceiling on Stage 2's fetch radius, regardless of what Stage 1 reported. Defaults 50/ 1000. |
| max_buffer_km | no | 1000 | Numeric. Floor/ceiling on Stage 2's fetch radius, regardless of what Stage 1 reported. Defaults 50/ 1000. |
| near_lat_tolerance_deg | no | 6 | Numeric > 0. A second, complementary test to the nearest-point distance above: at least near_occurrence_min_n of a taxon's Stage-2-filtered records must fall within this many degrees of latitude of lat (proportional fallback when a taxon has fewer total filtered records than that -- see near_occurrence_min_n). Motivated by a real GLANSIS benchmark comparison, which found the plain nearest- point test alone is precision-poor: several species passed it purely on the strength of ONE isolated occurrence record (a stray record, or a real but climatically-artificial thermal-discharge refugium) while the bulk of that species' real range sat many latitude degrees away -- climate-implausible warm-water species were the dominant real pattern. Latitude (not full geodesic distance) is used deliberately as a cheap climate-tolerance proxy -- thermal/seasonal regime tracks latitude far more than longitude for a fixed distance budget. Default 6 (~660km, a value tuned on that benchmark -- a tighter 3-degree pass cost a real, well-documented invader whose established population sat ~5 degrees of latitude from the study site despite being part of one connected system). |
| near_occurrence_min_n | no | 3L | Integer >= 0. A taxon must have at least this many Stage-2-filtered records within near_lat_tolerance_deg of lat, IN ADDITION TO clearing the nearest-point/buffer test above. Default 3L (an absolute count, not a fraction of a taxon's total filtered records -- a fraction would unfairly penalize a taxon with a large occurrence footprint and reward one with only a handful of records). Taxa with FEWER total Stage-2-filtered records than this threshold get a proportional fallback instead of an impossible bar: ALL of their (few) records must fall within near_lat_tolerance_deg, rather than requiring an absolute count they structurally cannot reach -- the real motivating case is a species with exactly 1 occurrence record, genuinely close, that a flat count-of-3 test would otherwise always reject regardless of proximity. Set to 0 or 1 to disable this test and fall back to the original nearest-point-only behavior. |
| max_coord_uncertainty | no | 500 | Numeric. Forwarded to TaxaFetch::filter_gbif_quality(). Default 500 (meters, matching that function's own default). |
| year_range | no | paste0("2000,", format(Sys.Date(), "%Y")) | Character ("YYYY,YYYY") or NULL. Forwarded to TaxaFetch::get_gbif_occurrences()'s Stage 2 fetch. Default: 2000 to the current year, the same window every other GBIF fetcher in this ecosystem defaults to. PASS THE STUDY'S OWN WINDOW (the same year_range the main occurrence fetch used) so regional evidence and resident priors are judged on the same record set. An unbounded window (NULL, all time) is available but not the default: record age is the signal the p_conc discount reads out, but that discount only narrows a row's CONFIDENCE, never its weight -- a 1929 preserved specimen of a captive siamang 74 km from Point Conception still lifted that species' prior 480x above the zero-record floor and turned an 82%-identity family-level call into a species call. |
| cache_dir | no | tools::R_user_dir("TaxaFetch", "cache") | Character or NULL. Forwarded to the Stage 2 fetch for checkpointing. Default tools::R_user_dir("TaxaFetch", "cache"). |
| tile_cache_dir | no | NULL | Character or NULL (default). Forwarded straight through to Stage 1's TaxaFlag::check_gbif_tile_range( cache_dir = ) -- see that function's own Caching section for the exact key/no-expiry/age-reporting design. NULL (the default) disables Stage 1 caching entirely: every zero-record taxon re-pays a live GBIF tile fetch on every call, which is exactly the cost this parameter exists to remove on a repeat run against unchanged data (a real PtConception run spent 43 minutes here across 256 taxa). When supplied, this function also emits one summary line when it finishes: how many Stage 1 verdicts were served from cache, how many were freshly fetched, and the age in days of the oldest cache hit actually used -- so staleness (there is no TTL; see check_gbif_tile_range()) is visible to the caller rather than silent. |
| verbose | no | FALSE | Logical. Print per-taxon Stage 1/Stage 2 progress. Default FALSE. |

**Value:** A tibble with one row per taxon that cleared both stages: 'taxon_name', 'weight', 'p_conc', 'source' (always '"regional_proximity"') - matches the evidence-table schema 'apply_undetected_evidence' expects - plus audit columns 'distance_km', 'record_year', 'age_years' ('NA' when the matched record had no usable year), 'tile_zoom_used'. Empty tibble (correct schema, zero rows) when nothing in 'zero_bbox_taxa' clears Stage 1, Stage 2's quality filter, or GBIF key resolution.

#### Stage 1 -- cheap gate, no quality filtering possible

check_gbif_tile_range reads presence/ absence off GBIF's pre-rendered density tiles for a handful of tile downloads, regardless of how many records exist worldwide. This is deliberately the ONLY thing a bare density tile can answer -- a pixel carries no per-record fields, so no eDNA-keyword/coordinate-quality/ institution-proximity screening is possible at this stage (the same "raw/unfiltered" caveat already documented on that function itself). Most taxa are expected to come back beyond_buffer = TRUE even after escalation; that IS the answer for them -- no further cost, no evidence row, the species stays at the ordinary dark-diversity floor.

#### Stage 2 -- real, filtered fetch, only for taxa Stage 1 found something for

A real TaxaFetch::get_gbif_occurrences() call, scoped to a buffer around the study site sized from Stage 1's own reported distance (not a global fetch), run through TaxaFetch::filter_gbif_quality() -- the same eDNA-exclusion/coordinate-quality/CoordinateCleaner checks every other GBIF pull in this ecosystem gets, closing the exact gap Stage 1 structurally cannot. A bad single record can trigger a wasted Stage 2 fetch, but can never move a prior on its own, since only the filtered survivors ever produce an evidence row. compute_local_occurrence_distance (via its date_col argument) then gives the real distance AND the matched record's age from the filtered data.

#### From distance/age to weight/p_conc -- deliberately NOT a connectivity check

This deliberately does not implement a watershed/basin-connectivity gate (is the nearby record even in a hydrologically connected water body): this package needs to stay simple and generalize across a wide range of taxa and geographic settings, and hydrological connectivity is a specific-study solve, not a generalizable primitive. Raw distance is the only generic signal used. The geographic-plausibility judgment (is a record 100km away actually reachable, given basin/ dispersal-barrier structure) is left to a human or LLM reviewer with real domain knowledge, not computed here -- see TaxaFlag::review_assignments()'s existing GBIF-tile-context annotation pattern for the established way to surface facts like this for that judgment, rather than encoding a rule.

Weight (how far toward the singleton ceiling this pulls the prior's MEAN) is a saturating decay in distance: weight = w_scale * exp(-distance_km / d_half) -- read as P(locally present | nearest record at this distance, no in-bbox records) in the presence-mixture framing. Presence-claim confidence (p_conc, how much weight the claim carries against future evidence -- NOT the static prior's concentration, which is moment-matched by apply_undetected_evidence) is a saturating decay in record age: p_conc = exp(-age_years / age_half) -- a fresh record counts as one pseudo-observation about presence, an old record as less than one. These are deliberately two independent knobs, not one composite score -- an old record doesn't mean the species is systematically LESS likely to be present (it could reflect a real, still-extant population never resurveyed, or a range that has since contracted; occurrence data alone can't tell these apart), so age widens uncertainty around the same distance-driven mean rather than discounting the mean itself. A record with no usable year value gets p_conc = 1 (no extra discount, not a value in between) -- absence of age information is not evidence of great age.

d_half/age_half ship with a default but are fully overridable -- there is no universally defensible distance or age scale across taxa (a sedentary benthic invertebrate and a highly vagile bird do not share a dispersal-distance order of magnitude), so the defaults are a starting point to adjust for your own study system, not a claim of correctness. See Choosing d_half/age_half below for how each one shapes the output.

#### Choosing d_half/age_half

weight = w_scale * exp(-distance_km / d_half) -- d_half is the distance at which the pull toward the singleton-mirror ceiling has decayed to half its near-boundary value w_scale. At d_half = 150: a record 100km away gives weight ~= 0.51 * w_scale; a record 3000km away gives weight ~= 4e-9 (indistinguishable from no evidence at all). Halving d_half halves how far a given weight reaches; doubling it reaches twice as far for the same weight. age_half works the same way on age_years instead of distance_km, controlling p_conc instead of the mean -- at the default age_half = 15, a 15-year-old record's presence claim is held with half the effective confidence of a fresh one.

### generate_uncertain_habitat_evidence(occurrence_data, site_lat, site_lon, site_habitat, habitat_levels, taxa = NULL, d_half = 150, w_scale = 1, year_col = NULL, age_half = 15, taxon_col = "taxon_name", lat_col = "decimalLatitude", lon_col = "decimalLongitude", habitat_col = "main_habitat", verbose = TRUE)

Presence Evidence From Records Whose Habitat Could Not Be Resolved

Prices the taxa that the kernel estimator cannot see: those with records near the site, all of them at points whose habitat is unassigned, and none in the site's habitat stratum. Returns a standard evidence table for 'apply_undetected_evidence', so these taxa appear in the priors as present in the region instead of vanishing.

| Param | Required | Default | Doc |
|---|---|---|---|
| occurrence_data | yes |  | Data frame of cleaned, habitat-labelled occurrence records (one row per record) -- the same table given to estimate_kernel_priors. |
| site_lat | yes |  | Numeric scalars. Sampling site coordinates. |
| site_lon | yes |  | Numeric scalars. Sampling site coordinates. |
| site_habitat | yes |  | Character scalar. The focal habitat. A taxon with ANY record in this stratum is excluded: it already has a resident prior, and adding evidence would double-count it. Must be one of habitat_levels. |
| habitat_levels | yes |  | Character vector of the scheme's real habitat names -- in the standard workflows, simple_scheme$l1_name. Everything in habitat_col that is not one of these is treated as unassigned. No default, deliberately: a default would be a copy of some producer's sentinel vocabulary living at this function's declaration site, which is the coupling the closed-world test exists to avoid. See Details. |
| taxa | no | NULL | Optional character vector restricting the result to taxa of interest (e.g. the marker's match list). NULL (default) considers every taxon in occurrence_data. |
| d_half | no | 150 | Numeric > 0. Distance (km) at which the weight is half w_scale. Default 150, matching generate_regional_proximity_evidence. Pass the run's own value so the two sources are priced on one scale. |
| w_scale | no | 1 | Numeric in (0, 1]. Weight at zero distance. Default 1. Pass the run's own value. |
| year_col | no | NULL | Optional column of record years. When supplied, p_conc = exp(-age_years / age_half) from the nearest record's year, matching the regional-proximity generator. NULL (default) leaves p_conc = 1. |
| age_half | no | 15 | Numeric > 0. Age (years) at which p_conc halves. Default 15. Ignored when year_col is NULL. |
| taxon_col | no | "taxon_name" | Column names in occurrence_data. Defaults "taxon_name", "decimalLatitude", "decimalLongitude", "main_habitat". |
| lat_col | no | "decimalLatitude" | Column names in occurrence_data. Defaults "taxon_name", "decimalLatitude", "decimalLongitude", "main_habitat". |
| lon_col | no | "decimalLongitude" | Column names in occurrence_data. Defaults "taxon_name", "decimalLatitude", "decimalLongitude", "main_habitat". |
| habitat_col | no | "main_habitat" | Column names in occurrence_data. Defaults "taxon_name", "decimalLatitude", "decimalLongitude", "main_habitat". |
| verbose | no | TRUE | Logical. Report counts. Default TRUE. |

**Value:** A data frame, one row per qualifying taxon, with the evidence schema 'apply_undetected_evidence' expects - 'taxon_name', 'weight', 'p_conc', 'source' (always '"uncertain_habitat_proximity"') - plus audit columns 'distance_km' (to the nearest unassigned-habitat record), 'n_records_unassigned' (how many such records the taxon has) and 'record_year'/'age_years' ('NA' without 'year_col'). Zero rows with the correct schema when nothing qualifies, which is the expected result on a well-scoped dataset.

#### Details

The gap this closes. estimate_kernel_priors keeps only records whose point carries site_habitat (keep <- !is.na(hab) & hab == site_habitat). A point the habitat consensus could not place fails that test whatever it is labelled -- as NA because it fails !is.na(), as any other non-matching string because it fails the equality -- so a taxon whose nearby records all sit at such points yields no resident row.

Why habitat_levels rather than a list of sentinels. This function has to tell an UNPLACEABLE point (recoverable) from one placed in a DIFFERENT habitat (correctly excluded, not this function's business). Testing against the producer's sentinels (NA, "", "Uncertain") would make this package responsible for a vocabulary it does not own: a sentinel added in the producer would silently keep returning FALSE here. The producer may not even be TaxaHabitat -- a habitat column can come from a polygon layer, which is why TaxaExpect only Suggests that package.

So the test is CLOSED-WORLD: unassigned is anything that is not one of the scheme's own declared habitats, which the caller already has in hand (simple_scheme$l1_name in the standard workflows). NA and "" fall out for free, and so does any later sentinel or typo. A label that is neither a declared habitat nor a recognisable no-verdict marker would be RECOVERED as evidence -- the unsafe direction -- so the function names those labels in a warning rather than acting on them quietly.

Downstream, the standard workflow builds its evidence candidate list as setdiff(match_list, taxaexpect_priors$taxon_name): every taxon with no prior row. Such a taxon therefore reaches generate_regional_proximity_evidence labelled zero-bbox -- priced as having no records in the search polygon at all, and re-queried from GBIF to find its nearest one. That claim is false: the records exist, they are in the bbox, and their distance is already known exactly from the occurrence table.

Not the same thing as a habitat-agnostic prior. A main_habitat of NA in a PRIORS table means "matches any habitat" -- generate_domestic_food_priors sets it deliberately, and TaxaAssign::join_priors() reads it to build the domestic/food wildcard tier. An occurrence whose habitat could not be determined is the opposite claim: a real organism at a real place, whose place could not be classified. Rows from this function are ordinary evidence rows carrying source = "uncertain_habitat_proximity"; they never enter that wildcard tier.

Pricing. The same saturating decay generate_regional_proximity_evidence uses, on the distance to the taxon's nearest unassigned-habitat record: w = w_{scale} \times \exp(-d_{nearest} / d_{half}) measured directly from the occurrence table, with no network call. Records at points assigned to a DIFFERENT habitat are ignored: those were excluded because their habitat is known and wrong, which is a correct exclusion and not this function's business.

What is still unknown, and who resolves it. This weight answers "is the taxon present near the site", not "does it occupy the site habitat" -- the point's habitat is precisely what could not be determined. Pass the result through condition_evidence_on_habitat exactly as for the other generators: with the point uninformative, the taxon's own habitat weight is the right fallback, and it is applied on the same footing as every other evidence row rather than as a special case.

The count is a floor, deliberately. A taxon is skipped when it has ANY record in the focal stratum, because such a taxon normally has a resident row and adding evidence would double-count it. Whether it actually has a row can depend on filters estimate_kernel_priors applies downstream of the stratum -- a year window, for instance. A taxon whose only in-stratum records fall outside such a filter is skipped here, keeps no resident row, and stays on the zero-bbox path. This errs toward under-recovery, the safe direction: this function can only ever fail to rescue a taxon, never inflate one. Read the returned row count as a lower bound on the affected population.

Scale. Expect a small residual. A large number of unassigned points usually means records outside the study scope (e.g. out-of-scope taxa) that should have been removed by a scope filter before fetching; treat a large one as a scope-filter problem first.

Not alongside the kernel's own unplaceable-record rule. estimate_kernel_priors() can count the same records itself, at their taxon's habitat weight, when given habitat_levels and habitat_weights. A taxon then has a resident row AND would be priced here as evidence from the same points: counted twice. Use one of the two. With the kernel rule in place this function finds no qualifying taxa only for taxa whose weight is positive; a taxon with no habitat weight still has no resident row and would be recovered here, which is the one case where the two are complementary.

### generate_undetected_diversity(model_obj, jeffreys_threshold = 2L, singleton_ess = 2L, taxonomy = NULL)

Generate Priors for Undetected Species

Constructs Beta(alpha, beta) prior objects for species that are plausibly present in the regional pool but were not recorded anywhere in the dataset (Tier 3 species). Two sources of priors are generated:

| Param | Required | Default | Doc |
|---|---|---|---|
| model_obj | yes |  | A taxaexpect_kernel_priors object (output of estimate_kernel_priors). N is its Kish effective sample size; singletons are its neighborhood singletons, stamped with the site id. |
| jeffreys_threshold | no | 2L | Integer. If N_total is below this value, use a Jeffreys prior Beta(0.5, 0.5) for the global floor instead of Beta(1, N_total - 1). Default 2. |
| singleton_ess | no | 2L | Integer. Effective sample size used for moment-matching singleton mirror priors. Controls how tightly the prior is concentrated around the observed singleton theta: alpha = theta_obs * singleton_ess, beta = (1 - theta_obs) * singleton_ess. A small value (default 2) produces a diffuse prior appropriate for a species seen exactly once. |
| taxonomy | no | NULL | Optional data frame with columns taxon_name and any subset of genus, family, order, class, phylum. When supplied, singleton mirror rows are annotated with the full taxonomic hierarchy of their source_taxon_name via a left join on taxon_name. Typically built from occurrences_std (which carries the full GBIF hierarchy). Used by TaxaAssign::join_priors() for hierarchical dark diversity grouping (Issue 3). Global floor rows always receive NA for all taxonomy columns. Default NULL (taxonomy columns added as NA). |

**Value:** A tibble with one row per undetected species proxy, containing: taxon_name Always NA - proxies have no taxonomic identity. grid_id Grid cell identifier inherited from singleton source, or NA for the global floor. habitat Habitat inherited from singleton source, or NA for global floor. alpha Alpha parameter of Beta(alpha, beta) prior. beta Beta parameter of Beta(alpha, beta) prior. theta_mean Derived: alpha / (alpha + beta). theta_sd Derived: SD of Beta(alpha, beta). n_obs Total community count N at the source cell, or N_total for the global floor. model_tier Always "tier3_undetected". Kernel-path output uses 'prior_branch' + 'effective_records' instead; this column is kept for schema parity with every other prior-generating function in this package. undetected_type Character: "singleton_mirror" or "global_floor". source_taxon_name Taxon name of the singleton source, or NA for the global floor. For auditing only - not passed to TaxaAssign.

#### Details

- Singleton mirrors: For each single-detection species (a species observed exactly once across all samples in the dataset), one anonymous undetected species proxy is created, inheriting the singleton's habitat, location, and theta. The rationale is that locations and habitats with many single-detection species indicate high undetected diversity. (Note: "singleton" here refers to detection frequency, not to "singleton sequences" in TaxaLikely, which are reference sequences with no within-species neighbours.)

- Global floor prior: A single effort-based prior always included regardless of whether singletons are present: theta = 1 / N_total, parameterized as Beta(1, N_total - 1). This ensures TaxaAssign always has at least one undetected competitor.

Alpha/beta conversion from observed theta: For singleton mirrors, the observed theta (n=1 / N) is converted to Beta parameters using a moment-matching approach with a fixed effective sample size (ESS). The ESS controls how tightly the prior is concentrated around the observed theta:


```

alpha = theta_obs * ESS beta = (1 - theta_obs) * ESS ```

A small ESS (default 2) produces a weak, diffuse prior appropriate for a species seen exactly once. This is intentionally conservative -- we have very little information about a singleton's true theta.

Global floor: Beta(1, N_total - 1) places the prior mean at 1/N_total, equivalent to the theta expected if an undetected species appeared exactly once across all sampling effort. This is always smaller than any singleton-derived theta in a well-sampled dataset.

No singletons: If the dataset contains no singletons (as is common when rare species have already been filtered upstream), only the global floor prior is returned. This is the minimum viable undetected pool.

Taxonomic-group dilution (mitigated via the grouped pathway, opt-in): N_total is computed across all taxa in model_obj regardless of taxonomic group. When a marker captures groups of very different sizes (e.g. ~800 fish + ~20 mammals on a 12S marker), the global floor Beta(1, N_total - 1) is diluted by the dominant group. For a mammal query the floor prior would be Beta(1, 819) rather than the group-appropriate Beta(1, 19), making unmodelled mammals appear ~41x less likely than they should be relative to the mammal species pool. Confirmed on real PtConception 18S data: pooling macroinvertebrates + other_vascular_plants + zooplankton into one N_total gives zooplankton a floor ~34x too low relative to its own group's true effort.

Fix: estimate_kernel_priors(sampling_group_col = ...) solves this same problem natively -- its Good-Turing budget (f1/f2/ chao_missing/theta_present) is computed within each sampling group rather than pooled, so a minority group's floor is never diluted by a dominant one. If you do not group your data this way, the dilution described above still applies uncorrected -- in practice its impact is also blunted by three things even when unmitigated: (1) modelled species priors come from the Tier 1/2 model and are unaffected; (2) the dark_mean used for modelled-species floor promotion is dominated by singleton mirrors, which are themselves group-weighted; and (3) minority-group queries are typically rare on group-biased markers.

#### Domestic/synanthropic species

Both priors above are ultimately derived from model_obj's training occurrence data (typically fetched from GBIF/iNaturalist). Those sources structurally under-index captive/domestic organisms (pets, livestock), so a domestic species with no detections in your dataset will receive the same tiny global-floor prior as a genuinely implausible candidate -- not because it is actually rare, but because the occurrence database it's being compared against under-counts it. This is not something generate_undetected_diversity() (or any prior-generation step downstream) can correct on its own, since it has no way to distinguish "genuinely undetected" from "detected in reality but not in this data source." If your study system includes domestic/synanthropic species that are plausible detections (e.g. camera-trap surveys near human habitation), augment your occurrence data with their known local presence before calling estimate_kernel_priors(), rather than relying on the automatic floor to represent them. TaxaFlag:: add_posthoc_assessment(domestic_taxa = ...) can flag the resulting low-prior-vs-strong-likelihood contrast for review if augmentation isn't practical for your workflow.

### generate_user_specified_evidence(taxon_weights, p_conc = 1)

User-specified presence evidence for species of special concern

The explicit policy knob for unobserved taxa: a user may assert a presence probability 'w' for particular species (raising a watch species' chance of _resolving_ in consensus - detection itself is already guaranteed prior-free by 'TaxaFlag::flag_watch_candidates()'). Rows carry 'source = "user_specified"' so the provenance survives into 'evidence_sources' and any downstream caveat can see it.

| Param | Required | Default | Doc |
|---|---|---|---|
| taxon_weights | yes |  | Named numeric vector: names are species, values are presence probabilities in (0, 1]. |
| p_conc | no | 1 | Numeric scalar > 0 (default 1). |

**Value:** A data frame with columns 'taxon_name', 'weight', 'p_conc', 'source' - ready for 'apply_undetected_evidence()'.

### kernel_budget_sensitivity(fit, occurrence_data, support_weight_grid = exp(-(1:5)), lambda_grid = NULL, verbose = FALSE)

Sensitivity of a kernel Good-Turing budget to its counting radius

Re-computes the $budget of a fitted 'estimate_kernel_priors()' object across a grid of counting radii ('support_weight') and, optionally, geographic bandwidths ('lambda_km'), and summarizes how far each group's budget quantities move. Report this next to any 'chao_missing' or 'theta_present' figure you intend to act on.

| Param | Required | Default | Doc |
|---|---|---|---|
| fit | yes |  | A "taxaexpect_kernel_priors" object from estimate_kernel_priors(). |
| occurrence_data | yes |  | The same occurrence data fit was computed from. The fit does not retain the records, so they must be supplied again; passing different data silently answers a different question, and a mismatch at the fit's own settings is reported by $reproduces_fit. |
| support_weight_grid | no | exp(-(1:5)) | Numeric vector in (0, 1] of counting radii to sweep. Default exp(-(1:5)), i.e. 1 to 5 bandwidths, which brackets the exp(-3) default on both sides. |
| lambda_grid | no | NULL | Optional numeric vector of geographic bandwidths (km). NULL (default) sweeps only the counting radius, holding lambda_km at the fit's own value -- the cleaner diagnostic, since it moves one boundary and nothing else. Supply a grid to see the joint sensitivity. |
| verbose | no | FALSE | Logical. Message each setting as it is computed. |

**Value:** An object of class '"taxaexpect_kernel_budget_sensitivity"': a list with budget Long data frame, one row per (setting, sampling group): the $budget columns plus 'lambda_km', 'support_weight', 'radius_lambdas' ('-log(support_weight)') and 'radius_km'. summary One row per sampling group: the range of 'f1', 'f2', 'chao_missing' and 'theta_present' over the sweep, 'theta_present_spread' (max/min over settings where it is defined), 'theta_present_at_fit', and 'n_unpriced' (settings where the group had no defined price). at_fit The budget at the fit's own settings. reproduces_fit Logical: whether the fit's own settings reproduced the fit's $budget exactly. 'FALSE' means 'occurrence_data' is not the data 'fit' was computed from. params The sweep's own provenance.

#### Details

support_weight is the kernel weight at which a record starts counting toward the discrete support statistics f1 (singletons) and f2 (doubletons). It is a pure counting boundary: moving it changes neither theta nor n_eff nor missing_mass's definition, only which records are inside the neighborhood being counted. Sweeping it therefore isolates the budget's dependence on that boundary from every other modelling choice.

chao_missing is f1^2 / (2 f2), so it is quadratic in f1 and inverse in f2. With f2 in single digits -- the usual case for anything but the largest group -- one doubleton entering or leaving the neighborhood moves the estimate by tens of percent. The f2_min column of $summary is the number to look at first for that figure. theta_present is priced from missing_mass / f1, so it does not inherit f2's instability -- but it still moves with the counting radius through f1 and missing_mass themselves, which is what theta_present_spread reports.

The sweep calls estimate_kernel_priors() itself rather than recomputing the statistics from the fit, so the numbers reported here cannot drift from what the estimator would say. That costs one O(records) pass per setting (~2 s per pass at 2 million records).

### plot_theta_surface(kernel_fit, occurrence_data, taxon, n_grid = 256L, bbox = NULL, m = NULL, covariate_at = NULL, n_eff_floor = NULL, mask = NULL, theta_range = "shared", palette = "YlOrRd", bg = "grey92", support_panel = TRUE, support_field = c("n_eff", "W"), site_marker_radius = 5, hover_labels = TRUE, interactive = FALSE, taxon_col = "taxon_name", lat_col = "decimalLatitude", lon_col = "decimalLongitude", habitat_col = "main_habitat", ...)

Evaluate the kernel-prior estimator on a spatial lattice (KDE prior field)

Computes the SAME distance-kernel estimator 'estimate_kernel_priors()' applies at one site, at every point of a regular lattice instead, via binned FFT convolution. The result is a genuine prior FIELD: evaluating the surface at the site's own coordinates reproduces 'estimate_kernel_priors()''s 'theta_mean' for the requested taxon exactly (to numerical/grid-discretization tolerance), because it is the identical formula, not a smoothed rendering of it.

| Param | Required | Default | Doc |
|---|---|---|---|
| kernel_fit | yes |  | A taxaexpect_kernel_priors object from A fit built with habitat_levels/habitat_weights (see estimate_kernel_priors()) carries them in $params, and the surface counts unplaceable-habitat records the same way, so the site-identity invariant holds for such a fit too. estimate_kernel_priors() -- the source of lambda_km, m, lambda_latitude, covariate_col, lambda_covariate, site_habitat, and the site coordinates (site_lat/site_lon, marked on the map). Every tuning parameter defaults from this object so the surface cannot silently drift from the priors it claims to depict. |
| occurrence_data | yes |  | The SAME occurrence data frame passed to estimate_kernel_priors() to produce kernel_fit (cleaned, habitat-labelled occurrence records). |
| taxon | yes |  | Character vector of one or more species names to surface. Length 1 returns a single surface; length > 1 returns one surface per taxon (a facet grid for the static plot, a layer-toggle overlay for the interactive map). |
| n_grid | no | 256L | Integer, lattice resolution per side (default 256L). |
| bbox | no | NULL | Optional named numeric vector/list with lat_min, lat_max, lon_min, lon_max. Default NULL: computed from the full extent of the habitat-stratified records (unioned with the site coordinates) plus padding, which GUARANTEES every record that estimate_kernel_priors() would use is included in the lattice binning -- this is what makes the site-identity invariant hold. Supplying a smaller custom bbox excludes records outside it from the surface (a documented, deliberate window truncation), which can disagree with the exact site value if the site itself sits near or outside that window. |
| m | no | NULL | Optional back-off mass override. Default NULL: use kernel_fit$params$m (the value the priors were actually fit with). |
| covariate_at | no | NULL | Optional numeric scalar: the covariate value (e.g. depth) to hold fixed across the whole lattice. Default NULL: the covariate factor is omitted entirely and a message documents this (see @section Covariate and latitude factors). Only meaningful when kernel_fit was built with a covariate_col; supplying it against a fit that has none is an error (nothing to condition on). |
| n_eff_floor | no | NULL | Optional numeric. Lattice points with n_eff(x) below this value are masked outright (drawn as background). Default NULL: no outright mask. |
| mask | no | NULL | Optional geometry restricting the surface to a region of interest (a lake outline, a bay, a survey boundary). Cells whose centres fall outside become NA -- transparent on the map, and excluded from any summary of the returned matrices. Accepts a WKT POLYGON/ MULTIPOLYGON string -- including, directly, the same search polygon a workflow already passes to its GBIF fetch, which is usually what you want, since it clips the map to the geometry the records were fetched under -- or an sf/sfc polygon (requires the sf package), or a plain two-column lon/lat matrix/data frame, or a list of such matrices (a cell is kept if it falls inside ANY of them, for islands or multi-basin masks). Deliberately a parameter with no default: the correct mask is application-specific, so the package supplies none. Whenever mask is supplied, its boundary is also DRAWN (not just used to clip), on both the static and interactive renders -- there is no case where you would want the clip without seeing its edge, so this is automatic, not a separate toggle. |
| theta_range | no | "shared" | Controls the colour scale across the requested taxon panels/layers. Default "shared": one range computed across every requested taxon, so a contrast pair (placed side by side specifically to be compared) is actually comparable -- the same colour means the same theta in every panel. For a single taxon this is identical to scaling to its own range (there is nothing else to share against), so the default changes nothing about a single-taxon call. NULL reverts to the original per-panel behaviour (each taxon scaled to its OWN range(theta), so the same colour can mean a different theta in different panels); a numeric c(lo, hi) fixes an absolute scale instead, for cross-run/cross-report comparability. Never changes a value in $surface -- only how it is coloured. |
| palette | no | "YlOrRd" | Either a name from grDevices::hcl.pals() (matched case-insensitively; e.g. "YlOrRd", "Viridis", "Plasma") or a vector of 2+ colours to ramp via grDevices::colorRampPalette(). Resolved to ONE 256-colour vector used for both the static ramp and the interactive leaflet::colorNumeric() palette, so the two renders of the same surface can no longer disagree about what a colour means. A recognised hcl.pals() NAME is reversed so low theta is pale/light and high theta is dark/saturated (grDevices::hcl.colors()'s own default direction for these sequential palettes is the opposite -- dark at the low end -- and the reversal matches both this package's historical static ramp and leaflet::colorNumeric()'s own convention for a named sequential palette); a colour VECTOR is used exactly as given, low to high, with no reversal, since the caller has already stated the order they want. Default "YlOrRd" -- zero new package dependencies (grDevices is already Imports). This is a default recommendation, not a restriction: palette = "Viridis" or any other hcl.pals() name works identically. |
| bg | no | "grey92" | Background colour for the STATIC render only (default "grey92", a neutral mid-grey -- never the palette's own low end, and never pure white/black). Drawn behind every panel before the raster, so a masked cell or a species absent from a habitat stratum reads as "outside the surface" rather than blending into a pale low-theta colour or a plain white page. Has no interactive-render analogue: leaflet already renders a masked/absent cell as transparent over its own basemap tiles. |
| support_panel | no | TRUE | Logical (default TRUE). Adds ONE extra panel/layer showing the support field named by support_field on its own colour scale. Support (n_eff or W) is per-LOCATION, not per-taxon -- a single dedicated panel says what it has to say once, instead of length(taxon) times. Every taxon panel always renders at full opacity (see @section Why no opacity fade); support_panel = FALSE simply omits the support panel/layer rather than routing that information back into opacity. |
| support_field | no | c("n_eff", "W") | Character, "n_eff" (default) or "W". Which field the support_panel shows. n_eff (Kish effective sample size) is what estimate_kernel_priors() actually puts in the Beta concentration, but it is SCALE-INVARIANT (multiplying every record's weight by a constant does not move it) -- a single record 2 km away and 200 records 400 km away can read the identical n_eff, so a high value does not mean "lots of evidence here," only "many records contributed comparably." W (the raw total kernel weight, shown log-scaled) is the more literal answer to "is there actually data near this point." n_eff_floor always thresholds the real n_eff regardless of this argument -- it is a distinct, already-documented outright mask. |
| site_marker_radius | no | 5 | Numeric (default 5). Radius in pixels of the hollow circle marking the site on the interactive map. The marker is drawn unfilled and on top so it cannot hide the cell it marks (the default pin marker did, which is why this is small and hollow). |
| hover_labels | no | TRUE | Logical (default TRUE). Show theta and the local effective sample size on hover over each rendered cell of the interactive map. |
| interactive | no | FALSE | Logical (default FALSE). FALSE returns a static base-graphics plot. TRUE returns a Leaflet overlay (guarded by requireNamespace("leaflet")); leaflet is already in TaxaExpect's Suggests, so this adds no new dependency. |
| taxon_col | no | "taxon_name" | Column names in occurrence_data (defaults matching estimate_kernel_priors(): "taxon_name", "decimalLatitude", "decimalLongitude", "main_habitat"). kernel_fit does not carry these names, so they are supplied here with the same defaults the estimator uses. |
| lat_col | no | "decimalLatitude" | Column names in occurrence_data (defaults matching estimate_kernel_priors(): "taxon_name", "decimalLatitude", "decimalLongitude", "main_habitat"). kernel_fit does not carry these names, so they are supplied here with the same defaults the estimator uses. |
| lon_col | no | "decimalLongitude" | Column names in occurrence_data (defaults matching estimate_kernel_priors(): "taxon_name", "decimalLatitude", "decimalLongitude", "main_habitat"). kernel_fit does not carry these names, so they are supplied here with the same defaults the estimator uses. |
| habitat_col | no | "main_habitat" | Column names in occurrence_data (defaults matching estimate_kernel_priors(): "taxon_name", "decimalLatitude", "decimalLongitude", "main_habitat"). kernel_fit does not carry these names, so they are supplied here with the same defaults the estimator uses. |
| ... | yes |  | Passed to the static plot's underlying graphics::image() call (e.g. main) or, when interactive = TRUE, to leaflet::addRectangles(). |

**Value:** An object of class '"taxaexpect_theta_surface"': a list with surface A list with 'lat_grid', 'lon_grid' (lattice coordinates), 'theta' (an 'n_grid' x 'n_grid' matrix for one taxon, or a named list of such matrices for several), 'n_eff', 'W' (Kish effective sample size and total kernel weight at every lattice point), 'regional_composition' (the 'p_i' used per requested taxon), and 'params' (the resolved tuning values, for provenance). plot The plot object: a base graphics call (invisible 'NULL', since base graphics draws immediately) when 'interactive = FALSE', or a 'leaflet' htmlwidget when 'interactive = TRUE'. Returned invisibly is never done here - callers can inspect or re-render $surface without recomputing.

#### The estimator, on a lattice

For evaluation point x and the habitat-stratified record set (the same stratification estimate_kernel_priors() applies): w_r(x) = \exp(-d(x,r)/\lambda) (times the optional per-record covariate factor and the optional absolute-latitude climate factor -- see below), then W(x) = \sum_r w_r(x), \quad S_2(x) = \sum_r w_r(x)^2, \quad n_{eff}(x) = W(x)^2 / S_2(x) (Kish effective sample size), and for species i c_i(x) = \sum_{r \in i} w_r(x), \quad \theta_i(x) = (c_i(x) n_{eff}(x)/W(x) + m p_i) / (n_{eff}(x) + m) with p_i the same unweighted habitat-stratified regional composition estimate_kernel_priors() uses. All three lattice surfaces (a species indicator mass, the all-records mass, and the all-records squared-weight mass) are computed by binning records onto the output lattice and convolving with the kernel evaluated on the same lattice via stats::fft() (zero-padded to avoid circular wraparound) -- this is O(n_grid^2 log n_grid) regardless of species count, not O(records) per pixel.

#### Covariate and latitude factors

The geographic kernel (and the optional absolute-latitude climate factor) are functions of position, so both belong inside the lattice kernel. The COVARIATE factor (e.g. depth) is a per-record attribute, not a function of map position -- a 2-D surface cannot represent it unless the covariate is held fixed. When covariate_at is supplied (and kernel_fit was built with a covariate_col), records are reweighted by exp(-|c_r - covariate_at| / lambda_covariate) before binning -- constant across the lattice, so it only reweights which records count, exactly mirroring estimate_kernel_priors()'s own per-record factor. When covariate_at is NULL (default), the factor is OMITTED and a message says so -- the returned object and plot never imply the map shows a depth-conditioned field when it does not.

Whichever of the three states applies -- the fit has no covariate, it has one that this map OMITS, or it has one held at a stated value -- is written onto the rendered map itself (a subtitle on the static plot, a caption on the interactive one) alongside the habitat stratum, and printed by print(), so the conditions travel with a screenshot. A fit that has a covariate but is drawn without it says so affirmatively, because silence would read as "this model has no covariate", a different and false claim. To see a different habitat or covariate value, re-fit: both are choices made in estimate_kernel_priors(), not view settings on an existing fit.

The optional latitude factor exp(-111 * ||lat_r| - |lat_x|| / lambda_latitude) is folded into the SAME lattice kernel using signed lat_x - lat_r (translation-invariant, so it convolves in one FFT pass together with the geographic factor). This is mathematically EXACT whenever the site, the lattice, and every contributing record share the same hemisphere sign (any site not within a bandwidth of the equator); see @section Limitations for the general case.

#### Why no opacity fade

Every taxon panel always renders at full opacity; support is shown in its own support_panel instead of as a fade toward transparent. n_eff is SCALE-INVARIANT (see support_field), so a confidently opaque cell can be pure far-field extrapolation. Support is also per-LOCATION, not per-taxon, so a fade would be multiplied into every facet panel without discriminating between taxa. And fading toward bg can look like a genuinely low-theta cell, collapsing two different claims into similar colours.

#### Limitations

If the lattice or the stratified records span BOTH hemispheres (some latitudes positive, some negative) and lambda_latitude is not NULL, the single-kernel-pass latitude factor above can differ from estimate_kernel_priors()'s exact ||lat_r| - |lat_x|| formula for cross-equatorial record/point pairs (the general form requires a second, hemisphere-mirrored convolution pass that this function does not perform). A message is emitted when this condition is detected. It does not affect the site-identity invariant for a site outside the equatorial band.

A kernel_fit built with sampling_group_col is REFUSED with an error. That argument makes estimate_kernel_priors() compute n_eff and the regional back-off separately within each sampling group; this function has no equivalent split and would silently draw the pooled, ungrouped field. Map one group at a time by fitting it on its own record subset.

### report_priors(priors_output, verbose = FALSE)

Generate a Report Section for Prior Estimation

Summarizes the prior estimation produced by TaxaExpect into a structured 'report_section' object (from TaxaTools). Works standalone or feeds into 'TaxaTools::assemble_report()' for a unified pipeline report.

| Param | Required | Default | Doc |
|---|---|---|---|
| priors_output | yes |  | Either: A list with a $priors element (contains $priors, $model, $occurrences, $grid_result) -- accepted for a caller holding a cached, list-shaped priors result on disk. A data frame of priors directly -- the shape produced by estimate_kernel_priors. |
| verbose | no | FALSE | Logical. Print summary messages. Default FALSE. |

**Value:** A 'report_section' object with: methods Template text describing prior estimation approach. results Template text summarizing prior coverage. citations Propagated from occurrence data if available. params Named list of prior parameters. statistics Named list of summary counts.

## Quick Start

``` r
library(TaxaExpect)

# 1. Calibrate the kernel bandwidth (and regional back-off m) by
#    leave-one-block-out composition prediction -- never hand-set.
calib <- calibrate_kernel_bandwidth(
  occurrence_data = occurrences,   # habitat-labelled occurrence records
  site_habitat    = "Marine",
  lambda_grid     = c(10, 25, 50, 100, 200)   # km
)
lambda_km <- calib$best$lambda_km

# 2. Estimate kernel priors at your site (kernel_estimated rows)
kernel_fit <- estimate_kernel_priors(
  occurrence_data = occurrences,
  site_lat        = 34.45,
  site_lon        = -120.47,
  site_habitat    = "Marine",
  lambda_km       = lambda_km
)

# 3. Add resident_undetected rows (singleton mirrors + Good-Turing floor)
undetected <- generate_undetected_diversity(kernel_fit)

# 4. Assemble the prior table for TaxaAssign
priors <- dplyr::bind_rows(kernel_fit$priors, undetected)

# 5. Explore the prior field
plot_theta_surface(kernel_fit, occurrence_data = occurrences,
                    taxon = "Girella nigricans")
```

### Reading values off a surface

A rendered surface is also data. `as.data.frame()` returns the whole
lattice as a long table (lon, lat, taxon, theta, n_eff, W), with masked
cells dropped, so "inside the polygon" comes for free.

``` r
r <- plot_theta_surface(kernel_fit, occurrence_data = occurrences,
                        taxon = c("Girella nigricans", "Pisaster ochraceus"))
grid <- as.data.frame(r)                  # one row per cell x taxon
```

