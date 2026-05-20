#' Interactive Theta Heatmap with Occurrence Points
#'
#' Opens a Shiny gadget showing predicted theta (\code{theta_mean}) from
#' \code{priors_combined} as a colour-coded grid heatmap over a zoomable
#' Leaflet basemap, with raw occurrence points overlaid. Taxon is selected via
#' a dropdown; one or more habitats are selected via checkboxes and the map
#' updates reactively.
#'
#' @param priors A dataframe of predicted priors, typically
#'   \code{priors_combined} from \code{generate_undetected_diversity()} or
#'   the output of the modelling pipeline. Must contain columns
#'   \code{taxon_name}, \code{grid_id}, \code{theta_mean}, and the column
#'   named by \code{prior_habitat_col} (default \code{"main_habitat"}).
#' @param occurrences A dataframe of occurrence records with habitat
#'   assignments, typically \code{occurrences_with_habitat}. Must contain
#'   \code{decimalLatitude}, \code{decimalLongitude}, and \code{taxon_name}.
#'   The habitat column to match against is controlled by
#'   \code{occurrence_habitat_col}. Set to \code{NULL} to show no occurrence
#'   points.
#' @param prior_habitat_col Character. Name of the habitat column in
#'   \code{priors}. Default \code{"main_habitat"}.
#' @param occurrence_habitat_col Character. Name of the habitat column in
#'   \code{occurrences}. Default \code{"main_habitat"}. When provided,
#'   occurrence points are coloured by habitat using the shared ecological
#'   palette. Set to \code{NULL} to disable habitat filtering and colouring
#'   (points will use \code{point_color} instead).
#' @param tile Character. Leaflet tile provider. Default
#'   \code{"Esri.OceanBasemap"}. Use \code{"OpenStreetMap"} for terrestrial
#'   datasets or \code{"Esri.WorldImagery"} for satellite imagery.
#' @param theta_col Character. Name of the theta column in \code{priors}.
#'   Default \code{"theta_mean"}.
#' @param grid_opacity Numeric in \[0, 1\]. Opacity of grid cell rectangles.
#'   Default \code{0.7}.
#' @param point_radius Numeric. Radius of occurrence point markers in pixels.
#'   Default \code{4}.
#' @param point_color Character. Fallback colour of occurrence point markers,
#'   used only when \code{occurrence_habitat_col = NULL}. Default
#'   \code{"#ff6600"} (orange). When \code{occurrence_habitat_col} is
#'   provided, points are coloured by habitat via the shared ecological palette
#'   and this argument is ignored.
#'
#' @return \code{NULL} invisibly. The gadget is for exploration only; use
#'   \code{plot_theta_map()} when you need a static exportable figure.
#'
#' @details
#' \strong{grid_id parsing:} Grid cell centroids are derived by parsing the
#' \code{grid_id} string (e.g. \code{"Grid_33p1_m118p5"} -> lat 33.1,
#' lon -118.5). The grid cell size is inferred from the spacing of unique
#' centroid latitudes in the filtered data.
#'
#' \strong{Habitat selection:} All habitats available for the selected taxon
#' are shown as checkboxes. All are ticked by default. Use the \strong{All}
#' and \strong{None} buttons to select or clear all at once. The theta
#' heatmap and occurrence points update immediately to reflect the current
#' selection. When multiple habitats are shown simultaneously, occurrence
#' points are coloured by habitat so they remain distinguishable against the
#' theta grid.
#'
#' \strong{Habitat matching:} The habitat checkboxes are populated from
#' \code{prior_habitat_col} in \code{priors}. Occurrence points are filtered
#' to match the selected habitats using \code{occurrence_habitat_col} in
#' \code{occurrences}. These two columns should contain equivalent labels
#' (both derived from the IUCN hierarchy).
#'
#' \strong{Grid cell popups} show: theta mean and SD, number of observations,
#' model tier, and any active flags (effort, extrapolation, Jeffreys fallback).
#'
#' \strong{Requirements:} Packages \code{shiny}, \code{miniUI}, and
#' \code{leaflet} must be installed. Only works in interactive RStudio sessions.
#'
#' @seealso \code{TaxaHabitat::plot_habitat_points_interactive()}
#'
#' @importFrom stats setNames
#' @export
#'
#' @examples
#' \dontrun{
#' plot_theta_map_interactive(priors_combined, occurrences_with_habitat)
#'
#' # Ocean basemap, satellite imagery, or streets
#' plot_theta_map_interactive(priors_combined, occurrences_with_habitat,
#'                             tile = "Esri.WorldImagery")
#'
#' # No occurrence points
#' plot_theta_map_interactive(priors_combined, occurrences = NULL)
#'
#' # Single colour for occurrence points (no habitat coloring)
#' plot_theta_map_interactive(priors_combined, occurrences_with_habitat,
#'                             occurrence_habitat_col = NULL,
#'                             point_color = "#0000ff")
#' }

