# ==============================================================================
# define_search_polygon.R
# TaxaFetch -- Interactive polygon tool for defining GBIF search geometry
# ==============================================================================

#' Define a Search Polygon Interactively
#'
#' Opens an interactive Shiny gadget centred on a given point.  The initial
#' shape is a square with four draggable corner markers.  Drag any marker to
#' reshape the polygon.  Use \strong{Add Point} to insert a new vertex at the
#' midpoint of the longest side (then drag it into place); use
#' \strong{Remove Last Point} to undo the most recent addition.  Click
#' \strong{Done} to return the polygon as a WKT string ready to pass to
#' \code{\link{download_gbif_occurrences}} or
#' \code{\link{fetch_gbif_occurrences}}.
#'
#' @param lat Numeric. Latitude of the centre point in decimal degrees (WGS 84).
#' @param lon Numeric. Longitude of the centre point in decimal degrees (WGS 84).
#' @param radius_deg Numeric. Half-width of the initial square in decimal
#'   degrees. For reference: 1 degree ≈ 111 km.
#' @param tile Character. Leaflet tile provider name. Default
#'   \code{"Esri.OceanBasemap"}. Any string accepted by
#'   \code{leaflet::addProviderTiles()} works (e.g. \code{"OpenStreetMap"},
#'   \code{"Esri.WorldImagery"}).
#'
#' @return A length-1 character WKT \code{POLYGON} string with vertices ordered
#'   counter-clockwise and the ring closed (first == last vertex), ready for the
#'   \code{geometry} argument of \code{\link{download_gbif_occurrences}}.
#'   Returns \code{NULL} if the user closes the gadget without clicking Done.
#'
#' @details
#' \strong{Interaction model:}
#' \itemize{
#'   \item Drag any numbered circle to move that vertex.
#'   \item \strong{Add Point} inserts a new draggable vertex at the midpoint of
#'     the current longest side.  Drag it to the desired position.  There is no
#'     limit on the number of vertices.
#'   \item \strong{Remove Last Point} removes the most recently added vertex.
#'     The four initial corners cannot be removed this way.
#'   \item The WKT string updates live in the toolbar so you can inspect it
#'     before clicking Done.
#' }
#'
#' \strong{Tile choice:} For marine / coastal studies use the default
#' \code{"Esri.OceanBasemap"} (shows bathymetry and shelf).  For terrestrial or
#' freshwater studies \code{"OpenStreetMap"} or \code{"Esri.WorldTopoMap"} may
#' be clearer.
#'
#' \strong{Non-interactive use:} For scripted or non-interactive workflows use
#' \code{\link{make_bbox_wkt}} instead.
#'
#' @seealso \code{\link{make_bbox_wkt}}, \code{\link{download_gbif_occurrences}},
#'   \code{\link{fetch_gbif_occurrences}}
#'
#' @examples
#' \dontrun{
#' # Define a custom polygon around a coastal sampling site
#' bbox <- define_search_polygon(lat = 34.4, lon = -120.4, radius_deg = 2)
#'
#' # Pass directly to the GBIF download
#' raw_gbif <- download_gbif_occurrences(
#'   keys     = valid_keys,
#'   geometry = bbox,
#'   limit    = 5000L
#' )
#' }
#'
#' @export
define_search_polygon <- function(lat,
                                  lon,
                                  radius_deg,
                                  tile = "Esri.OceanBasemap") {

  # ---------------------------------------------------------------------------
  # 0. Checks
  # ---------------------------------------------------------------------------

  if (!is.numeric(lat) || length(lat) != 1L || is.na(lat))
    stop("define_search_polygon: 'lat' must be a single non-NA numeric.", call. = FALSE)
  if (!is.numeric(lon) || length(lon) != 1L || is.na(lon))
    stop("define_search_polygon: 'lon' must be a single non-NA numeric.", call. = FALSE)
  if (!is.numeric(radius_deg) || length(radius_deg) != 1L ||
      is.na(radius_deg) || radius_deg <= 0)
    stop("define_search_polygon: 'radius_deg' must be a single positive numeric.", call. = FALSE)
  if (lat < -90 || lat > 90)
    stop("define_search_polygon: 'lat' must be in [-90, 90].", call. = FALSE)
  if (lon < -180 || lon > 180)
    stop("define_search_polygon: 'lon' must be in [-180, 180].", call. = FALSE)
  if (!interactive())
    stop("define_search_polygon: must be run in an interactive R session.", call. = FALSE)

  for (pkg in c("shiny", "miniUI", "leaflet")) {
    if (!requireNamespace(pkg, quietly = TRUE))
      stop(sprintf(
        "define_search_polygon: package '%s' is required. Install with: install.packages('%s')",
        pkg, pkg), call. = FALSE)
  }

  # ---------------------------------------------------------------------------
  # 1. Internal helpers
  # ---------------------------------------------------------------------------

  # Build a closed WKT POLYGON string from ordered (lng, lat) vectors.
  # WKT uses (longitude latitude) — X before Y.
  .pts_to_wkt <- function(lng, lat) {
    lng_c  <- c(lng, lng[1L])
    lat_c  <- c(lat, lat[1L])
    coords <- paste(sprintf("%.6f %.6f", lng_c, lat_c), collapse = ", ")
    sprintf("POLYGON ((%s))", coords)
  }

  # Initial square: SW → SE → NE → NW (counter-clockwise)
  init_pts <- data.frame(
    id  = 1:4,
    lat = c(lat - radius_deg, lat - radius_deg,
            lat + radius_deg, lat + radius_deg),
    lng = c(lon - radius_deg, lon + radius_deg,
            lon + radius_deg, lon - radius_deg),
    stringsAsFactors = FALSE
  )

  # Sensible initial zoom for the given radius
  init_zoom <- max(3L, min(12L, round(8L - log2(radius_deg))))

  # ---------------------------------------------------------------------------
  # 2. UI
  # ---------------------------------------------------------------------------

  ui <- miniUI::miniPage(
    miniUI::gadgetTitleBar(
      "Define Search Polygon",
      right = miniUI::miniTitleBarButton("done", "Done", primary = TRUE)
    ),
    miniUI::miniContentPanel(
      leaflet::leafletOutput("map", height = "100%"),
      padding = 0
    ),
    shiny::tags$div(
      style = paste(
        "padding: 6px 12px;",
        "background: #f5f5f5;",
        "border-top: 1px solid #ccc;",
        "display: flex;",
        "align-items: center;",
        "gap: 8px;"
      ),
      shiny::actionButton(
        "add_pt", "Add Point",
        style = "font-size:12px; padding:3px 10px;"
      ),
      shiny::actionButton(
        "remove_pt", "Remove Last Point",
        style = "font-size:12px; padding:3px 10px;"
      ),
      shiny::tags$span(style = "flex:1;"),
      shiny::tags$small(
        style = "color:#555; font-family:monospace; overflow:hidden; white-space:nowrap;",
        shiny::textOutput("wkt_preview", inline = TRUE)
      )
    )
  )

  # ---------------------------------------------------------------------------
  # 3. Server
  # ---------------------------------------------------------------------------

  server <- function(input, output, session) {

    rv <- shiny::reactiveValues(
      data    = init_pts,
      next_id = 5L         # IDs 1–4 are initial corners; added pts start at 5
    )

    # -- Initial map -----------------------------------------------------------
    output$map <- leaflet::renderLeaflet({
      leaflet::leaflet() |>
        leaflet::addProviderTiles(tile) |>
        leaflet::setView(lng = lon, lat = lat, zoom = init_zoom)
    })

    # -- Redraw polygon + markers whenever rv$data changes --------------------
    shiny::observe({
      d     <- rv$data
      n     <- nrow(d)
      proxy <- leaflet::leafletProxy("map", session)

      leaflet::clearShapes(proxy)
      leaflet::clearMarkers(proxy)

      # Polygon (close ring for display)
      leaflet::addPolygons(
        proxy,
        lng         = c(d$lng, d$lng[1L]),
        lat         = c(d$lat, d$lat[1L]),
        color       = "#2c7bb6",
        weight      = 2,
        fillColor   = "#2c7bb6",
        fillOpacity = 0.12,
        options     = leaflet::pathOptions(interactive = FALSE)
      )

      # Draggable numbered markers.
      # addCircleMarkers() does not support dragging (Leaflet.js L.CircleMarker
      # limitation); addMarkers() with markerOptions(draggable = TRUE) is required.
      leaflet::addMarkers(
        proxy,
        lng          = d$lng,
        lat          = d$lat,
        layerId      = paste0("pt_", d$id),
        label        = as.character(seq_len(n)),
        labelOptions = leaflet::labelOptions(
          noHide    = TRUE,
          direction = "top",
          textOnly  = FALSE,
          style     = list("font-weight" = "bold", "color" = "#2c7bb6",
                           "font-size" = "12px")
        ),
        options      = leaflet::markerOptions(draggable = TRUE)
      )
    })

    # -- Update position on drag end ------------------------------------------
    shiny::observeEvent(input$map_marker_dragend, {
      ev  <- input$map_marker_dragend
      mid <- suppressWarnings(as.integer(sub("^pt_", "", ev$id)))
      if (is.na(mid)) return()
      i <- which(rv$data$id == mid)
      if (length(i) == 1L) {
        rv$data$lat[i] <- ev$lat
        rv$data$lng[i] <- ev$lng
      }
    })

    # -- Add point: insert at midpoint of longest segment ---------------------
    shiny::observeEvent(input$add_pt, {
      d <- rv$data
      n <- nrow(d)

      # Squared Euclidean length of each segment (i → next, wraps at end)
      seg_sq <- vapply(seq_len(n), function(i) {
        j <- if (i == n) 1L else i + 1L
        (d$lat[j] - d$lat[i])^2 + (d$lng[j] - d$lng[i])^2
      }, numeric(1L))

      i_max <- which.max(seg_sq)
      j_max <- if (i_max == n) 1L else i_max + 1L

      new_row <- data.frame(
        id  = rv$next_id,
        lat = (d$lat[i_max] + d$lat[j_max]) / 2,
        lng = (d$lng[i_max] + d$lng[j_max]) / 2,
        stringsAsFactors = FALSE
      )
      rv$next_id <- rv$next_id + 1L

      # Insert between i_max and j_max
      if (i_max == n) {
        rv$data <- rbind(d, new_row)
      } else {
        rv$data <- rbind(
          d[seq_len(i_max),       , drop = FALSE],
          new_row,
          d[seq(i_max + 1L, n),  , drop = FALSE]
        )
      }
    })

    # -- Remove last added point (id > 4; minimum 4 corners retained) ---------
    shiny::observeEvent(input$remove_pt, {
      added <- rv$data[rv$data$id > 4L, , drop = FALSE]
      if (nrow(added) == 0L) {
        shiny::showNotification(
          "The four initial corners cannot be removed.",
          type = "message", duration = 2L
        )
        return()
      }
      remove_id <- max(added$id)
      rv$data   <- rv$data[rv$data$id != remove_id, , drop = FALSE]
    })

    # -- Live WKT preview ------------------------------------------------------
    output$wkt_preview <- shiny::renderText({
      d <- rv$data
      .pts_to_wkt(d$lng, d$lat)
    })

    # -- Done: return WKT ------------------------------------------------------
    shiny::observeEvent(input$done, {
      d <- shiny::isolate(rv$data)
      shiny::stopApp(returnValue = .pts_to_wkt(d$lng, d$lat))
    })

    # -- Cancel (X in title bar) -----------------------------------------------
    shiny::observeEvent(input$cancel, {
      shiny::stopApp(returnValue = NULL)
    })
  }

  # ---------------------------------------------------------------------------
  # 4. Launch gadget
  # ---------------------------------------------------------------------------

  shiny::runGadget(
    ui, server,
    viewer = shiny::dialogViewer(
      "Define Search Polygon",
      width  = 820,
      height = 620
    )
  )
}
