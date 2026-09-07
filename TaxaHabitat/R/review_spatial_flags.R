#' Review and Correct Spatial Flags Interactively
#'
#' Opens a Shiny gadget for reviewing the \code{spatial_flag} column added by
#' \code{\link{flag_habitat_inconsistencies}}. Points are shown in three views
#' -- \strong{Likely}, \strong{Questionable}, and \strong{Unlikely} --
#' corresponding to the three \code{spatial_flag} values. Clicking a point
#' reassigns it according to simple rules designed for a top-to-bottom review
#' workflow.
#'
#' @section Review workflow:
#' \enumerate{
#'   \item Start in \strong{Likely} view. Click any point that looks
#'     suspicious -- it moves to Questionable.
#'   \item Switch to \strong{Unlikely} view. Click any point that actually
#'     looks fine -- it moves to Questionable.
#'   \item Switch to \strong{Questionable} view. Click any point you are now
#'     satisfied with -- it moves to Likely.
#'   \item Click \strong{Done}. The returned dataframe retains only the updated
#'     \code{spatial_flag} values.
#'   \item Filter to keep only confirmed good points:
#'     \code{dplyr::filter(result, spatial_flag == "likely")}
#' }
#'
#' @section Click behaviour:
#' The \strong{Action} radio switches between two modes:
#' \describe{
#'   \item{Flag (default)}{Clicks reassign \code{spatial_flag}:
#'     Likely/Unlikely \eqn{\rightarrow} Questionable;
#'     Questionable \eqn{\rightarrow} Likely.}
#'   \item{Reassign Habitat}{Click selects a point and shows a dropdown of
#'     all habitats present in the dataset (plus \strong{Other} for a value
#'     not yet seen this session). Confirming updates \code{main_habitat} for
#'     all rows at that \code{point_id}. If the point's flag was
#'     \strong{Questionable} at the moment of reassignment, this counts as a
#'     spatially-informed resolution and the flag becomes \strong{Likely}
#'     (the point leaves the Questionable view). Reassigning from
#'     \strong{Likely}/\strong{Unlikely} keeps the point's existing flag --
#'     the reassignment itself is treated as a spatially-informed decision,
#'     so it does not force a second round-trip through the Questionable
#'     view.}
#' }
#' Every change appends a timestamped note to \code{spatial_flag_reason}.
#' A habitat value typed via \strong{Other} that doesn't already appear in
#' the dataset is added to the palette and the Habitats sidebar filter
#' immediately, without disturbing any existing habitat's colour.
#'
#' @section Habitat filter:
#' The sidebar \strong{Habitats} panel lists every habitat present in the
#' dataset (plus any added mid-session via a habitat reassignment) as a
#' colour-coded checkbox. Unchecking a habitat hides those points from the
#' map and excludes them from rectangle drag-selection and click actions.
#' Use \strong{All} / \strong{None} to select or clear all at once.
#'
#' @section Point Info panel:
#' Hovering over any map point updates the \strong{Point Info} sidebar section
#' with the point ID, its current habitat (reflecting any in-session
#' reassignments), and taxon information. By default only the first species
#' alphabetically and the total count are shown. Checking
#' \strong{Show full species list} expands the panel to display every taxon
#' recorded at the hovered point as a scrollable inline list. The toggle does
#' not affect hover or click behaviour.
#'
#' @param occurrence_data A dataframe output of \code{\link{flag_habitat_inconsistencies}}.
#'   Must contain \code{spatial_flag}, \code{spatial_flag_reason},
#'   \code{point_id}, and coordinate columns.
#' @param habitat_col Character. Habitat column for point colouring. Default
#'   \code{"main_habitat"}.
#' @param lat_col Character. Latitude column. Default \code{"decimalLatitude"}.
#' @param lon_col Character. Longitude column. Default
#'   \code{"decimalLongitude"}.
#' @param taxon_col Character or \code{NULL}. Taxon column for the Point Info
#'   species display. Default \code{"taxon_name"}.
#' @param colors Named character vector mapping habitat labels to colours.
#'   \code{NULL} uses the standard ecological palette.
#' @param tile Character. Leaflet tile provider. Default
#'   \code{"Esri.OceanBasemap"}.
#' @param point_radius Numeric. Circle marker radius in pixels. Default
#'   \code{6}.
#' @param viewer Shiny viewer function passed through to
#'   \code{\link[shiny]{runGadget}}. Default
#'   \code{shiny::paneViewer(minHeight = 450)} (RStudio's embedded Viewer
#'   pane). Some RStudio configurations have been observed to silently
#'   swallow leaflet-map click events inside the Viewer pane; pass
#'   \code{shiny::browserViewer()} to force the gadget into a real browser
#'   tab as a workaround/diagnostic if map clicks appear unresponsive.
#'
#' @return The input \code{occurrence_data} dataframe with \code{spatial_flag},
#'   \code{spatial_flag_reason}, and \code{main_habitat} updated where changed.
#'   Returns \code{NULL} if the user clicks Cancel. Filter to keep confirmed
#'   records:
#'   \preformatted{
#' reviewed <- review_spatial_flags(occurrences_flagged)
#' occurrences_clean <- dplyr::filter(reviewed, spatial_flag == "likely")
#'   }
#'
#' @seealso \code{\link{flag_habitat_inconsistencies}}
#'
#' @importFrom stats setNames
#' @importFrom leaflet.extras addDrawToolbar drawRectangleOptions drawShapeOptions removeDrawToolbar
#' @export
#'
#' @examples
#' \dontrun{
#' occurrences_flagged <- flag_habitat_inconsistencies(occurrences_with_habitat)
#'
#' reviewed <- review_spatial_flags(occurrences_flagged)
#'
#' occurrences_clean <- dplyr::filter(reviewed, spatial_flag == "likely")
#' }
review_spatial_flags <- function(
  occurrence_data,
  habitat_col = "main_habitat",
  lat_col = "decimalLatitude",
  lon_col = "decimalLongitude",
  taxon_col = "taxon_name",
  colors = NULL,
  tile = "Esri.OceanBasemap",
  point_radius = 6,
  viewer = shiny::paneViewer(minHeight = 450)
) {
  # --------------------------------------------------------------------------
  # 0. Checks
  # --------------------------------------------------------------------------

  if (!interactive()) {
    stop("review_spatial_flags: must be run in an interactive R session.")
  }

  for (pkg in c("shiny", "miniUI", "leaflet", "leaflet.extras")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf(
        "review_spatial_flags: package '%s' is required. Install with: install.packages('%s')",
        pkg, pkg
      ))
    }
  }
  if (!is.data.frame(occurrence_data)) {
    stop("review_spatial_flags: 'occurrence_data' must be a dataframe.")
  }
  for (col in c(
    habitat_col, lat_col, lon_col, "spatial_flag",
    "spatial_flag_reason", "point_id"
  )) {
    if (!col %in% names(occurrence_data)) {
      stop(sprintf(
        "review_spatial_flags: column '%s' not found. Run flag_habitat_inconsistencies() first.",
        col
      ))
    }
  }
  if (!is.null(taxon_col) && !taxon_col %in% names(occurrence_data)) {
    warning("review_spatial_flags: taxon_col not found -- species list suppressed.",
      call. = FALSE
    )
    taxon_col <- NULL
  }

  valid_flags <- c("likely", "questionable", "unlikely")
  bad_flags <- setdiff(unique(occurrence_data$spatial_flag), valid_flags)
  if (length(bad_flags) > 0L) {
    na_count <- sum(is.na(occurrence_data$spatial_flag))
    if (na_count > 0L && identical(bad_flags, NA_character_)) {
      stop(sprintf(
        paste0(
          "review_spatial_flags: %d row(s) have NA spatial_flag.\n",
          "  This usually means flag_habitat_inconsistencies() did not\n",
          "  complete successfully, or the output was modified before review.\n",
          "  Re-run flag_habitat_inconsistencies() and pass its output directly."
        ),
        na_count
      ))
    }
    stop(sprintf(
      "review_spatial_flags: unexpected spatial_flag values: %s.\n  Expected: likely, questionable, unlikely.",
      paste(bad_flags, collapse = ", ")
    ))
  }

  # --------------------------------------------------------------------------
  # 1. Build point-level summary
  # --------------------------------------------------------------------------

  pts <- .build_habitat_pts(occurrence_data, habitat_col, lat_col, lon_col, taxon_col)

  flag_tbl <- unique(occurrence_data[, c("point_id", "spatial_flag", "spatial_flag_reason")])
  flag_tbl <- flag_tbl[!duplicated(flag_tbl$point_id), ]

  pts <- merge(pts, flag_tbl, by = "point_id", all.x = TRUE)

  hab_levels <- sort(unique(pts$habitat))
  pal <- .habitat_palette(hab_levels, colors)
  pts$color <- pal[pts$habitat]

  # Fixed geographic frame for every render, computed ONCE from the FULL point
  # set (not the subset shown in whichever view is currently on screen).
  # Without this, leaflet's own auto-fit-to-added-occurrence_data behaviour (triggered
  # any time a layer function runs without a prior setView()/fitBounds() call)
  # recomputes bounds from THAT VIEW'S OWN markers on every view-mode switch --
  # confirmed live: two points ~11m apart rendered as two touching/overlapping
  # circles once few enough points remained in a view to zoom in tightly, and
  # a sparser view could auto-zoom out far enough to make a single remaining
  # point nearly invisible. Reviewers reassigning several points in sequence
  # hit exactly this: each view switch re-scales unpredictably around
  # whatever subset is visible, so points that were easy to click a moment
  # ago can end up overlapping (or a lone point can shrink to a speck) the
  # next time that view is opened -- looking like clicking "stopped working"
  # when the marker was just too small/overlapped to hit reliably. A single
  # bounding box shared by every view keeps the zoom level predictable and
  # consistent across Likely/Questionable/Unlikely, so a reviewer's mental
  # map of "where things are" stays valid after every reassignment/flag click.
  full_bounds <- list(
    lng1 = min(pts$lon), lat1 = min(pts$lat),
    lng2 = max(pts$lon), lat2 = max(pts$lat)
  )
  if (full_bounds$lng1 == full_bounds$lng2) {
    full_bounds$lng1 <- full_bounds$lng1 - 0.01
    full_bounds$lng2 <- full_bounds$lng2 + 0.01
  }
  if (full_bounds$lat1 == full_bounds$lat2) {
    full_bounds$lat1 <- full_bounds$lat1 - 0.01
    full_bounds$lat2 <- full_bounds$lat2 + 0.01
  }

  flag_ring_color <- c(
    likely       = "#2ca02c",
    questionable = "#ff7f0e",
    unlikely     = "#d62728"
  )

  # --------------------------------------------------------------------------
  # 1b. Full species list per point_id.
  #
  #     Built from the complete 'occurrence_data' dataframe (not the one-row-per-point
  #     'pts') so every occurrence row is captured.  Named list keyed by
  #     point_id; each element is a sorted unique character vector.
  #     NULL when taxon_col was not supplied.
  # --------------------------------------------------------------------------

  if (!is.null(taxon_col)) {
    spp_by_point <- tapply(
      occurrence_data[[taxon_col]],
      occurrence_data$point_id,
      function(x) sort(unique(x[!is.na(x) & nzchar(x)]))
    )
  } else {
    spp_by_point <- NULL
  }

  # --------------------------------------------------------------------------
  # 2. Map hover tooltips (always compact)
  # --------------------------------------------------------------------------

  pts$tooltip <- mapply(
    function(pid, hab, reason) {
      out <- sprintf("<b>%s</b>", .he(pid))
      out <- paste0(out, "<br/><b>Habitat:</b> ", .he(hab))
      if (!is.null(spp_by_point)) {
        spp <- spp_by_point[[pid]]
        n_spp <- length(spp)
        if (n_spp > 0L) {
          out <- paste0(
            out,
            "<br/><b>Species:</b> ", .he(spp[1L]),
            if (n_spp > 1L) sprintf(" <i>(+%d more)</i>", n_spp - 1L) else ""
          )
        }
      }
      if (!is.na(reason) && nzchar(reason)) {
        out <- paste0(out, "<br/><b>Flag reason:</b> ", .he(reason))
      }
      out
    },
    pts$point_id,
    pts$habitat,
    pts$spatial_flag_reason,
    SIMPLIFY = TRUE
  )

  # --------------------------------------------------------------------------
  # 3. Habitat checkbox HTML (coloured dot + label) for sidebar filter
  # --------------------------------------------------------------------------

  hab_choice_names <- lapply(hab_levels, function(h) {
    shiny::HTML(sprintf(
      paste0(
        '<span style="display:inline-flex;align-items:center;gap:5px;">',
        '<span style="display:inline-block;width:10px;height:10px;',
        'border-radius:50%%;background:%s;flex-shrink:0;"></span>',
        '<span style="font-size:11px;">%s</span>',
        "</span>"
      ),
      pal[[h]], .he(h)
    ))
  })

  # --------------------------------------------------------------------------
  # 4. UI
  # --------------------------------------------------------------------------

  ui <- miniUI::miniPage(
    miniUI::gadgetTitleBar(
      "Review Spatial Flags",
      right = miniUI::miniTitleBarButton("done", "Done", primary = TRUE),
      left  = miniUI::miniTitleBarButton("cancel", "Cancel", primary = FALSE)
    ),
    miniUI::miniContentPanel(
      padding = 0,
      shiny::fillRow(
        flex = c(1, NA),

        # Map
        leaflet::leafletOutput("map", height = "100%"),

        # Sidebar
        shiny::div(
          style = paste0(
            "width:230px;padding:10px;border-left:1px solid #ddd;",
            "background:#fafafa;height:100%;overflow-y:auto;box-sizing:border-box;"
          ),

          # ---- View --------------------------------------------------------
          shiny::h4("View", style = "margin-top:6px;margin-bottom:6px;font-size:14px;"),
          shiny::radioButtons(
            inputId  = "view_mode",
            label    = NULL,
            choices  = c("Likely", "Questionable", "Unlikely"),
            selected = "Likely",
            inline   = FALSE
          ),
          shiny::hr(style = "margin:8px 0;"),

          # ---- Habitat filter ----------------------------------------------
          shiny::h4("Habitats", style = "margin-top:0;margin-bottom:4px;font-size:14px;"),
          shiny::div(
            style = "display:flex;gap:4px;margin-bottom:6px;",
            shiny::actionButton(
              "hab_all", "All",
              style = paste0(
                "flex:1;font-size:11px;padding:2px 6px;",
                "background:#e8e8e8;border:1px solid #ccc;border-radius:3px;"
              )
            ),
            shiny::actionButton(
              "hab_none", "None",
              style = paste0(
                "flex:1;font-size:11px;padding:2px 6px;",
                "background:#e8e8e8;border:1px solid #ccc;border-radius:3px;"
              )
            )
          ),
          shiny::checkboxGroupInput(
            inputId      = "visible_habitats",
            label        = NULL,
            choiceNames  = hab_choice_names,
            choiceValues = hab_levels,
            selected     = hab_levels
          ),
          shiny::hr(style = "margin:8px 0;"),

          # ---- Point Info --------------------------------------------------
          # Header row: label left, toggle right
          shiny::div(
            style = "display:flex;align-items:baseline;justify-content:space-between;margin-bottom:4px;",
            shiny::h4("Point Info",
              style = "margin:0;font-size:14px;"
            ),
            shiny::div(
              style = "font-size:10px;color:#555;",
              shiny::checkboxInput(
                inputId = "show_all_spp",
                label = shiny::HTML(
                  '<span style="font-size:10px;color:#555;">Full species list</span>'
                ),
                value = FALSE
              )
            )
          ),
          shiny::uiOutput("point_info_panel"),
          shiny::hr(style = "margin:8px 0;"),

          # ---- Action ------------------------------------------------------
          shiny::h4("Action", style = "margin-top:0;margin-bottom:6px;font-size:14px;"),
          shiny::radioButtons(
            inputId  = "action_mode",
            label    = NULL,
            choices  = c("Flag", "Reassign Habitat"),
            selected = "Flag",
            inline   = FALSE
          ),
          shiny::hr(style = "margin:8px 0;"),
          shiny::conditionalPanel(
            condition = "input.action_mode == 'Flag'",
            shiny::div(
              style = paste0(
                "padding:8px;border-radius:4px;background:#f0f0f0;",
                "font-size:11px;color:#444;margin-bottom:8px;"
              ),
              shiny::strong("Click behaviour:"),
              shiny::br(),
              shiny::HTML(
                "Likely \u2192 Questionable<br/>",
                "Unlikely \u2192 Questionable<br/>",
                "Questionable \u2192 Likely"
              )
            )
          ),
          shiny::conditionalPanel(
            condition = "input.action_mode == 'Reassign Habitat'",
            shiny::div(
              style = paste0(
                "padding:8px;border-radius:4px;background:#fff8e1;",
                "font-size:11px;color:#444;margin-bottom:8px;"
              ),
              shiny::strong("Click a point to reassign its habitat."),
              shiny::br(),
              shiny::HTML("All rows at that location will be updated.")
            ),
            shiny::uiOutput("habitat_reassign_panel")
          ),
          shiny::hr(style = "margin:8px 0;"),

          # ---- Session overrides -------------------------------------------
          shiny::h4("Session overrides",
            style = "margin-top:0;margin-bottom:4px;font-size:13px;"
          ),
          shiny::uiOutput("override_summary"),
          shiny::hr(style = "margin:8px 0;"),
          shiny::uiOutput("point_count"),
          shiny::hr(style = "margin:8px 0;"),
          shiny::actionButton(
            "undo_last", "Undo Last",
            style = "width:100%;font-size:12px;padding:4px 8px;margin-bottom:4px;"
          )
        )
      )
    )
  )

  # --------------------------------------------------------------------------
  # 4b. Shared draw-toolbar / marker helpers
  #
  #     Closures over pal/point_radius (defined above), reused by the initial
  #     render and by every handler that redraws a marker after an override.
  # --------------------------------------------------------------------------

  .add_draw_toolbar <- function(target) {
    leaflet.extras::addDrawToolbar(
      target,
      targetGroup = "drawn",
      rectangleOptions = leaflet.extras::drawRectangleOptions(
        shapeOptions = leaflet.extras::drawShapeOptions(fillOpacity = 0.1, color = "#333", weight = 1)
      ),
      polylineOptions = FALSE, polygonOptions = FALSE,
      circleOptions = FALSE, markerOptions = FALSE,
      circleMarkerOptions = FALSE, editOptions = FALSE
    )
  }

  .reset_draw_toolbar <- function(proxy) {
    leaflet.extras::removeDrawToolbar(proxy, clearFeatures = TRUE)
    .add_draw_toolbar(proxy)
  }

  .add_habitat_marker <- function(target, row, color, group) {
    leaflet::addCircleMarkers(
      target,
      lng = row$lon,
      lat = row$lat,
      layerId = row$point_id,
      radius = point_radius,
      color = color,
      fillColor = color,
      fillOpacity = 0.8,
      opacity = 0.9,
      weight = 1,
      label = shiny::HTML(row$tooltip),
      labelOptions = leaflet::labelOptions(
        style     = list("font-size" = "12px", "padding" = "4px 6px"),
        direction = "auto",
        delay     = 600L
      ),
      group = group
    )
  }

  # --------------------------------------------------------------------------
  # 5. Server
  # --------------------------------------------------------------------------

  server <- function(input, output, session) {
    cur_flags <- shiny::reactiveVal(stats::setNames(flag_tbl$spatial_flag, flag_tbl$point_id))
    cur_reasons <- shiny::reactiveVal(stats::setNames(flag_tbl$spatial_flag_reason, flag_tbl$point_id))

    pts_hab_init <- stats::setNames(pts$habitat, pts$point_id)
    pts_hab_init <- pts_hab_init[!duplicated(names(pts_hab_init))]
    cur_habitats <- shiny::reactiveVal(pts_hab_init)

    selected_point <- shiny::reactiveVal(NULL)
    selected_points <- shiny::reactiveVal(NULL)
    hovered_point_id <- shiny::reactiveVal(NULL)
    history <- shiny::reactiveVal(list())

    # hab_levels/pal start as the STATIC sets computed above (from the
    # dataset's original habitat values) but must grow during the session:
    # a reviewer can reassign a point to a habitat value that never existed
    # in the input occurrence_data (typed via the "Other" text box below). Without this,
    # that new value has no palette entry (silently falls back to grey) and
    # is invisible to the sidebar's habitat-visibility checkboxes, which only
    # ever iterate the ORIGINAL hab_levels -- found live reviewing the
    # GreatLakes Lentic/Lotic reassignment case, where the region's initial
    # LLM classification can itself skew to one level, same as the pattern
    # that broke train_biodiversity_model()'s fixed effect for the same
    # dataset.
    hab_levels_rv <- shiny::reactiveVal(hab_levels)
    pal_rv <- shiny::reactiveVal(pal)

    # Authoritative record of which habitats are currently checked visible,
    # kept in sync with input$visible_habitats via the observer below.
    # .register_new_habitat() updates this DIRECTLY rather than reading
    # input$visible_habitats itself: updateCheckboxGroupInput() only sends a
    # message to the browser and input$visible_habitats only reflects it
    # after the client's reply round-trips back, so reading it synchronously
    # right after rebuilding the whole choice set is a genuine race --
    # keeping our own copy sidesteps that timing dependency entirely.
    visible_habitats_rv <- shiny::reactiveVal(hab_levels)

    # Registers a habitat value not yet known to this session: extends the
    # palette (never disturbing existing colour assignments -- see
    # .extend_habitat_palette()'s own docs for why a full re-sort-and-rebuild
    # would silently recolour already-displayed points) and syncs the
    # sidebar's Habitat checkbox list so the new level has a visible,
    # selectable entry immediately. No-op if new_hab is already known.
    .register_new_habitat <- function(new_hab) {
      cur_levels <- hab_levels_rv()
      if (new_hab %in% cur_levels) {
        return(invisible(NULL))
      }

      new_levels <- sort(c(cur_levels, new_hab))
      new_pal <- .extend_habitat_palette(pal_rv(), new_hab)
      hab_levels_rv(new_levels)
      pal_rv(new_pal)

      choice_names <- lapply(new_levels, function(h) {
        shiny::HTML(sprintf(
          paste0(
            '<span style="display:inline-flex;align-items:center;gap:5px;">',
            '<span style="display:inline-block;width:10px;height:10px;',
            'border-radius:50%%;background:%s;flex-shrink:0;"></span>',
            '<span style="font-size:11px;">%s</span>',
            "</span>"
          ),
          new_pal[[h]], .he(h)
        ))
      })
      new_visible <- union(visible_habitats_rv(), new_hab)
      visible_habitats_rv(new_visible)

      shiny::updateCheckboxGroupInput(
        session, "visible_habitats",
        choiceNames = choice_names,
        choiceValues = new_levels,
        selected = new_visible
      )
      invisible(NULL)
    }

    visible_habitats <- shiny::reactive({
      visible_habitats_rv()
    })

    # --------------------------------------------------------------------------
    # All / None habitat buttons
    # --------------------------------------------------------------------------

    shiny::observeEvent(input$hab_all, {
      shiny::updateCheckboxGroupInput(session, "visible_habitats", selected = hab_levels_rv())
    })

    shiny::observeEvent(input$hab_none, {
      shiny::updateCheckboxGroupInput(session, "visible_habitats", selected = character(0L))
    })

    # --------------------------------------------------------------------------
    # Show / hide Leaflet groups when checkbox state changes. Also keeps
    # visible_habitats_rv in sync -- this fires whenever the CHECKBOX WIDGET
    # itself changes (user click, or updateCheckboxGroupInput()'s own
    # selected= taking effect client-side), so it's the correct single place
    # to update our authoritative copy.
    # --------------------------------------------------------------------------

    shiny::observeEvent(input$visible_habitats,
      {
        visible_habitats_rv(input$visible_habitats %||% character(0L))
        proxy <- leaflet::leafletProxy("map")
        for (h in hab_levels_rv()) {
          if (h %in% input$visible_habitats) {
            proxy <- leaflet::showGroup(proxy, h)
          } else {
            proxy <- leaflet::hideGroup(proxy, h)
          }
        }
      },
      ignoreNULL = FALSE
    )

    # --------------------------------------------------------------------------
    # renderLeaflet -- reacts to view_mode only; cur_flags/cur_habitats/
    # hab_levels_rv/pal_rv all isolated (same convention). cur_habitats is
    # read here (not just pts$habitat, which is static from the original
    # occurrence_data) so a point re-colours correctly even after a habitat reassignment
    # if the user switches views away and back.
    # --------------------------------------------------------------------------

    view_trigger <- shiny::reactive({
      input$view_mode
    })

    output$map <- leaflet::renderLeaflet({
      view_lc <- tolower(view_trigger())
      fl <- shiny::isolate(cur_flags())
      habs_now <- shiny::isolate(cur_habitats())
      levels_now <- shiny::isolate(hab_levels_rv())
      pal_now <- shiny::isolate(pal_rv())
      show_ids <- names(fl)[fl == view_lc]
      sub_pts <- pts[pts$point_id %in% show_ids, ]
      sub_pts$habitat <- habs_now[sub_pts$point_id]

      m <- leaflet::leaflet() |>
        leaflet::addProviderTiles(tile) |>
        leaflet::fitBounds(
          full_bounds$lng1, full_bounds$lat1,
          full_bounds$lng2, full_bounds$lat2
        )

      if (nrow(sub_pts) == 0L) {
        return(m)
      }

      for (hab in intersect(levels_now, unique(sub_pts$habitat))) {
        hab_sub <- sub_pts[sub_pts$habitat == hab, ]
        m <- leaflet::addCircleMarkers(
          map = m,
          data = hab_sub,
          lng = ~lon,
          lat = ~lat,
          layerId = ~point_id,
          radius = point_radius,
          color = pal_now[[hab]],
          fillColor = pal_now[[hab]],
          fillOpacity = 0.8,
          opacity = 0.9,
          weight = 1,
          label = lapply(hab_sub$tooltip, shiny::HTML),
          labelOptions = leaflet::labelOptions(
            style     = list("font-size" = "12px", "padding" = "4px 6px"),
            direction = "auto",
            delay     = 600L
          ),
          group = hab
        )
      }

      # Re-apply habitat visibility after view switch
      cur_visible <- shiny::isolate(visible_habitats_rv())
      for (h in setdiff(levels_now, cur_visible)) {
        m <- leaflet::hideGroup(m, h)
      }

      m <- .add_draw_toolbar(m)
      m
    })

    # --------------------------------------------------------------------------
    # Marker hover -- update Point Info panel (both action modes, no side effects)
    # --------------------------------------------------------------------------

    shiny::observeEvent(input$map_marker_mouseover, {
      pid <- input$map_marker_mouseover$id
      if (!is.null(pid) && nzchar(pid)) hovered_point_id(pid)
    })

    # --------------------------------------------------------------------------
    # Point Info panel.
    #
    # Reads hovered_point_id(), cur_habitats() (so reassignments show live),
    # and input$show_all_spp to choose between compact and full species view.
    # Hover and click behaviour are completely unaffected by the toggle.
    # --------------------------------------------------------------------------

    output$point_info_panel <- shiny::renderUI({
      pid <- hovered_point_id()

      if (is.null(pid)) {
        return(shiny::p("(hover over a point)",
          style = "font-size:11px;color:#999;margin:0;"
        ))
      }

      cur_hab <- cur_habitats()[[pid]]
      cur_hab <- if (is.null(cur_hab) || is.na(cur_hab)) "unknown" else cur_hab
      hab_dot_col <- if (cur_hab %in% names(pal_rv())) pal_rv()[[cur_hab]] else "#aaaaaa"

      # Build species block: compact or full depending on toggle
      spp_block <- if (!is.null(spp_by_point)) {
        spp <- spp_by_point[[pid]]
        n_spp <- length(spp)

        if (n_spp == 0L) {
          shiny::p("No taxa recorded.",
            style = "font-size:11px;color:#888;margin:2px 0 0 0;"
          )
        } else if (!isTRUE(input$show_all_spp) || n_spp == 1L) {
          # Compact view (toggle off, or only one species anyway)
          shiny::p(
            shiny::HTML(sprintf(
              "<i>%s</i>%s",
              .he(spp[1L]),
              if (n_spp > 1L) {
                sprintf(" <span style='color:#888;'>(+%d more)</span>", n_spp - 1L)
              } else {
                ""
              }
            )),
            style = "font-size:11px;margin:2px 0 0 0;"
          )
        } else {
          # Full list view (toggle on, n_spp > 1)
          list_items <- paste(
            sprintf(
              '<li style="padding:1px 0;font-size:11px;">%s</li>',
              .he(spp)
            ),
            collapse = "\n"
          )
          shiny::div(
            style = "margin-top:3px;",
            shiny::p(
              sprintf("%d species:", n_spp),
              style = "font-size:10px;color:#666;margin:0 0 2px 0;"
            ),
            shiny::HTML(sprintf(
              paste0(
                '<ol style="margin:0;padding-left:16px;',
                "max-height:200px;overflow-y:auto;",
                "border:1px solid #dce3ea;border-radius:3px;",
                'background:white;padding:4px 4px 4px 20px;">',
                "%s</ol>"
              ),
              list_items
            ))
          )
        }
      } else {
        NULL
      }

      shiny::div(
        style = paste0(
          "padding:7px 8px;border-radius:4px;background:#f0f4f8;",
          "border:1px solid #dce3ea;font-size:11px;"
        ),
        # Point ID
        shiny::p(shiny::strong(pid),
          style = "margin:0 0 3px 0;font-size:11px;word-break:break-all;"
        ),
        # Habitat with colour dot
        shiny::p(
          shiny::HTML(sprintf(
            paste0(
              '<span style="display:inline-block;width:9px;height:9px;',
              "border-radius:50%%;background:%s;margin-right:4px;",
              'vertical-align:middle;"></span>%s'
            ),
            hab_dot_col, .he(cur_hab)
          )),
          style = "margin:0 0 3px 0;"
        ),
        spp_block
      )
    })

    # --------------------------------------------------------------------------
    # Draw rectangle -- bulk Flag OR bulk Reassign Habitat.
    # Hidden-habitat points excluded from selection in both modes.
    # --------------------------------------------------------------------------

    shiny::observeEvent(input$map_draw_new_feature, {
      message("[review_spatial_flags DEBUG] map_draw_new_feature fired")
      feat <- input$map_draw_new_feature
      if (is.null(feat)) {
        message("[review_spatial_flags DEBUG] feat is NULL, returning")
        return()
      }

      coords <- tryCatch(
        feat$geometry$coordinates[[1]],
        error = function(e) {
          message("[review_spatial_flags DEBUG] error extracting coordinates: ", conditionMessage(e))
          NULL
        }
      )
      if (is.null(coords)) {
        return()
      }

      lons <- tryCatch(vapply(coords, `[[`, numeric(1L), 1L), error = function(e) {
        message("[review_spatial_flags DEBUG] error extracting lons: ", conditionMessage(e))
        NA_real_
      })
      lats <- tryCatch(vapply(coords, `[[`, numeric(1L), 2L), error = function(e) {
        message("[review_spatial_flags DEBUG] error extracting lats: ", conditionMessage(e))
        NA_real_
      })
      xmin <- min(lons)
      xmax <- max(lons)
      ymin <- min(lats)
      ymax <- max(lats)
      message(sprintf(
        "[review_spatial_flags DEBUG] box = lon[%.6f, %.6f] lat[%.6f, %.6f], n_coord_pts=%d",
        xmin, xmax, ymin, ymax, length(coords)
      ))

      fl <- cur_flags()
      view_lc <- tolower(input$view_mode)
      vis_hab <- visible_habitats()
      message(sprintf(
        "[review_spatial_flags DEBUG] action_mode=%s view_lc=%s vis_hab=[%s] n_fl=%d n_view_matches=%d",
        input$action_mode, view_lc, paste(vis_hab, collapse = ","),
        length(fl), sum(fl == view_lc, na.rm = TRUE)
      ))

      in_box_ids <- pts$point_id[
        pts$point_id %in% names(fl)[fl == view_lc] &
          pts$habitat %in% vis_hab &
          pts$lon >= xmin & pts$lon <= xmax &
          pts$lat >= ymin & pts$lat <= ymax
      ]
      message(sprintf(
        "[review_spatial_flags DEBUG] in_box_ids length = %d", length(in_box_ids)
      ))

      if (input$action_mode == "Flag") {
        if (length(in_box_ids) == 0L) {
          message("[review_spatial_flags DEBUG] Flag mode, in_box_ids empty, returning (no-op)")
          return()
        }

        rs <- cur_reasons()
        new_flag <- if (view_lc %in% c("likely", "unlikely")) "questionable" else "likely"
        ts <- format(Sys.time(), "%Y-%m-%d %H:%M")
        flag_hist <- history()

        for (pid in in_box_ids) {
          flag_hist <- c(flag_hist, list(list(
            point_id    = pid,
            old_flag    = fl[[pid]],
            old_reason  = rs[[pid]],
            old_habitat = NA_character_
          )))
          rs[[pid]] <- paste0(
            rs[[pid]],
            sprintf(" [%s \u2192 %s, %s]", fl[[pid]], new_flag, ts)
          )
          fl[[pid]] <- new_flag
        }
        history(flag_hist)
        cur_flags(fl)
        cur_reasons(rs)

        proxy <- leaflet::leafletProxy("map")
        for (pid in in_box_ids) proxy <- leaflet::removeMarker(proxy, layerId = pid)

        .reset_draw_toolbar(leaflet::leafletProxy("map"))
      } else {
        selected_point(NULL)
        selected_points(if (length(in_box_ids) > 0L) in_box_ids else NULL)
      }
    })

    # --------------------------------------------------------------------------
    # Marker click -- branches on action_mode.
    # Belt-and-suspenders guard against hidden-habitat clicks.
    # Also pins Point Info to clicked point.
    # --------------------------------------------------------------------------

    shiny::observeEvent(input$map_marker_click, {
      pid <- input$map_marker_click$id
      if (is.null(pid) || !nzchar(pid)) {
        return()
      }

      pt_hab <- pts$habitat[pts$point_id == pid][1L]
      if (!isTRUE(pt_hab %in% visible_habitats())) {
        return()
      }

      hovered_point_id(pid)

      if (input$action_mode == "Flag") {
        fl <- cur_flags()
        rs <- cur_reasons()
        old_flag <- fl[[pid]]
        old_reason <- rs[[pid]]
        if (is.null(old_flag) || is.na(old_flag)) {
          return()
        }

        new_flag <- if (old_flag %in% c("likely", "unlikely")) "questionable" else "likely"
        ts <- format(Sys.time(), "%Y-%m-%d %H:%M")
        new_reason <- paste0(
          old_reason,
          sprintf(" [%s \u2192 %s, %s]", old_flag, new_flag, ts)
        )

        flag_hist <- history()
        history(c(flag_hist, list(list(
          point_id    = pid,
          old_flag    = old_flag,
          old_reason  = old_reason,
          old_habitat = NA_character_
        ))))

        fl[[pid]] <- new_flag
        rs[[pid]] <- new_reason
        cur_flags(fl)
        cur_reasons(rs)
        leaflet::leafletProxy("map") |> leaflet::removeMarker(layerId = pid)
      } else {
        selected_point(pid)
      }
    })

    # --------------------------------------------------------------------------
    # Habitat reassignment sidebar panel
    # --------------------------------------------------------------------------

    output$habitat_reassign_panel <- shiny::renderUI({
      pid <- selected_point()
      pids <- selected_points()

      if (is.null(pid) && is.null(pids)) {
        return(shiny::p("(click a point or draw a rectangle)",
          style = "font-size:11px;color:#999;margin:4px 0;"
        ))
      }

      if (!is.null(pids)) {
        header_html <- sprintf("<b>%d points selected</b>", length(pids))
        cur_hab <- NA_character_
      } else {
        cur_hab <- cur_habitats()[[pid]]
        header_html <- sprintf(
          "<b>Point:</b> %s<br/><b>Current:</b> %s",
          .he(pid), .he(cur_hab)
        )
      }

      hab_choices <- c(sort(hab_levels_rv()), "Other")

      shiny::div(
        style = "margin-top:6px;",
        shiny::p(shiny::HTML(header_html),
          style = "font-size:11px;margin:0 0 6px 0;"
        ),
        shiny::selectInput(
          inputId  = "new_habitat_choice",
          label    = NULL,
          choices  = hab_choices,
          selected = if (!is.na(cur_hab) && cur_hab %in% hab_choices) cur_hab else hab_choices[[1]],
          width    = "100%"
        ),
        shiny::conditionalPanel(
          condition = "input.new_habitat_choice == 'Other'",
          shiny::textInput(
            inputId     = "other_habitat_text",
            label       = NULL,
            placeholder = "Type habitat name...",
            width       = "100%"
          )
        ),
        shiny::actionButton(
          "confirm_habitat", "Confirm",
          style = "width:100%;font-size:12px;padding:4px 8px;background:#2196F3;color:white;border:none;"
        )
      )
    })

    # --------------------------------------------------------------------------
    # Confirm habitat reassignment
    # --------------------------------------------------------------------------

    shiny::observeEvent(input$confirm_habitat, {
      new_hab <- input$new_habitat_choice
      if (is.null(new_hab)) {
        return()
      }

      if (new_hab == "Other") {
        new_hab <- trimws(input$other_habitat_text)
        if (is.null(new_hab) || !nzchar(new_hab)) {
          return()
        }
      }

      # Register BEFORE computing new_col: a value typed via "Other" has no
      # palette entry yet on first use this session (see .register_new_
      # habitat()'s own comment for why this used to silently fall back to
      # grey and stay invisible to the sidebar's visibility filter).
      .register_new_habitat(new_hab)

      pid <- selected_point()
      pids <- selected_points()
      target_ids <- if (!is.null(pids)) pids else if (!is.null(pid)) pid else return()

      habs <- cur_habitats()
      fl <- cur_flags()
      rs <- cur_reasons()
      ts <- format(Sys.time(), "%Y-%m-%d %H:%M")
      flag_hist <- history()
      pal_now <- pal_rv()
      new_col <- if (new_hab %in% names(pal_now)) pal_now[[new_hab]] else "#aaaaaa"
      view_lc <- tolower(input$view_mode)
      proxy <- leaflet::leafletProxy("map")

      for (pid_i in target_ids) {
        old_hab <- habs[[pid_i]]
        old_flag <- fl[[pid_i]]
        old_reason <- rs[[pid_i]]

        if (identical(old_hab, new_hab)) next

        flag_hist <- c(flag_hist, list(list(
          point_id    = pid_i,
          old_flag    = old_flag,
          old_reason  = old_reason,
          old_habitat = old_hab
        )))

        # A reviewer reassigning habitat WHILE ALREADY reviewing a
        # Questionable point has, by construction, just made a spatially-
        # informed judgment call -- treat that as a resolution (-> Likely)
        # rather than resetting back to Questionable for a second round of
        # review. Any other source flag (Likely/Unlikely) now KEEPS its
        # existing flag instead of being pushed into Questionable for a
        # second look (changed 2026-08-02, at the user's request): forcing
        # every Likely/Unlikely habitat reassignment through a second
        # Questionable-view round trip doubled the reviewer's workload and
        # inflated the Questionable view specifically -- the one view where
        # bulk Flag-mode rectangle actions have repeatedly proven fragile at
        # scale (see this function's own multi-round debugging history in
        # the project memory system). The reviewer is now trusted to have
        # made a spatially-informed call at the moment of reassignment,
        # matching how the Questionable case already worked.
        new_flag <- if (identical(old_flag, "questionable")) "likely" else old_flag

        habs[[pid_i]] <- new_hab
        fl[[pid_i]] <- new_flag
        rs[[pid_i]] <- paste0(
          old_reason,
          sprintf(
            " [habitat: %s \u2192 %s, %s]",
            old_hab, new_hab, ts
          )
        )

        row <- pts[pts$point_id == pid_i, ][1L, ]
        proxy <- leaflet::removeMarker(proxy, layerId = pid_i)
        if (identical(new_flag, view_lc)) {
          # Still belongs in the view currently on screen -- recolour in place.
          proxy <- .add_habitat_marker(proxy, row, new_col, new_hab)
        }
        # Otherwise the point's flag changed to a view other than the one
        # displayed (e.g. Questionable -> Likely) -- leave it removed, same
        # as the "Flag" action mode already does when a flag change moves a
        # point out of the current view.
      }

      history(flag_hist)
      cur_habitats(habs)
      cur_flags(fl)
      cur_reasons(rs)

      if (!is.null(pids)) {
        .reset_draw_toolbar(leaflet::leafletProxy("map"))
      }

      selected_point(NULL)
      selected_points(NULL)
    })

    # --------------------------------------------------------------------------
    # Undo last override
    # --------------------------------------------------------------------------

    shiny::observeEvent(input$undo_last, {
      flag_hist <- history()
      if (length(flag_hist) == 0L) {
        return()
      }

      last <- flag_hist[[length(flag_hist)]]
      history(flag_hist[-length(flag_hist)])

      fl <- cur_flags()
      rs <- cur_reasons()
      habs <- cur_habitats()

      fl[[last$point_id]] <- last$old_flag
      rs[[last$point_id]] <- last$old_reason
      cur_flags(fl)
      cur_reasons(rs)

      # A restored flag may not match the currently displayed view (e.g. an
      # undone reassignment's old_flag was "likely" but the reviewer is now
      # looking at Questionable) -- only re-add a marker when it actually
      # belongs in what's on screen, mirroring confirm_habitat's own view_lc
      # check. Previously this always re-added the marker regardless of view,
      # a latent bug this fix's questionable->likely transition made more
      # reachable (more undos now cross views than before).
      view_lc <- tolower(input$view_mode)
      belongs_in_view <- identical(last$old_flag, view_lc)
      pal_now <- pal_rv()

      if (!is.na(last$old_habitat)) {
        habs[[last$point_id]] <- last$old_habitat
        cur_habitats(habs)

        proxy <- leaflet::removeMarker(leaflet::leafletProxy("map"), layerId = last$point_id)
        if (belongs_in_view) {
          old_col <- if (last$old_habitat %in% names(pal_now)) pal_now[[last$old_habitat]] else "#aaaaaa"
          row <- pts[pts$point_id == last$point_id, ][1L, ]
          .add_habitat_marker(proxy, row, old_col, last$old_habitat)
        }
      } else if (belongs_in_view) {
        row <- pts[pts$point_id == last$point_id, ][1L, ]
        cur_hab_val <- habs[[last$point_id]] %||% row$habitat
        cur_col <- if (cur_hab_val %in% names(pal_now)) pal_now[[cur_hab_val]] else "#aaaaaa"
        .add_habitat_marker(leaflet::leafletProxy("map"), row, cur_col, cur_hab_val)
      }
    })

    # --------------------------------------------------------------------------
    # Sidebar summary outputs
    # --------------------------------------------------------------------------

    output$override_summary <- shiny::renderUI({
      n_total <- length(history())
      if (n_total == 0L) {
        return(shiny::p("No overrides yet.", style = "font-size:11px;color:#999;margin:0;"))
      }
      fl <- cur_flags()
      shiny::div(
        style = "font-size:11px;color:#444;",
        shiny::p(sprintf("%d override(s) this session", n_total),
          style = "margin:0 0 4px 0;font-weight:bold;"
        ),
        shiny::p(shiny::HTML(sprintf(
          "<span style='color:%s'>\u25cf</span> Likely: %d &nbsp;
           <span style='color:%s'>\u25cf</span> Quest.: %d &nbsp;
           <span style='color:%s'>\u25cf</span> Unlikely: %d",
          flag_ring_color[["likely"]],       sum(fl == "likely"),
          flag_ring_color[["questionable"]], sum(fl == "questionable"),
          flag_ring_color[["unlikely"]],     sum(fl == "unlikely")
        )), style = "margin:0;")
      )
    })

    output$point_count <- shiny::renderUI({
      fl <- cur_flags()
      view_lc <- tolower(input$view_mode)
      n_view <- sum(fl == view_lc)
      n_vis <- sum(fl == view_lc &
        pts$habitat[match(names(fl), pts$point_id)] %in% visible_habitats())
      if (n_vis == n_view) {
        shiny::p(sprintf("%d point(s) in %s view", n_view, input$view_mode),
          style = "font-size:11px;color:#555;margin:0;"
        )
      } else {
        shiny::p(
          shiny::HTML(sprintf(
            "%d of %d point(s) visible in %s view",
            n_vis, n_view, input$view_mode
          )),
          style = "font-size:11px;color:#555;margin:0;"
        )
      }
    })

    # --------------------------------------------------------------------------
    # Done / Cancel
    # --------------------------------------------------------------------------

    shiny::observeEvent(input$done, {
      fl <- cur_flags()
      rs <- cur_reasons()
      habs <- cur_habitats()

      result <- occurrence_data
      result$spatial_flag <- fl[result$point_id]

      overridden_ids <- unique(vapply(history(), `[[`, character(1L), "point_id"))
      if (length(overridden_ids) > 0L) {
        rows <- result$point_id %in% overridden_ids
        result$spatial_flag_reason[rows] <- rs[result$point_id[rows]]
      }

      hab_changed_ids <- names(habs)[habs != pts_hab_init[names(habs)]]
      if (length(hab_changed_ids) > 0L) {
        for (pid in hab_changed_ids) {
          result[[habitat_col]][result$point_id == pid] <- habs[[pid]]
        }
      }

      shiny::stopApp(returnValue = result)
    })

    shiny::observeEvent(input$cancel, {
      shiny::stopApp(returnValue = NULL)
    })
  }

  # --------------------------------------------------------------------------
  # 6. Run gadget
  # --------------------------------------------------------------------------

  shiny::runGadget(
    ui,
    server,
    viewer = viewer
  )
}
