# ---------------------------------------------------------------------------
# Internal helper: parse grid_id strings to lat/lon coordinates
# Format: "Grid_{lat}p{dec}_{m}{lon}p{dec}"
# e.g. "Grid_33p1_m118p5" -> lat = 33.1, lon = -118.5
# ---------------------------------------------------------------------------
.parse_grid_id_basis <- function(grid_ids) {
  parse_one <- function(id) {
    x         <- sub("^Grid_", "", id)
    parts     <- strsplit(x, "_")[[1L]]
    if (length(parts) != 2L) return(c(lat = NA_real_, lon = NA_real_))
    parse_coord <- function(s) {
      neg <- startsWith(s, "m")
      s   <- sub("^m", "", s)
      s   <- gsub("p", ".", s, fixed = TRUE)
      val <- suppressWarnings(as.numeric(s))
      if (neg) -val else val
    }
    c(lat = parse_coord(parts[1L]), lon = parse_coord(parts[2L]))
  }
  result <- lapply(grid_ids, parse_one)
  data.frame(
    lat = vapply(result, `[[`, numeric(1L), "lat"),
    lon = vapply(result, `[[`, numeric(1L), "lon"),
    stringsAsFactors = FALSE
  )
}


#' Compute Moran Eigenvector Basis for Spatial Autocorrelation
#'
#' Constructs a set of Moran eigenvectors (MEM — Moran's Eigenvector Maps)
#' from a vector of \code{grid_id} strings.  The resulting basis columns can
#' be joined to a model dataframe and included as fixed-effect covariates in
#' \code{\link{train_biodiversity_model}} to capture spatial autocorrelation
#' patterns that are not explained by the habitat and geographic gradient terms.
#'
#' @details
#' The function performs the following steps:
#' \enumerate{
#'   \item Parse \code{grid_ids} to centroid coordinates using the TaxaExpect
#'     \code{Grid_{lat}p{dec}_{m}{lon}p{dec}} encoding.
#'   \item Build a binary adjacency matrix \eqn{W} where cells \eqn{i} and
#'     \eqn{j} are neighbours if their Euclidean distance (in degrees) is
#'     greater than zero and less than \code{distance_threshold}.
#'   \item Row-standardise \eqn{W} to \eqn{W^*}.
#'   \item Doubly-centre \eqn{W^*} to form the symmetric Moran operator
#'     \eqn{M = H W^* H}, where \eqn{H = I - \mathbf{1}\mathbf{1}^T / n}.
#'   \item Extract the \code{k} eigenvectors corresponding to the largest
#'     positive eigenvalues of \eqn{M}.
#'   \item Scale each eigenvector to unit standard deviation.
#' }
#'
#' If \code{distance_threshold} is \code{NULL} (the default), the threshold is
#' inferred automatically as 1.5 times the minimum spacing between unique
#' centroid coordinates — typically capturing all first-order neighbours on a
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
#' \dontrun{
#' basis <- compute_moran_basis(
#'   grid_ids = unique(model_data$grid_id),
#'   k        = 10L
#' )
#' # Join to model data before training
#' model_data <- dplyr::left_join(model_data, basis, by = "grid_id")
#' }
#'
#' @export
compute_moran_basis <- function(grid_ids,
                                k                  = 10L,
                                distance_threshold = NULL,
                                min_neighbours     = 1L) {

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

  # --- Parse grid_ids to coordinates ------------------------------------------
  coords      <- .parse_grid_id_basis(grid_ids)
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

  # --- Row-standardise W ------------------------------------------------------
  row_sums <- rowSums(W)
  zero_row <- row_sums == 0
  if (any(zero_row)) {
    warning(sprintf(
      "compute_moran_basis: %d row(s) in neighbour matrix have zero row-sum after isolated-cell removal. Setting to 1 to avoid NaN in row-standardised W.",
      sum(zero_row)
    ), call. = FALSE)
    row_sums[zero_row] <- 1
  }
  W_std    <- W / row_sums

  # --- Build doubly-centred Moran operator M = H W* H -------------------------
  n2         <- nrow(W_std)
  I          <- diag(n2)
  centering  <- I - matrix(1 / n2, n2, n2)
  M          <- centering %*% W_std %*% centering

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
