# ==============================================================================
# define_search_polygon.R
# TaxaTools -- Interactive polygon tool, shared across packages
#
# Moved here from TaxaFetch (Session 134b): the only generalization needed for
# this gadget to serve both a search-area purpose (TaxaFetch) and a
# spatial-group purpose (TaxaMatch::group_observations_by_bbox()) was letting
# the reference-point overlay be colored by an existing group column, and
# letting a previously drawn polygon be reopened for reshaping -- neither
# changes the core interaction model, so one shared gadget covers both.
# ==============================================================================

#' Build a closed WKT POLYGON string from ordered (lng, lat) vectors
#'
#' WKT uses (longitude latitude) order -- X before Y.
#' @noRd
.pts_to_wkt <- function(lng, lat) {
  lng_c <- c(lng, lng[1L])
  lat_c <- c(lat, lat[1L])
  coords <- paste(sprintf("%.6f %.6f", lng_c, lat_c), collapse = ", ")
  sprintf("POLYGON ((%s))", coords)
}

#' Parse a closed WKT POLYGON string back into ordered (lng, lat) vectors
#'
#' Drops the duplicated closing vertex (first == last in a closed ring).
#' @noRd
.wkt_to_pts <- function(wkt) {
  inner <- sub("^\\s*POLYGON\\s*\\(\\((.*)\\)\\)\\s*$", "\\1", wkt, ignore.case = TRUE)
  pairs <- strsplit(inner, ",\\s*")[[1]]
  mat <- do.call(rbind, lapply(pairs, function(p) as.numeric(strsplit(trimws(p), "\\s+")[[1]])))
  n <- nrow(mat)
  if (n > 1L && isTRUE(all.equal(mat[1L, ], mat[n, ]))) mat <- mat[-n, , drop = FALSE]
  list(lng = mat[, 1L], lat = mat[, 2L])
}

