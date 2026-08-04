# Internal helpers for resolving `site` parameter and shared utilities


#' Resolve llm_fn default: NULL → TaxaTools::call_api with clear error
#' @noRd
.resolve_llm_fn <- function(llm_fn, caller = "this function") {
  if (!is.null(llm_fn)) return(llm_fn)

  # Check TaxaTools auto-detected provider (set by TaxaTools .onAttach)
  opt <- getOption("TaxaID.llm_fn")
  if (!is.null(opt) && is.function(opt)) return(opt)

  # Fall back to Anthropic if TaxaTools is available
  if (!requireNamespace("TaxaTools", quietly = TRUE)) {
    cli::cli_abort(c(
      "{caller}: {.arg llm_fn} is NULL (default) and TaxaTools is not installed.",
      "i" = "Either install TaxaTools or pass an explicit {.arg llm_fn} argument.",
      "i" = "Install with: {.code devtools::install('<path_to_TaxaTools>')}"
    ))
  }
  TaxaTools::call_api
}


#' Build a "Context:" prompt block from a context list
#'
#' Shared context-formatting logic for LLM prompts. Used identically by
#' `assign_taxa_llm()`'s `.build_taxa_prompt()` and
#' `suggest_unreferenced_species()`'s `.build_plausible_prompt()`/
#' `.build_family_prompt()` -- the three previously duplicated this block
#' verbatim, differing only in which field name in `ctx` holds the habitat
#' value (`"main_habitat"` vs `"habitat"`).
#' @noRd
.build_context_block <- function(ctx, habitat_field = "main_habitat") {
  ctx_fields   <- c("ecoregion", "lat", "lon", "date", habitat_field)
  header_parts <- character(0L)
  for (fld in ctx_fields) {
    v <- ctx[[fld]]
    if (is.null(v) || length(v) != 1L || is.na(v) ||
        !nzchar(trimws(as.character(v))))
      next
    label <- if (fld == habitat_field) {
      "Habitat"
    } else {
      switch(fld, ecoregion = "Ecoregion", lat = "Latitude", lon = "Longitude",
             date = "Date/season", fld)
    }
    header_parts <- c(header_parts, paste0(label, ": ", as.character(v)))
  }
  if (length(header_parts) == 0L) return("")
  paste0("Context:\n", paste0("  ", header_parts, collapse = "\n"), "\n\n")
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

    cli::cli_abort(
      "{.arg site} list must have either (grid_id + main_habitat) or \\
      (lat + lon + main_habitat)."
    )
  }

  # --- Case: data.frame (multi-site) ---
  if (is.data.frame(site)) {

    if (!"observation_id" %in% names(site))
      cli::cli_abort("{.arg site} data frame must have an {.field observation_id} column.")

    # Existing format: already has grid_id + main_habitat
    if (all(c("grid_id", "main_habitat") %in% names(site))) {
      return(site[, c("observation_id", "grid_id", "main_habitat"), drop = FALSE])
    }

    # lat + lon + main_habitat per observation (main_habitat required)
    if (all(c("lat", "lon") %in% names(site))) {
      if (!"main_habitat" %in% names(site)) {
        cli::cli_abort(c(
          "{.arg site} data frame with lat/lon must also include a \\
          {.field main_habitat} column.",
          "i" = "Each row should specify the habitat for that observation's location."
        ))
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

    cli::cli_abort(
      "{.arg site} data frame must have either (grid_id + main_habitat) or \\
      (lat + lon + main_habitat) columns."
    )
  }

  cli::cli_abort(
    "{.arg site} must be a named list (single-site) or a data frame (multi-site)."
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
    cli::cli_warn(
      "Nearest grid cell {.val {nearest_grid}} \\
      ({sprintf('%.1f', nearest_row$grid_lat)}, {sprintf('%.1f', nearest_row$grid_lon)}) \\
      is {sprintf('%.1f', dist_deg)} degrees from provided coordinates \\
      ({sprintf('%.1f', lat)}, {sprintf('%.1f', lon)}). Priors may not be relevant."
    )
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

  hint_str <- sprintf(
    "site = list(lat = %.2f, lon = %.2f, main_habitat = \"...\")", lat, lon
  )

  if (is.null(main_habitat)) {
    cli::cli_abort(c(
      "{.arg main_habitat} is required. Available habitats at {nearest_grid}:",
      " " = counts_str,
      "i" = "Specify via: {.code {hint_str}}"
    ))
  }

  if (!main_habitat %in% available) {
    cli::cli_abort(c(
      "{.arg main_habitat} {.val {main_habitat}} not found at {nearest_grid}.",
      "i" = "Available habitats:",
      " " = counts_str,
      "i" = "Specify one of the above via: {.code {hint_str}}"
    ))
  }

  resolved_habitat <- main_habitat

  cli::cli_inform(
    "  Site ({sprintf('%.2f', lat)}, {sprintf('%.2f', lon)}) -> grid \\
    {.val {nearest_grid}}, habitat {.val {resolved_habitat}}."
  )

  list(grid_id = nearest_grid, main_habitat = resolved_habitat)
}
