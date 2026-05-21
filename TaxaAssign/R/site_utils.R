# Internal helpers for resolving `site` parameter and shared utilities


#' Resolve llm_fn default: NULL → TaxaTools::call_anthropic_api with clear error
#' @noRd
.resolve_llm_fn <- function(llm_fn, caller = "this function") {
  if (!is.null(llm_fn)) return(llm_fn)

  # Check TaxaTools auto-detected provider (set by TaxaTools .onAttach)
  opt <- getOption("TaxaID.llm_fn")
  if (!is.null(opt) && is.function(opt)) return(opt)

  # Fall back to Anthropic if TaxaTools is available
  if (!requireNamespace("TaxaTools", quietly = TRUE)) {
    stop(sprintf(
      "%s: 'llm_fn' is NULL (default) and TaxaTools is not installed.\n",
      caller
    ), "Either install TaxaTools or pass an explicit llm_fn argument.\n",
    "Install with: devtools::install('<path_to_TaxaTools>')",
    call. = FALSE)
  }
  TaxaTools::call_anthropic_api
}


#' Parse grid_id strings back to lat/lon coordinates
#' @noRd
.parse_grid_ids <- function(grid_ids) {
  # Grid_34p1_m119p1 → lat = 34.1, lon = -119.1
  stripped <- sub("^Grid_", "", grid_ids)
  parts <- strsplit(stripped, "_")
  lat_str <- vapply(parts, `[`, character(1L), 1L)
  lon_str <- vapply(parts, `[`, character(1L), 2L)

  parse_coord <- function(s) {
    as.numeric(gsub("p", ".", gsub("^m", "-", s)))
  }

  data.frame(
    grid_id  = grid_ids,
    grid_lat = parse_coord(lat_str),
    grid_lon = parse_coord(lon_str),
    stringsAsFactors = FALSE
  )
}

#' Find nearest grid_id for given lat/lon
#' @noRd
.find_nearest_grid <- function(lat, lon, grid_coords) {
  dist_sq <- (grid_coords$grid_lat - lat)^2 + (grid_coords$grid_lon - lon)^2
  grid_coords$grid_id[which.min(dist_sq)]
}

#' Resolve `site` parameter to a standardized event_meta data frame
#'
#' Accepts multiple formats:
#'   - list(grid_id, main_habitat) — existing single-site
#'   - list(lat, lon) — auto-derive grid_id + auto-select best habitat from priors
#'   - list(lat, lon, main_habitat) — auto-derive grid_id, use specified habitat
#'     (falls back to auto-select if habitat not available at resolved grid)
#'   - data.frame(observation_id, grid_id, main_habitat) — existing multi-site
#'   - data.frame(observation_id, lat, lon) — auto-derive per row
#'   - data.frame(observation_id, lat, lon, main_habitat) — auto-derive with hint
#'
#' @return data.frame with observation_id, grid_id, main_habitat
#' @noRd
.resolve_site <- function(site, observation_ids, taxaexpect_priors) {

  # --- Case: list (single-site) ---

  if (is.list(site) && !is.data.frame(site)) {

    # Existing format: grid_id + main_habitat
    if (all(c("grid_id", "main_habitat") %in% names(site))) {
      return(data.frame(
        observation_id    = observation_ids,
        grid_id      = site$grid_id,
        main_habitat = site$main_habitat,
        stringsAsFactors = FALSE
      ))
    }

    # lat + lon + main_habitat (main_habitat required by .latlon_to_grid)
    if (all(c("lat", "lon") %in% names(site))) {
      resolved <- .latlon_to_grid(
        lat              = site$lat,
        lon              = site$lon,
        main_habitat     = site$main_habitat,  # errors if NULL
        taxaexpect_priors = taxaexpect_priors
      )
      return(data.frame(
        observation_id    = observation_ids,
        grid_id      = resolved$grid_id,
        main_habitat = resolved$main_habitat,
        stringsAsFactors = FALSE
      ))
    }

    stop(
      "site list must have either (grid_id + main_habitat) or (lat + lon + main_habitat).",
      call. = FALSE
    )
  }

  # --- Case: data.frame (multi-site) ---
  if (is.data.frame(site)) {

    if (!"observation_id" %in% names(site))
      stop("site data frame must have a 'observation_id' column.", call. = FALSE)

    # Existing format: already has grid_id + main_habitat
    if (all(c("grid_id", "main_habitat") %in% names(site))) {
      return(site[, c("observation_id", "grid_id", "main_habitat"), drop = FALSE])
    }

    # lat + lon + main_habitat per observation (main_habitat required)
    if (all(c("lat", "lon") %in% names(site))) {
      if (!"main_habitat" %in% names(site)) {
        stop(
          "site data frame with lat/lon must also include a 'main_habitat' column.\n",
          "Each row should specify the habitat for that observation's location.",
          call. = FALSE
        )
      }
      has_habitat <- TRUE
      loc_cols <- c("lat", "lon", "main_habitat")
      unique_locs <- unique(site[, loc_cols, drop = FALSE])
      resolved_list <- lapply(seq_len(nrow(unique_locs)), function(i) {
        .latlon_to_grid(
          lat              = unique_locs$lat[i],
          lon              = unique_locs$lon[i],
          main_habitat     = if (has_habitat) unique_locs$main_habitat[i] else NULL,
          taxaexpect_priors = taxaexpect_priors
        )
      })
      coord_lookup <- unique_locs
      coord_lookup$grid_id <- vapply(resolved_list, `[[`, character(1L), "grid_id")
      coord_lookup$resolved_habitat <- vapply(resolved_list, `[[`, character(1L),
                                              "main_habitat")
      merge_cols <- loc_cols
      site_merge <- site[, c("observation_id", loc_cols), drop = FALSE]
      result <- merge(site_merge, coord_lookup, by = merge_cols)
      result$main_habitat <- result$resolved_habitat
      return(result[, c("observation_id", "grid_id", "main_habitat"), drop = FALSE])
    }

    stop(
      "site data frame must have either (grid_id + main_habitat) or (lat + lon + main_habitat) columns.",
      call. = FALSE
    )
  }

  stop(
    "site must be a named list (single-site) or a data frame (multi-site).",
    call. = FALSE
  )
}