plot_theta_map_interactive <- function(
    priors,
    occurrences            = NULL,
    prior_habitat_col      = "main_habitat",
    occurrence_habitat_col = "main_habitat",
    tile                   = "Esri.OceanBasemap",
    theta_col              = "theta_mean",
    grid_opacity           = 0.7,
    point_radius           = 4,
    point_color            = "#ff6600"
) {

  # --- Package checks ---------------------------------------------------------
  for (pkg in c("shiny", "miniUI", "leaflet")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf(
        "plot_theta_map_interactive: package '%s' is required. Install with: install.packages('%s')",
        pkg, pkg
      ))
    }
  }
  if (!interactive()) {
    stop("plot_theta_map_interactive: must be run in an interactive R session.")
  }

  # --- Input checks -----------------------------------------------------------
  if (!is.data.frame(priors)) {
    stop("plot_theta_map_interactive: 'priors' must be a dataframe.")
  }
  for (col in c("taxon_name", "grid_id", prior_habitat_col, theta_col)) {
    if (!col %in% names(priors)) {
      stop(sprintf(
        "plot_theta_map_interactive: column '%s' not found in priors.", col
      ))
    }
  }

  # --- Prepare occurrences ----------------------------------------------------
  # We need one row per point_id x taxon_name (x habitat when available) so
  # that occ_sel() can filter to the selected taxon and selected habitats.
  # .build_habitat_pts() deduplicates to point_id x habitat, which loses the
  # per-taxon rows needed here, so we build the occ frame manually but reuse
  # the same point_id synthesis logic from that helper.
  if (!is.null(occurrences)) {
    if (!is.data.frame(occurrences)) {
      stop("plot_theta_map_interactive: 'occurrences' must be a dataframe or NULL.")
    }
    for (col in c("decimalLatitude", "decimalLongitude", "taxon_name")) {
      if (!col %in% names(occurrences)) {
        stop(sprintf(
          "plot_theta_map_interactive: column '%s' not found in occurrences.", col
        ))
      }
    }
    if (!is.null(occurrence_habitat_col) &&
        !occurrence_habitat_col %in% names(occurrences)) {
      warning(sprintf(
        "plot_theta_map_interactive: occurrence_habitat_col '%s' not found -- occurrences will not be habitat-filtered or habitat-coloured.",
        occurrence_habitat_col
      ), call. = FALSE)
      occurrence_habitat_col <- NULL
    }

    occ <- data.frame(
      lat   = as.numeric(occurrences[["decimalLatitude"]]),
      lon   = as.numeric(occurrences[["decimalLongitude"]]),
      taxon = as.character(occurrences[["taxon_name"]]),
      stringsAsFactors = FALSE
    )
    # Reuse the same point_id synthesis logic as .build_habitat_pts()
    if ("point_id" %in% names(occurrences)) {
      occ$point_id <- as.character(occurrences[["point_id"]])
    } else {
      occ$point_id <- paste0(round(occ$lon, 6L), "_", round(occ$lat, 6L))
    }
    if (!is.null(occurrence_habitat_col)) {
      occ$habitat <- as.character(occurrences[[occurrence_habitat_col]])
    }
    occ <- occ[!is.na(occ$lat) & !is.na(occ$lon), ]
    occ <- occ[!duplicated(occ[, c("point_id", "taxon")]), ]
  } else {
    occ <- NULL
  }

  # --- Prepare priors ---------------------------------------------------------
  pr <- data.frame(
    taxon_name = as.character(priors[["taxon_name"]]),
    grid_id    = as.character(priors[["grid_id"]]),
    habitat    = as.character(priors[[prior_habitat_col]]),
    theta      = unname(as.numeric(priors[[theta_col]])),
    stringsAsFactors = FALSE
  )
  # Carry optional diagnostic columns if present — unname() strips vector names
  # (e.g. "eta_predict" from predict()) that break Leaflet's JSON serialization
  for (col in c("theta_sd", "n_obs", "model_tier",
                "effort_flag", "extrapolation_warning", "jeffreys_fallback")) {
    if (col %in% names(priors)) pr[[col]] <- unname(priors[[col]])
  }
  pr <- pr[!is.na(pr$theta) & !is.na(pr$grid_id), ]

  # --- Parse grid_id -> centroid coords ---------------------------------------
  coords     <- .parse_grid_id(pr$grid_id)
  pr$lat_ctr <- coords$lat
  pr$lon_ctr <- coords$lon
  bad_coords <- is.na(pr$lat_ctr) | is.na(pr$lon_ctr) |
                is.nan(pr$lat_ctr) | is.nan(pr$lon_ctr)
  if (any(bad_coords)) {
    warning(sprintf(
      "plot_theta_map_interactive: dropped %d rows with unparseable grid_id coordinates.",
      sum(bad_coords)
    ), call. = FALSE)
    pr <- pr[!bad_coords, ]
  }

  # --- Initial dropdown / checkbox state --------------------------------------
  all_taxa      <- sort(unique(pr$taxon_name))
  default_taxon <- all_taxa[1L]
  default_habs  <- sort(unique(pr$habitat[pr$taxon_name == default_taxon]))

  # --- UI ---------------------------------------------------------------------
  ui <- miniUI::miniPage(
    miniUI::gadgetTitleBar(
      "Theta Heatmap Explorer",
      right = miniUI::miniTitleBarButton("done", "Close", primary = TRUE)
    ),
    miniUI::miniContentPanel(
      padding = 0,
      shiny::div(
        style = "display:flex;width:100%;height:100%;",

        # Map — takes all remaining width
        shiny::div(
          style = "flex:1;min-width:0;position:relative;",
          leaflet::leafletOutput("map", width = "100%", height = "100%")
        ),

        # Controls sidebar — fixed width
        shiny::div(
          style = paste0(
            "width:230px;flex-shrink:0;padding:12px;border-left:1px solid #ddd;",
            "background:#fafafa;overflow-y:auto;"
          ),

          shiny::h4("Species", style = "margin:6px 0 4px;font-size:13px;"),
          shiny::selectInput(
            "taxon", label = NULL,
            choices  = all_taxa,
            selected = default_taxon,
            width    = "100%"
          ),

          shiny::h4("Habitats", style = "margin:6px 0 2px;font-size:13px;"),
          shiny::div(
            style = "display:flex;gap:6px;margin-bottom:6px;",
            shiny::actionButton(
              "select_all_hab", "All",
              style = "font-size:11px;padding:2px 8px;height:24px;"
            ),
            shiny::actionButton(
              "clear_hab", "None",
              style = "font-size:11px;padding:2px 8px;height:24px;"
            )
          ),
          shiny::checkboxGroupInput(
            "habitat", label = NULL,
            choices  = default_habs,
            selected = default_habs,
            width    = "100%"
          ),

          shiny::hr(style = "margin:8px 0;"),

          shiny::h4("Display", style = "margin:6px 0 4px;font-size:13px;"),
          shiny::checkboxInput("show_occ", "Show occurrence points",
                               value = !is.null(occ)),

          shiny::hr(style = "margin:8px 0;"),

          shiny::uiOutput("summary_panel")
        )
      )
    )
  )

  # --- Server -----------------------------------------------------------------
  server <- function(input, output, session) {

    # Update habitat checkboxes when taxon changes — select all by default
    shiny::observeEvent(input$taxon, {
      habs <- sort(unique(pr$habitat[pr$taxon_name == input$taxon]))
      shiny::updateCheckboxGroupInput(session, "habitat",
                                      choices  = habs,
                                      selected = habs)
    })

    # All / None buttons
    shiny::observeEvent(input$select_all_hab, {
      habs <- sort(unique(pr$habitat[pr$taxon_name == input$taxon]))
      shiny::updateCheckboxGroupInput(session, "habitat", selected = habs)
    })
    shiny::observeEvent(input$clear_hab, {
      shiny::updateCheckboxGroupInput(session, "habitat", selected = character(0L))
    })

    # Filtered priors for current taxon x selected habitats
    pr_sel <- shiny::reactive({
      pr[pr$taxon_name == input$taxon & pr$habitat %in% input$habitat, ]
    })

    # Filtered occurrences for current taxon x selected habitats
    occ_sel <- shiny::reactive({
      if (is.null(occ)) return(NULL)
      sub <- occ[occ$taxon == input$taxon, ]
      if (!is.null(occurrence_habitat_col) && "habitat" %in% names(sub)) {
        sub <- sub[sub$habitat %in% input$habitat, ]
      }
      sub
    })

    # Infer grid half-width from centroid spacing in filtered data
    cell_hw <- shiny::reactive({
      lats <- sort(unique(pr_sel()$lat_ctr))
      if (length(lats) >= 2L) {
        min(diff(lats)) / 2
      } else {
        all_lats <- sort(unique(pr$lat_ctr))
        if (length(all_lats) >= 2L) min(diff(all_lats)) / 2 else 0.05
      }
    })

    # Build popups for grid cells
    grid_popup <- shiny::reactive({
      d  <- pr_sel()
      if (nrow(d) == 0L) return(character(0L))
      mapply(function(theta, lat, lon, ...) {
        args  <- list(...)
        lines <- sprintf(
          "<b>Grid cell:</b> %.4f, %.4f<br/><b>%s:</b> %.4f",
          lat, lon, theta_col, theta
        )
        if (!is.null(args$theta_sd)) {
          lines <- paste0(lines, sprintf("<br/><b>theta_sd:</b> %.4f", args$theta_sd))
        }
        if (!is.null(args$n_obs)) {
          lines <- paste0(lines, sprintf("<br/><b>n_obs:</b> %d", as.integer(args$n_obs)))
        }
        if (!is.null(args$model_tier)) {
          lines <- paste0(lines, sprintf("<br/><b>tier:</b> %s", args$model_tier))
        }
        flags <- character(0L)
        if (isTRUE(args$effort_flag))           flags <- c(flags, "effort")
        if (isTRUE(args$extrapolation_warning)) flags <- c(flags, "extrapolation")
        if (isTRUE(args$jeffreys_fallback))     flags <- c(flags, "Jeffreys")
        if (length(flags)) {
          lines <- paste0(lines, sprintf("<br/><b>flags:</b> %s",
                                         paste(flags, collapse = ", ")))
        }
        lines
      },
      d$theta,
      d$lat_ctr,
      d$lon_ctr,
      theta_sd              = if ("theta_sd"              %in% names(d)) d$theta_sd              else rep(list(NULL), nrow(d)),
      n_obs                 = if ("n_obs"                 %in% names(d)) d$n_obs                 else rep(list(NULL), nrow(d)),
      model_tier            = if ("model_tier"            %in% names(d)) d$model_tier            else rep(list(NULL), nrow(d)),
      effort_flag           = if ("effort_flag"           %in% names(d)) d$effort_flag           else rep(list(NULL), nrow(d)),
      extrapolation_warning = if ("extrapolation_warning" %in% names(d)) d$extrapolation_warning else rep(list(NULL), nrow(d)),
      jeffreys_fallback     = if ("jeffreys_fallback"     %in% names(d)) d$jeffreys_fallback     else rep(list(NULL), nrow(d)),
      SIMPLIFY = TRUE
      )
    })

    # Initial map render — zoom to default taxon x all habitats extent
    output$map <- leaflet::renderLeaflet({
      d_init    <- pr[pr$taxon_name == default_taxon & pr$habitat %in% default_habs, ]
      lats_init <- sort(unique(d_init$lat_ctr))
      hw_init   <- if (length(lats_init) >= 2L) min(diff(lats_init)) / 2 else 0.05
      leaflet::leaflet() |>
        leaflet::addProviderTiles(tile) |>
        leaflet::fitBounds(
          lng1 = min(d_init$lon_ctr, na.rm = TRUE) - hw_init,
          lat1 = min(d_init$lat_ctr, na.rm = TRUE) - hw_init,
          lng2 = max(d_init$lon_ctr, na.rm = TRUE) + hw_init,
          lat2 = max(d_init$lat_ctr, na.rm = TRUE) + hw_init
        )
    })

    # Update rectangles and points when selection changes
    shiny::observe({
      d   <- pr_sel()
      hw  <- cell_hw()
      pop <- grid_popup()

      proxy <- leaflet::leafletProxy("map")

      proxy <- leaflet::clearGroup(proxy, "grid")
      proxy <- leaflet::clearGroup(proxy, "occurrences")
      proxy <- leaflet::clearControls(proxy)

      if (nrow(d) == 0L) return()

      # Theta palette scaled to current selection
      theta_range <- range(d$theta, na.rm = TRUE)
      if (diff(theta_range) == 0) theta_range <- c(0, max(theta_range, 1e-6))
      theta_pal <- leaflet::colorNumeric(
        palette  = "YlOrRd",
        domain   = theta_range,
        na.color = "transparent"
      )

      # Grid rectangles
      proxy <- leaflet::addRectangles(
        map         = proxy,
        lng1        = d$lon_ctr - hw,
        lat1        = d$lat_ctr - hw,
        lng2        = d$lon_ctr + hw,
        lat2        = d$lat_ctr + hw,
        fillColor   = theta_pal(d$theta),
        fillOpacity = grid_opacity,
        color       = theta_pal(d$theta),
        weight      = 0.5,
        opacity     = 0.3,
        popup       = pop,
        group       = "grid"
      )

      # Theta legend — title shows taxon only (habitat selection shown in sidebar)
      proxy <- leaflet::addLegend(
        map      = proxy,
        position = "bottomright",
        pal      = theta_pal,
        values   = theta_range,
        title    = sprintf("%s<br/><small>%s</small>",
                           theta_col,
                           .truncate_label(input$taxon, 28L)),
        labFormat = leaflet::labelFormat(digits = 3),
        opacity  = 0.9
      )

      # Occurrence points
      sub <- occ_sel()
      if (input$show_occ && !is.null(sub) && nrow(sub) > 0L) {

        occ_popup <- sprintf("<b>point_id:</b> %s<br/><b>taxon:</b> %s",
                             .he(sub$point_id), .he(sub$taxon))

        # Colour by habitat when available; fall back to point_color otherwise.
        # .habitat_palette() keys colours to the habitat labels present in the
        # current filtered occurrence subset, matching the palette used by the
        # other interactive plot functions in this package.
        if (!is.null(occurrence_habitat_col) && "habitat" %in% names(sub) &&
            length(unique(sub$habitat)) > 0L) {
          occ_hab_levels <- sort(unique(sub$habitat))
          occ_pal        <- .habitat_palette(occ_hab_levels)
          sub_colors     <- unname(occ_pal[sub$habitat])
        } else {
          sub_colors <- rep(point_color, nrow(sub))
        }

        proxy <- leaflet::addCircleMarkers(
          map         = proxy,
          lng         = sub$lon,
          lat         = sub$lat,
          radius      = point_radius,
          color       = sub_colors,
          fillColor   = sub_colors,
          fillOpacity = 0.9,
          opacity     = 1,
          weight      = 1,
          popup       = occ_popup,
          group       = "occurrences"
        )

        # Habitat legend for occurrence points — shown only when >1 habitat
        # is present in the current filtered subset
        if (!is.null(occurrence_habitat_col) && "habitat" %in% names(sub) &&
            length(unique(sub$habitat)) > 1L) {
          occ_pal_leaflet <- leaflet::colorFactor(
            palette = unname(occ_pal),
            levels  = occ_hab_levels
          )
          proxy <- leaflet::addLegend(
            map      = proxy,
            position = "bottomleft",
            pal      = occ_pal_leaflet,
            values   = occ_hab_levels,
            title    = "Habitat<br/><small>(occurrences)</small>",
            opacity  = 0.9
          )
        }
      }

      # Fit bounds to grid extent
      proxy <- leaflet::fitBounds(
        map  = proxy,
        lng1 = min(d$lon_ctr, na.rm = TRUE) - hw,
        lat1 = min(d$lat_ctr, na.rm = TRUE) - hw,
        lng2 = max(d$lon_ctr, na.rm = TRUE) + hw,
        lat2 = max(d$lat_ctr, na.rm = TRUE) + hw
      )
    })

    # Summary panel
    output$summary_panel <- shiny::renderUI({
      d <- pr_sel()
      if (length(input$habitat) == 0L) {
        return(shiny::p("No habitats selected.",
                        style = "font-size:11px;color:#999;"))
      }
      if (nrow(d) == 0L) {
        return(shiny::p("No data for this combination.",
                        style = "font-size:11px;color:#999;"))
      }
      hab_str <- if (length(input$habitat) == 1L) {
        .truncate_label(input$habitat, 26L)
      } else {
        sprintf("%d habitats", length(input$habitat))
      }
      shiny::tagList(
        shiny::h4("Summary", style = "margin:6px 0 4px;font-size:13px;"),
        shiny::p(
          sprintf("Habitats: %s", hab_str),
          shiny::br(),
          sprintf("Grid cells: %d", nrow(d)),
          shiny::br(),
          sprintf("theta range: %.3f \u2013 %.3f", min(d$theta), max(d$theta)),
          shiny::br(),
          sprintf("theta mean: %.3f", mean(d$theta)),
          if ("n_obs" %in% names(d))
            shiny::tagList(shiny::br(),
                           sprintf("Total obs: %d", sum(d$n_obs, na.rm = TRUE)))
          else NULL,
          style = "font-size:11px;line-height:1.7;margin:0;"
        )
      )
    })

    shiny::observeEvent(input$done, {
      shiny::stopApp(returnValue = invisible(NULL))
    })
  }

  shiny::runGadget(
    ui,
    server,
    viewer = shiny::paneViewer(minHeight = 500)
  )
}


# ==============================================================================
# Internal helpers
# ==============================================================================

#' Parse grid_id strings to centroid lat/lon
#' Format: "Grid_{lat_int}p{lat_dec}_{m}{lon_int}p{lon_dec}"
#' where "p" = decimal point, "m" prefix = negative
#' @noRd
.parse_grid_id <- function(grid_id) {
  x         <- sub("^Grid_", "", grid_id)
  parts     <- regmatches(x, regexpr("^[^_]+", x))
  lon_parts <- sub("^[^_]+_", "", x)

  parse_coord <- function(s) {
    neg <- startsWith(s, "m")
    s   <- sub("^m", "", s)
    s   <- gsub("p", ".", s, fixed = TRUE)
    val <- suppressWarnings(as.numeric(s))
    ifelse(neg, -val, val)
  }

  data.frame(
    lat = parse_coord(parts),
    lon = parse_coord(lon_parts),
    stringsAsFactors = FALSE
  )
}

#' Truncate a label for display
#' @noRd
.truncate_label <- function(x, n = 20L) {
  if (nchar(x) <= n) x else paste0(substr(x, 1L, n - 1L), "\u2026")
}
