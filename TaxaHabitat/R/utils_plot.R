# ==============================================================================
# Shared internal helpers for plot and review functions
#
# Used by:
#   plot_habitat_points_interactive()
#   select_habitat_outliers()
#   review_spatial_flags()
#
# None of these functions are exported.
# ==============================================================================


#' Build deduplicated point-level summary from occurrence data
#'
#' Reduces a full occurrence dataframe to one row per \code{point_id x habitat}
#' combination. Generates a synthetic \code{point_id} from rounded coordinates
#' if the column is absent. Optionally aggregates a species label string per
#' point for use in popups and tooltips.
#'
#' @param data Occurrence dataframe.
#' @param habitat_col,lat_col,lon_col Column name strings.
#' @param taxon_col Character column name for taxon labels, or \code{NULL}.
#' @param max_species Integer. Maximum species to list before truncating with
#'   "... and N more". Default \code{10L}.
#' @return A dataframe with columns \code{point_id}, \code{lon}, \code{lat},
#'   \code{habitat}, and optionally \code{spp_label}.
#' @noRd

.build_habitat_pts <- function(data, habitat_col, lat_col, lon_col,
                                taxon_col, max_species = 10L) {

  pts <- data.frame(
    lon     = as.numeric(data[[lon_col]]),
    lat     = as.numeric(data[[lat_col]]),
    habitat = as.character(data[[habitat_col]]),
    stringsAsFactors = FALSE
  )

  # Use existing point_id or synthesise from rounded coordinates
  if ("point_id" %in% names(data)) {
    pts$point_id <- as.character(data[["point_id"]])
  } else {
    pts$point_id <- paste0(round(pts$lon, 6L), "_", round(pts$lat, 6L))
  }

  if (!is.null(taxon_col) && taxon_col %in% names(data)) {
    pts$taxon <- as.character(data[[taxon_col]])
  }

  # Drop incomplete rows
  keep <- !is.na(pts$lon)     & !is.na(pts$lat)  &
          !is.na(pts$habitat) & nzchar(pts$habitat) &
          !is.na(pts$point_id)
  pts  <- pts[keep, ]

  if (nrow(pts) == 0L) return(pts)

  # Aggregate species per point_id before deduplication
  if (!is.null(taxon_col) && "taxon" %in% names(pts)) {
    spp_by_point <- tapply(
      pts$taxon,
      pts$point_id,
      function(x) {
        spp <- sort(unique(x[!is.na(x) & nzchar(x)]))
        if (length(spp) == 0L) return("(none)")
        if (length(spp) > max_species) {
          paste0(
            paste(spp[seq_len(max_species)], collapse = ", "),
            sprintf(" ... and %d more", length(spp) - max_species)
          )
        } else {
          paste(spp, collapse = ", ")
        }
      }
    )
    pts$spp_label <- spp_by_point[pts$point_id]
  }

  # Deduplicate to one row per point_id x habitat
  pts <- pts[!duplicated(pts[, c("point_id", "habitat")]), ]

  pts
}


#' Assign colours to habitat levels
#'
#' Returns a named character vector mapping each habitat label to a hex colour.
#' Uses a 12-colour ecological palette for up to 12 habitats; falls back to
#' \code{grDevices::rainbow} for larger sets. A user-supplied \code{colors}
#' vector takes priority; any habitats not covered receive \code{"#aaaaaa"}
#' with a warning.
#'
#' @param hab_levels Character vector of sorted unique habitat names.
#' @param colors Named character vector of user-supplied colours, or
#'   \code{NULL}.
#' @return Named character vector, same length as \code{hab_levels}.
#' @noRd

.habitat_palette <- function(hab_levels, colors = NULL) {

  n_hab <- length(hab_levels)

  if (!is.null(colors)) {
    missing_hab <- setdiff(hab_levels, names(colors))
    if (length(missing_hab) > 0L) {
      warning(
        ".habitat_palette: the following habitats are not in the user-supplied ",
        "'colors' vector and will be shown in grey: ",
        paste(missing_hab, collapse = ", "),
        call. = FALSE
      )
      extra  <- stats::setNames(rep("#aaaaaa", length(missing_hab)), missing_hab)
      colors <- c(colors, extra)
    }
    return(colors[hab_levels])
  }

  # Default 12-colour ecological palette
  eco_pal <- c(
    "#2166ac",  # deep blue      -- Marine
    "#74add1",  # mid blue       -- Marine Neritic / Freshwater
    "#4dac26",  # green          -- Terrestrial / Forest
    "#d6604d",  # terracotta     -- Rocky / Arid
    "#8073ac",  # purple         -- Subterranean / Cave
    "#f4a582",  # peach          -- Estuarine / Coastal
    "#1b7837",  # dark green     -- Woodland / Savanna
    "#bf812d",  # brown          -- Grassland / Desert
    "#35978f",  # teal           -- Wetlands
    "#de77ae",  # pink           -- Artificial
    "#fdbf6f",  # amber          -- Introduced Vegetation
    "#969696"   # grey           -- Other / Unknown
  )

  if (n_hab <= length(eco_pal)) {
    pal <- stats::setNames(eco_pal[seq_len(n_hab)], hab_levels)
  } else {
    pal <- stats::setNames(
      grDevices::rainbow(n_hab, s = 0.7, v = 0.85),
      hab_levels
    )
  }

  pal
}


#' Lightweight HTML escaping
#'
#' Escapes \code{&}, \code{<}, \code{>}, and \code{"} for safe embedding in
#' Leaflet popup and tooltip HTML strings.
#'
#' @param x Character vector.
#' @return Character vector of the same length.
#' @noRd

.he <- function(x) {
  x <- gsub("&",  "&amp;",  as.character(x), fixed = TRUE)
  x <- gsub("<",  "&lt;",   x,               fixed = TRUE)
  x <- gsub(">",  "&gt;",   x,               fixed = TRUE)
  x <- gsub("\"", "&quot;", x,               fixed = TRUE)
  x
}
