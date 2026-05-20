# ==============================================================================
#' Flag Spatially Inconsistent Habitat Assignments
#'
#' For each unique occurrence point, derives the physical spatial zone (inland,
#' coastal, marine shallow, marine deep, marine abyssal) using vector land
#' polygons for land/ocean classification and NOAA bathymetry for ocean depth,
#' then compares that zone against the species-based IUCN habitat assignment.
#' Points whose physical location is implausible given their assigned habitat
#' are flagged for user review.
#'
#' The most common error this function catches is a marine species assigned
#' a marine habitat but located far inland -- a GBIF georeferencing error.
#' Terrestrial species appearing in the ocean are also flagged.
#'
#' The function adds four columns to the input dataframe, repeated for every
#' row sharing the same location, so the dataframe structure and row count are
#' unchanged. The augmented object can be passed directly to
#' \code{plot_habitat_points_interactive(flag_col = "spatial_flag")} for
#' visual review, and filtered numerically using \code{dist_to_coast_km} and
#' \code{elevation_m} before passing to \code{select_habitat_outliers()}.
#'
#' @section Physical zone classification:
#' Land/ocean classification uses Natural Earth country polygons (vector),
#' which correctly handles enclosed water bodies like bays, estuaries, and
#' inland seas that raster-based approaches misclassify at low resolution.
#' Coastal zone is a buffer around the Natural Earth coastline. Ocean depth
#' for confirmed marine points comes from NOAA GEBCO bathymetry.
#' \describe{
#'   \item{inland}{Inside land polygon and distance to coast >
#'     \code{coast_buffer_m}.}
#'   \item{coastal}{Within \code{coast_buffer_m} of the coastline, on either
#'     side. Captures intertidal and supralittoral zones.}
#'   \item{marine_shallow}{Outside land polygon, outside coastal buffer, ocean
#'     depth 0 to \code{depth_neritic_m} metres.}
#'   \item{marine_deep}{Ocean depth \code{depth_neritic_m} to
#'     \code{depth_oceanic_m} metres.}
#'   \item{marine_abyssal}{Ocean depth > \code{depth_oceanic_m} metres.}
#' }
#'
#' @section Freshwater habitats:
#' Habitats whose IUCN L1 name contains "Wetland", "Aquatic", or "Freshwater"
#' are silently assigned \code{spatial_flag = "likely"} with reason
#' \code{"freshwater habitat not spatially verified"}. This avoids false
#' positives for a common and genuinely hard-to-check class.
#'
#' @param data A dataframe, typically \code{occurrences_with_habitat} from the
#'   TaxaExpect workflow. Must contain latitude, longitude, and habitat columns.
#' @param lat_col Character. Latitude column name. Default
#'   \code{"decimalLatitude"}.
#' @param lon_col Character. Longitude column name. Default
#'   \code{"decimalLongitude"}.
#' @param habitat_col Character. Habitat assignment column name. Default
#'   \code{"main_habitat"}.
#' @param coast_buffer_m Numeric. Buffer distance (metres) around coastlines
#'   for habitat classification. Points within this buffer are not flagged
#'   as marine/freshwater inconsistencies. The 1 km default accounts for GPS
#'   coordinate uncertainty, tidal zones, and coastal habitat gradients.
#'   Default \code{1000}.
#' @param marine_questionable_km Numeric. If greater than zero, marine species
#'   within this distance (km) of the coastline are flagged as
#'   \code{"questionable"} rather than \code{"likely"}, on the grounds that
#'   very nearshore points may warrant visual verification. Default \code{0}
#'   (disabled) -- all marine species in ocean are \code{"likely"} regardless
#'   of distance to shore. Set e.g. \code{0.1} to flag points within 100 m
#'   of the shoreline.
#' @param depth_neritic_m Numeric. Depth threshold (metres) defining the
#'   neritic (continental shelf) zone. Points shallower than this are
#'   classified as nearshore. The 200 m convention follows the standard
#'   oceanographic definition of the continental shelf edge. Default
#'   \code{200}.
#' @param depth_oceanic_m Numeric. Depth threshold (metres) defining the
#'   boundary between bathyal and abyssal zones. Follows the standard
#'   oceanographic depth zonation. Default \code{4000}.
#' @param resolution Integer. Bathymetry resolution in arc-minutes for the
#'   NOAA GEBCO download. Used only for depth classification of confirmed
#'   marine points -- does not affect land/ocean classification. Default
#'   \code{4}.
#' @param verbose Logical. Print progress messages. Default \code{TRUE}.
#' @param habitat_scheme Optional. A \code{habitat_prompt} object or habitat
#'   scheme dataframe used to resolve habitat names for depth/distance checks.
#'   If \code{NULL}, checks rely on the \code{habitat_col} values directly.
#'
#' @return The input \code{data} dataframe with four additional columns:
#' \describe{
#'   \item{elevation_m}{Numeric. GEBCO value at the point: negative values
#'     are ocean depth in metres; positive values are approximate land
#'     elevation. Diagnostic only -- land/ocean classification uses vector
#'     polygons, not this value.}
#'   \item{dist_to_coast_km}{Numeric. Distance in kilometres to the nearest
#'     coastline, rounded to 2 decimal places.}
#'   \item{spatial_flag}{Character. One of \code{"likely"}, \code{"questionable"}, or
#'     \code{"unlikely"}.}
#'   \item{spatial_flag_reason}{Character. Plain-English explanation including
#'     numeric context (e.g. distance inland, depth).}
#' }
#'
#' @seealso \code{plot_habitat_points_interactive()},
#'   \code{select_habitat_outliers()}
#'
#' @importFrom terra rast vect extract
#' @importFrom sf st_as_sf st_transform st_distance st_intersection st_union
#'   st_buffer st_within st_make_valid st_geometry st_as_sfc st_bbox st_crop
#'   sf_use_s2
#' @importFrom marmap getNOAA.bathy as.raster
#' @importFrom rnaturalearth ne_coastline ne_countries
#' @importFrom dplyr left_join
#' @export
#'
#' @examples
#' \dontrun{
#' occurrences_flagged <- flag_habitat_inconsistencies(
#'   occurrences_with_habitat,
#'   coast_buffer_m = 1000
#' )
#'
#' # Review on the map
#' plot_habitat_points_interactive(
#'   dplyr::filter(occurrences_flagged, spatial_flag != "likely"),
#'   flag_col = "spatial_flag",
#'   tile     = "Esri.OceanBasemap"
#' )
#'
#' # Filter numerically
#' likely_errors <- dplyr::filter(
#'   occurrences_flagged,
#'   spatial_flag == "unlikely",
#'   dist_to_coast_km > 5
#' )
#' }