#' Map lat/lon to nearest grid_id + main_habitat from taxaexpect_priors
#'
#' Requires `main_habitat` to be specified. When NULL or not matching any
#' habitat at the resolved grid, stops with an informative error listing
#' available habitats and row counts.
#' @noRd
.latlon_to_grid <- function(lat, lon, main_habitat = NULL, taxaexpect_priors) {

  # Parse all unique grid_ids to coordinates
  all_grids <- unique(taxaexpect_priors$grid_id)
  all_grids <- all_grids[!is.na(all_grids)]
  grid_coords <- .parse_grid_ids(all_grids)

  nearest_grid <- .find_nearest_grid(lat, lon, grid_coords)

  # Distance check: warn if nearest grid is far (> 1 degree)
  nearest_row <- grid_coords[grid_coords$grid_id == nearest_grid, ]
  dist_deg <- sqrt((nearest_row$grid_lat - lat)^2 +
                    (nearest_row$grid_lon - lon)^2)
  if (dist_deg > 1.0) {
    warning(sprintf(
      paste0("Nearest grid cell '%s' (%.1f, %.1f) is %.1f degrees from ",
             "provided coordinates (%.1f, %.1f). Priors may not be relevant."),
      nearest_grid, nearest_row$grid_lat, nearest_row$grid_lon,
      dist_deg, lat, lon
    ), call. = FALSE)
  }

  # Resolve habitat: require user to specify main_habitat

  grid_rows <- taxaexpect_priors[taxaexpect_priors$grid_id == nearest_grid &
                                   !is.na(taxaexpect_priors$main_habitat), ]
  available <- unique(grid_rows$main_habitat)
  habitat_counts <- table(grid_rows$main_habitat)

  # Format row counts for messaging: "Marine (847), Freshwater (356)"
  counts_str <- paste(
    sprintf("  \"%s\" (%d prior rows)", names(habitat_counts),
            as.integer(habitat_counts)),
    collapse = "\n"
  )

  if (is.null(main_habitat)) {
    stop(sprintf(
      paste0("main_habitat is required. Available habitats at %s:\n%s\n",
             "Specify via: site = list(lat = %.2f, lon = %.2f, ",
             "main_habitat = \"...\")"),
      nearest_grid, counts_str, lat, lon
    ), call. = FALSE)
  }

  if (!main_habitat %in% available) {
    stop(sprintf(
      paste0("main_habitat '%s' not found at %s.\n",
             "Available habitats:\n%s\n",
             "Specify one of the above via: site = list(lat = %.2f, ",
             "lon = %.2f, main_habitat = \"...\")"),
      main_habitat, nearest_grid, counts_str, lat, lon
    ), call. = FALSE)
  }

  resolved_habitat <- main_habitat

  message(sprintf("  Site (%.2f, %.2f) -> grid '%s', habitat '%s'.",
                  lat, lon, nearest_grid, resolved_habitat))

  list(grid_id = nearest_grid, main_habitat = resolved_habitat)
}
