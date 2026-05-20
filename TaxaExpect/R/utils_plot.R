# ==============================================================================
# Shared internal helpers for plot_theta_map_interactive()
# ==============================================================================


#' Assign colours to habitat levels
#'
#' Returns a named character vector mapping each habitat label to a hex colour.
#' Uses a 12-colour ecological palette for up to 12 habitats; falls back to
#' \code{grDevices::rainbow} for larger sets.
#'
#' @param hab_levels Character vector of sorted unique habitat names.
#' @param colors Named character vector of user-supplied colours, or \code{NULL}.
#' @return Named character vector, same length as \code{hab_levels}.
#' @importFrom stats setNames
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
#' Leaflet popup HTML strings.
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