flag_habitat_inconsistencies <- function(
    data,
    lat_col         = "decimalLatitude",
    lon_col         = "decimalLongitude",
    habitat_col     = "main_habitat",
    coast_buffer_m          = 1000,
    marine_questionable_km  = 0,
    depth_neritic_m = 200,
    depth_oceanic_m = 4000,
    resolution      = 4L,
    verbose         = TRUE,
    habitat_scheme  = NULL
) {

  # --------------------------------------------------------------------------
  # 0. Validate inputs
  # --------------------------------------------------------------------------

  for (col in c(lat_col, lon_col, habitat_col)) {
    if (!col %in% names(data)) {
      stop(sprintf("Column '%s' not found in data.", col))
    }
  }

  required_pkgs <- c("marmap", "rnaturalearth", "rnaturalearthdata",
                     "rnaturalearthhires", "sf", "terra")
  missing_pkgs <- required_pkgs[!vapply(required_pkgs, requireNamespace,
                                        logical(1L), quietly = TRUE)]
  if (length(missing_pkgs) > 0L) {
    stop(sprintf(
      "flag_habitat_inconsistencies requires %d package(s) not installed: %s\n  Install with: install.packages(c(%s))",
      length(missing_pkgs),
      paste(missing_pkgs, collapse = ", "),
      paste(sprintf('"%s"', missing_pkgs), collapse = ", ")
    ))
  }

  # --------------------------------------------------------------------------
  # 1. Extract unique coordinate + habitat combinations
  # --------------------------------------------------------------------------

  pts_all <- data.frame(
    lon     = data[[lon_col]],
    lat     = data[[lat_col]],
    habitat = data[[habitat_col]],
    stringsAsFactors = FALSE
  )

  complete_rows <- !is.na(pts_all$lon) & !is.na(pts_all$lat) & !is.na(pts_all$habitat)
  pts_unique    <- unique(pts_all[complete_rows, c("lon", "lat", "habitat")])
  n_pts         <- nrow(pts_unique)

  if (n_pts == 0L) stop("No complete (non-NA) points found.")

  if (verbose) {
    message(sprintf(
      "\n--- flag_habitat_inconsistencies(): %d unique point(s) ---", n_pts
    ))
  }

  # Bounding box with margin
  margin <- 0.5
  xmin   <- min(pts_unique$lon) - margin
  xmax   <- max(pts_unique$lon) + margin
  ymin   <- min(pts_unique$lat) - margin
  ymax   <- max(pts_unique$lat) + margin

  bbox_poly <- sf::st_as_sfc(
    sf::st_bbox(c(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax), crs = 4326L)
  )

  pts_sf <- sf::st_as_sf(pts_unique, coords = c("lon", "lat"), crs = 4326L)

  # Disable S2 spherical geometry for planar buffering operations
  old_s2 <- sf::sf_use_s2()
  suppressMessages(sf::sf_use_s2(FALSE))
  on.exit(suppressMessages(sf::sf_use_s2(old_s2)), add = TRUE)

  # --------------------------------------------------------------------------
  # 2. Land/ocean via vector land polygons
  #    Point-in-polygon is exact -- correctly classifies bays, estuaries, etc.
  # --------------------------------------------------------------------------

  if (verbose) message("  Classifying land/ocean via vector polygons...")

  world_land  <- rnaturalearth::ne_countries(scale = "large", returnclass = "sf")
  world_land  <- sf::st_make_valid(world_land)

  # suppressWarnings: sf emits "assumes planar coordinates" notices for every
  # spatial operation after sf_use_s2(FALSE).  These are expected -- planar
  # mode is intentional here to allow simple buffering.
  land_crop   <- suppressWarnings(tryCatch(
    sf::st_intersection(sf::st_geometry(world_land), bbox_poly),
    error = function(e) sf::st_geometry(world_land)
  ))
  land_union  <- sf::st_make_valid(suppressWarnings(sf::st_union(land_crop)))

  in_land     <- lengths(suppressWarnings(sf::st_within(pts_sf, sf::st_as_sf(data.frame(geometry = land_union))))) > 0L
  pts_unique$on_land <- in_land

  # --------------------------------------------------------------------------
  # 3. Coastal buffer around Natural Earth coastline
  # --------------------------------------------------------------------------

  if (verbose) message("  Building coastal buffer...")

  coast_sf   <- rnaturalearth::ne_coastline(scale = "large", returnclass = "sf")
  coast_crop <- suppressWarnings(tryCatch(
    sf::st_crop(sf::st_make_valid(coast_sf), bbox_poly),
    error = function(e) sf::st_make_valid(coast_sf)
  ))

  # Buffer in metres using projected CRS, then reproject back to WGS84
  coast_merc_buf    <- sf::st_transform(sf::st_geometry(coast_crop), crs = 3857L)
  coast_buffer_geom <- sf::st_make_valid(
    sf::st_union(sf::st_buffer(coast_merc_buf, dist = coast_buffer_m))
  )
  coast_buffer_geom <- sf::st_transform(coast_buffer_geom, crs = 4326L)

  in_coast <- lengths(
    suppressWarnings(sf::st_within(pts_sf, sf::st_as_sf(data.frame(geometry = coast_buffer_geom))))
  ) > 0L
  pts_unique$in_coastal_buffer <- in_coast

  # --------------------------------------------------------------------------
  # 4. Distance to coastline (km)
  # --------------------------------------------------------------------------

  if (verbose) message("  Computing distance to coastline...")

  pts_merc   <- sf::st_transform(pts_sf,     crs = 3857L)
  coast_merc <- sf::st_transform(coast_crop, crs = 3857L)

  dist_m <- sf::st_distance(pts_merc, coast_merc)
  pts_unique$dist_to_coast_km <- round(
    as.numeric(apply(dist_m, 1L, min)) / 1000,
    2L
  )

  # --------------------------------------------------------------------------
  # 5. GEBCO bathymetry: depth for marine zone subdivision + elevation_m column
  # --------------------------------------------------------------------------

  if (verbose) {
    message(sprintf(
      "  Downloading GEBCO bathymetry (resolution = %d arc-min)...", resolution
    ))
  }

  bathy_raw <- tryCatch(
    marmap::getNOAA.bathy(
      lon1 = xmin, lon2 = xmax,
      lat1 = ymin, lat2 = ymax,
      resolution = resolution,
      keep = FALSE
    ),
    error = function(e) {
      warning(sprintf(
        paste0(
          "flag_habitat_inconsistencies: NOAA bathymetry download failed ",
          "(%s). Ocean points will be classified as 'marine_shallow' ",
          "rather than subdivided by depth. ",
          "Re-run when the service is available for full depth classification."
        ),
        conditionMessage(e)
      ), call. = FALSE)
      NULL
    }
  )

  if (!is.null(bathy_raw)) {
    r_elev    <- terra::rast(marmap::as.raster(bathy_raw))
    names(r_elev) <- "elevation_m"
    elev_vals <- terra::extract(r_elev, terra::vect(pts_sf))
    pts_unique$elevation_m <- elev_vals$elevation_m
    if (verbose) message("  Bathymetry download complete.")
  } else {
    # Fallback: set elevation_m to NA for all points.
    # Physical zone classification handles NA depth by defaulting to
    # marine_shallow for confirmed ocean points (see section 6).
    pts_unique$elevation_m <- NA_real_
    if (verbose) {
      message(
        "  Bathymetry unavailable -- ocean points classified as 'marine_shallow'."
      )
    }
  }

  # --------------------------------------------------------------------------
  # 6. Classify physical zone
  #    Land polygon is authoritative for land/ocean.
  #    Coastal buffer overrides (applies to both sides of shoreline).
  #    GEBCO depth used only for marine zone subdivision.
  # --------------------------------------------------------------------------

  pts_unique$physical_zone <- mapply(
    function(on_land, in_coast, elev) {
      if (in_coast) return("coastal")
      if (on_land)  return("inland")
      # Ocean: subdivide by depth
      if (is.na(elev)) return("marine_shallow")
      depth <- abs(elev)
      if      (depth <= depth_neritic_m) "marine_shallow"
      else if (depth <= depth_oceanic_m) "marine_deep"
      else                               "marine_abyssal"
    },
    pts_unique$on_land,
    pts_unique$in_coastal_buffer,
    pts_unique$elevation_m
  )

  # --------------------------------------------------------------------------
  # 7. Classify habitat realm
  # --------------------------------------------------------------------------

  # Resolve scheme: accept habitat_prompt object, named scheme, or NULL (default 3-category)
  scheme <- if (inherits(habitat_scheme, "habitat_prompt")) {
    habitat_scheme$scheme
  } else if (is.null(habitat_scheme)) {
    data.frame(
      l1_name = c("Marine", "Freshwater", "Terrestrial"),
      l2_name = NA_character_,
      l2_code = NA_character_,
      realm   = c("marine", "freshwater", "terrestrial"),
      stringsAsFactors = FALSE
    )
  } else {
    .validate_habitat_scheme(habitat_scheme)
  }

  .realm <- function(hab) {
    hab_lc <- tolower(trimws(hab))

    # If scheme has a realm column, use it first
    if ("realm" %in% names(scheme) && any(!is.na(scheme$realm))) {
      # Try l2_name match, then l1_name match
      idx <- match(hab_lc, tolower(scheme$l2_name))
      if (is.na(idx)) idx <- match(hab_lc, tolower(scheme$l1_name))
      if (!is.na(idx) && !is.na(scheme$realm[idx])) return(scheme$realm[idx])
    }

    # Fall back to name-pattern matching (works for IUCN and sensibly named custom schemes)
    if (grepl("^marine|^ocean|^pelagic|^neritic|^intertidal|^subtidal|^littoral|^reef|^kelp|^seagrass|^estuar",
              hab_lc, perl = TRUE)) return("marine")
    if (grepl("freshwater|wetland|aquatic|lake|river|stream|pond|marsh|bog|fen|riparian",
              hab_lc, perl = TRUE)) return("freshwater")

    # For IUCN scheme, also check .iucn_habitat_lookup
    if (.is_iucn_scheme(scheme)) {
      idx <- match(hab_lc, tolower(.iucn_habitat_lookup$l2_name))
      if (is.na(idx)) idx <- match(hab_lc, tolower(.iucn_habitat_lookup$l1_name))
      if (!is.na(idx)) {
        l1 <- .iucn_habitat_lookup$l1_name[idx]
        if (grepl("^Marine", l1))                                        return("marine")
        if (grepl("Wetland|Aquatic|Freshwater", l1, ignore.case = TRUE)) return("freshwater")
        return("terrestrial")
      }
    }

    return("unknown")
  }

  pts_unique$habitat_realm <- vapply(pts_unique$habitat, .realm, character(1L))

  # --------------------------------------------------------------------------
  # 8. Flag each point
  # --------------------------------------------------------------------------

  flag_results <- mapply(
    function(zone, realm, elev, dist_km, hab) {

      if (realm == "freshwater") {
        return(list(flag = "likely", reason = "freshwater habitat not spatially verified"))
      }

      if (realm == "unknown") {
        return(list(
          flag   = "likely",
          reason = sprintf("habitat '%s' not found in habitat scheme -- skipped", hab)
        ))
      }

      # --- Marine species ---
      if (realm == "marine") {
        if (zone == "inland") {
          return(list(
            flag   = "unlikely",
            reason = sprintf(
              "%s species located inland: %.1f km from coast, elevation %.0f m",
              hab, dist_km, elev
            )
          ))
        }
        if (zone == "coastal") {
          if (marine_questionable_km > 0 && dist_km <= marine_questionable_km) {
            return(list(
              flag   = "questionable",
              reason = sprintf(
                "marine species within %.0f m coastal buffer (%.2f km from coast) -- verify location",
                coast_buffer_m, dist_km
              )
            ))
          }
          return(list(
            flag   = "likely",
            reason = sprintf(
              "marine species in coastal zone (%.2f km from coast)",
              dist_km
            )
          ))
        }
        return(list(
          flag   = "likely",
          reason = sprintf(
            "marine species in %s zone (dist to coast: %.2f km)",
            gsub("_", " ", zone), dist_km
          )
        ))
      }

      # --- Terrestrial species ---
      if (realm == "terrestrial") {
        if (zone %in% c("marine_shallow", "marine_deep", "marine_abyssal")) {
          return(list(
            flag   = "unlikely",
            reason = sprintf(
              "%s species located in ocean: depth %.0f m, %.2f km from coast",
              hab, abs(elev), dist_km
            )
          ))
        }
        if (zone == "coastal") {
          return(list(
            flag   = "questionable",
            reason = sprintf(
              "terrestrial species within coastal buffer (%.2f km from coast)",
              dist_km
            )
          ))
        }
        return(list(flag = "likely", reason = "terrestrial species on land"))
      }

      list(flag = "likely", reason = "no inconsistency detected")
    },
    pts_unique$physical_zone,
    pts_unique$habitat_realm,
    pts_unique$elevation_m,
    pts_unique$dist_to_coast_km,
    pts_unique$habitat,
    SIMPLIFY = FALSE
  )

  pts_unique$spatial_flag        <- vapply(flag_results, `[[`, character(1L), "flag")
  pts_unique$spatial_flag_reason <- vapply(flag_results, `[[`, character(1L), "reason")

  # --------------------------------------------------------------------------
  # 9. Join flag columns back to full dataframe
  # --------------------------------------------------------------------------

  if (verbose) {
    n_err  <- sum(pts_unique$spatial_flag == "unlikely")
    n_susp <- sum(pts_unique$spatial_flag == "questionable")
    n_ok   <- sum(pts_unique$spatial_flag == "likely")
    message(sprintf(
      "  Flagging complete: %d unlikely, %d questionable, %d likely.",
      n_err, n_susp, n_ok
    ))
  }

  pts_join <- pts_unique[, c(
    "lon", "lat",
    "elevation_m", "dist_to_coast_km",
    "spatial_flag", "spatial_flag_reason"
  )]

  data$._lon_ <- data[[lon_col]]
  data$._lat_ <- data[[lat_col]]

  data <- dplyr::left_join(
    data, pts_join,
    by = c("._lon_" = "lon", "._lat_" = "lat")
  )

  data$._lon_ <- NULL
  data$._lat_ <- NULL

  # Rows excluded from flagging (NA habitat or NA coordinates) receive a
  # explicit flag rather than NA, so downstream functions see only valid values.
  na_flag <- is.na(data$spatial_flag)
  if (any(na_flag)) {
    na_hab  <- is.na(data[[habitat_col]])
    na_coord <- is.na(data[[lon_col]]) | is.na(data[[lat_col]])
    data$spatial_flag[na_flag]        <- "likely"
    data$spatial_flag_reason[na_flag] <- ifelse(
      na_coord[na_flag],
      "missing coordinates -- not spatially validated",
      ifelse(
        na_hab[na_flag],
        "missing habitat -- not spatially validated",
        "not spatially validated"
      )
    )
    if (verbose) {
      message(sprintf(
        "  Note: %d row(s) with missing habitat or coordinates assigned spatial_flag = 'likely' (not validated).",
        sum(na_flag)
      ))
    }
  }

  if (verbose) message("--- flag_habitat_inconsistencies() complete ---\n")

  data
}
