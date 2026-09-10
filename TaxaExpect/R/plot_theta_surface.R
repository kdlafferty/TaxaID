# plot_theta_surface() -- the KDE prior-field map for the kernel-priors path
# (2026-09-01, branch theta-surface). Design record:
# ecosystem_docs/SPEC_plot_theta_surface.md, whose origin is the "Display
# companion" clause of the Phase 1 spec in
# ecosystem_docs/REENTRY_PROMPT_evidence_ceiling_and_habitat_bleed.md.
#
# WHAT THIS REPLACES: plot_theta_map_interactive() rendered per-GRID-CELL
# theta by parsing Grid_<lat>_<lon> identifiers into centroids. The
# kernel-priors redesign (estimate_kernel_priors()) produces ONE site row
# with an opaque site_id, so that function had nothing to draw on the kernel
# path -- it was gated OFF (if (!USE_KERNEL_PRIORS)) in all five production
# workflows. This function evaluates the SAME estimator formula on a
# lattice of points instead of at one site, via binned FFT convolution
# (stats::fft, base R -- no new dependency), so the resulting map IS the
# prior field, not a smoothed picture of something else.
# plot_theta_map_interactive() and the rest of the GLMM/grid prior-fitting
# chain were archived 2026-09-09 (see archive_glmm_prior_pipeline/ and
# TaxaExpect/CLAUDE.md's 2026-09-09 session note) -- this function is now
# the package's only prior-field visualization.