#' Define a Search Polygon Interactively
#'
#' Opens an interactive Shiny gadget centred on a given point (or on a
#' previously drawn polygon, via \code{init_polygon}). The initial shape is a
#' square with four draggable corner markers (or the reopened polygon's own
#' vertices). Drag any marker to reshape the polygon. Use \strong{Add Point} to
#' insert a new vertex at the midpoint of the longest side (then drag it into
#' place); use \strong{Remove Last Point} to undo the most recent addition.
#' Click \strong{Done} to return the polygon as a WKT string ready to pass to
#' \code{\link[TaxaFetch]{download_gbif_occurrences}} or
#' \code{\link[TaxaFetch]{fetch_gbif_occurrences}}.
#'
#' @param lat Numeric. Latitude of the centre point in decimal degrees (WGS
#'   84). Ignored when \code{init_polygon} is supplied (the centre is derived
#'   from the polygon instead). Required otherwise.
#' @param lon Numeric. Longitude of the centre point in decimal degrees (WGS
#'   84). Ignored when \code{init_polygon} is supplied. Required otherwise.
#' @param radius_deg Numeric. Half-width of the initial square in decimal
#'   degrees. For reference: 1 degree ~= 111 km. Ignored when
#'   \code{init_polygon} is supplied. Required otherwise.
#' @param tile Character. Leaflet tile provider name. Default
#'   \code{"Esri.OceanBasemap"}. Any string accepted by
#'   \code{leaflet::addProviderTiles()} works (e.g. \code{"OpenStreetMap"},
#'   \code{"Esri.WorldImagery"}).
#' @param points Data frame of observation coordinates to overlay on the map
#'   as small, non-interactive reference markers (does not affect the
#'   returned polygon). Must have \code{lat} and \code{lng} columns. Useful
#'   for seeing the actual data cloud while drawing a group or search-area
#'   boundary around it. Default \code{NULL} (no overlay).
#' @param group_col Character. Optional column name in \code{points} used to
#'   color the reference markers by group (e.g. an already-assigned
#'   \code{spatial_group_id}), with a legend. Lets a user drawing a broader
#'   search area see which points already belong to which group. Default
#'   \code{NULL} (all markers drawn in one flat color).
#' @param init_polygon Character. An existing WKT \code{POLYGON} string (as
#'   returned by a previous call to this function) to reopen for editing,
#'   instead of starting from a fresh square. Its own vertices become the
#'   initial draggable markers. When supplied, \code{lat}/\code{lon}/
#'   \code{radius_deg} are not required and are ignored if given.
#' @param title Character. Gadget title bar text. Default
#'   \code{"Define Search Polygon"}. Callers embedding this gadget in a
#'   larger workflow (e.g. \code{\link[TaxaMatch]{group_observations_by_bbox}})
#'   should pass something identifying what this particular call is for (e.g.
#'   which spatial group or search area is being drawn) -- session experience
#'   showed that information buried only in a console message is easy to miss
#'   while looking at the map itself.
#' @param done_label Character. Label for the primary (right-hand) title bar
#'   button. Default \code{"Done"}. Override with a verb describing what
#'   clicking it actually does in the calling context (e.g.
#'   \code{"Group These Points"}) -- generic "Done" reads as "confirm and
#'   proceed," which does not by itself convey that clicking it before
#'   resizing the initial square will capture everything currently visible.
#' @param cancel_label Character. Label for the title bar's cancel button
#'   (returns \code{NULL}). Default \code{"Cancel"}. Override with wording
#'   describing what \emph{not} drawing anything means in the calling context
#'   (e.g. \code{"No More Groups"}).
#' @param viewer A \pkg{shiny} gadget viewer, passed to
#'   \code{\link[shiny]{runGadget}}. Default \code{shiny::paneViewer(minHeight = 500)}
#'   (renders in RStudio's own Viewer pane) -- matches the viewer style already
#'   used by this ecosystem's other interactive mapping gadgets
#'   (\code{TaxaHabitat::review_spatial_flags()}), so all mapping
#'   interactions look and feel the same rather than mixing viewer styles.
#'   \strong{Not} \code{\link[shiny]{dialogViewer}} (RStudio's own popup
#'   dialog) -- on at least one real system, RStudio's embedded dialog webview
#'   silently swallowed the \strong{Done} button's return value for this
#'   specific gadget (confirmed reproducible: clicking Done closed the dialog
#'   but \code{define_search_polygon()} always returned \code{NULL}, even
#'   though an identical minimal gadget with no leaflet map worked fine in
#'   that same dialog viewer, and this exact gadget worked correctly via both
#'   \code{shiny::browserViewer()} and \code{shiny::paneViewer()} in that same
#'   session) -- most likely a Leaflet/webview rendering incompatibility
#'   specific to that embedded dialog, not something this package can
#'   control. Pass \code{shiny::browserViewer()} yourself if you'd rather open
#'   in your system's default web browser (also confirmed working); avoid
#'   \code{dialogViewer()} for this function unless you've independently
#'   confirmed it round-trips a real click on your machine.
#'
#' @return A length-1 character WKT \code{POLYGON} string with vertices ordered
#'   counter-clockwise and the ring closed (first == last vertex), ready for the
#'   \code{geometry} argument of \code{\link[TaxaFetch]{download_gbif_occurrences}}.
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
#'     The initial corners cannot be removed this way.
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
#' \code{\link[TaxaFetch]{make_bbox_wkt}} instead.
#'
#' @seealso \code{\link[TaxaFetch]{make_bbox_wkt}},
#'   \code{\link[TaxaFetch]{download_gbif_occurrences}},
#'   \code{\link[TaxaFetch]{fetch_gbif_occurrences}},
#'   \code{\link[TaxaMatch]{group_observations_by_bbox}}
#'
#' @examples
#' \dontrun{
#' # Define a custom polygon around a coastal sampling site
#' bbox <- define_search_polygon(lat = 34.4, lon = -120.4, radius_deg = 2)
#'
#' # Pass directly to the GBIF download
#' raw_gbif <- TaxaFetch::download_gbif_occurrences(
#'   keys     = valid_keys,
#'   geometry = bbox,
#'   limit    = 5000L
#' )
#'
#' # Reopen a previously drawn polygon to reshape it
#' bbox2 <- define_search_polygon(init_polygon = bbox)
#'
#' # Overlay points colored by an existing spatial_group_id
#' bbox3 <- define_search_polygon(
#'   lat = 34.4, lon = -120.4, radius_deg = 2,
#'   points = sites_with_groups,
#'   group_col = "spatial_group_id"
#' )
#' }
#'
#' @export
define_search_polygon <- function(lat = NULL,
                                  lon = NULL,
                                  radius_deg = NULL,
                                  tile = "Esri.OceanBasemap",
                                  points = NULL,
                                  group_col = NULL,
                                  init_polygon = NULL,
                                  title = "Define Search Polygon",
                                  done_label = "Done",
                                  cancel_label = "Cancel",
                                  viewer = shiny::paneViewer(minHeight = 500)) {
  # ---------------------------------------------------------------------------
  # 0. Checks
  # ---------------------------------------------------------------------------

  if (!is.null(init_polygon)) {
    if (!is.character(init_polygon) || length(init_polygon) != 1L || is.na(init_polygon)) {
      stop("define_search_polygon: 'init_polygon' must be a single non-NA WKT POLYGON string.", call. = FALSE)
    }
  } else {
    if (!is.numeric(lat) || length(lat) != 1L || is.na(lat)) {
      stop("define_search_polygon: 'lat' must be a single non-NA numeric.", call. = FALSE)
    }
    if (!is.numeric(lon) || length(lon) != 1L || is.na(lon)) {
      stop("define_search_polygon: 'lon' must be a single non-NA numeric.", call. = FALSE)
    }
    if (!is.numeric(radius_deg) || length(radius_deg) != 1L ||
      is.na(radius_deg) || radius_deg <= 0) {
      stop("define_search_polygon: 'radius_deg' must be a single positive numeric.", call. = FALSE)
    }
    if (lat < -90 || lat > 90) {
      stop("define_search_polygon: 'lat' must be in [-90, 90].", call. = FALSE)
    }
    if (lon < -180 || lon > 180) {
      stop("define_search_polygon: 'lon' must be in [-180, 180].", call. = FALSE)
    }
  }
  if (!interactive()) {
    stop("define_search_polygon: must be run in an interactive R session.", call. = FALSE)
  }
  if (!is.null(points)) {
    if (!is.data.frame(points) || !all(c("lat", "lng") %in% names(points))) {
      stop("define_search_polygon: 'points' must be a data frame with 'lat' and 'lng' columns.", call. = FALSE)
    }
    if (!is.null(group_col) && !group_col %in% names(points)) {
      stop(sprintf("define_search_polygon: 'group_col' (\"%s\") not found in 'points'.", group_col), call. = FALSE)
    }
  }

  for (pkg in c("shiny", "miniUI", "leaflet")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf(
        "define_search_polygon: package '%s' is required. Install with: install.packages('%s')",
        pkg, pkg
      ), call. = FALSE)
    }
  }

  if (!is.null(init_polygon)) {
    parsed <- tryCatch(.wkt_to_pts(init_polygon), error = function(e) NULL)
    if (is.null(parsed) || length(parsed$lat) < 3L) {
      stop("define_search_polygon: 'init_polygon' could not be parsed as a valid WKT POLYGON.", call. = FALSE)
    }
    init_pts <- data.frame(
      id = seq_along(parsed$lat), lat = parsed$lat, lng = parsed$lng,
      stringsAsFactors = FALSE
    )
    view_lat <- mean(range(parsed$lat))
    view_lon <- mean(range(parsed$lng))
    view_radius_deg <- max(diff(range(parsed$lat)) / 2, diff(range(parsed$lng)) / 2, 0.05) * 1.3
    n_init_corners <- nrow(init_pts)
    next_id_start <- n_init_corners + 1L
  } else {
    # Initial square: SW -> SE -> NE -> NW (counter-clockwise)
    init_pts <- data.frame(
      id = 1:4,
      lat = c(
        lat - radius_deg, lat - radius_deg,
        lat + radius_deg, lat + radius_deg
      ),
      lng = c(
        lon - radius_deg, lon + radius_deg,
        lon + radius_deg, lon - radius_deg
      ),
      stringsAsFactors = FALSE
    )
    view_lat <- lat
    view_lon <- lon
    view_radius_deg <- radius_deg
    n_init_corners <- 4L
    next_id_start <- 5L
  }

  # Sensible initial zoom for the given radius -- one step further out than
  # the exact fit, so the box's own edges (and its draggable corner markers)
  # are comfortably inside the visible frame on first open rather than right
  # at or beyond it (session experience: the exact-fit zoom made the initial
  # square hard to see/grab on first opening).
  init_zoom <- max(3L, min(12L, round(8L - log2(view_radius_deg)) - 1L))

  point_pal <- NULL
  if (!is.null(points) && !is.null(group_col)) {
    point_groups <- as.factor(points[[group_col]])
    point_pal <- leaflet::colorFactor(palette = "Set2", domain = point_groups)
  }

  # ---------------------------------------------------------------------------
  # 2. UI
  # ---------------------------------------------------------------------------

  ui <- miniUI::miniPage(
    miniUI::gadgetTitleBar(
      title,
      left  = miniUI::miniTitleBarCancelButton(label = cancel_label),
      right = miniUI::miniTitleBarButton("done", done_label, primary = TRUE)
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
      next_id = next_id_start
    )

    # -- Initial map -----------------------------------------------------------
    output$map <- leaflet::renderLeaflet({
      m <- leaflet::leaflet() |>
        leaflet::addProviderTiles(tile) |>
        leaflet::setView(lng = view_lon, lat = view_lat, zoom = init_zoom)

      if (!is.null(points)) {
        if (!is.null(point_pal)) {
          m <- leaflet::addCircleMarkers(
            m,
            lng         = points$lng,
            lat         = points$lat,
            radius      = 3,
            color       = point_pal(point_groups),
            fillOpacity = 0.8,
            stroke      = FALSE,
            group       = "reference_points",
            options     = leaflet::pathOptions(interactive = FALSE)
          )
          m <- leaflet::addLegend(
            m,
            position = "bottomright", pal = point_pal, values = point_groups,
            title = group_col, opacity = 0.8
          )
        } else {
          m <- leaflet::addCircleMarkers(
            m,
            lng         = points$lng,
            lat         = points$lat,
            radius      = 3,
            color       = "#e6550d",
            fillOpacity = 0.8,
            stroke      = FALSE,
            group       = "reference_points",
            options     = leaflet::pathOptions(interactive = FALSE)
          )
        }
      }

      m
    })

    # -- Redraw polygon + markers whenever rv$data changes --------------------
    # Scoped to the "editor" group -- clearShapes()/clearMarkers() clear EVERY
    # shape/marker layer on the map regardless of how it was added (this
    # bit us once already: it was wiping the "reference_points" overlay added
    # in the initial renderLeaflet() above, since this observer also fires on
    # gadget startup). clearGroup() only touches layers tagged with this group.
    shiny::observe({
      d <- rv$data
      n <- nrow(d)
      proxy <- leaflet::leafletProxy("map", session)

      leaflet::clearGroup(proxy, group = "editor")

      # Polygon (close ring for display)
      leaflet::addPolygons(
        proxy,
        lng         = c(d$lng, d$lng[1L]),
        lat         = c(d$lat, d$lat[1L]),
        color       = "#2c7bb6",
        weight      = 2,
        fillColor   = "#2c7bb6",
        fillOpacity = 0.12,
        group       = "editor",
        options     = leaflet::pathOptions(interactive = FALSE)
      )

      # Draggable numbered markers.
      # addCircleMarkers() does not support dragging (Leaflet.js L.CircleMarker
      # limitation); addMarkers() with markerOptions(draggable = TRUE) is required.
      leaflet::addMarkers(
        proxy,
        lng = d$lng,
        lat = d$lat,
        layerId = paste0("pt_", d$id),
        label = as.character(seq_len(n)),
        labelOptions = leaflet::labelOptions(
          noHide = TRUE,
          direction = "top",
          textOnly = FALSE,
          style = list(
            "font-weight" = "bold", "color" = "#2c7bb6",
            "font-size" = "12px"
          )
        ),
        group = "editor",
        options = leaflet::markerOptions(draggable = TRUE)
      )
    })

    # -- Update position on drag end ------------------------------------------
    shiny::observeEvent(input$map_marker_dragend, {
      ev <- input$map_marker_dragend
      mid <- suppressWarnings(as.integer(sub("^pt_", "", ev$id)))
      if (is.na(mid)) {
        return()
      }
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

      # Squared Euclidean length of each segment (i -> next, wraps at end)
      seg_sq <- vapply(seq_len(n), function(i) {
        j <- if (i == n) 1L else i + 1L
        (d$lat[j] - d$lat[i])^2 + (d$lng[j] - d$lng[i])^2
      }, numeric(1L))

      i_max <- which.max(seg_sq)
      j_max <- if (i_max == n) 1L else i_max + 1L

      new_row <- data.frame(
        id = rv$next_id,
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
          d[seq_len(i_max), , drop = FALSE],
          new_row,
          d[seq(i_max + 1L, n), , drop = FALSE]
        )
      }
    })

    # -- Remove last added point (protects the initial corners) ---------------
    shiny::observeEvent(input$remove_pt, {
      added <- rv$data[rv$data$id > n_init_corners, , drop = FALSE]
      if (nrow(added) == 0L) {
        shiny::showNotification(
          "The initial corners cannot be removed.",
          type = "message", duration = 2L
        )
        return()
      }
      remove_id <- max(added$id)
      rv$data <- rv$data[rv$data$id != remove_id, , drop = FALSE]
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

  shiny::runGadget(ui, server, viewer = viewer)
}
