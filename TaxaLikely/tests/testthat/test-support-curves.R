# Tests for R/support_curves.R -- .compute_rank_score_curves(),
# .lookup_confusion_risk_value(), compute_rank_thresholds().
#
# Fixture: 2 families x 2 genera x 3 species, with clearly separated score
# bands so every pair_type is populated and the expected curve shape is known
# by construction (same design as the synthetic check used when this file was
# first written, now committed rather than run ad hoc).

.curve_fixture <- function() {
  mk <- function(sx, sy, gx, gy, fx, fy, p) {
    data.frame(id_x = paste0(sx, "_1"), id_y = paste0(sy, "_1"),
               species.x = sx, species.y = sy,
               genus.x = gx, genus.y = gy,
               family.x = fx, family.y = fy,
               p_match = p, stringsAsFactors = FALSE)
  }
  rbind(
    # within-species (high)
    mk("Aa sp1", "Aa sp1", "Aa", "Aa", "Fam1", "Fam1", 0.995),
    mk("Aa sp2", "Aa sp2", "Aa", "Aa", "Fam1", "Fam1", 0.990),
    mk("Bb sp1", "Bb sp1", "Bb", "Bb", "Fam1", "Fam1", 0.985),
    mk("Cc sp1", "Cc sp1", "Cc", "Cc", "Fam2", "Fam2", 0.992),
    # congeneric (mid) -- Aa has 2, Bb has 1 (different n, exercises shrinkage)
    mk("Aa sp3", "Aa sp1", "Aa", "Aa", "Fam1", "Fam1", 0.930),
    mk("Aa sp4", "Aa sp2", "Aa", "Aa", "Fam1", "Fam1", 0.910),
    mk("Bb sp2", "Bb sp1", "Bb", "Bb", "Fam1", "Fam1", 0.900),
    # confamilial (lower)
    mk("Aa sp5", "Bb sp1", "Aa", "Bb", "Fam1", "Fam1", 0.750),
    mk("Bb sp3", "Aa sp1", "Bb", "Aa", "Fam1", "Fam1", 0.700),
    # cross-family (lowest)
    mk("Aa sp6", "Cc sp1", "Aa", "Cc", "Fam1", "Fam2", 0.400),
    mk("Cc sp2", "Bb sp1", "Cc", "Bb", "Fam2", "Fam1", 0.350)
  )
}
.rs <- c("family", "genus", "species")

test_that(".compute_rank_score_curves() returns all three tiers on a complete fixture", {
  cur <- .compute_rank_score_curves(.curve_fixture(), .rs)
  expect_false(is.null(cur))
  expect_true(all(c("species", "genus", "family") %in% names(cur)))
  expect_false(is.null(cur$species))
  expect_false(is.null(cur$genus))
  expect_false(is.null(cur$family))
  expect_equal(cur$prior_weight, 10.0)
})

test_that("rate curves carry BOTH a raw and a Jeffreys-smoothed column", {
  cur <- .compute_rank_score_curves(.curve_fixture(), .rs)
  sp <- cur$species
  expect_true(all(c("rate", "rate_smooth") %in% names(sp$fpr_by_genus_shrunk)))
  expect_true(all(c("pooled_rate", "pooled_rate_smooth") %in% names(sp$fpr_pooled)))
  expect_true(all(c("pooled_rate", "pooled_rate_smooth") %in% names(cur$family$fpr_pooled)))
})

test_that("rate_smooth is exactly the Jeffreys posterior mean (k + 1/2)/(n + 1)", {
  cur <- .compute_rank_score_curves(.curve_fixture(), .rs)
  s <- cur$species$fpr_by_genus_shrunk
  # Genus Aa has 2 congeneric pairs (0.930, 0.910 -> 93 and 91 pct).
  aa <- s[s$group == "Aa", ]
  expect_equal(unique(aa$n), 2)
  at <- function(t) aa[aa$threshold == t, ]
  # t = 90: both pairs qualify -> k = 2
  expect_equal(at(90)$rate, 1)
  expect_equal(at(90)$rate_smooth, (2 + 0.5) / (2 + 1))
  # t = 92: one pair qualifies -> k = 1
  expect_equal(at(92)$rate, 0.5)
  expect_equal(at(92)$rate_smooth, (1 + 0.5) / (2 + 1))
  # t = 95: none qualify -> k = 0, raw is exactly 0, smoothed is not
  expect_equal(at(95)$rate, 0)
  expect_equal(at(95)$rate_smooth, (0 + 0.5) / (2 + 1))
  expect_gt(at(95)$rate_smooth, 0)
})

test_that("the smoothed rate is never exactly 0 or 1, but the raw rate still can be", {
  cur <- .compute_rank_score_curves(.curve_fixture(), .rs)
  s <- cur$species$fpr_by_genus_shrunk
  expect_true(any(s$rate == 0))              # raw keeps the empirical extremes
  expect_true(any(s$rate == 1))
  expect_false(any(s$rate_smooth == 0))      # smoothed never claims certainty
  expect_false(any(s$rate_smooth == 1))
  expect_false(any(cur$species$fpr_pooled$pooled_rate_smooth == 0))
})