#' Evaluate the kernel-prior estimator on a spatial lattice (KDE prior field)
#'
#' Computes the SAME distance-kernel estimator [estimate_kernel_priors()]
#' applies at one site, at every point of a regular lattice instead, via
#' binned FFT convolution. The result is a genuine prior FIELD: evaluating
#' the surface at the site's own coordinates reproduces
#' [estimate_kernel_priors()]'s `theta_mean` for the requested taxon exactly
#' (to numerical/grid-discretization tolerance), because it is the identical
#' formula, not a smoothed rendering of it.
#'
#' @section The estimator, on a lattice:
#' For evaluation point \eqn{x} and the habitat-stratified record set (the
#' same stratification [estimate_kernel_priors()] applies):
#' \deqn{w_r(x) = \exp(-d(x,r)/\lambda)}
#' (times the optional per-record covariate factor and the optional
#' absolute-latitude climate factor -- see below), then
#' \deqn{W(x) = \sum_r w_r(x), \quad S_2(x) = \sum_r w_r(x)^2, \quad
#'   n_{eff}(x) = W(x)^2 / S_2(x)}
#' (Kish effective sample size), and for species \eqn{i}
#' \deqn{c_i(x) = \sum_{r \in i} w_r(x), \quad
#'   \theta_i(x) = (c_i(x) n_{eff}(x)/W(x) + m p_i) / (n_{eff}(x) + m)}
#' with \eqn{p_i} the same unweighted habitat-stratified regional
#' composition [estimate_kernel_priors()] uses. All three lattice surfaces
#' (a species indicator mass, the all-records mass, and the all-records
#' squared-weight mass) are computed by binning records onto the output
#' lattice and convolving with the kernel evaluated on the same lattice via
#' [stats::fft()] (zero-padded to avoid circular wraparound) -- this is
#' O(n_grid^2 log n_grid) regardless of species count, not O(records) per
#' pixel.
#'
#' @section Covariate and latitude factors:
#' The geographic kernel (and the optional absolute-latitude climate factor)
#' are functions of position, so both belong inside the lattice kernel. The
#' COVARIATE factor (e.g. depth) is a per-record attribute, not a function of
#' map position -- a 2-D surface cannot represent it unless the covariate is
#' held fixed. When `covariate_at` is supplied (and `kernel_fit` was built
#' with a `covariate_col`), records are reweighted by
#' `exp(-|c_r - covariate_at| / lambda_covariate)` before binning -- constant
#' across the lattice, so it only reweights which records count, exactly
#' mirroring [estimate_kernel_priors()]'s own per-record factor. When
#' `covariate_at` is `NULL` (default), the factor is OMITTED and a message
#' says so -- the returned object and plot never imply the map shows a
#' depth-conditioned field when it does not.
#'
#' Whichever of the three states applies -- the fit has no covariate, it has
#' one that this map OMITS, or it has one held at a stated value -- is written
#' onto the rendered map itself (a subtitle on the static plot, a caption on
#' the interactive one) alongside the habitat stratum, and printed by
#' `print()`. The conditions therefore travel with a screenshot. They are
#' shown as three visually distinct states on purpose: a fit that has a
#' covariate but is drawn without it says so affirmatively, because rendering
#' that case as silence would read as \"this model has no covariate\", which
#' is a different and false claim. To see a different habitat or a different
#' covariate value, re-fit: both are choices made in
#' [estimate_kernel_priors()], not view settings on an existing fit.
#'
#' The optional latitude factor
#' `exp(-111 * ||lat_r| - |lat_x|| / lambda_latitude)` is folded into the
#' SAME lattice kernel using signed `lat_x - lat_r` (translation-invariant,
#' so it convolves in one FFT pass together with the geographic factor).
#' This is mathematically EXACT whenever the site, the lattice, and every
#' contributing record share the same hemisphere sign (the case for every
#' real deployment of this package -- Great Lakes, Point Conception, Mugu --
#' none of which are within a bandwidth of the equator); see `@section
#' Limitations` for the general case.
#'
#' @section Limitations:
#' If the lattice or the stratified records span BOTH hemispheres (some
#' latitudes positive, some negative) and `lambda_latitude` is not `NULL`,
#' the single-kernel-pass latitude factor above can differ from
#' [estimate_kernel_priors()]'s exact `||lat_r| - |lat_x||` formula for
#' cross-equatorial record/point pairs (the general form requires a second,
#' hemisphere-mirrored convolution pass that this function does not
#' perform). A message is emitted when this condition is detected. It never
#' affects the site-identity invariant for a site that (like every current
#' deployment) sits comfortably outside the equatorial band.
#'
#' A `kernel_fit` built with `sampling_group_col` is REFUSED with an error.
#' That argument makes [estimate_kernel_priors()] compute `n_eff` and the
#' regional back-off separately within each sampling group; this function has
#' no equivalent split and would silently draw the pooled, ungrouped field.
#' Map one group at a time by fitting it on its own record subset (the shape
#' the 18S workflow already uses) rather than passing a grouped fit here.
#'
#' @section Relationship to the retired plot_theta_map_interactive():
#' The GLMM/grid prior-fitting chain's own visualization,
#' `plot_theta_map_interactive()`, parsed `Grid_<lat>_<lon>` identifiers out
#' of a `grid_id` column to find grid-cell centroids to draw -- it depicted
#' predictions already computed at a fixed set of grid cells. The
#' kernel-priors path (`estimate_kernel_priors()`) has no grid: it returns
#' ONE site row with an opaque `site_id` that encodes no spatial extent, so
#' that function had nothing to parse and nothing to draw for it (this is
#' why it was gated OFF on the kernel path in every production workflow).
#' `plot_theta_surface()` replaces it for kernel priors by evaluating the
#' estimator AT EVERY LATTICE POINT rather than relying on pre-computed
#' per-cell predictions, so the map is the estimator evaluated continuously,
#' not an interpolation between grid predictions. `plot_theta_map_
#' interactive()` was archived 2026-09-09 along with the rest of the GLMM
#' chain (see `archive_glmm_prior_pipeline/` and TaxaExpect/CLAUDE.md's
#' 2026-09-09 session note) -- this function is now the only prior-field
#' visualization in the package.
#'
#' @param kernel_fit A `taxaexpect_kernel_priors` object from
#'   [estimate_kernel_priors()] -- the source of `lambda_km`, `m`,
#'   `lambda_latitude`, `covariate_col`, `lambda_covariate`, `site_habitat`,
#'   and the site coordinates (`site_lat`/`site_lon`, marked on the map).
#'   Every tuning parameter defaults from this object so the surface cannot
#'   silently drift from the priors it claims to depict.
#' @param occurrence_data The SAME occurrence data frame passed to
#'   [estimate_kernel_priors()] to produce `kernel_fit` (cleaned,
#'   habitat-labelled occurrence records).
#' @param taxon Character vector of one or more species names to surface.
#'   Length 1 returns a single surface; length > 1 returns one surface per
#'   taxon (a facet grid for the static plot, a layer-toggle overlay for the
#'   interactive map).
#' @param n_grid Integer, lattice resolution per side (default `256L`).
#' @param bbox Optional named numeric vector/list with `lat_min`, `lat_max`,
#'   `lon_min`, `lon_max`. Default `NULL`: computed from the full extent of
#'   the habitat-stratified records (unioned with the site coordinates) plus
#'   padding, which GUARANTEES every record that [estimate_kernel_priors()]
#'   would use is included in the lattice binning -- this is what makes the
#'   site-identity invariant hold. Supplying a smaller custom `bbox` excludes
#'   records outside it from the surface (a documented, deliberate window
#'   truncation), which can disagree with the exact site value if the site
#'   itself sits near or outside that window.
#' @param m Optional back-off mass override. Default `NULL`: use
#'   `kernel_fit$params$m` (the value the priors were actually fit with).
#' @param covariate_at Optional numeric scalar: the covariate value (e.g.
#'   depth) to hold fixed across the whole lattice. Default `NULL`: the
#'   covariate factor is omitted entirely and a message documents this (see
#'   `@section Covariate and latitude factors`). Only meaningful when
#'   `kernel_fit` was built with a `covariate_col`; supplying it against a
#'   fit that has none is an error (nothing to condition on).
#' @param alpha_by_n_eff Logical (default `TRUE`). Fade the surface toward
#'   transparent where lattice-point `n_eff(x)` is low relative to the
#'   surface's own maximum, so a reader cannot mistake a lightly-supported
#'   extrapolation for a well-evidenced estimate.
#' @param n_eff_floor Optional numeric. Lattice points with `n_eff(x)` below
#'   this value are masked outright (drawn as background, not just faded),
#'   independent of `alpha_by_n_eff`. Default `NULL`: no outright mask.
#' @param mask Optional geometry restricting the surface to a region of
#'   interest (a lake outline, a bay, a survey boundary). Cells whose centres
#'   fall outside become `NA` -- transparent on the map, and excluded from
#'   any summary of the returned matrices. Accepts a WKT `POLYGON`/
#'   `MULTIPOLYGON` string -- including, directly, the same search polygon a
#'   workflow already passes to its GBIF fetch, which is usually what you
#'   want, since it clips the map to the geometry the records were fetched
#'   under -- or an `sf`/`sfc` polygon (requires the `sf` package), or a
#'   plain two-column lon/lat matrix/data frame, or a list of such matrices
#'   (a cell is kept if it falls inside ANY of them, for islands or
#'   multi-basin masks).
#'   Deliberately a parameter with no default: the correct mask is
#'   application-specific, so the package supplies none.
#' @param site_marker_radius Numeric (default `5`). Radius in pixels of the
#'   hollow circle marking the site on the interactive map. The marker is
#'   drawn unfilled and on top so it cannot hide the cell it marks (the
#'   default pin marker did, which is why this is small and hollow).
#' @param hover_labels Logical (default `TRUE`). Show `theta` and the local
#'   effective sample size on hover over each rendered cell of the
#'   interactive map.
#' @param interactive Logical (default `FALSE`). `FALSE` returns a static
#'   base-graphics plot. `TRUE` returns a Leaflet overlay (guarded by
#'   `requireNamespace("leaflet")`); `leaflet` is already in TaxaExpect's
#'   `Suggests`, so this adds no new dependency.
#' @param taxon_col,lat_col,lon_col,habitat_col Column names in
#'   `occurrence_data` (defaults matching [estimate_kernel_priors()]:
#'   `"taxon_name"`, `"decimalLatitude"`, `"decimalLongitude"`,
#'   `"main_habitat"`). `kernel_fit` does not carry these names, so they are
#'   supplied here with the same defaults the estimator uses.
#' @param ... Passed to the static plot's underlying [graphics::image()] call
#'   (e.g. `main`) or, when `interactive = TRUE`, to
#'   [leaflet::addRectangles()].
#'
#' @return An object of class `"taxaexpect_theta_surface"`: a list with
#'   \describe{
#'     \item{surface}{A list with `lat_grid`, `lon_grid` (lattice
#'       coordinates), `theta` (an `n_grid` x `n_grid` matrix for one taxon,
#'       or a named list of such matrices for several), `n_eff`, `W` (Kish
#'       effective sample size and total kernel weight at every lattice
#'       point), `regional_composition` (the `p_i` used per requested
#'       taxon), and `params` (the resolved tuning values, for provenance).}
#'     \item{plot}{The plot object: a base graphics call (invisible `NULL`,
#'       since base graphics draws immediately) when `interactive = FALSE`,
#'       or a `leaflet` htmlwidget when `interactive = TRUE`.}
#'   }
#'   Returned invisibly is never done here -- callers can inspect or
#'   re-render `$surface` without recomputing.
#' @seealso [estimate_kernel_priors()] for the site-level estimator this
#'   function reproduces on a lattice. The GLMM/grid-cell equivalent,
#'   `plot_theta_map_interactive()`, was archived 2026-09-09 along with the
#'   rest of the GLMM prior-fitting chain (see `archive_glmm_prior_pipeline/`).
#' @export
plot_theta_surface <- function(kernel_fit,
                               occurrence_data,
                               taxon,
                               n_grid = 256L,
                               bbox = NULL,
                               m = NULL,
                               covariate_at = NULL,
                               alpha_by_n_eff = TRUE,
                               n_eff_floor = NULL,
                               mask = NULL,
                               site_marker_radius = 5,
                               hover_labels = TRUE,
                               interactive = FALSE,
                               taxon_col = "taxon_name",
                               lat_col = "decimalLatitude",
                               lon_col = "decimalLongitude",
                               habitat_col = "main_habitat",
                               ...) {
  if (!inherits(kernel_fit, "taxaexpect_kernel_priors")) {
    stop("plot_theta_surface: 'kernel_fit' must be a taxaexpect_kernel_priors object (from estimate_kernel_priors()).")
  }
  if (!is.data.frame(occurrence_data) || nrow(occurrence_data) == 0L) {
    stop("plot_theta_surface: 'occurrence_data' must be a non-empty data frame.")
  }
  if (!is.character(taxon) || length(taxon) < 1L || anyNA(taxon)) {
    stop("plot_theta_surface: 'taxon' must be a non-NA character vector of one or more species names.")
  }
  if (!is.numeric(n_grid) || length(n_grid) != 1L || is.na(n_grid) || n_grid < 4L) {
    stop("plot_theta_surface: 'n_grid' must be a single numeric >= 4.")
  }
  n_grid <- as.integer(round(n_grid))

  p <- kernel_fit$params
  # estimate_kernel_priors() gained sampling_group_col on 2026-09-03: it splits
  # the stratum and computes n_eff and the regional back-off WITHIN each group.
  # This function has no such split -- it would pool every group and draw the
  # ungrouped field while still claiming, via the fit it was handed, to depict
  # that fit. That is a silent failure of the site-identity invariant, so it is
  # refused rather than approximated. The 18S workflow shows the supported
  # shape: fit each group on its own record subset, then map that fit.
  if (!is.null(p$sampling_group_col)) {
    stop(
      "plot_theta_surface: 'kernel_fit' was built with sampling_group_col = '",
      p$sampling_group_col, "', whose per-group n_eff and regional composition ",
      "this function does not reproduce -- the surface would show the POOLED ",
      "ungrouped field. Map one group at a time instead, by re-fitting on that ",
      "group's records: estimate_kernel_priors(subset(occurrence_data, ",
      p$sampling_group_col, " == g), ...)."
    )
  }
  m_use <- if (is.null(m)) p$m else m
  if (!is.numeric(m_use) || length(m_use) != 1L || is.na(m_use) || m_use < 0) {
    stop("plot_theta_surface: 'm' must be a single non-NA numeric >= 0.")
  }

  use_cov <- !is.null(p$covariate_col)
  if (!is.null(covariate_at) && !use_cov) {
    stop("plot_theta_surface: 'covariate_at' was supplied but kernel_fit has no covariate_col -- nothing to condition on.")
  }
  if (use_cov && is.null(covariate_at)) {
    message(sprintf(
      "plot_theta_surface: covariate_at not supplied -- the '%s' covariate factor is OMITTED from this surface. This map does NOT depict a %s-conditioned field.",
      p$covariate_col, p$covariate_col
    ))
  }

  surf <- .theta_surface_engine(
    occurrence_data = occurrence_data,
    site_lat = p$site_lat, site_lon = p$site_lon, site_habitat = p$site_habitat,
    lambda_km = p$lambda_km, m = m_use,
    covariate_col = p$covariate_col, covariate_at = covariate_at,
    lambda_covariate = p$lambda_covariate,
    lambda_latitude = p$lambda_latitude,
    taxon = taxon, n_grid = n_grid, bbox = bbox,
    taxon_col = taxon_col, lat_col = lat_col, lon_col = lon_col, habitat_col = habitat_col
  )

  if (!is.null(mask)) surf <- .theta_surface_apply_mask(surf, mask)

  plt <- if (isTRUE(interactive)) {
    .theta_surface_plot_leaflet(surf,
      site_lat = p$site_lat, site_lon = p$site_lon,
      site_id = p$site_id, alpha_by_n_eff = alpha_by_n_eff,
      n_eff_floor = n_eff_floor,
      site_marker_radius = site_marker_radius,
      hover_labels = hover_labels, ...
    )
  } else {
    .theta_surface_plot_static(surf,
      site_lat = p$site_lat, site_lon = p$site_lon,
      alpha_by_n_eff = alpha_by_n_eff, n_eff_floor = n_eff_floor, ...
    )
  }

  structure(list(surface = surf, plot = plt), class = "taxaexpect_theta_surface")
}

