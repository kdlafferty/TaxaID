# ==============================================================================
# review_institution_flags.R
# TaxaHabitat -- interactive map review of TaxaFetch::filter_gbif_quality()'s
# institution flags, tiered by flag_institution_candidates()
# ==============================================================================

#' Review Institution-Proximity Flags Interactively
#'
#' Opens a Shiny gadget for reviewing records \code{TaxaFetch::
#' filter_gbif_quality()} flagged as near a biodiversity institution
#' (\code{institution_flag = TRUE}), tiered by \code{\link{flag_institution_candidates}}.
#' Each flagged record is shown on a map alongside its own matched
#' institution's location, so a reviewer can see directly whether they
#' coincide (an archived-specimen coordinate) or are genuinely apart (a real
#' field observation near, but not at, the institution -- e.g. a shoreline
#' sample near a marine lab's own pier, versus its inland administrative
#' campus).
#'
#' Deliberately scoped down from \code{\link{review_spatial_flags}}: no
#' rectangle bulk-select, no habitat reassignment, single-level undo. The
#' institution-flagged subset of a real dataset is typically small (tens of
#' records, not thousands), so a simple one-point-at-a-time review is enough;
#' rebuild with bulk tools later if that stops being true.
#'
#' @section Review workflow:
#' \enumerate{
#'   \item Every flagged record starts as \strong{Keep} -- nothing is ever
#'     discarded just by opening this gadget or clicking Done without
#'     reviewing every point.
#'   \item Click a record's marker to toggle it to \strong{Remove}
#'     (institution error, discard) or back to \strong{Keep} (genuine
#'     observation, retain).
#'   \item Institution markers (blue squares) are shown for context --
#'     clicking them does nothing.
#'   \item Click \strong{Done}. Filter to keep confirmed-good records:
#'     \code{dplyr::filter(result, institution_decision != "remove")}
#'     (non-flagged rows keep \code{institution_decision = NA} and are
#'     always retained by that filter).
#' }
#'
#' @param occurrence_data A dataframe, typically the output of
#'   \code{\link{flag_institution_candidates}}. Must contain
#'   \code{institution_flag}, \code{institution_suspicion},
#'   \code{institution_name}, \code{institution_type},
#'   \code{institution_dist_m}, \code{institution_lon},
#'   \code{institution_lat}, and coordinate columns.
#' @param lat_col,lon_col Character. The record's own coordinate columns
#'   (not the institution's). Default \code{"decimalLatitude"}/
#'   \code{"decimalLongitude"} (GBIF standard names).
#' @param taxon_col Character or \code{NULL}. Column for the species label
#'   shown in tooltips. Default \code{"species"}.
#' @param tile Character. Leaflet tile provider. Default
#'   \code{"Esri.OceanBasemap"}.
#' @param point_radius Numeric. Base circle marker radius in pixels.
#'   Occurrence markers are drawn at \code{point_radius * 0.75}; institution
#'   reference markers at \code{point_radius * 0.5} (smaller and a distinct
#'   blue, so they provide spatial context without obscuring nearby
#'   occurrence points). Default \code{7}.
#'
#' @return \code{occurrence_data} with one additional column, \code{institution_decision}:
#'   \code{"keep"} or \code{"remove"} for every record that had
#'   \code{institution_flag = TRUE}; \code{NA} for every other record
#'   (never shown to the reviewer, never touched). Returns \code{NULL} if
#'   the user clicks Cancel.
#'
#' @seealso \code{\link{flag_institution_candidates}},
#'   \code{\link{review_spatial_flags}}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' clean <- TaxaFetch::filter_gbif_quality(gbif_raw)
#' tiered <- flag_institution_candidates(clean)
#' reviewed <- review_institution_flags(tiered)
#' final <- dplyr::filter(reviewed, institution_decision != "remove")
#' }
review_institution_flags <- function(
  occurrence_data,
  lat_col = "decimalLatitude",
  lon_col = "decimalLongitude",
  taxon_col = "species",
  tile = "Esri.OceanBasemap",
  point_radius = 7
) {
  # --------------------------------------------------------------------------
  # 0. Checks
  # --------------------------------------------------------------------------

  if (!interactive()) {
    stop("review_institution_flags: must be run in an interactive R session.")
  }
  for (pkg in c("shiny", "miniUI", "leaflet")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop(sprintf(
        "review_institution_flags: package '%s' is required. Install with: install.packages('%s')",
        pkg, pkg
      ))
    }
  }
  if (!is.data.frame(occurrence_data)) {
    stop("review_institution_flags: 'occurrence_data' must be a dataframe.")
  }
  required_cols <- c(
    "institution_flag", "institution_suspicion",
    "institution_name", "institution_type",
    "institution_dist_m", "institution_lon", "institution_lat",
    lat_col, lon_col
  )
  missing_cols <- setdiff(required_cols, names(occurrence_data))
  if (length(missing_cols) > 0L) {
    stop(sprintf(
      paste0(
        "review_institution_flags: missing column(s): %s.\n",
        "  Run TaxaFetch::filter_gbif_quality(flag_institution = TRUE) then\n",
        "  flag_institution_candidates() first."
      ),
      paste(missing_cols, collapse = ", ")
    ))
  }
  if (!is.null(taxon_col) && !taxon_col %in% names(occurrence_data)) {
    warning("review_institution_flags: taxon_col not found -- species label suppressed.",
      call. = FALSE
    )
    taxon_col <- NULL
  }

  is_flagged <- !is.na(occurrence_data$institution_flag) & occurrence_data$institution_flag
  if (!any(is_flagged)) {
    stop("review_institution_flags: no institution_flag = TRUE records to review.")
  }

  # --------------------------------------------------------------------------
  # 1. Build point-level table (one row per flagged RECORD, not deduplicated
  #    by location -- two different species at the same institution-adjacent
  #    coordinate are two separate decisions, unlike habitat review's
  #    per-location dedup).
  # --------------------------------------------------------------------------

  flagged_idx <- which(is_flagged)

  point_id <- if ("gbifID" %in% names(occurrence_data)) {
    as.character(occurrence_data$gbifID[flagged_idx])
  } else {
    NA_character_
  }
  if (anyNA(point_id) || anyDuplicated(point_id) > 0L) {
    point_id <- as.character(flagged_idx)
  }

  pts <- data.frame(
    point_id = point_id,
    row_idx = flagged_idx,
    lon = occurrence_data[[lon_col]][flagged_idx],
    lat = occurrence_data[[lat_col]][flagged_idx],
    taxon = if (!is.null(taxon_col)) as.character(occurrence_data[[taxon_col]][flagged_idx]) else NA_character_,
    suspicion = occurrence_data$institution_suspicion[flagged_idx],
    inst_name = occurrence_data$institution_name[flagged_idx],
    inst_type = occurrence_data$institution_type[flagged_idx],
    inst_dist_m = occurrence_data$institution_dist_m[flagged_idx],
    inst_lon = occurrence_data$institution_lon[flagged_idx],
    inst_lat = occurrence_data$institution_lat[flagged_idx],
    stringsAsFactors = FALSE
  )
  pts$suspicion[is.na(pts$suspicion)] <- "ambiguous"

  # Deduplicated institution reference layer -- several flagged records often
  # share the same nearest institution; show it once, not once per record.
  inst_pts <- unique(pts[!is.na(pts$inst_lon), c("inst_name", "inst_type", "inst_lon", "inst_lat")])

  tier_levels <- c("high", "low", "ambiguous")
  tier_color <- c(high = "#d62728", low = "#2ca02c", ambiguous = "#ff7f0e")
  decision_color <- c(keep = "#2ca02c", remove = "#d62728")

  pts$tooltip <- mapply(
    function(taxon, sus, iname, itype, idist) {
      out <- sprintf("<b>%s</b>", .he(if (is.na(taxon) || !nzchar(taxon)) "(no taxon)" else taxon))
      out <- paste0(out, "<br/><b>Suspicion:</b> ", .he(sus))
      out <- paste0(
        out, "<br/><b>Institution:</b> ", .he(iname),
        if (!is.na(itype)) sprintf(" (%s)", .he(itype)) else ""
      )
      out <- paste0(out, "<br/><b>Distance:</b> ", .he(sprintf("%.0f m", idist)))
      out
    }, pts$taxon, pts$suspicion, pts$inst_name, pts$inst_type, pts$inst_dist_m,
    SIMPLIFY = TRUE
  )

  # --------------------------------------------------------------------------
  # 2. UI
  # --------------------------------------------------------------------------

  ui <- miniUI::miniPage(
    miniUI::gadgetTitleBar(
      "Review Institution Flags",
      right = miniUI::miniTitleBarButton("done", "Done", primary = TRUE),
      left  = miniUI::miniTitleBarButton("cancel", "Cancel", primary = FALSE)
    ),
    miniUI::miniContentPanel(
      padding = 0,
      shiny::fillRow(
        flex = c(1, NA),
        leaflet::leafletOutput("map", height = "100%"),
        shiny::div(
          style = paste0(
            "width:240px;padding:10px;border-left:1px solid #ddd;",
            "background:#fafafa;height:100%;overflow-y:auto;box-sizing:border-box;"
          ),
          shiny::h4("Suspicion tier", style = "margin-top:6px;margin-bottom:6px;font-size:14px;"),
          shiny::checkboxGroupInput(
            inputId = "visible_tiers",
            label = NULL,
            choiceNames = lapply(tier_levels, function(t) {
              shiny::HTML(sprintf(
                paste0(
                  '<span style="display:inline-flex;align-items:center;gap:5px;">',
                  '<span style="display:inline-block;width:10px;height:10px;',
                  'border-radius:50%%;background:%s;flex-shrink:0;"></span>',
                  '<span style="font-size:11px;">%s</span></span>'
                ), tier_color[[t]], .he(t)
              ))
            }),
            choiceValues = tier_levels,
            selected = tier_levels
          ),
          shiny::hr(style = "margin:8px 0;"),
          shiny::h4("Point Info", style = "margin-top:0;margin-bottom:4px;font-size:14px;"),
          shiny::uiOutput("point_info_panel"),
          shiny::hr(style = "margin:8px 0;"),
          shiny::div(
            style = paste0(
              "padding:8px;border-radius:4px;background:#f0f0f0;",
              "font-size:11px;color:#444;margin-bottom:8px;"
            ),
            shiny::strong("Click a record's marker to toggle:"),
            shiny::br(),
            shiny::HTML("Keep \u2192 Remove \u2192 Keep")
          ),
          shiny::hr(style = "margin:8px 0;"),
          shiny::h4("Summary", style = "margin-top:0;margin-bottom:4px;font-size:13px;"),
          shiny::uiOutput("decision_summary"),
          shiny::hr(style = "margin:8px 0;"),
          shiny::actionButton(
            "undo_last", "Undo Last",
            style = "width:100%;font-size:12px;padding:4px 8px;"
          )
        )
      )
    )
  )

  # --------------------------------------------------------------------------
  # 3. Server
  # --------------------------------------------------------------------------

  server <- function(input, output, session) {
    cur_decisions <- shiny::reactiveVal(
      stats::setNames(rep("keep", nrow(pts)), pts$point_id)
    )
    hovered_point_id <- shiny::reactiveVal(NULL)
    history <- shiny::reactiveVal(list())

    visible_tiers <- shiny::reactive({
      input$visible_tiers %||% character(0L)
    })

    visible_pts <- shiny::reactive({
      pts[pts$suspicion %in% visible_tiers(), , drop = FALSE]
    })

    output$map <- leaflet::renderLeaflet({
      m <- leaflet::leaflet(options = leaflet::leafletOptions(maxZoom = 20)) |>
        leaflet::addProviderTiles(
          tile,
          options = leaflet::providerTileOptions(maxZoom = 20)
        )

      # Frame the view on the flagged points themselves (padded) rather than
      # leaflet's arbitrary global default -- starts already zoomed in
      # instead of requiring the reviewer to zoom in from a world view.
      all_lon <- c(pts$lon, inst_pts$inst_lon)
      all_lat <- c(pts$lat, inst_pts$inst_lat)
      m <- leaflet::fitBounds(
        m,
        lng1 = min(all_lon), lat1 = min(all_lat),
        lng2 = max(all_lon), lat2 = max(all_lat)
      )

      if (nrow(inst_pts) > 0L) {
        # Smaller circle marker, distinct blue, instead of leaflet's bundled
        # pin icon -- the pin was reported as obscuring nearby occurrence
        # points; a circle at half the occurrence radius keeps it visible as
        # context without dominating the map.
        m <- leaflet::addCircleMarkers(
          m,
          data        = inst_pts,
          lng         = ~inst_lon,
          lat         = ~inst_lat,
          radius      = point_radius * 0.5,
          color       = "#1f77b4",
          fillColor   = "#1f77b4",
          fillOpacity = 0.7,
          opacity     = 1,
          weight      = 1,
          label       = ~ sprintf("Institution: %s (%s)", .he(inst_name), .he(inst_type)),
          group       = "institutions"
        )
      }
      m
    })

    # Redraw occurrence markers whenever visible tiers or decisions change --
    # small point counts (tens, not thousands) make a full redraw cheap.
    shiny::observe({
      dec <- cur_decisions()
      sub_pts <- visible_pts()

      proxy <- leaflet::leafletProxy("map") |> leaflet::clearGroup("occurrences")

      if (nrow(sub_pts) == 0L) {
        return()
      }

      # unname() matters here, not just style: a NAMED color vector gets
      # serialized by leaflet's htmlwidgets JSON layer as a keyed object
      # (duplicate "keep"/"remove" keys silently collapse) instead of a
      # per-point array, breaking marker coloring entirely -- confirmed
      # directly (real bug, not cosmetic) by comparing the actual JSON
      # leaflet builds for named vs. unnamed color vectors before shipping
      # this fix. This is why markers rendered as leaflet's undefined-color
      # fallback (black) regardless of decision.
      cols <- unname(decision_color[dec[sub_pts$point_id]])

      leaflet::addCircleMarkers(
        proxy,
        data = sub_pts,
        lng = ~lon,
        lat = ~lat,
        layerId = ~point_id,
        radius = point_radius * 0.75,
        color = cols,
        fillColor = cols,
        fillOpacity = 0.85,
        opacity = 1,
        weight = 2,
        label = lapply(sub_pts$tooltip, shiny::HTML),
        labelOptions = leaflet::labelOptions(
          style     = list("font-size" = "12px", "padding" = "4px 6px"),
          direction = "auto",
          delay     = 600L
        ),
        group = "occurrences"
      )
    })

    shiny::observeEvent(input$map_marker_mouseover, {
      pid <- input$map_marker_mouseover$id
      if (!is.null(pid) && nzchar(pid) && pid %in% pts$point_id) hovered_point_id(pid)
    })

    output$point_info_panel <- shiny::renderUI({
      pid <- hovered_point_id()
      if (is.null(pid)) {
        return(shiny::p("(hover over a point)", style = "font-size:11px;color:#999;margin:0;"))
      }
      row <- pts[pts$point_id == pid, ][1L, ]
      dec <- cur_decisions()[[pid]]
      dec_col <- decision_color[[dec]]

      shiny::div(
        style = paste0(
          "padding:7px 8px;border-radius:4px;background:#f0f4f8;",
          "border:1px solid #dce3ea;font-size:11px;"
        ),
        shiny::p(shiny::HTML(sprintf(
          paste0(
            "<span style='display:inline-block;width:9px;height:9px;border-radius:50%%;",
            "background:%s;margin-right:4px;vertical-align:middle;'></span><b>%s</b>"
          ),
          dec_col, .he(toupper(dec))
        )), style = "margin:0 0 3px 0;"),
        shiny::p(shiny::HTML(row$tooltip), style = "margin:0;")
      )
    })

    shiny::observeEvent(input$map_marker_click, {
      pid <- input$map_marker_click$id
      if (is.null(pid) || !nzchar(pid) || !pid %in% pts$point_id) {
        return()
      }
      hovered_point_id(pid)

      dec <- cur_decisions()
      old_dec <- dec[[pid]]
      new_dec <- if (old_dec == "keep") "remove" else "keep"

      hist <- history()
      history(c(hist, list(list(point_id = pid, old_decision = old_dec))))

      dec[[pid]] <- new_dec
      cur_decisions(dec)
    })

    shiny::observeEvent(input$undo_last, {
      hist <- history()
      if (length(hist) == 0L) {
        return()
      }
      last <- hist[[length(hist)]]
      history(hist[-length(hist)])

      dec <- cur_decisions()
      dec[[last$point_id]] <- last$old_decision
      cur_decisions(dec)
    })

    output$decision_summary <- shiny::renderUI({
      dec <- cur_decisions()
      n_total <- length(dec)
      n_keep <- sum(dec == "keep")
      n_rem <- sum(dec == "remove")
      shiny::div(
        style = "font-size:11px;color:#444;",
        shiny::p(sprintf("%d flagged record(s)", n_total), style = "margin:0 0 4px 0;font-weight:bold;"),
        shiny::p(shiny::HTML(sprintf(
          "<span style='color:%s'>\u25cf</span> Keep: %d &nbsp; <span style='color:%s'>\u25cf</span> Remove: %d",
          decision_color[["keep"]], n_keep, decision_color[["remove"]], n_rem
        )), style = "margin:0;")
      )
    })

    shiny::observeEvent(input$done, {
      dec <- cur_decisions()
      result <- occurrence_data
      result$institution_decision <- NA_character_
      result$institution_decision[pts$row_idx] <- dec[pts$point_id]
      shiny::stopApp(returnValue = result)
    })

    shiny::observeEvent(input$cancel, {
      shiny::stopApp(returnValue = NULL)
    })
  }

  # --------------------------------------------------------------------------
  # 4. Run gadget
  # --------------------------------------------------------------------------

  shiny::runGadget(
    ui,
    server,
    viewer = shiny::paneViewer(minHeight = 450)
  )
}