test_that("smoothing preserves monotonicity in threshold", {
  cur <- .compute_rank_score_curves(.curve_fixture(), .rs)
  s <- cur$species$fpr_by_genus_shrunk
  for (g in unique(s$group)) {
    v <- s[s$group == g, ]
    v <- v[order(v$threshold), ]
    expect_true(all(diff(v$rate_smooth) <= 1e-12),
                info = paste("non-monotonic rate_smooth for group", g))
  }
})

test_that("EB shrinkage blends the SMOOTHED rate toward the SMOOTHED pooled target", {
  cur <- .compute_rank_score_curves(.curve_fixture(), .rs, prior_weight = 10)
  s <- cur$species$fpr_by_genus_shrunk
  row <- s[s$group == "Aa" & s$threshold == 92, ]
  w <- row$n / (row$n + 10)
  expect_equal(row$w, w)
  expect_equal(row$shrunk_rate,
               w * row$rate_smooth + (1 - w) * row$pooled_rate_smooth)
  # and specifically NOT the raw-rate version
  expect_false(isTRUE(all.equal(row$shrunk_rate,
                                w * row$rate + (1 - w) * row$pooled_rate)))
})

test_that(".lookup_confusion_risk_value() interpolates rather than snapping to a grid point", {
  pooled <- data.frame(threshold          = c(98, 99, 100),
                       pooled_rate        = c(0.40, 0.20, 0.00),
                       pooled_rate_smooth = c(0.40, 0.20, 0.00))
  # Exactly on a grid point -> that point's value.
  expect_equal(.lookup_confusion_risk_value(99, NULL, NULL, pooled), 0.20)
  # Halfway between -> halfway value, NOT either endpoint.
  expect_equal(.lookup_confusion_risk_value(99.5, NULL, NULL, pooled), 0.10)
  # The old nearest-neighbour snap would have returned 0.20 for both of these
  # and 0.00 for the second; interpolation separates them.
  expect_equal(.lookup_confusion_risk_value(99.25, NULL, NULL, pooled), 0.15)
  expect_equal(.lookup_confusion_risk_value(99.75, NULL, NULL, pooled), 0.05)
  expect_true(.lookup_confusion_risk_value(99.6, NULL, NULL, pooled) >
              .lookup_confusion_risk_value(99.9, NULL, NULL, pooled))
})

test_that(".lookup_confusion_risk_value() clamps outside the grid instead of returning NA", {
  pooled <- data.frame(threshold          = c(98, 99, 100),
                       pooled_rate        = c(0.40, 0.20, 0.00),
                       pooled_rate_smooth = c(0.40, 0.20, 0.05))
  expect_equal(.lookup_confusion_risk_value(101, NULL, NULL, pooled), 0.05)
  expect_equal(.lookup_confusion_risk_value(50,  NULL, NULL, pooled), 0.40)
  expect_true(is.na(.lookup_confusion_risk_value(NA_real_, NULL, NULL, pooled)))
  expect_true(is.na(.lookup_confusion_risk_value(99, NULL, NULL, NULL)))
})

test_that(".lookup_confusion_risk_value() prefers the group-specific shrunk curve", {
  pooled <- data.frame(threshold          = c(98, 99, 100),
                       pooled_rate        = c(0.40, 0.20, 0.00),
                       pooled_rate_smooth = c(0.40, 0.20, 0.00))
  shrunk <- data.frame(group       = rep("Aa", 3),
                       threshold   = c(98, 99, 100),
                       shrunk_rate = c(0.80, 0.60, 0.40))
  expect_equal(.lookup_confusion_risk_value(99, "Aa", shrunk, pooled), 0.60)
  expect_equal(.lookup_confusion_risk_value(99.5, "Aa", shrunk, pooled), 0.50)
  # A group with no row of its own falls back to the pooled curve.
  expect_equal(.lookup_confusion_risk_value(99, "Zz", shrunk, pooled), 0.20)
})

test_that(".lookup_confusion_risk_value() still works on a curves object with no smoothed column", {
  # Backward compatibility: a Confusion_Risk_Curves object stored before
  # pooled_rate_smooth existed must not error.
  legacy <- data.frame(threshold = c(98, 99, 100), pooled_rate = c(0.40, 0.20, 0.00))
  expect_equal(.lookup_confusion_risk_value(99, NULL, NULL, legacy), 0.20)
  expect_equal(.lookup_confusion_risk_value(99.5, NULL, NULL, legacy), 0.10)
})

test_that("compute_rank_thresholds() reads the RAW rate, so smoothing does not move it", {
  fx <- .curve_fixture()
  rt <- compute_rank_thresholds(fx, rank_system = .rs)
  expect_true(is.numeric(rt))
  expect_true(all(names(rt) %in% c("species", "genus", "family")))
  # Recompute Youden's J by hand off the raw pooled columns and confirm the
  # exported function agrees -- this is what pins it to `rate`, not `rate_smooth`.
  cur <- .compute_rank_score_curves(fx, .rs)
  m <- merge(cur$species$tpr_pooled, cur$species$fpr_pooled,
             by = "threshold", suffixes = c("_tpr", "_fpr"))
  j <- m$pooled_rate_tpr - m$pooled_rate_fpr
  expect_equal(unname(rt[["species"]]), m$threshold[which.max(j)])
})

test_that(".compute_rank_score_curves() degrades gracefully on thin input", {
  expect_null(.compute_rank_score_curves(.curve_fixture(), c("species")))
  fx <- .curve_fixture()
  fx$genus.x <- NULL
  expect_null(.compute_rank_score_curves(fx, .rs))
})
