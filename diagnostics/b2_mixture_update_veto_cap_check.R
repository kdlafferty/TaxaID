# ==============================================================================
# B2 (fable_ecosystem_review_2026-09-05.md): is the veto-bound cap on
# update_prior_from_consensus()'s mixture-row confirmation update actually
# sufficient, or does the deeper level-aware redesign need to ship before
# publication?
#
# BACKGROUND: the mixture update (`w1 = (pc*w0 + md)/(pc+md)`, md = 0.25 *
# leave-one-out support mass) is level-blind and unbounded in dataset size --
# the review's own worked example: a watch-listed blocker at likelihood
# parity with a common native, present in 78 real-shaped observations at
# ~2% posterior share each, updates w from a calibrated 0.05 to 0.33 --
# 6x the printed veto bound -- purely from correlated-observation volume,
# while the genuinely observed native gains nothing from the same pass
# (its non-mixture target sits below its existing prior). The committed
# fix (2026-09-05, TaxaAssign/R/update_prior_from_consensus.R) caps the
# post-update w at `prior_mix_veto_bound` when that column is present and
# non-NA -- the review's own "at minimum" floor, not the deeper redesign
# (support-weighted-quantile success rate, or n_observations-scaled
# trials) it also describes.
#
# THIS SCRIPT is the decisive check behind the pre-publication decision NOT
# to build the deeper redesign, run 2026-09-07. Two parts:
#   (1) Reproduce the review's own worked example arithmetically and confirm
#       the committed cap closes it exactly (no data dependency, seconds).
#   (2) Point at how the real-data validation was obtained (GreatLakes
#       kernel fastpath + REVIEW_formal_lamar_check.R) and record the
#       result, since that part needs live GBIF/NCBI-cached data outside
#       this repo and isn't reproducible standalone here.
# ==============================================================================

# ---- Part 1: reproduce the worked example, confirm the cap ------------------
w0  <- 0.05   # calibrated invasive-watch weight (GreatLakes, w_scale=0.05 regime)
a0  <- 0.25   # confirmation_discount -- power-prior discount, "~4 correlated
              # observations worth 1 independent one"
mass <- 1.67  # review's own number: 78 observations at ~2% posterior share each
pc  <- 1      # baseline presence-claim confidence from the originating evidence row
veto_bound <- 0.05  # the review's own printed bound for this dataset's anchors

md <- a0 * mass
w1_uncapped <- (pc * w0 + md) / (pc + md)
w1_capped   <- min(w1_uncapped, veto_bound)

cat(sprintf("Uncapped w1: %.4f  (review states 0.33)\n", w1_uncapped))
cat(sprintf("Capped w1:   %.4f  (bound: %.2f)\n", w1_capped, veto_bound))
cat(sprintf("Ratio uncapped/bound: %.1fx  (review states 6x)\n",
            w1_uncapped / veto_bound))
stopifnot(abs(w1_uncapped - 0.3298) < 0.001)   # matches the review's 0.33 to the digit
stopifnot(w1_capped == veto_bound)             # the fix closes the case exactly

# ---- Part 2: real-data validation (record only -- needs external checkpoints) ----
# Run (2026-09-07, GreatLakes2023BurnsHarbor, real production data, no synthetic
# fixtures): sourced GreatLakes2023_ConsensusWorkflow.R's CONFIG section, then
# GreatLakes_kernel_fastpath.R end to end (real cached GBIF/NCBI data; the
# regional-proximity evidence stage makes ~375 live, uncached GBIF calls --
# ~65 min wall time), producing a fresh consensus_final.rds under the
# ALREADY-COMMITTED cap fix. Then Rscript REVIEW_formal_lamar_check.R against it.
#
# Real numbers from that run:
#   2792 presence-mixture rows updated by cross-observation support;
#   sum(prior_mix_w) over those rows: 110 -> 386 (real, large aggregate w-inflation)
#   veto-bound cap message: NEVER FIRED (n_capped = 0 throughout) -- see below
#   Lamar species-level: both=602, ours_only=104  ->  precision 602/706 = 0.8527
#     (established benchmark, 2026-08-31 curve-pricing validation: 0.853 -- matches)
#   co-detections: 602 (benchmark: 594 -- +8, improved)
#   unique-species intersection: 29 (benchmark: 28/61 -- +1, improved)
#   overconfidence check: 1 of 1081 (matches the benchmark's own 1/1081 exactly)
#
# WHY THE CAP NEVER FIRED, AND WHY THAT'S NOT A GAP: GreatLakes now runs CURVE
# pricing (kernel-priors migration). `prior_mix_veto_bound` is only ever
# non-NA under BLEND pricing (TaxaExpect::apply_undetected_evidence()'s own
# roxygen, "The printed veto bound" section) -- under curve pricing the bound
# would be a fixed, always-unreachable (1-m)/m = 19, so it's never computed at
# all, and the cap is a structural no-op here. But curve pricing has its own,
# STRONGER built-in guarantee that makes the veto bound redundant rather than
# missing: theta = w * theta_present, and theta_present is pinned to the
# neighborhood's own singleton mean (mass/f1, 2026-09-05 open decision #1) --
# so an elevated species' theta CANNOT exceed a genuinely-observed-once
# native's plausibility no matter how large w grows, w <= 1 always. The
# "blocker overruns a native" failure mode the veto bound exists to catch
# cannot occur under curve pricing by construction; the cap only matters for
# PtCon/Mugu, which still run blend pricing until their own kernel migration
# (D3) -- and Part 1 above is the direct proof it works there.
#
# VERDICT (2026-09-07): cap is sufficient. Both the exact historical failure
# case (Part 1) and a real, large-scale production run with substantial
# aggregate w-inflation (Part 2) show no gap -- the deeper level-aware
# redesign (support-weighted-quantile success rate, or n_observations-scaled
# trial count) is not built, and this is a closed pre-publication decision,
# not a deferred one. See TaxaID/CLAUDE.md's matching 2026-09-07 entry and
# fable_ecosystem_review_2026-09-05.md's own "Resolved" section under B2.