#' @export
print.taxaexpect_theta_surface <- function(x, ...) {
  s <- x$surface
  taxa <- if (is.list(s$theta)) names(s$theta) else "1 taxon"
  cat(sprintf(
    "taxaexpect_theta_surface: %d x %d lattice, taxa: %s\n  lat [%.4f, %.4f], lon [%.4f, %.4f], lambda = %g km, m = %g\n",
    length(s$lat_grid), length(s$lon_grid), paste(taxa, collapse = ", "),
    min(s$lat_grid), max(s$lat_grid), min(s$lon_grid), max(s$lon_grid),
    s$params$lambda_km, s$params$m
  ))
  cat(sprintf("  %s\n", .theta_surface_condition_label(s$params)))
  # Show the map. A function named plot_*() that prints only a text summary
  # is a trap: at the console the summary looks like success while nothing is
  # drawn, so a STALE object from an earlier call keeps displaying (exactly
  # what happened on the 2026-09-01 click-through -- a three-species call
  # printed its summary while an earlier single-species object's map stayed
  # on screen, reading as "the selector is missing"). Printing the object now
  # prints the map too, so what you see is always the object you just built.
  if (!is.null(x$plot)) print(x$plot)
  invisible(x)
}

# ==============================================================================
# Internal engine
# ==============================================================================

