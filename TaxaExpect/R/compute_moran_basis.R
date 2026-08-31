#' Compute Moran Eigenvector Basis for Spatial Autocorrelation
#'
#' Constructs a set of Moran eigenvectors (MEM -- Moran's Eigenvector Maps)
#' from a vector of \code{grid_id} strings.  The resulting basis columns can
#' be joined to a model dataframe and included as fixed-effect covariates in
#' \code{\link{train_biodiversity_model}} to capture spatial autocorrelation
#' patterns that are not explained by the habitat and geographic gradient terms.
#'
#' @details
#' The function performs the following steps:
#' \enumerate{
#'   \item Resolve centroid coordinates for \code{grid_ids} -- from
#'     \code{coords} directly when supplied, otherwise by parsing the
#'     TaxaExpect \code{Grid_{lat}p{dec}_{m}{lon}p{dec}} encoding. Passing
#'     \code{coords} is preferred whenever you already have real \code{lat_r}/
#'     \code{lon_r} columns on hand (e.g. straight from
#'     \code{\link{prepare_model_dataframe}}'s output) -- string-round-tripping
#'     through \code{grid_id} is unnecessary work and, at high grid
#'     resolutions, loses precision relative to the source coordinates.
#'   \item Build a binary adjacency matrix \eqn{W} where cells \eqn{i} and
#'     \eqn{j} are neighbours if their Euclidean distance (in degrees) is
#'     greater than zero and less than \code{distance_threshold}. \eqn{W} is
#'     symmetric by construction (a symmetric distance test).
#'   \item Doubly-centre \eqn{W} to form the symmetric Moran operator
#'     \eqn{M = H W H}, where \eqn{H = I - \mathbf{1}\mathbf{1}^T / n}. \eqn{M}
#'     is symmetric because \eqn{W} and \eqn{H} both are -- this is required
#'     for \code{eigen(M, symmetric = TRUE)} below to be valid; a
#'     row-standardised \eqn{W} is asymmetric for any grid with unequal
#'     neighbour counts (i.e. almost any real, non-toroidal grid) and must
#'     not be used here.
#'   \item Extract the \code{k} eigenvectors corresponding to the largest
#'     positive eigenvalues of \eqn{M}.
#'   \item Scale each eigenvector to unit standard deviation.
#' }
#'
#' If \code{distance_threshold} is \code{NULL} (the default), the threshold is
#' inferred automatically as 1.5 times the minimum spacing between unique
#' centroid coordinates -- typically capturing all first-order neighbours on a
#' regular grid.
#'
#' Grid cells that cannot be parsed, or that have no neighbours at the chosen
#' threshold, are dropped with a warning.  If fewer than \code{k} positive
#' eigenvalues exist, \code{k} is silently reduced to the number available.
#'
#' @param grid_ids Character vector of grid cell identifiers following the
#'   TaxaExpect convention \code{"Grid_{lat}p{dec}_{m}{lon}p{dec}"}
#'   (e.g. \code{"Grid_33p1_m118p5"}).  Duplicates are silently removed.
#' @param k Positive integer.  Number of eigenvectors (basis columns) to
#'   return.  Must be less than the number of unique, parseable grid cells.
#'   Default \code{10L}.
#' @param distance_threshold Numeric or \code{NULL}.  Maximum Euclidean
#'   distance (decimal degrees) for two cells to be considered neighbours.
#'   When \code{NULL} (default), inferred automatically from the minimum
#'   coordinate spacing in \code{grid_ids}.
#' @param min_neighbours Positive integer.  Minimum number of neighbours a
#'   cell must have before a warning is issued about potential unreliability
#'   of the spatial basis for that cell.  Default \code{1L}.
#' @param coords Optional data frame with columns \code{grid_id}, \code{lat},
#'   \code{lon} giving each cell's real centroid coordinates directly (e.g.
#'   \code{dplyr::distinct(model_data, grid_id, lat = lat_r, lon = lon_r)}).
#'   When supplied, used in place of parsing \code{grid_ids}' own string
#'   encoding; rows not covering every value in \code{grid_ids} fall back to
#'   string-parsing for the missing ones. Default \code{NULL} (string-parse
#'   every \code{grid_id}, the original behavior).
#'
#' @return A data frame with \code{nrow} equal to the number of parseable,
#'   connected grid cells (which may be less than \code{length(grid_ids)}).
#'   Columns:
#'   \describe{
#'     \item{\code{grid_id}}{Character.  Grid cell identifier.}
#'     \item{\code{B1}, \code{B2}, \ldots, \code{B\{k\}}}{Numeric.
#'       Scaled Moran eigenvectors, ordered from largest to smallest
#'       eigenvalue (i.e. strongest to weakest positive spatial
#'       autocorrelation).}
#'   }
#'
#' @references
#' Dray, S., Legendre, P. and Peres-Neto, P.R. (2006). Spatial modelling: a
#' comprehensive framework for principal coordinate analysis of neighbour
#' matrices (PCNM). \emph{Ecological Modelling}, 196(3--4), 483--493.
#' \doi{10.1016/j.ecolmodel.2006.02.015}
#'
#' Griffith, D.A. and Peres-Neto, P.R. (2006). Spatial modeling in ecology:
#' the flexibility of eigenfunction spatial analyses. \emph{Ecology}, 87(10),
#' 2603--2613. \doi{10.1890/0012-9658(2006)87[2603:SMIETF]2.0.CO;2}
#'
#' @seealso \code{\link{prepare_model_dataframe}}, \code{\link{train_biodiversity_model}}
#'
#' @examples
#' # A small 4x4 regular grid, built the same way create_sites_from_grid()
#' # encodes coordinates into grid_id strings.
#' lat_seq  <- seq(33.0, 34.5, by = 0.5)
#' lon_seq  <- seq(-119.5, -118.0, by = 0.5)
#' grid_ids <- as.vector(outer(lat_seq, lon_seq, function(la, lo) {
#'   s <- sprintf("Grid_%.1f_%.1f", la, lo)
#'   s <- gsub("-", "m", s, fixed = TRUE)
#'   gsub(".", "p", s, fixed = TRUE)
#' }))
#' basis <- compute_moran_basis(grid_ids, k = 5L)
#' head(basis)
#'
#' \dontrun{
#' # Real usage: pass known lat_r/lon_r coordinates directly (avoids
#' # re-parsing grid_id's own string encoding) and join the result onto
#' # model data before training.
#' basis <- compute_moran_basis(
#'   grid_ids = unique(model_data$grid_id),
#'   k        = 10L,
#'   coords   = dplyr::distinct(model_data, grid_id, lat = lat_r, lon = lon_r)
#' )
#' model_data <- dplyr::left_join(model_data, basis, by = "grid_id")
#' }
#'
#' @section Deprecated (kernel-priors redesign, 2026-08-31):
#' This function is part of the grid/GLMM prior-fitting path, which is
#' deprecated in favor of site-centered kernel estimation -- see
#' \code{\link{estimate_kernel_priors}} and
#' \code{\link{calibrate_kernel_bandwidth}}. Leave-one-block-out
#' validation on real data found single-cell prediction scored worse than
#' ignoring space entirely, while the kernel estimator improved both
#' composition prediction and downstream assignment precision. The GLMM
#' path remains fully functional (existing workflows still run it) and
#' emits a once-per-session notice; it will be archived once remaining
#' workflows migrate.
#'
#' @export
compute_moran_basis <- function(grid_ids,
                                k                  = 10L,
                                distance_threshold = NULL,
                                min_neighbours     = 1L,
                                coords             = NULL) {

  .glmm_deprecation_notice("compute_moran_basis")

  # --- Input validation -------------------------------------------------------
  if (!is.character(grid_ids) || length(grid_ids) == 0L) {
    stop("compute_moran_basis: 'grid_ids' must be a non-empty character vector.")
  }
  grid_ids <- unique(grid_ids)
  n        <- length(grid_ids)

  if (!is.numeric(k) || length(k) != 1L || k < 1L || k != round(k)) {
    stop("compute_moran_basis: 'k' must be a positive integer.")
  }
  k <- as.integer(k)

  if (k >= n) {
    stop(sprintf(
      "compute_moran_basis: 'k' (%d) must be less than the number of unique grid cells (%d).",
      k, n
    ))
  }

  # --- Resolve coordinates: real coords when supplied, else parse grid_ids ----
  if (!is.null(coords)) {
    if (!is.data.frame(coords) ||
        !all(c("grid_id", "lat", "lon") %in% names(coords))) {
      stop("compute_moran_basis: 'coords' must be a data frame with columns ",
           "grid_id, lat, lon.")
    }
    coord_lookup <- coords[!duplicated(coords$grid_id), ]
    resolved     <- coord_lookup[match(grid_ids, coord_lookup$grid_id), c("lat", "lon")]
    unresolved   <- is.na(resolved$lat) | is.na(resolved$lon)
    if (any(unresolved)) {
      parsed_fallback       <- .parse_grid_id_coords(grid_ids[unresolved])
      resolved[unresolved, ] <- parsed_fallback
    }
    coords <- data.frame(lat = resolved$lat, lon = resolved$lon,
                          stringsAsFactors = FALSE)
  } else {
    coords <- .parse_grid_id_coords(grid_ids)
  }
  unparseable <- is.na(coords$lat) | is.na(coords$lon)

  if (any(unparseable)) {
    bad <- grid_ids[unparseable]
    warning(sprintf(
      "compute_moran_basis: %d grid_id(s) could not be parsed and will be dropped: %s",
      sum(unparseable),
      paste(utils::head(bad, 5L), collapse = ", ")
    ))
    grid_ids <- grid_ids[!unparseable]
    coords   <- coords[!unparseable, ]
    n        <- length(grid_ids)
    if (n < 3L) {
      stop("compute_moran_basis: fewer than 3 parseable grid cells \u2014 cannot compute basis.")
    }
  }

  # --- Infer distance threshold if not supplied --------------------------------
  if (is.null(distance_threshold)) {
    lat_sorted <- sort(unique(round(coords$lat, 4L)))
    if (length(lat_sorted) < 2L) {
      lon_sorted   <- sort(unique(round(coords$lon, 4L)))
      diffs        <- diff(lon_sorted)
    } else {
      diffs        <- diff(lat_sorted)
    }
    pos_diffs    <- diffs[diffs > 1e-6]
    grid_spacing <- if (length(pos_diffs) > 0L) min(pos_diffs) else 1.0
    distance_threshold <- 1.5 * grid_spacing
    message(sprintf(
      "compute_moran_basis: inferred grid spacing %.4f deg; distance threshold set to %.4f deg.",
      grid_spacing, distance_threshold
    ))
  }

  # --- Build binary adjacency matrix ------------------------------------------
  D <- as.matrix(stats::dist(coords[, c("lon", "lat")]))
  W <- (D > 0 & D < distance_threshold) * 1L

  # --- Drop isolated cells ----------------------------------------------------
  n_neighbours <- rowSums(W)
  isolated     <- n_neighbours == 0L

  if (any(isolated)) {
    warning(sprintf(
      "compute_moran_basis: %d grid cell(s) have 0 neighbours at the current threshold (%.4f deg) and will be dropped. Consider increasing distance_threshold.",
      sum(isolated), distance_threshold
    ))
    keep     <- !isolated
    grid_ids <- grid_ids[keep]
    coords   <- coords[keep, ]
    W        <- W[keep, keep]
    n        <- length(grid_ids)
    if (n < 3L) {
      stop("compute_moran_basis: fewer than 3 connected grid cells remain.")
    }
  }

  # --- Warn about sparse cells ------------------------------------------------
  sparse_cells <- n_neighbours[!isolated] < min_neighbours
  if (any(sparse_cells)) {
    message(sprintf(
      "compute_moran_basis: %d cell(s) have fewer than %d neighbour(s). Spatial basis may be unreliable for these cells.",
      sum(sparse_cells), min_neighbours
    ))
  }

  # --- Build doubly-centred Moran operator M = H W H ---------------------------
  # W is already binary and symmetric (built from a symmetric distance test
  # above), which is required for M to be symmetric and for
  # eigen(M, symmetric = TRUE) below to be valid. Do NOT row-standardise W
  # here: row-standardising divides row i by its own neighbour count, which
  # is asymmetric whenever two neighbouring cells have different neighbour
  # counts -- true for essentially any real (non-toroidal, boundary-having)
  # grid. eigen(..., symmetric = TRUE) silently reads only the lower
  # triangle of its input with no warning, so an asymmetric M here would
  # silently produce a wrong basis with no error at all.
  n2         <- nrow(W)
  I          <- diag(n2)
  centering  <- I - matrix(1 / n2, n2, n2)
  M          <- centering %*% W %*% centering

  # --- Eigen decomposition ----------------------------------------------------
  eig     <- eigen(M, symmetric = TRUE)
  pos_idx <- which(eig$values > 1e-8)

  if (length(pos_idx) == 0L) {
    stop("compute_moran_basis: no positive eigenvalues found. Check that grid cells form a connected network.")
  }

  if (k > length(pos_idx)) {
    message(sprintf(
      "compute_moran_basis: only %d positive eigenvector(s) available; reducing k from %d to %d.",
      length(pos_idx), k, length(pos_idx)
    ))
    k <- length(pos_idx)
  }

  # --- Extract and scale eigenvectors -----------------------------------------
  vecs <- eig$vectors[, pos_idx[seq_len(k)], drop = FALSE]
  vecs <- scale(vecs, center = FALSE, scale = apply(vecs, 2, stats::sd))

  # --- Assemble output dataframe ----------------------------------------------
  basis_df          <- as.data.frame(vecs)
  colnames(basis_df) <- paste0("B", seq_len(k))
  basis_df          <- cbind(
    data.frame(grid_id = grid_ids, stringsAsFactors = FALSE),
    basis_df
  )

  message(sprintf(
    "compute_moran_basis: returned %d Moran eigenvectors for %d grid cells.",
    k, n2
  ))

  basis_df
}
