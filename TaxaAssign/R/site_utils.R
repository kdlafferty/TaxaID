# Internal helpers for resolving `site` parameter and shared utilities


#' Warn if a user-supplied rank_system disagrees in relative order with
#' TaxaTools::standard_ranks
#'
#' Several functions in this package (`join_priors()`, `posterior_consensus()`,
#' `score_consensus()`) infer coarsest/finest rank from a `rank_system`
#' vector's POSITION (`rank_system[1]` = coarsest, `rank_system[length(...)]`
#' = finest), on the assumption that the caller supplied it already ordered
#' coarse-to-fine. There is no way to fully verify an arbitrary user-supplied
#' vector is correctly ordered (a caller can use non-standard rank names this
#' package has never heard of), but for the common case -- a `rank_system`
#' built from Linnaean rank names TaxaTools already knows about -- this
#' checks that any names shared with `TaxaTools::standard_ranks` appear in
#' the SAME RELATIVE ORDER in both, catching the class of bug where a caller
#' accidentally reverses or otherwise misorders a hand-typed vector (e.g.
#' `c("species", "genus", "family")` instead of
#' `c("family", "genus", "species")`), which would otherwise silently swap
#' "coarsest" and "finest" throughout.
#' @noRd
.check_rank_system_order <- function(rank_system, caller = "this function") {
  if (is.null(rank_system) || length(rank_system) < 2L) {
    return(invisible(NULL))
  }
  if (!requireNamespace("TaxaTools", quietly = TRUE)) {
    return(invisible(NULL))
  }
  known <- intersect(rank_system, TaxaTools::standard_ranks)
  if (length(known) < 2L) {
    return(invisible(NULL))
  }

  pos_in_rank_system <- match(known, rank_system)
  pos_in_standard <- match(known, TaxaTools::standard_ranks)
  if (is.unsorted(pos_in_rank_system[order(pos_in_standard)])) {
    cli::cli_warn(c(
      "{caller}: {.arg rank_system} = {.val {rank_system}} disagrees in \\
      relative order with the standard coarse-to-fine Linnaean ordering \\
      ({.val {TaxaTools::standard_ranks}}) for the rank name(s) it shares \\
      with that ordering.",
      "i" = "Rank-position logic (coarsest/finest) assumes {.arg rank_system} \\
      is ordered coarse-to-fine -- double-check this is intentional."
    ))
  }
  invisible(NULL)
}


#' Beta distribution mean from alpha/beta
#'
#' Duplicated (not shared via a dependency) from `TaxaExpect:::.beta_mean()` --
#' TaxaAssign does not depend on TaxaExpect, and the formula is a one-liner
#' used in only two places in this package (`adjust_inat_range_priors()`), so
#' a cross-package exported utility was not judged worth the coordination
#' cost. See TaxaAssign's code review response for the full reasoning.
#' @param a,b Numeric vectors. Beta shape parameters.
#' @return Numeric vector.
#' @noRd
.beta_mean <- function(a, b) a / (a + b)