#' Compute the kernel-prior estimator on a lattice
#' @noRd
.theta_surface_engine <- function(occurrence_data, site_lat, site_lon, site_habitat,
                                  lambda_km, m, covariate_col, covariate_at,
                                  lambda_covariate, lambda_latitude,
                                  taxon, n_grid, bbox,
                                  taxon_col, lat_col, lon_col, habitat_col) {
  hab <- occurrence_data[[habitat_col]]
  keep <- !is.na(hab) & hab == site_habitat & !is.na(occurrence_data[[taxon_col]]) &
    !is.na(occurrence_data[[lat_col]]) & !is.na(occurrence_data[[lon_col]])
  rec <- occurrence_data[keep, , drop = FALSE]
  if (nrow(rec) == 0L) {
    stop(sprintf("plot_theta_surface: no usable records with %s == '%s'.", habitat_col, site_habitat))
  }
  taxa <- as.character(rec[[taxon_col]])
  rec_lat <- as.numeric(rec[[lat_col]])
  rec_lon <- as.numeric(rec[[lon_col]])

  # ---- regional composition p_i, exactly as estimate_kernel_priors() -------
  p_reg <- table(taxa)
  p_reg <- as.numeric(p_reg) / sum(p_reg)
  names(p_reg) <- names(table(taxa))
  p_i <- stats::setNames(rep(0, length(taxon)), taxon)
  found <- intersect(taxon, names(p_reg))
  p_i[found] <- p_reg[found]
  missing_taxa <- setdiff(taxon, names(p_reg))
  if (length(missing_taxa) > 0L) {
    message(sprintf(
      "plot_theta_surface: taxon %s has zero records in this habitat stratum -- c_i(x) = 0 across the whole surface (theta given entirely by the back-off term).",
      paste(sprintf("'%s'", missing_taxa), collapse = ", ")
    ))
  }

  # ---- lattice (anchored on the site so it lands EXACTLY on a lattice node --
  # this is what makes the site-identity invariant hold to near machine
  # precision rather than only to within half a grid cell) ------------------
  bb <- .theta_surface_bbox(bbox, rec_lat, rec_lon, site_lat, site_lon, lambda_km, n_grid)
  lat_ax <- .theta_surface_axis(bb["lat_min"], bb["lat_max"], site_lat, n_grid)
  lon_ax <- .theta_surface_axis(bb["lon_min"], bb["lon_max"], site_lon, n_grid)
  lat_grid <- lat_ax$grid
  lon_grid <- lon_ax$grid
  dlat <- lat_ax$d
  dlon <- lon_ax$d

  # ---- hemisphere-mixing check for the latitude factor -----------------------
  if (!is.null(lambda_latitude)) {
    signs <- sign(c(lat_grid, rec_lat, site_lat))
    signs <- signs[signs != 0]
    if (length(unique(signs)) > 1L) {
      message("plot_theta_surface: the lattice/records span both hemispheres and lambda_latitude is set -- see @section Limitations in ?plot_theta_surface for the single-kernel-pass approximation this implies away from the site.")
    }
  }

  # ---- per-record covariate weight (constant across x -> folds into mass) ---
  w_cov <- rep(1, nrow(rec))
  if (!is.null(covariate_at)) {
    cv <- rec[[covariate_col]]
    w_cov <- ifelse(is.na(cv), 1, exp(-abs(cv - covariate_at) / lambda_covariate))
  }

  # ---- bin records onto the lattice ------------------------------------------
  i_idx <- .theta_surface_bin_index(rec_lat, lat_grid, dlat)
  j_idx <- .theta_surface_bin_index(rec_lon, lon_grid, dlon)
  in_bbox <- !is.na(i_idx) & !is.na(j_idx)

  mass_all <- .theta_surface_accumulate(i_idx[in_bbox], j_idx[in_bbox], w_cov[in_bbox], n_grid, n_grid)
  mass2_all <- .theta_surface_accumulate(i_idx[in_bbox], j_idx[in_bbox], w_cov[in_bbox]^2, n_grid, n_grid)

  mass_taxon <- stats::setNames(vector("list", length(taxon)), taxon)
  for (tx in taxon) {
    sel <- in_bbox & taxa == tx
    mass_taxon[[tx]] <- .theta_surface_accumulate(i_idx[sel], j_idx[sel], w_cov[sel], n_grid, n_grid)
  }

  # ---- kernel image (translation-invariant: geo x latitude factor) ----------
  # K is shared by W and every per-taxon c_i (same geo/lat kernel, different
  # mass image); K2 (for S2) is a second, separate kernel. Batching all
  # K-convolutions behind ONE forward FFT of K (instead of re-transforming it
  # per taxon) is the difference between O(taxa) and O(1) kernel FFTs.
  K <- .theta_surface_kernel(lat_grid, lon_grid, site_lat, lambda_km, lambda_latitude)
  K2 <- K^2

  # index 1 = all-records mass; indices 2..(1+length(taxon)) = per-taxon
  # masses, positionally matched to `taxon` (never name-keyed, so a species
  # literally named like an internal sentinel can never collide).
  k_group <- c(list(mass_all), unname(mass_taxon[taxon]))
  k_conv <- .theta_surface_fft_convolve_batch(k_group, K)
  S2_mat <- .theta_surface_fft_convolve_batch(list(mass2_all), K2)[[1L]]

  W_mat <- k_conv[[1L]]
  W_mat[W_mat < 0] <- 0 # guard against FFT round-off noise at ~0
  S2_mat[S2_mat < 0] <- 0
  # FFT round-off noise scales with the LARGEST value in the transform, not with
  # .Machine$double.eps, so a lattice point whose true kernel weight underflows
  # to zero (far from every record) comes back as a small POSITIVE number the
  # negative clamps above cannot catch -- and W and S2 carry INDEPENDENT noise,
  # so n_eff = W^2/S2 there is an arbitrary ratio rather than a small number.
  # Real consequence, measured on a two-cluster lattice: 2,817 of 16,384 points
  # returned n_eff = Inf (and theta = NaN), and because that Inf becomes
  # max(n_eff), alpha_by_n_eff faded the ENTIRE surface to fully transparent --
  # a blank map. Points below a relative tolerance (1e-12 of the peak weight,
  # i.e. ~28 bandwidths out, where a record carries no meaningful weight
  # anyway) are therefore treated as genuinely unsupported: n_eff = 0, and
  # theta falls back to the regional composition p_i, the correct limit for a
  # point with no records near it. The test is applied to W and S2 separately
  # because S2 decays TWICE as fast (exp(-2d/lambda)) and so reaches its own
  # noise floor first: the band where W is still real but S2 is not produced
  # finite-but-impossible n_eff values in the same test (5,565 from 800
  # records, where Kish's n_eff is bounded above by the record count). Those
  # points sit ~18+ bandwidths out, where the true n_eff is ~1 and theta is the
  # back-off p_i to many decimal places either way.
  no_support <- !(W_mat > max(W_mat) * 1e-12) |
    !(S2_mat > max(S2_mat) * 1e-12)
  W_mat[no_support] <- 0
  S2_mat[no_support] <- 0
  n_eff_mat <- ifelse(no_support, 0, W_mat^2 / S2_mat)

  theta_list <- stats::setNames(vector("list", length(taxon)), taxon)
  for (ti in seq_along(taxon)) {
    tx <- taxon[ti]
    c_mat <- k_conv[[ti + 1L]]
    c_mat[c_mat < 0] <- 0
    scale_term <- ifelse(W_mat > .Machine$double.eps, c_mat * n_eff_mat / W_mat, 0)
    theta_list[[tx]] <- (scale_term + m * p_i[tx]) / (n_eff_mat + m)
  }
  if (length(taxon) == 1L) theta_list <- theta_list[[1L]]

  list(
    lat_grid = lat_grid, lon_grid = lon_grid,
    theta = theta_list, n_eff = n_eff_mat, W = W_mat,
    regional_composition = p_i,
    params = list(
      site_lat = site_lat, site_lon = site_lon, site_habitat = site_habitat,
      habitat_col = habitat_col,
      lambda_km = lambda_km, m = m, covariate_col = covariate_col,
      covariate_at = covariate_at, lambda_covariate = lambda_covariate,
      lambda_latitude = lambda_latitude, taxon = taxon, n_grid = n_grid,
      n_records_stratum = nrow(rec)
    )
  )
}

