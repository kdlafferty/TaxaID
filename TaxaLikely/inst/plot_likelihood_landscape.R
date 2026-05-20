# ==============================================================================
# plot_likelihood_landscape.R
# Standalone visualization script for presentations and manuscripts.
# Produces a two-panel figure showing H1 and H2 density surfaces with
# three example hypotheses (A = correct species, B = wrong species,
# U = unreferenced species).
#
# Usage:
#   source(system.file("plot_likelihood_landscape.R", package = "TaxaLikely"))
#
# To use with a trained model, load model_params first:
#   model <- readRDS("trained_model.rds")
#   # then set h1_mu, h1_sigma, h2_mu, h2_sigma from model (see below)
#
# No package dependencies beyond base R.
# ==============================================================================

# --- Bivariate normal density (base R) --------------------------------------
dmvnorm2 <- function(x, mu, sigma) {
  d <- as.numeric(x - mu)
  det_s <- sigma[1,1] * sigma[2,2] - sigma[1,2] * sigma[2,1]
  inv_s <- matrix(c(sigma[2,2], -sigma[1,2], -sigma[2,1], sigma[1,1]),
                  ncol = 2) / det_s
  exp(-0.5 * sum(d * (inv_s %*% d))) / (2 * pi * sqrt(det_s))
}

logit <- function(p) {
  p <- pmin(pmax(p, 1e-4), 1 - 1e-4)
  log(p / (1 - p))
}

# ==============================================================================
# PARAMETERS
# ==============================================================================
# To use a trained taxa_model_params object instead:
#   h1_mu    <- as.numeric(model$H1_Global_Mu)
#   h1_sigma <- as.matrix(model$H1_Sigma)
#   h2_mu    <- c(h1_mu[1] - model$H2$delta, 0)
#   h2_sigma <- as.matrix(model$H2$sigma)

# Conceptual defaults (pedagogically tuned)
h1_mu    <- c(7.5, 3.0)
h1_sigma <- matrix(c(4.0, 1.0, 1.0, 3.0), ncol = 2)
h2_mu    <- c(4.5, 0.0)
h2_sigma <- matrix(c(2.0, 0.5, 0.5, 2.0), ncol = 2)

# ==============================================================================
# THREE EXAMPLE HYPOTHESES
# ==============================================================================
# A: correct species (at H1 center)
pt_a <- data.frame(score = h1_mu[1], gap = h1_mu[2])
# B: wrong referenced species (lower score, negative gap — outscored)
pt_b <- data.frame(score = logit(0.95), gap = -1.5)
# U: unreferenced species (at H2 center)
pt_u <- data.frame(score = h2_mu[1], gap = h2_mu[2])

# ==============================================================================
# DENSITY GRID
# ==============================================================================
x_seq <- seq(-4, 16, length.out = 200)
y_seq <- seq(-8, 10, length.out = 200)
z_h1 <- outer(x_seq, y_seq, Vectorize(function(x, y)
  dmvnorm2(c(x, y), h1_mu, h1_sigma)))
z_h2 <- outer(x_seq, y_seq, Vectorize(function(x, y)
  dmvnorm2(c(x, y), h2_mu, h2_sigma)))
z_h1_n <- z_h1 / max(z_h1)
z_h2_n <- z_h2 / max(z_h2)

# ==============================================================================
# RASTER BUILDER
# ==============================================================================
make_raster <- function(z_norm, ramp_colors) {
  n_col <- 256
  ramp <- colorRampPalette(ramp_colors)(n_col)
  mat <- matrix(NA_character_, nrow = nrow(z_norm), ncol = ncol(z_norm))
  for (i in seq_len(nrow(z_norm)))
    for (j in seq_len(ncol(z_norm))) {
      idx <- max(1L, min(n_col, ceiling(z_norm[i, j] * (n_col - 1)) + 1L))
      mat[i, j] <- ramp[idx]
    }
  as.raster(t(mat[, ncol(mat):1]))
}

raster_h1 <- make_raster(z_h1_n, c("white", "#2166AC"))
raster_h2 <- make_raster(z_h2_n, c("white", "#B2182B"))

# ==============================================================================
# AXIS SETUP
# ==============================================================================
prob_ticks  <- c(0.80, 0.90, 0.95, 0.99, 0.999)
logit_ticks <- logit(prob_ticks)
tick_labels <- paste0(prob_ticks * 100, "%")
keep <- logit_ticks >= 1 & logit_ticks <= 11
logit_ticks <- logit_ticks[keep]
tick_labels <- tick_labels[keep]

xlim <- c(1, 11); ylim <- c(-3, 6)
contour_levels <- c(0.1, 0.3, 0.5, 0.7, 0.9)
contour_lwd    <- c(0.6, 0.8, 1.2, 1.6, 2.0)

# ==============================================================================
# PLOT: TWO PANELS
# ==============================================================================
draw_panel <- function(raster, z_norm, panel_title, contour_col, subtitle_col,
                       pt_a, pt_b, pt_u, show_ylab = TRUE) {
  plot(NULL, xlim = xlim, ylim = ylim,
       xlab = "Match Score (Probability)",
       ylab = if (show_ylab) "Gap to Best Alternative (Logit Units)" else "",
       main = panel_title, axes = FALSE)
  axis(1, at = logit_ticks, labels = tick_labels)
  axis(2, at = seq(-3, 6, 1))
  rasterImage(raster, min(x_seq), min(y_seq), max(x_seq), max(y_seq),
              interpolate = TRUE)
  contour(x_seq, y_seq, z_norm, levels = contour_levels, add = TRUE,
          drawlabels = FALSE, col = contour_col, lwd = contour_lwd)
  box()
  mtext("Shading = likelihood", side = 3, line = 0.2, cex = 0.85, col = "grey40")

  # Points
  points(pt_a$score, pt_a$gap, pch = 21, cex = 4, bg = "white", col = "#0a2d5e", lwd = 2)
  text(pt_a$score, pt_a$gap, "A", col = "#0a2d5e", font = 2, cex = 1.6)
  points(pt_b$score, pt_b$gap, pch = 21, cex = 4, bg = "white", col = "#555555", lwd = 2)
  text(pt_b$score, pt_b$gap, "B", col = "#555555", font = 2, cex = 1.6)
  points(pt_u$score, pt_u$gap, pch = 21, cex = 4, bg = "white", col = "#8B0000", lwd = 2)
  text(pt_u$score, pt_u$gap, "U", col = "#8B0000", font = 2, cex = 1.6)
}

par(mfrow = c(1, 2), mar = c(5, 5, 3, 1), family = "sans")
draw_panel(raster_h1, z_h1_n, "H1: Known Species", "#0a3d7a", "grey40",
           pt_a, pt_b, pt_u, show_ylab = TRUE)
draw_panel(raster_h2, z_h2_n, "H2: Unreferenced Species", "#7a0a0a", "grey40",
           pt_a, pt_b, pt_u, show_ylab = FALSE)

# ==============================================================================
# INTERPRETATION
# ==============================================================================
# A (correct species): High likelihood on H1, Low on H2
# B (wrong species):   Low likelihood on BOTH — eliminated regardless
# U (unreferenced):    Low likelihood on H1, High on H2
# ==============================================================================