#' Resolve llm_fn default: NULL → TaxaTools::call_api with clear error
#'
#' Known footgun (see TaxaID/CLAUDE.md's "Known R Footguns"): TaxaTools'
#' provider auto-detection (`options(TaxaID.llm_fn = ...)`) is set by
#' `TaxaTools::.onAttach()`, which only fires via `library(TaxaTools)` --
#' never via a bare `TaxaTools::` namespace reference. A caller that never
#' explicitly loads TaxaTools (e.g. a fully-namespaced script calling only
#' `TaxaAssign::run_llm_pipeline()`) will find `getOption("TaxaID.llm_fn")`
#' unset here even with a real API key configured, and fall through to the
#' bare `TaxaTools::call_api` below -- which itself has no provider
#' configured either, and (per that package's own documented behavior)
#' degrades to a uniform/degraded fallback rather than erroring loudly. The
#' `cli_warn()` below turns that silent degradation into a visible one at
#' the point it becomes likely, rather than leaving it to surface later as a
#' suspiciously-uniform LLM result with no explanation.
#' @noRd
.resolve_llm_fn <- function(llm_fn, caller = "this function") {
  if (!is.null(llm_fn)) {
    return(llm_fn)
  }

  # Check TaxaTools auto-detected provider (set by TaxaTools .onAttach)
  opt <- getOption("TaxaID.llm_fn")
  if (!is.null(opt) && is.function(opt)) {
    return(opt)
  }

  # Fall back to Anthropic if TaxaTools is available
  if (!requireNamespace("TaxaTools", quietly = TRUE)) {
    cli::cli_abort(c(
      "{caller}: {.arg llm_fn} is NULL (default) and TaxaTools is not installed.",
      "i" = "Either install TaxaTools or pass an explicit {.arg llm_fn} argument.",
      "i" = "Install with: {.code devtools::install('<path_to_TaxaTools>')}"
    ))
  }
  cli::cli_warn(c(
    "{caller}: {.arg llm_fn} is NULL and no LLM provider was auto-detected \\
    ({.code getOption(\"TaxaID.llm_fn\")} is unset).",
    "i" = "This is expected if TaxaTools was never attached via \\
    {.code library(TaxaTools)} -- namespaced calls alone \\
    ({.code TaxaTools::fn()}) do not trigger its provider auto-detection.",
    "i" = "Falling back to bare {.fn TaxaTools::call_api}, which may itself \\
    silently return a degraded/uniform result if it also has no provider \\
    configured. Run {.code library(TaxaTools)} first, or pass an explicit \\
    {.arg llm_fn}, e.g. {.code function(prompt) TaxaTools::call_api(prompt, \\
    provider = \"anthropic\")}."
  ))
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
  ctx_fields <- c("ecoregion", "lat", "lon", "date", habitat_field)
  header_parts <- character(0L)
  for (fld in ctx_fields) {
    v <- ctx[[fld]]
    if (is.null(v) || length(v) != 1L || is.na(v) ||
      !nzchar(trimws(as.character(v)))) {
      next
    }
    label <- if (fld == habitat_field) {
      "Habitat"
    } else {
      switch(fld,
        ecoregion = "Ecoregion",
        lat = "Latitude",
        lon = "Longitude",
        date = "Date/season",
        fld
      )
    }
    header_parts <- c(header_parts, paste0(label, ": ", as.character(v)))
  }
  if (length(header_parts) == 0L) {
    return("")
  }
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
    grid_id = grid_ids,
    grid_lat = parse_coord(lat_str),
    grid_lon = parse_coord(lon_str),
    stringsAsFactors = FALSE
  )
}

#' Find nearest grid_id for given lat/lon
#'
#' Uses an equirectangular (cosine-latitude-corrected) approximation, not
#' raw Euclidean degree distance -- a degree of longitude is shorter than a
#' degree of latitude away from the equator (by a factor of
#' cos(latitude)), so naive Euclidean distance in (lat, lon) degree-space
#' over-weights longitude differences and can select the wrong "nearest"
#' cell, especially at higher latitudes or for grids spanning a wide
#' longitude range relative to latitude. Adequate for selecting among
#' nearby grid cells (not intended as a general-purpose geodesic distance);
#' a full haversine/great-circle formula was judged unnecessary complexity
#' for this use.
#'
#' @return A list with `grid_id` (character) and `dist_deg` (numeric, the
#'   equirectangular-approximated distance in degrees to the nearest cell) --
#'   returning the distance too avoids `.latlon_to_grid()` recomputing the
#'   identical nearest-point calculation a second time just to decide
#'   whether to emit its "far from provided coordinates" warning.
#' @noRd
.find_nearest_grid <- function(lat, lon, grid_coords) {
  lat_scale <- cos(mean(c(lat, grid_coords$grid_lat), na.rm = TRUE) * pi / 180)
  dist_sq <- (grid_coords$grid_lat - lat)^2 +
    ((grid_coords$grid_lon - lon) * lat_scale)^2
  idx <- which.min(dist_sq)
  list(grid_id = grid_coords$grid_id[idx], dist_deg = sqrt(dist_sq[idx]))
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
        observation_id = observation_ids,
        grid_id = site$grid_id,
        main_habitat = site$main_habitat,
        stringsAsFactors = FALSE
      ))
    }

    # lat + lon + main_habitat (main_habitat required by .latlon_to_grid)
    if (all(c("lat", "lon") %in% names(site))) {
      resolved <- .latlon_to_grid(
        lat = site$lat,
        lon = site$lon,
        main_habitat = site$main_habitat, # errors if NULL
        taxaexpect_priors = taxaexpect_priors
      )
      return(data.frame(
        observation_id = observation_ids,
        grid_id = resolved$grid_id,
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
    if (!"observation_id" %in% names(site)) {
      cli::cli_abort("{.arg site} data frame must have an {.field observation_id} column.")
    }

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
          lat = unique_locs$lat[i],
          lon = unique_locs$lon[i],
          main_habitat = if (has_habitat) unique_locs$main_habitat[i] else NULL,
          taxaexpect_priors = taxaexpect_priors
        )
      })
      coord_lookup <- unique_locs
      coord_lookup$grid_id <- vapply(resolved_list, `[[`, character(1L), "grid_id")
      coord_lookup$resolved_habitat <- vapply(
        resolved_list, `[[`, character(1L),
        "main_habitat"
      )
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

  # .find_nearest_grid() already computes the nearest cell's distance
  # internally (to pick the minimum) -- reuse it here instead of
  # recomputing the same calculation a second time.
  nearest <- .find_nearest_grid(lat, lon, grid_coords)
  nearest_grid <- nearest$grid_id
  dist_deg <- nearest$dist_deg

  # Distance check: warn if nearest grid is far (> 1 degree)
  if (dist_deg > 1.0) {
    nearest_row <- grid_coords[grid_coords$grid_id == nearest_grid, ]
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
  if (nrow(grid_rows) == 0L) {
    cli::cli_abort(c(
      "No prior rows with a non-NA {.field main_habitat} exist at the \\
      nearest grid cell {.val {nearest_grid}}.",
      "i" = "Check {.arg taxaexpect_priors} coverage near ({sprintf('%.2f', lat)}, \\
      {sprintf('%.2f', lon)})."
    ))
  }
  available <- unique(grid_rows$main_habitat)
  habitat_counts <- table(grid_rows$main_habitat)

  # Format row counts for messaging: "Marine (847), Freshwater (356)"
  counts_str <- paste(
    sprintf(
      "  \"%s\" (%d prior rows)", names(habitat_counts),
      as.integer(habitat_counts)
    ),
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