#' Default/validated lattice bounding box
#' @noRd
.theta_surface_bbox <- function(bbox, rec_lat, rec_lon, site_lat, site_lon, lambda_km, n_grid) {
  if (!is.null(bbox)) {
    req <- c("lat_min", "lat_max", "lon_min", "lon_max")
    if (!all(req %in% names(bbox))) {
      stop("plot_theta_surface: 'bbox' must have names lat_min, lat_max, lon_min, lon_max.")
    }
    if (bbox["lat_min"] >= bbox["lat_max"] || bbox["lon_min"] >= bbox["lon_max"]) {
      stop("plot_theta_surface: 'bbox' must have lat_min < lat_max and lon_min < lon_max.")
    }
    return(unlist(bbox[req]))
  }
  # padding: a few bandwidths (in degrees), floored so a single/degenerate
  # record set (or an infinite top-hat lambda) still yields a sane extent.
  pad <- max(3 * lambda_km / 111, 0.05)
  if (!is.finite(pad)) pad <- 0.05
  lat_all <- c(rec_lat, site_lat)
  lon_all <- c(rec_lon, site_lon)
  lat_min <- min(lat_all) - pad
  lat_max <- max(lat_all) + pad
  lon_min <- min(lon_all) - pad
  lon_max <- max(lon_all) + pad
  if (lat_min == lat_max) {
    lat_min <- lat_min - pad
    lat_max <- lat_max + pad
  }
  if (lon_min == lon_max) {
    lon_min <- lon_min - pad
    lon_max <- lon_max + pad
  }
  c(lat_min = lat_min, lat_max = lat_max, lon_min = lon_min, lon_max = lon_max)
}

#' A regular axis of n points spanning at least min_v to max_v, anchored so
#' that `anchor` (the site coordinate) lands EXACTLY on one lattice node --
#' this is what makes the site-identity invariant hold to near machine
#' precision, independent of n_grid.
#' @noRd
.theta_surface_axis <- function(min_v, max_v, anchor, n) {
  d <- (max_v - min_v) / (n - 1L)
  if (!is.finite(d) || d <= 0) d <- 0.05 / (n - 1L)
  k_min <- floor((min_v - anchor) / d)
  grid <- anchor + d * (k_min + (0:(n - 1L)))
  list(grid = grid, d = d)
}

#' Nearest-lattice-index bin assignment; NA (dropped) when outside the lattice
#' @noRd
.theta_surface_bin_index <- function(x, grid, d) {
  idx <- round((x - grid[1]) / d) + 1L
  idx[idx < 1L | idx > length(grid)] <- NA_integer_
  idx
}

#' Accumulate weighted record counts into an ny x nx mass matrix
#' @noRd
.theta_surface_accumulate <- function(i_idx, j_idx, w, ny, nx) {
  mass <- numeric(ny * nx)
  if (length(i_idx) == 0L) {
    return(matrix(mass, ny, nx))
  }
  lin <- (j_idx - 1L) * ny + i_idx
  rs <- rowsum(w, lin)
  mass[as.integer(rownames(rs))] <- rs[, 1L]
  matrix(mass, ny, nx)
}

#' Translation-invariant geo (x lat-factor) kernel image, offsets
#' di in -(ny-1):(ny-1), dj in -(nx-1):(nx-1)
#' @noRd
.theta_surface_kernel <- function(lat_grid, lon_grid, site_lat, lambda_km, lambda_latitude) {
  ny <- length(lat_grid)
  nx <- length(lon_grid)
  dlat <- lat_grid[2] - lat_grid[1]
  dlon <- lon_grid[2] - lon_grid[1]
  di <- ((-(ny - 1L)):(ny - 1L)) * dlat
  dj <- ((-(nx - 1L)):(nx - 1L)) * dlon
  delta_lat <- matrix(di, nrow = 2L * ny - 1L, ncol = 2L * nx - 1L)
  delta_lon <- matrix(dj, nrow = 2L * ny - 1L, ncol = 2L * nx - 1L, byrow = TRUE)
  d_km <- 111 * sqrt(delta_lat^2 + (delta_lon * cos(site_lat * pi / 180))^2)
  K <- exp(-d_km / lambda_km)
  if (!is.null(lambda_latitude)) {
    K <- K * exp(-111 * abs(delta_lat) / lambda_latitude)
  }
  K
}

#' 2-D linear convolution via zero-padded FFT (avoids circular wraparound);
#' returns the ny x nx region aligned with the original mass lattice.
#' @noRd
.theta_surface_fft_convolve <- function(mass, kernel) {
  ny <- nrow(mass)
  nx <- ncol(mass)
  ky <- nrow(kernel)
  kx <- ncol(kernel)
  Nr <- stats::nextn(ny + ky - 1L)
  Nc <- stats::nextn(nx + kx - 1L)
  Mpad <- matrix(0, Nr, Nc)
  Mpad[seq_len(ny), seq_len(nx)] <- mass
  Kpad <- matrix(0, Nr, Nc)
  Kpad[seq_len(ky), seq_len(kx)] <- kernel
  Cfull <- Re(stats::fft(stats::fft(Mpad) * stats::fft(Kpad), inverse = TRUE)) / (Nr * Nc)
  Cfull[ny:(2L * ny - 1L), nx:(2L * nx - 1L)]
}

#' Convolve ONE kernel against several mass images, forward-transforming the
#' kernel only once (not once per mass image) -- the difference between
#' O(taxa) and O(1) kernel FFTs when surfacing several species at once.
#' Mathematically identical to calling .theta_surface_fft_convolve() once per
#' mass image; kept as a separate code path purely for that shared-FFT saving.
#' @noRd
.theta_surface_fft_convolve_batch <- function(mass_list, kernel) {
  ny <- nrow(mass_list[[1L]])
  nx <- ncol(mass_list[[1L]])
  ky <- nrow(kernel)
  kx <- ncol(kernel)
  Nr <- stats::nextn(ny + ky - 1L)
  Nc <- stats::nextn(nx + kx - 1L)
  Kpad <- matrix(0, Nr, Nc)
  Kpad[seq_len(ky), seq_len(kx)] <- kernel
  Kfft <- stats::fft(Kpad)
  lapply(mass_list, function(mass) {
    Mpad <- matrix(0, Nr, Nc)
    Mpad[seq_len(ny), seq_len(nx)] <- mass
    Cfull <- Re(stats::fft(stats::fft(Mpad) * Kfft, inverse = TRUE)) / (Nr * Nc)
    Cfull[ny:(2L * ny - 1L), nx:(2L * nx - 1L)]
  })
}

# ==============================================================================
# Plotting
# ==============================================================================

#' One-line statement of the CONDITIONS the surface is drawn under
#'
#' The map is a habitat-stratified, optionally covariate-conditioned field.
#' Both are analyst choices rather than properties of the geography, and
#' neither is recoverable from the picture -- so both are rendered onto the
#' plot itself, not merely messaged at construction. A console message is gone
#' the moment the object is re-printed or the map is screenshotted into a talk;
#' that is the same lesson as the stale-map trap fixed in
#' print.taxaexpect_theta_surface() (2026-09-01 click-through).
#'
#' The three states are deliberately DISTINCT, because the middle one is the
#' trap: a fit that HAS a covariate but is drawn without it must say so
#' affirmatively. Rendering that case as absence would read exactly like "this
#' model has no covariate" -- a different, and false, claim.
#'
#' lambda_km and m are deliberately EXCLUDED. They set how smooth the surface
#' is, not what it is a surface OF, and no reader retunes them from the map;
#' they stay in print.taxaexpect_theta_surface() where there is room for them.
#' @noRd
.theta_surface_condition_label <- function(params) {
  hab_col <- if (is.null(params$habitat_col)) "habitat" else params$habitat_col
  parts <- sprintf("%s: %s", hab_col, params$site_habitat)
  if (!is.null(params$covariate_col)) {
    parts <- c(parts, if (is.null(params$covariate_at)) {
      sprintf(
        "%s: OMITTED (not a %s-conditioned field)",
        params$covariate_col, params$covariate_col
      )
    } else {
      sprintf(
        "%s = %s (held constant)", params$covariate_col,
        format(params$covariate_at, trim = TRUE)
      )
    })
  }
  paste(parts, collapse = "   |   ")
}

#' Static base-graphics rendering
#' @noRd
.theta_surface_plot_static <- function(surf, site_lat, site_lon, alpha_by_n_eff, n_eff_floor, ...) {
  theta <- if (is.list(surf$theta)) surf$theta else stats::setNames(list(surf$theta), "1")
  n_panel <- length(theta)
  old_par <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old_par), add = TRUE)
  if (n_panel > 1L) {
    ncol_p <- ceiling(sqrt(n_panel))
    nrow_p <- ceiling(n_panel / ncol_p)
    graphics::par(mfrow = c(nrow_p, ncol_p))
  }
  for (nm in names(theta)) {
    ras <- .theta_surface_raster(theta[[nm]], surf$n_eff, alpha_by_n_eff, n_eff_floor)
    graphics::plot.new()
    graphics::plot.window(xlim = range(surf$lon_grid), ylim = range(surf$lat_grid), asp = 1)
    graphics::rasterImage(
      ras, min(surf$lon_grid), min(surf$lat_grid),
      max(surf$lon_grid), max(surf$lat_grid)
    )
    graphics::points(site_lon, site_lat, pch = 4, lwd = 2, col = "black")
    graphics::axis(1)
    graphics::axis(2)
    graphics::box()
    graphics::title(main = if (is.list(surf$theta)) nm else "theta", xlab = "lon", ylab = "lat", ...)
    graphics::mtext(.theta_surface_condition_label(surf$params),
      side = 3,
      line = 0.25, cex = 0.7, col = "grey25"
    )
  }
  invisible(NULL)
}

#' Build an RGBA raster (grDevices::as.raster) from a theta matrix, fading/
#' masking by n_eff exactly as alpha_by_n_eff / n_eff_floor specify.
#' @noRd
.theta_surface_raster <- function(theta_mat, n_eff_mat, alpha_by_n_eff, n_eff_floor) {
  pal <- grDevices::colorRampPalette(c("#fffde7", "#fee090", "#fc8d59", "#d73027", "#7f0000"))(256)
  pal_rgb <- grDevices::col2rgb(pal)
  rng <- range(theta_mat, na.rm = TRUE)
  if (diff(rng) == 0) rng <- c(0, max(rng, 1e-9))
  idx <- pmin(256L, pmax(1L, round((theta_mat - rng[1]) / diff(rng) * 255) + 1L))
  # NA cells (outside a `mask`, or a species absent from a masked region)
  # must render as fully transparent background rather than reaching
  # grDevices::rgb(), which errors on an NA colour index.
  na_cell <- is.na(as.numeric(theta_mat))
  idx[na_cell] <- 1L
  alpha <- rep(1, length(theta_mat))
  if (isTRUE(alpha_by_n_eff)) {
    ref <- max(n_eff_mat, na.rm = TRUE)
    if (ref > 0) alpha <- pmin(1, sqrt(as.numeric(n_eff_mat) / ref))
  }
  if (!is.null(n_eff_floor)) alpha[as.numeric(n_eff_mat) < n_eff_floor] <- 0
  alpha[na_cell] <- 0
  alpha[is.na(alpha)] <- 0
  rgba_vec <- grDevices::rgb(pal_rgb[1, idx], pal_rgb[2, idx], pal_rgb[3, idx],
    alpha * 255,
    maxColorValue = 255
  )
  rgba <- matrix(rgba_vec, nrow(theta_mat), ncol(theta_mat))
  # rasterImage expects row 1 = top of image (north); lat_grid is ascending
  # south-to-north, so flip rows.
  grDevices::as.raster(rgba[rev(seq_len(nrow(rgba))), , drop = FALSE])
}

#' Interactive leaflet overlay -- guarded by requireNamespace("leaflet"),
#' the same pattern this package's other leaflet-based renderers use.
#' Renders at a capped resolution (the returned $surface stays at full
#' n_grid) since a leaflet map with
#' n_grid^2 rectangles is impractical in a browser.
#'
#' User-feedback round 2026-09-01 (first real click-through, GreatLakes):
#' (1) the default pin marker covered the heat map exactly where the reader
#' most needs it -- replaced with a small hollow circle; (2) no legend --
#' added, per species and group-tied so it follows the layer selector;
#' (3) no values on hover -- rectangles now carry a label with theta and the
#' local effective sample size; (4) species selection is now a RADIO
#' selector (baseGroups: one species at a time) rather than independent
#' overlay checkboxes that stack unreadably.
#' @noRd
.theta_surface_plot_leaflet <- function(surf, site_lat, site_lon, site_id,
                                        alpha_by_n_eff, n_eff_floor,
                                        site_marker_radius = 5,
                                        hover_labels = TRUE, ...) {
  if (!requireNamespace("leaflet", quietly = TRUE)) {
    stop("plot_theta_surface: package 'leaflet' is required for interactive = TRUE. Install with: install.packages('leaflet')")
  }
  theta <- if (is.list(surf$theta)) surf$theta else stats::setNames(list(surf$theta), "1")
  max_dim <- 80L
  ds <- .theta_surface_downsample(surf, max_dim)
  cell_hw_lat <- (ds$lat_grid[2] - ds$lat_grid[1]) / 2
  cell_hw_lon <- (ds$lon_grid[2] - ds$lon_grid[1]) / 2
  lat_v <- rep(ds$lat_grid, times = length(ds$lon_grid))
  lon_v <- rep(ds$lon_grid, each = length(ds$lat_grid))

  map <- leaflet::leaflet() |> leaflet::addProviderTiles("Esri.OceanBasemap")

  nms <- names(theta)
  for (nm in nms) {
    th_ds <- .theta_surface_downsample_matrix(theta[[nm]], surf, ds)
    n_eff_ds <- .theta_surface_downsample_matrix(surf$n_eff, surf, ds)
    th_v <- as.vector(th_ds)
    ne_v <- as.vector(n_eff_ds)
    pal <- leaflet::colorNumeric("YlOrRd",
      domain = range(th_v, na.rm = TRUE),
      na.color = "transparent"
    )
    opac <- rep(0.7, length(th_v))
    if (isTRUE(alpha_by_n_eff)) {
      ref <- max(ne_v, na.rm = TRUE)
      opac <- if (ref > 0) 0.7 * pmin(1, sqrt(ne_v / ref)) else opac
    }
    if (!is.null(n_eff_floor)) opac[ne_v < n_eff_floor] <- 0
    labs <- NULL
    if (isTRUE(hover_labels)) {
      labs <- sprintf("%s\ntheta = %.3g\nn_eff = %.0f", nm, th_v, ne_v)
      labs[is.na(th_v)] <- NA_character_
      labs <- lapply(labs, function(x) if (is.na(x)) NULL else htmltools::HTML(gsub("\n", "<br/>", x)))
    }
    map <- leaflet::addRectangles(
      map,
      lng1 = lon_v - cell_hw_lon, lat1 = lat_v - cell_hw_lat,
      lng2 = lon_v + cell_hw_lon, lat2 = lat_v + cell_hw_lat,
      fillColor = pal(th_v), fillOpacity = opac, stroke = FALSE,
      label = labs, group = nm, ...
    )
    # Legend per species, tied to the same group so the radio selector
    # swaps the legend along with the surface.
    map <- leaflet::addLegend(
      map,
      position = "bottomright", pal = pal, values = th_v,
      title = sprintf("theta<br/><span class='taxa-legend-tag' data-group=\"%s\" style='font-weight:normal'>%s</span>", nm, nm),
      opacity = 0.7, group = nm, na.label = "masked/absent"
    )
  }

  # Site marker LAST so it draws above the surface, and small + hollow so it
  # never hides the cell it marks (2026-09-01 user feedback).
  map <- leaflet::addCircleMarkers(
    map,
    lng = site_lon, lat = site_lat,
    radius = site_marker_radius, stroke = TRUE, weight = 2,
    color = "#1a1a1a", opacity = 1, fill = FALSE,
    label = htmltools::HTML(sprintf("site: %s", site_id))
  )

  if (length(theta) > 1L) {
    map <- leaflet::addLayersControl(
      map,
      baseGroups = nms,
      options = leaflet::layersControlOptions(collapsed = length(nms) > 6L)
    )
    # Legend/base-group sync. leaflet's own addLegend(group=) binding follows
    # OVERLAY toggles only -- with baseGroups (the radio selector this map
    # wants, so surfaces never stack) every species' legend stays visible at
    # once, which is what the first real click-through showed (three legends
    # stacked down the right edge). Verified in a real browser, not inferred.
    # Each legend title carries a data-group tag; this handler shows only the
    # active one and re-syncs on every baselayerchange. hideGroup() is
    # deliberately NOT used: Leaflet already guarantees base-group
    # exclusivity, and hiding them fights its own bookkeeping.
    if (requireNamespace("htmlwidgets", quietly = TRUE)) {
      first <- gsub('"', '\\\\"', nms[1L], fixed = TRUE)
      js <- sprintf(
        "function(el, x) { var sync = function(name) { var tags = el.querySelectorAll('.taxa-legend-tag'); for (var i = 0; i < tags.length; i++) { var leg = tags[i].closest('.legend'); if (leg) { leg.style.display = (tags[i].getAttribute('data-group') === name) ? '' : 'none'; } } }; sync(\"%s\"); this.on('baselayerchange', function(e) { sync(e.name); }); }",
        first
      )
      map <- htmlwidgets::onRender(map, js)
    }
  }

  # The layers control names the TAXON; nothing else on the widget says which
  # habitat stratum or covariate slice is being shown, and a screenshot of the
  # map carries no console message with it. bottomleft keeps clear of the
  # layers control (topright) and the legend (bottomright).
  map <- leaflet::addControl(
    map,
    html = sprintf(
      "<div style='background:rgba(255,255,255,0.85);padding:3px 6px;border-radius:3px;font:11px/1.4 sans-serif;color:#333'>%s</div>",
      htmltools::htmlEscape(.theta_surface_condition_label(surf$params))
    ),
    position = "bottomleft"
  )
  map
}

#' Downsampled lattice coordinates (stride subsetting) for leaflet rendering
#' @noRd
.theta_surface_downsample <- function(surf, max_dim) {
  ny <- length(surf$lat_grid)
  nx <- length(surf$lon_grid)
  i_keep <- unique(round(seq(1, ny, length.out = min(max_dim, ny))))
  j_keep <- unique(round(seq(1, nx, length.out = min(max_dim, nx))))
  list(
    lat_grid = surf$lat_grid[i_keep], lon_grid = surf$lon_grid[j_keep],
    i_keep = i_keep, j_keep = j_keep
  )
}

#' Apply a previously-computed downsample index to another matrix on the same lattice
#' @noRd
.theta_surface_downsample_matrix <- function(mat, surf, ds) {
  mat[ds$i_keep, ds$j_keep, drop = FALSE]
}

#' Convert a WKT POLYGON/MULTIPOLYGON string to lon/lat polygon matrices
#'
#' Uses `sf` when available, which handles interior rings (holes) and
#' multipart geometry correctly. Without `sf`, falls back to a
#' dependency-free parse that is only safe for a single-ring polygon --
#' the hand-drawn search-polygon case -- and refuses anything more complex
#' rather than silently filling in a hole.
#' @noRd
.theta_surface_wkt_to_polys <- function(wkt) {
  if (length(wkt) != 1L || is.na(wkt) || !nzchar(trimws(wkt))) {
    stop("plot_theta_surface: 'mask' given as text must be a single non-empty WKT POLYGON string.")
  }
  if (!grepl("POLYGON", wkt, ignore.case = TRUE)) {
    stop("plot_theta_surface: 'mask' given as text must be a WKT POLYGON or MULTIPOLYGON string.")
  }

  if (requireNamespace("sf", quietly = TRUE)) {
    geom <- tryCatch(sf::st_sfc(sf::st_as_sfc(wkt), crs = 4326),
      error = function(e) {
        stop(sprintf(
          "plot_theta_surface: could not parse 'mask' as WKT: %s",
          conditionMessage(e)
        ), call. = FALSE)
      }
    )
    return(geom)
  }

  rings <- regmatches(wkt, gregexpr("\\(([^()]*)\\)", wkt))[[1L]]
  if (length(rings) == 0L) {
    stop("plot_theta_surface: 'mask' WKT contained no coordinate ring.")
  }
  if (length(rings) > 1L) {
    stop(paste0(
      "plot_theta_surface: this 'mask' WKT has ", length(rings),
      " rings (a hole or a multipart polygon), which cannot be handled ",
      "without the 'sf' package -- treating them as separate outer ",
      "rings would fill in the holes. Install sf, or pass a two-column ",
      "lon/lat matrix."
    ))
  }

  coords <- gsub("^\\(|\\)$", "", rings[[1L]])
  pairs <- strsplit(trimws(strsplit(coords, ",")[[1L]]), "[[:space:]]+")
  ok <- vapply(pairs, length, integer(1L)) >= 2L
  if (!any(ok)) {
    stop("plot_theta_surface: 'mask' WKT ring had no parseable lon/lat pairs.")
  }
  m <- do.call(rbind, lapply(pairs[ok], function(p) as.numeric(p[1:2])))
  if (anyNA(m)) {
    stop("plot_theta_surface: 'mask' WKT contained non-numeric coordinates.")
  }
  # WKT is lon-first, which is the orientation the matrix branch expects.
  list(m)
}

#' Point-in-polygon mask for a theta surface
#'
#' `mask` is deliberately a PARAMETER, not built-in geometry: the right mask
#' (a lake outline, a bay, a survey boundary) is application-specific, and a
#' package-level default would be wrong for most deployments. Cells whose
#' centres fall outside the mask become `NA` in every surface matrix, so they
#' render transparent and drop out of summaries alike.
#'
#' Accepts a WKT `POLYGON`/`MULTIPOLYGON` string, an `sf`/`sfc` polygon (when
#' `sf` is installed), or a plain two-column lon/lat matrix/data frame -- or a
#' list of such matrices, in which case a cell is kept if it falls inside ANY
#' of them (islands, multi-basin masks).
#' @noRd
.theta_surface_apply_mask <- function(surf, mask) {
  lat_v <- rep(surf$lat_grid, times = length(surf$lon_grid))
  lon_v <- rep(surf$lon_grid, each = length(surf$lat_grid))

  # A WKT POLYGON string is what every workflow in this ecosystem already holds
  # -- TaxaTools::define_search_polygon() returns one, and it is the same object
  # passed to the GBIF fetch. Accepting it here means the map can be clipped to
  # the SAME geometry the records were fetched under, in one argument, instead
  # of the caller hand-converting a string it already has.
  if (is.character(mask)) mask <- .theta_surface_wkt_to_polys(mask)

  if (inherits(mask, c("sf", "sfc"))) {
    if (!requireNamespace("sf", quietly = TRUE)) {
      stop("plot_theta_surface: 'mask' is an sf object but the 'sf' package is not installed. Install sf, or pass a two-column lon/lat matrix instead.")
    }
    crs_use <- tryCatch(sf::st_crs(mask), error = function(e) NA)
    if (is.na(crs_use)) crs_use <- 4326
    pts <- sf::st_as_sf(data.frame(lon = lon_v, lat = lat_v),
      coords = c("lon", "lat"), crs = crs_use
    )
    keep <- lengths(sf::st_intersects(pts, sf::st_union(mask))) > 0L
  } else {
    polys <- if (is.list(mask) && !is.data.frame(mask)) mask else list(mask)
    keep <- rep(FALSE, length(lat_v))
    for (poly in polys) {
      poly <- as.matrix(poly)
      if (!is.numeric(poly) || ncol(poly) < 2L) {
        stop("plot_theta_surface: each 'mask' polygon must be a two-column numeric lon/lat matrix or data frame.")
      }
      keep <- keep | .theta_surface_in_polygon(lon_v, lat_v, poly[, 1L], poly[, 2L])
    }
  }

  drop_mat <- function(mat) {
    mat[!keep] <- NA_real_
    mat
  }
  surf$theta <- if (is.list(surf$theta)) lapply(surf$theta, drop_mat) else drop_mat(surf$theta)
  surf$n_eff <- drop_mat(surf$n_eff)
  surf$W <- drop_mat(surf$W)
  surf$params$masked_cells <- sum(!keep)
  surf
}

#' Vectorised ray-casting point-in-polygon (no spatial dependency)
#' @noRd
.theta_surface_in_polygon <- function(x, y, poly_x, poly_y) {
  n <- length(poly_x)
  if (n < 3L) stop("plot_theta_surface: a 'mask' polygon needs at least 3 vertices.")
  inside <- rep(FALSE, length(x))
  j <- n
  for (i in seq_len(n)) {
    yi <- poly_y[i]
    yj <- poly_y[j]
    straddles <- (yi > y) != (yj > y)
    if (any(straddles)) {
      xint <- (poly_x[j] - poly_x[i]) * (y - yi) / (yj - yi) + poly_x[i]
      inside <- xor(inside, straddles & (x < xint))
    }
    j <- i
  }
  inside
}
